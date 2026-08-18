using System;
using System.Collections.Generic;
using System.IO;
using System.Threading;
using Newtonsoft.Json.Linq;
using CF7Launcher.Guardian;

namespace CF7Launcher.Guardian.Hud.Loot
{
    /// <summary>
    /// LootFeedTask 触发纸娃娃烘焙的注入点（单测用记录假实现）。
    /// </summary>
    public interface IDollBakeSink
    {
        void EnsurePortrait(IReadOnlyDictionary<string, string> tuple, string key);
    }

    /// <summary>
    /// 运行时纸娃娃胸像烘焙调度：loot feed 击杀事件到达时，若运行时缓存目录
    /// （launcher/data/doll-portraits/&lt;hex&gt;.png）尚无该键落盘，则经 C#→WebView2 桥
    /// （WebOverlayForm.TryPostToWeb，type="dollBake"）请求常驻 overlay 的 doll-bake.js
    /// 用 dressup 渲染器烘焙 256×256 胸像；web 侧完成后经 task 桥回传 doll_bake_result，
    /// 由 DollBakeTask 原子落盘并回调 NotifyResult 清除在飞状态。
    ///
    /// 降级语义（绝不阻断游戏）：文件已存在直接返回；同键全局单飞去重；在飞上限 64，
    /// 满则丢弃记日志；桥不可用（WebView2 未就绪）不入队、下次事件自然重试；
    /// 请求 10s 无结果超时丢弃记日志，后续事件可重试。
    /// </summary>
    public sealed class DollPortraitBakeService : IDollBakeSink, IDisposable
    {
        internal const int MaxInFlight = 64;
        internal static readonly TimeSpan DefaultRequestTimeout = TimeSpan.FromSeconds(10);

        private sealed class InFlight
        {
            internal string RequestId;
            internal Timer Timer;
        }

        private readonly string _dir;
        private readonly Func<string, bool> _postToWeb;
        private readonly TimeSpan _requestTimeout;
        private readonly object _gate = new object();
        private readonly Dictionary<string, InFlight> _inFlight =
            new Dictionary<string, InFlight>(StringComparer.Ordinal);
        private long _seq;
        private bool _disposed;

        /// <param name="dollPortraitsDir">运行时缓存目录（Program.cs 用 projectRoot 注入）。</param>
        /// <param name="postToWeb">C#→Web 桥（WebOverlayForm.TryPostToWeb）；null 视为桥永久不可用。</param>
        public DollPortraitBakeService(string dollPortraitsDir, Func<string, bool> postToWeb)
            : this(dollPortraitsDir, postToWeb, DefaultRequestTimeout)
        {
        }

        /// <summary>测试钩子：可注入短超时。</summary>
        internal DollPortraitBakeService(string dollPortraitsDir, Func<string, bool> postToWeb,
            TimeSpan requestTimeout)
        {
            if (string.IsNullOrEmpty(dollPortraitsDir)) throw new ArgumentException("dir required", nameof(dollPortraitsDir));
            _dir = dollPortraitsDir;
            _postToWeb = postToWeb;
            _requestTimeout = requestTimeout;
        }

        /// <summary>在飞请求数（测试/诊断钩子）。</summary>
        internal int PendingCount
        {
            get { lock (_gate) return _inFlight.Count; }
        }

        /// <summary>
        /// 确保 &lt;hex&gt;.png 落盘：已有文件或同键在飞则直接返回；
        /// 否则单飞入队并向 web 侧发烘焙请求。任何失败静默降级（记日志），不抛。
        /// </summary>
        public void EnsurePortrait(IReadOnlyDictionary<string, string> tuple, string key)
        {
            if (tuple == null || string.IsNullOrEmpty(key)) return;
            string hex;
            if (!DollBakeTaskKey.TryExtractHex(key, out hex)) return;

            try
            {
                string path = Path.Combine(_dir, hex + ".png");
                if (File.Exists(path)) return;
            }
            catch { /* 路径不可达时仍走烘焙流程，落盘由 DollBakeTask 兜底 */ }

            InFlight entry = new InFlight();
            lock (_gate)
            {
                if (_disposed) return;
                if (_inFlight.ContainsKey(key)) return; // 同键单飞
                if (_inFlight.Count >= MaxInFlight)
                {
                    LogManager.Log("[DollBake] in-flight cap reached (" + MaxInFlight + "), dropped: " + key);
                    return;
                }
                entry.RequestId = "doll_" + (++_seq).ToString() + "_" + Guid.NewGuid().ToString("N");
                _inFlight.Add(key, entry);
            }

            JObject msg = new JObject();
            msg["type"] = "dollBake";
            msg["requestId"] = entry.RequestId;
            msg["key"] = key;
            JObject tupleJson = new JObject();
            string[] fields = DollPortraitKey.Fields;
            for (int i = 0; i < fields.Length; i++)
            {
                string value;
                tupleJson[fields[i]] = tuple.TryGetValue(fields[i], out value) && value != null ? value : string.Empty;
            }
            msg["tuple"] = tupleJson;

            bool posted = false;
            try { posted = _postToWeb != null && _postToWeb(msg.ToString(Newtonsoft.Json.Formatting.None)); }
            catch (Exception ex) { LogManager.Log("[DollBake] post failed: " + ex.Message); }

            if (!posted)
            {
                // WebView2 未就绪：不入队，静默降级；下一次击杀事件自然重试
                RemoveInFlight(key, null);
                LogManager.Log("[DollBake] bridge unavailable, skipped: " + key);
                return;
            }

            entry.Timer = new Timer(OnTimeout, key, _requestTimeout, Timeout.InfiniteTimeSpan);
        }

        /// <summary>
        /// 烘焙成功（文件已落盘）回调：由 DollBakeTask 在原子写成功后触发。
        /// Program.cs 将其接线到 LootFeedWidget.NotifyIconReady，驱动占位卡片原地升级。
        /// </summary>
        public Action<string> PortraitReady;

        /// <summary>DollBakeTask 终态回调（清除在飞允许后续重试；成功时触发 PortraitReady）。</summary>
        internal void NotifyResult(string key, bool success)
        {
            if (string.IsNullOrEmpty(key)) return;
            RemoveInFlight(key, null);
            if (success)
            {
                Action<string> h = PortraitReady;
                if (h != null)
                {
                    try { h(key); } catch { }
                }
            }
        }

        private void OnTimeout(object state)
        {
            string key = state as string;
            if (key == null) return;
            if (RemoveInFlight(key, null))
                LogManager.Log("[DollBake] request timeout (" + _requestTimeout.TotalSeconds + "s), dropped: " + key);
        }

        private bool RemoveInFlight(string key, InFlight expected)
        {
            InFlight entry = null;
            lock (_gate)
            {
                if (!_inFlight.TryGetValue(key, out entry)) return false;
                if (expected != null && !ReferenceEquals(entry, expected)) return false;
                _inFlight.Remove(key);
            }
            if (entry != null && entry.Timer != null)
            {
                try { entry.Timer.Dispose(); } catch { }
            }
            return true;
        }

        public void Dispose()
        {
            List<InFlight> entries = new List<InFlight>();
            lock (_gate)
            {
                if (_disposed) return;
                _disposed = true;
                foreach (KeyValuePair<string, InFlight> kvp in _inFlight) entries.Add(kvp.Value);
                _inFlight.Clear();
            }
            for (int i = 0; i < entries.Count; i++)
            {
                if (entries[i].Timer != null)
                {
                    try { entries[i].Timer.Dispose(); } catch { }
                }
            }
        }
    }

    /// <summary>纸娃娃键（"纸娃娃-&lt;8位小写hex&gt;"）的共享校验（DollBakeTask 与服务共用）。</summary>
    internal static class DollBakeTaskKey
    {
        internal static bool TryExtractHex(string key, out string hex)
        {
            hex = null;
            if (string.IsNullOrEmpty(key)) return false;
            if (!key.StartsWith(DollPortraitKey.Prefix, StringComparison.Ordinal)) return false;
            string candidate = key.Substring(DollPortraitKey.Prefix.Length);
            if (candidate.Length != 8) return false;
            for (int i = 0; i < 8; i++)
            {
                char c = candidate[i];
                bool ok = (c >= '0' && c <= '9') || (c >= 'a' && c <= 'f');
                if (!ok) return false;
            }
            hex = candidate;
            return true;
        }
    }
}
