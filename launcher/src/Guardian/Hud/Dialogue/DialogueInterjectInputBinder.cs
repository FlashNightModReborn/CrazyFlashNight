using System;
using System.Drawing;
using System.Windows.Forms;
using CF7Launcher.Tasks;

namespace CF7Launcher.Guardian.Hud.Dialogue
{
    /// <summary>
    /// 插话输入浮窗的宿主适配（P1）：把控制器的输入状态映射成"显示/隐藏 + 可用/禁用"，
    /// 并把浮窗贴在对话面板正下方（不遮正文、不压“下一条”热区）。
    ///
    /// 只由宿主接线使用（dialogueInterjectEnabled）；控制器本身不认识控件，
    /// 单测直接对状态流断言，不构造窗口。
    /// </summary>
    internal sealed class DialogueInterjectInputBinder : IDisposable
    {
        private readonly Form _owner;
        private readonly NativeDialogueWidget _widget;
        private readonly DialogueInterjectInputOverlay _overlay;
        private readonly EventHandler _boundsHandler;
        private bool _disposed;

        internal DialogueInterjectInputBinder(Form owner, NativeDialogueWidget widget,
            DialogueInterjectInputOverlay overlay)
        {
            _owner = owner ?? throw new ArgumentNullException(nameof(owner));
            _widget = widget ?? throw new ArgumentNullException(nameof(widget));
            _overlay = overlay ?? throw new ArgumentNullException(nameof(overlay));
            _boundsHandler = delegate { if (_overlay.Visible) Position(); };
            _widget.BoundsOrVisibilityChanged += _boundsHandler;
        }

        internal DialogueInterjectInputOverlay Overlay { get { return _overlay; } }

        /// <summary>输入状态变化：Hidden=收起并还焦点；Locked=显示禁用（“……”）；
        /// Preparing=显示禁用（“（正在准备…）”，草案/检索中）；Ready=可用。</summary>
        internal void Apply(DialogueInterjectInputState state)
        {
            if (_disposed) return;
            switch (state)
            {
                case DialogueInterjectInputState.Hidden:
                    if (_overlay.Visible) _overlay.DismissToOwner();
                    break;
                case DialogueInterjectInputState.Locked:
                    ShowPassive();
                    _overlay.SetInputEnabled(false);
                    _overlay.SetPlaceholder("……");
                    break;
                case DialogueInterjectInputState.Preparing:
                    ShowPassive();
                    _overlay.SetInputEnabled(false);
                    _overlay.SetPlaceholder("（正在准备…）");
                    break;
                case DialogueInterjectInputState.Ready:
                    ShowPassive();
                    _overlay.SetInputEnabled(true);
                    _overlay.SetPlaceholder("说点什么…");
                    break;
            }
        }

        private void ShowPassive()
        {
            Position();
            if (!_overlay.Visible) _overlay.Show();   // ShowWithoutActivation：不抢前台
        }

        /// <summary>贴在面板下沿；越出窗体客户区时上移，不夹到左右角落。</summary>
        internal void Position()
        {
            if (_overlay == null || _owner == null) return;
            Rectangle panel;
            float scale;
            if (!_widget.TryGetInterjectInputAnchor(out panel, out scale)) return;
            Rectangle viewport = _owner.RectangleToScreen(_owner.ClientRectangle);
            if (viewport.Width <= 0 || viewport.Height <= 0) return;
            int height = Math.Max(24, (int)Math.Round(34 * scale));
            int width = Math.Max(160, panel.Width);
            int gap = Math.Max(2, (int)Math.Round(6 * scale));
            int x = panel.Left;
            int y = panel.Bottom + gap;
            if (x + width > viewport.Right) x = viewport.Right - width;
            if (x < viewport.Left) x = viewport.Left;
            if (y + height > viewport.Bottom) y = viewport.Bottom - height;
            if (y < viewport.Top) y = viewport.Top;
            _overlay.Bounds = new Rectangle(x, y, width, height);
        }

        public void Dispose()
        {
            if (_disposed) return;
            _disposed = true;
            try { _widget.BoundsOrVisibilityChanged -= _boundsHandler; } catch { }
            try { _overlay.DismissToOwner(); } catch { }
        }
    }
}
