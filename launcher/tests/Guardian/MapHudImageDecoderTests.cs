using System;
using System.Drawing;
using System.Drawing.Imaging;
using System.IO;
using CF7Launcher.Guardian.Hud;
using Xunit;

namespace CF7Launcher.Tests.Guardian
{
    public class MapHudImageDecoderTests
    {
        [Fact]
        public void Decode_RuntimeWebp_ProducesPremultipliedSystemDrawingBitmap()
        {
            string assetPath = FindRuntimeAsset("assets/map/composite/base/base-roof.webp");
            using (Bitmap bitmap = MapHudImageDecoder.LoadBitmap(assetPath))
            {
                Assert.True(bitmap.Width > 0);
                Assert.True(bitmap.Height > 0);
                Assert.Equal(PixelFormat.Format32bppPArgb, bitmap.PixelFormat);
            }
        }

        private static string FindRuntimeAsset(string relativePath)
        {
            string current = AppContext.BaseDirectory;
            for (int i = 0; i < 8 && !string.IsNullOrEmpty(current); i++)
            {
                string normalized = relativePath.Replace('/', Path.DirectorySeparatorChar);
                string[] candidates = {
                    Path.Combine(current, "web", normalized),
                    Path.Combine(current, "launcher", "web", normalized)
                };
                for (int j = 0; j < candidates.Length; j++)
                    if (File.Exists(candidates[j])) return candidates[j];
                current = Directory.GetParent(current)?.FullName;
            }
            throw new FileNotFoundException("Runtime map asset not found for decode test: " + relativePath);
        }
    }
}
