using Newtonsoft.Json;
using Newtonsoft.Json.Linq;

namespace CF7Launcher.Guardian.Handlers
{
    internal static class CharacterCreateCommandHandler
    {
        internal static void HandleOpen(
            JObject message,
            BootstrapPanel bootForm,
            GameLaunchFlow launchFlow)
        {
            string mode = ReadExactString(message, "mode");
            string requestedSlot = ReadExactString(message, "slotKey");
            string openRequestId = ReadExactString(message, "openRequestId");
            if (launchFlow == null)
            {
                PostState(bootForm, "rejected", openRequestId, null, requestedSlot,
                    "flash_start_failed", true);
                return;
            }

            string attemptId;
            string slotKey;
            string error;
            if (!launchFlow.OpenCharacterCreate(
                    mode,
                    requestedSlot,
                    openRequestId,
                    out attemptId,
                    out slotKey,
                    out error))
            {
                PostState(bootForm, "rejected", openRequestId, null, requestedSlot, error, true);
            }
        }

        internal static void HandleSubmit(
            JObject message,
            BootstrapPanel bootForm,
            GameLaunchFlow launchFlow)
        {
            string openRequestId = ReadExactString(message, "openRequestId");
            string attemptId = ReadExactString(message, "attemptId");
            string slotKey = ReadExactString(message, "slotKey");
            string displayName = ReadExactString(message, "displayName");
            bool? displayNameCustomized = ReadExactBoolean(
                message,
                "displayNameCustomized");
            JObject draft = message != null ? message["draft"] as JObject : null;
            if (launchFlow == null)
            {
                PostState(bootForm, "rejected", openRequestId, attemptId, slotKey,
                    "flash_start_failed", true);
                return;
            }
            if (string.IsNullOrEmpty(attemptId))
            {
                PostState(bootForm, "rejected", openRequestId, null, slotKey,
                    "attempt_missing", false);
                return;
            }
            if (!displayNameCustomized.HasValue)
            {
                PostState(bootForm, "rejected", openRequestId, attemptId, slotKey,
                    "display_name_customization_missing", false);
                return;
            }

            string error;
            if (!launchFlow.SubmitCharacterCreate(
                    openRequestId,
                    attemptId,
                    slotKey,
                    displayNameCustomized.Value,
                    displayName,
                    draft,
                    out error))
            {
                PostState(bootForm, "rejected", openRequestId, attemptId, slotKey,
                    error, error != "stale_attempt"
                        && error != "submit_already_pending");
            }
        }

        private static string ReadExactString(JObject message, string key)
        {
            JToken token = message != null ? message[key] : null;
            return token != null && token.Type == JTokenType.String
                ? token.Value<string>()
                : null;
        }

        private static bool? ReadExactBoolean(JObject message, string key)
        {
            JToken token = message != null ? message[key] : null;
            return token != null && token.Type == JTokenType.Boolean
                ? token.Value<bool?>()
                : null;
        }

        private static void PostState(
            BootstrapPanel bootForm,
            string phase,
            string openRequestId,
            string attemptId,
            string slotKey,
            string error,
            bool retryable)
        {
            JObject response = new JObject
            {
                ["type"] = "bootstrap",
                ["cmd"] = "character_create_state",
                ["phase"] = phase,
                ["retryable"] = retryable
            };
            if (openRequestId != null) response["openRequestId"] = openRequestId;
            if (attemptId != null) response["attemptId"] = attemptId;
            if (slotKey != null) response["slotKey"] = slotKey;
            if (error != null) response["error"] = error;
            bootForm.PostToWeb(response.ToString(Formatting.None));
        }
    }
}
