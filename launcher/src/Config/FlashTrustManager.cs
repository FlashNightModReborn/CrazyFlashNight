// Flash Player 本地信任文件管理
// 确保本地 SWF 有权访问网络（XMLSocket / HTTP）
// C# 5 语法

using System;
using System.IO;
using CF7Launcher.Guardian;

namespace CF7Launcher.Config
{
    static class FlashTrustManager
    {
        private const string TrustFileName = "cf7me.cfg";

        /// <summary>
        /// 检查并配置 Flash Player 信任文件。
        /// 优先写用户级目录（无需管理员），失败时尝试系统级目录。
        /// </summary>
        /// <returns>true 表示信任已就绪（已存在或成功写入）</returns>
        public static bool EnsureTrust(string projectRoot)
        {
            // 规范化路径（去尾斜杠，统一大小写比较）
            string normalizedRoot = Path.GetFullPath(projectRoot).TrimEnd('\\', '/');

            // 1. 用户级信任目录（不需要管理员权限）
            string userTrustDir = Path.Combine(
                Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData),
                "Macromedia", "Flash Player", "#Security", "FlashPlayerTrust");

            if (TryEnsureTrustFile(userTrustDir, normalizedRoot))
                return true;

            // 2. 系统级信任目录（需要管理员权限）
            string systemTrustDir = Path.Combine(
                Environment.GetFolderPath(Environment.SpecialFolder.Windows),
                "SysWOW64", "Macromed", "Flash", "FlashPlayerTrust");

            if (TryEnsureTrustFile(systemTrustDir, normalizedRoot))
                return true;

            // 64 位系统上也检查 System32 路径
            string system32TrustDir = Path.Combine(
                Environment.GetFolderPath(Environment.SpecialFolder.Windows),
                "System32", "Macromed", "Flash", "FlashPlayerTrust");

            if (!system32TrustDir.Equals(systemTrustDir, StringComparison.OrdinalIgnoreCase))
            {
                if (TryEnsureTrustFile(system32TrustDir, normalizedRoot))
                    return true;
            }

            return false;
        }

        /// <summary>
        /// 尝试在指定信任目录中确保包含 projectRoot 的信任文件。
        /// </summary>
        private static bool TryEnsureTrustFile(string trustDir, string projectRoot)
        {
            try
            {
                string trustFile = Path.Combine(trustDir, TrustFileName);

                // 检查是否已配置
                if (File.Exists(trustFile))
                {
                    string content = File.ReadAllText(trustFile).Trim();
                    // 逐行检查是否已包含当前路径
                    string[] lines = content.Split(new char[] { '\n', '\r' }, StringSplitOptions.RemoveEmptyEntries);
                    foreach (string line in lines)
                    {
                        if (line.Trim().Equals(projectRoot, StringComparison.OrdinalIgnoreCase))
                        {
                            LogManager.Log("[FlashTrust] Already trusted: " + trustFile);
                            return true;
                        }
                    }
                    // 路径不在文件中，追加
                    File.AppendAllText(trustFile, Environment.NewLine + projectRoot);
                    LogManager.Log("[FlashTrust] Appended to: " + trustFile);
                    return true;
                }

                // 文件不存在，创建目录和文件
                if (!Directory.Exists(trustDir))
                    Directory.CreateDirectory(trustDir);

                File.WriteAllText(trustFile, projectRoot);
                LogManager.Log("[FlashTrust] Created: " + trustFile);
                return true;
            }
            catch (UnauthorizedAccessException)
            {
                LogManager.Log("[FlashTrust] No permission: " + trustDir);
                return false;
            }
            catch (Exception ex)
            {
                LogManager.Log("[FlashTrust] Failed (" + trustDir + "): " + ex.Message);
                return false;
            }
        }
    }
}
