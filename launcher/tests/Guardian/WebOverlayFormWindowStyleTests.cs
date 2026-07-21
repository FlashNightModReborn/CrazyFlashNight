using System;
using CF7Launcher.Guardian;
using Xunit;

namespace CF7Launcher.Tests.Guardian
{
    public class WebOverlayFormWindowStyleTests
    {
        private const int WsExToolWindow = 0x00000080;
        private const int WsExNoActivate = 0x08000000;
        private const int WsExTransparent = 0x00000020;
        private const int WsExLayered = 0x00080000;

        [Fact]
        public void NormalizeOverlayExStyle_PanelForeground_RepairsTransparencyKeyStyleRefresh()
        {
            // Real-runtime regression: ResumeForPanel produced 0x10080, then WinForms applied
            // CreateParams after TransparencyKey=Empty and the live HWND became 0x80100A0.
            const int unrelatedAppWindowBit = 0x00010000;
            int styleAfterWinFormsRefresh = unrelatedAppWindowBit | WsExToolWindow
                | WsExNoActivate | WsExTransparent;

            int normalized = WebOverlayForm.NormalizeOverlayExStyle(
                styleAfterWinFormsRefresh, panelMode: true, panelTakeForeground: true);

            Assert.Equal(unrelatedAppWindowBit | WsExToolWindow, normalized);
            Assert.Equal(0, normalized & (WsExLayered | WsExTransparent | WsExNoActivate));
        }

        [Fact]
        public void NormalizeOverlayExStyle_PanelRollback_KeepsNoActivateButNeverClickThrough()
        {
            int normalized = WebOverlayForm.NormalizeOverlayExStyle(
                WsExToolWindow | WsExLayered | WsExTransparent,
                panelMode: true, panelTakeForeground: false);

            Assert.Equal(WsExToolWindow | WsExNoActivate, normalized);
            Assert.Equal(0, normalized & (WsExLayered | WsExTransparent));
        }

        [Fact]
        public void NormalizeOverlayExStyle_Idle_RestoresClickThroughInvariant()
        {
            const int unrelatedAppWindowBit = 0x00010000;
            int normalized = WebOverlayForm.NormalizeOverlayExStyle(
                unrelatedAppWindowBit | WsExToolWindow,
                panelMode: false, panelTakeForeground: true);

            Assert.Equal(unrelatedAppWindowBit | WsExToolWindow | WsExNoActivate
                | WsExTransparent | WsExLayered, normalized);
        }

        [Fact]
        public void PanelFocusTarget_RequiresExactOverlayOrItsChildTree()
        {
            IntPtr overlay = new IntPtr(0x100);

            Assert.True(WebOverlayForm.IsPanelFocusTargetForeground(
                overlay, overlay, false));
            Assert.True(WebOverlayForm.IsPanelFocusTargetForeground(
                new IntPtr(0x101), overlay, true));
            Assert.False(WebOverlayForm.IsPanelFocusTargetForeground(
                new IntPtr(0x200), overlay, false));
            Assert.False(WebOverlayForm.IsPanelFocusTargetForeground(
                IntPtr.Zero, IntPtr.Zero, true));
        }
    }
}
