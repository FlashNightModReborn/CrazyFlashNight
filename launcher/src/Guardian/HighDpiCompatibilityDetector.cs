using System;
using System.Drawing;
using System.Windows.Forms;
using Microsoft.Win32;

namespace CF7Launcher.Guardian
{
    public sealed class HighDpiCompatibilityResult
    {
        public string RawValue;
        public string Source;
        public bool IsApplicationOverride;
        public bool IsRiskyOverride;
        public string RiskReason;

        public string Describe()
        {
            return "source=" + (Source ?? "none")
                + " appOverride=" + IsApplicationOverride
                + " risky=" + IsRiskyOverride
                + " reason=" + (RiskReason ?? "")
                + " raw=" + (RawValue ?? "");
        }
    }

    public static class HighDpiCompatibilityDetector
    {
        private const string LayersPath = @"Software\Microsoft\Windows NT\CurrentVersion\AppCompatFlags\Layers";
        private static bool _warningShown;

        public static HighDpiCompatibilityResult Detect(string exePath)
        {
            HighDpiCompatibilityResult result = new HighDpiCompatibilityResult();
            if (string.IsNullOrEmpty(exePath))
                return result;

            string raw;
            string source;
            if (TryReadLayerValue(Registry.CurrentUser, "HKCU", exePath, out raw, out source) ||
                TryReadLayerValue(Registry.LocalMachine, "HKLM", exePath, out raw, out source))
            {
                result.RawValue = raw;
                result.Source = source;
                string upper = (raw ?? "").ToUpperInvariant();
                result.IsApplicationOverride = upper.IndexOf("HIGHDPIAWARE", StringComparison.Ordinal) >= 0
                    && upper.IndexOf("DPIUNAWARE", StringComparison.Ordinal) < 0
                    && upper.IndexOf("GDIDPISCALING", StringComparison.Ordinal) < 0;
                result.IsRiskyOverride = upper.IndexOf("DPIUNAWARE", StringComparison.Ordinal) >= 0
                    || upper.IndexOf("GDIDPISCALING", StringComparison.Ordinal) >= 0;
                if (result.IsRiskyOverride)
                    result.RiskReason = "Windows compatibility scaling is forcing System/System Enhanced behavior";
                else if (result.IsApplicationOverride)
                    result.RiskReason = "Application DPI override is supported";
                return result;
            }

            result.Source = "none";
            result.RawValue = "";
            return result;
        }

        public static void ScheduleRiskWarning(Form owner, HighDpiCompatibilityResult result)
        {
            if (owner == null || result == null || !result.IsRiskyOverride || _warningShown)
                return;
            _warningShown = true;

            Action show = delegate
            {
                try
                {
                    Form dialog = new Form();
                    dialog.Text = "CF7:ME - 高 DPI 兼容性提示";
                    dialog.StartPosition = FormStartPosition.CenterParent;
                    dialog.FormBorderStyle = FormBorderStyle.FixedDialog;
                    dialog.MaximizeBox = false;
                    dialog.MinimizeBox = false;
                    dialog.ShowInTaskbar = false;
                    dialog.AutoScaleMode = AutoScaleMode.None;
                    dialog.ClientSize = new Size(560, 220);

                    Label label = new Label();
                    label.AutoSize = false;
                    label.Location = new Point(18, 16);
                    label.Size = new Size(524, 150);
                    label.Text =
                        "检测到当前 EXE 启用了 Windows 高 DPI 缩放替代的“系统/系统(增强)”模式。\r\n\r\n"
                        + "这会让 Windows 接管像素缩放，Launcher 的 WebView2 覆盖层和鼠标命中区域可能无法保持像素级对齐。\r\n\r\n"
                        + "正式支持的设置是：不勾选高 DPI 缩放替代，或勾选后选择“应用程序”。\r\n\r\n"
                        + "当前兼容性值: " + (result.RawValue ?? "");

                    Button ok = new Button();
                    ok.Text = "知道了";
                    ok.Size = new Size(88, 28);
                    ok.Location = new Point(dialog.ClientSize.Width - ok.Width - 18,
                        dialog.ClientSize.Height - ok.Height - 16);
                    ok.Anchor = AnchorStyles.Right | AnchorStyles.Bottom;
                    ok.Click += delegate { dialog.Close(); };

                    dialog.Controls.Add(label);
                    dialog.Controls.Add(ok);
                    dialog.AcceptButton = ok;
                    dialog.Show(owner);
                }
                catch { }
            };

            if (owner.IsHandleCreated)
            {
                try { owner.BeginInvoke(show); }
                catch { show(); }
            }
            else
            {
                owner.HandleCreated += delegate
                {
                    try { owner.BeginInvoke(show); }
                    catch { show(); }
                };
            }
        }

        private static bool TryReadLayerValue(RegistryKey root, string rootName, string exePath, out string raw, out string source)
        {
            raw = null;
            source = null;
            try
            {
                using (RegistryKey key = root.OpenSubKey(LayersPath))
                {
                    if (key == null)
                        return false;
                    object value = key.GetValue(exePath);
                    if (value == null)
                        return false;
                    raw = Convert.ToString(value);
                    source = rootName + "\\" + LayersPath;
                    return true;
                }
            }
            catch
            {
                return false;
            }
        }
    }
}
