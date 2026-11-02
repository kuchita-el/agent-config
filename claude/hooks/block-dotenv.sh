#!/bin/bash
# PreToolUse hook: ツール呼び出し JSON 内の .env パス参照を検出してブロックする。
# 主防御層 (L2) として settings.json の deny ルール (L3) を補完する。

set -euo pipefail

LOG_DIR="$HOME/.claude/logs"
LOG_FILE="$LOG_DIR/blocked-dotenv-$(date +%Y%m%d).log"

input=$(cat)

# JSON 内の文字列値 (.. | strings) を再帰抽出して
# .env / .env.<ext> をパス境界つきで検出する。
#
# 境界文字 (前): 行頭 / `/` ` ` `\t` `"` `'` `=` `:`
# 境界文字 (後): 行末 / `/` ` ` `\t` `"` `'` `=` `:` `>`
# 例:
#   ".env"            → match
#   "/abs/.env.local" → match
#   "cat .env"        → match
#   ".envoy.json"     → no match (語延長は除外)
#   "./env"           → no match (`.env` 部分文字列が存在しない)
#
# regex は awk スクリプト内にリテラル埋め込みする。
# `-v pat=` 経由だと awk の文字列エスケープ処理で `\.` が `.` (任意文字) に
# 退化し、`.envoy.json` のような語延長を誤検出するため。
#
# ファイルへ書き込む本文の項目は検査から除く。本文で dotenv に言及するだけの
# 書き込み（ドキュメント・設定例）を誤ってブロックしないため。書き込み先の
# パス項目は除かないので、dotenv 自体への書き込みは引き続きブロックされる。
# 同じ理由で、ファイル操作に使われない文章の項目（コマンドの説明文、サブエージェント
# への依頼文と報告文、ユーザーへの問い、検索語等）も検査から除く。ファイル名に
# 触れるだけの文章でのブロックが、誤検知の大半を占めていたため。実際の読み書きは、
# 依頼を受けたサブエージェント自身のツール呼び出しで検査される。
# 除外はツール名と組にして行う。項目名だけで一律に除くと、MCP ツール等の
# 同名の引数まで検査から漏れる。未知のツールは全文字列を検査する。
matched=$(printf '%s' "$input" \
    | jq -r '
        if   .tool_name == "Write"            then del(.tool_input.content)
        elif .tool_name == "Edit"             then del(.tool_input.old_string, .tool_input.new_string)
        elif .tool_name == "MultiEdit"        then del(.tool_input.edits[]?.old_string, .tool_input.edits[]?.new_string)
        elif .tool_name == "NotebookEdit"     then del(.tool_input.new_source)
        elif .tool_name == "Bash"             then del(.tool_input.description)
        elif .tool_name == "Monitor"          then del(.tool_input.description)
        elif .tool_name == "Agent"            then del(.tool_input.prompt, .tool_input.description)
        elif .tool_name == "SubagentHandback" then del(.tool_input.message)
        elif .tool_name == "SendMessage"      then del(.tool_input.message, .tool_input.summary)
        elif .tool_name == "AskUserQuestion"  then del(.tool_input.questions)
        elif .tool_name == "WebFetch"         then del(.tool_input.prompt)
        elif .tool_name == "WebSearch"        then del(.tool_input.query)
        elif .tool_name == "ScheduleWakeup"   then del(.tool_input.reason, .tool_input.prompt)
        else . end
        | .. | strings
      ' 2>/dev/null \
    | awk '
        /(^|[\/ \t"'"'"'=:])\.env(\.[^\/ \t"'"'"'=:]*)?($|[\/ \t"'"'"'=:>])/ {
            print
            found = 1
        }
        END { exit (found ? 0 : 1) }
      ' \
    || true)

if [[ -n "$matched" ]]; then
    mkdir -p "$LOG_DIR"
    ts=$(date -Iseconds)
    session=$(printf '%s' "$input" | jq -r '.session_id // "unknown"' 2>/dev/null)
    tool=$(printf '%s' "$input" | jq -r '.tool_name // "unknown"' 2>/dev/null)
    # tool_input には書き込み内容など機密が含まれ得るため、
    # 入力 JSON 全体はログに残さない。matched（検出パス）のみ記録する。
    {
        printf '%s | %s | %s | blocked\n' "$ts" "$session" "$tool"
        printf '  matched: %s\n' "$(printf '%s' "$matched" | tr '\n' ' ')"
        printf -- '---\n'
    } >> "$LOG_FILE"
    # 検出した名前だけを抜き出して返す。どの部分を外せば通るかを示すため。
    names=$(printf '%s' "$matched" \
        | awk '{
            s = $0
            while (match(s, /(^|[\/ \t"'"'"'=:])\.env(\.[^\/ \t"'"'"'=:>]*)?($|[\/ \t"'"'"'=:>])/)) {
                t = substr(s, RSTART, RLENGTH)
                sub(/^[\/ \t"'"'"'=:]/, "", t)
                sub(/[\/ \t"'"'"'=:>]$/, "", t)
                print t
                s = substr(s, RSTART + RLENGTH)
            }
          }' \
        | sort -u | paste -sd ' ' -)
    cat >&2 <<EOF
block-dotenv: dotenv ファイルを指す引数があるため止めた（検出: ${names}）。
- 中身や値が要る場合は、会話ログ・履歴・別のファイル等の代わりの経路から拾わず、ユーザーに尋ねる。
- サンドボックス内の git status に出る未追跡の .env やドットファイル群、変更扱いの .env.example 等は、サンドボックスが拒否するパスに置く空ファイル等による見かけ上の変化で、作業による変更ではない。調べる必要はない。
- 存在や差分を確かめるだけの目的なら、該当の名前を外して実行し直す。
EOF
    exit 2
fi

exit 0
