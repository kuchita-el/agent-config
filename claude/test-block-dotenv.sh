#!/bin/bash
# hooks/block-dotenv.sh のテスト。PreToolUse の入力 JSON を標準入力で与え、終了コードで判定する。
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
HOOK="$SCRIPT_DIR/hooks/block-dotenv.sh"

TEST_ROOT=$(mktemp -d)
trap 'rm -rf "$TEST_ROOT"' EXIT
export HOME="$TEST_ROOT/home"
mkdir -p "$HOME"

# dotenv の表記はソースに直接書かず実行時に組み立てる。
# 現行フックの下でこのファイル自体の Write や Bash 経由の参照がブロックされるのを避けるため。
DOT=$(printf '.%s' env)
SECRET='SECRET_VALUE_MUST_NOT_BE_LOGGED'

failures=0

# check <期待終了コード> <説明> <tool_name> <tool_input JSON>
check() {
    local expected=$1 desc=$2 tool=$3 tool_input=$4
    local payload actual
    payload=$(jq -cn --arg tool "$tool" --argjson ti "$tool_input" \
        '{session_id: "test", cwd: "/work", hook_event_name: "PreToolUse", tool_name: $tool, tool_input: $ti}')
    set +e
    printf '%s' "$payload" | bash "$HOOK" 2>/dev/null
    actual=$?
    set -e
    if [[ "$actual" -eq "$expected" ]]; then
        printf 'ok   %s\n' "$desc"
    else
        printf 'FAIL %s (expected %s, got %s)\n' "$desc" "$expected" "$actual"
        failures=$((failures + 1))
    fi
}

ti() { jq -cn "$@"; }

# AC1: file_path（NotebookEdit は notebook_path）が dotenv を指す → ブロック
check 2 "AC1 Write file_path" Write "$(ti --arg p "/work/$DOT" '{file_path: $p, content: "x"}')"
check 2 "AC1 Edit file_path (拡張子つき)" Edit "$(ti --arg p "/work/$DOT.local" '{file_path: $p, old_string: "a", new_string: "b"}')"
check 2 "AC1 Read file_path (相対)" Read "$(ti --arg p "$DOT" '{file_path: $p}')"
check 2 "AC1 NotebookEdit notebook_path" NotebookEdit "$(ti --arg p "/work/$DOT" '{notebook_path: $p, new_source: "x"}')"
check 2 "AC1 MultiEdit file_path" MultiEdit "$(ti --arg p "/work/$DOT" '{file_path: $p, edits: [{old_string: "a", new_string: "b"}]}')"

# AC2: Grep・Glob の path / pattern が dotenv を指す → ブロック
check 2 "AC2 Grep path" Grep "$(ti --arg p "/work/$DOT" '{pattern: "KEY", path: $p}')"
check 2 "AC2 Grep pattern" Grep "$(ti --arg p "$DOT" '{pattern: $p}')"
check 2 "AC2 Glob pattern" Glob "$(ti --arg p "**/$DOT" '{pattern: $p}')"
check 2 "AC2 Glob path" Glob "$(ti --arg p "/work/$DOT.d" '{pattern: "*", path: $p}')"

# AC3: Bash の command が dotenv のパスを含む → ブロック
check 2 "AC3 Bash cat" Bash "$(ti --arg c "cat $DOT" '{command: $c}')"
check 2 "AC3 Bash git show" Bash "$(ti --arg c "git show HEAD:$DOT.local" '{command: $c}')"
check 2 "AC3 Bash リダイレクト" Bash "$(ti --arg c "echo x > $DOT" '{command: $c}')"

# AC4: Write で本文にだけ dotenv の表記を含む → 通過
check 0 "AC4 Write content のみ" Write "$(ti --arg c "denyRead: [\"~/**/$DOT\", \"~/**/$DOT.*\"]" '{file_path: "/work/docs/example.md", content: $c}')"

# AC5: Edit で old_string / new_string にだけ dotenv の表記を含む → 通過
check 0 "AC5 Edit new_string のみ" Edit "$(ti --arg s "see $DOT here" '{file_path: "/work/docs/example.md", old_string: "see x here", new_string: $s}')"
check 0 "AC5 Edit old_string のみ" Edit "$(ti --arg s "see $DOT here" '{file_path: "/work/docs/example.md", old_string: $s, new_string: "see x here"}')"

# AC4・5 と同型: NotebookEdit / MultiEdit の本文 → 通過
check 0 "NotebookEdit new_source のみ" NotebookEdit "$(ti --arg s "open('$DOT')" '{notebook_path: "/work/a.ipynb", new_source: $s}')"
check 0 "MultiEdit edits の本文のみ" MultiEdit "$(ti --arg s "cat $DOT" '{file_path: "/work/a.md", edits: [{old_string: $s, new_string: "x"}, {old_string: "y", new_string: $s}]}')"

# AC6: 上記以外のツールは任意の引数を検査する（現行の挙動を維持）
check 2 "AC6 MCP path 引数" mcp__fs__read "$(ti --arg p "/work/$DOT" '{path: $p}')"
check 2 "AC6 MCP content 引数 (本文除外はツール限定)" mcp__fs__write "$(ti --arg c "cat $DOT" '{target: "/work/a.md", content: $c}')"
check 2 "AC6 MCP 入れ子の引数" mcp__x__y "$(ti --arg p "$DOT" '{opts: {files: [$p]}}')"

# AC7: 語の延長はどのツール・どの項目でも通過（現行の挙動を維持）
EXT="${DOT}oy.json"
check 0 "AC7 Write file_path" Write "$(ti --arg p "/work/$EXT" '{file_path: $p, content: "x"}')"
check 0 "AC7 Read file_path" Read "$(ti --arg p "/work/$EXT" '{file_path: $p}')"
check 0 "AC7 Grep path" Grep "$(ti --arg p "/work/$EXT" '{pattern: "x", path: $p}')"
check 0 "AC7 Glob pattern" Glob "$(ti --arg p "**/$EXT" '{pattern: $p}')"
check 0 "AC7 Bash command" Bash "$(ti --arg c "cat $EXT" '{command: $c}')"
check 0 "AC7 MCP 引数" mcp__fs__read "$(ti --arg p "/work/$EXT" '{path: $p}')"

# ブロック時のログに本文を残さない
check 2 "ログ検査用: Write file_path + 本文" Write "$(ti --arg p "/work/$DOT" --arg c "$SECRET" '{file_path: $p, content: $c}')"
check 2 "ログ検査用: MCP 引数に本文" mcp__fs__write "$(ti --arg p "/work/$DOT" --arg c "$SECRET" '{path: $p, content: $c}')"
if command grep -rqF "$SECRET" "$HOME/.claude/logs"; then
    printf 'FAIL ブロック時のログに本文が含まれる\n'
    failures=$((failures + 1))
else
    printf 'ok   ブロック時のログに本文が含まれない\n'
fi

if [[ "$failures" -gt 0 ]]; then
    printf '%d 件失敗\n' "$failures"
    exit 1
fi
echo "block-dotenv hook tests passed"
