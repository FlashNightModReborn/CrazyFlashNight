#nullable enable
using CF7Launcher.Guardian.Hud.UnitLife;

namespace CF7Launcher.Guardian.Hud.PlayerInfo;

internal sealed partial class PlayerHudFocusTargetWidget
{
    private static UnitLifeBarStyle FillStyle(string role) => role == "boss" ? UnitLifeBarStyle.Boss :
        role == "combat" ? UnitLifeBarStyle.Hostile : UnitLifeBarStyle.Friendly;
}
