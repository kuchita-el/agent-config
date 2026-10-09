# サンドボックス設定の理由

`claude/settings.json` の `sandbox` 節と、それに関わる `permissions.ask` の2件（`Bash(dangerouslyDisableSandbox:true)`、`Bash(docker *)`）が、なぜこの形なのかを説明する。`sandbox` 節を変えるときはこの文書を読み、一緒に更新する。

## 前提

- ローカルの Claude Code は、bubblewrap で Bash コマンドを1つずつ隔離する。既定では、書き込みは作業ディレクトリとセッションの一時ディレクトリに限られ、読み取りはマシン全体に及び、事前に許可する通信先は無い
- クラウドのセッション（`claude --cloud`、デスクトップアプリ）は VM で隔離され、ユーザースコープの `~/.claude/settings.json` を読まない
- WSL2 では、Windows のプログラム（`/mnt/c/` 配下、`*.exe`）の起動が、Unix ソケット経由で Windows 側へ委ねられる。このソケットを遮断するのは任意の依存である seccomp フィルタで、無ければ Unix ソケットは遮断されない
- 所有者の端末では、git の署名（1Password）と SSH が Windows 側のプログラムを使う
- `permissions.defaultMode` は `auto`。未許可の通信先と、サンドボックス外での再試行は、分類器が審査する
- permissions の `Read` の deny ルールは、サンドボックスの `denyRead` に合算される

## 置き場所

サンドボックスの設定は、ユーザースコープ（`claude/settings.json`）に置く。サンドボックスはローカル専用で、クラウドでは VM の隔離が同等の脅威に対処している。プロジェクト固有の許可ドメインや書き込み先は、各プロジェクトの `.claude/settings.local.json`（コミットしない）に置く。

## 署名と SSH を伴う git 操作（`excludedCommands`）

署名や SSH 通信を伴う git のサブコマンドは、`excludedCommands` に入れてサンドボックスの外で実行する。permissions の allow / ask は、外で実行するコマンドにも効く。

- `allowAllUnixSockets: true` にはしない。サンドボックス内から任意の Windows のプログラム（`cmd.exe`、`powershell.exe`）を起動でき、実質的に隔離を抜けられる
- 署名を Linux 側へ移さない。鍵ファイルならサンドボックス内から秘密鍵が読め、ssh-agent ならソケットの許可に `allowAllUnixSockets` が要る。1Password の承認付き署名という利点も失う
- `excludedCommands` は、単独の形のコマンドにだけ一致する。`cd x && git commit ...` や `git -C x commit ...` はサンドボックス内で走り、署名に失敗する（安全側の失敗）。そのため `claude/CLAUDE.md` に、除外対象の git コマンドは単独で実行する規則を置いている。除外のパターンを前置き付き（`* && git commit *` など）に広げると、任意のコマンドを前置きして隔離の外で走らせられるため、広げない

## 通信先（`network.allowedDomains`）

全プロジェクトが必要とする GitHub の4つ（`github.com`、`api.github.com`、`*.githubusercontent.com`、`codeload.github.com`）だけを入れる。それ以外は、auto モードの分類器が審査する。

- `uploads.github.com` は書き込みの経路になるため入れない
- 言語やツールのレジストリ（npm、PyPI など）は、使うプロジェクトの `.claude/settings.local.json` に入れる
- `strictAllowlist` は使わない。新しい通信先が要るたびにコマンドが失敗し、この設定の編集が要る

## サンドボックス外での再試行（`permissions.ask` の `Bash(dangerouslyDisableSandbox:true)`）

再試行そのものは許す（`allowUnsandboxedCommands` は既定の `true`）。ただし ask ルールで、毎回本人に確認させる。分類器の判定に任せると、プロンプトインジェクションで「サンドボックスの外で実行しろ」と誘導されたときに通りうる。再試行を禁じると、失敗のたびに手で実行する必要がある。

## 秘密情報の読み取り拒否（`credentials.files`）

`~/.ssh`、`~/.aws`、`~/.azure`、`~/.docker/config.json`、`~/.claude/.credentials.json` を読めなくする。

- 拒否の対象がシンボリックリンクだと、サンドボックスがどのコマンドも起動できなくなる（`bwrap: Can't mount tmpfs on /newroot/...`）。対象は、実体のディレクトリかファイルにするか、存在しない状態にしておく。存在しないパスは起動を妨げない
- dotenv ファイルは、permissions の `Read` の deny ルールが `denyRead` に合算されることで拒否される。合算で拒否されるのは、作業ディレクトリ配下に限られる。`sandbox.filesystem.denyRead` へワイルドカードで追記すると、Linux ではコマンドのたびに実在ファイルを走査して展開するため、`~/Development/**/` 程度でも Bash 1回あたり数秒の遅延になる。守りたいのは作業中のプロジェクトの秘密の持ち出しで、これは既存のルールで塞がる。他のプロジェクトの dotenv を読みに行く挙動は、dotenv を遮断するフック（`claude/hooks/block-dotenv.sh`）と分類器で防ぐ
- gh のトークンは読めるままにし、トークンの権限を絞る。拒否しても、サンドボックス内の gh がトークンを使える限り `gh api` 経由の書き込みは防げず、防げるのは窃取だけである。窃取されたときの被害はトークンの権限で決まるため、SSH 鍵の追加（`admin:public_key`）のような、永続的な侵入につながる権限を外しておく

## 起動できないとき（`failIfUnavailable`）

`true` にする。依存が欠けていれば Claude Code の起動を失敗させ、隔離なしで黙って走る事態を防ぐ。その環境だけ一時的に外すときは、`claude --settings` で上書きする。

socat が欠けると、エラーメッセージを出さずに、ログイン直後に終了したように見える。起動が理由なく落ちるときは、`claude/install.sh` を実行して依存の警告を確かめる。seccomp フィルタは任意の依存のため、欠けても `failIfUnavailable` では拾えない。これも `claude/install.sh` が有無を確かめて警告する。

## docker（`excludedCommands` と `permissions.ask` の `Bash(docker *)`）

`docker *` はサンドボックスの外で実行し、ask ルールで毎回確認させる。docker を使えることは、ホストの root 権限に等しいため、本人の承認を必須にする。

Linux のサンドボックスはネットワーク名前空間を切り、外への通信をホスト側のプロキシ経由に限る。そのため、compose がホストに公開した localhost のポートへは、サンドボックス内のコマンドから直接つながらない。DB につなぐコマンドは、そのプロジェクトの `.claude/settings.local.json` で `excludedCommands` に入れる。
