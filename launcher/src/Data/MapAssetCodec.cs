using System;
using System.IO;
using System.Linq;
using Newtonsoft.Json.Linq;
using SkiaSharp;

namespace CF7Launcher.Data
{
    /// <summary>地图静态素材的有界 sRGB 解码和显式无损 WebP 编码；任何往返像素差异都拒绝。</summary>
    public static class MapAssetCodec
    {
        public const int MaxBytes = 16 * 1024 * 1024, MaxSide = 4096, MaxPixels = 16 * 1024 * 1024;
        public sealed class Image
        {
            public byte[] Bytes;
            public JObject Metadata;
        }
        private static SKBitmap Decode(byte[] bytes, out SKEncodedImageFormat format)
        {
            MapRuleEvaluator.Need(bytes != null && bytes.Length is > 0 and <= MaxBytes, "图片须为 1 字节至 16 MiB。");
            using var data = SKData.CreateCopy(bytes); using var codec = SKCodec.Create(data);
            MapRuleEvaluator.Need(codec != null, "图片无法解码；不能只凭扩展名导入。");
            format = codec.EncodedFormat;
            MapRuleEvaluator.Need(new[] { SKEncodedImageFormat.Png, SKEncodedImageFormat.Webp, SKEncodedImageFormat.Jpeg }.Contains(format), "地图素材支持静态 PNG、WebP、JPEG。");
            MapRuleEvaluator.Need(codec.FrameCount <= 1, "该图片包含动画；请明确导出所需静态帧，不会静默截取首帧。");
            MapRuleEvaluator.Need(codec.EncodedOrigin == SKEncodedOrigin.TopLeft, "图片带有旋转方向信息，请先在绘图软件应用旋转并导出。");
            int width = codec.Info.Width, height = codec.Info.Height;
            MapRuleEvaluator.Need(width > 0 && height > 0 && width <= MaxSide && height <= MaxSide && (long)width * height <= MaxPixels, "图片尺寸超过 4096×4096 或总像素限制。");
            using var colorSpace = SKColorSpace.CreateSrgb();
            var info = new SKImageInfo(width, height, SKColorType.Rgba8888, SKAlphaType.Unpremul, colorSpace);
            var bitmap = new SKBitmap(info);
            try
            {
                MapRuleEvaluator.Need(codec.GetPixels(info, bitmap.GetPixels()) == SKCodecResult.Success, "图片不完整或解码失败。");
                return bitmap;
            }
            catch { bitmap.Dispose(); throw; }
        }
        public static Image Convert(byte[] source, Func<byte[], byte[]> exactEncoder = null)
        {
            using var bitmap = Decode(source, out var format);
            using var pixels = bitmap.PeekPixels();
            using var encoded = pixels.Encode(new SKWebpEncoderOptions(SKWebpEncoderCompression.Lossless, 100));
            MapRuleEvaluator.Need(encoded != null && encoded.Size <= MaxBytes, "无损 WebP 编码失败或产物超过 16 MiB。");
            byte[] output = encoded.ToArray();
            bool Matches(byte[] bytes)
            {
                using var decoded = Decode(bytes, out var outputFormat);
                return outputFormat == SKEncodedImageFormat.Webp && decoded.Width == bitmap.Width && decoded.Height == bitmap.Height && bitmap.Bytes.AsSpan().SequenceEqual(decoded.Bytes);
            }
            string encoder = "skia-lossless";
            if (!Matches(output) && exactEncoder != null)
            {
                // Skia 的 WebP 入口不暴露 libwebp exact，可能改写 alpha=0 的 RGB；保留严格像素门，复用现役 exact 转换器。
                output = exactEncoder(source); encoder = "pillow-lossless-exact";
            }
            MapRuleEvaluator.Need(Matches(output), "图片无损往返不一致，未应用候选。");
            return new Image { Bytes = output, Metadata = new JObject { ["width"] = bitmap.Width, ["height"] = bitmap.Height,
                ["bytes"] = output.Length, ["sha256"] = MapDefinition.Hash(output), ["sourceSha256"] = MapDefinition.Hash(source),
                ["sourceFormat"] = format.ToString(), ["format"] = "Webp", ["encoding"] = "webp-lossless-pixel-verified", ["encoder"] = encoder,
                ["comparisonColorSpace"] = "srgb", ["pixelSha256"] = MapDefinition.Hash(bitmap.Bytes) } };
        }
        public static JObject Inspect(byte[] bytes)
        {
            using var image = Decode(bytes, out var format);
            return new JObject { ["width"] = image.Width, ["height"] = image.Height, ["bytes"] = bytes.Length, ["format"] = format.ToString(), ["sha256"] = MapDefinition.Hash(bytes) };
        }
        public static JObject InspectPublished(byte[] bytes)
        {
            var metadata = Inspect(bytes);
            MapRuleEvaluator.Need((string)metadata["format"] == "Webp", "发布地图图片的实际格式必须是静态 WebP，不能只修改扩展名。");
            return metadata;
        }
        public static byte[] Crop(byte[] source, JObject rect)
        {
            MapRuleEvaluator.Keys(rect, "x", "y", "w", "h");
            int x = checked((int)MapRuleEvaluator.Integer(rect["x"], "裁切左边")), y = checked((int)MapRuleEvaluator.Integer(rect["y"], "裁切上边"));
            int width = checked((int)MapRuleEvaluator.Integer(rect["w"], "裁切宽度")), height = checked((int)MapRuleEvaluator.Integer(rect["h"], "裁切高度"));
            using var image = Decode(source, out _);
            MapRuleEvaluator.Need(width > 0 && height > 0 && x <= image.Width - width && y <= image.Height - height, "裁切矩形超出图片或为空。");
            using var colorSpace = SKColorSpace.CreateSrgb();
            using var result = new SKBitmap(new SKImageInfo(width, height, SKColorType.Rgba8888, SKAlphaType.Unpremul, colorSpace));
            byte[] sourcePixels = image.Bytes;
            for (int row = 0; row < height; row++) System.Runtime.InteropServices.Marshal.Copy(sourcePixels, (y + row) * image.RowBytes + x * 4, IntPtr.Add(result.GetPixels(), row * result.RowBytes), width * 4);
            using var pixels = result.PeekPixels(); using var encoded = pixels.Encode(SKEncodedImageFormat.Png, 100);
            MapRuleEvaluator.Need(encoded != null && encoded.Size <= MaxBytes, "裁切产物编码失败或过大。");
            byte[] bytes = encoded.ToArray(); using var roundtrip = Decode(bytes, out _);
            MapRuleEvaluator.Need(result.Bytes.AsSpan().SequenceEqual(roundtrip.Bytes), "裁切像素往返不一致，未生成候选。");
            return bytes;
        }
    }
}
