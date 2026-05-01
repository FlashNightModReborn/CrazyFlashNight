using CF7Launcher.Guardian;
using Xunit;

namespace CF7Launcher.Tests.Guardian
{
    public class WebOverlayFormPanelCloseTests
    {
        [Fact]
        public void ResolvePanelCloseGameCommand_StageSelect_NotifiesFlashClose()
        {
            Assert.Equal("stageSelectPanelClose", WebOverlayForm.ResolvePanelCloseGameCommand("stage-select"));
        }

        [Fact]
        public void ResolvePanelCloseGameCommand_KnownPanels_KeepExistingCloseActions()
        {
            Assert.Equal("shopPanelClose", WebOverlayForm.ResolvePanelCloseGameCommand("kshop"));
            Assert.Equal("mapPanelClose", WebOverlayForm.ResolvePanelCloseGameCommand("map"));
            Assert.Null(WebOverlayForm.ResolvePanelCloseGameCommand("help"));
            Assert.Null(WebOverlayForm.ResolvePanelCloseGameCommand("intelligence"));
        }
    }
}
