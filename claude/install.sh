#!/bin/bash
set -euo pipefail

DOTFILES_DIR="$(cd "$(dirname "$0")" && pwd)"
CLAUDE_SRC="$DOTFILES_DIR"
CLAUDE_DEST="$HOME/.claude"
BACKUP_DIR="$CLAUDE_DEST/backups/dotfiles"

FILES=("settings.json" "statusline-command.sh" "CLAUDE.md")

# プラットフォーム検出（ログ出力用）
detect_platform() {
    if [ -f /proc/version ] && grep -qi microsoft /proc/version; then
        echo "WSL"
    elif [ "$(uname)" = "Darwin" ]; then
        echo "macOS"
    elif [ -f /.dockerenv ] || [ -n "${REMOTE_CONTAINERS:-}" ] || [ -n "${CODESPACES:-}" ]; then
        echo "DevContainer"
    else
        echo "Linux"
    fi
}

platform=$(detect_platform)
echo "プラットフォーム: $platform"
echo "dotfilesディレクトリ: $DOTFILES_DIR"
echo ""

# ~/.claude/ の存在確認・作成
if [ ! -d "$CLAUDE_DEST" ]; then
    echo "$CLAUDE_DEST を作成します..."
    mkdir -p "$CLAUDE_DEST"
fi

for file in "${FILES[@]}"; do
    src="$CLAUDE_SRC/$file"
    dest="$CLAUDE_DEST/$file"

    if [ ! -f "$src" ]; then
        echo "[エラー] ソースファイルが見つかりません: $src"
        continue
    fi

    # すでに正しいシンボリックリンクの場合はスキップ
    if [ -L "$dest" ] && [ "$(readlink "$dest")" = "$src" ]; then
        echo "[スキップ] $file: 正しいシンボリックリンクが存在します"
        continue
    fi

    # 通常ファイルが存在する場合はバックアップ
    if [ -f "$dest" ] && [ ! -L "$dest" ]; then
        mkdir -p "$BACKUP_DIR"
        backup_name="${file}.$(date +%Y%m%d%H%M%S)"
        echo "[バックアップ] $dest → $BACKUP_DIR/$backup_name"
        mv "$dest" "$BACKUP_DIR/$backup_name"
    fi

    # 別のシンボリックリンクが存在する場合は警告して上書き
    if [ -L "$dest" ]; then
        echo "[警告] $dest は別のシンボリックリンクです（$(readlink "$dest")）。上書きします"
        rm "$dest"
    fi

    ln -s "$src" "$dest"
    echo "[作成] $dest → $src"
done

# hooks ディレクトリ内のスクリプトをシンボリックリンク
HOOKS_SRC="$CLAUDE_SRC/hooks"
HOOKS_DEST="$CLAUDE_DEST/hooks"

if [ -d "$HOOKS_SRC" ]; then
    mkdir -p "$HOOKS_DEST"
    for hook_file in "$HOOKS_SRC"/*.sh; do
        [ -f "$hook_file" ] || continue
        name=$(basename "$hook_file")
        src="$HOOKS_SRC/$name"
        dest="$HOOKS_DEST/$name"

        if [ -L "$dest" ] && [ "$(readlink "$dest")" = "$src" ]; then
            echo "[スキップ] hooks/$name: 正しいシンボリックリンクが存在します"
            continue
        fi

        if [ -f "$dest" ] && [ ! -L "$dest" ]; then
            mkdir -p "$BACKUP_DIR"
            backup_name="hooks_${name}.$(date +%Y%m%d%H%M%S)"
            echo "[バックアップ] $dest → $BACKUP_DIR/$backup_name"
            mv "$dest" "$BACKUP_DIR/$backup_name"
        fi

        if [ -L "$dest" ]; then
            echo "[警告] $dest は別のシンボリックリンクです（$(readlink "$dest")）。上書きします"
            rm "$dest"
        fi

        ln -s "$src" "$dest"
        echo "[作成] hooks/$name → $src"
    done
fi

# agents ディレクトリ内のエージェント定義をシンボリックリンク
AGENTS_SRC="$CLAUDE_SRC/agents"
AGENTS_DEST="$CLAUDE_DEST/agents"

if [ -d "$AGENTS_SRC" ]; then
    mkdir -p "$AGENTS_DEST"
    for agent_file in "$AGENTS_SRC"/*.md; do
        [ -f "$agent_file" ] || continue
        name=$(basename "$agent_file")
        src="$AGENTS_SRC/$name"
        dest="$AGENTS_DEST/$name"

        if [ -L "$dest" ] && [ "$(readlink "$dest")" = "$src" ]; then
            echo "[スキップ] agents/$name: 正しいシンボリックリンクが存在します"
            continue
        fi

        if [ -f "$dest" ] && [ ! -L "$dest" ]; then
            mkdir -p "$BACKUP_DIR"
            backup_name="agents_${name}.$(date +%Y%m%d%H%M%S)"
            echo "[バックアップ] $dest → $BACKUP_DIR/$backup_name"
            mv "$dest" "$BACKUP_DIR/$backup_name"
        fi

        if [ -L "$dest" ]; then
            echo "[警告] $dest は別のシンボリックリンクです（$(readlink "$dest")）。上書きします"
            rm "$dest"
        fi

        ln -s "$src" "$dest"
        echo "[作成] agents/$name → $src"
    done
fi

# git global ignore（settings.local.json を全リポジトリで無視）
GIT_IGNORE_DIR="$HOME/.config/git"
GIT_IGNORE_FILE="$GIT_IGNORE_DIR/ignore"
IGNORE_PATTERN="**/.claude/settings.local.json"

mkdir -p "$GIT_IGNORE_DIR"
if [ ! -f "$GIT_IGNORE_FILE" ]; then
    echo "$IGNORE_PATTERN" > "$GIT_IGNORE_FILE"
    echo "[作成] $GIT_IGNORE_FILE"
elif ! grep -qF "$IGNORE_PATTERN" "$GIT_IGNORE_FILE"; then
    echo "$IGNORE_PATTERN" >> "$GIT_IGNORE_FILE"
    echo "[追加] $GIT_IGNORE_FILE に $IGNORE_PATTERN を追加しました"
else
    echo "[スキップ] $GIT_IGNORE_FILE: パターンは既に存在します"
fi
# プラグインのセットアップ
#
# settings.json の extraKnownMarketplaces / enabledPlugins を単一の出典とし、
# そこから実体の配置を導出する。プラグインを増減させる際は settings.json だけを編集すればよい。
#
# 宣言済みのものを add / install しても settings.json は書き換えられない（宣言と一致するため
# 書き込みが発生しない）。逆に未宣言のものを扱うとCLIが settings.json へ追記するため、
# ここで扱う対象は必ず settings.json に宣言しておくこと。
#
# marketplace の登録は install の前提。未clone のマーケットプレイスからは
# plugin install が解決に失敗する。
SETTINGS_FILE="$CLAUDE_SRC/settings.json"

echo ""
echo "=== プラグイン ==="

if ! command -v claude &>/dev/null; then
    echo "[スキップ] claude CLIが見つかりません"
elif ! command -v jq &>/dev/null; then
    echo "[スキップ] jqが見つかりません"
else
    while IFS= read -r mp_name; do
        repo=$(jq -r --arg n "$mp_name" '.extraKnownMarketplaces[$n].source.repo // empty' "$SETTINGS_FILE")
        if [ -z "$repo" ]; then
            echo "[スキップ] marketplace $mp_name: github以外のsourceは未対応"
            continue
        fi
        claude plugin marketplace add "$repo" || true
        claude plugin marketplace update "$mp_name" || true
    done < <(jq -r '.extraKnownMarketplaces // {} | keys[]' "$SETTINGS_FILE")

    # 外部リポジトリをsourceに持つプラグイン（例: superpowers）は宣言だけでは実体が入らないため、
    # enabledPlugins の全件に対して明示的に install する
    while IFS= read -r plugin_id; do
        claude plugin install "$plugin_id" --scope user || true
    done < <(jq -r '.enabledPlugins // {} | to_entries[] | select(.value == true) | .key' "$SETTINGS_FILE")
fi

# サンドボックス依存の確認（導入は行わず、欠けていれば警告のみ）
# macOSはSeatbeltを使うためbwrap等は不要。Linux系（WSL/Linux/DevContainer）でのみ確認する。
if [ "$platform" != "macOS" ]; then
    echo ""
    echo "=== サンドボックス依存の確認 ==="

    sandbox_ok=1

    if ! command -v bwrap &>/dev/null; then
        echo "[警告] bwrap が見つかりません。サンドボックスが起動できません（wsl/install.sh で導入）"
        sandbox_ok=0
    fi

    if ! command -v socat &>/dev/null; then
        echo "[警告] socat が見つかりません。サンドボックスが起動できません（wsl/install.sh で導入）"
        sandbox_ok=0
    fi

    case "$(uname -m)" in
        x86_64) seccomp_arch="x64" ;;
        aarch64|arm64) seccomp_arch="arm64" ;;
        *) seccomp_arch="" ;;
    esac

    if [ -z "$seccomp_arch" ]; then
        echo "[スキップ] 未対応のアーキテクチャのためseccompフィルタの確認を省略します"
    else
        seccomp_filter="$HOME/.npm-global/lib/node_modules/@anthropic-ai/sandbox-runtime/vendor/seccomp/$seccomp_arch/apply-seccomp"
        if [ ! -x "$seccomp_filter" ]; then
            echo "[警告] seccompフィルタが見つかりません: $seccomp_filter"
            echo "       フィルタが無いとUnixソケットが遮断されず、WSLでは隔離の外でWindowsバイナリを起動できてしまいます"
            echo "       導入: mise exec node@lts -- npm install -g --prefix ~/.npm-global @anthropic-ai/sandbox-runtime"
            sandbox_ok=0
        fi
    fi

    if [ "$sandbox_ok" = 1 ]; then
        echo "[OK] サンドボックス依存は揃っています"
    fi
fi

echo ""
echo "完了しました。"
