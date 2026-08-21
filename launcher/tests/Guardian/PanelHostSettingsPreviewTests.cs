using System;
using System.Drawing;
using System.IO;
using CF7Launcher.Guardian;
using Newtonsoft.Json.Linq;
using Xunit;

namespace CF7Launcher.Tests.Guardian
{
    public sealed class PanelHostSettingsPreviewTests
    {
        [Fact]
        public void EntrySnapshot_PreservesCroppedOriginalResolutionInBoundedDataUri()
        {
            using (var source = new Bitmap(1280, 800))
            {
                using (Graphics graphics = Graphics.FromImage(source))
                {
                    graphics.Clear(Color.FromArgb(35, 72, 126));
                    graphics.FillRectangle(Brushes.Orange, 320, 240, 400, 180);
                }
                int width;
                int height;
                string dataUrl = PanelHostController.EncodePanelPreviewDataUri(
                    source,
                    new Rectangle(0, 40, 1280, 720),
                    out width,
                    out height);
                Assert.StartsWith("data:image/jpeg;base64,", dataUrl, StringComparison.Ordinal);
                Assert.True(dataUrl.Length < PanelHostController.SettingsPreviewMaximumDataUriCharacters);
                Assert.Equal(1280, width);
                Assert.Equal(720, height);
                byte[] bytes = Convert.FromBase64String(dataUrl.Substring(dataUrl.IndexOf(',') + 1));
                using (var stream = new MemoryStream(bytes))
                using (Image decoded = Image.FromStream(stream))
                {
                    Assert.Equal(1280, decoded.Width);
                    Assert.Equal(720, decoded.Height);
                }
            }
        }

        [Theory]
        [InlineData(1024, 576, true)]
        [InlineData(1600, 900, true)]
        [InlineData(4096, 2304, true)]
        [InlineData(4097, 2304, false)]
        [InlineData(1024, 600, false)]
        [InlineData(0, 576, false)]
        public void PreviewDimensions_RequireBoundedSixteenByNineOriginalPixels(
            int width,
            int height,
            bool accepted)
        {
            Assert.Equal(
                accepted,
                PanelHostController.AreSettingsPreviewDimensionsValid(width, height));
        }

        [Fact]
        public void Preview_IsAttachedOnlyToSettingsInitData()
        {
            const string uri = "data:image/jpeg;base64,QUJDRA==";
            string settingsJson = PanelHostController.AttachSettingsFlashPreview(
                "settings", "{\"existing\":true}", uri, 1280, 720);
            JObject settings = JObject.Parse(settingsJson);
            Assert.True(settings.Value<bool>("existing"));
            Assert.Equal(1, settings["flashPreview"].Value<int>("v"));
            Assert.Equal("entry_flash_snapshot", settings["flashPreview"].Value<string>("source"));
            Assert.Equal(1280, settings["flashPreview"].Value<int>("width"));
            Assert.Equal(720, settings["flashPreview"].Value<int>("height"));
            Assert.Equal(uri, settings["flashPreview"].Value<string>("dataUrl"));
            JObject openPayload = JObject.Parse(PanelHostController.BuildPanelOpenPayload(
                "settings", settingsJson, "settings.preview.instance"));
            Assert.Equal(uri, openPayload["initData"]["flashPreview"].Value<string>("dataUrl"));
            Assert.Equal("settings.preview.instance", openPayload["initData"].Value<string>("panelInstanceId"));

            const string untouched = "{\"existing\":true}";
            Assert.Equal(untouched, PanelHostController.AttachSettingsFlashPreview(
                "workbench", untouched, uri, 1280, 720));
            Assert.Equal(untouched, PanelHostController.AttachSettingsFlashPreview(
                "settings", untouched, null, 0, 0));
            Assert.Equal(untouched, PanelHostController.AttachSettingsFlashPreview(
                "settings", untouched, uri, 1024, 600));
            JObject stripped = JObject.Parse(PanelHostController.AttachSettingsFlashPreview(
                "settings", "{\"flashPreview\":{\"source\":\"caller_spoof\"}}", null, 0, 0));
            Assert.Null(stripped["flashPreview"]);
        }
    }
}
