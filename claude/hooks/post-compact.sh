#!/bin/bash
# PostCompactフック: コンパクション後にプロジェクトの動的コンテキストを再注入する
#
# CLAUDE.mdは自動リロードされるため、ここではgit状態など
# 動的な情報のみをstdoutに出力してコンテキストに注入する。

INPUT=$(cat)

CWD=$(echo "$INPUT" | jq -r '.cwd // empty')
cd "${CWD:-.}" 2>/dev/null || true

echo "=== コンパクション後のプロジェクトコンテキスト ==="

# 現在のブランチ
BRANCH=$(GIT_OPTIONAL_LOCKS=0 git symbolic-ref --short HEAD 2>/dev/null)
if [ -n "$BRANCH" ]; then
    echo ""
    echo "ブランチ: $BRANCH"

    # 直近のコミット
    echo ""
    echo "直近のコミット:"
    GIT_OPTIONAL_LOCKS=0 git log --oneline -5 2>/dev/null

    # 変更中のファイル
    CHANGED=$(GIT_OPTIONAL_LOCKS=0 git diff --name-only 2>/dev/null)
    STAGED=$(GIT_OPTIONAL_LOCKS=0 git diff --cached --name-only 2>/dev/null)
    UNTRACKED=$(GIT_OPTIONAL_LOCKS=0 git ls-files --others --exclude-standard 2>/dev/null)

    if [ -n "$STAGED" ]; then
        echo ""
        echo "ステージ済み:"
        echo "$STAGED" | sed 's/^/  /'
    fi

    if [ -n "$CHANGED" ]; then
        echo ""
        echo "未ステージの変更:"
        echo "$CHANGED" | sed 's/^/  /'
    fi

    if [ -n "$UNTRACKED" ]; then
        echo ""
        echo "未追跡ファイル:"
        echo "$UNTRACKED" | sed 's/^/  /'
    fi
fi

exit 0
