// BMH 拆分：start_game / reveal_ok / retry。
// 零行为改动，纯搬运。

using Newtonsoft.Json.Linq;
using CF7Launcher.Tasks;

namespace CF7Launcher.Guardian.Handlers
{
    internal static class GameStateCommandHandler
    {
        /// <summary>
        /// start_game validates a discovered physical slot and delegates
        /// reveal flags to GameLaunchFlow. LastPlayedSlot is written only after
        /// the exact scene-ready receipt; a durable create alone is insufficient.
        /// </summary>
        internal static void HandleStart(
            JObject msg,
            BootstrapPanel bootForm,
            GameLaunchFlow launchFlow,
            ArchiveTask archiveTask)
        {
            string slot;
            string slotError;
            if (!BootstrapCommandHelpers.TryReadDiscoveredSlotKey(
                    msg, "slot", archiveTask, out slot, out slotError))
            {
                BootstrapCommandHelpers.PostError(
                    bootForm, slotError, "start_game needs an exact slot key");
                return;
            }
            if (launchFlow == null)
            {
                BootstrapCommandHelpers.PostError(bootForm, "flash_start_failed",
                    "launchFlow not available (flash path missing?)");
                return;
            }
            // Phase 2b-ext: defer reveal 两个独立 flag, 前端按需 opt-in
            //   deferReveal       — 片头视频播放期 (JS 发 reveal_ok 才清)
            //   requireFlashReveal — Flash 封面帧 (Flash 发 bootstrap_reveal_ready 才清)
            bool deferJs = msg.Value<bool?>("deferReveal") ?? false;
            bool reqFlash = msg.Value<bool?>("requireFlashReveal") ?? false;
            launchFlow.StartGameFromBootstrap(slot, deferJs, reqFlash);
        }

        /// <summary>Phase 2b-ext: JS 侧 reveal 信号 (片头视频播完 / 跳过 / 无片头直通)。</summary>
        internal static void HandleRevealOk(GameLaunchFlow launchFlow)
        {
            if (launchFlow != null) launchFlow.OnJsRevealOk();
        }

        internal static void HandleRetry(BootstrapPanel bootForm, GameLaunchFlow launchFlow)
        {
            if (launchFlow == null)
            {
                BootstrapCommandHelpers.PostError(bootForm, "flash_start_failed", "launchFlow not available");
                return;
            }
            launchFlow.Retry();
        }
    }
}
