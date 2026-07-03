using CF7Launcher.Guardian;
using Newtonsoft.Json.Linq;
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
            Assert.Equal("taskPanelClose", WebOverlayForm.ResolvePanelCloseGameCommand("tasks"));
            Assert.Null(WebOverlayForm.ResolvePanelCloseGameCommand("help"));
            Assert.Null(WebOverlayForm.ResolvePanelCloseGameCommand("intelligence"));
            Assert.Null(WebOverlayForm.ResolvePanelCloseGameCommand("mercs"));
            Assert.Null(WebOverlayForm.ResolvePanelCloseGameCommand("pets"));
            Assert.Null(WebOverlayForm.ResolvePanelCloseGameCommand("team"));
            Assert.Null(WebOverlayForm.ResolvePanelCloseGameCommand("arena"));
        }

        [Fact]
        public void ShouldReturnBaseOnPanelClose_OnlyArenaReturnBaseFlagTriggers()
        {
            Assert.True(WebOverlayForm.ShouldReturnBaseOnPanelClose(
                "arena",
                JObject.Parse("{\"returnBase\":true}")));

            Assert.False(WebOverlayForm.ShouldReturnBaseOnPanelClose(
                "arena",
                JObject.Parse("{}")));
            Assert.False(WebOverlayForm.ShouldReturnBaseOnPanelClose(
                "arena",
                JObject.Parse("{\"returnBase\":false}")));
            Assert.False(WebOverlayForm.ShouldReturnBaseOnPanelClose(
                "stage-select",
                JObject.Parse("{\"returnBase\":true}")));
            Assert.False(WebOverlayForm.ShouldReturnBaseOnPanelClose("arena", null));
        }
    }
}
