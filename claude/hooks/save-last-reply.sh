#!/bin/bash
# Stop hook: 主セッションの最後の応答を、セッションごとに手元へ保存する。
#
# log-confusion.sh（UserPromptSubmit）が、利用者に通じなかった応答を記録するときに使う。
# UserPromptSubmit の時点では会話の記録ファイル（transcript）の書き込みが遅れうると
# 公式文書にあるため、Stop の入力に確実に入る last_assistant_message を控えておく。
#
# 保存先は ~/.claude/logs/last-reply/<session_id>.txt。毎ターン上書きする。
# 別の Stop フックの差し止めで同じターンが続いた回（stop_hook_active が true）は、
# 追記の応答を後ろへ足す。利用者が読んだのは元の応答と追記の両方のため。
# 失敗しても常に exit 0。標準出力には何も出さない。

set -uo pipefail

DIR="$HOME/.claude/logs/last-reply"

input=$(cat)

session=$(printf '%s' "$input" | jq -r '.session_id // ""' 2>/dev/null) || exit 0
[[ -z "$session" || "$session" == */* ]] && exit 0
msg=$(printf '%s' "$input" | jq -r '.last_assistant_message // ""' 2>/dev/null) || exit 0
[[ -z "$msg" ]] && exit 0
active=$(printf '%s' "$input" | jq -r '.stop_hook_active // false' 2>/dev/null) || exit 0

mkdir -p "$DIR" 2>/dev/null || exit 0
if [[ "$active" == "true" && -f "$DIR/$session.txt" ]]; then
    printf '\n\n%s' "$msg" >> "$DIR/$session.txt" 2>/dev/null || true
else
    printf '%s' "$msg" > "$DIR/$session.txt" 2>/dev/null || true
fi

exit 0
