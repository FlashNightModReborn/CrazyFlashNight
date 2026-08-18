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
    /// {task:"doll_bake_result", payload:{key, pngBase64, requestId, error?}}。
    /// requestId 必须与当前 key 的在飞请求 exact 匹配；本 task 完整解码并确认 256×256
    /// 后才原子写入运行时缓存目录 launcher/data/doll-portraits/&lt;hex&gt;.png。
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
        private const int MaxRequestIdLength = 128;

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
            string requestId = null;
            bool ok = false;
            bool resultClaimed = false;
            try
            {
                JObject payload = message.Value<JObject>("payload");
                if (payload == null)
                    return BuildError("missing payload");

                key = payload.Value<string>("key");
                string hex;
                if (!DollBakeTaskKey.TryExtractHex(key, out hex))
                    return BuildError("invalid key: " + (key ?? "<null>"));

                requestId = payload.Value<string>("requestId");
                if (string.IsNullOrEmpty(requestId) || requestId.Length > MaxRequestIdLength)
                    return BuildError("invalid requestId");
                if (_bakeService != null)
                {
                    if (!_bakeService.TryBeginResult(key, requestId))
                        return BuildError("stale or unknown doll bake request");
                    resultClaimed = true;
                }

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
                string pngError = DollPortraitPngValidator.ValidateBytes(png);
                if (pngError != null)
                {
                    LogManager.Log("[DollBakeTask] rejected portrait for " + key
                        + " req=" + requestId + ": " + pngError);
                    return BuildError(pngError);
                }

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
                // 只有已通过 exact key+requestId 栅栏的终态才能清除对应在飞项；
                // stale/unsolicited 回包不得影响更新请求。成功时驱动占位卡片原地升级。
                if (_bakeService != null && resultClaimed)
                {
                    try { _bakeService.CompleteResult(key, requestId, ok); } catch { }
                }
            }
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
