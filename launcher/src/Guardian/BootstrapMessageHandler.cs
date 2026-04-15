// P3b Phase 1g: Bootstrap JS→C# 协议 handler（spike 与正常路径共用）
// 入站 cmd: ready / list / start_game / delete / rebuild / retry / ping
// 出站 cmd: state / list_resp / delete_resp / error / pong
// 详见 plan compressed-floating-nebula.md Phase 1g 协议表。

using System;
using Newtonsoft.Json;
using Newtonsoft.Json.Linq;
using CF7Launcher.Tasks;

namespace CF7Launcher.Guardian
{
    public static class BootstrapMessageHandler
    {
        public static void Handle(
            string json,
            BootstrapForm bootForm,
            ArchiveTask archiveTask,
            GameLaunchFlow launchFlow)
        {
            JObject msg;
            try { msg = JObject.Parse(json); }
            catch (Exception ex)
            {
                PostError(bootForm, "bad_json", ex.Message);
                return;
            }

            string cmd = msg.Value<string>("cmd");
            if (string.IsNullOrEmpty(cmd))
            {
                PostError(bootForm, "unknown_cmd", "missing cmd");
                return;
            }

            switch (cmd)
            {
                case "ready":
                    // bootstrap.html 已 loaded；C# 无需回包
                    return;

                case "ping":
                    PostPong(bootForm, msg["payload"]);
                    return;

                case "list":
                    DispatchArchive(bootForm, archiveTask, BuildArchivePayload("list", null), "list_resp",
                        /*forwardSlots:*/ true);
                    return;

                case "delete":
                    {
                        string slot = msg.Value<string>("slot");
                        if (string.IsNullOrEmpty(slot)) { PostError(bootForm, "slot_missing", "delete needs slot"); return; }
                        DispatchArchive(bootForm, archiveTask, BuildArchivePayload("delete", slot), "delete_resp",
                            /*forwardSlots:*/ false);
                        return;
                    }

                case "start_game":
                case "rebuild":
                    {
                        string slot = msg.Value<string>("slot");
                        if (string.IsNullOrEmpty(slot)) { PostError(bootForm, "slot_missing", cmd + " needs slot"); return; }
                        if (launchFlow == null)
                        {
                            PostError(bootForm, "flash_start_failed", "launchFlow not available (flash path missing?)");
                            return;
                        }
                        launchFlow.StartGame(slot);
                        return;
                    }

                case "retry":
                    if (launchFlow == null) { PostError(bootForm, "flash_start_failed", "launchFlow not available"); return; }
                    launchFlow.Retry();
                    return;

                default:
                    PostError(bootForm, "unknown_cmd", cmd);
                    return;
            }
        }

        private static JObject BuildArchivePayload(string op, string slot)
        {
            JObject msg = new JObject();
            msg["task"] = "archive";
            JObject payload = new JObject();
            payload["op"] = op;
            if (slot != null) payload["slot"] = slot;
            msg["payload"] = payload;
            return msg;
        }

        private static void DispatchArchive(
            BootstrapForm bootForm,
            ArchiveTask archiveTask,
            JObject archiveMsg,
            string outCmd,
            bool forwardSlots)
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

                JObject outMsg = new JObject();
                outMsg["type"] = "bootstrap";
                outMsg["cmd"] = outCmd;
                if (forwardSlots)
                {
                    JToken slots = result["slots"];
                    outMsg["slots"] = slots != null ? slots : (JToken)new JArray();
                }
                else
                {
                    bool ok = result.Value<bool?>("success") ?? false;
                    outMsg["ok"] = ok;
                    string slot = result.Value<string>("slot");
                    if (slot != null) outMsg["slot"] = slot;
                    string err = result.Value<string>("error");
                    if (!ok && err != null) outMsg["error"] = err;
                }
                bootForm.PostToWeb(outMsg.ToString(Formatting.None));
            });
        }

        private static void PostError(BootstrapForm bootForm, string code, string msg)
        {
            JObject obj = new JObject();
            obj["type"] = "bootstrap";
            obj["cmd"] = "error";
            obj["code"] = code;
            obj["msg"] = msg ?? "";
            bootForm.PostToWeb(obj.ToString(Formatting.None));
        }

        private static void PostPong(BootstrapForm bootForm, JToken payload)
        {
            JObject obj = new JObject();
            obj["type"] = "bootstrap";
            obj["cmd"] = "pong";
            if (payload != null) obj["payload"] = payload;
            bootForm.PostToWeb(obj.ToString(Formatting.None));
        }
    }
}
