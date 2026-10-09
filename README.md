# agent-config

Claude Code と Codex の個人設定。

読んで参考にするための資料として公開している。配布物ではなく、他人の環境での動作は保証しない。断片を写して使うのは自由（ライセンスは MIT）。

## 構成

```text
claude/
  settings.json          権限、フック、サンドボックス、プラグインの宣言
  CLAUDE.md              全プロジェクト共通の作業ルール（ユーザースコープ）
  statusline-command.sh  ステータスライン
  hooks/                 フック（dotenv への参照の遮断、ツール呼び出しの記録、圧縮後の動的な文脈の再注入）
  agents/                サブエージェントの定義
  install.sh             ~/.claude/ への配置（git のグローバルな除外設定への追記を含む）
  test-install.sh        install.sh のテスト
  test-block-dotenv.sh   dotenv を遮断するフックのテスト
codex/
  config.toml            Codex の設定（端末状態を除いたもの）
  install.sh             ~/.codex/config.toml への統合
  test-install.sh        install.sh のテスト
docs/
  sandbox.md             settings.json の sandbox 節の理由
```

## 配置の方式

- `claude/` のファイルは、`~/.claude/` へシンボリックリンクで配置する。CLI が `settings.json` を書き換えると、このリポジトリの差分として現れる
- `codex/config.toml` は、`~/.codex/config.toml` へ統合する。Codex は trust やフックの承認、画面の表示状態を設定と同じファイルへ書き込むため、それらは端末側の実ファイルにだけ残し、リポジトリには入れない

## 所有者のセットアップ

```bash
git clone git@github.com:kuchita-el/agent-config.git ~/Development/agent-config
bash ~/Development/agent-config/claude/install.sh
bash ~/Development/agent-config/codex/install.sh
```

### Codex Worktrees

ChatGPTデスクトップアプリのCodex Worktreesは、Gitリポジトリから独立した作業用worktreeを作成します。Worktreeの保存先はアプリの Settings > Worktrees > Worktree root で変更でき、既定では `$CODEX_HOME/worktrees` が使われます。

## 関連リポジトリ

- [claude-shared-skills](https://github.com/kuchita-el/claude-shared-skills): スキル群。Claude Code と Codex の両方が、マーケットプレイスとして参照している

## ライセンス

MIT
