// CF7:ME — Native HUD image decode boundary.
// System.Drawing/GDI+ cannot decode WebP reliably on supported Windows installs,
// so runtime map assets are decoded with SkiaSharp and copied into the existing
// premultiplied System.Drawing.Bitmap rendering pipeline.

using System;
using System.Drawing;
using System.Drawing.Imaging;
using System.Runtime.InteropServices;
using SkiaSharp;

namespace CF7Launcher.Guardian.Hud
{
    internal static class MapHudImageDecoder
    {
        internal static Bitmap LoadBitmap(string path)
        {
            if (string.IsNullOrEmpty(path)) throw new ArgumentException("Image path is required.", nameof(path));

            using (SKData encoded = SKData.Create(path))
            using (SKCodec codec = SKCodec.Create(encoded))
            {
                if (codec == null) throw new InvalidOperationException("Unsupported or corrupt image: " + path);

                int width = codec.Info.Width;
                int height = codec.Info.Height;
                SKImageInfo decodeInfo = new SKImageInfo(width, height, SKColorType.Bgra8888, SKAlphaType.Premul);
                using (SKBitmap decoded = new SKBitmap(decodeInfo))
                {
                    SKCodecResult result = codec.GetPixels(decodeInfo, decoded.GetPixels());
                    if (result != SKCodecResult.Success)
                        throw new InvalidOperationException("Image decode failed (" + result + "): " + path);

                    int sourceStride = decoded.RowBytes;
                    byte[] sourcePixels = new byte[checked(sourceStride * height)];
                    Marshal.Copy(decoded.GetPixels(), sourcePixels, 0, sourcePixels.Length);

                    Bitmap bitmap = new Bitmap(width, height, PixelFormat.Format32bppPArgb);
                    try
                    {
                        BitmapData data = bitmap.LockBits(
                            new Rectangle(0, 0, width, height),
                            ImageLockMode.WriteOnly,
                            PixelFormat.Format32bppPArgb);
                        try
                        {
                            int rowBytes = checked(width * 4);
                            for (int y = 0; y < height; y++)
                            {
                                Marshal.Copy(
                                    sourcePixels,
                                    y * sourceStride,
                                    IntPtr.Add(data.Scan0, y * data.Stride),
                                    rowBytes);
                            }
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
}
