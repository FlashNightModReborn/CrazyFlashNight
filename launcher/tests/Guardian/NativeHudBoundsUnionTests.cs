using System;
using System.Collections.Generic;
using System.Drawing;
using System.Windows.Forms;
using CF7Launcher.Guardian;
using CF7Launcher.Guardian.Hud;
using Xunit;

namespace CF7Launcher.Tests.Guardian
{
    public class NativeHudBoundsUnionTests
    {
        [Fact]
        public void EmptyWidgetList_ReturnsNull()
        {
            Rectangle? r = NativeHudOverlay.ComputeBoundsUnion(new List<INativeHudWidget>(), 6);
            Assert.False(r.HasValue);
        }

        [Fact]
        public void NullList_ReturnsNull()
        {
            Rectangle? r = NativeHudOverlay.ComputeBoundsUnion(null, 6);
            Assert.False(r.HasValue);
        }

        [Fact]
        public void AllInvisibleWidgets_ReturnsNull()
        {
            var widgets = new List<INativeHudWidget>
            {
                new FakeWidget(new Rectangle(0, 0, 100, 50), visible: false),
                new FakeWidget(new Rectangle(200, 0, 100, 50), visible: false),
            };
            Assert.False(NativeHudOverlay.ComputeBoundsUnion(widgets, 6).HasValue);
        }

        [Fact]
        public void SingleVisibleWidget_ReturnsItsRectInflatedByPadding()
        {
            var widgets = new List<INativeHudWidget>
            {
                new FakeWidget(new Rectangle(100, 200, 50, 30), visible: true),
            };
            Rectangle? r = NativeHudOverlay.ComputeBoundsUnion(widgets, 6);
            Assert.True(r.HasValue);
            Assert.Equal(new Rectangle(94, 194, 62, 42), r.Value);
        }

        [Fact]
        public void MultipleVisibleWidgets_ReturnsUnionInflatedByPadding()
        {
            var widgets = new List<INativeHudWidget>
            {
                new FakeWidget(new Rectangle(0, 0, 100, 50), visible: true),
                new FakeWidget(new Rectangle(200, 100, 50, 50), visible: true),
            };
            Rectangle? r = NativeHudOverlay.ComputeBoundsUnion(widgets, 4);
            Assert.True(r.HasValue);
            // union: (0,0,250,150) → inflate(4,4) → (-4,-4,258,158)
            Assert.Equal(new Rectangle(-4, -4, 258, 158), r.Value);
        }

        [Fact]
        public void InvisibleWidgetsSkipped_OnlyVisibleContributesToUnion()
        {
            var widgets = new List<INativeHudWidget>
            {
                new FakeWidget(new Rectangle(0, 0, 100, 50), visible: true),
                new FakeWidget(new Rectangle(500, 500, 100, 100), visible: false), // 不可见，不应进入 union
                new FakeWidget(new Rectangle(50, 0, 50, 50), visible: true),
            };
            Rectangle? r = NativeHudOverlay.ComputeBoundsUnion(widgets, 0);
            Assert.True(r.HasValue);
            Assert.Equal(new Rectangle(0, 0, 100, 50), r.Value);
        }

        [Fact]
        public void ZeroSizeWidget_Skipped()
        {
            var widgets = new List<INativeHudWidget>
            {
                new FakeWidget(new Rectangle(50, 50, 0, 0), visible: true),
                new FakeWidget(new Rectangle(100, 100, 20, 10), visible: true),
            };
            Rectangle? r = NativeHudOverlay.ComputeBoundsUnion(widgets, 0);
            Assert.True(r.HasValue);
            // 零矩形跳过，仅第二个进入
            Assert.Equal(new Rectangle(100, 100, 20, 10), r.Value);
        }

        [Fact]
        public void ShouldRunAnimationTick_NoVisibleWidgetWantsTick_ReturnsFalse()
        {
            var widgets = new List<INativeHudWidget>
            {
                new FakeWidget(new Rectangle(0, 0, 10, 10), visible: true, wantsTick: false),
                new FakeWidget(new Rectangle(0, 0, 10, 10), visible: false, wantsTick: true), // 不可见 widget 即便 wantsTick 也忽略
            };
            Assert.False(NativeHudOverlay.ShouldRunAnimationTick(widgets));
        }

        [Fact]
        public void ShouldRunAnimationTick_AnyVisibleWidgetWantsTick_ReturnsTrue()
        {
            var widgets = new List<INativeHudWidget>
            {
                new FakeWidget(new Rectangle(0, 0, 10, 10), visible: true, wantsTick: false),
                new FakeWidget(new Rectangle(0, 0, 10, 10), visible: true, wantsTick: true),
            };
            Assert.True(NativeHudOverlay.ShouldRunAnimationTick(widgets));
        }

        [Fact]
        public void ShouldRunAnimationTick_EmptyOrNull_ReturnsFalse()
        {
            Assert.False(NativeHudOverlay.ShouldRunAnimationTick(new List<INativeHudWidget>()));
            Assert.False(NativeHudOverlay.ShouldRunAnimationTick(null));
        }

        // Test fixture
        private sealed class FakeWidget : INativeHudWidget
        {
            private readonly Rectangle _bounds;
            private readonly bool _visible;
            private readonly bool _wantsTick;
            public FakeWidget(Rectangle bounds, bool visible, bool wantsTick = false)
            {
                _bounds = bounds;
                _visible = visible;
                _wantsTick = wantsTick;
            }
            public Rectangle ScreenBounds { get { return _bounds; } }
            public bool Visible { get { return _visible; } }
            public void Paint(Graphics g, float dpr, Point hudOrigin) { }
            public bool TryHitTest(Point screenPt) { return false; }
            public void OnMouseEvent(MouseEventArgs e, MouseEventKind kind) { }
            public bool WantsAnimationTick { get { return _wantsTick; } }
            public void Tick(int deltaMs) { }
            public event EventHandler BoundsOrVisibilityChanged { add { } remove { } }
            public event EventHandler RepaintRequested { add { } remove { } }
            public event EventHandler AnimationStateChanged { add { } remove { } }
        }
    }
}
