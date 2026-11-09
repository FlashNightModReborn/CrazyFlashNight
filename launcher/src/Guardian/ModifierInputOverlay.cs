using System;
using System.Drawing;
using System.Windows.Forms;

namespace CF7Launcher.Guardian
{
    internal sealed class ModifierInputOverlay : Form
    {
        internal ModifierInputOverlay(Form owner)
        {
            FormBorderStyle = FormBorderStyle.None;
            ShowInTaskbar = false;
            StartPosition = FormStartPosition.Manual;
            AutoScaleMode = AutoScaleMode.None;
            BackColor = Color.Magenta;
            TransparencyKey = Color.Magenta;
            Owner = owner;
        }

        protected override bool ShowWithoutActivation { get { return true; } }

        protected override CreateParams CreateParams
        {
            get
            {
                CreateParams cp = base.CreateParams;
                cp.ExStyle |= 0x00000080 | 0x08000000;
                return cp;
            }
        }

        internal void Sync(bool visible, Rectangle bounds)
        {
            Bounds = bounds;
            if (visible && !Visible) Show();
            else if (!visible && Visible) Hide();
        }
    }
}
