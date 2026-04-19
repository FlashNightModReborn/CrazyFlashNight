// BMH 拆分：所有 handler 共享的 helper（响应构造 / 数据归一化 / Idle 守卫 / archive 分发）。
// 从 BootstrapMessageHandler.cs 平移出来，零行为改动。

using System;
using Newtonsoft.Json;
using Newtonsoft.Json.Linq;
using CF7Launcher.Config;
using CF7Launcher.Tasks;

namespace CF7Launcher.Guardian.Handlers
{
    internal static class BootstrapCommandHelpers
    {
        // ─────── 响应构造 ───────

        /// <summary>通用响应：{type:"bootstrap", cmd, ok, slot?, error?}</summary>
        internal static void PostResp(BootstrapPanel bootForm, string cmd, bool ok, string slot, string error)
        {
            JObject obj = new JObject();
            obj["type"] = "bootstrap";
            obj["cmd"] = cmd;
            obj["ok"] = ok;
            if (slot != null) obj["slot"] = slot;
            if (!ok && error != null) obj["error"] = error;
            bootForm.PostToWeb(obj.ToString(Formatting.None));
        }

        internal static void PostError(BootstrapPanel bootForm, string code, string msg)
        {
            JObject obj = new JObject();
            obj["type"] = "bootstrap";
            obj["cmd"] = "error";
            obj["code"] = code;
            obj["msg"] = msg ?? "";
            bootForm.PostToWeb(obj.ToString(Formatting.None));
        }

        internal static void PostPong(BootstrapPanel bootForm, JToken payload)
        {
            JObject obj = new JObject();
            obj["type"] = "bootstrap";
            obj["cmd"] = "pong";
            if (payload != null) obj["payload"] = payload;
            bootForm.PostToWeb(obj.ToString(Formatting.None));
        }

        // ─────── 数据归一化 ───────

        /// <summary>
        /// 将 string 或 JObject 的 data 归一为 JObject（C# 5 兼容）。
        /// </summary>
        internal static bool NormalizeDataToJObject(JToken raw, out JObject obj, out string error)
        {
            obj = null;
            error = null;
            if (raw == null) { error = "missing_data"; return false; }
            if (raw.Type == JTokenType.Object)
            {
                obj = (JObject)raw;
                return true;
            }
            if (raw.Type == JTokenType.String)
            {
                try
                {
                    obj = JObject.Parse((string)raw);
                    return true;
                }
                catch
                {
                    error = "schema_parse_failed";
                    return false;
                }
            }
            error = "schema_data_type_invalid";
            return false;
        }

        // ─────── Idle 守卫 ───────

        /// <summary>
        /// Phase D Step D11: Idle 守卫 + silent prewarm tear down 回调协议.
        ///   - Idle → 直接 onReady()
        ///   - silent prewarm (launchFlow.IsInSilentPrewarm) → Reset(onReady, "user_edit_" + cmd),
        ///     Reset 推到 Idle 后 flush pending queue 跑 onReady; 用户编辑不被 prewarm 挡住
        ///   - 其他非 Idle (用户已点 play, Embedding/WaitingGameReady/Ready) → reject not_idle
        /// </summary>
        internal static void RequireIdleOrTearDown(string cmd, BootstrapPanel bootForm, GameLaunchFlow launchFlow, Action onReady)
        {
            if (launchFlow == null)
            {
                PostNotIdleResp(cmd, bootForm);
                return;
            }
            if (launchFlow.CurrentState == "Idle")
            {
                onReady();
                return;
            }
            if (launchFlow.IsInSilentPrewarm)
            {
                LogManager.Log("[BMH] silent teardown for cmd=" + cmd + " → Reset(user_edit_" + cmd + ")");
                launchFlow.Reset(onReady, "user_edit_" + cmd);
                return;
            }
            PostNotIdleResp(cmd, bootForm);
        }

        internal static void PostNotIdleResp(string cmd, BootstrapPanel bootForm)
        {
            string outCmd;
            switch (cmd)
            {
                case "save":          outCmd = "save_resp";   break;
                case "reset":         outCmd = "reset_resp";  break;
                case "import_start":  outCmd = "import_resp"; break;
                case "import_commit": outCmd = "import_resp"; break;
                default:              outCmd = "error";       break;
            }
            PostResp(bootForm, outCmd, false, null, "not_idle");
        }

        // ─────── archive 分发 ───────

        internal static JObject BuildArchivePayload(string op, string slot)
        {
            JObject msg = new JObject();
            msg["task"] = "archive";
            JObject payload = new JObject();
            payload["op"] = op;
            if (slot != null) payload["slot"] = slot;
            msg["payload"] = payload;
            return msg;
        }

        /// <summary>
        /// Phase 2a 通用 archive dispatch：透传 result 全部字段 + 映射 cmd。
        /// 用于 load / load_raw 等需要原样转发 data/tombstoned/corrupt 字段的场景。
        /// </summary>
        internal static void DispatchArchiveGeneric(
            BootstrapPanel bootForm,
            ArchiveTask archiveTask,
            JObject archiveMsg,
            string outCmd)
        {
            archiveTask.HandleAsync(archiveMsg, delegate(string resultJson)
            {
                JObject result;
                try { result = JObject.Parse(resultJson); }
                catch
                {
                    PostResp(bootForm, outCmd, false, null, "archive_task_failed");
                    return;
                }

                bool ok = result.Value<bool?>("success") ?? false;
                JObject outMsg = new JObject();
                outMsg["type"] = "bootstrap";
                outMsg["cmd"] = outCmd;
                outMsg["ok"] = ok;

                // 透传所有非 success/task 字段
                foreach (var kv in result)
                {
                    if (kv.Key == "success" || kv.Key == "task") continue;
                    outMsg[kv.Key] = kv.Value;
                }

                bootForm.PostToWeb(outMsg.ToString(Formatting.None));
            });
        }

        /// <summary>Phase 1 DispatchArchive（list_resp / delete_resp 专用，保留 forwardSlots 逻辑）。
        /// Phase 2b: forwardSlots 路径 (list_resp) 附带 UserPrefs 的 lastPlayedSlot / introEnabled,
        /// 让欢迎页一次性拿到"上次槽位 + 片头偏好", 不需要额外 roundtrip.</summary>
        internal static void DispatchArchive(
            BootstrapPanel bootForm,
            ArchiveTask archiveTask,
            JObject archiveMsg,
            string outCmd,
            bool forwardSlots,
            UserPrefs userPrefs = null)
        {
            archiveTask.HandleAsync(archiveMsg, delegate(string resultJson)
            {
                JObject result;
                try { result = JObject.Parse(resultJson); }
                catch
                {
                    PostError(bootForm, "archive_task_failed", "bad archive response");
                    return;
                }

                JObject outMsgObj = new JObject();
                outMsgObj["type"] = "bootstrap";
                outMsgObj["cmd"] = outCmd;
                if (forwardSlots)
                {
                    JToken slots = result["slots"];
                    outMsgObj["slots"] = slots != null ? slots : (JToken)new JArray();
                    // Phase 2b: 欢迎页偏好附带
                    if (userPrefs != null)
                    {
                        if (!string.IsNullOrEmpty(userPrefs.LastPlayedSlot))
                            outMsgObj["lastPlayedSlot"] = userPrefs.LastPlayedSlot;
                        outMsgObj["introEnabled"] = userPrefs.IntroEnabled;
                        outMsgObj["sfxEnabled"] = userPrefs.SfxEnabled;
                        outMsgObj["ambientEnabled"] = userPrefs.AmbientEnabled;
                    }
                }
                else
                {
                    bool ok = result.Value<bool?>("success") ?? false;
                    outMsgObj["ok"] = ok;
                    string slot = result.Value<string>("slot");
                    if (slot != null) outMsgObj["slot"] = slot;
                    string err = result.Value<string>("error");
                    if (!ok && err != null) outMsgObj["error"] = err;
                }
                bootForm.PostToWeb(outMsgObj.ToString(Formatting.None));
            });
        }
    }
}
