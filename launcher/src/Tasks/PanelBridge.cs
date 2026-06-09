using System.Collections.Generic;
using Newtonsoft.Json.Linq;

namespace CF7Launcher.Tasks
{
    /// <summary>
    /// Web → Flash 面板命令信封构造（全部 panel 桥共用的单一实现）。
    ///
    /// 安全要点：固定保留键集（含 <c>action</c> / <c>task</c>）一律不透传给 Flash，杜绝 Web 消息
    /// 夹带同名字段覆盖 C# 由 cmd 派生的可信 <c>action</c>。AS2 端
    /// <c>ServerManager.handleGameCommand</c> 是 <c>_root.gameCommands[action]</c> 裸分发、无白名单——
    /// 一旦被 Web 覆盖 action，即可绕过 cmd→action 映射调用任意已注册全局命令、并跳过前端确认。
    ///
    /// 设计动机：守卫此前在 8 个桥里逐份复制，靠纪律维持、加新桥极易漏抄（无 lint/CI 强制）。
    /// 收口到此构造器后，新桥只需调 <see cref="BuildFlashCommand"/>，保留键集只有一处、改一处即全生效。
    /// </summary>
    internal static class PanelBridge
    {
        // Web 信封 / 路由保留键：不透传给 Flash。
        //   type/panel/cmd/callId = WebOverlay 信封字段（噪声）；
        //   action/task           = 安全守卫（防 Web 覆盖可信 action 与 task 信封值）。
        private static readonly HashSet<string> Reserved =
            new HashSet<string> { "type", "panel", "cmd", "callId", "action", "task" };

        /// <summary>
        /// 构造发往 Flash 的命令对象：<c>{ task:"cmd", action, callId }</c> + 透传 <paramref name="parsed"/>
        /// 中的非保留参数。各桥据此把 cmd 映射出的可信 action 与业务参数一起下发。
        /// </summary>
        /// <param name="action">C# 由 cmd 派生的可信 action（如 taskSnapshot）；调用方负责其可信。</param>
        /// <param name="callId">Flash 侧 callId（int 序号）。</param>
        /// <param name="parsed">原始 Web 消息；其 action/task 等保留键被忽略，绝不覆盖信封。</param>
        public static JObject BuildFlashCommand(string action, int callId, JObject parsed)
        {
            var flashMsg = new JObject();
            flashMsg["task"] = "cmd";
            flashMsg["action"] = action;
            flashMsg["callId"] = callId;
            if (parsed != null)
            {
                foreach (var prop in parsed.Properties())
                {
                    if (!Reserved.Contains(prop.Name))
                        flashMsg[prop.Name] = prop.Value;
                }
            }
            return flashMsg;
        }
    }
}
