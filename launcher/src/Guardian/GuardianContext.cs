// P3b Phase 1i: ApplicationContext 替换 Application.Run(form)
// BootstrapForm 作 MainForm; Bootstrap Ready 时 Hide 不 Close.
// 所有退出路径经 guard.ForceExit → DoExit → ExitGuard 8s (不变式: 不绕开保险).

using System;
using System.Windows.Forms;

namespace CF7Launcher.Guardian
{
    public class GuardianContext : ApplicationContext
    {
        private readonly BootstrapForm _boot;
        private readonly GuardianForm _guard;

        public GuardianContext(BootstrapForm boot, GuardianForm guard)
        {
            _boot = boot;
            _guard = guard;
            this.MainForm = _boot;

            // BootstrapForm 关闭: 路由到 guard.ForceExit (保证经 DoExit + ExitGuard 8s 强杀)
            // FormClosing 里按 close-policy 拦截 Spawning/Embedding 等非终止状态; 进入这里的都是允许退出
            _boot.FormClosed += delegate
            {
                if (_guard != null && !_guard.IsDisposed)
                {
                    try { _guard.ForceExit(); }
                    catch (Exception ex)
                    {
                        LogManager.Log("[Ctx] guard.ForceExit error, fallback ExitThread: " + ex.Message);
                        ExitThread();
                    }
                }
                else
                {
                    LogManager.Log("[Ctx] guard disposed, bypass DoExit");
                    ExitThread();
                }
            };

            // GuardianForm 关闭: DoExit 已跑完 (含 ExitGuard), 退消息循环
            _guard.FormClosed += delegate { ExitThread(); };
        }
    }
}
