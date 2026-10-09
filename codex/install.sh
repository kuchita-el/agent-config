#!/bin/bash
# codex/config.toml を ~/.codex/config.toml へ統合する。
#
# Codex は trust やフックの承認、画面の表示状態（端末状態）を、設定と同じ config.toml へ書き込む。端末状態を
# リポジトリへ入れないため、シンボリックリンクにはせず実ファイルとする。リポジトリの内容を土台に、
# 既存のファイルから端末状態の表だけを持ち越して書き出し、それ以外はリポジトリの内容で上書きする。
set -euo pipefail

SRC_DIR="$(cd "$(dirname "$0")" && pwd)"
CODEX_SRC="$SRC_DIR/config.toml"
CODEX_DEST_ROOT="${CODEX_HOME:-$HOME/.codex}"
CODEX_DEST="$CODEX_DEST_ROOT/config.toml"
BACKUP_DIR="$CODEX_DEST_ROOT/backups/agent-config"

# 標準入力の TOML を表の見出しで区切り、端末状態の表（state）か、それ以外の管理部分（managed）を出す。
# 端末状態の表は、[projects.*]（trust）と、[hooks.state] とその下の表（フックの承認）、[tui] とその下の表（画面の表示状態）。
# 最初の見出しより前のキーは、管理部分に含める。
split_toml() {
    awk -v mode="$1" '
        /^\[/ { in_state = ($0 ~ /^\[(projects\.|hooks\.state[].]|tui[].])/) }
        { if (in_state) { if (mode == "state") print } else { if (mode == "managed") print } }
    '
}

# 管理部分を比較用に正規化する。空行と、Codex が管理部分の表へ書き足す実行時のキー（last_updated）を除く。
normalize_managed() {
    split_toml managed | grep -v -E -e '^[[:space:]]*$' -e '^last_updated[[:space:]]*=' || true
}

# 標準入力の TOML から、Git のマーケットプレイスの「名前<TAB>参照先」を出す（source_type が local のものは除く）
list_git_marketplaces() {
    awk '
        function flush() { if (name != "" && src != "" && !is_local) print name "\t" src }
        /^\[/ { flush(); name = ""; src = ""; is_local = 0 }
        /^\[marketplaces\.[^]]*\]/ { name = $0; sub(/^\[marketplaces\./, "", name); sub(/\].*$/, "", name) }
        name != "" && /^source_type[[:space:]]*=/ && /"local"/ { is_local = 1 }
        name != "" && /^source[[:space:]]*=/ { src = $0; sub(/^source[[:space:]]*=[[:space:]]*"/, "", src); sub(/".*$/, "", src) }
        END { flush() }
    '
}

if [ ! -f "$CODEX_SRC" ]; then
    echo "[エラー] ソースファイルが見つかりません: $CODEX_SRC" >&2
    exit 1
fi

if [ -n "$(split_toml state < "$CODEX_SRC")" ]; then
    echo "[エラー] $CODEX_SRC に端末状態の表（[projects.*] / [hooks.state] / [tui]）があります。リポジトリから取り除いてください" >&2
    exit 1
fi

if ! command -v python3 &>/dev/null || ! python3 -I -c 'import tomllib' 2>/dev/null; then
    echo "[エラー] 統合した結果の検証に python3（3.11 以上。tomllib を使う）が必要です" >&2
    exit 1
fi

mkdir -p "$CODEX_DEST_ROOT"

current=""
if [ -L "$CODEX_DEST" ] && [ ! -e "$CODEX_DEST" ]; then
    echo "[警告] $CODEX_DEST はリンク先の無いシンボリックリンクです（$(readlink "$CODEX_DEST")）。端末状態は持ち越せません"
elif [ -f "$CODEX_DEST" ]; then
    current=$(cat "$CODEX_DEST")
elif [ -e "$CODEX_DEST" ]; then
    echo "[エラー] $CODEX_DEST は通常ファイルまたはシンボリックリンクではありません" >&2
    exit 1
fi

state=$(printf '%s\n' "$current" | split_toml state)
merged=$(cat "$CODEX_SRC")
if [ -n "$state" ]; then
    merged="$merged"$'\n\n'"$state"
fi

if ! printf '%s\n' "$merged" | python3 -I -c 'import sys, tomllib; tomllib.loads(sys.stdin.read())' 2>/dev/null; then
    echo "[エラー] 統合した結果が TOML として読めません。$CODEX_DEST は変更していません" >&2
    exit 1
fi

if [ ! -L "$CODEX_DEST" ] && [ "$merged" = "$current" ]; then
    echo "[スキップ] config.toml: 統合済みです"
else
    if [ -n "$current" ]; then
        managed_dest=$(printf '%s\n' "$current" | normalize_managed)
        managed_src=$(normalize_managed < "$CODEX_SRC")
        if [ "$managed_dest" != "$managed_src" ]; then
            echo "[差分] 管理部分がリポジトリの内容と異なるため、リポジトリの内容で上書きします"
            diff -u --label "$CODEX_DEST" --label "$CODEX_SRC" \
                <(printf '%s\n' "$managed_dest") <(printf '%s\n' "$managed_src") || true
            mkdir -p "$BACKUP_DIR"
            backup_path="$BACKUP_DIR/config.toml.$(date +%Y%m%d%H%M%S)"
            if [ -e "$backup_path" ]; then
                backup_path="$backup_path.$$"
            fi
            printf '%s\n' "$current" > "$backup_path"
            echo "[バックアップ] $CODEX_DEST → $backup_path"
        fi
    fi
    tmp=$(mktemp "$CODEX_DEST_ROOT/config.toml.XXXXXX")
    printf '%s\n' "$merged" > "$tmp"
    mv -f "$tmp" "$CODEX_DEST"
    echo "[作成] $CODEX_DEST（リポジトリの内容に端末状態を統合）"
fi

# マーケットプレイスの取得
# Git のマーケットプレイスは、config.toml に宣言しただけでは取得されない。upgrade で取得すると、
# 有効にしたプラグインのキャッシュまで作られるため、plugin add は要らない。config.toml の管理部分は変わらない。
echo ""
echo "=== マーケットプレイス ==="
if ! command -v codex &>/dev/null; then
    echo "[スキップ] codex CLIが見つかりません"
else
    while IFS=$'\t' read -r mp_name _; do
        if ! codex plugin marketplace upgrade "$mp_name"; then
            echo "[警告] マーケットプレイス $mp_name を取得できませんでした。codex plugin marketplace upgrade $mp_name を再実行してください"
        fi
    done < <(list_git_marketplaces < "$CODEX_SRC")
fi
