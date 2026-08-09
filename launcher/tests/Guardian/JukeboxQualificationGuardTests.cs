using CF7Launcher.Guardian;
using Newtonsoft.Json.Linq;
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
    }
}
