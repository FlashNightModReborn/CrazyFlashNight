using CF7Launcher.Guardian;
using Newtonsoft.Json.Linq;
using Xunit;

namespace CF7Launcher.Tests.Guardian
{
    public class WebOverlayFormPanelCloseTests
    {
        [Fact]
        public void FormatPanelEnvelopeLog_MinigameSessionRedactsWholePayload()
        {
            const string secret = "one-time-capability";
            string json = "{\"cmd\":\"minigame_session\",\"payload\":{\"game\":\"lockbox\",\"capability\":\""
                + secret + "\"}}";

            string line = WebOverlayForm.FormatPanelEnvelopeLog("minigame_session", json);

            Assert.Equal("[Panel] HandlePanelMessage: cmd=minigame_session payload=redacted", line);
            Assert.DoesNotContain(secret, line);
        }

        [Fact]
        public void FormatPanelEnvelopeLog_NonMinigameKeepsDiagnosticEnvelope()
        {
            const string json = "{\"cmd\":\"ready\"}";

            Assert.Equal("[Panel] HandlePanelMessage: " + json,
                WebOverlayForm.FormatPanelEnvelopeLog("ready", json));
        }

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
            Assert.Null(WebOverlayForm.ResolvePanelCloseGameCommand("hairdresser"));
        }

        [Fact]
        public void HairdresserDomain_RoutesExplicitlyWhileCloseKeepsPriority()
        {
            Assert.Equal(
                WebOverlayForm.PanelDomainRoute.Hairdresser,
                WebOverlayForm.ResolvePanelDomainRoute("snapshot", "hairdresser"));
            Assert.Equal(
                WebOverlayForm.PanelDomainRoute.Close,
                WebOverlayForm.ResolvePanelDomainRoute("close", "hairdresser"));
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

        [Fact]
        public void ForeignCloseCannotTearDownActiveTrackedLootPanel()
        {
            JObject foreign = JObject.Parse(
                "{\"type\":\"panel\",\"panel\":\"kshop\",\"cmd\":\"close\"}");
            JObject exactLoot = JObject.Parse(
                "{\"type\":\"panel\",\"panel\":\"loot\",\"cmd\":\"close\"}");

            Assert.True(WebOverlayForm.ShouldRejectForeignCloseWhileLootActive(
                foreign, "loot"));
            Assert.False(WebOverlayForm.ShouldRejectForeignCloseWhileLootActive(
                exactLoot, "loot"));
            Assert.False(WebOverlayForm.ShouldRejectForeignCloseWhileLootActive(
                foreign, "kshop"));
            Assert.False(WebOverlayForm.ShouldRejectForeignCloseWhileLootActive(
                foreign, null));
        }
    }
}
