using System;
using System.Drawing;
using System.Runtime.ExceptionServices;
using System.Threading;
using System.Windows.Forms;
using CF7Launcher.Guardian.Hud;
using CF7Launcher.Guardian.Hud.Tooltip;
using Newtonsoft.Json.Linq;
using Xunit;

namespace CF7Launcher.Tests.Guardian
{
    /// <summary>
    /// ni04 反馈回归：dense 长文注释「pending 条出现但不能滚」。
    /// 与 TooltipInspectionControllerTests 的差别：走完整生产路由
    /// NativeTooltipSurfaceAdapter + 真 NativeTooltipWidget + TooltipInspectionController
    /// + NativeInteractionWheelRoute.Dispatch，且**不手工赋 OwnerScreenBounds**——
    /// 旧 bug 正是 getter 返回 null 导致 TryConsumeWheel 永远放行。
    /// 输入用例用真 WinFormsInspectionPump（STA + Application.DoEvents 有界驱动），
    /// 证明 Pending→Inspect 真实推进后滚轮才被消费；另附滚条 thumb 越界位图回归。
    /// </summary>
    public sealed class TooltipInspectionFeedbackTests
    {
        private static JObject DensePayload(string rid, string sceneId, int descLines)
        {
            string[] lines = new string[descLines];
            for (int i = 0; i < descLines; i++)
                lines[i] = "第" + (i + 1).ToString("00") + "行 说明文字说明文字";
            string desc = string.Join("\n", lines);
            return JObject.Parse(@"{
              'version':1,'requestId':'" + rid + @"','sceneId':'" + sceneId + @"',
              'x':750,'y':450,
              'document':{'version':1,'title':'测试','profile':'dense',
                'sections':[
                  {'role':'intro','runs':[{'text':'物品'}]},
                  {'role':'description','runs':[{'text':'" + desc + @"'}]}
                ]}}");
        }

        /// <summary>STA + DoEvents：真 System.Windows.Forms.Timer 只在有消息泵的线程上 Tick。</summary>
        private static void RunOnSta(Action body)
        {
            Exception error = null;
            Thread t = new Thread(delegate()
            {
                try { body(); }
                catch (Exception ex) { error = ex; }
            });
            t.SetApartmentState(ApartmentState.STA);
            t.Start();
            Assert.True(t.Join(TimeSpan.FromSeconds(30)), "STA 用例超时未结束");
            if (error != null) ExceptionDispatchInfo.Capture(error).Throw();
        }

        [Fact]
        public void RealTimer_ProductionRoute_PendingToInspect_WheelConsumes()
        {
            RunOnSta(delegate
            {
                using (Control anchor = new Control { Size = new Size(1500, 900) })
                using (NativeTooltipWidget widget =
                    new NativeTooltipWidget(anchor, null, () => 1.5f))
                {
                    NativeTooltipSurfaceAdapter surface = new NativeTooltipSurfaceAdapter(widget);
                    Point ptr = new Point(400, 400); // 始终在 anchor 客户区内
                    // pump=null → 生产默认 WinFormsInspectionPump；now=null → 真实钟。
                    using (TooltipInspectionController ctl =
                        new TooltipInspectionController(surface, null, () => ptr, null))
                    {
                        try
                        {
                            NativeInteractionWheelRoute.AttachInspection(ctl, widget);
                            Assert.True(widget.Show(DensePayload("ni:1", "s1", 40)));
                            Assert.True(widget.Scrollable, "长 desc 应可滚");
                            // owner 兜底：未手工赋值时返回 anchor 客户区（旧 bug 为 null）
                            Assert.Equal(new Rectangle(0, 0, 1500, 900), widget.OwnerScreenBounds);

                            ctl.Sync();
                            Assert.Equal(TooltipInspectionPhase.Pending, ctl.CurrentPhase);
                            Assert.Equal("pending", widget.CurrentInspectionState);
                            // pending 态滚轮放行（web：仅 inspecting 才接管 owner 滚轮）
                            Assert.False(NativeInteractionWheelRoute.Dispatch(widget, 400, 400, -120));

                            // 真泵驱动：DoEvents 派发 WM_TIMER，~1s 稳定驻留 → inspect。
                            // 同时证明每 tick 重复 UpdatePumpLocked→Start() 不打断计时器。
                            DateTime deadline = DateTime.UtcNow.AddSeconds(5);
                            while (ctl.CurrentPhase != TooltipInspectionPhase.Inspect
                                && DateTime.UtcNow < deadline)
                            {
                                Application.DoEvents();
                                Thread.Sleep(8);
                            }
                            Assert.Equal(TooltipInspectionPhase.Inspect, ctl.CurrentPhase);
                            Assert.Equal("inspect", widget.CurrentInspectionState);

                            // inspect + 客户区内：滚轮消费且实际滚动；边界仍消费不穿透
                            int before = widget.ScrollLineOffset;
                            Assert.True(NativeInteractionWheelRoute.Dispatch(widget, 400, 400, -120));
                            Assert.True(widget.ScrollLineOffset > before, "向下滚应推进 scrollLine");
                            Assert.True(NativeInteractionWheelRoute.Dispatch(widget, 400, 400, 120));
                            Assert.Equal(before, widget.ScrollLineOffset); // 上滚回到原位
                            // 客户区外放行（不全桌面拦轮）
                            Assert.False(NativeInteractionWheelRoute.Dispatch(widget, 9500, 9500, -120));

                            // Esc：inspect → scan，不 hide；滚轮重新放行
                            Assert.True(ctl.EscConsumable);
                            Assert.True(ctl.ExitInspection());
                            Assert.Equal(TooltipInspectionPhase.Scan, ctl.CurrentPhase);
                            Assert.False(NativeInteractionWheelRoute.Dispatch(widget, 400, 400, -120));
                            Assert.True(widget.Visible, "Esc 退检视不得 hide");

                            // 会话终结：reset + sync → 快照清空、路由放行
                            widget.Reset();
                            ctl.Sync();
                            Assert.Null(ctl.GetSnapshot());
                            Assert.False(NativeInteractionWheelRoute.Dispatch(widget, 400, 400, -120));
                        }
                        finally
                        {
                            NativeInteractionWheelRoute.DetachInspection();
                        }
                    }
                }
            });
        }

        /// <summary>
        /// 滚条 thumb 越界位图回归：29 行 desc 产生部分可见行
        /// （MaxScrollLine > total-visible），旧 DrawScrollbar 按 total-visible 做除数
        /// 会把滑块画出 DescPanel/PlacedRect 下缘。修复后按 plan.MaxScrollLine 分压并钳位。
        /// 断言：滚到底重绘后，滚条 x 带内 PlacedRect.Bottom 以下无任何非透明像素。
        /// </summary>
        [Fact]
        public void Scrollbar_Thumb_ClampedInsidePlacedRect_AtMaxScroll()
        {
            using (Control anchor = new Control { Size = new Size(1500, 900) })
            using (NativeTooltipWidget widget =
                new NativeTooltipWidget(anchor, null, () => 1.5f))
            {
                Assert.True(widget.Show(DensePayload("ni:2", "s1", 29)));
                Assert.True(widget.Scrollable, "29 行 desc 应可滚");
                NativeTooltipLayout.Plan plan = widget.ActivePlan;
                Assert.NotNull(plan);
                // 需处于「部分可见行」区间，否则旧除数也恰好正确、回归无意义
                Assert.True(plan.MaxScrollLine > plan.DescTotalLines - plan.DescVisibleLines,
                    "需 MaxScrollLine(" + plan.MaxScrollLine + ") > total-visible("
                    + (plan.DescTotalLines - plan.DescVisibleLines) + ") 才覆盖旧越界路径");

                Assert.True(widget.ScrollByLines(plan.MaxScrollLine), "滚到最大行");
                Assert.Equal(plan.MaxScrollLine, widget.ScrollLineOffset);

                Rectangle tip = widget.PlacedRect;
                Assert.False(tip.IsEmpty);
                using (Bitmap bmp = new Bitmap(1500, 900))
                using (Graphics g = Graphics.FromImage(bmp))
                {
                    g.Clear(Color.Transparent);
                    widget.Paint(g, 1f, Point.Empty);
                    // 滚条轨道 = DescPanel 右缘整条；取 tip 右缘内 24px 覆盖轨道+滑块带
                    int x0 = Math.Max(0, tip.Right - 24);
                    for (int y = tip.Bottom; y < bmp.Height; y++)
                        for (int x = x0; x < tip.Right && x < bmp.Width; x++)
                            Assert.True(bmp.GetPixel(x, y).A == 0,
                                "滚条像素越出 PlacedRect.Bottom: (" + x + "," + y + ")");
                }
            }
        }
    }
}
