using System;
using System.IO;
using Newtonsoft.Json;
using Newtonsoft.Json.Linq;
using CF7Launcher.Guardian;
using CF7Launcher.Guardian.Hud.Loot;

namespace CF7Launcher.Tasks
{
    /// <summary>
    /// doll_bake_result sync handler：常驻 WebView2 overlay 的 doll-bake.js 用 dressup
    /// 渲染器把击杀斗士的外观元组烘焙成 256×256 PNG，经 Web→C# task 桥回传
    /// {task:"doll_bake_result", payload:{key, pngBase64, requestId?, error?}}，
    /// 本 task 校验后原子写入运行时缓存目录 launcher/data/doll-portraits/&lt;hex&gt;.png。
    ///
    /// 与 IconBakeTask 的差异：无 begin/chunk/end 分块（web 单次 toDataURL 回传）、
    /// 无 manifest（文件存在即注册，LootIconCatalog 第四源按 纸娃娃-&lt;hex&gt; ref 直读）。
    /// key 必须匹配 ^纸娃娃-[0-9a-f]{8}$（路径穿越防护；前缀只进 name/日志，文件名只用 hex）。
    /// 已存在且字节一致跳过；任何失败回 error JSON 并记日志，绝不抛出影响其它 task。
    /// </summary>
    public class DollBakeTask
    {
        // 防御上限：256×256 PNG 的 base64 远超此值即视为异常载荷
        private const int MaxPngBase64Length = 4 * 1024 * 1024;
        private static readonly byte[] PngMagic = { 0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A };

        private readonly string _dir;
        private readonly DollPortraitBakeService _bakeService; // 可为 null（测试/降级）

        public DollBakeTask(string projectRoot, DollPortraitBakeService bakeService = null)
        {
            if (string.IsNullOrEmpty(projectRoot)) throw new ArgumentException("projectRoot required", nameof(projectRoot));
            _dir = Path.Combine(projectRoot, "launcher", "data", "doll-portraits");
            _bakeService = bakeService;
        }

        private DollBakeTask(string dollPortraitsDir, DollPortraitBakeService bakeService, bool directDir)
        {
            _dir = dollPortraitsDir;
            _bakeService = bakeService;
        }

        /// <summary>测试钩子：直接注入目录。</summary>
        internal static DollBakeTask ForDirectory(string dollPortraitsDir, DollPortraitBakeService bakeService)
        {
            if (string.IsNullOrEmpty(dollPortraitsDir)) throw new ArgumentException("dir required", nameof(dollPortraitsDir));
            return new DollBakeTask(dollPortraitsDir, bakeService, true);
        }

        public string Handle(JObject message)
        {
            string key = null;
            bool ok = false;
            try
            {
                JObject payload = message.Value<JObject>("payload");
                if (payload == null)
                    return BuildError("missing payload");

                key = payload.Value<string>("key");
                string hex;
                if (!DollBakeTaskKey.TryExtractHex(key, out hex))
                    return BuildError("invalid key: " + (key ?? "<null>"));

                string requestId = payload.Value<string>("requestId");
                string webError = payload.Value<string>("error");
                if (!string.IsNullOrEmpty(webError))
                {
                    // web 侧显式失败：等价于超时丢弃（记日志），由在飞清理允许后续重试
                    LogManager.Log("[DollBakeTask] web bake failed for " + key
                        + (requestId != null ? " req=" + requestId : "") + ": " + webError);
                    return BuildError("web bake failed: " + webError);
                }

                string b64 = payload.Value<string>("pngBase64");
                if (string.IsNullOrEmpty(b64) || b64.Length > MaxPngBase64Length)
                    return BuildError("invalid pngBase64 (len=" + (b64 == null ? -1 : b64.Length) + ")");

                byte[] png;
                try { png = Convert.FromBase64String(b64); }
                catch (FormatException) { return BuildError("pngBase64 is not valid base64"); }
                if (png.Length < PngMagic.Length || !HasPngMagic(png))
                    return BuildError("payload is not a PNG");

                if (!Directory.Exists(_dir))
                    Directory.CreateDirectory(_dir);

                string filePath = Path.Combine(_dir, hex + ".png");
                string action;
                if (File.Exists(filePath))
                {
                    byte[] existing = File.ReadAllBytes(filePath);
                    if (BytesEqual(existing, png))
                    {
                        action = "unchanged";
                    }
                    else
                    {
                        AtomicWrite(filePath, png);
                        action = "updated";
                    }
                }
                else
                {
                    AtomicWrite(filePath, png);
                    action = "created";
                }

                LogManager.Log("[DollBakeTask] " + action + ": " + key
                    + (requestId != null ? " req=" + requestId : "")
                    + " bytes=" + png.Length);

                JObject resp = new JObject();
                resp["success"] = true;
                resp["task"] = "doll_bake_result";
                resp["action"] = action;
                ok = true;
                return resp.ToString(Formatting.None);
            }
            catch (Exception ex)
            {
                LogManager.Log("[DollBakeTask] Exception: " + ex);
                return BuildError("exception: " + ex.Message);
            }
            finally
            {
                // 任何终态都清除在飞标记（键合法时），允许下一次击杀重试；
                // 成功（含 unchanged）时经 PortraitReady 驱动占位卡片原地升级
                if (_bakeService != null && key != null)
                {
                    string hexIgnored;
                    if (DollBakeTaskKey.TryExtractHex(key, out hexIgnored))
                    {
                        try { _bakeService.NotifyResult(key, ok); } catch { }
                    }
                }
            }
        }

        private static bool HasPngMagic(byte[] bytes)
        {
            for (int i = 0; i < PngMagic.Length; i++)
                if (bytes[i] != PngMagic[i]) return false;
            return true;
        }

        private static bool BytesEqual(byte[] a, byte[] b)
        {
            if (a == null || b == null || a.Length != b.Length) return false;
            for (int i = 0; i < a.Length; i++)
                if (a[i] != b[i]) return false;
            return true;
        }

        /// <summary>tmp 文件 + Move 覆盖的原子写（同目录卷内 Rename 语义）。</summary>
        private static void AtomicWrite(string filePath, byte[] bytes)
        {
            string tmp = filePath + ".tmp-" + Guid.NewGuid().ToString("N");
            File.WriteAllBytes(tmp, bytes);
            try
            {
                File.Move(tmp, filePath, true);
            }
            catch
            {
                try { if (File.Exists(tmp)) File.Delete(tmp); } catch { }
                throw;
            }
        }

        private static string BuildError(string error)
        {
            JObject obj = new JObject();
            obj["success"] = false;
            obj["task"] = "doll_bake_result";
            obj["error"] = error;
            return obj.ToString(Formatting.None);
        }
    }
}
