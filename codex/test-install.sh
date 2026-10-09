#!/bin/bash
# codex/install.sh のテスト。
# 仮のリポジトリ（install.sh の複製と仮の config.toml）と、仮の CODEX_HOME で統合の振る舞いを確かめる。
# 最後に、実際の codex/config.toml が公開してよい内容かを確かめる。
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TEST_ROOT=$(mktemp -d)
trap 'rm -rf "$TEST_ROOT"' EXIT
export HOME="$TEST_ROOT/home"
mkdir -p "$HOME"

# codex CLI を見つけさせない（実環境やネットワークに触れないため）
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

# 仮のリポジトリを作る: <dir> <config.toml の内容>
make_repo() {
    mkdir -p "$1"
    cp "$SCRIPT_DIR/install.sh" "$1/install.sh"
    printf '%s\n' "$2" > "$1/config.toml"
}

# 配置する: <CODEX_HOME> <仮のリポジトリ>
run_install() {
    CODEX_HOME="$1" PATH="$SAFE_PATH" bash "$2/install.sh"
}

# 退避の件数: <CODEX_HOME>。退避先がまだ無いときは 0（find の失敗で set -e が止めないようにする）
backup_count() {
    { find "$1/backups/agent-config" -maxdepth 1 -type f 2>/dev/null || true; } | wc -l
}

REPO_CONFIG='model = "gpt-new"
model_reasoning_effort = "medium"

[marketplaces.claude-shared-skills]
source_type = "git"
source = "kuchita-el/claude-shared-skills"

[plugins."dev-workflow@claude-shared-skills"]
enabled = true'

# 実際の Codex の書き方と同じく、端末状態の表が管理部分の表の間に挟まっている
LIVE_CONFIG='model = "gpt-old"
model_reasoning_effort = "medium"
[projects."/work/a"]
trust_level = "trusted"

[marketplaces.claude-shared-skills]
last_updated = "2026-08-09T10:55:14Z"
source_type = "local"
source = "/work/claude-shared-skills"

[plugins."dev-workflow@claude-shared-skills"]
enabled = true

[hooks.state]

[hooks.state."dev-workflow@claude-shared-skills:hooks/hooks.json:session_start:0:0"]
trusted_hash = "sha256:abc"

[tui]
screen_reader_detection_done = true

[tui.model_availability_nux]
"gpt-new" = 1'

REPO="$TEST_ROOT/repo"
make_repo "$REPO" "$REPO_CONFIG"

# 1. 既存の実ファイルを統合する
H1="$TEST_ROOT/case1/.codex"
mkdir -p "$H1"
printf '%s\n' "$LIVE_CONFIG" > "$H1/config.toml"
printf 'untouched state\n' > "$H1/state.db"
run_install "$H1" "$REPO" > "$TEST_ROOT/case1.log"
check "統合後は実ファイルになる" test -f "$H1/config.toml" -a ! -L "$H1/config.toml"
check "管理部分がリポジトリの内容になる" grep -Fqx 'model = "gpt-new"' "$H1/config.toml"
check "古い管理部分が残らない" bash -c '! grep -Fq "gpt-old" "$1"' _ "$H1/config.toml"
check "ローカル参照が残らない" bash -c '! grep -Fq "source_type = \"local\"" "$1"' _ "$H1/config.toml"
check "実行時のキー last_updated が残らない" bash -c '! grep -q "^last_updated" "$1"' _ "$H1/config.toml"
check "trust の表が持ち越される" grep -Fqx '[projects."/work/a"]' "$H1/config.toml"
check "trust の値が持ち越される" grep -Fqx 'trust_level = "trusted"' "$H1/config.toml"
check "フックの承認が持ち越される" grep -Fqx 'trusted_hash = "sha256:abc"' "$H1/config.toml"
check "画面の状態の表が持ち越される" grep -Fqx 'screen_reader_detection_done = true' "$H1/config.toml"
check "画面の状態の下の表が持ち越される" grep -Fqx '[tui.model_availability_nux]' "$H1/config.toml"
check "管理部分が変わったので退避される" test "$(backup_count "$H1")" -eq 1
check "退避したファイルは元の内容と一致する" \
    cmp -s "$(find "$H1/backups/agent-config" -type f -print -quit 2>/dev/null)" <(printf '%s\n' "$LIVE_CONFIG")
check "管理部分の差分を表示する" grep -q '^\[差分\]' "$TEST_ROOT/case1.log"
check "CODEX_HOME の他のファイルに触れない" test "$(cat "$H1/state.db")" = 'untouched state'

# 2. 2回目の実行では何も変わらない
cp "$H1/config.toml" "$TEST_ROOT/case1-first.toml"
run_install "$H1" "$REPO" > /dev/null
check "2回目の実行で内容が変わらない" cmp -s "$H1/config.toml" "$TEST_ROOT/case1-first.toml"
check "2回目の実行で退避が増えない" test "$(backup_count "$H1")" -eq 1

# 3. 管理部分が同じなら、端末状態や last_updated があっても退避しない
H3="$TEST_ROOT/case3/.codex"
mkdir -p "$H3"
printf '%s\n' 'model = "gpt-new"
model_reasoning_effort = "medium"
[projects."/work/b"]
trust_level = "trusted"

[tui]
screen_reader_detection_done = true

[marketplaces.claude-shared-skills]
last_updated = "2026-10-01T00:00:00Z"
source_type = "git"
source = "kuchita-el/claude-shared-skills"

[plugins."dev-workflow@claude-shared-skills"]
enabled = true' > "$H3/config.toml"
run_install "$H3" "$REPO" > "$TEST_ROOT/case3.log"
check "管理部分が同じなら退避しない" test "$(backup_count "$H3")" -eq 0
check "管理部分が同じなら差分を表示しない" bash -c '! grep -q "^\[差分\]" "$1"' _ "$TEST_ROOT/case3.log"
check "管理部分が同じでも trust は持ち越される" grep -Fqx '[projects."/work/b"]' "$H3/config.toml"
check "管理部分が同じでも画面の状態は持ち越される" grep -Fqx '[tui]' "$H3/config.toml"

# 4. 移行前のシンボリックリンクからも統合できる
H4="$TEST_ROOT/case4/.codex"
mkdir -p "$H4" "$TEST_ROOT/old"
printf '%s\n' "$LIVE_CONFIG" > "$TEST_ROOT/old/config.toml"
ln -s "$TEST_ROOT/old/config.toml" "$H4/config.toml"
run_install "$H4" "$REPO" > /dev/null
check "シンボリックリンクは実ファイルに置き換わる" test -f "$H4/config.toml" -a ! -L "$H4/config.toml"
check "リンク先から trust が持ち越される" grep -Fqx '[projects."/work/a"]' "$H4/config.toml"
check "リンク先のファイルは変わらない" cmp -s "$TEST_ROOT/old/config.toml" <(printf '%s\n' "$LIVE_CONFIG")

# 5. リンク先の無いシンボリックリンクは、端末状態なしとして書き出す
H5="$TEST_ROOT/case5/.codex"
mkdir -p "$H5"
ln -s "$TEST_ROOT/missing/config.toml" "$H5/config.toml"
run_install "$H5" "$REPO" > "$TEST_ROOT/case5.log"
check "壊れたリンクは実ファイルに置き換わる" test -f "$H5/config.toml" -a ! -L "$H5/config.toml"
check "壊れたリンクの場合はリポジトリの内容になる" cmp -s "$H5/config.toml" "$REPO/config.toml"
check "壊れたリンクを警告する" grep -q '^\[警告\]' "$TEST_ROOT/case5.log"

# 6. 新規に配置する
H6="$TEST_ROOT/case6/.codex"
run_install "$H6" "$REPO" > /dev/null
check "新規ではリポジトリの内容になる" cmp -s "$H6/config.toml" "$REPO/config.toml"
check "新規では退避しない" test "$(backup_count "$H6")" -eq 0

# 7. 統合した結果が TOML として読めなければ、書き出さない
H7="$TEST_ROOT/case7/.codex"
mkdir -p "$H7"
printf '%s\n' 'model = "gpt-new"
[projects."/work/c"]
trust_level =' > "$H7/config.toml"
cp "$H7/config.toml" "$TEST_ROOT/case7-before.toml"
check "TOML として読めない統合結果では失敗する" \
    bash -c '! CODEX_HOME="$1" PATH="$2" bash "$3/install.sh" >/dev/null 2>&1' _ "$H7" "$SAFE_PATH" "$REPO"
check "TOML として読めないときは既存のファイルを保つ" cmp -s "$H7/config.toml" "$TEST_ROOT/case7-before.toml"
check "TOML として読めないときは退避もしない" test "$(backup_count "$H7")" -eq 0

# 8. リポジトリ側に端末状態の表があれば、配置を拒否する
BAD_REPO="$TEST_ROOT/bad-repo"
make_repo "$BAD_REPO" "$REPO_CONFIG

[projects.\"/work/leak\"]
trust_level = \"trusted\""
H8="$TEST_ROOT/case8/.codex"
mkdir -p "$H8"
printf '%s\n' "$LIVE_CONFIG" > "$H8/config.toml"
check "リポジトリ側に端末状態があれば失敗する" \
    bash -c '! CODEX_HOME="$1" PATH="$2" bash "$3/install.sh" >/dev/null 2>&1' _ "$H8" "$SAFE_PATH" "$BAD_REPO"
check "リポジトリ側に端末状態があるときは既存のファイルを保つ" cmp -s "$H8/config.toml" <(printf '%s\n' "$LIVE_CONFIG")

TUI_REPO="$TEST_ROOT/tui-repo"
make_repo "$TUI_REPO" "$REPO_CONFIG

[tui]
screen_reader_detection_done = true"
H8T="$TEST_ROOT/case8-tui/.codex"
mkdir -p "$H8T"
printf '%s\n' "$LIVE_CONFIG" > "$H8T/config.toml"
check "リポジトリ側に画面の状態の表があれば失敗する" \
    bash -c '! CODEX_HOME="$1" PATH="$2" bash "$3/install.sh" >/dev/null 2>&1' _ "$H8T" "$SAFE_PATH" "$TUI_REPO"
check "リポジトリ側に画面の状態の表があるときは既存のファイルを保つ" cmp -s "$H8T/config.toml" <(printf '%s\n' "$LIVE_CONFIG")

# 9. 実際の codex/config.toml が、公開してよい内容である
REAL="$SCRIPT_DIR/config.toml"
check "実際の config.toml に端末状態の表が無い" bash -c '! grep -Eq "^\[(projects\.|hooks\.state[].]|tui[].])" "$1"' _ "$REAL"
check "実際の config.toml にローカル参照が無い" bash -c '! grep -Eq "source_type[[:space:]]*=[[:space:]]*\"local\"" "$1"' _ "$REAL"
check "実際の config.toml に絶対パスが無い" bash -c '! grep -Eq "\"/(home|mnt|tmp|Users)/" "$1"' _ "$REAL"
check "実際の config.toml に実行時のキーが無い" bash -c '! grep -Eq "^last_updated[[:space:]]*=" "$1"' _ "$REAL"
check "実際の config.toml は TOML として読める" \
    python3 -I -c 'import sys, tomllib; tomllib.load(open(sys.argv[1], "rb"))' "$REAL"

if [ "$failures" -gt 0 ]; then
    printf '%d 件失敗\n' "$failures"
    exit 1
fi
echo "codex installer tests passed"
