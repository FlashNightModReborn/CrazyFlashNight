using System;
using System.Collections.Generic;
using System.IO;
using System.Text;
using CF7Launcher.Save;
using Newtonsoft.Json.Linq;

namespace CF7Launcher.Config
{
    internal sealed class FlashLocalStorageStatus
    {
        public bool Ok { get; set; }
        public string Error { get; set; }
        public double LimitKb { get; set; }
        public bool Unlimited { get; set; }
        public long? LimitBytes { get; set; }
        public long UsedBytes { get; set; }
        public int UsedFiles { get; set; }
        public string Source { get; set; }
        public string Status { get; set; }
        public bool NeedsAttention { get; set; }
        public string SettingsPath { get; set; }
        public string SharedObjectsRoot { get; set; }

        internal JObject ToJson(bool? canModifyNow = null)
        {
            var obj = new JObject
            {
                ["ok"] = Ok,
                ["limitKb"] = LimitKb,
                ["unlimited"] = Unlimited,
                ["limitBytes"] = LimitBytes.HasValue ? (JToken)new JValue(LimitBytes.Value) : JValue.CreateNull(),
                ["usedBytes"] = UsedBytes,
                ["usedFiles"] = UsedFiles,
                ["source"] = Source ?? "flash_default",
                ["status"] = Status ?? "ok",
                ["needsAttention"] = NeedsAttention
            };
            if (!Ok && !string.IsNullOrEmpty(Error)) obj["error"] = Error;
            if (!string.IsNullOrEmpty(SettingsPath)) obj["settingsPath"] = SettingsPath;
            if (!string.IsNullOrEmpty(SharedObjectsRoot)) obj["sharedObjectsRoot"] = SharedObjectsRoot;
            if (canModifyNow.HasValue) obj["canModifyNow"] = canModifyNow.Value;
            return obj;
        }
    }

    /// <summary>
    /// 读取并安全修改 Adobe Flash Player Standalone 的本机存储配额（%APPDATA%\Macromedia\Flash Player\...）。
    ///
    /// 实测现役 flashplayer_sa 二进制格式（#local\settings.sol）：
    ///   - SOL header: 00 BF [u32 BE bodyLen] "TCSO" 00 04 00 00 00 00 [u16 BE nameLen] [name] 00 00 00 00
    ///   - 每个顶层属性: [u16 BE keyLen] [UTF-8 key] [AMF0 value] 00
    ///   - klimit（AMF0 Number, IEEE-754 BE double）:
    ///       -2.0 (C0 00 00 00 00 00 00 00) = 无限制
    ///        0.0                           = 禁止本地存储 (0 KB)
    ///       10.0 / 100.0 / 1024.0 / 10240.0 = 对应 KB 上限
    ///       -1.0                           = 回退到全局 defaultklimit
    ///
    /// 设计不变式：
    ///   1. 严格解析 AMF0（拒绝未知类型/越界/AMF3/损坏文件），绝不覆写无法解析的原文件；
    ///   2. 写入只更新 klimit（及必要时在 sys\settings.sol 的 domains 中补 local=true），其余属性逐字节保真；
    ///   3. 落盘统一走 DurableFileWriter.WriteAllBytes（刷盘临时文件 + 保留旧副本 + 读回校验）；
    ///   4. 仅由用户显式动作调用写入；调用方负责在修改前保证无运行中 Flash（空闲 prewarm 须先 teardown）。
    /// </summary>
    internal static class FlashLocalStorageSettings
    {
        internal const double LimitUnlimitedKb = -2.0;
        internal const double DefaultFlashLimitKb = 100.0;
        private const long MinSafeHeadroomBytes = 64 * 1024; // 单槽 CF7 存档约 20–60 KB
        private const int MaxSolFileBytes = 1024 * 1024;
        private const int MaxAmfDepth = 16;

        internal static readonly double[] AllowedPresetLimitsKb = new[]
        {
            100.0,
            1024.0,
            10240.0,
            LimitUnlimitedKb
        };

        private static readonly object WriteLock = new object();

        internal static bool IsAllowedPresetLimitKb(double limitKb)
        {
            if (double.IsNaN(limitKb) || double.IsInfinity(limitKb)) return false;
            for (int i = 0; i < AllowedPresetLimitsKb.Length; i++)
            {
                if (Math.Abs(AllowedPresetLimitsKb[i] - limitKb) < 0.0001) return true;
            }
            return false;
        }

        internal static double NormalizePresetLimitKb(double limitKb)
        {
            for (int i = 0; i < AllowedPresetLimitsKb.Length; i++)
            {
                if (Math.Abs(AllowedPresetLimitsKb[i] - limitKb) < 0.0001) return AllowedPresetLimitsKb[i];
            }
            throw new ArgumentOutOfRangeException(nameof(limitKb), "Unsupported Flash local storage limit preset.");
        }

        internal static string GetFlashPlayerRoot(string roamingAppData = null)
        {
            string roaming = ResolveRoaming(roamingAppData);
            return Path.Combine(roaming, "Macromedia", "Flash Player");
        }

        internal static string GetGlobalSettingsSolPath(string roamingAppData = null)
        {
            return Path.Combine(GetFlashPlayerRoot(roamingAppData),
                "macromedia.com", "support", "flashplayer", "sys", "settings.sol");
        }

        internal static string GetLocalSettingsSolPath(string roamingAppData = null)
        {
            return Path.Combine(GetFlashPlayerRoot(roamingAppData),
                "macromedia.com", "support", "flashplayer", "sys", "#local", "settings.sol");
        }

        internal static string GetSharedObjectsRoot(string roamingAppData = null)
        {
            return Path.Combine(GetFlashPlayerRoot(roamingAppData), "#SharedObjects");
        }

        internal static FlashLocalStorageStatus ReadStatus(string roamingAppData = null)
        {
            string localSolPath;
            string globalSolPath;
            string sharedObjectsRoot;
            try
            {
                localSolPath = GetLocalSettingsSolPath(roamingAppData);
                globalSolPath = GetGlobalSettingsSolPath(roamingAppData);
                sharedObjectsRoot = GetSharedObjectsRoot(roamingAppData);
            }
            catch (Exception ex)
            {
                return new FlashLocalStorageStatus
                {
                    Ok = false,
                    Error = "path_unavailable:" + ex.GetType().Name,
                    LimitKb = DefaultFlashLimitKb,
                    Unlimited = false,
                    LimitBytes = (long)(DefaultFlashLimitKb * 1024),
                    Source = "flash_default",
                    Status = "warning",
                    NeedsAttention = true
                };
            }

            long usedBytes;
            int usedFiles;
            ScanLocalhostUsage(sharedObjectsRoot, out usedBytes, out usedFiles);

            double effectiveLimitKb = DefaultFlashLimitKb;
            string source = "flash_default";
            string parseError = null;

            bool hasLocalLimit = false;
            if (File.Exists(localSolPath))
            {
                SolDocument localDoc;
                if (TryParseSolFile(localSolPath, out localDoc, out string localErr))
                {
                    if (localDoc.TryGetNumber("klimit", out double klimit) && !double.IsNaN(klimit) && !double.IsInfinity(klimit))
                    {
                        if (Math.Abs(klimit - (-1.0)) >= 0.0001)
                        {
                            effectiveLimitKb = klimit;
                            source = "local_settings";
                            hasLocalLimit = true;
                        }
                    }
                }
                else
                {
                    parseError = "local_" + localErr;
                }
            }

            if (!hasLocalLimit && File.Exists(globalSolPath))
            {
                SolDocument globalDoc;
                if (TryParseSolFile(globalSolPath, out globalDoc, out _))
                {
                    if (globalDoc.TryGetNumber("defaultklimit", out double defLimit)
                        && !double.IsNaN(defLimit) && !double.IsInfinity(defLimit)
                        && Math.Abs(defLimit - (-1.0)) >= 0.0001)
                    {
                        effectiveLimitKb = defLimit;
                        source = "default_settings";
                    }
                }
            }

            bool unlimited = effectiveLimitKb <= -1.5;
            long? limitBytes = unlimited ? (long?)null : (long)Math.Max(0.0, Math.Round(effectiveLimitKb * 1024.0));
            string status = ClassifyStatus(effectiveLimitKb, unlimited, limitBytes, usedBytes);

            return new FlashLocalStorageStatus
            {
                Ok = parseError == null,
                Error = parseError,
                LimitKb = unlimited ? LimitUnlimitedKb : effectiveLimitKb,
                Unlimited = unlimited,
                LimitBytes = limitBytes,
                UsedBytes = usedBytes,
                UsedFiles = usedFiles,
                Source = source,
                Status = status,
                NeedsAttention = status != "ok" || parseError != null,
                SettingsPath = localSolPath,
                SharedObjectsRoot = sharedObjectsRoot
            };
        }

        internal static FlashLocalStorageStatus SetLocalLimitKb(double targetLimitKb, string roamingAppData = null)
        {
            if (!IsAllowedPresetLimitKb(targetLimitKb))
            {
                var current = ReadStatus(roamingAppData);
                current.Ok = false;
                current.Error = "invalid_limit";
                return current;
            }
            double normalizedLimit = NormalizePresetLimitKb(targetLimitKb);

            lock (WriteLock)
            {
                string localSolPath;
                string globalSolPath;
                try
                {
                    localSolPath = GetLocalSettingsSolPath(roamingAppData);
                    globalSolPath = GetGlobalSettingsSolPath(roamingAppData);
                }
                catch (Exception ex)
                {
                    var failed = ReadStatus(roamingAppData);
                    failed.Ok = false;
                    failed.Error = "path_unavailable:" + ex.GetType().Name;
                    return failed;
                }

                byte[] newLocalBytes;
                if (File.Exists(localSolPath))
                {
                    if (!TryParseSolFile(localSolPath, out SolDocument localDoc, out string parseErr))
                    {
                        var failed = ReadStatus(roamingAppData);
                        failed.Ok = false;
                        failed.Error = "sol_parse_failed:" + parseErr;
                        return failed;
                    }
                    localDoc.SetNumber("klimit", normalizedLimit);
                    newLocalBytes = localDoc.Serialize();
                }
                else
                {
                    var localDoc = CreateDefaultLocalSettingsDocument(normalizedLimit);
                    newLocalBytes = localDoc.Serialize();
                }

                // 若 sys\settings.sol 存在且 domains 对象缺少 local=true，则一并补齐以保证 Flash 识别 #local\settings.sol。
                byte[] patchedGlobalBytes = null;
                if (File.Exists(globalSolPath))
                {
                    if (!TryParseSolFile(globalSolPath, out SolDocument globalDoc, out string globalErr))
                    {
                        var failed = ReadStatus(roamingAppData);
                        failed.Ok = false;
                        failed.Error = "global_sol_parse_failed:" + globalErr;
                        return failed;
                    }
                    if (globalDoc.TryEnsureDomainFlag("domains", "local", true, out bool globalChanged) && globalChanged)
                    {
                        patchedGlobalBytes = globalDoc.Serialize();
                    }
                }

                try
                {
                    string localDir = Path.GetDirectoryName(localSolPath);
                    if (!string.IsNullOrEmpty(localDir)) Directory.CreateDirectory(localDir);
                    DurableFileWriter.WriteAllBytes(localSolPath, newLocalBytes);
                    if (patchedGlobalBytes != null)
                    {
                        DurableFileWriter.WriteAllBytes(globalSolPath, patchedGlobalBytes);
                    }
                }
                catch (Exception ex)
                {
                    var failed = ReadStatus(roamingAppData);
                    failed.Ok = false;
                    failed.Error = "write_failed:" + ex.GetType().Name;
                    return failed;
                }

                return ReadStatus(roamingAppData);
            }
        }

        private static string ClassifyStatus(double limitKb, bool unlimited, long? limitBytes, long usedBytes)
        {
            if (unlimited) return "ok";
            if (limitKb <= 0.0 || !limitBytes.HasValue || limitBytes.Value <= 0) return "blocked";
            if (usedBytes >= limitBytes.Value || (limitBytes.Value - usedBytes) < MinSafeHeadroomBytes)
                return "exceeded";
            if (limitKb <= DefaultFlashLimitKb || usedBytes * 100L >= limitBytes.Value * 80L)
                return "warning";
            return "ok";
        }

        private static void ScanLocalhostUsage(string sharedObjectsRoot, out long totalBytes, out int totalFiles)
        {
            totalBytes = 0;
            totalFiles = 0;
            if (string.IsNullOrEmpty(sharedObjectsRoot) || !Directory.Exists(sharedObjectsRoot)) return;
            try
            {
                string[] profileDirs = Directory.GetDirectories(sharedObjectsRoot);
                for (int i = 0; i < profileDirs.Length; i++)
                {
                    string localhostDir = Path.Combine(profileDirs[i], "localhost");
                    if (!Directory.Exists(localhostDir)) continue;
                    AccumulateSolBytes(localhostDir, ref totalBytes, ref totalFiles);
                }
            }
            catch
            {
                // 只读统计，忽略个别不可访问路径
            }
        }

        private static void AccumulateSolBytes(string dir, ref long totalBytes, ref int totalFiles)
        {
            var stack = new Stack<string>();
            stack.Push(dir);
            while (stack.Count > 0)
            {
                string current = stack.Pop();
                try
                {
                    foreach (string file in Directory.GetFiles(current, "*.sol"))
                    {
                        try
                        {
                            var fi = new FileInfo(file);
                            if ((fi.Attributes & FileAttributes.ReparsePoint) != 0) continue;
                            totalBytes += fi.Length;
                            totalFiles++;
                        }
                        catch { }
                    }
                    foreach (string sub in Directory.GetDirectories(current))
                    {
                        try
                        {
                            var di = new DirectoryInfo(sub);
                            if ((di.Attributes & FileAttributes.ReparsePoint) != 0) continue;
                            stack.Push(sub);
                        }
                        catch { }
                    }
                }
                catch { }
            }
        }

        private static string ResolveRoaming(string supplied)
        {
            string value = supplied ?? Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData);
            if (string.IsNullOrWhiteSpace(value) || !Path.IsPathRooted(value))
                throw new IOException("Roaming AppData must resolve to an absolute path.");
            return Path.GetFullPath(value);
        }

        private static SolDocument CreateDefaultLocalSettingsDocument(double limitKb)
        {
            var doc = new SolDocument("local/settings");
            doc.SetBool("allow", false);
            doc.SetBool("always", false);
            doc.SetNumber("klimit", limitKb);
            doc.SetBool("allowsecure", false);
            doc.SetBool("alwayssecure", false);
            return doc;
        }

        private static bool TryParseSolFile(string path, out SolDocument doc, out string error)
        {
            doc = null;
            error = null;
            byte[] bytes;
            try
            {
                using (var stream = new FileStream(path, FileMode.Open, FileAccess.Read, FileShare.ReadWrite))
                {
                    if (stream.Length < 22 || stream.Length > MaxSolFileBytes)
                    {
                        error = "size_out_of_range";
                        return false;
                    }
                    bytes = new byte[(int)stream.Length];
                    int read = 0;
                    while (read < bytes.Length)
                    {
                        int n = stream.Read(bytes, read, bytes.Length - read);
                        if (n <= 0) break;
                        read += n;
                    }
                    if (read != bytes.Length)
                    {
                        error = "short_read";
                        return false;
                    }
                }
            }
            catch (Exception ex)
            {
                error = "io_" + ex.GetType().Name;
                return false;
            }
            return SolDocument.TryParse(bytes, out doc, out error);
        }

        // ── 严格 AMF0 SOL 文档读写器（保留未知属性原始字节，fail-closed）──

        internal sealed class SolProperty
        {
            public string Name;
            public byte[] RawValue;
        }

        internal sealed class SolDocument
        {
            public string Name { get; }
            public List<SolProperty> Properties { get; } = new List<SolProperty>();

            public SolDocument(string name)
            {
                Name = name ?? throw new ArgumentNullException(nameof(name));
            }

            public static bool TryParse(byte[] bytes, out SolDocument doc, out string error)
            {
                doc = null;
                error = null;
                if (bytes == null || bytes.Length < 22)
                {
                    error = "truncated_header";
                    return false;
                }
                if (bytes[0] != 0x00 || bytes[1] != 0xBF)
                {
                    error = "bad_magic";
                    return false;
                }
                uint bodyLen = ReadU32BE(bytes, 2);
                if (bodyLen + 6 != (uint)bytes.Length)
                {
                    error = "body_length_mismatch";
                    return false;
                }
                if (bytes[6] != (byte)'T' || bytes[7] != (byte)'C' || bytes[8] != (byte)'S' || bytes[9] != (byte)'O'
                    || bytes[10] != 0x00 || bytes[11] != 0x04
                    || bytes[12] != 0x00 || bytes[13] != 0x00 || bytes[14] != 0x00 || bytes[15] != 0x00)
                {
                    error = "bad_tcso_marker";
                    return false;
                }

                int pos = 16;
                if (!TryReadUtf8Short(bytes, ref pos, out string solName))
                {
                    error = "bad_sol_name";
                    return false;
                }
                if (pos + 4 > bytes.Length)
                {
                    error = "missing_amf_version";
                    return false;
                }
                uint amfVersion = ReadU32BE(bytes, pos);
                pos += 4;
                if (amfVersion != 0)
                {
                    error = "unsupported_amf_version";
                    return false;
                }

                var result = new SolDocument(solName);
                while (pos < bytes.Length)
                {
                    if (!TryReadUtf8Short(bytes, ref pos, out string propName))
                    {
                        error = "bad_property_name";
                        return false;
                    }
                    int valueStart = pos;
                    if (!TrySkipAmf0Value(bytes, ref pos, 0))
                    {
                        error = "bad_amf0_value";
                        return false;
                    }
                    int valueLen = pos - valueStart;
                    if (pos >= bytes.Length || bytes[pos] != 0x00)
                    {
                        error = "missing_property_trailer";
                        return false;
                    }
                    pos++; // trailing 0x00

                    var rawVal = new byte[valueLen];
                    Buffer.BlockCopy(bytes, valueStart, rawVal, 0, valueLen);
                    result.Properties.Add(new SolProperty { Name = propName, RawValue = rawVal });
                }

                doc = result;
                return true;
            }

            public bool TryGetNumber(string name, out double value)
            {
                value = 0;
                for (int i = 0; i < Properties.Count; i++)
                {
                    var p = Properties[i];
                    if (string.Equals(p.Name, name, StringComparison.Ordinal))
                    {
                        if (p.RawValue != null && p.RawValue.Length == 9 && p.RawValue[0] == 0x00)
                        {
                            value = ReadDoubleBE(p.RawValue, 1);
                            return true;
                        }
                        return false;
                    }
                }
                return false;
            }

            public void SetNumber(string name, double value)
            {
                byte[] raw = EncodeAmf0Number(value);
                SetRawProperty(name, raw);
            }

            public void SetBool(string name, bool value)
            {
                byte[] raw = new byte[] { 0x01, value ? (byte)0x01 : (byte)0x00 };
                SetRawProperty(name, raw);
            }

            /// <summary>
            /// 在 AMF0 Object 属性（如 sys\settings.sol 中的 domains）内确保存在指定 bool 键。
            /// 保留对象中所有其他键的原始字节；仅当键不存在或值不同时才重建该对象字节。
            /// </summary>
            public bool TryEnsureDomainFlag(string objectPropName, string key, bool flagValue, out bool changed)
            {
                changed = false;
                SolProperty prop = null;
                for (int i = 0; i < Properties.Count; i++)
                {
                    if (string.Equals(Properties[i].Name, objectPropName, StringComparison.Ordinal))
                    {
                        prop = Properties[i];
                        break;
                    }
                }
                if (prop == null || prop.RawValue == null || prop.RawValue.Length < 4 || prop.RawValue[0] != 0x03)
                    return false;

                byte[] objBytes = prop.RawValue;
                int pos = 1;
                var entries = new List<Tuple<string, byte[]>>();
                bool found = false;
                while (pos < objBytes.Length)
                {
                    if (pos + 3 <= objBytes.Length && objBytes[pos] == 0x00 && objBytes[pos + 1] == 0x00 && objBytes[pos + 2] == 0x09)
                    {
                        pos += 3;
                        break;
                    }
                    if (!TryReadUtf8Short(objBytes, ref pos, out string memberName)) return false;
                    int valStart = pos;
                    if (!TrySkipAmf0Value(objBytes, ref pos, 1)) return false;
                    byte[] memberVal = new byte[pos - valStart];
                    Buffer.BlockCopy(objBytes, valStart, memberVal, 0, memberVal.Length);
                    if (string.Equals(memberName, key, StringComparison.Ordinal))
                    {
                        found = true;
                        byte expected = flagValue ? (byte)0x01 : (byte)0x00;
                        if (memberVal.Length == 2 && memberVal[0] == 0x01 && memberVal[1] == expected)
                            return true; // already matches
                        memberVal = new byte[] { 0x01, expected };
                        changed = true;
                    }
                    entries.Add(Tuple.Create(memberName, memberVal));
                }
                if (pos != objBytes.Length) return false;

                if (!found)
                {
                    entries.Add(Tuple.Create(key, new byte[] { 0x01, flagValue ? (byte)0x01 : (byte)0x00 }));
                    changed = true;
                }
                if (!changed) return true;

                using (var ms = new MemoryStream())
                {
                    ms.WriteByte(0x03);
                    for (int i = 0; i < entries.Count; i++)
                    {
                        WriteUtf8Short(ms, entries[i].Item1);
                        ms.Write(entries[i].Item2, 0, entries[i].Item2.Length);
                    }
                    ms.WriteByte(0x00);
                    ms.WriteByte(0x00);
                    ms.WriteByte(0x09);
                    prop.RawValue = ms.ToArray();
                }
                return true;
            }

            public byte[] Serialize()
            {
                byte[] body;
                using (var ms = new MemoryStream())
                {
                    ms.Write(new byte[] { (byte)'T', (byte)'C', (byte)'S', (byte)'O', 0x00, 0x04, 0x00, 0x00, 0x00, 0x00 }, 0, 10);
                    WriteUtf8Short(ms, Name);
                    ms.Write(new byte[] { 0x00, 0x00, 0x00, 0x00 }, 0, 4); // AMF0
                    for (int i = 0; i < Properties.Count; i++)
                    {
                        WriteUtf8Short(ms, Properties[i].Name);
                        ms.Write(Properties[i].RawValue, 0, Properties[i].RawValue.Length);
                        ms.WriteByte(0x00);
                    }
                    body = ms.ToArray();
                }

                byte[] full = new byte[6 + body.Length];
                full[0] = 0x00;
                full[1] = 0xBF;
                uint len = (uint)body.Length;
                full[2] = (byte)((len >> 24) & 0xFF);
                full[3] = (byte)((len >> 16) & 0xFF);
                full[4] = (byte)((len >> 8) & 0xFF);
                full[5] = (byte)(len & 0xFF);
                Buffer.BlockCopy(body, 0, full, 6, body.Length);
                return full;
            }

            private void SetRawProperty(string name, byte[] raw)
            {
                for (int i = 0; i < Properties.Count; i++)
                {
                    if (string.Equals(Properties[i].Name, name, StringComparison.Ordinal))
                    {
                        Properties[i].RawValue = raw;
                        return;
                    }
                }
                Properties.Add(new SolProperty { Name = name, RawValue = raw });
            }

            private static byte[] EncodeAmf0Number(double value)
            {
                byte[] raw = new byte[9];
                raw[0] = 0x00;
                byte[] num = BitConverter.GetBytes(value);
                if (BitConverter.IsLittleEndian) Array.Reverse(num);
                Buffer.BlockCopy(num, 0, raw, 1, 8);
                return raw;
            }

            private static double ReadDoubleBE(byte[] data, int offset)
            {
                byte[] num = new byte[8];
                Buffer.BlockCopy(data, offset, num, 0, 8);
                if (BitConverter.IsLittleEndian) Array.Reverse(num);
                return BitConverter.ToDouble(num, 0);
            }

            private static uint ReadU32BE(byte[] data, int offset)
            {
                return ((uint)data[offset] << 24)
                    | ((uint)data[offset + 1] << 16)
                    | ((uint)data[offset + 2] << 8)
                    | data[offset + 3];
            }

            private static ushort ReadU16BE(byte[] data, int offset)
            {
                return (ushort)((data[offset] << 8) | data[offset + 1]);
            }

            private static bool TryReadUtf8Short(byte[] data, ref int pos, out string value)
            {
                value = null;
                if (pos + 2 > data.Length) return false;
                int len = ReadU16BE(data, pos);
                pos += 2;
                if (pos + len > data.Length) return false;
                value = Encoding.UTF8.GetString(data, pos, len);
                pos += len;
                return true;
            }

            private static void WriteUtf8Short(Stream stream, string value)
            {
                byte[] encoded = Encoding.UTF8.GetBytes(value ?? string.Empty);
                if (encoded.Length > ushort.MaxValue)
                    throw new InvalidDataException("SOL string exceeds AMF0 uint16 length.");
                stream.WriteByte((byte)((encoded.Length >> 8) & 0xFF));
                stream.WriteByte((byte)(encoded.Length & 0xFF));
                stream.Write(encoded, 0, encoded.Length);
            }

            private static bool TrySkipAmf0Value(byte[] data, ref int pos, int depth)
            {
                if (depth > MaxAmfDepth || pos >= data.Length) return false;
                byte marker = data[pos++];
                switch (marker)
                {
                    case 0x00: // Number
                        if (pos + 8 > data.Length) return false;
                        pos += 8;
                        return true;
                    case 0x01: // Boolean
                        if (pos + 1 > data.Length) return false;
                        pos += 1;
                        return true;
                    case 0x02: // String
                        return TryReadUtf8Short(data, ref pos, out _);
                    case 0x03: // Object
                        return TrySkipAmf0ObjectMembers(data, ref pos, depth + 1);
                    case 0x05: // Null
                    case 0x06: // Undefined
                        return true;
                    case 0x07: // Reference
                        if (pos + 2 > data.Length) return false;
                        pos += 2;
                        return true;
                    case 0x08: // ECMA Array
                        if (pos + 4 > data.Length) return false;
                        pos += 4;
                        return TrySkipAmf0ObjectMembers(data, ref pos, depth + 1);
                    case 0x0A: // Strict Array
                        if (pos + 4 > data.Length) return false;
                        uint count = ReadU32BE(data, pos);
                        pos += 4;
                        if (count > 65536) return false;
                        for (uint i = 0; i < count; i++)
                        {
                            if (!TrySkipAmf0Value(data, ref pos, depth + 1)) return false;
                        }
                        return true;
                    case 0x0B: // Date
                        if (pos + 10 > data.Length) return false;
                        pos += 10;
                        return true;
                    case 0x0C: // Long String
                    case 0x0F: // XML Document
                        if (pos + 4 > data.Length) return false;
                        uint slen = ReadU32BE(data, pos);
                        pos += 4;
                        if (slen > (uint)(data.Length - pos)) return false;
                        pos += (int)slen;
                        return true;
                    case 0x10: // Typed Object
                        if (!TryReadUtf8Short(data, ref pos, out _)) return false;
                        return TrySkipAmf0ObjectMembers(data, ref pos, depth + 1);
                    default:
                        return false;
                }
            }

            private static bool TrySkipAmf0ObjectMembers(byte[] data, ref int pos, int depth)
            {
                if (depth > MaxAmfDepth) return false;
                while (pos < data.Length)
                {
                    if (pos + 3 <= data.Length && data[pos] == 0x00 && data[pos + 1] == 0x00 && data[pos + 2] == 0x09)
                    {
                        pos += 3;
                        return true;
                    }
                    if (!TryReadUtf8Short(data, ref pos, out _)) return false;
                    if (!TrySkipAmf0Value(data, ref pos, depth + 1)) return false;
                }
                return false;
            }
        }
    }
}
