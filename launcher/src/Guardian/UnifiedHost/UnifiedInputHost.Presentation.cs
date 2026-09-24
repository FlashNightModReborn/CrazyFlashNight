#nullable enable
using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Threading;
using System.Threading.Tasks;
using System.Drawing;
using System.Windows.Forms;
using System.Drawing.Imaging;
using System.Runtime.InteropServices;
using CF7Launcher.Guardian.InputOwnership;
using Microsoft.Web.WebView2.Core;

namespace CF7Launcher.Guardian.UnifiedHost;

internal sealed partial class UnifiedInputHost
{
    // Presentation survives controller retirement. Neither a bitmap nor a
    // render receipt is an input owner/cancellation acknowledgement.
    private bool modalPresentation, frozenPresentation;
    private long presentationSerial;

    private void PresentModal(bool modal, bool frozen, string reason)
    {
        modalPresentation = modal; frozenPresentation = modal && frozen;
        ResizePresentation();
        Log("presentation", new { modal, frozen = frozenPresentation, reason, pageInstance, pageGeneration, round = liveRound });
    }
    private void ResizePresentation()
    {
        if (compositionScene == null) return;
        compositionScene.Presentation(modalPresentation, frozenPresentation, Math.Max(1, ClientSize.Width), Math.Max(1, ClientSize.Height));
    }
    private async Task FreezePresentation(HandoffRound round)
    {
        presentationSerial++;
        if (livePageOpen) pageReady = false;
        if (!livePageOpen || !modalPresentation || frozenPresentation || web == null) return;
        var endpoint = web;
        // Shut the real page gate before capturing. Do not close Panels yet:
        // its cleanup makes the transparent Web visual expose the world.
        LiveWeb("freeze_view", round);
        using var png = await CapturePresentation(endpoint);
        if (closing || !livePageOpen || !ReferenceEquals(endpoint, web)) return;
        png.Position = 0;
        using var source = Image.FromStream(png);
        using var bitmap = new Bitmap(source.Width, source.Height, PixelFormat.Format32bppPArgb);
        using (var graphics = Graphics.FromImage(bitmap)) {
            graphics.Clear(Color.FromArgb(16, 24, 32));
            graphics.DrawImageUnscaled(source, 0, 0);
        }
        var bits = bitmap.LockBits(new Rectangle(Point.Empty, bitmap.Size), ImageLockMode.ReadOnly, PixelFormat.Format32bppPArgb);
        try { compositionScene!.Snapshot(bits.Scan0, bitmap.Width, bitmap.Height, bits.Stride); }
        finally { bitmap.UnlockBits(bits); }
        PresentModal(true, true, "before_page_cleanup");
    }
    private async Task RevealPresentation(HandoffRound round)
    {
        var endpoint = web; long serial = presentationSerial;
        if (endpoint == null || !livePageOpen) return;
        try {
            // page_ready follows DOM restoration and two animation frames.
            // CapturePreview observes browser painting, not DWM scanout. The
            // independent opaque backdrop remains for the entire modal lifetime.
            using var png = await CapturePresentation(endpoint);
            if (closing || inputProbe == null) return;
            var current = await inputProbe!.OnObserver((_, _) => coordinator!.Round);
            if (closing || !ReferenceEquals(endpoint, web) || serial != presentationSerial || current != round || !livePageOpen) {
                Log("presentation_stale_ready", new { serial, presentationSerial, round }); return;
            }
            if (png.Length == 0) throw new InvalidDataException("Empty restored Web preview");
            PresentModal(true, false, "restored_page_painted");
            pageReady = true;
        } catch (Exception error) {
            if (closing || !ReferenceEquals(endpoint, web)) return;
            Log("presentation_failed", error.ToString()); liveFault = true;
            await inputProbe!.OnObserver((_, _) => { coordinator!.Fail("presentation_failed"); return true; });
        }
    }
    private static async Task<MemoryStream> CapturePresentation(CoreWebView2CompositionController endpoint)
    {
        var png = new MemoryStream();
        Task? captureTask = null;
        try {
            captureTask = endpoint.CoreWebView2.CapturePreviewAsync(CoreWebView2CapturePreviewImageFormat.Png, png);
            await captureTask.WaitAsync(TimeSpan.FromSeconds(5));
            return png;
        } catch {
            // A timed-out browser may still own the stream. Dispose after its
            // callback, but never let a late preview open the input gate.
            if (captureTask == null || captureTask.IsCompleted) png.Dispose();
            else _ = captureTask.ContinueWith(done => { _ = done.Exception; png.Dispose(); }, TaskScheduler.Default);
            throw;
        }
    }
}
