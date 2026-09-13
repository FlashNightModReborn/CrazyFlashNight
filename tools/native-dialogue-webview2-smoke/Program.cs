using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Drawing;
using System.Drawing.Imaging;
using System.IO;
using System.Linq;
using System.Reflection;
using System.Security.Cryptography;
using System.Threading.Tasks;
using System.Windows.Forms;
using Microsoft.Web.WebView2.Core;
using Microsoft.Web.WebView2.WinForms;
using Newtonsoft.Json.Linq;
using CF7Launcher.Guardian.Hud.Dialogue;

internal sealed class SmokeForm : Form
{
    private readonly string root;
    private readonly string output;
    private readonly WebView2 web = new WebView2 { Dock = DockStyle.Fill };
    private readonly List<object> results = new List<object>();
    private object service;
    private Type serviceType;
    private int posted;
    private bool hidden;
    private readonly TaskCompletionSource<JObject> legacyResult = new TaskCompletionSource<JObject>(TaskCreationOptions.RunContinuationsAsynchronously);

    [STAThread]
    private static void Main(string[] args)
    {
        if (args.Length != 2) { Environment.ExitCode = 2; return; }
        Application.EnableVisualStyles();
        Application.Run(new SmokeForm(Path.GetFullPath(args[0]), Path.GetFullPath(args[1])));
    }

    private SmokeForm(string root, string output)
    {
        this.root = root; this.output = output;
        Directory.CreateDirectory(output);
        ShowInTaskbar = false; Opacity = 0; Width = 1024; Height = 576;
        Controls.Add(web);
        Shown += async (_, _) => await Run();
    }

    private async Task Run()
    {
        try
        {
            var env = await CoreWebView2Environment.CreateAsync(null, Path.Combine(output, "profile"));
            await web.EnsureCoreWebView2Async(env);
            web.CoreWebView2.SetVirtualHostNameToFolderMapping("u2.local", root, CoreWebView2HostResourceAccessKind.Allow);
            web.CoreWebView2.WebMessageReceived += (_, e) =>
            {
                var message = JObject.Parse(e.WebMessageAsJson);
                if (message.Value<string>("task") == "doll_bake_result")
                {
                    legacyResult.TrySetResult(message["payload"] as JObject);
                    return;
                }
                if (message.Value<string>("task") != "dialogue_portrait_result") return;
                InvokeService("HandleResult", message);
            };
            serviceType = typeof(NativeDialogueFrame).Assembly.GetType("CF7Launcher.Guardian.Dialogue.DialoguePortraitService", true);
            service = CreateService();
            var navigation = new TaskCompletionSource<bool>();
            web.CoreWebView2.NavigationCompleted += (_, e) => navigation.TrySetResult(e.IsSuccess);
            web.CoreWebView2.Navigate("https://u2.local/tools/native-dialogue-webview2-smoke/fixture.html");
            if (!await navigation.Task.WaitAsync(TimeSpan.FromSeconds(30))) throw new Exception("fixture navigation failed");
            Hide(); hidden = !Visible;
            await Task.Delay(200);
            await Render("male-normal", "男", "普通");
            await Render("male-angry", "男", "愤怒");
            await Render("female-normal", "女", "普通");
            await Render("male-armored", "男", "普通", new JObject {
                ["gender"] = "男", ["face"] = "1", ["hair"] = "3", ["mask"] = "",
                ["head"] = "钛合金61式头部装甲", ["body"] = "钛合金61式胸甲",
                ["leg"] = "钛合金61式腿甲", ["hand"] = "钛合金61式手甲",
                ["foot"] = "钛合金61式装甲鞋", ["neck"] = ""
            });
            int beforeCache = posted;
            await Render("male-normal-cached", "男", "普通");
            if (posted != beforeCache) throw new Exception("Same identity failed to hit Host bitmap cache");
            string normal = Hash(Path.Combine(output, "male-normal.png"));
            if (normal == Hash(Path.Combine(output, "male-angry.png"))) throw new Exception("Requested face expressions produced identical pixels");
            if (normal == Hash(Path.Combine(output, "female-normal.png"))) throw new Exception("Independent actors produced identical pixels");
            if (normal != Hash(Path.Combine(output, "male-normal-cached.png"))) throw new Exception("Cached pixels changed");
            string diskDirectory = Path.Combine(output, "cache-root", "launcher", "data", "dialogue-portraits");
            for (int wait = 0; wait < 100 && (!Directory.Exists(diskDirectory)
                    || Directory.GetFiles(diskDirectory, "*.png").Length < 4); wait++) await Task.Delay(25);
            if (!Directory.Exists(diskDirectory) || Directory.GetFiles(diskDirectory, "*.png").Length != 4)
                throw new Exception("Expected four validated disk cache entries");
            (service as IDisposable)?.Dispose();
            service = CreateService();
            await Render("male-normal-disk", "男", "普通");
            if (posted != beforeCache || normal != Hash(Path.Combine(output, "male-normal-disk.png")))
                throw new Exception("New service did not reuse identical disk-cached pixels");
            await RenderLegacyIcon();
            await RenderStatic("Pig", "普通", "pig");
            await RenderStatic("Blue", "普通", "blue");
            await RenderStatic("The Girl", "普通", "the-girl");
            await RenderStatic("武器大师", "普通", "weapon-master");
            await RenderStatic("室友-男", "普通", "roommate-male");
            await RenderStatic("室友-女", "普通", "roommate-female");
            await RenderStatic("artist", "愤怒", "artist-angry");
            await RenderStatic("Andy Law", "微笑2", "andy-type2");
            File.WriteAllText(Path.Combine(output, "result.json"), JObject.FromObject(new
            {
                status = "hidden_webview2_portrait_smoke_passed", hidden, posted, diskCacheCrossInstance = true,
                browserVersion = env.BrowserVersionString, results,
                assemblyPath = typeof(NativeDialogueFrame).Assembly.Location,
                assemblySha256 = Hash(typeof(NativeDialogueFrame).Assembly.Location),
                dressupManifestSha256 = Hash(Path.Combine(root, "launcher/web/assets/dressup/manifest.json")),
                portraitManifestSha256 = Hash(Path.Combine(root, "launcher/web/assets/dialogue-portraits/manifest.json")),
                uiManifestSha256 = Hash(Path.Combine(root, "launcher/web/assets/dialogue-ui/manifest.json")),
                scope = "Hidden WebView2 fixture, production portrait decoding and NativeHud bitmap paint; not a player dialogue, physical-input or save journey"
            }).ToString());
        }
        catch (Exception error)
        {
            File.WriteAllText(Path.Combine(output, "failure.txt"), error.ToString());
            Environment.ExitCode = 1;
        }
        finally { (service as IDisposable)?.Dispose(); web.Dispose(); Close(); }
    }

    private object CreateService()
    {
        return Activator.CreateInstance(serviceType, BindingFlags.Instance | BindingFlags.NonPublic, null,
                new object[] { root, new Func<string, bool>(wire =>
                {
                    if (!hidden) throw new InvalidOperationException("Renderer must run after the window is hidden");
                    posted++;
                    BeginInvoke(new Action(() => web.CoreWebView2.PostWebMessageAsJson(wire)));
                    return true;
                }), Path.Combine(output, "cache-root") }, null);
    }

    private object InvokeService(string method, params object[] args)
    {
        return serviceType.GetMethods(BindingFlags.Instance | BindingFlags.NonPublic | BindingFlags.Public)
            .Single(candidate => candidate.Name == method
                && candidate.GetParameters().Length == args.Length
                && candidate.GetParameters().Zip(args, (parameter, value) =>
                    value == null || parameter.ParameterType.IsInstanceOfType(value)).All(match => match))
            .Invoke(service, args);
    }

    private async Task Render(string name, string gender, string expression, JObject appearanceOverride = null)
    {
        var tcs = new TaskCompletionSource<(Bitmap Image, RectangleF? StageRect)>(TaskCreationOptions.RunContinuationsAsynchronously);
        var frame = new NativeDialogueFrame { RequestId = "nd:1", SceneId = "fixture", Revision = results.Count + 1,
            IsDoll = true, PortraitKey = "hero", Expression = expression };
        var appearance = appearanceOverride ?? new JObject { ["gender"] = gender, ["face"] = gender == "男" ? "1" : "0", ["hair"] = "" };
        var latency = Stopwatch.StartNew();
        InvokeService("LoadPortrait", frame, appearance,
            new Action<Bitmap, RectangleF?>((bitmap, rect) => tcs.TrySetResult((bitmap, rect))));
        var loaded = await tcs.Task.WaitAsync(TimeSpan.FromSeconds(25));
        double loadMs = latency.Elapsed.TotalMilliseconds;
        using (Bitmap bitmap = loaded.Image)
        {
            if (bitmap.Width != 768 || bitmap.Height != 768) throw new Exception("Unexpected PNG dimensions");
            int alpha = 0;
            for (int y = 0; y < bitmap.Height; y++)
                for (int x = 0; x < bitmap.Width; x++) if (bitmap.GetPixel(x, y).A > 8) alpha++;
            if (alpha < 64) throw new Exception("Transparent portrait");
            string path = Path.Combine(output, name + ".png");
            bitmap.Save(path, ImageFormat.Png);
            results.Add(new { name, gender, expression, loadMs, width = bitmap.Width, height = bitmap.Height, alphaPixels = alpha, sha256 = Hash(path) });
            if (name == "male-normal" || name == "male-armored")
                PaintPortrait(bitmap, name, "独立人形单位", frame, loaded.StageRect);
        }
    }

    private async Task RenderStatic(string key, string expression, string name)
    {
        var tcs = new TaskCompletionSource<(Bitmap Image, RectangleF? StageRect)>(TaskCreationOptions.RunContinuationsAsynchronously);
        var frame = new NativeDialogueFrame { RequestId = "nd:2", SceneId = "fixture", Revision = 1,
            PortraitKey = key, Expression = expression, IsDoll = false };
        InvokeService("LoadPortrait", frame, null,
            new Action<Bitmap, RectangleF?>((bitmap, rect) => tcs.TrySetResult((bitmap, rect))));
        var loaded = await tcs.Task.WaitAsync(TimeSpan.FromSeconds(25));
        using (Bitmap bitmap = loaded.Image)
        {
            if (bitmap == null) throw new Exception("Static portrait decode failed: " + key);
            string path = Path.Combine(output, name + ".png");
            bitmap.Save(path, ImageFormat.Png);
            results.Add(new { name, key, expression, width = bitmap.Width, height = bitmap.Height, sha256 = Hash(path) });
            PaintPortrait(bitmap, name, key, frame, loaded.StageRect);
        }
    }

    private async Task RenderLegacyIcon()
    {
        web.CoreWebView2.PostWebMessageAsJson(new JObject {
            ["type"] = "dollBake", ["key"] = "纸娃娃-" + new string('a', 64), ["requestId"] = "legacy-smoke",
            ["tuple"] = new JObject { ["gender"] = "男", ["face"] = "1", ["hair"] = "" }
        }.ToString());
        JObject payload = await legacyResult.Task.WaitAsync(TimeSpan.FromSeconds(25));
        if (payload == null || payload["error"] != null) throw new Exception("Legacy icon render: " + payload);
        if (payload.Value<string>("requestId") != "legacy-smoke") throw new Exception("Legacy icon request mismatch");
        byte[] png = Convert.FromBase64String(payload.Value<string>("pngBase64"));
        using (var stream = new MemoryStream(png))
        using (var bitmap = new Bitmap(stream))
        {
            if (bitmap.Width != 256 || bitmap.Height != 256) throw new Exception("Legacy icon size changed");
            int alpha = 0;
            for (int y = 0; y < 256; y++) for (int x = 0; x < 256; x++) if (bitmap.GetPixel(x, y).A > 8) alpha++;
            if (alpha < 64) throw new Exception("Legacy icon is transparent");
            string path = Path.Combine(output, "legacy-loot-icon.png");
            File.WriteAllBytes(path, png);
            results.Add(new { name = "legacy-loot-web-icon", width = 256, height = 256, alphaPixels = alpha, sha256 = Hash(path) });
        }
    }

    private void PaintPortrait(Bitmap portrait, string name, string actor, NativeDialogueFrame sourceFrame,
        RectangleF? stageRect)
    {
        foreach (int width in new[] { 1024, 1920 })
        {
            int height = width * 9 / 16;
            var skinType = typeof(NativeDialogueWidget).Assembly.GetType(
                "CF7Launcher.Guardian.Hud.Dialogue.DialogueUiSkin", true);
            using var skin = (IDisposable)skinType.GetMethod("ForProjectRoot",
                BindingFlags.Static | BindingFlags.NonPublic).Invoke(null, new object[] { root });
            if (skin == null) throw new Exception("Original XFL dialogue skin was not loaded");
            var stage = (Bitmap)skinType.GetMethod("RasterStage", BindingFlags.Instance | BindingFlags.NonPublic)
                .Invoke(skin, new object[] { width / 1024f });
            if (stage == null) throw new Exception("Original SVG rasterization failed");
            using (var anchor = new Control())
            using (var widget = (NativeDialogueWidget)Activator.CreateInstance(typeof(NativeDialogueWidget),
                BindingFlags.Instance | BindingFlags.NonPublic, null,
                new object[] { anchor, new Func<Rectangle>(() => new Rectangle(0, 0, width, height)), skin }, null))
            using (var canvas = new Bitmap(width, height))
            using (Graphics g = Graphics.FromImage(canvas))
            {
                var displayFrame = sourceFrame.Snapshot();
                displayFrame.Name = actor;
                displayFrame.Title = "<FONT COLOR='#FFCC00'>永恒强者</FONT>";
                displayFrame.LineCount = 3;
                displayFrame.Text = "远处的风掠过街口。<font color='#E8C477'>人物线条、面部表情和透明边缘</font>应当清晰稳定。<BR>按下交互键先补全文字，再推进对白。";
                displayFrame.ImageAction = "clear";
                widget.ShowFrame(displayFrame);
                widget.SetPortrait(displayFrame.RequestId, displayFrame.Revision, portrait, stageRect);
                widget.TryAdvance();
                var watch = Stopwatch.StartNew();
                for (int i = 0; i < 12; i++)
                {
                    g.Clear(Color.FromArgb(32, 34, 39));
                    widget.Paint(g, 1f, Point.Empty);
                }
                watch.Stop();
                string path = Path.Combine(output, name + "-native-" + width + ".png");
                canvas.Save(path, ImageFormat.Png);
                results.Add(new { name = name + "-native", width, height, authorStageRect = stageRect,
                    meanBitmapPaintMs = watch.Elapsed.TotalMilliseconds / 12,
                    idleRequestsAnimation = widget.WantsAnimationTick, sha256 = Hash(path) });
                if (widget.WantsAnimationTick) throw new Exception("Completed static dialogue must stop animation ticks");
            }
        }
    }

    private static string Hash(string path) => Convert.ToHexString(SHA256.HashData(File.ReadAllBytes(path)));
}
