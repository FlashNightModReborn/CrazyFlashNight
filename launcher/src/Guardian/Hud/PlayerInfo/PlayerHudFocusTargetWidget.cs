#nullable enable
using System;
using System.Drawing;
using System.Globalization;
using System.Windows.Forms;

namespace CF7Launcher.Guardian.Hud.PlayerInfo;

/// <summary>Read-only target strip in the existing Buff surface; no pointer or animation owner.</summary>
internal sealed class PlayerHudFocusTargetWidget : PlayerHudWidgetBase
{
    private readonly Font _font = NativeHudFonts.CreateUiFont(12, FontStyle.Regular, GraphicsUnit.Pixel);
    private PlayerHudFocusTarget? _lastTarget;
    private RectangleF _lastLayout;
    private bool _lastSuppressed;
    protected override bool HasContent => Snapshot?.FocusTarget != null;
    protected override RectangleF LogicalBounds => BoundsForBuffCount(Snapshot?.Buffs.Length ?? 0);
    // Keep the complete strip in the left column, clear of the widest centered
    // notch and its wave/pause rows. Buff rows still determine its vertical slot.
    internal static RectangleF BoundsForBuffCount(int count) => new(6,
        Math.Max(1, (int)Math.Ceiling(Math.Clamp(count, 0, 256) / 32d)) * NativeHudTheme.TopBarHeightBase + 4,
        (1024 - RightHudLayout.PreferredNotchMaxWidthBase) / 2f - RightHudLayout.NotchRightGapBase - 6, 30);
    internal PlayerHudFocusTargetWidget(Control anchor, PlayerHudController controller) : base(anchor, controller) { }

    protected override void OnStateChanged()
    {
        var target = Snapshot?.FocusTarget;
        var layout = LogicalBounds;
        if (target == _lastTarget && layout == _lastLayout && Suppressed == _lastSuppressed) return;
        _lastTarget = target; _lastLayout = layout; _lastSuppressed = Suppressed;
        base.OnStateChanged();
    }

    protected override void PaintLogical(Graphics g)
    {
        var target = Snapshot!.FocusTarget!;
        var bounds = LogicalBounds;
        var color = target.Role == "boss" ? NativeHudTheme.Danger : NativeHudTheme.Cyan;
        // Shared native frame rules keep borders one device pixel at normal viewport scales.
        var saved = g.Save();
        g.ScaleTransform(1 / Scale, 1 / Scale);
        var pixels = Rectangle.FromLTRB((int)Math.Round(bounds.Left * Scale), (int)Math.Round(bounds.Top * Scale),
            (int)Math.Round(bounds.Right * Scale), (int)Math.Round(bounds.Bottom * Scale));
        NativeHudTheme.DrawPanel(g, pixels, Scale, NativeHudTheme.PanelFill, Color.Empty, false);
        g.Restore(saved);

        var track = new RectangleF(bounds.X + 6, bounds.Y + 21, bounds.Width - 12, 4);
        using var background = new SolidBrush(Color.FromArgb(235, 35, 37, 40));
        using var fill = new SolidBrush(color);
        g.FillRectangle(background, track);
        double ratio = Math.Clamp(target.Hp / target.HpMax, 0, 1);
        if (ratio > 0) g.FillRectangle(fill, track.X, track.Y, (float)(track.Width * ratio), track.Height);
        using var labelBrush = new SolidBrush(NativeHudTheme.TextPrimary);
        using var format = new StringFormat(StringFormat.GenericTypographic)
        { FormatFlags = StringFormatFlags.NoWrap, Trimming = StringTrimming.EllipsisCharacter };
        var role = target.Role == "boss" ? "Boss" : "保护目标";
        g.DrawString(role + "  " + target.Name.Replace('\r', ' ').Replace('\n', ' '), _font, labelBrush,
            new RectangleF(bounds.X + 6, bounds.Y + 3, bounds.Width - 142, 16), format);
        format.Alignment = StringAlignment.Far;
        g.DrawString(HealthText(target), _font, labelBrush,
            new RectangleF(bounds.Right - 128, bounds.Y + 3, 122, 16), format);
    }
    internal static string HealthText(PlayerHudFocusTarget target) =>
        Value(target.Hp) + " / " + Value(target.HpMax);
    private static string Value(double value) => Math.Abs(value) >= 1e9
        ? value.ToString("0.##E+0", CultureInfo.InvariantCulture)
        : Math.Floor(value).ToString("0", CultureInfo.InvariantCulture);
    public override bool TryHitTest(Point screenPt) => false;
    public override void OnMouseEvent(MouseEventArgs e, MouseEventKind kind) { }
    public override void Dispose() { _font.Dispose(); base.Dispose(); }
}
