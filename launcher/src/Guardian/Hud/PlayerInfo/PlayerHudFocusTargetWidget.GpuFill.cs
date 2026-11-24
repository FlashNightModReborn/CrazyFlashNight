#nullable enable
using System;
using System.Drawing;
using CF7Launcher.Guardian.Hud.UnitLife;
using CF7Launcher.Guardian.WorldCompositor;

namespace CF7Launcher.Guardian.Hud.PlayerInfo;

internal sealed partial class PlayerHudFocusTargetWidget
{
    // Dual-track D2 unit bars use pre-baked Format32bppPArgb strips in UnitLifeBarPainter,
    // which composite shield caps, darkened stagger states, poise segments and hit flashes
    // directly in a single pass. Keep the presentation seam cleared when focus GPU fill is active.
    internal Rectangle[]? ResidualDamage(Rectangle[]? damage, Rectangle extent) => damage;

    internal void PrepareGpuFill(WorldRasterPresentation? presentation, Point bitmapOrigin, bool covered)
    {
        if (presentation?.SupportsFocus == true)
            presentation.StageFocus(null, 0, 0, Array.Empty<int>(), 0);
    }

    private static UnitLifeBarStyle FillStyle(string role) => role == "boss" ? UnitLifeBarStyle.Boss :
        role == "combat" ? UnitLifeBarStyle.Hostile : UnitLifeBarStyle.Friendly;
}
