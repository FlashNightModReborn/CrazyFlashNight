#nullable enable
using System;
using System.Drawing;
using System.Windows.Forms;
using CF7Launcher.Guardian.InputOwnership;
using CF7Launcher.Guardian.WorldCompositor;

namespace CF7Launcher.Guardian.Hud.PlayerInfo;

// Reuses the widget's exact target checks and controller. Neither queued pointer
// work nor a presentation restart can turn an old press into a new domain action.
internal sealed class PlayerHudPointerInput : IWorldHudInput
{
    internal const string Endpoint = "hud.player.slots";
    private readonly PlayerHudBottomWidget _widget;
    private readonly Func<bool> _available;
    private IUiPointerAuthority? _authority;
    private long _instanceGeneration;
    private long _bindingVersion;
    private sealed record Hit(PlayerHudTarget Target, Rectangle Bounds, long BindingVersion);
    private Hit? _down;
    private HudPointerClaim? _claim;
    private bool _hovered;

    internal PlayerHudPointerInput(PlayerHudBottomWidget widget, Func<bool> available)
    {
        _widget = widget;
        _available = available;
    }

    internal void BindPointerAuthority(IUiPointerAuthority? authority, long instanceGeneration)
    {
        if (ReferenceEquals(_authority, authority) && _instanceGeneration == instanceGeneration) return;
        RetireBinding();
        _authority = authority;
        _instanceGeneration = instanceGeneration;
    }

    internal static string TargetId(PlayerHudTarget target) => $"{target.Kind}.{target.Slot}";

    public object? HitTest(Point screen)
    {
        if (!_available()) return null;
        var target = _widget.CapturePointerTarget(screen);
        return target == null ? null : new Hit(target, _widget.ScreenBounds, _bindingVersion);
    }

    private bool IsCurrent(Hit hit, Point screen) => _available() && hit.BindingVersion == _bindingVersion
        && hit.Bounds == _widget.ScreenBounds && hit.Target == _widget.CapturePointerTarget(screen);

    public void Dispatch(int message, Point screen, uint data, object? target)
    {
        if (_down != null && (_claim is { IsCurrent: false } || !IsCurrent(_down, screen)))
            ClearPress("player_hud_pointer_boundary");
        if (message == 0x2A3 || target is not Hit hit || !IsCurrent(hit, screen))
        {
            ClearPress("player_hud_target_changed");
            return;
        }
        if (message == 0x200)
        {
            _hovered = true;
            _widget.OnMouseEvent(new MouseEventArgs(MouseButtons.None, 0, screen.X, screen.Y, 0), MouseEventKind.Move);
            return;
        }
        var args = new MouseEventArgs(MouseButtons.Left, 1, screen.X, screen.Y, 0);
        if (message == 0x201)
        {
            if (_down != null) ClearPress("player_hud_new_down");
            if (_authority != null && !HudPointerClaim.TryBegin(_authority, Endpoint, _instanceGeneration,
                1, screen, TargetId(hit.Target), out _claim)) return;
            _down = hit;
            _widget.OnMouseEvent(args, MouseEventKind.Down);
        }
        else if (message == 0x202)
        {
            if (_down != hit || _claim is { CanCommit: false })
            {
                ClearPress("player_hud_invalid_up");
                return;
            }
            var claim = _claim;
            _claim = null;
            _down = null;
            bool committed = false;
            try
            {
                _widget.OnMouseEvent(args, MouseEventKind.Up);
                if (IsCurrent(hit, screen) && claim is not { CanCommit: false })
                {
                    _widget.OnMouseEvent(args, MouseEventKind.Click);
                    committed = true;
                }
            }
            finally { claim?.End(committed); }
        }
    }

    internal void RetireBinding()
    {
        ++_bindingVersion;
        Cancel();
    }

    public void Cancel() => ClearPress("player_hud_cancelled");

    private void ClearPress(string reason)
    {
        bool owned = _down != null || _hovered;
        var claim = _claim;
        _claim = null;
        _down = null;
        _hovered = false;
        claim?.Cancel(reason);
        if (owned) _widget.OnMouseEvent(new MouseEventArgs(MouseButtons.None, 0, 0, 0, 0), MouseEventKind.Cancel);
    }
}
