using System;
using System.Collections.Generic;
using System.IO;
using System.Runtime.InteropServices;
using CF7Launcher.Guardian;
using Microsoft.Win32;
using SharpDX.DXGI;

namespace CF7Launcher.Config
{
    /// <summary>
    /// 管理 HKCU\Software\Microsoft\DirectX\UserGpuPreferences 下的 per-application GPU 偏好条目。
    ///
    /// 模式 (mode)：
    ///   off  = 启动时只做 revert（清遗留），不写入新条目。默认。
    ///   auto = 同时满足"探测到独显"与"接 AC 电源"才写入；否则 revert。
    ///   on   = 无条件写入。
    ///
    /// 只管理 launcher 自己 + msedgewebview2.exe；不写 Flash Player（引擎与独显驱动兼容性存疑）。
    /// 始终在退出时 revert，避免注册表残留污染系统。
    /// </summary>
    public static class GpuPreferenceManager
    {
        private const string RegistryPath = @"Software\Microsoft\DirectX\UserGpuPreferences";
        private const string HighPerformanceValue = "GpuPreference=2;";
        private const int IntelVendorId = 0x8086;
        private const int MicrosoftVendorId = 0x1414;

        private static readonly object _lock = new object();
        private static List<string> _appliedPaths;

        [StructLayout(LayoutKind.Sequential)]
        private struct SYSTEM_POWER_STATUS
        {
            public byte ACLineStatus;
            public byte BatteryFlag;
            public byte BatteryLifePercent;
            public byte Reserved1;
            public int BatteryLifeTime;
            public int BatteryFullLifeTime;
        }

        [DllImport("kernel32.dll", SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool GetSystemPowerStatus(out SYSTEM_POWER_STATUS status);

        /// <summary>
        /// 根据 mode 计算并应用 effective 状态。启动时调用一次即可。
        /// 调用前会先 revert 历史条目，保证每次启动注册表状态由当前配置唯一决定。
        /// </summary>
        public static void ApplyIfNeeded(string projectRoot, string mode)
        {
            string normalized = (mode ?? "off").Trim().ToLowerInvariant();
            List<string> candidates = GetCandidateExecutables(projectRoot);

            // 统一先清理一次历史条目（覆盖前一次启动遗留 / 模式切换场景）。
            DeleteRegistryEntries(candidates);

            bool shouldApply = false;
            string reason;
            if (normalized == "on")
            {
                shouldApply = true;
                reason = "mode=on (forced)";
            }
            else if (normalized == "auto")
            {
                bool hasDGpu = HasDiscreteGpu();
                bool onAC = IsOnACPower();
                shouldApply = hasDGpu && onAC;
                reason = "mode=auto (discreteGpu=" + hasDGpu + ", onAC=" + onAC + ")";
            }
            else
            {
                reason = "mode=off";
            }

            LogManager.Log("[GpuPref] " + reason);

            if (!shouldApply)
            {
                lock (_lock) { _appliedPaths = null; }
                return;
            }

            List<string> written = WriteRegistryEntries(candidates);
            lock (_lock) { _appliedPaths = written; }
            LogManager.Log("[GpuPref] wrote " + written.Count + " entries (launcher + webview2)");
        }

        /// <summary>
        /// 进程退出时清理写入的条目。幂等，可多次调用。
        /// 即便 Apply 时因探测失败未写入，也尝试删除一次 candidate 列表，兜底历史脏数据。
        /// </summary>
        public static void Revert(string projectRoot)
        {
            List<string> toDelete;
            lock (_lock)
            {
                toDelete = _appliedPaths;
                _appliedPaths = null;
            }

            if (toDelete == null || toDelete.Count == 0)
            {
                // 即便本次没写过，也兜底清一次 candidate 列表（消除历史脏数据）。
                toDelete = GetCandidateExecutables(projectRoot);
            }

            DeleteRegistryEntries(toDelete);
        }

        private static List<string> GetCandidateExecutables(string projectRoot)
        {
            List<string> result = new List<string>();

            // launcher 自身
            try
            {
                string exe = typeof(GpuPreferenceManager).Assembly.Location;
                if (!string.IsNullOrEmpty(exe) && File.Exists(exe))
                {
                    string full = Path.GetFullPath(exe);
                    if (!result.Contains(full)) result.Add(full);
                }
            }
            catch (Exception ex) { LogManager.Log("[GpuPref] resolve launcher exe failed: " + ex.Message); }

            // projectRoot 下的 launcher exe（兼容从非项目目录启动场景）
            try
            {
                string rooted = Path.Combine(projectRoot, "CRAZYFLASHER7MercenaryEmpire.exe");
                if (File.Exists(rooted))
                {
                    string full = Path.GetFullPath(rooted);
                    if (!result.Contains(full)) result.Add(full);
                }
            }
            catch { }

            // msedgewebview2.exe (Evergreen Runtime, 每用户和系统级两处都枚举)
            string[] wvRoots = new string[]
            {
                Environment.GetFolderPath(Environment.SpecialFolder.ProgramFilesX86) == null
                    ? null
                    : Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ProgramFilesX86), @"Microsoft\EdgeWebView\Application"),
                Environment.GetFolderPath(Environment.SpecialFolder.ProgramFiles) == null
                    ? null
                    : Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ProgramFiles), @"Microsoft\EdgeWebView\Application"),
                Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData) ?? "",
                             @"Microsoft\EdgeWebView\Application")
            };
            foreach (string root in wvRoots)
            {
                if (string.IsNullOrEmpty(root) || !Directory.Exists(root)) continue;
                try
                {
                    string[] dirs = Directory.GetDirectories(root);
                    foreach (string dir in dirs)
                    {
                        string candidate = Path.Combine(dir, "msedgewebview2.exe");
                        if (File.Exists(candidate))
                        {
                            string full = Path.GetFullPath(candidate);
                            if (!result.Contains(full)) result.Add(full);
                        }
                    }
                }
                catch (Exception ex) { LogManager.Log("[GpuPref] enum WebView2 at " + root + " failed: " + ex.Message); }
            }

            return result;
        }

        private static bool HasDiscreteGpu()
        {
            Factory1 factory = null;
            try
            {
                factory = new Factory1();
                int count = factory.GetAdapterCount1();
                for (int i = 0; i < count; i++)
                {
                    Adapter1 adapter = null;
                    try
                    {
                        adapter = factory.GetAdapter1(i);
                        AdapterDescription1 desc = adapter.Description1;

                        // 跳过软件适配器（WARP / Basic Render Driver）
                        if ((desc.Flags & AdapterFlags.Software) != 0) continue;
                        if (desc.VendorId == MicrosoftVendorId) continue;

                        // Intel 集显跳过；任何其他非软件适配器即视为独显
                        if (desc.VendorId == IntelVendorId) continue;

                        // 进一步用名称兜底（某些平台 VendorId 识别不全）
                        string descName = desc.Description ?? "";
                        if (descName.IndexOf("Intel", StringComparison.OrdinalIgnoreCase) >= 0) continue;

                        LogManager.Log("[GpuPref] discrete GPU detected: " + descName
                            + " (Vendor=0x" + desc.VendorId.ToString("X4") + ")");
                        return true;
                    }
                    finally { if (adapter != null) adapter.Dispose(); }
                }
            }
            catch (Exception ex)
            {
                LogManager.Log("[GpuPref] DXGI enumeration failed: " + ex.Message);
            }
            finally { if (factory != null) factory.Dispose(); }
            return false;
        }

        private static bool IsOnACPower()
        {
            try
            {
                SYSTEM_POWER_STATUS status;
                if (!GetSystemPowerStatus(out status)) return true; // 读取失败时假设台式机（AC 在线）
                // 1 = Online, 0 = Offline, 255 = Unknown
                if (status.ACLineStatus == 1) return true;
                if (status.ACLineStatus == 0) return false;
                // Unknown (255): 多数台式机会回 255，按 AC 在线处理
                return true;
            }
            catch (Exception ex)
            {
                LogManager.Log("[GpuPref] GetSystemPowerStatus failed: " + ex.Message);
                return true;
            }
        }

        private static List<string> WriteRegistryEntries(List<string> paths)
        {
            List<string> written = new List<string>();
            RegistryKey key = null;
            try
            {
                key = Registry.CurrentUser.CreateSubKey(RegistryPath);
                if (key == null)
                {
                    LogManager.Log("[GpuPref] failed to open/create registry key");
                    return written;
                }
                foreach (string path in paths)
                {
                    try
                    {
                        key.SetValue(path, HighPerformanceValue, RegistryValueKind.String);
                        written.Add(path);
                    }
                    catch (Exception ex)
                    {
                        LogManager.Log("[GpuPref] write failed for " + path + ": " + ex.Message);
                    }
                }
            }
            catch (Exception ex)
            {
                LogManager.Log("[GpuPref] open registry failed: " + ex.Message);
            }
            finally { if (key != null) key.Close(); }
            return written;
        }

        private static void DeleteRegistryEntries(List<string> paths)
        {
            if (paths == null || paths.Count == 0) return;
            RegistryKey key = null;
            try
            {
                key = Registry.CurrentUser.OpenSubKey(RegistryPath, writable: true);
                if (key == null) return; // 键不存在，无需清理
                foreach (string path in paths)
                {
                    try { key.DeleteValue(path, throwOnMissingValue: false); }
                    catch (Exception ex) { LogManager.Log("[GpuPref] delete failed for " + path + ": " + ex.Message); }
                }
            }
            catch (Exception ex)
            {
                LogManager.Log("[GpuPref] open registry for delete failed: " + ex.Message);
            }
            finally { if (key != null) key.Close(); }
        }
    }
}
