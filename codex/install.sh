#!/bin/bash
set -euo pipefail

DOTFILES_DIR="$(cd "$(dirname "$0")" && pwd)"
CODEX_SRC="$DOTFILES_DIR/config.toml"
CODEX_DEST_ROOT="${CODEX_HOME:-$HOME/.codex}"
CODEX_DEST="$CODEX_DEST_ROOT/config.toml"
BACKUP_DIR="$CODEX_DEST_ROOT/backups/dotfiles"

if [ ! -f "$CODEX_SRC" ]; then
    echo "[エラー] ソースファイルが見つかりません: $CODEX_SRC" >&2
    exit 1
fi

mkdir -p "$CODEX_DEST_ROOT"

if [ -L "$CODEX_DEST" ] && [ "$(readlink "$CODEX_DEST")" = "$CODEX_SRC" ]; then
    echo "[スキップ] config.toml: 正しいシンボリックリンクが存在します"
    exit 0
fi

if [ -f "$CODEX_DEST" ] && [ ! -L "$CODEX_DEST" ]; then
    mkdir -p "$BACKUP_DIR"
    backup_name="config.toml.$(date +%Y%m%d%H%M%S)"
    backup_path="$BACKUP_DIR/$backup_name"
    if [ -e "$backup_path" ]; then
        backup_path="$BACKUP_DIR/config.toml.$(date +%Y%m%d%H%M%S).$$"
    fi
    echo "[バックアップ] $CODEX_DEST → $backup_path"
    mv "$CODEX_DEST" "$backup_path"
elif [ -L "$CODEX_DEST" ]; then
    echo "[警告] $CODEX_DEST は別のシンボリックリンクです（$(readlink "$CODEX_DEST")）。上書きします"
    rm "$CODEX_DEST"
elif [ -e "$CODEX_DEST" ]; then
    echo "[エラー] $CODEX_DEST は通常ファイルまたはシンボリックリンクではありません" >&2
    exit 1
fi

ln -s "$CODEX_SRC" "$CODEX_DEST"
echo "[作成] $CODEX_DEST → $CODEX_SRC"
