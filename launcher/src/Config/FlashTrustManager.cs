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

        // 关键：带 BOM 的 UTF-8。Flash Player 读取无 BOM 的 trust 文件时会按系统默认代码页
        // (中文系统为 GBK/936) 解释；中文安装路径用 UTF-8 无 BOM 写入会被解成乱码 →
        // 受信路径与实际 SWF 路径不匹配 → SWF 落入受限沙箱 → 无法连本地后端 (socket 超时)。
        // 写入 BOM 让 Flash 在任何默认代码页下都按 UTF-8 正确解析路径。
        private static readonly System.Text.UTF8Encoding Utf8Bom = new System.Text.UTF8Encoding(true);

        // 只记录本次 **新写入/追加** 的信任文件路径，退出时逐一清理
        // 预存条目（EnsureTrust 前就已存在的）不纳入此列表
        private static readonly List<string> _ownedLeasePaths = new List<string>();
        private static string _leasedRoot;

        /// <summary>
        /// 写入信任文件（租约）。Guardian 启动时调用。
        /// 优先写用户级目录（无需管理员），失败时尝试系统级目录。
        /// </summary>
        public static bool EnsureTrust(string projectRoot)
        {
            string normalizedRoot = Path.GetFullPath(projectRoot).TrimEnd('\\', '/');
            _leasedRoot = normalizedRoot;

            // 非 ASCII 安装路径告警：即便已写 UTF-8 BOM 缓解，仍保留显式告警，
            // 以便在个别 Flash 构建不识别 BOM 时快速定位"加载界面卡住/无法连后端"问题。
            if (HasNonAscii(normalizedRoot))
            {
                LogManager.Log("[FlashTrust] WARNING: 安装路径含非 ASCII(中文)字符 — " +
                    "若游戏卡在加载界面/无法连接后端, 建议重装到纯英文路径。Path: " + normalizedRoot);
            }

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
        /// 只清理本次 EnsureTrust 新写入/追加的条目，不动预存的。
        /// </summary>
        public static void RevokeTrust()
        {
            if (_leasedRoot == null) return;

            foreach (string filePath in _ownedLeasePaths)
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
                        File.WriteAllText(filePath, string.Join(Environment.NewLine, remaining.ToArray()), Utf8Bom);
                        LogManager.Log("[FlashTrust] Lease revoked (removed entry): " + filePath);
                    }
                }
                catch (Exception ex)
                {
                    LogManager.Log("[FlashTrust] Revoke failed (" + filePath + "): " + ex.Message);
                }
            }

            _ownedLeasePaths.Clear();
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
                            // 条目已存在（由 bat 或之前的进程写入），不纳入租约
                            // 退出时不会删除此条目
                            LogManager.Log("[FlashTrust] Already trusted (not leased): " + trustFile);
                            return true;
                        }
                    }
                    // 路径不在文件中，追加——这是我们写的，纳入租约。
                    // 用全量重写(带 BOM)而非 AppendAllText：保证整个文件有 BOM，
                    // 同时把旧版本可能遗留的无 BOM 文件一并修正(已存在条目原样保留)。
                    File.WriteAllText(trustFile, content + Environment.NewLine + projectRoot, Utf8Bom);
                    _ownedLeasePaths.Add(trustFile);
                    LogManager.Log("[FlashTrust] Lease acquired (appended): " + trustFile);
                }
                else
                {
                    // 文件不存在，整个文件由我们创建，纳入租约
                    if (!Directory.Exists(trustDir))
                        Directory.CreateDirectory(trustDir);
                    File.WriteAllText(trustFile, projectRoot, Utf8Bom);
                    _ownedLeasePaths.Add(trustFile);
                    LogManager.Log("[FlashTrust] Lease acquired (created): " + trustFile);
                }

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

        private static bool HasNonAscii(string s)
        {
            if (s == null) return false;
            for (int i = 0; i < s.Length; i++)
            {
                if (s[i] > 0x7F) return true;
            }
            return false;
        }
    }
}
