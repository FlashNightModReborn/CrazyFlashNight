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
