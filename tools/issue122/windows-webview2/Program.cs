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
    private readonly string root;
    private readonly string output;
    private readonly List<JObject> cells = new();

    [STAThread]
    private static void Main(string[] args)
    {
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
        Directory.CreateDirectory(output);
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
            await RunEnvironment("gpu", "");
            await RunEnvironment("software", "--disable-gpu --disable-gpu-rasterization");

            var by = cells.ToDictionary(
                x => x.Value<string>("backend") + "/" + x.Value<string>("camera") + "/" + x.Value<string>("mode"),
                x => x);
            string[] cameras = { "issue-time", "current" };
            bool gpuRawChunkedAll = cameras.All(camera =>
                SamePixels(by["gpu/" + camera + "/raw"], by["gpu/" + camera + "/chunked"]));
            bool gpuChunkedNonindexedAll = cameras.All(camera =>
                SamePixels(by["gpu/" + camera + "/chunked"], by["gpu/" + camera + "/nonindexed"]));
            bool softwareRawChunkedAll = cameras.All(camera =>
                SamePixels(by["software/" + camera + "/raw"], by["software/" + camera + "/chunked"]));

            string classification =
                !gpuRawChunkedAll && gpuChunkedNonindexedAll && softwareRawChunkedAll
                    ? "gpu_uint32_path_reproduced"
                : gpuRawChunkedAll && gpuChunkedNonindexedAll && softwareRawChunkedAll
                    ? "not_reproduced_in_isolated_webview2"
                : "mixed_result_manual_review_required";

            var result = new JObject {
                ["schema"] = 1,
                ["status"] = "completed",
                ["classification"] = classification,
                ["repoRoot"] = root,
                ["os"] = Environment.OSVersion.ToString(),
                ["processArch"] = System.Runtime.InteropServices.RuntimeInformation.ProcessArchitecture.ToString(),
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

            if (classification == "mixed_result_manual_review_required")
                Environment.ExitCode = 1;
        }
        catch (Exception error)
        {
            File.WriteAllText(Path.Combine(output, "failure.txt"), error.ToString());
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

        foreach (string camera in new[] { "issue-time", "current" })
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

        JObject fixture = await WaitForFixture(web, backend, mode);
        JObject gl = await ReadGlIdentity(web);

        await Task.Delay(150);
        string imagePath = Path.Combine(output, backend + "-" + camera + "-" + mode + ".png");
        using (var stream = File.Create(imagePath))
            await web.CoreWebView2.CapturePreviewAsync(
                CoreWebView2CapturePreviewImageFormat.Png, stream);

        cells.Add(new JObject {
            ["backend"] = backend,
            ["camera"] = camera,
            ["mode"] = mode,
            ["browserArguments"] = browserArguments,
            ["browserVersion"] = env.BrowserVersionString,
            ["source"] = url,
            ["stats"] = fixture["stats"],
            ["gl"] = gl,
            ["png"] = new JObject {
                ["path"] = Path.GetFileName(imagePath),
                ["bytes"] = new FileInfo(imagePath).Length,
                ["sha256"] = Hash(imagePath),
                ["pixelSha256"] = PixelHash(imagePath)
            }
        });
    }

    private static async Task<JObject> WaitForFixture(
        WebView2 web, string backend, string mode)
    {
        for (int i = 0; i < 300; i++)
        {
            string raw = await web.ExecuteScriptAsync(
                @"(() => JSON.stringify({
                    ready: !!window.Issue122Fixture?.ready,
                    error: window.Issue122Fixture?.error || null,
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
                if (stats.Value<int>("triangles") != 361010)
                    throw new Exception("Triangle count mismatch");
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

    private static bool SamePixels(JObject a, JObject b) =>
        a["png"]?.Value<string>("pixelSha256") ==
        b["png"]?.Value<string>("pixelSha256");

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
