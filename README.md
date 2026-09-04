# git-pull-all

指定したディレクトリの直下にある Git リポジトリを一括で最新にする macOS 向けのスクリプト。
チェックアウト中のブランチは切り替えないので、作業中の feature ブランチはそのまま残る。

## 何をするか

対象ディレクトリ直下の各リポジトリで `git fetch --prune` したあと、デフォルトブランチ
（`origin/HEAD` が指すブランチ。`main` とは限らない）を origin の最新に進める。

| リポジトリの状態 | 動作 |
| --- | --- |
| デフォルトブランチ以外をチェックアウト中 | `git fetch origin <default>:<default>` で参照だけ進める。作業ツリーには触れない |
| デフォルトブランチをチェックアウト中・変更なし | fast-forward で merge |
| デフォルトブランチをチェックアウト中・追跡ファイルに変更あり | stash → fast-forward → stash を戻す |
| `git worktree` として作られたディレクトリ | 対象外 |
| origin remote がない / detached HEAD | 対象外 |

fast-forward できないとき（ローカルが独自に進んでいる、履歴が分かれている）は何もせず
`warn` として記録する。マージやリベースは一切しない。

stash を戻すときに衝突した場合は、作業ツリーを merge 前の状態に戻し、変更は stash に
置いたままにする。無人実行で衝突マーカーの残ったファイルを作らないため。この場合は
リポジトリで `git stash pop` を手で実行して解決する。

## 使い方

```sh
./git-pull-all.sh ~/path/to/repos
```

出力は 1 リポジトリ 1 行。

```
=== 2026-01-15 12:00:03  /Users/you/repos
my-app                                       ok   main updated
some-lib                                     ok   main updated (on refactor-parser)
old-tool                                     warn main not fast-forwardable
scratch                                      skip no origin remote
--- ok=2 warn=1 fail=0
```

`fail` が 1 件でもあれば終了コードは 1 になる。

## 毎日自動で実行する

`install.sh` が launchd のジョブ（毎日 12:00）を登録する。

```sh
./install.sh ~/path/to/repos
```

登録されるもの:

- `~/Library/LaunchAgents/local.git-pull-all.plist`
- ログ `~/Library/Logs/git-pull-all.log`（追記される）

時刻を変えるときは `launchd/local.git-pull-all.plist` の `StartCalendarInterval` を
編集してから `install.sh` を実行し直す。

その場で一度動かす:

```sh
launchctl kickstart -p gui/$(id -u)/local.git-pull-all
```

解除する:

```sh
./install.sh --uninstall
```

Mac がスリープしていて実行時刻を過ぎた場合、launchd は復帰後に一度だけ実行する。

## 前提

fetch は認証プロンプトを出さない設定（`GIT_TERMINAL_PROMPT=0`、SSH は `BatchMode=yes`）で
動く。無人実行が入力待ちで止まらないようにするため。SSH 鍵にパスフレーズを設定している
場合は、キーチェーンに登録して ssh-agent から使える状態にしておく。

```sh
ssh-add --apple-use-keychain ~/.ssh/id_ed25519
```

登録されていないと該当リポジトリが `fail fetch failed` になる。
