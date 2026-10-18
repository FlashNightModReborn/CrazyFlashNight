using System;
using System.Collections.Generic;
using System.Drawing;
using System.IO;
using System.Runtime.ExceptionServices;
using System.Text;
using System.Threading;
using System.Threading.Tasks;
using System.Windows.Forms;
using CF7Launcher.Guardian;
using CF7Launcher.Guardian.Hud;
using Xunit;

namespace CF7Launcher.Tests.Guardian
{
    /// <summary>
    /// P0.5：owner 失活白名单。只放行"插话输入浮窗是本会话前台"这一种情形；
    /// 其他窗口（切到别的程序）仍走原有隐藏，其他 overlay 完全不受影响。
    ///
    /// 只验证状态机与钩子（_ownerVisible / OnOwnerBecameHidden），不冒充窗口 z-order
    /// 或真机 IME —— 那些由作者进游戏验收。
    /// </summary>
    public sealed class NativeHudInterjectFocusTests
    {
        private static void RunOnSta(Action body)
        {
            Exception failure = null;
            var worker = new Thread(() =>
            {
                try { body(); }
                catch (Exception ex) { failure = ex; }
            });
            worker.SetApartmentState(ApartmentState.STA);
            worker.Start();
            Assert.True(worker.Join(TimeSpan.FromSeconds(30)), "STA body did not finish");
            if (failure != null) ExceptionDispatchInfo.Capture(failure).Throw();
        }

        private sealed class ProbeOverlay : OverlayBase
        {
            internal int HiddenHooks;
            internal int DeactivatedVisibilityHooks;

            internal ProbeOverlay(Form owner, Control anchor)
                : base(owner, anchor, 800f, 450f)
            {
            }

            protected override void OnOwnerBecameHidden() { HiddenHooks++; }

            protected override void OnOwnerVisibilityChanged(bool ownerVisible)
            {
                if (!ownerVisible) DeactivatedVisibilityHooks++;
            }
        }

        private sealed class ProbeHud : NativeHudOverlay
        {
            internal int HiddenHooks;
            internal int DeactivatedVisibilityHooks;

            internal ProbeHud(Form owner, Control anchor) : base(owner, anchor)
            {
            }

            protected override void OnOwnerBecameHidden() { HiddenHooks++; }

            protected override void OnOwnerVisibilityChanged(bool ownerVisible)
            {
                if (!ownerVisible) DeactivatedVisibilityHooks++;
            }
        }

        private static Form NewOwner()
        {
            return new Form
            {
                ClientSize = new Size(1024, 576),
                Location = new Point(-20000, -20000),
                StartPosition = FormStartPosition.Manual
            };
        }

        [Fact]
        public void WhitelistedInputForegroundSkipsOwnerDeactivationHide()
        {
            RunOnSta(() =>
            {
                using (Form owner = NewOwner())
                {
                    var anchor = new Panel { Dock = DockStyle.Fill };
                    owner.Controls.Add(anchor);
                    owner.Show();
                    using (var hud = new ProbeHud(owner, anchor))
                    {
                        hud.InterjectInputForegroundProbe = () => true;
                        hud.HandleOwnerDeactivated();

                        Assert.True(hud.OwnerVisibleForTest);      // 不置 false
                        Assert.Equal(0, hud.HiddenHooks);          // 不触发 OnOwnerBecameHidden
                        Assert.Equal(0, hud.DeactivatedVisibilityHooks);
                    }
                }
            });
        }

        [Fact]
        public void OtherWindowForegroundStillHidesHud()
        {
            RunOnSta(() =>
            {
                using (Form owner = NewOwner())
                {
                    var anchor = new Panel { Dock = DockStyle.Fill };
                    owner.Controls.Add(anchor);
                    owner.Show();
                    using (var hud = new ProbeHud(owner, anchor))
                    {
                        hud.InterjectInputForegroundProbe = () => false;   // 前台是别的窗口
                        hud.HandleOwnerDeactivated();

                        Assert.False(hud.OwnerVisibleForTest);
                        Assert.Equal(1, hud.HiddenHooks);
                        Assert.Equal(1, hud.DeactivatedVisibilityHooks);
                    }
                }
            });
        }

        [Fact]
        public void UnregisteredOrFaultyProbeFallsBackToLegacyHide()
        {
            RunOnSta(() =>
            {
                using (Form owner = NewOwner())
                {
                    var anchor = new Panel { Dock = DockStyle.Fill };
                    owner.Controls.Add(anchor);
                    owner.Show();
                    using (var hud = new ProbeHud(owner, anchor))
                    {
                        hud.HandleOwnerDeactivated();          // 未注册探针
                        Assert.False(hud.OwnerVisibleForTest);
                        Assert.Equal(1, hud.HiddenHooks);

                        hud.InterjectInputForegroundProbe = () => { throw new InvalidOperationException("probe"); };
                        hud.HandleOwnerDeactivated();          // 探针异常也要按原行为隐藏
                        Assert.Equal(2, hud.HiddenHooks);
                    }
                }
            });
        }

        [Fact]
        public void NonInterjectOverlayKeepsOriginalDeactivateBehavior()
        {
            RunOnSta(() =>
            {
                using (Form owner = NewOwner())
                {
                    var anchor = new Panel { Dock = DockStyle.Fill };
                    owner.Controls.Add(anchor);
                    owner.Show();
                    using (var overlay = new ProbeOverlay(owner, anchor))
                    {
                        overlay.HandleOwnerDeactivated();
                        Assert.False(overlay.OwnerVisibleForTest);
                        Assert.Equal(1, overlay.HiddenHooks);
                        Assert.Equal(1, overlay.DeactivatedVisibilityHooks);
                    }
                }
            });
        }

        [Fact]
        public void InputOverlayTextStateTracksFocusAndDismiss()
        {
            RunOnSta(() =>
            {
                using (Form owner = NewOwner())
                {
                    var anchor = new Panel { Dock = DockStyle.Fill };
                    owner.Controls.Add(anchor);
                    owner.Show();
                    var overlay = new CF7Launcher.Guardian.Hud.Dialogue.DialogueInterjectInputOverlay();
                    overlay.AttachOwner(owner);
                    try
                    {
                        Assert.Same(owner, overlay.Owner);
                        Assert.False(overlay.IsTextInputActive());

                        // 焦点事件是热键放行的唯一来源：聚焦/失焦必须成对翻转
                        overlay.SetFocused(true);
                        Assert.True(overlay.IsTextInputActive());
                        overlay.SetFocused(false);
                        Assert.False(overlay.IsTextInputActive());

                        overlay.SetFocused(true);
                        overlay.DismissToOwner();
                        Assert.False(overlay.IsTextInputActive());   // 收起必须清掉文字输入态
                    }
                    finally
                    {
                        overlay.Dispose();
                    }
                }
            });
        }
    }
}
