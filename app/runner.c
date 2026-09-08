/*
 * .app バンドルの実行ファイル。
 *
 * launchd から引数付きで呼ばれたときは、受け取った引数をそのまま bash に渡して exec する。
 * launchd からシェルスクリプトを直接起動すると、macOS のアクセス制御 (TCC) は
 * /bin/bash を主体として判定する。/bin/bash は SIP に保護されていてフルディスク
 * アクセスに登録できないため、代わりにこのラッパーを .app として登録できるように
 * する。exec した bash はこのバンドルの権限を引き継ぐ。
 *
 * Finder でダブルクリックされたとき（引数なし）は、登録済みの launchd ジョブを
 * その場で起動する。手動で 1 回更新したいときに使う。
 */

#include <stdio.h>
#include <unistd.h>

#define LABEL "local.git-pull-all"

int main(int argc, char *argv[]) {
  char target[64];

  if (argc < 2 || argv[1][0] == '-') {
    snprintf(target, sizeof target, "gui/%u/" LABEL, getuid());
    execl("/bin/launchctl", "launchctl", "kickstart", "-p", target, (char *)0);
    return 127;
  }

  argv[0] = "/bin/bash";
  execv("/bin/bash", argv);
  return 127;
}
