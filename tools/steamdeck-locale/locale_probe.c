/* CF7 #46：只读取本进程环境与 libc 的 LC_CTYPE；不启动 Wine，不改变父进程。
 * 输出中的环境值按原始字节 JSON 转义，避免终端编码掩盖异常。
 */
#include <errno.h>
#include <langinfo.h>
#include <locale.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static void json_string(const char *s) {
    const unsigned char *p = (const unsigned char *)s;
    if (!s) { fputs("null", stdout); return; }
    putchar('"');
    for (; *p; ++p) {
        if (*p == '"' || *p == '\\') { putchar('\\'); putchar(*p); }
        else if (*p < 32 || *p >= 127) printf("\\u%04x", (unsigned)*p);
        else putchar(*p);
    }
    putchar('"');
}

static int is_utf8(const char *s) {
    char normalized[24];
    size_t n = 0;
    for (; *s && n + 1 < sizeof(normalized); ++s) {
        unsigned char c = (unsigned char)*s;
        if (c == '-' || c == '_' || c == '.') continue;
        if (c >= 'a' && c <= 'z') c -= 'a' - 'A';
        normalized[n++] = (char)c;
    }
    normalized[n] = 0;
    return strcmp(normalized, "UTF8") == 0;
}

int main(int argc, char **argv) {
    const char *keys[] = {"LANG", "LC_ALL", "LC_CTYPE", "HOST_LC_ALL",
                         "LANGUAGE", "LOCPATH", "PYTHONUTF8", "PYTHONCOERCECLOCALE"};
    const char *stage = "libc-direct";
    const char *selected, *codeset;
    size_t i;
    int saved_errno, rc;
    if (argc == 3 && strcmp(argv[1], "--stage") == 0) stage = argv[2];
    else if (argc != 1) {
        fputs("usage: locale-probe [--stage LABEL]\n", stderr);
        return 2;
    }
    fputs("{\"schema\":\"cf7-locale-probe/v1\",\"scope\":\"native-libc-only\",\"stage\":", stdout);
    json_string(stage);
    fputs(",\"wine_executed\":false,\"environment_bytes\":{", stdout);
    for (i = 0; i < sizeof(keys)/sizeof(keys[0]); ++i) {
        if (i) putchar(',');
        json_string(keys[i]); putchar(':'); json_string(getenv(keys[i]));
    }
    fputs("},\"initial_lc_ctype\":", stdout); json_string(setlocale(LC_CTYPE, NULL));
    errno = 0;
    selected = setlocale(LC_CTYPE, "");
    saved_errno = errno;
    codeset = nl_langinfo(CODESET);
    rc = !selected ? 21 : (is_utf8(codeset) ? 0 : 20);
    fputs(",\"setlocale_ok\":", stdout); fputs(selected ? "true" : "false", stdout);
    fputs(",\"setlocale_result\":", stdout); json_string(selected);
    fputs(",\"libc_codeset\":", stdout); json_string(codeset);
    printf(",\"errno\":%d,\"utf8_ready\":%s,\"exit_code\":%d}\n",
           saved_errno, rc == 0 ? "true" : "false", rc);
    return ferror(stdout) ? 2 : rc;
}
