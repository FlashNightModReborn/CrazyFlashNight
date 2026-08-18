using System;
using System.Collections.Generic;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Drawing.Imaging;
using System.IO;
using System.Text;
using System.Text.RegularExpressions;
using Newtonsoft.Json.Linq;
using SkiaSharp;
using Svg;
using Svg.Model;
using Svg.Skia;

namespace CF7Launcher.Guardian.Hud.Loot
{
    /// <summary>
    /// NativeHud 侧物品图标目录：读 launcher/web/icons/manifest.json（IconBakeTask 烘焙产物），
    /// 把图标名解析为帧集（静态 1 帧 / png-sequence 动画 N 帧 / webp-animated 动画 N 帧），
    /// 经 MapHudImageDecoder（单帧）或 SKCodec 逐帧合成（webp-animated）全尺寸解码后
    /// 用 GDI+ 高质量缩放为 64px 缩略图（不依赖 SKCodec 缩放——PNG 源在 Skia 下不支持任意采样比，
    /// 曾导致 金钱/K点 "Codec cannot satisfy requested decode size"）。
    /// 帧位图按 uri（webp-animated 逐帧用 "uri#fN"）进共享 LRU；
    /// png-sequence 时间轴由调用方按 fps 推进（对齐 web icons.js 的 fpsForEntry），
    /// webp-animated（目前仅 强化石）按 LootIconFrames.DurationMs 逐帧时长推进；
    /// 动画源取条目 uri（f1 只是烘焙侧抽出的静态首帧），解码失败/单帧一律落回静态 f1。
    /// 物品 manifest 未命中时按敌人头像库（launcher/web/assets/enemy-portraits，键 = "敌人-*" ref）
    /// 解析：默认 variant 的 subject SVG 经 Svg.Skia 光栅化为静态帧（键 "portrait:&lt;ref&gt;"），
    /// 支持 manifest aliases 指向目标 ref；SVG 无 PNG 替代是头像库现状，光栅化是唯一路径。
    /// 敌人头像仍未命中时按运行时纸娃娃胸像库（launcher/data/doll-portraits，键 = "纸娃娃-&lt;hex&gt;" ref，
    /// DollPortraitBakeService 经 WebView2 dressup 渲染器烘焙、DollBakeTask 原子落盘）解析：
    /// 文件名即键的 hex 部分，无 manifest，文件存在即注册（键 "doll:&lt;ref&gt;"）。
    /// 因烘焙异步落盘、首次击杀时文件可能未就绪，doll 源 miss 的负缓存带 2000ms TTL，
    /// 到期允许重探；烘焙完成经 InvalidateDoll 主动失效可立即重探；其余源负缓存行为不变（永久）。
    /// 解析失败/缺失一律负缓存并返回 false，由调用方画占位，不抛异常。
    /// </summary>
    public sealed class LootIconCatalog : IDisposable
    {
        internal const int ThumbSize = 64;
        private const double DefaultFps = 24.0;
        /// <summary>doll 源负缓存 TTL（ms）：烘焙异步落盘，到期重探。</summary>
        internal const long DollMissTtlMs = 2000;

        /// <summary>单图标帧集。Frames 为缓存共享位图，调用方不得 Dispose。</summary>
        internal sealed class LootIconFrames
        {
            internal Bitmap[] Frames;
            internal double Fps;
            internal int[] DurationMs; // 逐帧时长 ms（webp-animated）；null = 均匀 fps（png-sequence/静态）
            internal bool Animated { get { return Frames != null && Frames.Length > 1; } }
            internal Bitmap First { get { return Frames != null && Frames.Length > 0 ? Frames[0] : null; } }
        }

        private sealed class ManifestEntry
        {
            internal string F1;
            internal string Uri; // webp-animated 的动画源文件（f1 为静态首帧抽帧）
            internal string Format; // manifest format 字段（"webp-animated" 等）
            internal List<string> FrameUris; // 动画时间轴（含重复帧展开）；静态为 null
            internal double Fps;
        }

        private readonly string _iconsDir;
        private readonly string _manifestPath;
        private readonly string _enemyPortraitsDir; // null = 头像库关闭
        private readonly string _dollPortraitsDir; // null = 运行时纸娃娃胸像库关闭
        private readonly object _gate = new object();
        private readonly BitmapLruCache _frameCache; // key = uri 文件名（头像用 "portrait:<ref>"，纸娃娃用 "doll:<ref>"）
        private readonly Dictionary<string, LootIconFrames> _setCache =
            new Dictionary<string, LootIconFrames>(StringComparer.Ordinal); // key = 图标名
        private readonly HashSet<string> _missing = new HashSet<string>(StringComparer.Ordinal);
        // doll 源专用 TTL 负缓存：ref → 上次 miss 的 NowMs（烘焙异步落盘，到期重探）
        private readonly Dictionary<string, long> _missingDoll =
            new Dictionary<string, long>(StringComparer.Ordinal);
        /// <summary>时钟注入（测试钩子，对齐 LootFeedModel 的 nowMs 注入风格）。</summary>
        internal Func<long> NowMs = () => Environment.TickCount64;
        private Dictionary<string, ManifestEntry> _manifest; // lazy
        private bool _manifestLoaded;
        private Dictionary<string, string> _portraitSubjects; // lazy：ref → subject 相对路径
        private Dictionary<string, string> _portraitAliases;  // lazy：ref → 目标 ref
        private bool _portraitManifestLoaded;

        public LootIconCatalog(string iconsDir, string enemyPortraitsDir = null,
            long maxCacheBytes = 24L * 1024 * 1024, string dollPortraitsDir = null)
        {
            if (string.IsNullOrEmpty(iconsDir)) throw new ArgumentException("Icons dir is required.", nameof(iconsDir));
            _iconsDir = iconsDir;
            _manifestPath = Path.Combine(iconsDir, "manifest.json");
            _enemyPortraitsDir = string.IsNullOrEmpty(enemyPortraitsDir) ? null : enemyPortraitsDir;
            _dollPortraitsDir = string.IsNullOrEmpty(dollPortraitsDir) ? null : dollPortraitsDir;
            _frameCache = new BitmapLruCache(maxCacheBytes, StringComparer.Ordinal);
        }

        /// <summary>成功时 out 帧集（共享位图，调用方不得 Dispose）。任何失败返回 false。</summary>
        internal bool TryGet(string iconName, out LootIconFrames frames)
        {
            frames = null;
            if (string.IsNullOrEmpty(iconName)) return false;

            lock (_gate)
            {
                if (_setCache.TryGetValue(iconName, out frames)) return true;
                if (_missing.Contains(iconName)) return false;
                bool isDollRef = iconName.StartsWith(DollPortraitKey.Prefix, StringComparison.Ordinal);
                if (isDollRef)
                {
                    // doll 负缓存带 TTL：烘焙异步落盘，TTL 内直接判 miss，到期放行重探
                    long missAt;
                    if (_missingDoll.TryGetValue(iconName, out missAt)
                        && NowMs() - missAt < DollMissTtlMs)
                        return false;
                }

                EnsureManifestLoaded();
                ManifestEntry entry;
                if (_manifest == null || !_manifest.TryGetValue(iconName, out entry) || entry == null)
                {
                    // 物品图标未命中 → 敌人头像库（ref = "敌人-*" 类型键）
                    EnsurePortraitManifestLoaded();
                    Bitmap portrait = LoadPortrait(iconName);
                    if (portrait == null)
                    {
                        // 敌人头像未命中 → 运行时纸娃娃胸像（ref = "纸娃娃-<hex>"）
                        portrait = LoadDoll(iconName);
                    }
                    if (portrait != null)
                    {
                        frames = new LootIconFrames
                        {
                            Frames = new Bitmap[] { portrait },
                            Fps = DefaultFps
                        };
                        _setCache[iconName] = frames;
                        if (isDollRef) _missingDoll.Remove(iconName);
                        return true;
                    }
                    if (isDollRef) _missingDoll[iconName] = NowMs();
                    else _missing.Add(iconName);
                    return false;
                }

                // webp-animated：动画帧全部在单个 .webp 内（uri 字段；f1 只是静态首帧），
                // 走 SKCodec 逐帧合成；解码失败/单帧则落回下方静态 f1 路径
                if ((entry.FrameUris == null || entry.FrameUris.Count == 0)
                    && entry.Format == "webp-animated")
                {
                    int[] durationMs;
                    Bitmap[] webpFrames = LoadWebpFrames(
                        !string.IsNullOrEmpty(entry.Uri) ? entry.Uri : entry.F1, out durationMs);
                    if (webpFrames != null && webpFrames.Length > 1)
                    {
                        frames = new LootIconFrames
                        {
                            Frames = webpFrames,
                            Fps = entry.Fps > 0 ? entry.Fps : DefaultFps,
                            DurationMs = durationMs
                        };
                        _setCache[iconName] = frames;
                        return true;
                    }
                }

                List<string> uris = entry.FrameUris;
                if (uris == null || uris.Count == 0)
                {
                    if (string.IsNullOrEmpty(entry.F1))
                    {
                        _missing.Add(iconName);
                        return false;
                    }
                    uris = new List<string> { entry.F1 };
                }

                List<Bitmap> bitmaps = new List<Bitmap>(uris.Count);
                for (int i = 0; i < uris.Count; i++)
                {
                    Bitmap bmp = LoadFrame(uris[i]);
                    // 单帧缺失只丢帧，不否整个图标；重复 uri 解析为同一位图引用，
                    // 保留完整时间轴长度以维持烘焙侧的 hold 时长语义
                    if (bmp == null) continue;
                    bitmaps.Add(bmp);
                }
                if (bitmaps.Count == 0)
                {
                    _missing.Add(iconName);
                    return false;
                }

                frames = new LootIconFrames
                {
                    Frames = bitmaps.ToArray(),
                    Fps = entry.Fps > 0 ? entry.Fps : DefaultFps
                };
                _setCache[iconName] = frames;
                return true;
            }
        }

        /// <summary>按 uri 载帧：LRU 命中直发；否则全尺寸解码 + GDI+ 缩略。失败返回 null。</summary>
        private Bitmap LoadFrame(string uri)
        {
            if (string.IsNullOrEmpty(uri)) return null;
            Bitmap bmp;
            if (_frameCache.TryGet(uri, out bmp)) return bmp;

            string path = Path.Combine(_iconsDir, uri);
            if (!File.Exists(path)) return null;

            try
            {
                using (Bitmap full = MapHudImageDecoder.LoadBitmap(path))
                {
                    bmp = CreateThumb(full);
                }
            }
            catch (Exception ex)
            {
                LogManager.Log("[LootIcon] decode failed for '" + uri + "': " + ex.Message);
                return null;
            }

            if (!_frameCache.TryAdd(uri, bmp))
            {
                // 超预算（64px 帧 16KB，理论上不会），退化为不缓存直发
                return bmp;
            }
            return bmp;
        }

        /// <summary>全尺寸帧 → 64px 缩略图（GDI+ 高质量缩放，规避 SKCodec 采样比限制）。</summary>
        private static Bitmap CreateThumb(Bitmap full)
        {
            Bitmap thumb = new Bitmap(ThumbSize, ThumbSize, PixelFormat.Format32bppPArgb);
            try
            {
                using (Graphics g = Graphics.FromImage(thumb))
                {
                    g.InterpolationMode = InterpolationMode.HighQualityBicubic;
                    g.SmoothingMode = SmoothingMode.HighQuality;
                    g.PixelOffsetMode = PixelOffsetMode.HighQuality;
                    g.DrawImage(full, 0, 0, ThumbSize, ThumbSize);
                }
            }
            catch
            {
                thumb.Dispose();
                throw;
            }
            return thumb;
        }

        /// <summary>
        /// webp-animated 全帧解码：SKCodec 逐帧取帧，按 SKCodecFrameInfo.RequiredFrame
        /// 把依赖帧的完整合成结果铺进画布再解码（SKCodecOptions priorFrame 语义；
        /// RequiredFrame=-1 即独立帧，先清透明画布），disposal/blend 由 codec 依据
        /// priorFrame 内容自行处理——调用方只需保证“dst = required 帧合成态”。
        /// 输出每帧完整合成后的 64px 缩略图（key "uri#fN" 进共享 LRU）与逐帧时长。
        /// 非动画/解码失败返回 null，由调用方落回静态首帧。
        /// </summary>
        private Bitmap[] LoadWebpFrames(string uri, out int[] durationMs)
        {
            durationMs = null;
            if (string.IsNullOrEmpty(uri)) return null;
            string path = Path.Combine(_iconsDir, uri);
            if (!File.Exists(path)) return null;

            try
            {
                using (SKData encoded = SKData.Create(path))
                using (SKCodec codec = SKCodec.Create(encoded))
                {
                    if (codec == null || codec.FrameCount < 2) return null;
                    int frameCount = codec.FrameCount;
                    SKCodecFrameInfo[] frameInfos = codec.FrameInfo;
                    int width = codec.Info.Width;
                    int height = codec.Info.Height;
                    if (width <= 0 || height <= 0) return null;

                    SKImageInfo decodeInfo = new SKImageInfo(width, height, SKColorType.Bgra8888, SKAlphaType.Premul);
                    Bitmap[] composited = new Bitmap[frameCount]; // 全尺寸合成态，供后续帧作 priorFrame
                    int[] durations = new int[frameCount];
                    try
                    {
                        for (int i = 0; i < frameCount; i++)
                        {
                            int required = frameInfos[i].RequiredFrame; // -1 = 独立帧
                            bool hasPrior = required >= 0 && required < i && composited[required] != null;
                            Bitmap canvas = new Bitmap(width, height, PixelFormat.Format32bppPArgb);
                            try
                            {
                                using (Graphics g = Graphics.FromImage(canvas))
                                {
                                    if (hasPrior)
                                        g.DrawImageUnscaled(composited[required], 0, 0);
                                    else
                                        g.Clear(Color.Transparent);
                                }
                                // ReadWrite：codec 需在保留 priorFrame 内容的缓冲上就地混合，
                                // WriteOnly 可能拿到不含先验内容的暂存缓冲
                                BitmapData data = canvas.LockBits(
                                    new Rectangle(0, 0, width, height),
                                    ImageLockMode.ReadWrite,
                                    PixelFormat.Format32bppPArgb);
                                try
                                {
                                    if (data.Stride <= 0)
                                        throw new InvalidOperationException("Unexpected negative bitmap stride: " + path);
                                    SKCodecResult result = codec.GetPixels(decodeInfo, data.Scan0, data.Stride,
                                        new SKCodecOptions(i, hasPrior ? required : -1));
                                    if (result != SKCodecResult.Success)
                                        throw new InvalidOperationException(
                                            "WebP frame decode failed (" + result + "): " + path + "#f" + i);
                                }
                                finally
                                {
                                    canvas.UnlockBits(data);
                                }
                            }
                            catch
                            {
                                canvas.Dispose();
                                throw;
                            }
                            composited[i] = canvas;
                            durations[i] = Math.Max(0, frameInfos[i].Duration);
                        }
                    }
                    catch
                    {
                        for (int i = 0; i < composited.Length; i++)
                            if (composited[i] != null) composited[i].Dispose();
                        throw;
                    }

                    // 缩略 + 进 LRU；全尺寸合成态即用即弃
                    Bitmap[] thumbs = new Bitmap[frameCount];
                    try
                    {
                        for (int i = 0; i < frameCount; i++)
                        {
                            thumbs[i] = CreateThumb(composited[i]);
                            // 超预算退化为不缓存直发（与 LoadFrame 同策略）
                            _frameCache.TryAdd(uri + "#f" + i, thumbs[i]);
                        }
                    }
                    finally
                    {
                        for (int i = 0; i < composited.Length; i++)
                            if (composited[i] != null) composited[i].Dispose();
                    }

                    long total = 0;
                    for (int i = 0; i < durations.Length; i++) total += durations[i];
                    durationMs = total > 0 ? durations : null; // 全 0 时长 → 调用方走均匀 fps
                    return thumbs;
                }
            }
            catch (Exception ex)
            {
                LogManager.Log("[LootIcon] webp-animated decode failed for '" + uri + "': " + ex.Message);
                durationMs = null;
                return null;
            }
        }

        /// <summary>敌人头像解析：ref → subject SVG → 光栅化 64px 缩略。失败返回 null。</summary>
        private Bitmap LoadPortrait(string portraitRef)
        {
            if (_enemyPortraitsDir == null || _portraitSubjects == null) return null;
            string cacheKey = "portrait:" + portraitRef;
            Bitmap cached;
            if (_frameCache.TryGet(cacheKey, out cached)) return cached;

            string rel = null;
            if (!_portraitSubjects.TryGetValue(portraitRef, out rel))
            {
                string aliasTarget;
                if (_portraitAliases != null && _portraitAliases.TryGetValue(portraitRef, out aliasTarget))
                    _portraitSubjects.TryGetValue(aliasTarget, out rel);
            }
            if (string.IsNullOrEmpty(rel)) return null;

            string path = Path.Combine(_enemyPortraitsDir, rel.Replace('/', Path.DirectorySeparatorChar));
            if (!File.Exists(path)) return null;

            Bitmap thumb;
            try
            {
                using (Bitmap full = RenderSvg(path, 256))
                    thumb = CreateThumb(full);
            }
            catch (Exception ex)
            {
                LogManager.Log("[LootIcon] portrait svg rasterize failed for '" + portraitRef + "': " + ex.Message);
                return null;
            }

            if (!_frameCache.TryAdd(cacheKey, thumb))
                return thumb; // 超预算退化为不缓存直发（与 LoadFrame 同策略）
            return thumb;
        }

        /// <summary>烘焙完成/外部变更时主动失效 doll 负缓存，允许立即重探（异步图标升级链路）。</summary>
        internal void InvalidateDoll(string dollRef)
        {
            if (string.IsNullOrEmpty(dollRef)) return;
            lock (_gate)
            {
                _missingDoll.Remove(dollRef);
            }
        }

        /// <summary>
        /// 运行时纸娃娃胸像解析：ref = "纸娃娃-&lt;hex&gt;" → doll-portraits/&lt;hex&gt;.png
        /// （DollBakeTask 原子落盘产物，无 manifest，文件存在即注册）→ 全尺寸解码 + 64px 缩略。
        /// 键非法/文件缺失/解码失败返回 null，由 TryGet 进 TTL 负缓存。
        /// </summary>
        private Bitmap LoadDoll(string dollRef)
        {
            if (_dollPortraitsDir == null) return null;
            string hex;
            if (!DollBakeTaskKey.TryExtractHex(dollRef, out hex)) return null;
            string cacheKey = "doll:" + dollRef;
            Bitmap cached;
            if (_frameCache.TryGet(cacheKey, out cached)) return cached;

            string path = Path.Combine(_dollPortraitsDir, hex + ".png");
            if (!File.Exists(path)) return null;

            Bitmap thumb;
            try
            {
                using (Bitmap full = MapHudImageDecoder.LoadBitmap(path))
                    thumb = CreateThumb(full);
            }
            catch (Exception ex)
            {
                LogManager.Log("[LootIcon] doll portrait decode failed for '" + dollRef + "': " + ex.Message);
                return null;
            }

            if (!_frameCache.TryAdd(cacheKey, thumb))
                return thumb; // 超预算退化为不缓存直发（与 LoadFrame 同策略）
            return thumb;
        }

        /// <summary>
        /// Svg.Skia 光栅化：按 CullRect 等比适配进 size×size 透明画布，Bgra8888/Premul 输出。
        /// 配置与 SKSvg 生命周期严格对齐 PlayerInfo 已验证路径（PlayerInfoStrictSvg.cs StrictSvgFacade）：
        /// picture 播放依赖 SKSvg 持有的解析期资源，**SKSvg 必须存活到 DrawPicture 完成**，
        /// 提前 Dispose 会以 native use-after-free 崩溃（"Fatal error"，托管不可捕获）。
        /// </summary>
        private static Bitmap RenderSvg(string path, int size)
        {
            SKSvg svg = new SKSvg();
            try
            {
                SvgDocument.DisableDtdProcessing = true;
                svg.Settings.AlphaType = SKAlphaType.Premul;
                svg.Settings.ColorType = SKColorType.Bgra8888;
                svg.Settings.EnableJavaScript = false;
                svg.Settings.EnableExternalJavaScript = false;
                svg.Settings.EnableBrokenImagePlaceholders = false;
                svg.Settings.EnableSvgFonts = false;
                svg.Settings.EnableTextReferences = false;
                svg.Settings.EnableFilterBackgroundInputs = false;
                svg.Settings.EnableTextSelectionRendering = false;

                var loadOptions = new SvgDocumentLoadOptions
                {
                    ProcessingMode = SvgProcessingMode.SecureStatic,
                    ExternalResources = SvgExternalResourcePolicy.Disabled,
                    PreserveUnknownElements = false,
                    PreferSvg2Href = true
                };
                var parameters = new SvgParameters(null, null, null, loadOptions);

                // FFDec 头像 SVG 的 <filter>（Flash 发光/模糊/投影效果，160/221 头像使用）在部分
                // 内容上会压垮光栅化——64px 播报图标不需要这些效果，解析前整体剥离
                string svgText = StripSvgFilters(File.ReadAllText(path, Encoding.UTF8));
                SKPicture picture;
                using (MemoryStream stream = new MemoryStream(Encoding.UTF8.GetBytes(svgText), writable: false))
                    picture = svg.Load(stream, parameters, new Uri("urn:cf7:loot:enemy-portrait"));
                if (picture == null)
                    throw new InvalidDataException("Svg.Skia returned no picture: " + path);
                try
                {
                    SKRect bounds = picture.CullRect;
                    if (bounds.Width <= 0 || bounds.Height <= 0)
                        throw new InvalidDataException("SVG has empty cull rect: " + path);
                    float scale = Math.Min(size / bounds.Width, size / bounds.Height);
                    float tx = (size - bounds.Width * scale) / 2f - bounds.Left * scale;
                    float ty = (size - bounds.Height * scale) / 2f - bounds.Top * scale;

                    Bitmap result = new Bitmap(size, size, PixelFormat.Format32bppPArgb);
                    try
                    {
                        using (SKBitmap skBitmap = new SKBitmap(size, size, SKColorType.Bgra8888, SKAlphaType.Premul))
                        {
                            using (SKCanvas canvas = new SKCanvas(skBitmap))
                            {
                                canvas.Clear(SKColors.Transparent);
                                canvas.Translate(tx, ty);
                                canvas.Scale(scale);
                                canvas.DrawPicture(picture);
                                canvas.Flush();
                            }
                            BitmapData data = result.LockBits(
                                new Rectangle(0, 0, size, size),
                                ImageLockMode.WriteOnly,
                                PixelFormat.Format32bppPArgb);
                            try
                            {
                                if (data.Stride <= 0)
                                    throw new InvalidOperationException("Unexpected negative bitmap stride: " + path);
                                bool ok = skBitmap.PeekPixels().ReadPixels(
                                    new SKImageInfo(size, size, SKColorType.Bgra8888, SKAlphaType.Premul),
                                    data.Scan0, data.Stride, 0, 0);
                                if (!ok)
                                    throw new InvalidOperationException("ReadPixels failed: " + path);
                            }
                            finally
                            {
                                result.UnlockBits(data);
                            }
                        }
                        return result;
                    }
                    catch
                    {
                        result.Dispose();
                        throw;
                    }
                }
                finally
                {
                    picture.Dispose();
                }
            }
            finally
            {
                svg.Dispose();
            }
        }

        /// <summary>
        /// 剥离 SVG 中的 &lt;filter&gt; 定义与 filter="url(#...)" 属性引用（InternalsVisibleTo 单测钩子）。
        /// FFDec 从头像导出的 Flash 滤镜（发光/模糊/投影）在 Svg.Skia 光栅化时会触发 native 致命崩溃，
        /// 无法托管捕获；64px 播报图标不需要这些效果，整体剥离后视觉差异可忽略。
        /// 对 &lt;use&gt;/图形元素遗留的悬空 url(#filter) 引用，渲染器按忽略处理。
        /// </summary>
        internal static string StripSvgFilters(string svgText)
        {
            if (string.IsNullOrEmpty(svgText)) return svgText;
            string stripped = Regex.Replace(svgText,
                "<filter\\b[^>]*/>", string.Empty,
                RegexOptions.Singleline | RegexOptions.IgnoreCase);
            stripped = Regex.Replace(stripped,
                "<filter\\b[^>]*>.*?</filter\\s*>", string.Empty,
                RegexOptions.Singleline | RegexOptions.IgnoreCase);
            stripped = Regex.Replace(stripped,
                "\\s*filter\\s*=\\s*\"url\\(#[^\"]*\\)\"", string.Empty,
                RegexOptions.IgnoreCase);
            stripped = Regex.Replace(stripped,
                "\\s*filter\\s*=\\s*'url\\(#[^']*\\)'", string.Empty,
                RegexOptions.IgnoreCase);
            return stripped;
        }

        private void EnsurePortraitManifestLoaded()
        {
            if (_portraitManifestLoaded) return;
            _portraitManifestLoaded = true;
            _portraitSubjects = null;
            _portraitAliases = null;
            if (_enemyPortraitsDir == null) return;
            try
            {
                string path = Path.Combine(_enemyPortraitsDir, "manifest.json");
                if (!File.Exists(path)) return;
                JObject root = JObject.Parse(File.ReadAllText(path, Encoding.UTF8));

                Dictionary<string, string> subjects = new Dictionary<string, string>(StringComparer.Ordinal);
                JObject entries = root["entries"] as JObject;
                if (entries != null)
                {
                    foreach (KeyValuePair<string, JToken> kvp in entries)
                    {
                        JObject entry = kvp.Value as JObject;
                        if (entry == null) continue;
                        string defaultVariant = entry.Value<string>("defaultVariant") ?? "default";
                        JObject variants = entry["variants"] as JObject;
                        JObject variant = variants != null ? variants[defaultVariant] as JObject : null;
                        JObject subject = variant != null ? variant["subject"] as JObject : null;
                        JObject svg = subject != null ? subject["svg"] as JObject : null;
                        string url = svg != null ? svg.Value<string>("url") : null;
                        if (string.IsNullOrEmpty(url)) continue;
                        // "assets/enemy-portraits/subjects/xxx.svg" → 库根相对路径
                        int idx = url.IndexOf("enemy-portraits/", StringComparison.Ordinal);
                        subjects[kvp.Key] = idx >= 0
                            ? url.Substring(idx + "enemy-portraits/".Length)
                            : url;
                    }
                }

                Dictionary<string, string> aliases = new Dictionary<string, string>(StringComparer.Ordinal);
                JObject aliasObj = root["aliases"] as JObject;
                if (aliasObj != null)
                {
                    foreach (KeyValuePair<string, JToken> kvp in aliasObj)
                    {
                        JObject a = kvp.Value as JObject;
                        string target = a != null ? a.Value<string>("targetPortraitRef") : null;
                        if (!string.IsNullOrEmpty(target)) aliases[kvp.Key] = target;
                    }
                }

                _portraitSubjects = subjects;
                _portraitAliases = aliases;
            }
            catch (Exception ex)
            {
                LogManager.Log("[LootIcon] portrait manifest load failed: " + ex.Message);
                _portraitSubjects = null;
                _portraitAliases = null;
            }
        }

        private void EnsureManifestLoaded()
        {
            if (_manifestLoaded) return;
            _manifestLoaded = true;
            _manifest = null;
            try
            {
                if (!File.Exists(_manifestPath)) return;
                string json = File.ReadAllText(_manifestPath, Encoding.UTF8);
                JObject root = JObject.Parse(json);
                Dictionary<string, ManifestEntry> map =
                    new Dictionary<string, ManifestEntry>(StringComparer.Ordinal);
                foreach (KeyValuePair<string, JToken> kvp in root)
                {
                    JObject entry = kvp.Value as JObject;
                    if (entry == null) continue;

                    ManifestEntry parsed = new ManifestEntry();
                    parsed.F1 = entry.Value<string>("f1");
                    parsed.Uri = entry.Value<string>("uri");
                    parsed.Format = entry.Value<string>("format");
                    parsed.Fps = entry.Value<double?>("fps") ?? DefaultFps;

                    // png-sequence 动画：frames 展开时间轴；static 标记显式不播
                    string playback = entry.Value<string>("playback");
                    bool staticPlayback = playback == "static" || playback == "static-first-frame";
                    JArray framesArr = entry["frames"] as JArray;
                    if (!staticPlayback && framesArr != null && framesArr.Count > 1)
                    {
                        List<string> uris = new List<string>(framesArr.Count);
                        for (int i = 0; i < framesArr.Count; i++)
                        {
                            JObject f = framesArr[i] as JObject;
                            string uri = f != null ? f.Value<string>("uri") : null;
                            if (!string.IsNullOrEmpty(uri)) uris.Add(uri);
                        }
                        if (uris.Count > 1) parsed.FrameUris = uris;
                    }

                    if (parsed.FrameUris == null && string.IsNullOrEmpty(parsed.F1)) continue;
                    map[kvp.Key] = parsed;
                }
                _manifest = map;
            }
            catch (Exception ex)
            {
                LogManager.Log("[LootIcon] manifest load failed: " + ex.Message);
                _manifest = null;
            }
        }

        public void Dispose()
        {
            lock (_gate)
            {
                _frameCache.Dispose();
            }
        }
    }
}
