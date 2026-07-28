using System;
using System.Drawing;
using CF7Launcher.Guardian.Hud;
using Xunit;

namespace CF7Launcher.Tests.Guardian
{
    public class NativeHudTopologyProbeTests
    {
        private static readonly Rectangle Viewport = new Rectangle(0, 0, 1024, 576);

        private static Rectangle ExistingRightTopHud
        {
            get
            {
                return RightHudLayout.TopToolsRectFromViewport(
                    Viewport,
                    RightHudLayout.ScaleForViewport(Viewport));
            }
        }

        [Fact]
        public void FullStagePlayerInfo_RequiresExplicitDecision_AndRecordsFullBridge()
        {
            // B0-01A: the source child is a 1024x64 stage placed at main-stage y=512.
            Rectangle fullStagePlayerInfo = new Rectangle(0, 512, 1024, 64);
            Rectangle[] fixedBounds = { ExistingRightTopHud, fullStagePlayerInfo };

            Assert.Throws<InvalidOperationException>(delegate
            {
                NativeHudTopologyProbe.Capture(Viewport, fixedBounds);
            });

            NativeHudTopologyProbeResult result = NativeHudTopologyProbe.Capture(
                Viewport,
                fixedBounds,
                6,
                NativeHudTopologyDecision.SplitRequired);

            Assert.Equal(Viewport, result.RawOuterUnion);
            Assert.Equal(new Rectangle(-6, -6, 1036, 588), result.InflatedOuterUnion);
            Assert.Equal(Viewport, result.ClippedSurface);
            Assert.Equal(2, result.Components);
            Assert.True(result.FullViewportBridge);
            Assert.True(result.NearFullBridge);
            Assert.True(result.RequiresDecision);
            Assert.Equal(NativeHudTopologyDecision.SplitRequired, result.Decision);
            Assert.Equal("split_required", result.DecisionValue);
            Assert.Equal(1024L * 64L + 252L * 32L, result.ExactRectangleUnionPixels);
            Assert.Equal(
                result.SubmittedSurfacePixels - result.ExactRectangleUnionPixels,
                result.BridgeWastePixels);
            Assert.Equal(
                result.RawInflatedSurfacePixels * 4L,
                result.RawInflatedSurfaceBytes);
            Assert.Equal(
                result.SubmittedSurfacePixels * 4L,
                result.SubmittedSurfaceBytes);
            Assert.True(
                result.RawInflatedSurfacePixels > result.SubmittedSurfacePixels);
            Assert.True(result.OffViewportPixels > 0);
            Assert.True(result.ElapsedTicks >= 0);
            Assert.True(result.ElapsedMilliseconds >= 0);
        }

        [Fact]
        public void TightEnvelopePlayerInfo_IsNearFullBridge_NotFullBridge()
        {
            // B0-04 canonical stageMatrix + viewBox-derived 1x envelope.
            Rectangle tightPlayerInfo = new Rectangle(0, 512, 282, 46);
            Rectangle[] fixedBounds = { ExistingRightTopHud, tightPlayerInfo };

            NativeHudTopologyProbeResult result = NativeHudTopologyProbe.Capture(
                Viewport,
                fixedBounds,
                6,
                NativeHudTopologyDecision.SplitRequired);

            Assert.Equal(new Rectangle(0, 0, 976, 558), result.RawOuterUnion);
            Assert.Equal(new Rectangle(-6, -6, 988, 570), result.InflatedOuterUnion);
            Assert.Equal(new Rectangle(0, 0, 982, 564), result.ClippedSurface);
            Assert.Equal(2, result.Components);
            Assert.False(result.FullViewportBridge);
            Assert.True(result.NearFullBridge);
            Assert.True(result.RequiresDecision);
            Assert.Equal("split_required", result.DecisionValue);
            Assert.True(result.ClippedViewportRatio >= 0.90);
            Assert.True(result.ExactVisibleFillRatio <= 0.50);
            Assert.True(result.Amplification > 1.0);
            Assert.Equal(
                result.RawInflatedSurfacePixels - result.SubmittedSurfacePixels,
                result.OffViewportPixels);
        }

        [Fact]
        public void CompactSingleComponent_DefaultsToNotRequired()
        {
            Rectangle[] fixedBounds =
            {
                new Rectangle(100, 100, 80, 20),
                new Rectangle(180, 100, 40, 20)
            };

            NativeHudTopologyProbeResult result =
                NativeHudTopologyProbe.Capture(Viewport, fixedBounds);

            Assert.Equal(1, result.Components);
            Assert.False(result.RequiresDecision);
            Assert.Equal(NativeHudTopologyDecision.NotRequired, result.Decision);
            Assert.Equal("not_required", result.DecisionValue);
            Assert.Equal(120L * 20L, result.ExactRectangleUnionPixels);
        }

        [Fact]
        public void ExactRectangleUnion_DoesNotDoubleCountOverlap()
        {
            Rectangle[] fixedBounds =
            {
                new Rectangle(10, 10, 20, 20),
                new Rectangle(20, 10, 20, 20)
            };

            NativeHudTopologyProbeResult result =
                NativeHudTopologyProbe.Capture(Viewport, fixedBounds);

            Assert.Equal(600, result.ExactRectangleUnionPixels);
            Assert.Equal(1, result.Components);
        }

        [Fact]
        public void InputWhoseRightEdgeWrapsInt32_FailsClosed()
        {
            Rectangle[] invalidBounds =
            {
                new Rectangle(Int32.MaxValue - 2, 10, 4, 1)
            };

            Assert.Throws<OverflowException>(delegate
            {
                NativeHudTopologyProbe.Capture(Viewport, invalidBounds);
            });
        }

        [Fact]
        public void InputWhoseBottomEdgeWrapsInt32_FailsClosed()
        {
            Rectangle[] invalidBounds =
            {
                new Rectangle(10, Int32.MaxValue - 2, 1, 4)
            };

            Assert.Throws<OverflowException>(delegate
            {
                NativeHudTopologyProbe.Capture(Viewport, invalidBounds);
            });
        }

        [Fact]
        public void OuterUnionWhoseSpanExceedsInt32_FailsClosed()
        {
            Rectangle extremeViewport =
                new Rectangle(Int32.MinValue, 0, Int32.MaxValue, 10);
            Rectangle[] separatedBounds =
            {
                new Rectangle(Int32.MinValue, 0, 1, 1),
                new Rectangle(0, 0, 1, 1)
            };

            Assert.Throws<OverflowException>(delegate
            {
                NativeHudTopologyProbe.Capture(
                    extremeViewport,
                    separatedBounds,
                    0,
                    NativeHudTopologyDecision.SplitRequired);
            });
        }

        [Fact]
        public void InflateWhoseSpanExceedsRectangleCapacity_FailsClosed()
        {
            Rectangle extremeViewport =
                new Rectangle(Int32.MinValue, 0, Int32.MaxValue, 10);
            Rectangle[] bounds =
            {
                new Rectangle(Int32.MinValue + 1, 0, Int32.MaxValue - 1, 1)
            };

            Assert.Throws<OverflowException>(delegate
            {
                NativeHudTopologyProbe.Capture(
                    extremeViewport,
                    bounds,
                    1,
                    NativeHudTopologyDecision.SplitRequired);
            });
        }

        [Fact]
        public void NegativeDimension_FailsClosedInsteadOfBeingSilentlyIgnored()
        {
            Rectangle[] invalidBounds =
            {
                new Rectangle(10, 10, -1, 4)
            };

            Assert.Throws<ArgumentOutOfRangeException>(delegate
            {
                NativeHudTopologyProbe.Capture(Viewport, invalidBounds);
            });
        }
    }
}
