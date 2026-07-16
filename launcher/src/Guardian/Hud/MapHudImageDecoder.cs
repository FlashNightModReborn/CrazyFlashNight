// CF7:ME — Native HUD image decode boundary.
// System.Drawing/GDI+ cannot decode WebP reliably on supported Windows installs,
// so runtime map assets are decoded with SkiaSharp and copied into the existing
// premultiplied System.Drawing.Bitmap rendering pipeline.

using System;
using System.Drawing;
using System.Drawing.Imaging;
using SkiaSharp;

namespace CF7Launcher.Guardian.Hud
{
    internal static class MapHudImageDecoder
    {
        internal const int DEFAULT_MAX_DIMENSION = 512;

        internal static Bitmap LoadBitmap(string path)
        {
            return LoadBitmap(path, DEFAULT_MAX_DIMENSION);
        }

        internal static Bitmap LoadBitmap(string path, int maxDimension)
        {
            if (string.IsNullOrEmpty(path)) throw new ArgumentException("Image path is required.", nameof(path));
            if (maxDimension <= 0) throw new ArgumentOutOfRangeException(nameof(maxDimension));

            using (SKData encoded = SKData.Create(path))
            using (SKCodec codec = SKCodec.Create(encoded))
            {
                if (codec == null) throw new InvalidOperationException("Unsupported or corrupt image: " + path);

                int sourceWidth = codec.Info.Width;
                int sourceHeight = codec.Info.Height;
                float scale = Math.Min(1f, (float)maxDimension / Math.Max(sourceWidth, sourceHeight));
                SKSizeI scaled = codec.GetScaledDimensions(scale);
                int width = scaled.Width;
                int height = scaled.Height;
                if (width <= 0 || height <= 0)
                    throw new InvalidOperationException("Invalid decoded image dimensions: " + path);
                if (Math.Max(width, height) > maxDimension)
                    throw new InvalidOperationException("Codec cannot satisfy requested decode size: " + path);

                SKImageInfo decodeInfo = new SKImageInfo(width, height, SKColorType.Bgra8888, SKAlphaType.Premul);
                Bitmap bitmap = new Bitmap(width, height, PixelFormat.Format32bppPArgb);
                try
                {
                    BitmapData data = bitmap.LockBits(
                        new Rectangle(0, 0, width, height),
                        ImageLockMode.WriteOnly,
                        PixelFormat.Format32bppPArgb);
                    try
                    {
                        if (data.Stride <= 0)
                            throw new InvalidOperationException("Unexpected negative bitmap stride: " + path);
                        SKCodecResult result = codec.GetPixels(decodeInfo, data.Scan0, data.Stride, new SKCodecOptions());
                        if (result != SKCodecResult.Success)
                            throw new InvalidOperationException("Image decode failed (" + result + "): " + path);
                    }
                    finally
                    {
                        bitmap.UnlockBits(data);
                    }
                    return bitmap;
                }
                catch
                {
                    bitmap.Dispose();
                    throw;
                }
            }
        }
    }
}
