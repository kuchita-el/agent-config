#!/bin/bash
# Stop hook: 最終応答に、作業の内側の記号・番号が意味を添えずに使われていないかを検査する。
#
# 利用者は、作業の中で付いた記号（判断の番号 J2、決定の番号 K3、仮説番号 H1、
# 節番号 §3.5、Issue 番号 #552、ファイルの行番号 foo.md:12 など）を覚えていない。
# 過去の記録では、こうした記号で組んだ問いや報告が通じず差し戻される例が繰り返し
# あり、規約や記憶に「記号を使わない」と書いて文脈に載せても再発した。そのため、
# 文を足す代わりに、応答の終了時点で文字の並びとして機械的に拾う。
#
# 検出しないもの:
#   - コードブロック・インラインコード・リンクの行き先・URL の中
#   - 括弧（全角・半角）の中。記号を脇に置き、本文は中身の言葉で書いた形とみなす
#   - 直後に括弧が続く記号。括弧で意味を添えた形とみなす
#
# 検出したら decision: "block" で終了を差し止め、該当の文だけの言い直しを求める。
# stop_hook_active が true（このフックの差し止めで続いている）なら検査しない。
# 入力の解析に失敗したときは何もせず通す（フックの不具合で応答を止めない）。

set -uo pipefail

LOG_DIR="$HOME/.claude/logs"

input=$(cat)

active=$(printf '%s' "$input" | jq -r '.stop_hook_active // false' 2>/dev/null) || exit 0
[[ "$active" == "true" ]] && exit 0

msg=$(printf '%s' "$input" | jq -r '.last_assistant_message // ""' 2>/dev/null) || exit 0
[[ -z "$msg" ]] && exit 0

found=$(printf '%s' "$msg" | perl -CSD -Mutf8 -0777 -ne '
    # 検査の対象から外す部分を消す
    s/^[ \t]*(```|~~~).*?^[ \t]*\1[^\n]*$//gms;   # フェンスのコードブロック
    s/`[^`\n]*`//g;                                 # インラインコード
    s/\]\([^)\n]*\)/]/g;                            # リンクの行き先
    s{https?://\S+}{}g;                             # URL
    s/<!--.*?-->//gs;                               # HTML のコメント

    my $sym = qr{
        (?<![A-Za-z0-9_./\-])[A-Z]{1,4}[0-9]+[a-z]?(?![A-Za-z0-9_./\-])   # J2, K10, AC17, H3
      | §\s*[0-9][0-9.]*                                                   # §3.5
      | (?<![A-Za-z0-9_/\-])\#[0-9]+\b                                     # #552
      | (?<![A-Za-z0-9_./\-])[A-Za-z_][A-Za-z0-9_.\-]*:[0-9]+(?:-[0-9]+)?\b  # foo.md:12
    }x;

    my %seen;
    my @out;
    for my $line (split /\n/) {
        while ($line =~ /($sym)/g) {
            my ($tok, $start, $end) = ($1, $-[1], $+[1]);
            # 括弧の中か
            my $prefix = substr($line, 0, $start);
            my $open  = () = $prefix =~ /[（(]/g;
            my $close = () = $prefix =~ /[）)]/g;
            next if $open > $close;
            # 直後に括弧が続くか
            next if substr($line, $end) =~ /^\s*[（(]/;
            $tok =~ s/\s+//g;
            push @out, $tok unless $seen{$tok}++;
        }
    }
    print join(", ", @out);
' 2>/dev/null) || exit 0

[[ -z "$found" ]] && exit 0

# 効果と誤検知を後で数えるため、検出した記号だけを記録する。応答の本文は残さない。
mkdir -p "$LOG_DIR" 2>/dev/null && {
    session=$(printf '%s' "$input" | jq -r '.session_id // "unknown"' 2>/dev/null)
    printf '%s | %s | %s\n' "$(date -Iseconds)" "$session" "$found" \
        >> "$LOG_DIR/internal-symbols-$(date +%Y%m%d).log"
} || true

reason="直前の応答に、意味を添えていない記号・番号がある: ${found}。利用者は作業の中で付いた記号を覚えていない前提に立つ。該当する文だけを、記号を中身の言葉に置き換えるか、記号の直後の括弧で意味を添えて言い直し、追記として出す。全文は繰り返さない。どれも利用者に通じる語（製品名・規格名など）で言い直しが要らないなら、「補足なし」とだけ出して終える。"

jq -cn --arg reason "$reason" '{decision: "block", reason: $reason}'
exit 0
