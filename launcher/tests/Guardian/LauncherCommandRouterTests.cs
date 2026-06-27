using System.Collections.Generic;
using System.Windows.Forms;
using CF7Launcher.Guardian;
using Xunit;

namespace CF7Launcher.Tests.Guardian
{
    /// <summary>
    /// Router 单测。Flag OFF 路径（_panelHost == null）触发 PostToWeb fallback；
    /// Flag ON 路径无法在单测里覆盖（PanelHostController 依赖 Form），通过集成测试 + 手测覆盖。
    /// </summary>
    public class LauncherCommandRouterTests
    {
        private class Capture
        {
            public List<Keys> SentKeys = new List<Keys>();
            public List<string> Posts = new List<string>();
            public List<string> ActivePanels = new List<string>();
            public List<bool> StateCallbacks = new List<bool>();
            public int Fullscreen, Log, Exit;
        }

        private static LauncherCommandRouter MakeRouter(Capture c)
        {
            return new LauncherCommandRouter(
                socketServer: null,
                onSendKey: k => c.SentKeys.Add(k),
                onToggleFullscreen: () => c.Fullscreen++,
                onToggleLog: () => c.Log++,
                onForceExit: () => c.Exit++,
                postToWeb: s => c.Posts.Add(s),
                onPanelStateChanged: b => c.StateCallbacks.Add(b),
                setActivePanel: name => c.ActivePanels.Add(name));
        }

        [Fact]
        public void KeyDispatch_QWRPO_ForwardedAsKeys()
        {
            Capture c = new Capture();
            LauncherCommandRouter r = MakeRouter(c);
            r.Dispatch("Q");
            r.Dispatch("W");
            r.Dispatch("R");
            r.Dispatch("P");
            r.Dispatch("O");
            Assert.Equal(new[] { Keys.Q, Keys.W, Keys.R, Keys.P, Keys.O }, c.SentKeys);
        }

        [Fact]
        public void F_TogglesFullscreen_NotSentAsKey()
        {
            Capture c = new Capture();
            LauncherCommandRouter r = MakeRouter(c);
            r.Dispatch("F");
            Assert.Equal(1, c.Fullscreen);
            Assert.Empty(c.SentKeys);
        }

        [Fact]
        public void LOG_TogglesLog()
        {
            Capture c = new Capture();
            LauncherCommandRouter r = MakeRouter(c);
            r.Dispatch("LOG");
            Assert.Equal(1, c.Log);
        }

        [Fact]
        public void EXIT_AndExitConfirm_ForceExit()
        {
            Capture c = new Capture();
            LauncherCommandRouter r = MakeRouter(c);
            r.Dispatch("EXIT");
            r.Dispatch("EXIT_CONFIRM");
            Assert.Equal(2, c.Exit);
        }

        [Fact]
        public void HELP_OpenPanelFallback_PostsPanelCmdOpen()
        {
            Capture c = new Capture();
            LauncherCommandRouter r = MakeRouter(c);
            r.Dispatch("HELP");
            Assert.Single(c.Posts);
            Assert.Contains("\"panel\":\"help\"", c.Posts[0]);
            Assert.Contains("\"cmd\":\"open\"", c.Posts[0]);
            Assert.Equal(new[] { "help" }, c.ActivePanels);
            Assert.Equal(new[] { true }, c.StateCallbacks);
        }

        [Fact]
        public void GOBANG_TEST_OpenPanelFallback_IncludesInitData()
        {
            Capture c = new Capture();
            LauncherCommandRouter r = MakeRouter(c);
            r.Dispatch("GOBANG_TEST");
            Assert.Single(c.Posts);
            Assert.Contains("\"panel\":\"gobang\"", c.Posts[0]);
            Assert.Contains("\"initData\"", c.Posts[0]);
            Assert.Contains("\"ruleset\":\"casual\"", c.Posts[0]);
        }

        [Fact]
        public void INTELLIGENCE_TEST_OpenPanelFallback_IncludesFixtureInitData()
        {
            Capture c = new Capture();
            LauncherCommandRouter r = MakeRouter(c);
            r.Dispatch("INTELLIGENCE_TEST");
            Assert.Single(c.Posts);
            Assert.Contains("\"panel\":\"intelligence\"", c.Posts[0]);
            Assert.Contains("\"itemName\":\"资料\"", c.Posts[0]);
            Assert.Contains("\"value\":99", c.Posts[0]);
            Assert.Contains("\"decryptLevel\":10", c.Posts[0]);
        }

        [Fact]
        public void INTELLIGENCE_OpenPanelFallback_UsesRuntimeProdInitData()
        {
            Capture c = new Capture();
            LauncherCommandRouter r = MakeRouter(c);
            r.Dispatch("INTELLIGENCE");
            Assert.Single(c.Posts);
            Assert.Contains("\"panel\":\"intelligence\"", c.Posts[0]);
            Assert.Contains("\"mode\":\"prod\"", c.Posts[0]);
            Assert.Contains("\"source\":\"runtime\"", c.Posts[0]);
            Assert.Contains("\"debug\":false", c.Posts[0]);
            Assert.Equal(new[] { "intelligence" }, c.ActivePanels);
            Assert.Equal(new[] { true }, c.StateCallbacks);
        }

        [Fact]
        public void NewTaskUi_WhenFlashUnavailable_PostsUnavailableToast()
        {
            Capture c = new Capture();
            LauncherCommandRouter r = MakeRouter(c);
            r.Dispatch("NEW_TASK_UI");

            Assert.Single(c.Posts);
            Assert.Contains("任务面板暂时不可用", c.Posts[0]);
            Assert.Empty(c.ActivePanels);
            Assert.Empty(c.StateCallbacks);
        }

        [Theory]
        [InlineData("TEAM")]
        [InlineData("PETS")]
        [InlineData("MERCS")]
        public void TeamEntries_WhenFlashUnavailable_PostUnavailableToast(string key)
        {
            Capture c = new Capture();
            LauncherCommandRouter r = MakeRouter(c);

            r.Dispatch(key);

            Assert.Single(c.Posts);
            Assert.Contains("战队面板暂时不可用", c.Posts[0]);
            Assert.Empty(c.ActivePanels);
        }

        [Fact]
        public void RequestOpenPanel_Map_RoutesToOpenMapPanel()
        {
            Capture c = new Capture();
            LauncherCommandRouter r = MakeRouter(c);
            r.RequestOpenPanel("map", "as2_request", "page-1");
            Assert.Single(c.Posts);
            Assert.Contains("\"panel\":\"map\"", c.Posts[0]);
            Assert.Contains("\"page\":\"page-1\"", c.Posts[0]);
            Assert.Contains("\"source\":\"as2_request\"", c.Posts[0]);
        }

        [Fact]
        public void RequestOpenPanel_StageSelect_RoutesRuntimeInitData()
        {
            Capture c = new Capture();
            LauncherCommandRouter r = MakeRouter(c);
            r.RequestOpenPanel("stage-select", "as2_base_gate", null, "基地门口");
            Assert.Single(c.Posts);
            Assert.Contains("\"panel\":\"stage-select\"", c.Posts[0]);
            Assert.Contains("\"mode\":\"runtime\"", c.Posts[0]);
            Assert.Contains("\"fixture\":\"mixed\"", c.Posts[0]);
            Assert.Contains("\"frameLabel\":\"基地门口\"", c.Posts[0]);
            Assert.Contains("\"returnFrameLabel\":\"基地门口\"", c.Posts[0]);
            Assert.Contains("\"source\":\"as2_base_gate\"", c.Posts[0]);
            Assert.Contains("\"debug\":false", c.Posts[0]);
        }

        [Fact]
        public void RequestOpenPanel_StageSelect_CarriesExplicitReturnFrame()
        {
            Capture c = new Capture();
            LauncherCommandRouter r = MakeRouter(c);
            r.RequestOpenPanel("stage-select", "as2_legacy_stage_gate", null, "黑铁会总部", "基地车库");
            Assert.Single(c.Posts);
            Assert.Contains("\"frameLabel\":\"黑铁会总部\"", c.Posts[0]);
            Assert.Contains("\"returnFrameLabel\":\"基地车库\"", c.Posts[0]);
        }

        [Fact]
        public void RequestOpenPanel_Tasks_RoutesToOpenTasksPanelWithInitData()
        {
            // 副本任务（委托任务）入口回归：NPC openWebDungeon 发 panel_request panel="tasks"，
            // 必须开 tasks 面板并透传 initData {view,taskId}。曾因 RequestOpenPanel 无 tasks 分支
            // 静默丢弃（"[Router] RequestOpenPanel unsupported panel=tasks"），NPC 点击无反应。
            Capture c = new Capture();
            LauncherCommandRouter r = MakeRouter(c);
            r.RequestOpenPanel("tasks", "npc_dungeon", null, null, null, null, null, "{\"view\":\"dungeon\",\"taskId\":20052}");
            Assert.Single(c.Posts);
            Assert.Contains("\"panel\":\"tasks\"", c.Posts[0]);
            Assert.Contains("\"view\":\"dungeon\"", c.Posts[0]);
            Assert.Contains("\"taskId\":20052", c.Posts[0]);
            Assert.Contains("\"source\":\"npc_dungeon\"", c.Posts[0]);
        }

        [Fact]
        public void RequestOpenPanel_Team_RoutesToOpenTeamPanelWithInitData()
        {
            // 世界内雇佣入口：NPC openWebHire 发 panel_request panel="team"，必须开 team 面板并
            // 透传 initData {view:"hire",kind,npcId,initialTab}。无 team 分支会静默丢弃（unsupported panel）。
            Capture c = new Capture();
            LauncherCommandRouter r = MakeRouter(c);
            r.RequestOpenPanel("team", "npc_hire", null, null, null, null, null, "{\"view\":\"hire\",\"kind\":\"merc\",\"npcId\":\"敌人123\",\"initialTab\":\"mercenary\"}");
            Assert.Single(c.Posts);
            Assert.Contains("\"panel\":\"team\"", c.Posts[0]);
            Assert.Contains("\"view\":\"hire\"", c.Posts[0]);
            Assert.Contains("\"kind\":\"merc\"", c.Posts[0]);
            Assert.Contains("\"source\":\"npc_hire\"", c.Posts[0]);
        }

        [Fact]
        public void RequestOpenPanel_Unknown_NoPost()
        {
            Capture c = new Capture();
            LauncherCommandRouter r = MakeRouter(c);
            r.RequestOpenPanel("nonexistent", "src", null);
            Assert.Empty(c.Posts);
        }

        [Fact]
        public void EmptyKey_SilentlyIgnored()
        {
            Capture c = new Capture();
            LauncherCommandRouter r = MakeRouter(c);
            r.Dispatch("");
            r.Dispatch(null);
            Assert.Empty(c.SentKeys);
            Assert.Empty(c.Posts);
        }

        [Fact]
        public void UnknownKey_SilentlyIgnored()
        {
            Capture c = new Capture();
            LauncherCommandRouter r = MakeRouter(c);
            r.Dispatch("NONEXISTENT_KEY");
            Assert.Empty(c.SentKeys);
            Assert.Empty(c.Posts);
        }
    }
}
