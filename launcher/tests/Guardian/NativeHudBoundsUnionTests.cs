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

        // ── BuildLegacyTypeSet：legacy type 门控不变量 ──
        // FrameTask 每帧推 combo|...，QuestNotice 不订阅 combo → 整包必须早 return；
        // 否则每帧 BeginInvoke + DispatchLegacy 即便 widget 内 switch 默认 return，仍污染 UI 线程预算。

        [Fact]
        public void ComputeAnimationDelta_FirstTick_UsesFrameDelta()
        {
            Assert.Equal(16, NativeHudOverlay.ComputeAnimationDeltaForTest(0, 1000));
        }

        [Fact]
        public void ComputeAnimationDelta_LongUiGap_IsCapped()
        {
            Assert.Equal(50, NativeHudOverlay.ComputeAnimationDeltaForTest(1000, 5000));
        }

        [Fact]
        public void BuildLegacyTypeSet_NullOrEmpty_ReturnsEmpty()
        {
            Assert.Empty(NativeHudOverlay.BuildLegacyTypeSet(null));
            Assert.Empty(NativeHudOverlay.BuildLegacyTypeSet(new List<INativeHudWidget>()));
        }

        [Fact]
        public void BuildLegacyTypeSet_NoLegacyConsumers_ReturnsEmpty()
        {
            // 普通 INativeHudWidget 不实现 IUiDataLegacyConsumer
            var widgets = new List<INativeHudWidget>
            {
                new FakeWidget(new Rectangle(0, 0, 10, 10), visible: true),
            };
            Assert.Empty(NativeHudOverlay.BuildLegacyTypeSet(widgets));
        }

        [Fact]
        public void BuildLegacyTypeSet_QuestNoticeOnly_ContainsTaskAnnounce_NotCombo()
        {
            // 关键回归：注册 QuestNotice → set 含 task/announce；不含 combo / currency
            var widgets = new List<INativeHudWidget>
            {
                new FakeLegacyWidget(new[] { "task", "announce" }),
            };
            HashSet<string> set = NativeHudOverlay.BuildLegacyTypeSet(widgets);
            Assert.Contains("task", set);
            Assert.Contains("announce", set);
            Assert.DoesNotContain("combo", set);
            Assert.DoesNotContain("currency", set);
            Assert.Equal(2, set.Count);
        }

        [Fact]
        public void BuildLegacyTypeSet_MultipleConsumers_UnionsAllTypes()
        {
            // 未来 ComboWidget 加入后，set 应是 union
            var widgets = new List<INativeHudWidget>
            {
                new FakeLegacyWidget(new[] { "task", "announce" }),
                new FakeLegacyWidget(new[] { "combo" }),
            };
            HashSet<string> set = NativeHudOverlay.BuildLegacyTypeSet(widgets);
            Assert.Equal(3, set.Count);
            Assert.Contains("task", set);
            Assert.Contains("announce", set);
            Assert.Contains("combo", set);
        }

        [Fact]
        public void BuildLegacyTypeSet_NullOrEmptyTypeNames_Skipped()
        {
            var widgets = new List<INativeHudWidget>
            {
                new FakeLegacyWidget(new[] { "task", null, "", "announce" }),
            };
            HashSet<string> set = NativeHudOverlay.BuildLegacyTypeSet(widgets);
            Assert.Equal(2, set.Count);
            Assert.Contains("task", set);
            Assert.Contains("announce", set);
        }

        [Fact]
        public void BuildLegacyTypeSet_ConsumerWithNullTypes_HandledSafely()
        {
            var widgets = new List<INativeHudWidget>
            {
                new FakeLegacyWidget(null),
            };
            Assert.Empty(NativeHudOverlay.BuildLegacyTypeSet(widgets));
        }

        // ── BuildNoticeCategorySet：N 前缀 notice 门控不变量 ──
        // socket worker 每次 N 前缀（perf / icon_bake / wave / combo / ...）都会调 INotchSink.AddNotice；
        // 没人订阅的 category 必须早 return，不污染 UI 线程派发预算。

        [Fact]
        public void BuildNoticeCategorySet_NullOrEmpty_ReturnsEmpty()
        {
            Assert.Empty(NativeHudOverlay.BuildNoticeCategorySet(null));
            Assert.Empty(NativeHudOverlay.BuildNoticeCategorySet(new List<INativeHudWidget>()));
        }

        [Fact]
        public void BuildNoticeCategorySet_NoNoticeConsumers_ReturnsEmpty()
        {
            var widgets = new List<INativeHudWidget>
            {
                new FakeWidget(new Rectangle(0, 0, 10, 10), visible: true),
                new FakeLegacyWidget(new[] { "task" }), // legacy 但非 notice consumer
            };
            Assert.Empty(NativeHudOverlay.BuildNoticeCategorySet(widgets));
        }

        [Fact]
        public void BuildNoticeCategorySet_ComboOnly_ContainsCombo_NotPerf()
        {
            // 关键回归：ComboWidget 注册 → set={combo}；perf/icon_bake/wave 不在 set 中 → 整包早 return
            var widgets = new List<INativeHudWidget>
            {
                new FakeNoticeWidget(new[] { "combo" }),
            };
            HashSet<string> set = NativeHudOverlay.BuildNoticeCategorySet(widgets);
            Assert.Contains("combo", set);
            Assert.DoesNotContain("perf", set);
            Assert.DoesNotContain("icon_bake", set);
            Assert.DoesNotContain("game", set);
            Assert.Equal(1, set.Count);
        }

        [Fact]
        public void BuildNoticeCategorySet_MultipleConsumers_UnionsCategories()
        {
            var widgets = new List<INativeHudWidget>
            {
                new FakeNoticeWidget(new[] { "combo" }),
                new FakeNoticeWidget(new[] { "perf", "wave" }),
            };
            HashSet<string> set = NativeHudOverlay.BuildNoticeCategorySet(widgets);
            Assert.Equal(3, set.Count);
            Assert.Contains("combo", set);
            Assert.Contains("perf", set);
            Assert.Contains("wave", set);
        }

        [Fact]
        public void BuildNoticeCategorySet_NullOrEmptyCategories_Skipped()
        {
            var widgets = new List<INativeHudWidget>
            {
                new FakeNoticeWidget(new[] { "combo", null, "", "perf" }),
            };
            HashSet<string> set = NativeHudOverlay.BuildNoticeCategorySet(widgets);
            Assert.Equal(2, set.Count);
            Assert.Contains("combo", set);
            Assert.Contains("perf", set);
        }

        [Fact]
        public void BuildNoticeCategorySet_ConsumerWithNullCategories_HandledSafely()
        {
            var widgets = new List<INativeHudWidget>
            {
                new FakeNoticeWidget(null),
            };
            Assert.Empty(NativeHudOverlay.BuildNoticeCategorySet(widgets));
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

        /// <summary>实现 IUiDataLegacyConsumer 的最小 widget；用 BuildLegacyTypeSet 验证 type union。</summary>
        private sealed class FakeLegacyWidget : INativeHudWidget, IUiDataLegacyConsumer
        {
            private readonly string[] _types;
            public FakeLegacyWidget(string[] types) { _types = types; }
            public IEnumerable<string> LegacyTypes { get { return _types; } }
            public void OnLegacyUiData(string type, string[] fields) { }
            public Rectangle ScreenBounds { get { return Rectangle.Empty; } }
            public bool Visible { get { return false; } }
            public void Paint(Graphics g, float dpr, Point hudOrigin) { }
            public bool TryHitTest(Point screenPt) { return false; }
            public void OnMouseEvent(MouseEventArgs e, MouseEventKind kind) { }
            public bool WantsAnimationTick { get { return false; } }
            public void Tick(int deltaMs) { }
            public event EventHandler BoundsOrVisibilityChanged { add { } remove { } }
            public event EventHandler RepaintRequested { add { } remove { } }
            public event EventHandler AnimationStateChanged { add { } remove { } }
        }

        /// <summary>实现 INotchNoticeConsumer 的最小 widget；用 BuildNoticeCategorySet 验证 category union。</summary>
        private sealed class FakeNoticeWidget : INativeHudWidget, INotchNoticeConsumer
        {
            private readonly string[] _cats;
            public FakeNoticeWidget(string[] cats) { _cats = cats; }
            public IEnumerable<string> NoticeCategories { get { return _cats; } }
            public void OnNotchNotice(string category, string text, Color accentColor) { }
            public Rectangle ScreenBounds { get { return Rectangle.Empty; } }
            public bool Visible { get { return false; } }
            public void Paint(Graphics g, float dpr, Point hudOrigin) { }
            public bool TryHitTest(Point screenPt) { return false; }
            public void OnMouseEvent(MouseEventArgs e, MouseEventKind kind) { }
            public bool WantsAnimationTick { get { return false; } }
            public void Tick(int deltaMs) { }
            public event EventHandler BoundsOrVisibilityChanged { add { } remove { } }
            public event EventHandler RepaintRequested { add { } remove { } }
            public event EventHandler AnimationStateChanged { add { } remove { } }
        }
    }
}
