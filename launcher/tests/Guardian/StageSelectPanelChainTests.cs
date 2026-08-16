using System;
using System.Collections.Generic;
using CF7Launcher.Guardian;
using CF7Launcher.Tasks;
using Newtonsoft.Json.Linq;
using Xunit;

namespace CF7Launcher.Tests.Guardian
{
    /// <summary>
    /// Map → stage-select → arena → 返回 全链会话测试：PanelHost returnTo 栈语义 +
    /// P3 实例守卫（关闭观察器驱动 StageSelectTask 清 pending / 解绑）。
    /// AS2 侧锚点：StageSelectPanelService.requestOpenArenaPanel 的 returnTo="stage-select"
    /// 与 returnToInitData（frameLabel/returnFrameLabel）；本层验证 Host 侧的 reopen 承诺。
    /// </summary>
    public sealed class StageSelectPanelChainTests
    {
        private sealed class Harness : IDisposable
        {
            internal readonly Queue<Action> Pumps = new Queue<Action>();
            internal readonly PanelHostController Host;
            internal readonly List<KeyValuePair<string, string>> CloseEvents =
                new List<KeyValuePair<string, string>>();
            internal readonly List<KeyValuePair<string, string>> OpenInitData =
                new List<KeyValuePair<string, string>>();

            internal Harness()
            {
                Host = new PanelHostController(
                    action => Pumps.Enqueue(action),
                    action => action());
                Host.SetPanelCloseObserver(delegate(string name, string instance)
                {
                    CloseEvents.Add(new KeyValuePair<string, string>(name, instance));
                });
                // 生产路径由 BuildPanelOpenPayload 把 panelInstanceId 注入 initData；
                // 测试泵路径只回调 enricher，这里按同语义记录 (panelInstanceId, initDataJson)。
                Host.SetInitDataEnricher(delegate(string name, string initDataJson, string instanceId)
                {
                    OpenInitData.Add(new KeyValuePair<string, string>(instanceId, initDataJson ?? ""));
                    return initDataJson;
                });
            }

            internal void Pump()
            {
                Action action = Assert.Single(Pumps);
                Pumps.Clear();
                action();
            }

            internal string Open(string name, string initDataJson)
            {
                Assert.True(Host.TryOpenPanel(name, initDataJson, null, null));
                Pump();
                Assert.Equal(name, Host.ActivePanelName);
                return Host.ActivePanelInstanceId;
            }

            public void Dispose()
            {
                Host.Dispose();
            }
        }

        [Fact]
        public void ArenaReturnToReopensStageSelectWithFreshInstance()
        {
            using var harness = new Harness();
            string stageSelectInit =
                "{\"mode\":\"runtime\",\"fixture\":\"mixed\",\"frameLabel\":\"基地车库\","
                + "\"returnFrameLabel\":\"基地门口\",\"debug\":false,\"source\":\"as2_base_gate\"}";
            string firstStageSelect = harness.Open("stage-select", stageSelectInit);

            // AS2 角斗场重定向锚点（requestOpenArenaPanel）：returnTo + returnToInitData。
            string returnInit =
                "{\"mode\":\"runtime\",\"fixture\":\"mixed\",\"frameLabel\":\"基地车库\","
                + "\"returnFrameLabel\":\"基地门口\",\"debug\":false,\"source\":\"arena_return\"}";
            Assert.True(harness.Host.TryOpenPanel(
                "arena", "{\"difficulty\":\"冒险\"}", "stage-select", returnInit));
            harness.Pump();
            Assert.Equal("arena", harness.Host.ActivePanelName);
            string arenaInstance = harness.Host.ActivePanelInstanceId;
            // 开 arena 先 DoClose stage-select：观察器按精确实例上报。
            Assert.Contains(
                new KeyValuePair<string, string>("stage-select", firstStageSelect),
                harness.CloseEvents);

            // 关闭 arena → pop returnTo 栈 → 以 returnToInitData 重开 stage-select（新实例）。
            harness.Host.ClosePanel();
            harness.Pump();
            Assert.Equal("stage-select", harness.Host.ActivePanelName);
            string secondStageSelect = harness.Host.ActivePanelInstanceId;
            Assert.NotEqual(firstStageSelect, secondStageSelect);
            var reopen = Assert.Single(
                harness.OpenInitData.FindAll(
                    entry => entry.Key == secondStageSelect));
            Assert.Equal(returnInit, reopen.Value);
            Assert.Contains(
                new KeyValuePair<string, string>("arena", arenaInstance),
                harness.CloseEvents);

            // 再关 stage-select：栈已空，不得再次 reopen，也不得误关其它面板。
            harness.Host.ClosePanel();
            harness.Pump();
            Assert.False(harness.Host.IsPanelOpen);
            Assert.Null(harness.Host.ActivePanelName);
            Assert.Equal(3, harness.CloseEvents.Count);
            Assert.Equal(
                new KeyValuePair<string, string>("stage-select", secondStageSelect),
                harness.CloseEvents[2]);
        }

        [Fact]
        public void ReturnStackDoesNotLeakAcrossIndependentPanels()
        {
            using var harness = new Harness();
            harness.Open("stage-select", "{\"mode\":\"runtime\",\"frameLabel\":\"基地门口\"}");
            // 地图二级动作链的另一半：stage-select 之后独立打开 map 不携带 returnTo，
            // 关闭 map 不得触发任何 reopen。
            harness.Open("map", "{\"page\":\"base\"}");
            harness.Host.ClosePanel();
            harness.Pump();
            Assert.False(harness.Host.IsPanelOpen);
            Assert.Equal(2, harness.CloseEvents.Count);
            Assert.Equal("stage-select", harness.CloseEvents[0].Key);
            Assert.Equal("map", harness.CloseEvents[1].Key);
        }

        [Fact]
        public void CloseObserverClearsStageSelectTaskPendingAcrossArenaChain()
        {
            using var harness = new Harness();
            var posts = new List<string>();
            var task = new StageSelectTask(
                delegate { return true; },
                delegate(string payload) { });
            task.SetPostToWeb(delegate(string json) { posts.Add(json); });
            // 与 Program.cs SetPanelCloseObserver 的 stage-select 分支同一接线语义。
            harness.Host.SetPanelCloseObserver(delegate(string name, string instance)
            {
                if (name == "stage-select") task.HandleAuthoritativePanelClosed(instance);
            });

            string firstStageSelect = harness.Open("stage-select", "{\"mode\":\"runtime\"}");
            Assert.True(task.BindPanelInstance(firstStageSelect));
            task.HandleWebRequest("snapshot", JObject.Parse(
                "{\"callId\":\"web-chain\",\"panelInstanceId\":\"" + firstStageSelect + "\"}"));

            // 进入 arena（returnTo=stage-select）：DoClose 观察器令旧实例在途请求失效。
            Assert.True(harness.Host.TryOpenPanel(
                "arena", "{}", "stage-select", "{\"mode\":\"runtime\",\"source\":\"arena_return\"}"));
            harness.Pump();
            Assert.Equal("arena", harness.Host.ActivePanelName);
            Assert.Null(task.PanelInstanceId);
            string asyncResponse = "not-called";
            task.HandleFlashResponse(
                JObject.Parse("{\"task\":\"stage_select_response\",\"callId\":1,\"success\":true,\"snapshot\":{}}"),
                delegate(string json) { asyncResponse = json; });
            Assert.Null(asyncResponse);
            Assert.Empty(posts);   // 迟到回包无处可投

            // arena 关闭 → stage-select 以新实例重开；任务保持未绑定，直到首个请求路由时重绑。
            harness.Host.ClosePanel();
            harness.Pump();
            Assert.Equal("stage-select", harness.Host.ActivePanelName);
            string secondStageSelect = harness.Host.ActivePanelInstanceId;
            Assert.NotEqual(firstStageSelect, secondStageSelect);
            Assert.Null(task.PanelInstanceId);
            Assert.True(task.BindPanelInstance(secondStageSelect));
            task.HandleWebRequest("snapshot", JObject.Parse(
                "{\"callId\":\"web-chain-2\",\"panelInstanceId\":\"" + secondStageSelect + "\"}"));
            task.HandleFlashResponse(
                JObject.Parse("{\"task\":\"stage_select_response\",\"callId\":2,\"success\":true,\"snapshot\":{}}"),
                delegate(string json) { });
            var resp = JObject.Parse(Assert.Single(posts));
            Assert.Equal(secondStageSelect, (string)resp["panelInstanceId"]);
            Assert.Equal("web-chain-2", (string)resp["callId"]);
        }
    }
}
