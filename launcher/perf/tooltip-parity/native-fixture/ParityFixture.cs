// tooltip-parity 原生侧 fixture：真实生产 NativeTooltipWidget 离屏 Form 绘制。
// 输入 samples.json + scenarios.json（与 web-shoot 同源），逐 case 输出
// native.png（viewport 尺寸画布）+ native.json（Plan 几何/文本行/滚动数据）。
// 不运行游戏、不触碰共享构建；几何均归一到画布坐标（Flash 逻辑 px @ viewport）。
using System;
using System.Collections.Generic;
using System.Drawing;
using System.IO;
using System.Text;
using System.Windows.Forms;
using CF7Launcher.Fonts;
using CF7Launcher.Guardian.Hud.Loot;
using CF7Launcher.Guardian.Hud.Tooltip;
using Newtonsoft.Json;
using Newtonsoft.Json.Linq;

internal static class ParityFixture
{
    // 与 web fixture 画布底色一致（#181A1C）。
    private static readonly Color CanvasBg = Color.FromArgb(255, 24, 26, 28);

    [STAThread]
    private static int Main(string[] args)
    {
        string samplesPath = Arg(args, "--samples", true);
        string scenariosPath = Arg(args, "--scenarios", true);
        string outDir = Arg(args, "--out", true);
        string repo = Arg(args, "--repo", false)
            ?? Path.GetFullPath(Path.Combine(Directory.GetCurrentDirectory(), "..", "..", "..", "..", ".."));
        Directory.CreateDirectory(outDir);

        RuntimeFontCatalog.Configure(repo);
        Console.WriteLine("fontCatalog ready=" + RuntimeFontCatalog.IsReady
            + " failure=" + (RuntimeFontCatalog.Failure ?? "-"));

        string casesArg = Arg(args, "--cases", false);
        HashSet<string> caseFilter = casesArg == null ? null
            : new HashSet<string>(casesArg.Split(','));

        JObject samplesDoc = JObject.Parse(File.ReadAllText(samplesPath));
        JObject scenariosDoc = JObject.Parse(File.ReadAllText(scenariosPath));
        JArray samples = (JArray)samplesDoc["samples"];
        JArray scenarios = (JArray)scenariosDoc["scenarios"];

        string iconsDir = Path.Combine(repo, "launcher", "web", "icons");
        string portraitsDir = Path.Combine(repo, "launcher", "web", "assets", "enemy-portraits");
        string dollDir = Path.Combine(repo, "launcher", "data", "doll-portraits");

        using (LootIconCatalog icons = new LootIconCatalog(iconsDir, portraitsDir, dollPortraitsDir: dollDir))
        using (Form hostForm = new Form())
        {
            hostForm.FormBorderStyle = FormBorderStyle.None;
            hostForm.StartPosition = FormStartPosition.Manual;
            hostForm.Location = new Point(-30000, -30000);
            // 宿主 Form 固定小尺寸：顶层窗口 ClientSize 会被 OS 工作区钳制
            // （请求 1080 实测 980 → plan.Scale=1.134 vs web 1.25）。
            // anchor 为非 dock 子控件，按场景显式 Size——子控件可超出顶层工作区，
            // 位图由 widget.Paint 直接渲染，不受 OS 裁剪影响。
            hostForm.ClientSize = new Size(640, 480);
            hostForm.ShowInTaskbar = false;
            hostForm.Opacity = 0;
            Control anchor = new Control { Location = Point.Empty };
            hostForm.Controls.Add(anchor);
            hostForm.Show();
            anchor.CreateControl();

            // 与 Edge deviceScaleFactor 同源；生产默认值仍读取 owner.DeviceDpi。
            float scenarioDpiScale = 1f;
            using (NativeTooltipWidget widget = new NativeTooltipWidget(anchor, icons, () => scenarioDpiScale))
            {
                foreach (JObject sample in samples)
                {
                    foreach (JObject scenario in scenarios)
                    {
                        string cid = CaseId(sample, scenario);
                        if (caseFilter != null && !caseFilter.Contains(cid)) continue;
                        try
                        {
                            scenarioDpiScale = (float)(scenario["viewport"]?["dpi"] ?? 1);
                            if (!float.IsFinite(scenarioDpiScale) || scenarioDpiScale < 1f || scenarioDpiScale > 3f)
                                throw new InvalidOperationException("Invalid scenario DPI");
                            RunCase(widget, icons, hostForm, anchor, sample, scenario, cid, outDir);
                        }
                        catch (Exception ex)
                        {
                            Console.WriteLine("[native] " + cid + " ERROR " + ex.Message);
                            string caseDir = Path.Combine(outDir, "cases", cid);
                            Directory.CreateDirectory(caseDir);
                            File.WriteAllText(Path.Combine(caseDir, "native.json"),
                                JsonConvert.SerializeObject(new { caseId = cid, error = ex.ToString() }, Formatting.Indented));
                        }
                    }
                }
            }
        }
        Console.WriteLine("native fixture done → " + outDir);
        return 0;
    }

    private static void RunCase(NativeTooltipWidget widget, LootIconCatalog icons,
        Form hostForm, Control anchor, JObject sample, JObject scenario, string cid, string outDir)
    {
        int vw = (int)(scenario["viewport"]?["w"] ?? 1024);
        int vh = (int)(scenario["viewport"]?["h"] ?? 576);
        if (anchor.Width != vw || anchor.Height != vh)
            anchor.Size = new Size(vw, vh);
        // 硬断言：fixture 视口必须等于请求值，否则 plan.Scale/placement 静默失真。
        if (anchor.ClientSize.Width != vw || anchor.ClientSize.Height != vh)
            throw new InvalidOperationException("anchor viewport clamped: requested " + vw + "x" + vh
                + " actual " + anchor.ClientSize.Width + "x" + anchor.ClientSize.Height);
        Point canvasOrigin = anchor.PointToScreen(Point.Empty);

        widget.Reset();
        JObject payload = BuildPayload(sample, scenario, cid);
        bool shown = payload != null && widget.Show(payload);
        int scrollLines = (int)(scenario["scrollLines"] ?? 0);
        for (int i = 0; i < scrollLines; i++) widget.ScrollByLines(1);

        // 滚动可达性：逐项推进到底，验证 MaxScrollLine 真实可达。
        int requestedScrollOffset = widget.ScrollLineOffset;
        bool reachBottom = true;
        int guard = 0;
        if (widget.Scrollable)
        {
            while (widget.ScrollLineOffset < widget.MaxScrollLine && guard++ < 512)
                if (!widget.ScrollByLines(1)) break;
            reachBottom = widget.ScrollLineOffset == widget.MaxScrollLine;
            // 与 Web 的读后恢复一致：可达性探针不得改变待截图的请求滚动位置。
            widget.ScrollByLines(requestedScrollOffset - widget.ScrollLineOffset);
            if (widget.ScrollLineOffset != requestedScrollOffset)
                throw new InvalidOperationException("Scroll reachability probe did not restore the requested offset");
        }

        Rectangle placed = widget.ScreenBounds;
        Rectangle placedCanvas = new Rectangle(placed.X - canvasOrigin.X, placed.Y - canvasOrigin.Y,
            placed.Width, placed.Height);
        var plan = widget.ActivePlan;
        var doc = widget.ActiveDocument;

        var geo = new JObject
        {
            ["shown"] = shown && widget.Visible,
            ["dpiProbe"] = new JObject {
                ["injectedDpiScale"] = (float)(scenario["viewport"]?["dpi"] ?? 1),
                ["actualHostDeviceDpi"] = anchor.DeviceDpi,
                ["physicalWidth"] = anchor.ClientSize.Width,
                ["physicalHeight"] = anchor.ClientSize.Height
            },
            ["profile"] = doc != null ? ProfileName(doc.Profile) : null,
            ["layoutType"] = doc != null ? doc.LayoutType : null,
            ["placement"] = plan != null ? plan.Side : null,
            ["tooltipRect"] = RectJson(placedCanvas),
            ["introPanelRect"] = plan != null ? RectJson(Offset(plan.IntroPanel, placedCanvas)) : null,
            ["descPanelRect"] = plan != null && !plan.DescPanel.IsEmpty
                ? RectJson(Offset(plan.DescPanel, placedCanvas)) : null,
            ["iconRect"] = plan != null && !plan.IconRect.IsEmpty
                ? RectJson(Offset(plan.IconRect, placedCanvas)) : null,
            ["scrollViewportRect"] = plan != null && !plan.ScrollViewportRect.IsEmpty
                ? RectJson(Offset(plan.ScrollViewportRect, placedCanvas)) : null,
            ["layout"] = plan == null ? null : new JObject
            {
                ["split"] = plan.Split,
                ["merge"] = !plan.Split,
                ["stacked"] = plan.Stacked,
                ["pinned"] = plan.Pinned,
                ["plain"] = plan.Plain,
                ["wide"] = plan.LayoutWide
            },
            ["text"] = new JObject
            {
                ["title"] = plan != null ? plan.Title : (doc != null ? doc.Title : null),
                ["intro"] = plan != null ? LinesJson(plan.IntroLines) : null,
                ["desc"] = plan != null ? LinesJson(plan.DescLines) : null
            },
            ["scroll"] = new JObject
            {
                ["scrollable"] = widget.Scrollable,
                ["totalLines"] = plan != null ? plan.DescTotalLines : 0,
                ["visibleLines"] = plan != null ? plan.DescVisibleLines : 0,
                ["scrollLine"] = widget.ScrollLineOffset,
                ["maxScrollLine"] = widget.MaxScrollLine,
                ["reachBottom"] = reachBottom
            },
            ["lineHeightPx"] = plan != null
                ? new JObject { ["intro"] = plan.LineHeightIntroPx, ["desc"] = plan.LineHeightDescPx }
                : null,
            ["scale"] = plan != null ? (double)plan.Scale : 0,
            ["iconSource"] = IconSource(icons, plan != null ? plan.IconName : null)
        };

        using (Bitmap canvas = new Bitmap(vw, vh, System.Drawing.Imaging.PixelFormat.Format32bppArgb))
        using (Graphics g = Graphics.FromImage(canvas))
        {
            g.Clear(CanvasBg);
            if (shown) widget.Paint(g, 1.0f, canvasOrigin);
            string caseDir = Path.Combine(outDir, "cases", cid);
            Directory.CreateDirectory(caseDir);
            canvas.Save(Path.Combine(caseDir, "native.png"), System.Drawing.Imaging.ImageFormat.Png);
            File.WriteAllText(Path.Combine(caseDir, "native.json"), JsonConvert.SerializeObject(new
            {
                caseId = cid,
                sampleId = (string)sample["id"],
                scenarioId = (string)scenario["id"],
                viewport = new { w = vw, h = vh },
                anchor = scenario["anchor"],
                geometry = geo
            }, Formatting.Indented));
        }
        Console.WriteLine("[native] " + cid + " shown=" + shown + " side=" + geo["placement"]
            + " tip=" + placedCanvas.Width + "x" + placedCanvas.Height);
    }

    private static JObject BuildPayload(JObject sample, JObject scenario, string cid)
    {
        JObject document = sample["document"] != null
            ? (JObject)sample["document"].DeepClone() : null;
        if (document == null) return null;
        string profile = (string)(scenario["profile"] ?? document["profile"]);
        if (!string.IsNullOrEmpty(profile)) document["profile"] = profile;
        var anchor = scenario["anchor"];
        var payload = new JObject
        {
            ["version"] = 1,
            ["kind"] = "tooltip",
            ["op"] = "show",
            ["requestId"] = "parity-" + cid,
            ["sceneId"] = "parity",
            ["x"] = anchor != null ? (double?)anchor["x"] : null,
            ["y"] = anchor != null ? (double?)anchor["y"] : null,
            ["document"] = document
        };
        if (scenario["anchorRect"] is JObject) payload["anchorRect"] = scenario["anchorRect"].DeepClone();
        if (scenario["placement"] != null) payload["placement"] = scenario["placement"].DeepClone();
        return payload;
    }

    private static string ProfileName(NativeTooltipProfile p)
    {
        switch (p)
        {
            case NativeTooltipProfile.Simple: return "simple-tooltip";
            case NativeTooltipProfile.Pinned: return "pinned-inspector";
            default: return "dense-inspect";
        }
    }


    private static JObject IconSource(LootIconCatalog icons, string iconName)
    {
        if (string.IsNullOrEmpty(iconName) || icons == null) return null;
        LootIconCatalog.LootIconFrames frames;
        if (!icons.TryGet(iconName, out frames) || frames == null || frames.First == null) return null;
        return new JObject { ["name"] = iconName, ["w"] = frames.First.Width, ["h"] = frames.First.Height };
    }

    private static JArray LinesJson(List<NativeTooltipLayout.VisualLine> lines)
    {
        var arr = new JArray();
        if (lines == null) return arr;
        foreach (var vl in lines)
        {
            if (vl.IsBlank) continue;
            var sb = new StringBuilder();
            if (vl.Slices != null)
                foreach (var s in vl.Slices) sb.Append(s.Text);
            string t = sb.ToString().Replace("\r", "");
            if (t.TrimEnd(' ', '\t', ' ').Length > 0) arr.Add(t);
        }
        return arr;
    }

    private static Rectangle Offset(Rectangle r, Rectangle origin)
    {
        return new Rectangle(r.X + origin.X, r.Y + origin.Y, r.Width, r.Height);
    }

    private static JObject RectJson(Rectangle r)
    {
        return new JObject
        {
            ["left"] = r.Left, ["top"] = r.Top,
            ["right"] = r.Right, ["bottom"] = r.Bottom,
            ["width"] = r.Width, ["height"] = r.Height
        };
    }

    private static string CaseId(JObject sample, JObject scenario)
    {
        string raw = Convert.ToString(sample["id"]) + "__" + Convert.ToString(scenario["id"]);
        var chars = raw.ToCharArray();
        for (int i = 0; i < chars.Length; i++)
            if (!(char.IsLetterOrDigit(chars[i]) || chars[i] == '-' || chars[i] == '_' || chars[i] == '.'))
                chars[i] = '_';
        return new string(chars);
    }

    private static string Arg(string[] args, string name, bool required)
    {
        for (int i = 0; i < args.Length - 1; i++)
            if (args[i] == name) return args[i + 1];
        if (required) throw new ArgumentException("missing " + name);
        return null;
    }
}
