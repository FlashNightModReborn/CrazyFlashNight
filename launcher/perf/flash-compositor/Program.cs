using System.Diagnostics;
using System.Globalization;
using System.Runtime.InteropServices;
using System.Security.Cryptography;
using System.Text.Json;
using CF7Launcher.Guardian.WorldCompositor;

namespace FlashCompositorProbe;

internal static class Program
{
    [STAThread]
    private static int Main(string[] args)
    {
        string report = Path.Combine(AppContext.BaseDirectory, "..", "startup-error.json");
        int reportIndex = Array.IndexOf(args, "--report");
        if (reportIndex >= 0 && reportIndex+1 < args.Length) report = Path.GetFullPath(args[reportIndex+1]);
        try
        {
            var options = Options.Parse(args);
            report = options.Report;
            Application.SetHighDpiMode(HighDpiMode.PerMonitorV2);
            Application.EnableVisualStyles();
            Application.SetCompatibleTextRenderingDefault(false);
            using var form = new ProbeForm(options);
            Application.Run(form);
            return form.ExitCode;
        }
        catch (Exception error)
        {
            Directory.CreateDirectory(Path.GetDirectoryName(report)!);
            File.WriteAllText(report, JsonSerializer.Serialize(new { success = false, error = error.ToString() }, JsonOptions));
            return 1;
        }
    }
    internal static readonly JsonSerializerOptions JsonOptions = new() { WriteIndented = true, IncludeFields = true };
}

internal sealed record Options(string Adapter, string Report, bool Auto, int PhaseSeconds, int Duration,
    string? FlashExe, string? Swf, nint Hwnd, int Pid, string Topology, bool CaptureOutput, bool StallF, bool HoldFrames,
    int WeatherType, float WeatherIntensity, float WeatherScale, float WeatherPanX, float WeatherPanY,
    int AtmospherePreset, string? VisualPresets, string? LutSet)
{
    internal static Options Parse(string[] args)
    {
        var values = new Dictionary<string,string>(StringComparer.Ordinal);
        for (int i = 0; i < args.Length; ++i)
        {
            if (args[i] is "--auto" or "--capture-output" or "--stall-f" or "--debug-hold-frames") { values.Add(args[i], "true"); continue; }
            if (!new[] { "--adapter", "--report", "--phase-seconds", "--duration", "--flash-exe", "--swf", "--hwnd", "--pid", "--topology", "--weather", "--weather-intensity", "--weather-scale", "--weather-pan-x", "--weather-pan-y", "--atmosphere", "--visual-presets", "--lut-set" }.Contains(args[i]))
                throw new ArgumentException("Unknown option: " + args[i]);
            if (++i == args.Length) throw new ArgumentException("Missing option value");
            values.Add(args[i-1], args[i]);
        }
        string adapter = values.GetValueOrDefault("--adapter", "auto");
        if (!new[] { "auto", "intel", "nvidia" }.Contains(adapter)) throw new ArgumentException("adapter must be auto/intel/nvidia");
        string topology = values.GetValueOrDefault("--topology", "embedded");
        if (!new[] { "embedded", "toproot", "embeddedF" }.Contains(topology)) throw new ArgumentException("topology must be embedded/toproot/embeddedF");
        bool captureOutput = values.ContainsKey("--capture-output");
        bool stallF = values.ContainsKey("--stall-f"), holdFrames = values.ContainsKey("--debug-hold-frames");
        if ((stallF || holdFrames) && (topology != "embeddedF" || !values.ContainsKey("--auto") || captureOutput || (stallF && holdFrames) || values.ContainsKey("--flash-exe")))
            throw new ArgumentException("Freeze controls require --topology embeddedF --auto and the owned fixture; controls are mutually exclusive");
        if (captureOutput && (topology == "embedded" || !values.ContainsKey("--auto")))
            throw new ArgumentException("--capture-output is a deliberate misconfiguration and requires --topology toproot|embeddedF --auto");
        int seconds = int.Parse(values.GetValueOrDefault("--phase-seconds", "5"));
        int duration = int.Parse(values.GetValueOrDefault("--duration", "0"));
        if (seconds < 3 || seconds > 60 || duration < 0 || duration > 3600) throw new ArgumentException("Duration out of range");
        string? exe = values.GetValueOrDefault("--flash-exe"), swf = values.GetValueOrDefault("--swf");
        if ((exe == null) != (swf == null)) throw new ArgumentException("flash-exe and swf must be supplied together");
        nint hwnd = new(long.Parse(values.GetValueOrDefault("--hwnd", "0")));
        int pid = int.Parse(values.GetValueOrDefault("--pid", "0"));
        if ((hwnd == 0) != (pid == 0) || pid < 0 || (exe != null && hwnd != 0)) throw new ArgumentException("Invalid source selection");
        if (topology == "embeddedF" && hwnd != 0) throw new ArgumentException("embeddedF requires a probe-owned source (fixture or --flash-exe); attached windows cannot be embedded");
        if (hwnd != 0 && values.ContainsKey("--auto")) throw new ArgumentException("Automatic window transitions only apply to a source owned by this probe");
        if (exe != null && (!File.Exists(exe) || !File.Exists(swf))) throw new ArgumentException("Flash executable/SWF missing");
        int weatherType = values.GetValueOrDefault("--weather", "none") switch {
            "none" => 0, "rain" => 1, "snow" => 2, "dust" => 3, "fog" => 4, "slash" => 5,
            _ => throw new ArgumentException("weather must be none/rain/snow/dust/fog/slash")
        };
        float weatherIntensity = float.Parse(values.GetValueOrDefault("--weather-intensity",weatherType==0 ? "0" : "0.7"),CultureInfo.InvariantCulture);
        if (!float.IsFinite(weatherIntensity) || weatherIntensity<0 || weatherIntensity>1)
            throw new ArgumentException("weather intensity must be finite in [0,1]");
        float weatherScale = float.Parse(values.GetValueOrDefault("--weather-scale","1"),CultureInfo.InvariantCulture);
        if (!float.IsFinite(weatherScale) || weatherScale<0.25f || weatherScale>4f)
            throw new ArgumentException("weather scale must be finite in [0.25,4]");
        float panX = float.Parse(values.GetValueOrDefault("--weather-pan-x","0"),CultureInfo.InvariantCulture);
        float panY = float.Parse(values.GetValueOrDefault("--weather-pan-y","0"),CultureInfo.InvariantCulture);
        if (!float.IsFinite(panX) || !float.IsFinite(panY) || Math.Abs(panX)>500 || Math.Abs(panY)>500)
            throw new ArgumentException("weather pan speed must be finite in [-500,500]");
        int atmospherePreset = values.GetValueOrDefault("--atmosphere","none") switch {
            "none"=>0, "alert"=>1, "medical"=>2, "industrial"=>3, "toxic"=>4,
            "corrosion"=>5, "cold-iron"=>6, "ambush"=>7, "banquet"=>8,
            "blood-moon"=>9, "incense"=>10, "custom"=>11,
            _=>throw new ArgumentException("Unknown atmosphere preset")
        };
        string? visualPresets=values.GetValueOrDefault("--visual-presets");
        if ((weatherType!=0 || atmospherePreset!=0) && visualPresets==null)
            throw new ArgumentException("Visual preview requires --visual-presets");
        if (visualPresets!=null) visualPresets=Path.GetFullPath(visualPresets);
        string? lutSet=values.GetValueOrDefault("--lut-set");
        if (lutSet!=null) lutSet=Path.GetFullPath(lutSet);
        return new(adapter, Path.GetFullPath(values.GetValueOrDefault("--report", "flash-compositor-report.json")),
            values.ContainsKey("--auto"), seconds, duration, exe == null ? null : Path.GetFullPath(exe),
            swf == null ? null : Path.GetFullPath(swf), hwnd, pid, topology, captureOutput, stallF, holdFrames,
            weatherType, weatherIntensity, weatherScale, panX, panY, atmospherePreset, visualPresets, lutSet);
    }
}

internal sealed class ProbeForm : Form
{
    private readonly Options options;
    private string? visualCatalogSha;
    private string? lutSetSha;
    private readonly Panel surface = new() { Dock = DockStyle.Fill, BackColor = Color.Black };
    private readonly Label status = new() { AutoSize = true, ForeColor = Color.White, Padding = new Padding(6) };
    private readonly System.Windows.Forms.Timer poll = new() { Interval = 250 };
    private readonly Stopwatch clock = new();
    private readonly List<object> samples = [];
    private readonly List<PhaseResult> phases = [];
    private readonly string[] plan;
    private FixtureForm? fixture;
    private Form? occluder;
    private Process? ownedFlash;
    private Process? targetProcess;
    private nint source, native;
    private Rectangle sourceBounds;
    private int phaseIndex, mode;
    private double phaseStart;
    private ulong phaseStartFrames;
    private ulong phaseStartReceived;
    private bool requestedProof;
    private ulong heldPresented;
    private bool heldImageStable=true, resumedGeometry;
    // grab-check 阶段（lut-set-v1 回归）：ProbeGrabLatestFrame 尺寸查询 + 实抓 + 非纯色校验。
    private bool grabAttempted, grabPassed;
    private uint grabWidth, grabHeight;
    private Native.Stats latest;
    private object? sourceIdentity;
    private string? failure;
    private PresentationForm? player;
    private nint fHwnd, outputHwnd;
    private Rectangle pExpectedBounds;
    private readonly List<GeometryCheck> pGeometryChecks = [];
    private readonly List<MarkerSample> markerScreenSamples = [];
    private uint[]? markerIns, markerOuts;
    private bool markerSampled, markerInP, markerInSource, pAliveAtEnd;
    private string? markerVerdict, markerScreenshot;
    private readonly List<string> violations = [];
    private object? sIdentity, pIdentity, fIdentity, entryFacts, topologyAssertions;
    private Panel? embedPanel;
    private Rectangle fRegionScreen, sFrameBounds, appliedCrop;
    private ulong phaseStartProofs;
    private bool flashEmbedded;
    private object? flashEmbedding, pFRegionOverlap;
    private uint[]? coveredPixels;
    private ulong coveredCaptured, coveredPresented;
    private bool coveredProofLanded, coveredNoMarker, coveredPalette;
    private string coveredVerdict = "unevaluated";
    private sealed record ContentProof(uint Count, double Seconds, ulong Captured, ulong Presented, uint[] Input, uint[] Output, uint MaxError, Native.ContentStats? Roi);
    private Native.ContentStats contentStats;
    private readonly List<ContentProof> contentProofs = [];
    private readonly List<object> contentPhases = [];
    private uint observedProof;
    private double lastProofRequest;
    private bool proofPending, freezeChrome;
    private readonly List<string> untestedItems = ["multi-monitor", "per-monitor-dpi", "negative-coordinates", "real-keyboard-alt-tab-taskbar", "pointer-and-key-feel"];
    internal int ExitCode { get; private set; } = 1;

    internal ProbeForm(Options options)
    {
        this.options = options;
        plan = options.Topology switch
        {
            "toproot" => ["raw", "night", "nightvision", "p-marker", "occluded", "offscreen", "restored", "grab-check", "minimized", "restore-minimized", "hidden", "restore-hidden", "resized", "viewport-held", "viewport-resumed"],
            "embeddedF" => ["raw", "night", "nightvision", "p-marker", "covered", "occluded", "offscreen", "restored", "grab-check", "minimized", "restore-minimized", "hidden", "restore-hidden", "resized", "viewport-held", "viewport-resumed"],
            _ => ["raw", "night", "nightvision", "occluded", "offscreen", "restored", "grab-check", "minimized", "restore-minimized", "hidden", "restore-hidden", "resized", "viewport-held", "viewport-resumed"]
        };
        if (options.StallF) plan = plan.SelectMany(p => p == "covered" ? new[] { "covered-stalled", p } : new[] { p }).ToArray();
        Text = "CF7 Flash compositor prototype — NOT DEPLOYED";
        StartPosition = FormStartPosition.Manual;
        Bounds = options.Topology == "embeddedF" ? new Rectangle(60, 60, 1050, 720) : new Rectangle(760, 90, 1050, 720);
        BackColor = Color.FromArgb(25,25,25);
        var controls = new FlowLayoutPanel { Dock = DockStyle.Top, Height = 74, AutoSize = false };
        foreach (var item in new[] { ("原画",0), ("夜间",1), ("夜视",2) })
        {
            int selected = item.Item2;
            var button = new Button { Text = item.Item1, AutoSize = true, Enabled = !options.Auto };
            button.Click += (_,_) => SetMode(selected);
            controls.Controls.Add(button);
        }
        controls.Controls.Add(status);
        Controls.Add(surface); Controls.Add(controls);
        poll.Tick += (_,_) => TickProbe();
        Shown += async (_,_) =>
        {
            try { await StartProbe(); }
            catch (Exception e) { failure = e.ToString(); if (e is EmbeddingUntestedException) ExitCode = 4; Close(); }
        };
    }

    private sealed class EmbeddingUntestedException(string message) : Exception(message);

    private async Task StartProbe()
    {
        Process? fProcess;
        bool embeddedF = options.Topology == "embeddedF";
        if (options.FlashExe != null)
        {
            var start = new ProcessStartInfo(options.FlashExe) { UseShellExecute = false, WorkingDirectory = Path.GetDirectoryName(options.Swf)! };
            start.ArgumentList.Add(options.Swf!);
            ownedFlash = Process.Start(start) ?? throw new InvalidOperationException("Flash launch failed");
            for (int i = 0; i < 100 && !IsDisposed; ++i)
            {
                ownedFlash.Refresh();
                if (ownedFlash.HasExited) throw new InvalidOperationException("Owned Flash exited before exposing a window");
                if (ownedFlash.MainWindowHandle != 0) break;
                await Task.Delay(100);
            }
            if (IsDisposed) return;
            fHwnd = ownedFlash.MainWindowHandle;
            fProcess = ownedFlash;
            if (fHwnd == 0) throw new InvalidOperationException("No owned Flash HWND after 10 seconds");
            if (embeddedF) await EmbedFlashIntoS();
            // Only the explicitly launched disposable source may be repositioned.
            else Native.SetWindowPos(fHwnd, 0, 50, 140, 640, 460, 0x0014);
        }
        else if (options.Hwnd != 0)
        {
            fHwnd = options.Hwnd;
            fProcess = Process.GetProcessById(options.Pid);
        }
        else
        {
            if (embeddedF)
            {
                embedPanel = new EmbeddedFixturePanel { Location = new Point(40, 40), Size = new Size(640, 320) };
                surface.Controls.Add(embedPanel);
                fHwnd = embedPanel.Handle;
            }
            else { fixture = new FixtureForm(); fixture.Show(); fHwnd = fixture.Handle; }
            fProcess = Process.GetCurrentProcess();
        }
        Rectangle fBounds;
        if (embeddedF) fBounds = fRegionScreen = ClientScreen(fHwnd);
        else { Native.GetWindowRect(fHwnd, out var fRect); fBounds = fRect.Rectangle; }
        if (options.Topology is "toproot" or "embeddedF")
        {
            Rectangle pBounds = fBounds;
            if (embeddedF)
            {
                // P must fully cover F with its marker band overlapping the F region (isolation evidence),
                // and its output surface is sized to exactly F so the diagnostic proof samples a 1:1 texel
                // grid — a downscaled grid can pick a neighboring texel on high-frequency content.
                int pHeight = fBounds.Height;
                for (int i = 0; i < 20; ++i)
                {
                    int next = fBounds.Height + Math.Max(24, (int)(pHeight * 0.36));
                    if (next == pHeight) break;
                    pHeight = next;
                }
                pBounds = new Rectangle(fBounds.X, fBounds.Y, fBounds.Width, pHeight);
            }
            player = new PresentationForm(this) { Bounds = pBounds };
            player.LayoutSurface();
            player.Show();
            pExpectedBounds = player.Bounds;
        }
        if (options.CaptureOutput)
        {
            // Deliberate misconfiguration: the captured "source" is P, the probe's own output window.
            source = player!.Handle; targetProcess = Process.GetCurrentProcess(); sourceBounds = player.Bounds;
        }
        else if (embeddedF)
        {
            // The candidate production topology captures S itself and crops F's region out of it.
            source = Handle; targetProcess = Process.GetCurrentProcess(); sourceBounds = Bounds;
        }
        else
        {
            source = fHwnd; targetProcess = fProcess; sourceBounds = fBounds;
        }
        Native.GetWindowThreadProcessId(source, out uint actualPid);
        if (actualPid != targetProcess.Id || targetProcess.HasExited) throw new InvalidOperationException("Source HWND/PID mismatch");
        string kind = options.CaptureOutput ? "presentation-window-P"
            : embeddedF ? (embedPanel is EmbeddedFixturePanel ? "S-probe-form-with-embedded-fixture-F" : flashEmbedded ? "S-probe-form-with-embedded-flash-F" : "S-probe-form-flash-embedding-untested")
            : fixture != null ? "winforms-animation-fixture" : ownedFlash != null ? "owned-flash-asset" : "attached-window";
        sourceIdentity = new {
            kind, pid = targetProcess.Id, hwnd = source.ToInt64(), path = targetProcess.MainModule?.FileName,
            startUtc = targetProcess.StartTime.ToUniversalTime(), swf = options.Swf,
            swfSha256 = options.Swf == null ? null : Hash(options.Swf), initialBounds = sourceBounds
        };
        uint vendor = options.Adapter switch { "intel" => 0x8086, "nvidia" => 0x10de, _ => 0 };
        outputHwnd = player != null ? player.OutputSurface.Handle : surface.Handle;
        native = Native.ProbeStart(source, actualPid, outputHwnd, vendor);
        if (native == 0) throw new InvalidOperationException("Native capture initialization failed");
        if (Native.ProbeGetAbiVersion()!=5) throw new InvalidOperationException("Native visual catalog ABI mismatch");
        if (options.LutSet!=null)
        {
            var lut=WorldLutSet.Load(options.LutSet);
            lutSetSha=lut.DataSha256;
            if (Native.ProbeSetLut(native,lut.BlendLevel(7))!=1)
                throw new InvalidOperationException("Native LUT preview state rejected");
        }
        WorldPresentationCatalog? catalog=options.VisualPresets==null ? null
            : WorldPresentationCatalog.Load(options.VisualPresets);
        visualCatalogSha=catalog?.Sha256;
        if (options.WeatherType!=0)
        {
            WeatherLook look=catalog!.Weather(options.WeatherType);
            if (Native.ProbeSetWeatherStyle(native,look.Type,look.Count,look.Tuning)!=1)
                throw new InvalidOperationException("Native weather style rejected");
        }
        if (options.WeatherType!=0 && Native.ProbeSetWeather(native,options.WeatherType,options.WeatherIntensity,0,17)!=1)
            throw new InvalidOperationException("Native weather preview state rejected");
        if ((options.WeatherType!=0 || options.AtmospherePreset!=0)
            && Native.ProbeSetWeatherCamera(native,0,0,options.WeatherScale,360,520)!=1)
            throw new InvalidOperationException("Native weather camera preview state rejected");
        if (options.AtmospherePreset is >0 and <11)
        {
            string[] names={"","警报","医疗警报","工业警报","毒气","腐蚀","寒铁","伏击","鸿门宴","血月","檀烟"};
            AtmosphereLook look=catalog!.Atmosphere(names[options.AtmospherePreset]);
            if (Native.ProbeSetAtmosphereStyle(native,look.Family,look.Tuning)!=1)
                throw new InvalidOperationException("Native atmosphere style rejected");
        }
        if (options.AtmospherePreset!=0 && Native.ProbeSetAtmosphere(native,options.AtmospherePreset,
            [0.8f,0.35f,0.2f,0.25f,0f,0f,2.4f,0.05f,0.2f,0f,0f,0f])!=1)
            throw new InvalidOperationException("Native atmosphere preview state rejected");
        if (embeddedF && !options.CaptureOutput)
        {
            // WGC window content maps to the DWM extended frame bounds, so F's offset inside S's frame is the crop origin.
            if (Native.DwmGetWindowAttribute(Handle, 9, out var sFrame, Marshal.SizeOf<Native.Rect>()) != 0)
                throw new InvalidOperationException("Cannot resolve the S capture frame bounds");
            sFrameBounds = sFrame.Rectangle;
            appliedCrop = new Rectangle(fRegionScreen.X - sFrameBounds.X, fRegionScreen.Y - sFrameBounds.Y, fRegionScreen.Width, fRegionScreen.Height);
            if (Native.ProbeSetCrop(native, appliedCrop.X, appliedCrop.Y, appliedCrop.Width, appliedCrop.Height) != 1)
                throw new InvalidOperationException("ProbeSetCrop rejected the F-region crop");
        }
        if (player != null) CollectTopologyFacts();
        clock.Start(); poll.Start();
    }

    private async Task EmbedFlashIntoS()
    {
        var host = new Panel { Location = new Point(40, 40), Size = new Size(640, 320), BackColor = Color.Black };
        surface.Controls.Add(host);
        embedPanel = host;
        long styleBefore = Native.GetWindowLongPtr(fHwnd, -16).ToInt64();
        long embeddedStyle = (styleBefore & ~0x80000000L & ~0x00C00000L & ~0x00040000L & ~0x00080000L & ~0x00010000L & ~0x00020000L) | 0x40000000L;
        Native.SetWindowLongPtr(fHwnd, -16, new nint(embeddedStyle));
        nint previousParent = Native.SetParent(fHwnd, host.Handle);
        int parentError = previousParent == 0 ? Marshal.GetLastWin32Error() : 0;
        Native.SetWindowPos(fHwnd, 0, 0, 0, host.ClientSize.Width, host.ClientSize.Height, 0x0040 | 0x0020);
        await Task.Delay(1200);
        ownedFlash!.Refresh();
        bool isChild = Native.IsChild(host.Handle, fHwnd) && Native.GetParent(fHwnd) == host.Handle;
        bool alive = Native.IsWindow(fHwnd) && !ownedFlash.HasExited;
        Native.GetWindowRect(fHwnd, out var rect);
        flashEmbedded = previousParent != 0 && isChild && alive;
        flashEmbedding = new {
            attempted = true, hostHwnd = host.Handle.ToInt64(), previousParent = previousParent.ToInt64(),
            setParentWin32Error = parentError == 0 ? (int?)null : parentError,
            styleBefore, styleAfter = Native.GetWindowLongPtr(fHwnd, -16).ToInt64(),
            isChildOfFHost = isChild, windowAlive = alive, processAlive = !ownedFlash.HasExited,
            windowRect = rect.Rectangle, status = flashEmbedded ? "embedded" : "untested"
        };
        if (!flashEmbedded)
        {
            untestedItems.Add("flash-source-embedding");
            throw new EmbeddingUntestedException(previousParent == 0
                ? $"SetParent failed, Win32 error {parentError}"
                : !isChild ? "Flash window did not become a descendant of the F host panel"
                : "Flash window or process did not survive embedding");
        }
    }

    private void SetMode(int value)
    {
        mode = value;
        if (native != 0) Native.ProbeSetMode(native, value);
    }

    private void TickProbe()
    {
        try
        {
            latest = Native.Read(native);
            if (options.Topology == "embeddedF") contentStats = Native.ReadContent(native);
            double elapsed = clock.Elapsed.TotalSeconds;
            if ((options.WeatherType!=0 || options.AtmospherePreset!=0) && (options.WeatherPanX!=0 || options.WeatherPanY!=0)
                && Native.ProbeSetWeatherCamera(native,(float)(elapsed*options.WeatherPanX),
                    (float)(elapsed*options.WeatherPanY),options.WeatherScale,360,520)!=1)
                throw new InvalidOperationException("Native weather pan preview rejected");
            string phase = options.Auto ? plan[phaseIndex] : "interactive";
            double frameAge = latest.LastFrameQpcMs > 0 ? Stopwatch.GetTimestamp()*1000.0/Stopwatch.Frequency-latest.LastFrameQpcMs : 0;
            samples.Add(new { seconds = elapsed, phase, mode, frameAgeMs = frameAge, stats = latest });
            if (!freezeChrome) status.Text = $"{options.Adapter} / {phase}\n{latest.Presented} 帧 · 当前帧龄 {frameAge:F1} ms · {latest.Width}×{latest.Height}";
            if (latest.State == 3) { failure = $"0x{latest.Error:X8}: {latest.Message}"; Close(); return; }
            if (latest.State == 2) { failure = "Source closed before probe completed"; Close(); return; }
            bool contentPhase = phase is "covered" or "covered-stalled";
            if (latest.ProofCount > observedProof)
            {
                bool roiReady = options.CaptureOutput || contentStats.ProofCount == latest.ProofCount;
                if (contentPhase && proofPending && roiReady)
                    contentProofs.Add(new(latest.ProofCount, elapsed-phaseStart, latest.Received-phaseStartReceived,
                        latest.Presented-phaseStartFrames, (uint[])latest.InputPixels.Clone(), (uint[])latest.OutputPixels.Clone(), latest.ProofMaxError,
                        options.CaptureOutput ? null : contentStats));
                if (!contentPhase || !proofPending || roiReady) { observedProof = latest.ProofCount; proofPending = false; }
            }
            bool wantsProof = phaseIndex < 3 || phase == "p-marker";
            if (options.Auto && wantsProof && !requestedProof && elapsed-phaseStart >= 1 && latest.Received > 0)
            {
                Native.ProbeRequestProof(native); requestedProof = true;
            }
            if (options.Auto && contentPhase && !proofPending && contentProofs.Count < 4
                && elapsed-phaseStart >= 0.75 && elapsed-phaseStart < options.PhaseSeconds-0.5 && elapsed-lastProofRequest >= 0.45)
            {
                if (options.CaptureOutput) Native.ProbeRequestProof(native);
                else Native.ProbeRequestContentProof(native);
                proofPending = true; lastProofRequest = elapsed;
            }
            if (phase == "p-marker" && !markerSampled && latest.ProofCount >= 4) SampleMarker();
            if (options.Auto && elapsed - phaseStart >= options.PhaseSeconds)
            {
                RecordPGeometry(phase);
                if (phase == "p-marker") EvaluateMarker();
                if (contentPhase) EvaluateCovered(phase, latest.Received - phaseStartReceived, latest.Presented - phaseStartFrames);
                phases.Add(new(phase, latest.Presented - phaseStartFrames, latest.Received-phaseStartReceived,
                    elapsed-phaseStart, latest.ProofCount, latest.ProofMode, latest.ProofMaxError, latest.ProofDistinct));
                if (++phaseIndex == plan.Length) { phaseIndex--; ExitCode = CorePassed() ? 0 : 2; Close(); return; }
                phaseStart = elapsed; phaseStartFrames = latest.Presented; phaseStartReceived = latest.Received; phaseStartProofs = latest.ProofCount; requestedProof = false;
                contentProofs.Clear(); proofPending = false; observedProof = latest.ProofCount;
                Transition(plan[phaseIndex]);
            }
            if (phase=="viewport-held" && latest.Presented!=heldPresented) heldImageStable=false;
            if (phase=="viewport-resumed" && latest.Width==320 && latest.Height==180) resumedGeometry=true;
            if (options.Duration > 0 && elapsed >= options.Duration) { ExitCode = latest.Presented > 5 ? 0 : 2; Close(); }
        }
        catch (Exception e) { failure = e.ToString(); Close(); }
    }

    private bool HasFixtureSource => fixture != null || embedPanel is EmbeddedFixturePanel;

    private bool CorePassed() => failure == null && phases.Count == plan.Length
        && phases.Take(3).Sum(p => (long)p.CapturedFrames) >= 30
        && phases.Take(3).Select((p,i) => (!HasFixtureSource || p.CapturedFrames >= 10) && p.ProofCount == i+1 && p.ProofMode == i
            && p.ProofMaxError <= 2 && (!HasFixtureSource || p.ProofDistinct == 1)).All(p => p)
        && phases.Where(p => p.Name.StartsWith("restore") || p.Name == "resized").All(p => p.CapturedFrames >= (HasFixtureSource ? 10UL : 1UL))
        && latest.CpuReadbacks == latest.ProofCount*6 + contentStats.Count*2 + (grabAttempted ? 1UL : 0UL)
        && grabPassed
        && heldImageStable && resumedGeometry
        && phases.Single(p => p.Name=="viewport-resumed").CapturedFrames>0
        && (player == null || (markerSampled && markerInP && markerInSource == options.CaptureOutput
            && source == ExpectedCaptureHwnd() && pGeometryChecks.All(g => g.Match)))
        && (options.Topology != "embeddedF" || (phases.Single(p => p.Name == "covered").CapturedFrames > 0
            && phases.Single(p => p.Name == "occluded").CapturedFrames > 0
            && coveredVerdict == "streaming-under-cover"));

    // ProbeGrabLatestFrame 回归（加性 ABI 3 下抓帧路径不受影响）：尺寸查询 → 实抓 → 非纯色/非全黑。
    private void PerformGrabCheck()
    {
        grabAttempted = true;
        int query = Native.ProbeGrabLatestFrame(native, null, 0, out uint w, out uint h);
        if (query != -2 || w < 1 || h < 1)
            throw new InvalidOperationException($"grab size query failed: code={query} {w}x{h}");
        var buffer = new byte[(ulong)w * h * 4];
        int result = Native.ProbeGrabLatestFrame(native, buffer, (uint)buffer.Length, out uint gw, out uint gh);
        if (result != 1 || gw != w || gh != h)
            throw new InvalidOperationException($"grab failed: code={result} {gw}x{gh} != {w}x{h}");
        byte b0 = buffer[0], b1 = buffer[1], b2 = buffer[2];
        bool distinct = false, nonBlack = false;
        for (int i = 0; i + 2 < buffer.Length; i += 4096 * 4)
        {
            if (buffer[i] != b0 || buffer[i + 1] != b1 || buffer[i + 2] != b2) distinct = true;
            if (buffer[i] > 8 || buffer[i + 1] > 8 || buffer[i + 2] > 8) nonBlack = true;
        }
        if (!distinct || !nonBlack) throw new InvalidOperationException("grab returned uniform/blank frame");
        grabWidth = w; grabHeight = h; grabPassed = true;
    }

    private void Transition(string phase)
    {
        if (fixture == null && ownedFlash == null && embedPanel == null) throw new InvalidOperationException("Cannot mutate attached source");
        switch (phase)
        {
            case "night": SetMode(1); break;
            case "nightvision": SetMode(2); break;
            case "p-marker":
                SetMode(0);
                if (options.HoldFrames) { ((EmbeddedFixturePanel)embedPanel!).SetFrozen(true); freezeChrome = true; }
                break;
            case "covered-stalled":
                ((EmbeddedFixturePanel)embedPanel!).SetFrozen(true); break;
            case "covered":
                if (options.StallF) ((EmbeddedFixturePanel)embedPanel!).SetFrozen(false);
                SetMode(0);
                if (player != null && player.Bounds != pExpectedBounds) player.Bounds = pExpectedBounds;
                break;
            case "occluded":
                if (options.HoldFrames) { ((EmbeddedFixturePanel)embedPanel!).SetFrozen(false); freezeChrome = false; }
                SetMode(0);
                occluder = new Form { Text = "Probe-owned occluder", BackColor = Color.DarkSlateGray, StartPosition = FormStartPosition.Manual, Bounds = sourceBounds };
                occluder.Show(); break;
            case "offscreen":
                occluder?.Close(); occluder = null;
                Native.SetWindowPos(source, 0, -10000, -10000, 0, 0, 0x0015); break;
            case "restored": RestoreSource(); break;
            case "grab-check": PerformGrabCheck(); break;
            case "minimized": Native.ShowWindow(source, 6); break;
            case "restore-minimized": Native.ShowWindow(source, 9); RestoreSource(); break;
            case "hidden": Native.ShowWindow(source, 0); break;
            case "restore-hidden": Native.ShowWindow(source, 4); RestoreSource(); break;
            case "resized":
                Native.SetWindowPos(source, 0, sourceBounds.X, sourceBounds.Y, sourceBounds.Width+120, sourceBounds.Height+80, 0x0014); break;
            case "viewport-held":
                Native.ProbeHoldViewport(native);
                heldPresented=Native.Read(native).Presented;
                Native.SetWindowPos(source,0,sourceBounds.X,sourceBounds.Y,sourceBounds.Width-120,sourceBounds.Height-80,0x0014);
                Native.ProbeSetMode(native,1);
                break;
            case "viewport-resumed":
                if(Native.ProbeSetViewport(native,0,0,320,180,Stopwatch.GetTimestamp()*1000.0/Stopwatch.Frequency)!=1)
                    throw new InvalidOperationException("Viewport handoff rejected");
                break;
        }
    }
    private void RestoreSource() => Native.SetWindowPos(source, 0, sourceBounds.X, sourceBounds.Y, sourceBounds.Width, sourceBounds.Height, 0x0014);
    private static string Hash(string file) { using var stream = File.OpenRead(file); return Convert.ToHexString(SHA256.HashData(stream)); }

    private nint ExpectedCaptureHwnd() => options.CaptureOutput ? player!.Handle : options.Topology == "embeddedF" ? Handle : fHwnd;
    private void Violate(string message) { violations.Add(message); failure ??= message; }

    private Rectangle ChoosePBounds(Rectangle fBounds)
    {
        var wa = Screen.PrimaryScreen?.WorkingArea ?? new Rectangle(0, 0, 1920, 1080);
        var candidates = new[]
        {
            new Rectangle(wa.Left + 40, wa.Bottom - 400, 560, 360),
            new Rectangle(wa.Right - 620, wa.Bottom - 400, 560, 360),
            new Rectangle(wa.Left + 40, wa.Top + 40, 560, 360),
            new Rectangle(wa.Right - 620, wa.Top + 40, 560, 360),
        };
        foreach (var candidate in candidates)
            if (!candidate.IntersectsWith(fBounds) && !candidate.IntersectsWith(Bounds)) return candidate;
        return candidates[0];
    }

    private void CollectTopologyFacts()
    {
        var p = player!;
        bool embeddedF = options.Topology == "embeddedF";
        sIdentity = Describe(Handle, "S-probe-form");
        pIdentity = Describe(p.Handle, "P-presentation", pSurface: p.OutputSurface.Handle);
        fIdentity = Describe(fHwnd, embeddedF ? "F-embedded-in-S" : "F-source");
        var pEntry = EntryFacts(p.Handle);
        entryFacts = new {
            s = EntryFacts(Handle), p = pEntry, f = EntryFacts(fHwnd),
            pCreatesSecondBareEntry = pEntry.TaskbarButtonDerived || pEntry.AltTabDerived,
            note = "Taskbar/Alt-Tab entries derived from WS_*/WS_EX_* rules (visible top-level, unowned-or-APPWINDOW, not TOOLWINDOW). Real Alt-Tab, taskbar clicks and keyboard feel are not exercised by this probe.",
            realKeyboardAndPointerFeel = "human_required"
        };
        bool pOwnRoot = Native.GetAncestor(p.Handle, 2) == p.Handle;
        bool pOwnedByS = Native.GetWindow(p.Handle, 4) == Handle;
        if (!embeddedF)
        {
            bool captureIsF = source == fHwnd;
            bool pNotDescendant = !Native.IsChild(fHwnd, p.Handle);
            topologyAssertions = new { captureHwndIsF = captureIsF, pNotDescendantOfF = pNotDescendant, pIsOwnGaRoot = pOwnRoot, pOwnedByS, expectedCaptureHwnd = ExpectedCaptureHwnd().ToInt64() };
            if (!options.CaptureOutput && !captureIsF) Violate("capture HWND is not F");
            if (options.CaptureOutput && captureIsF) Violate("negative control inert: capture HWND resolved to F instead of P");
            if (!pNotDescendant) Violate("P is a descendant of F");
            if (!pOwnRoot) Violate("P is not its own GA_ROOT");
        }
        else
        {
            bool captureIsS = source == Handle;
            bool fIsDescendant = Native.IsChild(Handle, fHwnd);
            bool pNotDescendantOfS = !Native.IsChild(Handle, p.Handle);
            var overlap = Rectangle.Intersect(p.Bounds, fRegionScreen);
            long overlapPx = (long)overlap.Width * overlap.Height, fAreaPx = (long)fRegionScreen.Width * fRegionScreen.Height;
            bool fullyCovers = overlap == fRegionScreen;
            Rectangle actualClient=ClientScreen(fHwnd);
            bool cropIsF = appliedCrop == new Rectangle(actualClient.X - sFrameBounds.X, actualClient.Y - sFrameBounds.Y, actualClient.Width, actualClient.Height)
                && actualClient==fRegionScreen;
            var pSurfaceSize = new Size(p.ClientSize.Width, p.ClientSize.Height - p.BandHeight);
            bool surfaceMatchesF = pSurfaceSize == fRegionScreen.Size;
            pFRegionOverlap = new {
                pBounds = p.Bounds, fRegionScreen, intersection = overlap, pSurfaceSize,
                overlapPx, fRegionAreaPx = fAreaPx, fraction = fAreaPx > 0 ? (double)overlapPx / fAreaPx : 0, fullyCovers
            };
            topologyAssertions = new {
                captureHwndIsS = captureIsS, appliedCrop, sContentFrame = sFrameBounds, cropIsFRegion = cropIsF, actualFClientScreen = actualClient, coordinateSpace = "caller-per-monitor-v2-physical", geometryVersion = 1,
                fIsDescendantOfS = fIsDescendant, pNotDescendantOfS, pIsOwnGaRoot = pOwnRoot, pOwnedByS,
                pFRegionOverlapPx = overlapPx, fRegionAreaPx = fAreaPx, pFullyCoversFRegion = fullyCovers,
                pSurfaceMatchesFSize = surfaceMatchesF, expectedCaptureHwnd = ExpectedCaptureHwnd().ToInt64()
            };
            if (!options.CaptureOutput && !captureIsS) Violate("capture HWND is not S");
            if (options.CaptureOutput && captureIsS) Violate("negative control inert: capture HWND resolved to S instead of P");
            if (!fIsDescendant) Violate("F is not embedded inside S");
            if (!pNotDescendantOfS) Violate("P is a descendant of S");
            if (!pOwnRoot) Violate("P is not its own GA_ROOT");
            if (!fullyCovers) Violate("P does not fully cover the F region");
            if(!options.CaptureOutput && !cropIsF) Violate("Actual F client does not match the applied crop");
            if (!surfaceMatchesF) Violate("P output surface is not F-sized — proof grid is not 1:1");
        }
    }

    private static Rectangle ClientScreen(nint hwnd)
    {
        if(!Native.GetClientRect(hwnd,out var rect))throw new InvalidOperationException("Missing F client");
        var first=new Point(rect.Left,rect.Top);var last=new Point(rect.Right,rect.Bottom);
        if(!Native.ClientToScreen(hwnd,ref first) || !Native.ClientToScreen(hwnd,ref last))throw new InvalidOperationException("F client mapping failed");
        return Rectangle.FromLTRB(first.X,first.Y,last.X,last.Y);
    }
    private static object Describe(nint hwnd, string role, nint pSurface = 0)
    {
        uint tid = Native.GetWindowThreadProcessId(hwnd, out uint pid);
        string? path = null;
        try { path = Process.GetProcessById((int)pid).MainModule?.FileName; } catch { }
        Native.GetWindowRect(hwnd, out var window); Native.GetClientRect(hwnd, out var client);
        return new {
            role, hwnd = hwnd.ToInt64(), pid, tid, path,
            getParent = Native.GetParent(hwnd).ToInt64(), gwOwner = Native.GetWindow(hwnd, 4).ToInt64(),
            gaRoot = Native.GetAncestor(hwnd, 2).ToInt64(), gaRootOwner = Native.GetAncestor(hwnd, 3).ToInt64(),
            style = Native.GetWindowLongPtr(hwnd, -16).ToInt64(), exStyle = Native.GetWindowLongPtr(hwnd, -20).ToInt64(),
            windowRect = window.Rectangle, clientRect = client.Rectangle, clientScreen = ClientScreen(hwnd), isWindow = Native.IsWindow(hwnd),
            outputHostHwnd = pSurface == 0 ? (long?)null : pSurface.ToInt64()
        };
    }

    private sealed record EntryFact(long Hwnd, long Style, long ExStyle, bool WsVisible, bool WsChild, bool WsPopup,
        bool WsExAppWindow, bool WsExToolWindow, bool WsExNoActivate, bool WsExLayered,
        long Owner, bool IsOwnGaRoot, bool TaskbarButtonDerived, bool AltTabDerived);
    private static EntryFact EntryFacts(nint hwnd)
    {
        long style = Native.GetWindowLongPtr(hwnd, -16).ToInt64(), exStyle = Native.GetWindowLongPtr(hwnd, -20).ToInt64();
        nint owner = Native.GetWindow(hwnd, 4);
        bool visible = (style & 0x10000000L) != 0, child = (style & 0x40000000L) != 0, popup = (style & -2147483648L) != 0;
        bool appWindow = (exStyle & 0x40000L) != 0, tool = (exStyle & 0x80L) != 0, noActivate = (exStyle & 0x8000000L) != 0, layered = (exStyle & 0x80000L) != 0;
        bool ownRoot = Native.GetAncestor(hwnd, 2) == hwnd;
        bool taskbar = ownRoot && !child && visible && !tool && (owner == 0 || appWindow);
        return new(hwnd.ToInt64(), style, exStyle, visible, child, popup, appWindow, tool, noActivate, layered,
            owner.ToInt64(), ownRoot, taskbar, taskbar);
    }

    private void RecordPGeometry(string phase)
    {
        if (player == null) return;
        Native.GetWindowRect(player.Handle, out var rect);
        var actual = rect.Rectangle;
        bool match = actual == pExpectedBounds;
        pGeometryChecks.Add(new(phase, pExpectedBounds, actual, match));
        if (!match) Violate($"P bounds {actual} differ from expected {pExpectedBounds} after phase {phase}");
    }

    private void SampleMarker()
    {
        markerSampled = true;
        markerIns = (uint[])latest.InputPixels.Clone();
        markerOuts = (uint[])latest.OutputPixels.Clone();
        if (player == null) return;
        // Foreign windows may overlap P; sampling measures the pixels P actually presents,
        // so raise P above all others for the measurement only (no activation, no style change).
        Native.SetWindowPos(player.Handle, -1, 0, 0, 0, 0, 0x0001 | 0x0002 | 0x0010 | 0x0040);
        player.Refresh(); System.Threading.Thread.Sleep(80);
        var band = player.RectangleToScreen(new Rectangle(0, 0, player.ClientSize.Width, player.BandHeight));
        var dc = Native.GetDC(nint.Zero);
        try
        {
            for (int i = 0; i < 5; ++i)
            {
                int x = band.Left + (int)(band.Width * (0.12 + 0.19 * i)), y = band.Top + band.Height / 2;
                uint raw = Native.GetPixel(dc, x, y);
                int r = (int)(raw & 0xff), g = (int)((raw >> 8) & 0xff), b = (int)((raw >> 16) & 0xff);
                nint top = Native.WindowFromPoint(new System.Drawing.Point(x, y));
                var cls = new System.Text.StringBuilder(64); Native.GetClassName(top, cls, cls.Capacity);
                var title = new System.Text.StringBuilder(128); Native.GetWindowText(top, title, title.Capacity);
                Native.GetWindowThreadProcessId(top, out uint topPid);
                markerScreenSamples.Add(new(x, y, raw, r, g, b, IsMagenta(r, g, b),
                    top.ToInt64(), cls.ToString(), title.ToString(), (int)topPid,
                    top == player.Handle || Native.IsChild(player.Handle, top)));
            }
        }
        finally { Native.ReleaseDC(nint.Zero, dc); }
        markerInP = markerScreenSamples.Count == 5 && markerScreenSamples.All(s => s.Magenta);
        markerInSource = markerIns.Any(p => IsMagenta((int)(p >> 16) & 255, (int)(p >> 8) & 255, (int)p & 255));
        try
        {
            var shot = Path.Combine(Path.GetDirectoryName(options.Report)!, Path.GetFileNameWithoutExtension(options.Report) + "-pscreen.png");
            var area = player.RectangleToScreen(player.ClientRectangle); area.Inflate(24, 24);
            using var bitmap = new Bitmap(area.Width, area.Height);
            using (var g = Graphics.FromImage(bitmap)) g.CopyFromScreen(area.Left, area.Top, 0, 0, area.Size);
            bitmap.Save(shot, System.Drawing.Imaging.ImageFormat.Png);
            markerScreenshot = shot;
        }
        catch { }
        Native.SetWindowPos(player.Handle, -2, 0, 0, 0, 0, 0x0001 | 0x0002 | 0x0010);
    }

    private void EvaluateMarker()
    {
        if (!markerSampled) { markerVerdict = "unsampled"; Violate("p-marker diagnostic proof never landed"); return; }
        if (!markerInP) Violate("P marker not confirmed on screen — isolation check would be vacuous");
        if (markerInSource) Violate("captured source frames contain P marker pixels");
        markerVerdict = !markerInP ? "marker-not-confirmed"
            : markerInSource ? (options.CaptureOutput ? "control-detected" : "leak")
            : (options.CaptureOutput ? "control-inconclusive" : "isolated");
    }

    private void EvaluateCovered(string phase, ulong captured, ulong presented)
    {
        coveredCaptured = captured; coveredPresented = presented;
        Rectangle actualClient=ClientScreen(fHwnd);
        if(options.Topology=="embeddedF" && actualClient!=fRegionScreen)Violate("F geometry changed during content proof");
        coveredProofLanded = contentProofs.Count > 0;
        coveredPixels = contentProofs.LastOrDefault()?.Input;
        coveredNoMarker = coveredProofLanded && contentProofs.All(s => !s.Input.Any(p => IsMagenta((int)(p >> 16) & 255, (int)(p >> 8) & 255, (int)p & 255)));
        coveredPalette = coveredProofLanded && contentProofs.All(s => IsRedish(s.Input[0]) && IsGreenish(s.Input[1]) && IsBlueish(s.Input[2]));
        bool changed = contentProofs.Count >= 2 && contentProofs.All(s => s.Roi.HasValue)
            && contentProofs.Skip(1).Any(s => s.Roi!.Value.InputHash != contentProofs[0].Roi!.Value.InputHash);
        bool outputCorrelated = contentProofs.Count >= 2 && contentProofs.All(s => s.Roi.HasValue && s.Roi.Value.MaxRgbError <= 2)
            && contentProofs.Skip(1).Any(s => s.Roi!.Value.OutputHash != contentProofs[0].Roi!.Value.OutputHash);
        coveredVerdict = captured == 0 ? "stalled-under-cover"
            : !coveredProofLanded ? "no-proof"
            : !coveredNoMarker ? "marker-leak"
            : embedPanel is EmbeddedFixturePanel && !coveredPalette ? "palette-mismatch"
            : contentProofs.Count < 2 ? "insufficient-proof"
            : !changed ? (embedPanel is EmbeddedFixturePanel ? "s-chrome-only" : "content-unproven")
            : !outputCorrelated ? "output-not-correlated"
            : "streaming-under-cover";
        contentPhases.Add(new { phase, capturedFrames = captured, presentedFrames = presented, verdict = coveredVerdict,
            inputPixelsChanged = changed, outputCorrelated, actualFClientScreen = actualClient, appliedCrop, geometryVersion = 1, proofs = contentProofs.ToArray(),
            interpretation = "Full F-ROI RGB FNV-1a hashes and pixelwise raw 1:1 output comparison per proof. Three texels remain only the palette/marker oracle. Output is GPU readback before Present, not screen scanout or Flash logic progress." });
        if (captured == 0) Violate("covered phase captured zero frames — WGC-by-S stalls while P covers the F region");
        else if (!coveredProofLanded) Violate("covered phase diagnostic proof never landed");
        else if (!coveredNoMarker) Violate("captured F-region frames contain P marker pixels while covered");
        else if (embedPanel is EmbeddedFixturePanel && !coveredPalette) Violate("covered-phase proof pixels do not match the embedded fixture palette — crop is not the F region");
        else if (coveredVerdict != "streaming-under-cover") Violate(phase + ": " + coveredVerdict);
    }

    private static bool IsMagenta(int r, int g, int b) => r >= 150 && b >= 100 && g <= 80;
    private static bool IsRedish(uint p) => ((p >> 16) & 255) >= 150 && ((p >> 8) & 255) <= 80 && (p & 255) <= 80;
    private static bool IsGreenish(uint p) => ((p >> 8) & 255) >= 150 && ((p >> 16) & 255) <= 80 && (p & 255) <= 80;
    private static bool IsBlueish(uint p) => (p & 255) >= 150 && ((p >> 16) & 255) <= 80 && ((p >> 8) & 255) <= 80;
    private sealed record GeometryCheck(string Phase, Rectangle Expected, Rectangle Actual, bool Match);
    private sealed record MarkerSample(int X, int Y, uint Raw, int R, int G, int B, bool Magenta,
        long TopWindowHwnd, string TopWindowClass, string TopWindowTitle, int TopWindowPid, bool BelongsToP);

    protected override void OnFormClosing(FormClosingEventArgs e)
    {
        poll.Stop();
        string? atmosphereScreenshot=null;
        if (options.AtmospherePreset!=0 && latest.Presented>0)
        {
            try
            {
                Control target=player?.OutputSurface ?? surface;
                Rectangle area=target.RectangleToScreen(target.ClientRectangle);
                if (area.Width>0 && area.Height>0)
                {
                    using var bitmap=new Bitmap(area.Width,area.Height);
                    using var graphics=Graphics.FromImage(bitmap);
                    graphics.CopyFromScreen(area.Location,Point.Empty,area.Size);
                    atmosphereScreenshot=Path.ChangeExtension(options.Report,".png");
                    Directory.CreateDirectory(Path.GetDirectoryName(atmosphereScreenshot)!);
                    bitmap.Save(atmosphereScreenshot,System.Drawing.Imaging.ImageFormat.Png);
                }
            }
            catch (Exception) { atmosphereScreenshot=null; }
        }
        if (native != 0) { latest = Native.Read(native); if (options.Topology == "embeddedF") contentStats=Native.ReadContent(native); Native.ProbeStop(native); native = 0; }
        pAliveAtEnd = player != null && Native.IsWindow(player.Handle);
        occluder?.Close(); fixture?.Close(); player?.Close();
        bool flashExited = true;
        if (ownedFlash is { HasExited: false })
        {
            ownedFlash.CloseMainWindow(); flashExited = ownedFlash.WaitForExit(3000);
            // Only this probe's child asset player can be terminated on cleanup failure.
            if (!flashExited) { ownedFlash.Kill(); ownedFlash.WaitForExit(3000); }
        }
        if (!options.Auto && failure == null && latest.Presented > 5) ExitCode = 0;
        Directory.CreateDirectory(Path.GetDirectoryName(options.Report)!);
        object report = player == null
            ? new {
                schemaVersion = 1, scope = "capture-postprocess-prototype", deployed = false,
                success = ExitCode == 0 && failure == null, automatedCorePassed = options.Auto && CorePassed(),
                humanAcceptance = "NOT_PERFORMED", inputForwarding = "NOT_IMPLEMENTED", performanceBenefit = "NOT_ESTABLISHED",
                failure, source = sourceIdentity,
                grabCheck = new { attempted = grabAttempted, passed = grabPassed, width = grabWidth, height = grabHeight },
                options = new { options.Adapter, options.Auto, options.PhaseSeconds, options.Duration, options.WeatherType, options.WeatherIntensity, options.WeatherScale, options.WeatherPanX, options.WeatherPanY, options.AtmospherePreset, options.VisualPresets, options.LutSet }, os = Environment.OSVersion.ToString(),
                binarySha256 = Hash(Environment.ProcessPath!), nativeSha256 = Hash(Path.Combine(AppContext.BaseDirectory, "FlashCompositorNative.dll")),
                managedSha256 = Hash(typeof(Program).Assembly.Location),
                metricsNote = "AgeMs is WGC timestamp-to-dequeue age, not input-to-photon latency; SubmitMs is CPU submission, not GPU execution. Auto mode requests 3 diagnostic proofs, 6 one-pixel CPU readbacks each. Interactive mode performs none.",
                ownedFlashExitedNormally = flashExited, finalStats = latest, phases, samples, atmosphereScreenshot, visualCatalogSha, lutSetSha
            }
            : new {
                schemaVersion = 1, scope = "capture-postprocess-prototype", deployed = false,
                success = ExitCode == 0 && failure == null, automatedCorePassed = options.Auto && CorePassed(),
                humanAcceptance = "NOT_PERFORMED", inputForwarding = "NOT_IMPLEMENTED", performanceBenefit = "NOT_ESTABLISHED",
                failure, source = sourceIdentity,
                grabCheck = new { attempted = grabAttempted, passed = grabPassed, width = grabWidth, height = grabHeight },
                options = new { options.Adapter, options.Auto, options.PhaseSeconds, options.Duration, options.Topology, options.CaptureOutput, options.StallF, options.HoldFrames, options.WeatherType, options.WeatherIntensity, options.WeatherScale, options.WeatherPanX, options.WeatherPanY, options.AtmospherePreset, options.VisualPresets, options.LutSet }, os = Environment.OSVersion.ToString(),
                binarySha256 = Hash(Environment.ProcessPath!), nativeSha256 = Hash(Path.Combine(AppContext.BaseDirectory, "FlashCompositorNative.dll")),
                managedSha256 = Hash(typeof(Program).Assembly.Location),
                metricsNote = "AgeMs is WGC timestamp-to-dequeue age, not input-to-photon latency; SubmitMs is CPU submission, not GPU execution. Each proof uses 6 one-pixel readbacks; explicit covered content proofs add 2 full-ROI readbacks. Interactive mode performs none.",
                ownedFlashExitedNormally = flashExited, finalStats = latest, phases, samples, atmosphereScreenshot, visualCatalogSha, lutSetSha,
                topologyExperiment = new {
                    topology = options.Topology, captureOutputRequested = options.CaptureOutput,
                    captureHwnd = source.ToInt64(), outputHwnd = outputHwnd.ToInt64(),
                    s = sIdentity, p = pIdentity, f = fIdentity, assertions = topologyAssertions,
                    crop = options.Topology == "embeddedF" ? (object)new { applied = !options.CaptureOutput, rect = appliedCrop, sContentFrame = sFrameBounds } : null,
                    fRegionScreen = options.Topology == "embeddedF" ? fRegionScreen : (Rectangle?)null,
                    pFRegionOverlap,
                    covered = options.Topology == "embeddedF" ? (object)new {
                        phase = "covered", capturedFrames = coveredCaptured, presentedFrames = coveredPresented,
                        proofLanded = coveredProofLanded, proofInputPixels = coveredPixels,
                        containsPMarker = coveredProofLanded && !coveredNoMarker,
                        fixturePaletteMatch = coveredPalette, verdict = coveredVerdict
                    } : null,
                    contentPhases, contentStats, flashEmbedding,
                    marker = new {
                        phase = "p-marker", sampled = markerSampled, screenSamples = markerScreenSamples,
                        inputPixels = markerIns, outputPixels = markerOuts, screenshot = markerScreenshot,
                        raisedToTopmostForSampling = markerSampled && player != null,
                        markerVisibleOnP = markerInP, markerInCapturedSource = markerInSource, verdict = markerVerdict
                    },
                    pGeometryChecks, pAliveAtEnd,
                    entryFacts, violations,
                    negativeControl = options.CaptureOutput ? (markerInSource ? "detected" : "inconclusive") : "not-applicable",
                    untested = untestedItems
                }
            };
        File.WriteAllText(options.Report, JsonSerializer.Serialize(report, Program.JsonOptions));
        base.OnFormClosing(e);
    }
    private sealed record PhaseResult(string Name, ulong PresentedFrames, ulong CapturedFrames, double Seconds,
        uint ProofCount, uint ProofMode, uint ProofMaxError, uint ProofDistinct);
}

internal sealed class FixtureForm : Form
{
    private readonly System.Windows.Forms.Timer timer = new() { Interval = 33 };
    private int frame;
    internal FixtureForm()
    {
        Text = "CF7 capture source fixture"; StartPosition = FormStartPosition.Manual;
        Bounds = new Rectangle(50,140,640,460); DoubleBuffered = true;
        timer.Tick += (_,_) => { frame++; Invalidate(); }; timer.Start();
    }
    protected override void OnPaint(PaintEventArgs e) => FixturePaint.Draw(e.Graphics, frame, ClientSize.Width, ClientSize.Height);
    protected override void Dispose(bool disposing) { if (disposing) timer.Dispose(); base.Dispose(disposing); }
}

internal static class FixturePaint
{
    internal static void Draw(Graphics g, int frame, int w, int h)
    {
        g.Clear(Color.FromArgb(32,48,64));
        g.FillRectangle(Brushes.Red, 0,0,w/3,h/2);
        g.FillRectangle(Brushes.Lime, w/3,0,w/3,h/2);
        g.FillRectangle(Brushes.Blue, 2*w/3,0,w-2*w/3,h/2);
        g.FillEllipse(Brushes.White, (frame*7)%Math.Max(1,w-70),h/2+20,64,64);
        using var font = new Font("Segoe UI", 22);
        g.DrawString($"LIVE FRAME {frame}\n{w} × {h}", font, Brushes.White, 15,h-100);
    }
}

// F for the embeddedF topology: the animated source is a child control inside S (ProbeForm),
// so WGC only reaches it by capturing S and cropping this region out of S's content.
internal sealed class EmbeddedFixturePanel : Panel
{
    private readonly System.Windows.Forms.Timer timer = new() { Interval = 33 };
    private int frame;
    internal EmbeddedFixturePanel()
    {
        DoubleBuffered = true; BackColor = Color.FromArgb(32,48,64);
        timer.Tick += (_,_) => { frame++; Invalidate(); };
        timer.Start();
    }
    internal void SetFrozen(bool frozen) { if (frozen) timer.Stop(); else timer.Start(); }
    protected override void OnPaint(PaintEventArgs e)
    {
        FixturePaint.Draw(e.Graphics, frame, ClientSize.Width, ClientSize.Height);
        // Keep the RGB crop oracle, but make its sampled texels carry F's own clock.
        int level = 160 + frame % 90;
        Color[] colors = [Color.FromArgb(level, 0, 0), Color.FromArgb(0, level, 0), Color.FromArgb(0, 0, level)];
        for (int i = 0; i < 3; i++)
        {
            using var brush = new SolidBrush(colors[i]);
            e.Graphics.FillRectangle(brush, (int)(ClientSize.Width * (0.2 + 0.3*i))-12, (int)(ClientSize.Height*0.3)-12, 25, 25);
        }
    }
    protected override void Dispose(bool disposing) { if (disposing) timer.Dispose(); base.Dispose(disposing); }
}

// P: the player-facing presentation window, a separate top-level root owned by ProbeForm (S).
// Top band is an animated magenta marker painted on P itself; the lower area hosts the compositor output.
internal sealed class PresentationForm : Form
{
    private readonly System.Windows.Forms.Timer markerTimer = new() { Interval = 40 };
    private int tick;
    internal readonly Panel OutputSurface = new() { BackColor = Color.Black };
    internal PresentationForm(Form owner)
    {
        Text = "CF7 compositor P — NOT DEPLOYED";
        FormBorderStyle = FormBorderStyle.None;
        StartPosition = FormStartPosition.Manual;
        ShowInTaskbar = false;
        Owner = owner;
        Controls.Add(OutputSurface);
        markerTimer.Tick += (_,_) => { tick++; Invalidate(new Rectangle(0, 0, ClientSize.Width, BandHeight)); };
        Shown += (_,_) => markerTimer.Start();
    }
    internal int BandHeight => Math.Max(24, (int)(ClientSize.Height * 0.36));
    internal void LayoutSurface() => OutputSurface.SetBounds(0, BandHeight, ClientSize.Width, ClientSize.Height - BandHeight);
    protected override bool ShowWithoutActivation => true;
    protected override void OnPaint(PaintEventArgs e)
    {
        var g = e.Graphics; int w = ClientSize.Width, bh = BandHeight;
        using var band = new SolidBrush(Color.FromArgb(190, 0, 130));
        g.FillRectangle(band, 0, 0, w, bh);
        int bx = (tick * 11) % Math.Max(1, w - 80);
        using var block = new SolidBrush(Color.FromArgb(255, 0, 255));
        g.FillRectangle(block, bx, bh / 2 - 24, 72, 48);
        using var font = new Font("Segoe UI", 8);
        g.DrawString($"P MARKER {tick}", font, Brushes.White, 6, 4);
    }
    protected override void Dispose(bool disposing) { if (disposing) markerTimer.Dispose(); base.Dispose(disposing); }
}

internal static class Native
{
    [StructLayout(LayoutKind.Sequential)]
    internal struct ContentStats
    {
        public uint Size, Count, ProofCount, Width, Height, MaxRgbError;
        public ulong InputHash, OutputHash;
        public readonly string InputHashHex => InputHash.ToString("X16");
        public readonly string OutputHashHex => OutputHash.ToString("X16");
    }
    internal static ContentStats ReadContent(nint handle)
    {
        var stats = new ContentStats { Size = (uint)Marshal.SizeOf<ContentStats>() };
        if (ProbeGetContentStats(handle, ref stats) != 1) throw new InvalidOperationException("Content diagnostic ABI mismatch");
        return stats;
    }
    [DllImport("FlashCompositorNative", CallingConvention = CallingConvention.Cdecl)] internal static extern void ProbeRequestContentProof(nint handle);
    [DllImport("FlashCompositorNative", CallingConvention = CallingConvention.Cdecl)] private static extern int ProbeGetContentStats(nint handle, ref ContentStats stats);
    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    internal struct Stats
    {
        public uint Size, State;
        public int Error;
        public uint Vendor, Device, FeatureLevel, Width, Height;
        public ulong Received, Presented, Superseded, Resizes, CpuReadbacks;
        public double AgeMs, MaxAgeMs, SubmitMs, PresentMs, LastFrameQpcMs;
        public uint ProofCount, ProofMode, ProofMaxError, ProofDistinct;
        [MarshalAs(UnmanagedType.ByValArray, SizeConst = 3)] public uint[] InputPixels;
        [MarshalAs(UnmanagedType.ByValArray, SizeConst = 3)] public uint[] OutputPixels;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 128)] public string Adapter;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 256)] public string Message;
    }
    internal static Stats Read(nint handle)
    {
        var stats = new Stats { Size = (uint)Marshal.SizeOf<Stats>() };
        if (ProbeGetStats(handle, ref stats) != 1) throw new InvalidOperationException("Native stats ABI mismatch");
        return stats;
    }
    [DllImport("FlashCompositorNative", CallingConvention = CallingConvention.Cdecl)] internal static extern nint ProbeStart(nint source, uint sourcePid, nint output, uint vendor);
    [DllImport("FlashCompositorNative", CallingConvention = CallingConvention.Cdecl)] internal static extern uint ProbeGetAbiVersion();
    [DllImport("FlashCompositorNative", CallingConvention = CallingConvention.Cdecl)] internal static extern void ProbeSetMode(nint handle, int mode);
    [DllImport("FlashCompositorNative", CallingConvention = CallingConvention.Cdecl)] internal static extern int ProbeSetLut(nint handle,[In] byte[] rgba);
    [DllImport("FlashCompositorNative", CallingConvention = CallingConvention.Cdecl)] internal static extern int ProbeSetWeather(nint handle,int type,float intensity,int quality,uint seed);
    [DllImport("FlashCompositorNative", CallingConvention = CallingConvention.Cdecl)] internal static extern int ProbeSetWeatherCamera(nint handle,float x,float y,float scale,float groundMin,float groundMax);
    [DllImport("FlashCompositorNative", CallingConvention = CallingConvention.Cdecl)] internal static extern int ProbeSetAtmosphere(nint handle,int preset,[In] float[] parameters);
    [DllImport("FlashCompositorNative", CallingConvention = CallingConvention.Cdecl)] internal static extern int ProbeSetWeatherStyle(nint handle,int type,int count,[In] float[] parameters);
    [DllImport("FlashCompositorNative", CallingConvention = CallingConvention.Cdecl)] internal static extern int ProbeSetAtmosphereStyle(nint handle,int family,[In] float[] parameters);
    [DllImport("FlashCompositorNative", CallingConvention = CallingConvention.Cdecl)] internal static extern int ProbeSetCrop(nint handle, int x, int y, int width, int height);
    [DllImport("FlashCompositorNative", CallingConvention = CallingConvention.Cdecl)] internal static extern void ProbeRequestProof(nint handle);
    [DllImport("FlashCompositorNative", CallingConvention = CallingConvention.Cdecl)] private static extern int ProbeGetStats(nint handle, ref Stats stats);
    [DllImport("FlashCompositorNative", CallingConvention = CallingConvention.Cdecl)] internal static extern void ProbeStop(nint handle);
    [DllImport("FlashCompositorNative", CallingConvention = CallingConvention.Cdecl)] internal static extern void ProbeHoldViewport(nint handle);
    [DllImport("FlashCompositorNative", CallingConvention = CallingConvention.Cdecl)] internal static extern int ProbeSetViewport(nint handle,int x,int y,int width,int height,double notBefore);
    [DllImport("FlashCompositorNative", CallingConvention = CallingConvention.Cdecl)] internal static extern int ProbeGrabLatestFrame(nint handle, byte[]? buffer, uint bufferSize, out uint width, out uint height);
    [DllImport("user32.dll")] internal static extern uint GetWindowThreadProcessId(nint window, out uint pid);
    [DllImport("user32.dll")] [return:MarshalAs(UnmanagedType.Bool)] internal static extern bool ClientToScreen(nint hwnd,ref Point point);
    [DllImport("user32.dll")] [return:MarshalAs(UnmanagedType.Bool)] internal static extern bool GetWindowRect(nint window, out Rect rect);
    [DllImport("user32.dll")] [return:MarshalAs(UnmanagedType.Bool)] internal static extern bool GetClientRect(nint window, out Rect rect);
    [DllImport("user32.dll")] [return:MarshalAs(UnmanagedType.Bool)] internal static extern bool SetWindowPos(nint window,nint after,int x,int y,int width,int height,uint flags);
    [DllImport("user32.dll")] [return:MarshalAs(UnmanagedType.Bool)] internal static extern bool ShowWindow(nint window,int command);
    [DllImport("user32.dll")] internal static extern nint GetParent(nint window);
    [DllImport("user32.dll")] internal static extern nint GetWindow(nint window, uint command);
    [DllImport("user32.dll")] internal static extern nint GetAncestor(nint window, uint flags);
    [DllImport("user32.dll", EntryPoint = "GetWindowLongPtrW")] internal static extern nint GetWindowLongPtr(nint window, int index);
    [DllImport("user32.dll")] [return:MarshalAs(UnmanagedType.Bool)] internal static extern bool IsWindow(nint window);
    [DllImport("user32.dll")] [return:MarshalAs(UnmanagedType.Bool)] internal static extern bool IsChild(nint parent, nint child);
    [DllImport("user32.dll")] internal static extern nint GetDC(nint window);
    [DllImport("user32.dll")] internal static extern int ReleaseDC(nint window, nint dc);
    [DllImport("user32.dll")] internal static extern nint WindowFromPoint(System.Drawing.Point point);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] internal static extern int GetClassName(nint window, System.Text.StringBuilder name, int max);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] internal static extern int GetWindowText(nint window, System.Text.StringBuilder text, int max);
    [DllImport("gdi32.dll")] internal static extern uint GetPixel(nint dc, int x, int y);
    [DllImport("user32.dll", SetLastError = true)] internal static extern nint SetParent(nint child, nint newParent);
    [DllImport("user32.dll", EntryPoint = "SetWindowLongPtrW")] internal static extern nint SetWindowLongPtr(nint window, int index, nint value);
    [DllImport("dwmapi.dll")] internal static extern int DwmGetWindowAttribute(nint window, int attribute, out Rect value, int size);
    [StructLayout(LayoutKind.Sequential)] internal struct Rect { public int Left,Top,Right,Bottom; public readonly Rectangle Rectangle => Rectangle.FromLTRB(Left,Top,Right,Bottom); }
}
