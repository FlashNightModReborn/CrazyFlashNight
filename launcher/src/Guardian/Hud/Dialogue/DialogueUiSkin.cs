using System;
using System.Collections.Generic;
using System.Drawing;
using System.Drawing.Imaging;
using System.Globalization;
using System.IO;
using System.Text;
using System.Text.RegularExpressions;
using Newtonsoft.Json.Linq;
using SkiaSharp;
using Svg;
using Svg.Model;
using Svg.Skia;
using CF7Launcher.Guardian.Hud.Loot;

namespace CF7Launcher.Guardian.Hud.Dialogue
{
    /// <summary>
    /// 对话框皮肤：消费 H 导出的 XFL 原版 UI 资产（launcher/web/assets/dialogue-ui/）。
    ///
    /// 资产合同见 tools/xfl-ui-svg/README.md 与产物 layout.json：
    /// - source.svg：viewBox="0 0 1024 576" 舞台源坐标装饰整幅（面板渐变体、深色头条、
    ///   互动键扳机、关闭/拖动按钮 up 态、细线与补片）。动态文本/人物不入 SVG。
    /// - buttons/{id}-{up,over,down}.svg：单态美术，viewBox = 该态在按钮符号局部坐标的
    ///   紧致 bbox；上屏舞台位置 = buttons[].matrix 作用于该 viewBox。
    /// - layout.json：fields/buttons/portraitSlots/clips 的矩阵、stageRect、字号与颜色；
    ///   全部缺省时回落到本类内置的 XFL 实测默认值（数值同源）。
    ///
    /// 光栅化沿用 LootIconCatalog 已验证路径：SecureStatic + 禁外部资源 + 剥离 &lt;filter&gt;
    /// （FFDec/导出滤镜在部分内容上会压垮 Svg.Skia native 光栅化，托管不可捕获；
    /// 代价只是丢掉面板投影），SKSvg 存活到 DrawPicture 完成，经 LockBits + ReadPixels
    /// 落到 Format32bppPArgb。结果按目标像素尺寸缓存（viewport 尺寸变化才重光栅化）。
    /// </summary>
    internal sealed class DialogueUiSkin : IDisposable
    {
        /// <summary>Flash 6 元组矩阵 [a,b,c,d,tx,ty]：stage = M × local。</summary>
        internal struct Mat
        {
            internal double A, B, C, D, Tx, Ty;

            internal static readonly Mat Identity = new Mat { A = 1, D = 1 };

            internal PointF Apply(double x, double y)
            {
                return new PointF((float)(A * x + C * y + Tx), (float)(B * x + D * y + Ty));
            }

            /// <summary>矩阵作用于局部矩形得到的舞台外接框（容忍 b/c 非 0）。</summary>
            internal RectangleF Apply(RectangleF r)
            {
                PointF p0 = Apply(r.Left, r.Top);
                PointF p1 = Apply(r.Right, r.Top);
                PointF p2 = Apply(r.Left, r.Bottom);
                PointF p3 = Apply(r.Right, r.Bottom);
                float x0 = Math.Min(Math.Min(p0.X, p1.X), Math.Min(p2.X, p3.X));
                float y0 = Math.Min(Math.Min(p0.Y, p1.Y), Math.Min(p2.Y, p3.Y));
                float x1 = Math.Max(Math.Max(p0.X, p1.X), Math.Max(p2.X, p3.X));
                float y1 = Math.Max(Math.Max(p0.Y, p1.Y), Math.Max(p2.Y, p3.Y));
                return RectangleF.FromLTRB(x0, y0, x1, y1);
            }
        }

        /// <summary>一个动态文本字段：局部文本空间 + 字段矩阵 + 舞台外接框。</summary>
        internal sealed class FieldSpec
        {
            internal string Id = "";
            internal Mat Matrix = Mat.Identity;
            internal float LocalW, LocalH;          // 字段局部宽/高（rect.w/h）
            // 保留作者的字段矩形与字号高度，字形等比绘制，避免姓名变宽、正文变瘦。
            internal float TextScale => Math.Max(0.0001f, (float)Math.Abs(Matrix.D));
            internal float TextLocalWidth => LocalW * (float)Math.Abs(Matrix.A) / TextScale;
            internal RectangleF Stage;              // stageRect（= Matrix×局部框）
            internal float FontSize;                // 局部字号（px）
            internal Color Color = Color.Black;
            internal bool Html;
            internal float Indent;
        }

        /// <summary>按钮：命中区（stageRect）+ 各态 SVG 与其舞台落位（matrix×viewBox）。</summary>
        internal sealed class ButtonSpec
        {
            internal string Id = "";
            internal Mat Matrix = Mat.Identity;
            internal RectangleF Hit;                // stageRect（全帧并集 = 原版可点区）
            internal float Alpha = 1f;
            internal byte[] UpSvg, OverSvg, DownSvg;
            internal RectangleF DestUp, DestOver, DestDown;   // 舞台逻辑坐标
        }

        // ── XFL 实测默认值（对话框界面 open 帧，stage 1024×576，与 layout.json 同源）──
        internal const float PanelX = 83.9f, PanelY = 400.55f, PanelW = 829.3f, PanelH = 189.4f;
        internal const float NextX = 95.95f, NextY = 438.98f, NextW = 800.93f, NextH = 143.12f;
        internal const float CloseX = 841.57f, CloseY = 339.57f, CloseW = 74.66f, CloseH = 82.34f;
        internal const float DragX = 25.72f, DragY = 382.26f, DragW = 74.88f, DragH = 82.66f;
        internal const float BodyX = 101.25f, BodyY = 443.3f, BodyW = 782.54f, BodyH = 118.36f;
        internal const float BodyLocalW = 573f, BodyLocalH = 72.65f, BodyFont = 12f;
        internal const double BodyA = 1.3656921, BodyD = 1.6292114;
        internal const float NameX = 109.65f, NameY = 406f, NameW = 227.9f, NameH = 31.7f;
        internal const float NameLocalW = 154.95f, NameLocalH = 31.7f, NameFont = 24f;
        internal const double NameA = 1.4708099;
        internal const float TitleX = 346.4f, TitleY = 418.25f, TitleW = 187.11f, TitleH = 18.45f;
        internal const float TitleLocalW = 162f, TitleLocalH = 18.45f, TitleFont = 14f;
        internal const double TitleA = 1.1550293;
        internal const float PortraitClipX = 30f, PortraitClipY = 30f;
        internal const float PortraitClipW = 880f, PortraitClipH = 389.35f;
        /// <summary>纸娃娃窗（对话框肖像 内部 mask）：local(-135,-257.3,425.2,365.25) 经实例
        /// tx=164.55,ty=298.25 → 舞台 (29.55,40.95)-(454.75,406.2)。</summary>
        internal const float DollClipX = 29.55f, DollClipY = 40.95f,
            DollClipW = 425.2f, DollClipH = 365.25f;
        /// <summary>立绘内容锚点：底 = external 烘焙窗口底（≈面板顶+5），中心 x = 原外部立绘典型内容心。</summary>
        internal const float PortraitBottom = 405f, PortraitCenterX = 325f;
        internal const float PortraitMaxW = 560f, PortraitMaxH = 352f;
        internal const float StageW = 1024f, StageH = 576f;

        private const string AssetSubDir = "dialogue-ui";
        private const int RasterCachePixelCap = 48 * 1024 * 1024;

        private byte[] _sourceSvg;
        private readonly Dictionary<string, Bitmap> _rasterCache = new Dictionary<string, Bitmap>(StringComparer.Ordinal);
        private long _rasterCachePixels;

        private DialogueUiSkin() { }

        internal FieldSpec Name { get; private set; }
        internal FieldSpec Title { get; private set; }
        internal FieldSpec Body { get; private set; }
        internal ButtonSpec Close { get; private set; }
        internal ButtonSpec Drag { get; private set; }
        internal RectangleF NextHit { get; private set; }
        internal RectangleF PanelArt { get; private set; }
        internal RectangleF PortraitClip { get; private set; }
        /// <summary>纸娃娃立绘窗：clips.internalPortraitClip（path bounds）或内置 XFL 实测值。</summary>
        internal RectangleF DollClip { get; private set; }
        /// <summary>layout.json buttonRendering=="separate"：source.svg 未烘焙按钮 up 态，
        /// 每帧需画所选状态；缺省/baked-up = up 态已在舞台美术内，仅叠画 over/down。</summary>
        internal bool ButtonsSeparate { get; private set; }
        internal bool HasStageArt { get { return _sourceSvg != null; } }

        /// <summary>无资产时的原版几何规格（值与 XFL/layout.json 同源）。</summary>
        internal static DialogueUiSkin CreateSpecOnly()
        {
            DialogueUiSkin s = new DialogueUiSkin();
            s.ApplyDefaultSpec();
            return s;
        }

        /// <summary>项目根 → launcher/web/assets/dialogue-ui。目录不存在返回 null。</summary>
        internal static DialogueUiSkin ForProjectRoot(string projectRoot)
        {
            if (string.IsNullOrEmpty(projectRoot)) return null;
            return TryLoad(Path.Combine(projectRoot, "launcher", "web", "assets", AssetSubDir));
        }

        /// <summary>
        /// 自 AppContext.BaseDirectory 向上找 launcher/web/assets/dialogue-ui/source.svg。
        /// 覆盖：runtime/x.exe → projectRoot；launcher/bin/... → projectRoot；tests/bin → projectRoot。
        /// 找不到返回 null（widget 走原版 fallback 装饰，不崩）。
        /// </summary>
        internal static DialogueUiSkin AutoDiscover()
        {
            try
            {
                string dir = AppContext.BaseDirectory;
                for (int i = 0; i < 10 && !string.IsNullOrEmpty(dir); i++)
                {
                    string cand = Path.Combine(dir, "launcher", "web", "assets", AssetSubDir);
                    if (File.Exists(Path.Combine(cand, "source.svg")))
                    {
                        DialogueUiSkin skin = TryLoad(cand);
                        if (skin != null) return skin;
                    }
                    DirectoryInfo parent = Directory.GetParent(dir);
                    dir = parent == null ? null : parent.FullName;
                }
            }
            catch { }
            return null;
        }

        /// <summary>加载资产目录；目录不存在返回 null。缺 layout.json 用内置实测值；缺 source.svg 仍可返回（HasStageArt=false）。</summary>
        internal static DialogueUiSkin TryLoad(string assetDir)
        {
            try
            {
                if (string.IsNullOrEmpty(assetDir) || !Directory.Exists(assetDir)) return null;
                DialogueUiSkin skin = new DialogueUiSkin();
                skin.ApplyDefaultSpec();

                string layoutPath = Path.Combine(assetDir, "layout.json");
                JObject layout = null;
                if (File.Exists(layoutPath))
                {
                    try { layout = JObject.Parse(File.ReadAllText(layoutPath, Encoding.UTF8)); }
                    catch { layout = null; }
                }
                if (layout != null) skin.ApplyLayout(layout, assetDir);
                else skin.LoadButtonsByConvention(assetDir);

                string sourcePath = Path.Combine(assetDir, "source.svg");
                if (File.Exists(sourcePath))
                {
                    try { skin._sourceSvg = File.ReadAllBytes(sourcePath); }
                    catch { skin._sourceSvg = null; }
                }
                return skin;
            }
            catch
            {
                return null;
            }
        }

        // ──────────────────────── 规格解析 ────────────────────────

        private void ApplyDefaultSpec()
        {
            Name = new FieldSpec
            {
                Id = "人物名字",
                Matrix = new Mat { A = NameA, D = 1, Tx = NameX, Ty = NameY },
                LocalW = NameLocalW, LocalH = NameLocalH,
                Stage = RectangleF.FromLTRB(NameX, NameY, NameX + NameW, NameY + NameH),
                FontSize = NameFont, Color = Color.White, Html = false
            };
            Title = new FieldSpec
            {
                Id = "人物称号",
                Matrix = new Mat { A = TitleA, D = 1, Tx = TitleX, Ty = TitleY },
                LocalW = TitleLocalW, LocalH = TitleLocalH,
                Stage = RectangleF.FromLTRB(TitleX, TitleY, TitleX + TitleW, TitleY + TitleH),
                FontSize = TitleFont, Color = Color.White, Html = true
            };
            Body = new FieldSpec
            {
                Id = "打字内容",
                Matrix = new Mat { A = BodyA, D = BodyD, Tx = BodyX, Ty = BodyY },
                LocalW = BodyLocalW, LocalH = BodyLocalH,
                Stage = RectangleF.FromLTRB(BodyX, BodyY, BodyX + BodyW, BodyY + BodyH),
                FontSize = BodyFont, Color = Color.Black, Html = true, Indent = 6f
            };
            Close = new ButtonSpec
            {
                Id = "close", Alpha = 0.8008f,
                Matrix = new Mat { A = 1.916672, D = 1.914825, Tx = 878.85, Ty = 380.45 },
                Hit = RectangleF.FromLTRB(CloseX, CloseY, CloseX + CloseW, CloseY + CloseH)
            };
            Drag = new ButtonSpec
            {
                Id = "drag", Alpha = 0.8008f,
                Matrix = new Mat { A = 1.922394, D = 1.922394, Tx = 63.4, Ty = 422.15 },
                Hit = RectangleF.FromLTRB(DragX, DragY, DragX + DragW, DragY + DragH)
            };
            NextHit = RectangleF.FromLTRB(NextX, NextY, NextX + NextW, NextY + NextH);
            PanelArt = RectangleF.FromLTRB(PanelX, PanelY, PanelX + PanelW, PanelY + PanelH);
            PortraitClip = RectangleF.FromLTRB(PortraitClipX, PortraitClipY,
                PortraitClipX + PortraitClipW, PortraitClipY + PortraitClipH);
            DollClip = RectangleF.FromLTRB(DollClipX, DollClipY,
                DollClipX + DollClipW, DollClipY + DollClipH);
        }

        private void ApplyLayout(JObject layout, string assetDir)
        {
            try
            {
                JArray fields = layout["fields"] as JArray;
                if (fields != null)
                {
                    foreach (JObject fo in fields.Children<JObject>())
                    {
                        FieldSpec f = ParseField(fo);
                        if (f == null) continue;
                        if (f.Id == "人物名字") Name = f;
                        else if (f.Id == "人物称号") Title = f;
                        else if (f.Id == "打字内容") Body = f;
                    }
                }
                if (string.Equals(layout.Value<string>("buttonRendering"),
                        "separate", StringComparison.Ordinal))
                    ButtonsSeparate = true;

                JArray buttons = layout["buttons"] as JArray;
                if (buttons != null)
                {
                    foreach (JObject bo in buttons.Children<JObject>())
                    {
                        string id = bo.Value<string>("id") ?? "";
                        bool hitOnly = bo.Value<bool?>("hitTestOnly") ?? false;
                        RectangleF hit = ParseStageRect(bo);
                        RectangleF hitOverride = ParseRectArray(bo["hitRect"] as JArray);
                        if (hitOverride != RectangleF.Empty) hit = hitOverride;
                        Mat m = ParseMat(bo["matrix"] as JArray, Mat.Identity);
                        if (id == "next" || (hitOnly && hit != RectangleF.Empty))
                        {
                            if (hit != RectangleF.Empty) NextHit = hit;
                            continue;
                        }
                        ButtonSpec b = new ButtonSpec { Id = id, Matrix = m, Hit = hit };
                        double? alpha = bo.Value<double?>("alpha");
                        if (alpha.HasValue) b.Alpha = (float)alpha.Value;
                        JObject states = bo["states"] as JObject;
                        // states 显式路径优先；缺键时回退 buttons/{id}-{state}.svg 约定
                        // （separate 合同的资产仍沿用同一目录约定）。
                        b.UpSvg = ReadState(assetDir, states, "up")
                            ?? ReadFileSafe(Path.Combine(assetDir, "buttons", id + "-up.svg"));
                        b.OverSvg = ReadState(assetDir, states, "over")
                            ?? ReadFileSafe(Path.Combine(assetDir, "buttons", id + "-over.svg"));
                        b.DownSvg = ReadState(assetDir, states, "down")
                            ?? ReadFileSafe(Path.Combine(assetDir, "buttons", id + "-down.svg"));
                        b.DestUp = DestFor(b, b.UpSvg);
                        b.DestOver = DestFor(b, b.OverSvg);
                        b.DestDown = DestFor(b, b.DownSvg);
                        if (id == "close") Close = b;
                        else if (id == "drag") Drag = b;
                    }
                }
                JObject clips = layout["clips"] as JObject;
                string clipPath = clips == null ? null : clips.Value<string>("portraitClip");
                RectangleF clipBounds;
                if (!string.IsNullOrEmpty(clipPath) && TryPathBounds(clipPath, out clipBounds))
                    PortraitClip = clipBounds;
                string dollPath = clips == null ? null : clips.Value<string>("internalPortraitClip");
                if (!string.IsNullOrEmpty(dollPath) && TryPathBounds(dollPath, out clipBounds))
                    DollClip = clipBounds;
            }
            catch
            {
                // 单字段解析失败不致命：保留已应用项与默认值。
            }
        }

        private void LoadButtonsByConvention(string assetDir)
        {
            LoadButtonConventional(Drag, assetDir);
            LoadButtonConventional(Close, assetDir);
        }

        private static void LoadButtonConventional(ButtonSpec b, string assetDir)
        {
            if (b == null) return;
            b.UpSvg = ReadFileSafe(Path.Combine(assetDir, "buttons", b.Id + "-up.svg"));
            b.OverSvg = ReadFileSafe(Path.Combine(assetDir, "buttons", b.Id + "-over.svg"));
            b.DownSvg = ReadFileSafe(Path.Combine(assetDir, "buttons", b.Id + "-down.svg"));
            b.DestUp = DestFor(b, b.UpSvg);
            b.DestOver = DestFor(b, b.OverSvg);
            b.DestDown = DestFor(b, b.DownSvg);
        }

        private static byte[] ReadState(string assetDir, JObject states, string name)
        {
            string rel = states == null ? null : states.Value<string>(name);
            if (string.IsNullOrEmpty(rel)) return null;
            return ReadFileSafe(Path.Combine(assetDir, rel.Replace('/', Path.DirectorySeparatorChar)));
        }

        private static byte[] ReadFileSafe(string path)
        {
            try { return File.Exists(path) ? File.ReadAllBytes(path) : null; }
            catch { return null; }
        }

        private static FieldSpec ParseField(JObject fo)
        {
            string id = fo.Value<string>("id");
            if (string.IsNullOrEmpty(id)) return null;
            FieldSpec f = new FieldSpec { Id = id };
            f.Matrix = ParseMat(fo["matrix"] as JArray, Mat.Identity);
            f.Stage = ParseStageRect(fo);
            JObject rect = fo["rect"] as JObject;
            if (rect != null)
            {
                f.LocalW = (float)(rect.Value<double?>("w") ?? 0);
                f.LocalH = (float)(rect.Value<double?>("h") ?? 0);
            }
            if (f.LocalW <= 0 && f.Stage.Width > 0) f.LocalW = f.Stage.Width;
            if (f.LocalH <= 0 && f.Stage.Height > 0) f.LocalH = f.Stage.Height;
            JObject font = fo["font"] as JObject;
            if (font != null)
            {
                f.FontSize = (float)(font.Value<double?>("size") ?? 12);
                string color = font.Value<string>("color");
                if (!string.IsNullOrEmpty(color)) f.Color = ParseHexColor(color, f.Color);
            }
            f.Html = fo.Value<bool?>("html") ?? false;
            f.Indent = (float)(fo.Value<double?>("indent") ?? 0);
            return f;
        }

        private static Mat ParseMat(JArray a, Mat fallback)
        {
            if (a == null || a.Count < 6) return fallback;
            return new Mat
            {
                A = a[0].Value<double>(), B = a[1].Value<double>(),
                C = a[2].Value<double>(), D = a[3].Value<double>(),
                Tx = a[4].Value<double>(), Ty = a[5].Value<double>()
            };
        }

        private static RectangleF ParseStageRect(JObject o)
        {
            return ParseRectArray(o["stageRect"] as JArray);
        }

        /// <summary>[left,top,right,bottom] 数组 → 矩形；缺/短 → Empty。</summary>
        private static RectangleF ParseRectArray(JArray r)
        {
            if (r == null || r.Count < 4) return RectangleF.Empty;
            return RectangleF.FromLTRB(
                (float)r[0].Value<double>(), (float)r[1].Value<double>(),
                (float)r[2].Value<double>(), (float)r[3].Value<double>());
        }

        private static Color ParseHexColor(string s, Color fallback)
        {
            int v;
            if (s != null && s.StartsWith("#", StringComparison.Ordinal)
                && int.TryParse(s.Substring(1), NumberStyles.HexNumber, CultureInfo.InvariantCulture, out v))
                return Color.FromArgb(255, (v >> 16) & 0xFF, (v >> 8) & 0xFF, v & 0xFF);
            return fallback;
        }

        /// <summary>按钮态 SVG viewBox（局部坐标）经按钮矩阵 → 舞台落位。无 viewBox 用命中区近似。</summary>
        private static RectangleF DestFor(ButtonSpec b, byte[] svgBytes)
        {
            RectangleF vb;
            if (svgBytes != null && TryViewBox(svgBytes, out vb))
                return b.Matrix.Apply(vb);
            return b.Hit;
        }

        private static readonly Regex ViewBoxRe = new Regex(
            "viewBox\\s*=\\s*\"\\s*(-?[\\d.eE+-]+)[ ,]+(-?[\\d.eE+-]+)[ ,]+(-?[\\d.eE+-]+)[ ,]+(-?[\\d.eE+-]+)",
            RegexOptions.Compiled);

        private static bool TryViewBox(byte[] svgBytes, out RectangleF vb)
        {
            vb = RectangleF.Empty;
            Match m = ViewBoxRe.Match(Encoding.UTF8.GetString(svgBytes, 0, Math.Min(svgBytes.Length, 2048)));
            if (!m.Success) return false;
            float x, y, w, h;
            if (!float.TryParse(m.Groups[1].Value, NumberStyles.Float, CultureInfo.InvariantCulture, out x)
                || !float.TryParse(m.Groups[2].Value, NumberStyles.Float, CultureInfo.InvariantCulture, out y)
                || !float.TryParse(m.Groups[3].Value, NumberStyles.Float, CultureInfo.InvariantCulture, out w)
                || !float.TryParse(m.Groups[4].Value, NumberStyles.Float, CultureInfo.InvariantCulture, out h)
                || w <= 0 || h <= 0) return false;
            vb = new RectangleF(x, y, w, h);
            return true;
        }

        private static readonly Regex PathPairRe = new Regex(
            "(-?\\d+\\.?\\d*(?:[eE][+-]?\\d+)?)[ ,]+(-?\\d+\\.?\\d*(?:[eE][+-]?\\d+)?)",
            RegexOptions.Compiled);

        /// <summary>取 SVG path 全部数对的外接框（mask 矩形近似用；控制点外扩少量可接受）。</summary>
        private static bool TryPathBounds(string path, out RectangleF bounds)
        {
            bounds = RectangleF.Empty;
            if (string.IsNullOrEmpty(path)) return false;
            float x0 = float.MaxValue, y0 = float.MaxValue, x1 = float.MinValue, y1 = float.MinValue;
            bool any = false;
            foreach (Match m in PathPairRe.Matches(path))
            {
                float x, y;
                if (!float.TryParse(m.Groups[1].Value, NumberStyles.Float, CultureInfo.InvariantCulture, out x)
                    || !float.TryParse(m.Groups[2].Value, NumberStyles.Float, CultureInfo.InvariantCulture, out y))
                    continue;
                any = true;
                if (x < x0) x0 = x; if (x > x1) x1 = x;
                if (y < y0) y0 = y; if (y > y1) y1 = y;
            }
            if (!any || x1 <= x0 || y1 <= y0) return false;
            bounds = RectangleF.FromLTRB(x0, y0, x1, y1);
            return true;
        }

        // ──────────────────────── 光栅化（按目标像素缓存） ────────────────────────

        /// <summary>整幅舞台装饰：按 scale 光栅化为 1024·scale × 576·scale 位图；null = 无资产。</summary>
        internal Bitmap RasterStage(float scale)
        {
            if (_sourceSvg == null || scale <= 0) return null;
            int w = Math.Max(1, (int)Math.Round(StageW * scale));
            int h = Math.Max(1, (int)Math.Round(StageH * scale));
            string key = "stage:" + w + "x" + h;
            Bitmap bmp;
            if (_rasterCache.TryGetValue(key, out bmp)) return bmp;
            bmp = RasterizeSvg(_sourceSvg, w, h, fillNonUniform: true);
            if (bmp != null) CachePut(key, bmp);
            return bmp;
        }

        /// <summary>按钮态：state 0=up 1=over 2=down。返回按 scale 光栅化的位图与舞台逻辑落位。</summary>
        internal Bitmap RasterButton(ButtonSpec b, int state, float scale, out RectangleF stageDest)
        {
            byte[] bytes; RectangleF dest;
            if (state == 1) { bytes = b.OverSvg; dest = b.DestOver; }
            else if (state == 2) { bytes = b.DownSvg; dest = b.DestDown; }
            else { bytes = b.UpSvg; dest = b.DestUp; }
            stageDest = dest;
            if (bytes == null || scale <= 0 || dest.Width <= 0 || dest.Height <= 0) return null;
            int w = Math.Max(1, (int)Math.Round(dest.Width * scale));
            int h = Math.Max(1, (int)Math.Round(dest.Height * scale));
            string key = b.Id + ":" + state + ":" + w + "x" + h;
            Bitmap bmp;
            if (_rasterCache.TryGetValue(key, out bmp)) return bmp;
            bmp = RasterizeSvg(bytes, w, h, fillNonUniform: true);
            if (bmp != null) CachePut(key, bmp);
            return bmp;
        }

        private void CachePut(string key, Bitmap bmp)
        {
            long px = (long)bmp.Width * bmp.Height;
            if (_rasterCachePixels + px > RasterCachePixelCap)
            {
                foreach (Bitmap old in _rasterCache.Values) old.Dispose();
                _rasterCache.Clear();
                _rasterCachePixels = 0;
            }
            _rasterCache[key] = bmp;
            _rasterCachePixels += px;
        }

        /// <summary>
        /// Svg.Skia 光栅化（生命周期严格对齐 LootIconCatalog.RenderSvg 已验证路径）：
        /// SKSvg 必须存活到 DrawPicture 完成；&lt;filter&gt; 整体剥离（native 崩溃规避，丢投影可接受）；
        /// SecureStatic + 禁外部资源，离线无脚本。fillNonUniform：把 CullRect 精确铺满 w×h。
        /// </summary>
        private static Bitmap RasterizeSvg(byte[] svgBytes, int w, int h, bool fillNonUniform)
        {
            if (svgBytes == null || w <= 0 || h <= 0) return null;
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

                string svgText = LootIconCatalog.StripSvgFilters(Encoding.UTF8.GetString(svgBytes));
                SKPicture picture;
                using (MemoryStream stream = new MemoryStream(Encoding.UTF8.GetBytes(svgText), writable: false))
                    picture = svg.Load(stream, parameters, new Uri("urn:cf7:dialogue-ui"));
                if (picture == null) return null;
                try
                {
                    SKRect bounds = picture.CullRect;
                    if (bounds.Width <= 0 || bounds.Height <= 0) return null;
                    float sx = w / bounds.Width;
                    float sy = fillNonUniform ? h / bounds.Height : sx;
                    float tx = -bounds.Left * sx;
                    float ty = -bounds.Top * sy;

                    Bitmap result = new Bitmap(w, h, PixelFormat.Format32bppPArgb);
                    try
                    {
                        using (SKBitmap skBitmap = new SKBitmap(w, h, SKColorType.Bgra8888, SKAlphaType.Premul))
                        {
                            using (SKCanvas canvas = new SKCanvas(skBitmap))
                            {
                                canvas.Clear(SKColors.Transparent);
                                canvas.Translate(tx, ty);
                                canvas.Scale(sx, sy);
                                canvas.DrawPicture(picture);
                                canvas.Flush();
                            }
                            BitmapData data = result.LockBits(
                                new Rectangle(0, 0, w, h),
                                ImageLockMode.WriteOnly,
                                PixelFormat.Format32bppPArgb);
                            try
                            {
                                if (data.Stride <= 0)
                                    throw new InvalidOperationException("Unexpected negative bitmap stride");
                                bool ok = skBitmap.PeekPixels().ReadPixels(
                                    new SKImageInfo(w, h, SKColorType.Bgra8888, SKAlphaType.Premul),
                                    data.Scan0, data.Stride, 0, 0);
                                if (!ok) throw new InvalidOperationException("ReadPixels failed");
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
                        return null;
                    }
                }
                finally
                {
                    picture.Dispose();
                }
            }
            catch
            {
                return null;
            }
            finally
            {
                svg.Dispose();
            }
        }

        public void Dispose()
        {
            foreach (Bitmap bmp in _rasterCache.Values) bmp.Dispose();
            _rasterCache.Clear();
            _rasterCachePixels = 0;
            _sourceSvg = null;
        }
    }
}
