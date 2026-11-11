// BMH 拆分：所有 handler 共享的 helper（响应构造 / 数据归一化 / Idle 守卫 / archive 分发）。
// 从 BootstrapMessageHandler.cs 平移出来，零行为改动。

using System;
using Newtonsoft.Json;
using Newtonsoft.Json.Linq;
using CF7Launcher.Config;
using CF7Launcher.Save;
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

        internal static bool TryReadSlotKey(
            JObject message,
            string propertyName,
            out string slotKey,
            out string error)
        {
            slotKey = null;
            error = null;
            JToken token = message != null ? message[propertyName] : null;
            if (token == null || token.Type == JTokenType.Null)
            {
                error = "slot_missing";
                return false;
            }
            if (token.Type != JTokenType.String
                || !SaveSlotKey.TryValidateExisting(token.Value<string>(), out slotKey))
            {
                error = "invalid_slot_key";
                return false;
            }
            return true;
        }

        internal static bool TryReadDiscoveredSlotKey(
            JObject message,
            string propertyName,
            ArchiveTask archiveTask,
            out string slotKey,
            out string error)
        {
            if (!TryReadSlotKey(
                    message,
                    propertyName,
                    out slotKey,
                    out error))
                return false;
            if (archiveTask == null || !archiveTask.SlotExistsSync(slotKey))
            {
                slotKey = null;
                error = "slot_not_found";
                return false;
            }
            return true;
        }

        internal static bool TryReadWritableSlotKey(
            JObject message,
            string propertyName,
            ArchiveTask archiveTask,
            out string slotKey,
            out string error)
        {
            if (!TryReadSlotKey(
                    message,
                    propertyName,
                    out slotKey,
                    out error))
                return false;
            if (SaveSlotKey.IsValid(slotKey))
                return true;
            if (archiveTask != null && archiveTask.SlotExistsSync(slotKey))
                return true;
            slotKey = null;
            error = "slot_not_found";
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
        internal static void RequireIdleOrTearDown(string cmd, BootstrapPanel bootForm, GameLaunchFlow launchFlow, Action onReady, JObject request = null)
        {
            if (launchFlow == null)
            {
                PostNotIdleResp(cmd, bootForm, request);
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
            PostNotIdleResp(cmd, bootForm, request);
        }

        internal static void PostNotIdleResp(string cmd, BootstrapPanel bootForm, JObject request = null)
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
            if (request != null) PostSlotFailure(bootForm, request, outCmd, "not_idle");
            else PostResp(bootForm, outCmd, false, null, "not_idle");
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

        internal static JObject BuildSlotReply(JObject request, string cmd, JObject result)
        {
            bool validKey = TryReadSlotKey(request, "slot", out string slot, out _);
            bool ok = result?["success"]?.Type == JTokenType.Boolean && (bool)result["success"];
            bool matches = validKey && string.Equals(result?.Value<string>("slot"), slot, StringComparison.Ordinal);
            var reply = new JObject { ["type"] = "bootstrap", ["cmd"] = cmd, ["ok"] = ok && matches };
            if (validKey) reply["slot"] = slot;
            if (request?["requestId"]?.Type == JTokenType.Integer) reply["requestId"] = request["requestId"];
            if (!ok || !matches)
            {
                reply["error"] = ok ? "archive_slot_mismatch" : result?.Value<string>("error") ?? "archive_task_failed";
                return reply;
            }
            foreach (string field in new[] { "data", "size", "warnings", "warning", "tombstoned", "corrupt", "reset" })
                if (result[field] != null) reply[field] = result[field];
            return reply;
        }

        internal static void PostSlotFailure(BootstrapPanel panel, JObject request, string cmd, string error)
        {
            var failure = new JObject { ["success"] = false, ["error"] = error };
            panel.PostToWeb(BuildSlotReply(request, cmd, failure).ToString(Formatting.None));
        }

        internal static void DispatchSlot(BootstrapPanel panel, ArchiveTask archive, JObject request,
            JObject archiveMessage, string cmd)
        {
            archive.HandleAsync(archiveMessage, json =>
            {
                JObject result = null;
                try { result = JObject.Parse(json); } catch (JsonException) { }
                panel.PostToWeb(BuildSlotReply(request, cmd, result).ToString(Formatting.None));
            });
        }

        internal static void DispatchList(BootstrapPanel panel, ArchiveTask archive, UserPrefs prefs)
        {
            archive.HandleAsync(BuildArchivePayload("list", null), json =>
            {
                JObject result = null;
                try { result = JObject.Parse(json); } catch (JsonException) { }
                if (result?.Value<bool?>("success") != true || !(result["slots"] is JArray))
                {
                    PostResp(panel, "list_resp", false, null, result?.Value<string>("error") ?? "archive_task_failed");
                    return;
                }
                var reply = new JObject
                {
                    ["type"] = "bootstrap", ["cmd"] = "list_resp", ["ok"] = true,
                    ["slots"] = result["slots"], ["archiveRequestIds"] = true
                };
                if (prefs != null)
                {
                    if (!string.IsNullOrEmpty(prefs.LastPlayedSlot)) reply["lastPlayedSlot"] = prefs.LastPlayedSlot;
                    reply["introEnabled"] = prefs.IntroEnabled;
                    reply["sfxEnabled"] = prefs.SfxEnabled;
                    reply["ambientEnabled"] = prefs.AmbientEnabled;
                    reply["uiFontScale"] = prefs.UiFontScale;
                }
                panel.PostToWeb(reply.ToString(Formatting.None));
            });
        }
    }
}
