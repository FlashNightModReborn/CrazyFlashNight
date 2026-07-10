using System;
using System.Drawing;
using System.IO;
using CF7Launcher.Guardian.Hud;
using Xunit;

namespace CF7Launcher.Tests.Guardian
{
    public class NativeHudFontsTests
    {
        [Fact]
        public void CandidatePaths_ReuseFontPackAndNeverUseFlashAuthoringFolder()
        {
            string[] paths = NativeHudFonts.CandidatePathsForTest;

            Assert.NotEmpty(paths);
            Assert.Contains(paths, p => p.EndsWith(NativeHudFonts.SourceHanSerifFileName,
                StringComparison.OrdinalIgnoreCase));
            Assert.DoesNotContain(paths, p => p.IndexOf("闪7重置版字体", StringComparison.OrdinalIgnoreCase) >= 0);
        }

        [Fact]
        public void CreateUiFont_AlwaysReturnsUsableFontAndLoadsFontPackAppDataCopyWhenPresent()
        {
            using (Font font = NativeHudFonts.CreateUiFont(14f, FontStyle.Bold, GraphicsUnit.Pixel))
            {
                Assert.NotNull(font);
                Assert.False(string.IsNullOrWhiteSpace(font.FontFamily.Name));
                Assert.True(font.Size > 0f);
            }

            string localAppData = Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData);
            string expected = Path.Combine(localAppData, "CF7FlashNight", "fonts",
                NativeHudFonts.SourceHanSerifFileName);
            if (File.Exists(expected))
            {
                Assert.Equal(Path.GetFullPath(expected), Path.GetFullPath(NativeHudFonts.LoadedPathForTest));
                string family = NativeHudFonts.LoadedFamilyNameForTest;
                Assert.True(family.IndexOf("Source Han Serif", StringComparison.OrdinalIgnoreCase) >= 0
                    || family.IndexOf("思源宋体", StringComparison.OrdinalIgnoreCase) >= 0,
                    "unexpected loaded family: " + family);
            }
        }
    }
}
