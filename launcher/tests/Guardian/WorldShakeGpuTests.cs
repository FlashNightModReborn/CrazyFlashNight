using System;
using System.Diagnostics;
using System.Drawing;
using System.IO;
using System.Threading;
using System.Windows.Forms;
using CF7Launcher.Guardian.WorldCompositor;
using Xunit;

namespace CF7Launcher.Tests.Guardian
{
    public sealed class WorldShakeGpuFactAttribute : FactAttribute
    {
        internal const string ModuleVariable = "CF7_TEST_WORLD_SHAKE_NATIVE_DLL";

        public WorldShakeGpuFactAttribute()
        {
            if (string.IsNullOrWhiteSpace(Environment.GetEnvironmentVariable(ModuleVariable)))
                Skip = $"Set {ModuleVariable} to an explicit shake-capable candidate DLL.";
        }
    }

    public sealed partial class OpaqueHudGpuTests
    {
        [WorldShakeGpuFact]
        public void WorldShakeMovesWorldAndDamageWithOneOffsetAndClearsToIdle()
        {
            Run((world, scene, _, source) =>
            {
                Assert.True(world.WorldShakeAvailable, "The specified DLL lacks the additive shake exports.");
                world.Postprocess(false, 0, false);
                var worldMarker = new Rectangle(56, 60, 32, 24);
                ((Window)source).FixturePaint = graphics =>
                {
                    graphics.Clear(Color.FromArgb(30, 80, 140));
                    graphics.FillRectangle(Brushes.Lime, worldMarker);
                };
                source.Refresh();
                WithPixels(Tile(26, 18, 104, 20, 30, 230, 255), p => world.SetHudRaster(0, p, 26, 18, 104, 180, 104));
                WithPixels(Tile(28, 20, 112, 210, 28, 60, 255), p => world.SetHudRaster(1, p, 28, 20, 112, 330, 165));
                Frame identity = PixelsUntil(world, scene, f => Pixel(f, 68, 68, 0, 255, 0)
                    && Pixel(f, 190, 115, 20, 30, 230) && Pixel(f, 342, 174, 210, 28, 60), "world + damage + fixed HUD");
                // The source remains static for the rest of this test.
                Thread.Sleep(200);
                var beforeIdle = world.Read();
                world.SetWorldShakeGrant(1, clearState: true);
                Thread.Sleep(250);
                var idleStats = world.ReadWorldShake().Value;
                Assert.Equal(0ul, idleStats.ActivePasses);
                Assert.Equal(0ul, idleStats.TailPasses);
                Assert.Equal(beforeIdle.Received, world.Read().Received);
                Assert.Equal(beforeIdle.Presented, world.Read().Presented);
                // Composite readback itself requests a diagnostic render.
                Assert.Equal(identity.Pixels, Grab(world).Pixels);

                var impulse = new CombatFxShakeImpulse(1, 6, 512, 288);
                var worldRegion = Rectangle.Inflate(worldMarker, 12, 12);
                var damageRegion = new Rectangle(168, 92, 50, 42);
                var fixedRegion = new Rectangle(318, 153, 52, 44);
                ulong tailsBeforeClear = 0;
                var shifted = new Frame(new byte[identity.Pixels.Length], identity.Width, identity.Height);
                world.SubmitWorldShake(1, new[] { impulse }, 0, 0, 1);
                Pump(() =>
                {
                    ulong before = world.Read().Presented;
                    Assert.Equal(NativeCompositorSession.GrabOk,
                        world.GrabCompositeFrame(shifted.Pixels, out int width, out int height));
                    Assert.Equal((identity.Width, identity.Height), (width, height));
                    // Readback completes before Present updates the last offset.
                    Assert.True(SpinWait.SpinUntil(() => world.Read().Presented > before, TimeSpan.FromSeconds(2)));
                    var after = world.ReadWorldShake().Value;
                    if (after.LastOffsetX == 0 && after.LastOffsetY == 0
                        || !SameRegion(identity, shifted, worldRegion, after.LastOffsetX, after.LastOffsetY))
                        return false;
                    Assert.True(after.ActivePasses > 0);
                    Assert.False(SameRegion(identity, shifted, worldRegion, 0, 0));
                    Assert.False(SameRegion(identity, shifted, damageRegion, 0, 0));
                    Assert.True(SameRegion(identity, shifted, damageRegion, after.LastOffsetX, after.LastOffsetY));
                    Assert.True(SameRegion(identity, shifted, fixedRegion, 0, 0));
                    tailsBeforeClear = after.TailPasses;
                    world.SetWorldShakeGrant(0, clearState: true);
                    return true;
                }, scene, "same-offset active world and damage");
                Assert.Equal(beforeIdle.Received, world.Read().Received);

                Pump(() =>
                {
                    var stats = world.ReadWorldShake().Value;
                    return stats.TailPasses > tailsBeforeClear && stats.ActiveCount == 0 && stats.TailPending == 0;
                }, scene, "clear presents one identity tail");
                var cleared = world.ReadWorldShake().Value;
                Assert.Equal(tailsBeforeClear + 1, cleared.TailPasses);
                Assert.Equal((0, 0), (cleared.LastOffsetX, cleared.LastOffsetY));
                Assert.Equal(0u, cleared.CurrentGrant);
                ulong presented = world.Read().Presented;
                world.SubmitWorldShake(1, new[] { impulse }, 0, 0, 1);
                Thread.Sleep(250);
                var stale = world.ReadWorldShake().Value;
                Assert.Equal(cleared.RejectedGrant + 1, stale.RejectedGrant);
                Assert.Equal(0u, stale.ActiveCount);
                Assert.Equal((0, 0), (stale.LastOffsetX, stale.LastOffsetY));
                Assert.Equal(cleared.TailPasses, stale.TailPasses);
                Assert.Equal(cleared.ActivePasses, stale.ActivePasses);
                Assert.Equal(presented, world.Read().Presented);
                Assert.Equal(beforeIdle.Received, world.Read().Received);
                Assert.Equal(identity.Pixels, Grab(world).Pixels);
            }, new Size(512, 288), nativeModule: Environment.GetEnvironmentVariable(WorldShakeGpuFactAttribute.ModuleVariable));
        }

        [WorldShakeGpuFact]
        public void WorldShakeRespectsShowAllLetterboxAndZeroVsNonZeroClipBoundary()
        {
            Run((world, scene, _, source) =>
            {
                Assert.True(world.WorldShakeAvailable);
                world.Postprocess(false, 0, false);
                ((Window)source).FixturePaint = graphics =>
                {
                    graphics.Clear(Color.Black);
                    graphics.FillRectangle(Brushes.DarkCyan, 0, 60, 640, 360);
                    graphics.FillRectangle(Brushes.Gold, 0, 60, 640, 15);
                    graphics.FillRectangle(Brushes.Blue, 0, 405, 640, 15);
                };
                source.Refresh();
                PutShakeTestRaster(world, 0, new Rectangle(280, 412, 56, 14), Color.Red);
                var identity = PixelsUntil(world, scene, f => Pixel(f, 120, 60, 0, 215, 255)
                    && Pixel(f, 120, 419, 255, 0, 0) && Pixel(f, 300, 425, 0, 0, 255)
                    && Pixel(f, 120, 59, 0, 0, 0) && Pixel(f, 120, 420, 0, 0, 0), "showAll zero offset");

                BeginShake(world, 1);
                var shifted = ObserveShakeFrame(world, scene, identity, (frame, dx, dy) =>
                {
                    if (dy <= 0 || dy > 6) return false;
                    // Without edge replication, this looks up the original upper black bar.
                    return Pixel(frame, 120, 60, 0, 215, 255)
                        && Pixel(frame, 120, 59, 0, 0, 0) && Pixel(frame, 120, 420, 0, 0, 0)
                        && Pixel(frame, 300 + dx, 419, 0, 0, 255)
                        && Pixel(frame, 300 + dx, 420, 0, 0, 0)
                        && Pixel(frame, 300 + dx, 425, 0, 0, 0)
                        && Pixel(frame, 300 + dx, 411 + dy, 255, 0, 0);
                }, "nonzero world edge replication and damage-only clipping");
                ClearShakeAndWait(world, scene, shifted);
                Assert.Equal(identity.Pixels, Grab(world).Pixels);
                AssertShakeIdle(world, scene);
            }, new Size(640, 480), nativeModule: Environment.GetEnvironmentVariable(WorldShakeGpuFactAttribute.ModuleVariable));
        }

        [WorldShakeGpuFact]
        public void WorldShakeComposesWithNightVisionAndDynamicLightsInOneShift()
        {
            Run((world, scene, _, source) =>
            {
                Assert.True(world.WorldShakeAvailable);
                world.Postprocess(false, 0, false);
                var marker = new Rectangle(68, 76, 40, 24);
                ((Window)source).FixturePaint = graphics =>
                {
                    graphics.Clear(Color.FromArgb(80, 80, 80));
                    using var fill = new SolidBrush(Color.FromArgb(125, 125, 125));
                    graphics.FillRectangle(fill, marker);
                };
                source.Refresh();
                PixelsUntil(world, scene, f => Pixel(f, 80, 85, 125, 125, 125), "ungraded world marker");
                string presets = Path.Combine(AppContext.BaseDirectory, "..", "..", "..", "..",
                    "data", "environment", "color_engine_preset.xml");
                const string mode = "中级夜视仪";
                var profile = NightVisionProfile.Load(presets)[mode];
                // Keep authored spatial grading while removing temporal exposure/scan drift in the pixel oracle.
                profile.Native[12] = 1;
                profile.Native[15] = 0;
                byte[] lut = WorldLutBaker.BakeFromXml(presets, mode, 0, 1, out string resolved);
                Assert.Equal(mode, resolved);
                world.NightVision(profile, 1, ShakeTestIdentityGrade, true, lut);
                PutShakeTestRaster(world, 0, new Rectangle(176, 112, 28, 20), Color.Magenta);
                PutShakeTestRaster(world, 1, new Rectangle(370, 180, 30, 22), Color.Yellow);
                var unlit = PixelsUntil(world, scene, f => Channel(f, 80, 85, 1) > Channel(f, 80, 85, 2) + 10
                    && Pixel(f, 190, 121, 255, 0, 255) && Pixel(f, 385, 190, 0, 255, 255), "green world with ungraded HUD");

                var light = new CombatFxDrawFrame(0) { LightCount = 1, MaximumLightResponse = .8f };
                float[] lamp = { 580, 240, 90, 2f, 1, 1, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0 };
                Array.Copy(lamp, light.Lights, lamp.Length);
                var beforeLight = world.ReadWork().Value;
                world.CombatFxFrame(light, 0, 0, 1);
                var identity = PixelsUntil(world, scene,
                    f => Channel(f, 290, 120, 1) > Channel(unlit, 290, 120, 1) + 8, "local point light on graded world");
                Assert.True(world.ReadWork().Value.LightDraws > beforeLight.LightDraws);
                Assert.True(SameRegion(unlit, identity, new Rectangle(60, 70, 55, 36), 0, 0));

                BeginShake(world, 1);
                var shifted = ObserveShakeFrame(world, scene, identity, (frame, dx, dy) =>
                    SameRegion(identity, frame, new Rectangle(64, 72, 50, 33), dx, dy)
                    && !SameRegion(identity, frame, new Rectangle(64, 72, 50, 33), 0, 0)
                    && SameRegion(identity, frame, new Rectangle(271, 101, 39, 39), dx, dy)
                    && !SameRegion(identity, frame, new Rectangle(271, 101, 39, 39), 0, 0)
                    && SameRegion(identity, frame, new Rectangle(172, 108, 36, 28), dx, dy)
                    && Pixel(frame, 190 + dx, 121 + dy, 255, 0, 255)
                    && SameRegion(identity, frame, new Rectangle(362, 172, 46, 38), 0, 0),
                    "one shifted world, point light and damage with fixed HUD");
                ClearShakeAndWait(world, scene, shifted);
                Assert.True(SamePixels(Grab(world), identity.Pixels));
            }, new Size(512, 288), nativeModule: Environment.GetEnvironmentVariable(WorldShakeGpuFactAttribute.ModuleVariable));
        }

        [WorldShakeGpuFact]
        public void WorldShakeHandlesOutputResizeAndSourceViewportChangeWithoutStaleOffset()
        {
            Run((world, scene, output, source) =>
            {
                Assert.True(world.WorldShakeAvailable);
                world.Postprocess(false, 0, false);
                Size viewport = source.ClientSize;
                ((Window)source).FixturePaint = graphics =>
                {
                    graphics.Clear(Color.Black);
                    graphics.FillRectangle(Brushes.Teal, 0, 0, viewport.Width, viewport.Height);
                    graphics.FillRectangle(Brushes.Lime, viewport.Width / 4, viewport.Height / 4,
                        viewport.Width / 8, viewport.Height / 8);
                };
                source.Refresh();
                PutShakeTestRaster(world, 0, new Rectangle(205, 120, 28, 18), Color.Magenta);
                var identity = PixelsUntil(world, scene, f => Pixel(f, 138, 80, 0, 255, 0)
                    && Pixel(f, 216, 128, 255, 0, 255), "original geometry");
                BeginShake(world, 1);
                ObserveShakeFrame(world, scene, identity,
                    (f, dx, dy) => SameRegion(identity, f, new Rectangle(116, 62, 87, 52), dx, dy), "shake before output resize");

                var capture = world.Read();
                output.ClientSize = new Size(640, 360);
                var resized = PixelsUntil(world, scene, f => f.Width == 640 && f.Height == 360
                    && Pixel(f, 175, 100, 0, 255, 0)
                    && (world.ReadWorldShake().Value.LastOffsetX, world.ReadWorldShake().Value.LastOffsetY) == (0, 0),
                    "output resize retires the offset at unchanged capture size");
                Assert.Equal((capture.Width, capture.Height), (world.Read().Width, world.Read().Height));
                Assert.True(Pixel(resized, 216, 128, 255, 0, 255));

                BeginShake(world, 2);
                var active = ObserveShakeFrame(world, scene, resized,
                    (f, dx, dy) => SameRegion(resized, f, new Rectangle(150, 80, 98, 63), dx, dy), "shake before source handoff");
                world.HoldViewport();
                ulong held = world.Read().Presented;
                world.SetWorldShakeGrant(0, clearState: true);
                double fence = Stopwatch.GetTimestamp() * 1000.0 / Stopwatch.Frequency;
                viewport = new Size(384, 216);
                source.Refresh();
                Application.DoEvents();
                Assert.Equal(held, world.Read().Presented);
                world.Viewport(new Rectangle(Point.Empty, viewport), fence);
                Pump(() =>
                {
                    var stats = world.Read();
                    return stats.Width == viewport.Width && stats.Height == viewport.Height
                        && stats.LastFrameQpcMs >= fence && stats.Presented > held;
                }, scene, "fresh smaller viewport");
                WaitForIdentityTail(world, scene, active.TailPasses);
                var cropped = PixelsUntil(world, scene, f => f.Width == 640 && f.Height == 360
                    && Pixel(f, 170, 100, 0, 255, 0) && Pixel(f, 630, 355, 128, 128, 0)
                    && Pixel(f, 216, 128, 255, 0, 255), "DRS viewport fills unchanged output");
                world.SetWorldShakeGrant(3, clearState: true);
                var readmitted = world.ReadWorldShake().Value;
                Assert.Equal(3u, readmitted.CurrentGrant);
                Assert.Equal((0, 0), (readmitted.LastOffsetX, readmitted.LastOffsetY));
                Assert.Equal(0u, readmitted.ActiveCount);
                Assert.True(SameRegion(resized, cropped, new Rectangle(167, 100, 30, 20), 0, 0));
                Assert.True(SameRegion(resized, cropped, new Rectangle(400, 269, 60, 44), 0, 0));
                AssertShakeIdle(world, scene);
            }, new Size(512, 288), nativeModule: Environment.GetEnvironmentVariable(WorldShakeGpuFactAttribute.ModuleVariable));
        }

        private static readonly float[] ShakeTestIdentityGrade = { 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1 };

        private static byte Channel(Frame frame, int x, int y, int channel) => frame.Pixels[(y * frame.Width + x) * 4 + channel];

        private static void PutShakeTestRaster(NativeCompositorSession world, int layer, Rectangle bounds, Color color)
        {
            int stride = bounds.Width * 4;
            WithPixels(Tile(bounds.Width, bounds.Height, stride, color.B, color.G, color.R, 255),
                p => world.SetHudRaster(layer, p, bounds.Width, bounds.Height, stride, bounds.X, bounds.Y));
        }

        private static void BeginShake(NativeCompositorSession world, int grant)
        {
            world.SetWorldShakeGrant(grant, clearState: true);
            SubmitShake(world, grant);
        }

        private static void SubmitShake(NativeCompositorSession world, int grant) =>
            world.SubmitWorldShake(grant, new[] { new CombatFxShakeImpulse(grant, 6, 512, 288) }, 0, 0, 1);

        private static NativeCompositorSession.WorldShakeStats ObserveShakeFrame(NativeCompositorSession world,
            CompositionSceneHost scene, Frame identity, Func<Frame, int, int, bool> expected, string phase)
        {
            var frame = new Frame(new byte[identity.Pixels.Length], identity.Width, identity.Height);
            NativeCompositorSession.WorldShakeStats observed = default;
            Pump(() =>
            {
                ulong before = world.Read().Presented;
                Assert.Equal(NativeCompositorSession.GrabOk, world.GrabCompositeFrame(frame.Pixels, out int width, out int height));
                Assert.Equal((frame.Width, frame.Height), (width, height));
                Assert.True(SpinWait.SpinUntil(() => world.Read().Presented > before, TimeSpan.FromSeconds(2)));
                observed = world.ReadWorldShake().Value;
                return (observed.LastOffsetX != 0 || observed.LastOffsetY != 0)
                    && expected(frame, observed.LastOffsetX, observed.LastOffsetY);
            }, scene, phase);
            Assert.True(observed.ActivePasses > 0);
            return observed;
        }

        private static void ClearShakeAndWait(NativeCompositorSession world, CompositionSceneHost scene,
            NativeCompositorSession.WorldShakeStats active)
        {
            world.SetWorldShakeGrant(0, clearState: true);
            WaitForIdentityTail(world, scene, active.TailPasses);
        }

        private static void WaitForIdentityTail(NativeCompositorSession world, CompositionSceneHost scene, ulong precedingTails)
        {
            Pump(() =>
            {
                var stats = world.ReadWorldShake().Value;
                return stats.TailPasses > precedingTails && stats.ActiveCount == 0 && stats.TailPending == 0;
            }, scene, "one identity tail");
            var cleared = world.ReadWorldShake().Value;
            Assert.Equal(precedingTails + 1, cleared.TailPasses);
            Assert.Equal((0, 0), (cleared.LastOffsetX, cleared.LastOffsetY));
            Assert.Equal(0u, cleared.CurrentGrant);
        }

        private static void AssertShakeIdle(NativeCompositorSession world, CompositionSceneHost scene)
        {
            Application.DoEvents();
            scene.Commit();
            Thread.Sleep(200);
            var before = world.Read();
            var shake = world.ReadWorldShake().Value;
            Thread.Sleep(300);
            var after = world.Read();
            Assert.Equal((before.Presented, before.Received), (after.Presented, after.Received));
            Assert.Equal(shake.ActivePasses, world.ReadWorldShake().Value.ActivePasses);
            Assert.Equal(shake.TailPasses, world.ReadWorldShake().Value.TailPasses);
        }

        private static bool SameRegion(Frame identity, Frame shifted, Rectangle region, int dx, int dy)
        {
            Assert.Equal((identity.Width, identity.Height), (shifted.Width, shifted.Height));
            for (int y = region.Top; y < region.Bottom; y++)
            {
                int source = (y * identity.Width + region.Left) * 4;
                int target = ((y + dy) * shifted.Width + region.Left + dx) * 4;
                if (!identity.Pixels.AsSpan(source, region.Width * 4).SequenceEqual(
                    shifted.Pixels.AsSpan(target, region.Width * 4))) return false;
            }
            return true;
        }
    }
}
