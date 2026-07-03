// ============================================================
// CF7:FlashNight Bootstrap Wrapper
// 用户面入口 — 文件名是 CRAZYFLASHER7MercenaryEmpire.exe，本身不依赖 .NET runtime
//
// 工作流：
//   1. 写一行 boot start 到 logs\bootstrap.log（即便 runtime 缺失也有 trace）
//   2. 检测 .NET 10 Desktop Runtime 是否在 %ProgramFiles%\dotnet\shared\
//      Microsoft.WindowsDesktop.App\10.x 下
//   3. 若缺失：弹 MessageBox 询问，用户同意后 ShellExecute "runas" 跑
//      tools\dotnet-runtime\windowsdesktop-runtime-10.0.x-win-x64.exe
//      /install /passive /norestart（UAC 一次性提示）
//   4. 等 installer 退出 + 二次确认 runtime 已就位
//   5. ShellExecute runtime\CRAZYFLASHER7MercenaryEmpire.Core.exe（FDD apphost）
//      用 --project-root "<bootstrap 所在目录绝对路径>" 显式把 projectRoot 传给 Core
//      （Core 在子目录，AppContext.BaseDirectory ≠ projectRoot；不传 Core 会 fallback walk-up）
//   6. bootstrap 自身立刻退出
//
// 设计原则：纯 Win32 + CRT（静态链接 /MT），零 STL，单文件 ~150KB；能在裸 Windows 跑
// 日志原则：每次启动 append；> LOG_ROTATE_BYTES 时滚动一次到 .old（保留前一份诊断）
// ============================================================

#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <shellapi.h>
#include <shlobj.h>
#include <strsafe.h>
#include <stdio.h>
#include <stdlib.h>
#include <share.h>
#include <time.h>

#pragma comment(lib, "shell32.lib")
#pragma comment(lib, "user32.lib")
#pragma comment(lib, "kernel32.lib")

static const wchar_t* TITLE = L"CF7:FlashNight";
// installer 用 glob 扫 windowsdesktop-runtime-10.*-win-x64.exe（10.0.8 / 10.0.9 / 10.1.x ...），
// 版本 bump 无需改源码 + 同步 4 处脚本
//
// 版本策略 — bootstrap 是「下限把关」，Core 的 runtimeconfig 是「上限放行」：
//   - bootstrap 只接受 10.* 目录（拒绝裸 .NET 11+ 机器，会触发 bundled 10.0.8 安装）
//   - 但 Core 的 runtimeconfig.json 设了 RollForward=LatestMajor + csproj 同步
//     → 一旦机器装了 10.x，未来升 11.x 而不卸 10.x 仍能跑（Core 自己 roll-forward）
//   - 副作用：用户裸 .NET 11 机器明明 Core 能跑，bootstrap 还是会装 10.0.8。
//     这是有意的——bootstrap 是首装入口，确保 ship 的 runtime 上限是已测过的版本。
//
// 不校验最小 patch（10.0.0 也算 hit）：当前 .NET 10 仅有 servicing patch（无 breaking），
// 不存在「需要 10.0.5+」的场景。未来真要卡 min patch 时在 ScanOneDotnetRoot 内做版本字符串比较。
static const wchar_t* RUNTIME_INSTALLER_DIR_REL = L"\\tools\\dotnet-runtime";
static const wchar_t* RUNTIME_INSTALLER_GLOB = L"\\tools\\dotnet-runtime\\windowsdesktop-runtime-10.*-win-x64.exe";
static const wchar_t* CORE_EXE_REL = L"\\runtime\\CRAZYFLASHER7MercenaryEmpire.Core.exe";
static const wchar_t* LOG_DIR_REL = L"\\logs";
static const wchar_t* LOG_FILE_REL = L"\\logs\\bootstrap.log";
static const wchar_t* LOG_FILE_OLD_REL = L"\\logs\\bootstrap.log.old";
static const DWORD CORE_EARLY_EXIT_GRACE_MS = 5000;
// 滚动阈值：10MB。bootstrap 每次启动 ~10 行 ~1KB，理论可记 10 万次启动；
// 不希望诊断文件无限增长，> 10MB 时滚一次（保留 .old 一份做事后复盘）
static const long LOG_ROTATE_BYTES = 10L * 1024L * 1024L;

// ---- 工具：获取 bootstrap 自身所在目录（不含末尾反斜杠） ----
static bool GetExeDir(wchar_t* out, size_t cch)
{
    if (GetModuleFileNameW(NULL, out, (DWORD)cch) == 0) return false;
    for (size_t i = wcslen(out); i > 0; --i) {
        if (out[i - 1] == L'\\' || out[i - 1] == L'/') {
            out[i - 1] = L'\0';
            return true;
        }
    }
    return false;
}

// ---- 日志：append 一行到 logs\bootstrap.log，带时间戳 ----
// 即便文件写失败也吞，不影响主流程；这是诊断辅助不是关键路径
static FILE* g_logFp = NULL;
static wchar_t g_logPath[MAX_PATH] = { 0 };
static DWORD g_lastCoreLaunchError = 0;

static void LogOpen(const wchar_t* exeDir)
{
    // 确保 logs 目录存在
    wchar_t logDir[MAX_PATH];
    if (FAILED(StringCchCopyW(logDir, MAX_PATH, exeDir))) return;
    if (FAILED(StringCchCatW(logDir, MAX_PATH, LOG_DIR_REL))) return;
    CreateDirectoryW(logDir, NULL);  // 已存在返回 ERROR_ALREADY_EXISTS，忽略

    if (FAILED(StringCchCopyW(g_logPath, MAX_PATH, exeDir))) return;
    if (FAILED(StringCchCatW(g_logPath, MAX_PATH, LOG_FILE_REL))) return;

    // 滚动：当前 log > LOG_ROTATE_BYTES → 当前重命名为 .old，新启动写空文件
    // 不依赖额外库，用 GetFileSizeEx + MoveFileEx；MOVEFILE_REPLACE_EXISTING 自动覆盖旧 .old，
    // 无需 DeleteFileW 预删（少一步 syscall，并缩小双实例同时启动的竞态窗口）
    HANDLE hFile = CreateFileW(g_logPath, FILE_READ_ATTRIBUTES,
                                FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE,
                                NULL, OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, NULL);
    if (hFile != INVALID_HANDLE_VALUE) {
        LARGE_INTEGER size;
        BOOL gotSize = GetFileSizeEx(hFile, &size);
        CloseHandle(hFile);
        if (gotSize && size.QuadPart > LOG_ROTATE_BYTES) {
            wchar_t oldPath[MAX_PATH];
            if (SUCCEEDED(StringCchCopyW(oldPath, MAX_PATH, exeDir)) &&
                SUCCEEDED(StringCchCatW(oldPath, MAX_PATH, LOG_FILE_OLD_REL))) {
                MoveFileExW(g_logPath, oldPath, MOVEFILE_REPLACE_EXISTING);
            }
        }
    }

    // append 模式打开，二进制（自己控制换行）；UTF-8 编码
    g_logFp = _wfsopen(g_logPath, L"ab", _SH_DENYNO);
    if (g_logFp == NULL) {
        g_logFp = NULL;
        return;
    }

    // 文件起始没 BOM 的话不补；append 模式不动文件头
}

static void Log(const char* level, const wchar_t* msg)
{
    if (g_logFp == NULL) return;

    SYSTEMTIME st;
    GetLocalTime(&st);

    // 把 wide msg 转 UTF-8 写入
    int u8Len = WideCharToMultiByte(CP_UTF8, 0, msg, -1, NULL, 0, NULL, NULL);
    if (u8Len <= 0) return;
    char* u8Buf = (char*)malloc((size_t)u8Len);
    if (u8Buf == NULL) return;
    WideCharToMultiByte(CP_UTF8, 0, msg, -1, u8Buf, u8Len, NULL, NULL);

    fprintf(g_logFp,
            "[%04d-%02d-%02d %02d:%02d:%02d.%03d] [bootstrap] [%s] %s\n",
            st.wYear, st.wMonth, st.wDay,
            st.wHour, st.wMinute, st.wSecond, st.wMilliseconds,
            level, u8Buf);
    fflush(g_logFp);

    free(u8Buf);
}

static void Logf(const char* level, const wchar_t* fmt, ...)
{
    wchar_t buf[2048];
    va_list ap;
    va_start(ap, fmt);
    StringCchVPrintfW(buf, 2048, fmt, ap);
    va_end(ap);
    Log(level, buf);
}

static void LogClose()
{
    if (g_logFp != NULL) {
        fclose(g_logFp);
        g_logFp = NULL;
    }
}

static void OpenLogsFolder()
{
    if (g_logPath[0] == L'\0') return;

    wchar_t logsDir[MAX_PATH];
    if (FAILED(StringCchCopyW(logsDir, MAX_PATH, g_logPath))) return;
    for (size_t i = wcslen(logsDir); i > 0; --i) {
        if (logsDir[i - 1] == L'\\' || logsDir[i - 1] == L'/') {
            logsDir[i - 1] = L'\0';
            break;
        }
    }
    if (logsDir[0] == L'\0') return;
    ShellExecuteW(NULL, L"open", L"explorer.exe", logsDir, NULL, SW_SHOWNORMAL);
}

static void ShowNativeDiagnosticDialog(const wchar_t* code, const wchar_t* msg, const wchar_t* advice)
{
    wchar_t text[4096];
    const wchar_t* safeCode = (code && code[0]) ? code : L"CF7-BOOT-UNKNOWN";
    const wchar_t* safeMsg = (msg && msg[0]) ? msg : L"引导器启动失败。";
    const wchar_t* safeAdvice = (advice && advice[0]) ? advice : L"请重试一次；如果问题持续存在，请把日志发给开发组。";
    const wchar_t* safeLogPath = (g_logPath[0]) ? g_logPath : L"(日志尚未创建)";

    StringCchPrintfW(text, 4096,
        L"游戏启动失败。\n\n"
        L"错误码：%s\n\n"
        L"%s\n\n"
        L"建议操作：\n%s\n\n"
        L"日志位置：\n%s\n\n"
        L"点击「是」打开日志文件夹，点击「否」关闭。",
        safeCode, safeMsg, safeAdvice, safeLogPath);

    int choice = MessageBoxW(NULL, text, TITLE, MB_YESNO | MB_ICONERROR);
    if (choice == IDYES) {
        OpenLogsFolder();
    }
}

static bool BuildRootPath(const wchar_t* exeDir, const wchar_t* rel, wchar_t* out, size_t cch)
{
    if (FAILED(StringCchCopyW(out, cch, exeDir))) return false;
    if (FAILED(StringCchCatW(out, cch, rel))) return false;
    return true;
}

static void FormatFileTimeLocal(const FILETIME* ft, wchar_t* out, size_t cch)
{
    if (out == NULL || cch == 0) return;
    out[0] = L'\0';
    if (ft == NULL) return;

    FILETIME localFt;
    SYSTEMTIME st;
    if (!FileTimeToLocalFileTime(ft, &localFt)) return;
    if (!FileTimeToSystemTime(&localFt, &st)) return;
    StringCchPrintfW(out, cch, L"%04d-%02d-%02d %02d:%02d:%02d",
        st.wYear, st.wMonth, st.wDay, st.wHour, st.wMinute, st.wSecond);
}

static bool LogPathProbe(const wchar_t* label, const wchar_t* path, bool required)
{
    WIN32_FILE_ATTRIBUTE_DATA fad;
    if (!GetFileAttributesExW(path, GetFileExInfoStandard, &fad)) {
        DWORD err = GetLastError();
        Logf(required ? "ERROR" : "WARN",
            L"[preflight] %s missing path=%s GetLastError=%lu", label, path, err);
        return false;
    }

    if (fad.dwFileAttributes & FILE_ATTRIBUTE_DIRECTORY) {
        Logf("INFO", L"[preflight] %s directory ok path=%s", label, path);
        return true;
    }

    ULONGLONG size = (((ULONGLONG)fad.nFileSizeHigh) << 32) | fad.nFileSizeLow;
    wchar_t mtime[64];
    FormatFileTimeLocal(&fad.ftLastWriteTime, mtime, 64);
    Logf("INFO", L"[preflight] %s file ok size=%llu mtime=%s path=%s",
        label, size, mtime, path);
    return true;
}

static bool LogRelativePathProbe(const wchar_t* exeDir, const wchar_t* label, const wchar_t* rel, bool required)
{
    wchar_t path[MAX_PATH];
    if (!BuildRootPath(exeDir, rel, path, MAX_PATH)) {
        Logf(required ? "ERROR" : "WARN", L"[preflight] %s path overflow rel=%s", label, rel);
        return false;
    }
    return LogPathProbe(label, path, required);
}

static void LogRuntimeInventory(const wchar_t* exeDir)
{
    wchar_t pattern[MAX_PATH];
    if (!BuildRootPath(exeDir, L"\\runtime\\*", pattern, MAX_PATH)) {
        Log("ERROR", L"[preflight] runtime inventory path overflow");
        return;
    }

    WIN32_FIND_DATAW fd;
    HANDLE h = FindFirstFileW(pattern, &fd);
    if (h == INVALID_HANDLE_VALUE) {
        Logf("ERROR", L"[preflight] runtime directory unreadable pattern=%s GetLastError=%lu",
            pattern, GetLastError());
        return;
    }

    int count = 0;
    do {
        if (fd.cFileName[0] == L'.') continue;
        count++;
        if (fd.dwFileAttributes & FILE_ATTRIBUTE_DIRECTORY) {
            Logf("INFO", L"[preflight] runtime entry dir name=%s", fd.cFileName);
        } else {
            ULONGLONG size = (((ULONGLONG)fd.nFileSizeHigh) << 32) | fd.nFileSizeLow;
            Logf("INFO", L"[preflight] runtime entry file name=%s size=%llu",
                fd.cFileName, size);
        }
    } while (FindNextFileW(h, &fd));
    FindClose(h);
    Logf("INFO", L"[preflight] runtime inventory complete count=%d", count);
}

static bool PreflightCriticalFiles(const wchar_t* exeDir)
{
    bool ok = true;

    ok = LogRelativePathProbe(exeDir, L"Core apphost", L"\\runtime\\CRAZYFLASHER7MercenaryEmpire.Core.exe", true) && ok;
    ok = LogRelativePathProbe(exeDir, L"Core assembly", L"\\runtime\\CRAZYFLASHER7MercenaryEmpire.Core.dll", true) && ok;
    ok = LogRelativePathProbe(exeDir, L"Core deps", L"\\runtime\\CRAZYFLASHER7MercenaryEmpire.Core.deps.json", true) && ok;
    ok = LogRelativePathProbe(exeDir, L"Core runtimeconfig", L"\\runtime\\CRAZYFLASHER7MercenaryEmpire.Core.runtimeconfig.json", true) && ok;
    ok = LogRelativePathProbe(exeDir, L"WebView2 loader", L"\\runtime\\WebView2Loader.dll", true) && ok;
    ok = LogRelativePathProbe(exeDir, L"WebView2 managed", L"\\runtime\\Microsoft.Web.WebView2.Core.dll", true) && ok;
    ok = LogRelativePathProbe(exeDir, L"ClearScript V8 native", L"\\runtime\\ClearScriptV8.win-x64.dll", true) && ok;
    ok = LogRelativePathProbe(exeDir, L"miniaudio sidecar", L"\\runtime\\miniaudio.dll", true) && ok;
    ok = LogRelativePathProbe(exeDir, L"sol_parser sidecar", L"\\runtime\\sol_parser.dll", true) && ok;
    ok = LogRelativePathProbe(exeDir, L"Flash Player", L"\\Adobe Flash Player 20.exe", true) && ok;
    ok = LogRelativePathProbe(exeDir, L"Game SWF", L"\\CRAZYFLASHER7MercenaryEmpire.swf", true) && ok;
    ok = LogRelativePathProbe(exeDir, L"bootstrap HTML", L"\\launcher\\web\\bootstrap.html", true) && ok;
    ok = LogRelativePathProbe(exeDir, L"crossdomain policy", L"\\crossdomain.xml", true) && ok;

    LogRelativePathProbe(exeDir, L"config.toml", L"\\config.toml", false);
    LogRelativePathProbe(exeDir, L"hotkey guard", L"\\hotkey_guard.exe", false);
    LogRuntimeInventory(exeDir);
    Logf(ok ? "INFO" : "ERROR", L"[preflight] critical file check %s", ok ? L"OK" : L"FAILED");
    return ok;
}

// ---- 扫一个 dotnet 安装根（e.g. C:\Program Files\dotnet 或 %LOCALAPPDATA%\Microsoft\dotnet） ----
// 返回 true 时 foundVersionOut 填版本名（如 "10.0.8"）
static bool ScanOneDotnetRoot(const wchar_t* dotnetRoot, wchar_t* foundVersionOut, size_t foundVersionCch)
{
    if (dotnetRoot == NULL || dotnetRoot[0] == L'\0') return false;

    wchar_t sharedDir[MAX_PATH];
    if (FAILED(StringCchCopyW(sharedDir, MAX_PATH, dotnetRoot))) return false;
    if (FAILED(StringCchCatW(sharedDir, MAX_PATH, L"\\shared\\Microsoft.WindowsDesktop.App"))) return false;

    wchar_t searchPattern[MAX_PATH];
    if (FAILED(StringCchCopyW(searchPattern, MAX_PATH, sharedDir))) return false;
    if (FAILED(StringCchCatW(searchPattern, MAX_PATH, L"\\10.*"))) return false;

    Logf("INFO", L"scanning runtime: %s", searchPattern);

    WIN32_FIND_DATAW fd;
    HANDLE h = FindFirstFileW(searchPattern, &fd);
    if (h == INVALID_HANDLE_VALUE) return false;

    bool found = false;
    do {
        if ((fd.dwFileAttributes & FILE_ATTRIBUTE_DIRECTORY) == 0) continue;
        if (fd.cFileName[0] == L'.') continue;

        wchar_t depsPath[MAX_PATH];
        if (FAILED(StringCchCopyW(depsPath, MAX_PATH, sharedDir))) continue;
        if (FAILED(StringCchCatW(depsPath, MAX_PATH, L"\\"))) continue;
        if (FAILED(StringCchCatW(depsPath, MAX_PATH, fd.cFileName))) continue;
        if (FAILED(StringCchCatW(depsPath, MAX_PATH, L"\\Microsoft.WindowsDesktop.App.deps.json"))) continue;

        DWORD attr = GetFileAttributesW(depsPath);
        if (attr != INVALID_FILE_ATTRIBUTES && (attr & FILE_ATTRIBUTE_DIRECTORY) == 0) {
            if (foundVersionOut && foundVersionCch > 0) {
                StringCchCopyW(foundVersionOut, foundVersionCch, fd.cFileName);
            }
            found = true;
            break;
        }
        Logf("WARN", L"runtime candidate %s missing deps.json; skipping", fd.cFileName);
    } while (FindNextFileW(h, &fd));

    FindClose(h);
    return found;
}

// ---- 多位置检查 .NET 10 桌面运行时 ----
// 按 .NET host 实际查找顺序检查：
//   1. %DOTNET_ROOT_X64% / %DOTNET_ROOT% (env override)
//   2. %ProgramFiles%\dotnet (默认 system-wide)
//   3. %LOCALAPPDATA%\Microsoft\dotnet (dotnet-install.ps1 默认 user-scope)
//   4. %USERPROFILE%\.dotnet (legacy user-scope)
// 找到任一即视为已装；如果命中非默认位置（#1 #3 #4），foundRootOut 返回该 dotnet 根目录，
// 调用方需 SetEnvironmentVariable("DOTNET_ROOT_X64"/"DOTNET_ROOT", root) 让 Core 的 apphost
// 找得到 runtime（apphost 默认只搜 %ProgramFiles%\dotnet）
static bool IsRuntimeInstalled(wchar_t* foundVersionOut, size_t foundVersionCch,
                                wchar_t* foundRootOut, size_t foundRootCch,
                                bool* needSetEnvOut)
{
    if (foundVersionOut && foundVersionCch > 0) foundVersionOut[0] = L'\0';
    if (foundRootOut && foundRootCch > 0) foundRootOut[0] = L'\0';
    if (needSetEnvOut) *needSetEnvOut = false;

    wchar_t candidate[MAX_PATH];

    // 1. DOTNET_ROOT_X64 优先（apphost 自己读这个）
    DWORD got = GetEnvironmentVariableW(L"DOTNET_ROOT_X64", candidate, MAX_PATH);
    if (got > 0 && got < MAX_PATH) {
        Logf("INFO", L"env DOTNET_ROOT_X64 = %s", candidate);
        if (ScanOneDotnetRoot(candidate, foundVersionOut, foundVersionCch)) {
            Logf("INFO", L"runtime detected: %s @ DOTNET_ROOT_X64 (%s)", foundVersionOut, candidate);
            if (foundRootOut) StringCchCopyW(foundRootOut, foundRootCch, candidate);
            // env 已经设了，apphost 会读，无需重设
            return true;
        }
    }

    // 2. DOTNET_ROOT
    got = GetEnvironmentVariableW(L"DOTNET_ROOT", candidate, MAX_PATH);
    if (got > 0 && got < MAX_PATH) {
        Logf("INFO", L"env DOTNET_ROOT = %s", candidate);
        if (ScanOneDotnetRoot(candidate, foundVersionOut, foundVersionCch)) {
            Logf("INFO", L"runtime detected: %s @ DOTNET_ROOT (%s)", foundVersionOut, candidate);
            if (foundRootOut) StringCchCopyW(foundRootOut, foundRootCch, candidate);
            return true;
        }
    }

    // 3. %ProgramFiles%\dotnet (apphost 默认 system 路径)
    wchar_t programFiles[MAX_PATH];
    if (SUCCEEDED(SHGetFolderPathW(NULL, CSIDL_PROGRAM_FILES, NULL, 0, programFiles))) {
        if (FAILED(StringCchCopyW(candidate, MAX_PATH, programFiles))) return false;
        if (FAILED(StringCchCatW(candidate, MAX_PATH, L"\\dotnet"))) return false;
        if (ScanOneDotnetRoot(candidate, foundVersionOut, foundVersionCch)) {
            Logf("INFO", L"runtime detected: %s @ %s (system default)", foundVersionOut, candidate);
            if (foundRootOut) StringCchCopyW(foundRootOut, foundRootCch, candidate);
            // apphost 默认会找这里，无需设 env
            return true;
        }
    }

    // 4. %LOCALAPPDATA%\Microsoft\dotnet (dotnet-install.ps1 默认 user-scope)
    if (SUCCEEDED(SHGetFolderPathW(NULL, CSIDL_LOCAL_APPDATA, NULL, 0, programFiles))) {
        if (FAILED(StringCchCopyW(candidate, MAX_PATH, programFiles))) return false;
        if (FAILED(StringCchCatW(candidate, MAX_PATH, L"\\Microsoft\\dotnet"))) return false;
        if (ScanOneDotnetRoot(candidate, foundVersionOut, foundVersionCch)) {
            Logf("INFO", L"runtime detected: %s @ %s (user-scope %%LOCALAPPDATA%%)", foundVersionOut, candidate);
            if (foundRootOut) StringCchCopyW(foundRootOut, foundRootCch, candidate);
            if (needSetEnvOut) *needSetEnvOut = true;  // 非默认位置，需要给 Core 设 env
            return true;
        }
    }

    // 5. %USERPROFILE%\.dotnet (legacy user-scope)
    if (SUCCEEDED(SHGetFolderPathW(NULL, CSIDL_PROFILE, NULL, 0, programFiles))) {
        if (FAILED(StringCchCopyW(candidate, MAX_PATH, programFiles))) return false;
        if (FAILED(StringCchCatW(candidate, MAX_PATH, L"\\.dotnet"))) return false;
        if (ScanOneDotnetRoot(candidate, foundVersionOut, foundVersionCch)) {
            Logf("INFO", L"runtime detected: %s @ %s (legacy %%USERPROFILE%%\\.dotnet)", foundVersionOut, candidate);
            if (foundRootOut) StringCchCopyW(foundRootOut, foundRootCch, candidate);
            if (needSetEnvOut) *needSetEnvOut = true;
            return true;
        }
    }

    Log("INFO", L"runtime scan: no valid 10.x runtime found in any known location");
    return false;
}

// ---- 弹自诊断错误框 + 返回（含日志） ----
static int FatalExit(const wchar_t* code, const wchar_t* msg, const wchar_t* advice)
{
    Logf("ERROR", L"FatalExit code=%s message=%s", code ? code : L"(null)", msg ? msg : L"(null)");
    LogClose();
    ShowNativeDiagnosticDialog(code, msg, advice);
    return 1;
}

// ---- 同步跑 installer（"runas" 触发 UAC，等其退出） ----
// 返回 installer 的退出码；-2 = 用户拒绝 UAC；-(系统错误码) = 启动失败
static int RunInstaller(const wchar_t* installerPath)
{
    Logf("INFO", L"launching installer (runas): %s", installerPath);

    SHELLEXECUTEINFOW sei = { 0 };
    sei.cbSize = sizeof(sei);
    sei.fMask = SEE_MASK_NOCLOSEPROCESS | SEE_MASK_NOASYNC;
    sei.lpVerb = L"runas";
    sei.lpFile = installerPath;
    sei.lpParameters = L"/install /passive /norestart";
    sei.nShow = SW_SHOW;

    if (!ShellExecuteExW(&sei)) {
        DWORD err = GetLastError();
        if (err == ERROR_CANCELLED) {
            Log("WARN", L"installer launch cancelled (user denied UAC)");
            return -2;
        }
        Logf("ERROR", L"installer launch failed (GetLastError=%lu)", err);
        return -((int)err);
    }

    if (sei.hProcess == NULL) {
        Log("WARN", L"installer reused existing process; cannot wait");
        return 0;
    }

    Log("INFO", L"installer started, waiting...");
    WaitForSingleObject(sei.hProcess, INFINITE);
    DWORD exitCode = 0;
    GetExitCodeProcess(sei.hProcess, &exitCode);
    CloseHandle(sei.hProcess);
    Logf("INFO", L"installer exited (code=%lu)", exitCode);
    return (int)exitCode;
}

// ---- 启动 Core apphost ----
// 传递: --project-root "<exeDir 绝对路径>" + 原始命令行参数
static bool LaunchCore(const wchar_t* exeDir, const wchar_t* corePath, LPWSTR origCmdLine)
{
    g_lastCoreLaunchError = 0;
    // 构造 args: --project-root "<exeDir>" <origCmdLine>
    // NTFS 路径分量禁止 `"`（连同 < > : / \ | ? * 都是保留字符），
    // 所以 GetModuleFileNameW 拿到的 exeDir 永远不含 "，下方裸 quote 拼接安全。
    // 若极端情况下真出现（例如 GetModuleFileNameW 被劫持），写日志后拒绝启动避免误解析。
    if (wcschr(exeDir, L'"') != NULL) {
        Logf("ERROR", L"exeDir contains '\"' which NTFS prohibits — refusing to launch: %s", exeDir);
        return false;
    }
    wchar_t args[4096];
    if (origCmdLine && origCmdLine[0] != L'\0') {
        StringCchPrintfW(args, 4096, L"--project-root \"%s\" %s", exeDir, origCmdLine);
    } else {
        StringCchPrintfW(args, 4096, L"--project-root \"%s\"", exeDir);
    }

    Logf("INFO", L"launching Core: %s", corePath);
    Logf("INFO", L"  args: %s", args);
    Logf("INFO", L"  cwd : %s", exeDir);

    SHELLEXECUTEINFOW sei = { 0 };
    sei.cbSize = sizeof(sei);
    sei.fMask = SEE_MASK_NOCLOSEPROCESS | SEE_MASK_NOASYNC;
    sei.lpFile = corePath;
    sei.lpParameters = args;
    sei.lpDirectory = exeDir;
    sei.nShow = SW_SHOWNORMAL;

    if (ShellExecuteExW(&sei)) {
        Log("INFO", L"Core launch issued OK");
        if (sei.hProcess != NULL) {
            DWORD wait = WaitForSingleObject(sei.hProcess, CORE_EARLY_EXIT_GRACE_MS);
            if (wait == WAIT_OBJECT_0) {
                DWORD exitCode = 0;
                if (GetExitCodeProcess(sei.hProcess, &exitCode)) {
                    Logf(exitCode == 0 ? "WARN" : "ERROR",
                        L"Core process exited within %lu ms (exitCode=%lu)",
                        CORE_EARLY_EXIT_GRACE_MS, exitCode);
                } else {
                    Logf("ERROR", L"Core process exited within %lu ms but exit code read failed (GetLastError=%lu)",
                        CORE_EARLY_EXIT_GRACE_MS, GetLastError());
                }
            } else if (wait == WAIT_TIMEOUT) {
                Logf("INFO", L"Core still running after %lu ms; bootstrap handoff considered alive",
                    CORE_EARLY_EXIT_GRACE_MS);
            } else {
                Logf("WARN", L"Core early-exit wait failed (wait=%lu GetLastError=%lu)",
                    wait, GetLastError());
            }
            CloseHandle(sei.hProcess);
        } else {
            Log("WARN", L"Core launch returned no process handle; cannot observe early exit");
        }
        return true;
    }
    DWORD err = GetLastError();
    g_lastCoreLaunchError = err;
    Logf("ERROR", L"Core launch failed (GetLastError=%lu)", err);
    return false;
}

int WINAPI wWinMain(HINSTANCE, HINSTANCE, LPWSTR cmdLine, int)
{
    wchar_t exeDir[MAX_PATH];
    if (!GetExeDir(exeDir, MAX_PATH)) {
        // 没法 log，直接 MessageBox + exit
        MessageBoxW(NULL, L"无法解析 bootstrap 自身路径。",
                    TITLE, MB_OK | MB_ICONERROR);
        return 1;
    }

    LogOpen(exeDir);
    Log("INFO", L"==== bootstrap start ====");
    Logf("INFO", L"exeDir = %s", exeDir);
    Logf("INFO", L"cmdLine = %s", (cmdLine && cmdLine[0]) ? cmdLine : L"(empty)");
    Logf("INFO", L"bootstrap pid=%lu", GetCurrentProcessId());

    // 1. 检测 runtime（检查 ProgramFiles、LOCALAPPDATA、USERPROFILE\.dotnet、DOTNET_ROOT env）
    wchar_t foundVer[64] = { 0 };
    wchar_t foundRoot[MAX_PATH] = { 0 };
    bool needSetEnv = false;
    bool hasRuntime = IsRuntimeInstalled(foundVer, 64, foundRoot, MAX_PATH, &needSetEnv);

    if (!hasRuntime) {
        // 2. 用 glob 扫 tools\dotnet-runtime\windowsdesktop-runtime-10.*-win-x64.exe；
        //    版本 bump（10.0.8 → 10.0.9 → 10.1.x）不需要改源码 + 同步 build.ps1 / pack.config
        wchar_t installerGlob[MAX_PATH];
        if (FAILED(StringCchCopyW(installerGlob, MAX_PATH, exeDir)) ||
            FAILED(StringCchCatW(installerGlob, MAX_PATH, RUNTIME_INSTALLER_GLOB))) {
            return FatalExit(L"CF7-BOOT-PATH",
                L"内部错误：路径拼接溢出。",
                L"请把 logs\\bootstrap.log 发给开发组。");
        }

        wchar_t installerPath[MAX_PATH] = { 0 };
        WIN32_FIND_DATAW instFd;
        HANDLE hInst = FindFirstFileW(installerGlob, &instFd);
        if (hInst != INVALID_HANDLE_VALUE) {
            if ((instFd.dwFileAttributes & FILE_ATTRIBUTE_DIRECTORY) == 0) {
                StringCchCopyW(installerPath, MAX_PATH, exeDir);
                StringCchCatW(installerPath, MAX_PATH, RUNTIME_INSTALLER_DIR_REL);
                StringCchCatW(installerPath, MAX_PATH, L"\\");
                StringCchCatW(installerPath, MAX_PATH, instFd.cFileName);
            }
            FindClose(hInst);
        }

        if (installerPath[0] == L'\0') {
            wchar_t err[1024];
            StringCchPrintfW(err, 1024,
                L"未检测到 .NET 10 桌面运行时，且 bundled installer 缺失：\n%s\n\n"
                L"请重新下载完整安装包，或手动从 Microsoft 网站安装 .NET 10 桌面运行时。",
                installerGlob);
            return FatalExit(L"CF7-BOOT-RUNTIME-INSTALLER-MISSING", err,
                L"请重新下载完整安装包，或手动从 Microsoft 网站安装 .NET 10 Desktop Runtime。");
        }
        Logf("INFO", L"installer resolved: %s", installerPath);

        // 3. 用户确认
        Log("INFO", L"runtime missing, prompting user to install");
        int choice = MessageBoxW(NULL,
            L"首次启动需要安装 .NET 10 桌面运行时（约 58MB，需要管理员授权一次）。\n\n"
            L"这是 Microsoft 官方安装包，预计耗时约 1 分钟。\n\n"
            L"点击「是」开始安装，点击「否」退出。",
            TITLE, MB_YESNO | MB_ICONINFORMATION);
        if (choice != IDYES) {
            Log("WARN", L"user declined runtime install, exiting");
            LogClose();
            return 1;
        }

        // 4. 运行 installer（同步 + 等退出）
        int installResult = RunInstaller(installerPath);
        if (installResult == -2) {
            return FatalExit(L"CF7-BOOT-RUNTIME-UAC-CANCELLED",
                L"管理员授权被取消，运行时未安装。",
                L"请重新启动游戏并允许管理员授权安装 .NET 10 Desktop Runtime。");
        }
        if (installResult < 0) {
            wchar_t err[256];
            StringCchPrintfW(err, 256,
                L"无法启动运行时安装包（系统错误码 %d）。",
                -installResult);
            return FatalExit(L"CF7-BOOT-RUNTIME-INSTALLER-LAUNCH", err,
                L"请手动运行 tools\\dotnet-runtime\\ 目录下的 .NET Runtime 安装包。");
        }
        // installer 退出码: 0 = 成功; 1602 = 用户取消; 1603 = 通用失败; 3010 = 需要重启
        if (installResult != 0 && installResult != 3010) {
            wchar_t err[1024];
            StringCchPrintfW(err, 1024,
                L"运行时安装失败（installer 退出码 %d）。\n\n"
                L"请尝试手动运行：\n%s",
                installResult, installerPath);
            return FatalExit(L"CF7-BOOT-RUNTIME-INSTALLER-FAILED", err,
                L"请手动运行提示中的安装包；如果安装器要求重启，请重启 Windows 后再启动游戏。");
        }

        // 5. 二次确认 runtime 已就位
        if (!IsRuntimeInstalled(foundVer, 64, foundRoot, MAX_PATH, &needSetEnv)) {
            return FatalExit(L"CF7-BOOT-RUNTIME-NOT-DETECTED",
                L"运行时安装似乎完成但未被检测到。\n\n"
                L"如果安装包提示需要重启，请重启 Windows 后再次双击启动。\n"
                L"否则请尝试重新运行 tools\\dotnet-runtime\\ 目录下的 installer。",
                L"请先重启 Windows；若仍失败，请手动安装 .NET 10 Desktop Runtime。");
        }
        Logf("INFO", L"runtime installed OK (version=%s)", foundVer);
    } else {
        Logf("INFO", L"runtime already present (version=%s @ %s)", foundVer, foundRoot);
    }

    // 1b. 如果 runtime 在非默认位置（user-scope LOCALAPPDATA / USERPROFILE\.dotnet），
    //     给当前进程设 DOTNET_ROOT_X64 + DOTNET_ROOT；ShellExecute Core 时 Core 继承本进程的 env，
    //     Core 的 apphost 读 env 就能找到 runtime（apphost 默认只看 %ProgramFiles%\dotnet）
    if (needSetEnv && foundRoot[0] != L'\0') {
        SetEnvironmentVariableW(L"DOTNET_ROOT_X64", foundRoot);
        SetEnvironmentVariableW(L"DOTNET_ROOT", foundRoot);
        Logf("INFO", L"set DOTNET_ROOT_X64 / DOTNET_ROOT = %s (for Core inheritance)", foundRoot);
    }

    // 运行时和游戏关键文件预检：只做诊断与 fail-fast，不尝试修复。
    if (!PreflightCriticalFiles(exeDir)) {
        return FatalExit(L"CF7-BOOT-FILE-INTEGRITY",
            L"启动器关键文件缺失或损坏。\n\n"
            L"请在 Steam 中验证游戏文件完整性，或重新下载完整安装包。\n"
            L"详细缺失项见 logs\\bootstrap.log 的 [preflight] 行。",
            L"请通过 Steam 验证游戏文件完整性；如果不是 Steam 版本，请重新解压完整安装包。");
    }

    // 6. 启动 Core
    wchar_t corePath[MAX_PATH];
    if (FAILED(StringCchCopyW(corePath, MAX_PATH, exeDir)) ||
        FAILED(StringCchCatW(corePath, MAX_PATH, CORE_EXE_REL))) {
        return FatalExit(L"CF7-BOOT-PATH",
            L"内部错误：路径拼接溢出。",
            L"请把 logs\\bootstrap.log 发给开发组。");
    }

    DWORD coreAttr = GetFileAttributesW(corePath);
    if (coreAttr == INVALID_FILE_ATTRIBUTES || (coreAttr & FILE_ATTRIBUTE_DIRECTORY)) {
        wchar_t err[1024];
        StringCchPrintfW(err, 1024,
            L"主程序缺失：\n%s\n\n"
            L"请确认整包完整 / 跑过 launcher\\build.ps1。",
            corePath);
        return FatalExit(L"CF7-BOOT-CORE-MISSING", err,
            L"请通过 Steam 验证游戏文件完整性，或重新下载完整安装包。");
    }

    if (!LaunchCore(exeDir, corePath, cmdLine)) {
        DWORD err = g_lastCoreLaunchError != 0 ? g_lastCoreLaunchError : GetLastError();
        wchar_t buf[256];
        StringCchPrintfW(buf, 256,
            L"无法启动主程序（系统错误码 %lu）。",
            err);
        return FatalExit(L"CF7-BOOT-CORE-LAUNCH", buf,
            L"请重试一次；如果仍失败，请检查杀毒软件是否拦截 runtime\\CRAZYFLASHER7MercenaryEmpire.Core.exe。");
    }

    Log("INFO", L"==== bootstrap exit OK ====");
    LogClose();
    return 0;
}
