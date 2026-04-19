// BMH 拆分：start_game / rebuild / reveal_ok / retry。
// 零行为改动，纯搬运。

using Newtonsoft.Json.Linq;
using CF7Launcher.Config;

namespace CF7Launcher.Guardian.Handlers
{
    internal static class GameStateCommandHandler
    {
        /// <summary>
        /// start_game 和 rebuild 共享骨架：slot 校验 + lastPlayedSlot 写入 +
        /// deferReveal / requireFlashReveal 两个独立 flag 解析 + 分派到 launchFlow。
        /// </summary>
        internal static void HandleStartOrRebuild(
            JObject msg,
            string cmd,
            BootstrapPanel bootForm,
            GameLaunchFlow launchFlow,
            UserPrefs userPrefs)
        {
            string slot = msg.Value<string>("slot");
            if (string.IsNullOrEmpty(slot))
            {
                BootstrapCommandHelpers.PostError(bootForm, "slot_missing", cmd + " needs slot");
                return;
            }
            if (launchFlow == null)
            {
                BootstrapCommandHelpers.PostError(bootForm, "flash_start_failed",
                    "launchFlow not available (flash path missing?)");
                return;
            }
            // start_game / rebuild 都代表用户要以这个槽位继续游戏或重建后开局，
            // 都应更新欢迎页默认槽位。
            if (userPrefs != null && userPrefs.LastPlayedSlot != slot)
            {
                userPrefs.LastPlayedSlot = slot;
                userPrefs.Save();
            }
            // Phase 2b-ext: defer reveal 两个独立 flag, 前端按需 opt-in
            //   deferReveal       — 片头视频播放期 (JS 发 reveal_ok 才清)
            //   requireFlashReveal — Flash 封面帧 (Flash 发 bootstrap_reveal_ready 才清)
            bool deferJs = msg.Value<bool?>("deferReveal") ?? false;
            bool reqFlash = msg.Value<bool?>("requireFlashReveal") ?? false;
            if (cmd == "rebuild") launchFlow.StartFreshGame(slot, deferJs, reqFlash);
            else launchFlow.StartGame(slot, deferJs, reqFlash);
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
