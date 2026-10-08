#!/bin/bash
# PostToolUseフック: ツール呼び出しをログに記録する
#
# 出力先: ~/.claude/logs/tool-use-YYYYMMDD.log
# 形式: タイムスタンプ | セッションID | ツール名 | ツール入力(JSON)

INPUT=$(cat)

LOG_DIR="$HOME/.claude/logs"
mkdir -p "$LOG_DIR"
LOG_FILE="$LOG_DIR/tool-use-$(date +%Y%m%d).log"

TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // "N/A"')
TOOL_INPUT=$(echo "$INPUT" | jq -c '.tool_input // {}')
SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // "unknown"')
TIMESTAMP=$(date -Iseconds)

echo "${TIMESTAMP} | ${SESSION_ID} | ${TOOL_NAME} | ${TOOL_INPUT}" >> "$LOG_FILE"

exit 0
