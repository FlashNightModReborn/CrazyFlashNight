using System;
using System.Collections.Generic;
using System.Drawing;
using System.Drawing.Imaging;
using System.IO;
using System.Reflection;
using System.Runtime.ExceptionServices;
using System.Threading;
using System.Windows.Forms;
using CF7Launcher.Guardian.Hud.Loot;
using CF7Launcher.Guardian.Hud.PlayerInfo;
using Newtonsoft.Json.Linq;
using Xunit;
using Xunit.Abstractions;

namespace CF7Launcher.Tests.Guardian.Hud.Loot
{
    public sealed class LootFeedAnimationTests
    {
        private readonly ITestOutputHelper _output;
        public LootFeedAnimationTests(ITestOutputHelper output) { _output = output; }
        private static Color FrameColor(int i) => Color.FromArgb(255, 40 + i * 5, 190 - i * 3, 60 + i * 4);
        private static void Sta(Action action)
        {
            Exception error = null;
            var thread = new Thread(() => { try { action(); } catch (Exception e) { error = e; } }) { IsBackground = true };
            thread.SetApartmentState(ApartmentState.STA);
            thread.Start();
            Assert.True(thread.Join(TimeSpan.FromSeconds(40)), "STA fixture timed out");
            if (error != null) ExceptionDispatchInfo.Capture(error).Throw();
        }

        private sealed class Fixture : IDisposable
        {
            internal readonly string Root = Path.Combine(Path.GetTempPath(), "cf7-loot-animation-" + Guid.NewGuid().ToString("N"));
            internal readonly Form Form;
            internal readonly Panel Anchor;
            internal readonly LootIconCatalog Catalog;
            internal readonly LootFeedWidget Widget;
            internal readonly LootFeedModel Model;
            internal long Clock;
            private readonly string _mode = PlayerHudMotionSettings.Mode;
            private readonly bool _motionOverride = (bool)typeof(PlayerHudMotionSettings).GetField("_reducedOverride", BindingFlags.NonPublic | BindingFlags.Static).GetValue(null);
            internal Fixture(bool animated = true, string iconsDirectory = null)
            {
                PlayerHudMotionSettings.Configure("full"); PlayerHudMotionSettings.ReducedMotion = false;
                Directory.CreateDirectory(Root);
                var frames = new JArray();
                for (int i = 0; i < 32; i++)
                {
                    string name = i + ".png";
                    Save(name, FrameColor(i));
                    frames.Add(new JObject { ["uri"] = name });
                }
                Save("poster.png", Color.White);
                File.WriteAllText(Path.Combine(Root, "manifest.json"), new JObject {
                    ["a"] = new JObject { ["f1"] = "poster.png", ["fps"] = 25, ["frames"] = animated ? frames : null },
                    ["static"] = new JObject { ["f1"] = "poster.png" }
                }.ToString());
                Form = new Form { ClientSize = new Size(1024, 576) };
                Anchor = new Panel { Dock = DockStyle.Fill };
                Form.Controls.Add(Anchor); Form.CreateControl(); Anchor.CreateControl();
                _ = Anchor.Handle; // BeginInvoke/DoEvents runs on an owned, hidden STA anchor.
                Catalog = new LootIconCatalog(iconsDirectory ?? Root);
                Widget = new LootFeedWidget(Anchor, Catalog, () => Clock);
                Model = (LootFeedModel)typeof(LootFeedWidget).GetField("_model", BindingFlags.NonPublic | BindingFlags.Instance).GetValue(Widget);
            }
            private void Save(string name, Color color)
            {
                using var b = new Bitmap(16, 16);
                using (var g = Graphics.FromImage(b)) g.Clear(color);
                b.Save(Path.Combine(Root, name), ImageFormat.Png);
            }
            internal void Add(string name = "a", string icon = "a", int elite = 0)
            {
                Widget.AddEvent(elite > 0 ? "kill" : "item", name, 1, elite > 0 ? "kill" : "pickup", icon, elite);
                Application.DoEvents();
            }
            internal void Advance(int delta, int? modelDelta = null)
            {
                Clock += delta * TimeSpan.TicksPerMillisecond;
                Widget.Tick(modelDelta ?? delta);
            }
            internal int Pixel()
            {
                var bounds = Widget.ScreenBounds;
                using var image = new Bitmap(bounds.Width, bounds.Height);
                using (var g = Graphics.FromImage(image)) Widget.Paint(g, 1f, bounds.Location);
                return image.GetPixel(17, 16).ToArgb();
            }
            internal string IconFingerprint()
            {
                var bounds = Widget.ScreenBounds;
                using var image = new Bitmap(bounds.Width, bounds.Height);
                using (var g = Graphics.FromImage(image)) Widget.Paint(g, 1f, bounds.Location);
                using var bytes = new MemoryStream();
                using var icon = image.Clone(new Rectangle(7, 6, 20, 20), PixelFormat.Format32bppArgb);
                icon.Save(bytes, ImageFormat.Png);
                return Convert.ToHexString(System.Security.Cryptography.SHA256.HashData(bytes.ToArray()));
            }
            public void Dispose()
            {
                Widget.Dispose(); Catalog.Dispose(); Form.Dispose();
                PlayerHudMotionSettings.Configure(_mode); PlayerHudMotionSettings.ReducedMotion = _motionOverride;
                Directory.Delete(Root, true);
            }
        }

        [Fact]
        public void ForcedPaint_ContinuesSelectingPixelsAfter450ms()
        {
            Sta(() => {
                using var f = new Fixture(); f.Add();
                var colors = new HashSet<int>();
                for (int ms = 32; ms <= 1984; ms += 32) { f.Advance(32); if (ms >= 600) colors.Add(f.Pixel()); }
                Assert.True(colors.Count > 15, "Content selection froze after the entry window.");
            });
        }

        [Fact]
        public void OwnRepaintRequests_ContinueChangingPixelsWithoutAnotherWidget()
        {
            Sta(() => {
                using var f = new Fixture(); f.Add();
                bool dirty = false; int requests = 0;
                f.Widget.RepaintRequested += (_, _) => { dirty = true; requests++; };
                var colors = new HashSet<int>();
                for (int ms = 32; ms <= 1984; ms += 32)
                {
                    dirty = false; f.Advance(32);
                    if (dirty && ms >= 600) colors.Add(f.Pixel());
                }
                Assert.True(colors.Count > 15, "The feed relied on an unrelated widget to repaint.");
                Assert.InRange(requests, 20, 62);
            });
        }

        [Fact]
        public void StaticHoldHasNoContentRepaint_ButStillExpires()
        {
            Sta(() => {
                using var f = new Fixture(false); f.Add(); f.Advance(600);
                int requests = 0; f.Widget.RepaintRequested += (_, _) => requests++;
                for (int i = 0; i < 30; i++) f.Advance(32);
                Assert.Equal(0, requests); Assert.True(f.Widget.WantsAnimationTick);
                for (int i = 0; i < 40; i++) f.Advance(32);
                Assert.False(f.Widget.Visible); Assert.False(f.Widget.WantsAnimationTick);
            });
        }

        [Fact]
        public void LongStallUsesRealContentTime_NotClampedModelDelta()
        {
            Sta(() => {
                using var f = new Fixture(); f.Add(); f.Advance(600);
                f.Advance(2000, 50);
                Assert.Equal(FrameColor(1).ToArgb(), f.Pixel()); // 2600ms modulo 1280ms = 40ms.
                Assert.True(f.Widget.Visible);
            });
        }

        [Fact]
        public void SuppressionAndReducedMotionFreezePhase_ThenResumeSameCard()
        {
            Sta(() => {
                using var f = new Fixture(); f.Add(); f.Advance(900);
                int phase = f.Pixel();
                f.Widget.SetHostSuppressed(true); f.Advance(2000, 32);
                int requests = 0; f.Widget.RepaintRequested += (_, _) => requests++;
                f.Advance(2000, 32); Assert.Equal(0, requests);
                f.Widget.SetHostSuppressed(false); Assert.Equal(phase, f.Pixel());
                PlayerHudMotionSettings.Configure("reduced"); f.Widget.Tick(0);
                Assert.Equal(Color.White.ToArgb(), f.Pixel());
                f.Advance(2000, 32);
                PlayerHudMotionSettings.Configure("full"); f.Widget.Tick(0);
                Assert.Equal(phase, f.Pixel());
                f.Advance(200, 32); Assert.Equal(FrameColor(27).ToArgb(), f.Pixel());
            });
        }

        [Fact]
        public void MergeAndPreemptionKeepCardPhase_WhileNewCardStartsAtZero()
        {
            Sta(() => {
                using var f = new Fixture(); f.Add();
                for (int i = 1; i < 5; i++) f.Add("other" + i, null);
                f.Advance(900); f.Add(); Assert.Equal(FrameColor(22).ToArgb(), f.Pixel());
                f.Add("boss", null, 2);
                Assert.Single(f.Model.PendingCards);
                f.Advance(2000, 32);
                var boss = f.Model.Cards[0]; Assert.Equal("boss", boss.Name);
                boss.RemainingHoldMs = 0; boss.FadeElapsedMs = LootFeedModel.FadeMs;
                f.Widget.Tick(0); f.Advance(200, 200);
                Assert.Equal("a", f.Model.Cards[0].Name);
                Assert.Equal(FrameColor(27).ToArgb(), f.Pixel());
            });
        }

        [Fact]
        public void DisposeStopsTickAndFurtherRepaint()
        {
            Sta(() => {
                using var f = new Fixture(); f.Add(); f.Advance(600);
                int requests = 0; f.Widget.RepaintRequested += (_, _) => requests++;
                f.Widget.Dispose(); f.Advance(1000); f.Widget.SetHostSuppressed(false);
                Assert.Equal(0, requests); Assert.False(f.Widget.WantsAnimationTick); Assert.False(f.Widget.Visible);
            });
        }

        [Theory]
        [InlineData("金钱", 10560000L)]
        [InlineData("K点", 13333334L)]
        [InlineData("强化石", 50400000L)]
        public void RealAssets_RenderBeyondEntryAndAcrossTwoFullCycles(string name, long period)
        {
            Sta(() => {
                using var f = new Fixture(iconsDirectory: LootIconPlaybackMetricsTests.FindIcons());
                f.Add(name, name);
                f.Model.Cards[0].RemainingHoldMs = int.MaxValue; // Test fixture only; product lifetime is unchanged.
                f.Model.Cards[0].VisibleAgeMs = 600;
                string first = f.IconFingerprint();
                var pictures = new HashSet<string>();
                string review = Environment.GetEnvironmentVariable("CF7_LOOT_ANIMATION_REVIEW_DIR");
                int exported = 0;
                for (long t = 6000000; t <= period * 2; t += 320000)
                {
                    f.Clock = t; f.Widget.Tick(32); pictures.Add(f.IconFingerprint());
                    if (!string.IsNullOrEmpty(review) && exported < 5 && ((t - 6000000) / 320000) % 9 == 0)
                    {
                        Directory.CreateDirectory(review);
                        var bounds = f.Widget.ScreenBounds;
                        using var image = new Bitmap(bounds.Width, bounds.Height);
                        using (var g = Graphics.FromImage(image)) f.Widget.Paint(g, 1f, bounds.Location);
                        image.Save(Path.Combine(review, name + "-" + t / TimeSpan.TicksPerMillisecond + "ms.png"), ImageFormat.Png);
                        exported++;
                    }
                }
                Assert.True(pictures.Count > 8, name + " did not loop through distinct pictures");
                f.Clock = period * 2; f.Widget.Tick(0);
                Assert.Equal(first, f.IconFingerprint());
            });
        }

        [Fact]
        public void IndependentCardsStartAtZero_AndResizeKeepsEachPhase()
        {
            Sta(() => {
                using var f = new Fixture(); f.Add(); f.Advance(600); f.Add("second");
                f.Model.Cards[1].VisibleAgeMs = 600;
                // The new instance occupies the second slot, and has its own phase zero.
                var states = (System.Collections.IDictionary)typeof(LootFeedWidget).GetField("_contentPlayback", BindingFlags.Instance | BindingFlags.NonPublic).GetValue(f.Widget);
                object a = states[f.Model.Cards[0].Sequence], b = states[f.Model.Cards[1].Sequence];
                long Elapsed(object state) => (long)state.GetType().GetField("Elapsed", BindingFlags.Instance | BindingFlags.NonPublic).GetValue(state);
                Assert.Equal(6000000, Elapsed(a)); Assert.Equal(0, Elapsed(b));
                f.Form.ClientSize = new Size(1600, 900); Application.DoEvents();
                Assert.Equal(6000000, Elapsed(a)); Assert.Equal(0, Elapsed(b));
            });
        }

        [Fact]
        public void FirstPendingCardBindsOnlyOnFirstVisibility_AtPhaseZero()
        {
            Sta(() => {
                using var f = new Fixture();
                for (int i = 0; i < 5; i++) f.Add("card" + i, "static");
                f.Add("pending"); Assert.Single(f.Model.PendingCards);
                var pending = f.Model.PendingCards[0];
                var states = (System.Collections.IDictionary)typeof(LootFeedWidget).GetField("_contentPlayback", BindingFlags.Instance | BindingFlags.NonPublic).GetValue(f.Widget);
                Assert.False(states.Contains(pending.Sequence));
                f.Advance(2000, 32);
                foreach (var card in f.Model.Cards) { card.RemainingHoldMs = 0; card.FadeElapsedMs = LootFeedModel.FadeMs; }
                f.Widget.Tick(0);
                Assert.Same(pending, Assert.Single(f.Model.Cards));
                pending.VisibleAgeMs = 600;
                Assert.Equal(FrameColor(0).ToArgb(), f.Pixel());
            });
        }

        [Theory]
        [InlineData(1, true)]
        [InlineData(5, true)]
        [InlineData(1, false)]
        [InlineData(5, false)]
        public void SteadyWidgetTickAndOwnRepaint_RecordsOneAndFiveCardCosts(int count, bool animated)
        {
            Sta(() => {
                using var f = new Fixture(animated);
                for (int i = 0; i < count; i++) f.Add("card" + i);
                foreach (var card in f.Model.Cards) card.RemainingHoldMs = int.MaxValue;
                f.Advance(600); f.Pixel();
                using var image = new Bitmap(f.Widget.ScreenBounds.Width, f.Widget.ScreenBounds.Height);
                using var g = Graphics.FromImage(image);
                bool dirty = false; int requests = 0, paints = 0, boundsChanges = 0;
                f.Widget.RepaintRequested += (_, _) => { dirty = true; requests++; };
                f.Widget.BoundsOrVisibilityChanged += (_, _) => boundsChanges++;
                const int iterations = 400;
                var ticks = new long[iterations]; var paintTimes = new long[iterations];
                long allocated = GC.GetAllocatedBytesForCurrentThread();
                int gen0 = GC.CollectionCount(0);
                for (int i = 0; i < iterations; i++)
                {
                    dirty = false;
                    long start = System.Diagnostics.Stopwatch.GetTimestamp(); f.Advance(32);
                    ticks[i] = System.Diagnostics.Stopwatch.GetTimestamp() - start;
                    if (dirty)
                    {
                        start = System.Diagnostics.Stopwatch.GetTimestamp();
                        g.Clear(Color.Transparent); f.Widget.Paint(g, 1f, f.Widget.ScreenBounds.Location);
                        paintTimes[paints++] = System.Diagnostics.Stopwatch.GetTimestamp() - start;
                    }
                }
                allocated = GC.GetAllocatedBytesForCurrentThread() - allocated;
                Assert.Equal(0, boundsChanges);
                if (animated) Assert.InRange(requests, 250, iterations); else Assert.Equal(0, requests);
                object Stats(long[] values, int length)
                {
                    if (length == 0) return new { samples = 0, meanUs = 0d, p95Us = 0d, p99Us = 0d };
                    Array.Sort(values, 0, length); double sum = 0; for (int i = 0; i < length; i++) sum += values[i];
                    double us = 1e6 / System.Diagnostics.Stopwatch.Frequency;
                    return new { samples = length, meanUs = sum / length * us, p95Us = values[(length - 1) * 95 / 100] * us, p99Us = values[(length - 1) * 99 / 100] * us };
                }
                _output.WriteLine("LOOT_WIDGET_METRICS " + Newtonsoft.Json.JsonConvert.SerializeObject(new {
                    count, animated, logicalDurationMs = iterations * 32, ticks = iterations, requests, paints,
                    boundsChanges, allocatedBytes = allocated, gen0 = GC.CollectionCount(0) - gen0,
                    tick = Stats(ticks, iterations), paint = Stats(paintTimes, paints),
                    paintedPixels = (long)paints * image.Width * image.Height,
                    boundary = "real production Widget; injected clock; forced 32ms ticks; own-request GDI Paint; Overlay Commit/GPU upload excluded"
                }));
            });
        }
    }
}
