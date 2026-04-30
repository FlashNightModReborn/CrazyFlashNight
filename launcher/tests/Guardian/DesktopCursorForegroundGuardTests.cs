using CF7Launcher.Guardian;
using Xunit;

namespace CF7Launcher.Tests.Guardian
{
    public class DesktopCursorForegroundGuardTests
    {
        [Fact]
        public void SameProcessForeground_IsAccepted()
        {
            Assert.True(WebOverlayForm.IsDesktopCursorForegroundAccepted(
                foregroundPid: 100,
                ourPid: 100,
                foregroundInOwnerTree: false));
        }

        [Fact]
        public void EmbeddedChildForeground_IsAcceptedEvenWithDifferentPid()
        {
            Assert.True(WebOverlayForm.IsDesktopCursorForegroundAccepted(
                foregroundPid: 200,
                ourPid: 100,
                foregroundInOwnerTree: true));
        }

        [Fact]
        public void ExternalForeground_IsRejected()
        {
            Assert.False(WebOverlayForm.IsDesktopCursorForegroundAccepted(
                foregroundPid: 200,
                ourPid: 100,
                foregroundInOwnerTree: false));
        }

        [Fact]
        public void MissingPid_WithoutOwnerTree_IsRejected()
        {
            Assert.False(WebOverlayForm.IsDesktopCursorForegroundAccepted(
                foregroundPid: 0,
                ourPid: 100,
                foregroundInOwnerTree: false));
        }
    }
}
