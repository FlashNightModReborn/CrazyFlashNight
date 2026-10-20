// CF7:ME Guardian Process — ExitGuard 行为探针
// C# 5 语法

using System;
using System.Threading;
using System.Windows.Forms;

namespace CF7Launcher.Guardian
{
    /// <summary>
    /// phase1 owner 矩阵 ExitGuard 覆盖测试探针。
    /// 仅由 CF7_EXITGUARD_PROBE=&lt;OnShutdownEarly 毫秒&gt; 环境变量显式激活，
    /// Program.Main 在一切启动组件之前直接调用；-1 单独验证 Agent 回包后退出顺序。
    ///
    /// 语义：用真实 GuardianForm + ForceExit 走 DoExit 完整顺序
    /// （fence → MarkShuttingDown → ExitGuard 后台线程 → OnShutdownEarly → …）。
    /// OnShutdownEarly 注入 Thread.Sleep 阻塞：
    ///   - 阻塞 ≥ 8s：ExitGuard 后台线程仍应触发 Environment.Exit(1)，
    ///     进程 exit code 1 且在 8s 附近终止，不等 OnShutdownEarly 醒来；
    ///   - 阻塞 &lt; 8s：清理先完成，探针正常返回 exit code 0，
    ///     后台守卫线程随进程退出，不误杀正常退出路径。
    /// </summary>
    internal static class ExitGuardProbe
    {
        internal static int Run(int earlySleepMs)
        {
            if (earlySleepMs == -1) return RunAgentResponseCompletion();
            if (earlySleepMs < 0) earlySleepMs = 0;
            using (var form = new GuardianForm())
            {
                form.OnShutdownEarly = delegate
                {
                    Thread.Sleep(earlySleepMs);
                };
                form.ForceExit();
            }
            // 到达这里 = cleanup 在 8s 内完成且 ExitGuard 未提前强杀，
            // 是“正常退出”通道的探针结果（exit code 0）。
            return 0;
        }

        // -1 exercises the real response-completion boundary without a save slot or Flash process.
        private static int RunAgentResponseCompletion()
        {
            using (var responseReturned = new ManualResetEventSlim(false))
            using (var form = new GuardianForm())
            {
                form.OnShutdownEarly = delegate
                {
                    // The response writer cannot resume until its marshalled UI callback returns.
                    if (!responseReturned.Wait(2000)) Environment.Exit(91);
                };
                form.Shown += delegate
                {
                    form.BeginInvoke(new Action(delegate
                    {
                        const string actionId = "agent-exit-response-probe";
                        if (!form.TryPrepareAgentRuntimeExit(actionId)) Environment.Exit(92);
                        form.CompleteAgentRuntimeExit(actionId);
                        responseReturned.Set();
                    }));
                };
                Application.Run(form);
            }
            return 0;
        }
    }
}
