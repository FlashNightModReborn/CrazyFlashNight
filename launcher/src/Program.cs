// CF7:ME Guardian Process — 入口
// C# 5 语法

using System;
using System.Diagnostics;
using System.IO;
using System.Runtime.CompilerServices;
using System.Text.Json;
using System.Threading;
using System.Windows.Forms;
using CF7Launcher.Bus;
using CF7Launcher.Config;
using CF7Launcher.Diagnostic;
using CF7Launcher.Guardian;
using CF7Launcher.Data;
using CF7Launcher.Tasks;
using CF7Launcher.V8;
using Microsoft.Web.WebView2.Core;

class Program
{
    // volatile: HandleUiThreadException 可能在 form 引用刚被赋值后立即跑 (Application.Run 早期),
    // 不写成 volatile 时 JIT 理论上能 hoist 出 null. 实际 UI 线程单点写 + 单点读, 但加 volatile 零成本上保险.
    static volatile GuardianForm _guardianForm;
    static int _fatalUiExceptionExiting;

    // 退出早期把 overlay form 立即 SW_HIDE, 防 KillFlash WaitForExit / Dispose 期间任何窗口背景闪现.
    // 直接走 Form.Hide() 等价 ShowWindow(SW_HIDE), 不会触发 FormClosing.
    static void HideOverlayForm(System.Windows.Forms.Form f)
    {
        if (f == null) return;
        try { if (f.IsDisposed || !f.IsHandleCreated) return; } catch { return; }
        try { f.Hide(); } catch { }
    }

    static void HandleUiThreadException(Exception ex)
    {
        StartupDiagnostics.Exception("ui_thread_exception", ex);
        if (GuardianLifecycle.IsShuttingDown)
        {
            try { LogManager.Log("[Guardian] UI thread exception suppressed during shutdown:\n" + ex); } catch { }
            return;
        }

        if (Interlocked.Exchange(ref _fatalUiExceptionExiting, 1) != 0)
        {
            try { LogManager.Log("[Guardian] duplicate UI thread fatal exception dropped:\n" + ex); } catch { }
            return;
        }

        try { LogManager.Log("[Guardian] UI thread fatal exception; forcing shutdown:\n" + ex); } catch { }
        GuardianLifecycle.MarkShuttingDown();

        GuardianForm form = _guardianForm;
        if (form != null)
        {
            try
            {
                form.ForceExit();
                return;
            }
            catch (Exception exitEx)
            {
                try { LogManager.Log("[Guardian] ForceExit after UI fatal failed: " + exitEx); } catch { }
            }
        }

        try { Application.ExitThread(); } catch { }
        Environment.Exit(1);
    }

    [STAThread]
    static int Main(string[] args)
    {
        // candidate runtime-only 是显式的人类验收能力，不能让目录 walk-up 隐式触发。
        string explicitProjectRoot = TryGetProjectRootFromArgs(args);
        string earlyProjectRoot = explicitProjectRoot
                                  ?? TryWalkUpForProjectRoot(Environment.ProcessPath)
                                  ?? Path.GetDirectoryName(Environment.ProcessPath);
        StartupDiagnostics.Init(earlyProjectRoot);
        StartupDiagnostics.Mark("core.main_enter", "projectRoot=" + earlyProjectRoot);
        bool isolatedRuntimeCandidate;
        if (!VerifyDeployedRuntimeBundle(explicitProjectRoot, out isolatedRuntimeCandidate))
        {
            StartupDiagnostics.Exit("runtime_bundle_self_check_failed");
            return 2;
        }
        return MainAfterStartupDiagnostics(args, earlyProjectRoot, isolatedRuntimeCandidate);
    }

    // Headless scripts normally probe through the native bootstrap first, but the invariant
    // must also survive manual Core.exe launch and future entrypoints. Reuse the native verifier
    // instead of maintaining a second manifest parser in managed code.
    static bool VerifyDeployedRuntimeBundle(string explicitProjectRoot, out bool isolatedRuntimeCandidate)
    {
        isolatedRuntimeCandidate = false;
        string baseDir = Path.GetFullPath(AppContext.BaseDirectory).TrimEnd(Path.DirectorySeparatorChar);
        DirectoryInfo runtimeDir = new DirectoryInfo(baseDir);
        if (!string.Equals(runtimeDir.Name, "runtime", StringComparison.OrdinalIgnoreCase)) return true;

        DirectoryInfo projectRoot = runtimeDir.Parent;
        if (projectRoot == null) return false;
        string bootstrap = Path.Combine(projectRoot.FullName, "CRAZYFLASHER7MercenaryEmpire.exe");
        if (!File.Exists(bootstrap)) return false;

        try
        {
            string verificationArgument = SelectRuntimeVerificationArgument(runtimeDir.FullName, explicitProjectRoot);
            isolatedRuntimeCandidate = verificationArgument == "--verify-runtime-only";
            StartupDiagnostics.Mark("runtime_bundle_self_check_start",
                "mode=" + (isolatedRuntimeCandidate ? "isolated_candidate" : "formal_runtime"));
            ProcessStartInfo psi = new ProcessStartInfo
            {
                FileName = bootstrap,
                Arguments = verificationArgument,
                UseShellExecute = false,
                CreateNoWindow = true,
                WorkingDirectory = projectRoot.FullName
            };
            using (Process probe = Process.Start(psi))
            {
                if (probe == null) return false;
                if (!probe.WaitForExit(60000))
                {
                    try { probe.Kill(true); } catch { }
                    return false;
                }
                return probe.ExitCode == 0;
            }
        }
        catch (Exception ex)
        {
            StartupDiagnostics.Exception("runtime_bundle_self_check_exception", ex);
            return false;
        }
    }

    // 未提交工作树的人类验收使用 producer 生成的隔离 candidate Core，并通过显式
    // --project-root 加载当前工作树。只有“显式项目根与 candidate 根不同”、candidate 位于
    // 该根的固定 producer 输出树、路径不含 reparse 别名、完整安装哨兵存在，且 metadata 与 runtime manifest 身份
    // 完全匹配时才允许 runtime-only；正式部署、坏 marker、身份漂移一律保持完整安装校验。
    internal static string SelectRuntimeVerificationArgument(string runtimeDirectory, string explicitProjectRoot)
    {
        return IsIsolatedRuntimeCandidate(runtimeDirectory, explicitProjectRoot)
            ? "--verify-runtime-only"
            : "--verify-only";
    }

    internal static bool IsIsolatedRuntimeCandidate(string runtimeDirectory, string explicitProjectRoot)
    {
        if (string.IsNullOrEmpty(runtimeDirectory) || string.IsNullOrEmpty(explicitProjectRoot)) return false;

        try
        {
            string runtimePath = Path.TrimEndingDirectorySeparator(Path.GetFullPath(runtimeDirectory));
            DirectoryInfo runtimeDir = new DirectoryInfo(runtimePath);
            if (!string.Equals(runtimeDir.Name, "runtime", StringComparison.OrdinalIgnoreCase)) return false;

            DirectoryInfo candidateRoot = runtimeDir.Parent;
            if (candidateRoot == null) return false;
            string selectedRoot = Path.TrimEndingDirectorySeparator(Path.GetFullPath(explicitProjectRoot));
            if (string.Equals(candidateRoot.FullName, selectedRoot, StringComparison.OrdinalIgnoreCase)) return false;
            if (!Directory.Exists(selectedRoot)) return false;
            if (!File.Exists(Path.Combine(selectedRoot, "crossdomain.xml"))) return false;
            if (!File.Exists(Path.Combine(selectedRoot, "launcher", "web", "bootstrap.html"))) return false;

            string candidateBase = Path.Combine(selectedRoot, "tmp", "runtime-candidates", "v2");
            string candidateBasePath = Path.TrimEndingDirectorySeparator(Path.GetFullPath(candidateBase));
            string candidateRootPath = Path.TrimEndingDirectorySeparator(candidateRoot.FullName);
            if (!candidateRootPath.StartsWith(candidateBasePath + Path.DirectorySeparatorChar,
                    StringComparison.OrdinalIgnoreCase))
                return false;
            if (HasReparsePointBelowRoot(runtimeDir, selectedRoot)) return false;

            string metadataPath = Path.Combine(candidateRoot.FullName, "runtime-build-metadata.v2.json");
            string manifestPath = Path.Combine(runtimePath, "cf7-runtime-manifest.tsv");
            if (!TryReadCandidateIdentity(metadataPath, out string metadataBuildIdentity, out string metadataPayloadClosure))
                return false;
            if (!TryReadManifestIdentity(manifestPath, out string manifestBuildIdentity, out string manifestPayloadClosure))
                return false;

            return string.Equals(metadataBuildIdentity, manifestBuildIdentity, StringComparison.OrdinalIgnoreCase)
                   && string.Equals(metadataPayloadClosure, manifestPayloadClosure, StringComparison.OrdinalIgnoreCase);
        }
        catch
        {
            return false;
        }
    }

    static bool TryReadCandidateIdentity(string metadataPath, out string buildIdentity, out string payloadClosure)
    {
        buildIdentity = null;
        payloadClosure = null;
        if (!File.Exists(metadataPath)) return false;
        long length = new FileInfo(metadataPath).Length;
        if (length <= 0 || length > 64 * 1024) return false;

        using (JsonDocument document = JsonDocument.Parse(File.ReadAllText(metadataPath)))
        {
            JsonElement root = document.RootElement;
            if (root.ValueKind != JsonValueKind.Object) return false;
            int schemaCount = 0;
            int buildCount = 0;
            int payloadCount = 0;
            foreach (JsonProperty property in root.EnumerateObject())
            {
                if (property.NameEquals("schema")) schemaCount++;
                else if (property.NameEquals("buildIdentityHash")) buildCount++;
                else if (property.NameEquals("payloadClosureHash")) payloadCount++;
            }
            if (schemaCount != 1 || buildCount != 1 || payloadCount != 1) return false;
            if (!root.TryGetProperty("schema", out JsonElement schema)
                || !string.Equals(schema.GetString(), "cf7-runtime-candidate-metadata.v2", StringComparison.Ordinal))
                return false;
            if (!root.TryGetProperty("buildIdentityHash", out JsonElement build)
                || !root.TryGetProperty("payloadClosureHash", out JsonElement payload))
                return false;

            buildIdentity = build.GetString();
            payloadClosure = payload.GetString();
            return IsSha256Hex(buildIdentity) && IsSha256Hex(payloadClosure);
        }
    }

    static bool TryReadManifestIdentity(string manifestPath, out string buildIdentity, out string payloadClosure)
    {
        buildIdentity = null;
        payloadClosure = null;
        if (!File.Exists(manifestPath)) return false;
        long length = new FileInfo(manifestPath).Length;
        if (length <= 0 || length > 1024 * 1024) return false;

        string[] lines = File.ReadAllLines(manifestPath);
        if (lines.Length == 0 || !string.Equals(lines[0], "cf7-runtime-manifest-v2", StringComparison.Ordinal))
            return false;
        for (int i = 1; i < lines.Length; i++)
        {
            string[] fields = lines[i].Split('\t');
            if (fields.Length != 2) continue;
            if (string.Equals(fields[0], "buildIdentityHash", StringComparison.Ordinal))
            {
                if (buildIdentity != null) return false;
                buildIdentity = fields[1];
            }
            else if (string.Equals(fields[0], "payloadClosureHash", StringComparison.Ordinal))
            {
                if (payloadClosure != null) return false;
                payloadClosure = fields[1];
            }
        }
        return IsSha256Hex(buildIdentity) && IsSha256Hex(payloadClosure);
    }

    static bool HasReparsePointBelowRoot(DirectoryInfo leaf, string rootPath)
    {
        string normalizedRoot = Path.TrimEndingDirectorySeparator(Path.GetFullPath(rootPath));
        DirectoryInfo current = leaf;
        while (current != null
               && !string.Equals(Path.TrimEndingDirectorySeparator(current.FullName), normalizedRoot,
                   StringComparison.OrdinalIgnoreCase))
        {
            if ((current.Attributes & FileAttributes.ReparsePoint) != 0) return true;
            current = current.Parent;
        }
        return current == null;
    }

    static bool IsSha256Hex(string value)
    {
        if (string.IsNullOrEmpty(value) || value.Length != 64) return false;
        for (int i = 0; i < value.Length; i++)
        {
            if (!Uri.IsHexDigit(value[i])) return false;
        }
        return true;
    }

    // 防止 JIT 内联导致 DpiAwarenessBootstrap.Initialize() 的异常栈折叠进 Main，影响 startup diagnostics 定位。
    [MethodImpl(MethodImplOptions.NoInlining)]
    static int MainAfterStartupDiagnostics(string[] args, string earlyProjectRoot, bool isolatedRuntimeCandidate)
    {
        long processStart = Stopwatch.GetTimestamp();
        PerfTrace.SetProcessStart(processStart);
        DpiAwarenessBootstrap.Initialize();

        // 单例检查
        bool createdNew;
        Mutex mutex = new Mutex(true, "Global\\CF7ME_Guardian", out createdNew);
        if (!createdNew)
        {
            StartupDiagnostics.Exit("singleton_already_running");
            mutex.Dispose();
            return 0;
        }

        Application.EnableVisualStyles();
        Application.SetCompatibleTextRenderingDefault(false);

        // UI 线程未处理异常: 必须在第一次 WinForms 调用之前 SetUnhandledExceptionMode + 装 handler.
        // 退出期只写日志并压掉默认 ThreadExceptionDialog; 运行期仍按 fatal 处理并退出, 避免半状态继续跑.
        Application.SetUnhandledExceptionMode(UnhandledExceptionMode.CatchException);
        Application.ThreadException += delegate(object s, System.Threading.ThreadExceptionEventArgs te)
        {
            HandleUiThreadException(te.Exception);
        };

        // 非 UI 线程未处理异常：仅补日志（进程即将终止，CLR 自行处理）
        AppDomain.CurrentDomain.UnhandledException += delegate(object s, UnhandledExceptionEventArgs ue)
        {
            try { StartupDiagnostics.Mark("appdomain_unhandled_exception", Convert.ToString(ue.ExceptionObject)); } catch { }
            try { LogManager.Log("[Guardian] Unhandled exception:\n" + ue.ExceptionObject); } catch { }
        };

        try
        {
            return Run(args, isolatedRuntimeCandidate);
        }
        catch (Exception ex)
        {
            StartupDiagnostics.Exception("core.main_unhandled_exception", ex);
            try { LogManager.Log("[Guardian] Main fatal exception:\n" + ex); } catch { }
            try
            {
                StartupFailureReporter.ReportTerminalFailure(
                    null,
                    earlyProjectRoot,
                    "core.main_unhandled_exception",
                    "CF7-LAUNCH-CORE-UNHANDLED",
                    "启动器发生未处理异常",
                    ex.GetType().FullName + ": " + ex.Message,
                    "请重启游戏；如果问题持续存在，请把诊断包发给开发组。",
                    null,
                    null,
                    null);
            }
            catch { }
            return 1;
        }
        finally
        {
            StartupDiagnostics.Mark("core.main_exit");
            mutex.ReleaseMutex();
            mutex.Dispose();
        }
    }

    /// <summary>
    /// 从命令行参数读 --project-root <abs path>（bootstrap 注入）。返回 null 表示没传或路径无效。
    /// </summary>
    static string TryGetProjectRootFromArgs(string[] args)
    {
        if (args == null) return null;
        for (int i = 0; i < args.Length - 1; i++)
        {
            if (string.Equals(args[i], "--project-root", StringComparison.OrdinalIgnoreCase))
            {
                string path = args[i + 1];
                if (!string.IsNullOrEmpty(path) && Directory.Exists(path))
                {
                    return Path.GetFullPath(path).TrimEnd('\\', '/');
                }
            }
        }
        return null;
    }

    /// <summary>
    /// 剥离 args 中已被 bootstrap injection 消费的 --project-root <path> 二元组，
    /// 让下游解析器看不到这两个 token。当前下游用 Array.IndexOf 检 flag，本不冲突；
    /// 防御未来位置参数解析撞上 "--project-root"/路径字符串造成误判。
    /// </summary>
    static string[] StripProjectRootArgs(string[] args)
    {
        if (args == null || args.Length == 0) return args;
        string[] tmp = new string[args.Length];
        int n = 0;
        for (int i = 0; i < args.Length; i++)
        {
            if (string.Equals(args[i], "--project-root", StringComparison.OrdinalIgnoreCase)
                && i + 1 < args.Length)
            {
                i++; // 跳过紧跟的路径值
                continue;
            }
            tmp[n++] = args[i];
        }
        if (n == args.Length) return args;
        string[] result = new string[n];
        Array.Copy(tmp, result, n);
        return result;
    }

    /// <summary>
    /// 哨兵文件 walk-up：从 startExePath 所在目录向上找含 crossdomain.xml 的目录。
    /// crossdomain.xml 是 Flash socket 跨域策略文件，必须放在 projectRoot；存在即认作 projectRoot.
    /// 最多向上 6 层；找不到返回 null（调用方 fallback 到 ProcessPath 父目录）。
    /// </summary>
    static string TryWalkUpForProjectRoot(string startExePath)
    {
        if (string.IsNullOrEmpty(startExePath)) return null;
        try
        {
            string dir = Path.GetDirectoryName(startExePath);
            for (int i = 0; i < 6 && !string.IsNullOrEmpty(dir); i++)
            {
                if (File.Exists(Path.Combine(dir, "crossdomain.xml")))
                {
                    return Path.GetFullPath(dir).TrimEnd('\\', '/');
                }
                string parent = Path.GetDirectoryName(dir);
                if (parent == dir) break;  // 已到根
                dir = parent;
            }
        }
        catch { }
        return null;
    }

    static HighDpiCompatibilityResult DetectDpiCompatibility(string projectRoot, string coreExePath)
    {
        HighDpiCompatibilityResult core = HighDpiCompatibilityDetector.Detect(coreExePath);

        string bootstrapExePath = null;
        if (!string.IsNullOrEmpty(projectRoot))
            bootstrapExePath = Path.Combine(projectRoot, "CRAZYFLASHER7MercenaryEmpire.exe");
        HighDpiCompatibilityResult bootstrap = HighDpiCompatibilityDetector.Detect(bootstrapExePath);

        if (bootstrap != null && bootstrap.IsRiskyOverride) return bootstrap;
        if (core != null && core.IsRiskyOverride) return core;
        if (bootstrap != null && bootstrap.IsApplicationOverride) return bootstrap;
        if (core != null && core.IsApplicationOverride) return core;
        return core ?? bootstrap;
    }

    static int Run(string[] args, bool isolatedRuntimeCandidate)
    {
        // 定位项目根目录:
        // 1. 优先 bootstrap 传 --project-root <abs>（FDD 产物在 projectRoot/runtime/ 子目录,
        //    AppContext.BaseDirectory != projectRoot, 必须显式传）
        // 2. 否则 fallback: 从 Environment.ProcessPath 向上 walk 找哨兵文件 crossdomain.xml,
        //    覆盖 dev 直跑 bin/Debug/net10.0-windows/win-x64/*.exe 的场景, 以及未来 packer 可能
        //    改变 Core 子目录名时的 robustness
        // 3. 都失败: 退而用 Environment.ProcessPath 父目录, 与历史行为一致（user 误点 Core 时
        //    至少不立刻 NullReferenceException, 由后续资产 verify 给出可读错误）
        string projectRoot = TryGetProjectRootFromArgs(args)
                             ?? TryWalkUpForProjectRoot(Environment.ProcessPath)
                             ?? Path.GetDirectoryName(Environment.ProcessPath);
        string exePath = Environment.ProcessPath;
        StartupDiagnostics.Init(projectRoot);

        // 剥离已消费的 --project-root <path>，避免下游 flag 检测撞上路径字符串
        args = StripProjectRootArgs(args);

        bool busOnly = Array.IndexOf(args, "--bus-only") >= 0;
        bool forceWebViewFail = Array.IndexOf(args, "--force-webview-fail") >= 0;
        StartupDiagnostics.LogCoreEnvironment(exePath, args, busOnly, forceWebViewFail);
        StartupDiagnostics.ProbeCoreSidecars();
        StartupDiagnostics.Mark("core.run_start", "busOnly=" + busOnly);
        LogManager.InitFileLog(projectRoot);
        StartupDiagnostics.Mark("launcher_log.early_ready", "path=" + LogManager.LogFilePath);
        LogManager.Log("[Guardian] Early file log ready before WebView2 precheck");
        PerfTrace.Init(projectRoot);
        PerfTrace.Mark("guardian.run_start");

        // Phase 1 (11b-β): WebView2 全局硬依赖 fail-closed 预检.
        // 正常模式必须 WebView2 Runtime 可用才能创建 BootstrapForm; bus-only 跳过.
        if (!busOnly)
        {
            long wv2CheckStart = Stopwatch.GetTimestamp();
            string wv2Error = null;
            if (forceWebViewFail)
            {
                wv2Error = "forced by --force-webview-fail flag";
            }
            else
            {
                try
                {
                    string wv2Version = CoreWebView2Environment.GetAvailableBrowserVersionString();
                    StartupDiagnostics.Mark("webview2.precheck_ok", "version=" + wv2Version);
                }
                catch (Exception ex) { wv2Error = ex.Message; }
            }
            PerfTrace.Duration("webview2.runtime_precheck", wv2CheckStart,
                wv2Error == null ? "ok" : wv2Error);
            if (wv2Error != null)
            {
                LogManager.Log("[Guardian] FATAL: webview2_missing — exiting with code 1; detail=" + wv2Error);
                StartupFailureReporter.ReportTerminalFailure(
                    null,
                    projectRoot,
                    "webview2_missing",
                    "CF7-LAUNCH-WEBVIEW2-MISSING",
                    "WebView2 Runtime 不可用",
                    wv2Error,
                    "请安装或修复 Microsoft Edge WebView2 Runtime，然后重新启动游戏。官方下载页: https://developer.microsoft.com/microsoft-edge/webview2/",
                    null,
                    null,
                    null);
                PerfTrace.Mark("guardian.exit", "webview2_missing");
                PerfTrace.Shutdown();
                return 1;
            }
        }

        // Phase A: single-Form 模型。GuardianForm 承载 BootstrapPanel（正常模式）。
        // bus-only 模式 bootstrapWebDir=null，不创建 BootstrapPanel，FlashHostPanel 直接可见。
        long configStart = Stopwatch.GetTimestamp();
        StartupDiagnostics.Mark("config.load_start");
        AppConfig config = new AppConfig(projectRoot);
        PerfTrace.Duration("config.load", configStart);
        StartupDiagnostics.Mark("config.load_ok",
            "useNativeHud=" + config.UseNativeHud
            + " webView2DisableGpu=" + config.WebView2DisableGpu
            + " gpuPreference=" + config.GpuPreference);
        StartupDiagnostics.ProbeProjectFiles(projectRoot, config.FlashPlayerPath, config.SwfPath, !busOnly);

        string bootstrapWebDir = busOnly ? null : Path.Combine(projectRoot, "launcher", "web");
        long formStart = Stopwatch.GetTimestamp();
        StartupDiagnostics.Mark("guardian.form_construct_start", "bootstrapWebDir=" + (bootstrapWebDir ?? "(null)"));
        GuardianForm form = new GuardianForm(
            bootstrapWebDir,
            config.WebView2DisableGpu,
            config.WebView2AdditionalArgs,
            isolatedRuntimeCandidate);
        _guardianForm = form;
        PerfTrace.Duration("guardian.form_construct", formStart);
        PerfTrace.Mark("guardian.form_constructed");
        StartupDiagnostics.Mark("guardian.form_construct_ok");

        // 文件日志已在 WebView2 预检前启用；这里幂等确认，GuardianForm 构造函数中已初始化 UI 通道。
        LogManager.InitFileLog(projectRoot);
        StartupDiagnostics.Mark("launcher_log.ready", "path=" + LogManager.LogFilePath);
        if (!string.IsNullOrEmpty(PerfTrace.TracePath))
            LogManager.Log("[PerfTrace] writing " + PerfTrace.TracePath);

        LogManager.Log("[Guardian] Project root: " + projectRoot);

        // ====== 渲染合成层诊断 (config.toml diag* / env CF7_DIAG_* opt-in, 默认 OFF) ======
        // diagLayerAudit           启动 + ready + shutdown 三次 dump 所有 top-level HWND + WS_EX 标志
        // diagUlwMonitor           持续监控 OverlayBase.CommitBitmap 频率 / p50 / p95 / p99 / max
        // diagEtwDwm               订阅 Microsoft-Windows-Dwm-Core ETW provider (需 admin)
        // diagReportIntervalSec    ULW + ETW 报告周期, 默认 5s
        DiagnosticsBootstrap.Init(
            config.DiagLayerAudit,
            config.DiagUlwMonitor,
            config.DiagEtwDwm,
            config.DiagReportIntervalSec);

        // 开发用 Ctrl+G GPU 探针：仅 config.devGpuProbeHotkey=true 时启用。玩家版默认不注入。
        if (config.DevGpuProbeHotkey)
            form.EnableDevGpuProbeHotkey();

        // UserGpuPreferences 在子进程创建时被 Windows 读取。WebView2 真正 spawn 发生在 Application.Run
        // 触发 BootstrapPanel.Load 之后，所以这里写入仍然赶得上；放在日志通道就绪之后可以把诊断完整写进 launcher.log。
        GpuPreferenceManager.ApplyIfNeeded(projectRoot, config.GpuPreference);
        // Phase 2b: 用户级偏好 (lastPlayedSlot / introEnabled), 落盘到 launcher_user_prefs.json
        CF7Launcher.Config.UserPrefs userPrefs = new CF7Launcher.Config.UserPrefs(projectRoot);

        HighDpiCompatibilityResult dpiCompat = DetectDpiCompatibility(projectRoot, exePath);
        DpiDiagnostics.LogProcessStartup(DpiAwarenessBootstrap.Result, dpiCompat);
        DpiDiagnostics.LogWindow("GuardianForm", form.Handle);
        HighDpiCompatibilityDetector.ScheduleRiskWarning(form, dpiCompat, userPrefs);
        if (busOnly)
            LogManager.Log("[Guardian] --bus-only mode: skipping Flash Player startup");

        // Steam 正版所有权校验（不通过则不写信任文件，Flash 无法联网）
        StartupDiagnostics.Mark("steam.check_start");
        if (!SteamOwnershipCheck.Check(projectRoot))
        {
            LogManager.Log("[Guardian] Steam ownership check FAILED — refusing to write trust file");
            string reason = SteamOwnershipCheck.FailReason;
            LogManager.Log("[Guardian] FATAL: steam_ownership_failed — exiting with code 1; reason=" + (reason ?? "(null)"));
            string steamCode = "CF7-LAUNCH-STEAM-OWNERSHIP";
            string steamRecommendation = "请从 Steam 库启动游戏，并确认当前 Steam 账号拥有本游戏。";
            if (reason == "steam_not_running")
            {
                steamCode = "CF7-LAUNCH-STEAM-NOT-RUNNING";
                steamRecommendation = "请先启动 Steam，然后从 Steam 库重新启动游戏。";
            }
            else if (reason == "not_owned")
            {
                steamCode = "CF7-LAUNCH-STEAM-NOT-OWNED";
                steamRecommendation = "当前 Steam 账号未检测到游戏所有权。请切换到拥有本游戏的账号后重试。";
            }
            else if (reason == "dll_missing" || reason == "dll_load_failed")
            {
                steamCode = "CF7-LAUNCH-STEAM-RUNTIME";
                steamRecommendation = "Steam 运行时文件缺失或损坏。请通过 Steam 验证游戏文件完整性。";
            }
            StartupFailureReporter.ReportTerminalFailure(
                form,
                projectRoot,
                "steam_ownership_failed",
                steamCode,
                "Steam 所有权校验失败",
                "reason=" + (reason ?? "(null)"),
                steamRecommendation,
                null,
                config.SwfPath,
                null);
            PerfTrace.Mark("guardian.exit", "steam_ownership_failed");
            PerfTrace.Shutdown();
            return 1;
        }
        StartupDiagnostics.Mark("steam.check_ok");

        // Flash Player 本地信任配置（确保 SWF 可访问网络）
        // 使用 try/finally 确保所有退出路径都调用 RevokeTrust
        StartupDiagnostics.Mark("flash_trust.start");
        bool trustAcquired = FlashTrustManager.EnsureTrust(projectRoot);
        if (!trustAcquired)
        {
            LogManager.Log("[Guardian] WARNING: Flash trust not configured — SWF may fail to connect");
            StartupDiagnostics.Warn("flash_trust.failed", "SWF may fail to connect");
        }
        else
        {
            StartupDiagnostics.Mark("flash_trust.ok");
        }

        try
        {

        if (!busOnly)
        {
            if (!File.Exists(config.FlashPlayerPath))
            {
                LogManager.Log("[Guardian] FATAL: flash_player_missing — exiting with code 1; path=" + config.FlashPlayerPath);
                StartupFailureReporter.ReportTerminalFailure(
                    form,
                    projectRoot,
                    "flash_player_missing",
                    "CF7-LAUNCH-FILE-MISSING-FLASH",
                    "Flash Player 文件缺失",
                    config.FlashPlayerPath,
                    "请通过 Steam 验证游戏文件完整性，或重新下载完整安装包。",
                    null,
                    config.SwfPath,
                    null);
                return 1;
            }
            if (!File.Exists(config.SwfPath))
            {
                LogManager.Log("[Guardian] FATAL: swf_missing — exiting with code 1; path=" + config.SwfPath);
                StartupFailureReporter.ReportTerminalFailure(
                    form,
                    projectRoot,
                    "swf_missing",
                    "CF7-LAUNCH-FILE-MISSING-SWF",
                    "游戏 SWF 文件缺失",
                    config.SwfPath,
                    "请通过 Steam 验证游戏文件完整性，或重新下载完整安装包。",
                    null,
                    config.SwfPath,
                    null);
                return 1;
            }

            LogManager.Log("[Guardian] Flash: " + config.FlashPlayerPath);
            LogManager.Log("[Guardian] SWF: " + config.SwfPath);
        }

        // === 音频引擎（在所有网络服务之前初始化）===
        using (PerfTrace.Scope("audio.init"))
        {
            StartupDiagnostics.Mark("audio.init_start");
            bool audioOk = CF7Launcher.Audio.AudioEngine.Init(projectRoot);
            if (audioOk)
            {
                StartupDiagnostics.Mark("audio.init_ok");
            }
            else
            {
                StartupDiagnostics.Warn("audio.init_failed", "continuing without audio");
                LogManager.Log("[Guardian] WARNING: Audio engine init failed, continuing without audio");
            }
        }
        // P0 perf：SFX preload 异步化。主线程不再为 ~1.2s 文件 I/O 阻塞；
        // preload 在后台 ThreadPool 跑（与 PerfTrace.Scope 不兼容，自带 audio.sfx_preload_done mark），
        // socket 线程通过 ResolveSfxHandle 拿 handle，未完成期间返回 -1 = "id 不存在"行为，不会错位播音。
        // Flash 在 t≈6s 才连接、reveal 在 t≈15s，1.2s 后台加载完全藏在等待窗口内。
        CF7Launcher.Audio.AudioEngine.PreloadFromDirectoriesAsync(projectRoot);
        PerfTrace.Mark("audio.sfx_preload_dispatched_async");

        // 默认音量（直接 P/Invoke，不依赖 Flash socket）
        // Flash 存档加载后会通过 setGlobalVolume/setBGMVolume 覆盖
        CF7Launcher.Audio.AudioEngine.ma_bridge_set_master_volume(0.5f);  // 50%

        // === 音乐目录（扫描 + 热加载监听）===
        CF7Launcher.Audio.MusicCatalog musicCatalog;
        using (PerfTrace.Scope("music.catalog_init"))
        {
            musicCatalog = new CF7Launcher.Audio.MusicCatalog(projectRoot);
        }

        // === V8 总线（两种模式都启动）===

        PortAllocator portAlloc = new PortAllocator();
        MessageRouter router = new MessageRouter();

        int httpPort = portAlloc.ClaimPort();

        XmlSocketServer socketServer = new XmlSocketServer(router);
        int socketPort = portAlloc.ClaimPort();
        bool socketStarted = false;
        if (socketPort >= 0)
        {
            using (PerfTrace.Scope("socket.start"))
            {
                socketStarted = socketServer.Start(socketPort);
            }
        }
        if (socketPort < 0 || !socketStarted)
        {
            LogManager.Log("[Guardian] FATAL: socket_start_failed — exiting with code 1; port=" + socketPort);
            StartupFailureReporter.ReportTerminalFailure(
                form,
                projectRoot,
                "socket_start_failed",
                "CF7-LAUNCH-SOCKET-START",
                "本地通信端口启动失败",
                "socketPort=" + socketPort,
                "请关闭重复启动的游戏/启动器后重试；如果仍失败，请重启 Windows 或把诊断包发给开发组。",
                null,
                config.SwfPath,
                null);
            socketServer.Dispose();
            return 1;
        }
        StartupDiagnostics.Mark("socket.start_ok", "port=" + socketPort);

        HttpApiServer httpServer = new HttpApiServer(socketPort, projectRoot, socketServer);
        bool httpStarted = false;
        if (httpPort >= 0)
        {
            using (PerfTrace.Scope("http.start"))
            {
                httpStarted = httpServer.Start(httpPort);
            }
        }
        if (httpPort < 0 || !httpStarted)
        {
            LogManager.Log("[Guardian] FATAL: http_start_failed — exiting with code 1; port=" + httpPort);
            StartupFailureReporter.ReportTerminalFailure(
                form,
                projectRoot,
                "http_start_failed",
                "CF7-LAUNCH-HTTP-START",
                "本地 HTTP 服务启动失败",
                "httpPort=" + httpPort,
                "请关闭重复启动的游戏/启动器后重试；如果仍失败，请重启 Windows 或把诊断包发给开发组。",
                null,
                config.SwfPath,
                null);
            socketServer.Dispose();
            httpServer.Dispose();
            return 1;
        }
        StartupDiagnostics.Mark("http.start_ok", "port=" + httpPort);

        router.OnConsoleResult += delegate(string json)
        {
            httpServer.ResolveConsoleResult(json);
        };

        // 音乐目录推送：Flash 业务就绪后发送完整 catalog
        socketServer.OnClientReady += delegate {
            LogManager.Log("[MusicCatalog] Pushing full catalog to Flash");
            string catalogJson = musicCatalog.GetFullCatalogJson();
            socketServer.Send(catalogJson + "\0");
        };

        // 音乐目录热更新推送到 Flash
        musicCatalog.CatalogChanged += delegate(string updateJson) {
            if (socketServer.IsClientReady)
                socketServer.Send(updateJson + "\0");
        };

        // Toast overlay（GDI+ 独立 ULW，仅 useNativeHud=false 时实例化）。
        // useNativeHud=true 时 ToastWidget 在 NativeHudOverlay 内承载，省一层全屏 layered window。
        ToastOverlay toastOverlay = null;
        if (!config.UseNativeHud)
        {
            toastOverlay = new ToastOverlay(form, form.FlashHostPanel);
        }

        // V8 持久化 Runtime + 打击伤害数字 overlay
        string scriptsDir = Path.Combine(projectRoot, "launcher", "scripts");
        V8Runtime v8Runtime;
        using (PerfTrace.Scope("v8.construct"))
        {
            v8Runtime = new V8Runtime(scriptsDir);
        }
        HitNumberOverlay hnOverlay = new HitNumberOverlay(form, form.FlashHostPanel);
        FrameTask frameTask = new FrameTask(v8Runtime, hnOverlay);

        // 性能决策引擎（主控模式：发送 P 指令到 AS2，AS2 端只采样+执行）
        var perfEngine = new PerfDecisionEngine(frameTask.FpsBuffer, socketServer);
        perfEngine.IsActive = true;
        frameTask.SetDecisionEngine(perfEngine);

        // 搓招输入处理：注入 socket 引用用于 K 前缀推送，初始化 V8 GameInput
        frameTask.SetSocket(socketServer);
        using (PerfTrace.Scope("v8.game_input_init"))
        {
            v8Runtime.InitGameInput();
        }

        // 刘海 Notch overlay（FPS 显示 + 可展开工具栏）。
        // useNativeHud=true 时不实例化独立 ULW；下面 if (UseNativeHud) 分支用 NotchWidget 在 NativeHud 内承载，省一层 layered window。
        NotchOverlay notchOverlay = null;
        if (!config.UseNativeHud)
        {
            notchOverlay = new NotchOverlay(
                form, form.FlashHostPanel, frameTask.FpsBuffer,
                projectRoot,
                new Action(form.ToggleFullscreen),
                new Action(form.ToggleLog),
                delegate
                {
                    form.EmergencyExit(
                        GuardianForm.EmergencyExitReason.HardExitKeyQ);
                },
                new Action<Keys>(form.HandleButtonClick));
        }

        // Phase 1 (11c): WebView2 全局硬依赖; 入口已预检, 这里 WebOverlayForm 构造异常直接 throw 到上游
        string wv2ver;
        using (PerfTrace.Scope("webview2.runtime_check"))
        {
            wv2ver = CoreWebView2Environment.GetAvailableBrowserVersionString();
        }
        LogManager.Log("[WebView2] Runtime found: " + wv2ver);
        StartupDiagnostics.Mark("webview2.runtime_check_ok", "version=" + wv2ver);
        string webDir = Path.Combine(projectRoot, "launcher", "web");
        // Flash hwnd 动态查询（SA 进程重启后 hwnd 变）。提前到 WebOverlay 构造前，
        // 因为后续 PanelHostController 也复用同一份。WebOverlay 自身的焦点回推走 flashFocusRestorer。
        Func<IntPtr> flashHwndProvider = delegate { return form.GetFlashHwnd(); };
        // WindowManager 早声明：WebOverlay 构造时需要它的 RestoreFlashInputFocus primitive；
        // 实际 form.BindWindowManager / perfEngine.SetActivationState / OnKillFlash 还在后面统一装配。
        WindowManager windowManager = new WindowManager();
        WebOverlayForm webOverlay;
        using (PerfTrace.Scope("web_overlay.construct"))
        {
            StartupDiagnostics.Mark("web_overlay.construct_start");
            // Flash 焦点恢复 primitive：所有 panel close / navigate 路径都走 WindowManager.RestoreFlashInputFocus，
            // 带 AttachThreadInput 兜底 + 前后 fg/pid 日志 + 校验，统一替代散落的裸 SetForegroundWindow。
            Func<string, bool> flashFocusRestorer = delegate(string reason)
            {
                return windowManager.RestoreFlashInputFocus(reason);
            };
            webOverlay = new WebOverlayForm(form, form.FlashHostPanel, webDir, projectRoot,
                config.WebOverlayLowEffects,
                config.WebOverlayDisableCssAnimations,
                config.WebOverlayDisableVisualizers,
                config.WebOverlayFrameRateLimit,
                config.WebView2DisableGpu,
                config.WebView2AdditionalArgs,
                config.WebOverlayPanelTakeForeground,
                config.WebOverlayHotReload,
                flashFocusRestorer);
        }
        StartupDiagnostics.Mark("web_overlay.construct_ok");
        CF7Launcher.Guardian.Hud.INativeCursor cursorOverlay = null;
        if (config.NativeCursorOverlayEnabled)
        {
            string cursorAssetDir = Path.Combine(webDir, "assets", "cursor", "native");
            if (config.UseDesktopCursorOverlay)
            {
                cursorOverlay = new DesktopCursorOverlay(form, cursorAssetDir);
                LogManager.Log("[Cursor] native overlay enabled (DesktopCursorOverlay — Phase 1 desktop ULW)");
            }
            else
            {
                cursorOverlay = new CursorOverlayForm(form, form.FlashHostPanel, cursorAssetDir);
                LogManager.Log("[Cursor] native overlay enabled (CursorOverlayForm — legacy OverlayBase)");
            }
        }
        else
        {
            LogManager.Log("[Cursor] native overlay disabled by config; using system cursor for A/B diagnostics");
        }

        // Notch 依赖 + InputShieldForm
        InputShieldForm inputShield = null;
        // UiData handlers are wired before TaskRegistry construction. Capture this holder so
        // both native and fallback paths can feed the eventual AgentControlTask without a
        // second raw payload split.
        AgentControlTask agentControlTask = null;
        CF7Launcher.Guardian.Hud.SafeExitPanelWidget safeExitPanel = null;
        {
            webOverlay.SetNotchDependencies(frameTask.FpsBuffer,
                new Action(form.ToggleFullscreen),
                new Action(form.ToggleLog),
                delegate
                {
                    form.EmergencyExit(
                        GuardianForm.EmergencyExitReason.HardExitKeyQ);
                },
                new Action<Keys>(form.HandleButtonClick));

            // GDI+ fallback：WebView2 初始化失败或未就绪时走这里。
            // useNativeHud=true 时 toastOverlay/notchOverlay 都为 null；下面 if (UseNativeHud) 分支会用 nativeHud
            // 同时充当 IToastSink + INotchSink 覆盖（NotchWidget/ToastWidget 接管渲染）。
            webOverlay.SetFallback(toastOverlay, notchOverlay);

            // 光照等级数据（与 NotchOverlay 共用同一默认值）
            webOverlay.SetLightLevels(new int[] {
                0, 0, 1, 4, 7, 7, 7, 7, 7, 7, 7, 7, 9, 7, 7, 7, 7, 7, 7, 4, 1, 0, 0, 0
            });

            // 游戏命令通道（pause 等）
            webOverlay.SetSocketServer(socketServer);

            // 开发环境检测：非 git 仓库时隐藏"其他"菜单中的开发工具
            webOverlay.SetDevMode(SteamOwnershipCheck.IsDevRepository(projectRoot));

            // 音乐目录注入
            webOverlay.SetMusicCatalog(musicCatalog);

            // U 前缀快车道：UI 数据透传到 WebView2，并把同一解析包交给 agent 实收门。
            Action<string> fallbackUiDataTee = delegate(string raw)
            {
                if (string.IsNullOrEmpty(raw)) return;
                CF7Launcher.Guardian.Hud.UiDataPacket pkt =
                    new CF7Launcher.Guardian.Hud.UiDataPacket(raw);
                try { webOverlay.HandleUiData(pkt); }
                catch (Exception ex) { LogManager.Log("[Tee] web UiData throw: " + ex.Message); }
                try
                {
                    if (safeExitPanel != null)
                        safeExitPanel.HandleUiData(pkt);
                }
                catch (Exception ex)
                {
                    LogManager.Log("[Tee] safe-exit UiData throw: " + ex.Message);
                }
                try { if (agentControlTask != null) agentControlTask.ObserveUiData(pkt); }
                catch (Exception ex) { LogManager.Log("[Tee] agent UiData throw: " + ex.Message); }
            };
            socketServer.SetUiDataHandler(fallbackUiDataTee);

            // combo hints → WebView2 (FrameTask 每帧推送)
            frameTask.SetUiDataHandler(fallbackUiDataTee);

            // 幽灵输入层：GDI+ 命中测试 + CDP 注入
            inputShield = new InputShieldForm(form, form.FlashHostPanel);
            webOverlay.SetInputShield(inputShield);
            webOverlay.SetCursorOverlay(cursorOverlay);
        }

        // === LauncherCommandRouter 装配（始终装配，Flag OFF 时也用，避免 HandleButtonClick 走两套路径）===
        // Router 是按钮命令的唯一中枢；Flag OFF 时 OpenPanel 走旧 PostToWeb panel_cmd open 兜底。
        LauncherCommandRouter commandRouter = new LauncherCommandRouter(
            socketServer,
            new Action<Keys>(form.HandleButtonClick),
            new Action(form.ToggleFullscreen),
            new Action(form.ToggleLog),
            new Action(form.ForceExit),
            new Action<string>(webOverlay.PostToWeb),
            new Action<bool>(form.HandlePanelStateChanged),
            new Action<string>(webOverlay.SetActivePanel));
        commandRouter.SetFallbackVisualRetire(delegate(string reason)
        {
            webOverlay.ForceIdleState(reason);
            return true;
        });
        commandRouter.SetPanelAdmissionGate(
            delegate
            {
                return !form.IsShutdownAdmissionClosed;
            });
        webOverlay.SetCommandRouter(commandRouter);
        if (notchOverlay != null) notchOverlay.SetCommandRouter(commandRouter);

        // === Phase 2: Native HUD + PanelHostController 完整装配（config.useNativeHud）===
        // Flag OFF：跳过 NativeHud/Backdrop/PanelHost；router 走 PostToWeb 旧路径
        // Flag ON：完整装配；所有 panel 打开走 PanelHost.OpenPanel → snapshot/backdrop/EX_STYLE/HUD-suspend 序列
        NativeHudOverlay nativeHud = null;
        NativePanelBackdrop backdrop = null;
        PanelHostController panelHost = null;
        if (config.UseNativeHud)
        {
            // Phase 3: 通知 WebOverlay 进入 NativeHud 模式：
            //   - SetReady 时不调 SuspendFallback，让 NotchOverlay/ToastOverlay 一直作为常驻 HUD
            //   - 注入 CSS 隐藏 web 端 #notch / #toast-container 避免双重 UI
            //   - notch/toast 消息走 fallback (NotchOverlay/ToastOverlay) 而不是 web ExecScript
            webOverlay.SetUseNativeHud(true);
            nativeHud = new NativeHudOverlay(form, form.FlashHostPanel);
            backdrop = new NativePanelBackdrop(form);
            // flashHwndProvider 在 WebOverlay 构造前已声明（snapshot 路径用），此处复用给 PanelHostController；
            // WebOverlay 自身的焦点回推不走 provider 而走 flashFocusRestorer 统一 primitive。
            // Phase 3: 注入 NotchOverlay/ToastOverlay，让 PanelHost 在 panel open/close 时显式 Suspend/Resume
            panelHost = new PanelHostController(form, webOverlay, nativeHud, backdrop,
                inputShield, hnOverlay, cursorOverlay, form.GetPanelEscapeSource(), flashHwndProvider,
                notchOverlay, toastOverlay);
            webOverlay.SetPanelHost(panelHost);
            commandRouter.SetPanelHost(panelHost);

            // Phase 5.7: 注册常驻 widget。右侧 HUD 收敛为 RightContextWidget：
            //   TopRightTools + context panel(map/装备/任务/notice) + Jukebox titlebar 共用一套 Web 常量布局。
            //   Currency / NotchToolbar / TopRightTools / MapHud / QuestNotice / JukeboxTitlebar 旧独立 widget 保留但默认不注册。
            // Phase 4 收尾：DoFullIdleSuspend 启用 → 进入 ~15pp DWM α 地板回收阶段。
            // 无 widget 时 NativeHud SW_HIDE，不影响 Phase 3 行为。
            // P2-2 perf：catalog 异步加载（162 KB JSON 反序列化挪到后台）。
            // 加载完成前 GetEntry 返回 null，widget 静默不渲染地图，无错位；
            // ~30-80ms 的 JSON parse 全藏在 Flash 启动等待里。
            string mapHudJsonPath = Path.Combine(projectRoot, "launcher", "data", "map_hud_data.json");
            CF7Launcher.Guardian.Hud.MapHudDataCatalog mapCatalog =
                CF7Launcher.Guardian.Hud.MapHudDataCatalog.LoadFromFileAsync(mapHudJsonPath);
            CF7Launcher.Guardian.Hud.RightContextWidget rightContext =
                new CF7Launcher.Guardian.Hud.RightContextWidget(
                    form.FlashHostPanel,
                    commandRouter,
                    mapCatalog,
                    CF7Launcher.Guardian.Hud.MapDisplayPolicy.ParsePreference(userPrefs.MapDisplayPreference),
                    delegate(CF7Launcher.Guardian.Hud.MapDisplayPreference preference)
                    {
                        userPrefs.MapDisplayPreference =
                            CF7Launcher.Guardian.Hud.MapDisplayPolicy.ToPersistedValue(preference);
                        if (!userPrefs.Save())
                            LogManager.Log("[NativeHud] mapDisplayPreference save failed; keeping process-local value="
                                + userPrefs.MapDisplayPreference);
                        nativeHud.AddMessage("地图显示："
                            + CF7Launcher.Guardian.Hud.MapDisplayPolicy.ToDisplayLabel(preference));
                    });
            nativeHud.AddWidget(rightContext);
            safeExitPanel =
                new CF7Launcher.Guardian.Hud.SafeExitPanelWidget(form.FlashHostPanel, commandRouter);
            // 地图不再常驻预留 header；仅 SafeExit 真正可见时通知 RightContext 留出状态槽，
            // 避免确认条覆盖地图顶部，同时保持普通地图紧贴动作行。
            safeExitPanel.BoundsOrVisibilityChanged += delegate
            {
                rightContext.SetExternalStatusSlotActive(safeExitPanel.Visible);
            };
            nativeHud.AddWidget(safeExitPanel);
            CF7Launcher.Guardian.Hud.ComboWidget comboWidget =
                new CF7Launcher.Guardian.Hud.ComboWidget(form.FlashHostPanel);
            nativeHud.AddWidget(comboWidget);
            // ToastWidget 顶替原 ToastOverlay 全屏 ULW。NativeHudOverlay.AddWidget 自动捕获引用，
            // IToastSink.AddMessage / SetReady 会 fan-out 到此 widget。
            CF7Launcher.Guardian.Hud.ToastWidget toastWidget =
                new CF7Launcher.Guardian.Hud.ToastWidget(form.FlashHostPanel);
            nativeHud.AddWidget(toastWidget);
            // NotchWidget 顶替原 NotchOverlay 独立 ULW（FPS 药丸 + 工具栏 + 通知栈 + 展开图表）。
            // AudioHudState 在此成为 native HUD 唯一的 BGM 峰值历史；低频包络绘于 FPS 折线背景。
            // INotchSink.AddNotice/SetStatusItem/ClearStatusItem 路由到此 widget。
            CF7Launcher.Guardian.Hud.AudioHudState audioHudState =
                new CF7Launcher.Guardian.Hud.AudioHudState();
            CF7Launcher.Guardian.Hud.NotchWidget notchWidget =
                new CF7Launcher.Guardian.Hud.NotchWidget(
                    form.FlashHostPanel, frameTask.FpsBuffer, projectRoot,
                    new Action(form.ToggleFullscreen),
                    new Action(form.ToggleLog),
                    delegate
                    {
                        form.EmergencyExit(
                            GuardianForm.EmergencyExitReason.HardExitKeyQ);
                    },
                    new Action<Keys>(form.HandleButtonClick),
                    audioHudState);
            notchWidget.SetCommandRouter(commandRouter);
            nativeHud.AddWidget(notchWidget);
            // 升级 webOverlay 的 toast/notch fallback：先前以 toastOverlay=null/notchOverlay=null 注入，
            // nativeHud 就绪后接管 IToastSink + INotchSink。webOverlay.AddMessage/AddNotice 在
            // _useNativeHud=true 时直接转发 _toastFallback / _notchFallback，无需 ExecScript。
            webOverlay.SetFallback(nativeHud, nativeHud);
            // 刘海 MAPHUD_TOGGLE 只管显示/关闭；卡片尺寸按钮在 compact/expanded 间往返。
            // 两者都只写用户显示偏好；AS2 mm runtimeMapMode 保持只读并继续承担玩法门控。
            commandRouter.OnMapHudToggle = delegate { rightContext.ToggleMapVisibility(); };
            // z-order 锚点：把 NativeHud 沉到 HitNumber 之下（Cursor 在 HitNumber 之上 → 自动也在 NativeHud 之上）
            // 这样 widget 区域不会遮挡伤害数字与鼠标。
            if (hnOverlay != null) nativeHud.SetZOrderInsertAfter(hnOverlay.Handle);

            // P1 perf：tee 路径单次 parse 后分发给 3 消费者。
            // 旧版每条 raw 被三方各自 Split('|')；高频 socket / FrameTask 流下 ~3x 字符串数组分配。
            // 共享 UiDataPacket 后只 split 一次。
            WebOverlayForm capturedWeb = webOverlay;
            NotchOverlay capturedNotch = notchOverlay; // useNativeHud=true 时为 null，下面 try 中守护
            NativeHudOverlay capturedHud2 = nativeHud;
            Action<string> uiDataTee = delegate(string raw)
            {
                if (string.IsNullOrEmpty(raw)) return;
                CF7Launcher.Guardian.Hud.UiDataPacket pkt = new CF7Launcher.Guardian.Hud.UiDataPacket(raw);
                try { capturedWeb.HandleUiData(pkt); }
                catch (Exception ex) { LogManager.Log("[Tee] web UiData throw: " + ex.Message); }
                try { if (capturedNotch != null) capturedNotch.HandleUiData(pkt); }
                catch (Exception ex) { LogManager.Log("[Tee] notch UiData throw: " + ex.Message); }
                try { capturedHud2.HandleUiData(pkt); }
                catch (Exception ex) { LogManager.Log("[Tee] hud UiData throw: " + ex.Message); }
                try { if (agentControlTask != null) agentControlTask.ObserveUiData(pkt); }
                catch (Exception ex) { LogManager.Log("[Tee] agent UiData throw: " + ex.Message); }
            };
            socketServer.SetUiDataHandler(uiDataTee);
            frameTask.SetUiDataHandler(uiDataTee);

            // P2-1 perf：后台预热 GDI+ 字体 / 字形栅格化；地图 WebP 在 mh 到达后按当前工作集预热。
            // 与 SFX preload / catalog async 并行，全部藏在 Flash 启动等待窗口（~4-5s）。
            // 玩家首次看到 native UI 时所有冷启动开销已被吸收。
            CF7Launcher.Guardian.Hud.NativeHudPrewarm.RunAsync(mapCatalog);

            // P2-3 perf：ULW 首帧预提交（1×1 透明）。让 DWM 把 NativeHud / HitNumber / Cursor
            // 加入合成树 + per-pixel α 路径建立；玩家可见的第一次 commit 不再触发"新 layered window 合成"冷路径。
            try { nativeHud.PreCommitTransparent(); } catch (Exception ex) { LogManager.Log("[NativeHud] PreCommit failed: " + ex.Message); }
            try { if (hnOverlay != null) hnOverlay.PreCommitTransparent(); } catch (Exception ex) { LogManager.Log("[HitNumber] PreCommit failed: " + ex.Message); }
            try { if (cursorOverlay != null) cursorOverlay.PreCommitTransparent(); } catch (Exception ex) { LogManager.Log("[Cursor] PreCommit failed: " + ex.Message); }

            LogManager.Log("[NativeHud] enabled (Phase 5.7: native notch + right context parity)");
            PerfTrace.Mark("native_hud.enabled");
        }
        else
        {
            // Web HUD rollback still uses the same Host-owned one-shot authority. It is not
            // rendered by NativeHud, but the fallback UiData tee above feeds s/sv deltas so
            // EXIT_CONFIRM remains exact instead of becoming a raw Bridge capability.
            safeExitPanel =
                new CF7Launcher.Guardian.Hud.SafeExitPanelWidget(
                    form.FlashHostPanel,
                    commandRouter);
            LogManager.Log("[NativeHud] disabled (config useNativeHud=false; router goes through PostToWeb fallback)");
            PerfTrace.Mark("native_hud.disabled");
        }
        // 必须在 authority 实例化后注入：router SAFEEXIT click → Arm → Saving；
        // sv:2 才赋予一次 EXIT_CONFIRM，send false/throw 则立即进入 Failed。
        commandRouter.OnSafeExitArm =
            delegate { safeExitPanel.Arm(); };
        commandRouter.OnSafeExitSendFailed =
            delegate { safeExitPanel.FailAttempt(); };
        commandRouter.TryConsumeSafeExitConfirm =
            delegate { return safeExitPanel.TryAuthorizeExitConfirm(); };

        // Phase 1 (11c): WebView2 硬依赖 — webOverlay 必有, 直接用
        IToastSink toastSink = webOverlay;
        // useNativeHud=true：notchSink 直接是 nativeHud。NotchWidget 注册后处理所有 category 的
        // AddNotice/SetStatusItem/ClearStatusItem，无需再复合 webOverlay：
        //   - WebOverlayForm.AddNotice/SetStatusItem/ClearStatusItem 在 _useNativeHud=true 时本就 forward
        //     给 _notchFallback（A.2 起 = nativeHud），把 webOverlay 留在 CompositeNotchSink 里会让
        //     SetStatusItem/ClearStatusItem 通过 nativeHud→webOverlay→nativeHud 派发两次，徒增
        //     UI 线程 BeginInvoke + NotchWidget upsert/repaint 压力（id 去重避免视觉双显但不省 CPU）。
        //   - AddNotice 由 NotchWidget 通用兜底接管 + INotchNoticeConsumer 精确订阅，duplicate 已被
        //     NativeHudOverlay.HasNoticeConsumerFor 收口；CompositeNotchSink 的 webOverlay 路径在 A.2 后
        //     是死路径（AcceptCategory 永远 false）。
        // useNativeHud=false：保留旧路径，notchSink = webOverlay（ExecScript / GDI+ NotchOverlay 兜底）。
        INotchSink notchSink = config.UseNativeHud && nativeHud != null
            ? (INotchSink)nativeHud
            : webOverlay;
        ToastTask toastTask = new ToastTask(toastSink);
        // 音量 sanity toast（迁移期临时兜底）：master_vol==0 / bgm_vol<0.02 时进程级首次提示。
        // 设置入口在 Flash 侧迁移完成前，存档编辑器简易模式系统卡片为唯一恢复路径。
        CF7Launcher.Tasks.AudioTask.SetToastSink(toastSink);

        // 快车道注入：F/R 前缀消息由 XmlSocketServer 直接分发到 FrameTask，绕过 MessageRouter
        socketServer.SetFrameHandler(frameTask);
        // N/W 前缀快车道：通知 + 波次计时器 → Notch sink
        socketServer.SetNotchHandler(notchSink);

        // Task 注册（TaskRegistry = single source of truth）
        GomokuTask gomokuTask;
        using (PerfTrace.Scope("task.gomoku_init"))
        {
            gomokuTask = new GomokuTask(projectRoot);
        }
        DataCache dataCache;
        using (PerfTrace.Scope("data.cache_init"))
        {
            dataCache = new DataCache(projectRoot);
        }
        DataQueryTask dataQueryTask = new DataQueryTask(dataCache);
        CF7Launcher.Tasks.AudioTask audioTask = new CF7Launcher.Tasks.AudioTask();
        IconBakeTask iconBakeTask;
        using (PerfTrace.Scope("task.icon_bake_init"))
        {
            iconBakeTask = new IconBakeTask(projectRoot, notchSink);
        }
        ShopTask shopTask = new ShopTask(socketServer);
        InventoryTask inventoryTask = new InventoryTask(socketServer);
        LootPanelCoordinator lootPanelCoordinator = new LootPanelCoordinator(
            new LootPanelHostPort(panelHost),
            delegate { return webOverlay.ReleaseLootPanelPause(); },
            null,
            delegate(LootPanelCoordinator.Binding binding, string reason)
            {
                return webOverlay.TryRequestLootPanelRecovery(binding, reason);
            });
        LootTask lootTask = new LootTask(socketServer, lootPanelCoordinator);
        lootPanelCoordinator.SetAdmissionLeaseFactory(
            lootTask.TryAcquirePanelAdmissionLease);
        if (panelHost != null)
            panelHost.PanelClosed += lootPanelCoordinator.OnPanelHostClosed;
        NpcShopTask npcShopTask = new NpcShopTask(socketServer);
        CraftingTask craftingTask = new CraftingTask(socketServer);
        HairdresserTask hairdresserTask = new HairdresserTask(socketServer);
        EquipmentTuningTask equipmentTuningTask = new EquipmentTuningTask(socketServer);
        commandRouter.SetEquipmentTuningTask(equipmentTuningTask);
        CharacterBuildTask characterBuildTask = new CharacterBuildTask(socketServer);
        characterBuildTask.SetAdmissionGate(
            delegate
            {
                return !form.IsShutdownAdmissionClosed;
            });
        commandRouter.SetCharacterBuildTask(characterBuildTask);
        lootPanelCoordinator.SetExternalAdmissionGate(
            delegate
            {
                return !form.IsShutdownAdmissionClosed
                    && !characterBuildTask.HasBoundPanel;
            });
        SkillTask skillTask = new SkillTask(socketServer);
        commandRouter.SetSkillTask(skillTask);
        if (panelHost != null)
        {
            panelHost.SetOpenGate(delegate(string panelName)
            {
                // CharacterBuild owns the shared pause authority until acknowledged recovery
                // consumes its exact binding. This gate also covers PanelHost's internal returnTo
                // reopen path, which never passes through LauncherCommandRouter.
                  return !form.IsShutdownAdmissionClosed
                      && !characterBuildTask.HasBoundPanel;
            });
            panelHost.SetRebindGate(delegate(string panelName)
            {
                if (panelName == "skills") return skillTask.CanRebind;
                if (panelName == "workbench")
                {
                    if (equipmentTuningTask.HasBoundPanel
                        && !equipmentTuningTask.CanRebind) return false;
                }
                return true;
            });
            panelHost.SetInitDataEnricher(delegate(string panelName, string initDataJson)
            {
                return panelName == "skills" ? skillTask.EnrichPanelInitData(initDataJson) : initDataJson;
            });
            panelHost.SetPanelCloseObserver(delegate(string panelName, string panelInstanceId)
            {
                if (panelName == "skills") skillTask.HandleAuthoritativePanelClosed(panelInstanceId);
                if (panelName == "workbench" && equipmentTuningTask.HasBoundPanel)
                    equipmentTuningTask.HandlePanelClosed(panelInstanceId);
                if (panelName == "hairdresser") hairdresserTask.ClearPending();
            });
            panelHost.PanelClosed += delegate(
                string panelName,
                string panelInstanceId)
            {
                // Safety net for Host-owned closes that did not originate in WebOverlay/Router.
                // PanelClosed fires only after native/Web visual teardown; it may arm and continue
                // recovery here without releasing pause behind a visible replacement.
                if (panelName != "workbench"
                    || !characterBuildTask.HasBoundPanel
                    || characterBuildTask.RequiresDetachRecovery)
                {
                    return;
                }
                string boundInstance =
                    characterBuildTask.PanelInstanceId;
                if (characterBuildTask
                        .BeginNormalCloseBarrier(
                            boundInstance))
                {
                    characterBuildTask
                        .ContinueDetachRecoveryAfterVisualRetired(
                            0);
                }
            };
        }
        skillTask.SetCoordinatorSettled(delegate
        {
            if (panelHost != null) panelHost.FlushDeferredRebind("skills");
            commandRouter.FlushDeferredFallbackSkillRebind();
        });
        equipmentTuningTask.SetCoordinatorSettled(delegate
        {
            if (panelHost != null) panelHost.FlushDeferredRebind("workbench");
        });
        characterBuildTask.SetCoordinatorSettled(delegate
        {
            bool skillsNavigationConsumed =
                commandRouter
                    .TryCompleteCharacterBuildSkillsNavigation();
            if (panelHost != null)
            {
                if (!skillsNavigationConsumed)
                {
                    panelHost.FlushDeferredBarrierOpen();
                    panelHost.FlushDeferredRebind("workbench");
                }
            }
        });
        MapTask mapTask = new MapTask(socketServer);
        StageSelectTask stageSelectTask = new StageSelectTask(socketServer);
        ArenaTask arenaTask = new ArenaTask(socketServer);
        ArenaCalibrationTask arenaCalibrationTask = new ArenaCalibrationTask(socketServer, projectRoot);
        arenaTask.SetCalibrationTask(arenaCalibrationTask);
        agentControlTask = new AgentControlTask(
            delegate { return socketServer.HasClient; },
            delegate
            {
                return Newtonsoft.Json.Linq.JObject.Parse(arenaCalibrationTask.HandleControl(
                    new Newtonsoft.Json.Linq.JObject { ["action"] = "status" }));
            },
            delegate(string slot)
            {
                if (userPrefs != null && userPrefs.LastPlayedSlot != slot)
                {
                    userPrefs.LastPlayedSlot = slot;
                    userPrefs.Save();
                }
            });
        agentControlTask.SetEquipmentTuningOpenAction(delegate
        {
            const string payload = "{\"task\":\"cmd\",\"action\":\"openInventoryWorkbench\","
                + "\"profile\":\"battlebox\",\"view\":\"tuning\",\"source\":\"agent_control\"}\0";
            return socketServer != null && socketServer.IsClientReady && socketServer.TrySend(payload);
        });
        agentControlTask.SetCharacterBuildOpenAction(delegate
        {
            const string payload = "{\"task\":\"cmd\",\"action\":\"openInventoryWorkbench\","
                + "\"profile\":\"battlebox\",\"view\":\"build\",\"source\":\"agent_control\"}\0";
            return !form.IsShutdownAdmissionClosed
                && socketServer != null && socketServer.IsClientReady
                && socketServer.TrySend(payload);
        });
        agentControlTask.SetActivePanelStatusProvider(delegate
        {
            string name = panelHost != null ? panelHost.ActivePanelName : commandRouter.ActiveFallbackPanelName;
            string instanceId = panelHost != null ? panelHost.ActivePanelInstanceId : commandRouter.ActiveFallbackPanelInstanceId;
            return new Newtonsoft.Json.Linq.JObject
            {
                ["name"] = name == null ? Newtonsoft.Json.Linq.JValue.CreateNull() : (Newtonsoft.Json.Linq.JToken)name,
                ["instanceId"] = instanceId == null ? Newtonsoft.Json.Linq.JValue.CreateNull() : (Newtonsoft.Json.Linq.JToken)instanceId
            };
        });
        PetTask petTask = new PetTask(socketServer, projectRoot);
        MercTask mercTask = new MercTask(socketServer);
        TaskTask taskTask = new TaskTask(socketServer);
        IntelligenceTask intelligenceTask = new IntelligenceTask(projectRoot, socketServer);
        ArchiveTask archiveTask;
        using (PerfTrace.Scope("task.archive_init"))
        {
            archiveTask = new ArchiveTask(projectRoot);
        }

        // INV-2: 旧版反污染 gate. 检测玩家是否曾在 launcher 修复版之前用过本机.
        // 命中提示后立刻写回 marker, 让二次启动沉默. 不阻塞启动 (gate 失败仅丢日志).
        CF7Launcher.Save.LauncherVersionGate.GateResult versionGate = null;
        try
        {
            versionGate = CF7Launcher.Save.LauncherVersionGate.Check(archiveTask.SavesDir);
            CF7Launcher.Save.LauncherVersionGate.WriteMarker(archiveTask.SavesDir);
            if (versionGate.ShouldShowToast)
            {
                LogManager.Log("[VersionGate] WARN reason=" + versionGate.Reason
                    + " prev=" + versionGate.PreviousVersion
                    + " current=" + CF7Launcher.Save.LauncherVersionGate.CurrentSchemaVersion
                    + " — 若曾用过老版本 launcher, 建议跑 tools/cf7-save-repair 检查存档");
            }
            else
            {
                LogManager.Log("[VersionGate] OK reason=" + versionGate.Reason);
            }
        }
        catch (Exception ex)
        {
            LogManager.Log("[VersionGate] check/write failed: " + ex.Message);
        }

        // C2-α: 启动期 silent 自动修复. 扫描 saves/{slot}.json，对高置信度命中
        // (self_ref / dict_unique) 自动应用 fix_value/rename_key/clear/drop，备份
        // 原档到 .repair-backups/，bump lastSaved（INV-1）。
        // L0 / L1 多候选 / L1 装备槽位 key / L1 0 候选不动，留给 C2-β 卡片。
        // 失败不阻塞启动。
        try
        {
            using (PerfTrace.Scope("save.auto_repair"))
            {
                CF7Launcher.Save.SaveAutoRepairService.RunAll(projectRoot, archiveTask);
            }
        }
        catch (Exception ex)
        {
            LogManager.Log("[AutoRepair] top-level exception: " + ex.Message);
        }

        BenchTask benchTask = new BenchTask(socketServer);

        // 字体包：按需下载到 %LOCALAPPDATA%/CF7FlashNight/fonts/，WebOverlay 把该目录映射为 cfn-fonts.local
        FontPackTask fontPackTask;
        using (PerfTrace.Scope("task.font_pack_init"))
        {
            fontPackTask = new FontPackTask(projectRoot, notchSink, toastSink);
        }
        webOverlay.SetFontsDir(fontPackTask.AppDataFontsDir,
            Path.Combine(projectRoot, "launcher", "web", "assets", "fonts"));

        using (PerfTrace.Scope("task.registry_register_all"))
        {
            TaskRegistry.RegisterAll(router, gomokuTask, toastTask, frameTask, dataQueryTask, v8Runtime, hnOverlay, audioTask, iconBakeTask, shopTask, inventoryTask, lootTask, lootPanelCoordinator, npcShopTask, craftingTask, hairdresserTask, equipmentTuningTask, characterBuildTask, skillTask, mapTask, stageSelectTask, arenaTask, arenaCalibrationTask, agentControlTask, petTask, mercTask, taskTask, intelligenceTask, archiveTask, benchTask, fontPackTask, webOverlay);
        }
        StartupDiagnostics.Mark("task.registry_register_all_ok");

        // 注入 router 到 webOverlay：开启 Web→C# 通用 task 桥（FontPack 安装条幅等使用）
        webOverlay.SetTaskRouter(router);

        // 面板系统接线 (11c: webOverlay 必有)
        webOverlay.SetShopTask(shopTask);
        webOverlay.SetInventoryTask(inventoryTask);
        webOverlay.SetLootTask(lootTask);
        webOverlay.SetLootPanelCoordinator(lootPanelCoordinator);
        webOverlay.SetNpcShopTask(npcShopTask);
        webOverlay.SetCraftingTask(craftingTask);
        webOverlay.SetHairdresserTask(hairdresserTask);
        webOverlay.SetEquipmentTuningTask(equipmentTuningTask);
        webOverlay.SetCharacterBuildTask(characterBuildTask);
        webOverlay.SetSkillTask(skillTask);
        webOverlay.SetGomokuTask(gomokuTask);
        webOverlay.SetMapTask(mapTask);
        webOverlay.SetStageSelectTask(stageSelectTask);
        webOverlay.SetArenaTask(arenaTask);
        webOverlay.SetPetTask(petTask);
        webOverlay.SetMercTask(mercTask);
        webOverlay.SetTaskTask(taskTask);
        webOverlay.SetIntelligenceTask(intelligenceTask);
        webOverlay.SetPanelStateCallback(form.HandlePanelStateChanged);
        form.SetWebOverlay(webOverlay);
        socketServer.OnClientDisconnectedForGeneration += webOverlay.OnSocketDisconnected;
        socketServer.OnClientReadyForGeneration += webOverlay.OnSocketReconnected;

        // 注入 router 到 HttpApiServer（供 /task 端点使用）
        httpServer.SetRouter(router);

        // 注入 shutdown 回调
        httpServer.SetShutdownAction(delegate { form.ForceExit(); });
        agentControlTask.SetShutdownAction(delegate { form.ForceExit(); });

        // CharacterBuild may own dirty live/loadout state even when Web has stopped responding.
        // Controlled exit must obtain the existing exact recoverDetach persistence proof before
        // any overlay suspension, task disposal, socket teardown, or Flash termination begins.
        form.OnShutdownFence = delegate
        {
            string outcome;
            bool passed =
                characterBuildTask
                    .TryCompleteHostShutdownPersistence(
                        3000,
                        out outcome);
            if (!passed)
            {
                LogManager.Log(
                    "[Guardian] CharacterBuild shutdown persistence blocked outcome="
                    + (outcome ?? "unknown"));
                try
                {
                    if (toastSink != null)
                    {
                        toastSink.AddMessage(
                            "角色配装尚未安全保存，已取消退出；请稍后重试，或按 Ctrl+Q 放弃未保存改动并强制退出");
                    }
                }
                catch { }
            }
            return passed;
        };

        // 退出前回调：在 Form dispose 之前断开快车道，防退出竞态
        form.OnShutdownEarly = delegate
        {
            // 顺序敏感: 这两步必须最前。
            // 1) 卸全局低级鼠标 hook —— UI 线程接下来要被 KillFlash WaitForExit 阻塞数秒,
            //    hook 还挂着的话全系统鼠标消息都要排队走它的回调, 光标视觉延迟显著。
            // 2) WebOverlay panel→idle —— SW_HIDE + 恢复 EX_TRANSPARENT + 停 web timer + TrySuspendAsync,
            //    后面的 _webView.Dispose() 才不会卡住 200-800ms 销毁 Chromium。
            try { if (inputShield != null) inputShield.ExitTelemetryMode(); } catch (Exception ex) { LogManager.Log("[Guardian] ExitTelemetryMode early failed: " + ex.Message); }
            try { if (webOverlay != null) webOverlay.SuspendAfterPanel("shutdown"); } catch (Exception ex) { LogManager.Log("[Guardian] SuspendAfterPanel early failed: " + ex.Message); }
            try { lootTask.OnTransportDetached(); lootPanelCoordinator.ForceDetach("host_shutdown"); } catch (Exception ex) { LogManager.Log("[Guardian] loot detach early failed: " + ex.GetType().Name); }
            try { lootPanelCoordinator.Dispose(); } catch { }

            // 所有 overlay form 立即 Hide: 退出过程中后续的 KillFlash WaitForExit / Dispose 阶段,
            // WebView2 子窗口、α-shield、HUD widget 任何一帧背景闪现都不再可见。
            // 这是白闪兜底——SuspendAfterPanel 只在 _panelMode=true 时切 idle, 但用户可能在 panel 已关后才点退出,
            // 那种路径下 webOverlay 仍在 idle 透明态, dispose 中间帧仍可能露默认背景。
            HideOverlayForm(webOverlay);
            HideOverlayForm(inputShield);
            HideOverlayForm(nativeHud);
            HideOverlayForm(notchOverlay);
            HideOverlayForm(hnOverlay);
            HideOverlayForm(toastOverlay);
            HideOverlayForm(backdrop);

            musicCatalog.Dispose();
            frameTask.Stop();
            shopTask.Dispose();
            lootTask.Dispose();
            npcShopTask.Dispose();
            craftingTask.Dispose();
            hairdresserTask.Dispose();
            equipmentTuningTask.Dispose();
            characterBuildTask.Dispose();
            mapTask.Dispose();
            stageSelectTask.Dispose();
            intelligenceTask.Dispose();
            socketServer.SetFrameHandler(null);
            socketServer.SetNotchHandler(null);
        };

        // 写端口文件（CLI 和 AS2 可直接读取，无需盲扫）
        string portsFile = Path.Combine(projectRoot, "launcher_ports.json");
        string portsJson = "{\"httpPort\":" + httpPort
            + ",\"socketPort\":" + socketPort
            + ",\"pid\":" + Process.GetCurrentProcess().Id + "}";
        try
        {
            File.WriteAllText(portsFile, portsJson);
            LogManager.Log("[Guardian] Wrote " + portsFile);
            StartupDiagnostics.Mark("ports.write_ok", portsJson);
        }
        catch (Exception ex)
        {
            LogManager.Log("[Guardian] Failed to write ports file: " + ex.Message);
            StartupDiagnostics.Warn("ports.write_failed", ex.Message);
        }

        LogManager.Log("[Guardian] Bus ready: HTTP=" + httpPort + " Socket=" + socketPort);
        StartupDiagnostics.Mark("bus.ready", "http=" + httpPort + " socket=" + socketPort);

        if (busOnly)
        {
            // === bus-only 模式：仅运行通信总线，不启动 Flash Player ===
            // Flash Player 由外部（如 Flash CS6 testMovie）自行启动并连接
            LogManager.Log("[Guardian] Bus-only mode active. Waiting for external Flash connection...");
            StartupDiagnostics.Mark("bus_only.ready");
            form.Text = isolatedRuntimeCandidate
                ? "CF7:ME Bus (test mode) — 隔离候选 / 未部署"
                : "CF7:ME Bus (test mode)";

            // 消息循环（保持进程存活）
            Application.Run(form);

            // 清理：每步 try-catch 保护，防止单点异常跳过后续步骤
            LogManager.Log("[Guardian] Bus-only shutting down...");
            StartupDiagnostics.Mark("bus_only.shutdown_start");
            try { DiagnosticsBootstrap.Shutdown(); } catch { }
            try { frameTask.Stop(); } catch { }
            try { socketServer.SetFrameHandler(null); } catch { }
            try { socketServer.SetNotchHandler(null); } catch { }
            try { gomokuTask.Dispose(); } catch { }
            try { shopTask.Dispose(); } catch { }
            try { lootTask.Dispose(); } catch { }
            try { npcShopTask.Dispose(); } catch { }
            try { craftingTask.Dispose(); } catch { }
            try { hairdresserTask.Dispose(); } catch { }
            try { lootPanelCoordinator.Dispose(); } catch { }
            try { equipmentTuningTask.Dispose(); } catch { }
            try { characterBuildTask.Dispose(); } catch { }
            try { skillTask.Dispose(); } catch { }
            try { mapTask.Dispose(); } catch { }
            try { stageSelectTask.Dispose(); } catch { }
            try { socketServer.Dispose(); } catch { }
            try { httpServer.Dispose(); } catch { }
            try { if (panelHost != null) panelHost.Dispose(); } catch { }
            try { if (inputShield != null) inputShield.Dispose(); } catch { }
            try { if (webOverlay != null) webOverlay.Dispose(); } catch { }
            try { if (backdrop != null) backdrop.Dispose(); } catch { }
            try { if (nativeHud != null) nativeHud.Dispose(); } catch { }
            try { if (notchOverlay != null) notchOverlay.Dispose(); } catch { }
            try { hnOverlay.Dispose(); } catch { }
            try { v8Runtime.Dispose(); } catch { }
            try { if (toastOverlay != null) toastOverlay.Dispose(); } catch { }
            try { File.Delete(portsFile); } catch { }
            LogManager.Shutdown();
            StartupDiagnostics.Mark("bus_only.shutdown_complete");

            return 0;
        }

        // === 正常模式：启动 Flash Player 并嵌入 ===

        // 快捷键拦截（独立进程）
        string guardExe = Path.Combine(projectRoot, "hotkey_guard.exe");
        Process guardProc = null;
        if (File.Exists(guardExe))
        {
            try
            {
                ProcessStartInfo gsi = new ProcessStartInfo();
                gsi.FileName = guardExe;
                gsi.Arguments = Process.GetCurrentProcess().Id.ToString();
                gsi.UseShellExecute = false;
                gsi.CreateNoWindow = true;
                guardProc = Process.Start(gsi);
                LogManager.Log("[Guardian] HotkeyGuard started, PID=" + guardProc.Id);
                StartupDiagnostics.Mark("hotkey_guard.started", "pid=" + guardProc.Id);
            }
            catch (Exception ex)
            {
                LogManager.Log("[Guardian] HotkeyGuard failed: " + ex.Message);
                StartupDiagnostics.Warn("hotkey_guard.failed", ex.Message);
            }
        }
        else
        {
            LogManager.Log("[Guardian] hotkey_guard.exe not found, shortcuts not blocked");
            StartupDiagnostics.Warn("hotkey_guard.missing", guardExe);
        }

        // 守护进程核心（windowManager 已在 WebOverlay 构造前 early-declared，flashFocusRestorer 依赖它）
        ProcessManager processManager = new ProcessManager(
            config.FlashPlayerPath, config.SwfPath);

        form.BindWindowManager(windowManager);

        // 11b-α: processManager.Start / TrackProcess / TrackFlashProcess 迁入 GameLaunchFlow.TransitionToSpawning
        //   Flash 不立即启动, 由 BootstrapForm 的 start_game 触发 launchFlow.StartGame(slot)

        // 延迟注入应用激活状态到性能决策引擎（bus-only 模式不走此路径）
        perfEngine.SetActivationState(form.ActivationState);

        // 11c: Flash 退出 + zombie 兜底整体迁入 GameLaunchFlow (按 state + attempt 隔离)
        //   Ready 状态 → 触发 form.ForceExit (玩家正常关游戏)
        //   活跃非 Ready 状态 → TransitionToError (允许 retry)
        //   Idle/Error/Resetting → 忽略

        // 退出前杀 Flash + 停音频（在 DoExit 的 ExitThread 之前执行）
        form.OnKillFlash = delegate
        {
            windowManager.DetachFlash();
            CF7Launcher.Audio.AudioEngine.Shutdown();
            processManager.KillFlash();
        };

        // 11b-α: ThreadPool embed + form.Show/Activate + SetReady 整块迁入 GameLaunchFlow.TransitionToEmbedding / TransitionToReady
        //   (readyWiring 关闭注入 toastOverlay/webOverlay/inputShield/hnOverlay.SetReady)

        // ArchiveTask 已在 TaskRegistry.RegisterAll 中注册 (line 401-402)
        // Phase A: BootstrapPanel 已在 GuardianForm ctor 内嵌入，不再单独构造 BootstrapForm

        // Phase C: 存档决议依赖链。SolFileLocator 缓存 hash 子目录 + variant；SolResolver
        // 通过 ArchiveTask 的 sync API 读 tombstone / shadow。SaveResolutionContext 只是 DI 聚合。
        CF7Launcher.Save.SolFileLocator solLocator = new CF7Launcher.Save.SolFileLocator();
        CF7Launcher.Save.SolResolver solResolver = new CF7Launcher.Save.SolResolver(
            solLocator, archiveTask, new CF7Launcher.Save.NativeSolParser(), archiveTask);
        CF7Launcher.Save.SaveResolutionContext saveCtx = new CF7Launcher.Save.SaveResolutionContext(
            solLocator, solResolver, archiveTask, config.SwfPath, projectRoot);

        // 注入诊断打包依赖：HttpApiServer 的 /diagnostic 端点需要 SOL 解析器复制原件
        httpServer.SetDiagnosticDeps(config.SwfPath, solLocator);

        // Phase A 两段式初始化：GuardianForm 已建（line 97），BootstrapPanel 已作为其子控件构造。
        // 此处构造 GameLaunchFlow（依赖 form + form.BootstrapPanel）→ 调 InitializeLaunchFlow 补 wire.
        CF7Launcher.Guardian.GameLaunchFlow launchFlow = new CF7Launcher.Guardian.GameLaunchFlow(
            socketServer, router, processManager, windowManager,
            form, form.BootstrapPanel,
            /* readyWiring */ delegate
            {
                // Phase 1 全局硬依赖 WebView2: webOverlay 永不为 null
                // A.1 (2026-05-24): 每个 SetReady 加 stopwatch, 定位 boot UI 冻最贵段
                long tOverall = System.Diagnostics.Stopwatch.GetTimestamp();
                if (toastOverlay != null)
                {
                    long t = System.Diagnostics.Stopwatch.GetTimestamp();
                    using (CF7Launcher.Guardian.PerfTrace.Scope("reveal.setready.toast"))
                        toastOverlay.SetReady();
                    LogManager.Log("[RevealProbe] setready.toast " + ((System.Diagnostics.Stopwatch.GetTimestamp() - t) * 1000.0 / System.Diagnostics.Stopwatch.Frequency).ToString("0.0") + "ms");
                }
                {
                    long t = System.Diagnostics.Stopwatch.GetTimestamp();
                    using (CF7Launcher.Guardian.PerfTrace.Scope("reveal.setready.web"))
                        webOverlay.SetReady();
                    LogManager.Log("[RevealProbe] setready.web " + ((System.Diagnostics.Stopwatch.GetTimestamp() - t) * 1000.0 / System.Diagnostics.Stopwatch.Frequency).ToString("0.0") + "ms");
                }
                if (inputShield != null)
                {
                    long t = System.Diagnostics.Stopwatch.GetTimestamp();
                    using (CF7Launcher.Guardian.PerfTrace.Scope("reveal.setready.input_shield"))
                        inputShield.SetReady();
                    LogManager.Log("[RevealProbe] setready.input_shield " + ((System.Diagnostics.Stopwatch.GetTimestamp() - t) * 1000.0 / System.Diagnostics.Stopwatch.Frequency).ToString("0.0") + "ms");
                }
                {
                    long t = System.Diagnostics.Stopwatch.GetTimestamp();
                    using (CF7Launcher.Guardian.PerfTrace.Scope("reveal.setready.hitnum"))
                        hnOverlay.SetReady();
                    LogManager.Log("[RevealProbe] setready.hitnum " + ((System.Diagnostics.Stopwatch.GetTimestamp() - t) * 1000.0 / System.Diagnostics.Stopwatch.Frequency).ToString("0.0") + "ms");
                }
                if (nativeHud != null)
                {
                    long t = System.Diagnostics.Stopwatch.GetTimestamp();
                    using (CF7Launcher.Guardian.PerfTrace.Scope("reveal.setready.native_hud"))
                        nativeHud.SetReady();
                    LogManager.Log("[RevealProbe] setready.native_hud " + ((System.Diagnostics.Stopwatch.GetTimestamp() - t) * 1000.0 / System.Diagnostics.Stopwatch.Frequency).ToString("0.0") + "ms");
                }
                // 11b-β: Ready 才让托盘可见
                {
                    long t = System.Diagnostics.Stopwatch.GetTimestamp();
                    using (CF7Launcher.Guardian.PerfTrace.Scope("reveal.show_tray"))
                        form.ShowTrayIcon();
                    LogManager.Log("[RevealProbe] show_tray " + ((System.Diagnostics.Stopwatch.GetTimestamp() - t) * 1000.0 / System.Diagnostics.Stopwatch.Frequency).ToString("0.0") + "ms");
                }
                // 渲染合成层诊断: overlay 全部 ready 后再 dump 一次, 这一份才是稳态 baseline
                DiagnosticsBootstrap.ReadySnapshot();
                LogManager.Log("[RevealProbe] readyWiring.total " + ((System.Diagnostics.Stopwatch.GetTimestamp() - tOverall) * 1000.0 / System.Diagnostics.Stopwatch.Frequency).ToString("0.0") + "ms");
            },
            /* hotkeyGuardSpawn */ null,
            saveCtx);

        // Phase A Step A2: wire launchFlow 到 GuardianForm（OnFormClosing 状态分流 + 热键 state-aware guard）
        form.InitializeLaunchFlow(launchFlow);
        agentControlTask.SetLaunchFlow(launchFlow);

        // Phase D Step D11: silent prewarm 状态不广播给 bootstrap UI,
        // 避免 archive-editor 进只读 / bootstrap.html 闪 running badge / BMH RequireIdle 挡 save.
        // silentAtEmit 在 SetState 锁内快照, 不受 BeginInvoke 排队延迟影响.
        launchFlow.OnStateChanged += delegate(string state, string smsg, bool silentAtEmit)
        {
            StartupDiagnostics.Mark("launch.state", state + " silent=" + silentAtEmit
                + (string.IsNullOrEmpty(smsg) ? "" : " msg=" + smsg));
            if (silentAtEmit) return;   // prewarm 活跃 + _pendingSlot==null 的 teardown 窗口 → 过滤
            Newtonsoft.Json.Linq.JObject obj = new Newtonsoft.Json.Linq.JObject();
            obj["type"] = "bootstrap";
            obj["cmd"] = "state";
            obj["state"] = state;
            obj["msg"] = smsg ?? "";
            if (form.BootstrapPanel != null)
                form.BootstrapPanel.PostToWeb(obj.ToString(Newtonsoft.Json.Formatting.None));
        };
        if (form.BootstrapPanel != null)
        {
            form.BootstrapPanel.OnJsMessage += delegate(string json)
            {
                CF7Launcher.Guardian.BootstrapMessageHandler.Handle(
                    json,
                    form.BootstrapPanel,
                    archiveTask,
                    launchFlow,
                    saveCtx,
                    userPrefs,
                    fontPackTask);
            };
            // FontPackTask 进度推送 → bootstrap fontpack_progress 消息
            CF7Launcher.Guardian.Handlers.FontPackCommandHandler.RegisterProgressSink(
                form.BootstrapPanel, fontPackTask);
        }

        // Phase A Step A3: GuardianContext 单 Form 模型（原 boot.FormClosed → guard.ForceExit 桥已删除）
        CF7Launcher.Guardian.GuardianContext ctx = new CF7Launcher.Guardian.GuardianContext(form);

        LogManager.Log("[Guardian] Bootstrap ready. Waiting for user to select slot...");
        StartupDiagnostics.Mark("bootstrap.ready");
        PerfTrace.Mark("guardian.bootstrap_ready");
        PerfTrace.FlushCounters("bootstrap_ready");

        // 消息循环: ctx (GuardianForm MainForm, BootstrapPanel 作为其子控件，Ready 时 panel swap)
        Application.Run(ctx);
        StartupDiagnostics.Mark("application.run_returned");

        // 清理：每步 try-catch 保护，防止单点异常跳过后续步骤
        GuardianLifecycle.MarkShuttingDown();
        LogManager.Log("[Guardian] Shutting down...");
        StartupDiagnostics.Mark("guardian.shutdown_start");
        PerfTrace.Mark("guardian.shutdown_start");
        PerfTrace.FlushCounters("shutdown_start");
        try { DiagnosticsBootstrap.Shutdown(); } catch { }
        try { frameTask.Stop(); } catch { }
        try { socketServer.SetFrameHandler(null); } catch { }
        try { socketServer.SetNotchHandler(null); } catch { }
        try { CF7Launcher.Audio.AudioEngine.Shutdown(); } catch { }
        try { processManager.Dispose(); } catch { }
        try { gomokuTask.Dispose(); } catch { }
        try { shopTask.Dispose(); } catch { }
        try { lootTask.Dispose(); } catch { }
        try { npcShopTask.Dispose(); } catch { }
        try { craftingTask.Dispose(); } catch { }
        try { hairdresserTask.Dispose(); } catch { }
        try { lootPanelCoordinator.Dispose(); } catch { }
        try { equipmentTuningTask.Dispose(); } catch { }
        try { characterBuildTask.Dispose(); } catch { }
        try { mapTask.Dispose(); } catch { }
        try { stageSelectTask.Dispose(); } catch { }
        try { intelligenceTask.Dispose(); } catch { }
        try { socketServer.Dispose(); } catch { }
        try { httpServer.Dispose(); } catch { }
        try { if (panelHost != null) panelHost.Dispose(); } catch { }
        try { if (inputShield != null) inputShield.Dispose(); } catch { }
        try { if (webOverlay != null) webOverlay.Dispose(); } catch { }
        try { if (backdrop != null) backdrop.Dispose(); } catch { }
        try { if (nativeHud != null) nativeHud.Dispose(); } catch { }
        try { notchOverlay.Dispose(); } catch { }
        try { hnOverlay.Dispose(); } catch { }
        try { v8Runtime.Dispose(); } catch { }
        try { toastOverlay.Dispose(); } catch { }
        try { File.Delete(portsFile); } catch { }
        LogManager.Shutdown();
        StartupDiagnostics.Mark("guardian.shutdown_complete");

        return 0;

        } // end try
        finally
        {
            // 统一出口：无论正常退出还是早退（Flash/SWF 缺失、端口失败等），
            // 都确保清理本次写入的信任条目，不留残留
            if (trustAcquired)
                FlashTrustManager.RevokeTrust();

            // UserGpuPreferences 注册表条目一律在退出时清理，避免玩家卸载后残留。
            try { GpuPreferenceManager.Revert(projectRoot); } catch { }
            try { PerfTrace.Shutdown(); } catch { }
            StartupDiagnostics.Mark("core.run_finally_complete");
        }
    }
}
