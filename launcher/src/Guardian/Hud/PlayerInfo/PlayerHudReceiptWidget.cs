#nullable enable
using System;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Windows.Forms;

namespace CF7Launcher.Guardian.Hud.PlayerInfo;

internal sealed class PlayerHudReceiptWidget : PlayerHudWidgetBase
{
    internal const int HoldMs = 2100, FadeMs = 400, TotalMs = HoldMs + FadeMs;
    private readonly Font _font = NativeHudFonts.CreateRoleFont("native.player-info.body", 9.4f, FontStyle.Bold, GraphicsUnit.Pixel);
    private readonly StringFormat _center = new(StringFormat.GenericTypographic)
    {
        Alignment = StringAlignment.Center, LineAlignment = StringAlignment.Center,
        FormatFlags = StringFormatFlags.NoWrap, Trimming = StringTrimming.EllipsisCharacter
    };
    private readonly GraphicsPath _plate = new();
    private string _message = "";
    private long _epoch, _lastNotice;
    private int _age;
    private float _top;
    private bool _pending;

    internal PlayerHudReceiptWidget(Control anchor, PlayerHudController controller) : base(anchor, controller)
    {
        _plate.AddPolygon(new PointF[] { new(0,0), new(300,0), new(300,12), new(293,19), new(7,19), new(0,12) });
        _top = HudZoneLayout.ComboTop(HudZoneLayout.NotchStableBottom);
        controller.StatusChanged += OnControllerStatus;
        HudZoneLayout.Changed += OnZoneChanged;
        OnStateChanged();
        if (controller.WritePending) OnControllerStatus();
    }

    protected override PlayerHudGroups ConsumedGroups => PlayerHudGroups.Resources | PlayerHudGroups.Vitals;
    protected override bool HasContent => Snapshot != null && _message.Length != 0;
    protected override RectangleF LogicalBounds => new(361, _top-1, 302, 21);
    public override bool WantsAnimationTick => Visible && !_pending;
    public override bool TryHitTest(Point screen) => false;
    public override void OnMouseEvent(MouseEventArgs e, MouseEventKind kind) { }

    private void OnZoneChanged(object? sender, EventArgs args)
    {
        float top = HudZoneLayout.ComboTop(HudZoneLayout.NotchStableBottom);
        if (_top == top) return;
        _top = top;
        if (Visible) base.OnStateChanged();
    }

    private void OnControllerStatus() => Show(Controller.Message, Controller.WritePending);

    private void Show(string text, bool pending)
    {
        if (pending && _pending && _message == text) return;
        _message = text;
        _age = 0;
        _pending = pending;
        UpdatePresentation();
    }

    private void UpdatePresentation()
    {
        HudZoneLayout.ReportReceiptVisible(Visible);
        base.OnStateChanged();
    }

    protected override void OnStateChanged()
    {
        var snapshot = Snapshot;
        var notice = snapshot?.Resources?.Feedback;
        long epoch = snapshot?.Epoch ?? 0;
        if (_epoch != epoch)
        {
            _epoch = epoch;
            _lastNotice = notice?.Serial ?? 0;
            if (Controller.WritePending || _message.Length != 0)
            {
                _pending = Controller.WritePending;
                _message = _pending ? Controller.Message : "";
                _age = 0;
                UpdatePresentation();
            }
            return;
        }
        if (notice == null || notice.Serial <= _lastNotice) return;
        _lastNotice = notice.Serial;
        if (Suppressed || _pending || snapshot!.Vitals.Paused || snapshot.Vitals.Hp <= 0) return;
        Show(notice.Reason switch
        {
            "mp" => "魔力不足，无法施放",
            "empty" => "另一组没有剩余药剂",
            _ => "道具或材料不足"
        }, false);
    }

    public override void SetHostSuppressed(bool suppressed)
    {
        if (Suppressed == suppressed) return;
        Suppressed = suppressed;
        if (suppressed && !_pending) _message = "";
        UpdatePresentation();
    }

    public override void Tick(int deltaMs)
    {
        if (!WantsAnimationTick || deltaMs <= 0) return;
        int before = _age;
        _age = (int)Math.Min((long)_age + deltaMs, TotalMs);
        if (_age == TotalMs) Show("", false);
        else if (_age > HoldMs && (before <= HoldMs || (_age-HoldMs)/33 != (before-HoldMs)/33)) Repaint();
    }

    protected override void PaintLogical(Graphics g)
    {
        g.TranslateTransform(362, _top);
        g.SmoothingMode = SmoothingMode.AntiAlias;
        float alpha = _pending ? 1f : Math.Min(1f, (TotalMs-_age)/(float)FadeMs);
        using var fill = new LinearGradientBrush(new RectangleF(0,0,300,19),
            Color.FromArgb((int)(245*alpha),45,51,54), Color.FromArgb((int)(245*alpha),16,19,21), 90f);
        using var rim = new Pen(Color.FromArgb((int)(184*alpha),222,186,112), .85f);
        using var accent = new SolidBrush(Color.FromArgb((int)(255*alpha),230,188,104));
        using var text = new SolidBrush(Color.FromArgb((int)(255*alpha),244,237,216));
        g.FillPath(fill, _plate);
        g.DrawPath(rim, _plate);
        g.FillRectangle(accent, 2,2.2f,2.2f,14.6f);
        g.DrawString(_message, _font, text, new RectangleF(11,0,278,19), _center);
    }

    public override void Dispose()
    {
        if (Disposed) return;
        Controller.StatusChanged -= OnControllerStatus;
        HudZoneLayout.Changed -= OnZoneChanged;
        HudZoneLayout.ReportReceiptVisible(false);
        _plate.Dispose(); _font.Dispose(); _center.Dispose();
        base.Dispose();
    }
}
