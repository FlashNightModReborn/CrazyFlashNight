using System;
using System.Drawing;
using System.Threading;
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
