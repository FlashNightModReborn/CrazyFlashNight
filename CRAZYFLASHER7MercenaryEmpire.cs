// ============================================================
// CRAZYFLASHER7MercenaryEmpire.exe — 极简启动器 stub
// 职责：环境检测 → 调用同目录下的 .bat 脚本
// 所有可变业务逻辑在 .bat 中，此文件编译后几乎不需要再改
//
// 编译命令（在此文件所在目录执行）：
//   C:\Windows\Microsoft.NET\Framework64\v4.0.30319\csc.exe
//     /target:winexe /win32icon:CRAZYFLASHER7MercenaryEmpire.ico
//     /out:CRAZYFLASHER7MercenaryEmpire.exe
//     CRAZYFLASHER7MercenaryEmpire.cs
// ============================================================

using System;
using System.Diagnostics;
using System.IO;
using System.Runtime.InteropServices;
using System.Windows.Forms;

class Launcher
{
    // Win7 上即使有 .NET 2.0 也不一定有 WinForms 的 MessageBox
    // 用 Win32 API 确保在最低环境也能弹窗
    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    static extern int MessageBoxW(IntPtr hWnd, string text, string caption, uint type);

    const uint MB_OK = 0x00000000;
    const uint MB_ICONERROR = 0x00000010;
    const uint MB_ICONWARNING = 0x00000030;

    static void ShowError(string message)
    {
        MessageBoxW(IntPtr.Zero, message, "CRAZYFLASHER7 佣兵帝国", MB_OK | MB_ICONERROR);
    }

    static void ShowWarning(string message)
    {
        MessageBoxW(IntPtr.Zero, message, "CRAZYFLASHER7 佣兵帝国", MB_OK | MB_ICONWARNING);
    }

    static int Main(string[] args)
    {
        // 定位自身所在目录
        string exePath = typeof(Launcher).Assembly.Location;
        string exeDir = Path.GetDirectoryName(exePath);

        // 查找同目录下的 .bat 脚本
        string batName = Path.GetFileNameWithoutExtension(exePath) + ".bat";
        string batPath = Path.Combine(exeDir, batName);

        if (!File.Exists(batPath))
        {
            ShowError(
                "找不到启动脚本：\n" + batName +
                "\n\n请确保该文件与 EXE 在同一目录下。" +
                "\n\n当前目录：\n" + exeDir);
            return 1;
        }

        // 环境检测：检查 Flash Player 是否存在
        // 先简单读 config.toml 获取 Flash Player 路径
        string flashPlayer = "Adobe Flash Player 20.exe";
        string configPath = Path.Combine(exeDir, "config.toml");

        if (File.Exists(configPath))
        {
            try
            {
                string[] lines = File.ReadAllLines(configPath);
                foreach (string line in lines)
                {
                    string trimmed = line.Trim();
                    if (trimmed.StartsWith("flashPlayerPath", StringComparison.OrdinalIgnoreCase))
                    {
                        int eq = trimmed.IndexOf('=');
                        if (eq >= 0)
                        {
                            flashPlayer = trimmed.Substring(eq + 1).Trim().Trim('"');
                        }
                    }
                }
            }
            catch { }
        }

        // 解析 Flash Player 路径
        string flashPlayerFull = flashPlayer;
        if (!Path.IsPathRooted(flashPlayerFull))
        {
            flashPlayerFull = Path.Combine(exeDir, flashPlayerFull);
        }

        if (!File.Exists(flashPlayerFull))
        {
            ShowError(
                "找不到 Flash Player：\n" + flashPlayer +
                "\n\n请检查以下位置是否存在该文件：\n" + exeDir +
                "\n\n或在 config.toml 中修正 flashPlayerPath 配置。");
            return 1;
        }

        // 启动 .bat（隐藏命令行窗口）
        try
        {
            ProcessStartInfo psi = new ProcessStartInfo();
            psi.FileName = "cmd.exe";
            psi.Arguments = "/c \"" + batPath + "\"";
            psi.WorkingDirectory = exeDir;
            psi.UseShellExecute = false;
            psi.CreateNoWindow = true;
            Process.Start(psi);
        }
        catch (Exception ex)
        {
            ShowError("启动失败：\n" + ex.Message);
            return 1;
        }

        return 0;
    }
}
