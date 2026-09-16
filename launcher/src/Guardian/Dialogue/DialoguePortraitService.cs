using System;
using System.Collections.Generic;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Drawing.Imaging;
using System.IO;
using System.Linq;
using System.Security.Cryptography;
using System.Text;
using System.Threading;
using System.Threading.Tasks;
using Newtonsoft.Json;
using Newtonsoft.Json.Linq;
using CF7Launcher.Guardian.Hud;
using CF7Launcher.Guardian.Hud.Dialogue;

namespace CF7Launcher.Guardian.Dialogue
{
    /// <summary>大立绘独立于 256px 战利品图标协议。缓存只保存可重建的像素。</summary>
    internal sealed class DialoguePortraitService : IDisposable
    {
        internal const int RenderSize = 768;
        // fit 后位图典型 944×704×4 ≈ 2.7MB、最大 1536px ≈ 4MB，纸娃娃 768² ≈ 2.25MB；
        // 静态表情/配图/纸娃娃共享同一 LRU。24MB 只容 6-8 张，对话中换表情即驱逐、
        // 回切旧表情被迫重解码；64MB 容约 16-24 张，覆盖一段对话的多角色多表情工作集。
        private const int CacheLimit = 64 * 1024 * 1024;
        private readonly string _root;
        private readonly string _portraitRoot;
        private readonly JObject _manifest;
        private readonly string _assetVersion;
        private readonly Func<string, bool> _postToWeb;
        private readonly object _gate = new object();
        private readonly Dictionary<string, Bitmap> _cache = new Dictionary<string, Bitmap>();
        private readonly LinkedList<string> _lru = new LinkedList<string>();
        private readonly Dictionary<string, Pending> _pending = new Dictionary<string, Pending>();
        // 解码并发上限 3：每次 decode 走独立的 SKData/SKCodec 实例（Skia 每实例线程安全），
        // ReadAndFit 的 GDI+ 操作都作用在各自新建的 Bitmap 上，_cache/_pending 均有 _gate 保护。
        private readonly SemaphoreSlim _decodeQueue = new SemaphoreSlim(3, 3);
        private readonly DialoguePortraitDiskCache _disk;
        private long _cacheBytes;
        private bool _disposed;

        private sealed class Pending
        {
            internal string Key;
            internal string RequestId;
            internal readonly List<Action<Bitmap>> Callbacks = new List<Action<Bitmap>>();
            internal System.Threading.Timer Timer;
        }

        internal DialoguePortraitService(string root, Func<string, bool> postToWeb)
            : this(root, postToWeb, root) { }

        internal DialoguePortraitService(string root, Func<string, bool> postToWeb, string cacheRoot)
        {
            _root = Path.GetFullPath(root);
            _portraitRoot = Path.Combine(_root, "launcher", "web", "assets", "dialogue-portraits");
            _postToWeb = postToWeb;
            try { _manifest = JObject.Parse(File.ReadAllText(Path.Combine(_portraitRoot, "manifest.json"))); }
            catch (Exception ex) { LogManager.Log("[NativeDialogue] portrait manifest: " + ex.Message); _manifest = new JObject(); }
            _assetVersion = ComputeRenderAssetVersion(_root);
            _disk = new DialoguePortraitDiskCache(cacheRoot);
        }

        /// <summary>
        /// 纸娃娃渲染资产版本：dressup manifest + 渲染器源码（asset-timeline /
        /// dressup-doll-renderer / live-portrait / live-portrait-bake）联合哈希。
        /// 磁盘缓存跨进程复用同一 key，渲染器任一变更必须让旧 PNG 全部 miss。
        /// </summary>
        internal static string ComputeRenderAssetVersion(string root)
        {
            using (var sha = SHA256.Create())
            {
                HashFile(sha, Path.Combine(root, "launcher", "web", "assets", "dressup", "manifest.json"));
                HashFile(sha, Path.Combine(root, "launcher", "web", "modules", "asset-timeline.js"));
                HashFile(sha, Path.Combine(root, "launcher", "web", "modules", "dressup-doll-renderer.js"));
                HashFile(sha, Path.Combine(root, "launcher", "web", "modules", "dialogue", "live-portrait.js"));
                HashFile(sha, Path.Combine(root, "launcher", "web", "modules", "dialogue", "live-portrait-bake.js"));
                sha.TransformFinalBlock(new byte[0], 0, 0);
                return Convert.ToHexString(sha.Hash).ToLowerInvariant();
            }
        }

        private static void HashFile(SHA256 sha, string path)
        {
            byte[] name = Encoding.UTF8.GetBytes(Path.GetFileName(path) + "\n");
            sha.TransformBlock(name, 0, name.Length, null, 0);
            byte[] data;
            try { data = File.Exists(path) ? File.ReadAllBytes(path) : Encoding.UTF8.GetBytes("missing:" + Path.GetFileName(path)); }
            catch { data = Encoding.UTF8.GetBytes("unreadable:" + Path.GetFileName(path)); }
            sha.TransformBlock(data, 0, data.Length, null, 0);
        }

        internal void LoadPortrait(NativeDialogueFrame frame, JObject appearance, Action<Bitmap> ready)
        {
            if (frame.IsDoll) { RequestDoll(frame, appearance, ready); return; }
            string key = "static:" + frame.PortraitKey + ":" + frame.Expression;
            LoadCached(key, () => LoadStatic(frame.PortraitKey, frame.Expression), ready);
        }

        /// <summary>
        /// 元数据感知版：回调收到 (位图, 作者取景矩形)。外部 SWF 的取景 = LoadStatic
        /// 稳定 crop（union∩window）÷ manifest.zoom 还原的舞台逻辑矩形，与位图一一对应；
        /// 纸娃娃/sprite-natural/未知来源 → null（widget 走各自 fit 规则）。
        /// 矩形在调用时同步从 manifest 解析，与同 key 的加载器同源确定性一致。
        /// </summary>
        internal void LoadPortrait(NativeDialogueFrame frame, JObject appearance,
            Action<Bitmap, RectangleF?> ready)
        {
            if (frame.IsDoll)
            {
                RequestDoll(frame, appearance, bmp => ready(bmp, null));
                return;
            }
            string key = "static:" + frame.PortraitKey + ":" + frame.Expression;
            RectangleF? stageRect = ResolveStaticStageRect(frame.PortraitKey);
            LoadCached(key, () => LoadStatic(frame.PortraitKey, frame.Expression),
                bmp => ready(bmp, stageRect));
        }

        /// <summary>外部 SWF 立绘的舞台逻辑取景（烘焙像素 crop ÷ manifest.zoom）；
        /// 非 external-swf / sprite-natural / 无数据 → null。</summary>
        private RectangleF? ResolveStaticStageRect(string portraitKey)
        {
            try
            {
                JObject entry = FindStaticEntry(portraitKey);
                if (entry == null) return null;
                if (entry.Value<string>("source") != "external-swf"
                    || entry.Value<string>("coordinateSpace") == "sprite-natural")
                    return null;
                var expressions = entry["expressions"] as JObject;
                if (expressions == null) return null;
                RectangleF? crop = ComputeStaticCrop(entry, expressions);
                if (!crop.HasValue || crop.Value.Width <= 0 || crop.Value.Height <= 0) return null;
                float zoom = _manifest.Value<float?>("zoom") ?? 1f;
                if (zoom <= 0) zoom = 1f;
                RectangleF c = crop.Value;
                return new RectangleF(c.X / zoom, c.Y / zoom, c.Width / zoom, c.Height / zoom);
            }
            catch { return null; }
        }

        internal void LoadSceneImage(string relative, Action<Bitmap> ready)
        {
            string path = SafeChild(_root, relative);
            string imageRoot = Path.Combine(_root, "flashswf", "images") + Path.DirectorySeparatorChar;
            if (path == null || !path.StartsWith(imageRoot, StringComparison.OrdinalIgnoreCase)) return;
            LoadCached("scene:" + relative, () => ReadAndFit(path, null), ready);
        }

        private void LoadCached(string key, Func<Bitmap> loader, Action<Bitmap> ready)
        {
            Task.Run(async () =>
            {
                Bitmap result = GetCached(key);
                if (result != null) { ready(result); return; }
                await _decodeQueue.WaitAsync().ConfigureAwait(false);
                try
                {
                    lock (_gate) { if (_disposed) return; }
                    result = GetCached(key);
                    if (result == null)
                    {
                        using (Bitmap loaded = loader())
                        {
                            if (loaded == null) return;
                            PutCached(key, loaded);
                            result = (Bitmap)loaded.Clone();
                        }
                    }
                }
                catch (Exception ex) { LogManager.Log("[NativeDialogue] image load: " + ex.Message); }
                finally { _decodeQueue.Release(); }
                if (result != null) ready(result);
            });
        }

        private JObject FindStaticEntry(string key)
        {
            var entries = _manifest["entries"] as JObject;
            var entry = entries?[key] as JObject;
            if (entry == null)
            {
                string alias = _manifest["aliases"]?[key]?.Value<string>();
                if (alias != null) entry = entries?[alias] as JObject;
            }
            return entry;
        }

        /// <summary>LoadStatic 的稳定取景：全表情 bounds 并集；external-swf（非
        /// sprite-natural）再∩作者遮罩窗。返回烘焙像素坐标矩形；无 bounds → null
        /// （ReadAndFit 用整图）。</summary>
        private RectangleF? ComputeStaticCrop(JObject entry, JObject expressions)
        {
            RectangleF union = RectangleF.Empty;
            foreach (JProperty property in expressions.Properties())
            {
                JObject bounds = property.Value["bounds"] as JObject;
                if (bounds == null) continue;
                RectangleF box = Rect(bounds, 1);
                if (box.Width > 0 && box.Height > 0)
                    union = union.IsEmpty ? box : RectangleF.Union(union, box);
            }
            // 同一人物全部表情共用取景，移除无内容的舞台留白，不随单句缩放跳动。
            // 外部 SWF 再与作者遮罩相交，遮罩下未完成的底座不能重新露出。
            if (entry.Value<string>("source") == "external-swf"
                && entry.Value<string>("coordinateSpace") != "sprite-natural")
            {
                JObject window = _manifest["portraitWindow"]?["external-swf"] as JObject;
                // manifest 窗口已经包含导出倍率，不能再次乘 zoom。
                if (window != null)
                    return union.IsEmpty ? Rect(window, 1) : RectangleF.Intersect(union, Rect(window, 1));
            }
            return union.IsEmpty ? (RectangleF?)null : union;
        }

        private Bitmap LoadStatic(string key, string expression)
        {
            JObject entry = FindStaticEntry(key);
            if (entry == null) return null;
            var expressions = entry["expressions"] as JObject;
            var selected = expressions?[expression] as JObject
                ?? expressions?[entry.Value<string>("defaultExpression") ?? "普通"] as JObject;
            if (selected == null) return null;
            string path = SafeChild(_portraitRoot, selected.Value<string>("uri"));
            if (path == null || !File.Exists(path)) return null;
            RectangleF? crop = ComputeStaticCrop(entry, expressions);
            return ReadAndFit(path, crop);
        }

        private static RectangleF Rect(JObject box, float scale)
        {
            return new RectangleF((box.Value<float?>("x") ?? 0) * scale,
                (box.Value<float?>("y") ?? 0) * scale,
                (box.Value<float?>("width") ?? 0) * scale,
                (box.Value<float?>("height") ?? 0) * scale);
        }

        private static Bitmap ReadAndFit(string path, RectangleF? crop)
        {
            using (Bitmap source = MapHudImageDecoder.LoadBitmap(path, 4096))
            {
                RectangleF area = RectangleF.Intersect(crop ?? new RectangleF(0, 0, source.Width, source.Height),
                    new RectangleF(0, 0, source.Width, source.Height));
                if (area.Width <= 0 || area.Height <= 0) return null;
                float scale = Math.Min(1, 1536f / Math.Max(area.Width, area.Height));
                var result = new Bitmap(Math.Max(1, (int)Math.Ceiling(area.Width * scale)),
                    Math.Max(1, (int)Math.Ceiling(area.Height * scale)), PixelFormat.Format32bppPArgb);
                using (Graphics g = Graphics.FromImage(result))
                {
                    g.CompositingMode = CompositingMode.SourceCopy;
                    g.InterpolationMode = InterpolationMode.HighQualityBicubic;
                    g.PixelOffsetMode = PixelOffsetMode.HighQuality;
                    g.DrawImage(source, new Rectangle(0, 0, result.Width, result.Height), area, GraphicsUnit.Pixel);
                }
                return result;
            }
        }

        private void RequestDoll(NativeDialogueFrame frame, JObject appearance, Action<Bitmap> ready)
        {
            JObject normalized = NormalizeAppearance(appearance);
            if (normalized == null) return;
            RequestDollCore(normalized, frame.Expression, ready);
        }

        /// <summary>
        /// 预取下一句立绘（warm-only）：只暖内存/磁盘缓存，绝不投递 widget、不发事件、
        /// 失败静默。normalizedAppearance==null 走静态链（key 即 manifest 立绘名）；
        /// 否则按纸娃娃处理（调用方已归一化）。doll 预取让位前景加载：pending 已占
        /// ≥2 槽时静默跳过（pending 上限 4，预取最多占 2 槽）。回调克隆立即释放，
        /// 缓存本体留 LRU。
        /// </summary>
        internal void PrefetchPortrait(string key, string expression, JObject normalizedAppearance)
        {
            if (normalizedAppearance == null)
            {
                LoadCached("static:" + key + ":" + expression, () => LoadStatic(key, expression),
                    bmp => { if (bmp != null) bmp.Dispose(); });
                return;
            }
            lock (_gate) { if (_pending.Count >= 2) return; }
            RequestDollCore(normalizedAppearance, expression, bmp => { if (bmp != null) bmp.Dispose(); });
        }

        /// <summary>纸娃娃磁盘→Web 链核心：normalized 必须已归一化。内存命中同步回调、
        /// 同 key pending 合并、4 槽上限与 15s 过期语义对前景加载与预取一致。</summary>
        private void RequestDollCore(JObject normalized, string expression, Action<Bitmap> ready)
        {
            string key = DollKey(normalized, expression, _assetVersion);
            Bitmap cached = GetCached(key);
            if (cached != null) { ready(cached); return; }
            Pending pending;
            lock (_gate)
            {
                if (_disposed) return;
                if (_pending.TryGetValue(key, out pending)) { pending.Callbacks.Add(ready); return; }
                if (_pending.Count >= 4) return;
                pending = new Pending { Key = key, RequestId = Guid.NewGuid().ToString("N") };
                pending.Callbacks.Add(ready);
                _pending.Add(key, pending);
                pending.Timer = new System.Threading.Timer(_ => Expire(pending), null, 15000, Timeout.Infinite);
            }
            // 磁盘先查再发 Web：同 key 在途合并由 pending 保证，磁盘命中即按同一
            // pending 生命周期交付，不会再向 Web 发同 key 请求。IO 全在后台线程。
            Task.Run(() =>
            {
                Bitmap diskImage = null;
                try { diskImage = _disk.TryLoad(key, RenderSize); }
                catch (Exception ex) { LogManager.Log("[NativeDialogue] disk cache read: " + ex.Message); }
                if (diskImage != null) { DeliverDiskHit(pending, diskImage); return; }
                lock (_gate)
                {
                    if (_disposed || !_pending.TryGetValue(key, out var current)
                        || !ReferenceEquals(current, pending)) return;
                }
                var message = new JObject
                {
                    ["type"] = "dialoguePortraitBake", ["requestId"] = pending.RequestId, ["key"] = key,
                    ["appearance"] = normalized, ["expression"] = expression,
                    ["size"] = RenderSize, ["rig"] = "dialogue", ["assetVersion"] = _assetVersion
                };
                bool posted = false;
                try { posted = _postToWeb != null && _postToWeb(message.ToString(Formatting.None)); }
                catch (Exception ex) { LogManager.Log("[NativeDialogue] portrait bridge: " + ex.Message); }
                if (!posted) Expire(pending);
            });
        }

        /// <summary>磁盘命中交付：同一 pending 生命周期内移除+落内存缓存+发回调；
        /// pending 已被超时/释放顶替时仍写入内存缓存（数据有效），但绝不发旧回调。</summary>
        private void DeliverDiskHit(Pending expected, Bitmap image)
        {
            Action<Bitmap>[] callbacks = null;
            lock (_gate)
            {
                Pending current;
                if (_pending.TryGetValue(expected.Key, out current) && ReferenceEquals(current, expected))
                {
                    _pending.Remove(expected.Key);
                    expected.Timer?.Dispose();
                    callbacks = expected.Callbacks.ToArray();
                }
            }
            try
            {
                PutCached(expected.Key, image);
                if (callbacks != null)
                    foreach (Action<Bitmap> callback in callbacks) callback((Bitmap)image.Clone());
            }
            finally { image.Dispose(); }
        }

        internal static JObject NormalizeAppearance(JObject source)
        {
            if (source == null) return null;
            var result = new JObject();
            foreach (string field in new[] { "gender", "face", "hair", "mask", "head", "body", "leg", "hand", "foot", "neck" })
            {
                JToken token = source[field];
                if (token != null && token.Type != JTokenType.String && token.Type != JTokenType.Integer) return null;
                string value = token?.ToString() ?? "";
                if (value.Length > 256 || value.IndexOf('\0') >= 0) return null;
                result[field] = value;
            }
            var keyMap = source["keyMap"] as JObject;
            if (keyMap != null)
            {
                if (keyMap.Count > 48) return null;
                var map = new JObject();
                foreach (var field in keyMap.Properties().OrderBy(p => p.Name, StringComparer.Ordinal))
                {
                    if (field.Name.Length > 80 || field.Value.Type != JTokenType.String || field.Value.Value<string>().Length > 256) return null;
                    map[field.Name] = field.Value.DeepClone();
                }
                result["keyMap"] = map;
            }
            return result;
        }

        internal static string DollKey(JObject normalized, string expression, string assetVersion)
        {
            return Hash(Encoding.UTF8.GetBytes("dialogue:768:v1\n" + assetVersion + "\n" + expression + "\n"
                + normalized.ToString(Formatting.None)));
        }

        /// <summary>
        /// Web 合成结果回送。调用方是 WebView2 同步桥（UI 线程），web 侧对返回值
        /// fire-and-forget，因此这里只做轻量受理校验：base64 解码、GDI+ 全量校验、
        /// 回调交付与磁盘落盘全部移到后台线程，受理即返回。
        /// 同步返回 false 的拒绝面与旧版一致：无此 pending / requestId 不符 /
        /// pngBase64 缺失·非字符串·超 8MB 上限；受理后 decode 失败只记日志、
        /// 不触发回调（与旧同步路径的可观测结果一致）。
        /// 注意：回调现在在线程池线程触发，不再保证是调用线程——消费方
        /// NativeDialogueTask.CompleteBitmap 自己会 dispatch 回 UI 线程。
        /// </summary>
        internal string HandleResult(JObject message)
        {
            var payload = message?["payload"] as JObject;
            string key = payload?["key"]?.Type == JTokenType.String ? payload.Value<string>("key") : null;
            string request = payload?["requestId"]?.Type == JTokenType.String ? payload.Value<string>("requestId") : null;
            Action<Bitmap>[] callbacks;
            lock (_gate)
            {
                Pending pending;
                if (_disposed || key == null || !_pending.TryGetValue(key, out pending)
                    || request != pending.RequestId) return "{\"success\":false}";
                _pending.Remove(key);
                pending.Timer.Dispose();
                callbacks = pending.Callbacks.ToArray();
            }
            // 结构拒绝保持同步可观测：缺失 / 非字符串 / 空 / 超 8MB 上限。
            if (payload["pngBase64"]?.Type != JTokenType.String) return "{\"success\":false}";
            string base64 = payload.Value<string>("pngBase64");
            if (string.IsNullOrEmpty(base64) || base64.Length > 8 * 1024 * 1024)
                return "{\"success\":false}";
            Task.Run(() => DeliverResult(key, base64, callbacks));
            return "{\"success\":true}";
        }

        /// <summary>后台交付：base64 解码 → GDI+ 校验 → 内存缓存 + 逐个回调（各持
        /// Clone）→ 同一任务内落盘。解码失败只记日志不回调；落盘失败不影响已完成的
        /// 交付。动共享状态前先在 _gate 下复核 _disposed（对齐 LoadCached 模式）。</summary>
        private void DeliverResult(string key, string base64, Action<Bitmap>[] callbacks)
        {
            try
            {
                byte[] pngBytes = Convert.FromBase64String(base64);
                using (Bitmap image = DecodeResult(pngBytes))
                {
                    if (image == null)
                    {
                        LogManager.Log("[NativeDialogue] rejected portrait: decode failed");
                        return;
                    }
                    lock (_gate) { if (_disposed) return; }
                    PutCached(key, image);
                    foreach (Action<Bitmap> callback in callbacks) callback((Bitmap)image.Clone());
                }
                // 先完成内存/回调交付，再落盘——存盘失败不影响本次结果。
                lock (_gate) { if (_disposed) return; }
                try { _disk.Store(key, pngBytes, RenderSize); }
                catch (Exception ex) { LogManager.Log("[NativeDialogue] disk cache write: " + ex.Message); }
            }
            catch (Exception ex) { LogManager.Log("[NativeDialogue] rejected portrait: " + ex.Message); }
        }

        internal static Bitmap DecodeResult(string base64)
        {
            if (string.IsNullOrEmpty(base64) || base64.Length > 8 * 1024 * 1024) return null;
            return DecodeResult(Convert.FromBase64String(base64));
        }

        internal static Bitmap DecodeResult(byte[] bytes)
        {
            return DialoguePortraitDiskCache.DecodePng(bytes, RenderSize);
        }

        private void Expire(Pending expected)
        {
            lock (_gate)
            {
                Pending current;
                if (!_pending.TryGetValue(expected.Key, out current) || !ReferenceEquals(current, expected)) return;
                _pending.Remove(expected.Key);
                expected.Timer?.Dispose();
            }
        }

        private Bitmap GetCached(string key)
        {
            lock (_gate)
            {
                Bitmap image;
                if (_disposed || !_cache.TryGetValue(key, out image)) return null;
                _lru.Remove(key); _lru.AddLast(key);
                return (Bitmap)image.Clone();
            }
        }

        private void PutCached(string key, Bitmap image)
        {
            lock (_gate)
            {
                if (_disposed || _cache.ContainsKey(key)) return;
                long bytes = (long)image.Width * image.Height * 4;
                if (bytes > CacheLimit) return;
                while (_cacheBytes + bytes > CacheLimit && _lru.Count > 0)
                {
                    string oldest = _lru.First.Value; _lru.RemoveFirst();
                    Bitmap old = _cache[oldest]; _cache.Remove(oldest);
                    _cacheBytes -= (long)old.Width * old.Height * 4; old.Dispose();
                }
                _cache[key] = (Bitmap)image.Clone(); _lru.AddLast(key); _cacheBytes += bytes;
            }
        }

        internal static string SafeChild(string root, string relative)
        {
            if (string.IsNullOrEmpty(relative) || Path.IsPathRooted(relative) || relative.Contains(':')) return null;
            try
            {
                string parent = Path.GetFullPath(root).TrimEnd(Path.DirectorySeparatorChar) + Path.DirectorySeparatorChar;
                string path = Path.GetFullPath(Path.Combine(parent, relative.Replace('/', Path.DirectorySeparatorChar)));
                return path.StartsWith(parent, StringComparison.OrdinalIgnoreCase) ? path : null;
            }
            catch { return null; }
        }

        private static string Hash(byte[] bytes) { return Convert.ToHexString(SHA256.HashData(bytes)).ToLowerInvariant(); }

        public void Dispose()
        {
            lock (_gate)
            {
                _disposed = true;
                foreach (Pending pending in _pending.Values) pending.Timer?.Dispose();
                _pending.Clear();
                foreach (Bitmap image in _cache.Values) image.Dispose();
                _cache.Clear(); _lru.Clear(); _cacheBytes = 0;
            }
        }
    }
}
