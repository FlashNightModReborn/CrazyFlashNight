using System;
using System.Collections.Generic;
using System.Drawing;
using System.Drawing.Imaging;
using System.IO;
using System.Linq;
using System.Reflection;
using System.Security.Cryptography;
using System.Text;
using System.Threading;
using CF7Launcher.Guardian;
using CF7Launcher.Guardian.Dialogue;
using CF7Launcher.Guardian.Hud;
using CF7Launcher.Guardian.Hud.Dialogue;
using Newtonsoft.Json.Linq;
using Xunit;

namespace CF7Launcher.Tests.Guardian
{
    /// <summary>
    /// DialoguePortraitService 磁盘缓存层定向回归。
    ///
    /// 覆盖合同关键点：
    /// - 同 root 跨 service/cache 实例：先 Web 合成落盘，再新实例同 key 直读磁盘，
    ///   postToWeb 零调用（重启/内存逐出后不再等 Web 重烘焙）。
    /// - 外观/表情/渲染资产版本任一变化 → key 变化 → 磁盘 miss → 回退 Web 路径。
    /// - 损坏缓存（垃圾字节/非 768 PNG）一律按 miss 处理，不吐坏图。
    /// - 边界回收只动 64hex.png；非缓存文件（txt、非 hex png）原样保留。
    /// - DollKey 静态签名与 LoadPortrait 双回调签名不变。
    /// - HandleResult 受理即返回：结构拒绝仍同步 false，解码/回调/落盘改在
    ///   后台线程完成；内存 LRU 64MB 下 >8 张 ~3MB 位图同时存活。
    /// </summary>
    public sealed class NativeDialogueCacheTests
    {
        private static readonly string[] RendererFiles =
        {
            "modules/asset-timeline.js",
            "modules/dressup-doll-renderer.js",
            "modules/dialogue/live-portrait.js",
            "modules/dialogue/live-portrait-bake.js"
        };

        /// <summary>最小 root：dressup manifest + 4 个渲染器文件 + 空立绘 manifest。</summary>
        private static string MakeRoot()
        {
            string root = Path.Combine(Path.GetTempPath(),
                "ndcache-" + Guid.NewGuid().ToString("N"));
            Directory.CreateDirectory(Path.Combine(root, "launcher", "web", "assets", "dialogue-portraits"));
            File.WriteAllText(Path.Combine(root, "launcher", "web", "assets", "dialogue-portraits", "manifest.json"), "{}");
            Directory.CreateDirectory(Path.Combine(root, "launcher", "web", "assets", "dressup"));
            File.WriteAllText(Path.Combine(root, "launcher", "web", "assets", "dressup", "manifest.json"), "{}");
            foreach (string rel in RendererFiles)
            {
                string p = Path.Combine(root, "launcher", "web", rel.Replace('/', Path.DirectorySeparatorChar));
                Directory.CreateDirectory(Path.GetDirectoryName(p));
                File.WriteAllText(p, "// renderer " + rel);
            }
            return root;
        }

        private static NativeDialogueFrame DollFrame(string expression = "普通")
        {
            return new NativeDialogueFrame
            {
                RequestId = "nd:1", SceneId = "sceneA", Revision = 1,
                Name = "主角", Text = "……", PortraitKey = "hero",
                Expression = expression, IsDoll = true, ImageAction = "keep"
            };
        }

        private static JObject Appearance(string body = "钛合金装甲", string face = "玩家脸甲")
        {
            return new JObject
            {
                ["gender"] = "男", ["face"] = face, ["hair"] = "寸头",
                ["head"] = "战术目镜", ["body"] = body, ["leg"] = "钛合金护腿",
                ["hand"] = "战术手套", ["foot"] = "军靴", ["neck"] = ""
            };
        }

        private static byte[] Png768()
        {
            using (var bmp = new Bitmap(768, 768, PixelFormat.Format32bppPArgb))
            using (var ms = new MemoryStream())
            {
                using (var graphics = Graphics.FromImage(bmp)) graphics.Clear(Color.Red);
                bmp.Save(ms, ImageFormat.Png);
                return ms.ToArray();
            }
        }

        private static bool WaitFor(Func<bool> cond, int ms = 8000)
        {
            var deadline = DateTime.UtcNow.AddMilliseconds(ms);
            while (DateTime.UtcNow < deadline)
            {
                if (cond()) return true;
                Thread.Sleep(25);
            }
            return cond();
        }

        private static string DiskDir(string root)
        {
            return Path.Combine(root, "launcher", "data", "dialogue-portraits");
        }

        /// <summary>驱动一次 Web 合成并让磁盘落盘；返回 posted 消息（含 key/requestId）。</summary>
        private static JObject BakeOnce(string root, DialoguePortraitService svc,
            List<string> posted, JObject appearance, string expression)
        {
            var done = new ManualResetEventSlim();
            svc.LoadPortrait(DollFrame(expression), appearance, _ => done.Set());
            Assert.True(WaitFor(() => posted.Count > 0), "expected a web bake request");
            JObject msg = JObject.Parse(posted[0]);
            string result = svc.HandleResult(new JObject
            {
                ["payload"] = new JObject
                {
                    ["key"] = msg["key"], ["requestId"] = msg["requestId"],
                    ["pngBase64"] = Convert.ToBase64String(Png768())
                }
            });
            Assert.Equal("{\"success\":true}", result);
            Assert.True(done.Wait(5000), "bake callback not delivered");
            string key = msg.Value<string>("key");
            string path = Path.Combine(DiskDir(root), key + ".png");
            Assert.True(WaitFor(() => File.Exists(path)), "disk file not written");
            return msg;
        }

        [Fact]
        public void DiskHit_CrossInstance_NoWebCall()
        {
            string root = MakeRoot();
            try
            {
                var posted = new List<string>();
                using (var a = new DialoguePortraitService(root,
                    m => { lock (posted) posted.Add(m); return true; }))
                {
                    BakeOnce(root, a, posted, Appearance(), "普通");
                }
                // 新 service + 新 disk cache 实例：同 key 必须磁盘命中、零 Web 请求
                posted.Clear();
                using (var b = new DialoguePortraitService(root,
                    m => { lock (posted) posted.Add(m); return true; }))
                {
                    var done = new ManualResetEventSlim();
                    Bitmap got = null;
                    b.LoadPortrait(DollFrame(), Appearance(), bmp => { got = bmp; done.Set(); });
                    Assert.True(done.Wait(5000), "disk-hit callback not delivered");
                    Assert.NotNull(got);
                    Assert.Equal(768, got.Width);
                    got.Dispose();
                    Thread.Sleep(200); // 给潜在误发一个窗口
                    Assert.Empty(posted);
                }
            }
            finally { try { Directory.Delete(root, true); } catch { } }
        }

        [Fact]
        public void MissOnDifferentAppearanceExpressionAndAssetVersion()
        {
            string root = MakeRoot();
            try
            {
                var posted = new List<string>();
                using (var a = new DialoguePortraitService(root,
                    m => { lock (posted) posted.Add(m); return true; }))
                {
                    BakeOnce(root, a, posted, Appearance(), "普通");
                }
                posted.Clear();
                using (var b = new DialoguePortraitService(root,
                    m => { lock (posted) posted.Add(m); return true; }))
                {
                    // 不同外观 → 不同 key → 发 Web
                    b.LoadPortrait(DollFrame(), Appearance(body: "布甲"), _ => { });
                    Assert.True(WaitFor(() => posted.Count > 0), "changed appearance should miss");
                    // 不同表情 → 不同 key → 发 Web
                    posted.Clear();
                    b.LoadPortrait(DollFrame("微笑"), Appearance(), _ => { });
                    Assert.True(WaitFor(() => posted.Count > 0), "changed expression should miss");
                }
                // 渲染器源码变化 → assetVersion 变化 → 同外观也 miss
                File.AppendAllText(Path.Combine(root, "launcher", "web", "modules",
                    "dialogue", "live-portrait.js"), "// v2");
                posted.Clear();
                using (var c = new DialoguePortraitService(root,
                    m => { lock (posted) posted.Add(m); return true; }))
                {
                    c.LoadPortrait(DollFrame(), Appearance(), _ => { });
                    Assert.True(WaitFor(() => posted.Count > 0),
                        "renderer change must invalidate disk key");
                }
            }
            finally { try { Directory.Delete(root, true); } catch { } }
        }

        [Fact]
        public void CorruptCache_IsMiss_NotBadBitmap()
        {
            string root = MakeRoot();
            try
            {
                var posted = new List<string>();
                string key;
                using (var a = new DialoguePortraitService(root,
                    m => { lock (posted) posted.Add(m); return true; }))
                {
                    key = BakeOnce(root, a, posted, Appearance(), "普通").Value<string>("key");
                }
                // 覆写为垃圾字节
                File.WriteAllBytes(Path.Combine(DiskDir(root), key + ".png"),
                    new byte[] { 1, 2, 3, 4 });
                posted.Clear();
                using (var b = new DialoguePortraitService(root,
                    m => { lock (posted) posted.Add(m); return true; }))
                {
                    var done = new ManualResetEventSlim();
                    b.LoadPortrait(DollFrame(), Appearance(), _ => done.Set());
                    Assert.True(WaitFor(() => posted.Count > 0), "corrupt cache should post to web");
                    JObject msg = JObject.Parse(posted[0]);
                    Assert.Equal("{\"success\":true}", b.HandleResult(new JObject
                    {
                        ["payload"] = new JObject
                        {
                            ["key"] = msg["key"], ["requestId"] = msg["requestId"],
                            ["pngBase64"] = Convert.ToBase64String(Png768())
                        }
                    }));
                    Assert.True(done.Wait(5000));
                }
            }
            finally { try { Directory.Delete(root, true); } catch { } }
        }

        [Fact]
        public void Bounds_Enforced_OnlyCacheFilesTouched()
        {
            string root = MakeRoot();
            try
            {
                var cache = new DialoguePortraitDiskCache(root);
                byte[] png = Png768();
                Directory.CreateDirectory(cache.DirectoryPath);
                // 非缓存形态文件：必须原样保留
                File.WriteAllText(Path.Combine(cache.DirectoryPath, "note.txt"), "keep");
                File.WriteAllBytes(Path.Combine(cache.DirectoryPath, "deadbeef.png"), png);
                // 写 MaxFiles+5 个合法条目触发回收
                for (int i = 0; i < DialoguePortraitDiskCache.MaxFiles + 5; i++)
                {
                    string k = Convert.ToHexString(
                        SHA256.HashData(BitConverter.GetBytes(i))).ToLowerInvariant();
                    Assert.True(cache.Store(k, png, 768));
                    File.SetLastWriteTimeUtc(Path.Combine(cache.DirectoryPath, k + ".png"),
                        DateTime.UtcNow.AddSeconds(i - DialoguePortraitDiskCache.MaxFiles - 10));
                }
                var remaining = new DirectoryInfo(cache.DirectoryPath).EnumerateFiles("*.png")
                    .Where(f => DialoguePortraitDiskCache.IsValidKey(
                        Path.GetFileNameWithoutExtension(f.Name))).ToList();
                Assert.True(remaining.Count <= DialoguePortraitDiskCache.MaxFiles,
                    "cache file count over bound: " + remaining.Count);
                Assert.True(File.Exists(Path.Combine(cache.DirectoryPath, "note.txt")),
                    "non-cache txt must be preserved");
                Assert.True(File.Exists(Path.Combine(cache.DirectoryPath, "deadbeef.png")),
                    "non-64hex png must be preserved");
                // 尺寸不符的 PNG 拒绝落盘
                using (var small = new Bitmap(767, 767))
                using (var ms = new MemoryStream())
                {
                    small.Save(ms, ImageFormat.Png);
                    string k = new string('a', 64);
                    Assert.False(cache.Store(k, ms.ToArray(), 768), "non-768 png must be rejected");
                }
            }
            finally { try { Directory.Delete(root, true); } catch { } }
        }

        [Fact]
        public void HandleResult_SyncRejectPaths_StayFalse()
        {
            string root = MakeRoot();
            try
            {
                var posted = new List<string>();
                using (var svc = new DialoguePortraitService(root,
                    m => { lock (posted) posted.Add(m); return true; }))
                {
                    // key 无对应 pending → 同步 false
                    Assert.Equal("{\"success\":false}", svc.HandleResult(new JObject
                    {
                        ["payload"] = new JObject
                        {
                            ["key"] = "no-such-key", ["requestId"] = "x",
                            ["pngBase64"] = Convert.ToBase64String(Png768())
                        }
                    }));

                    // requestId 不匹配 → 同步 false，且 pending 不被消费：
                    // 改回正确 requestId 仍可受理并交付回调。
                    var done = new ManualResetEventSlim();
                    svc.LoadPortrait(DollFrame(), Appearance(), _ => done.Set());
                    Assert.True(WaitFor(() => posted.Count > 0), "expected a web bake request");
                    JObject msg = JObject.Parse(posted[0]);
                    Assert.Equal("{\"success\":false}", svc.HandleResult(new JObject
                    {
                        ["payload"] = new JObject
                        {
                            ["key"] = msg["key"], ["requestId"] = "wrong-request",
                            ["pngBase64"] = Convert.ToBase64String(Png768())
                        }
                    }));
                    Assert.False(done.Wait(300), "mismatched requestId must not deliver");
                    Assert.Equal("{\"success\":true}", svc.HandleResult(new JObject
                    {
                        ["payload"] = new JObject
                        {
                            ["key"] = msg["key"], ["requestId"] = msg["requestId"],
                            ["pngBase64"] = Convert.ToBase64String(Png768())
                        }
                    }));
                    Assert.True(done.Wait(5000), "accepted result should deliver callback");

                    // pngBase64 缺失 / 非字符串 / 超 8MB → 同步 false，不触发回调。
                    // 结构拒绝同样消耗 pending（与旧版一致），每轮用新表情造新 key。
                    string[] expressions = { "生气", "悲伤", "微笑" };
                    for (int i = 0; i < expressions.Length; i++)
                    {
                        posted.Clear();
                        var rejected = new ManualResetEventSlim();
                        svc.LoadPortrait(DollFrame(expressions[i]), Appearance(), _ => rejected.Set());
                        Assert.True(WaitFor(() => posted.Count > 0), "expected a web bake request");
                        JObject m = JObject.Parse(posted[0]);
                        var payload = new JObject
                        {
                            ["key"] = m["key"], ["requestId"] = m["requestId"]
                        };
                        if (i == 1) payload["pngBase64"] = 123;
                        if (i == 2) payload["pngBase64"] = new string('A', 8 * 1024 * 1024 + 1);
                        Assert.Equal("{\"success\":false}",
                            svc.HandleResult(new JObject { ["payload"] = payload }));
                        Assert.False(rejected.Wait(300), "rejected payload must not deliver");
                    }
                }
            }
            finally { try { Directory.Delete(root, true); } catch { } }
        }

        [Fact]
        public void HandleResult_Accepted_DeliversOnBackgroundThread()
        {
            string root = MakeRoot();
            try
            {
                var posted = new List<string>();
                using (var svc = new DialoguePortraitService(root,
                    m => { lock (posted) posted.Add(m); return true; }))
                {
                    var done = new ManualResetEventSlim();
                    Bitmap got = null;
                    svc.LoadPortrait(DollFrame(), Appearance(), bmp => { got = bmp; done.Set(); });
                    Assert.True(WaitFor(() => posted.Count > 0), "expected a web bake request");
                    JObject msg = JObject.Parse(posted[0]);
                    // 受理即返回；解码/交付在后台完成，回调不再同步发生。
                    Assert.Equal("{\"success\":true}", svc.HandleResult(new JObject
                    {
                        ["payload"] = new JObject
                        {
                            ["key"] = msg["key"], ["requestId"] = msg["requestId"],
                            ["pngBase64"] = Convert.ToBase64String(Png768())
                        }
                    }));
                    Assert.True(done.Wait(5000), "async delivery callback not fired");
                    Assert.NotNull(got);
                    Assert.Equal(768, got.Width);
                    got.Dispose();
                    string path = Path.Combine(DiskDir(root), msg.Value<string>("key") + ".png");
                    Assert.True(WaitFor(() => File.Exists(path)), "disk file not written");
                }
            }
            finally { try { Directory.Delete(root, true); } catch { } }
        }

        [Fact]
        public void HandleResult_UndecodablePayload_SkipsCallback()
        {
            string root = MakeRoot();
            try
            {
                var posted = new List<string>();
                using (var svc = new DialoguePortraitService(root,
                    m => { lock (posted) posted.Add(m); return true; }))
                {
                    var done = new ManualResetEventSlim();
                    svc.LoadPortrait(DollFrame(), Appearance(), _ => done.Set());
                    Assert.True(WaitFor(() => posted.Count > 0), "expected a web bake request");
                    JObject msg = JObject.Parse(posted[0]);
                    // 受理成功但 PNG 不可解码：只记日志，回调不触发（同旧版可观测结果）。
                    Assert.Equal("{\"success\":true}", svc.HandleResult(new JObject
                    {
                        ["payload"] = new JObject
                        {
                            ["key"] = msg["key"], ["requestId"] = msg["requestId"],
                            ["pngBase64"] = Convert.ToBase64String(new byte[] { 1, 2, 3, 4 })
                        }
                    }));
                    Assert.False(done.Wait(500), "undecodable payload must not deliver");
                }
            }
            finally { try { Directory.Delete(root, true); } catch { } }
        }

        [Fact]
        public void MemoryCache_64MB_KeepsMoreThanEightLargeBitmaps()
        {
            string root = MakeRoot();
            try
            {
                using (var svc = new DialoguePortraitService(root, _ => true))
                {
                    var put = typeof(DialoguePortraitService).GetMethod("PutCached",
                        BindingFlags.NonPublic | BindingFlags.Instance);
                    var get = typeof(DialoguePortraitService).GetMethod("GetCached",
                        BindingFlags.NonPublic | BindingFlags.Instance);
                    Assert.NotNull(put);
                    Assert.NotNull(get);
                    // 每张 1024×768×4 = 3MB；12 张共 36MB——超旧 24MB 上限、低于 64MB，
                    // 旧容量下最早条目必被逐出，新容量下应全部存活。
                    for (int i = 0; i < 12; i++)
                    {
                        using (var bmp = new Bitmap(1024, 768, PixelFormat.Format32bppPArgb))
                            put.Invoke(svc, new object[] { "k" + i, bmp });
                    }
                    for (int i = 0; i < 12; i++)
                    {
                        var hit = (Bitmap)get.Invoke(svc, new object[] { "k" + i });
                        Assert.NotNull(hit);
                        hit.Dispose();
                    }
                }
            }
            finally { try { Directory.Delete(root, true); } catch { } }
        }

        /// <summary>MakeRoot + 一张可解码的静态立绘（manifest entries + PNG）。</summary>
        private static string MakeRootWithStaticPortrait()
        {
            string root = MakeRoot();
            string dir = Path.Combine(root, "launcher", "web", "assets", "dialogue-portraits");
            File.WriteAllText(Path.Combine(dir, "manifest.json"), new JObject
            {
                ["entries"] = new JObject
                {
                    ["hero"] = new JObject
                    {
                        ["expressions"] = new JObject
                        {
                            ["普通"] = new JObject { ["uri"] = "hero-normal.png" }
                        }
                    }
                }
            }.ToString());
            File.WriteAllBytes(Path.Combine(dir, "hero-normal.png"), Png768());
            return root;
        }

        private static Bitmap PeekCached(DialoguePortraitService svc, string key)
        {
            var get = typeof(DialoguePortraitService).GetMethod("GetCached",
                BindingFlags.NonPublic | BindingFlags.Instance);
            return (Bitmap)get.Invoke(svc, new object[] { key });
        }

        [Fact]
        public void StaticPrefetchWarmsMemoryCacheForNextLoadPortrait()
        {
            string root = MakeRootWithStaticPortrait();
            try
            {
                using (var svc = new DialoguePortraitService(root, _ => true))
                {
                    svc.PrefetchPortrait("hero", "普通", null);
                    // 暖完的标志：同 key 进入内存 LRU（对齐 MemoryCache 测试的反射观察手法）。
                    Assert.True(WaitFor(() =>
                    {
                        Bitmap hit = PeekCached(svc, "static:hero:普通");
                        if (hit == null) return false;
                        hit.Dispose();
                        return true;
                    }), "static prefetch should warm memory cache");
                    // 预取后同 key LoadPortrait 内存命中并交付位图。
                    var done = new ManualResetEventSlim();
                    Bitmap got = null;
                    svc.LoadPortrait(new NativeDialogueFrame
                    {
                        RequestId = "nd:1", SceneId = "sceneA", Revision = 1,
                        Name = "n", Text = "t", PortraitKey = "hero",
                        Expression = "普通", IsDoll = false, ImageAction = "keep"
                    }, null, bmp => { got = bmp; done.Set(); });
                    Assert.True(done.Wait(5000), "memory-hit callback not delivered");
                    Assert.NotNull(got);
                    got.Dispose();
                }
            }
            finally { try { Directory.Delete(root, true); } catch { } }
        }

        [Fact]
        public void DollPrefetchYieldsWhenPendingSlotsOccupied()
        {
            string root = MakeRoot();
            try
            {
                var posted = new List<string>();
                using (var svc = new DialoguePortraitService(root,
                    m => { lock (posted) posted.Add(m); return true; }))
                {
                    // 占满 2 个 pending 槽（两笔在途 bake 永不回包）。
                    svc.LoadPortrait(DollFrame(), Appearance(), _ => { });
                    svc.LoadPortrait(DollFrame(), Appearance(face: "乙号脸"), _ => { });
                    Assert.True(WaitFor(() => { lock (posted) return posted.Count >= 2; }),
                        "expected two in-flight web bake requests");
                    // 预取让位：不同外观（不合并入既有 pending）也不得新增 Web 消息。
                    svc.PrefetchPortrait("hero", "普通",
                        DialoguePortraitService.NormalizeAppearance(Appearance(body: "布甲")));
                    Thread.Sleep(300);
                    lock (posted) Assert.Equal(2, posted.Count);
                }
            }
            finally { try { Directory.Delete(root, true); } catch { } }
        }

        [Fact]
        public void DollPrefetchFullChainWarmsMemoryCache()
        {
            string root = MakeRoot();
            try
            {
                var posted = new List<string>();
                using (var svc = new DialoguePortraitService(root,
                    m => { lock (posted) posted.Add(m); return true; }))
                {
                    svc.PrefetchPortrait("hero", "普通",
                        DialoguePortraitService.NormalizeAppearance(Appearance()));
                    Assert.True(WaitFor(() => { lock (posted) return posted.Count > 0; }),
                        "doll prefetch should post a web bake request");
                    JObject msg;
                    lock (posted) msg = JObject.Parse(posted[0]);
                    Assert.Equal("{\"success\":true}", svc.HandleResult(new JObject
                    {
                        ["payload"] = new JObject
                        {
                            ["key"] = msg["key"], ["requestId"] = msg["requestId"],
                            ["pngBase64"] = Convert.ToBase64String(Png768())
                        }
                    }));
                    string key = msg.Value<string>("key");
                    Assert.True(WaitFor(() =>
                    {
                        Bitmap hit = PeekCached(svc, key);
                        if (hit == null) return false;
                        hit.Dispose();
                        return true;
                    }), "baked prefetch should land in memory cache");
                    // 前景同 key 内存命中：回调交付位图，且不再发第二次 Web 请求。
                    var done = new ManualResetEventSlim();
                    Bitmap got = null;
                    svc.LoadPortrait(DollFrame(), Appearance(), bmp => { got = bmp; done.Set(); });
                    Assert.True(done.Wait(5000), "memory-hit callback not delivered");
                    Assert.NotNull(got);
                    Assert.Equal(768, got.Width);
                    got.Dispose();
                    lock (posted) Assert.Single(posted);
                }
            }
            finally { try { Directory.Delete(root, true); } catch { } }
        }
    }
}
