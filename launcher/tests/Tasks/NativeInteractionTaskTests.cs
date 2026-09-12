using System;
using System.Collections.Generic;
using System.Drawing;
using System.Windows.Forms;
using CF7Launcher.Guardian.Hud;
using CF7Launcher.Guardian.Hud.Tooltip;
using CF7Launcher.Tasks;
using Newtonsoft.Json.Linq;
using Xunit;

namespace CF7Launcher.Tests.Tasks
{
    /// <summary>
    /// NativeInteractionTask 定向回归（COMMON 桥协议 v1 + INTEGRATION 身份契约）：
    /// - requestId 精确形 ni:&lt;正整数&gt;：非精确形 show 拒绝；hide 只按 kind+requestId+sceneId 精确匹配。
    /// - 全局序号前沿仅作用于 show：旧 seq show 拒收；seq==max 只在"同 kind+requestId+sceneId
    ///   仍存活"时按刷新放行，其余一律按已消费请求复活/换 kind/换 scene 拒绝。
    /// - hide 不受序号门控——另一种浮层的更新 show 不能拒掉本实例的匹配 hide。
    /// - 回包 nativeInteractionAction / nativeInteractionCancel 携带 {version,requestId,sceneId[,actionId]}。
    /// - 断线全清且序号归零；malformed 输入不得抛出。
    /// </summary>
    public sealed class NativeInteractionTaskTests
    {
        private sealed class TooltipStub : INativeInteractionTooltipSurface
        {
            public int ShowCalls;
            public int HideCalls;
            public int ResetCalls;
            public int SuppressCalls;
            public string LastHideId;
            public string SceneId;
            public string RequestId;
            public bool Pinned;
            public NativeTooltipDocument Doc;
            public bool IsScrollable;
            public Rectangle Bounds;
            public Rectangle? OwnerBounds;
            public int ScrollCalls;
            public int ScrollDeltaTotal;
            public bool ScrollResult = true;
            public string LastInspectionState;
            public int LastInspectionRemaining;
            public int InspectionPushCount;

            public event Action<string> DismissRequested;

            public bool Show(JObject payload) { ShowCalls++; return true; }
            public bool Hide(string requestId)
            {
                HideCalls++;
                LastHideId = requestId;
                if (RequestId == requestId) { RequestId = null; Doc = null; Pinned = false; }
                return true;
            }
            public void Reset() { ResetCalls++; RequestId = null; Doc = null; }
            public void OnHostSuppressed(string reason) { SuppressCalls++; Doc = null; RequestId = null; }
            public string CurrentSceneId { get { return SceneId; } }
            public string CurrentRequestId { get { return RequestId; } }
            public bool HasPinnedSession { get { return Pinned; } }
            public NativeTooltipDocument ActiveDocument { get { return Doc; } }
            public bool Scrollable { get { return IsScrollable; } }
            public Rectangle ScreenBounds { get { return Bounds; } }
            public Rectangle? OwnerScreenBounds { get { return OwnerBounds; } }
            public bool ScrollByLines(int delta)
            {
                ScrollCalls++;
                ScrollDeltaTotal += delta;
                return ScrollResult;
            }
            public void SetInspectionState(string state, int remainingMs)
            {
                InspectionPushCount++;
                LastInspectionState = state;
                LastInspectionRemaining = remainingMs;
            }

            public void FireDismiss(string requestId)
            {
                Action<string> h = DismissRequested;
                if (h != null) h(requestId);
            }
        }

        private static NpcMenuWidget NewMenu()
        {
            // 1024x576 等比 anchor → viewport 全幅 scale=1；无 handle 时 ScreenBounds=Empty。
            return new NpcMenuWidget(new Control { Size = new Size(1024, 576) });
        }

        private static JObject Envelope(JObject payload)
        {
            JObject m = new JObject();
            m["task"] = "native_interaction";
            m["payload"] = payload;
            return m;
        }

        private static JObject MenuShow(string requestId, string sceneId, JArray actions)
        {
            JObject p = new JObject();
            p["version"] = 1;
            p["kind"] = "menu";
            p["op"] = "show";
            p["requestId"] = requestId;
            p["sceneId"] = sceneId;
            p["x"] = 200;
            p["y"] = 200;
            p["targetName"] = "npc_a";
            p["title"] = "测试 NPC";
            if (actions != null) p["actions"] = actions;
            return p;
        }

        private static JArray Actions(params object[][] tuples)
        {
            JArray arr = new JArray();
            for (int i = 0; i < tuples.Length; i++)
            {
                object[] t = (object[])tuples[i];
                JObject a = new JObject();
                a["id"] = (string)t[0];
                a["label"] = (string)t[1];
                a["enabled"] = (bool)t[2];
                arr.Add(a);
            }
            return arr;
        }

        private static JObject HideMsg(string kind, string requestId, string sceneId)
        {
            JObject p = new JObject();
            p["version"] = 1;
            p["kind"] = kind;
            p["op"] = "hide";
            p["requestId"] = requestId;
            p["sceneId"] = sceneId;
            return p;
        }

        private static JObject TooltipShow(string requestId, string sceneId)
        {
            JObject p = new JObject();
            p["version"] = 1;
            p["kind"] = "tooltip";
            p["op"] = "show";
            p["requestId"] = requestId;
            p["sceneId"] = sceneId;
            return p;
        }

        // scale=1 时的逻辑尺寸（与 NpcMenuWidget 常量一致）
        private const int Pad = 5, TitleH = 26, RowH = 24, Width = 170;

        private static Rectangle MenuRect(int entryCount)
        {
            return new Rectangle(0, 0, Width, Pad + TitleH + entryCount * RowH + Pad);
        }

        private static MouseEventArgs ClickArgs(int x, int y)
        {
            return new MouseEventArgs(MouseButtons.Left, 1, x, y, 0);
        }

        private static int RowCenterY(int row)
        {
            return Pad + TitleH + row * RowH + RowH / 2;
        }

        // ── ni:<n> 解析 ──

        [Theory]
        [InlineData("ni:1", 1)]
        [InlineData("ni:42", 42)]
        [InlineData("ni:9223372036854775806", 9223372036854775806L)]
        public void TryParseRequestSeq_AcceptsExactNiPositive(string rid, long expected)
        {
            long seq;
            Assert.True(NativeInteractionTask.TryParseRequestSeq(rid, out seq));
            Assert.Equal(expected, seq);
        }

        [Theory]
        [InlineData(null)]
        [InlineData("")]
        [InlineData("ni:")]
        [InlineData("ni:0")]
        [InlineData("ni:-1")]
        [InlineData("ni:abc")]
        [InlineData("ni:1x")]
        [InlineData("x:1")]
        [InlineData("NI:1")]
        [InlineData("ni:9223372036854775808")]
        public void TryParseRequestSeq_RejectsNonExact(string rid)
        {
            long seq;
            Assert.False(NativeInteractionTask.TryParseRequestSeq(rid, out seq));
        }

        // ── show/hide 身份与序号 ──

        [Fact]
        public void MenuShow_AppliesSession()
        {
            NpcMenuWidget menu = NewMenu();
            TooltipStub tip = new TooltipStub();
            NativeInteractionTask task = new NativeInteractionTask(null, menu, tip, a => a());
            task.Handle(Envelope(MenuShow("ni:1", "s1",
                Actions(new object[] { "talk", "对话", true }))));
            Assert.Equal("ni:1", menu.CurrentRequestId);
            Assert.Equal("s1", menu.CurrentSceneId);
            Assert.Equal(1, menu.SessionEntryCountForTest);
        }

        [Fact]
        public void StaleShow_SmallerSeq_Dropped()
        {
            NpcMenuWidget menu = NewMenu();
            NativeInteractionTask task = new NativeInteractionTask(null, menu, null, a => a());
            task.Handle(Envelope(MenuShow("ni:9", "s1",
                Actions(new object[] { "a", "A", true }))));
            task.Handle(Envelope(MenuShow("ni:3", "s1",
                Actions(new object[] { "b", "B", true }))));
            Assert.Equal("ni:9", menu.CurrentRequestId);
        }

        [Fact]
        public void SameSeqRefresh_SameKindSameScene_Allowed()
        {
            NpcMenuWidget menu = NewMenu();
            NativeInteractionTask task = new NativeInteractionTask(null, menu, null, a => a());
            task.Handle(Envelope(MenuShow("ni:4", "s1",
                Actions(new object[] { "a", "A", true }))));
            task.Handle(Envelope(MenuShow("ni:4", "s1",
                Actions(new object[] { "a", "A", true }, new object[] { "b", "B", true }))));
            Assert.Equal("ni:4", menu.CurrentRequestId);
            Assert.Equal(2, menu.SessionEntryCountForTest);
        }

        [Fact]
        public void SameSeqRevival_AfterClose_Rejected()
        {
            NpcMenuWidget menu = NewMenu();
            NativeInteractionTask task = new NativeInteractionTask(null, menu, null, a => a());
            task.Handle(Envelope(MenuShow("ni:4", "s1",
                Actions(new object[] { "a", "A", true }))));
            task.Handle(Envelope(HideMsg("menu", "ni:4", "s1")));
            Assert.Null(menu.CurrentRequestId);
            // 关闭后同号 show = 已消费请求复活，拒绝
            task.Handle(Envelope(MenuShow("ni:4", "s1",
                Actions(new object[] { "a", "A", true }))));
            Assert.Null(menu.CurrentRequestId);
        }

        [Fact]
        public void SameSeq_CrossKind_Rejected()
        {
            NpcMenuWidget menu = NewMenu();
            TooltipStub tip = new TooltipStub();
            NativeInteractionTask task = new NativeInteractionTask(null, menu, tip, a => a());
            task.Handle(Envelope(MenuShow("ni:5", "s1",
                Actions(new object[] { "a", "A", true }))));
            // 同 requestId 换 kind：menu ni:5 存活时 tooltip ni:5 不得复活到注释侧
            task.Handle(Envelope(TooltipShow("ni:5", "s1")));
            Assert.Equal(0, tip.ShowCalls);
            Assert.Equal("ni:5", menu.CurrentRequestId);
        }

        [Fact]
        public void SameSeq_DifferentScene_Rejected()
        {
            NpcMenuWidget menu = NewMenu();
            NativeInteractionTask task = new NativeInteractionTask(null, menu, null, a => a());
            task.Handle(Envelope(MenuShow("ni:6", "s1",
                Actions(new object[] { "a", "A", true }))));
            // 同 requestId 换 scene：seq==max 且 active 实例仍在但场景不同 → 拒
            task.Handle(Envelope(MenuShow("ni:6", "s2",
                Actions(new object[] { "a", "A", true }))));
            Assert.Equal("s1", menu.CurrentSceneId);
        }

        [Fact]
        public void LateHide_CannotCloseNewerInstance()
        {
            NpcMenuWidget menu = NewMenu();
            NativeInteractionTask task = new NativeInteractionTask(null, menu, null, a => a());
            task.Handle(Envelope(MenuShow("ni:2", "s1",
                Actions(new object[] { "a", "A", true }))));
            task.Handle(Envelope(HideMsg("menu", "ni:1", "s1")));
            Assert.Equal("ni:2", menu.CurrentRequestId);
            // 同 requestId 但 sceneId 不匹配同样不得清
            task.Handle(Envelope(HideMsg("menu", "ni:2", "other")));
            Assert.Equal("ni:2", menu.CurrentRequestId);
        }

        [Fact]
        public void Hide_PerKindIndependent_NotGatedByOtherKindNewerShow()
        {
            NpcMenuWidget menu = NewMenu();
            TooltipStub tip = new TooltipStub();
            NativeInteractionTask task = new NativeInteractionTask(null, menu, tip, a => a());
            task.Handle(Envelope(MenuShow("ni:1", "s1",
                Actions(new object[] { "a", "A", true }))));
            task.Handle(Envelope(TooltipShow("ni:7", "s1"))); // 抬高全局 seq 前沿
            Assert.Equal(1, tip.ShowCalls);
            // tooltip 的更新 show 不得拒掉 menu 的匹配 hide
            task.Handle(Envelope(HideMsg("menu", "ni:1", "s1")));
            Assert.Null(menu.CurrentRequestId);
            Assert.Equal(0, tip.ResetCalls);
        }

        [Fact]
        public void SceneRoll_ClearsOldSceneInstances()
        {
            NpcMenuWidget menu = NewMenu();
            TooltipStub tip = new TooltipStub();
            NativeInteractionTask task = new NativeInteractionTask(null, menu, tip, a => a());
            task.Handle(Envelope(MenuShow("ni:2", "s1",
                Actions(new object[] { "a", "A", true }))));
            tip.SceneId = "s1"; tip.RequestId = "ni:4"; // 模拟 tooltip 侧持有旧场景实例
            task.Handle(Envelope(MenuShow("ni:9", "s2",
                Actions(new object[] { "b", "B", true }))));
            Assert.Equal("ni:9", menu.CurrentRequestId);
            Assert.Equal("s2", menu.CurrentSceneId);
            Assert.Equal(1, tip.ResetCalls); // 旧场景 tooltip 被滚转清除
        }

        // ── 回包 ──

        [Fact]
        public void ActionChosen_SendsNativeInteractionAction()
        {
            NpcMenuWidget menu = NewMenu();
            NativeInteractionTask task = new NativeInteractionTask(null, menu, null, a => a());
            List<string> sent = new List<string>();
            task.SendPayloadOverride = s => { sent.Add(s); return true; };
            task.Handle(Envelope(MenuShow("ni:3", "s1",
                Actions(new object[] { "talk", "对话", true }, new object[] { "shop", "商店", false }))));

            Rectangle rect = MenuRect(2);
            menu.HandleMouseEventForTest(ClickArgs(20, RowCenterY(0)), MouseEventKind.Down, rect);
            menu.HandleMouseEventForTest(ClickArgs(20, RowCenterY(0)), MouseEventKind.Click, rect);

            Assert.Single(sent);
            JObject cmd = JObject.Parse(sent[0].TrimEnd('\0'));
            Assert.Equal("cmd", cmd.Value<string>("task"));
            Assert.Equal("nativeInteractionAction", cmd.Value<string>("action"));
            Assert.Equal(1, cmd.Value<int>("version"));
            Assert.Equal("ni:3", cmd.Value<string>("requestId"));
            Assert.Equal("s1", cmd.Value<string>("sceneId"));
            Assert.Equal("talk", cmd.Value<string>("actionId"));
            Assert.Null(menu.CurrentRequestId); // 派发后会话结束
        }

        [Fact]
        public void DisabledRow_Click_NoDispatch_MenuStays()
        {
            NpcMenuWidget menu = NewMenu();
            NativeInteractionTask task = new NativeInteractionTask(null, menu, null, a => a());
            List<string> sent = new List<string>();
            task.SendPayloadOverride = s => { sent.Add(s); return true; };
            task.Handle(Envelope(MenuShow("ni:3", "s1",
                Actions(new object[] { "talk", "对话", false }))));

            Rectangle rect = MenuRect(1);
            menu.HandleMouseEventForTest(ClickArgs(20, RowCenterY(0)), MouseEventKind.Down, rect);
            menu.HandleMouseEventForTest(ClickArgs(20, RowCenterY(0)), MouseEventKind.Click, rect);

            Assert.Empty(sent);
            Assert.Equal("ni:3", menu.CurrentRequestId);
        }

        [Fact]
        public void Dismiss_SendsNativeInteractionCancel()
        {
            NpcMenuWidget menu = NewMenu();
            NativeInteractionTask task = new NativeInteractionTask(null, menu, null, a => a());
            List<string> sent = new List<string>();
            task.SendPayloadOverride = s => { sent.Add(s); return true; };
            task.Handle(Envelope(MenuShow("ni:8", "s7",
                Actions(new object[] { "talk", "对话", true }))));
            task.NotifyInteractionEscape();
            Assert.Single(sent);
            JObject cmd = JObject.Parse(sent[0].TrimEnd('\0'));
            Assert.Equal("nativeInteractionCancel", cmd.Value<string>("action"));
            Assert.Equal("ni:8", cmd.Value<string>("requestId"));
            Assert.Equal("s7", cmd.Value<string>("sceneId"));
            Assert.Null(menu.CurrentRequestId);
        }

        [Fact]
        public void TooltipDismiss_CancelCarriesTooltipIdentity()
        {
            NpcMenuWidget menu = NewMenu();
            TooltipStub tip = new TooltipStub();
            NativeInteractionTask task = new NativeInteractionTask(null, menu, tip, a => a());
            List<string> sent = new List<string>();
            task.SendPayloadOverride = s => { sent.Add(s); return true; };
            tip.RequestId = "ni:9";
            tip.SceneId = "s9";
            tip.FireDismiss("ni:9");
            Assert.Single(sent);
            JObject cmd = JObject.Parse(sent[0].TrimEnd('\0'));
            Assert.Equal("nativeInteractionCancel", cmd.Value<string>("action"));
            Assert.Equal("ni:9", cmd.Value<string>("requestId"));
            Assert.Equal("s9", cmd.Value<string>("sceneId"));
        }

        [Fact]
        public void PanelSuspend_TerminatesBoth_SendsMenuCancel()
        {
            NpcMenuWidget menu = NewMenu();
            TooltipStub tip = new TooltipStub();
            NativeInteractionTask task = new NativeInteractionTask(null, menu, tip, a => a());
            List<string> sent = new List<string>();
            task.SendPayloadOverride = s => { sent.Add(s); return true; };
            task.Handle(Envelope(MenuShow("ni:8", "s1",
                Actions(new object[] { "a", "A", true }))));
            task.OnPanelSuspending();
            Assert.Null(menu.CurrentRequestId);
            Assert.Equal(1, tip.SuppressCalls);
            Assert.Single(sent);
            Assert.Contains("nativeInteractionCancel", sent[0]);
        }

        // ── malformed / 断线 ──

        [Fact]
        public void MalformedInputs_DoNotThrow_DoNotApply()
        {
            NpcMenuWidget menu = NewMenu();
            TooltipStub tip = new TooltipStub();
            NativeInteractionTask task = new NativeInteractionTask(null, menu, tip, a => a());

            task.Handle(new JObject()); // 无 payload
            task.Handle(Envelope(new JObject())); // 空 payload
            JObject bad = new JObject();
            bad["version"] = new JObject(); // 对象而非整数——Value<int?> 会抛，安全读取应回落
            bad["kind"] = "menu"; bad["op"] = "show";
            bad["requestId"] = "ni:1"; bad["sceneId"] = "s1";
            task.Handle(Envelope(bad));
            bad["version"] = 2; // 版本不符
            task.Handle(Envelope(bad));
            bad["version"] = 1; bad["requestId"] = "x9"; // 非 ni:<n> 的 show → 拒
            task.Handle(Envelope(bad));
            bad["requestId"] = "ni:1"; bad["kind"] = "bogus"; // 未知 kind
            task.Handle(Envelope(bad));
            bad["kind"] = "menu"; bad["op"] = "blink"; // 未知 op
            task.Handle(Envelope(bad));

            Assert.Null(menu.CurrentRequestId);
            Assert.Equal(0, tip.ShowCalls);
        }

        [Fact]
        public void MalformedActions_EntriesSkippedNotThrow()
        {
            NpcMenuWidget menu = NewMenu();
            NativeInteractionTask task = new NativeInteractionTask(null, menu, null, a => a());
            JObject p = MenuShow("ni:1", "s1", null);
            JArray actions = new JArray();
            actions.Add(new JValue(42));            // 非对象
            JObject noId = new JObject(); noId["label"] = "x";
            actions.Add(noId);                       // 缺 id
            JObject ok = new JObject();
            ok["id"] = "talk"; ok["label"] = "对话";
            ok["enabled"] = "yes";                   // 非 bool → 回落默认 true
            actions.Add(ok);
            p["actions"] = actions;
            task.Handle(Envelope(p));
            Assert.Equal(1, menu.SessionEntryCountForTest);
        }

        [Fact]
        public void Disconnect_ClearsAll_ResetsSequence()
        {
            NpcMenuWidget menu = NewMenu();
            TooltipStub tip = new TooltipStub();
            NativeInteractionTask task = new NativeInteractionTask(null, menu, tip, a => a());
            task.Handle(Envelope(MenuShow("ni:9", "s1",
                Actions(new object[] { "a", "A", true }))));
            task.HandleTransportDisconnected();
            Assert.Null(menu.CurrentRequestId);
            Assert.Equal(1, tip.ResetCalls);
            // 重连后 ni:<n> 重新计数：低序号 show 必须被接受
            task.Handle(Envelope(MenuShow("ni:1", "s2",
                Actions(new object[] { "b", "B", true }))));
            Assert.Equal("ni:1", menu.CurrentRequestId);
        }

        // ── 外部点击 / ESC ──

        [Fact]
        public void IsExternalPress_PureBoundary()
        {
            Rectangle r = new Rectangle(100, 100, 170, 84);
            Assert.True(NativeInteractionTask.IsExternalPress(true, r, 10, 10));
            Assert.True(NativeInteractionTask.IsExternalPress(true, r, 500, 200));
            Assert.False(NativeInteractionTask.IsExternalPress(true, r, 150, 120)); // 界内
            Assert.False(NativeInteractionTask.IsExternalPress(false, r, 10, 10));  // 菜单未开
            Assert.False(NativeInteractionTask.IsExternalPress(true, Rectangle.Empty, 10, 10)); // 无界
        }

        [Fact]
        public void EscapableProbe_MenuOrPinnedOnly()
        {
            NpcMenuWidget menu = NewMenu();
            TooltipStub tip = new TooltipStub();
            NativeInteractionTask task = new NativeInteractionTask(null, menu, tip, a => a());
            Assert.False(task.IsInteractionEscapable());
            task.Handle(Envelope(MenuShow("ni:1", "s1",
                Actions(new object[] { "a", "A", true }))));
            Assert.True(task.IsInteractionEscapable());
            task.Handle(Envelope(HideMsg("menu", "ni:1", "s1")));
            Assert.False(task.IsInteractionEscapable());
            tip.Pinned = true; // pinned tooltip 存活 → 可 ESC
            Assert.True(task.IsInteractionEscapable());
        }

        [Fact]
        public void Escape_PinnedTooltip_SendsCancelAndResets()
        {
            NpcMenuWidget menu = NewMenu();
            TooltipStub tip = new TooltipStub();
            NativeInteractionTask task = new NativeInteractionTask(null, menu, tip, a => a());
            List<string> sent = new List<string>();
            task.SendPayloadOverride = s => { sent.Add(s); return true; };
            tip.Pinned = true;
            tip.RequestId = "ni:11";
            tip.SceneId = "s11";
            task.NotifyInteractionEscape();
            Assert.Equal(1, tip.ResetCalls);
            Assert.Single(sent);
            JObject cmd = JObject.Parse(sent[0].TrimEnd('\0'));
            Assert.Equal("nativeInteractionCancel", cmd.Value<string>("action"));
            Assert.Equal("ni:11", cmd.Value<string>("requestId"));
            Assert.Equal("s11", cmd.Value<string>("sceneId"));
        }
    }
}
