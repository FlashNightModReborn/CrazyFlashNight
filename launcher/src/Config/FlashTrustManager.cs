// Flash Player 本地信任文件管理（租约模式）
// Guardian 启动时写入，退出时删除，生命周期绑定进程
// C# 5 语法

using System;
using System.Collections.Generic;
using System.IO;
using CF7Launcher.Guardian;

namespace CF7Launcher.Config
{
    static class FlashTrustManager
    {
        private const string TrustFileName = "cf7me.cfg";

        // 记录本次写入的信任文件路径，退出时逐一清理
        private static readonly List<string> _activeLeasePaths = new List<string>();
        private static string _leasedRoot;

        /// <summary>
        /// 写入信任文件（租约）。Guardian 启动时调用。
        /// 优先写用户级目录（无需管理员），失败时尝试系统级目录。
        /// </summary>
        public static bool EnsureTrust(string projectRoot)
        {
            string normalizedRoot = Path.GetFullPath(projectRoot).TrimEnd('\\', '/');
            _leasedRoot = normalizedRoot;

            // 收集所有候选信任目录
            List<string> trustDirs = new List<string>();

            // 1. 用户级（不需要管理员权限）
            trustDirs.Add(Path.Combine(
                Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData),
                "Macromedia", "Flash Player", "#Security", "FlashPlayerTrust"));

            // 2. 系统级 SysWOW64
            string sysWow64 = Path.Combine(
                Environment.GetFolderPath(Environment.SpecialFolder.Windows),
                "SysWOW64", "Macromed", "Flash", "FlashPlayerTrust");
            trustDirs.Add(sysWow64);

            // 3. 系统级 System32（如果和 SysWOW64 不同）
            string system32 = Path.Combine(
                Environment.GetFolderPath(Environment.SpecialFolder.Windows),
                "System32", "Macromed", "Flash", "FlashPlayerTrust");
            if (!system32.Equals(sysWow64, StringComparison.OrdinalIgnoreCase))
                trustDirs.Add(system32);

            bool anySuccess = false;
            foreach (string dir in trustDirs)
            {
                if (TryWriteTrustFile(dir, normalizedRoot))
                    anySuccess = true;
            }

            if (!anySuccess)
                LogManager.Log("[FlashTrust] WARNING: failed to write any trust file");

            return anySuccess;
        }

        /// <summary>
        /// 撤销信任文件（退租）。Guardian 退出时调用。
        /// 只清理本次 EnsureTrust 写入的文件和条目。
        /// </summary>
        public static void RevokeTrust()
        {
            if (_leasedRoot == null) return;

            foreach (string filePath in _activeLeasePaths)
            {
                try
                {
                    if (!File.Exists(filePath)) continue;

                    string content = File.ReadAllText(filePath).Trim();
                    string[] lines = content.Split(new char[] { '\n', '\r' }, StringSplitOptions.RemoveEmptyEntries);

                    // 过滤掉本进程写入的路径
                    List<string> remaining = new List<string>();
                    foreach (string line in lines)
                    {
                        if (!line.Trim().Equals(_leasedRoot, StringComparison.OrdinalIgnoreCase))
                            remaining.Add(line);
                    }

                    if (remaining.Count == 0)
                    {
                        // 文件里只有我们的路径，直接删除整个文件
                        File.Delete(filePath);
                        LogManager.Log("[FlashTrust] Lease revoked (deleted): " + filePath);
                    }
                    else
                    {
                        // 还有其他项目的信任路径，只移除我们的
                        File.WriteAllText(filePath, string.Join(Environment.NewLine, remaining.ToArray()));
                        LogManager.Log("[FlashTrust] Lease revoked (removed entry): " + filePath);
                    }
                }
                catch (Exception ex)
                {
                    LogManager.Log("[FlashTrust] Revoke failed (" + filePath + "): " + ex.Message);
                }
            }

            _activeLeasePaths.Clear();
            _leasedRoot = null;
        }

        private static bool TryWriteTrustFile(string trustDir, string projectRoot)
        {
            try
            {
                string trustFile = Path.Combine(trustDir, TrustFileName);

                if (File.Exists(trustFile))
                {
                    string content = File.ReadAllText(trustFile).Trim();
                    string[] lines = content.Split(new char[] { '\n', '\r' }, StringSplitOptions.RemoveEmptyEntries);
                    foreach (string line in lines)
                    {
                        if (line.Trim().Equals(projectRoot, StringComparison.OrdinalIgnoreCase))
                        {
                            // 已存在，纳入租约管理
                            _activeLeasePaths.Add(trustFile);
                            LogManager.Log("[FlashTrust] Lease acquired (existing): " + trustFile);
                            return true;
                        }
                    }
                    File.AppendAllText(trustFile, Environment.NewLine + projectRoot);
                }
                else
                {
                    if (!Directory.Exists(trustDir))
                        Directory.CreateDirectory(trustDir);
                    File.WriteAllText(trustFile, projectRoot);
                }

                _activeLeasePaths.Add(trustFile);
                LogManager.Log("[FlashTrust] Lease acquired: " + trustFile);
                return true;
            }
            catch (UnauthorizedAccessException)
            {
                // 系统级目录无权限，静默跳过
                return false;
            }
            catch (Exception ex)
            {
                LogManager.Log("[FlashTrust] Write failed (" + trustDir + "): " + ex.Message);
                return false;
            }
        }
    }
}
