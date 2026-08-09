using System;
using System.Globalization;
using Newtonsoft.Json;
using Newtonsoft.Json.Linq;

namespace CF7Launcher.Audio
{
    /// <summary>
    /// Strict projection of one immutable coordinator snapshot onto the two
    /// Audio Platform v2 lifecycle envelopes consumed by AS2.
    /// </summary>
    internal static class AudioLifecycleWireV2
    {
        internal static bool TrySerialize(
            AudioCoordinatorSnapshotV2 snapshot,
            out string json,
            out string error)
        {
            json = null;
            error = null;
            if (snapshot == null)
            {
                error = "audio.lifecycle.snapshot_null";
                return false;
            }
            if (!IsCanonicalUuidV4(snapshot.AudioSessionId))
            {
                error = "audio.lifecycle.session";
                return false;
            }

            string readyGeneration = snapshot.AudioReadyGeneration.ToString(
                CultureInfo.InvariantCulture);
            string deviceGeneration = snapshot.DeviceGeneration.ToString(
                CultureInfo.InvariantCulture);

            JObject envelope;
            if (snapshot.IsReady)
            {
                if (snapshot.AudioReadyGeneration == 0uL ||
                    snapshot.DeviceGeneration == 0uL ||
                    snapshot.Loaded < 0 || snapshot.Failed < 0 ||
                    snapshot.Overrides < 0 ||
                    !IsSha256Hex(snapshot.CapabilityDigest))
                {
                    error = "audio.lifecycle.ready_invalid";
                    return false;
                }
                envelope = new JObject
                {
                    ["task"] = "audio_ready",
                    ["wireRevision"] = AudioWireV2.WireRevision,
                    ["audioSessionId"] = snapshot.AudioSessionId,
                    ["audioReadyGeneration"] = readyGeneration,
                    ["deviceGeneration"] = deviceGeneration,
                    ["loaded"] = snapshot.Loaded,
                    ["failed"] = snapshot.Failed,
                    ["overrides"] = snapshot.Overrides,
                    ["capabilityDigest"] = snapshot.CapabilityDigest
                };
            }
            else
            {
                string category = CategoryName(snapshot.FailureCategory);
                if (category == "ok") category = "not_ready";
                string messageKey = snapshot.MessageKey;
                if (!IsMessageKey(messageKey))
                    messageKey = "audio.lifecycle_invalid_state";
                envelope = new JObject
                {
                    ["task"] = "audio_unavailable",
                    ["wireRevision"] = AudioWireV2.WireRevision,
                    ["audioSessionId"] = snapshot.AudioSessionId,
                    ["audioReadyGeneration"] = readyGeneration,
                    ["deviceGeneration"] = deviceGeneration,
                    ["category"] = category,
                    ["messageKey"] = messageKey
                };
            }

            json = envelope.ToString(Formatting.None);
            return true;
        }

        private static string CategoryName(uint value)
        {
            string[] names =
            {
                "ok", "missing", "unsupported_container",
                "unsupported_codec", "malformed", "truncated",
                "io_error", "abi_mismatch", "not_ready",
                "stale_generation", "unknown_id", "throttled",
                "start_failed", "seek_failed", "device_unavailable",
                "device_lost", "superseded", "internal_error"
            };
            return value < (uint)names.Length
                ? names[(int)value]
                : "internal_error";
        }

        private static bool IsCanonicalUuidV4(string value)
        {
            Guid parsed;
            return value != null && value.Length == 36 &&
                Guid.TryParseExact(value, "D", out parsed) &&
                string.Equals(
                    parsed.ToString("D"),
                    value,
                    StringComparison.Ordinal) &&
                value[14] == '4' &&
                (value[19] == '8' || value[19] == '9' ||
                    value[19] == 'a' || value[19] == 'b');
        }

        private static bool IsSha256Hex(string value)
        {
            if (value == null || value.Length != 64) return false;
            for (int index = 0; index < value.Length; index++)
            {
                char c = value[index];
                if (!((c >= '0' && c <= '9') ||
                    (c >= 'a' && c <= 'f') ||
                    (c >= 'A' && c <= 'F'))) return false;
            }
            return true;
        }

        private static bool IsMessageKey(string value)
        {
            if (string.IsNullOrEmpty(value) || value.Length > 128)
                return false;
            for (int index = 0; index < value.Length; index++)
            {
                char c = value[index];
                if (!((c >= 'a' && c <= 'z') ||
                    (c >= '0' && c <= '9') ||
                    c == '.' || c == '_' || c == '-')) return false;
            }
            return true;
        }
    }
}
