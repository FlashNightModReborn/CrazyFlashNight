using System;
using System.IO;
using System.Runtime.InteropServices;
using CF7Launcher.Data;
using Newtonsoft.Json.Linq;
using SkiaSharp;
using Xunit;

namespace CF7Launcher.Tests.Tasks
{
    public sealed class MapDomainCoreTests
    {
        [Fact]
        public void Rule_UnknownIsNotPassedAndOrRetainsKnownBranch()
        {
            var rule = JObject.Parse("{type:'any',children:[{type:'chain',key:'主线',min:10},{type:'task',key:'1',state:'finished'}]}");
            var facts = JObject.Parse("{chains:{'主线':10},tasks:{}}");
            Assert.True(MapRuleEvaluator.Passed(MapRuleEvaluator.Evaluate(rule, new JObject(), facts)));
            facts["chains"]["主线"] = 9;
            Assert.Equal("unknown", (string)MapRuleEvaluator.Evaluate(rule, new JObject(), facts)["state"]);
        }
        [Fact]
        public void Rule_ActiveAndFinishedDoNotImplyDeliverable()
        {
            var facts = JObject.Parse("{tasks:{'1':{finished:3,active:true,deliverable:false}}}");
            var rule = JObject.Parse("{type:'task',key:'1',state:'deliverable'}");
            Assert.False(MapRuleEvaluator.Passed(MapRuleEvaluator.Evaluate(rule, new JObject(), facts)));
        }
        [Fact]
        public void Rule_RejectsCyclesUnknownKeysAndExcessDepth()
        {
            var rules = JObject.Parse("{a:{condition:{type:'rule',key:'b'}},b:{condition:{type:'rule',key:'a'}}}");
            Assert.Throws<InvalidDataException>(() => MapRuleEvaluator.Validate(JObject.Parse("{type:'rule',key:'a'}"), rules));
            Assert.Throws<InvalidDataException>(() => MapRuleEvaluator.Validate(JObject.Parse("{type:'always',script:'return true'}"), new JObject()));
            JObject nested = MapDomainDefinition.Always();
            for (int i = 0; i < 10; i++) nested = new JObject { ["type"] = "all", ["children"] = new JArray(nested) };
            Assert.Throws<InvalidDataException>(() => MapRuleEvaluator.Validate(nested, new JObject()));
        }
        [Fact]
        public void AssetCodec_ExplicitLosslessRoundtripAndTruncationRejection()
        {
            using var bitmap = new SKBitmap(new SKImageInfo(3, 1, SKColorType.Rgba8888, SKAlphaType.Unpremul));
            byte[] rgba = { 255, 0, 0, 255, 73, 17, 203, 123, 91, 53, 171, 0 };
            Marshal.Copy(rgba, 0, bitmap.GetPixels(), rgba.Length);
            using var image = SKImage.FromBitmap(bitmap); using var png = image.Encode(SKEncodedImageFormat.Png, 100);
            string root = AppContext.BaseDirectory;
            while (!File.Exists(Path.Combine(root, "tools", "convert-map-assets-webp.py"))) root = Directory.GetParent(root)?.FullName ?? throw new IOException("Project root not found.");
            var converted = MapAssetCodec.Convert(png.ToArray(), bytes => MapAssetTools.EncodeExact(root, bytes));
            Assert.Equal(3, (int)converted.Metadata["width"]);
            Assert.Equal("webp-lossless-pixel-verified", (string)converted.Metadata["encoding"]);
            Assert.Equal("pillow-lossless-exact", (string)converted.Metadata["encoder"]);
            Assert.Equal("Webp", (string)MapAssetCodec.Inspect(converted.Bytes)["format"]);
            Assert.Throws<InvalidDataException>(() => MapAssetCodec.Convert(new byte[] { 137, 80, 78, 71 }));
        }
        [Fact]
        public void AssetCrop_PreservesTransparentRgbAndRejectsRenamedPngOrOutOfBounds()
        {
            using var bitmap = new SKBitmap(new SKImageInfo(3, 1, SKColorType.Rgba8888, SKAlphaType.Unpremul));
            byte[] rgba = { 255, 0, 0, 255, 73, 17, 203, 123, 91, 53, 171, 0 };
            Marshal.Copy(rgba, 0, bitmap.GetPixels(), rgba.Length);
            using var pixels = bitmap.PeekPixels(); using var encoded = pixels.Encode(SKEncodedImageFormat.Png, 100);
            byte[] png = encoded.ToArray(), cropped = MapAssetCodec.Crop(png, JObject.Parse("{x:1,y:0,w:2,h:1}"));
            using var data = SKData.CreateCopy(cropped); using var codec = SKCodec.Create(data);
            using var result = new SKBitmap(new SKImageInfo(2, 1, SKColorType.Rgba8888, SKAlphaType.Unpremul));
            Assert.Equal(SKCodecResult.Success, codec.GetPixels(result.Info, result.GetPixels()));
            Assert.Equal(rgba.AsSpan(4).ToArray(), result.Bytes);
            Assert.Throws<InvalidDataException>(() => MapAssetCodec.InspectPublished(png));
            Assert.Throws<InvalidDataException>(() => MapAssetCodec.Crop(png, JObject.Parse("{x:-1,y:0,w:2,h:1}")));
            Assert.Throws<InvalidDataException>(() => MapAssetCodec.Crop(png, JObject.Parse("{x:2,y:0,w:2,h:1}")));
        }
    }
}
