using System;
using System.Collections.Generic;
using System.Drawing;
using System.Windows.Forms;
using CF7Launcher.Guardian.Hud;
using CF7Launcher.Guardian.Hud.Tooltip;
using CF7Launcher.Tasks;
using Newtonsoft.Json.Linq;
using Xunit;

namespace CF7Launcher.Tests.Guardian
{
    /// <summary>
    /// NpcMenuWidget + native_interaction 滚轮分派定向回归：
    /// - 定位：锚点右下展开，边沿翻转 + 硬 clamp 进 viewport inset。
    /// - 行命中：标题/padding 不命中行；禁用行命中但不派发；down/up 错位不派发。
    /// - 身份：HideSession 只在 requestId+sceneId 双匹配时清；压隐终结会话并上报 dismiss；
    ///   ForceClear 静默（断线/场景滚转不发 cancel）。
    /// - 滚轮：pinned 框内消费；dense 未进 inspect 一律放行（检视仲裁归
    ///   TooltipInspectionController，见其专属测试）；simple/框外放行——
    ///   经 NativeInteractionWheelRoute.Dispatch（= Program.cs 钩子上挂的同一入口）验证。
    /// </summary>
    public sealed class NativeInteractionMenuTests
    {
        private static Control Anchor()
        {
            return new Control { Size = new Size(1024, 576) };
        }

        private static NpcMenuWidget.MenuSession Session(
            string requestId, string sceneId, params object[][] entries)
        {
            NpcMenuWidget.MenuSession s = new NpcMenuWidget.MenuSession();
            s.RequestId = requestId;
            s.SceneId = sceneId;
            s.Title = "NPC";
            s.AnchorFx = 200f;
            s.AnchorFy = 200f;
            NpcMenuWidget.Entry[] list = new NpcMenuWidget.Entry[entries.Length];
            for (int i = 0; i < entries.Length; i++)
            {
                object[] t = entries[i];
                NpcMenuWidget.Entry e = new NpcMenuWidget.Entry();
                e.Id = (string)t[0];
                e.Label = (string)t[1];
                e.Enabled = (bool)t[2];
                list[i] = e;
            }
            s.Entries = list;
            return s;
        }

        private static MouseEventArgs ClickArgs(int x, int y)
        {
            return new MouseEventArgs(MouseButtons.Left, 1, x, y, 0);
        }

        // scale=1 尺寸与 NpcMenuWidget 常量一致
        private const int Pad = 5, TitleH = 26, RowH = 24, Width = 170;

        private static Rectangle RectFor(int entries)
        {
            return new Rectangle(0, 0, Width, Pad + TitleH + entries * RowH + Pad);
        }

        private static int RowY(int row)
        {
            return Pad + TitleH + row * RowH + RowH / 2;
        }

        // ── 定位 ──

        [Fact]
        public void ComputeMenuRect_DefaultRightBottom()
        {
            Rectangle vp = new Rectangle(0, 0, 1024, 576);
            Rectangle r = NpcMenuWidget.ComputeMenuRect(200, 200, 170, 84, 6, vp, 6);
            Assert.Equal(206, r.X);
            Assert.Equal(206, r.Y);
        }

        [Fact]
        public void ComputeMenuRect_FlipsLeftOnRightOverflow()
        {
            Rectangle vp = new Rectangle(0, 0, 1024, 576);
            // 锚点贴右边：206 位宽放不进 → 翻到锚点左侧
            Rectangle r = NpcMenuWidget.ComputeMenuRect(1000, 200, 170, 84, 6, vp, 6);
            Assert.Equal(1000 - 6 - 170, r.X);
        }

        [Fact]
        public void ComputeMenuRect_FlipsUpOnBottomOverflow()
        {
            Rectangle vp = new Rectangle(0, 0, 1024, 576);
            Rectangle r = NpcMenuWidget.ComputeMenuRect(200, 560, 170, 84, 6, vp, 6);
            Assert.Equal(560 - 6 - 84, r.Y);
        }

        [Fact]
        public void ComputeMenuRect_HardClampsInsideViewport()
        {
            Rectangle vp = new Rectangle(100, 50, 800, 500);
            // 锚点在 viewport 左上角之外：默认右下展开仍越左/上界 → 硬 clamp 进 inset
            Rectangle r = NpcMenuWidget.ComputeMenuRect(-50, -50, 170, 200, 6, vp, 6);
            Assert.Equal(vp.Left + 6, r.X);
            Assert.Equal(vp.Top + 6, r.Y);
        }

        [Fact]
        public void ComputeMenuRect_TallerThanViewport_PinsToTopInset()
        {
            Rectangle vp = new Rectangle(100, 50, 800, 500);
            // 菜单比 viewport 高：clamp 区间塌缩到 minY，顶边贴 inset（底边允许溢出）
            Rectangle r = NpcMenuWidget.ComputeMenuRect(300, 300, 170, 600, 6, vp, 6);
            Assert.Equal(vp.Top + 6, r.Y);
            Assert.True(r.Bottom > vp.Bottom);
        }

        // ── 行命中 ──

        [Fact]
        public void HitRowIndex_TitleAndPadReturnMinusOne()
        {
            Rectangle r = RectFor(2);
            Assert.Equal(-1, NpcMenuWidget.HitRowIndex(r, Pad, TitleH, RowH, 2, 20, Pad + 3));
            Assert.Equal(-1, NpcMenuWidget.HitRowIndex(r, Pad, TitleH, RowH, 2, 20, r.Bottom - 2));
            Assert.Equal(-1, NpcMenuWidget.HitRowIndex(r, Pad, TitleH, RowH, 2, 1, RowY(0))); // 左 pad 区
        }

        [Fact]
        public void HitRowIndex_RowsHit()
        {
            Rectangle r = RectFor(3);
            Assert.Equal(0, NpcMenuWidget.HitRowIndex(r, Pad, TitleH, RowH, 3, 20, RowY(0)));
            Assert.Equal(1, NpcMenuWidget.HitRowIndex(r, Pad, TitleH, RowH, 3, 20, RowY(1)));
            Assert.Equal(2, NpcMenuWidget.HitRowIndex(r, Pad, TitleH, RowH, 3, 20, RowY(2)));
        }

        // ── 身份 / 关闭路径 ──

        [Fact]
        public void HideSession_ExactMatchOnly()
        {
            using (Control a = Anchor())
            {
                NpcMenuWidget w = new NpcMenuWidget(a);
                w.ShowSession(Session("ni:5", "s1", new object[] { "t", "T", true }));
                Assert.False(w.HideSession("ni:4", "s1"));
                Assert.False(w.HideSession("ni:5", "s9"));
                Assert.Equal("ni:5", w.CurrentRequestId);
                Assert.True(w.HideSession("ni:5", "s1"));
                Assert.Null(w.CurrentRequestId);
            }
        }

        [Fact]
        public void Suppression_DismissesAndReports()
        {
            using (Control a = Anchor())
            {
                NpcMenuWidget w = new NpcMenuWidget(a);
                string gotRid = null, gotSid = null, gotReason = null;
                w.SessionDismissed = delegate(string rid, string sid, string reason)
                { gotRid = rid; gotSid = sid; gotReason = reason; };
                w.ShowSession(Session("ni:7", "s2", new object[] { "t", "T", true }));
                w.OnHostSuppressed("panel_suspend");
                Assert.Equal("ni:7", gotRid);
                Assert.Equal("s2", gotSid);
                Assert.Equal("panel_suspend", gotReason);
                Assert.Null(w.CurrentRequestId);
            }
        }

        [Fact]
        public void ForceClear_IsSilent()
        {
            using (Control a = Anchor())
            {
                NpcMenuWidget w = new NpcMenuWidget(a);
                bool fired = false;
                w.SessionDismissed = delegate { fired = true; };
                w.ShowSession(Session("ni:7", "s2", new object[] { "t", "T", true }));
                w.ForceClear();
                Assert.False(fired);
                Assert.Null(w.CurrentRequestId);
            }
        }

        // ── 点击派发 ──

        [Fact]
        public void ClickEnabledRow_DispatchesAndCloses()
        {
            using (Control a = Anchor())
            {
                NpcMenuWidget w = new NpcMenuWidget(a);
                string gotAction = null, gotRid = null;
                w.ActionChosen = delegate(string rid, string sid, string aid)
                { gotRid = rid; gotAction = aid; };
                w.ShowSession(Session("ni:3", "s1",
                    new object[] { "talk", "对话", true },
                    new object[] { "shop", "商店", true }));
                Rectangle r = RectFor(2);
                w.HandleMouseEventForTest(ClickArgs(20, RowY(1)), MouseEventKind.Down, r);
                w.HandleMouseEventForTest(ClickArgs(20, RowY(1)), MouseEventKind.Click, r);
                Assert.Equal("shop", gotAction);
                Assert.Equal("ni:3", gotRid);
                Assert.Null(w.CurrentRequestId);
            }
        }

        [Fact]
        public void DisabledRow_HitButNoDispatch()
        {
            using (Control a = Anchor())
            {
                NpcMenuWidget w = new NpcMenuWidget(a);
                bool dispatched = false;
                w.ActionChosen = delegate { dispatched = true; };
                w.ShowSession(Session("ni:3", "s1", new object[] { "talk", "对话", false }));
                Rectangle r = RectFor(1);
                w.HandleMouseEventForTest(ClickArgs(20, RowY(0)), MouseEventKind.Down, r);
                w.HandleMouseEventForTest(ClickArgs(20, RowY(0)), MouseEventKind.Click, r);
                Assert.False(dispatched);
                Assert.Equal("ni:3", w.CurrentRequestId); // 菜单保持打开
            }
        }

        [Fact]
        public void DownUpMismatch_NoDispatch()
        {
            using (Control a = Anchor())
            {
                NpcMenuWidget w = new NpcMenuWidget(a);
                bool dispatched = false;
                w.ActionChosen = delegate { dispatched = true; };
                w.ShowSession(Session("ni:3", "s1",
                    new object[] { "a", "A", true }, new object[] { "b", "B", true }));
                Rectangle r = RectFor(2);
                w.HandleMouseEventForTest(ClickArgs(20, RowY(0)), MouseEventKind.Down, r);
                w.HandleMouseEventForTest(ClickArgs(20, RowY(1)), MouseEventKind.Click, r);
                Assert.False(dispatched);
                Assert.Equal("ni:3", w.CurrentRequestId);
            }
        }

        [Fact]
        public void ClickWithoutDown_NoDispatch()
        {
            using (Control a = Anchor())
            {
                NpcMenuWidget w = new NpcMenuWidget(a);
                bool dispatched = false;
                w.ActionChosen = delegate { dispatched = true; };
                w.ShowSession(Session("ni:3", "s1", new object[] { "a", "A", true }));
                w.HandleMouseEventForTest(ClickArgs(20, RowY(0)), MouseEventKind.Click, RectFor(1));
                Assert.False(dispatched);
            }
        }

        // ── 滚轮分派（Program.cs 钩子实际入口） ──

        private static JObject DenseScrollablePayload()
        {
            string longText = "";
            for (int i = 0; i < 80; i++) longText += "第" + i + "行装备属性明细描述说明文字，";
            return JObject.Parse(@"{
              'version':1,'requestId':'tt-long','sceneId':'s1','x':500,'y':200,
              'document':{'version':1,'title':'密集检视','profile':'dense',
                'sections':[
                  {'role':'intro','runs':[{'text':'测试物品·长文'}]},
                  {'role':'description','runs':[{'text':'" + longText + @"'}]}
                ]}}");
        }

        [Fact]
        public void WheelRoute_DenseScrollable_NotInspecting_Releases()
        {
            using (Control a = Anchor())
            using (NativeTooltipWidget w = new NativeTooltipWidget(a))
            {
                Assert.True(w.Show(DenseScrollablePayload()));
                if (!w.Scrollable) return; // 样本保证可滚；防线断以防内容不足
                // 权威语义（web dense-inspect）：未进 inspect 态一律放行——
                // 「visible+scrollable 任意位置即滚」已废弃。scan/pending、框内框外都不消费；
                // inspect 态 owner 区命中由 TooltipInspectionController 仲裁（其专属测试覆盖）。
                Rectangle b = w.PlacedRect;
                Point outside = new Point(b.X - 100, b.Y - 100);
                Point inside = new Point(b.X + b.Width / 2, b.Y + b.Height / 2);
                Assert.False(b.Contains(outside));
                Assert.False(NativeInteractionWheelRoute.Dispatch(w, outside.X, outside.Y, -120));
                Assert.False(NativeInteractionWheelRoute.Dispatch(w, inside.X, inside.Y, -120));
                Assert.Equal(0, w.ScrollLineOffset);
            }
        }

        [Fact]
        public void WheelRoute_DenseScrollable_AfterHide_SamePointReleases()
        {
            using (Control a = Anchor())
            using (NativeTooltipWidget w = new NativeTooltipWidget(a))
            {
                Assert.True(w.Show(DenseScrollablePayload()));
                Assert.True(w.Hide("tt-long"));
                Assert.False(NativeInteractionWheelRoute.Dispatch(w, 500, 200, -120));
            }
        }

        [Fact]
        public void WheelRoute_PinnedConsumesInside()
        {
            using (Control a = Anchor())
            using (NativeTooltipWidget w = new NativeTooltipWidget(a))
            {
                JObject p = JObject.Parse(@"{
                  'version':1,'requestId':'tt-p','sceneId':'s1','x':500,'y':200,
                  'document':{'version':1,'title':'固定检视','profile':'pinned',
                    'sections':[{'role':'intro','runs':[{'text':'内容'}]}]}}");
                Assert.True(w.Show(p));
                Rectangle b = w.PlacedRect;
                Point inside = new Point(b.X + b.Width / 2, b.Y + b.Height / 2);
                Assert.True(NativeInteractionWheelRoute.Dispatch(w, inside.X, inside.Y, -120));
                Assert.False(NativeInteractionWheelRoute.Dispatch(w, b.X - 50, b.Y - 50, -120));
            }
        }

        [Fact]
        public void WheelRoute_NoInstanceOrSimple_Releases()
        {
            using (Control a = Anchor())
            using (NativeTooltipWidget w = new NativeTooltipWidget(a))
            {
                Assert.False(NativeInteractionWheelRoute.Dispatch(w, 10, 10, -120));
                JObject p = JObject.Parse(@"{
                  'version':1,'requestId':'tt-s','sceneId':'s1','x':500,'y':200,
                  'document':{'version':1,'title':'短提示','profile':'simple',
                    'sections':[{'role':'intro','runs':[{'text':'内容'}]}]}}");
                Assert.True(w.Show(p));
                Rectangle b = w.PlacedRect;
                Assert.False(NativeInteractionWheelRoute.Dispatch(
                    w, b.X + b.Width / 2, b.Y + b.Height / 2, -120));
            }
        }

        [Fact]
        public void Widget_NoSession_NotVisible_EmptyBounds()
        {
            using (Control a = Anchor())
            {
                NpcMenuWidget w = new NpcMenuWidget(a);
                Assert.False(w.Visible);
                Assert.Equal(Rectangle.Empty, w.ScreenBounds);
                Assert.False(w.TryHitTest(new Point(50, 50)));
            }
        }

        // ── R1：pinned × 关闭 → 真实事件→task 桥（widget+adapter+task 全真） ──

        private static JObject PinnedPayload(string requestId)
        {
            return JObject.Parse(@"{
              'version':1,'kind':'tooltip','op':'show',
              'requestId':'" + requestId + @"','sceneId':'s1','x':500,'y':200,
              'document':{'version':1,'title':'固定检视','profile':'pinned',
                'sections':[{'role':'intro','runs':[{'text':'内容'}]}]}}");
        }

        private static JObject Wrap(JObject payload)
        {
            JObject m = new JObject();
            m["task"] = "native_interaction";
            m["payload"] = payload;
            return m;
        }

        private static NativeInteractionTask BridgeTask(
            NpcMenuWidget menu, NativeTooltipWidget tip, List<JObject> sent)
        {
            NativeInteractionTask task = new NativeInteractionTask(
                null, menu, new NativeTooltipSurfaceAdapter(tip),
                delegate(Action run) { run(); });
            task.SendPayloadOverride = delegate(string p)
            {
                sent.Add(JObject.Parse(p.TrimEnd('\0')));
                return true;
            };
            return task;
        }

        [Fact]
        public void PinnedCloseClick_RealEvent_ClosesAndSendsCancelOnce()
        {
            using (Control a = Anchor())
            using (NativeTooltipWidget tip = new NativeTooltipWidget(a))
            {
                NpcMenuWidget menu = new NpcMenuWidget(a);
                List<JObject> sent = new List<JObject>();
                NativeInteractionTask task = BridgeTask(menu, tip, sent);

                task.Handle(Wrap(PinnedPayload("ni:9")));
                Assert.Equal("ni:9", tip.CurrentRequestId);

                // 真实 × 命中路径：OnMouseEvent Down→Click 落在 plan.CloseRect
                Rectangle pr = tip.PlacedRect;
                Rectangle cr = tip.ActivePlan.CloseRect;
                Assert.False(cr.IsEmpty);
                Point closePt = new Point(
                    pr.X + cr.X + cr.Width / 2, pr.Y + cr.Y + cr.Height / 2);
                MouseEventArgs e = new MouseEventArgs(
                    MouseButtons.Left, 1, closePt.X, closePt.Y, 0);
                tip.OnMouseEvent(e, MouseEventKind.Down);
                tip.OnMouseEvent(e, MouseEventKind.Click);

                // R1 修复点：本地实例同步终结（AS2 handleCancel 不回 hide）
                Assert.Null(tip.CurrentRequestId);
                JObject cancel = Assert.Single(sent);
                Assert.Equal("nativeInteractionCancel", (string)cancel["action"]);
                Assert.Equal("ni:9", (string)cancel["requestId"]);
                Assert.Equal("s1", (string)cancel["sceneId"]);

                // 迟到 AS2 hide：不复活、不重复发包
                JObject late = new JObject();
                late["version"] = 1; late["kind"] = "tooltip"; late["op"] = "hide";
                late["requestId"] = "ni:9"; late["sceneId"] = "s1";
                task.Handle(Wrap(late));
                Assert.Single(sent);
                Assert.Null(tip.CurrentRequestId);
            }
        }

        [Fact]
        public void PinnedPanelSuspend_RealBridge_SingleCancelAndCleared()
        {
            using (Control a = Anchor())
            using (NativeTooltipWidget tip = new NativeTooltipWidget(a))
            {
                NpcMenuWidget menu = new NpcMenuWidget(a);
                List<JObject> sent = new List<JObject>();
                NativeInteractionTask task = BridgeTask(menu, tip, sent);

                task.Handle(Wrap(PinnedPayload("ni:10")));
                Assert.Equal("ni:10", tip.CurrentRequestId);

                // 生产路径：panel companion → task.OnPanelSuspending → widget.OnHostSuppressed
                // → DismissRequested（handler 内 Hide 清实例 + 一次 cancel）→ widget Clear（幂等）
                task.OnPanelSuspending();

                Assert.Null(tip.CurrentRequestId);
                JObject cancel = Assert.Single(sent);
                Assert.Equal("nativeInteractionCancel", (string)cancel["action"]);
                Assert.Equal("ni:10", (string)cancel["requestId"]);
                Assert.Equal("s1", (string)cancel["sceneId"]);
            }
        }
    }
}
