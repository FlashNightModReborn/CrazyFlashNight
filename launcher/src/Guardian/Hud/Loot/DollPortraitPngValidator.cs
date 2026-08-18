using System;
using System.IO;
using SkiaSharp;

namespace CF7Launcher.Guardian.Hud.Loot
{
    /// <summary>
    /// 纸娃娃运行时缓存的单一 PNG 校验边界。新回包和历史落盘文件都必须通过
    /// 完整像素解码与 exact 256×256 尺寸检查，避免旧缓存绕过写入侧校验。
    /// </summary>
    internal static class DollPortraitPngValidator
    {
        internal const int ExpectedSize = 256;
        internal const int MaxEncodedBytes = 3 * 1024 * 1024;

        private static readonly byte[] PngMagic =
        {
            0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A
        };

        internal static string ValidateFile(string path)
        {
            try
            {
                FileInfo info = new FileInfo(path);
                if (!info.Exists) return "PNG file is missing";
                if (info.Length <= 0 || info.Length > MaxEncodedBytes)
                    return "PNG file size is invalid (bytes=" + info.Length + ")";
                return ValidateBytes(File.ReadAllBytes(path));
            }
            catch (Exception ex)
            {
                return "PNG read failed (" + ex.GetType().Name + ")";
            }
        }

        internal static string ValidateBytes(byte[] png)
        {
            if (png == null || png.Length < PngMagic.Length || png.Length > MaxEncodedBytes)
                return "payload is not a PNG";
            for (int i = 0; i < PngMagic.Length; i++)
            {
                if (png[i] != PngMagic[i]) return "payload is not a PNG";
            }

            try
            {
                using (SKData data = SKData.CreateCopy(png))
                using (SKCodec codec = SKCodec.Create(data))
                {
                    if (codec == null)
                        return "PNG is corrupt or unsupported";
                    if (codec.Info.Width != ExpectedSize || codec.Info.Height != ExpectedSize)
                    {
                        return "PNG dimensions must be 256x256 (got "
                            + codec.Info.Width + "x" + codec.Info.Height + ")";
                    }

                    SKImageInfo imageInfo = new SKImageInfo(ExpectedSize, ExpectedSize,
                        SKColorType.Bgra8888, SKAlphaType.Premul);
                    using (SKBitmap decoded = new SKBitmap(imageInfo))
                    {
                        SKCodecResult result = codec.GetPixels(
                            imageInfo, decoded.GetPixels(), decoded.RowBytes, new SKCodecOptions());
                        if (result != SKCodecResult.Success)
                            return "PNG decode failed (" + result + ")";
                    }
                }
                return null;
            }
            catch (Exception ex)
            {
                return "PNG decode failed (" + ex.GetType().Name + ")";
            }
        }
    }
}
