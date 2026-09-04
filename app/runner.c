/*
 * .app バンドルの実行ファイル。受け取った引数をそのまま bash に渡して exec する。
 *
 * launchd からシェルスクリプトを直接起動すると、macOS のアクセス制御 (TCC) は
 * /bin/bash を主体として判定する。/bin/bash は SIP に保護されていてフルディスク
 * アクセスに登録できないため、代わりにこのラッパーを .app として登録できるように
 * する。exec した bash はこのバンドルの権限を引き継ぐ。
 */

#include <unistd.h>

int main(int argc, char *argv[]) {
  (void)argc;
  argv[0] = "/bin/bash";
  execv("/bin/bash", argv);
  return 127;
}
