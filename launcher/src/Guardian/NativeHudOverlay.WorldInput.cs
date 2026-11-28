using System;
using System.Drawing;
using System.Reflection;
using System.Threading;
using System.Windows.Forms;
using CF7Launcher.Guardian.Hud;
using CF7Launcher.Guardian.Hud.Dialogue;
using CF7Launcher.Guardian.Hud.PlayerInfo;
using CF7Launcher.Guardian.Hud.Tooltip;
using CF7Launcher.Guardian.InputOwnership;
using CF7Launcher.Guardian.WorldCompositor;

namespace CF7Launcher.Guardian;

public partial class NativeHudOverlay
{
    private IUiPointerAuthority _worldPointerAuthority;
    private MainHudInput _mainHudWorldInput;
    private MainHudInput _fallbackHudInput;
    private static long _nextPointerInstance;
    internal long PointerInstanceGeneration { get; } = Interlocked.Increment(ref _nextPointerInstance);

    internal void BindPointerAuthority(IUiPointerAuthority pointerAuthority)
    {
        if (ReferenceEquals(_worldPointerAuthority, pointerAuthority)) return;
        CancelPointerGesture("hud_pointer_authority_changed");
        _worldPointerAuthority = pointerAuthority;
    }

    private bool FallbackPointerAvailable => _sharedPresentation == null && _ready && _shown
        && !_suspendedForPanel && !FrontDoorVisible && IsHandleCreated && !Disposing && !IsDisposed;

    private MainHudInput FallbackHudInput => _fallbackHudInput ??=
        new MainHudInput(this, _anchor, () => FallbackPointerAvailable);

    internal bool OwnsBoundFallbackPointer(Form owner) => ReferenceEquals(_owner, owner)
        && _worldPointerAuthority != null && FallbackPointerAvailable;

    internal bool HasBoundFallbackPress => _sharedPresentation == null && _fallbackHudInput?.IsPressed == true;

    internal bool TryRouteBoundFallbackWheel(Point screen, int delta)
    {
        if (_worldPointerAuthority == null || !FallbackPointerAvailable) return false;
        var input = FallbackHudInput;
        var hit = input.HitTestWheel(screen);
        if (hit == null) return false;
        try { input.Dispatch(0x20A, screen, (uint)(ushort)delta << 16, hit); }
        catch (Exception error) { LogManager.Log("[NativeHud] fallback wheel failed: " + error.Message); }
        return true;
    }

    internal bool HasPinnedTooltip()
    {
        lock (_widgetsLock)
            return _widgets.Exists(widget => widget is NativeTooltipWidget tooltip
                && tooltip.ActiveDocument?.Profile == NativeTooltipProfile.Pinned);
    }

    internal bool TryRouteBoundNpcOutside(Point screen, int button, Action ownRelease, Action dismiss)
    {
        var authority = _worldPointerAuthority;
        if (authority == null) return false;
        NpcMenuWidget menu;
        lock (_widgetsLock) menu = _widgets.Find(widget => widget is NpcMenuWidget) as NpcMenuWidget;
        if (menu == null || !menu.Visible) return false;
        Rectangle bounds = menu.ScreenBounds;
        if (bounds.Width <= 0 || bounds.Height <= 0 || bounds.Contains(screen)) return false;
        ownRelease();
        if (!(SharedInputAvailable || FallbackPointerAvailable)) return true;

        const string endpoint = "hud.main.npc.outside";
        object session = menu.CapturePointerTarget(bounds.Location);
        if (session == null || !HudPointerClaim.TryBegin(authority, endpoint, PointerInstanceGeneration,
            button, screen, endpoint, out var claim)) return true;
        if (!claim.Value.CanCommit || !Equals(session, menu.CapturePointerTarget(bounds.Location)))
        {
            claim.Value.Cancel("hud_npc_outside_stale");
            return true;
        }
        bool committed = false;
        try
        {
            dismiss();
            committed = true;
        }
        catch (Exception error) { LogManager.Log("[NativeHud] outside dismiss failed: " + error.Message); }
        finally { claim.Value.End(committed); }
        return true;
    }

    private static readonly FieldInfo NotchExpandRectField =
        typeof(NotchWidget).GetField("_expandButtonRect", BindingFlags.Instance | BindingFlags.NonPublic);
    private static readonly FieldInfo NotchAnchorField =
        typeof(NotchWidget).GetField("_anchor", BindingFlags.Instance | BindingFlags.NonPublic);
    private static readonly FieldInfo NotchStateField =
        typeof(NotchWidget).GetField("_state", BindingFlags.Instance | BindingFlags.NonPublic);

    internal IWorldHudInput CreateWorldInput(Control anchor)
    {
        _mainHudWorldInput?.Cancel();
        return _mainHudWorldInput = new MainHudInput(this, anchor, () => SharedInputAvailable);
    }

    internal bool ProbeClickExpandButton()
    {
        if (_notchWidget == null || !_notchWidget.Visible || _worldPointerAuthority == null || _suspendedForPanel)
            return false;
        var anchor = NotchAnchorField?.GetValue(_notchWidget) as Control;
        if (anchor == null || !anchor.IsHandleCreated) return false;
        Rectangle bounds = _notchWidget.ScreenBounds;
        if (bounds.Width <= 0 || bounds.Height <= 0) return false;
        if (NotchExpandRectField?.GetValue(_notchWidget) is Rectangle rect0 && rect0.Width <= 0)
        {
            using var bmp = new Bitmap(Math.Max(1, bounds.Width), Math.Max(1, bounds.Height));
            using var g = Graphics.FromImage(bmp);
            _notchWidget.Paint(g, 1f, bounds.Location);
        }
        if (NotchExpandRectField?.GetValue(_notchWidget) is not Rectangle local || local.Width <= 0 || local.Height <= 0)
            return false;
        Point center = new Point(bounds.X + local.X + local.Width / 2, bounds.Y + local.Y + local.Height / 2);
        var router = new MainHudInput(this, anchor, () => !_suspendedForPanel);
        object hoverTarget = router.HitTest(center);
        if (hoverTarget == null) return false;
        router.Dispatch(0x200, center, 0, hoverTarget);
        Rectangle boundsAfterHover = _notchWidget.ScreenBounds;
        if (boundsAfterHover.Width > 0 && boundsAfterHover.Height > 0 &&
            NotchExpandRectField?.GetValue(_notchWidget) is Rectangle rectAfter && rectAfter.Width <= 0)
        {
            using var bmpHover = new Bitmap(Math.Max(1, boundsAfterHover.Width), Math.Max(1, boundsAfterHover.Height));
            using var gHover = Graphics.FromImage(bmpHover);
            _notchWidget.Paint(gHover, 1f, boundsAfterHover.Location);
        }
        if (NotchExpandRectField?.GetValue(_notchWidget) is Rectangle localNow && localNow.Width > 0 && localNow.Height > 0)
        {
            center = new Point(boundsAfterHover.X + localNow.X + localNow.Width / 2,
                boundsAfterHover.Y + localNow.Y + localNow.Height / 2);
        }
        object target = router.HitTest(center);
        if (target == null) return false;
        object before = NotchStateField?.GetValue(_notchWidget);
        router.Dispatch(0x201, center, 0, target);
        object upTarget = router.RetainPointerTarget(target, center) ?? router.HitTest(center);
        router.Dispatch(0x202, center, 0, upTarget);
        object after = NotchStateField?.GetValue(_notchWidget);
        router.Dispatch(0x2A3, Point.Empty, 0, null);
        return before != null && after != null && !Equals(before, after);
    }

    internal sealed class MainHudInput : IWorldHudInput
    {
        private readonly NativeHudOverlay _hud;
        private readonly Control _anchor;
        private readonly Func<bool> _available;
        private sealed record Hit(INativeHudWidget Widget, object Action, long Generation, Rectangle Viewport, bool Wheel);
        private Hit _down, _capture;
        private INativeHudWidget _hover;
        private const string ExpandTarget = "hud.notch.expand";
        private HudPointerClaim? _claim;
        internal bool IsPressed => _down != null;

        // Preserve the original probe endpoint for the Notch expand action.
        private static class NotchAction
        {
            internal static readonly FieldInfo Kind = typeof(NotchWidget)
                .GetNestedType("PointerActionToken", BindingFlags.NonPublic)?.GetField("Kind");
            internal static readonly object Expand = Kind?.FieldType.GetField("ExpandButton")?.GetValue(null);
        }
        internal MainHudInput(NativeHudOverlay hud, Control anchor, Func<bool> available)
        {
            _hud = hud;
            _anchor = anchor;
            _available = available;
        }
        private Rectangle Viewport => _anchor.RectangleToScreen(_anchor.ClientRectangle);

        public object HitTest(Point screen)
        {
            if (!_available()) return null;
            if (_capture != null && Current(_capture, screen)) return _capture;
            var widget = _hud.HitTestScreen(screen);
            return widget == null ? null : Capture(widget, screen);
        }
        public object RetainPointerTarget(object pressedTarget, Point screen)
        {
            if (pressedTarget is not Hit hit || !IsLive(hit)
                || hit.Widget is not INativeHudPointerSnapshot snapshot) return null;
            return snapshot.IsCapturedPointerCurrent(hit.Action) ? hit : null;
        }
        public object HitTestWheel(Point screen)
        {
            if (!_available()) return null;
            INativeHudWidget[] widgets;
            lock (_hud._widgetsLock) widgets = _hud._widgets.ToArray();
            for (int i = widgets.Length - 1; i >= 0; i--)
            {
                var widget = widgets[i];
                if (!widget.Visible) continue;
                var target = (widget as INativeHudPointerSnapshot)?.CaptureWheelTarget(screen);
                if (target != null) return new Hit(widget, target, _hud._pointerInputGeneration, Viewport, true);
                if (widget.TryHitTest(screen)) return Capture(widget, screen);
            }
            return null;
        }

        private static object CaptureAction(INativeHudWidget widget, Point screen) => widget switch
        {
            INativeHudPointerSnapshot snapshot => snapshot.CapturePointerTarget(screen),
            PlayerHudBottomWidget bottom => bottom.CapturePointerTarget(screen),
            _ => widget.ScreenBounds
        };

        private Hit Capture(INativeHudWidget widget, Point screen) =>
            new(widget, CaptureAction(widget, screen), _hud._pointerInputGeneration, Viewport, false);

        private bool IsLive(Hit hit)
        {
            if (!_available() || hit.Generation != _hud._pointerInputGeneration || hit.Viewport != Viewport
                || !hit.Widget.Visible || hit.Action == null) return false;
            lock (_hud._widgetsLock) return _hud._widgets.Contains(hit.Widget);
        }

        private bool Current(Hit hit, Point screen)
        {
            if (!IsLive(hit)) return false;
            if (hit.Wheel) return Equals(hit, HitTestWheel(screen));
            if (ReferenceEquals(hit, _capture) && hit.Widget is INativeHudPointerSnapshot snapshot
                && snapshot.IsCapturedPointerCurrent(hit.Action)) return true;
            return ReferenceEquals(_hud.HitTestScreen(screen), hit.Widget)
                && Equals(hit.Action, CaptureAction(hit.Widget, screen));
        }

        private (string Endpoint, string Target) TicketTarget(Hit hit)
        {
            if (hit.Widget is NotchWidget && NotchAction.Expand != null
                && Equals(NotchAction.Kind.GetValue(hit.Action), NotchAction.Expand))
                return (ExpandTarget, ExpandTarget);
            if (hit.Widget is PlayerHudBottomWidget && hit.Action is PlayerHudTarget slot)
                return (PlayerHudPointerInput.Endpoint, PlayerHudPointerInput.TargetId(slot));
            string endpoint = hit.Widget switch
            {
                NotchWidget => "hud.main.notch",
                NativeDialogueWidget => "hud.main.dialogue",
                NpcMenuWidget => "hud.main.npc",
                RightContextWidget => "hud.main.context",
                SafeExitPanelWidget => "hud.main.safe_exit",
                PlayerHudBuffWidget => "hud.player.buffs",
                PlayerHudAllyWidget => "hud.player.ally",
                PlayerHudFocusTargetWidget => "hud.player.focus",
                NativeTooltipWidget => "tooltip.pinned." + _hud.PointerInstanceGeneration,
                _ => "hud.main.widget." + _hud.PointerInstanceGeneration
            };
            // The structured action in Hit is checked independently of the authority's target ID.
            return (endpoint, hit.Wheel ? endpoint + ".wheel" : endpoint + ".press");
        }

        public void Dispatch(int message, Point screen, uint data, object target)
        {
            if (message == 0x2A3)
            {
                Cancel("hud_pointer_left");
                return;
            }
            if (_down != null && (_claim is { IsCurrent: false } || !Current(_down, screen)
                || _capture != null && _claim is { CanCommit: false }))
                CancelDown("hud_pointer_boundary");
            if (target is not Hit hit || !Current(hit, screen))
            {
                if (message == 0x200) SetHover(null, screen);
                else if (message is 0x201 or 0x202) Cancel("hud_target_changed");
                return;
            }
            if (message == 0x20A)
            {
                DispatchWheel(hit, screen, unchecked((short)(data >> 16)));
                return;
            }
            SetHover(hit.Widget, screen);
            switch (message)
            {
                case 0x200:
                    hit.Widget.OnMouseEvent(Args(screen, MouseButtons.None), MouseEventKind.Move);
                    break;
                case 0x201:
                    BeginDown(hit, screen);
                    break;
                case 0x202:
                    CommitUp(hit, screen);
                    break;
            }
        }

        private bool TryBegin(Hit hit, Point screen, int button, out HudPointerClaim? claim)
        {
            claim = null;
            if (!Current(hit, screen)) return false;
            var authority = _hud._worldPointerAuthority;
            if (authority == null) return true;
            var (endpoint, target) = TicketTarget(hit);
            return HudPointerClaim.TryBegin(authority, endpoint, _hud.PointerInstanceGeneration,
                button, screen, target, out claim);
        }

        private void BeginDown(Hit hit, Point screen)
        {
            CancelDown("hud_new_down");
            if (!TryBegin(hit, screen, 1, out _claim)) return;
            _down = hit;
            hit.Widget.OnMouseEvent(Args(screen, MouseButtons.Left), MouseEventKind.Down);
            if (_down == hit && hit.Widget is INativeHudPointerSnapshot snapshot
                && snapshot.IsCapturedPointerCurrent(hit.Action)) _capture = hit;
        }

        private void CommitUp(Hit hit, Point screen)
        {
            if (_down != hit || _claim is { CanCommit: false })
            {
                CancelDown("hud_invalid_up");
                return;
            }
            var claim = _claim;
            _claim = null;
            _down = _capture = null;
            var args = Args(screen, MouseButtons.Left);
            bool click = hit.Widget is not INativeHudPointerSnapshot snapshot || snapshot.NeedsPointerClick;
            bool committed = false;
            try
            {
                hit.Widget.OnMouseEvent(args, MouseEventKind.Up);
                if (click && Current(hit, screen) && claim is not { CanCommit: false })
                {
                    hit.Widget.OnMouseEvent(args, MouseEventKind.Click);
                    committed = true;
                }
                else committed = !click;
            }
            finally { claim?.End(committed); }
        }

        private void DispatchWheel(Hit hit, Point screen, int delta)
        {
            if (!hit.Wheel || hit.Widget is not INativeHudWheelConsumer wheel) return;
            CancelDown("hud_wheel");
            if (!TryBegin(hit, screen, 0, out var claim)) return;
            if (claim is { CanCommit: false })
            {
                claim.Value.Cancel("hud_invalid_wheel");
                return;
            }
            bool committed = false;
            try { committed = wheel.OnMouseWheel(screen, delta); }
            finally { claim?.End(committed); }
        }

        private static MouseEventArgs Args(Point point, MouseButtons buttons) => new(buttons, 1, point.X, point.Y, 0);

        private void SetHover(INativeHudWidget next, Point screen)
        {
            if (ReferenceEquals(next, _hover)) return;
            var old = _hover;
            _hover = next;
            old?.OnMouseEvent(Args(screen, MouseButtons.None), MouseEventKind.Leave);
            next?.OnMouseEvent(Args(screen, MouseButtons.None), MouseEventKind.Enter);
        }

        private void CancelDown(string reason)
        {
            var claim = _claim;
            var down = _down;
            _claim = null;
            _down = _capture = null;
            claim?.Cancel(reason);
            down?.Widget.OnMouseEvent(Args(Point.Empty, MouseButtons.None), MouseEventKind.Cancel);
        }

        internal void Cancel(string reason)
        {
            CancelDown(reason);
            SetHover(null, Point.Empty);
        }

        public void Cancel() => Cancel("hud_pointer_cancelled");
    }
}

internal readonly record struct HudPointerClaim(IUiPointerAuthority Authority, PointerGestureTicket Ticket, string Target)
{
    internal static bool TryBegin(IUiPointerAuthority authority, string endpoint, long generation,
        int button, Point screen, string target, out HudPointerClaim? claim)
    {
        claim = null;
        if (!authority.TryBeginPointer(endpoint, generation, button, screen, target, out var ticket)) return false;
        claim = new HudPointerClaim(authority, ticket, target);
        return true;
    }

    internal bool IsCurrent => Ticket.PointerEpoch == Authority.CurrentPointerEpoch
        && Ticket.GeometryVersion == Authority.CurrentGeometryVersion;
    internal bool CanCommit => IsCurrent && Authority.ValidatePointerCommit(Ticket, Target);
    internal void End(bool committed) => Authority.EndPointer(Ticket, committed);
    internal void Cancel(string reason) => Authority.CancelPointer(Ticket, reason);
}
