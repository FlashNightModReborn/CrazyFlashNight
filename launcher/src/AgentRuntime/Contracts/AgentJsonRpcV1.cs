using System;
using System.Buffers.Binary;
using System.Collections.Generic;
using System.Collections.ObjectModel;
using System.IO;
using System.Linq;
using System.Text;
using System.Text.Json;
using System.Text.Json.Serialization;
using System.Text.RegularExpressions;

namespace CF7Launcher.AgentRuntime.Contracts
{
    public sealed class AgentMethodDefinition
    {
        internal AgentMethodDefinition(
            string name,
            string requiredCapability,
            string parameterContract,
            bool preAuthentication)
        {
            Name = name;
            RequiredCapability = requiredCapability;
            ParameterContract = parameterContract;
            PreAuthentication = preAuthentication;
        }

        public string Name { get; }
        public string RequiredCapability { get; }
        public string ParameterContract { get; }
        public bool PreAuthentication { get; }
    }

    /// <summary>
    /// Closed v1 method registry. GUI capabilities are the wire methods;
    /// there is intentionally no second generic action.execute route.
    /// </summary>
    public static class AgentMethodsV1
    {
        public const string RuntimeHello = "runtime.hello";
        public const string ObservationGrantIssue =
            "observation.grant.issue";
        public const string ObservationGrantRevoke =
            "observation.grant.revoke";
        public const string ObservationCapture =
            "observation.capture";
        public const string ObservationGet = "observation.get";
        public const string ObservationAck = "observation.ack";
        public const string ContentRead = "content.read";
        public const string ActionGet = "action.get";
        public const string HairInspect =
            "appearance.hair.change.v1.inspect";
        public const string HairPreview =
            "appearance.hair.change.v1.preview";
        public const string HairConsent =
            "appearance.hair.change.v1.consent";
        public const string HairCommit =
            "appearance.hair.change.v1.commit";
        public const string HairReconcile =
            "appearance.hair.change.v1.reconcile";
        public const string HairRestore =
            "appearance.hair.change.v1.restore";

        private static readonly IReadOnlyDictionary<
            string,
            AgentMethodDefinition> Registry =
            new ReadOnlyDictionary<
                string,
                AgentMethodDefinition>(
                new[]
                {
                    Define(
                        RuntimeHello,
                        null,
                        "hello",
                        true),

                    DefineCapability(
                        AgentCapabilitiesV1.ListWindows,
                        "windowList"),
                    DefineCapability(
                        AgentCapabilitiesV1.GetWindow,
                        "windowTarget"),
                    DefineCapability(
                        AgentCapabilitiesV1.ListApps,
                        "empty"),
                    DefineCapability(
                        AgentCapabilitiesV1.LaunchApp,
                        "appLaunch"),
                    DefineCapability(
                        AgentCapabilitiesV1.GetWindowState,
                        "windowState"),
                    DefineCapability(
                        AgentCapabilitiesV1.Click,
                        "actionEnvelope"),
                    DefineCapability(
                        AgentCapabilitiesV1.PressKey,
                        "actionEnvelope"),
                    DefineCapability(
                        AgentCapabilitiesV1.TypeText,
                        "actionEnvelope"),
                    DefineCapability(
                        AgentCapabilitiesV1.Scroll,
                        "actionEnvelope"),
                    DefineCapability(
                        AgentCapabilitiesV1.SetValue,
                        "actionEnvelope"),
                    DefineCapability(
                        AgentCapabilitiesV1.Drag,
                        "actionEnvelope"),
                    DefineCapability(
                        AgentCapabilitiesV1
                            .PerformSecondaryAction,
                        "actionEnvelope"),
                    DefineCapability(
                        AgentCapabilitiesV1.ActivateWindow,
                        "actionEnvelope"),

                    DefineCapability(
                        AgentCapabilitiesV1.SessionStatus,
                        "empty"),
                    DefineCapability(
                        AgentCapabilitiesV1.SessionDiscover,
                        "empty"),
                    DefineCapability(
                        AgentCapabilitiesV1.SessionAttach,
                        "sessionBinding"),
                    DefineCapability(
                        AgentCapabilitiesV1.SessionDetach,
                        "sessionBinding"),
                    DefineCapability(
                        AgentCapabilitiesV1.SessionShutdown,
                        "actionEnvelope"),
                    DefineCapability(
                        AgentCapabilitiesV1.LifecycleReveal,
                        "actionEnvelope"),
                    DefineCapability(
                        AgentCapabilitiesV1.LifecycleCancel,
                        "actionEnvelope"),
                    DefineCapability(
                        AgentCapabilitiesV1.PanelOpen,
                        "actionEnvelope"),
                    DefineCapability(
                        AgentCapabilitiesV1.LeaseAcquire,
                        "leaseAcquire"),
                    DefineCapability(
                        AgentCapabilitiesV1.LeaseRenew,
                        "leaseRenew"),
                    DefineCapability(
                        AgentCapabilitiesV1.LeaseRelease,
                        "leaseRelease"),
                    DefineCapability(
                        AgentCapabilitiesV1.TraceExport,
                        "traceExport"),

                    Define(
                        ObservationGrantIssue,
                        AgentCapabilitiesV1
                            .ObservationGrantManage,
                        "observationGrantIssue",
                        false),
                    Define(
                        ObservationGrantRevoke,
                        AgentCapabilitiesV1
                            .ObservationGrantManage,
                        "observationGrantRevoke",
                        false),
                    Define(
                        ObservationCapture,
                        AgentCapabilitiesV1
                            .ObservationCapture,
                        "observationCapture",
                        false),
                    Define(
                        ObservationGet,
                        AgentCapabilitiesV1
                            .ObservationCapture,
                        "observationReference",
                        false),
                    Define(
                        ObservationAck,
                        AgentCapabilitiesV1
                            .ObservationCapture,
                        "observationReference",
                        false),
                    Define(
                        ContentRead,
                        AgentCapabilitiesV1.ContentRead,
                        "contentReadRequest",
                        false),
                    Define(
                        ActionGet,
                        AgentCapabilitiesV1.ActionGet,
                        "actionGet",
                        false),

                    DefineHair(HairInspect, "hairInspect"),
                    DefineHair(HairPreview, "hairPreview"),
                    DefineHair(HairConsent, "hairConsent"),
                    DefineHair(HairCommit, "actionEnvelope"),
                    DefineHair(HairReconcile, "hairReconcile"),
                    DefineHair(HairRestore, "actionEnvelope")
                }.ToDictionary(
                    definition => definition.Name,
                    StringComparer.Ordinal));

        public static IReadOnlyDictionary<
            string,
            AgentMethodDefinition> All => Registry;

        public static bool TryGet(
            string method,
            out AgentMethodDefinition definition)
        {
            return Registry.TryGetValue(
                method ?? string.Empty,
                out definition);
        }

        private static AgentMethodDefinition DefineCapability(
            string capability,
            string parameterContract = "object")
        {
            return Define(
                capability,
                capability,
                parameterContract,
                false);
        }

        private static AgentMethodDefinition DefineHair(
            string name,
            string parameterContract)
        {
            return Define(
                name,
                AgentCapabilitiesV1.AppearanceHairChange,
                parameterContract,
                false);
        }

        private static AgentMethodDefinition Define(
            string name,
            string requiredCapability,
            string parameterContract,
            bool preAuthentication)
        {
            return new AgentMethodDefinition(
                name,
                requiredCapability,
                parameterContract,
                preAuthentication);
        }
    }

    public sealed class AgentJsonRpcRequest
    {
        [JsonPropertyName("jsonrpc")]
        public string JsonRpc { get; set; } = "2.0";

        public string Id { get; set; }
        public string Method { get; set; }
        public JsonElement Params { get; set; }
    }

    public sealed class AgentJsonRpcSuccessResponse
    {
        [JsonPropertyName("jsonrpc")]
        public string JsonRpc { get; set; } = "2.0";

        public string Id { get; set; }
        public JsonElement Result { get; set; }
    }

    public sealed class AgentJsonRpcErrorResponse
    {
        [JsonPropertyName("jsonrpc")]
        public string JsonRpc { get; set; } = "2.0";

        public string Id { get; set; }
        public AgentJsonRpcError Error { get; set; }
    }

    public sealed class AgentJsonRpcError
    {
        public int Code { get; set; }
        public string Message { get; set; }
        public AgentJsonRpcErrorData Data { get; set; }
    }

    public sealed class AgentJsonRpcErrorData
    {
        public string ReasonCode { get; set; }
        public bool Retryable { get; set; }
        public ReconcileKind ReconcileKind { get; set; }
        public ulong ServerSequence { get; set; }
    }

    public sealed class ContentReadRequest
    {
        public string Handle { get; set; }
        public long Offset { get; set; }
        public int Count { get; set; }
    }

    public sealed class BinaryChunkMetadata
    {
        public string Handle { get; set; }
        public long Offset { get; set; }
        public long TotalLength { get; set; }
        public bool Final { get; set; }
        public string ContentHash { get; set; }
    }

    public sealed class DecodedBinaryChunk
    {
        internal DecodedBinaryChunk(
            BinaryChunkMetadata metadata,
            byte[] content)
        {
            Metadata = metadata;
            Content = content;
        }

        public BinaryChunkMetadata Metadata { get; }
        public byte[] Content { get; }
    }

    public static class AgentJsonRpcValidator
    {
        private static readonly Regex OpaqueIdPattern = new Regex(
            "^[A-Za-z0-9_-]{"
                + AgentProtocolV1.MinimumOpaqueIdCharacters
                + ","
                + AgentProtocolV1.MaximumOpaqueIdCharacters
                + "}$",
            RegexOptions.CultureInvariant);

        public static IReadOnlyList<ContractViolation>
            ValidateRequest(JsonElement root)
        {
            var errors = new List<ContractViolation>();
            if (root.ValueKind != JsonValueKind.Object)
            {
                Error(
                    errors,
                    "$",
                    "rpc_request_object_required",
                    "Batch, scalar, and null requests are not accepted.");
                return errors;
            }
            RejectDuplicateProperties(root, "$", errors);
            ExactProperties(
                root,
                new[] { "jsonrpc", "id", "method", "params" },
                "$",
                errors);
            ExactString(root, "jsonrpc", "2.0", errors);
            ValidateId(root, errors);

            string method = ReadRequiredString(
                root,
                "method",
                "$.method",
                128,
                errors);
            if (method != null
                && !AgentMethodsV1.TryGet(method, out _))
            {
                Error(
                    errors,
                    "$.method",
                    "rpc_method_not_found",
                    "The method is not in the closed v1 registry.");
            }

            if (!root.TryGetProperty(
                    "params",
                    out JsonElement parameters)
                || parameters.ValueKind
                    != JsonValueKind.Object)
            {
                Error(
                    errors,
                    "$.params",
                    "rpc_params_object_required",
                    "Named object params are required.");
            }
            else if (method != null)
            {
                foreach (ContractViolation violation
                    in ValidateParameters(
                        method,
                        parameters))
                {
                    errors.Add(violation);
                }
            }
            return errors;
        }

        public static IReadOnlyList<ContractViolation>
            ValidateParameters(
                string method,
                JsonElement parameters)
        {
            var errors = new List<ContractViolation>();
            if (parameters.ValueKind
                != JsonValueKind.Object)
            {
                Error(
                    errors,
                    "$.params",
                    "rpc_params_object_required",
                    "Named object params are required.");
                return errors;
            }
            if (string.Equals(
                method,
                AgentMethodsV1.RuntimeHello,
                StringComparison.Ordinal))
            {
                ValidateHello(parameters, errors);
                return errors;
            }
            foreach (ContractViolation violation
                in AgentMethodParameterValidatorV1.Validate(
                    method,
                    parameters))
            {
                errors.Add(violation);
            }
            return errors;
        }

        public static IReadOnlyList<ContractViolation>
            ValidateResponse(JsonElement root)
        {
            var errors = new List<ContractViolation>();
            if (root.ValueKind != JsonValueKind.Object)
            {
                Error(
                    errors,
                    "$",
                    "rpc_response_object_required",
                    "A single response object is required.");
                return errors;
            }
            RejectDuplicateProperties(root, "$", errors);
            bool hasResult = root.TryGetProperty(
                "result",
                out _);
            bool hasError = root.TryGetProperty(
                "error",
                out JsonElement error);
            if (hasResult == hasError)
            {
                Error(
                    errors,
                    "$",
                    "rpc_result_error_exclusive",
                    "Exactly one of result or error is required.");
                return errors;
            }
            ExactProperties(
                root,
                hasResult
                    ? new[] { "jsonrpc", "id", "result" }
                    : new[] { "jsonrpc", "id", "error" },
                "$",
                errors);
            ExactString(root, "jsonrpc", "2.0", errors);
            ValidateId(root, errors);
            if (hasError)
            {
                ValidateError(error, errors);
            }
            return errors;
        }

        public static IReadOnlyList<ContractViolation>
            Validate(ContentReadRequest request)
        {
            var errors = new List<ContractViolation>();
            if (request == null)
            {
                Error(
                    errors,
                    "$",
                    "required",
                    "A content read request is required.");
                return errors;
            }
            OpaqueId(
                request.Handle,
                "$.handle",
                errors);
            if (request.Offset < 0
                || request.Offset
                    > CanonicalJsonV1.MaximumSafeInteger)
            {
                Error(
                    errors,
                    "$.offset",
                    "range",
                    "Offset must be a non-negative safe integer.");
            }
            if (request.Count <= 0
                || request.Count
                    > AgentProtocolV1.MaximumBinaryReadCount)
            {
                Error(
                    errors,
                    "$.count",
                    "range",
                    "Count exceeds the bounded binary read request.");
            }
            return errors;
        }

        private static void ValidateHello(
            JsonElement parameters,
            ICollection<ContractViolation> errors)
        {
            ExactProperties(
                parameters,
                new[]
                {
                    "protocolVersion",
                    "clientInstanceId",
                    "clientKind",
                    "requestedCapabilities",
                    "nonce",
                    "connectionToken",
                    "credentialProof"
                },
                "$.params",
                errors);
            HelloMessage hello;
            try
            {
                hello = JsonSerializer.Deserialize<HelloMessage>(
                    parameters.GetRawText(),
                    AgentProtocolV1.JsonOptions);
            }
            catch (JsonException)
            {
                Error(
                    errors,
                    "$.params",
                    "hello_invalid",
                    "Hello params do not match HelloMessage.");
                return;
            }
            if (hello == null)
            {
                Error(
                    errors,
                    "$.params",
                    "hello_invalid",
                    "Hello params are required.");
                return;
            }
            if (!string.Equals(
                    hello.ProtocolVersion,
                    AgentProtocolV1.Version,
                    StringComparison.Ordinal))
            {
                Error(
                    errors,
                    "$.params.protocolVersion",
                    "protocol_version_mismatch",
                    "Hello protocolVersion must be 1.0.");
            }
            OpaqueId(
                hello.ClientInstanceId,
                "$.params.clientInstanceId",
                errors);
            OpaqueId(
                hello.Nonce,
                "$.params.nonce",
                errors);
            OpaqueId(
                hello.ConnectionToken,
                "$.params.connectionToken",
                errors);
            if (string.IsNullOrWhiteSpace(
                hello.CredentialProof))
            {
                Error(
                    errors,
                    "$.params.credentialProof",
                    "required",
                    "Credential proof is required.");
            }
            if (hello.RequestedCapabilities == null
                || hello.RequestedCapabilities.Count == 0)
            {
                Error(
                    errors,
                    "$.params.requestedCapabilities",
                    "non_empty",
                    "At least one capability must be requested.");
            }
            else
            {
                var seen = new HashSet<string>(
                    StringComparer.Ordinal);
                for (int index = 0;
                    index < hello.RequestedCapabilities.Count;
                    index++)
                {
                    string capability =
                        hello.RequestedCapabilities[index];
                    if (!AgentCapabilitiesV1.All.Contains(
                            capability ?? string.Empty))
                    {
                        Error(
                            errors,
                            "$.params.requestedCapabilities["
                                + index
                                + "]",
                            "unknown_capability",
                            "Capability is not registered.");
                    }
                    if (!seen.Add(
                            capability ?? string.Empty))
                    {
                        Error(
                            errors,
                            "$.params.requestedCapabilities["
                                + index
                                + "]",
                            "duplicate",
                            "Capabilities must be unique.");
                    }
                }
            }
        }

        private static void ValidateError(
            JsonElement error,
            ICollection<ContractViolation> errors)
        {
            if (error.ValueKind != JsonValueKind.Object)
            {
                Error(
                    errors,
                    "$.error",
                    "rpc_error_object_required",
                    "Error must be an object.");
                return;
            }
            ExactProperties(
                error,
                new[] { "code", "message", "data" },
                "$.error",
                errors);
            if (!error.TryGetProperty(
                    "code",
                    out JsonElement code)
                || code.ValueKind != JsonValueKind.Number
                || !code.TryGetInt32(out _))
            {
                Error(
                    errors,
                    "$.error.code",
                    "integer_required",
                    "JSON-RPC error code must be an Int32.");
            }
            ReadRequiredString(
                error,
                "message",
                "$.error.message",
                512,
                errors);
            if (!error.TryGetProperty(
                    "data",
                    out JsonElement data)
                || data.ValueKind != JsonValueKind.Object)
            {
                Error(
                    errors,
                    "$.error.data",
                    "rpc_error_data_required",
                    "Structured error data is required.");
                return;
            }
            ExactProperties(
                data,
                new[]
                {
                    "reasonCode",
                    "retryable",
                    "reconcileKind",
                    "serverSequence"
                },
                "$.error.data",
                errors);
            string reasonCode = ReadRequiredString(
                data,
                "reasonCode",
                "$.error.data.reasonCode",
                128,
                errors);
            ReasonCodeDefinition reason = null;
            if (reasonCode != null
                && !AgentReasonCodesV1.TryGet(
                    reasonCode,
                    out reason))
            {
                Error(
                    errors,
                    "$.error.data.reasonCode",
                    "unknown_reason_code",
                    "Reason code is not registered.");
            }
            else if (reason != null)
            {
                if (!data.TryGetProperty(
                        "retryable",
                        out JsonElement retryable)
                    || retryable.ValueKind
                        != JsonValueKind.True
                        && retryable.ValueKind
                        != JsonValueKind.False)
                {
                    Error(
                        errors,
                        "$.error.data.retryable",
                        "boolean_required",
                        "retryable must be boolean.");
                }
                else if (retryable.GetBoolean()
                    != reason.Retryable)
                {
                    Error(
                        errors,
                        "$.error.data.retryable",
                        "reason_metadata_mismatch",
                        "retryable must match the reason registry.");
                }

                if (!TryReadReconcileKind(
                        data,
                        out ReconcileKind reconcileKind)
                    || !reason.AllowedReconcileKinds.Contains(
                        reconcileKind))
                {
                    Error(
                        errors,
                        "$.error.data.reconcileKind",
                        "reason_metadata_mismatch",
                        "reconcileKind must match the reason registry.");
                }
            }
            if (!data.TryGetProperty(
                    "serverSequence",
                    out JsonElement sequence)
                || sequence.ValueKind
                    != JsonValueKind.Number
                || !sequence.TryGetUInt64(
                    out ulong sequenceValue)
                || sequenceValue == 0
                || sequenceValue
                    > (ulong)CanonicalJsonV1
                        .MaximumSafeInteger)
            {
                Error(
                    errors,
                    "$.error.data.serverSequence",
                    "positive_required",
                    "serverSequence must be a positive safe integer.");
            }
        }

        private static bool TryReadReconcileKind(
            JsonElement data,
            out ReconcileKind value)
        {
            value = default;
            if (!data.TryGetProperty(
                    "reconcileKind",
                    out JsonElement element)
                || element.ValueKind
                    != JsonValueKind.String)
            {
                return false;
            }
            try
            {
                value = JsonSerializer.Deserialize<
                    ReconcileKind>(
                    element.GetRawText(),
                    AgentProtocolV1.JsonOptions);
                return true;
            }
            catch (JsonException)
            {
                return false;
            }
        }

        private static void ValidateId(
            JsonElement root,
            ICollection<ContractViolation> errors)
        {
            if (!root.TryGetProperty(
                    "id",
                    out JsonElement id)
                || id.ValueKind != JsonValueKind.String)
            {
                Error(
                    errors,
                    "$.id",
                    "rpc_string_id_required",
                    "Numeric, null, and omitted IDs are rejected.");
                return;
            }
            string value = id.GetString();
            if (string.IsNullOrEmpty(value)
                || value.Length > 128
                || value.Any(char.IsControl))
            {
                Error(
                    errors,
                    "$.id",
                    "rpc_string_id_invalid",
                    "ID must be 1-128 non-control characters.");
            }
        }

        private static void ExactString(
            JsonElement root,
            string propertyName,
            string expected,
            ICollection<ContractViolation> errors)
        {
            if (!root.TryGetProperty(
                    propertyName,
                    out JsonElement value)
                || value.ValueKind != JsonValueKind.String
                || !string.Equals(
                    value.GetString(),
                    expected,
                    StringComparison.Ordinal))
            {
                Error(
                    errors,
                    "$." + propertyName,
                    "constant",
                    propertyName + " must equal " + expected + ".");
            }
        }

        private static string ReadRequiredString(
            JsonElement root,
            string propertyName,
            string path,
            int maximumLength,
            ICollection<ContractViolation> errors)
        {
            if (!root.TryGetProperty(
                    propertyName,
                    out JsonElement value)
                || value.ValueKind != JsonValueKind.String
                || string.IsNullOrWhiteSpace(value.GetString()))
            {
                Error(
                    errors,
                    path,
                    "required",
                    "A non-empty string is required.");
                return null;
            }
            string text = value.GetString();
            if (text.Length > maximumLength)
            {
                Error(
                    errors,
                    path,
                    "maximum_length",
                    "The string exceeds its v1 bound.");
                return null;
            }
            return text;
        }

        private static void ExactProperties(
            JsonElement root,
            IEnumerable<string> expected,
            string path,
            ICollection<ContractViolation> errors)
        {
            var required = new HashSet<string>(
                expected,
                StringComparer.Ordinal);
            var actual = new HashSet<string>(
                StringComparer.Ordinal);
            foreach (JsonProperty property
                in root.EnumerateObject())
            {
                actual.Add(property.Name);
            }
            foreach (string missing in required.Except(actual))
            {
                Error(
                    errors,
                    path + "." + missing,
                    "required",
                    "The exact JSON-RPC property is required.");
            }
            foreach (string extra in actual.Except(required))
            {
                Error(
                    errors,
                    path + "." + extra,
                    "unknown_property",
                    "Unknown JSON-RPC properties are rejected.");
            }
        }

        private static void RejectDuplicateProperties(
            JsonElement element,
            string path,
            ICollection<ContractViolation> errors)
        {
            if (element.ValueKind == JsonValueKind.Object)
            {
                var seen = new HashSet<string>(
                    StringComparer.Ordinal);
                foreach (JsonProperty property
                    in element.EnumerateObject())
                {
                    if (!seen.Add(property.Name))
                    {
                        Error(
                            errors,
                            path + "." + property.Name,
                            "duplicate",
                            "Duplicate JSON properties are rejected.");
                    }
                    RejectDuplicateProperties(
                        property.Value,
                        path + "." + property.Name,
                        errors);
                }
            }
            else if (element.ValueKind
                == JsonValueKind.Array)
            {
                int index = 0;
                foreach (JsonElement item
                    in element.EnumerateArray())
                {
                    RejectDuplicateProperties(
                        item,
                        path + "[" + index + "]",
                        errors);
                    index++;
                }
            }
        }

        private static void OpaqueId(
            string value,
            string path,
            ICollection<ContractViolation> errors)
        {
            if (value == null
                || !OpaqueIdPattern.IsMatch(value))
            {
                Error(
                    errors,
                    path,
                    "opaque_id",
                    "Expected a 22-128 character opaque ID.");
            }
        }

        private static void Error(
            ICollection<ContractViolation> errors,
            string path,
            string code,
            string message)
        {
            errors.Add(
                new ContractViolation(path, code, message));
        }
    }

    public static class BinaryChunkCodecV1
    {
        private static readonly UTF8Encoding StrictUtf8 =
            new UTF8Encoding(false, true);
        private static readonly Regex HashPattern = new Regex(
            "^[A-Fa-f0-9]{64}$",
            RegexOptions.CultureInvariant);
        private static readonly Regex HandlePattern = new Regex(
            "^[A-Za-z0-9_-]{"
                + AgentProtocolV1.MinimumOpaqueIdCharacters
                + ","
                + AgentProtocolV1.MaximumOpaqueIdCharacters
                + "}$",
            RegexOptions.CultureInvariant);

        public static int MaximumDataBytesForMetadata(
            int metadataBytes)
        {
            if (metadataBytes <= 0
                || metadataBytes
                    > AgentProtocolV1
                        .MaximumBinaryChunkMetadataBytes)
            {
                throw new ArgumentOutOfRangeException(
                    nameof(metadataBytes));
            }
            return AgentProtocolV1.MaximumBinaryChunkBytes
                - AgentProtocolV1
                    .BinaryChunkMetadataLengthBytes
                - metadataBytes;
        }

        public static byte[] Encode(
            BinaryChunkMetadata metadata,
            ReadOnlySpan<byte> content)
        {
            ValidateMetadata(metadata, content.Length);
            byte[] metadataBytes = JsonSerializer.SerializeToUtf8Bytes(
                metadata,
                AgentProtocolV1.JsonOptions);
            int maximumData =
                MaximumDataBytesForMetadata(
                    metadataBytes.Length);
            if (content.Length > maximumData)
            {
                throw new InvalidDataException(
                    "Binary chunk exceeds the outer 4 MiB payload cap.");
            }
            byte[] payload = new byte[
                AgentProtocolV1.BinaryChunkMetadataLengthBytes
                + metadataBytes.Length
                + content.Length];
            BinaryPrimitives.WriteInt32LittleEndian(
                payload.AsSpan(
                    0,
                    AgentProtocolV1
                        .BinaryChunkMetadataLengthBytes),
                metadataBytes.Length);
            metadataBytes.CopyTo(
                payload,
                AgentProtocolV1
                    .BinaryChunkMetadataLengthBytes);
            content.CopyTo(
                payload.AsSpan(
                    AgentProtocolV1
                        .BinaryChunkMetadataLengthBytes
                    + metadataBytes.Length));
            return payload;
        }

        public static DecodedBinaryChunk Decode(
            ReadOnlySpan<byte> payload)
        {
            if (payload.Length
                    < AgentProtocolV1
                        .BinaryChunkMetadataLengthBytes
                || payload.Length
                    > AgentProtocolV1.MaximumBinaryChunkBytes)
            {
                throw new InvalidDataException(
                    "Binary payload length is invalid.");
            }
            int metadataLength =
                BinaryPrimitives.ReadInt32LittleEndian(
                    payload.Slice(
                        0,
                        AgentProtocolV1
                            .BinaryChunkMetadataLengthBytes));
            if (metadataLength <= 0
                || metadataLength
                    > AgentProtocolV1
                        .MaximumBinaryChunkMetadataBytes
                || metadataLength
                    > payload.Length
                        - AgentProtocolV1
                            .BinaryChunkMetadataLengthBytes)
            {
                throw new InvalidDataException(
                    "Binary metadata length is invalid.");
            }

            ReadOnlySpan<byte> metadataBytes =
                payload.Slice(
                    AgentProtocolV1
                        .BinaryChunkMetadataLengthBytes,
                    metadataLength);
            BinaryChunkMetadata metadata;
            try
            {
                string json = StrictUtf8.GetString(
                    metadataBytes);
                using JsonDocument document =
                    JsonDocument.Parse(
                        json,
                        new JsonDocumentOptions
                        {
                            AllowTrailingCommas = false,
                            CommentHandling =
                                JsonCommentHandling.Disallow,
                            MaxDepth = 8
                        });
                ValidateExactMetadataObject(
                    document.RootElement);
                metadata =
                    JsonSerializer.Deserialize<
                        BinaryChunkMetadata>(
                        json,
                        AgentProtocolV1.JsonOptions);
            }
            catch (Exception exception)
                when (exception is JsonException
                    || exception
                        is DecoderFallbackException)
            {
                throw new InvalidDataException(
                    "Binary metadata is invalid.",
                    exception);
            }

            byte[] content = payload.Slice(
                    AgentProtocolV1
                        .BinaryChunkMetadataLengthBytes
                    + metadataLength)
                .ToArray();
            ValidateMetadata(metadata, content.Length);
            return new DecodedBinaryChunk(
                metadata,
                content);
        }

        private static void ValidateExactMetadataObject(
            JsonElement root)
        {
            if (root.ValueKind != JsonValueKind.Object)
            {
                throw new InvalidDataException(
                    "Binary metadata must be an object.");
            }
            var expected = new HashSet<string>(
                new[]
                {
                    "handle",
                    "offset",
                    "totalLength",
                    "final",
                    "contentHash"
                },
                StringComparer.Ordinal);
            var seen = new HashSet<string>(
                StringComparer.Ordinal);
            foreach (JsonProperty property
                in root.EnumerateObject())
            {
                if (!expected.Contains(property.Name)
                    || !seen.Add(property.Name))
                {
                    throw new InvalidDataException(
                        "Binary metadata has an unknown or duplicate property.");
                }
            }
            if (!seen.SetEquals(expected))
            {
                throw new InvalidDataException(
                    "Binary metadata is missing a required property.");
            }
        }

        private static void ValidateMetadata(
            BinaryChunkMetadata metadata,
            int contentLength)
        {
            if (metadata == null)
            {
                throw new InvalidDataException(
                    "Binary metadata is required.");
            }
            if (metadata.Handle == null
                || !HandlePattern.IsMatch(metadata.Handle))
            {
                throw new InvalidDataException(
                    "Binary handle is invalid.");
            }
            if (metadata.Offset < 0
                || metadata.TotalLength < 0
                || metadata.TotalLength
                    > AgentProtocolV1
                        .MaximumBinaryObjectBytes
                || metadata.Offset
                    > metadata.TotalLength
                || metadata.Offset + contentLength
                    > metadata.TotalLength)
            {
                throw new InvalidDataException(
                    "Binary range is invalid.");
            }
            bool actuallyFinal =
                metadata.Offset + contentLength
                    == metadata.TotalLength;
            if (metadata.Final != actuallyFinal
                || (!metadata.Final
                    && contentLength == 0))
            {
                throw new InvalidDataException(
                    "Binary final marker is inconsistent.");
            }
            if (metadata.ContentHash == null
                || !HashPattern.IsMatch(
                    metadata.ContentHash))
            {
                throw new InvalidDataException(
                    "Binary content hash is invalid.");
            }
        }
    }
}
