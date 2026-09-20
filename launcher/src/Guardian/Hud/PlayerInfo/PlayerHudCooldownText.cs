#nullable enable
using System;
using System.Globalization;

namespace CF7Launcher.Guardian.Hud.PlayerInfo;

internal static class PlayerHudCooldownText
{
    // v1 cooldown steps use ManualCooldownService.FRAME_MS. The contract test
    // binds this display conversion to the AS2 source; Ready alone unlocks a slot.
    internal const double StepMilliseconds=33.33333;
    internal static string Format(PlayerHudCooldown cooldown)
    {
        if(cooldown.Ready)return "";
        var tenths=Math.Ceiling(Math.Max(1,cooldown.Total-cooldown.Step)*StepMilliseconds/100);
        if(tenths>=36000)return Math.Floor(tenths/36000).ToString("0",CultureInfo.InvariantCulture)+"h";
        if(tenths>=600)
        {
            var total=(int)Math.Ceiling(tenths/10);
            return (total/60).ToString(CultureInfo.InvariantCulture)+":"+(total%60).ToString("00",CultureInfo.InvariantCulture);
        }
        return tenths>=100 ? Math.Ceiling(tenths/10).ToString("0",CultureInfo.InvariantCulture)+"s"
            : (tenths/10).ToString("0.0",CultureInfo.InvariantCulture)+"s";
    }
}
