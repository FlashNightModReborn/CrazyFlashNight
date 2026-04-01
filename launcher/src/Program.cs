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

        // 定位项目根目录（EXE 所在目录）
        string exePath = typeof(Program).Assembly.Location;
        string projectRoot = Path.GetDirectoryName(exePath);

        // 创建 Guardian 窗口（bus-only 模式下也需要，因为 LogManager/Overlay 依赖 Form）
        GuardianForm form = new GuardianForm();

        // 启用文件日志（GuardianForm 构造函数中已初始化 UI 日志，这里补充文件通道）
        LogManager.InitFileLog(projectRoot);

        LogManager.Log("[Guardian] Project root: " + projectRoot);
        if (busOnly)
            LogManager.Log("[Guardian] --bus-only mode: skipping Flash Player startup");

        // 读配置（bus-only 跳过文件验证）
        AppConfig config = new AppConfig(projectRoot);

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

        // Toast overlay（GDI+ 保留作 fallback）
        ToastOverlay toastOverlay = new ToastOverlay(form, form.FlashHostPanel);

        // V8 持久化 Runtime + 打击伤害数字 overlay
        string scriptsDir = Path.Combine(projectRoot, "launcher", "scripts");
        V8Runtime v8Runtime = new V8Runtime(scriptsDir);
        HitNumberOverlay hnOverlay = new HitNumberOverlay(form, form.FlashHostPanel);
        FrameTask frameTask = new FrameTask(v8Runtime, hnOverlay);

        // 刘海 Notch overlay（FPS 显示 + 可展开工具栏）
        NotchOverlay notchOverlay = new NotchOverlay(
            form, form.FlashHostPanel, frameTask.FpsBuffer,
            projectRoot,
            new Action(form.ToggleFullscreen),
            new Action(form.ToggleLog),
            new Action(form.ForceExit),
            new Action<Keys>(form.HandleButtonClick));

        // WebView2 overlay（与 GDI+ overlay 并存，Phase 0 PoC）
        WebOverlayForm webOverlay = null;
        try
        {
            string wv2ver = CoreWebView2Environment.GetAvailableBrowserVersionString();
            LogManager.Log("[WebView2] Runtime found: " + wv2ver);
            string webDir = Path.Combine(projectRoot, "launcher", "web");
            webOverlay = new WebOverlayForm(form, form.FlashHostPanel, webDir);
        }
        catch (Exception ex)
        {
            LogManager.Log("[WebView2] Runtime not available, overlay disabled: " + ex.Message);
        }

        // WebView2 可用时注入 Notch 依赖 + 创建 InputShieldForm
        InputShieldForm inputShield = null;
        if (webOverlay != null)
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

            // 幽灵输入层：GDI+ 命中测试 + CDP 注入
            inputShield = new InputShieldForm(form, form.FlashHostPanel);
            webOverlay.SetInputShield(inputShield);
        }

        // Toast/Notch 路由：WebView2 可用时走 Web 渲染，否则 GDI+ fallback
        IToastSink toastSink = (webOverlay != null) ? (IToastSink)webOverlay : (IToastSink)toastOverlay;
        INotchSink notchSink = (webOverlay != null) ? (INotchSink)webOverlay : (INotchSink)notchOverlay;
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
        TaskRegistry.RegisterAll(router, gomokuTask, toastTask, frameTask, dataQueryTask, v8Runtime, hnOverlay, audioTask);

        // 注入 router 到 HttpApiServer（供 /task 端点使用）
        httpServer.SetRouter(router);

        // 注入 shutdown 回调
        httpServer.SetShutdownAction(delegate { form.ForceExit(); });

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

            // 清理
            LogManager.Log("[Guardian] Bus-only shutting down...");
            gomokuTask.Dispose();
            socketServer.Dispose();
            httpServer.Dispose();
            if (inputShield != null) inputShield.Dispose();
            if (webOverlay != null) webOverlay.Dispose();
            notchOverlay.Dispose();
            hnOverlay.Dispose();
            v8Runtime.Dispose();
            toastOverlay.Dispose();
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

        if (!processManager.Start())
        {
            ShowError("Failed to start Flash Player.");
            socketServer.Dispose();
            httpServer.Dispose();
            gomokuTask.Dispose();
            try { File.Delete(portsFile); } catch { }
            return 1;
        }

        windowManager.TrackProcess(processManager.FlashProcess);

        // Flash 退出双重检测：Process.Exited 事件 + 定时器后备
        form.TrackFlashProcess(processManager.FlashProcess);
        processManager.OnFlashExited += delegate
        {
            form.ForceExit();
        };

        // 在后台线程等待 Flash 窗口出现并嵌入
        ThreadPool.QueueUserWorkItem(delegate
        {
            if (config.GpuSharpeningEnabled)
            {
                LogManager.Log("[Guardian] GPU mode skipped: strict single-window capture path is not viable yet");
            }

            windowManager.EmbedFlashWindow(processManager.FlashProcess, form.FlashHostPanel);
            form.BeginInvoke(new Action(delegate
            {
                form.Show();
                form.Activate();
                if (webOverlay != null)
                {
                    // WebView2 接管 Toast + Notch，GDI+ overlay 不激活
                    webOverlay.SetReady();
                    // 幽灵输入层：在 WebOverlay 之后激活，确保 Z-order 在最上层
                    if (inputShield != null)
                        inputShield.SetReady();
                }
                else
                {
                    // fallback: GDI+ overlay
                    toastOverlay.SetReady();
                    notchOverlay.SetReady();
                }
                hnOverlay.SetReady();
            }));
        });

        LogManager.Log("[Guardian] All systems ready. Flash is running.");

        // 消息循环
        Application.Run(form);

        // 清理
        LogManager.Log("[Guardian] Shutting down...");
        CF7Launcher.Audio.AudioEngine.Shutdown();
        processManager.Dispose();
        gomokuTask.Dispose();
        socketServer.Dispose();
        httpServer.Dispose();
        if (inputShield != null) inputShield.Dispose();
        if (webOverlay != null) webOverlay.Dispose();
        notchOverlay.Dispose();
        hnOverlay.Dispose();
        v8Runtime.Dispose();
        toastOverlay.Dispose();
        try { File.Delete(portsFile); } catch { }
        LogManager.Shutdown();

        return 0;
    }
}
