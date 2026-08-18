using System;
using System.Drawing;
using System.Drawing.Imaging;
using System.IO;
using System.Linq;
using System.Runtime.InteropServices;
using CF7Launcher.Guardian.Hud.Loot;
using SkiaSharp;
using Xunit;
using Xunit.Abstractions;

namespace CF7Launcher.Tests.Guardian.Hud.Loot
{
    /// <summary>
    /// webp-animated 图标专项：以真实烘焙产物 315cd810.webp（强化石，VP8X/ANIM 动画 webp，
    /// 42/84ms 混合时长、含 disposal/blend 子矩形帧）驱动目录全链路。
    /// SkiaSharp 3.119 只暴露单帧 SKWebpEncoderOptions，无动画 webp 编码器，
    /// 无法合成 fixture，故按预案用真实资产（相对测试程序集向上定位 repo 根）。
    /// </summary>
    public class LootIconCatalogWebpTests
    {
        private const string AnimatedIconName = "强化石";
        private const string AnimatedIconUri = "315cd810.webp";

        private readonly ITestOutputHelper _output;

        public LootIconCatalogWebpTests(ITestOutputHelper output)
        {
            _output = output;
        }

        private static string FindIconsDir()
        {
            DirectoryInfo dir = new DirectoryInfo(AppContext.BaseDirectory);
            while (dir != null)
            {
                string candidate = Path.Combine(dir.FullName, "launcher", "web", "icons");
                if (File.Exists(Path.Combine(candidate, "manifest.json"))) return candidate;
                dir = dir.Parent;
            }
            throw new DirectoryNotFoundException(
                "launcher/web/icons not found above " + AppContext.BaseDirectory);
        }

        [Fact]
        public void TryGet_WebpAnimated_DecodesAllFramesWithPerFrameDurations()
        {
            string iconsDir = FindIconsDir();
            using (LootIconCatalog catalog = new LootIconCatalog(iconsDir))
            {
                LootIconCatalog.LootIconFrames frames;
                Assert.True(catalog.TryGet(AnimatedIconName, out frames));
                Assert.NotNull(frames);
                Assert.True(frames.Animated);

                // 与 SKCodec 独立读出的真实帧数/逐帧时长对齐（不硬编码帧数，跟随资产）
                int codecFrameCount;
                int[] codecDurations;
                using (SKData data = SKData.Create(Path.Combine(iconsDir, AnimatedIconUri)))
                using (SKCodec codec = SKCodec.Create(data))
                {
                    Assert.NotNull(codec);
                    codecFrameCount = codec.FrameCount;
                    codecDurations = codec.FrameInfo.Select(f => Math.Max(0, f.Duration)).ToArray();
                }
                Assert.True(codecFrameCount > 1);
                Assert.Equal(codecFrameCount, frames.Frames.Length);

                Assert.NotNull(frames.DurationMs);
                Assert.Equal(frames.Frames.Length, frames.DurationMs.Length);
                Assert.All(frames.DurationMs, d => Assert.True(d > 0));
                Assert.Equal(codecDurations, frames.DurationMs);
                // 当前资产为 42/84ms 混合：逐帧时长解析必须保留非均匀分布
                Assert.True(frames.DurationMs.Distinct().Count() > 1);

                // 缩略图尺寸/像素格式与静态路径一致
                Assert.All(frames.Frames, b =>
                {
                    Assert.Equal(LootIconCatalog.ThumbSize, b.Width);
                    Assert.Equal(LootIconCatalog.ThumbSize, b.Height);
                    Assert.Equal(PixelFormat.Format32bppPArgb, b.PixelFormat);
                });

                _output.WriteLine("frames=" + frames.Frames.Length
                    + " distinctDurations=" + string.Join(",", frames.DurationMs.Distinct().OrderBy(d => d))
                    + " totalPeriodMs=" + frames.DurationMs.Sum());
            }
        }

        [Fact]
        public void TryGet_WebpAnimated_CompositedFramesAreNotAllIdentical()
        {
            using (LootIconCatalog catalog = new LootIconCatalog(FindIconsDir()))
            {
                LootIconCatalog.LootIconFrames frames;
                Assert.True(catalog.TryGet(AnimatedIconName, out frames));
                Assert.True(frames.Animated);

                byte[] first = PixelsOf(frames.Frames[0]);
                int different = frames.Frames.Skip(1).Count(b => !PixelsOf(b).SequenceEqual(first));
                _output.WriteLine("framesDifferingFromFirst=" + different + "/" + (frames.Frames.Length - 1));
                Assert.True(different > 0, "all composited frames are pixel-identical to frame 0");
            }
        }

        [Fact]
        public void TryGet_WebpAnimated_MissingAnimatedSource_FallsBackToStaticFirstFrame()
        {
            // 合成 manifest：format=webp-animated 但 uri 指向不存在文件 → 落回 f1 静态
            string iconsDir = FindIconsDir();
            string tempDir = Path.Combine(Path.GetTempPath(),
                "cf7-looticon-webp-" + Guid.NewGuid().ToString("N"));
            Directory.CreateDirectory(tempDir);
            try
            {
                File.Copy(Path.Combine(iconsDir, "315cd810_1.webp"),
                    Path.Combine(tempDir, "static_first.webp"));
                File.WriteAllText(Path.Combine(tempDir, "manifest.json"),
                    "{\"测试石\":{\"f1\":\"static_first.webp\",\"uri\":\"missing_anim.webp\","
                    + "\"format\":\"webp-animated\",\"fps\":24}}");
                using (LootIconCatalog catalog = new LootIconCatalog(tempDir))
                {
                    LootIconCatalog.LootIconFrames frames;
                    Assert.True(catalog.TryGet("测试石", out frames));
                    Assert.False(frames.Animated);
                    Assert.Single(frames.Frames);
                    Assert.Null(frames.DurationMs);
                }
            }
            finally
            {
                Directory.Delete(tempDir, true);
            }
        }

        [Fact]
        public void SelectFrameIndex_PerFrameDurations_UsesCumulativeLookup()
        {
            LootIconCatalog.LootIconFrames frames = new LootIconCatalog.LootIconFrames
            {
                Frames = new Bitmap[3],
                Fps = 24,
                DurationMs = new[] { 100, 50, 50 } // 周期 200ms
            };
            Assert.Equal(0, LootFeedWidget.SelectFrameIndex(frames, 0));
            Assert.Equal(0, LootFeedWidget.SelectFrameIndex(frames, 99));
            Assert.Equal(1, LootFeedWidget.SelectFrameIndex(frames, 100));
            Assert.Equal(1, LootFeedWidget.SelectFrameIndex(frames, 149));
            Assert.Equal(2, LootFeedWidget.SelectFrameIndex(frames, 150));
            Assert.Equal(2, LootFeedWidget.SelectFrameIndex(frames, 199));
            Assert.Equal(0, LootFeedWidget.SelectFrameIndex(frames, 200)); // 周期回绕
            Assert.Equal(0, LootFeedWidget.SelectFrameIndex(frames, 250)); // t=50 仍在第 0 帧窗口
            Assert.Equal(1, LootFeedWidget.SelectFrameIndex(frames, 300)); // t=100
        }

        [Fact]
        public void SelectFrameIndex_NullDurations_KeepsUniformFpsSemantics()
        {
            LootIconCatalog.LootIconFrames frames = new LootIconCatalog.LootIconFrames
            {
                Frames = new Bitmap[3],
                Fps = 2,
                DurationMs = null // png-sequence：均匀帧率
            };
            Assert.Equal(0, LootFeedWidget.SelectFrameIndex(frames, 0));
            Assert.Equal(0, LootFeedWidget.SelectFrameIndex(frames, 499));
            Assert.Equal(1, LootFeedWidget.SelectFrameIndex(frames, 500));
            Assert.Equal(2, LootFeedWidget.SelectFrameIndex(frames, 1000));
            Assert.Equal(0, LootFeedWidget.SelectFrameIndex(frames, 1500)); // (1500*2/1000)%3 = 0
        }

        private static byte[] PixelsOf(Bitmap bmp)
        {
            BitmapData data = bmp.LockBits(
                new Rectangle(0, 0, bmp.Width, bmp.Height),
                ImageLockMode.ReadOnly, PixelFormat.Format32bppPArgb);
            try
            {
                byte[] bytes = new byte[Math.Abs(data.Stride) * data.Height];
                Marshal.Copy(data.Scan0, bytes, 0, bytes.Length);
                return bytes;
            }
            finally
            {
                bmp.UnlockBits(data);
            }
        }
    }
}
