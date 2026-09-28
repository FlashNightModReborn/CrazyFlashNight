using System;
using System.Collections.Generic;
using System.Drawing;
using System.IO;
using System.Linq;
using System.Drawing.Imaging;
using System.Runtime.InteropServices;
using System.Security.Cryptography;
using System.Threading.Tasks;
using System.Windows.Forms;
using Microsoft.Web.WebView2.Core;
using Microsoft.Web.WebView2.WinForms;
using Newtonsoft.Json.Linq;

internal sealed class Issue122Form : Form
{
    protected override bool ShowWithoutActivation => true;
    private readonly string root;
    private readonly string output;
    private readonly List<JObject> cells = new();
    private readonly JObject assetHashes;
    private readonly string[] cameras = Environment.GetEnvironmentVariable("CF7_ISSUE122_CAMERA_SET") == "low"
        ? new[] { "diagnostic-low-front", "diagnostic-low-side" }
        : new[] { "issue-time", "current" };

    [STAThread]
    private static void Main(string[] args)
    {
        if (args.Length == 2 && args[0] == "--self-test")
        {
            ProbeRules.RunTests(args[1]);
            return;
        }
        if (args.Length != 2)
        {
            Console.Error.WriteLine("Usage: Issue122.WebView2.exe <repo-root> <output-dir>");
            Environment.ExitCode = 2;
            return;
        }
        Application.EnableVisualStyles();
        Application.Run(new Issue122Form(Path.GetFullPath(args[0]), Path.GetFullPath(args[1])));
    }

    private Issue122Form(string root, string output)
    {
        this.root = root;
        this.output = output;
        if (Directory.Exists(output) && Directory.EnumerateFileSystemEntries(output).Any())
            throw new InvalidOperationException("Output directory must be fresh; evidence is never overwritten.");
        Directory.CreateDirectory(output);
        assetHashes = new JObject {
            ["city.glb"] = Hash(Path.Combine(root, "launcher/web/assets/stage-diorama/fallen-city/city.glb")),
            ["selection.glb"] = Hash(Path.Combine(root, "launcher/web/assets/stage-diorama/fallen-city/selection.glb"))
        };
        File.WriteAllText(Path.Combine(output, "asset-hashes.json"), assetHashes.ToString());
        Text = "CF7 Issue #122 WebView2 A/B";
        ShowInTaskbar = false;
        FormBorderStyle = FormBorderStyle.FixedToolWindow;
        StartPosition = FormStartPosition.Manual;
        Location = new Point(0, 0);
        ClientSize = new Size(1024, 576);
        Shown += async (_, _) => await Run();
    }

    private async Task Run()
    {
        try
        {
            await RunEnvironment("gpu", Environment.GetEnvironmentVariable("CF7_ISSUE122_GPU_ARGS") ?? "");
            await RunEnvironment("software", "--disable-gpu --disable-gpu-rasterization");

            var by = cells.ToDictionary(
                x => x.Value<string>("backend") + "/" + x.Value<string>("camera") + "/" + x.Value<string>("mode"),
                x => x);
            bool gpuRawChunkedAll = cameras.All(camera =>
                SamePixels(by["gpu/" + camera + "/raw"], by["gpu/" + camera + "/chunked"]));
            bool gpuChunkedNonindexedAll = cameras.All(camera =>
                SamePixels(by["gpu/" + camera + "/chunked"], by["gpu/" + camera + "/nonindexed"]));
            bool softwareRawChunkedAll = cameras.All(camera =>
                SamePixels(by["software/" + camera + "/raw"], by["software/" + camera + "/chunked"]));

            bool backendVerified = ProbeRules.VerifiedBackends(cells);
            string classification = ProbeRules.Classify(
                cameras.Select(c => SamePixels(by["gpu/" + c + "/raw"], by["gpu/" + c + "/chunked"])).ToArray(),
                cameras.Select(c => SamePixels(by["gpu/" + c + "/chunked"], by["gpu/" + c + "/nonindexed"])).ToArray(),
                cameras.Select(c => SamePixels(by["software/" + c + "/raw"], by["software/" + c + "/chunked"])).ToArray(),
                backendVerified);

            var result = new JObject {
                ["schema"] = 2,
                ["status"] = "completed",
                ["classification"] = classification,
                ["repoRoot"] = root,
                ["os"] = Environment.OSVersion.ToString(),
                ["processArch"] = System.Runtime.InteropServices.RuntimeInformation.ProcessArchitecture.ToString(),
                ["assetHashes"] = assetHashes,
                ["backendVerified"] = backendVerified,
                ["cameraProfiles"] = new JArray(cameras),
                ["comparisons"] = new JObject {
                    ["gpuRawVsChunkedPixelsExactAllCameras"] = gpuRawChunkedAll,
                    ["gpuChunkedVsNonindexedPixelsExactAllCameras"] = gpuChunkedNonindexedAll,
                    ["softwareRawVsChunkedPixelsExactAllCameras"] = softwareRawChunkedAll,
                    ["byCamera"] = JObject.FromObject(cameras.ToDictionary(camera => camera, camera => new {
                        gpuRawVsChunkedPixelsExact = SamePixels(by["gpu/" + camera + "/raw"], by["gpu/" + camera + "/chunked"]),
                        gpuChunkedVsNonindexedPixelsExact = SamePixels(by["gpu/" + camera + "/chunked"], by["gpu/" + camera + "/nonindexed"]),
                        softwareRawVsChunkedPixelsExact = SamePixels(by["software/" + camera + "/raw"], by["software/" + camera + "/chunked"])
                    }))
                },
                ["cells"] = new JArray(cells)
            };
            File.WriteAllText(Path.Combine(output, "result.json"), result.ToString());

            if (classification == "mixed_result_manual_review_required" || !backendVerified)
                Environment.ExitCode = 1;
        }
        catch (Exception error)
        {
            File.WriteAllText(Path.Combine(output, "failure.txt"), error.ToString());
            File.WriteAllText(Path.Combine(output, "result.json"), new JObject {
                ["schema"] = 2, ["status"] = "failed", ["repoRoot"] = root,
                ["assetHashes"] = assetHashes, ["error"] = error.ToString(),
                ["cells"] = new JArray(cells)
            }.ToString());
            Environment.ExitCode = 1;
        }
        finally
        {
            Close();
        }
    }

    private async Task RunEnvironment(string backend, string browserArguments)
    {
        string profile = Path.Combine(output, "profile-" + backend);
        var options = new CoreWebView2EnvironmentOptions(browserArguments);
        var env = await CoreWebView2Environment.CreateAsync(null, profile, options);
        string[] modes = backend == "gpu"
            ? new[] { "raw", "chunked", "nonindexed" }
            : new[] { "raw", "chunked" };

        foreach (string camera in cameras)
            foreach (string mode in modes)
                await CaptureCell(env, backend, browserArguments, camera, mode);
    }

    private async Task CaptureCell(
        CoreWebView2Environment env,
        string backend,
        string browserArguments,
        string camera,
        string mode)
    {
        File.AppendAllText(Path.Combine(output, "progress.log"), DateTime.UtcNow.ToString("O") + " " + backend + "/" + camera + "/" + mode + "\n");
        using var web = new WebView2 { Dock = DockStyle.Fill };
        Controls.Clear();
        Controls.Add(web);
        await web.EnsureCoreWebView2Async(env);
        web.CoreWebView2.SetVirtualHostNameToFolderMapping(
            "issue122.local",
            Path.Combine(root, "launcher", "web"),
            CoreWebView2HostResourceAccessKind.Allow);

        var navigation = new TaskCompletionSource<bool>(
            TaskCreationOptions.RunContinuationsAsynchronously);
        web.CoreWebView2.NavigationCompleted += (_, e) =>
            navigation.TrySetResult(e.IsSuccess);

        string url =
            "https://issue122.local/modules/stage-select/dev/issue122-index-fixture.html" +
            "?issue122IndexMode=" + Uri.EscapeDataString(mode) +
            "&issue122Camera=" + Uri.EscapeDataString(camera);
        web.CoreWebView2.Navigate(url);
        if (!await navigation.Task.WaitAsync(TimeSpan.FromSeconds(30)))
            throw new Exception("Navigation failed: " + backend + "/" + mode);

        JObject fixture = await WaitForFixture(web, backend, camera, mode);
        JObject gl = await ReadGlIdentity(web);
        foreach (var asset in assetHashes.Properties())
            if (fixture["stats"]?["loadedHashes"]?.Value<string>(asset.Name) != asset.Value.Value<string>())
                throw new Exception("Fixture asset identity mismatch: " + asset.Name);

        await Task.Delay(150);
        string imagePath = Path.Combine(output, backend + "-" + camera + "-" + mode + ".png");
        using (var stream = File.Create(imagePath))
            await web.CoreWebView2.CapturePreviewAsync(
                CoreWebView2CapturePreviewImageFormat.Png, stream);
        await Task.Delay(150);
        string repeatPath = Path.Combine(output, backend + "-" + camera + "-" + mode + "-repeat.png");
        using (var stream = File.Create(repeatPath))
            await web.CoreWebView2.CapturePreviewAsync(CoreWebView2CapturePreviewImageFormat.Png, stream);
        string pixelHash = PixelHash(imagePath);
        bool stable = pixelHash == PixelHash(repeatPath);
        using var bitmap = new Bitmap(imagePath);

        cells.Add(new JObject {
            ["backend"] = backend,
            ["camera"] = camera,
            ["mode"] = mode,
            ["browserArguments"] = browserArguments,
            ["browserVersion"] = env.BrowserVersionString,
            ["source"] = url,
            ["stats"] = fixture["stats"],
            ["gl"] = gl,
            ["observedBackendKind"] = ProbeRules.BackendKind(gl),
            ["pixelsStable"] = stable,
            ["png"] = new JObject {
                ["path"] = Path.GetFileName(imagePath),
                ["bytes"] = new FileInfo(imagePath).Length,
                ["sha256"] = Hash(imagePath),
                ["pixelSha256"] = pixelHash,
                ["width"] = bitmap.Width,
                ["height"] = bitmap.Height,
                ["repeatPixelSha256"] = PixelHash(repeatPath)
            }
        });
        File.WriteAllText(Path.Combine(output, "partial-result.json"), new JObject {
            ["schema"] = 2, ["status"] = "in_progress", ["cells"] = new JArray(cells)
        }.ToString());
        if (!stable) throw new Exception("Non-deterministic pixels: " + backend + "/" + camera + "/" + mode);
    }

    private static async Task<JObject> WaitForFixture(
        WebView2 web, string backend, string camera, string mode)
    {
        for (int i = 0; i < 300; i++)
        {
            string raw = await web.ExecuteScriptAsync(
                @"(() => JSON.stringify({
                    ready: !!window.Issue122Fixture?.ready,
                    error: window.Issue122Fixture?.error || null,
                    camera: window.Issue122Fixture?.cameraProfile || null,
                    stats: window.Issue122Fixture?.ready
                        ? window.Issue122Fixture.stats()
                        : null
                }))()");
            string json = JToken.Parse(raw).Value<string>();
            var state = JObject.Parse(json);
            if (state.Value<string>("error") is string error && error.Length > 0)
                throw new Exception(
                    "Fixture failed " + backend + "/" + mode + ": " + error);
            if (state.Value<bool>("ready"))
            {
                var stats = state["stats"] as JObject;
                if (stats == null) throw new Exception("Missing fixture stats");
                if (stats.Value<string>("issue122Mode") != mode)
                    throw new Exception("Mode propagation mismatch");
                if (state.Value<string>("camera") != camera)
                    throw new Exception("Camera propagation mismatch");
                if (stats.Value<int>("triangles") != 361010)
                    throw new Exception("Triangle count mismatch");
                if (stats.Value<int>("calls") != (mode == "chunked" ? 55 : 51))
                    throw new Exception("Draw count mismatch");
                var adaptation = stats["indexCompatibility"]?.First as JObject;
                if (adaptation == null || adaptation.Value<string>("mode") != mode ||
                    (mode == "chunked" && adaptation.Value<int>("outputChunks") != 5) ||
                    (mode == "nonindexed" && adaptation.Value<int>("expandedBatches") != 1))
                    throw new Exception("Index adaptation mismatch");
                return state;
            }
            await Task.Delay(100);
        }
        throw new TimeoutException("Fixture timeout: " + backend + "/" + mode);
    }

    private static async Task<JObject> ReadGlIdentity(WebView2 web)
    {
        string raw = await web.ExecuteScriptAsync(
            @"(() => {
                const canvas=document.querySelector('canvas.stage-select-diorama-canvas');
                const gl=canvas&&canvas.getContext('webgl2');
                if(!gl)return JSON.stringify({webgl2:false});
                const ext=gl.getExtension('WEBGL_debug_renderer_info');
                return JSON.stringify({
                    webgl2:true,
                    vendor:gl.getParameter(gl.VENDOR),
                    renderer:gl.getParameter(gl.RENDERER),
                    version:gl.getParameter(gl.VERSION),
                    shadingLanguageVersion:gl.getParameter(gl.SHADING_LANGUAGE_VERSION),
                    unmaskedVendor:ext?gl.getParameter(ext.UNMASKED_VENDOR_WEBGL):null,
                    unmaskedRenderer:ext?gl.getParameter(ext.UNMASKED_RENDERER_WEBGL):null,
                    maxElementsIndices:gl.getParameter(gl.MAX_ELEMENTS_INDICES),
                    maxElementsVertices:gl.getParameter(gl.MAX_ELEMENTS_VERTICES),
                    error:gl.getError(),
                    userAgent:navigator.userAgent
                    ,viewport:{width:innerWidth,height:innerHeight,dpr:devicePixelRatio,canvasWidth:canvas.width,canvasHeight:canvas.height}
                });
            })()");
        string json = JToken.Parse(raw).Value<string>();
        var result = JObject.Parse(json);
        if (!result.Value<bool>("webgl2"))
            throw new Exception("WebGL2 unavailable");
        if (result.Value<int>("error") != 0)
            throw new Exception("WebGL error: " + result.Value<int>("error"));
        return result;
    }

    private static bool SamePixels(JObject a, JObject b) => ProbeRules.SamePixels(a, b);

    private static string PixelHash(string path)
    {
        using var source = new Bitmap(path);
        using var bitmap = new Bitmap(source.Width, source.Height, PixelFormat.Format32bppArgb);
        using (Graphics g = Graphics.FromImage(bitmap)) g.DrawImageUnscaled(source, 0, 0);
        var rect = new Rectangle(0, 0, bitmap.Width, bitmap.Height);
        var data = bitmap.LockBits(rect, ImageLockMode.ReadOnly, PixelFormat.Format32bppArgb);
        try
        {
            int rowBytes = bitmap.Width * 4;
            byte[] normalized = new byte[rowBytes * bitmap.Height];
            for (int y = 0; y < bitmap.Height; y++)
            {
                IntPtr sourceRow = data.Stride >= 0
                    ? IntPtr.Add(data.Scan0, y * data.Stride)
                    : IntPtr.Add(data.Scan0, (bitmap.Height - 1 - y) * -data.Stride);
                Marshal.Copy(sourceRow, normalized, y * rowBytes, rowBytes);
            }
            return Convert.ToHexString(SHA256.HashData(normalized)).ToLowerInvariant();
        }
        finally { bitmap.UnlockBits(data); }
    }

    private static string Hash(string path)
    {
        using var stream = File.OpenRead(path);
        return Convert.ToHexString(SHA256.HashData(stream)).ToLowerInvariant();
    }
}
