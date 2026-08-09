using CF7Launcher.Guardian;
using Newtonsoft.Json.Linq;
using System.Numerics;
using Xunit;

namespace CF7Launcher.Tests.Guardian
{
    public sealed class JukeboxQualificationGuardTests
    {
        [Fact]
        public void StrictParser_RejectsDuplicateProperties()
        {
            JObject parsed;

            Assert.True(WebOverlayForm.TryParseStrictJukeboxMessage(
                "{\"type\":\"jukebox\",\"cmd\":\"stop\"}",
                out parsed));
            Assert.False(WebOverlayForm.TryParseStrictJukeboxMessage(
                "{\"type\":\"jukebox\",\"cmd\":\"stop\",\"cmd\":\"play\"}",
                out parsed));
            Assert.False(WebOverlayForm.TryParseStrictJukeboxMessage(
                "{\"type\":\"panel\",\"cmd\":\"stop\"}",
                out parsed));
        }

        [Fact]
        public void PlayRequest_RequiresExactSchemaAndAuthoritativeAvailability()
        {
            JObject exact = JObject.Parse(
                "{\"type\":\"jukebox\",\"cmd\":\"play\",\"title\":\"Qualified Track\"}");
            string title;

            Assert.False(WebOverlayForm.IsQualifiedJukeboxPlayRequest(
                exact,
                candidate => false,
                out title));
            Assert.Null(title);

            Assert.True(WebOverlayForm.IsQualifiedJukeboxPlayRequest(
                exact,
                candidate => candidate == "Qualified Track",
                out title));
            Assert.Equal("Qualified Track", title);

            JObject extra = (JObject)exact.DeepClone();
            extra["availability"] = "available";
            Assert.False(WebOverlayForm.IsQualifiedJukeboxPlayRequest(
                extra,
                candidate => true,
                out title));

            JObject wrongType = (JObject)exact.DeepClone();
            wrongType["title"] = 7;
            Assert.False(WebOverlayForm.IsQualifiedJukeboxPlayRequest(
                wrongType,
                candidate => true,
                out title));

            JObject missing = (JObject)exact.DeepClone();
            missing.Remove("title");
            Assert.False(WebOverlayForm.IsQualifiedJukeboxPlayRequest(
                missing,
                candidate => true,
                out title));
        }

        [Fact]
        public void SeekRequest_RequiresExactSchemaAndFiniteBoundedNumber()
        {
            double seconds;
            JObject exact = JObject.Parse(
                "{\"type\":\"jukebox\",\"cmd\":\"seek\",\"sec\":12.5}");

            Assert.True(WebOverlayForm.IsQualifiedJukeboxSeekRequest(
                exact, out seconds));
            Assert.Equal(12.5, seconds);

            JObject zero = JObject.Parse(
                "{\"type\":\"jukebox\",\"cmd\":\"seek\",\"sec\":0}");
            Assert.True(WebOverlayForm.IsQualifiedJukeboxSeekRequest(
                zero, out seconds));
            Assert.Equal(0, seconds);

            JObject extra = (JObject)exact.DeepClone();
            extra["path"] = "sounds/forged.mp3";
            Assert.False(WebOverlayForm.IsQualifiedJukeboxSeekRequest(
                extra, out seconds));

            JObject wrongType = (JObject)exact.DeepClone();
            wrongType["sec"] = "12.5";
            Assert.False(WebOverlayForm.IsQualifiedJukeboxSeekRequest(
                wrongType, out seconds));

            JObject negative = (JObject)exact.DeepClone();
            negative["sec"] = -0.01;
            Assert.False(WebOverlayForm.IsQualifiedJukeboxSeekRequest(
                negative, out seconds));

            JObject overBound = (JObject)exact.DeepClone();
            overBound["sec"] = 86400.01;
            Assert.False(WebOverlayForm.IsQualifiedJukeboxSeekRequest(
                overBound, out seconds));

            JObject nonFinite = (JObject)exact.DeepClone();
            nonFinite["sec"] = double.NaN;
            Assert.False(WebOverlayForm.IsQualifiedJukeboxSeekRequest(
                nonFinite, out seconds));

            JObject hugeInteger = (JObject)exact.DeepClone();
            hugeInteger["sec"] = new JValue(
                BigInteger.Parse(new string('9', 400)));
            Assert.False(WebOverlayForm.IsQualifiedJukeboxSeekRequest(
                hugeInteger, out seconds));

            JObject missing = (JObject)exact.DeepClone();
            missing.Remove("sec");
            Assert.False(WebOverlayForm.IsQualifiedJukeboxSeekRequest(
                missing, out seconds));
        }
    }
}
