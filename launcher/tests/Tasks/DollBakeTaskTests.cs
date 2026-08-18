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
    /// DollBakeTask：web 侧 doll-bake.js 烘焙回传 {key, pngBase64} → 校验 +
    /// 原子写 launcher/data/doll-portraits/&lt;hex&gt;.png。覆盖落盘正确性、
    /// 同字节跳过、坏 key（路径穿越防护）、非 PNG 拒绝与 web 显式失败。
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

        private static byte[] CreatePng(byte seed)
        {
            using (Bitmap bmp = new Bitmap(8, 8, PixelFormat.Format32bppArgb))
            {
                for (int y = 0; y < 8; y++)
                    for (int x = 0; x < 8; x++)
                        bmp.SetPixel(x, y, Color.FromArgb(255, (byte)(seed + x), (byte)(seed + y), 40));
                using (MemoryStream ms = new MemoryStream())
                {
                    bmp.Save(ms, ImageFormat.Png);
                    return ms.ToArray();
                }
            }
        }

        private static JObject Message(string key, string pngBase64, string requestId = null, string error = null)
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
        public void Handle_ResultClearsBakeServiceInFlight()
        {
            string dir = CreateTempDir();
            try
            {
                int posts = 0;
                var service = new DollPortraitBakeService(dir, delegate { posts++; return true; });
                var task = DollBakeTask.ForDirectory(dir, service);
                var tuple = new System.Collections.Generic.Dictionary<string, string>
                {
                    { "face", "女变装-基本脸型" }, { "gender", "女" }
                };
                string key = DollPortraitKey.Compute(tuple);

                service.EnsurePortrait(tuple, key);
                Assert.Equal(1, posts);
                Assert.Equal(1, service.PendingCount);

                task.Handle(Message(key, Convert.ToBase64String(CreatePng(7))));
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
    }
}
