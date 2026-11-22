#!/bin/bash
# hooks/check-internal-symbols.sh のテスト。Stop の入力 JSON を標準入力で与え、差し止めの有無で判定する。
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
HOOK="$SCRIPT_DIR/hooks/check-internal-symbols.sh"

TEST_ROOT=$(mktemp -d)
trap 'rm -rf "$TEST_ROOT"' EXIT
export HOME="$TEST_ROOT/home"
mkdir -p "$HOME"

failures=0

# run <stop_hook_active> <最終応答>: フックの標準出力を返す
run() {
    jq -cn --argjson active "$1" --arg msg "$2" \
        '{session_id: "test", hook_event_name: "Stop", stop_hook_active: $active, last_assistant_message: $msg}' \
        | bash "$HOOK"
}

# expect_block <説明> <最終応答> <reason に含まれるべき記号>
expect_block() {
    local desc=$1 msg=$2 token=$3 out
    out=$(run false "$msg")
    if [[ "$(printf '%s' "$out" | jq -r '.decision // empty' 2>/dev/null)" == "block" ]] \
        && printf '%s' "$out" | jq -r '.reason' | grep -qF -- "$token"; then
        printf 'ok   %s\n' "$desc"
    else
        printf 'FAIL %s (out: %s)\n' "$desc" "$out"
        failures=$((failures + 1))
    fi
}

# expect_pass <説明> <最終応答> [stop_hook_active]
expect_pass() {
    local desc=$1 msg=$2 active=${3:-false} out
    out=$(run "$active" "$msg")
    if [[ -z "$out" ]]; then
        printf 'ok   %s\n' "$desc"
    else
        printf 'FAIL %s (out: %s)\n' "$desc" "$out"
        failures=$((failures + 1))
    fi
}

# 検出する
expect_block "判断の番号"           "推奨は J2 のイ。"                       "J2"
expect_block "英字複数＋数字"       "AC17 を満たすかを確かめる。"            "AC17"
expect_block "節番号"               "詳しくは §3.5 に書いた。"               "§3.5"
expect_block "Issue 番号"           "#552 の再発防止策として扱う。"          "#552"
expect_block "ファイルの行番号"     "根拠は notes.jsonl:593 の発言。"           "notes.jsonl:593"
expect_block "行範囲"               "doc-reviewer.md:31-35 を直す。"         "doc-reviewer.md:31-35"
expect_block "日本語に接した記号"   "K3は保留とする。"                       "K3"
expect_block "複数の記号を全て挙げる" "J2 と K3 を決める。"                  "K3"

# 検出しない
expect_pass "記号を含まない応答"     "利用者の言葉だけで書いた応答。"
expect_pass "空の応答"               ""
expect_pass "差し止めで続いている"   "J2 を採る。" true
expect_pass "直後の括弧で意味を添える" "J2（問いが分からない型の扱い）はアに決まった。"
expect_pass "半角括弧で意味を添える" "J2 (問いの扱い) は決まった。"
expect_pass "括弧の中に脇置き"       "問いの扱いはアに決まった（設計書の J2）。"
expect_pass "インラインコード"       "設定は \`J2\` と \`foo.md:12\` にある。"
expect_pass "コードブロック"         $'例:\n```\nJ2 K3 #552\n```\n以上。'
expect_pass "リンクの行き先"         "[設計書](docs/design.md:12) を見る。"
expect_pass "URL"                    "https://github.com/owner/repo/issues/552#issuecomment-1 を見る。"
expect_pass "版番号や語の一部"       "v2.1 と UTF-8 と claude-opus-5 を使う。"
expect_pass "時刻"                   "10:15 に作成した。"

# 入力の解析に失敗しても通す
out=$(printf 'not json' | bash "$HOOK")
if [[ -z "$out" ]]; then
    printf 'ok   %s\n' "不正な入力は通す"
else
    printf 'FAIL %s (out: %s)\n' "不正な入力は通す" "$out"
    failures=$((failures + 1))
fi

# 検出した記号だけを記録し、応答の本文は残さない
run false "秘密の本文 J2 を含む応答。" > /dev/null
log=$(cat "$HOME"/.claude/logs/internal-symbols-*.log 2>/dev/null || true)
if printf '%s' "$log" | grep -qF "J2" && ! printf '%s' "$log" | grep -qF "秘密の本文"; then
    printf 'ok   %s\n' "記録は記号だけ"
else
    printf 'FAIL %s (log: %s)\n' "記録は記号だけ" "$log"
    failures=$((failures + 1))
fi

if [[ "$failures" -gt 0 ]]; then
    printf '\n%d 件失敗\n' "$failures"
    exit 1
fi
printf '\n全件成功\n'
