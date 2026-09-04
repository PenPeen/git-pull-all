#!/usr/bin/env bash
#
# launchd に git-pull-all を毎日 12:00 実行のジョブとして登録する。
# 起動は .app バンドル経由にする。理由は app/runner.c を参照。

set -euo pipefail

readonly LABEL="local.git-pull-all"
readonly APP_NAME="git-pull-all.app"

usage() {
  cat <<'USAGE'
Usage: install.sh <directory>

<directory> を対象に git-pull-all.sh を毎日実行する launchd ジョブを登録する。
起動用の .app を ~/Applications にビルドし、それを launchd から呼ぶ。
既に同名のジョブがあれば入れ替える。

  install.sh --uninstall   ジョブと .app を取り除く
USAGE
}

here=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
app_path="$HOME/Applications/$APP_NAME"
plist_target="$HOME/Library/LaunchAgents/$LABEL.plist"
domain="gui/$(id -u)"

unload_if_loaded() {
  launchctl bootout "$domain/$LABEL" 2>/dev/null || true
}

build_icon() {
  local iconset size
  iconset=$(mktemp -d)/git-pull-all.iconset
  mkdir -p "$iconset"

  for size in 16 32 128 256 512; do
    sips -z "$size" "$size" "$here/assets/icon.png" \
      --out "$iconset/icon_${size}x${size}.png" >/dev/null
    sips -z "$((size * 2))" "$((size * 2))" "$here/assets/icon.png" \
      --out "$iconset/icon_${size}x${size}@2x.png" >/dev/null
  done

  iconutil --convert icns "$iconset" --output "$app_path/Contents/Resources/git-pull-all.icns"
  rm -rf "$(dirname -- "$iconset")"
}

build_app() {
  rm -rf "$app_path"
  mkdir -p "$app_path/Contents/MacOS" "$app_path/Contents/Resources"
  cp "$here/app/Info.plist" "$app_path/Contents/Info.plist"
  xcrun clang -O2 -o "$app_path/Contents/MacOS/git-pull-all" "$here/app/runner.c"
  build_icon
  codesign --force --sign - "$app_path"
}

case ${1:-} in
  --uninstall)
    unload_if_loaded
    rm -f "$plist_target"
    rm -rf "$app_path"
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

mkdir -p "$HOME/Applications" "$HOME/Library/LaunchAgents" "$(dirname -- "$log_path")"

build_app

sed \
  -e "s|__RUNNER__|$app_path/Contents/MacOS/git-pull-all|" \
  -e "s|__SCRIPT__|$here/git-pull-all.sh|" \
  -e "s|__REPOS_DIR__|$repos_dir|" \
  -e "s|__LOG__|$log_path|g" \
  "$here/launchd/$LABEL.plist" > "$plist_target"

unload_if_loaded
launchctl bootstrap "$domain" "$plist_target"

printf 'app:       %s\n' "$app_path"
printf 'installed: %s\n' "$plist_target"
printf 'target:    %s\n' "$repos_dir"
printf 'log:       %s\n' "$log_path"
printf '\n'
printf 'デスクトップ・書類・ダウンロード配下を対象にする場合は、システム設定 >\n'
printf 'プライバシーとセキュリティ > フルディスクアクセス に次を追加する。\n'
printf '  %s\n' "$app_path"
printf '\n'
printf 'run now:   launchctl kickstart -p %s/%s\n' "$domain" "$LABEL"
