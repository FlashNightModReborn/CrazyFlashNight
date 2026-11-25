// BMH 拆分：Flash 本地存储配额查询与设置（flash_storage_status / flash_storage_set）。
//
// 入站 cmd:
//   flash_storage_status                             — 只读探测当前 #local\settings.sol 限额与 #SharedObjects\*\localhost 已用空间
//   flash_storage_set { limitKb, requestId? }        — 显式修改 #local\settings.sol 的 klimit（-2=无限制, 100/1024/10240）
// 出站 cmd:
//   flash_storage_status_resp
//   flash_storage_set_resp
//
// 安全与时序约束：
//   - 写入必须先通过 BootstrapCommandHelpers.RequireIdleOrTearDown：
//     Idle 直接落盘；仅后台静默 prewarm 时先 Reset 终止空闲 Flash 进程再落盘；
//     运行中游戏/建角会话一律拒绝 (not_idle)，绝不强杀活动会话或在 Flash 运行时并发写 settings.sol。

using System;
using System.Threading;
using Newtonsoft.Json;
using Newtonsoft.Json.Linq;
using CF7Launcher.Config;

namespace CF7Launcher.Guardian.Handlers
{
    internal static class FlashStorageCommandHandler
    {
        internal static void HandleStatus(BootstrapPanel bootForm, GameLaunchFlow launchFlow)
        {
            if (bootForm == null) return;
            ThreadPool.QueueUserWorkItem(delegate
            {
                try
                {
                    var status = FlashLocalStorageSettings.ReadStatus();
                    PostStatusResp(bootForm, "flash_storage_status_resp", status, CanModify(launchFlow), null);
                }
                catch (Exception ex)
                {
                    LogManager.Log("[BMH] flash_storage_status error: " + ex.Message);
                    PostErrorResp(bootForm, "flash_storage_status_resp", "status_failed", null, CanModify(launchFlow));
                }
            });
        }

        internal static void HandleSet(JObject msg, BootstrapPanel bootForm, GameLaunchFlow launchFlow)
        {
            if (bootForm == null) return;
            long? requestId = ReadRequestId(msg);
            JToken limitTok = msg != null ? msg["limitKb"] : null;
            if (limitTok == null || (limitTok.Type != JTokenType.Float && limitTok.Type != JTokenType.Integer))
            {
                ReplyWithCurrentStatus(bootForm, launchFlow, "invalid_limit", requestId);
                return;
            }
            double limitKb = limitTok.Value<double>();
            if (!FlashLocalStorageSettings.IsAllowedPresetLimitKb(limitKb))
            {
                ReplyWithCurrentStatus(bootForm, launchFlow, "invalid_limit", requestId);
                return;
            }

            if (launchFlow == null)
            {
                ReplyWithCurrentStatus(bootForm, null, "not_idle", requestId);
                return;
            }

            // Idle 直接执行；静默 prewarm 先同步 Reset 停止空闲 Flash 进程；游戏/建角运行中拒绝 not_idle。
            if (launchFlow.CurrentState != "Idle" && !launchFlow.IsInSilentPrewarm)
            {
                ReplyWithCurrentStatus(bootForm, launchFlow, "not_idle", requestId);
                return;
            }

            BootstrapCommandHelpers.RequireIdleOrTearDown(
                "flash_storage_set",
                bootForm,
                launchFlow,
                delegate
                {
                    ThreadPool.QueueUserWorkItem(delegate
                    {
                        try
                        {
                            // 二次复核：Reset 完成到线程调度期间若已被其他流程启动，仍 fail-closed。
                            if (launchFlow.CurrentState != "Idle")
                            {
                                var busy = FlashLocalStorageSettings.ReadStatus();
                                busy.Ok = false;
                                busy.Error = "not_idle";
                                PostStatusResp(bootForm, "flash_storage_set_resp", busy, CanModify(launchFlow), requestId);
                                return;
                            }
                            var updated = FlashLocalStorageSettings.SetLocalLimitKb(limitKb);
                            LogManager.Log("[FlashStorage] local quota update targetKb=" + limitKb
                                + " ok=" + updated.Ok + " effectiveKb=" + updated.LimitKb
                                + " usedBytes=" + updated.UsedBytes
                                + (updated.Error != null ? " error=" + updated.Error : ""));
                            PostStatusResp(bootForm, "flash_storage_set_resp", updated, CanModify(launchFlow), requestId);
                        }
                        catch (Exception ex)
                        {
                            LogManager.Log("[BMH] flash_storage_set error: " + ex.Message);
                            PostErrorResp(bootForm, "flash_storage_set_resp", "exception", requestId, CanModify(launchFlow));
                        }
                    });
                },
                msg);
        }

        private static bool CanModify(GameLaunchFlow launchFlow)
        {
            if (launchFlow == null) return false;
            return launchFlow.CurrentState == "Idle" || launchFlow.IsInSilentPrewarm;
        }

        private static long? ReadRequestId(JObject msg)
        {
            JToken tok = msg != null ? msg["requestId"] : null;
            return (tok != null && tok.Type == JTokenType.Integer) ? (long?)tok.Value<long>() : null;
        }

        private static void ReplyWithCurrentStatus(
            BootstrapPanel bootForm,
            GameLaunchFlow launchFlow,
            string error,
            long? requestId)
        {
            ThreadPool.QueueUserWorkItem(delegate
            {
                try
                {
                    var current = FlashLocalStorageSettings.ReadStatus();
                    current.Ok = false;
                    current.Error = error;
                    PostStatusResp(bootForm, "flash_storage_set_resp", current, CanModify(launchFlow), requestId);
                }
                catch
                {
                    PostErrorResp(bootForm, "flash_storage_set_resp", error, requestId, CanModify(launchFlow));
                }
            });
        }

        private static void PostStatusResp(
            BootstrapPanel bootForm,
            string outCmd,
            FlashLocalStorageStatus status,
            bool canModifyNow,
            long? requestId)
        {
            JObject obj = status != null ? status.ToJson(canModifyNow) : new JObject { ["ok"] = false, ["error"] = "status_unavailable" };
            obj["type"] = "bootstrap";
            obj["cmd"] = outCmd;
            if (requestId.HasValue) obj["requestId"] = requestId.Value;
            bootForm.PostToWeb(obj.ToString(Formatting.None));
        }

        private static void PostErrorResp(
            BootstrapPanel bootForm,
            string outCmd,
            string error,
            long? requestId,
            bool canModifyNow)
        {
            var obj = new JObject
            {
                ["type"] = "bootstrap",
                ["cmd"] = outCmd,
                ["ok"] = false,
                ["error"] = error ?? "unknown_error",
                ["canModifyNow"] = canModifyNow
            };
            if (requestId.HasValue) obj["requestId"] = requestId.Value;
            bootForm.PostToWeb(obj.ToString(Formatting.None));
        }
    }
}
