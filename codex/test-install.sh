#!/bin/bash
set -euo pipefail

TEST_ROOT=$(mktemp -d)
trap 'rm -rf "$TEST_ROOT"' EXIT

export HOME="$TEST_ROOT/home"
export CODEX_HOME="$HOME/.codex"
mkdir -p "$CODEX_HOME"
printf 'existing config\n' > "$CODEX_HOME/config.toml"
printf 'untouched state\n' > "$CODEX_HOME/state.db"

bash "$(cd "$(dirname "$0")" && pwd)/install.sh"

managed_config="$(cd "$(dirname "$0")" && pwd)/config.toml"
test -L "$CODEX_HOME/config.toml"
test "$(readlink "$CODEX_HOME/config.toml")" = "$managed_config"
backup_config=$(find "$CODEX_HOME/backups/dotfiles" -maxdepth 1 -type f -name 'config.toml.*' -print -quit)
test -n "$backup_config"
cmp -s "$backup_config" <(printf 'existing config\n')
test "$(cat "$CODEX_HOME/state.db")" = 'untouched state'

first_target=$(readlink "$CODEX_HOME/config.toml")
bash "$(cd "$(dirname "$0")" && pwd)/install.sh" >/dev/null
test "$(readlink "$CODEX_HOME/config.toml")" = "$first_target"
test "$(find "$CODEX_HOME/backups/dotfiles" -maxdepth 1 -type f | wc -l)" -eq 1

echo "codex installer tests passed"
