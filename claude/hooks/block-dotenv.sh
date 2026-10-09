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
# 除外はツール名と組にして行う。項目名だけで一律に除くと、MCP ツール等の
# 同名の引数まで検査から漏れる。未知のツールは全文字列を検査する。
matched=$(printf '%s' "$input" \
    | jq -r '
        if   .tool_name == "Write"        then del(.tool_input.content)
        elif .tool_name == "Edit"         then del(.tool_input.old_string, .tool_input.new_string)
        elif .tool_name == "MultiEdit"    then del(.tool_input.edits[]?.old_string, .tool_input.edits[]?.new_string)
        elif .tool_name == "NotebookEdit" then del(.tool_input.new_source)
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
    echo "block-dotenv: .env ファイルへのアクセスはブロックされました" >&2
    exit 2
fi

exit 0
