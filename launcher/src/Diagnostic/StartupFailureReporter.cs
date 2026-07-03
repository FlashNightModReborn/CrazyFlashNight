using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Drawing;
using System.IO;
using System.Text;
using System.Windows.Forms;
using CF7Launcher.Guardian;
using CF7Launcher.Save;

namespace CF7Launcher.Diagnostic
{
    public sealed class StartupFailureReport
    {
        public string Code;
        public string Reason;
        public string Title;
        public string Detail;
        public string Recommendation;
        public string ProjectRoot;
        public string LogsDir;
        public string SummaryPath;
        public string ZipPath;
        public string ZipName;
        public long ZipSize;
        public bool PackageOk;
        public string PackageError;
        public List<string> Warnings = new List<string>();

        public string BuildClipboardText()
        {
            StringBuilder sb = new StringBuilder();
            sb.AppendLine("CF7:ME 启动诊断摘要");
            sb.AppendLine("错误码: " + (Code ?? "(unknown)"));
            sb.AppendLine("原因: " + (Reason ?? "(unknown)"));
            sb.AppendLine("标题: " + (Title ?? ""));
            if (!string.IsNullOrWhiteSpace(Detail))
                sb.AppendLine("详情: " + Detail);
            if (!string.IsNullOrWhiteSpace(Recommendation))
                sb.AppendLine("建议: " + Recommendation);
            sb.AppendLine("项目目录: " + (ProjectRoot ?? "(unknown)"));
            sb.AppendLine("日志目录: " + (LogsDir ?? "(unknown)"));
            if (PackageOk)
            {
                sb.AppendLine("诊断包: " + ZipPath);
                sb.AppendLine("诊断包大小: " + ZipSize + " bytes");
            }
            else
            {
                sb.AppendLine("诊断包: 生成失败 - " + (PackageError ?? "unknown"));
            }
            if (Warnings != null && Warnings.Count > 0)
            {
                sb.AppendLine("诊断包警告:");
                for (int i = 0; i < Warnings.Count; i++)
                    sb.AppendLine("- " + Warnings[i]);
            }
            return sb.ToString();
        }

        public string BuildDialogBody()
        {
            StringBuilder sb = new StringBuilder();
            sb.AppendLine("错误码: " + (Code ?? "(unknown)"));
            sb.AppendLine();
            if (!string.IsNullOrWhiteSpace(Detail))
            {
                sb.AppendLine("检测结果:");
                sb.AppendLine(Detail);
                sb.AppendLine();
            }
            if (!string.IsNullOrWhiteSpace(Recommendation))
            {
                sb.AppendLine("建议操作:");
                sb.AppendLine(Recommendation);
                sb.AppendLine();
            }
            if (PackageOk)
            {
                sb.AppendLine("诊断包已生成:");
                sb.AppendLine(ZipPath);
            }
            else
            {
                sb.AppendLine("诊断包生成失败:");
                sb.AppendLine(PackageError ?? "unknown");
                sb.AppendLine();
                sb.AppendLine("仍可把日志目录发给开发组:");
                sb.AppendLine(LogsDir ?? "(unknown)");
            }
            return sb.ToString();
        }
    }

    public static class StartupFailureReporter
    {
        public static StartupFailureReport ReportTerminalFailure(
            IWin32Window owner,
            string projectRoot,
            string reason,
            string code,
            string title,
            string detail,
            string recommendation,
            string slot,
            string swfPath,
            ISolFileLocator solLocator)
        {
            StartupDiagnostics.Exit(reason, DetailWithCode(code, detail));
            StartupFailureReport report = CreateReport(
                projectRoot, reason, code, title, detail, recommendation,
                slot, swfPath, solLocator, true);
            ShowDialog(owner, report);
            return report;
        }

        public static StartupFailureReport ReportRecoverableFailure(
            IWin32Window owner,
            string projectRoot,
            string reason,
            string code,
            string title,
            string detail,
            string recommendation,
            string slot,
            string swfPath,
            ISolFileLocator solLocator)
        {
            StartupDiagnostics.Failure(reason, DetailWithCode(code, detail));
            StartupFailureReport report = CreateReport(
                projectRoot, reason, code, title, detail, recommendation,
                slot, swfPath, solLocator, true);
            ShowDialog(owner, report);
            return report;
        }

        public static StartupFailureReport CreateReport(
            string projectRoot,
            string reason,
            string code,
            string title,
            string detail,
            string recommendation,
            string slot,
            string swfPath,
            ISolFileLocator solLocator,
            bool packageDiagnostics)
        {
            StartupFailureReport report = new StartupFailureReport();
            report.ProjectRoot = NormalizeRoot(projectRoot);
            report.Reason = string.IsNullOrWhiteSpace(reason) ? "unknown" : reason;
            report.Code = string.IsNullOrWhiteSpace(code) ? "CF7-LAUNCH-UNKNOWN" : code;
            report.Title = string.IsNullOrWhiteSpace(title) ? "启动失败" : title;
            report.Detail = detail ?? "";
            report.Recommendation = recommendation ?? "请重试一次；如果问题持续存在，请把诊断包发给开发组。";

            if (!string.IsNullOrEmpty(report.ProjectRoot))
            {
                report.LogsDir = Path.Combine(report.ProjectRoot, "logs");
                try { Directory.CreateDirectory(report.LogsDir); } catch { }
                report.SummaryPath = Path.Combine(report.LogsDir, "startup-failure-latest.txt");
            }

            WriteSummaryFile(report);

            if (packageDiagnostics && !string.IsNullOrEmpty(report.ProjectRoot))
            {
                DiagnosticResult packed = DiagnosticPackager.Pack(report.ProjectRoot, slot, swfPath, solLocator);
                report.PackageOk = packed.Ok;
                report.ZipPath = packed.ZipPath;
                report.ZipName = packed.ZipName;
                report.ZipSize = packed.ZipSize;
                report.PackageError = packed.Error;
                if (packed.Warnings != null)
                    report.Warnings = packed.Warnings;
                WriteSummaryFile(report);
            }
            else
            {
                report.PackageOk = false;
                report.PackageError = "projectRoot unavailable";
            }

            try
            {
                LogManager.Log("[StartupFailure] code=" + report.Code
                    + " reason=" + report.Reason
                    + " packageOk=" + report.PackageOk
                    + (report.PackageOk ? " zip=" + report.ZipName : " error=" + report.PackageError));
            }
            catch { }

            return report;
        }

        public static string DetailWithCode(string code, string detail)
        {
            string safeCode = string.IsNullOrWhiteSpace(code) ? "CF7-LAUNCH-UNKNOWN" : code;
            return "code=" + safeCode + (string.IsNullOrWhiteSpace(detail) ? "" : " detail=" + detail);
        }

        public static string CodeForLaunchFlowReason(string msg)
        {
            switch (msg ?? "")
            {
                case "flash_start_failed": return "CF7-LAUNCH-FLASH-START";
                case "socket_connect_timeout": return "CF7-LAUNCH-SOCKET-TIMEOUT";
                case "handshake_timeout": return "CF7-LAUNCH-HANDSHAKE-TIMEOUT";
                case "embed_timeout": return "CF7-LAUNCH-EMBED-TIMEOUT";
                case "game_ready_timeout": return "CF7-LAUNCH-GAME-READY-TIMEOUT";
                case "flash_exited_pre_reveal": return "CF7-LAUNCH-FLASH-EXITED-PRE-REVEAL";
                case "flash_exited": return "CF7-LAUNCH-FLASH-EXITED";
                case "reset_socket_force_close_failed": return "CF7-LAUNCH-RESET-FAILED";
                default: return "CF7-LAUNCH-FLOW-ERROR";
            }
        }

        public static string RecommendationForLaunchFlowReason(string msg)
        {
            switch (msg ?? "")
            {
                case "flash_start_failed":
                    return "请先点击重试；如果仍失败，请通过 Steam 验证游戏文件完整性，并检查杀毒软件是否隔离了 Flash Player。";
                case "socket_connect_timeout":
                    return "请关闭残留的 Flash Player 或重复启动的游戏进程后重试；如果仍失败，请把诊断包发给开发组。";
                case "handshake_timeout":
                    return "Flash 已启动但未完成启动握手。请重试一次；如果持续发生，请验证游戏文件完整性。";
                case "embed_timeout":
                    return "Flash 窗口未能嵌入启动器。请重试一次；如果持续发生，请检查是否启用了特殊兼容性/窗口管理工具。";
                case "game_ready_timeout":
                    return "Flash 已嵌入但游戏未回报就绪。请重试一次；如果持续发生，请验证 SWF 与数据文件完整性。";
                case "flash_exited_pre_reveal":
                case "flash_exited":
                    return "Flash 在进入游戏前退出或崩溃。请重试一次；如果仍失败，请验证游戏文件完整性并发送诊断包。";
                default:
                    return "请先点击重试；如果问题持续存在，请把诊断包发给开发组。";
            }
        }

        public static void ShowReportDialog(IWin32Window owner, StartupFailureReport report)
        {
            ShowDialog(owner, report);
        }

        private static void ShowDialog(IWin32Window owner, StartupFailureReport report)
        {
            if (report == null) return;
            try
            {
                using (StartupFailureDialog dialog = new StartupFailureDialog(report))
                {
                    if (owner != null)
                        dialog.ShowDialog(owner);
                    else
                        dialog.ShowDialog();
                }
            }
            catch (Exception ex)
            {
                try
                {
                    MessageBox.Show(report.BuildDialogBody() + "\r\n\r\n弹窗渲染失败: " + ex.Message,
                        "CF7:ME - " + report.Title,
                        MessageBoxButtons.OK,
                        MessageBoxIcon.Error);
                }
                catch { }
            }
        }

        private static string NormalizeRoot(string projectRoot)
        {
            if (string.IsNullOrWhiteSpace(projectRoot)) return null;
            try { return Path.GetFullPath(projectRoot).TrimEnd('\\', '/'); }
            catch { return projectRoot; }
        }

        private static void WriteSummaryFile(StartupFailureReport report)
        {
            if (report == null || string.IsNullOrEmpty(report.SummaryPath)) return;
            try
            {
                File.WriteAllText(report.SummaryPath, report.BuildClipboardText(), new UTF8Encoding(false));
            }
            catch { }
        }

        private sealed class StartupFailureDialog : Form
        {
            private readonly StartupFailureReport _report;

            public StartupFailureDialog(StartupFailureReport report)
            {
                _report = report;
                Text = "CF7:ME - 启动诊断";
                StartPosition = FormStartPosition.CenterParent;
                FormBorderStyle = FormBorderStyle.FixedDialog;
                MinimizeBox = false;
                MaximizeBox = false;
                ShowIcon = false;
                ClientSize = new Size(680, 420);

                Label title = new Label();
                title.AutoSize = false;
                title.Text = report.Title;
                title.Font = new Font(Font.FontFamily, 12.5f, FontStyle.Bold);
                title.Location = new Point(18, 16);
                title.Size = new Size(ClientSize.Width - 36, 30);

                TextBox body = new TextBox();
                body.Multiline = true;
                body.ReadOnly = true;
                body.ScrollBars = ScrollBars.Vertical;
                body.BorderStyle = BorderStyle.FixedSingle;
                body.Text = report.BuildDialogBody();
                body.Location = new Point(18, 54);
                body.Size = new Size(ClientSize.Width - 36, 280);
                body.Anchor = AnchorStyles.Left | AnchorStyles.Top | AnchorStyles.Right | AnchorStyles.Bottom;

                Button copy = NewButton("复制摘要", 18);
                copy.Click += delegate { CopySummary(); };

                Button open = NewButton(report.PackageOk ? "打开报告位置" : "打开日志目录", 122);
                open.Click += delegate { OpenReportLocation(); };

                Button close = NewButton("关闭", ClientSize.Width - 18 - 92);
                close.Anchor = AnchorStyles.Right | AnchorStyles.Bottom;
                close.Click += delegate { Close(); };

                Controls.Add(title);
                Controls.Add(body);
                Controls.Add(copy);
                Controls.Add(open);
                Controls.Add(close);
                AcceptButton = close;
                CancelButton = close;
            }

            private Button NewButton(string text, int x)
            {
                Button b = new Button();
                b.Text = text;
                b.Size = new Size(92, 30);
                b.Location = new Point(x, ClientSize.Height - 46);
                b.Anchor = AnchorStyles.Left | AnchorStyles.Bottom;
                return b;
            }

            private void CopySummary()
            {
                try
                {
                    Clipboard.SetText(_report.BuildClipboardText());
                    LogManager.Log("[StartupFailure] copied summary code=" + _report.Code);
                }
                catch (Exception ex)
                {
                    LogManager.Log("[StartupFailure] copy summary failed: " + ex.Message);
                    MessageBox.Show(this, "复制失败: " + ex.Message,
                        "CF7:ME - 启动诊断", MessageBoxButtons.OK, MessageBoxIcon.Warning);
                }
            }

            private void OpenReportLocation()
            {
                try
                {
                    if (_report.PackageOk && !string.IsNullOrEmpty(_report.ZipPath) && File.Exists(_report.ZipPath))
                    {
                        Process.Start("explorer.exe", "/select,\"" + _report.ZipPath + "\"");
                        return;
                    }
                    if (!string.IsNullOrEmpty(_report.LogsDir) && Directory.Exists(_report.LogsDir))
                    {
                        Process.Start("explorer.exe", "\"" + _report.LogsDir + "\"");
                        return;
                    }
                }
                catch (Exception ex)
                {
                    LogManager.Log("[StartupFailure] open report location failed: " + ex.Message);
                    MessageBox.Show(this, "打开失败: " + ex.Message,
                        "CF7:ME - 启动诊断", MessageBoxButtons.OK, MessageBoxIcon.Warning);
                }
            }
        }
    }
}
