using System;
using System.Buffers;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Security.Cryptography;
using System.Text;
using System.Text.Encodings.Web;
using System.Text.Json;
using System.Text.Json.Nodes;

namespace CF7Launcher.AgentRuntime.Contracts
{
    /// <summary>
    /// CF7 v1 canonical JSON profile used for action idempotency.
    /// Objects are ordinal-key-sorted, arrays retain order, strings retain Unicode code points,
    /// and numbers are restricted to the interoperable signed integer range.
    /// </summary>
    public static class CanonicalJsonV1
    {
        public const long MaximumSafeInteger = 9_007_199_254_740_991L;
        public const long MinimumSafeInteger = -9_007_199_254_740_991L;

        public static string CreateActionPayload(ActionEnvelope action)
        {
            if (action == null) throw new ArgumentNullException(nameof(action));
            if (action.Arguments.ValueKind == JsonValueKind.Undefined)
                throw new InvalidDataException("Action arguments must be a JSON object.");

            var root = new JsonObject
            {
                ["operation"] = action.Operation,
                ["arguments"] = JsonNode.Parse(action.Arguments.GetRawText()),
                ["sessionId"] = action.SessionId,
                ["observationGrantId"] = action.ObservationGrantId,
                ["leaseId"] = action.LeaseId,
                ["observationId"] = action.ObservationId,
                ["expectedLifecycleGeneration"] = action.ExpectedLifecycleGeneration,
                ["targetId"] = action.TargetId,
                ["expectedSurfaceEpoch"] = action.ExpectedSurfaceEpoch,
                ["expectedCoordinateSpaceVersion"] = action.ExpectedCoordinateSpaceVersion,
                ["expectedFocusEpoch"] = action.ExpectedFocusEpoch,
                ["expectedModalEpoch"] = action.ExpectedModalEpoch
            };
            AddIfNotNull(root, "expectedAttemptId", action.ExpectedAttemptId);
            AddIfHasValue(root, "expectedAttemptGeneration", action.ExpectedAttemptGeneration);
            AddIfNotNull(root, "expectedPanelInstanceId", action.ExpectedPanelInstanceId);
            AddIfHasValue(root, "expectedSemanticGeneration", action.ExpectedSemanticGeneration);
            AddIfHasValue(root, "expectedDocumentGeneration", action.ExpectedDocumentGeneration);
            AddIfNotNull(root, "frameId", action.FrameId);
            AddIfNotNull(root, "semanticSnapshotId", action.SemanticSnapshotId);
            AddIfNotNull(root, "nodeId", action.NodeId);
            return Canonicalize(root.ToJsonString(AgentProtocolV1.JsonOptions));
        }

        public static byte[] CreateActionPayloadUtf8(ActionEnvelope action)
        {
            return Encoding.UTF8.GetBytes(CreateActionPayload(action));
        }

        public static string ComputeActionPayloadSha256(ActionEnvelope action)
        {
            return Convert.ToHexString(SHA256.HashData(CreateActionPayloadUtf8(action)));
        }

        public static string CreateArgumentBoundsPayload(
            string operation,
            JsonElement arguments)
        {
            if (string.IsNullOrWhiteSpace(operation))
                throw new ArgumentException(
                    "An operation is required.",
                    nameof(operation));
            if (arguments.ValueKind != JsonValueKind.Object)
                throw new InvalidDataException(
                    "Argument bounds require a JSON object.");

            var root = new JsonObject
            {
                ["operation"] = operation,
                ["arguments"] =
                    JsonNode.Parse(arguments.GetRawText())
            };
            return Canonicalize(
                root.ToJsonString(
                    AgentProtocolV1.JsonOptions));
        }

        public static string ComputeArgumentBoundsSha256(
            string operation,
            JsonElement arguments)
        {
            return Convert.ToHexString(
                SHA256.HashData(
                    Encoding.UTF8.GetBytes(
                        CreateArgumentBoundsPayload(
                            operation,
                            arguments))));
        }

        public static bool FixedTimeEqualsSha256(
            string expected,
            string actual)
        {
            if (expected == null || actual == null)
                return false;
            try
            {
                byte[] expectedBytes =
                    Convert.FromHexString(expected);
                byte[] actualBytes =
                    Convert.FromHexString(actual);
                return expectedBytes.Length == 32
                    && actualBytes.Length == 32
                    && CryptographicOperations.FixedTimeEquals(
                        expectedBytes,
                        actualBytes);
            }
            catch (FormatException)
            {
                return false;
            }
            catch (ArgumentException)
            {
                return false;
            }
        }

        public static string Canonicalize(string json)
        {
            if (json == null) throw new ArgumentNullException(nameof(json));
            byte[] utf8 = Encoding.UTF8.GetBytes(json);
            using JsonDocument document = JsonDocument.Parse(
                utf8,
                new JsonDocumentOptions
                {
                    AllowTrailingCommas = false,
                    CommentHandling = JsonCommentHandling.Disallow,
                    MaxDepth = 64
                });

            var buffer = new ArrayBufferWriter<byte>();
            using (var writer = new Utf8JsonWriter(
                buffer,
                new JsonWriterOptions
                {
                    Encoder = JavaScriptEncoder.UnsafeRelaxedJsonEscaping,
                    Indented = false,
                    SkipValidation = false
                }))
            {
                WriteElement(writer, document.RootElement, "$", 0);
            }
            return Encoding.UTF8.GetString(buffer.WrittenSpan);
        }

        private static void WriteElement(Utf8JsonWriter writer, JsonElement value, string path, int depth)
        {
            if (depth > 64) throw new InvalidDataException("Canonical JSON exceeds depth 64 at " + path + ".");
            switch (value.ValueKind)
            {
                case JsonValueKind.Object:
                    writer.WriteStartObject();
                    var properties = value.EnumerateObject().ToArray();
                    var names = new HashSet<string>(StringComparer.Ordinal);
                    foreach (JsonProperty property in properties)
                    {
                        if (!names.Add(property.Name))
                            throw new InvalidDataException("Duplicate JSON property at " + path + "." + property.Name + ".");
                    }
                    foreach (JsonProperty property in properties.OrderBy(item => item.Name, StringComparer.Ordinal))
                    {
                        writer.WritePropertyName(property.Name);
                        WriteElement(writer, property.Value, path + "." + property.Name, depth + 1);
                    }
                    writer.WriteEndObject();
                    break;

                case JsonValueKind.Array:
                    writer.WriteStartArray();
                    int index = 0;
                    foreach (JsonElement item in value.EnumerateArray())
                    {
                        WriteElement(writer, item, path + "[" + index + "]", depth + 1);
                        index++;
                    }
                    writer.WriteEndArray();
                    break;

                case JsonValueKind.String:
                    writer.WriteStringValue(value.GetString());
                    break;

                case JsonValueKind.Number:
                    if (!TryReadCanonicalInteger(value, out long integer) ||
                        integer < MinimumSafeInteger ||
                        integer > MaximumSafeInteger)
                    {
                        throw new InvalidDataException(
                            "Canonical action JSON permits only interoperable signed integers at " + path + ".");
                    }
                    writer.WriteNumberValue(integer);
                    break;

                case JsonValueKind.True:
                    writer.WriteBooleanValue(true);
                    break;

                case JsonValueKind.False:
                    writer.WriteBooleanValue(false);
                    break;

                case JsonValueKind.Null:
                    writer.WriteNullValue();
                    break;

                default:
                    throw new InvalidDataException("Unsupported JSON token at " + path + ".");
            }
        }

        private static bool TryReadCanonicalInteger(JsonElement value, out long integer)
        {
            if (value.TryGetInt64(out integer)) return true;
            if (!decimal.TryParse(
                    value.GetRawText(),
                    NumberStyles.AllowLeadingSign | NumberStyles.AllowDecimalPoint |
                    NumberStyles.AllowExponent,
                    CultureInfo.InvariantCulture,
                    out decimal parsed) ||
                parsed != decimal.Truncate(parsed) ||
                parsed < long.MinValue ||
                parsed > long.MaxValue)
            {
                integer = 0;
                return false;
            }
            integer = decimal.ToInt64(parsed);
            return true;
        }

        private static void AddIfNotNull(JsonObject root, string name, string value)
        {
            if (value != null) root[name] = value;
        }

        private static void AddIfHasValue(JsonObject root, string name, ulong? value)
        {
            if (value.HasValue) root[name] = value.Value;
        }
    }
}
