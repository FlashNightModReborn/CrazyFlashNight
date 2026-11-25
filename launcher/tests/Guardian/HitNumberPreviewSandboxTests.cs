using System;
using System.Drawing;
using System.IO;
using System.Runtime.InteropServices;
using CF7Launcher.Guardian.HitNumbers;
using Newtonsoft.Json.Linq;
using Xunit;

namespace CF7Launcher.Tests.Guardian
{
    public sealed class HitNumberPreviewSandboxTests
    {
        [DllImport("user32.dll")]
        private static extern uint GetGuiResources(IntPtr hProcess, uint uiFlags);

        [Fact]
        public void Capability_ExposesBoundedOriginDimensionsAndFourPresets()
        {
            JObject capability = HitNumberPreviewWebResources.BuildCapability();
            Assert.Equal(1, capability.Value<int>("v"));
            Assert.Equal("https://cf7-hitpreview.local", capability.Value<string>("origin"));
            Assert.Equal(512, capability.Value<int>("width"));
            Assert.Equal(288, capability.Value<int>("height"));
            var presets = Assert.IsType<JArray>(capability["presets"]);
            Assert.Equal(4, presets.Count);
            Assert.Equal("light", presets[0].Value<string>("id"));
            Assert.Equal("barrage", presets[1].Value<string>("id"));
            Assert.Equal("crowd", presets[2].Value<string>("id"));
            Assert.Equal("healing", presets[3].Value<string>("id"));
        }

        [Theory]
        [InlineData("light", "balanced", 24, 1450)]
        [InlineData("barrage", "balanced", 24, 1850)]
        [InlineData("barrage", "total", 24, 1850)]
        [InlineData("barrage", "classic", 0, 1850)]
        [InlineData("barrage", "detail", 24, 1850)]
        [InlineData("crowd", "detail", 24, 1700)]
        [InlineData("healing", "balanced", 24, 1800)]
        [InlineData("healing", "total", 24, 1800)]
        public void Sandbox_RendersValidTransparentPngWithVisibleCombatNumbers(
            string presetId,
            string modeName,
            int limit,
            int timeMs)
        {
            HitNumberDisplayMode mode = HitNumberRuntimeOptions.FromPreferences(modeName, limit).Mode;
            using (var sandbox = new HitNumberPreviewSandbox())
            {
                HitNumberPreviewFrameResult frame = sandbox.RenderFrame(new HitNumberPreviewRequest(
                    presetId, mode, limit, timeMs, 512, 288, true));

                Assert.NotNull(frame.PngBytes);
                Assert.True(frame.PngBytes.Length > 200);
                Assert.True(frame.ActiveItems > 0, "Expected visible items for " + presetId + "/" + mode);

                using (var stream = new MemoryStream(frame.PngBytes))
                using (var decoded = new Bitmap(stream))
                {
                    Assert.Equal(512, decoded.Width);
                    Assert.Equal(288, decoded.Height);
                    // 四角保持透明，允许前端叠加压暗背景或游戏进入截图
                    Assert.Equal(0, decoded.GetPixel(0, 0).A);
                    Assert.Equal(0, decoded.GetPixel(511, 0).A);
                }
            }
        }

        [Fact]
        public void Sandbox_OffModeClearsCombatNumbersAndLowLimitReportsOmittedRows()
        {
            using (var sandbox = new HitNumberPreviewSandbox())
            {
                HitNumberPreviewFrameResult off = sandbox.RenderFrame(new HitNumberPreviewRequest(
                    "barrage", HitNumberDisplayMode.Off, 24, 1850, 512, 288, false));
                Assert.Equal(0, off.ActiveItems);
                Assert.Equal(0, off.ActiveRows);

                HitNumberPreviewFrameResult unlimited = sandbox.RenderFrame(new HitNumberPreviewRequest(
                    "barrage", HitNumberDisplayMode.Detail, 0, 1850, 512, 288, true));
                HitNumberPreviewFrameResult capped = sandbox.RenderFrame(new HitNumberPreviewRequest(
                    "barrage", HitNumberDisplayMode.Detail, 3, 1850, 512, 288, true));

                Assert.True(unlimited.ActiveRows > capped.ActiveRows);
                Assert.True(capped.ActiveRows <= 3);
                Assert.True(capped.OmittedRows > 0);
            }
        }

        [Fact]
        public void WebResources_EnforcesExactInstanceIdAndValidatesParameters()
        {
            using (var sandbox = new HitNumberPreviewSandbox())
            {
                HitNumberPreviewHttpResponse ok = HitNumberPreviewWebResources.Resolve(
                    "https://cf7-hitpreview.local/frame?instance=settings.inst.1&preset=barrage&mode=balanced&limit=24&t=1850",
                    "GET",
                    sandbox,
                    "settings.inst.1");
                Assert.Equal(200, ok.StatusCode);
                Assert.Equal("image/png", ok.ContentType);
                Assert.True(ok.Body.Length > 200);

                HitNumberPreviewHttpResponse foreign = HitNumberPreviewWebResources.Resolve(
                    "https://cf7-hitpreview.local/frame?instance=settings.inst.old&preset=barrage&mode=balanced&limit=24&t=1850",
                    "GET",
                    sandbox,
                    "settings.inst.1");
                Assert.Equal(403, foreign.StatusCode);

                HitNumberPreviewHttpResponse noActive = HitNumberPreviewWebResources.Resolve(
                    "https://cf7-hitpreview.local/frame?instance=settings.inst.1&preset=barrage&mode=balanced&limit=24&t=1850",
                    "GET",
                    sandbox,
                    null);
                Assert.Equal(403, noActive.StatusCode);

                HitNumberPreviewHttpResponse badPreset = HitNumberPreviewWebResources.Resolve(
                    "https://cf7-hitpreview.local/frame?instance=settings.inst.1&preset=evil&mode=balanced",
                    "GET",
                    sandbox,
                    "settings.inst.1");
                Assert.Equal(400, badPreset.StatusCode);

                HitNumberPreviewHttpResponse badMode = HitNumberPreviewWebResources.Resolve(
                    "https://cf7-hitpreview.local/frame?instance=settings.inst.1&preset=light&mode=hack",
                    "GET",
                    sandbox,
                    "settings.inst.1");
                Assert.Equal(400, badMode.StatusCode);

                HitNumberPreviewHttpResponse badLimit = HitNumberPreviewWebResources.Resolve(
                    "https://cf7-hitpreview.local/frame?instance=settings.inst.1&preset=light&mode=balanced&limit=9999",
                    "GET",
                    sandbox,
                    "settings.inst.1");
                Assert.Equal(400, badLimit.StatusCode);

                HitNumberPreviewHttpResponse postRejected = HitNumberPreviewWebResources.Resolve(
                    "https://cf7-hitpreview.local/frame?instance=settings.inst.1&preset=light&mode=balanced",
                    "POST",
                    sandbox,
                    "settings.inst.1");
                Assert.Equal(405, postRejected.StatusCode);
            }
        }

        [Fact]
        public void Sandbox_ReleaseResourcesDisposesGdiAndStaysBoundedAcrossCycles()
        {
            IntPtr proc = System.Diagnostics.Process.GetCurrentProcess().Handle;
            using (var sandbox = new HitNumberPreviewSandbox())
            {
                // 预热一次以排除测试进程首次加载字体/GDI 内部池的冷启动抖动
                sandbox.RenderFrame(new HitNumberPreviewRequest(
                    "barrage", HitNumberDisplayMode.Balanced, 24, 1500, 512, 288, true));
                sandbox.ReleaseResources();
                Assert.False(sandbox.HasAllocatedResourcesForTests);

                uint gdiBefore = GetGuiResources(proc, 0);
                for (int cycle = 0; cycle < 8; cycle++)
                {
                    for (int step = 0; step < 5; step++)
                    {
                        sandbox.RenderFrame(new HitNumberPreviewRequest(
                            "barrage", HitNumberDisplayMode.Detail, 24, 400 + step * 120, 512, 288, true));
                    }
                    sandbox.ReleaseResources();
                    Assert.False(sandbox.HasAllocatedResourcesForTests);
                }
                uint gdiAfter = GetGuiResources(proc, 0);
                Assert.True((int)gdiAfter - (int)gdiBefore <= 4,
                    "GDI handle delta exceeded threshold: before=" + gdiBefore + " after=" + gdiAfter);
            }
        }
    }
}
