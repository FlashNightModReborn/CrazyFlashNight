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

        [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
        private delegate IntPtr SteamApps_Delegate();

        [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
        private delegate bool SteamAPI_ISteamApps_BIsSubscribedApp_Delegate(IntPtr self, uint appID);

        /// <summary>
        /// 检查当前 Steam 用户是否拥有本体游戏。
        /// 开发环境（存在 scripts/ 目录）自动跳过。
        /// </summary>
        /// <returns>true=拥有或无法验证（容错），false=确认不拥有</returns>
        public static bool Check(string projectRoot)
        {
            // 开发环境检测：.git/ 目录只存在于开发仓库，打包产物中不可能有
            if (Directory.Exists(Path.Combine(projectRoot, ".git")))
            {
                LogManager.Log("[SteamCheck] Dev environment detected (.git/ exists), skipping");
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

        private static bool DoCheck(IntPtr hModule)
        {
            // 解析函数指针
            IntPtr pInit = GetProcAddress(hModule, "SteamAPI_Init");
            IntPtr pApps = GetProcAddress(hModule, "SteamApps");
            IntPtr pSubscribed = GetProcAddress(hModule, "SteamAPI_ISteamApps_BIsSubscribedApp");

            if (pInit == IntPtr.Zero || pApps == IntPtr.Zero || pSubscribed == IntPtr.Zero)
            {
                // 可能是旧版 SDK，函数名不同
                LogManager.Log("[SteamCheck] Function resolution failed, trying v2 names");
                pSubscribed = GetProcAddress(hModule, "SteamAPI_ISteamApps_BIsSubscribedApp");
                if (pSubscribed == IntPtr.Zero)
                {
                    LogManager.Log("[SteamCheck] Cannot resolve Steam API functions, skipping");
                    return true;
                }
            }

            var fnInit = (SteamAPI_Init_Delegate)Marshal.GetDelegateForFunctionPointer(
                pInit, typeof(SteamAPI_Init_Delegate));
            var fnApps = (SteamApps_Delegate)Marshal.GetDelegateForFunctionPointer(
                pApps, typeof(SteamApps_Delegate));
            var fnSubscribed = (SteamAPI_ISteamApps_BIsSubscribedApp_Delegate)Marshal.GetDelegateForFunctionPointer(
                pSubscribed, typeof(SteamAPI_ISteamApps_BIsSubscribedApp_Delegate));

            // Init
            if (!fnInit())
            {
                LogManager.Log("[SteamCheck] SteamAPI_Init failed — Steam not running or not launched from Steam");
                return false;
            }

            LogManager.Log("[SteamCheck] SteamAPI initialized");

            // 获取 ISteamApps 接口
            IntPtr steamApps = fnApps();
            if (steamApps == IntPtr.Zero)
            {
                LogManager.Log("[SteamCheck] SteamApps() returned null");
                return false;
            }

            // 检查所有权
            bool owned = fnSubscribed(steamApps, BASE_GAME_APP_ID);
            LogManager.Log("[SteamCheck] BIsSubscribedApp(" + BASE_GAME_APP_ID + ") = " + owned);

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
