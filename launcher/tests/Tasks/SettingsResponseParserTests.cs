using System.Collections.Generic;
using System.Numerics;
using CF7Launcher.Tasks;
using Newtonsoft.Json.Linq;
using Xunit;

namespace CF7Launcher.Tests.Tasks
{
    public sealed class SettingsResponseParserTests
    {
        public static IEnumerable<object[]> InvalidControlValues()
        {
            foreach (string field in new[] { "requiresReconcile", "applied", "durable", "needsSaveRetry", "migrationPending", "success" })
                foreach (string value in new[] { "null", "0", "1", "\"true\"", "{}", "[]" }) yield return new object[] { field, value };
        }
        private static JObject Failure() => new JObject {
            ["task"] = "settings_response", ["v"] = 1, ["operation"] = "save", ["success"] = false,
            ["error"] = "save_unavailable"
        };
        [Theory][MemberData(nameof(InvalidControlValues))]
        public void EveryControlFieldRequiresLiteralBoolean(string field, string value)
        {
            var response = Failure(); response[field] = JToken.Parse(value);
            var parsed = SettingsTask.ParseFlashResponseNoThrow(response, "save");
            Assert.True(parsed.Malformed); Assert.Equal(field, parsed.FailureField);
        }
        [Fact] public void OldBeforeEffectSaveFailureKeepsItsCompatibleShape()
        { Assert.False(SettingsTask.ParseFlashResponseNoThrow(Failure(), "save").Malformed); }
        [Fact] public void FailedSaveCannotClaimDurableTrue()
        {
            var response = Failure(); response["error"] = "save_failed"; response["durable"] = true;
            response["needsSaveRetry"] = true; response["revision"] = 7; response["migrationPending"] = false;
            Assert.True(SettingsTask.ParseFlashResponseNoThrow(response, "save").Malformed);
        }
        [Fact] public void UnknownFailureRequiresExactReconciliation()
        {
            var response = Failure(); response["error"] = "unexpected_after_effect";
            var parsed = SettingsTask.ParseFlashResponseNoThrow(response, "save");
            Assert.False(parsed.Malformed); Assert.True(parsed.RequiresReconcile);
        }
        [Fact] public void OversizedIntegerNeverEscapesTheParser()
        {
            var response = Failure(); response["error"] = "save_failed"; response["durable"] = false;
            response["needsSaveRetry"] = true; response["revision"] = new JValue(BigInteger.Pow(10, 80)); response["migrationPending"] = false;
            Assert.True(SettingsTask.ParseFlashResponseNoThrow(response, "save").Malformed);
        }
    }
}
