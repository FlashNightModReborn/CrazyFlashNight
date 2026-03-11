Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$flash = Get-Process -Name Flash -ErrorAction SilentlyContinue | Select-Object -First 1
if (-not $flash) { Write-Host 'Flash not running'; exit 1 }

Add-Type -ReferencedAssemblies System.Drawing -TypeDefinition @'
using System;
using System.Drawing;
using System.Drawing.Imaging;
using System.Runtime.InteropServices;
using System.Threading;

public class Win32Capture {
    [DllImport("user32.dll")]
    public static extern bool SetForegroundWindow(IntPtr hWnd);

    [DllImport("user32.dll")]
    public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);

    [DllImport("user32.dll")]
    public static extern bool GetWindowRect(IntPtr hWnd, out RECT lpRect);

    [DllImport("dwmapi.dll")]
    public static extern int DwmGetWindowAttribute(IntPtr hwnd, int dwAttribute, out RECT pvAttribute, int cbAttribute);

    [StructLayout(LayoutKind.Sequential)]
    public struct RECT { public int Left, Top, Right, Bottom; }

    public static Bitmap CaptureWindow(IntPtr hwnd) {
        // SW_RESTORE = 9, restore if minimized
        ShowWindow(hwnd, 9);
        SetForegroundWindow(hwnd);
        // Wait for window to be fully rendered in foreground
        Thread.Sleep(500);

        RECT rect;
        int hr = DwmGetWindowAttribute(hwnd, 9, out rect, Marshal.SizeOf(typeof(RECT)));
        if (hr != 0) {
            GetWindowRect(hwnd, out rect);
        }

        int w = rect.Right - rect.Left;
        int h = rect.Bottom - rect.Top;
        if (w <= 0 || h <= 0) return null;

        Bitmap bmp = new Bitmap(w, h);
        using (Graphics g = Graphics.FromImage(bmp)) {
            g.CopyFromScreen(rect.Left, rect.Top, 0, 0, new Size(w, h));
        }
        return bmp;
    }
}
'@

$hwnd = $flash.MainWindowHandle
Write-Host "Flash HWND: $hwnd"

$bmp = [Win32Capture]::CaptureWindow($hwnd)
if ($null -eq $bmp) { Write-Host 'Failed to capture window'; exit 1 }

Write-Host "Captured: $($bmp.Width)x$($bmp.Height)"

$outPath = Join-Path $PSScriptRoot 'screenshot.png'
$bmp.Save($outPath, [System.Drawing.Imaging.ImageFormat]::Png)
$bmp.Dispose()
Write-Host "Saved to: $outPath"
