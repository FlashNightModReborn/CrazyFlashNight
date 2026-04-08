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
    ///
    /// Task 清单：
    ///   frame        快车道 F 前缀   AS2→C#  (XmlSocketServer 直分发，不经 MessageRouter)
    ///   hn_reset     快车道 R 前缀   AS2→C#  (同上)
    ///   toast        JSON sync      AS2→C#  httpCallable=true
    ///   gomoku_eval  JSON async     AS2↔C#  httpCallable=true
    ///   audio        JSON sync      AS2→C#  httpCallable=true
    ///   sfx          快车道 S 前缀   AS2→C#  (XmlSocketServer 直分发，不经 MessageRouter)
    ///   console      JSON push      C#→AS2  (HttpApiServer /console 专用端点)
    ///   console_result  JSON event  AS2→C#  (内部事件，触发 OnConsoleResult)
    ///   icon_bake       JSON sync   AS2↔C#  (图标烘焙：begin/chunk/end/complete)
    /// </summary>
    public static class TaskRegistry
    {
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
            ShopTask shopTask)
        {
            // JSON 路由 task（经 MessageRouter 分发）
            router.RegisterAsync("gomoku_eval", gomoku.HandleAsync);
            router.RegisterAsync("data_query", dataQuery.HandleAsync);
            router.RegisterSync("toast", toast.Handle);
            router.RegisterSync("audio", audio.Handle);
            router.RegisterSync("icon_bake", iconBake.Handle);

            // 商城面板回包路由
            if (shopTask != null)
                router.RegisterAsync("shop_response", shopTask.HandleFlashResponse);

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

            // 全量 task 清单（含元数据）
            AppendTask(sb, "frame",          "fast_lane", "AS2->C#", false); sb.Append(",");
            AppendTask(sb, "hn_reset",       "fast_lane", "AS2->C#", false); sb.Append(",");
            AppendTask(sb, "toast",          "json_sync", "AS2->C#", true);  sb.Append(",");
            AppendTask(sb, "gomoku_eval",    "json_async","AS2<->C#",true);  sb.Append(",");
            AppendTask(sb, "data_query",     "json_async","AS2<->C#",true);  sb.Append(",");
            AppendTask(sb, "audio",          "json_sync", "AS2->C#", true);  sb.Append(",");
            AppendTask(sb, "sfx",            "fast_lane", "AS2->C#", false); sb.Append(",");
            AppendTask(sb, "console",        "json_push", "C#->AS2", false); sb.Append(",");
            AppendTask(sb, "console_result", "json_event","AS2->C#", false); sb.Append(",");
            AppendTask(sb, "icon_bake",      "json_sync", "AS2<->C#",false); sb.Append(",");
            AppendTask(sb, "shop_response",  "json_async","AS2<->C#",false);

            sb.Append("]}");
            return sb.ToString();
        }

        private static void AppendTask(StringBuilder sb, string name, string transport,
                                         string direction, bool httpCallable)
        {
            sb.Append("{\"name\":\"").Append(name).Append("\"");
            sb.Append(",\"transport\":\"").Append(transport).Append("\"");
            sb.Append(",\"direction\":\"").Append(direction).Append("\"");
            sb.Append(",\"httpCallable\":").Append(httpCallable ? "true" : "false");
            sb.Append("}");
        }
    }
}
