using System;
using System.Collections.Generic;
using System.Collections.ObjectModel;
using System.Linq;
using System.Text.Json;
using System.Text.RegularExpressions;

namespace CF7Launcher.AgentRuntime.Contracts
{
    public sealed class EmptyParametersV1
    {
    }

    public class WindowListParametersV1
    {
        public string SessionId { get; set; }
        public string ObservationGrantId { get; set; }
        public string DataScope { get; set; }
    }

    public sealed class WindowTargetParametersV1
        : WindowListParametersV1
    {
        public string TargetId { get; set; }
    }

    public sealed class AppLaunchParametersV1
    {
        public string LaunchRequestId { get; set; }
        public string EntryPoint { get; set; }
        public RuntimeMode RuntimeMode { get; set; }
        public string ExpectedBuildIdentity { get; set; }
        public string ExpectedPayloadClosure { get; set; }
    }

    public sealed class SessionBindingParametersV1
    {
        public string SessionId { get; set; }
        public ulong LifecycleGeneration { get; set; }
    }

    public sealed class LeaseAcquireParametersV1
    {
        public string SessionId { get; set; }
        public string Kind { get; set; }
        public List<string> Capabilities { get; set; }
        public List<string> TargetScope { get; set; }
        public int RequestedTtlMs { get; set; }
        public int RequestedActionLimit { get; set; }
        public string ConsentReceipt { get; set; }
        public string ArgumentBoundsHash { get; set; }
        public string PreviewHash { get; set; }
        public string ExpectedRevision { get; set; }
        public string Operation { get; set; }
    }

    public sealed class LeaseRenewParametersV1
    {
        public string LeaseId { get; set; }
        public int RequestedTtlMs { get; set; }
    }

    public sealed class LeaseReleaseParametersV1
    {
        public string LeaseId { get; set; }
    }

    public sealed class TraceExportParametersV1
    {
        public string SessionId { get; set; }
        public string ObservationGrantId { get; set; }
        public string ConsentPurpose { get; set; }
        public ulong FromServerSequence { get; set; }
        public int MaximumRecords { get; set; }
        public string Format { get; set; }
    }

    public sealed class ObservationGrantIssueParametersV1
    {
        public string LifecycleRef { get; set; }
        public List<string> TargetIds { get; set; }
        public List<string> TargetKinds { get; set; }
        public List<string> DataScopes { get; set; }
        public int RequestedTtlMs { get; set; }
        public bool AllowEphemeralKeyframes { get; set; }
        public bool AllowPersistence { get; set; }
        public bool AllowExport { get; set; }
        public string ConsentReceipt { get; set; }
    }

    public sealed class ObservationGrantRevokeParametersV1
    {
        public string ObservationGrantId { get; set; }
    }

    public sealed class ObservationCaptureParametersV1
    {
        public string ObservationGrantId { get; set; }
        public string SessionId { get; set; }
        public string TargetId { get; set; }
        public string DataScope { get; set; }
        public bool AllowValidatedFlashKeyframeFallback { get; set; }
    }

    public sealed class ObservationReferenceParametersV1
    {
        public string ObservationGrantId { get; set; }
        public string SessionId { get; set; }
        public string ObservationId { get; set; }
    }

    public sealed class ActionGetParametersV1
    {
        public string SessionId { get; set; }
        public string ActionId { get; set; }
    }

    public sealed class HairSaveBindingParametersV1
    {
        public string SessionId { get; set; }
        public ulong LifecycleGeneration { get; set; }
        public string AttemptId { get; set; }
        public ulong AttemptGeneration { get; set; }
        public string SlotId { get; set; }
        public string SaveSignature { get; set; }
    }

    public class HairInspectParametersV1
    {
        public string ObservationGrantId { get; set; }
        public string TargetId { get; set; }
        public HairSaveBindingParametersV1 Binding { get; set; }
    }

    public sealed class HairPreviewParametersV1
        : HairInspectParametersV1
    {
        public string HairIdentifier { get; set; }
        public string ExpectedCurrentHair { get; set; }
        public long ExpectedRevision { get; set; }
        public long ExpectedGeneration { get; set; }
        public string ExpectedSnapshotHash { get; set; }
    }

    public sealed class HairConsentParametersV1
    {
        public string ObservationGrantId { get; set; }
        public string TargetId { get; set; }
        public string SessionId { get; set; }
        public ulong LifecycleGeneration { get; set; }
        public string TransactionId { get; set; }
        public string PreviewHash { get; set; }
    }

    public sealed class HairReconcileParametersV1
    {
        public string ObservationGrantId { get; set; }
        public string TargetId { get; set; }
        public string TransactionId { get; set; }
    }

    public sealed class AgentParameterContractDefinition
    {
        internal AgentParameterContractDefinition(
            string name,
            IEnumerable<string> requiredProperties,
            IEnumerable<string> optionalProperties)
        {
            Name = name;
            RequiredProperties = Array.AsReadOnly(
                requiredProperties.ToArray());
            OptionalProperties = Array.AsReadOnly(
                optionalProperties.ToArray());
        }

        public string Name { get; }
        public ReadOnlyCollection<string> RequiredProperties { get; }
        public ReadOnlyCollection<string> OptionalProperties { get; }
    }

    public static class AgentParameterContractsV1
    {
        public const string Empty = "empty";
        public const string WindowList = "windowList";
        public const string WindowTarget = "windowTarget";
        public const string WindowState = "windowState";
        public const string AppLaunch = "appLaunch";
        public const string SessionBinding = "sessionBinding";
        public const string ActionEnvelope = "actionEnvelope";
        public const string LeaseAcquire = "leaseAcquire";
        public const string LeaseRenew = "leaseRenew";
        public const string LeaseRelease = "leaseRelease";
        public const string TraceExport = "traceExport";
        public const string ObservationGrantIssue =
            "observationGrantIssue";
        public const string ObservationGrantRevoke =
            "observationGrantRevoke";
        public const string ObservationCapture =
            "observationCapture";
        public const string ObservationReference =
            "observationReference";
        public const string ContentRead = "contentReadRequest";
        public const string ActionGet = "actionGet";
        public const string HairInspect = "hairInspect";
        public const string HairPreview = "hairPreview";
        public const string HairConsent = "hairConsent";
        public const string HairReconcile = "hairReconcile";

        private static readonly IReadOnlyDictionary<
            string,
            AgentParameterContractDefinition> Registry =
            new ReadOnlyDictionary<
                string,
                AgentParameterContractDefinition>(
                new[]
                {
                    Define(Empty, Array.Empty<string>()),
                    Define(
                        WindowList,
                        "sessionId",
                        "observationGrantId",
                        "dataScope"),
                    Define(
                        WindowTarget,
                        "sessionId",
                        "observationGrantId",
                        "dataScope",
                        "targetId"),
                    Define(
                        WindowState,
                        "sessionId",
                        "observationGrantId",
                        "dataScope",
                        "targetId"),
                    Define(
                        AppLaunch,
                        new[]
                        {
                            "launchRequestId",
                            "entryPoint",
                            "runtimeMode"
                        },
                        new[]
                        {
                            "expectedBuildIdentity",
                            "expectedPayloadClosure"
                        }),
                    Define(
                        SessionBinding,
                        "sessionId",
                        "lifecycleGeneration"),
                    Define(
                        ActionEnvelope,
                        new[]
                        {
                            "actionId",
                            "idempotencyKey",
                            "deadlineMs",
                            "sessionId",
                            "observationGrantId",
                            "leaseId",
                            "observationId",
                            "expectedLifecycleGeneration",
                            "targetId",
                            "expectedSurfaceEpoch",
                            "expectedCoordinateSpaceVersion",
                            "expectedFocusEpoch",
                            "expectedModalEpoch",
                            "operation",
                            "arguments",
                            "reason"
                        },
                        new[]
                        {
                            "expectedAttemptId",
                            "expectedAttemptGeneration",
                            "expectedPanelInstanceId",
                            "expectedSemanticGeneration",
                            "expectedDocumentGeneration",
                            "frameId",
                            "semanticSnapshotId",
                            "nodeId"
                        }),
                    Define(
                        LeaseAcquire,
                        new[]
                        {
                            "sessionId",
                            "kind",
                            "capabilities",
                            "targetScope",
                            "requestedTtlMs",
                            "requestedActionLimit"
                        },
                        new[]
                        {
                            "consentReceipt",
                            "argumentBoundsHash",
                            "previewHash",
                            "expectedRevision",
                            "operation"
                        }),
                    Define(
                        LeaseRenew,
                        "leaseId",
                        "requestedTtlMs"),
                    Define(LeaseRelease, "leaseId"),
                    Define(
                        TraceExport,
                        "sessionId",
                        "observationGrantId",
                        "consentPurpose",
                        "fromServerSequence",
                        "maximumRecords",
                        "format"),
                    Define(
                        ObservationGrantIssue,
                        new[]
                        {
                            "lifecycleRef",
                            "dataScopes",
                            "requestedTtlMs",
                            "allowEphemeralKeyframes",
                            "allowPersistence",
                            "allowExport"
                        },
                        new[]
                        {
                            "targetIds",
                            "targetKinds",
                            "consentReceipt"
                        }),
                    Define(
                        ObservationGrantRevoke,
                        "observationGrantId"),
                    Define(
                        ObservationCapture,
                        "observationGrantId",
                        "sessionId",
                        "targetId",
                        "dataScope",
                        "allowValidatedFlashKeyframeFallback"),
                    Define(
                        ObservationReference,
                        "observationGrantId",
                        "sessionId",
                        "observationId"),
                    Define(
                        ContentRead,
                        "handle",
                        "offset",
                        "count"),
                    Define(ActionGet, "sessionId", "actionId"),
                    Define(
                        HairInspect,
                        "observationGrantId",
                        "targetId",
                        "binding"),
                    Define(
                        HairPreview,
                        "observationGrantId",
                        "targetId",
                        "binding",
                        "hairIdentifier",
                        "expectedCurrentHair",
                        "expectedRevision",
                        "expectedGeneration",
                        "expectedSnapshotHash"),
                    Define(
                        HairConsent,
                        "observationGrantId",
                        "targetId",
                        "sessionId",
                        "lifecycleGeneration",
                        "transactionId",
                        "previewHash"),
                    Define(
                        HairReconcile,
                        "observationGrantId",
                        "targetId",
                        "transactionId")
                }.ToDictionary(
                    definition => definition.Name,
                    StringComparer.Ordinal));

        public static IReadOnlyDictionary<
            string,
            AgentParameterContractDefinition> All => Registry;

        public static bool TryGet(
            string name,
            out AgentParameterContractDefinition definition)
        {
            return Registry.TryGetValue(
                name ?? string.Empty,
                out definition);
        }

        private static AgentParameterContractDefinition Define(
            string name,
            params string[] required)
        {
            return Define(
                name,
                required,
                Array.Empty<string>());
        }

        private static AgentParameterContractDefinition Define(
            string name,
            IEnumerable<string> required,
            IEnumerable<string> optional)
        {
            return new AgentParameterContractDefinition(
                name,
                required,
                optional);
        }
    }

    public static class AgentMethodParameterValidatorV1
    {
        private static readonly Regex Sha256Pattern = new Regex(
            "^[A-Fa-f0-9]{64}$",
            RegexOptions.CultureInvariant);
        private static readonly Regex ProtocolNamePattern =
            new Regex(
                "^[a-z][a-z0-9_.-]{0,127}$",
                RegexOptions.CultureInvariant);
        private static readonly Regex OpaqueIdPattern = new Regex(
            "^[A-Za-z0-9_-]{"
                + AgentProtocolV1.MinimumOpaqueIdCharacters
                + ","
                + AgentProtocolV1.MaximumOpaqueIdCharacters
                + "}$",
            RegexOptions.CultureInvariant);

        public static IReadOnlyList<ContractViolation> Validate(
            string method,
            JsonElement parameters)
        {
            var errors = new List<ContractViolation>();
            if (!AgentMethodsV1.TryGet(
                    method,
                    out AgentMethodDefinition methodDefinition))
            {
                Error(
                    errors,
                    "$.method",
                    "rpc_method_not_found",
                    "Method is not registered.");
                return errors;
            }
            if (methodDefinition.PreAuthentication)
            {
                Error(
                    errors,
                    "$.params",
                    "preauthentication_contract",
                    "Pre-authentication params use HelloMessage.");
                return errors;
            }
            if (!AgentParameterContractsV1.TryGet(
                    methodDefinition.ParameterContract,
                    out AgentParameterContractDefinition contract))
            {
                Error(
                    errors,
                    "$.params",
                    "parameter_contract_missing",
                    "Method parameter contract is not compiled.");
                return errors;
            }
            Exact(
                parameters,
                contract.RequiredProperties,
                contract.OptionalProperties,
                "$.params",
                errors);
            if (errors.Count != 0) return errors;

            switch (methodDefinition.ParameterContract)
            {
                case AgentParameterContractsV1.Empty:
                    break;
                case AgentParameterContractsV1.WindowList:
                    ValidateWindow(parameters, false, errors);
                    break;
                case AgentParameterContractsV1.WindowTarget:
                    ValidateWindow(parameters, true, errors);
                    break;
                case AgentParameterContractsV1.WindowState:
                    ValidateWindowState(parameters, errors);
                    break;
                case AgentParameterContractsV1.AppLaunch:
                    ValidateAppLaunch(parameters, errors);
                    break;
                case AgentParameterContractsV1.SessionBinding:
                    Opaque(parameters, "sessionId", errors);
                    Positive(
                        parameters,
                        "lifecycleGeneration",
                        errors);
                    break;
                case AgentParameterContractsV1.ActionEnvelope:
                    ValidateAction(method, parameters, errors);
                    break;
                case AgentParameterContractsV1.LeaseAcquire:
                    ValidateLeaseAcquire(parameters, errors);
                    break;
                case AgentParameterContractsV1.LeaseRenew:
                    Opaque(parameters, "leaseId", errors);
                    Integer(
                        parameters,
                        "requestedTtlMs",
                        1,
                        1_800_000,
                        errors);
                    break;
                case AgentParameterContractsV1.LeaseRelease:
                    Opaque(parameters, "leaseId", errors);
                    break;
                case AgentParameterContractsV1.TraceExport:
                    ValidateTraceExport(parameters, errors);
                    break;
                case AgentParameterContractsV1
                    .ObservationGrantIssue:
                    ValidateObservationGrantIssue(
                        parameters,
                        errors);
                    break;
                case AgentParameterContractsV1
                    .ObservationGrantRevoke:
                    Opaque(
                        parameters,
                        "observationGrantId",
                        errors);
                    break;
                case AgentParameterContractsV1
                    .ObservationCapture:
                    ValidateObservationCapture(
                        parameters,
                        errors);
                    break;
                case AgentParameterContractsV1
                    .ObservationReference:
                    Opaque(
                        parameters,
                        "observationGrantId",
                        errors);
                    Opaque(parameters, "sessionId", errors);
                    Opaque(parameters, "observationId", errors);
                    break;
                case AgentParameterContractsV1.ContentRead:
                    ValidateContentRead(parameters, errors);
                    break;
                case AgentParameterContractsV1.ActionGet:
                    Opaque(parameters, "sessionId", errors);
                    Opaque(parameters, "actionId", errors);
                    break;
                case AgentParameterContractsV1.HairInspect:
                    ValidateHairObservation(parameters, errors);
                    break;
                case AgentParameterContractsV1.HairPreview:
                    ValidateHairObservation(parameters, errors);
                    String(
                        parameters,
                        "hairIdentifier",
                        1,
                        160,
                        errors);
                    String(
                        parameters,
                        "expectedCurrentHair",
                        1,
                        160,
                        errors);
                    Integer(
                        parameters,
                        "expectedRevision",
                        0,
                        CanonicalJsonV1.MaximumSafeInteger,
                        errors);
                    Integer(
                        parameters,
                        "expectedGeneration",
                        0,
                        CanonicalJsonV1.MaximumSafeInteger,
                        errors);
                    Sha256(
                        parameters,
                        "expectedSnapshotHash",
                        errors);
                    break;
                case AgentParameterContractsV1.HairConsent:
                    Opaque(
                        parameters,
                        "observationGrantId",
                        errors);
                    Opaque(parameters, "targetId", errors);
                    Opaque(parameters, "sessionId", errors);
                    Positive(
                        parameters,
                        "lifecycleGeneration",
                        errors);
                    Opaque(
                        parameters,
                        "transactionId",
                        errors);
                    Sha256(
                        parameters,
                        "previewHash",
                        errors);
                    break;
                case AgentParameterContractsV1.HairReconcile:
                    Opaque(
                        parameters,
                        "observationGrantId",
                        errors);
                    Opaque(parameters, "targetId", errors);
                    Opaque(parameters, "transactionId", errors);
                    break;
                default:
                    Error(
                        errors,
                        "$.params",
                        "parameter_contract_missing",
                        "Method parameter validator is not compiled.");
                    break;
            }
            return errors;
        }

        private static void ValidateWindow(
            JsonElement parameters,
            bool targetRequired,
            ICollection<ContractViolation> errors)
        {
            Opaque(parameters, "sessionId", errors);
            Opaque(
                parameters,
                "observationGrantId",
                errors);
            ConstantString(
                parameters,
                "dataScope",
                ObservationDataScopesV1.WindowMetadata,
                errors);
            if (targetRequired)
            {
                Opaque(parameters, "targetId", errors);
            }
        }

        private static void ValidateWindowState(
            JsonElement parameters,
            ICollection<ContractViolation> errors)
        {
            Opaque(parameters, "sessionId", errors);
            Opaque(
                parameters,
                "observationGrantId",
                errors);
            string dataScope = String(
                parameters,
                "dataScope",
                1,
                64,
                errors);
            if (dataScope != null
                && dataScope
                    != ObservationDataScopesV1.WindowMetadata
                && dataScope
                    != ObservationDataScopesV1.Pixels)
            {
                Error(
                    errors,
                    "$.params.dataScope",
                    "enum",
                    "window.state accepts window_metadata or pixels.");
            }
            Opaque(parameters, "targetId", errors);
        }

        private static void ValidateAppLaunch(
            JsonElement parameters,
            ICollection<ContractViolation> errors)
        {
            Opaque(parameters, "launchRequestId", errors);
            ConstantString(
                parameters,
                "entryPoint",
                "standard_entry",
                errors);
            string runtimeMode = String(
                parameters,
                "runtimeMode",
                1,
                64,
                errors);
            if (runtimeMode != "formal_runtime"
                && runtimeMode != "isolated_candidate"
                && runtimeMode != "unqualified_dev")
            {
                Error(
                    errors,
                    "$.params.runtimeMode",
                    "enum",
                    "runtimeMode is not registered.");
            }
            OptionalString(
                parameters,
                "expectedBuildIdentity",
                1,
                256,
                errors);
            OptionalSha256(
                parameters,
                "expectedPayloadClosure",
                errors);
            if (runtimeMode == "isolated_candidate"
                && (!parameters.TryGetProperty(
                        "expectedBuildIdentity",
                        out _)
                    || !parameters.TryGetProperty(
                        "expectedPayloadClosure",
                        out _)))
            {
                Error(
                    errors,
                    "$.params",
                    "candidate_identity_required",
                    "Candidate launch requires build identity and payload closure.");
            }
        }

        private static void ValidateAction(
            string method,
            JsonElement parameters,
            ICollection<ContractViolation> errors)
        {
            ActionEnvelope action;
            try
            {
                action = JsonSerializer.Deserialize<ActionEnvelope>(
                    parameters.GetRawText(),
                    AgentProtocolV1.JsonOptions);
            }
            catch (JsonException)
            {
                Error(
                    errors,
                    "$.params",
                    "action_envelope_invalid",
                    "Params do not match ActionEnvelope.");
                return;
            }
            foreach (ContractViolation violation
                in AgentContractValidator.Validate(action))
            {
                errors.Add(
                    new ContractViolation(
                        "$.params"
                            + violation.Path.Substring(1),
                        violation.Code,
                        violation.Message));
            }
            if (action == null
                || !string.Equals(
                    action.Operation,
                    method,
                    StringComparison.Ordinal))
            {
                Error(
                    errors,
                    "$.params.operation",
                    "operation_method_mismatch",
                    "ActionEnvelope.operation must equal the wire method.");
                return;
            }
            if (action.Arguments.ValueKind
                == JsonValueKind.Object)
            {
                ValidateActionArguments(
                    method,
                    action,
                    errors);
            }
        }

        private static void ValidateActionArguments(
            string method,
            ActionEnvelope action,
            ICollection<ContractViolation> errors)
        {
            JsonElement arguments = action.Arguments;
            switch (method)
            {
                case AgentCapabilitiesV1.Click:
                    bool semantic =
                        action.NodeId != null;
                    Exact(
                        arguments,
                        semantic
                            ? new[]
                            {
                                "button",
                                "clickCount"
                            }
                            : new[]
                            {
                                "coordinateSpace",
                                "x",
                                "y",
                                "button",
                                "clickCount"
                            },
                        Array.Empty<string>(),
                        "$.params.arguments",
                        errors);
                    if (!semantic)
                    {
                        CoordinateSpace(arguments, errors);
                        Coordinate(arguments, "x", errors);
                        Coordinate(arguments, "y", errors);
                    }
                    MouseButton(arguments, errors);
                    Integer(
                        arguments,
                        "clickCount",
                        1,
                        2,
                        errors,
                        "$.params.arguments");
                    break;
                case AgentCapabilitiesV1.PressKey:
                    Exact(
                        arguments,
                        new[] { "key", "modifiers", "repeat" },
                        Array.Empty<string>(),
                        "$.params.arguments",
                        errors);
                    String(
                        arguments,
                        "key",
                        1,
                        64,
                        errors,
                        "$.params.arguments");
                    StringArray(
                        arguments,
                        "modifiers",
                        new HashSet<string>(
                            new[] { "ctrl", "alt", "shift" },
                            StringComparer.Ordinal),
                        false,
                        3,
                        errors,
                        "$.params.arguments");
                    Integer(
                        arguments,
                        "repeat",
                        1,
                        16,
                        errors,
                        "$.params.arguments");
                    break;
                case AgentCapabilitiesV1.TypeText:
                    ExactArgument(arguments, "text", errors);
                    String(
                        arguments,
                        "text",
                        1,
                        32_768,
                        errors,
                        "$.params.arguments");
                    break;
                case AgentCapabilitiesV1.Scroll:
                    Exact(
                        arguments,
                        new[]
                        {
                            "coordinateSpace",
                            "x",
                            "y",
                            "deltaX",
                            "deltaY"
                        },
                        Array.Empty<string>(),
                        "$.params.arguments",
                        errors);
                    CoordinateSpace(arguments, errors);
                    Coordinate(arguments, "x", errors);
                    Coordinate(arguments, "y", errors);
                    long? deltaX = Integer(
                        arguments,
                        "deltaX",
                        -120_000,
                        120_000,
                        errors,
                        "$.params.arguments");
                    long? deltaY = Integer(
                        arguments,
                        "deltaY",
                        -120_000,
                        120_000,
                        errors,
                        "$.params.arguments");
                    if (deltaX == 0
                        && deltaY == 0)
                    {
                        Error(
                            errors,
                            "$.params.arguments",
                            "scroll_delta_required",
                            "At least one scroll delta must be non-zero.");
                    }
                    break;
                case AgentCapabilitiesV1.SetValue:
                    ExactArgument(arguments, "value", errors);
                    String(
                        arguments,
                        "value",
                        0,
                        32_768,
                        errors,
                        "$.params.arguments");
                    break;
                case AgentCapabilitiesV1.Drag:
                    Exact(
                        arguments,
                        new[]
                        {
                            "coordinateSpace",
                            "startX",
                            "startY",
                            "endX",
                            "endY",
                            "durationMs"
                        },
                        Array.Empty<string>(),
                        "$.params.arguments",
                        errors);
                    CoordinateSpace(arguments, errors);
                    Coordinate(arguments, "startX", errors);
                    Coordinate(arguments, "startY", errors);
                    Coordinate(arguments, "endX", errors);
                    Coordinate(arguments, "endY", errors);
                    Integer(
                        arguments,
                        "durationMs",
                        1,
                        10_000,
                        errors,
                        "$.params.arguments");
                    break;
                case AgentCapabilitiesV1.PerformSecondaryAction:
                    ExactArgument(arguments, "action", errors);
                    string actionName = String(
                        arguments,
                        "action",
                        1,
                        128,
                        errors,
                        "$.params.arguments");
                    if (actionName != null
                        && !ProtocolNamePattern.IsMatch(actionName))
                    {
                        Error(
                            errors,
                            "$.params.arguments.action",
                            "protocol_name",
                            "Secondary action must be a protocol name.");
                    }
                    break;
                case AgentCapabilitiesV1.ActivateWindow:
                case AgentCapabilitiesV1.SessionShutdown:
                case AgentCapabilitiesV1.LifecycleReveal:
                case AgentCapabilitiesV1.LifecycleCancel:
                    Exact(
                        arguments,
                        Array.Empty<string>(),
                        Array.Empty<string>(),
                        "$.params.arguments",
                        errors);
                    break;
                case AgentCapabilitiesV1.PanelOpen:
                    ExactArgument(arguments, "panel", errors);
                    string panel = String(
                        arguments,
                        "panel",
                        1,
                        128,
                        errors,
                        "$.params.arguments");
                    if (panel != null
                        && !ProtocolNamePattern.IsMatch(panel))
                    {
                        Error(
                            errors,
                            "$.params.arguments.panel",
                            "protocol_name",
                            "Panel must be a protocol name.");
                    }
                    break;
                case AgentMethodsV1.HairCommit:
                    Exact(
                        arguments,
                        new[]
                        {
                            "transactionId",
                            "previewHash",
                            "consentToken"
                        },
                        Array.Empty<string>(),
                        "$.params.arguments",
                        errors);
                    Opaque(
                        arguments,
                        "transactionId",
                        errors,
                        "$.params.arguments");
                    Sha256(
                        arguments,
                        "previewHash",
                        errors,
                        "$.params.arguments");
                    String(
                        arguments,
                        "consentToken",
                        1,
                        256,
                        errors,
                        "$.params.arguments");
                    break;
                case AgentMethodsV1.HairRestore:
                    Exact(
                        arguments,
                        new[] { "transactionId", "restoreToken" },
                        Array.Empty<string>(),
                        "$.params.arguments",
                        errors);
                    Opaque(
                        arguments,
                        "transactionId",
                        errors,
                        "$.params.arguments");
                    String(
                        arguments,
                        "restoreToken",
                        1,
                        256,
                        errors,
                        "$.params.arguments");
                    break;
                default:
                    Error(
                        errors,
                        "$.params.arguments",
                        "action_arguments_contract_missing",
                        "Action method has no exact arguments contract.");
                    break;
            }
        }

        private static void ValidateLeaseAcquire(
            JsonElement parameters,
            ICollection<ContractViolation> errors)
        {
            Opaque(parameters, "sessionId", errors);
            string kind = String(
                parameters,
                "kind",
                1,
                64,
                errors);
            if (kind != "gui_input"
                && kind != "domain_transaction"
                && kind != "structured_action"
                && kind != "shutdown")
            {
                Error(
                    errors,
                    "$.params.kind",
                    "enum",
                    "Lease kind is not registered.");
            }
            IReadOnlyList<string> requestedCapabilities =
                StringArray(
                    parameters,
                    "capabilities",
                    AgentCapabilitiesV1.All,
                    true,
                    AgentCapabilitiesV1.All.Count,
                    errors);
            IReadOnlyList<string> requestedTargets =
                StringArray(
                    parameters,
                    "targetScope",
                    null,
                    true,
                    AgentProtocolV1.MaximumTargetScopeItems,
                    errors,
                    opaqueItems: true);
            long? requestedTtlMs = Integer(
                parameters,
                "requestedTtlMs",
                1,
                1_800_000,
                errors);
            long? requestedActionLimit = Integer(
                parameters,
                "requestedActionLimit",
                1,
                10_000,
                errors);
            OptionalString(
                parameters,
                "consentReceipt",
                1,
                512,
                errors);
            OptionalSha256(
                parameters,
                "argumentBoundsHash",
                errors);
            OptionalSha256(parameters, "previewHash", errors);
            OptionalString(
                parameters,
                "expectedRevision",
                1,
                256,
                errors);
            string operation = OptionalString(
                parameters,
                "operation",
                1,
                128,
                errors);
            bool requestsShutdown =
                requestedCapabilities?.Contains(
                    AgentCapabilitiesV1.SessionShutdown,
                    StringComparer.Ordinal) == true;
            bool requestsStructuredAction =
                requestedCapabilities?.Contains(
                    AgentCapabilitiesV1.PanelOpen,
                    StringComparer.Ordinal) == true;
            if (kind == "domain_transaction")
            {
                if (requestsShutdown)
                {
                    Error(
                        errors,
                        "$.params.capabilities",
                        "lease_kind_mismatch",
                        "Shutdown requires the dedicated shutdown lease kind.");
                }
                if (operation != AgentMethodsV1.HairCommit
                    && operation != AgentMethodsV1.HairRestore)
                {
                    Error(
                        errors,
                        "$.params.operation",
                        "domain_operation_required",
                        "The v1 domain lease must bind a hair commit or restore.");
                }
                if (requestedCapabilities != null
                    && !requestedCapabilities.Contains(
                        AgentCapabilitiesV1.AppearanceHairChange,
                        StringComparer.Ordinal))
                {
                    Error(
                        errors,
                        "$.params.capabilities",
                        "capability_scope_required",
                        "Hair domain lease requires its domain capability.");
                }
                if (requestsStructuredAction)
                {
                    Error(
                        errors,
                        "$.params.capabilities",
                        "lease_kind_mismatch",
                        "panel.open requires the dedicated structured-action lease kind.");
                }
            }
            else if (kind == "shutdown")
            {
                if (requestedCapabilities == null
                    || requestedCapabilities.Count != 1
                    || !requestsShutdown)
                {
                    Error(
                        errors,
                        "$.params.capabilities",
                        "capability_scope_required",
                        "Shutdown leases require exactly session.shutdown.");
                }
                if (requestedTargets == null
                    || requestedTargets.Count != 1)
                {
                    Error(
                        errors,
                        "$.params.targetScope",
                        "exactly_one",
                        "Shutdown leases bind exactly one Runtime-owned target.");
                }
                if (requestedActionLimit != 1)
                {
                    Error(
                        errors,
                        "$.params.requestedActionLimit",
                        "constant",
                        "Shutdown leases are one-shot.");
                }
                if (requestedTtlMs > 30_000)
                {
                    Error(
                        errors,
                        "$.params.requestedTtlMs",
                        "maximum",
                        "Shutdown leases expire within 30 seconds.");
                }
                if (operation != null
                    || parameters.TryGetProperty(
                        "previewHash",
                        out _)
                    || parameters.TryGetProperty(
                        "expectedRevision",
                        out _))
                {
                    Error(
                        errors,
                        "$.params",
                        "shutdown_lease_fields",
                        "Shutdown operation binding is derived by the server.");
                }
                if (requestsStructuredAction)
                {
                    Error(
                        errors,
                        "$.params.capabilities",
                        "lease_kind_mismatch",
                        "panel.open requires the dedicated structured-action lease kind.");
                }
            }
            else if (kind == "structured_action")
            {
                if (requestsShutdown)
                {
                    Error(
                        errors,
                        "$.params.capabilities",
                        "lease_kind_mismatch",
                        "session.shutdown requires the dedicated shutdown lease kind.");
                }
                if (requestedCapabilities == null
                    || requestedCapabilities.Count != 1
                    || !requestsStructuredAction)
                {
                    Error(
                        errors,
                        "$.params.capabilities",
                        "capability_scope_required",
                        "Structured-action leases require exactly panel.open.");
                }
                if (requestedTargets == null
                    || requestedTargets.Count != 1)
                {
                    Error(
                        errors,
                        "$.params.targetScope",
                        "exactly_one",
                        "Structured-action leases bind exactly one Runtime-owned target.");
                }
                if (requestedActionLimit != 1)
                {
                    Error(
                        errors,
                        "$.params.requestedActionLimit",
                        "constant",
                        "Structured-action leases are one-shot.");
                }
                if (requestedTtlMs > 30_000)
                {
                    Error(
                        errors,
                        "$.params.requestedTtlMs",
                        "maximum",
                        "Structured-action leases expire within 30 seconds.");
                }
                if (operation != null
                    || parameters.TryGetProperty(
                        "previewHash",
                        out _)
                    || parameters.TryGetProperty(
                        "expectedRevision",
                        out _))
                {
                    Error(
                        errors,
                        "$.params",
                        "structured_action_lease_fields",
                        "Structured-action operation binding is derived by the server.");
                }
            }
            else
            {
                if (operation != null
                    || parameters.TryGetProperty(
                        "previewHash",
                        out _)
                    || parameters.TryGetProperty(
                        "expectedRevision",
                        out _))
                {
                    Error(
                        errors,
                        "$.params",
                        "gui_lease_domain_fields",
                        "GUI leases cannot carry domain transaction fields.");
                }
                if (requestsShutdown)
                {
                    Error(
                        errors,
                        "$.params.capabilities",
                        "lease_kind_mismatch",
                        "Shutdown requires the dedicated shutdown lease kind.");
                }
                if (requestsStructuredAction)
                {
                    Error(
                        errors,
                        "$.params.capabilities",
                        "lease_kind_mismatch",
                        "panel.open requires the dedicated structured-action lease kind.");
                }
            }
        }

        private static void ValidateTraceExport(
            JsonElement parameters,
            ICollection<ContractViolation> errors)
        {
            Opaque(parameters, "sessionId", errors);
            Opaque(parameters, "observationGrantId", errors);
            ConstantSetString(
                parameters,
                "consentPurpose",
                TraceExportConsentPurposesV1.All,
                errors);
            Integer(
                parameters,
                "fromServerSequence",
                0,
                CanonicalJsonV1.MaximumSafeInteger,
                errors);
            Integer(
                parameters,
                "maximumRecords",
                1,
                10_000,
                errors);
            ConstantString(
                parameters,
                "format",
                "jsonl",
                errors);
        }

        private static void ValidateObservationGrantIssue(
            JsonElement parameters,
            ICollection<ContractViolation> errors)
        {
            Opaque(parameters, "lifecycleRef", errors);
            bool hasTargetIds =
                parameters.TryGetProperty("targetIds", out _);
            bool hasTargetKinds =
                parameters.TryGetProperty("targetKinds", out _);
            if (hasTargetIds == hasTargetKinds)
            {
                Error(
                    errors,
                    "$.params",
                    "target_selector_exclusive",
                    "Exactly one of targetIds or targetKinds is required.");
            }
            if (hasTargetIds)
            {
                StringArray(
                    parameters,
                    "targetIds",
                    null,
                    true,
                    AgentProtocolV1.MaximumTargetScopeItems,
                    errors,
                    opaqueItems: true);
            }
            if (hasTargetKinds)
            {
                StringArray(
                    parameters,
                    "targetKinds",
                    AgentSurfaceKindsV1.All,
                    true,
                    AgentSurfaceKindsV1.All.Count,
                    errors);
            }
            IReadOnlyList<string> scopes = StringArray(
                parameters,
                "dataScopes",
                ObservationDataScopesV1.All,
                true,
                ObservationDataScopesV1.All.Count,
                errors);
            Integer(
                parameters,
                "requestedTtlMs",
                1,
                AgentProtocolV1.MaximumObservationGrantTtlMs,
                errors);
            bool? keyframes = Boolean(
                parameters,
                "allowEphemeralKeyframes",
                errors);
            bool? persistence = Boolean(
                parameters,
                "allowPersistence",
                errors);
            bool? export = Boolean(
                parameters,
                "allowExport",
                errors);
            string consent = OptionalString(
                parameters,
                "consentReceipt",
                1,
                512,
                errors);
            if (keyframes == true
                && scopes != null
                && !scopes.Contains(
                    ObservationDataScopesV1.Pixels,
                    StringComparer.Ordinal))
            {
                Error(
                    errors,
                    "$.params.allowEphemeralKeyframes",
                    "pixels_scope_required",
                    "Keyframes require pixels scope.");
            }
            ValidateRetentionFlag(
                persistence,
                scopes,
                ObservationDataScopesV1.RetentionPersist,
                "allowPersistence",
                consent,
                errors);
            ValidateRetentionFlag(
                export,
                scopes,
                ObservationDataScopesV1.DataExport,
                "allowExport",
                consent,
                errors);
        }

        private static void ValidateRetentionFlag(
            bool? enabled,
            IReadOnlyList<string> scopes,
            string requiredScope,
            string property,
            string consent,
            ICollection<ContractViolation> errors)
        {
            if (!enabled.HasValue || scopes == null) return;
            bool hasScope = scopes.Contains(
                requiredScope,
                StringComparer.Ordinal);
            if (enabled.Value != hasScope)
            {
                Error(
                    errors,
                    "$.params." + property,
                    "scope_flag_mismatch",
                    property + " must exactly match its data scope.");
            }
            if (enabled.Value
                && consent == null)
            {
                Error(
                    errors,
                    "$.params.consentReceipt",
                    "consent_required",
                    "Persistence/export requires a consent receipt.");
            }
        }

        private static void ValidateObservationCapture(
            JsonElement parameters,
            ICollection<ContractViolation> errors)
        {
            Opaque(
                parameters,
                "observationGrantId",
                errors);
            Opaque(parameters, "sessionId", errors);
            Opaque(parameters, "targetId", errors);
            string scope = String(
                parameters,
                "dataScope",
                1,
                64,
                errors);
            if (scope != null
                && scope != ObservationDataScopesV1.Pixels)
            {
                Error(
                    errors,
                    "$.params.dataScope",
                    "pixels_scope_required",
                    "observation.capture only accepts pixels.");
            }
            bool? fallback = Boolean(
                parameters,
                "allowValidatedFlashKeyframeFallback",
                errors);
            if (fallback == true
                && scope != ObservationDataScopesV1.Pixels)
            {
                Error(
                    errors,
                    "$.params.allowValidatedFlashKeyframeFallback",
                    "pixels_scope_required",
                    "Flash keyframe fallback is only valid for pixels.");
            }
        }

        private static void ValidateContentRead(
            JsonElement parameters,
            ICollection<ContractViolation> errors)
        {
            ContentReadRequest request;
            try
            {
                request = JsonSerializer.Deserialize<
                    ContentReadRequest>(
                    parameters.GetRawText(),
                    AgentProtocolV1.JsonOptions);
            }
            catch (JsonException)
            {
                Error(
                    errors,
                    "$.params",
                    "content_read_invalid",
                    "Params do not match ContentReadRequest.");
                return;
            }
            foreach (ContractViolation violation
                in AgentJsonRpcValidator.Validate(request))
            {
                errors.Add(
                    new ContractViolation(
                        "$.params"
                            + violation.Path.Substring(1),
                        violation.Code,
                        violation.Message));
            }
        }

        private static void ValidateHairObservation(
            JsonElement parameters,
            ICollection<ContractViolation> errors)
        {
            Opaque(
                parameters,
                "observationGrantId",
                errors);
            Opaque(parameters, "targetId", errors);
            JsonElement binding =
                parameters.GetProperty("binding");
            Exact(
                binding,
                new[]
                {
                    "sessionId",
                    "lifecycleGeneration",
                    "attemptId",
                    "attemptGeneration",
                    "slotId",
                    "saveSignature"
                },
                Array.Empty<string>(),
                "$.params.binding",
                errors);
            if (binding.ValueKind
                != JsonValueKind.Object)
            {
                return;
            }
            Opaque(
                binding,
                "sessionId",
                errors,
                "$.params.binding");
            Positive(
                binding,
                "lifecycleGeneration",
                errors,
                "$.params.binding");
            Opaque(
                binding,
                "attemptId",
                errors,
                "$.params.binding");
            Positive(
                binding,
                "attemptGeneration",
                errors,
                "$.params.binding");
            String(
                binding,
                "slotId",
                1,
                128,
                errors,
                "$.params.binding");
            Sha256(
                binding,
                "saveSignature",
                errors,
                "$.params.binding");
        }

        private static void CoordinateSpace(
            JsonElement arguments,
            ICollection<ContractViolation> errors)
        {
            ConstantString(
                arguments,
                "coordinateSpace",
                "observation_px",
                errors,
                "$.params.arguments");
        }

        private static void Coordinate(
            JsonElement arguments,
            string name,
            ICollection<ContractViolation> errors)
        {
            Integer(
                arguments,
                name,
                0,
                int.MaxValue,
                errors,
                "$.params.arguments");
        }

        private static void MouseButton(
            JsonElement arguments,
            ICollection<ContractViolation> errors)
        {
            string button = String(
                arguments,
                "button",
                1,
                16,
                errors,
                "$.params.arguments");
            if (button != "primary"
                && button != "secondary"
                && button != "middle")
            {
                Error(
                    errors,
                    "$.params.arguments.button",
                    "enum",
                    "Mouse button is not registered.");
            }
        }

        private static void ExactArgument(
            JsonElement arguments,
            string name,
            ICollection<ContractViolation> errors)
        {
            Exact(
                arguments,
                new[] { name },
                Array.Empty<string>(),
                "$.params.arguments",
                errors);
        }

        private static void Exact(
            JsonElement value,
            IEnumerable<string> requiredProperties,
            IEnumerable<string> optionalProperties,
            string path,
            ICollection<ContractViolation> errors)
        {
            if (value.ValueKind != JsonValueKind.Object)
            {
                Error(
                    errors,
                    path,
                    "object_required",
                    "An object is required.");
                return;
            }
            var required = new HashSet<string>(
                requiredProperties,
                StringComparer.Ordinal);
            var allowed = new HashSet<string>(
                required,
                StringComparer.Ordinal);
            allowed.UnionWith(optionalProperties);
            var seen = new HashSet<string>(
                StringComparer.Ordinal);
            foreach (JsonProperty property
                in value.EnumerateObject())
            {
                if (!seen.Add(property.Name))
                {
                    Error(
                        errors,
                        path + "." + property.Name,
                        "duplicate",
                        "Duplicate properties are rejected.");
                }
                if (!allowed.Contains(property.Name))
                {
                    Error(
                        errors,
                        path + "." + property.Name,
                        "unknown_property",
                        "Property is not in the exact parameter contract.");
                }
            }
            foreach (string missing
                in required.Except(seen))
            {
                Error(
                    errors,
                    path + "." + missing,
                    "required",
                    "A required parameter is missing.");
            }
        }

        private static string String(
            JsonElement root,
            string name,
            int minimumLength,
            int maximumLength,
            ICollection<ContractViolation> errors,
            string path = "$.params")
        {
            if (!root.TryGetProperty(
                    name,
                    out JsonElement value)
                || value.ValueKind != JsonValueKind.String)
            {
                Error(
                    errors,
                    path + "." + name,
                    "string_required",
                    "A string is required.");
                return null;
            }
            string text;
            try
            {
                text = value.GetString();
            }
            catch (InvalidOperationException)
            {
                Error(
                    errors,
                    path + "." + name,
                    "string_range",
                    "String length or characters are invalid.");
                return null;
            }
            if (text.Length < minimumLength
                || text.Length > maximumLength
                || text.Any(char.IsControl))
            {
                Error(
                    errors,
                    path + "." + name,
                    "string_range",
                    "String length or characters are invalid.");
                return null;
            }
            return text;
        }

        private static string OptionalString(
            JsonElement root,
            string name,
            int minimumLength,
            int maximumLength,
            ICollection<ContractViolation> errors)
        {
            return root.TryGetProperty(name, out _)
                ? String(
                    root,
                    name,
                    minimumLength,
                    maximumLength,
                    errors)
                : null;
        }

        private static void ConstantString(
            JsonElement root,
            string name,
            string expected,
            ICollection<ContractViolation> errors,
            string path = "$.params")
        {
            string actual = String(
                root,
                name,
                1,
                Math.Max(128, expected.Length),
                errors,
                path);
            if (actual != null
                && !string.Equals(
                    actual,
                    expected,
                    StringComparison.Ordinal))
            {
                Error(
                    errors,
                    path + "." + name,
                    "constant",
                    name + " must equal " + expected + ".");
            }
        }

        private static void ConstantSetString(
            JsonElement root,
            string name,
            IReadOnlySet<string> allowed,
            ICollection<ContractViolation> errors,
            string path = "$.params")
        {
            string actual = String(
                root,
                name,
                1,
                AgentProtocolV1
                    .MaximumOpaqueIdCharacters,
                errors,
                path);
            if (actual != null
                && (allowed == null
                    || !allowed.Contains(actual)))
            {
                Error(
                    errors,
                    path + "." + name,
                    "enum",
                    name
                        + " is not an exportable consent purpose.");
            }
        }

        private static void Opaque(
            JsonElement root,
            string name,
            ICollection<ContractViolation> errors,
            string path = "$.params")
        {
            string value = String(
                root,
                name,
                AgentProtocolV1.MinimumOpaqueIdCharacters,
                AgentProtocolV1.MaximumOpaqueIdCharacters,
                errors,
                path);
            if (value != null
                && !OpaqueIdPattern.IsMatch(value))
            {
                Error(
                    errors,
                    path + "." + name,
                    "opaque_id",
                    "A base64url-compatible opaque ID is required.");
            }
        }

        private static void Sha256(
            JsonElement root,
            string name,
            ICollection<ContractViolation> errors,
            string path = "$.params")
        {
            string value = String(
                root,
                name,
                64,
                64,
                errors,
                path);
            if (value != null
                && !Sha256Pattern.IsMatch(value))
            {
                Error(
                    errors,
                    path + "." + name,
                    "sha256",
                    "A SHA-256 hex string is required.");
            }
        }

        private static void OptionalSha256(
            JsonElement root,
            string name,
            ICollection<ContractViolation> errors)
        {
            if (root.TryGetProperty(name, out _))
            {
                Sha256(root, name, errors);
            }
        }

        private static void Positive(
            JsonElement root,
            string name,
            ICollection<ContractViolation> errors,
            string path = "$.params")
        {
            Integer(
                root,
                name,
                1,
                CanonicalJsonV1.MaximumSafeInteger,
                errors,
                path);
        }

        private static long? Integer(
            JsonElement root,
            string name,
            long minimum,
            long maximum,
            ICollection<ContractViolation> errors,
            string path = "$.params")
        {
            if (!root.TryGetProperty(
                    name,
                    out JsonElement value)
                || value.ValueKind != JsonValueKind.Number
                || !value.TryGetInt64(out long number)
                || number < minimum
                || number > maximum)
            {
                Error(
                    errors,
                    path + "." + name,
                    "integer_range",
                    "Integer is outside the frozen range.");
                return null;
            }
            return number;
        }

        private static bool? Boolean(
            JsonElement root,
            string name,
            ICollection<ContractViolation> errors)
        {
            if (!root.TryGetProperty(
                    name,
                    out JsonElement value)
                || value.ValueKind != JsonValueKind.True
                && value.ValueKind != JsonValueKind.False)
            {
                Error(
                    errors,
                    "$.params." + name,
                    "boolean_required",
                    "A boolean is required.");
                return null;
            }
            return value.GetBoolean();
        }

        private static IReadOnlyList<string> StringArray(
            JsonElement root,
            string name,
            IReadOnlySet<string> allowed,
            bool requireNonEmpty,
            int maximumItems,
            ICollection<ContractViolation> errors,
            string path = "$.params",
            bool opaqueItems = false)
        {
            if (!root.TryGetProperty(
                    name,
                    out JsonElement value)
                || value.ValueKind != JsonValueKind.Array)
            {
                Error(
                    errors,
                    path + "." + name,
                    "array_required",
                    "An array is required.");
                return null;
            }
            if ((requireNonEmpty
                    && value.GetArrayLength() == 0)
                || value.GetArrayLength() > maximumItems)
            {
                Error(
                    errors,
                    path + "." + name,
                    "array_range",
                    "Array size is outside the frozen range.");
            }
            var result = new List<string>();
            var seen = new HashSet<string>(
                StringComparer.Ordinal);
            int index = 0;
            foreach (JsonElement item
                in value.EnumerateArray())
            {
                if (item.ValueKind
                    != JsonValueKind.String)
                {
                    Error(
                        errors,
                        path
                            + "."
                            + name
                            + "["
                            + index
                            + "]",
                        "string_required",
                        "Array items must be strings.");
                    index++;
                    continue;
                }
                string text = item.GetString();
                if (text.Length == 0
                    || text.Length
                        > AgentProtocolV1
                            .MaximumOpaqueIdCharacters
                    || (opaqueItems
                        && !OpaqueIdPattern.IsMatch(text))
                    || (allowed != null
                        && !allowed.Contains(text))
                    || !seen.Add(text))
                {
                    Error(
                        errors,
                        path
                            + "."
                            + name
                            + "["
                            + index
                            + "]",
                        "array_item_invalid",
                        "Array item is unknown, duplicate, or malformed.");
                }
                result.Add(text);
                index++;
            }
            return result;
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
}
