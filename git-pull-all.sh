#!/usr/bin/env bash
#
# 指定ディレクトリの直下にある各 Git リポジトリのデフォルトブランチを最新にする。
# チェックアウト中のブランチは切り替えないので、作業中のブランチはそのまま残る。

set -uo pipefail

# 認証プロンプトで待ち続けると launchd 上でジョブが終わらなくなる。
export GIT_TERMINAL_PROMPT=0
export GIT_SSH_COMMAND="${GIT_SSH_COMMAND:-ssh -o BatchMode=yes}"

readonly STASH_MESSAGE="git-pull-all: auto stash"

ok_count=0
warn_count=0
fail_count=0

usage() {
  cat <<'USAGE'
Usage: git-pull-all.sh <directory>

<directory> の直下にある各 Git リポジトリで、デフォルトブランチ (origin/HEAD)
を origin の最新に進める。

  - チェックアウト中のブランチがデフォルトブランチ以外なら、作業ツリーには
    一切触れずにデフォルトブランチの参照だけを進める。
  - チェックアウト中がデフォルトブランチなら、追跡ファイルに変更があれば
    stash してから fast-forward し、stash を戻す。
  - git worktree として作られたディレクトリは対象外。
USAGE
}

report() {
  printf '%-44s %-4s %s\n' "$1" "$2" "$3"
}

record_ok() {
  ok_count=$((ok_count + 1))
  report "$1" "ok" "$2"
}

record_warn() {
  warn_count=$((warn_count + 1))
  report "$1" "warn" "$2"
}

record_fail() {
  fail_count=$((fail_count + 1))
  report "$1" "fail" "$2"
}

record_skip() {
  report "$1" "skip" "$2"
}

# origin/HEAD からデフォルトブランチ名を返す。未設定なら origin に問い合わせて設定する。
default_branch() {
  local repo=$1 ref

  ref=$(git -C "$repo" symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>/dev/null)
  if [ -z "$ref" ]; then
    git -C "$repo" remote set-head origin --auto >/dev/null 2>&1
    ref=$(git -C "$repo" symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>/dev/null)
  fi

  [ -n "$ref" ] || return 1
  printf '%s\n' "${ref#origin/}"
}

# チェックアウトしていないデフォルトブランチを、作業ツリーに触れずに進める。
update_detached_branch() {
  local repo=$1 name=$2 branch=$3 current=$4

  if git -C "$repo" fetch --quiet origin "$branch:$branch" 2>/dev/null; then
    record_ok "$name" "$branch updated (on $current)"
  else
    record_warn "$name" "$branch not fast-forwardable (on $current)"
  fi
}

# stash pop が衝突すると作業ツリーに衝突マーカーが残る。無人実行でそれを残すと
# 気づかないまま壊れたファイルを触ることになるので、作業ツリーは戻し、変更は
# stash に置いたままにする。
restore_after_failed_pop() {
  local repo=$1 name=$2 message=$3

  if ! git -C "$repo" stash list | grep -qF "$STASH_MESSAGE"; then
    record_fail "$name" "$message, stash pop failed and the stash entry is gone"
    return
  fi

  git -C "$repo" reset --quiet
  git -C "$repo" checkout --quiet --force -- .
  record_warn "$name" "$message, changes left in stash (pop conflicted)"
}

update_current_branch() {
  local repo=$1 name=$2 branch=$3
  local stashed=0 status message

  if ! git -C "$repo" diff --quiet || ! git -C "$repo" diff --cached --quiet; then
    if git -C "$repo" stash push --quiet --message "$STASH_MESSAGE"; then
      stashed=1
    else
      record_fail "$name" "stash failed"
      return
    fi
  fi

  if git -C "$repo" merge --ff-only --quiet "origin/$branch" 2>/dev/null; then
    status=ok
    message="$branch updated"
  else
    status=warn
    message="$branch not fast-forwardable"
  fi

  if [ "$stashed" -eq 1 ]; then
    if git -C "$repo" stash pop --quiet >/dev/null 2>&1; then
      message="$message, stash restored"
    else
      restore_after_failed_pop "$repo" "$name" "$message"
      return
    fi
  fi

  "record_$status" "$name" "$message"
}

update_repo() {
  local repo=$1
  local name=${repo##*/}
  local branch current

  if ! git -C "$repo" remote get-url origin >/dev/null 2>&1; then
    record_skip "$name" "no origin remote"
    return
  fi

  if ! git -C "$repo" fetch --quiet --prune origin 2>/dev/null; then
    record_fail "$name" "fetch failed"
    return
  fi

  if ! branch=$(default_branch "$repo"); then
    record_skip "$name" "default branch unknown"
    return
  fi

  current=$(git -C "$repo" symbolic-ref --quiet --short HEAD 2>/dev/null)
  if [ -z "$current" ]; then
    record_skip "$name" "detached HEAD"
    return
  fi

  if [ "$current" = "$branch" ]; then
    update_current_branch "$repo" "$name" "$branch"
  else
    update_detached_branch "$repo" "$name" "$branch" "$current"
  fi
}

main() {
  local root=${1:-} repo

  if [ -z "$root" ]; then
    usage >&2
    exit 2
  fi

  if [ ! -d "$root" ]; then
    printf 'not a directory: %s\n' "$root" >&2
    exit 2
  fi

  printf '=== %s  %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$root"

  # worktree の .git はファイルなので -type d で除外される。
  while IFS= read -r repo; do
    update_repo "$repo"
  done < <(find "$root" -mindepth 2 -maxdepth 2 -name .git -type d -exec dirname {} \; | sort)

  printf -- '--- ok=%d warn=%d fail=%d\n' "$ok_count" "$warn_count" "$fail_count"
  [ "$fail_count" -eq 0 ]
}

main "$@"
