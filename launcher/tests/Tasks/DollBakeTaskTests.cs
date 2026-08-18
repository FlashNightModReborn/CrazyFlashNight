using System;
using System.Drawing;
using System.Drawing.Imaging;
using System.IO;
using Newtonsoft.Json.Linq;
using Xunit;
using CF7Launcher.Guardian.Hud.Loot;
using CF7Launcher.Tasks;

namespace CF7Launcher.Tests.Tasks
{
    /// <summary>
    /// DollBakeTask：web 侧 doll-bake.js 烘焙回传 {key, requestId, pngBase64} → 校验 +
    /// 原子写 launcher/data/doll-portraits/&lt;hex&gt;.png。覆盖落盘正确性、
    /// exact 在飞关联、同字节跳过、坏 key（路径穿越防护）、完整 PNG/尺寸与 web 显式失败。
    /// </summary>
    public class DollBakeTaskTests
    {
        private const string ValidKey = "纸娃娃-8a44ae89";

        private static string CreateTempDir()
        {
            string dir = Path.Combine(Path.GetTempPath(), "cf7-doll-bake-test-" + Guid.NewGuid().ToString("N"));
            Directory.CreateDirectory(dir);
            return dir;
        }

        private static byte[] CreatePng(byte seed, int size = 256)
        {
            using (Bitmap bmp = new Bitmap(size, size, PixelFormat.Format32bppArgb))
            using (Graphics graphics = Graphics.FromImage(bmp))
            {
                graphics.Clear(Color.FromArgb(255, seed, (byte)(255 - seed), 40));
                using (SolidBrush marker = new SolidBrush(Color.FromArgb(255, 40, seed, (byte)(255 - seed))))
                    graphics.FillRectangle(marker, 0, 0, Math.Max(1, size / 4), Math.Max(1, size / 4));
                using (MemoryStream ms = new MemoryStream())
                {
                    bmp.Save(ms, ImageFormat.Png);
                    return ms.ToArray();
                }
            }
        }

        private static JObject Message(string key, string pngBase64,
            string requestId = "direct-test", string error = null)
        {
            var payload = new JObject();
            if (key != null) payload["key"] = key;
            if (pngBase64 != null) payload["pngBase64"] = pngBase64;
            if (requestId != null) payload["requestId"] = requestId;
            if (error != null) payload["error"] = error;
            var msg = new JObject();
            msg["payload"] = payload;
            return msg;
        }

        [Fact]
        public void Handle_ValidResult_WritesPngFileContent()
        {
            string dir = CreateTempDir();
            try
            {
                var task = DollBakeTask.ForDirectory(dir, null);
                byte[] png = CreatePng(10);
                string resp = task.Handle(Message(ValidKey, Convert.ToBase64String(png), "req-1"));

                JObject parsed = JObject.Parse(resp);
                Assert.True(parsed.Value<bool>("success"));
                Assert.Equal("created", parsed.Value<string>("action"));

                string filePath = Path.Combine(dir, "8a44ae89.png");
                Assert.True(File.Exists(filePath));
                Assert.Equal(png, File.ReadAllBytes(filePath));
            }
            finally
            {
                Directory.Delete(dir, true);
            }
        }

        [Fact]
        public void Handle_SameBytes_SkipsAsUnchanged()
        {
            string dir = CreateTempDir();
            try
            {
                var task = DollBakeTask.ForDirectory(dir, null);
                byte[] png = CreatePng(20);
                File.WriteAllBytes(Path.Combine(dir, "8a44ae89.png"), png);

                string resp = task.Handle(Message(ValidKey, Convert.ToBase64String(png)));
                JObject parsed = JObject.Parse(resp);
                Assert.True(parsed.Value<bool>("success"));
                Assert.Equal("unchanged", parsed.Value<string>("action"));
                Assert.Equal(png, File.ReadAllBytes(Path.Combine(dir, "8a44ae89.png")));
            }
            finally
            {
                Directory.Delete(dir, true);
            }
        }

        [Fact]
        public void Handle_DifferentBytes_Updates()
        {
            string dir = CreateTempDir();
            try
            {
                var task = DollBakeTask.ForDirectory(dir, null);
                File.WriteAllBytes(Path.Combine(dir, "8a44ae89.png"), CreatePng(1));
                byte[] newer = CreatePng(90);

                string resp = task.Handle(Message(ValidKey, Convert.ToBase64String(newer)));
                JObject parsed = JObject.Parse(resp);
                Assert.True(parsed.Value<bool>("success"));
                Assert.Equal("updated", parsed.Value<string>("action"));
                Assert.Equal(newer, File.ReadAllBytes(Path.Combine(dir, "8a44ae89.png")));
            }
            finally
            {
                Directory.Delete(dir, true);
            }
        }

        [Theory]
        [InlineData("纸娃娃-../../evil")]
        [InlineData("纸娃娃-..\\..\\evil")]
        [InlineData("纸娃娃-ABCDEF12")] // 大写 hex 非法（契约锁定小写）
        [InlineData("纸娃娃-123")]      // 长度不足
        [InlineData("纸娃娃-8a44ae89ff")] // 超长
        [InlineData("斗士-8a44ae89")]   // 错误前缀
        [InlineData("纸娃娃-8a44ae8g")] // 非 hex 字符
        [InlineData(null)]
        public void Handle_BadKey_RejectedNoFile(string badKey)
        {
            string dir = CreateTempDir();
            try
            {
                var task = DollBakeTask.ForDirectory(dir, null);
                string resp = task.Handle(Message(badKey, Convert.ToBase64String(CreatePng(3))));
                JObject parsed = JObject.Parse(resp);
                Assert.False(parsed.Value<bool>("success"));
                Assert.Empty(Directory.GetFiles(dir));
            }
            finally
            {
                Directory.Delete(dir, true);
            }
        }

        [Fact]
        public void Handle_NotPng_Rejected()
        {
            string dir = CreateTempDir();
            try
            {
                var task = DollBakeTask.ForDirectory(dir, null);
                string resp = task.Handle(Message(ValidKey,
                    Convert.ToBase64String(System.Text.Encoding.UTF8.GetBytes("not a png at all"))));
                JObject parsed = JObject.Parse(resp);
                Assert.False(parsed.Value<bool>("success"));
                Assert.Empty(Directory.GetFiles(dir));
            }
            finally
            {
                Directory.Delete(dir, true);
            }
        }

        [Fact]
        public void Handle_MissingRequestId_RejectedNoFile()
        {
            string dir = CreateTempDir();
            try
            {
                var task = DollBakeTask.ForDirectory(dir, null);
                string resp = task.Handle(Message(ValidKey,
                    Convert.ToBase64String(CreatePng(3)), requestId: null));

                JObject parsed = JObject.Parse(resp);
                Assert.False(parsed.Value<bool>("success"));
                Assert.Contains("requestId", parsed.Value<string>("error"));
                Assert.Empty(Directory.GetFiles(dir));
            }
            finally
            {
                Directory.Delete(dir, true);
            }
        }

        [Fact]
        public void Handle_PngSignatureWithoutDecodableImage_RejectedNoFile()
        {
            string dir = CreateTempDir();
            try
            {
                var task = DollBakeTask.ForDirectory(dir, null);
                byte[] corrupt =
                {
                    0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A,
                    0x00, 0x00, 0x00, 0x00
                };
                string resp = task.Handle(Message(ValidKey, Convert.ToBase64String(corrupt)));

                JObject parsed = JObject.Parse(resp);
                Assert.False(parsed.Value<bool>("success"));
                Assert.Contains("corrupt", parsed.Value<string>("error"), StringComparison.OrdinalIgnoreCase);
                Assert.Empty(Directory.GetFiles(dir));
            }
            finally
            {
                Directory.Delete(dir, true);
            }
        }

        [Fact]
        public void Handle_WrongPngDimensions_RejectedNoFile()
        {
            string dir = CreateTempDir();
            try
            {
                var task = DollBakeTask.ForDirectory(dir, null);
                string resp = task.Handle(Message(ValidKey,
                    Convert.ToBase64String(CreatePng(4, 8))));

                JObject parsed = JObject.Parse(resp);
                Assert.False(parsed.Value<bool>("success"));
                Assert.Contains("256x256", parsed.Value<string>("error"));
                Assert.Empty(Directory.GetFiles(dir));
            }
            finally
            {
                Directory.Delete(dir, true);
            }
        }

        [Fact]
        public void Handle_WebErrorPayload_ReturnsErrorNoFile()
        {
            string dir = CreateTempDir();
            try
            {
                var task = DollBakeTask.ForDirectory(dir, null);
                string resp = task.Handle(Message(ValidKey, null, "req-9", "empty render"));
                JObject parsed = JObject.Parse(resp);
                Assert.False(parsed.Value<bool>("success"));
                Assert.Empty(Directory.GetFiles(dir));
            }
            finally
            {
                Directory.Delete(dir, true);
            }
        }

        [Fact]
        public void Handle_ResultRequiresExactRequestBeforeWriteAndClear()
        {
            string dir = CreateTempDir();
            try
            {
                int posts = 0;
                string posted = null;
                var service = new DollPortraitBakeService(dir, delegate(string json)
                {
                    posts++;
                    posted = json;
                    return true;
                });
                var task = DollBakeTask.ForDirectory(dir, service);
                var tuple = new System.Collections.Generic.Dictionary<string, string>
                {
                    { "face", "女变装-基本脸型" }, { "gender", "女" }
                };
                string key = DollPortraitKey.Compute(tuple);

                service.EnsurePortrait(tuple, key);
                Assert.Equal(1, posts);
                Assert.Equal(1, service.PendingCount);
                string requestId = JObject.Parse(posted).Value<string>("requestId");
                string pngBase64 = Convert.ToBase64String(CreatePng(7));

                JObject stale = JObject.Parse(task.Handle(Message(key, pngBase64, "stale-request")));
                Assert.False(stale.Value<bool>("success"));
                Assert.Equal(1, service.PendingCount);
                Assert.False(File.Exists(Path.Combine(dir, DollPortraitKey.ComputeHex(tuple) + ".png")));

                JObject accepted = JObject.Parse(task.Handle(Message(key, pngBase64, requestId)));
                Assert.True(accepted.Value<bool>("success"));
                Assert.Equal(0, service.PendingCount);
                Assert.True(File.Exists(Path.Combine(dir, DollPortraitKey.ComputeHex(tuple) + ".png")));
                service.Dispose();
            }
            finally
            {
                Directory.Delete(dir, true);
            }
        }

        [Fact]
        public void Handle_LatePriorResultCannotWriteOrClearReplacementRequest()
        {
            string dir = CreateTempDir();
            try
            {
                var posts = new System.Collections.Generic.List<JObject>();
                var service = new DollPortraitBakeService(dir, delegate(string json)
                {
                    posts.Add(JObject.Parse(json));
                    return true;
                });
                var task = DollBakeTask.ForDirectory(dir, service);
                var tuple = new System.Collections.Generic.Dictionary<string, string>
                {
                    { "face", "女变装-基本脸型" }, { "gender", "女" }
                };
                string key = DollPortraitKey.Compute(tuple);
                string filePath = Path.Combine(dir, DollPortraitKey.ComputeHex(tuple) + ".png");
                string pngBase64 = Convert.ToBase64String(CreatePng(11));

                service.EnsurePortrait(tuple, key);
                string requestA = posts[0].Value<string>("requestId");
                JObject failedA = JObject.Parse(task.Handle(
                    Message(key, null, requestA, "render failed")));
                Assert.False(failedA.Value<bool>("success"));
                Assert.Equal(0, service.PendingCount);

                service.EnsurePortrait(tuple, key);
                string requestB = posts[1].Value<string>("requestId");
                Assert.NotEqual(requestA, requestB);
                Assert.Equal(1, service.PendingCount);

                JObject lateA = JObject.Parse(task.Handle(Message(key, pngBase64, requestA)));
                Assert.False(lateA.Value<bool>("success"));
                Assert.Equal(1, service.PendingCount);
                Assert.False(File.Exists(filePath));

                JObject acceptedB = JObject.Parse(task.Handle(Message(key, pngBase64, requestB)));
                Assert.True(acceptedB.Value<bool>("success"));
                Assert.Equal(0, service.PendingCount);
                Assert.True(File.Exists(filePath));

                JObject duplicateB = JObject.Parse(task.Handle(Message(key, pngBase64, requestB)));
                Assert.False(duplicateB.Value<bool>("success"));
                Assert.Equal(0, service.PendingCount);
                service.Dispose();
            }
            finally
            {
                Directory.Delete(dir, true);
            }
        }

        [Fact]
        public void EnsurePortrait_SingleFlightAndBridgeDegrade()
        {
            string dir = CreateTempDir();
            try
            {
                // 桥不可用：不入队、不计在飞，返回后允许重试
                var offline = new DollPortraitBakeService(dir, delegate { return false; });
                var tuple = new System.Collections.Generic.Dictionary<string, string> { { "gender", "女" } };
                string key = DollPortraitKey.Compute(tuple);
                offline.EnsurePortrait(tuple, key);
                Assert.Equal(0, offline.PendingCount);

                // 同键单飞：重复 EnsurePortrait 不重复发请求
                int posts = 0;
                var service = new DollPortraitBakeService(dir, delegate { posts++; return true; });
                service.EnsurePortrait(tuple, key);
                service.EnsurePortrait(tuple, key);
                Assert.Equal(1, posts);
                Assert.Equal(1, service.PendingCount);
                service.Dispose();
            }
            finally
            {
                Directory.Delete(dir, true);
            }
        }

        [Fact]
        public void EnsurePortrait_ExistingFileShortCircuits()
        {
            string dir = CreateTempDir();
            try
            {
                var tuple = new System.Collections.Generic.Dictionary<string, string> { { "gender", "女" } };
                string hex = DollPortraitKey.ComputeHex(tuple);
                File.WriteAllBytes(Path.Combine(dir, hex + ".png"), CreatePng(5));

                int posts = 0;
                var service = new DollPortraitBakeService(dir, delegate { posts++; return true; });
                service.EnsurePortrait(tuple, DollPortraitKey.Compute(tuple));
                Assert.Equal(0, posts);
                Assert.Equal(0, service.PendingCount);
            }
            finally
            {
                Directory.Delete(dir, true);
            }
        }

        [Fact]
        public void EnsurePortrait_WrongSizedLegacyCacheRequestsRebake()
        {
            string dir = CreateTempDir();
            try
            {
                var tuple = new System.Collections.Generic.Dictionary<string, string> { { "gender", "female" } };
                string hex = DollPortraitKey.ComputeHex(tuple);
                File.WriteAllBytes(Path.Combine(dir, hex + ".png"), CreatePng(5, 384));

                int posts = 0;
                var service = new DollPortraitBakeService(dir, delegate { posts++; return true; });
                service.EnsurePortrait(tuple, DollPortraitKey.Compute(tuple));
                Assert.Equal(1, posts);
                Assert.Equal(1, service.PendingCount);
            }
            finally
            {
                Directory.Delete(dir, true);
            }
        }
    }
}
