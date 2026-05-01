using System;
using System.Collections.Generic;
using System.Text;
using Newtonsoft.Json.Linq;
using CF7Launcher.Tasks;
using CF7Launcher.Data;
using CF7Launcher.V8;
using CF7Launcher.Guardian;

namespace CF7Launcher.Bus
{
    /// <summary>
    /// Single source of truth：全部活跃 task 的注册与元数据。
    /// httpCallable 标记在此统一声明，HttpApiServer 通过 IsHttpCallable() 查询。
    ///
    /// Task 清单：
    ///   frame        快车道 F 前缀   AS2→C#  (XmlSocketServer 直分发，不经 MessageRouter)
    ///   hn_reset     快车道 R 前缀   AS2→C#  (同上)
    ///   toast        JSON sync      AS2→C#  httpCallable=true
    ///   gomoku_eval  JSON async     AS2↔C#  httpCallable=true
    ///   data_query   JSON async     AS2↔C#  httpCallable=true
    ///   audio        JSON sync      AS2→C#  httpCallable=true
    ///   sfx          快车道 S 前缀   AS2→C#  (XmlSocketServer 直分发，不经 MessageRouter)
    ///   console      JSON push      C#→AS2  (HttpApiServer /console 专用端点)
    ///   console_result  JSON event  AS2→C#  (内部事件，触发 OnConsoleResult)
    ///   icon_bake       JSON sync   AS2↔C#  (图标烘焙：begin/chunk/end/complete)
    ///   archive         JSON async  AS2↔C#  httpCallable=true  (存档shadow备份/读取)
    ///   panel_request   JSON sync   AS2→C#  (旧 Flash UI 请求 WebView 打开面板: map / stage-select)
    ///   stage_select_response JSON async AS2↔C# (选关 Web panel 测试入口)
    /// </summary>
    public static class TaskRegistry
    {
        private static readonly HashSet<string> _httpCallable = new HashSet<string>();

        /// <summary>
        /// 检查 task 是否允许经 HTTP /task 端点调用。
        /// 唯一真相源：由 ToStatusJson 中的 AppendTask 声明自动收集。
        /// </summary>
        public static bool IsHttpCallable(string taskName)
        {
            return _httpCallable.Contains(taskName);
        }

        /// <summary>
        /// 向 MessageRouter 注册所有 JSON 路由的 task（快车道 task 不在此注册）。
        /// </summary>
        public static void RegisterAll(
            MessageRouter router,
            GomokuTask gomoku,
            ToastTask toast,
            FrameTask frame,
            DataQueryTask dataQuery,
            V8Runtime v8,
            HitNumberOverlay hnOverlay,
            AudioTask audio,
            IconBakeTask iconBake,
            ShopTask shopTask,
            MapTask mapTask,
            StageSelectTask stageSelectTask,
            ArchiveTask archiveTask,
            BenchTask benchTask,
            WebOverlayForm webOverlay)
        {
            // JSON 路由 task（经 MessageRouter 分发）
            router.RegisterAsync("gomoku_eval", gomoku.HandleAsync);
            router.RegisterAsync("data_query", dataQuery.HandleAsync);
            router.RegisterSync("toast", toast.Handle);
            router.RegisterSync("audio", audio.Handle);
            router.RegisterSync("icon_bake", iconBake.Handle);
            if (benchTask != null)
            {
                router.RegisterSync("bench_sync", benchTask.HandleSync);
                router.RegisterAsync("bench_async", benchTask.HandleAsync);
                router.RegisterSync("bench_push", benchTask.HandlePush);
            }

            // 商城面板回包路由
            if (shopTask != null)
                router.RegisterAsync("shop_response", shopTask.HandleFlashResponse);

            // 地图面板回包路由
            if (mapTask != null)
                router.RegisterAsync("map_response", mapTask.HandleFlashResponse);

            // 选关面板回包路由
            if (stageSelectTask != null)
                router.RegisterAsync("stage_select_response", stageSelectTask.HandleFlashResponse);

            // AS2 → C# 面板打开请求 (旧 Flash 地图界面按钮 / openTaskMap 命令接入 WebView)
            if (webOverlay != null)
            {
                router.RegisterSync("cursor_control", webOverlay.HandleCursorControl);

                router.RegisterSync("panel_request", delegate(JObject msg)
                {
                    string panel = msg.Value<string>("panel") ?? "";
                    string source = msg.Value<string>("source") ?? "as2_request";
                    string pageId = msg.Value<string>("pageId") ?? "";
                    string frameLabel = msg.Value<string>("frameLabel") ?? "";
                    webOverlay.RequestOpenPanel(panel, source, pageId, frameLabel);
                    return null;
                });
            }

            // 存档 shadow 备份
            if (archiveTask != null)
                router.RegisterAsync("archive", archiveTask.HandleAsync);

            // C4: AS2 兜底 fffd 扫描结果上报 (loadAll 末尾扫一次).
            //   载荷: { slot, fffdCount, keyHits, sampled, elapsedMs, paths }.
            //   仅记日志, 不阻断游戏 (fire-and-forget).
            router.RegisterSync("save_corrupt_late", delegate(JObject msg)
            {
                try
                {
                    string slot = msg.Value<string>("slot") ?? "?";
                    int fffd = msg.Value<int?>("fffdCount") ?? 0;
                    int keys = msg.Value<int?>("keyHits") ?? 0;
                    bool sampled = msg.Value<bool?>("sampled") ?? false;
                    int elapsed = msg.Value<int?>("elapsedMs") ?? -1;
                    JArray paths = msg.Value<JArray>("paths");
                    string pathsStr = (paths != null && paths.Count > 0)
                        ? string.Join(", ", paths.ToObject<string[]>())
                        : "(none)";
                    LogManager.Log("[SaveCorruptLate] slot=" + slot
                        + " fffd=" + fffd + " keyHits=" + keys
                        + " sampled=" + sampled + " elapsedMs=" + elapsed
                        + " paths=[" + pathsStr + "]");
                }
                catch (Exception ex)
                {
                    LogManager.Log("[SaveCorruptLate] handler exception: " + ex.Message);
                }
                return null;
            });

            // JSON 回退路径：frame/hn_reset 的 JSON 格式兼容入口
            // 正常流量走快车道（XmlSocketServer 前缀检测），此处仅作防御性保留
            router.RegisterSync("frame", frame.Handle);
            router.RegisterSync("hn_reset", delegate(JObject msg)
            {
                v8.Reset();
                hnOverlay.NotifyReset();
                return null;
            });

            // console / console_result 不在此注册：
            //   console_result 由 MessageRouter 内部特殊处理（OnConsoleResult 事件）
            //   console 是 HttpApiServer /console 端点主动推送到 AS2

            // 初始化 httpCallable 集合（与 ToStatusJson 元数据同步）
            BuildTaskMetadata();
        }

        /// <summary>
        /// 生成 /status 端点的 JSON 响应。
        /// </summary>
        public static string ToStatusJson(bool socketConnected, int httpPort, int socketPort)
        {
            StringBuilder sb = new StringBuilder(512);
            sb.Append("{\"ok\":true,\"socketConnected\":");
            sb.Append(socketConnected ? "true" : "false");
            sb.Append(",\"httpPort\":");
            sb.Append(httpPort);
            sb.Append(",\"socketPort\":");
            sb.Append(socketPort);
            sb.Append(",\"tasks\":[");

            BuildTaskList(sb);

            sb.Append("]}");
            return sb.ToString();
        }

        /// <summary>
        /// 全量 task 清单（含元数据）。httpCallable 标记在此声明，同时驱动
        /// _httpCallable 集合和 /status JSON 输出，消除双写不一致风险。
        /// </summary>
        private static void BuildTaskList(StringBuilder sb)
        {
            bool first = true;
            first = AppendTask(sb, "frame",          "fast_lane", "AS2->C#", false, first);
            first = AppendTask(sb, "hn_reset",       "fast_lane", "AS2->C#", false, first);
            first = AppendTask(sb, "toast",          "json_sync", "AS2->C#", true,  first);
            first = AppendTask(sb, "gomoku_eval",    "json_async","AS2<->C#",true,  first);
            first = AppendTask(sb, "data_query",     "json_async","AS2<->C#",true,  first);
            first = AppendTask(sb, "audio",          "json_sync", "AS2->C#", true,  first);
            first = AppendTask(sb, "sfx",            "fast_lane", "AS2->C#", false, first);
            first = AppendTask(sb, "console",        "json_push", "C#->AS2", false, first);
            first = AppendTask(sb, "console_result", "json_event","AS2->C#", false, first);
            first = AppendTask(sb, "icon_bake",      "json_sync", "AS2<->C#",false, first);
            first = AppendTask(sb, "shop_response",  "json_async","AS2<->C#",false, first);
            first = AppendTask(sb, "map_response",   "json_async","AS2<->C#",false, first);
            first = AppendTask(sb, "stage_select_response","json_async","AS2<->C#",false, first);
            first = AppendTask(sb, "cursor_control", "json_sync", "AS2->C#", false, first);
            first = AppendTask(sb, "panel_request",  "json_sync", "AS2->C#", false, first);
            first = AppendTask(sb, "archive",        "json_async","AS2<->C#",true,  first);
            first = AppendTask(sb, "bench_sync",     "json_sync", "AS2<->C#",false, first);
            first = AppendTask(sb, "bench_async",    "json_async","AS2<->C#",false, first);
            first = AppendTask(sb, "bench_push",     "json_push", "AS2<->C#",false, first);
        }

        /// <summary>
        /// 从 BuildTaskList 中提取 httpCallable 集合。只在 RegisterAll 时调用一次。
        /// </summary>
        private static void BuildTaskMetadata()
        {
            _httpCallable.Clear();
            // 用 null sb 调用 AppendTask，仅收集 httpCallable 标记
            BuildTaskList(null);
        }

        private static bool AppendTask(StringBuilder sb, string name, string transport,
                                         string direction, bool httpCallable, bool first)
        {
            if (httpCallable)
                _httpCallable.Add(name);

            if (sb != null)
            {
                if (!first) sb.Append(",");
                sb.Append("{\"name\":\"").Append(name).Append("\"");
                sb.Append(",\"transport\":\"").Append(transport).Append("\"");
                sb.Append(",\"direction\":\"").Append(direction).Append("\"");
                sb.Append(",\"httpCallable\":").Append(httpCallable ? "true" : "false");
                sb.Append("}");
            }
            return false;
        }
    }
}
