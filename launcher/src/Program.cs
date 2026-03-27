// CF7:ME Guardian Process — 入口
// C# 5 语法

using System;
using System.IO;
using System.Runtime.InteropServices;
using System.Threading;
using System.Windows.Forms;
using CF7Launcher.Bus;
using CF7Launcher.Config;
using CF7Launcher.Guardian;
using CF7Launcher.Tasks;

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
        // 定位项目根目录（EXE 所在目录）
        string exePath = typeof(Program).Assembly.Location;
        string projectRoot = Path.GetDirectoryName(exePath);

        // 创建 Guardian 窗口（默认隐藏，托盘图标可唤出）
        GuardianForm form = new GuardianForm();

        // 从此刻起所有日志走 LogManager
        LogManager.Log("[Guardian] Project root: " + projectRoot);

        // 读配置
        AppConfig config = new AppConfig(projectRoot);

        // 验证文件
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

        // === V8 总线 ===

        PortAllocator portAlloc = new PortAllocator();
        MessageRouter router = new MessageRouter();

        // 端口顺序：先 HTTP 再 XMLSocket（与 Node.js 版一致）
        int httpPort = portAlloc.ClaimPort();

        XmlSocketServer socketServer = new XmlSocketServer(router);
        int socketPort = portAlloc.ClaimPort();
        if (socketPort < 0 || !socketServer.Start(socketPort))
        {
            LogManager.Log("[Guardian] WARNING: XMLSocket server failed to start");
            socketPort = 0;
        }

        HttpApiServer httpServer = new HttpApiServer(socketPort, projectRoot, socketServer);
        if (httpPort < 0 || !httpServer.Start(httpPort))
        {
            LogManager.Log("[Guardian] WARNING: HTTP server failed to start");
        }

        router.OnConsoleResult += delegate(string json)
        {
            httpServer.ResolveConsoleResult(json);
        };

        // Task 处理器
        GomokuTask gomokuTask = new GomokuTask(projectRoot);
        router.RegisterSync("eval", EvalTask.Handle);
        router.RegisterSync("regex", RegexTask.Handle);
        router.RegisterSync("computation", ComputationTask.Handle);
        router.RegisterAsync("gomoku_eval", gomokuTask.HandleAsync);
        router.RegisterSync("audio", delegate(Newtonsoft.Json.Linq.JObject msg)
        {
            return "{\"success\":false,\"error\":\"audio task not supported in this version\"}";
        });

        LogManager.Log("[Guardian] Bus ready: HTTP=" + httpPort + " Socket=" + socketPort);

        // === 守护进程核心 ===

        WindowManager windowManager = new WindowManager();
        KeyboardHook keyboardHook = new KeyboardHook(windowManager);
        ProcessManager processManager = new ProcessManager(
            config.FlashPlayerPath, config.SwfPath);

        if (!keyboardHook.Install())
        {
            LogManager.Log("[Guardian] WARNING: Keyboard hook failed");
        }

        // 绑定 WindowManager，让按钮可以向 Flash 发送按键
        form.BindWindowManager(windowManager);

        if (!processManager.Start())
        {
            ShowError("Failed to start Flash Player.");
            keyboardHook.Dispose();
            socketServer.Dispose();
            httpServer.Dispose();
            gomokuTask.Dispose();
            return 1;
        }

        windowManager.TrackProcess(processManager.FlashProcess);

        // 在后台线程等待 Flash 窗口出现并嵌入
        System.Threading.ThreadPool.QueueUserWorkItem(delegate
        {
            windowManager.EmbedFlashWindow(processManager.FlashProcess, form.FlashHostPanel);
            // 嵌入后显示主窗口
            form.BeginInvoke(new Action(delegate
            {
                form.Show();
                form.Activate();
            }));
        });

        // Flash 退出时关闭应用
        processManager.OnFlashExited += delegate
        {
            form.ForceExit();
        };

        LogManager.Log("[Guardian] All systems ready. Flash is running.");

        // 消息循环（GuardianForm 提供消息泵 + 托盘图标）
        // 窗口默认不显示，双击托盘图标可打开日志
        Application.Run(form);

        // 清理
        LogManager.Log("[Guardian] Shutting down...");
        keyboardHook.Dispose();
        processManager.Dispose();
        gomokuTask.Dispose();
        socketServer.Dispose();
        httpServer.Dispose();

        return 0;
    }
}
