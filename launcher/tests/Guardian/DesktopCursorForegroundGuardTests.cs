using System;
using CF7Launcher.Guardian;
using Xunit;

namespace CF7Launcher.Tests.Guardian
{
    public class DesktopCursorForegroundGuardTests
    {
        [Fact]
        public void SameProcessForeground_IsAccepted()
        {
            Assert.True(Classify(
                new IntPtr(0x01), 100, false, false, false, false)
                .IsSessionOwned);
        }

        [Fact]
        public void EmbeddedChildForeground_IsAcceptedEvenWithDifferentPid()
        {
            Assert.True(Classify(
                new IntPtr(0x02), 200, false, true, false, false)
                .IsSessionOwned);
        }

        [Fact]
        public void ExternalForeground_IsRejected()
        {
            Assert.False(Classify(
                new IntPtr(0x03), 200, false, false, false, false)
                .IsSessionOwned);
        }

        [Fact]
        public void MissingPid_WithoutOwnerTree_IsRejected()
        {
            Assert.False(Classify(
                new IntPtr(0x04), 0, false, false, false, false)
                .IsSessionOwned);
        }

        [Fact]
        public void SessionClassifier_DistinguishesNullGuardianOwnerOverlayFlashAndExternal()
        {
            WebOverlayForm.SessionForegroundSnapshot missing = Classify(
                IntPtr.Zero, 0, false, false, false, false);
            Assert.Equal(WebOverlayForm.SessionForegroundKind.Null, missing.Kind);
            Assert.Equal("null", missing.OwnershipLabel);
            Assert.False(missing.IsSessionOwned);

            WebOverlayForm.SessionForegroundSnapshot guardian = Classify(
                new IntPtr(0x10), 100, false, false, false, false);
            Assert.Equal(WebOverlayForm.SessionForegroundKind.GuardianProcess, guardian.Kind);
            Assert.True(guardian.IsSessionOwned);

            WebOverlayForm.SessionForegroundSnapshot owner = Classify(
                new IntPtr(0x11), 100, true, false, false, false);
            Assert.Equal(WebOverlayForm.SessionForegroundKind.Owner, owner.Kind);
            Assert.True(owner.IsSessionOwned);

            WebOverlayForm.SessionForegroundSnapshot embeddedFlash = Classify(
                new IntPtr(0x12), 200, false, true, false, false);
            Assert.Equal(WebOverlayForm.SessionForegroundKind.OwnerTree, embeddedFlash.Kind);
            Assert.True(embeddedFlash.IsSessionOwned);

            WebOverlayForm.SessionForegroundSnapshot overlay = Classify(
                new IntPtr(0x13), 100, false, false, true, false);
            Assert.Equal(WebOverlayForm.SessionForegroundKind.Overlay, overlay.Kind);
            Assert.True(overlay.IsSessionOwned);

            WebOverlayForm.SessionForegroundSnapshot overlayChild = Classify(
                new IntPtr(0x14), 300, false, false, false, true);
            Assert.Equal(WebOverlayForm.SessionForegroundKind.OverlayTree, overlayChild.Kind);
            Assert.True(overlayChild.IsSessionOwned);

            WebOverlayForm.SessionForegroundSnapshot external = Classify(
                new IntPtr(0x15), 200, false, false, false, false);
            Assert.Equal(WebOverlayForm.SessionForegroundKind.External, external.Kind);
            Assert.Equal("external", external.OwnershipLabel);
            Assert.False(external.IsSessionOwned);
        }

        [Fact]
        public void PanelCloseHandoffClassifier_DistinguishesSessionTransferExternalAndNull()
        {
            WebOverlayForm.SessionForegroundSnapshot overlay = Classify(
                new IntPtr(0x20), 100, false, false, true, false);
            WebOverlayForm.SessionForegroundSnapshot flash = Classify(
                new IntPtr(0x21), 200, false, true, false, false);
            WebOverlayForm.SessionForegroundSnapshot external = Classify(
                new IntPtr(0x22), 300, false, false, false, false);
            WebOverlayForm.SessionForegroundSnapshot missing = Classify(
                IntPtr.Zero, 0, false, false, false, false);

            Assert.Equal("self_hide_session_transfer_candidate",
                WebOverlayForm.ClassifyPanelCloseHandoffTransition(overlay, flash));
            Assert.Equal("external",
                WebOverlayForm.ClassifyPanelCloseHandoffTransition(overlay, external));
            Assert.Equal("null",
                WebOverlayForm.ClassifyPanelCloseHandoffTransition(overlay, missing));
            Assert.Equal("session_stable",
                WebOverlayForm.ClassifyPanelCloseHandoffTransition(overlay, overlay));
        }

        private static WebOverlayForm.SessionForegroundSnapshot Classify(
            IntPtr hwnd,
            uint pid,
            bool isOwner,
            bool inOwnerTree,
            bool isOverlay,
            bool inOverlayTree)
        {
            return WebOverlayForm.ClassifySessionForeground(
                hwnd,
                pid,
                guardianPid: 100,
                foregroundIsOwner: isOwner,
                foregroundInOwnerTree: inOwnerTree,
                foregroundIsOverlay: isOverlay,
                foregroundInOverlayTree: inOverlayTree);
        }
    }
}
