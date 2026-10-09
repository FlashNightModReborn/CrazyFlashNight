using System;
using System.Drawing;
using System.Runtime.InteropServices;

namespace CF7Launcher.Guardian
{
    public partial class WindowManager
    {
        private int _flashRenderHeight;
        private volatile int _availableFlashSourceHeight=1080;
        private volatile FlashSourceSize _flashSourceSize=new(0,0);
        private sealed record FlashSourceSize(int Width,int Height);
        [DllImport("user32.dll")] private static extern bool GetClientRect(IntPtr hwnd,out RECT rect);
        internal int AvailableFlashSourceHeight => _availableFlashSourceHeight;
        internal Size ActualFlashSourceSize { get { var size=_flashSourceSize; return new(size.Width,size.Height); } }

        // A zero budget is used only before the paired policy is attached at startup.
        public void SetFlashRenderHeight(int sourceHeight)
        {
            if (sourceHeight<0 || sourceHeight>4096) throw new ArgumentOutOfRangeException(nameof(sourceHeight));
            _flashRenderHeight=sourceHeight;
            if (_flashHwnd==IntPtr.Zero || _hostPanel==null) return;
            if (!ResizeFlashToPanelCore()) throw new InvalidOperationException("Flash 绘制尺寸调整失败");
            if (sourceHeight>0 && ActualFlashSourceSize.Height>sourceHeight+1)
                throw new InvalidOperationException("Flash 实际绘制尺寸超出本次预算");
        }
        private Size SourcePixels(Size physical)
        {
            DpiDiagnostics.TryGetWindowDpi(_flashHwnd,out uint windowDpi,out _);
            DpiDiagnostics.TryGetMonitorDpi(DpiDiagnostics.GetMonitorFromWindow(_flashHwnd),out uint dpiX,out uint dpiY);
            FlashSnapshot.ComputeCaptureSourceSize(physical.Width,physical.Height,
                DpiAwarenessBootstrap.GetEffectiveAwarenessForWindow(_flashHwnd),windowDpi,dpiX,dpiY,
                out int width,out int height);
            return new Size(width,height);
        }
        private Size ResolveFlashRenderSize()
        {
            var output=new Size(Math.Max(1,_hostPanel.Width),Math.Max(1,_hostPanel.Height));
            var source=SourcePixels(output);
            _availableFlashSourceHeight=Math.Max(1,source.Height);
            return FlashRenderBudget.Fit(output,source.Height,_flashRenderHeight);
        }
        private bool UpdateFlashRenderSize()
        {
            if (!GetClientRect(_flashHwnd,out var client)) return false;
            var source=SourcePixels(new Size(client.right-client.left,client.bottom-client.top));
            if(source.Width<1 || source.Height<1) return false;
            _flashSourceSize=new FlashSourceSize(source.Width,source.Height);
            return true;
        }
    }
    internal static class FlashRenderBudget
    {
        internal static Size Fit(Size output,int fullSourceHeight,int budget)
        {
            if(output.Width<1 || output.Height<1 || fullSourceHeight<1 || budget<0)
                throw new ArgumentOutOfRangeException(nameof(output));
            double scale=budget==0 ? 1 : Math.Min(1,(double)budget/fullSourceHeight);
            return new Size(Math.Max(1,(int)Math.Floor(output.Width*scale)),
                Math.Max(1,(int)Math.Floor(output.Height*scale)));
        }
    }
}
