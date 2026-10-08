#!/bin/bash
# claude/install.sh のテスト。仮の HOME に配置し、シンボリックリンク・退避・冪等性を確かめる。
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TEST_ROOT=$(mktemp -d)
trap 'rm -rf "$TEST_ROOT"' EXIT
export HOME="$TEST_ROOT/home"
mkdir -p "$HOME/.claude/agents"

# claude CLI を見つけさせない（プラグインの導入で、実環境やネットワークに触れないため）
SAFE_PATH=/usr/bin:/bin

failures=0
check() {
    local desc=$1
    shift
    if "$@"; then
        printf 'ok   %s\n' "$desc"
    else
        printf 'NG   %s\n' "$desc"
        failures=$((failures + 1))
    fi
}

# 退避の件数。退避先がまだ無いときは 0（find の失敗で set -e が止めないようにする）
backup_count() {
    { find "$HOME/.claude/backups/agent-config" -maxdepth 1 -type f 2>/dev/null || true; } | wc -l
}

# 既存の実ファイル。退避されてからシンボリックリンクに置き換わるはずのもの
printf 'old settings\n' > "$HOME/.claude/settings.json"
printf 'old agent\n' > "$HOME/.claude/agents/sweeper.md"

PATH="$SAFE_PATH" bash "$SCRIPT_DIR/install.sh" > /dev/null

check "settings.json がリポジトリへのシンボリックリンクになる" \
    test "$(readlink "$HOME/.claude/settings.json")" = "$SCRIPT_DIR/settings.json"
check "エージェント定義がリポジトリへのシンボリックリンクになる" \
    test "$(readlink "$HOME/.claude/agents/sweeper.md")" = "$SCRIPT_DIR/agents/sweeper.md"
check "既存の settings.json が agent-config の退避先へ移る" \
    test -n "$(find "$HOME/.claude/backups/agent-config" -maxdepth 1 -name 'settings.json.*' -print -quit 2>/dev/null)"
check "既存のエージェント定義が agent-config の退避先へ移る" \
    test -n "$(find "$HOME/.claude/backups/agent-config" -maxdepth 1 -name 'agents_sweeper.md.*' -print -quit 2>/dev/null)"
check "dotfiles の退避先を作らない" \
    test ! -e "$HOME/.claude/backups/dotfiles"

before=$(backup_count)
PATH="$SAFE_PATH" bash "$SCRIPT_DIR/install.sh" > /dev/null
check "2回目の実行では退避が増えない" test "$(backup_count)" -eq "$before"

if [ "$failures" -gt 0 ]; then
    printf '%d 件失敗\n' "$failures"
    exit 1
fi
echo "claude installer tests passed"
