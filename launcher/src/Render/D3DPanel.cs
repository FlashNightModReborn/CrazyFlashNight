// Double-buffered display panel for GPU post-processed frames.
// In GPU mode it paints the latest readback bitmap; in fallback mode it can
// still act as the parent panel for the embedded Flash window.

using System.Drawing;
using System.Windows.Forms;

namespace CF7Launcher.Render
{
    class D3DPanel : Panel
    {
        public GpuRenderer Renderer { get; set; }

        public D3DPanel()
        {
            SetStyle(ControlStyles.OptimizedDoubleBuffer
                   | ControlStyles.AllPaintingInWmPaint
                   | ControlStyles.UserPaint
                   | ControlStyles.Selectable, true);
            DoubleBuffered = true;
            TabStop = true;
            BackColor = Color.Black;
        }

        protected override void OnPaint(PaintEventArgs e)
        {
            e.Graphics.Clear(BackColor);
            if (Renderer != null)
                Renderer.DrawOutput(e.Graphics, ClientRectangle);
        }

        protected override void OnPaintBackground(PaintEventArgs e)
        {
            e.Graphics.Clear(BackColor);
        }

        protected override bool IsInputKey(Keys keyData)
        {
            return true;
        }
    }
}
