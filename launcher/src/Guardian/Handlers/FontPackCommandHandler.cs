// 字体包 bootstrap-side handler：把 FontPackTask 的 task 协议透传成 bootstrap 协议，
// 让 Welcome 页能在游戏外的"准备时间"完成字体包安装决策。
//
// 入站 cmd: fontpack_status / fontpack_install (带 group) / fontpack_cancel
// 出站 cmd: fontpack_status_resp / fontpack_install_resp / fontpack_progress (push)

using System;
using Newtonsoft.Json;
using Newtonsoft.Json.Linq;
using CF7Launcher.Tasks;

namespace CF7Launcher.Guardian.Handlers
{
    internal static class FontPackCommandHandler
    {
        /// <summary>
        /// Program.cs 在装配 fontPackTask 后调用一次：把 FontPackTask 的 progress 事件
        /// 转译为 bootstrap fontpack_progress push 消息。
        /// 注意：bootstrap webview 隐藏后 PostToWeb 仍然安全（WebView2 内部排队），
        /// 所以即使玩家点了"确认"进游戏，progress 事件继续累积但不打断下载。
        /// </summary>
        internal static void RegisterProgressSink(BootstrapPanel bootForm, FontPackTask fontPack)
        {
            if (bootForm == null || fontPack == null) return;
            fontPack.SetProgressSink(delegate(JObject p)
            {
                JObject outMsg = new JObject();
                outMsg["type"] = "bootstrap";
                outMsg["cmd"] = "fontpack_progress";
                foreach (var kv in p) outMsg[kv.Key] = kv.Value;
                bootForm.PostToWeb(outMsg.ToString(Formatting.None));
            });
        }

        internal static void HandleCancel(BootstrapPanel bootForm, FontPackTask fontPack)
        {
            if (fontPack == null)
            {
                BootstrapCommandHelpers.PostResp(bootForm, "fontpack_cancel_resp", false, null, "fontpack_unavailable");
                return;
            }
            bool wasInProgress = fontPack.RequestCancel();
            JObject outMsg = new JObject();
            outMsg["type"] = "bootstrap";
            outMsg["cmd"] = "fontpack_cancel_resp";
            outMsg["ok"] = true;
            outMsg["wasInProgress"] = wasInProgress;
            bootForm.PostToWeb(outMsg.ToString(Formatting.None));
        }

        internal static void HandleStatus(BootstrapPanel bootForm, FontPackTask fontPack)
        {
            if (fontPack == null)
            {
                BootstrapCommandHelpers.PostResp(bootForm, "fontpack_status_resp", false, null, "fontpack_unavailable");
                return;
            }
            JObject taskMsg = BuildTaskMessage("status", null);
            fontPack.HandleAsync(taskMsg, delegate(string resultJson)
            {
                ForwardTaskResult(bootForm, "fontpack_status_resp", resultJson);
            });
        }

        internal static void HandleInstall(JObject msg, BootstrapPanel bootForm, FontPackTask fontPack)
        {
            if (fontPack == null)
            {
                BootstrapCommandHelpers.PostResp(bootForm, "fontpack_install_resp", false, null, "fontpack_unavailable");
                return;
            }
            string group = msg.Value<string>("group");
            if (string.IsNullOrEmpty(group))
            {
                BootstrapCommandHelpers.PostResp(bootForm, "fontpack_install_resp", false, null, "missing_group");
                return;
            }
            JObject payload = new JObject();
            payload["group"] = group;
            JObject taskMsg = BuildTaskMessage("download_group", payload);
            fontPack.HandleAsync(taskMsg, delegate(string resultJson)
            {
                ForwardTaskResult(bootForm, "fontpack_install_resp", resultJson);
            });
        }

        // 把 FontPackTask 自己的 result JSON 透传给 bootstrap 端，
        // 字段保留（groups / installed / failed / fontsDir 等）只重写 type/cmd。
        private static void ForwardTaskResult(BootstrapPanel bootForm, string outCmd, string resultJson)
        {
            JObject result;
            try { result = string.IsNullOrEmpty(resultJson) ? new JObject() : JObject.Parse(resultJson); }
            catch
            {
                BootstrapCommandHelpers.PostResp(bootForm, outCmd, false, null, "fontpack_bad_response");
                return;
            }

            JObject outMsg = new JObject();
            outMsg["type"] = "bootstrap";
            outMsg["cmd"] = outCmd;
            outMsg["ok"] = result.Value<bool?>("success") ?? false;
            foreach (var kv in result)
            {
                if (kv.Key == "success" || kv.Key == "task") continue;
                outMsg[kv.Key] = kv.Value;
            }
            bootForm.PostToWeb(outMsg.ToString(Formatting.None));
        }

        private static JObject BuildTaskMessage(string op, JObject extraPayload)
        {
            JObject taskMsg = new JObject();
            taskMsg["task"] = "font_pack";
            JObject payload = extraPayload != null ? (JObject)extraPayload.DeepClone() : new JObject();
            payload["op"] = op;
            taskMsg["payload"] = payload;
            return taskMsg;
        }
    }
}
