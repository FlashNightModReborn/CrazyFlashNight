#nullable enable
using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Threading;
using System.Threading.Tasks;
using System.Drawing;
using System.Windows.Forms;
using System.Runtime.InteropServices;
using CF7Launcher.Guardian.InputOwnership;
using Microsoft.Web.WebView2.Core;
using Newtonsoft.Json.Linq;

namespace CF7Launcher.Guardian.UnifiedHost;

internal sealed partial class UnifiedInputHost
{
    private InputScope? pendingWebReplacement;
    private bool webExposed, webRetiring;
    private JObject? restoreAfterRetirement;
    private readonly HashSet<IntPtr> retiredFocusWindows = new();

    private async Task RetireWebEndpoint(HandoffRound round, JObject? draft)
    {
        if (webRetiring || web == null) return;
        webRetiring = true; pageReady = false; webGrant = false;
        try {
            var old = WScope;
            var focus = FocusedWebWindow();
            if (focus != IntPtr.Zero && focus != Handle && GetAncestor(focus, 2) == Handle) retiredFocusWindows.Add(focus);
            restoreAfterRetirement = livePageOpen && draft != null ? (JObject)draft.DeepClone() : null;
            if (restoreAfterRetirement == null) {
                livePageOpen = false; presentationSerial++;
                PresentModal(false, false, "no_retained_page");
            }
            var retired = web;
            retired.CoreWebView2.ProcessFailed -= OnWebProcessFailed;
            retired.CoreWebView2.WebMessageReceived -= OnWebMessage;
            retired.RootVisualTarget = null;
            retired.Close(); // retirement, not a hide or close-post acknowledgement
            web = null;
            if (webVisual != null && Marshal.IsComObject(webVisual)) Marshal.ReleaseComObject(webVisual);
            webVisual = null;
            pendingWebReplacement = old; webExposed = false;
            Log("web_controller_retired", new { scope = old, round, focus, draftRetained = restoreAfterRetirement != null });
            await AckCancel(old, round);
        } catch (Exception error) {
            Log("web_retirement_failed", error.ToString()); liveFault = true;
            await inputProbe!.OnObserver((_, _) => { coordinator!.Fail("web_retirement_failed"); return true; });
        } finally { webRetiring = false; }
    }

    private async Task ReplaceWebEndpoint()
    {
        if (!pendingWebReplacement.HasValue) return;
        var old = pendingWebReplacement.Value;
        var replacement = new InputScope("Web", checked(old.Incarnation + 1));
        bool restore = restoreAfterRetirement != null;
        bool replaced = await inputProbe!.OnObserver((_, _) => {
            if (!coordinator!.ReplaceRetiredScope(old, replacement, MScope, restore)) return false;
            WScope = replacement; return true;
        });
        if (!replaced) return;
        pageGeneration++; pageInstance = "c1.surgery." + Guid.NewGuid().ToString("N");
        await CreateWebEndpoint();
        pendingWebReplacement = null; pageReady = true;
        Log("web_controller_replaced", new { old, replacement, pageInstance, pageGeneration, restore });
    }

    private void OnWebProcessFailed(object? sender, CoreWebView2ProcessFailedEventArgs args)
    {
        // Only the live controller may fault this host; a retired controller's
        // late event must not kill its replacement's owner.
        if (web == null || !ReferenceEquals(sender, web.CoreWebView2)) {
            Log("stale_web_process_failed", new { kind = args.ProcessFailedKind.ToString() });
            return;
        }
        Log("live_fault", "current_web_process_failed:" + args.ProcessFailedKind);
        liveFault = true;
    }

    private IntPtr FocusedWebWindow()
    {
        uint thread = GetWindowThreadProcessId(Handle, out _);
        var info = new GuiThread { Size = (uint)Marshal.SizeOf<GuiThread>() };
        return GetGUIThreadInfo(thread, ref info) ? info.Focus : IntPtr.Zero;
    }
    [StructLayout(LayoutKind.Sequential)] private struct GuiThread {
        public uint Size, Flags;
        public IntPtr Active, Focus, Capture, MenuOwner, MoveSize, Caret;
        public ClientRect CaretRect;
    }
    [DllImport("user32.dll")] private static extern uint GetWindowThreadProcessId(IntPtr hwnd, out uint pid);
    [DllImport("user32.dll")] private static extern bool GetGUIThreadInfo(uint thread, ref GuiThread info);
    [DllImport("user32.dll")] private static extern IntPtr GetAncestor(IntPtr hwnd, uint flags);
}
