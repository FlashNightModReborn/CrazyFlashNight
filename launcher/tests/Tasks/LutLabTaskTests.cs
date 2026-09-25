using System;
using System.IO;
using System.Threading;
using CF7Launcher.Bus;
using CF7Launcher.Guardian;
using CF7Launcher.Guardian.WorldCompositor;
using CF7Launcher.Tasks;
using Newtonsoft.Json.Linq;
using SkiaSharp;
using Xunit;

namespace CF7Launcher.Tests.Tasks
{
    public class LutLabTaskTests
    {
        private static string RepoRoot()
        {
            string root = AppContext.BaseDirectory;
            while (!File.Exists(Path.Combine(root, "AGENTS.md")))
                root = Directory.GetParent(root)?.FullName ?? throw new Exception("Repository missing");
            return root;
        }

        private static string Call(LutLabTask task, JObject message)
        {
            string result = null;
            using (var done = new ManualResetEventSlim())
            {
                task.HandleAsync(message, delegate (string s) { result = s; done.Set(); });
                Assert.True(done.Wait(TimeSpan.FromSeconds(15)), "lutlab task did not respond");
            }
            return result;
        }

        private static LutLabTask NewTask(
            Func<byte[], WorldCompositorController.LutLabGrabResult> grab = null,
            string root = null)
        {
            return new LutLabTask(root ?? RepoRoot(), grab, 1);
        }

        // 信封随 bridge.js：{ task:"lutlab.bakeXml", payload:{ level, mode } }。
        private static JObject BakeMessage(object level, string mode)
        {
            var payload = new JObject();
            if (level != null) payload["level"] = level is JToken t ? t : JToken.FromObject(level);
            if (mode != null) payload["mode"] = mode;
            return new JObject { ["task"] = "lutlab.bakeXml", ["payload"] = payload };
        }

        private static JObject GrabMessage()
        {
            return new JObject { ["task"] = "lutlab.grabFrame", ["payload"] = new JObject() };
        }

        [Fact]
        public void BakeXmlHappyPathMatchesDirectBake()
        {
            var task = NewTask();
            var resp = JObject.Parse(Call(task, BakeMessage(3, "光照")));
            Assert.True(resp.Value<bool>("ok"));
            Assert.True(resp.Value<bool>("success"));
            Assert.Equal("lutlab.bakeXml", resp.Value<string>("task"));
            Assert.Equal("光照", resp.Value<string>("mode"));
            Assert.Equal(32, resp.Value<int>("size"));
            byte[] bytes = Convert.FromBase64String(resp.Value<string>("rgbaBase64"));
            Assert.Equal(WorldLutBaker.RgbaBytes, bytes.Length);
            string resolved;
            byte[] expected = WorldLutBaker.BakeFromXml(
                Path.Combine(RepoRoot(), "data", "environment", "color_engine_preset.xml"),
                "光照", 3, 1, out resolved);
            Assert.Equal(expected, bytes);
        }

        [Fact]
        public void BakeXmlNightVisionAliasResolvesToXmlPresetSet()
        {
            var task = NewTask();
            var resp = JObject.Parse(Call(task, BakeMessage(5, "夜视")));
            Assert.True(resp.Value<bool>("ok"));
            Assert.Equal("夜视仪", resp.Value<string>("mode"));
        }

        [Fact]
        public void BakeXmlRoundTripThroughRealMessageRouter()
        {
            // 生产接线镜像（TaskRegistry.cs RegisterAsync）：真实 LutLabTask 挂进真实
            // MessageRouter，信封与 Web 桥一致 { task, callId, payload }；不起游戏、不碰原生。
            var router = new MessageRouter();
            router.RegisterAsync(LutLabTask.TaskNameBakeXml, NewTask().HandleAsync);
            string result = null;
            using (var done = new ManualResetEventSlim())
            {
                string sync = router.ProcessMessage(
                    "{\"task\":\"lutlab.bakeXml\",\"callId\":\"wt_roundtrip_1\",\"payload\":{\"level\":5,\"mode\":\"夜视\"}}",
                    delegate(string s) { result = s; done.Set(); });
                Assert.Null(sync); // 异步任务不立即返回
                Assert.True(done.Wait(TimeSpan.FromSeconds(15)), "lutlab.bakeXml bus round trip did not respond");
            }
            var resp = JObject.Parse(result);
            Assert.True(resp.Value<bool>("ok"));
            Assert.Equal("wt_roundtrip_1", resp.Value<string>("callId"));
            Assert.Equal("lutlab.bakeXml", resp.Value<string>("task"));
            Assert.Equal("夜视仪", resp.Value<string>("mode"));
            Assert.Equal(32, resp.Value<int>("size"));
            byte[] bytes = Convert.FromBase64String(resp.Value<string>("rgbaBase64"));
            Assert.Equal(WorldLutBaker.RgbaBytes, bytes.Length);
            // 与直接烘焙逐字节一致
            string resolved;
            byte[] expected = WorldLutBaker.BakeFromXml(
                Path.Combine(RepoRoot(), "data", "environment", "color_engine_preset.xml"),
                "夜视", 5, 1, out resolved);
            Assert.Equal(expected, bytes);
        }

        [Fact]
        public void BakeXmlLevelTenUsesExtrapolation()
        {
            var task = NewTask();
            var resp = JObject.Parse(Call(task, BakeMessage(10, "光照")));
            Assert.True(resp.Value<bool>("ok"));
            byte[] bytes = Convert.FromBase64String(resp.Value<string>("rgbaBase64"));
            // 光照 level 10 = 8/9 档外推：亮度 40、对比度 0、饱和度 30、色相 0、乘数 1。
            byte[] expected = WorldLutBaker.Bake(new double[] { 1, 1, 1, 1, 40, 0, 30, 0 }, 1);
            Assert.Equal(expected, bytes);
        }

        [Fact]
        public void BakeXmlRejectsInvalidLevelAndMode()
        {
            var task = NewTask();
            Assert.False(JObject.Parse(Call(task, BakeMessage(null, "光照"))).Value<bool>("ok"));
            Assert.False(JObject.Parse(Call(task, BakeMessage("3", "光照"))).Value<bool>("ok"));
            Assert.False(JObject.Parse(Call(task, BakeMessage(-1, "光照"))).Value<bool>("ok"));
            Assert.False(JObject.Parse(Call(task, BakeMessage(11, "光照"))).Value<bool>("ok"));
            Assert.False(JObject.Parse(Call(task, BakeMessage(new JValue(double.NaN), "光照"))).Value<bool>("ok"));
            Assert.False(JObject.Parse(Call(task, BakeMessage(3, null))).Value<bool>("ok"));
            var unknown = JObject.Parse(Call(task, BakeMessage(3, "不存在")));
            Assert.False(unknown.Value<bool>("ok"));
            Assert.Equal("unknown mode: 不存在", unknown.Value<string>("error"));
        }

        [Fact]
        public void GrabFrameWithoutValidFrameReturnsExplicitError()
        {
            var task = NewTask(
                _ => new WorldCompositorController.LutLabGrabResult(NativeCompositorSession.GrabNoFrame, 0, 0));
            var resp = JObject.Parse(Call(task, GrabMessage()));
            Assert.False(resp.Value<bool>("ok"));
            Assert.False(resp.Value<bool>("success"));
            Assert.Equal("no_frame", resp.Value<string>("error"));
        }

        [Fact]
        public void GrabFrameReportsMissingCompanionNativeBuild()
        {
            var task = NewTask(
                _ => new WorldCompositorController.LutLabGrabResult(
                    NativeCompositorSession.GrabExportUnavailable, 0, 0));
            var resp = JObject.Parse(Call(task, GrabMessage()));
            Assert.False(resp.Value<bool>("ok"));
            Assert.Equal("grab_export_unavailable", resp.Value<string>("error"));
        }

        [Fact]
        public void GrabFrameWritesPngAndReturnsVirtualHostUrl()
        {
            string root = Path.Combine(Path.GetTempPath(), "cf7-lutlab-test-" + Guid.NewGuid().ToString("N"));
            try
            {
                // 4x2 BGRA：pixel(0,0)=B10/G20/R30/A255，其余递增。
                var pixels = new byte[4 * 2 * 4];
                for (int i = 0; i < pixels.Length; i += 4)
                {
                    pixels[i] = (byte)(10 + i / 4); pixels[i + 1] = (byte)(20 + i / 4);
                    pixels[i + 2] = (byte)(30 + i / 4); pixels[i + 3] = 255;
                }
                Func<byte[], WorldCompositorController.LutLabGrabResult> grab = buffer =>
                {
                    if (buffer == null)
                        return new WorldCompositorController.LutLabGrabResult(
                            NativeCompositorSession.GrabBufferTooSmall, 4, 2);
                    Array.Copy(pixels, buffer, pixels.Length);
                    return new WorldCompositorController.LutLabGrabResult(NativeCompositorSession.GrabOk, 4, 2);
                };
                var task = NewTask(grab, root);
                var resp = JObject.Parse(Call(task, GrabMessage()));
                Assert.True(resp.Value<bool>("ok"), resp.ToString());
                Assert.Equal(4, resp.Value<int>("width"));
                Assert.Equal(2, resp.Value<int>("height"));
                string url = resp.Value<string>("url");
                Assert.StartsWith("https://cf7-lutlab/frames/frame-", url);
                Assert.EndsWith(".png", url);
                string name = url.Substring("https://cf7-lutlab/frames/".Length);
                string path = Path.Combine(root, "tmp", "lut-lab", "frames", name);
                Assert.True(File.Exists(path));
                byte[] png = File.ReadAllBytes(path);
                Assert.Equal(new byte[] { 137, 80, 78, 71, 13, 10, 26, 10 },
                    new byte[] { png[0], png[1], png[2], png[3], png[4], png[5], png[6], png[7] });
                using (var bitmap = SKBitmap.Decode(png))
                {
                    Assert.Equal(4, bitmap.Width);
                    Assert.Equal(2, bitmap.Height);
                    var pixel = bitmap.GetPixel(0, 0);
                    Assert.Equal(30, pixel.Red);
                    Assert.Equal(20, pixel.Green);
                    Assert.Equal(10, pixel.Blue);
                }
            }
            finally
            {
                if (Directory.Exists(root)) Directory.Delete(root, true);
            }
        }

        [Fact]
        public void BakeXmlSetReturnsTenLevelsMatchingDirectBake()
        {
            var task = NewTask();
            var message = new JObject
            {
                ["task"] = "lutlab.bakeXmlSet",
                ["payload"] = new JObject { ["mode"] = "光照" }
            };
            var resp = JObject.Parse(Call(task, message));
            Assert.True(resp.Value<bool>("ok"), resp.ToString());
            Assert.Equal("光照", resp.Value<string>("mode"));
            Assert.Equal(32, resp.Value<int>("size"));
            var levels = (JArray)resp["levels"];
            Assert.Equal(10, levels.Count);
            string xmlPath = Path.Combine(RepoRoot(), "data", "environment", "color_engine_preset.xml");
            for (int level = 0; level <= 9; level++)
            {
                var entry = (JObject)levels[level];
                Assert.Equal(level, entry.Value<int>("level"));
                string resolved;
                byte[] expected = WorldLutBaker.BakeFromXml(xmlPath, "光照", level, 1, out resolved);
                Assert.Equal(
                    Convert.ToBase64String(expected),
                    entry.Value<string>("rgbaBase64"));
            }
        }

        [Fact]
        public void BakeXmlSetNightVisionAliasAndModeValidation()
        {
            var task = NewTask();
            var nightVision = JObject.Parse(Call(task, new JObject
            {
                ["task"] = "lutlab.bakeXmlSet",
                ["payload"] = new JObject { ["mode"] = "夜视" }
            }));
            Assert.True(nightVision.Value<bool>("ok"));
            Assert.Equal("夜视仪", nightVision.Value<string>("mode"));
            Assert.Equal(10, ((JArray)nightVision["levels"]).Count);

            var missing = JObject.Parse(Call(task, new JObject
            {
                ["task"] = "lutlab.bakeXmlSet",
                ["payload"] = new JObject()
            }));
            Assert.False(missing.Value<bool>("ok"));
            var unknown = JObject.Parse(Call(task, new JObject
            {
                ["task"] = "lutlab.bakeXmlSet",
                ["payload"] = new JObject { ["mode"] = "不存在" }
            }));
            Assert.False(unknown.Value<bool>("ok"));
            Assert.Equal("unknown mode: 不存在", unknown.Value<string>("error"));
        }

        [Fact]
        public void SavePresetWritesCubesAndManifestAtomicallyWithSelfCheck()
        {
            string root = Path.Combine(Path.GetTempPath(), "cf7-lutlab-test-" + Guid.NewGuid().ToString("N"));
            try
            {
                var task = NewTask(null, root);
                // 10 档确定性字节：第 i 档整体值=i（便于回读逐字节核对）
                var levels = new JArray();
                var expectedRgba = new byte[10][];
                for (int i = 0; i < 10; i++)
                {
                    byte[] rgba = new byte[WorldLutBaker.RgbaBytes];
                    for (int p = 0; p < rgba.Length; p += 4)
                    {
                        rgba[p] = (byte)i; rgba[p + 1] = (byte)(i * 2); rgba[p + 2] = (byte)(255 - i); rgba[p + 3] = 255;
                    }
                    expectedRgba[i] = rgba;
                    levels.Add(new JObject
                    {
                        ["level"] = i,
                        ["rgbaBase64"] = Convert.ToBase64String(rgba)
                    });
                }
                var message = new JObject
                {
                    ["task"] = "lutlab.savePreset",
                    ["payload"] = new JObject
                    {
                        ["name"] = "t预设",
                        ["mode"] = "夜视",
                        ["preset"] = new JObject
                        {
                            ["schemaVersion"] = 1,
                            ["mode"] = "夜视",
                            ["edgePolicy"] = "hold",
                            ["notes"] = "测试预设"
                        },
                        ["levels"] = levels
                    }
                };
                var resp = JObject.Parse(Call(task, message));
                Assert.True(resp.Value<bool>("ok"), resp.ToString());
                Assert.Equal("t预设", resp.Value<string>("name"));
                Assert.Equal("presets/t预设", resp.Value<string>("dir"));
                Assert.Equal(10, ((JArray)resp["levels"]).Count);

                string dir = Path.Combine(root, "tmp", "lut-lab", "presets", "t预设");
                Assert.True(File.Exists(Path.Combine(dir, "preset.json")));
                // 每个 cube 与 WorldLutBaker.WriteCube 同序列化逐字节一致
                for (int i = 0; i < 10; i++)
                {
                    string path = Path.Combine(dir, "夜视-" + i + ".cube");
                    Assert.True(File.Exists(path));
                    string expectedPath = Path.Combine(root, "expected-" + i + ".cube");
                    WorldLutBaker.WriteCube(expectedPath,
                        "t预设 (夜视, lut-lab preset) L" + i, expectedRgba[i]);
                    Assert.Equal(
                        File.ReadAllText(expectedPath),
                        File.ReadAllText(path));
                }
                // manifest.sets.json 原子 upsert：条目存在且 files 为 10 档
                string manifestPath = Path.Combine(root, "tmp", "lut-lab", "sets", "manifest.sets.json");
                Assert.True(File.Exists(manifestPath));
                Assert.False(File.Exists(manifestPath + ".tmp"));
                var manifest = (JArray)JArray.Parse(File.ReadAllText(manifestPath));
                var entry = (JObject)manifest[0];
                Assert.Equal("t预设", entry.Value<string>("name"));
                Assert.Equal("预设 · t预设", entry.Value<string>("title"));
                Assert.Equal("夜视", entry.Value<string>("mode"));
                Assert.Equal("presets/t预设", entry.Value<string>("dir"));
                Assert.Equal(10, ((JArray)entry["files"]).Count);
                Assert.Equal("夜视-0.cube", ((JArray)entry["files"])[0].Value<string>());
                // 回包 levels 与输入逐字节一致（自检通过的内容）
                var respLevels = (JArray)resp["levels"];
                for (int i = 0; i < 10; i++)
                {
                    Assert.Equal(
                        Convert.ToBase64String(expectedRgba[i]),
                        ((JObject)respLevels[i]).Value<string>("rgbaBase64"));
                }

                // 同名再保存 = upsert（manifest 仍 1 条）
                var resp2 = JObject.Parse(Call(task, message));
                Assert.True(resp2.Value<bool>("ok"));
                manifest = (JArray)JArray.Parse(File.ReadAllText(manifestPath));
                Assert.Equal(1, manifest.Count);
            }
            finally
            {
                if (Directory.Exists(root)) Directory.Delete(root, true);
            }
        }

        [Fact]
        public void SavePresetRejectsBadNameModeAndLevels()
        {
            var task = NewTask();
            JObject MakeMessage(JToken name, JToken mode, JArray levels)
            {
                return new JObject
                {
                    ["task"] = "lutlab.savePreset",
                    ["payload"] = new JObject
                    {
                        ["name"] = name,
                        ["mode"] = mode,
                        ["preset"] = new JObject(),
                        ["levels"] = levels
                    }
                };
            }
            var goodLevels = new JArray();
            for (int i = 0; i < 10; i++)
            {
                goodLevels.Add(new JObject
                {
                    ["level"] = i,
                    ["rgbaBase64"] = Convert.ToBase64String(new byte[WorldLutBaker.RgbaBytes])
                });
            }
            foreach (string badName in new[] { "", " ", "a/b", "a\\b", "..", ".", " x" })
            {
                var resp = JObject.Parse(Call(task, MakeMessage(badName, "光照", goodLevels)));
                Assert.False(resp.Value<bool>("ok"), "name=" + badName);
            }
            var badMode = JObject.Parse(Call(task, MakeMessage("ok", "黄昏", goodLevels)));
            Assert.False(badMode.Value<bool>("ok"));
            var shortLevels = new JArray(goodLevels);
            shortLevels.RemoveAt(0);
            var badLevels = JObject.Parse(Call(task, MakeMessage("ok", "光照", shortLevels)));
            Assert.False(badLevels.Value<bool>("ok"));
            var notTempRoot = Path.Combine(Path.GetTempPath(), "cf7-lutlab-test-" + Guid.NewGuid().ToString("N"));
            try
            {
                var writeTask = NewTask(null, notTempRoot);
                var misordered = new JArray(goodLevels);
                ((JObject)misordered[3])["level"] = 7;
                var misorderedResp = JObject.Parse(Call(writeTask, MakeMessage("ok", "光照", misordered)));
                Assert.False(misorderedResp.Value<bool>("ok"));
                Assert.False(Directory.Exists(Path.Combine(notTempRoot, "tmp", "lut-lab", "presets")));
            }
            finally
            {
                if (Directory.Exists(notTempRoot)) Directory.Delete(notTempRoot, true);
            }
        }

        [Fact]
        public void TryValidatePresetNameContract()
        {
            string error;
            Assert.True(LutLabTask.TryValidatePresetName("t预设-1", out error));
            Assert.False(LutLabTask.TryValidatePresetName(null, out error));
            Assert.False(LutLabTask.TryValidatePresetName("a/b", out error));
            Assert.False(LutLabTask.TryValidatePresetName("a\\b", out error));
            Assert.False(LutLabTask.TryValidatePresetName(new string('x', 65), out error));
        }

        [Fact]
        public void TryGrabEntryFrameUrlWritesPngAndReturnsVhostUrl()
        {
            // 4x2 BGRA fixture（同 GrabFrameWritesPngAndReturnsVirtualHostUrl 语形）
            string root = Path.Combine(Path.GetTempPath(), "cf7-lutlab-test-" + Guid.NewGuid().ToString("N"));
            try
            {
                var pixels = new byte[4 * 2 * 4];
                for (int i = 0; i < pixels.Length; i += 4)
                {
                    pixels[i] = (byte)(10 + i / 4); pixels[i + 1] = (byte)(20 + i / 4);
                    pixels[i + 2] = (byte)(30 + i / 4); pixels[i + 3] = 255;
                }
                Func<byte[], WorldCompositorController.LutLabGrabResult> grab = buffer =>
                {
                    if (buffer == null)
                        return new WorldCompositorController.LutLabGrabResult(
                            NativeCompositorSession.GrabBufferTooSmall, 4, 2);
                    Array.Copy(pixels, buffer, pixels.Length);
                    return new WorldCompositorController.LutLabGrabResult(NativeCompositorSession.GrabOk, 4, 2);
                };
                var task = NewTask(grab, root);
                string url = task.TryGrabEntryFrameUrl();
                Assert.NotNull(url);
                Assert.StartsWith("https://cf7-lutlab/frames/frame-", url);
                Assert.EndsWith(".png", url);
                string name = url.Substring("https://cf7-lutlab/frames/".Length);
                string path = Path.Combine(root, "tmp", "lut-lab", "frames", name);
                Assert.True(File.Exists(path));
                byte[] png = File.ReadAllBytes(path);
                Assert.Equal(new byte[] { 137, 80, 78, 71, 13, 10, 26, 10 },
                    new byte[] { png[0], png[1], png[2], png[3], png[4], png[5], png[6], png[7] });
            }
            finally
            {
                if (Directory.Exists(root)) Directory.Delete(root, true);
            }
        }

        [Fact]
        public void TryGrabEntryFrameUrlReturnsNullOnNoFrame()
        {
            var task = NewTask(
                _ => new WorldCompositorController.LutLabGrabResult(NativeCompositorSession.GrabNoFrame, 0, 0));
            Assert.Null(task.TryGrabEntryFrameUrl());
        }

        [Fact]
        public void TryGrabEntryFrameUrlReturnsNullWithoutGrabSource()
        {
            // grab 未注入（合成器未接线）→ null，不抛异常
            Assert.Null(NewTask().TryGrabEntryFrameUrl());
        }

        [Fact]
        public void WebIngressForLutLabAllowedByTaskName()
        {
            // lutlab 三条 task 按名放行（无配置门控）；其他 task 名不放行。
            Assert.True(WebOverlayForm.IsLutLabIngressAllowed("lutlab.grabFrame"));
            Assert.True(WebOverlayForm.IsLutLabIngressAllowed("lutlab.bakeXml"));
            Assert.True(WebOverlayForm.IsLutLabIngressAllowed("lutlab.bakeXmlSet"));
            Assert.False(WebOverlayForm.IsLutLabIngressAllowed("font_pack"));
            // 静态 Web-origin 白名单不随 dev 面板变化。
            Assert.False(WebOverlayForm.IsWebTaskRouterIngressAllowed("lutlab.grabFrame"));
            Assert.False(WebOverlayForm.IsWebTaskRouterIngressAllowed("lutlab.bakeXml"));
            Assert.False(WebOverlayForm.IsWebTaskRouterIngressAllowed("lutlab.bakeXmlSet"));
        }
    }
}
