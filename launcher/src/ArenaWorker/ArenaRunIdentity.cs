using System;
using System.Text.RegularExpressions;
using Newtonsoft.Json.Linq;

namespace CF7Launcher.ArenaWorker
{
    // These values are captured before dispatch. A response must echo them;
    // the Host must never manufacture correlation fields for an AS2 result.
    internal static class ArenaRunIdentity
    {
        internal static readonly string[] Keys = {
            "workerId", "sessionEpoch", "assignmentId", "attemptId",
            "batchId", "manifestHash", "caseId", "caseHash", "runId", "repeatIndex"
        };
        private static readonly Regex SafeId = new Regex(
            "^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$", RegexOptions.Compiled);

        internal static string ReadId(JObject source, string key, string fallback = null)
        {
            JToken token = source?[key];
            string value = token == null ? fallback
                : token.Type == JTokenType.String ? token.Value<string>() : null;
            if (string.IsNullOrEmpty(value) || !SafeId.IsMatch(value))
                throw new InvalidOperationException(key + " must be a safe non-empty identity");
            return value;
        }

        internal static JObject Capture(JObject source)
        {
            var result = new JObject();
            foreach (string key in Keys) result[key] = source[key]?.DeepClone();
            return result;
        }

        internal static bool Matches(JObject expected, JObject response)
        {
            if (expected == null || response == null) return false;
            foreach (string key in Keys)
            {
                JToken actual = response[key];
                if (actual == null || actual.Type != expected[key]?.Type
                    || !JToken.DeepEquals(actual, expected[key])) return false;
            }
            return true;
        }

        internal static void Copy(JObject identity, JObject target)
        {
            foreach (JProperty field in identity.Properties())
                target[field.Name] = field.Value.DeepClone();
        }
    }
}
