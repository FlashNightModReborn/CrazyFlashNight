// Steam 正版所有权校验（Guardian 层）
// 动态加载 steam_api64.dll，检查用户是否拥有本体 AppID
// C# 5 语法，P/Invoke 动态绑定
//
// 安全策略：
//   开发环境（IsDevRepository=true）→ 全部 fail-open，不干扰开发
//   发行环境（IsDevRepository=false）→ DLL 缺失/加载失败 = fail-closed（疑似篡改）
//     仅导出名解析失败（SDK 版本不兼容）保留 fail-open
//
// GPLv3 合规：
//   开发环境检测不绑定特定 remote URL，fork/mirror/改名仓库均视为合法开发环境

using System;
using System.IO;
using System.Runtime.InteropServices;
using CF7Launcher.Guardian;

namespace CF7Launcher.Config
{
    static class SteamOwnershipCheck
    {
        // 本体 AppID（与 DLL 中 BIsSubscribedApp 使用的一致）
        private const uint BASE_GAME_APP_ID = 2402310;

        // 校验失败的具体原因（供调用方区分提示信息）
        private static string _failReason;
        public static string FailReason { get { return _failReason; } }

        [DllImport("kernel32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
        private static extern IntPtr LoadLibraryW(string lpFileName);

        [DllImport("kernel32.dll", SetLastError = true)]
        private static extern IntPtr GetProcAddress(IntPtr hModule, string lpProcName);

        [DllImport("kernel32.dll")]
        private static extern bool FreeLibrary(IntPtr hModule);

        // steam_api64.dll 函数签名
        [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
        private delegate bool SteamAPI_Init_Delegate();

        [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
        private delegate void SteamAPI_Shutdown_Delegate();

        // flat API: SteamAPI_SteamApps_v008() 返回 ISteamApps*
        [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
        private delegate IntPtr SteamAPI_SteamApps_Delegate();

        // flat API: SteamAPI_ISteamApps_BIsSubscribedApp(ISteamApps*, AppId_t)
        [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
        private delegate bool SteamAPI_ISteamApps_BIsSubscribedApp_Delegate(IntPtr self, uint appID);

        /// <summary>
        /// 检查当前 Steam 用户是否拥有本体游戏。
        /// 开发环境（合法 git 仓库）自动跳过。
        /// </summary>
        /// <returns>true=拥有/开发环境/无法验证, false=确认不拥有或疑似篡改</returns>
        public static bool Check(string projectRoot)
        {
            _failReason = null;

            // 开发环境检测：三级深度验证真实 git 仓库（支持 worktree/fork/mirror）
            bool isDev = IsDevRepository(projectRoot);
            if (isDev)
            {
                LogManager.Log("[SteamCheck] Dev repository detected, skipping ownership check");
                return true;
            }

            // === 以下为发行环境路径，采用 fail-closed 策略 ===

            string dllPath = FindSteamApiDll(projectRoot);
            if (dllPath == null)
            {
                // 发行环境下 DLL 应该存在，缺失视为篡改
                LogManager.Log("[SteamCheck] steam_api64.dll not found in release environment — blocking");
                _failReason = "dll_missing";
                return false;
            }

            LogManager.Log("[SteamCheck] Loading: " + dllPath);
            IntPtr hModule = LoadLibraryW(dllPath);
            if (hModule == IntPtr.Zero)
            {
                // DLL 存在但加载失败，可能被替换为无效文件
                LogManager.Log("[SteamCheck] LoadLibrary failed: " + Marshal.GetLastWin32Error());
                _failReason = "dll_load_failed";
                return false;
            }

            try
            {
                return DoCheck(hModule);
            }
            finally
            {
                // 不 Shutdown/FreeLibrary —— 让 Steam overlay 继续工作
                // Steam API 在进程生命周期内只应 Init 一次
            }
        }

        /// <summary>
        /// 三级深度验证：是否为真实的 git 开发仓库。
        /// 支持普通 clone、worktree、fork、mirror——不绑定特定 remote URL（GPLv3 合规）。
        ///
        /// Level 1: .git 入口有效（目录含 HEAD，或 worktree 文件含 gitdir:）
        /// Level 2: HEAD 内容是合法 git ref 或 commit hash
        /// Level 3: objects/pack/ 下存在真实 .pack 文件（证明有实际 git 历史）
        /// </summary>
        public static bool IsDevRepository(string projectRoot)
        {
            string gitPath = Path.Combine(projectRoot, ".git");
            string gitDir = null;

            // Level 1: 解析 .git 入口
            if (Directory.Exists(gitPath))
            {
                // 标准 clone：.git 是目录
                gitDir = gitPath;
            }
            else if (File.Exists(gitPath))
            {
                // git worktree：.git 是文件，内容为 "gitdir: /path/to/.git/worktrees/xxx"
                try
                {
                    string content = File.ReadAllText(gitPath).Trim();
                    if (content.StartsWith("gitdir:"))
                    {
                        string linked = content.Substring("gitdir:".Length).Trim();
                        // 处理相对路径
                        if (!Path.IsPathRooted(linked))
                            linked = Path.Combine(projectRoot, linked);
                        linked = Path.GetFullPath(linked);
                        if (Directory.Exists(linked))
                        {
                            gitDir = linked;
                            LogManager.Log("[SteamCheck] Worktree detected, gitDir=" + gitDir);
                        }
                    }
                }
                catch (Exception ex)
                {
                    LogManager.Log("[SteamCheck] Failed to read .git file: " + ex.Message);
                }
            }

            if (gitDir == null)
            {
                LogManager.Log("[SteamCheck] No valid .git entry found");
                return false;
            }

            // Level 2: HEAD 内容合法（ref: refs/heads/xxx 或 40位十六进制 commit hash）
            string headFile = Path.Combine(gitDir, "HEAD");
            if (!File.Exists(headFile))
            {
                LogManager.Log("[SteamCheck] No HEAD file in gitDir");
                return false;
            }

            try
            {
                string head = File.ReadAllText(headFile).Trim();
                bool validRef = head.StartsWith("ref: refs/");
                bool validHash = head.Length == 40 && IsHexString(head);
                if (!validRef && !validHash)
                {
                    LogManager.Log("[SteamCheck] HEAD content invalid: " + head);
                    return false;
                }
            }
            catch (Exception ex)
            {
                LogManager.Log("[SteamCheck] Failed to read HEAD: " + ex.Message);
                return false;
            }

            // Level 3: objects/pack/ 下存在至少一个 .pack 文件
            // 真实 clone 必有 pack 文件；mkdir .git + 伪造 HEAD 无法通过此检查
            // 对于 worktree，pack 文件在主仓库的 objects/ 下
            string objectsDir = ResolveObjectsDir(gitDir);
            if (objectsDir == null)
            {
                LogManager.Log("[SteamCheck] Cannot resolve objects directory");
                return false;
            }

            string packDir = Path.Combine(objectsDir, "pack");
            if (!Directory.Exists(packDir))
            {
                LogManager.Log("[SteamCheck] No objects/pack/ directory");
                return false;
            }

            string[] packFiles = Directory.GetFiles(packDir, "*.pack");
            if (packFiles.Length == 0)
            {
                LogManager.Log("[SteamCheck] No .pack files in objects/pack/");
                return false;
            }

            LogManager.Log("[SteamCheck] Valid git repository: " + packFiles.Length + " pack file(s)");
            return true;
        }

        /// <summary>
        /// 解析 objects 目录路径。
        /// 普通 clone：gitDir/objects/
        /// worktree：gitDir 是 .git/worktrees/xxx/，objects 在主 .git/objects/
        ///           通过 worktree 的 commondir 文件或向上查找 objects/ 获取
        /// </summary>
        private static string ResolveObjectsDir(string gitDir)
        {
            // 优先检查 commondir 文件（git worktree 标准机制）
            string commondirFile = Path.Combine(gitDir, "commondir");
            if (File.Exists(commondirFile))
            {
                try
                {
                    string commondir = File.ReadAllText(commondirFile).Trim();
                    if (!Path.IsPathRooted(commondir))
                        commondir = Path.Combine(gitDir, commondir);
                    commondir = Path.GetFullPath(commondir);
                    string objDir = Path.Combine(commondir, "objects");
                    if (Directory.Exists(objDir))
                        return objDir;
                }
                catch { }
            }

            // 直接检查 gitDir/objects/
            string direct = Path.Combine(gitDir, "objects");
            if (Directory.Exists(direct))
                return direct;

            return null;
        }

        private static bool IsHexString(string s)
        {
            for (int i = 0; i < s.Length; i++)
            {
                char c = s[i];
                if (!((c >= '0' && c <= '9') || (c >= 'a' && c <= 'f') || (c >= 'A' && c <= 'F')))
                    return false;
            }
            return true;
        }

        private static bool DoCheck(IntPtr hModule)
        {
            // 解析函数指针——使用 Steamworks flat API 正确的导出名
            IntPtr pInit = GetProcAddress(hModule, "SteamAPI_Init");
            IntPtr pApps = IntPtr.Zero;
            IntPtr pSubscribed = GetProcAddress(hModule, "SteamAPI_ISteamApps_BIsSubscribedApp");

            // SteamApps 接口获取：尝试多个 SDK 版本的导出名
            string[] steamAppsNames = new string[] {
                "SteamAPI_SteamApps_v008",
                "SteamAPI_SteamApps_v007",
                "SteamAPI_SteamApps_v006",
                "SteamAPI_SteamApps"
            };
            foreach (string name in steamAppsNames)
            {
                pApps = GetProcAddress(hModule, name);
                if (pApps != IntPtr.Zero)
                {
                    LogManager.Log("[SteamCheck] Resolved " + name);
                    break;
                }
            }

            // 逐个检查——导出名解析失败属于 SDK 版本不兼容，保留 fail-open
            // （与 DLL 缺失/加载失败不同，这不是用户可控的篡改向量）
            if (pInit == IntPtr.Zero)
            {
                LogManager.Log("[SteamCheck] Cannot resolve SteamAPI_Init, skipping (SDK mismatch)");
                return true;
            }
            if (pApps == IntPtr.Zero)
            {
                LogManager.Log("[SteamCheck] Cannot resolve SteamAPI_SteamApps_v00X, skipping (SDK mismatch)");
                return true;
            }
            if (pSubscribed == IntPtr.Zero)
            {
                LogManager.Log("[SteamCheck] Cannot resolve SteamAPI_ISteamApps_BIsSubscribedApp, skipping (SDK mismatch)");
                return true;
            }

            var fnInit = (SteamAPI_Init_Delegate)Marshal.GetDelegateForFunctionPointer(
                pInit, typeof(SteamAPI_Init_Delegate));
            var fnApps = (SteamAPI_SteamApps_Delegate)Marshal.GetDelegateForFunctionPointer(
                pApps, typeof(SteamAPI_SteamApps_Delegate));
            var fnSubscribed = (SteamAPI_ISteamApps_BIsSubscribedApp_Delegate)Marshal.GetDelegateForFunctionPointer(
                pSubscribed, typeof(SteamAPI_ISteamApps_BIsSubscribedApp_Delegate));

            // Init
            if (!fnInit())
            {
                LogManager.Log("[SteamCheck] SteamAPI_Init failed — Steam not running or not launched from Steam");
                _failReason = "steam_not_running";
                return false;
            }

            LogManager.Log("[SteamCheck] SteamAPI initialized");

            // 获取 ISteamApps 接口
            IntPtr steamApps = fnApps();
            if (steamApps == IntPtr.Zero)
            {
                LogManager.Log("[SteamCheck] SteamApps interface returned null");
                _failReason = "interface_null";
                return false;
            }

            // 检查所有权
            bool owned = fnSubscribed(steamApps, BASE_GAME_APP_ID);
            LogManager.Log("[SteamCheck] BIsSubscribedApp(" + BASE_GAME_APP_ID + ") = " + owned);

            if (!owned)
                _failReason = "not_owned";

            return owned;
        }

        /// <summary>
        /// 在多个候选路径中搜索 steam_api64.dll
        /// </summary>
        private static string FindSteamApiDll(string projectRoot)
        {
            string[] candidates = new string[]
            {
                // 1. Guardian 同级目录（打包后可能在这里）
                Path.Combine(projectRoot, "steam_api64.dll"),
                // 2. 基游 Plugins 目录（开发环境 + 标准 Steam 安装）
                Path.Combine(projectRoot, "..", "CrazyFlasher7StandAloneStarter_Data",
                    "Plugins", "x86_64", "steam_api64.dll"),
                // 3. 更上一级（resources/ 作为 projectRoot 时）
                Path.Combine(projectRoot, "..", "..", "CrazyFlasher7StandAloneStarter_Data",
                    "Plugins", "x86_64", "steam_api64.dll"),
            };

            foreach (string path in candidates)
            {
                string full = Path.GetFullPath(path);
                if (File.Exists(full))
                    return full;
            }

            return null;
        }
    }
}
