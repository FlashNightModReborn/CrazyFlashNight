using System.Collections.Generic;
using System.Windows.Forms;
using CF7Launcher.Guardian;
using CF7Launcher.Guardian.Hud;
using Xunit;

namespace CF7Launcher.Tests.Guardian
{
    /// <summary>
    /// QuestNoticeWidget 状态机回归。
    ///
    /// 关键不变量：
    /// 1. 未就绪（s=0 / 未推 s）→ 永远不可见，即便 td=1 也忽略
    /// 2. td=1 → TaskDone 持久态可见；td=0 → 退出可见态（除非有 flash）
    /// 3. canDeliver = td && tdn && tdh!="" && mm!="3" && !flash；任何条件不满足 → TASK_UI 路径
    /// 4. legacy task / announce 入队即显示 Flash；NOTICE_MS 后退出回落到 td 持久态或 Idle
    /// 5. flash 期间 click 走 TASK_UI（避免误点新任务横幅直传）
    /// 6. 文案与 click 路由同优先级（与 web buildTaskDoneText 对齐）
    /// </summary>
    public class QuestNoticeWidgetTests
    {
        private class Capture
        {
            public List<string> Dispatched = new List<string>();
            public List<string> RawJson = new List<string>();
        }

        private static LauncherCommandRouter MakeRouter(Capture c)
        {
            // 注入一个透传 wrapper，用于探测 router.Dispatch 调用
            // 但 LauncherCommandRouter 内部 switch 拦截 known key，需要测真正路由——
            // 改用直接断言 widget.ResolveClickRoute（pure 状态查询）+ widget 内的 dispatch try/catch 保护
            return new LauncherCommandRouter(
                socketServer: null,
                onSendKey: k => c.Dispatched.Add("KEY:" + k),
                onToggleFullscreen: () => c.Dispatched.Add("FS"),
                onToggleLog: () => c.Dispatched.Add("LOG"),
                onForceExit: () => c.Dispatched.Add("EXIT"),
                postToWeb: s => { },
                onPanelStateChanged: b => { },
                setActivePanel: name => { });
        }

        private static QuestNoticeWidget MakeWidget(out LauncherCommandRouter router, out Capture cap)
        {
            cap = new Capture();
            router = MakeRouter(cap);
            Control anchor = new Control();
            QuestNoticeWidget w = new QuestNoticeWidget(anchor, router);
            w.ForceGameReady(true);
            return w;
        }

        private static IReadOnlyDictionary<string, string> Snapshot(params string[] kvPieces)
        {
            Dictionary<string, string> dict = new Dictionary<string, string>();
            foreach (string p in kvPieces)
            {
                int colon = p.IndexOf(':');
                string k = colon > 0 ? p.Substring(0, colon) : p;
                dict[k] = p;
            }
            return dict;
        }

        // ── 可见性门控 ──

        [Fact]
        public void NotReady_TdSet_StaysHidden()
        {
            LauncherCommandRouter r; Capture c;
            QuestNoticeWidget w = MakeWidget(out r, out c);
            w.ForceGameReady(false);
            w.OnUiDataChanged(Snapshot("td:1"), new HashSet<string> { "td" });
            Assert.False(w.Visible);
            Assert.True(w.IsTaskDone); // 内部状态推进，但 visible 受 _gameReady 门控
        }

        [Fact]
        public void Td0_Hidden_Td1_Visible()
        {
            LauncherCommandRouter r; Capture c;
            QuestNoticeWidget w = MakeWidget(out r, out c);
            Assert.False(w.Visible);
            w.OnUiDataChanged(Snapshot("td:1"), new HashSet<string> { "td" });
            Assert.True(w.Visible);
            w.OnUiDataChanged(Snapshot("td:0"), new HashSet<string> { "td" });
            Assert.False(w.Visible);
        }

        // ── canDeliver / 文案优先级（对齐 web notch.js buildTaskDoneText） ──

        [Fact]
        public void TaskDone_NoHotspot_TaskUiRoute_TextNoTarget()
        {
            LauncherCommandRouter r; Capture c;
            QuestNoticeWidget w = MakeWidget(out r, out c);
            w.OnUiDataChanged(Snapshot("td:1"), new HashSet<string> { "td" });
            Assert.False(w.CanDeliver());
            Assert.Equal(QuestNoticeWidget.ClickRoute.TaskUi, w.ResolveClickRoute());
            Assert.Equal("任务已达成 · 暂无交付目标", w.BuildTaskDoneText());
        }

        [Fact]
        public void TaskDone_HotspotButNotNavigable_TaskUiRoute_TextLocked()
        {
            LauncherCommandRouter r; Capture c;
            QuestNoticeWidget w = MakeWidget(out r, out c);
            w.OnUiDataChanged(Snapshot("td:1", "tdh:hotspot_x"),
                new HashSet<string> { "td", "tdh" });
            Assert.False(w.CanDeliver());
            Assert.Equal("任务已达成 · 交付点未解锁", w.BuildTaskDoneText());
        }

        [Fact]
        public void TaskDone_NavigableInCombat_TaskUiRoute_TextWaitForBattle()
        {
            LauncherCommandRouter r; Capture c;
            QuestNoticeWidget w = MakeWidget(out r, out c);
            w.OnUiDataChanged(Snapshot("td:1", "tdh:hotspot_x", "tdn:1", "mm:3"),
                new HashSet<string> { "td", "tdh", "tdn", "mm" });
            Assert.False(w.CanDeliver()); // mm=3 战斗中禁用
            Assert.Equal("任务已达成 · 战后交付", w.BuildTaskDoneText());
            Assert.Equal(QuestNoticeWidget.ClickRoute.TaskUi, w.ResolveClickRoute());
        }

        [Fact]
        public void TaskDone_FullyDeliverable_TaskDeliverRoute_TextDeliverable()
        {
            LauncherCommandRouter r; Capture c;
            QuestNoticeWidget w = MakeWidget(out r, out c);
            w.OnUiDataChanged(Snapshot("td:1", "tdh:hotspot_x", "tdn:1", "mm:1"),
                new HashSet<string> { "td", "tdh", "tdn", "mm" });
            Assert.True(w.CanDeliver());
            Assert.Equal(QuestNoticeWidget.ClickRoute.TaskDeliver, w.ResolveClickRoute());
            Assert.Equal("任务已达成 · 可交付", w.BuildTaskDoneText());
        }

        // ── flash 入队 + 计时退场 ──

        [Fact]
        public void LegacyTask_EnqueuesFlashAndShowsImmediately()
        {
            LauncherCommandRouter r; Capture c;
            QuestNoticeWidget w = MakeWidget(out r, out c);
            // 初始 td=0：未 task-done
            Assert.False(w.Visible);
            w.OnLegacyUiData("task", new[] { "拯救公主" });
            Assert.True(w.Visible);
            Assert.True(w.HasActiveFlash);
            Assert.Equal("新任务: 拯救公主", w.DisplayText);
        }

        [Fact]
        public void LegacyAnnounce_EnqueuesFlash()
        {
            LauncherCommandRouter r; Capture c;
            QuestNoticeWidget w = MakeWidget(out r, out c);
            w.OnLegacyUiData("announce", new[] { "服务器维护通知" });
            Assert.True(w.Visible);
            Assert.True(w.HasActiveFlash);
            Assert.Equal("服务器维护通知", w.DisplayText);
        }

        [Fact]
        public void Flash_ExpiresAfterNoticeMs_FallsBackToIdle()
        {
            LauncherCommandRouter r; Capture c;
            QuestNoticeWidget w = MakeWidget(out r, out c);
            w.OnLegacyUiData("task", new[] { "X" });
            Assert.True(w.HasActiveFlash);
            // 推进略超过 NOTICE_MS（5000ms）
            w.AdvanceFlashMs(5001);
            Assert.False(w.HasActiveFlash);
            Assert.False(w.Visible); // td=0 → 回 Idle
        }

        [Fact]
        public void Flash_ExpiresWhileTaskDone_FallsBackToTaskDoneText()
        {
            LauncherCommandRouter r; Capture c;
            QuestNoticeWidget w = MakeWidget(out r, out c);
            w.OnUiDataChanged(Snapshot("td:1", "tdh:hp", "tdn:1", "mm:1"),
                new HashSet<string> { "td", "tdh", "tdn", "mm" });
            w.OnLegacyUiData("task", new[] { "插队任务" });
            Assert.Equal("插队任务".Length + "新任务: ".Length, w.DisplayText.Length);
            w.AdvanceFlashMs(5001);
            Assert.False(w.HasActiveFlash);
            Assert.True(w.Visible);
            Assert.Equal("任务已达成 · 可交付", w.DisplayText);
        }

        [Fact]
        public void Flash_DuringTaskDone_DisablesDeliverClick()
        {
            // 与 web canDeliverNow 等价：通知播放期不可交付（避免误点新任务直传）
            LauncherCommandRouter r; Capture c;
            QuestNoticeWidget w = MakeWidget(out r, out c);
            w.OnUiDataChanged(Snapshot("td:1", "tdh:hp", "tdn:1", "mm:1"),
                new HashSet<string> { "td", "tdh", "tdn", "mm" });
            Assert.True(w.CanDeliver());
            w.OnLegacyUiData("task", new[] { "插队" });
            Assert.False(w.CanDeliver());
            Assert.Equal(QuestNoticeWidget.ClickRoute.TaskUi, w.ResolveClickRoute());
        }

        [Fact]
        public void MultipleFlashes_QueueDrains()
        {
            LauncherCommandRouter r; Capture c;
            QuestNoticeWidget w = MakeWidget(out r, out c);
            w.OnLegacyUiData("task", new[] { "A" });
            w.OnLegacyUiData("announce", new[] { "B" });
            w.OnLegacyUiData("task", new[] { "C" });
            Assert.True(w.HasActiveFlash);
            Assert.Equal(2, w.FlashQueueCount); // 当前 active 不计
            w.AdvanceFlashMs(5001);
            Assert.True(w.HasActiveFlash);
            Assert.Equal(1, w.FlashQueueCount);
            Assert.Equal("B", w.DisplayText);
            w.AdvanceFlashMs(5001);
            Assert.True(w.HasActiveFlash);
            Assert.Equal(0, w.FlashQueueCount);
            Assert.Equal("新任务: C", w.DisplayText);
            w.AdvanceFlashMs(5001);
            Assert.False(w.HasActiveFlash);
            Assert.False(w.Visible);
        }

        // ── 复位 ──

        [Fact]
        public void GameNotReady_ClearsFlashQueue_AndResetsState()
        {
            LauncherCommandRouter r; Capture c;
            QuestNoticeWidget w = MakeWidget(out r, out c);
            w.OnLegacyUiData("task", new[] { "X" });
            w.OnLegacyUiData("announce", new[] { "Y" });
            Assert.True(w.HasActiveFlash);
            Assert.Equal(1, w.FlashQueueCount);
            w.OnUiDataChanged(Snapshot("s:0"), new HashSet<string> { "s" });
            Assert.False(w.Visible);
            Assert.False(w.HasActiveFlash);
            Assert.Equal(0, w.FlashQueueCount);
        }

        // ── tdh / tdn / mm 解析 ──

        [Fact]
        public void TdhWithPrefix_StripsToValueOnly()
        {
            LauncherCommandRouter r; Capture c;
            QuestNoticeWidget w = MakeWidget(out r, out c);
            w.OnUiDataChanged(Snapshot("tdh:hotspot_42"), new HashSet<string> { "tdh" });
            Assert.Equal("hotspot_42", w.HotspotId);
        }

        [Fact]
        public void MmDefault_When_Unset_Is_Zero()
        {
            LauncherCommandRouter r; Capture c;
            QuestNoticeWidget w = MakeWidget(out r, out c);
            // 未推 mm → 默认 "0"
            Assert.Equal("0", w.MapMode);
        }

        [Fact]
        public void EmptyAnnounce_NotEnqueued()
        {
            LauncherCommandRouter r; Capture c;
            QuestNoticeWidget w = MakeWidget(out r, out c);
            w.OnLegacyUiData("announce", new[] { "" });
            Assert.False(w.HasActiveFlash);
            Assert.False(w.Visible);
        }

        [Fact]
        public void UnknownLegacyType_Ignored()
        {
            LauncherCommandRouter r; Capture c;
            QuestNoticeWidget w = MakeWidget(out r, out c);
            w.OnLegacyUiData("combo", new[] { "ignored" }); // combo 不属于本 widget
            Assert.False(w.HasActiveFlash);
        }
    }
}
