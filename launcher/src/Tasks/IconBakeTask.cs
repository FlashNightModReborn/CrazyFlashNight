using System;
using System.Collections.Generic;
using System.Drawing;
using System.Drawing.Imaging;
using System.IO;
using System.Runtime.InteropServices;
using System.Text;
using Newtonsoft.Json;
using Newtonsoft.Json.Linq;
using CF7Launcher.Guardian;

namespace CF7Launcher.Tasks
{
    /// <summary>
    /// icon_bake sync handler：Flash AS2 端逐个光栅化矢量图标，
    /// 以 base64 编码分块传输像素数据，C# 端解码并保存为 256x256 PNG。
    ///
    /// 每个图标导出两帧：hash_1.png (图标) + hash_2.png (掉落物)。
    /// 全量烘焙完成后清理不再存在的图标（manifest 收敛）。
    ///
    /// 协议（全部走 RegisterSync，保证 begin→chunk→end 顺序）：
    ///   begin:    { op:"begin", iconName, hash, contentX, contentY, contentW, contentH }
    ///   chunk:    { op:"chunk", hash, b64data }
    ///   end:      { op:"end", hash, current, total }
    ///   complete: { op:"complete", total, failed, failedNames, fullBake }
    ///
    /// contentRect 裁剪：AS2 端用 getColorBoundsRect 裁剪透明区域，
    /// 只传输有内容的像素，C# 端在 256×256 画布对应位置重建。
    /// </summary>
    public class IconBakeTask
    {
        private const int ICON_SIZE = 256;
        private const int BYTES_PER_PIXEL = 4; // 32bpp
        // 阈值来源：全量烘焙实测 p99（ChangedPixels≈14872 / TotalDelta≈362K / AlphaPixels≈1001），各留 ~20-25% 余量。
        // SingleChannelDelta=255 当前等于关闭该门（byte 上限，判定恒假）：保留字段作为预留开关，
        // 后续若能从源头抑制大 delta（如统一编码器或渲染器），再收紧为有效值。
        private const int MICRO_DIFF_MAX_CHANGED_PIXELS = 18000;
        private const int MICRO_DIFF_MAX_SINGLE_CHANNEL_DELTA = 255;
        private const long MICRO_DIFF_MAX_TOTAL_CHANNEL_DELTA = 450000;
        private const int MICRO_DIFF_MAX_CHANGED_ALPHA_PIXELS = 1250;

        private readonly string _iconsDir;
        private readonly string _manifestPath;
        private readonly INotchSink _notchSink;

        // 当前图标的累积 buffer
        private MemoryStream _currentBuffer;
        private string _currentIconName;
        private string _currentHash;

        // 当前帧的 contentRect（由 begin 传入）
        private int _contentX;
        private int _contentY;
        private int _contentW;
        private int _contentH;

        // manifest: iconName → JObject { "f1": "hash_1.png", "f2": "hash_2.png" }
        private Dictionary<string, JObject> _manifest;

        // 本轮出现的 iconName 集合（全量烘焙时用于清理判断）
        private HashSet<string> _seenIcons;

        // 统计
        private int _created;
        private int _updated;
        private int _unchanged;

        // CRC32 查表
        private static readonly uint[] CrcTable = BuildCrcTable();

        public IconBakeTask(string projectRoot, INotchSink notchSink)
        {
            _iconsDir = Path.Combine(projectRoot, "launcher", "web", "icons");
            _manifestPath = Path.Combine(_iconsDir, "manifest.json");
            _notchSink = notchSink;
            _seenIcons = new HashSet<string>();
            LoadManifest();
        }

        public string Handle(JObject message)
        {
            try
            {
                JObject payload = message.Value<JObject>("payload");
                if (payload == null)
                    return BuildError("missing payload");

                string op = payload.Value<string>("op");
                switch (op)
                {
                    case "begin":       return HandleBegin(payload);
                    case "chunk":       return HandleChunk(payload);
                    case "end":         return HandleEnd(payload);
                    case "purge_frame": return HandlePurgeFrame(payload);
                    case "complete":    return HandleComplete(payload);
                    default:            return BuildError("unknown op: " + op);
                }
            }
            catch (Exception ex)
            {
                LogManager.Log("[IconBakeTask] Exception: " + ex);
                return BuildError("exception: " + ex.Message);
            }
        }

        // ================================================================
        // op handlers
        // ================================================================

        private string HandleBegin(JObject payload)
        {
            _currentIconName = payload.Value<string>("iconName");
            _currentHash = payload.Value<string>("hash");

            // 解析 contentRect（AS2 端 getColorBoundsRect 裁剪结果）
            _contentX = payload.Value<int?>("contentX") ?? 0;
            _contentY = payload.Value<int?>("contentY") ?? 0;
            _contentW = payload.Value<int?>("contentW") ?? ICON_SIZE;
            _contentH = payload.Value<int?>("contentH") ?? ICON_SIZE;

            _currentBuffer = new MemoryStream(_contentW * _contentH * BYTES_PER_PIXEL);

            // 记录本轮出现的 icon
            _seenIcons.Add(_currentIconName);

            return null;
        }

        private string HandleChunk(JObject payload)
        {
            string b64data = payload.Value<string>("b64data");
            if (b64data != null && _currentBuffer != null)
            {
                byte[] decoded = Convert.FromBase64String(b64data);
                _currentBuffer.Write(decoded, 0, decoded.Length);
            }
            return null;
        }

        private string HandleEnd(JObject payload)
        {
            string hash = payload.Value<string>("hash");
            int current = payload.Value<int>("current");
            int total = payload.Value<int>("total");

            if (_currentBuffer == null || _currentHash != hash)
                return BuildError("no matching begin for hash: " + hash);

            if (!Directory.Exists(_iconsDir))
                Directory.CreateDirectory(_iconsDir);

            string action;
            string iconNameForLog = _currentIconName;

            // 从 hash 提取帧标识：hash 格式为 "crc32hex_1" 或 "crc32hex_2"
            string frameKey = "f1";
            if (hash.Length > 2 && hash[hash.Length - 2] == '_')
            {
                frameKey = "f" + hash[hash.Length - 1];
            }

            try
            {
                byte[] rawArgb = _currentBuffer.ToArray();
                int expectedLen = _contentW * _contentH * BYTES_PER_PIXEL;
                if (rawArgb.Length != expectedLen)
                    return BuildError("pixel data length mismatch: expected " + expectedLen + " got " + rawArgb.Length
                        + " (contentRect=" + _contentX + "," + _contentY + "," + _contentW + "," + _contentH + ")");

                // 在 256×256 BGRA 画布的 contentRect 位置填充像素
                byte[] bgra = new byte[ICON_SIZE * ICON_SIZE * BYTES_PER_PIXEL];
                int srcIdx = 0;
                int stride = ICON_SIZE * BYTES_PER_PIXEL;
                for (int row = 0; row < _contentH; row++)
                {
                    int dstRowStart = (_contentY + row) * stride + _contentX * BYTES_PER_PIXEL;
                    for (int col = 0; col < _contentW; col++)
                    {
                        int di = dstRowStart + col * BYTES_PER_PIXEL;
                        // ARGB → BGRA
                        bgra[di + 0] = rawArgb[srcIdx + 3]; // B
                        bgra[di + 1] = rawArgb[srcIdx + 2]; // G
                        bgra[di + 2] = rawArgb[srcIdx + 1]; // R
                        bgra[di + 3] = rawArgb[srcIdx + 0]; // A
                        srcIdx += BYTES_PER_PIXEL;
                    }
                }

                byte[] newPng;
                using (Bitmap bmp = new Bitmap(ICON_SIZE, ICON_SIZE, PixelFormat.Format32bppArgb))
                {
                    BitmapData bmpData = bmp.LockBits(
                        new Rectangle(0, 0, ICON_SIZE, ICON_SIZE),
                        ImageLockMode.WriteOnly,
                        PixelFormat.Format32bppArgb);
                    Marshal.Copy(bgra, 0, bmpData.Scan0, bgra.Length);
                    bmp.UnlockBits(bmpData);

                    using (MemoryStream ms = new MemoryStream())
                    {
                        bmp.Save(ms, ImageFormat.Png);
                        newPng = ms.ToArray();
                    }
                }

                // 写前比较
                string filename = hash + ".png";
                string filePath = Path.Combine(_iconsDir, filename);

                if (File.Exists(filePath))
                {
                    IconBakePixelDiffStats diffStats;
                    if (ShouldTreatExistingPngAsUnchanged(filePath, bgra, out diffStats))
                    {
                        action = "unchanged";
                        _unchanged++;
                        if (diffStats.IsMicroDiff)
                        {
                            LogManager.Log("[IconBakeTask] ignored microdiff: " + iconNameForLog
                                + " [" + frameKey + "] changedPixels=" + diffStats.ChangedPixels
                                + " maxDelta=" + diffStats.MaxChannelDelta
                                + " totalDelta=" + diffStats.TotalChannelDelta
                                + " alphaPixels=" + diffStats.ChangedAlphaPixels);
                        }
                    }
                    else
                    {
                        File.WriteAllBytes(filePath, newPng);
                        action = "updated";
                        _updated++;
                    }
                }
                else
                {
                    File.WriteAllBytes(filePath, newPng);
                    action = "created";
                    _created++;
                }

                // 更新 manifest（每个 iconName 下按帧存储）
                JObject entry;
                if (_manifest.ContainsKey(_currentIconName))
                {
                    entry = _manifest[_currentIconName];
                }
                else
                {
                    entry = new JObject();
                    _manifest[_currentIconName] = entry;
                }
                entry[frameKey] = filename;
            }
            catch (Exception ex)
            {
                return BuildError("save failed: " + ex.Message);
            }
            finally
            {
                if (_currentBuffer != null) _currentBuffer.Dispose();
                _currentBuffer = null;
                _currentIconName = null;
                _currentHash = null;
            }

            LogManager.Log("[IconBakeTask] " + current + "/" + total + " " + action + ": " + iconNameForLog + " [" + frameKey + "]");
            if (_notchSink != null)
            {
                string label = "烘焙 " + current + "/" + total;
                _notchSink.SetStatusItem("icon_bake", label, iconNameForLog ?? hash, Color.Cyan);
            }

            JObject resp = new JObject();
            resp["success"] = true;
            resp["task"] = "icon_bake";
            resp["action"] = action;
            return resp.ToString(Formatting.None);
        }

        /// <summary>
        /// 删除指定图标的某一帧（如图标从 2 帧变为 1 帧时清除残留 f2）。
        /// </summary>
        private string HandlePurgeFrame(JObject payload)
        {
            string iconName = payload.Value<string>("iconName");
            string frameKey = payload.Value<string>("frameKey");

            if (iconName != null && frameKey != null && _manifest.ContainsKey(iconName))
            {
                JObject entry = _manifest[iconName];
                JToken fileToken = entry[frameKey];
                if (fileToken != null)
                {
                    string filename = fileToken.ToString();
                    string path = Path.Combine(_iconsDir, filename);
                    if (File.Exists(path))
                    {
                        try { File.Delete(path); }
                        catch { }
                        LogManager.Log("[IconBakeTask] purge_frame: " + iconName + " [" + frameKey + "] → " + filename);
                    }
                    entry.Remove(frameKey);
                }
            }

            // 记录本轮出现
            if (iconName != null) _seenIcons.Add(iconName);

            return null;
        }

        private string HandleComplete(JObject payload)
        {
            int total = payload.Value<int>("total");
            int failed = payload.Value<int>("failed");
            bool fullBake = payload.Value<bool>("fullBake");

            // 全量烘焙时清理失效图标
            int purgedManifest = 0;
            int purgedFiles = 0;
            if (fullBake)
            {
                // 1. 删除 manifest 中不在本轮出现的条目，及其 PNG 文件
                List<string> toRemove = new List<string>();
                foreach (var kvp in _manifest)
                {
                    if (!_seenIcons.Contains(kvp.Key))
                    {
                        toRemove.Add(kvp.Key);
                        // 删除该条目关联的所有 PNG
                        JObject entry = kvp.Value;
                        foreach (var frame in entry)
                        {
                            string filename = frame.Value.ToString();
                            string path = Path.Combine(_iconsDir, filename);
                            if (File.Exists(path))
                            {
                                try { File.Delete(path); purgedFiles++; }
                                catch { }
                            }
                        }
                    }
                }
                foreach (string key in toRemove)
                {
                    _manifest.Remove(key);
                    purgedManifest++;
                }

                // 2. 扫描目录中的孤儿 PNG（不在任何 manifest 条目中）
                HashSet<string> allManifestFiles = new HashSet<string>();
                foreach (var kvp in _manifest)
                {
                    foreach (var frame in kvp.Value)
                    {
                        allManifestFiles.Add(frame.Value.ToString());
                    }
                }
                allManifestFiles.Add("manifest.json"); // 不要删 manifest 自身
                try
                {
                    foreach (string filePath in Directory.GetFiles(_iconsDir))
                    {
                        string fname = Path.GetFileName(filePath);
                        if (!allManifestFiles.Contains(fname))
                        {
                            try { File.Delete(filePath); purgedFiles++; }
                            catch { }
                        }
                    }
                }
                catch { }

                // 保存清理后的 manifest
                SaveManifest();
            }
            else
            {
                // 部分烘焙只保存，不清理
                SaveManifest();
            }

            string summary = "烘焙完成: " + total + " 个图标";
            if (_created > 0) summary += ", 新增 " + _created;
            if (_updated > 0) summary += ", 更新 " + _updated;
            if (_unchanged > 0) summary += ", 未变 " + _unchanged;
            if (failed > 0) summary += ", 失败 " + failed;
            if (purgedManifest > 0) summary += ", 清理 " + purgedManifest + " 条目/" + purgedFiles + " 文件";

            LogManager.Log("[IconBakeTask] " + summary);

            if (_notchSink != null)
            {
                _notchSink.ClearStatusItem("icon_bake");
                _notchSink.AddNotice("icon_bake", summary, Color.LimeGreen);
            }

            // 重置统计和集合
            _created = 0;
            _updated = 0;
            _unchanged = 0;
            _seenIcons.Clear();

            return null;
        }

        // ================================================================
        // manifest 管理（新格式：iconName → { f1: "hash_1.png", f2: "hash_2.png" }）
        // ================================================================

        private void LoadManifest()
        {
            _manifest = new Dictionary<string, JObject>();
            if (!File.Exists(_manifestPath)) return;

            try
            {
                string json = File.ReadAllText(_manifestPath, Encoding.UTF8);
                JObject root = JObject.Parse(json);
                foreach (var kvp in root)
                {
                    JToken val = kvp.Value;
                    if (val.Type == JTokenType.Object)
                    {
                        // 新格式
                        _manifest[kvp.Key] = (JObject)val;
                    }
                    else if (val.Type == JTokenType.String)
                    {
                        // 兼容旧格式：iconName → "hash.png"
                        // 迁移为新格式，旧文件视为 f1
                        JObject entry = new JObject();
                        entry["f1"] = val.ToString();
                        _manifest[kvp.Key] = entry;
                    }
                }
            }
            catch (Exception ex)
            {
                LogManager.Log("[IconBakeTask] Failed to load manifest: " + ex.Message);
            }
        }

        private void SaveManifest()
        {
            try
            {
                JObject root = new JObject();
                foreach (var kvp in _manifest)
                {
                    root[kvp.Key] = kvp.Value;
                }
                File.WriteAllText(_manifestPath, root.ToString(Formatting.Indented), Encoding.UTF8);
            }
            catch (Exception ex)
            {
                LogManager.Log("[IconBakeTask] Failed to save manifest: " + ex.Message);
            }
        }

        // ================================================================
        // CRC32 / 辅助
        // ================================================================

        private static uint[] BuildCrcTable()
        {
            uint[] table = new uint[256];
            for (uint i = 0; i < 256; i++)
            {
                uint c = i;
                for (int j = 0; j < 8; j++)
                {
                    if ((c & 1) != 0)
                        c = 0xEDB88320u ^ (c >> 1);
                    else
                        c = c >> 1;
                }
                table[i] = c;
            }
            return table;
        }

        public static string ComputeCrc32(string input)
        {
            byte[] bytes = Encoding.UTF8.GetBytes(input);
            uint crc = 0xFFFFFFFF;
            for (int i = 0; i < bytes.Length; i++)
            {
                crc = CrcTable[(crc ^ bytes[i]) & 0xFF] ^ (crc >> 8);
            }
            crc ^= 0xFFFFFFFF;
            return crc.ToString("x8");
        }

        public struct IconBakePixelDiffStats
        {
            public bool ExactPixels;
            public bool IsMicroDiff;
            public int ChangedPixels;
            public int ChangedAlphaPixels;
            public int MaxChannelDelta;
            public long TotalChannelDelta;
        }

        public static bool ShouldTreatExistingPngAsUnchanged(
            string existingPngPath,
            byte[] newBgra,
            out IconBakePixelDiffStats stats)
        {
            stats = new IconBakePixelDiffStats();

            byte[] existingBgra;
            if (!TryReadPngBgra(existingPngPath, out existingBgra))
                return false;

            if (newBgra == null || existingBgra.Length != newBgra.Length)
                return false;

            for (int i = 0; i < existingBgra.Length; i += BYTES_PER_PIXEL)
            {
                int bDelta = Math.Abs(existingBgra[i] - newBgra[i]);
                int gDelta = Math.Abs(existingBgra[i + 1] - newBgra[i + 1]);
                int rDelta = Math.Abs(existingBgra[i + 2] - newBgra[i + 2]);
                int aDelta = Math.Abs(existingBgra[i + 3] - newBgra[i + 3]);

                if (bDelta == 0 && gDelta == 0 && rDelta == 0 && aDelta == 0)
                    continue;

                stats.ChangedPixels++;
                if (aDelta != 0) stats.ChangedAlphaPixels++;

                int maxDelta = bDelta;
                if (gDelta > maxDelta) maxDelta = gDelta;
                if (rDelta > maxDelta) maxDelta = rDelta;
                if (aDelta > maxDelta) maxDelta = aDelta;
                if (maxDelta > stats.MaxChannelDelta) stats.MaxChannelDelta = maxDelta;

                stats.TotalChannelDelta += bDelta + gDelta + rDelta + aDelta;

                if (stats.ChangedPixels > MICRO_DIFF_MAX_CHANGED_PIXELS
                    || stats.MaxChannelDelta > MICRO_DIFF_MAX_SINGLE_CHANNEL_DELTA
                    || stats.TotalChannelDelta > MICRO_DIFF_MAX_TOTAL_CHANNEL_DELTA
                    || stats.ChangedAlphaPixels > MICRO_DIFF_MAX_CHANGED_ALPHA_PIXELS)
                {
                    return false;
                }
            }

            if (stats.ChangedPixels == 0)
            {
                stats.ExactPixels = true;
                return true;
            }

            stats.IsMicroDiff = true;
            return true;
        }

        private static bool TryReadPngBgra(string filePath, out byte[] bgra)
        {
            bgra = null;

            try
            {
                using (Bitmap bmp = new Bitmap(filePath))
                {
                    if (bmp.Width != ICON_SIZE || bmp.Height != ICON_SIZE)
                        return false;

                    bgra = new byte[ICON_SIZE * ICON_SIZE * BYTES_PER_PIXEL];
                    BitmapData data = null;
                    try
                    {
                        data = bmp.LockBits(
                            new Rectangle(0, 0, ICON_SIZE, ICON_SIZE),
                            ImageLockMode.ReadOnly,
                            PixelFormat.Format32bppArgb);

                        int sourceStride = data.Stride;
                        int absStride = Math.Abs(sourceStride);
                        byte[] source = new byte[absStride * ICON_SIZE];
                        Marshal.Copy(data.Scan0, source, 0, source.Length);

                        int targetStride = ICON_SIZE * BYTES_PER_PIXEL;
                        for (int y = 0; y < ICON_SIZE; y++)
                        {
                            int sourceRow = sourceStride > 0
                                ? y * absStride
                                : (ICON_SIZE - 1 - y) * absStride;
                            Buffer.BlockCopy(source, sourceRow, bgra, y * targetStride, targetStride);
                        }
                    }
                    finally
                    {
                        if (data != null) bmp.UnlockBits(data);
                    }
                }

                return true;
            }
            catch (Exception ex)
            {
                LogManager.Log("[IconBakeTask] Failed to read existing PNG for pixel compare: " + ex.Message);
                bgra = null;
                return false;
            }
        }

        private static string BuildError(string error)
        {
            JObject obj = new JObject();
            obj["success"] = false;
            obj["task"] = "icon_bake";
            obj["error"] = error;
            return obj.ToString(Formatting.None);
        }
    }
}
