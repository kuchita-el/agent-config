#!/bin/bash
# hooks/log-confusion.sh のテスト。UserPromptSubmit の入力 JSON を標準入力で与え、記録の有無と標準出力で判定する。
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
HOOK="$SCRIPT_DIR/hooks/log-confusion.sh"

TEST_ROOT=$(mktemp -d)
trap 'rm -rf "$TEST_ROOT"' EXIT
export HOME="$TEST_ROOT/home"
mkdir -p "$HOME"

TRANSCRIPT="$TEST_ROOT/session.jsonl"
{
    jq -cn '{type: "user", message: {role: "user", content: "最初の依頼"}}'
    jq -cn '{type: "assistant", message: {content: [{type: "text", text: "古い応答"}]}}'
    jq -cn '{type: "user", message: {role: "user", content: [{type: "tool_result", content: "結果"}]}}'
    jq -cn '{type: "assistant", message: {content: [{type: "tool_use", name: "Bash"}]}}'
    jq -cn '{type: "assistant", message: {content: [{type: "text", text: "J2 はアで確定。K3 は保留でよいか。"}]}}'
} > "$TRANSCRIPT"

failures=0

log_lines() { cat "$HOME"/.claude/logs/confusion-*.jsonl 2>/dev/null | wc -l || true; }

# run <発言> [transcript_path]: フックを走らせ、標準出力を返す
run() {
    jq -cn --arg p "$1" --arg t "${2:-$TRANSCRIPT}" \
        '{session_id: "test", cwd: "/work", hook_event_name: "UserPromptSubmit", prompt: $p, transcript_path: $t}' \
        | bash "$HOOK"
}

# expect <説明> <発言> <記録が増える件数>
expect() {
    local desc=$1 prompt=$2 want=$3 before after out
    before=$(log_lines)
    out=$(run "$prompt")
    after=$(log_lines)
    if [[ -z "$out" && $((after - before)) -eq "$want" ]]; then
        printf 'ok   %s\n' "$desc"
    else
        printf 'FAIL %s (stdout: %s, 増分: %s)\n' "$desc" "$out" "$((after - before))"
        failures=$((failures + 1))
    fi
}

expect "全角の？だけ"           "？"                         1
expect "半角の?だけ"            "?"                          1
expect "前後に空白のある？"     "  ？ "                      1
expect "分からないを含む"       "何を聞かれているのか分からない" 1
expect "どういうことを含む"     "日程の行を足すってどういうこと？" 1
expect "ふつうの依頼"           "進めて"                     0
expect "？で終わる問い"         "これでいい？"               0
expect "空の発言"               ""                           0

expect "サブエージェントの報告"  "<task-notification> 分からない点がある </task-notification>" 0
expect "他セッションのメッセージ" $'  <cross-session-message from="x">\n？' 0

# check <説明> <条件の終了コード>
check() {
    if [[ "$2" -eq 0 ]]; then printf 'ok   %s\n' "$1"; else printf 'FAIL %s\n' "$1"; failures=$((failures + 1)); fi
}
last_rec() { tail -n 1 "$HOME"/.claude/logs/confusion-*.jsonl; }

# 控えが無いときは、記録ファイルの直前のテキスト応答を使い、ツール呼び出しは飛ばす
rec=$(last_rec)
[[ "$(printf '%s' "$rec" | jq -r '.assistant')" == "J2 はアで確定。K3 は保留でよいか。" \
   && "$(printf '%s' "$rec" | jq -r '.prompt')" == "日程の行を足すってどういうこと？" \
   && "$(printf '%s' "$rec" | jq -r '.source')" == "transcript" ]]
check "控えが無いときは記録ファイルの直前の応答" $?

# 応答の終了時の控え（save-last-reply.sh）
SAVE="$SCRIPT_DIR/hooks/save-last-reply.sh"
stop() {
    jq -cn --argjson a "$1" --arg m "$2" \
        '{session_id: "test", hook_event_name: "Stop", stop_hook_active: $a, last_assistant_message: $m}' \
        | bash "$SAVE"
}
SAVED="$HOME/.claude/logs/last-reply/test.txt"

out=$(stop false "元の応答。")
[[ -z "$out" && "$(cat "$SAVED")" == "元の応答。" ]]
check "控えは最後の応答で、標準出力は空" $?

stop true "追記の応答。" > /dev/null
[[ "$(cat "$SAVED")" == $'元の応答。\n\n追記の応答。' ]]
check "差し止めで続いた回は追記する" $?

stop false "次のターンの応答。" > /dev/null
[[ "$(cat "$SAVED")" == "次のターンの応答。" ]]
check "次のターンでは上書きする" $?

# 控えがあれば、記録ファイルより控えを優先する
run "？" > /dev/null
rec=$(last_rec)
[[ "$(printf '%s' "$rec" | jq -r '.assistant')" == "次のターンの応答。" \
   && "$(printf '%s' "$rec" | jq -r '.source')" == "stop-hook" ]]
check "控えを優先する" $?

# セッション ID にパスの区切りがあれば、控えを書かない
jq -cn '{session_id: "../x", last_assistant_message: "m"}' | bash "$SAVE"
[[ ! -e "$HOME/.claude/logs/x.txt" ]]
check "不正なセッション ID では書かない" $?

# 記録の場所が無い・壊れた入力でも、何も出さずに終わる
out=$(run "？" "$TEST_ROOT/missing.jsonl"); rc=$?
if [[ -z "$out" && $rc -eq 0 ]]; then printf 'ok   %s\n' "記録の写しが無い"; else printf 'FAIL %s\n' "記録の写しが無い"; failures=$((failures + 1)); fi
out=$(printf 'not json' | bash "$HOOK"); rc=$?
if [[ -z "$out" && $rc -eq 0 ]]; then printf 'ok   %s\n' "不正な入力"; else printf 'FAIL %s\n' "不正な入力"; failures=$((failures + 1)); fi

if [[ "$failures" -gt 0 ]]; then
    printf '\n%d 件失敗\n' "$failures"
    exit 1
fi
printf '\n全件成功\n'
