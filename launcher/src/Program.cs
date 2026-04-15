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

        // 创建 Guardian 窗口（bus-only 模式下也需要，因为 LogManager/Overlay 依赖 Form）
        GuardianForm form = new GuardianForm();

        // 启用文件日志（GuardianForm 构造函数中已初始化 UI 日志，这里补充文件通道）
        LogManager.InitFileLog(projectRoot);

        LogManager.Log("[Guardian] Project root: " + projectRoot);
        if (busOnly)
            LogManager.Log("[Guardian] --bus-only mode: skipping Flash Player startup");

        // 读配置（bus-only 跳过文件验证）
        AppConfig config = new AppConfig(projectRoot);

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
        WebOverlayForm webOverlay = new WebOverlayForm(form, form.FlashHostPanel, webDir);

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
        ArchiveTask archiveTask = new ArchiveTask(projectRoot);
        TaskRegistry.RegisterAll(router, gomokuTask, toastTask, frameTask, dataQueryTask, v8Runtime, hnOverlay, audioTask, iconBakeTask, shopTask, archiveTask);

        // 面板系统接线 (11c: webOverlay 必有)
        webOverlay.SetShopTask(shopTask);
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
            try { socketServer.Dispose(); } catch { }
            try { httpServer.Dispose(); } catch { }
            try { if (inputShield != null) inputShield.Dispose(); } catch { }
            try { if (webOverlay != null) webOverlay.Dispose(); } catch { }
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

        // Flash 退出兜底: 活跃状态下由 GameLaunchFlow.OnFlashExited 触发 Error; Ready 时仍退出守护进程
        processManager.OnFlashExited += delegate(System.Diagnostics.Process exited)
        {
            // 旧逻辑: 无条件 ForceExit. 新逻辑: GameLaunchFlow 会接管; 这里保留作为 Ready 后的兜底
            form.ForceExit();
        };

        // Flash 僵尸进程兜底：Socket 断连后 10s 内进程仍未退出则强制关闭
        // Flash Player 20 SA 偶发退出卡死，Process.Exited 和 HasExited 均不触发
        socketServer.OnClientDisconnected += delegate
        {
            System.Threading.Timer zombieTimer = null;
            zombieTimer = new System.Threading.Timer(delegate
            {
                try { zombieTimer.Dispose(); } catch { }
                Process fp = processManager.FlashProcess;
                if (fp != null && !fp.HasExited)
                {
                    LogManager.Log("[Guardian] Flash zombie detected (socket disconnected 10s ago, process still alive) — forcing exit");
                    form.ForceExit();
                }
            }, null, 10000, System.Threading.Timeout.Infinite);
        };

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
        // BootstrapForm (WebView2)
        string bootstrapWebDir = Path.Combine(projectRoot, "launcher", "web");
        CF7Launcher.Guardian.BootstrapForm bootForm = new CF7Launcher.Guardian.BootstrapForm(bootstrapWebDir);

        // GameLaunchFlow (状态机接管 processManager.Start / EmbedFlashWindow / SetReady 全链)
        CF7Launcher.Guardian.GameLaunchFlow launchFlow = new CF7Launcher.Guardian.GameLaunchFlow(
            socketServer, router, processManager, windowManager,
            form, bootForm,
            /* readyWiring */ delegate
            {
                // Phase 1 全局硬依赖 WebView2: webOverlay 永不为 null
                toastOverlay.SetReady();
                webOverlay.SetReady();
                if (inputShield != null) inputShield.SetReady();
                hnOverlay.SetReady();
                // 11b-β: Ready 才让托盘可见
                form.ShowTrayIcon();
            },
            /* hotkeyGuardSpawn */ null);

        bootForm.StateProvider = delegate { return launchFlow.CurrentState; };
        launchFlow.OnStateChanged += delegate(string state, string smsg)
        {
            Newtonsoft.Json.Linq.JObject obj = new Newtonsoft.Json.Linq.JObject();
            obj["type"] = "bootstrap";
            obj["cmd"] = "state";
            obj["state"] = state;
            obj["msg"] = smsg ?? "";
            bootForm.PostToWeb(obj.ToString(Newtonsoft.Json.Formatting.None));
        };
        bootForm.OnJsMessage += delegate(string json)
        {
            CF7Launcher.Guardian.BootstrapMessageHandler.Handle(json, bootForm, archiveTask, launchFlow);
        };

        // GuardianContext: BootstrapForm 作 MainForm; 退出走 guard.ForceExit -> DoExit -> ExitGuard
        CF7Launcher.Guardian.GuardianContext ctx = new CF7Launcher.Guardian.GuardianContext(bootForm, form);

        LogManager.Log("[Guardian] Bootstrap ready. Waiting for user to select slot...");

        // 消息循环: ctx (BootstrapForm MainForm, GuardianForm 由 launchFlow Ready 时 Show)
        Application.Run(ctx);

        // 清理：每步 try-catch 保护，防止单点异常跳过后续步骤
        LogManager.Log("[Guardian] Shutting down...");
        try { frameTask.Stop(); } catch { }
        try { socketServer.SetFrameHandler(null); } catch { }
        try { socketServer.SetNotchHandler(null); } catch { }
        try { CF7Launcher.Audio.AudioEngine.Shutdown(); } catch { }
        try { processManager.Dispose(); } catch { }
        try { gomokuTask.Dispose(); } catch { }
        try { socketServer.Dispose(); } catch { }
        try { httpServer.Dispose(); } catch { }
        try { if (inputShield != null) inputShield.Dispose(); } catch { }
        try { if (webOverlay != null) webOverlay.Dispose(); } catch { }
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
        }
    }
}
