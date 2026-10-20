using System;
using System.Drawing;
using System.Windows.Forms;
using CF7Launcher.Tasks;

namespace CF7Launcher.Guardian.Hud.Dialogue
{
    /// <summary>
    /// 插话输入浮窗的宿主适配：把控制器的输入状态映射成"显示/隐藏 + 可用/禁用"。
    ///
    /// 布局跟随对话面板（不是整窗右上角）：
    /// - 收起态：关闭钮左侧一个箭头按钮，默认不展开；
    /// - 展开态：从该按钮向上展开输入面板，右沿始终停在关闭钮左侧；
    /// - 两者都不覆盖关闭钮、正文与"下一条"热区。
    /// </summary>
    internal sealed class DialogueInterjectInputBinder : IDisposable
    {
        private readonly Form _owner;
        private readonly NativeDialogueWidget _widget;
        private readonly DialogueInterjectInputOverlay _overlay;
        private readonly Action _overlayLayoutHandler;
        private readonly EventHandler _panelLayoutHandler;
        private readonly EventHandler _ownerLayoutHandler;
        private bool _disposed;

        internal DialogueInterjectInputBinder(Form owner, NativeDialogueWidget widget,
            DialogueInterjectInputOverlay overlay)
        {
            _owner = owner ?? throw new ArgumentNullException(nameof(owner));
            _widget = widget ?? throw new ArgumentNullException(nameof(widget));
            _overlay = overlay ?? throw new ArgumentNullException(nameof(overlay));
            _overlayLayoutHandler = delegate { if (_overlay.Visible) Position(); };
            _panelLayoutHandler = delegate { if (_overlay.Visible) Position(); };
            _ownerLayoutHandler = delegate { if (_overlay.Visible) Position(); };
            _overlay.ExpandedChanged += _overlayLayoutHandler;
            _widget.BoundsOrVisibilityChanged += _panelLayoutHandler;
            _owner.Resize += _ownerLayoutHandler;
            _owner.ClientSizeChanged += _ownerLayoutHandler;
        }

        internal DialogueInterjectInputOverlay Overlay { get { return _overlay; } }

        /// <summary>输入状态变化：Hidden=收起并还焦点；Offline=终端未启动（禁言样式+启动）；
        /// NeedsConfig=终端就绪但缺模型配置（禁言样式+配置）；Locked/Preparing/Muted=收起条禁用提示；
        /// Ready=收起条可用，点击展开输入。</summary>
        internal void Apply(DialogueInterjectInputState state, string placeholder = null)
        {
            if (_disposed) return;
            switch (state)
            {
                case DialogueInterjectInputState.Hidden:
                    _overlay.SetStartRequired(false);
                    _overlay.SetConfigRequired(false);
                    if (_overlay.Visible) _overlay.DismissToOwner();
                    break;
                case DialogueInterjectInputState.Offline:
                    _overlay.SetConfigRequired(false);
                    _overlay.SetInputEnabled(false);
                    _overlay.SetStartRequired(true);
                    _overlay.SetPlaceholder(string.IsNullOrEmpty(placeholder)
                        ? "请先启动聊天终端" : placeholder);
                    ShowPassive();
                    break;
                case DialogueInterjectInputState.NeedsConfig:
                    _overlay.SetStartRequired(false);
                    _overlay.SetInputEnabled(false);
                    _overlay.SetConfigRequired(true);
                    _overlay.SetPlaceholder(string.IsNullOrEmpty(placeholder)
                        ? "请配置模型API" : placeholder);
                    ShowPassive();
                    break;
                case DialogueInterjectInputState.Locked:
                    _overlay.SetStartRequired(false);
                    _overlay.SetConfigRequired(false);
                    _overlay.SetInputEnabled(false);
                    _overlay.SetPlaceholder("……");
                    ShowPassive();
                    break;
                case DialogueInterjectInputState.Preparing:
                    _overlay.SetStartRequired(false);
                    _overlay.SetConfigRequired(false);
                    _overlay.SetInputEnabled(false);
                    _overlay.SetPlaceholder("（正在准备…）");
                    ShowPassive();
                    break;
                case DialogueInterjectInputState.Muted:
                    _overlay.SetStartRequired(false);
                    _overlay.SetConfigRequired(false);
                    _overlay.SetInputEnabled(false);
                    _overlay.SetPlaceholder(string.IsNullOrEmpty(placeholder)
                        ? "暂时不打算让你插话" : placeholder);
                    ShowPassive();
                    break;
                case DialogueInterjectInputState.Ready:
                    _overlay.SetStartRequired(false);
                    _overlay.SetConfigRequired(false);
                    _overlay.SetInputEnabled(true);
                    _overlay.SetPlaceholder("说点什么…");
                    ShowPassive();
                    break;
            }
        }

        private void ShowPassive()
        {
            Position();
            if (!_overlay.Visible) _overlay.Show();   // ShowWithoutActivation：不抢前台
        }

        /// <summary>收起箭头与展开面板都停在关闭钮左侧；展开面板从箭头向上长出，边界内收。</summary>
        internal void Position()
        {
            if (_overlay == null || _owner == null) return;
            Rectangle panel;
            Rectangle close;
            float scale;
            if (!_widget.TryGetInterjectInputAnchor(out panel, out close, out scale)) return;
            Rectangle viewport = _owner.RectangleToScreen(_owner.ClientRectangle);
            if (viewport.Width <= 0 || viewport.Height <= 0) return;
            int pad = DialogueInterjectInputOverlay.OuterPaddingForScale(scale);
            int rightLimit = close.IsEmpty ? panel.Right : close.Left;

            // 两态共用同一尺寸；展开态不再按自身画布重推，避免一大一小。
            int toggleW = DialogueInterjectInputOverlay.ToggleWidthForScale(scale);
            int toggleH = DialogueInterjectInputOverlay.ToggleHeightForScale(scale);
            _overlay.SetToggleMetrics(toggleW, toggleH, pad);
            int collapsedX = rightLimit - pad - toggleW;
            // 收起钮下沿贴住对话框黑色头条上沿，不再悬在关闭钮垂直中线。
            int collapsedY = panel.Top - toggleH;

            int width;
            int height;
            int x;
            int y;
            if (_overlay.IsExpanded)
            {
                width = Clamp((int)Math.Round(panel.Width * 0.47), 380, 660);
                height = Clamp((int)Math.Round(
                    DialogueInterjectInputOverlay.DesignHeight * scale), 170, 340);
                // 面板右沿贴关闭钮左界，内部再留 pad；这样展开态的箭头右沿
                // 与收起态箭头右沿落在同一条线上。
                x = rightLimit - width;
                int bottom = collapsedY + toggleH;   // 展开面板底边与对话框头条上沿重合
                y = bottom - height;
                if (y < viewport.Top) y = viewport.Top;
            }
            else
            {
                width = toggleW;
                height = toggleH;
                x = collapsedX;
                y = collapsedY;
            }

            if (x < viewport.Left) x = viewport.Left;
            if (y < viewport.Top) y = viewport.Top;
            if (x + width > viewport.Right) x = viewport.Right - width;
            if (y + height > viewport.Bottom) y = viewport.Bottom - height;
            // 位置被视口推回时仍尽量不压关闭钮。
            if (!close.IsEmpty && x + width > rightLimit)
                x = Math.Max(viewport.Left, rightLimit - width);
            _overlay.Bounds = new Rectangle(x, y, width, height);
        }

        private static int Clamp(int value, int min, int max)
        {
            if (value < min) return min;
            if (value > max) return max;
            return value;
        }

        public void Dispose()
        {
            if (_disposed) return;
            _disposed = true;
            try { _overlay.ExpandedChanged -= _overlayLayoutHandler; } catch { }
            try { _widget.BoundsOrVisibilityChanged -= _panelLayoutHandler; } catch { }
            try { _owner.Resize -= _ownerLayoutHandler; } catch { }
            try { _owner.ClientSizeChanged -= _ownerLayoutHandler; } catch { }
            try { _overlay.DismissToOwner(); } catch { }
        }
    }
}
