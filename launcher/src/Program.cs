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
        long processStart = Stopwatch.GetTimestamp();
        PerfTrace.SetProcessStart(processStart);
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
                try { CoreWebView2Environment.GetAvailableBrowserVersionString(); }
                catch (Exception ex) { wv2Error = ex.Message; }
            }
            PerfTrace.Duration("webview2.runtime_precheck", wv2CheckStart,
                wv2Error == null ? "ok" : wv2Error);
            if (wv2Error != null)
            {
                MessageBox.Show(
                    "WebView2 Runtime 不可用, 无法启动启动器.\n\n"
                    + "请安装 WebView2 Evergreen Bootstrapper:\n"
                    + "https://developer.microsoft.com/microsoft-edge/webview2/\n\n"
                    + "详情: " + wv2Error,
                    "CF7:ME - WebView2 缺失",
                    MessageBoxButtons.OK, MessageBoxIcon.Error);
                PerfTrace.Mark("guardian.exit", "webview2_missing");
                PerfTrace.Shutdown();
                return 1;
            }
        }

        // Phase A: single-Form 模型。GuardianForm 承载 BootstrapPanel（正常模式）。
        // bus-only 模式 bootstrapWebDir=null，不创建 BootstrapPanel，FlashHostPanel 直接可见。
        long configStart = Stopwatch.GetTimestamp();
        AppConfig config = new AppConfig(projectRoot);
        PerfTrace.Duration("config.load", configStart);

        string bootstrapWebDir = busOnly ? null : Path.Combine(projectRoot, "launcher", "web");
        long formStart = Stopwatch.GetTimestamp();
        GuardianForm form = new GuardianForm(
            bootstrapWebDir,
            config.WebView2DisableGpu,
            config.WebView2AdditionalArgs);
        PerfTrace.Duration("guardian.form_construct", formStart);
        PerfTrace.Mark("guardian.form_constructed");

        // 启用文件日志（GuardianForm 构造函数中已初始化 UI 日志，这里补充文件通道）
        LogManager.InitFileLog(projectRoot);
        if (!string.IsNullOrEmpty(PerfTrace.TracePath))
            LogManager.Log("[PerfTrace] writing " + PerfTrace.TracePath);

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
            PerfTrace.Mark("guardian.exit", "steam_ownership_failed");
            PerfTrace.Shutdown();
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
        using (PerfTrace.Scope("audio.init"))
        {
            CF7Launcher.Audio.AudioEngine.Init(projectRoot);
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
            ShowError("XMLSocket server failed to start.\nNo available port found.");
            socketServer.Dispose();
            return 1;
        }

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
                new Action(form.ForceExit),
                new Action<Keys>(form.HandleButtonClick));
        }

        // Phase 1 (11c): WebView2 全局硬依赖; 入口已预检, 这里 WebOverlayForm 构造异常直接 throw 到上游
        string wv2ver;
        using (PerfTrace.Scope("webview2.runtime_check"))
        {
            wv2ver = CoreWebView2Environment.GetAvailableBrowserVersionString();
        }
        LogManager.Log("[WebView2] Runtime found: " + wv2ver);
        string webDir = Path.Combine(projectRoot, "launcher", "web");
        WebOverlayForm webOverlay;
        using (PerfTrace.Scope("web_overlay.construct"))
        {
            webOverlay = new WebOverlayForm(form, form.FlashHostPanel, webDir,
                config.WebOverlayLowEffects,
                config.WebOverlayDisableCssAnimations,
                config.WebOverlayDisableVisualizers,
                config.WebOverlayFrameRateLimit,
                config.WebView2DisableGpu,
                config.WebView2AdditionalArgs);
        }
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
        {
            webOverlay.SetNotchDependencies(frameTask.FpsBuffer,
                new Action(form.ToggleFullscreen),
                new Action(form.ToggleLog),
                new Action(form.ForceExit),
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
            // Flash hwnd 动态查询（SA 进程重启后 hwnd 变）
            Func<IntPtr> flashHwndProvider = delegate { return form.GetFlashHwnd(); };
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
            // pause/expand 走两条独立路径：
            //   pause → webOverlay.ToggleBgmPause（与 HandleJukeboxMessage 共享 _bgmPaused 镜像，避免双权威源）
            //   expand → router JUKEBOX_EXPAND → OpenPanel("jukebox") (Phase 5：jukebox-panel.js 已注册 Panels.register)
            WebOverlayForm capturedWebForJukebox = webOverlay;
            LauncherCommandRouter capturedRouterForJukebox = commandRouter;
            CF7Launcher.Guardian.Hud.RightContextWidget rightContext =
                new CF7Launcher.Guardian.Hud.RightContextWidget(
                    form.FlashHostPanel,
                    commandRouter,
                    mapCatalog,
                    delegate { capturedWebForJukebox.ToggleBgmPause(); },
                    delegate { capturedRouterForJukebox.Dispatch("JUKEBOX_EXPAND"); });
            nativeHud.AddWidget(rightContext);
            CF7Launcher.Guardian.Hud.SafeExitPanelWidget safeExitPanel =
                new CF7Launcher.Guardian.Hud.SafeExitPanelWidget(form.FlashHostPanel, commandRouter);
            nativeHud.AddWidget(safeExitPanel);
            // 必须在 widget 实例化后注入：router SAFEEXIT click → widget.Arm() → 进 Saving 显示状态条。
            // 否则 widget 仅靠 sv 推送决定可见，会被普通自动存盘（商店关闭/升级/saveAll）误触发。
            commandRouter.OnSafeExitArm = delegate { safeExitPanel.Arm(); };
            CF7Launcher.Guardian.Hud.ComboWidget comboWidget =
                new CF7Launcher.Guardian.Hud.ComboWidget(form.FlashHostPanel);
            nativeHud.AddWidget(comboWidget);
            // ToastWidget 顶替原 ToastOverlay 全屏 ULW。NativeHudOverlay.AddWidget 自动捕获引用，
            // IToastSink.AddMessage / SetReady 会 fan-out 到此 widget。
            CF7Launcher.Guardian.Hud.ToastWidget toastWidget =
                new CF7Launcher.Guardian.Hud.ToastWidget(form.FlashHostPanel);
            nativeHud.AddWidget(toastWidget);
            // NotchWidget 顶替原 NotchOverlay 独立 ULW（FPS 药丸 + 工具栏 + 通知栈 + 展开图表）。
            // INotchSink.AddNotice/SetStatusItem/ClearStatusItem 路由到此 widget。
            CF7Launcher.Guardian.Hud.NotchWidget notchWidget =
                new CF7Launcher.Guardian.Hud.NotchWidget(
                    form.FlashHostPanel, frameTask.FpsBuffer, projectRoot,
                    new Action(form.ToggleFullscreen),
                    new Action(form.ToggleLog),
                    new Action(form.ForceExit),
                    new Action<Keys>(form.HandleButtonClick));
            notchWidget.SetCommandRouter(commandRouter);
            nativeHud.AddWidget(notchWidget);
            // 升级 webOverlay 的 toast/notch fallback：先前以 toastOverlay=null/notchOverlay=null 注入，
            // nativeHud 就绪后接管 IToastSink + INotchSink。webOverlay.AddMessage/AddNotice 在
            // _useNativeHud=true 时直接转发 _toastFallback / _notchFallback，无需 ExecScript。
            webOverlay.SetFallback(nativeHud, nativeHud);
            // web `#quest-row > #map-hud-toggle` click → router MAPHUD_TOGGLE → C# 折叠态切换
            commandRouter.OnMapHudToggle = delegate { rightContext.ToggleMapCollapsed(); };
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
            };
            socketServer.SetUiDataHandler(uiDataTee);
            frameTask.SetUiDataHandler(uiDataTee);

            // P2-1 perf：后台预热 GDI+ 字体 / 字形栅格化 / silhouette PNG。
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
            LogManager.Log("[NativeHud] disabled (config useNativeHud=false; router goes through PostToWeb fallback)");
            PerfTrace.Mark("native_hud.disabled");
        }

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
        MapTask mapTask = new MapTask(socketServer);
        StageSelectTask stageSelectTask = new StageSelectTask(socketServer);
        IntelligenceTask intelligenceTask = new IntelligenceTask(projectRoot);
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
        using (PerfTrace.Scope("task.registry_register_all"))
        {
            TaskRegistry.RegisterAll(router, gomokuTask, toastTask, frameTask, dataQueryTask, v8Runtime, hnOverlay, audioTask, iconBakeTask, shopTask, mapTask, stageSelectTask, archiveTask, benchTask, webOverlay);
        }

        // 面板系统接线 (11c: webOverlay 必有)
        webOverlay.SetShopTask(shopTask);
        webOverlay.SetGomokuTask(gomokuTask);
        webOverlay.SetMapTask(mapTask);
        webOverlay.SetStageSelectTask(stageSelectTask);
        webOverlay.SetIntelligenceTask(intelligenceTask);
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
            stageSelectTask.Dispose();
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
            try { stageSelectTask.Dispose(); } catch { }
            try { socketServer.Dispose(); } catch { }
            try { httpServer.Dispose(); } catch { }
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
                if (toastOverlay != null) toastOverlay.SetReady();
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
        PerfTrace.Mark("guardian.bootstrap_ready");
        PerfTrace.FlushCounters("bootstrap_ready");

        // 消息循环: ctx (GuardianForm MainForm, BootstrapPanel 作为其子控件，Ready 时 panel swap)
        Application.Run(ctx);

        // 清理：每步 try-catch 保护，防止单点异常跳过后续步骤
        LogManager.Log("[Guardian] Shutting down...");
        PerfTrace.Mark("guardian.shutdown_start");
        PerfTrace.FlushCounters("shutdown_start");
        try { frameTask.Stop(); } catch { }
        try { socketServer.SetFrameHandler(null); } catch { }
        try { socketServer.SetNotchHandler(null); } catch { }
        try { CF7Launcher.Audio.AudioEngine.Shutdown(); } catch { }
        try { processManager.Dispose(); } catch { }
        try { gomokuTask.Dispose(); } catch { }
        try { shopTask.Dispose(); } catch { }
        try { mapTask.Dispose(); } catch { }
        try { stageSelectTask.Dispose(); } catch { }
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
            try { PerfTrace.Shutdown(); } catch { }
        }
    }
}
