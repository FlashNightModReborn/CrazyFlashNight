#nullable enable
using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Threading;
using System.Threading.Tasks;
using System.Drawing;
using System.Windows.Forms;
using System.Diagnostics;
using System.Drawing.Imaging;
using System.Net;
using System.Net.Sockets;
using System.Runtime.InteropServices;
using System.Security.Cryptography;
using System.Text;
using System.Text.RegularExpressions;
using CF7Launcher.Guardian.Hud.PlayerInfo;
using CF7Launcher.Guardian.Hud.Tooltip;
using CF7Launcher.Tasks;
using CF7Launcher.Guardian.WorldCompositor;
using CF7Launcher.Guardian.InputOwnership;
using CF7Launcher.Guardian;
using Microsoft.Web.WebView2.Core;
using Newtonsoft.Json;
using Newtonsoft.Json.Linq;

// Real backend assembly probe. Input remains closed throughout this initial
// automatic lane; transport stimuli below do not substitute for C1 handoff.
namespace CF7Launcher.Guardian.UnifiedHost;

internal sealed partial class UnifiedInputHost : Form
{
    private readonly string root, evidence, session = Guid.NewGuid().ToString("N");
    private readonly List<object> checks = new();
    private readonly CF7Launcher.Bus.ExactProcessXmlSocketPeerAuthority peerAuthority = new();
    private readonly TcpListener listener = new(IPAddress.Loopback, 32188);
    private readonly System.Windows.Forms.Timer render = new() { Interval = 16 };
    private IntPtr sourceHwnd;
    private sealed class PassiveSourceForm : Form {
        protected override bool ShowWithoutActivation => true;
        protected override CreateParams CreateParams { get { var value = base.CreateParams; value.ExStyle |= 0x08000080; return value; } }
    }
    private readonly Form sourceRoot = new PassiveSourceForm { Text = "CF7 C1 source", Enabled = false, FormBorderStyle = FormBorderStyle.None, ShowInTaskbar = false, BackColor = Color.Magenta, StartPosition = FormStartPosition.Manual };
    private readonly bool independentSource;
    private readonly bool interactive;
    private readonly bool diagnosticCommands;
    private readonly UnifiedSceneProfile sceneProfile;
    private readonly Queue<JObject> messages = new();
    private NetworkStream? stream;
    private Process? flash;
    private CompositionSceneHost? compositionScene;
    private IntPtr capture;
    private CoreWebView2CompositionController? web;
    private object? webVisual;
    private PlasticSurgeryTask? surgery;
    private PlayerInfoRasterPipeline? pipeline;
    private PlayerInfoWidget? playerInfo;
    private NativeTooltipWidget? tooltip;
    private RawInputSource? inputProbe;
    private int renderTicks;
    private string closure = "", pageInstance = "";
    private long pageGeneration = 1;
    private bool pageBoot, closing, closeReceipt;
    private readonly Dictionary<string, byte[]> frozenWebCode = new(StringComparer.Ordinal);
    private int result = 2;
    private JObject Round => new() { ["session"] = session, ["coverage"] = closure, ["epoch"] = 1, ["ticket"] = 1, ["geometry"] = 1 };

    internal static int RunCandidate(UnifiedHostOptions options)
    {
        Application.SetHighDpiMode(HighDpiMode.PerMonitorV2); Application.EnableVisualStyles();
        using var host = new UnifiedInputHost(options);
        Application.Run(host); return host.result;
    }
    private UnifiedInputHost(UnifiedHostOptions options)
    {
        sceneProfile = options.Scene ?? throw new ArgumentNullException(nameof(options.Scene));
        root = options.ProjectRoot; evidence = options.Evidence; diagnosticCommands = options.DiagnosticCommands; independentSource = options.Mode == "--independent-source"; interactive = options.Mode == "--interactive"; Directory.CreateDirectory(evidence);
        if (File.Exists(Path.Combine(evidence, "identity.json"))) throw new InvalidOperationException("Evidence directory already has an identity");
        Text = "CF7 C1 backend assembly - input closed"; StartPosition = FormStartPosition.Manual;
        Location = new(120, 90); ClientSize = new(1024, 576); BackColor = Color.Black;
        ClientSizeChanged += (_, _) => ResizePresentation();
        render.Tick += (_, _) => {
            compositionScene?.Commit();
            if (interactive && liveStarted) PumpLive();
            if (inputProbe != null) {
                while (inputProbe.TryRead(out _)) { }
                if (++renderTicks % 60 == 0) Log(interactive ? "input_qualification" : "input_qualification_no_grant", new { status = inputProbe.Status, environment = inputProbe.EnvironmentDiagnostic });
            }
        };
        Shown += async (_, _) => { try { await Run(); } catch (Exception error) { Log("failure", error.ToString()); Finish(false); } };
        FormClosing += (_, _) => { if (!closing) { closing = true; result = 0; WriteResult(); } };
        FormClosed += (_, _) => Cleanup();
    }
    private void Log(string kind, object? detail) => File.AppendAllText(Path.Combine(evidence, "events.jsonl"),
        JsonConvert.SerializeObject(new { utc = DateTime.UtcNow, kind, detail }) + "\n");
    private void Check(string name, bool passed, object? detail = null)
    {
        checks.Add(new { name, passed, detail }); Log(name, new { passed, detail });
        if (!passed) throw new InvalidOperationException(name);
    }
    private async Task Wait(Func<bool> condition, string label, int timeout = 15000)
    {
        var watch = Stopwatch.StartNew();
        while (!closing) {
            if (condition()) return;
            if (watch.ElapsedMilliseconds >= timeout) break;
            await Task.Delay(25);
        }
        throw new TimeoutException(label);
    }
    private async Task<JObject> Receive(string kind)
    {
        JObject? found = null;
        await Wait(() => {
            while (messages.Count > 0) { var next = messages.Dequeue(); if (next.Value<string>("kind") == kind || next.Value<string>("task") == kind) { found = next; return true; } }
            return false;
        }, "AS2 " + kind);
        return found!;
    }
    private void Send(string op, JObject? fields = null)
    {
        var message = new JObject { ["op"] = op, ["session"] = session, ["coverage"] = closure, ["epoch"] = 1, ["ticket"] = 1, ["geometry"] = 1 };
        if (fields != null) message.Merge(fields);
        var bytes = Encoding.UTF8.GetBytes(message.ToString(Formatting.None) + "\0"); stream!.Write(bytes);
    }
    private async Task ReadSocket()
    {
        using var client = await listener.AcceptTcpClientAsync();
        if (!peerAuthority.TryAuthorize(client, out var reason)) { Log("peer_rejected", reason); return; }
        Log("exact_flash_peer_authorized", new { pid = flash!.Id }); stream = client.GetStream();
        var buffer = new byte[8192]; var pending = new List<byte>();
        try {
            int count;
            while ((count = await stream.ReadAsync(buffer)) > 0) for (int i = 0; i < count; i++) {
                if (buffer[i] != 0) { if (pending.Count >= 131072) throw new InvalidDataException("AS2 packet bound"); pending.Add(buffer[i]); continue; }
                var message = JObject.Parse(Encoding.UTF8.GetString(pending.ToArray())); pending.Clear(); Log("as2", message);
                if (interactive && liveStarted && delayNextIntent && message.Value<string>("task") == "panel_request") {
                    delayNextIntent = false; delayedAs2Intent = (JObject)message.DeepClone();
                    delayedAs2IntentAt = Environment.TickCount64 + 500;
                    Log("declared_intent_delay", message); continue;
                }
                if (message.Value<string>("task") == "plastic_surgery_response" && surgery != null) surgery.HandleFlashResponse(message, _ => { });
                else if (!interactive || !liveStarted || !ReceiveLive(message)) messages.Enqueue(message);
            }
            if (!closing) await EndLostPeer("peer_eof");
        } catch (Exception error) { if (!closing) await EndLostPeer("peer_read_failed: " + error.Message); }
    }
    private async Task EndLostPeer(string reason)
    {
        Log("transport_terminal", new { reason, freshVmRequired = true });
        if (inputProbe != null && coordinator != null)
            await inputProbe.OnObserver((_, _) => { coordinator.Fail(reason); return true; });
        Finish(false); // retires all endpoints and kills only this disposable VM
    }
    private async Task Run()
    {
        string frozen = Path.Combine(evidence, "flash"); Directory.CreateDirectory(frozen);
        foreach (string name in new[] { sceneProfile.Bootstrap, sceneProfile.Module })
            File.Copy(File.Exists(Path.Combine(AppContext.BaseDirectory, "flash", name))
                ? Path.Combine(AppContext.BaseDirectory, "flash", name)
                : Path.Combine(root, sceneProfile.Directory, name), Path.Combine(frozen, name), false);
        var sceneDependencies = new List<string>();
        foreach (string dependency in sceneProfile.Dependencies) {
            string destination = Path.Combine(frozen, dependency);
            Directory.CreateDirectory(Path.GetDirectoryName(destination)!);
            string packaged = Path.Combine(AppContext.BaseDirectory, "flash", dependency);
            File.Copy(File.Exists(packaged) ? packaged : Path.Combine(root, dependency), destination, false);
            sceneDependencies.Add(destination);
        }
        string movie = Path.Combine(frozen, sceneProfile.Bootstrap);
        string module = Path.Combine(frozen, sceneProfile.Module);
        const string entry = "modules/input-island/index.html";
        var webRoot = Path.Combine(root, "launcher/web");
        string frozenWebPath = Path.Combine(AppContext.BaseDirectory, "frozen-web.json");
        if (File.Exists(frozenWebPath)) {
            foreach (var pair in JsonConvert.DeserializeObject<Dictionary<string, string>>(File.ReadAllText(frozenWebPath))!)
                frozenWebCode[pair.Key] = Convert.FromBase64String(pair.Value);
            if (!frozenWebCode.ContainsKey(entry)) throw new InvalidDataException("Frozen Web entry missing");
        } else {
        frozenWebCode[entry] = File.ReadAllBytes(Path.Combine(webRoot, entry));
        foreach (Match match in Regex.Matches(Encoding.UTF8.GetString(frozenWebCode[entry]), "<script\\s+src=\"([^\"]+)\"")) {
            string relative = match.Groups[1].Value;
            if (!relative.StartsWith("modules/", StringComparison.Ordinal) || relative.Contains("..")) throw new InvalidDataException("Invalid executable Web closure");
            frozenWebCode[relative] = File.ReadAllBytes(Path.Combine(webRoot, relative));
        }
        foreach (string css in Directory.EnumerateFiles(Path.Combine(webRoot, "css"), "*.css", SearchOption.AllDirectories))
            frozenWebCode[Path.GetRelativePath(webRoot, css).Replace('\\', '/')] = File.ReadAllBytes(css);
        }
        var executableFiles = new[] { movie, module, Path.Combine(root, "Adobe Flash Player 20.exe") }
            .Concat(sceneDependencies)
            .Concat(Directory.EnumerateFiles(AppContext.BaseDirectory, "*.dll"))
            .Concat(Directory.Exists(Path.Combine(AppContext.BaseDirectory, "runtimes/win-x64"))
                ? Directory.EnumerateFiles(Path.Combine(AppContext.BaseDirectory, "runtimes/win-x64"), "*.dll", SearchOption.AllDirectories) : Array.Empty<string>())
            .Concat(Directory.EnumerateFiles(AppContext.BaseDirectory, "*.deps.json"))
            .Concat(Directory.EnumerateFiles(AppContext.BaseDirectory, "*.runtimeconfig.json"))
            .OrderBy(path => Path.GetFileName(path), StringComparer.Ordinal)
            .ToDictionary(path => path, path => Convert.ToHexString(SHA256.HashData(File.ReadAllBytes(path))));
        var executableWeb = frozenWebCode.OrderBy(pair => pair.Key, StringComparer.Ordinal)
            .ToDictionary(pair => pair.Key, pair => Convert.ToHexString(SHA256.HashData(pair.Value)));
        var portableFiles = executableFiles.ToDictionary(pair => pair.Key.StartsWith(frozen + Path.DirectorySeparatorChar, StringComparison.OrdinalIgnoreCase) ? "flash/" + Path.GetRelativePath(frozen, pair.Key).Replace('\\', '/')
            : pair.Key == Path.Combine(root, "Adobe Flash Player 20.exe") ? "projector/Adobe Flash Player 20.exe"
            : Path.GetRelativePath(AppContext.BaseDirectory, pair.Key).Replace('\\', '/'), pair => pair.Value);
        closure = Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes(JsonConvert.SerializeObject(new { portableFiles, executableWeb })))).ToLowerInvariant();
        string expectedPath = Path.Combine(AppContext.BaseDirectory, "c1-expected-closure.txt");
        if (File.Exists(expectedPath) && File.ReadAllText(expectedPath).Trim() != closure)
            throw new InvalidDataException("Frozen C1 candidate no longer matches its executable closure");
        File.WriteAllText(Path.Combine(evidence, "identity.json"), JsonConvert.SerializeObject(new {
            pid = Environment.ProcessId, session, closure, movie, utc = DateTime.UtcNow, inputInitiallyClosed = true, interactive, independentSource,
            firstClickPolicy = "activation_only", executableWeb, files = executableFiles
        }, Formatting.Indented));
        listener.Start(); _ = ReadSocket();
        var start = new ProcessStartInfo(Path.Combine(root, "Adobe Flash Player 20.exe")) { UseShellExecute = false };
        start.ArgumentList.Add(movie); flash = Process.Start(start)!;
        if (!peerAuthority.TrySetExpectedProcess(flash, out var peerError)) throw new InvalidOperationException(peerError);
        await Wait(() => { flash.Refresh(); return flash.MainWindowHandle != IntPtr.Zero; }, "projector HWND");
        IntPtr child = flash.MainWindowHandle;
        // The projector is a presentation source, never an OS input endpoint.
        // Logical world input travels through the qualified socket protocol.
        EnableWindow(child, false);
        Check("source_hwnd_input_disabled", !IsWindowEnabled(child));
        if (sceneProfile.RequiresLoadBarrier) {
            var bootstrapReady = await Receive("BOOTSTRAP_READY");
            Check("cold_bootstrap_boundary_before_game_load", bootstrapReady.Value<bool>("boundaryIntact")
                && !bootstrapReady.Value<bool>("gameLoaded") && !bootstrapReady.Value<bool>("inputGranted"));
            stream!.Write(Encoding.UTF8.GetBytes("LOAD_B1_RUNTIME\0"));
        }
        // A created HWND is not a loaded projector. In particular this entry
        // links real classes; wait for its closed BOOT/REGISTER before embedding.
        await Receive("BOOT"); Send("HELLO"); var registered = await Receive("REGISTER");
        Check("actual_cold_actor_ready", registered.Value<bool>("actorReady") && registered.Value<bool>("bodyAttached") && registered.Value<bool>("faceAttached") && !registered.Value<bool>("persistenceInstalled"));
        Check("legacy_drivers_excluded_before_module_initialization", registered["policy"]?.Value<bool>("valid") == true
            && !registered.Value<bool>("keyPollPresent") && !registered.Value<bool>("frameTimerPresent") && !registered.Value<bool>("cooldownDriverPresent"));
        int originalStyle = unchecked((int)GetWindowLongPtr(child, -16).ToInt64());
        SetMenu(child, IntPtr.Zero);
        uint capturePid;
        if (independentSource) {
            // Explicit comparison only; not silently promoted over the accepted
            // S/P/F source host. No AttachThreadInput or focus retry in either.
            sourceHwnd = child; capturePid = (uint)flash.Id;
            SetWindowLongPtr(child, -16, new IntPtr(0x90000000L)); SetWindowLongPtr(child, -20, new IntPtr(0x08000080));
            SetWindowPos(child, new IntPtr(1), 20, 60, sceneProfile.Width, sceneProfile.Height, 0x30);
        } else {
            sourceRoot.Location = new(20, 60); sourceRoot.ClientSize = new(sceneProfile.Width, sceneProfile.Height); sourceRoot.Show();
            SetWindowLongPtr(child, -16, new IntPtr(FlashWindowMenuPolicy.EmbeddedStyle(originalStyle))); SetParent(child, sourceRoot.Handle);
            SetWindowPos(child, IntPtr.Zero, 0, 0, sceneProfile.Width, sceneProfile.Height, 0x34);
            sourceHwnd = sourceRoot.Handle; capturePid = (uint)Environment.ProcessId;
        }
        EnableWindow(child, false); // a style replacement must not re-enable the source
        if (!independentSource) EnableWindow(sourceRoot.Handle, false);
        Check("embedded_source_remains_input_disabled", !IsWindowEnabled(child) && (independentSource || !IsWindowEnabled(sourceRoot.Handle)),
            new { childEnabled = IsWindowEnabled(child), rootEnabled = !independentSource && IsWindowEnabled(sourceRoot.Handle) });
        Log("source_topology", new { source = sourceHwnd, sourcePid = capturePid, flash = child, flashPid = flash.Id, output = Handle, outputPid = Environment.ProcessId, crossProcessParent = !independentSource });
        Send("CANCEL"); await Receive("CANCELLED");
        compositionScene = CompositionSceneHost.Create(Handle); Check("one_composition_scene_created", true);
        IntPtr worldVisual = compositionScene.AcquireVisual(0);
        try { capture = ProbeStartVisual(sourceHwnd, capturePid, Handle, worldVisual); }
        finally { if (worldVisual != IntPtr.Zero) Marshal.Release(worldVisual); }
        Check("world_capture_attached_to_scene", capture != IntPtr.Zero); render.Start();
        inputProbe = new RawInputSource();
        NativeCompositorSession.Stats captureStats = default;
        await Wait(() => {
            captureStats = new NativeCompositorSession.Stats { Size = (uint)Marshal.SizeOf<NativeCompositorSession.Stats>() };
            if (ProbeGetStats(capture, ref captureStats) != 1 || captureStats.State == 3) throw new InvalidOperationException("World capture failed: " + captureStats.Message);
            return captureStats.Received > 0 && captureStats.Presented > 0;
        }, "actual WGC frame in unified scene");
        Check("world_actual_frame_presented", true, captureStats);
        Send("VITALS"); var vitalsPacket = await Receive("VITALS");
        await PrepareNative(PlayerHudState.ReadVitals(vitalsPacket["vitals"]!));
        surgery = new PlasticSurgeryTask(() => stream != null && !closing, payload => {
            var message = JObject.Parse(payload.TrimEnd('\0'));
            var op = message.Value<string>("action") == "plasticSurgerySnapshot" ? "SNAPSHOT" : message.Value<string>("action") == "plasticSurgeryQuery" ? "QUERY" : throw new InvalidOperationException("Paid write escaped capability");
            if (liveStarted) LiveSend(op, liveRound, message); else Send(op, message); return true;
        }, draftOnly: true);
        surgery.SetInvoker(action => BeginInvoke(action)); surgery.SetPostToWeb(payload => { if (!closing && web != null) web.CoreWebView2.PostWebMessageAsJson(payload); });
        await CreateWebEndpoint();
        pageInstance = "c1.surgery." + Guid.NewGuid().ToString("N");
        if (interactive) { await StartLive(); return; }
        PostControl("prepare");
        string phase = "";
        var watch = Stopwatch.StartNew();
        while (watch.ElapsedMilliseconds < 30000) {
            phase = await web.CoreWebView2.ExecuteScriptAsync("window.PlasticSurgeryPanel && PlasticSurgeryPanel.debugState().phase");
            if (phase == "\"editing\"") break;
            await Task.Delay(100);
        }
        Check("real_surgery_page_uses_real_host_task_and_as2_snapshot", phase == "\"editing\"", phase);
        string inert = await web.CoreWebView2.ExecuteScriptAsync("document.body.inert && !C1IslandGate.granted");
        Check("preparation_does_not_grant_web_input", inert == "true");
        Log("visual_inspection_ready", new { Handle, source = sourceHwnd, pageInstance, Enabled, Visible, foreground = GetForegroundWindow() });
        // A PID/HWND-verified screenshot can inspect this exact scene. No automatic
        // arbitrary delay is promoted to rendering/interaction acceptance.
        await Wait(() => File.Exists(Path.Combine(evidence, "inspect.flag")), "scene inspection", 300000);
        PostControl("cancel"); await Wait(() => closeReceipt, "exact page cleanup receipt");
        Check("production_web_cleanup_receipt", true);
        web.CoreWebView2.ProcessFailed -= OnWebProcessFailed;
        web.CoreWebView2.WebMessageReceived -= OnWebMessage;
        web.RootVisualTarget = null; web.Close(); web = null;
        Check("exact_controller_retired_before_any_world_grant", true);
        Send("VISUAL"); Log("actual_as2_display_state", await Receive("VISUAL"));
        Log("world_inspection_ready", new { Handle });
        await Wait(() => File.Exists(Path.Combine(evidence, "world-inspect.flag")), "world/HUD inspection", 300000);
        Finish(true);
    }
    private async Task CreateWebEndpoint()
    {
        pageBoot = false;
        var environment = await CoreWebView2Environment.CreateAsync(null, Path.Combine(evidence, "web-profile"));
        string browserExpected = Path.Combine(AppContext.BaseDirectory, "c1-expected-browser.txt");
        if (File.Exists(browserExpected) && File.ReadAllText(browserExpected).Trim() != environment.BrowserVersionString)
            throw new InvalidDataException("WebView runtime changed since candidate qualification");
        Log("web_endpoint_environment", new { version = environment.BrowserVersionString, scope = WScope });
        web = await environment.CreateCoreWebView2CompositionControllerAsync(Handle);
        web.Bounds = ClientRectangle; web.DefaultBackgroundColor = Color.Transparent;
        web.CoreWebView2.Settings.AreDevToolsEnabled = false;
        web.CoreWebView2.Settings.AreDefaultContextMenusEnabled = false;
        web.CoreWebView2.Settings.IsZoomControlEnabled = false;
        web.CoreWebView2.Settings.AreBrowserAcceleratorKeysEnabled = false;
        var visual = compositionScene!.AcquireVisual(2);
        try { webVisual = Marshal.GetObjectForIUnknown(visual); web.RootVisualTarget = webVisual; }
        finally { Marshal.Release(visual); }
        web.CoreWebView2.SetVirtualHostNameToFolderMapping("cf7-c1.local", Path.Combine(root, "launcher/web"), CoreWebView2HostResourceAccessKind.DenyCors);
        web.CoreWebView2.NavigationStarting += (_, args) => { if (args.Uri != "https://cf7-c1.local/modules/input-island/index.html") args.Cancel = true; };
        web.CoreWebView2.AddWebResourceRequestedFilter("*", CoreWebView2WebResourceContext.All);
        web.CoreWebView2.WebResourceRequested += (_, args) => {
            string uri = args.Request.Uri;
            if (!uri.StartsWith("https://cf7-c1.local/", StringComparison.Ordinal)) {
                args.Response = environment.CreateWebResourceResponse(Stream.Null, 403, "C1 local closure only", "Content-Type: text/plain");
                return;
            }
            string path = Uri.UnescapeDataString(new Uri(uri).AbsolutePath.TrimStart('/'));
            if (frozenWebCode.TryGetValue(path, out var bytes)) {
                string mime = path.EndsWith(".js", StringComparison.Ordinal) ? "text/javascript" : path.EndsWith(".css", StringComparison.Ordinal) ? "text/css" : "text/html";
                args.Response = environment.CreateWebResourceResponse(new MemoryStream(bytes, false), 200, "OK", "Content-Type: " + mime + "; charset=utf-8\r\nCache-Control: no-store");
            } else if (args.ResourceContext is CoreWebView2WebResourceContext.Script or CoreWebView2WebResourceContext.Document)
                args.Response = environment.CreateWebResourceResponse(Stream.Null, 403, "Executable outside C1 closure", "Content-Type: text/plain");
        };
        web.CoreWebView2.NewWindowRequested += (_, args) => args.Handled = true;
        web.CoreWebView2.ProcessFailed += OnWebProcessFailed;
        web.CoreWebView2.WebMessageReceived += OnWebMessage;
        web.CoreWebView2.Navigate("https://cf7-c1.local/modules/input-island/index.html");
        await Wait(() => pageBoot, "real Web page boot", 30000);
    }
    private void PostControl(string op) => web!.CoreWebView2.PostWebMessageAsJson(new JObject {
        ["type"] = "c1_control", ["op"] = op, ["instance"] = pageInstance, ["generation"] = pageGeneration, ["round"] = Round, ["retire"] = op == "cancel"
    }.ToString(Formatting.None));
    private void OnWebMessage(object? sender, CoreWebView2WebMessageReceivedEventArgs args)
    {
        if (closing || web == null || !ReferenceEquals(sender, web.CoreWebView2) || args.Source != "https://cf7-c1.local/modules/input-island/index.html") return;
        var message = JObject.Parse(args.WebMessageAsJson); Log("web", message);
        if (interactive && liveStarted) {
            if (dropNextPrepared && message.Value<string>("type") == "c1_scope" && message.Value<string>("kind") == "prepared") {
                dropNextPrepared = false; Log("declared_prepared_drop", message); return;
            }
            if (message.Value<string>("type") == "c1_scope" && message.Value<string>("kind") == "boot") pageBoot = true;
            else if (delayNextSnapshot && message.Value<string>("type") == "panel" && message.Value<string>("cmd") == "snapshot") {
                delayNextSnapshot = false; delayedSnapshot = (JObject)message.DeepClone();
                delayedSnapshotEndpoint = web; delayedSnapshotAt = Environment.TickCount64 + 1200;
                Log("declared_snapshot_delay", message); // diagnostic transport delay; no fake response or grant
            }
            else ReceiveLiveWeb(message);
            return;
        }
        if (message.Value<string>("type") == "c1_scope") {
            if (message.Value<string>("kind") == "boot") pageBoot = true;
            if (message.Value<string>("instance") == pageInstance && message.Value<long?>("generation") == pageGeneration
                && message.Value<string>("kind") == "cancelled" && message.Value<bool>("gateClosed") && JToken.DeepEquals(message["round"], Round)) closeReceipt = true;
        } else if (message.Value<string>("type") == "panel" && message.Value<string>("panel") == "surgery"
            && message.Value<string>("panelInstanceId") == pageInstance && message.Value<long?>("inputGeneration") == pageGeneration
            && JToken.DeepEquals(message["inputRound"], Round))
            surgery!.HandleWebRequest(message.Value<string>("cmd"), message);
    }
    private async Task PrepareNative(PlayerHudVitals vitals)
    {
        liveVitals = vitals;
        var assets = PlayerInfoSvgAssetContract.LoadProductionEmbedded(false);
        var animation = new PlayerInfoAnimationModel(); animation.ResetProduction(); animation.ApplyProduction(vitals); animation.Tick(2000);
        playerInfo = new PlayerInfoWidget(assets, animation) { LiveVitals = vitals };
        pipeline = new PlayerInfoRasterPipeline(new PlayerInfoSvgRasterizer());
        var plan = PlayerInfoRasterPlanner.Create(assets, Rectangle.Round(WorldViewport(ClientSize)), DeviceDpi / 96f);
        pipeline.Request(plan); await pipeline.WaitForIdleAsync();
        var tight = plan.TightPhysicalBounds;
        using var bitmap = new Bitmap(tight.Width, tight.Height, PixelFormat.Format32bppPArgb);
        Check("actual_playerinfo_cache_painted", pipeline.TryUseCurrent((batch, current) => playerInfo.Paint(bitmap, batch, current)));
        var bits = bitmap.LockBits(new Rectangle(Point.Empty, bitmap.Size), ImageLockMode.ReadOnly, PixelFormat.Format32bppPArgb);
        try { compositionScene!.UploadHud(bits.Scan0, bitmap.Width, bitmap.Height, bits.Stride, tight.X, tight.Y); }
        finally { bitmap.UnlockBits(bits); }
        Check("playerinfo_gpu_upload", true, pipeline.Snapshot);
        Check("playerinfo_repeat_hits_real_cache", pipeline.Request(plan) == PlayerInfoRasterRequestResult.CurrentHit);
        tooltipAnchor.Bounds = ClientRectangle; Controls.Add(tooltipAnchor);
        tooltip = new NativeTooltipWidget(tooltipAnchor);
        var target = new PlayerHudTarget("resources", 0, "", 1, 1, 0, new RectangleF(0, 512, 280, 64));
        Check("existing_native_resource_tooltip_accepts_real_vitals", tooltip.Show(PlayerHudResourceTooltip.Build(vitals, 1, 1, target, "c1.resources.1")));
        tooltip.Reset(); // actual cancellation; no delayed snapshot can resurrect this instance
        Check("native_resource_tooltip_cancelled", tooltip.ActiveDocument == null);
    }
    private void Finish(bool passed)
    {
        if (closing) return; closing = true; result = passed ? 0 : 2;
        WriteResult(); Close();
    }
    private void WriteResult() => File.WriteAllText(Path.Combine(evidence, "result.json"), JsonConvert.SerializeObject(
        new { result, checks, C1Acceptance = false, liveMode = interactive, liveOpenCount, liveCloseCount }, Formatting.Indented));
    private void Cleanup()
    {
        closing = true; render.Stop(); surgery?.Dispose();
        inputProbe?.Dispose(); inputProbe = null;
        if (web != null) { web.CoreWebView2.ProcessFailed -= OnWebProcessFailed; web.CoreWebView2.WebMessageReceived -= OnWebMessage; web.RootVisualTarget = null; web.Close(); web = null; }
        if (webVisual != null && Marshal.IsComObject(webVisual)) Marshal.ReleaseComObject(webVisual); webVisual = null;
        tooltip?.Dispose(); playerInfo?.Dispose(); pipeline?.Dispose();
        if (capture != IntPtr.Zero) { ProbeStop(capture); capture = IntPtr.Zero; }
        compositionScene?.Dispose(); compositionScene = null;
        stream?.Dispose(); listener.Stop();
        if (flash is { HasExited: false }) { flash.Kill(); flash.WaitForExit(5000); } flash?.Dispose(); sourceRoot.Dispose();
    }
    [DllImport("FlashCompositorNative.dll", CallingConvention = CallingConvention.Cdecl)] private static extern IntPtr ProbeStartVisual(IntPtr source, uint pid, IntPtr output, IntPtr visual);
    [DllImport("FlashCompositorNative.dll", CallingConvention = CallingConvention.Cdecl)] private static extern void ProbeStop(IntPtr handle);
    [DllImport("FlashCompositorNative.dll", CallingConvention = CallingConvention.Cdecl)] private static extern int ProbeGetStats(IntPtr handle, ref NativeCompositorSession.Stats stats);
    [DllImport("user32.dll")] private static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll")] private static extern bool EnableWindow(IntPtr window, bool enable);
    [DllImport("user32.dll")] private static extern bool IsWindowEnabled(IntPtr window);
    [DllImport("user32.dll")] private static extern IntPtr SetParent(IntPtr child, IntPtr parent);
    [DllImport("user32.dll")] private static extern IntPtr SetWindowLongPtr(IntPtr window, int index, IntPtr value);
    [DllImport("user32.dll")] private static extern IntPtr GetWindowLongPtr(IntPtr window, int index);
    [DllImport("user32.dll")] private static extern bool SetWindowPos(IntPtr window, IntPtr after, int x, int y, int width, int height, uint flags);
    [DllImport("user32.dll")] private static extern bool SetMenu(IntPtr window, IntPtr menu);
}
