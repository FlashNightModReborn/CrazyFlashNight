using System.Drawing;
using CF7Launcher.Fonts;
using CF7Launcher.Guardian.Hud;
using Xunit;

namespace CF7Launcher.Tests.Guardian
{
    public sealed class NativeHudFontsTests
    {
        [Fact]
        public void Facade_UsesSemanticRoleAndAlwaysReturnsUsableFallback()
        {
            RuntimeFontCatalog.ResetForTest();
            Assert.Equal("native.hud.body", NativeHudFonts.UiRole);

            using (Font body = NativeHudFonts.CreateUiFont(14f, FontStyle.Bold, GraphicsUnit.Pixel))
            using (Font mono = NativeHudFonts.CreateRoleFont("native.hud.mono", 12f, FontStyle.Regular, GraphicsUnit.Pixel))
            {
                Assert.NotNull(body);
                Assert.NotNull(mono);
                Assert.False(string.IsNullOrWhiteSpace(body.FontFamily.Name));
                Assert.False(string.IsNullOrWhiteSpace(mono.FontFamily.Name));
                Assert.True(body.Size > 0f);
                Assert.True(mono.Size > 0f);
            }
        }
    }
}
