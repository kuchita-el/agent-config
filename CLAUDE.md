# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

Claude Code と Codex の個人設定を置く公開リポジトリ。所有者の端末では、このリポジトリの clone を出典として `~/.claude/`・`~/.codex/` へ配置する。読んで参考にする資料として公開しており、配布物ではない。

## 公開リポジトリとしての注意

- push した時点で、PR のブランチも含めて公開される。秘匿情報・個人情報・ローカルの絶対パスが無いかの点検は、push 前に手元で済ませる
- `codex/config.toml` に、端末状態（`[projects.*]`、`[hooks.state]`、`[tui]`）とローカル参照のマーケットプレイスを書かない。`bash codex/test-install.sh` が検査する

## 配置

### claude/install.sh

Claude Code の設定ファイルを `~/.claude/` にシンボリックリンクで配置する。

- 冪等に動作（何度実行しても安全）
- `~/.claude/` の外では、git のグローバルな除外設定（`~/.config/git/ignore`）に `**/.claude/settings.local.json` を足す。各プロジェクトの `settings.local.json` をコミットしないため
- 既存ファイルは `~/.claude/backups/agent-config/` にタイムスタンプ付きで退避

```bash
bash claude/install.sh
```

### codex/install.sh

`codex/config.toml` を `~/.codex/config.toml` へ統合する。シンボリックリンクにはしない。

- Codex は trust やフックの承認、画面の表示状態（端末状態）を、設定と同じファイルへ書き込む。リポジトリの内容を土台に、既存の `~/.codex/config.toml` から端末状態の表（`[projects.*]`、`[hooks.state]` とその下の表、`[tui]` とその下の表）だけを持ち越し、それ以外はリポジトリの内容で上書きする
- 管理部分が変わる場合は差分を表示し、`~/.codex/backups/agent-config/` に退避してから書き出す
- 統合の後、`codex/config.toml` に宣言した Git のマーケットプレイスを `codex plugin marketplace upgrade` で取得する。そのマーケットプレイスの、有効にしたプラグインのキャッシュもこれで作られる。Git のマーケットプレイスの外にあるプラグイン（`superpowers@openai-curated` など）は取得しないため、手作業で導入する。取得に失敗しても配置は成功とし、警告を出す
- `codex/config.toml` を変えたら、pull の後に `bash codex/install.sh` を再実行する。pull だけでは反映されない
- Codex の画面操作で管理部分を変えても、リポジトリへは戻らず、次の配置で上書きされる。設定の変更はこのリポジトリで行う

## claude/settings.json の編集運用

Claude Code本体がsettings.jsonを更新する際、JSONを内部構造体経由で再シリアライズするため、フィールドの並び順が本体の定義順にリセットされる（例: `/plugin marketplace add` 実行時の `extraKnownMarketplaces` 追記、`env` 位置の移動）。手書きの順序は保持されない。

- **CLIが書き換えた並び順をそのままコミットする**。一度コミットすれば同一バージョン内で決定論的に安定し、その後は差分が出ない
- 手動編集時は**現在の並びを崩さず追記**する。配列末尾への追加が安全
- `jq --sort-keys` 等での強制正規化は逆効果。CLIが次回起動で再度書き換えて差分が再発する
- `~/.claude/settings.json` がシンボリックリンクから実ファイルに置き換わり、リポジトリ側と乖離していた事例がある（原因未特定）。CLI操作後に差分が出るはずなのに出ない場合は `ls -l ~/.claude/settings.json` でリンク状態を確認し、実ファイル化していたら差分をリポジトリへ取り込んでから `bash claude/install.sh` で張り直す

## プラグインのプロビジョニング

`settings.json` の `extraKnownMarketplaces` / `enabledPlugins` を**単一の出典**とし、`claude/install.sh` がそこから実体配置を導出する。プラグインの増減は `settings.json` の編集だけで完結し、install.sh を触る必要はない。

前提となる本体の挙動（いずれも実測で確認）:

- **宣言済み**のマーケットプレイス・プラグインを `plugin marketplace add` / `plugin install` しても `settings.json` は書き換えられない。書き込みが必要な差分が無いため。逆に**未宣言**のものを扱うとCLIが `extraKnownMarketplaces` / `enabledPlugins` へ追記する。git管理下の `settings.json` に差分を出さないために、扱う対象は必ず先に宣言しておく
- `plugin install` は未cloneのマーケットプレイスからは解決できない（`not found in marketplace` で失敗）。`marketplace add` が前提になる
- マーケットプレイスのリポジトリに同梱されたプラグイン（`source` が `./plugins/...` の相対パス）は宣言だけで有効化されるが、**外部リポジトリを参照するプラグインは明示的な `install` が必要**。例: `superpowers` は公式マーケットプレイスのカタログ上 `source: url` で `github.com/obra/superpowers.git` を sha 固定参照しており、カタログのcloneには実体が含まれない
- `claude-plugins-official` は本体が既定で自動登録するため宣言は不要だが、**あえて宣言している**。初回 `claude` 起動より前に install.sh が公式マーケットプレイスを add する必要があり、未宣言のまま add すると `settings.json` へ追記されてしまうため

## サンドボックス

`claude/settings.json` の `sandbox` 節を変えるときは、`docs/sandbox.md` を読み、一緒に更新する。

## テスト

```bash
bash claude/test-install.sh
bash claude/test-block-dotenv.sh
bash codex/test-install.sh
```

## Key conventions

- UI messages and prompts are in Japanese
