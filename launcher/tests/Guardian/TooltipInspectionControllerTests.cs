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
    /// TooltipInspectionController 定向回归——权威 = 迁移前 web tooltip.js 三 profile 语义。
    /// 全部经 ManualPump + 假时钟 + 假指针驱动，零 sleep。
    /// dense：scan→pending(1000ms)→inspect、快速运动复位、inspect-only owner 滚轮（边界不穿透）、
    /// Esc 退 scan；simple：复合悬停 140ms 过桥 + 框内仅实际滚动才消费；
    /// pinned：外点关闭；identity：迟到消息不得重获旧身份。
    /// </summary>
    public sealed class TooltipInspectionControllerTests
    {
        // ── 测试基建 ──

        private sealed class ManualPump : ITooltipInspectionPump
        {
            public bool Running;
            public int Starts;
            public int Stops;
            public event Action Tick;
            public void Start() { Running = true; Starts++; }
            public void Stop() { Running = false; Stops++; }
            public void Fire() { Action h = Tick; if (h != null) h(); }
            public void Dispose() { }
        }

        private sealed class FakeSurface : INativeInteractionTooltipSurface
        {
            public NativeTooltipDocument Doc;
            public bool ScrollableFlag;
            public Rectangle Bounds = new Rectangle(100, 100, 200, 120);
            public Rectangle? Owner;
            public int ScrollCalls;
            public int LastScrollDelta;
            public bool ScrollResult = true;
            public int HideCalls;
            public string LastHideId;
            public readonly List<string> ProjectionLog = new List<string>();

            public event Action<string> DismissRequested;

            public bool Show(JObject payload) { Doc = NativeTooltipDocument.FromPayload(payload); return Doc != null; }
            public bool Hide(string requestId)
            {
                HideCalls++;
                LastHideId = requestId;
                if (Doc != null && Doc.RequestId == requestId) Doc = null;
                return true;
            }
            public void Reset() { Doc = null; }
            public void OnHostSuppressed(string reason) { Doc = null; }
            public string CurrentSceneId { get { return Doc != null ? Doc.SceneId : null; } }
            public string CurrentRequestId { get { return Doc != null ? Doc.RequestId : null; } }
            public bool HasPinnedSession
            {
                get { return Doc != null && Doc.Profile == NativeTooltipProfile.Pinned; }
            }
            public NativeTooltipDocument ActiveDocument { get { return Doc; } }
            public bool Scrollable { get { return ScrollableFlag; } }
            public Rectangle ScreenBounds { get { return Bounds; } }
            public Rectangle? OwnerScreenBounds { get { return Owner; } }
            public bool ScrollByLines(int delta) { ScrollCalls++; LastScrollDelta = delta; return ScrollResult; }
            public void SetInspectionState(string state, int remainingMs)
            {
                ProjectionLog.Add(state + ":" + remainingMs);
            }
            public void FireDismiss(string rid) { Action<string> h = DismissRequested; if (h != null) h(rid); }
        }

        private sealed class Rig
        {
            public FakeSurface Surface = new FakeSurface();
            public ManualPump Pump = new ManualPump();
            public Point Ptr = new Point(50, 50);
            public long Now;
            public readonly TooltipInspectionController Ctl;

            public Rig()
            {
                Ctl = new TooltipInspectionController(Surface, Pump, () => Ptr, () => Now);
            }
        }

        private static JObject Payload(string rid, string profile, string sceneId)
        {
            return Payload(rid, profile, sceneId, false);
        }

        private static JObject Payload(string rid, string profile, string sceneId, bool longDesc)
        {
            string text = longDesc
                ? "长正文" + new string('密', 2400)
                : "简短描述";
            return JObject.Parse(@"{
              'version':1,'requestId':'" + rid + @"','sceneId':'" + sceneId + @"','x':200,'y':200,
              'document':{'version':1,'title':'测试','profile':'" + profile + @"',
                'sections':[
                  {'role':'intro','runs':[{'text':'物品'}]},
                  {'role':'description','runs':[{'text':'" + text + @"'}]}
                ]}}");
        }

        private static NativeTooltipDocument Doc(FakeSurface s, string rid, string profile)
        {
            NativeTooltipDocument d = NativeTooltipDocument.FromPayload(Payload(rid, profile, "s1"));
            s.Doc = d;
            return d;
        }

        // ── dense：scan→pending→inspect ──

        [Fact]
        public void Dense_Scrollable_Show_EntersPending_WithFullDelay()
        {
            Rig r = new Rig();
            r.Surface.Owner = new Rectangle(0, 0, 1024, 576);
            r.Surface.ScrollableFlag = true;
            Doc(r.Surface, "ni:1", "dense");
            r.Ctl.Sync();
            Assert.Equal(TooltipInspectionPhase.Pending, r.Ctl.CurrentPhase);
            Assert.True(r.Pump.Running, "pending 期间泵应运行");
            Assert.Contains("pending:", r.Surface.ProjectionLog[r.Surface.ProjectionLog.Count - 1]);
        }

        [Fact]
        public void Dense_NotScrollable_Show_StaysScan()
        {
            Rig r = new Rig();
            r.Surface.ScrollableFlag = false;
            Doc(r.Surface, "ni:1", "dense");
            r.Ctl.Sync();
            Assert.Equal(TooltipInspectionPhase.Scan, r.Ctl.CurrentPhase);
            Assert.False(r.Ctl.EscConsumable);
        }

        [Fact]
        public void Dense_Pending_AdvancesToInspect_After1000ms()
        {
            Rig r = new Rig();
            r.Surface.Owner = new Rectangle(0, 0, 1024, 576);
            r.Surface.ScrollableFlag = true;
            Doc(r.Surface, "ni:1", "dense");
            r.Ctl.Sync();
            r.Now = 999; r.Pump.Fire();
            Assert.Equal(TooltipInspectionPhase.Pending, r.Ctl.CurrentPhase);
            r.Now = 1000; r.Pump.Fire();
            Assert.Equal(TooltipInspectionPhase.Inspect, r.Ctl.CurrentPhase);
            Assert.False(r.Pump.Running, "inspect 态泵应停");
            Assert.Equal("inspect:0", r.Surface.ProjectionLog[r.Surface.ProjectionLog.Count - 1]);
        }

        [Fact]
        public void Dense_FastMove_ResetsPendingTimer()
        {
            Rig r = new Rig();
            r.Surface.Owner = new Rectangle(0, 0, 1024, 576);
            r.Surface.ScrollableFlag = true;
            Doc(r.Surface, "ni:1", "dense");
            r.Ctl.Sync();               // t=0, lastPt=(50,50)
            r.Now = 500; r.Pump.Fire(); // 静止 → 已驻留 500ms
            Assert.Equal(TooltipInspectionPhase.Pending, r.Ctl.CurrentPhase);
            r.Ptr = new Point(100, 50); // 位移 50 ≥ 24 → 合格快速运动
            r.Now = 600; r.Pump.Fire();
            Assert.Equal(TooltipInspectionPhase.Pending, r.Ctl.CurrentPhase);
            r.Now = 1599; r.Pump.Fire();
            Assert.Equal(TooltipInspectionPhase.Pending, r.Ctl.CurrentPhase);
            r.Now = 1600; r.Pump.Fire(); // 复位后满 1000ms
            Assert.Equal(TooltipInspectionPhase.Inspect, r.Ctl.CurrentPhase);
        }

        [Fact]
        public void Dense_SmallSlowMove_DoesNotReset()
        {
            Rig r = new Rig();
            r.Surface.Owner = new Rectangle(0, 0, 1024, 576);
            r.Surface.ScrollableFlag = true;
            Doc(r.Surface, "ni:1", "dense");
            r.Ctl.Sync();
            r.Ptr = new Point(55, 50);   // 位移 5 < 8 tolerance
            r.Now = 500; r.Pump.Fire();
            r.Now = 1000; r.Pump.Fire(); // 未复位 → 到点晋级
            Assert.Equal(TooltipInspectionPhase.Inspect, r.Ctl.CurrentPhase);
        }

        [Fact]
        public void Dense_MoveOutsideOwner_DoesNotCountAsMotion()
        {
            // owner 区有界时，区外指针运动不算 owner hover 运动（web：事件落在 owner 上才计）
            Rig r = new Rig();
            r.Surface.Owner = new Rectangle(0, 0, 80, 80);
            r.Ptr = new Point(40, 40);   // owner 内
            r.Surface.ScrollableFlag = true;
            Doc(r.Surface, "ni:1", "dense");
            r.Ctl.Sync();
            r.Ptr = new Point(500, 500); // 跳出 owner 区
            r.Now = 500; r.Pump.Fire();
            r.Ptr = new Point(40, 40);   // 回到 owner 内（区外那次移动已不算）
            r.Now = 1000; r.Pump.Fire();
            Assert.Equal(TooltipInspectionPhase.Inspect, r.Ctl.CurrentPhase);
        }

        // ── dense：inspect-only owner 滚轮 ──

        [Fact]
        public void Wheel_ScanAndPending_NeverConsume()
        {
            Rig r = new Rig();
            r.Surface.Owner = new Rectangle(0, 0, 1024, 576);
            r.Surface.ScrollableFlag = true;
            Doc(r.Surface, "ni:1", "dense");
            r.Ctl.Sync(); // pending
            Assert.False(r.Ctl.TryConsumeWheel(50, 50, -120));
            Assert.Equal(0, r.Surface.ScrollCalls);
        }

        [Fact]
        public void Wheel_Inspect_InsideOwner_ConsumesEvenAtBoundary()
        {
            Rig r = new Rig();
            r.Surface.Owner = new Rectangle(0, 0, 200, 200);
            r.Surface.ScrollableFlag = true;
            Doc(r.Surface, "ni:1", "dense");
            r.Ctl.Sync();
            r.Now = 1000; r.Pump.Fire(); // → inspect
            Assert.True(r.Ctl.TryConsumeWheel(50, 50, -120));
            Assert.Equal(3, r.Surface.LastScrollDelta);
            r.Surface.ScrollResult = false; // 已到边界
            Assert.True(r.Ctl.TryConsumeWheel(50, 50, -120), "inspect 到边界仍消费，不穿透");
        }

        [Fact]
        public void Wheel_Inspect_OutsideOwner_Released()
        {
            Rig r = new Rig();
            r.Surface.Owner = new Rectangle(0, 0, 200, 200);
            r.Surface.ScrollableFlag = true;
            Doc(r.Surface, "ni:1", "dense");
            r.Ctl.Sync();
            r.Now = 1000; r.Pump.Fire();
            Assert.False(r.Ctl.TryConsumeWheel(900, 500, -120));
            Assert.Equal(0, r.Surface.ScrollCalls);
        }

        [Fact]
        public void Wheel_Inspect_NoOwnerBounds_FailOpen()
        {
            // root 约定：缺 owner 几何时至少限定 Flash 客户区——无几何可用则不拦轮
            Rig r = new Rig();
            r.Surface.Owner = null;
            r.Surface.ScrollableFlag = true;
            Doc(r.Surface, "ni:1", "dense");
            r.Ctl.Sync();
            r.Now = 1000; r.Pump.Fire();
            Assert.Equal(TooltipInspectionPhase.Inspect, r.Ctl.CurrentPhase);
            Assert.False(r.Ctl.TryConsumeWheel(50, 50, -120), "无 owner 区不拦轮（不能全桌面拦轮）");
            Assert.Equal(0, r.Surface.ScrollCalls);
        }

        // ── dense：Esc inspect→scan ──

        [Fact]
        public void Esc_Inspect_ReturnsToScan_WithoutHide()
        {
            Rig r = new Rig();
            r.Surface.Owner = new Rectangle(0, 0, 1024, 576);
            r.Surface.ScrollableFlag = true;
            Doc(r.Surface, "ni:1", "dense");
            r.Ctl.Sync();
            r.Now = 1000; r.Pump.Fire();
            Assert.True(r.Ctl.EscConsumable);
            Assert.True(r.Ctl.ExitInspection());
            Assert.Equal(TooltipInspectionPhase.Scan, r.Ctl.CurrentPhase);
            Assert.NotNull(r.Surface.Doc); // Esc 退检视不得 hide
            Assert.Equal(0, r.Surface.HideCalls);
            Assert.False(r.Ctl.TryConsumeWheel(50, 50, -120), "退回 scan 后滚轮放行");
            Assert.True(r.Pump.Running, "scan 继续采样复位运动");
        }

        [Fact]
        public void Esc_AfterScan_FastMove_Repend_ThenInspect()
        {
            Rig r = new Rig();
            r.Surface.Owner = new Rectangle(0, 0, 1024, 576);
            r.Surface.ScrollableFlag = true;
            Doc(r.Surface, "ni:1", "dense");
            r.Ctl.Sync();
            r.Now = 1000; r.Pump.Fire();
            r.Ctl.ExitInspection();          // → scan
            r.Now = 1100; r.Pump.Fire();     // scan 静止不晋级
            Assert.Equal(TooltipInspectionPhase.Scan, r.Ctl.CurrentPhase);
            r.Ptr = new Point(120, 50);      // 快速运动
            r.Now = 1150; r.Pump.Fire();
            Assert.Equal(TooltipInspectionPhase.Pending, r.Ctl.CurrentPhase);
            r.Now = 2150; r.Pump.Fire();     // 复位后满 1000ms
            Assert.Equal(TooltipInspectionPhase.Inspect, r.Ctl.CurrentPhase);
        }

        [Fact]
        public void Esc_OutsideOwner_NotConsumable()
        {
            Rig r = new Rig();
            r.Surface.Owner = new Rectangle(0, 0, 100, 100);
            r.Ptr = new Point(40, 40);
            r.Surface.ScrollableFlag = true;
            Doc(r.Surface, "ni:1", "dense");
            r.Ctl.Sync();
            r.Now = 1000;
            r.Ptr = new Point(500, 500); // 指针离开 owner
            r.Pump.Fire();
            Assert.Equal(TooltipInspectionPhase.Inspect, r.Ctl.CurrentPhase);
            Assert.False(r.Ctl.EscConsumable, "指针不在 owner 上时 Esc 不被吞");
        }

        // ── dense：内容刷新 / 身份 ──

        [Fact]
        public void ContentRefresh_SameRid_AfterEsc_ReinspectImmediately()
        {
            Rig r = new Rig();
            r.Surface.Owner = new Rectangle(0, 0, 1024, 576);
            r.Surface.ScrollableFlag = true;
            Doc(r.Surface, "ni:1", "dense");
            r.Ctl.Sync();
            r.Now = 1000; r.Pump.Fire();
            r.Ctl.ExitInspection(); // scan，dwellStartedAt 保持
            // 同 rid 内容刷新（web updateContent→contentChanged）：已停够 → 直接回 inspect
            Doc(r.Surface, "ni:1", "dense");
            r.Now = 1300;
            r.Ctl.Sync();
            Assert.Equal(TooltipInspectionPhase.Inspect, r.Ctl.CurrentPhase);
        }

        [Fact]
        public void ContentRefresh_Inspect_NoLongerScrollable_BackToScan()
        {
            Rig r = new Rig();
            r.Surface.Owner = new Rectangle(0, 0, 1024, 576);
            r.Surface.ScrollableFlag = true;
            Doc(r.Surface, "ni:1", "dense");
            r.Ctl.Sync();
            r.Now = 1000; r.Pump.Fire();
            Assert.Equal(TooltipInspectionPhase.Inspect, r.Ctl.CurrentPhase);
            r.Surface.ScrollableFlag = false; // 刷新后 desc 不再溢出
            r.Ctl.Sync();
            Assert.Equal(TooltipInspectionPhase.Scan, r.Ctl.CurrentPhase);
        }

        [Fact]
        public void NewRid_Show_ResetsDwell()
        {
            Rig r = new Rig();
            r.Surface.Owner = new Rectangle(0, 0, 1024, 576);
            r.Surface.ScrollableFlag = true;
            Doc(r.Surface, "ni:1", "dense");
            r.Ctl.Sync();
            r.Now = 900;
            Doc(r.Surface, "ni:2", "dense"); // 换实例
            r.Ctl.Sync();
            Assert.Equal(TooltipInspectionPhase.Pending, r.Ctl.CurrentPhase);
            r.Now = 1000; r.Pump.Fire();
            Assert.Equal(TooltipInspectionPhase.Pending, r.Ctl.CurrentPhase); // 新实例重新计时
            r.Now = 1900; r.Pump.Fire();
            Assert.Equal(TooltipInspectionPhase.Inspect, r.Ctl.CurrentPhase);
        }

        [Fact]
        public void StaleHide_DenseOrForeignRid_NeverDefers()
        {
            Rig r = new Rig();
            Doc(r.Surface, "ni:5", "dense");
            r.Ctl.Sync();
            Assert.False(r.Ctl.TryDeferHide("ni:9"), "非当前 rid 不得接管");
            Assert.False(r.Ctl.TryDeferHide("ni:5"), "dense hide 不延迟");
        }

        [Fact]
        public void DocCleared_Externally_TeardownStopsPump()
        {
            Rig r = new Rig();
            r.Surface.ScrollableFlag = true;
            Doc(r.Surface, "ni:1", "dense");
            r.Ctl.Sync();
            r.Surface.Doc = null; // 外部 hide/reset
            r.Pump.Fire();
            Assert.Equal(TooltipInspectionPhase.Idle, r.Ctl.CurrentPhase);
            Assert.Null(r.Ctl.GetSnapshot());
            Assert.False(r.Pump.Running);
            Assert.False(r.Ctl.EscConsumable);
            Assert.False(r.Ctl.TryConsumeWheel(50, 50, -120));
        }

        // ── simple：复合悬停 + 框内滚轮 ──

        [Fact]
        public void Simple_Hide_PointerInside_DeferredAndHeld()
        {
            Rig r = new Rig();
            r.Ptr = new Point(150, 150); // 浮层 rect (100,100,200,120) 内
            Doc(r.Surface, "ni:7", "simple");
            r.Ctl.Sync();
            Assert.True(r.Ctl.TryDeferHide("ni:7"));
            Assert.NotNull(r.Surface.Doc);
            Assert.Equal(0, r.Surface.HideCalls); // held 期间不得真 hide
            r.Now = 50; r.Pump.Fire();
            Assert.NotNull(r.Surface.Doc);
        }

        [Fact]
        public void Simple_Held_LeaveRect_HidesAfter140msGrace()
        {
            Rig r = new Rig();
            r.Ptr = new Point(150, 150);
            Doc(r.Surface, "ni:7", "simple");
            r.Ctl.Sync();
            Assert.True(r.Ctl.TryDeferHide("ni:7"));
            r.Ptr = new Point(0, 0);      // 离开浮层
            r.Now = 50; r.Pump.Fire();    // 记 exitSince=50
            Assert.NotNull(r.Surface.Doc);
            r.Now = 150; r.Pump.Fire();   // 100ms 宽限未到
            Assert.NotNull(r.Surface.Doc);
            r.Now = 191; r.Pump.Fire();   // ≥140ms → 真 hide
            Assert.Equal(1, r.Surface.HideCalls);
            Assert.Null(r.Surface.Doc);
        }

        [Fact]
        public void Simple_Hide_EntersWithin140ms_Holds()
        {
            Rig r = new Rig();
            r.Ptr = new Point(0, 0);      // 起初不在浮层内
            Doc(r.Surface, "ni:7", "simple");
            r.Ctl.Sync();
            Assert.True(r.Ctl.TryDeferHide("ni:7"), "simple hide 一律进过桥窗");
            r.Now = 100;
            r.Ptr = new Point(150, 150);  // 窗内进入
            r.Pump.Fire();
            r.Now = 500; r.Pump.Fire();   // 窗早已过但已 held
            Assert.NotNull(r.Surface.Doc);
            Assert.Equal(0, r.Surface.HideCalls);
        }

        [Fact]
        public void Simple_Hide_NeverInside_HidesAtDeadline()
        {
            Rig r = new Rig();
            r.Ptr = new Point(0, 0);
            Doc(r.Surface, "ni:7", "simple");
            r.Ctl.Sync();
            Assert.True(r.Ctl.TryDeferHide("ni:7"));
            r.Now = 139; r.Pump.Fire();
            Assert.NotNull(r.Surface.Doc);
            r.Now = 140; r.Pump.Fire();
            Assert.Equal(1, r.Surface.HideCalls);
            Assert.Null(r.Surface.Doc);
        }

        [Fact]
        public void Simple_Wheel_InsideRect_ConsumesOnlyWhenScrolled()
        {
            Rig r = new Rig();
            r.Surface.ScrollableFlag = true;
            Doc(r.Surface, "ni:7", "simple");
            r.Ctl.Sync();
            Assert.True(r.Ctl.TryConsumeWheel(150, 150, -120), "框内实际滚动→消费");
            r.Surface.ScrollResult = false; // 边界
            Assert.False(r.Ctl.TryConsumeWheel(150, 150, -120), "simple 到边界放行穿透");
            Assert.False(r.Ctl.TryConsumeWheel(500, 500, -120), "框外放行");
        }

        // ── pinned：外点关闭 ──

        [Fact]
        public void Pinned_OutsideClick_Dismisses_InsideAndOwner_Keep()
        {
            Rig r = new Rig();
            r.Surface.Owner = new Rectangle(10, 10, 60, 60);
            Doc(r.Surface, "ni:8", "pinned");
            r.Ctl.Sync();
            Assert.Null(r.Ctl.TryDismissPinnedAt(150, 150)); // 浮层内
            Assert.Null(r.Ctl.TryDismissPinnedAt(30, 30));   // owner 区内（anchor 豁免）
            string rid = r.Ctl.TryDismissPinnedAt(900, 500); // 界外
            Assert.Equal("ni:8", rid);
            Assert.Null(r.Surface.Doc);
            Assert.Null(r.Ctl.TryDismissPinnedAt(900, 500)); // 已终结不再重复 dismiss
        }

        [Fact]
        public void Pinned_StaleDismiss_NoReacquire()
        {
            Rig r = new Rig();
            Doc(r.Surface, "ni:8", "pinned");
            r.Ctl.Sync();
            // 实例已轮换后再点：快照已清 → 不 dismiss 任何人
            Doc(r.Surface, "ni:9", "simple");
            r.Ctl.Sync();
            Assert.Null(r.Ctl.TryDismissPinnedAt(900, 500));
            Assert.NotNull(r.Surface.Doc);
        }

        // ── task 级集成（真实 Host 分派断言） ──

        private static JObject Envelope(JObject payload)
        {
            JObject m = new JObject();
            m["task"] = "native_interaction";
            m["payload"] = payload;
            return m;
        }

        private static JObject ShowMsg(string kind, string rid, string sceneId, string profile)
        {
            JObject p = JObject.Parse(@"{
              'version':1,'kind':'" + kind + @"','op':'show',
              'requestId':'" + rid + @"','sceneId':'" + sceneId + @"','x':200,'y':200}");
            if (profile != null)
            {
                JObject doc = JObject.Parse(@"{'version':1,'title':'t','profile':'" + profile + @"',
                    'sections':[{'role':'description','runs':[{'text':'x'}]}]}");
                p["document"] = doc;
            }
            return p;
        }

        [Fact]
        public void Task_TooltipShow_DrivesInspection_EscReturnsToScan()
        {
            var menu = new NpcMenuWidget(new Control { Size = new Size(1024, 576) });
            var surface = new FakeSurface();
            var pump = new ManualPump();
            Point ptr = new Point(50, 50);
            long now = 0;
            var ctl = new TooltipInspectionController(surface, pump, () => ptr, () => now);
            var task = new NativeInteractionTask(null, menu, surface, a => a(), ctl);

            surface.Owner = new Rectangle(0, 0, 1024, 576);
            surface.ScrollableFlag = true;
            task.Handle(Envelope(ShowMsg("tooltip", "ni:1", "s1", "dense")));
            Assert.Equal(TooltipInspectionPhase.Pending, ctl.CurrentPhase);
            now = 1000; pump.Fire();
            Assert.Equal(TooltipInspectionPhase.Inspect, ctl.CurrentPhase);
            Assert.True(task.IsInteractionEscapable(), "inspect 态 Esc 应被交互层认领");
            task.NotifyInteractionEscape();
            Assert.Equal(TooltipInspectionPhase.Scan, ctl.CurrentPhase);
            Assert.False(task.IsInteractionEscapable(), "退回 scan 不再吃 Esc");
            Assert.NotNull(surface.Doc);
        }

        [Fact]
        public void Task_PinnedShow_BlocksNonPinnedShow()
        {
            var menu = new NpcMenuWidget(new Control { Size = new Size(1024, 576) });
            var surface = new FakeSurface();
            var task = new NativeInteractionTask(null, menu, surface, a => a(),
                new TooltipInspectionController(surface, new ManualPump(), () => new Point(0, 0), () => 0L));
            task.Handle(Envelope(ShowMsg("tooltip", "ni:5", "s1", "pinned")));
            Assert.Equal(NativeTooltipProfile.Pinned, surface.Doc.Profile);
            task.Handle(Envelope(ShowMsg("tooltip", "ni:6", "s1", "dense")));
            Assert.Equal("ni:5", surface.CurrentRequestId); // 普通 show 不得顶替 pinned
            Assert.Equal(NativeTooltipProfile.Pinned, surface.Doc.Profile);
            task.Handle(Envelope(ShowMsg("tooltip", "ni:7", "s1", "pinned")));
            Assert.Equal("ni:7", surface.CurrentRequestId); // 新 pinned 可替换
        }

        [Fact]
        public void Task_PinnedOutsideClick_SendsCancelOnce()
        {
            var menu = new NpcMenuWidget(new Control { Size = new Size(1024, 576) });
            var surface = new FakeSurface();
            var pump = new ManualPump();
            var task = new NativeInteractionTask(null, menu, surface, a => a(),
                new TooltipInspectionController(surface, pump, () => new Point(0, 0), () => 0L));
            var sent = new List<string>();
            task.SendPayloadOverride = s => { sent.Add(s); return true; };
            surface.Owner = new Rectangle(10, 10, 60, 60);
            task.Handle(Envelope(ShowMsg("tooltip", "ni:8", "s9", "pinned")));

            task.NotifyPhysicalButtonDown(150, 150, 0x201);   // 浮层内 → 不关
            Assert.Empty(sent);
            task.NotifyPhysicalButtonDown(900, 500, 0x201);   // 界外 → 关 + cancel
            Assert.Single(sent);
            JObject cmd = JObject.Parse(sent[0].TrimEnd('\0'));
            Assert.Equal("nativeInteractionCancel", cmd.Value<string>("action"));
            Assert.Equal("ni:8", cmd.Value<string>("requestId"));
            Assert.Equal("s9", cmd.Value<string>("sceneId"));
            Assert.Null(surface.Doc);
            task.NotifyPhysicalButtonDown(900, 500, 0x201);   // 已终结不重复
            Assert.Single(sent);
        }

        [Fact]
        public void Task_StaleDismissRequest_Dropped()
        {
            var menu = new NpcMenuWidget(new Control { Size = new Size(1024, 576) });
            var surface = new FakeSurface();
            var task = new NativeInteractionTask(null, menu, surface, a => a(),
                new TooltipInspectionController(surface, new ManualPump(), () => new Point(0, 0), () => 0L));
            var sent = new List<string>();
            task.SendPayloadOverride = s => { sent.Add(s); return true; };
            task.Handle(Envelope(ShowMsg("tooltip", "ni:9", "s1", "pinned")));
            surface.FireDismiss("ni:4"); // 迟到 dismiss（旧身份）→ 不动当前、不发 cancel
            Assert.Empty(sent);
            Assert.Equal("ni:9", surface.CurrentRequestId);
            Assert.Equal(0, surface.HideCalls);
            surface.FireDismiss("ni:9"); // 当前身份 → 关 + cancel
            Assert.Single(sent);
            Assert.Null(surface.Doc);
        }

        [Fact]
        public void Task_SimpleHide_CompositeHold_ThenGraceHide()
        {
            var menu = new NpcMenuWidget(new Control { Size = new Size(1024, 576) });
            var surface = new FakeSurface();
            var pump = new ManualPump();
            Point ptr = new Point(150, 150); // 浮层内
            long now = 0;
            var ctl = new TooltipInspectionController(surface, pump, () => ptr, () => now);
            var task = new NativeInteractionTask(null, menu, surface, a => a(), ctl);
            task.Handle(Envelope(ShowMsg("tooltip", "ni:7", "s1", "simple")));
            Assert.NotNull(surface.Doc);
            // owner leave 的 hide 到来：指针在浮层内 → 保持
            JObject hide = new JObject();
            hide["version"] = 1; hide["kind"] = "tooltip"; hide["op"] = "hide";
            hide["requestId"] = "ni:7"; hide["sceneId"] = "s1";
            task.Handle(Envelope(hide));
            Assert.Equal(0, surface.HideCalls);
            Assert.NotNull(surface.Doc);
            ptr = new Point(0, 0);        // 离开浮层
            now = 50; pump.Fire();
            Assert.NotNull(surface.Doc);
            now = 200; pump.Fire();       // 宽限 140ms 耗尽
            Assert.Equal(1, surface.HideCalls);
            Assert.Null(surface.Doc);
        }
    }
}
