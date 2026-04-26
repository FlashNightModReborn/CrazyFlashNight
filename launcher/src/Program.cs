// CF7:ME Guardian Process — 入口
// C# 5 语法

using System;
using System.Diagnostics;
using System.IO;
using System.Runtime.InteropServices;
using System.Threading;
using System.Windows.Forms;
using CF7Launcher.Bus;
using CF7Launcher.Config;
using CF7Launcher.Guardian;
using CF7Launcher.Data;
using CF7Launcher.Tasks;
using CF7Launcher.V8;
using Microsoft.Web.WebView2.Core;

class Program
{
    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    static extern int MessageBoxW(IntPtr hWnd, string text, string caption, uint type);

    const uint MB_OK = 0x00000000;
    const uint MB_ICONERROR = 0x00000010;

    static void ShowError(string message)
    {
        MessageBoxW(IntPtr.Zero, message, "CF7:ME Guardian", MB_OK | MB_ICONERROR);
    }

    [STAThread]
    static int Main(string[] args)
    {
        DpiAwarenessBootstrap.Initialize();

        // 单例检查
        bool createdNew;
        Mutex mutex = new Mutex(true, "Global\\CF7ME_Guardian", out createdNew);
        if (!createdNew)
            return 0;

        Application.EnableVisualStyles();
        Application.SetCompatibleTextRenderingDefault(false);

        // 非 UI 线程未处理异常：仅补日志（进程即将终止，CLR 自行处理）
        AppDomain.CurrentDomain.UnhandledException += delegate(object s, UnhandledExceptionEventArgs ue)
        {
            try { LogManager.Log("[Guardian] Unhandled exception:\n" + ue.ExceptionObject); } catch { }
        };

        try
        {
            return Run(args);
        }
        finally
        {
            mutex.ReleaseMutex();
            mutex.Dispose();
        }
    }

    static int Run(string[] args)
    {
        bool busOnly = Array.IndexOf(args, "--bus-only") >= 0;
        bool forceWebViewFail = Array.IndexOf(args, "--force-webview-fail") >= 0;

        // 定位项目根目录（EXE 所在目录）
        string exePath = typeof(Program).Assembly.Location;
        string projectRoot = Path.GetDirectoryName(exePath);

        // Phase 1 (11b-β): WebView2 全局硬依赖 fail-closed 预检.
        // 正常模式必须 WebView2 Runtime 可用才能创建 BootstrapForm; bus-only 跳过.
        if (!busOnly)
        {
            string wv2Error = null;
            if (forceWebViewFail)
            {
                wv2Error = "forced by --force-webview-fail flag";
            }
            else
            {
                try { CoreWebView2Environment.GetAvailableBrowserVersionString(); }
                catch (Exception ex) { wv2Error = ex.Message; }
            }
            if (wv2Error != null)
            {
                MessageBox.Show(
                    "WebView2 Runtime 不可用, 无法启动启动器.\n\n"
                    + "请安装 WebView2 Evergreen Bootstrapper:\n"
                    + "https://developer.microsoft.com/microsoft-edge/webview2/\n\n"
                    + "详情: " + wv2Error,
                    "CF7:ME - WebView2 缺失",
                    MessageBoxButtons.OK, MessageBoxIcon.Error);
                return 1;
            }
        }

        // Phase A: single-Form 模型。GuardianForm 承载 BootstrapPanel（正常模式）。
        // bus-only 模式 bootstrapWebDir=null，不创建 BootstrapPanel，FlashHostPanel 直接可见。
        AppConfig config = new AppConfig(projectRoot);

        string bootstrapWebDir = busOnly ? null : Path.Combine(projectRoot, "launcher", "web");
        GuardianForm form = new GuardianForm(
            bootstrapWebDir,
            config.WebView2DisableGpu,
            config.WebView2AdditionalArgs);

        // 启用文件日志（GuardianForm 构造函数中已初始化 UI 日志，这里补充文件通道）
        LogManager.InitFileLog(projectRoot);

        LogManager.Log("[Guardian] Project root: " + projectRoot);

        // 开发用 Ctrl+G GPU 探针：仅 config.devGpuProbeHotkey=true 时启用。玩家版默认不注入。
        if (config.DevGpuProbeHotkey)
            form.EnableDevGpuProbeHotkey();

        // UserGpuPreferences 在子进程创建时被 Windows 读取。WebView2 真正 spawn 发生在 Application.Run
        // 触发 BootstrapPanel.Load 之后，所以这里写入仍然赶得上；放在日志通道就绪之后可以把诊断完整写进 launcher.log。
        GpuPreferenceManager.ApplyIfNeeded(projectRoot, config.GpuPreference);
        // Phase 2b: 用户级偏好 (lastPlayedSlot / introEnabled), 落盘到 launcher_user_prefs.json
        CF7Launcher.Config.UserPrefs userPrefs = new CF7Launcher.Config.UserPrefs(projectRoot);

        HighDpiCompatibilityResult dpiCompat = HighDpiCompatibilityDetector.Detect(exePath);
        DpiDiagnostics.LogProcessStartup(DpiAwarenessBootstrap.Result, dpiCompat);
        DpiDiagnostics.LogWindow("GuardianForm", form.Handle);
        HighDpiCompatibilityDetector.ScheduleRiskWarning(form, dpiCompat, userPrefs);
        if (busOnly)
            LogManager.Log("[Guardian] --bus-only mode: skipping Flash Player startup");

        // Steam 正版所有权校验（不通过则不写信任文件，Flash 无法联网）
        if (!SteamOwnershipCheck.Check(projectRoot))
        {
            LogManager.Log("[Guardian] Steam ownership check FAILED — refusing to write trust file");
            string reason = SteamOwnershipCheck.FailReason;
            if (reason == "steam_not_running")
                ShowError("Steam is not running.\nPlease start Steam first, then launch the game from your Steam library.");
            else if (reason == "not_owned")
                ShowError("Game ownership not found.\nPlease make sure you own the game on this Steam account.");
            else if (reason == "dll_missing" || reason == "dll_load_failed")
                ShowError("Steam runtime files are missing or corrupted.\nPlease verify game files through Steam.");
            else
                ShowError("Steam ownership verification failed.\nPlease launch the game from Steam.");
            return 1;
        }

        // Flash Player 本地信任配置（确保 SWF 可访问网络）
        // 使用 try/finally 确保所有退出路径都调用 RevokeTrust
        bool trustAcquired = FlashTrustManager.EnsureTrust(projectRoot);
        if (!trustAcquired)
            LogManager.Log("[Guardian] WARNING: Flash trust not configured — SWF may fail to connect");

        try
        {

        if (!busOnly)
        {
            if (!File.Exists(config.FlashPlayerPath))
            {
                ShowError("Flash Player not found:\n" + config.FlashPlayerPath);
                return 1;
            }
            if (!File.Exists(config.SwfPath))
            {
                ShowError("SWF file not found:\n" + config.SwfPath);
                return 1;
            }

            LogManager.Log("[Guardian] Flash: " + config.FlashPlayerPath);
            LogManager.Log("[Guardian] SWF: " + config.SwfPath);
        }

        // === 音频引擎（在所有网络服务之前初始化）===
        CF7Launcher.Audio.AudioEngine.Init(projectRoot);
        CF7Launcher.Audio.AudioEngine.PreloadFromDirectories(projectRoot);

        // 默认音量（直接 P/Invoke，不依赖 Flash socket）
        // Flash 存档加载后会通过 setGlobalVolume/setBGMVolume 覆盖
        CF7Launcher.Audio.AudioEngine.ma_bridge_set_master_volume(0.5f);  // 50%

        // === 音乐目录（扫描 + 热加载监听）===
        var musicCatalog = new CF7Launcher.Audio.MusicCatalog(projectRoot);

        // === V8 总线（两种模式都启动）===

        PortAllocator portAlloc = new PortAllocator();
        MessageRouter router = new MessageRouter();

        int httpPort = portAlloc.ClaimPort();

        XmlSocketServer socketServer = new XmlSocketServer(router);
        int socketPort = portAlloc.ClaimPort();
        if (socketPort < 0 || !socketServer.Start(socketPort))
        {
            ShowError("XMLSocket server failed to start.\nNo available port found.");
            socketServer.Dispose();
            return 1;
        }

        HttpApiServer httpServer = new HttpApiServer(socketPort, projectRoot, socketServer);
        if (httpPort < 0 || !httpServer.Start(httpPort))
        {
            ShowError("HTTP server failed to start on port " + httpPort + ".\nAnother instance may be running.");
            socketServer.Dispose();
            httpServer.Dispose();
            return 1;
        }

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

        // Toast overlay（GDI+ 保留作 fallback）
        ToastOverlay toastOverlay = new ToastOverlay(form, form.FlashHostPanel);

        // V8 持久化 Runtime + 打击伤害数字 overlay
        string scriptsDir = Path.Combine(projectRoot, "launcher", "scripts");
        V8Runtime v8Runtime = new V8Runtime(scriptsDir);
        HitNumberOverlay hnOverlay = new HitNumberOverlay(form, form.FlashHostPanel);
        FrameTask frameTask = new FrameTask(v8Runtime, hnOverlay);

        // 性能决策引擎（主控模式：发送 P 指令到 AS2，AS2 端只采样+执行）
        var perfEngine = new PerfDecisionEngine(frameTask.FpsBuffer, socketServer);
        perfEngine.IsActive = true;
        frameTask.SetDecisionEngine(perfEngine);

        // 搓招输入处理：注入 socket 引用用于 K 前缀推送，初始化 V8 GameInput
        frameTask.SetSocket(socketServer);
        v8Runtime.InitGameInput();

        // 刘海 Notch overlay（FPS 显示 + 可展开工具栏）
        NotchOverlay notchOverlay = new NotchOverlay(
            form, form.FlashHostPanel, frameTask.FpsBuffer,
            projectRoot,
            new Action(form.ToggleFullscreen),
            new Action(form.ToggleLog),
            new Action(form.ForceExit),
            new Action<Keys>(form.HandleButtonClick));

        // Phase 1 (11c): WebView2 全局硬依赖; 入口已预检, 这里 WebOverlayForm 构造异常直接 throw 到上游
        string wv2ver = CoreWebView2Environment.GetAvailableBrowserVersionString();
        LogManager.Log("[WebView2] Runtime found: " + wv2ver);
        string webDir = Path.Combine(projectRoot, "launcher", "web");
        WebOverlayForm webOverlay = new WebOverlayForm(form, form.FlashHostPanel, webDir,
            config.WebOverlayLowEffects,
            config.WebOverlayDisableCssAnimations,
            config.WebOverlayDisableVisualizers,
            config.WebOverlayFrameRateLimit,
            config.WebView2DisableGpu,
            config.WebView2AdditionalArgs);
        CursorOverlayForm cursorOverlay = null;
        if (config.NativeCursorOverlayEnabled)
        {
            cursorOverlay = new CursorOverlayForm(form, form.FlashHostPanel,
                Path.Combine(webDir, "assets", "cursor", "native"));
            LogManager.Log("[Cursor] native overlay enabled");
        }
        else
        {
            LogManager.Log("[Cursor] native overlay disabled by config; using system cursor for A/B diagnostics");
        }

        // Notch 依赖 + InputShieldForm
        InputShieldForm inputShield = null;
        {
            webOverlay.SetNotchDependencies(frameTask.FpsBuffer,
                new Action(form.ToggleFullscreen),
                new Action(form.ToggleLog),
                new Action(form.ForceExit),
                new Action<Keys>(form.HandleButtonClick));

            // GDI+ fallback：WebView2 初始化失败或未就绪时走这里
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

            // U 前缀快车道：UI 数据透传到 WebView2
            socketServer.SetUiDataHandler(new Action<string>(webOverlay.HandleUiData));

            // combo hints → WebView2 (FrameTask 每帧推送)
            frameTask.SetUiDataHandler(new Action<string>(webOverlay.HandleUiData));

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
        webOverlay.SetCommandRouter(commandRouter);

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
            // Flash hwnd 动态查询（SA 进程重启后 hwnd 变）
            Func<IntPtr> flashHwndProvider = delegate { return form.GetFlashHwnd(); };
            // Phase 3: 注入 NotchOverlay/ToastOverlay，让 PanelHost 在 panel open/close 时显式 Suspend/Resume
            panelHost = new PanelHostController(form, webOverlay, nativeHud, backdrop,
                inputShield, hnOverlay, cursorOverlay, form.GetPanelEscapeSource(), flashHwndProvider,
                notchOverlay, toastOverlay);
            webOverlay.SetPanelHost(panelHost);
            commandRouter.SetPanelHost(panelHost);

            // Phase 4: 注册常驻 widget。已迁：TopRightTools / NotchToolbar / Currency / SafeExitPanel。
            // 待迁（下轮）：Combo / QuestNotice / JukeboxTitlebar / MapHud。
            // 无 widget 时 NativeHud SW_HIDE，不影响 Phase 3 行为。
            CF7Launcher.Guardian.Hud.TopRightToolsWidget topRightTools =
                new CF7Launcher.Guardian.Hud.TopRightToolsWidget(form.FlashHostPanel, commandRouter);
            nativeHud.AddWidget(topRightTools);
            CF7Launcher.Guardian.Hud.NotchToolbarWidget notchToolbar =
                new CF7Launcher.Guardian.Hud.NotchToolbarWidget(form.FlashHostPanel, commandRouter);
            nativeHud.AddWidget(notchToolbar);
            CF7Launcher.Guardian.Hud.CurrencyWidget currencyWidget =
                new CF7Launcher.Guardian.Hud.CurrencyWidget(form.FlashHostPanel);
            nativeHud.AddWidget(currencyWidget);
            CF7Launcher.Guardian.Hud.SafeExitPanelWidget safeExitPanel =
                new CF7Launcher.Guardian.Hud.SafeExitPanelWidget(form.FlashHostPanel, commandRouter);
            nativeHud.AddWidget(safeExitPanel);
            // 必须在 widget 实例化后注入：router SAFEEXIT click → widget.Arm() → 进 Saving 显示状态条。
            // 否则 widget 仅靠 sv 推送决定可见，会被普通自动存盘（商店关闭/升级/saveAll）误触发。
            commandRouter.OnSafeExitArm = delegate { safeExitPanel.Arm(); };
            // z-order 锚点：把 NativeHud 沉到 HitNumber 之下（Cursor 在 HitNumber 之上 → 自动也在 NativeHud 之上）
            // 这样 widget 区域不会遮挡伤害数字与鼠标。
            if (hnOverlay != null) nativeHud.SetZOrderInsertAfter(hnOverlay.Handle);

            // tee UiData：socket worker 既送 webOverlay 也送 nativeHud
            // Phase 3+ widget 实化为 IUiDataConsumer 后才有意义；当前 nativeHud.HandleUiData 有 fast-path 直接 return（无 IUiDataConsumer）
            Action<string> uiDataTee = delegate(string raw)
            {
                try { webOverlay.HandleUiData(raw); }
                catch (Exception ex) { LogManager.Log("[Tee] web UiData throw: " + ex.Message); }
                try { nativeHud.HandleUiData(raw); }
                catch (Exception ex) { LogManager.Log("[Tee] hud UiData throw: " + ex.Message); }
            };
            socketServer.SetUiDataHandler(uiDataTee);
            frameTask.SetUiDataHandler(uiDataTee);
            LogManager.Log("[NativeHud] enabled (Phase 2: panel routing hijacked)");
        }
        else
        {
            LogManager.Log("[NativeHud] disabled (config useNativeHud=false; router goes through PostToWeb fallback)");
        }

        // Phase 1 (11c): WebView2 硬依赖 — webOverlay 必有, 直接用
        IToastSink toastSink = webOverlay;
        INotchSink notchSink = webOverlay;
        ToastTask toastTask = new ToastTask(toastSink);

        // 快车道注入：F/R 前缀消息由 XmlSocketServer 直接分发到 FrameTask，绕过 MessageRouter
        socketServer.SetFrameHandler(frameTask);
        // N/W 前缀快车道：通知 + 波次计时器 → Notch sink
        socketServer.SetNotchHandler(notchSink);

        // Task 注册（TaskRegistry = single source of truth）
        GomokuTask gomokuTask = new GomokuTask(projectRoot);
        DataCache dataCache = new DataCache(projectRoot);
        DataQueryTask dataQueryTask = new DataQueryTask(dataCache);
        CF7Launcher.Tasks.AudioTask audioTask = new CF7Launcher.Tasks.AudioTask();
        IconBakeTask iconBakeTask = new IconBakeTask(projectRoot, notchSink);
        ShopTask shopTask = new ShopTask(socketServer);
        MapTask mapTask = new MapTask(socketServer);
        ArchiveTask archiveTask = new ArchiveTask(projectRoot);
        BenchTask benchTask = new BenchTask(socketServer);
        TaskRegistry.RegisterAll(router, gomokuTask, toastTask, frameTask, dataQueryTask, v8Runtime, hnOverlay, audioTask, iconBakeTask, shopTask, mapTask, archiveTask, benchTask, webOverlay);

        // 面板系统接线 (11c: webOverlay 必有)
        webOverlay.SetShopTask(shopTask);
        webOverlay.SetGomokuTask(gomokuTask);
        webOverlay.SetMapTask(mapTask);
        webOverlay.SetPanelStateCallback(form.HandlePanelStateChanged);
        form.SetWebOverlay(webOverlay);
        socketServer.OnClientDisconnected += webOverlay.OnSocketDisconnected;
        socketServer.OnClientReady += webOverlay.OnSocketReconnected;

        // 注入 router 到 HttpApiServer（供 /task 端点使用）
        httpServer.SetRouter(router);

        // 注入 shutdown 回调
        httpServer.SetShutdownAction(delegate { form.ForceExit(); });

        // 退出前回调：在 Form dispose 之前断开快车道，防退出竞态
        form.OnShutdownEarly = delegate
        {
            musicCatalog.Dispose();
            frameTask.Stop();
            shopTask.Dispose();
            mapTask.Dispose();
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
        }
        catch (Exception ex)
        {
            LogManager.Log("[Guardian] Failed to write ports file: " + ex.Message);
        }

        LogManager.Log("[Guardian] Bus ready: HTTP=" + httpPort + " Socket=" + socketPort);

        if (busOnly)
        {
            // === bus-only 模式：仅运行通信总线，不启动 Flash Player ===
            // Flash Player 由外部（如 Flash CS6 testMovie）自行启动并连接
            LogManager.Log("[Guardian] Bus-only mode active. Waiting for external Flash connection...");
            form.Text = "CF7:ME Bus (test mode)";

            // 消息循环（保持进程存活）
            Application.Run(form);

            // 清理：每步 try-catch 保护，防止单点异常跳过后续步骤
            LogManager.Log("[Guardian] Bus-only shutting down...");
            try { frameTask.Stop(); } catch { }
            try { socketServer.SetFrameHandler(null); } catch { }
            try { socketServer.SetNotchHandler(null); } catch { }
            try { gomokuTask.Dispose(); } catch { }
            try { shopTask.Dispose(); } catch { }
            try { mapTask.Dispose(); } catch { }
            try { socketServer.Dispose(); } catch { }
            try { httpServer.Dispose(); } catch { }
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
            }
            catch (Exception ex)
            {
                LogManager.Log("[Guardian] HotkeyGuard failed: " + ex.Message);
            }
        }
        else
        {
            LogManager.Log("[Guardian] hotkey_guard.exe not found, shortcuts not blocked");
        }

        // 守护进程核心
        WindowManager windowManager = new WindowManager();

        ProcessManager processManager = new ProcessManager(
            config.FlashPlayerPath, config.SwfPath);

        form.BindWindowManager(windowManager);

        // 11b-α: processManager.Start / TrackProcess / TrackFlashProcess 迁入 GameLaunchFlow.TransitionToSpawning
        //   Flash 不立即启动, 由 BootstrapForm 的 start_game 触发 launchFlow.StartGame(slot)

        // 延迟注入 WindowManager 到性能决策引擎（bus-only 模式不走此路径）
        perfEngine.SetWindowManager(windowManager);

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
            solLocator, solResolver, archiveTask, config.SwfPath);

        // Phase A 两段式初始化：GuardianForm 已建（line 97），BootstrapPanel 已作为其子控件构造。
        // 此处构造 GameLaunchFlow（依赖 form + form.BootstrapPanel）→ 调 InitializeLaunchFlow 补 wire.
        CF7Launcher.Guardian.GameLaunchFlow launchFlow = new CF7Launcher.Guardian.GameLaunchFlow(
            socketServer, router, processManager, windowManager,
            form, form.BootstrapPanel,
            /* readyWiring */ delegate
            {
                // Phase 1 全局硬依赖 WebView2: webOverlay 永不为 null
                toastOverlay.SetReady();
                webOverlay.SetReady();
                if (inputShield != null) inputShield.SetReady();
                hnOverlay.SetReady();
                if (nativeHud != null) nativeHud.SetReady();
                // 11b-β: Ready 才让托盘可见
                form.ShowTrayIcon();
            },
            /* hotkeyGuardSpawn */ null,
            saveCtx);

        // Phase A Step A2: wire launchFlow 到 GuardianForm（OnFormClosing 状态分流 + 热键 state-aware guard）
        form.InitializeLaunchFlow(launchFlow);

        // Phase D Step D11: silent prewarm 状态不广播给 bootstrap UI,
        // 避免 archive-editor 进只读 / bootstrap.html 闪 running badge / BMH RequireIdle 挡 save.
        // silentAtEmit 在 SetState 锁内快照, 不受 BeginInvoke 排队延迟影响.
        launchFlow.OnStateChanged += delegate(string state, string smsg, bool silentAtEmit)
        {
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
                    userPrefs);
            };
        }

        // Phase A Step A3: GuardianContext 单 Form 模型（原 boot.FormClosed → guard.ForceExit 桥已删除）
        CF7Launcher.Guardian.GuardianContext ctx = new CF7Launcher.Guardian.GuardianContext(form);

        LogManager.Log("[Guardian] Bootstrap ready. Waiting for user to select slot...");

        // 消息循环: ctx (GuardianForm MainForm, BootstrapPanel 作为其子控件，Ready 时 panel swap)
        Application.Run(ctx);

        // 清理：每步 try-catch 保护，防止单点异常跳过后续步骤
        LogManager.Log("[Guardian] Shutting down...");
        try { frameTask.Stop(); } catch { }
        try { socketServer.SetFrameHandler(null); } catch { }
        try { socketServer.SetNotchHandler(null); } catch { }
        try { CF7Launcher.Audio.AudioEngine.Shutdown(); } catch { }
        try { processManager.Dispose(); } catch { }
        try { gomokuTask.Dispose(); } catch { }
        try { shopTask.Dispose(); } catch { }
        try { mapTask.Dispose(); } catch { }
        try { socketServer.Dispose(); } catch { }
        try { httpServer.Dispose(); } catch { }
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
        }
    }
}
