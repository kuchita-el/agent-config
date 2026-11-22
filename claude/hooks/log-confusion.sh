#!/bin/bash
# UserPromptSubmit hook: 利用者が直前の応答を分からないと返したとき、その応答を手元へ記録する。
#
# AI の問いや報告が利用者に通じなかった例を、後で判定（応答の終了時の判定型フック）を
# 改良する素材にするため、機械的に集める。AI が自分で記録するかどうかに頼らない。
#
# 合図とみなす発言:
#   - 「？」「?」だけ（前後の空白は無視）
#   - 「分からない」「わからない」「どういうこと」「何のこと」「なんのこと」「意味が分から」を含む
# 後者は直前の応答と無関係な発言（例: エラーの原因が分からない）も拾う。記録には発言も
# 残すので、使うときに選り分ける。
#
# 記録先は ~/.claude/logs/confusion-YYYYMM.jsonl。応答の本文を含むので手元だけに置く。
# 標準出力に何か出すと会話の文脈に足されるため、何も出さない。失敗しても常に exit 0。

set -uo pipefail

LOG_DIR="$HOME/.claude/logs"

input=$(cat)

prompt=$(printf '%s' "$input" | jq -r '.prompt // ""' 2>/dev/null) || exit 0
[[ -z "$prompt" ]] && exit 0

# UserPromptSubmit は、背景サブエージェントの報告・他セッションからのメッセージ・予約タスクでも
# 発火する。これらはタグで始まるので除く。
[[ "$(printf '%s' "$prompt" | sed -n '1{s/^[[:space:]]*//;p}')" == \<* ]] && exit 0

trimmed=$(printf '%s' "$prompt" | tr -d '[:space:]　')
if [[ "$trimmed" != "？" && "$trimmed" != "?" ]] \
    && ! printf '%s' "$prompt" | grep -qE '分からない|わからない|どういうこと|何のこと|なんのこと|意味が分から'; then
    exit 0
fi

# 直前のアシスタント応答の本文。save-last-reply.sh（Stop）が控えたものを優先する。
# 控えが無いときだけ、会話の記録ファイルの最後のテキスト応答を使う（書き込みが遅れていれば
# 一つ前の応答になりうる。記録の source 欄で区別できるようにする）。
session=$(printf '%s' "$input" | jq -r '.session_id // ""' 2>/dev/null) || exit 0
saved="$HOME/.claude/logs/last-reply/$session.txt"
source="stop-hook"
last=""
if [[ -n "$session" && "$session" != */* && -f "$saved" ]]; then
    last=$(cat "$saved" 2>/dev/null) || last=""
fi
if [[ -z "$last" ]]; then
    source="transcript"
    transcript=$(printf '%s' "$input" | jq -r '.transcript_path // ""' 2>/dev/null) || exit 0
    transcript="${transcript/#\~/$HOME}"
    [[ -f "$transcript" ]] || exit 0
    last=$(jq -rs '
        [ .[] | select(.type == "assistant")
          | [ .message.content[]? | select(type == "object" and .type == "text") | .text ] | join("\n")
          | select(. != "") ]
        | last // ""
      ' "$transcript" 2>/dev/null) || exit 0
fi
[[ -z "$last" ]] && exit 0

mkdir -p "$LOG_DIR" 2>/dev/null || exit 0
jq -cn \
    --arg ts "$(date -Iseconds)" \
    --arg session "${session:-unknown}" \
    --arg cwd "$(printf '%s' "$input" | jq -r '.cwd // ""' 2>/dev/null)" \
    --arg prompt "$prompt" \
    --arg assistant "$last" \
    --arg source "$source" \
    '{ts: $ts, session_id: $session, cwd: $cwd, prompt: $prompt, assistant: $assistant, source: $source}' \
    >> "$LOG_DIR/confusion-$(date +%Y%m).jsonl" 2>/dev/null || true

exit 0
