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
    /// 协议（全部走 RegisterSync，保证 begin→chunk→end 顺序）：
    ///   begin:    { op:"begin", iconName:"...", hash:"..." }          → null（无响应）
    ///   chunk:    { op:"chunk", hash:"...", b64data:"..." }           → null（无响应）
    ///   end:      { op:"end", hash:"...", current:N, total:M }        → { success, action }
    ///   complete: { op:"complete", total:N, failed:M, failedNames:[] } → null（通知 INotchSink）
    /// </summary>
    public class IconBakeTask
    {
        private const int ICON_SIZE = 256;
        private const int BYTES_PER_PIXEL = 4; // ARGB

        private readonly string _iconsDir;
        private readonly string _manifestPath;
        private readonly INotchSink _notchSink;

        // 当前图标的累积 buffer（原始字节，chunk 到达时立即解码）
        private MemoryStream _currentBuffer;
        private string _currentIconName;
        private string _currentHash;

        // manifest: iconName → filename (e.g. "crc32hex.png")
        private Dictionary<string, string> _manifest;

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
            LoadManifest();
        }

        /// <summary>同步 handler，由 MessageRouter 在 socket 读线程上调用。</summary>
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
                    case "begin":    return HandleBegin(payload);
                    case "chunk":    return HandleChunk(payload);
                    case "end":      return HandleEnd(payload);
                    case "complete": return HandleComplete(payload);
                    default:         return BuildError("unknown op: " + op);
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
            _currentBuffer = new MemoryStream(ICON_SIZE * ICON_SIZE * BYTES_PER_PIXEL);
            LogManager.Log("[IconBakeTask] begin: " + _currentIconName + " (" + _currentHash + ")");
            return null; // 无响应
        }

        private string HandleChunk(JObject payload)
        {
            string b64data = payload.Value<string>("b64data");
            if (b64data != null && _currentBuffer != null)
            {
                // 每个 chunk 独立解码，避免 base64 padding 拼接问题
                byte[] decoded = Convert.FromBase64String(b64data);
                _currentBuffer.Write(decoded, 0, decoded.Length);
            }
            return null; // 无响应
        }

        private string HandleEnd(JObject payload)
        {
            string hash = payload.Value<string>("hash");
            int current = payload.Value<int>("current");
            int total = payload.Value<int>("total");

            if (_currentBuffer == null || _currentHash != hash)
                return BuildError("no matching begin for hash: " + hash);

            // 确保目录存在
            if (!Directory.Exists(_iconsDir))
                Directory.CreateDirectory(_iconsDir);

            string action;
            string iconNameForLog = _currentIconName; // 保存，finally 前使用
            try
            {
                // 从 MemoryStream 获取已解码的原始 ARGB 字节
                byte[] rawArgb = _currentBuffer.ToArray();
                int expectedLen = ICON_SIZE * ICON_SIZE * BYTES_PER_PIXEL;
                if (rawArgb.Length != expectedLen)
                    return BuildError("pixel data length mismatch: expected " + expectedLen + " got " + rawArgb.Length);

                // ARGB → BGRA 字节序转换 (GDI+ 在 little-endian 上用 BGRA)
                byte[] bgra = new byte[rawArgb.Length];
                for (int i = 0; i < rawArgb.Length; i += 4)
                {
                    bgra[i + 0] = rawArgb[i + 3]; // B ← rawArgb[3]
                    bgra[i + 1] = rawArgb[i + 2]; // G ← rawArgb[2]
                    bgra[i + 2] = rawArgb[i + 1]; // R ← rawArgb[1]
                    bgra[i + 3] = rawArgb[i + 0]; // A ← rawArgb[0]
                }

                // 编码为 PNG
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
                    byte[] existing = File.ReadAllBytes(filePath);
                    if (ByteArrayEqual(existing, newPng))
                    {
                        action = "unchanged";
                        _unchanged++;
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

                // 更新 manifest
                _manifest[_currentIconName] = filename;
                SaveManifest();

                // 检测 CRC32 冲突：不同 iconName 映射到同一 hash
                // （概率极低但防御性检查）
                foreach (var kvp in _manifest)
                {
                    if (kvp.Value == filename && kvp.Key != _currentIconName)
                    {
                        LogManager.Log("[IconBakeTask] CRC32 collision: '" + _currentIconName +
                                       "' and '" + kvp.Key + "' both map to " + filename);
                    }
                }
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

            // 进度通知 + 日志
            LogManager.Log("[IconBakeTask] " + current + "/" + total + " " + action + ": " + iconNameForLog);
            if (_notchSink != null)
            {
                string label = "烘焙 " + current + "/" + total;
                _notchSink.SetStatusItem("icon_bake", label, iconNameForLog ?? hash, Color.Cyan);
            }

            // 响应
            JObject resp = new JObject();
            resp["success"] = true;
            resp["task"] = "icon_bake";
            resp["action"] = action;
            return resp.ToString(Formatting.None);
        }

        private string HandleComplete(JObject payload)
        {
            int total = payload.Value<int>("total");
            int failed = payload.Value<int>("failed");

            string summary = "烘焙完成: " + total + " 个图标";
            if (_created > 0) summary += ", 新增 " + _created;
            if (_updated > 0) summary += ", 更新 " + _updated;
            if (_unchanged > 0) summary += ", 未变 " + _unchanged;
            if (failed > 0) summary += ", 失败 " + failed;

            LogManager.Log("[IconBakeTask] " + summary);

            if (_notchSink != null)
            {
                _notchSink.ClearStatusItem("icon_bake");
                _notchSink.AddNotice("icon_bake", summary, Color.LimeGreen);
            }

            // 重置统计
            _created = 0;
            _updated = 0;
            _unchanged = 0;

            return null; // 无响应
        }

        // ================================================================
        // manifest 管理
        // ================================================================

        private void LoadManifest()
        {
            _manifest = new Dictionary<string, string>();
            if (File.Exists(_manifestPath))
            {
                try
                {
                    string json = File.ReadAllText(_manifestPath, Encoding.UTF8);
                    JObject obj = JObject.Parse(json);
                    foreach (var kvp in obj)
                    {
                        _manifest[kvp.Key] = kvp.Value.ToString();
                    }
                }
                catch (Exception ex)
                {
                    LogManager.Log("[IconBakeTask] Failed to load manifest: " + ex.Message);
                }
            }
        }

        private void SaveManifest()
        {
            try
            {
                JObject obj = new JObject();
                foreach (var kvp in _manifest)
                {
                    obj[kvp.Key] = kvp.Value;
                }
                File.WriteAllText(_manifestPath, obj.ToString(Formatting.Indented), Encoding.UTF8);
            }
            catch (Exception ex)
            {
                LogManager.Log("[IconBakeTask] Failed to save manifest: " + ex.Message);
            }
        }

        // ================================================================
        // CRC32 (ISO 3309, polynomial 0xEDB88320)
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

        /// <summary>
        /// 计算字符串的 CRC32（UTF-8 编码后），返回 8 位十六进制字符串。
        /// 用于验证 AS2 端传来的 hash 一致性。
        /// </summary>
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

        // ================================================================
        // 辅助
        // ================================================================

        private static bool ByteArrayEqual(byte[] a, byte[] b)
        {
            if (a.Length != b.Length) return false;
            for (int i = 0; i < a.Length; i++)
            {
                if (a[i] != b[i]) return false;
            }
            return true;
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
