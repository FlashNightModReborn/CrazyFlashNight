using System;
using System.Collections.Generic;
using Newtonsoft.Json.Linq;

namespace CF7Launcher.Tasks
{
    public sealed partial class SettingsTask
    {
        internal sealed class ParsedSettingsResponse
        {
            internal bool Malformed = true, Success, RequiresReconcile;
            internal JObject Response;
            internal string FailureField;
        }
        private static readonly HashSet<string> BeforeEffectErrors = new HashSet<string>(StringComparer.Ordinal) {
            "unsupported_version", "unsupported_cmd", "invalid_payload", "invalid_settings", "invalid_keys",
            "reserved_key", "key_conflict", "save_unavailable", "settings_unavailable"
        };
        private static readonly string[] ResponseControlFlags = {
            "success", "requiresReconcile", "applied", "durable", "needsSaveRetry", "migrationPending",
            "previewActive", "previewRestored", "samplePlayed", "accepted", "dirty", "challengeMode", "revived", "closePanel"
        };
        private static int ReadResponseCorrelationNoThrow(JObject raw)
        {
            try { return ReadPositiveInt(raw?["callId"]); } catch { return 0; }
        }
        internal static ParsedSettingsResponse ParseFlashResponseNoThrow(JObject raw, string command)
        {
            var parsed = new ParsedSettingsResponse();
            try {
                if (raw == null) { parsed.FailureField = "response"; return parsed; }
                var response = (JObject)raw.DeepClone();
                foreach (string flag in ResponseControlFlags) {
                    JToken token = response[flag];
                    if (token != null && token.Type != JTokenType.Boolean) { parsed.FailureField = flag; return parsed; }
                }
                if (response["success"]?.Type != JTokenType.Boolean) { parsed.FailureField = "success"; return parsed; }
                if (response["operation"] != null &&
                    (response["operation"].Type != JTokenType.String || (string)response["operation"] != command)) {
                    parsed.FailureField = "operation"; return parsed;
                }
                bool success = (bool)response["success"];
                bool reconcile = response["requiresReconcile"]?.Type == JTokenType.Boolean && (bool)response["requiresReconcile"];
                if (!success && command == "save" && (string)response["error"] == "save_failed") {
                    long revision;
                    if (response["durable"]?.Type != JTokenType.Boolean || (bool)response["durable"] ||
                        response["needsSaveRetry"]?.Type != JTokenType.Boolean || !(bool)response["needsSaveRetry"] ||
                        !TryInteger(response["revision"], 0, int.MaxValue, out revision) || !IsBoolean(response["migrationPending"])) {
                        parsed.FailureField = "save_failed"; return parsed;
                    }
                }
                if (!success && command == "apply" && (string)response["error"] == "stale_state" &&
                    response["applied"] != null && (bool)response["applied"]) { parsed.FailureField = "applied"; return parsed; }
                if (!success && BeforeEffectErrors.Contains((string)response["error"])) {
                    if (response["applied"] != null && (bool)response["applied"] ||
                        response["durable"] != null && (bool)response["durable"] ||
                        response["needsSaveRetry"] != null && (bool)response["needsSaveRetry"]) {
                        parsed.FailureField = "before_effect"; return parsed;
                    }
                }
                if (IsMalformedFlashResponse(response, command)) { parsed.FailureField = "shape"; return parsed; }
                if (!success && command != "snapshot" && command != "preview" && command != "cancel" &&
                    !BeforeEffectErrors.Contains((string)response["error"]) &&
                    (string)response["error"] != "stale_state" && (string)response["error"] != "save_failed") reconcile = true;
                if (reconcile && response["needsSaveRetry"] != null && (bool)response["needsSaveRetry"]) {
                    parsed.FailureField = "needsSaveRetry"; return parsed;
                }
                if (reconcile) response["requiresReconcile"] = true;
                parsed.Response = response;
                parsed.Success = success; parsed.RequiresReconcile = reconcile; parsed.Malformed = false;
                return parsed;
            } catch (Exception error) { parsed.FailureField = error.GetType().Name; return parsed; }
        }
    }
}
