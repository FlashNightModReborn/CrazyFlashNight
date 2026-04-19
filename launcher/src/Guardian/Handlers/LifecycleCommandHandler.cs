// BMH 拆分：ready / ping / cancel_launch。
// 零行为改动，纯搬运。

using System;
using Newtonsoft.Json.Linq;

namespace CF7Launcher.Guardian.Handlers
{
    internal static class LifecycleCommandHandler
    {
        /// <summary>
        /// Phase D Step D9: 冷启动 prewarm 触发. Prewarm() 内部 session-level latch
        /// (_prewarmTriggered) 保证一次 launcher 生命周期仅尝试一次 — bootstrap.html
        /// reload / 双 rAF 导致 ready 多发也 no-op.
        /// </summary>
        internal static void HandleReady(GameLaunchFlow launchFlow)
        {
            if (launchFlow != null)
            {
                try { launchFlow.Prewarm(); }
                catch (Exception ex) { LogManager.Log("[BMH] Prewarm invoke error: " + ex.Message); }
            }
        }

        internal static void HandlePing(BootstrapPanel bootForm, JToken payload)
        {
            BootstrapCommandHelpers.PostPong(bootForm, payload);
        }

        /// <summary>
        /// Phase B Step B2: 启动中用户主动取消。仅非 Idle 有效，Idle 下 no-op + log。
        /// </summary>
        internal static void HandleCancelLaunch(GameLaunchFlow launchFlow)
        {
            if (launchFlow == null) return;
            if (launchFlow.CurrentState == "Idle")
            {
                LogManager.Log("[BMH] cancel_launch ignored: state=Idle");
                return;
            }
            launchFlow.Reset(null, "user_cancel");
        }
    }
}
