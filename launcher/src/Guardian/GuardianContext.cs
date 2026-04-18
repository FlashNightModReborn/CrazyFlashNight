// Phase A Step A3: 单 Form 模型
// - 原 BootstrapForm / GuardianForm 双 Form 结构已塌缩为 GuardianForm 单 Form + BootstrapPanel 嵌入
// - 退出 owner 唯一化为 GuardianForm.OnFormClosing（状态分流，详见 GuardianForm.cs）
// - 原 boot.FormClosed → guard.ForceExit 转发桥已删除，不再需要

using System.Windows.Forms;

namespace CF7Launcher.Guardian
{
    public class GuardianContext : ApplicationContext
    {
        public GuardianContext(GuardianForm form)
        {
            this.MainForm = form;
            // GuardianForm 关闭: DoExit 已跑完 (含 ExitGuard), 退消息循环
            form.FormClosed += delegate { ExitThread(); };
        }
    }
}
