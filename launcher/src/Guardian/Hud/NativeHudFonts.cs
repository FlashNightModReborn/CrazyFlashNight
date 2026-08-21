using System.Drawing;
using CF7Launcher.Fonts;

namespace CF7Launcher.Guardian.Hud
{
    /// <summary>
    /// Native HUD semantic-role facade. Physical families and paths live in fonts/fonts.xml;
    /// changing a role mapping never requires editing this class or another native consumer.
    /// </summary>
    internal static class NativeHudFonts
    {
        internal const string UiRole = "native.hud.body";

        internal static Font CreateUiFont(float size, FontStyle preferredStyle, GraphicsUnit unit)
        {
            return RuntimeFontCatalog.CreateFont(UiRole, size, preferredStyle, unit);
        }

        internal static Font CreateRoleFont(string roleId, float size, FontStyle preferredStyle, GraphicsUnit unit)
        {
            return RuntimeFontCatalog.CreateFont(roleId, size, preferredStyle, unit);
        }
    }
}
