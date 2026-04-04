// Steam 正版所有权校验（Guardian 层）
// 动态加载 steam_api64.dll，检查用户是否拥有本体 AppID
// C# 5 语法，P/Invoke 动态绑定

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
        /// 开发环境（合法 git clone）自动跳过。
        /// </summary>
        /// <returns>true=拥有或无法验证（容错），false=确认不拥有</returns>
        public static bool Check(string projectRoot)
        {
            _failReason = null;

            // 开发环境检测：三级深度验证真实 git clone
            if (IsDevRepository(projectRoot))
            {
                LogManager.Log("[SteamCheck] Dev repository detected, skipping ownership check");
                return true;
            }

            string dllPath = FindSteamApiDll(projectRoot);
            if (dllPath == null)
            {
                LogManager.Log("[SteamCheck] steam_api64.dll not found, skipping ownership check");
                return true; // 找不到 DLL 时容错放行
            }

            LogManager.Log("[SteamCheck] Loading: " + dllPath);
            IntPtr hModule = LoadLibraryW(dllPath);
            if (hModule == IntPtr.Zero)
            {
                LogManager.Log("[SteamCheck] LoadLibrary failed: " + Marshal.GetLastWin32Error());
                return true; // 加载失败容错
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
        /// 三级深度验证：是否为真正从 GitHub clone 的开发仓库。
        /// Level 1: .git/HEAD 是文件（拦截 mkdir .git）
        /// Level 2: HEAD 内容是合法 git ref（拦截空文件伪造）
        /// Level 3: .git/config 包含项目 remote URL（拦截伪造 git 结构）
        /// </summary>
        private static bool IsDevRepository(string projectRoot)
        {
            string gitDir = Path.Combine(projectRoot, ".git");

            // Level 1: .git/HEAD 必须是文件
            string headFile = Path.Combine(gitDir, "HEAD");
            if (!File.Exists(headFile))
            {
                LogManager.Log("[SteamCheck] No .git/HEAD found");
                return false;
            }

            // Level 2: HEAD 内容合法（ref: refs/heads/xxx 或 40位十六进制 commit hash）
            try
            {
                string head = File.ReadAllText(headFile).Trim();
                bool validRef = head.StartsWith("ref: refs/heads/");
                bool validHash = head.Length == 40 && IsHexString(head);
                if (!validRef && !validHash)
                {
                    LogManager.Log("[SteamCheck] .git/HEAD content invalid: " + head);
                    return false;
                }
            }
            catch (Exception ex)
            {
                LogManager.Log("[SteamCheck] Failed to read .git/HEAD: " + ex.Message);
                return false;
            }

            // Level 3: .git/config 包含项目的 remote URL
            string configFile = Path.Combine(gitDir, "config");
            if (!File.Exists(configFile))
            {
                LogManager.Log("[SteamCheck] No .git/config found");
                return false;
            }

            try
            {
                string config = File.ReadAllText(configFile);
                if (config.IndexOf("FlashNightModReborn/CrazyFlashNight", StringComparison.OrdinalIgnoreCase) < 0)
                {
                    LogManager.Log("[SteamCheck] .git/config does not contain expected remote URL");
                    return false;
                }
            }
            catch (Exception ex)
            {
                LogManager.Log("[SteamCheck] Failed to read .git/config: " + ex.Message);
                return false;
            }

            return true;
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

            // 逐个检查，给出具体失败的函数名
            if (pInit == IntPtr.Zero)
            {
                LogManager.Log("[SteamCheck] Cannot resolve SteamAPI_Init, skipping");
                return true;
            }
            if (pApps == IntPtr.Zero)
            {
                LogManager.Log("[SteamCheck] Cannot resolve SteamAPI_SteamApps_v00X, skipping");
                return true;
            }
            if (pSubscribed == IntPtr.Zero)
            {
                LogManager.Log("[SteamCheck] Cannot resolve SteamAPI_ISteamApps_BIsSubscribedApp, skipping");
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
