using System;
using System.Drawing;
using System.Windows.Forms;
using CF7Launcher.Guardian.Hud.Tooltip;
using CF7Launcher.Guardian.Hud;
using Newtonsoft.Json.Linq;
using Xunit;

namespace CF7Launcher.Tests.Guardian.Tooltip
{
    public sealed class NativeTooltipPointerFeedbackTests
    {
        private static JObject Payload(string id, string profile = "dense") => JObject.Parse(@"{
            'version':1, 'requestId':'" + id + @"', 'sceneId':'s1', 'x':700, 'y':200,
            'document':{'version':1,'profile':'" + profile + @"','title':'测试',
            'sections':[{'role':'body','runs':[{'text':'密集图标中的说明文字'}]}]}}");

        [Fact]
        public void Dense_MoveAcrossIcons_FollowsLatestPointer_WithoutRemeasuringOrHitTesting()
        {
            using var anchor = new Control { Size = new Size(1024, 576) };
            using var widget = new NativeTooltipWidget(anchor, null, () => 1f);
            widget.Show(Payload("ni:1"));
            var plan = widget.ActivePlan;
            int boundsEvents = 0;
            widget.BoundsOrVisibilityChanged += (_, _) => boundsEvents++;
            for (int x = 160; x < 950; x += 13)
            {
                var point = new Point(x, 250 + x % 80);
                widget.QueuePointerMove(x - 5, point.Y);
                widget.QueuePointerMove(x, point.Y);
                widget.FlushPointerMove();
                Assert.False(widget.PlacedRect.Contains(point));
                Assert.False(widget.TryHitTest(point));
                Assert.Same(plan, widget.ActivePlan);
            }
            Assert.True(boundsEvents > 0);
            int before = boundsEvents;
            widget.QueuePointerMove(940, 310);
            widget.FlushPointerMove();
            before = boundsEvents;
            widget.QueuePointerMove(940, 310);
            widget.FlushPointerMove();
            Assert.Equal(before, boundsEvents);
        }

        [Fact]
        public void RealIconRect_StaysClearAndStableDuringCellHover()
        {
            using var anchor = new Control { Size = new Size(1024, 576) };
            using var widget = new NativeTooltipWidget(anchor, null, () => 1f);
            JObject payload = Payload("ni:1");
            payload["x"] = 620; payload["y"] = 220;
            payload["anchorRect"] = JObject.Parse("{'x':600,'y':200,'width':72,'height':72}");
            widget.Show(payload);
            var cell = new Rectangle(600, 200, 72, 72);
            Assert.Equal(cell, widget.OwnerScreenBounds);
            var placed = widget.PlacedRect;
            Assert.False(placed.IntersectsWith(cell));
            for (int y = 204; y < 270; y += 8)
                for (int x = 604; x < 670; x += 8)
                {
                    widget.QueuePointerMove(x, y);
                    widget.FlushPointerMove();
                    Assert.Equal(placed, widget.PlacedRect);
                    Assert.False(widget.PlacedRect.Contains(x, y));
                }
            widget.QueuePointerMove(700, 220); // owner leave 等 AS2 hide，不拖走旧注释
            widget.FlushPointerMove();
            Assert.Equal(placed, widget.PlacedRect);
        }

        [Theory]
        [InlineData("null")]
        [InlineData("[]")]
        [InlineData("{'x':0,'y':0,'width':-1,'height':20}")]
        [InlineData("{'x':0,'y':0,'width':100000000,'height':20}")]
        [InlineData("{'x':0,'y':0,'height':20}")]
        public void InvalidOwnerRectangle_IsRejectedWithoutThrowing(string rectangle)
        {
            var payload = Payload("ni:1");
            payload["anchorRect"] = JToken.Parse(rectangle);
            Assert.Null(NativeTooltipDocument.FromPayload(payload));
        }

        [Fact]
        public void RealIconRect_UsesFlashLetterboxCoordinatesAtHighDpi()
        {
            using var anchor = new Control { Size = new Size(1500, 900) };
            using var widget = new NativeTooltipWidget(anchor, null, () => 1.5f);
            JObject payload = Payload("ni:1");
            payload["anchorRect"] = JObject.Parse("{'x':512,'y':288,'width':64,'height':64}");
            widget.Show(payload);
            // 1500x900 的 Flash 16:9 舞台上下各留 28.125px。
            Assert.Equal(new Rectangle(750, 450, 93, 93), widget.OwnerScreenBounds);
        }

        [Fact]
        public void PendingMove_CannotMoveNewRequest_OrResurrectHiddenTooltip()
        {
            using var anchor = new Control { Size = new Size(1024, 576) };
            using var widget = new NativeTooltipWidget(anchor);
            widget.Show(Payload("ni:1"));
            widget.QueuePointerMove(30, 40);
            widget.Show(Payload("ni:2"));
            var next = widget.PlacedRect;
            widget.FlushPointerMove();
            Assert.Equal(next, widget.PlacedRect);
            widget.QueuePointerMove(60, 50);
            widget.Hide("ni:2");
            widget.FlushPointerMove();
            Assert.False(widget.Visible);
        }

        [Theory]
        [InlineData("simple")]
        [InlineData("pinned")]
        public void ReadingSurface_DoesNotRunAwayFromPointer(string profile)
        {
            using var anchor = new Control { Size = new Size(1024, 576) };
            using var widget = new NativeTooltipWidget(anchor);
            widget.Show(Payload("ni:1", profile));
            var before = widget.PlacedRect;
            widget.QueuePointerMove(before.X + 2, before.Y + 2);
            widget.FlushPointerMove();
            Assert.Equal(before, widget.PlacedRect);
        }

        [Fact]
        public void MovingTooltip_RefreshesProductionInspectionHitGeometry()
        {
            using var anchor = new Control { Size = new Size(1024, 576) };
            using var widget = new NativeTooltipWidget(anchor);
            var surface = new NativeTooltipSurfaceAdapter(widget);
            Point pointer = new Point(600, 300);
            using var controller = new TooltipInspectionController(surface, null, () => pointer, null);
            try
            {
                NativeInteractionWheelRoute.AttachInspection(controller, widget);
                widget.Show(Payload("ni:1", "simple"));
                controller.Sync();
                var before = controller.GetSnapshot().ScreenBounds;
                pointer = new Point(120, 450);
                widget.QueuePointerMove(pointer.X, pointer.Y);
                widget.FlushPointerMove();
                Assert.NotEqual(before, widget.ScreenBounds);
                Assert.Equal(widget.ScreenBounds, controller.GetSnapshot().ScreenBounds);
            }
            finally { NativeInteractionWheelRoute.DetachInspection(); }
        }

        [Fact]
        public void OutsideClient_DoesNotDragTooltipAcrossDesktop()
        {
            using var anchor = new Control { Size = new Size(1024, 576) };
            using var widget = new NativeTooltipWidget(anchor);
            widget.Show(Payload("ni:1"));
            var before = widget.PlacedRect;
            widget.QueuePointerMove(-200, -200);
            widget.FlushPointerMove();
            Assert.Equal(before, widget.PlacedRect);
        }
    }
}
