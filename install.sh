#!/usr/bin/env bash
#
# launchd に git-pull-all を毎日 12:00 実行のジョブとして登録する。

set -euo pipefail

readonly LABEL="local.git-pull-all"

usage() {
  cat <<'USAGE'
Usage: install.sh <directory>

<directory> を対象に git-pull-all.sh を毎日実行する launchd ジョブを登録する。
既に同名のジョブがあれば入れ替える。

  install.sh --uninstall   登録を解除する
USAGE
}

here=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
plist_target="$HOME/Library/LaunchAgents/$LABEL.plist"
domain="gui/$(id -u)"

unload_if_loaded() {
  launchctl bootout "$domain/$LABEL" 2>/dev/null || true
}

case ${1:-} in
  --uninstall)
    unload_if_loaded
    rm -f "$plist_target"
    printf 'uninstalled: %s\n' "$LABEL"
    exit 0
    ;;
  "")
    usage >&2
    exit 2
    ;;
  -h | --help)
    usage
    exit 0
    ;;
esac

repos_dir=$(cd -- "$1" && pwd)
log_path="$HOME/Library/Logs/git-pull-all.log"

mkdir -p "$HOME/Library/LaunchAgents" "$(dirname -- "$log_path")"

sed \
  -e "s|__SCRIPT__|$here/git-pull-all.sh|" \
  -e "s|__REPOS_DIR__|$repos_dir|" \
  -e "s|__LOG__|$log_path|g" \
  "$here/launchd/$LABEL.plist" > "$plist_target"

unload_if_loaded
launchctl bootstrap "$domain" "$plist_target"

printf 'installed: %s\n' "$plist_target"
printf 'target:    %s\n' "$repos_dir"
printf 'log:       %s\n' "$log_path"
printf '\nrun now:   launchctl kickstart -p %s/%s\n' "$domain" "$LABEL"
