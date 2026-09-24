param(
    [int]$TargetProcessId = 0,
    [long]$WindowHandle = 0,
    [string]$OutputPath = '',
    [switch]$NoActivate
)
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

if ($TargetProcessId -gt 0) {
    $flash = Get-Process -Id $TargetProcessId
} else {
    $targets = @(Get-Process -Name Flash -ErrorAction SilentlyContinue)
    if ($targets.Count -ne 1) { throw 'Specify -TargetProcessId when there is not exactly one Flash process.' }
    $flash = $targets[0]
    $TargetProcessId = $flash.Id
}

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
    public static extern IntPtr GetForegroundWindow();

    [DllImport("user32.dll")]
    public static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint processId);

    [DllImport("user32.dll")]
    public static extern bool IsIconic(IntPtr hWnd);

    [DllImport("user32.dll")]
    public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);

    [DllImport("user32.dll")]
    public static extern bool GetWindowRect(IntPtr hWnd, out RECT lpRect);

    [DllImport("dwmapi.dll")]
    public static extern int DwmGetWindowAttribute(IntPtr hwnd, int dwAttribute, out RECT pvAttribute, int cbAttribute);

    [StructLayout(LayoutKind.Sequential)]
    public struct RECT { public int Left, Top, Right, Bottom; }

    public static Bitmap CaptureWindow(IntPtr hwnd, bool activate) {
        if (activate) {
            if (IsIconic(hwnd)) ShowWindow(hwnd, 9);
            SetForegroundWindow(hwnd);
        }
        // Wait for window to be fully rendered in foreground
        Thread.Sleep(500);
        if (activate && GetForegroundWindow() != hwnd)
            throw new InvalidOperationException("Exact target did not become foreground; no screenshot accepted.");

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
        if (activate && GetForegroundWindow() != hwnd) {
            bmp.Dispose();
            throw new InvalidOperationException("Foreground changed during capture; no screenshot accepted.");
        }
        return bmp;
    }
}
'@

$hwnd = if ($WindowHandle -ne 0) { [IntPtr]$WindowHandle } else { $flash.MainWindowHandle }
[uint32]$ownerId = 0
[void][Win32Capture]::GetWindowThreadProcessId($hwnd, [ref]$ownerId)
if ($hwnd -eq [IntPtr]::Zero -or $ownerId -ne $TargetProcessId) { throw 'Window does not belong to the exact target process.' }
Write-Host "Target PID: $TargetProcessId HWND: $hwnd"

$bmp = [Win32Capture]::CaptureWindow($hwnd, -not $NoActivate)
if ($null -eq $bmp) { Write-Host 'Failed to capture window'; exit 1 }

Write-Host "Captured: $($bmp.Width)x$($bmp.Height)"

$outPath = if ($OutputPath) { [IO.Path]::GetFullPath($OutputPath) } else { Join-Path $PSScriptRoot 'screenshot.png' }
try { $bmp.Save($outPath, [System.Drawing.Imaging.ImageFormat]::Png) } finally { $bmp.Dispose() }
@{ utc = [DateTime]::UtcNow.ToString('o'); pid = $TargetProcessId; hwnd = $hwnd.ToInt64();
   foreground = [Win32Capture]::GetForegroundWindow().ToInt64(); activationRequested = -not $NoActivate;
   captureKind = 'screen_rectangle'; foregroundVerified = -not $NoActivate; occlusionNotExcluded = $true
} | ConvertTo-Json | Set-Content -LiteralPath ($outPath + '.json') -Encoding UTF8
Write-Host "Saved to: $outPath"
