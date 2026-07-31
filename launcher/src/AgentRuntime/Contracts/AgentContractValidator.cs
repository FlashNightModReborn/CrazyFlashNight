using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Text.Json;
using System.Text.RegularExpressions;

namespace CF7Launcher.AgentRuntime.Contracts
{
    public sealed class ContractViolation
    {
        public ContractViolation(string path, string code, string message)
        {
            Path = path;
            Code = code;
            Message = message;
        }

        public string Path { get; }
        public string Code { get; }
        public string Message { get; }

        public override string ToString()
        {
            return Path + ": " + Code + " (" + Message + ")";
        }
    }

    public static class AgentContractValidator
    {
        private const ulong PlayerGuiLeaseMilliseconds = 30_000;
        private const ulong PlayerDomainLeaseMilliseconds = 60_000;
        private const ulong StructuredActionLeaseMilliseconds = 30_000;
        private const ulong ShutdownLeaseMilliseconds = 30_000;
        private const ulong DeveloperLeaseMilliseconds = 300_000;
        private const ulong UnattendedLeaseMilliseconds = 1_800_000;
        private const int MaximumPlayerGuiActions = 8;

        private static readonly Regex OpaqueIdPattern = new Regex(
            "^[A-Za-z0-9_-]{" + AgentProtocolV1.MinimumOpaqueIdCharacters + "," +
            AgentProtocolV1.MaximumOpaqueIdCharacters + "}$",
            RegexOptions.CultureInvariant);

        private static readonly Regex Sha256Pattern = new Regex(
            "^[A-Fa-f0-9]{64}$",
            RegexOptions.CultureInvariant);

        private static readonly IReadOnlySet<string> DataScopes =
            ObservationDataScopesV1.All;

        private static readonly IReadOnlySet<string> ExecutableOperations = new HashSet<string>(
            new[]
            {
                AgentCapabilitiesV1.Click,
                AgentCapabilitiesV1.PressKey,
                AgentCapabilitiesV1.TypeText,
                AgentCapabilitiesV1.Scroll,
                AgentCapabilitiesV1.SetValue,
                AgentCapabilitiesV1.Drag,
                AgentCapabilitiesV1.PerformSecondaryAction,
                AgentCapabilitiesV1.ActivateWindow,
                AgentCapabilitiesV1.SessionShutdown,
                AgentCapabilitiesV1.LifecycleReveal,
                AgentCapabilitiesV1.LifecycleCancel,
                AgentCapabilitiesV1.PanelOpen,
                AgentMethodsV1.HairInspect,
                AgentMethodsV1.HairPreview,
                AgentMethodsV1.HairCommit,
                AgentMethodsV1.HairReconcile,
                AgentMethodsV1.HairRestore
            },
            StringComparer.Ordinal);

        public static IReadOnlyList<ContractViolation> Validate(SessionDescriptor value)
        {
            var errors = new List<ContractViolation>();
            if (value == null)
            {
                Error(errors, "$", "required", "Session descriptor is required.");
                return errors;
            }

            ExactProtocol(value.ProtocolVersion, "$.protocolVersion", errors);
            OpaqueId(value.SessionId, "$.sessionId", errors);
            Positive(value.LifecycleGeneration, "$.lifecycleGeneration", errors);
            Required(value.Slot, "$.slot", 128, errors);
            Required(value.LauncherPath, "$.launcherPath", 32_767, errors);
            if (!string.IsNullOrWhiteSpace(value.LauncherPath) &&
                !Path.IsPathFullyQualified(value.LauncherPath))
            {
                Error(errors, "$.launcherPath", "absolute_path_required", "Launcher path must be absolute.");
            }
            if (value.LauncherPid <= 0)
                Error(errors, "$.launcherPid", "positive_required", "Launcher PID must be positive.");
            if (value.LauncherStartTime == default)
                Error(errors, "$.launcherStartTime", "required", "Launcher start time is required.");
            if (value.FlashPid.HasValue != value.FlashStartTime.HasValue)
            {
                Error(errors, "$.flashPid", "pair_required", "Flash PID and start time must be present together.");
            }
            if (value.FlashPid.HasValue && value.FlashPid.Value <= 0)
                Error(errors, "$.flashPid", "positive_required", "Flash PID must be positive.");
            Hash(value.CoreSha256, "$.coreSha256", errors);
            if ((value.AttemptId == null) != !value.AttemptGeneration.HasValue)
            {
                Error(errors, "$.attemptId", "pair_required", "Attempt ID and generation must be present together.");
            }
            if (value.AttemptId != null)
            {
                OpaqueId(value.AttemptId, "$.attemptId", errors);
                Positive(value.AttemptGeneration.GetValueOrDefault(), "$.attemptGeneration", errors);
            }

            ValidateRuntimeQualification(value, errors);

            if (value.Surfaces == null)
            {
                Error(errors, "$.surfaces", "required", "Surface list is required.");
            }
            else
            {
                var targetIds = new HashSet<string>(StringComparer.Ordinal);
                for (int i = 0; i < value.Surfaces.Count; i++)
                {
                    SurfaceDescriptor surface = value.Surfaces[i];
                    ValidateSurface(surface, "$.surfaces[" + i + "]", errors);
                    if (surface != null && surface.TargetId != null && !targetIds.Add(surface.TargetId))
                    {
                        Error(errors, "$.surfaces[" + i + "].targetId", "duplicate",
                            "Target IDs must be unique inside a session.");
                    }
                }
            }

            ValidateCapabilities(value.Capabilities, "$.capabilities", false, errors);
            if (value.ActivePanel != null)
            {
                Required(value.ActivePanel.Name, "$.activePanel.name", 128, errors);
                OpaqueId(value.ActivePanel.InstanceId, "$.activePanel.instanceId", errors);
                OpaqueId(value.ActivePanel.TargetId, "$.activePanel.targetId", errors);
                if (value.ActivePanel.TargetId != null
                    && (value.Surfaces == null
                        || !value.Surfaces.Any(
                            surface => string.Equals(
                                surface?.TargetId,
                                value.ActivePanel.TargetId,
                                StringComparison.Ordinal))))
                {
                    Error(
                        errors,
                        "$.activePanel.targetId",
                        "target_not_found",
                        "Active panel target must reference a discoverable surface.");
                }
            }
            return errors;
        }

        public static IReadOnlyList<ContractViolation> Validate(ObservationGrantDescriptor value)
        {
            var errors = new List<ContractViolation>();
            if (value == null)
            {
                Error(errors, "$", "required", "Observation grant is required.");
                return errors;
            }

            OpaqueId(value.ObservationGrantId, "$.observationGrantId", errors);
            OpaqueId(value.OwnerClientId, "$.ownerClientId", errors);
            OpaqueId(value.SecurityPrincipalId, "$.securityPrincipalId", errors);
            ValidateSessionScope(value.SessionScope, "$.sessionScope", errors);
            ValidateOpaqueIdList(value.TargetScope, "$.targetScope", true, errors);
            ValidateStringSet(value.DataScope, "$.dataScope", DataScopes, true, errors);
            ValidateTimeRange(
                value.IssuedMonotonic,
                value.ExpiresMonotonic,
                AgentProtocolV1.MaximumObservationGrantTtlMs,
                "$",
                errors);
            if (value.AllowPersistence &&
                (value.DataScope == null || !value.DataScope.Contains("retention.persist", StringComparer.Ordinal)))
            {
                Error(errors, "$.allowPersistence", "scope_required",
                    "Persistence requires retention.persist data scope.");
            }
            if (value.AllowExport &&
                (value.DataScope == null || !value.DataScope.Contains("data.export", StringComparer.Ordinal)))
            {
                Error(errors, "$.allowExport", "scope_required", "Export requires data.export scope.");
            }
            if (value.State == ObservationGrantState.Revoked)
                Required(value.RevokeReason, "$.revokeReason", 128, errors);
            return errors;
        }

        public static IReadOnlyList<ContractViolation> Validate(LeaseDescriptor value)
        {
            var errors = new List<ContractViolation>();
            if (value == null)
            {
                Error(errors, "$", "required", "Lease is required.");
                return errors;
            }

            OpaqueId(value.LeaseId, "$.leaseId", errors);
            OpaqueId(value.OwnerClientId, "$.ownerClientId", errors);
            OpaqueId(value.SecurityPrincipalId, "$.securityPrincipalId", errors);
            if (!Enum.IsDefined(value.Purpose))
            {
                Error(
                    errors,
                    "$.purpose",
                    "enum",
                    "Lease purpose is not registered.");
            }
            if (value.Scope == null)
            {
                Error(errors, "$.scope", "required", "Lease scope is required.");
            }
            else
            {
                ValidateSessionScope(value.Scope.Session, "$.scope.session", errors);
                ValidateOpaqueIdList(value.Scope.TargetScope, "$.scope.targetScope", true, errors);
                ValidateCapabilities(value.Scope.OperationScope, "$.scope.operationScope", true, errors);
                if (value.Scope.MaximumActions <= 0)
                    Error(errors, "$.scope.maximumActions", "positive_required", "Action count must be positive.");
                if (value.SessionMode == SessionMode.PlayerAssist)
                {
                    Required(value.Scope.ArgumentBoundsHash, "$.scope.argumentBoundsHash", 128, errors);
                }
            }

            ValidateCapabilities(value.Capabilities, "$.capabilities", true, errors);
            bool hasShutdownCapability =
                value.Capabilities?.Contains(
                    AgentCapabilitiesV1.SessionShutdown,
                    StringComparer.Ordinal) == true;
            bool hasShutdownOperationScope =
                value.Scope?.OperationScope?.Contains(
                    AgentCapabilitiesV1.SessionShutdown,
                    StringComparer.Ordinal) == true;
            bool hasStructuredActionCapability =
                value.Capabilities?.Contains(
                    AgentCapabilitiesV1.PanelOpen,
                    StringComparer.Ordinal) == true;
            bool hasStructuredActionOperationScope =
                value.Scope?.OperationScope?.Contains(
                    AgentCapabilitiesV1.PanelOpen,
                    StringComparer.Ordinal) == true;
            if (value.Purpose == LeasePurpose.Shutdown)
            {
                if (value.SessionMode == SessionMode.PlayerAssist)
                {
                    Error(
                        errors,
                        "$.sessionMode",
                        "lease_kind_mismatch",
                        "Player-assist sessions cannot carry shutdown leases.");
                }
                if (value.Capabilities == null
                    || value.Capabilities.Count != 1
                    || !hasShutdownCapability)
                {
                    Error(
                        errors,
                        "$.capabilities",
                        "exactly_one",
                        "Shutdown lease capability must be exactly session.shutdown.");
                }
                if (value.Scope?.OperationScope == null
                    || value.Scope.OperationScope.Count != 1
                    || !hasShutdownOperationScope)
                {
                    Error(
                        errors,
                        "$.scope.operationScope",
                        "exactly_one",
                        "Shutdown operation scope must be exactly session.shutdown.");
                }
                if (value.Scope?.TargetScope == null
                    || value.Scope.TargetScope.Count != 1)
                {
                    Error(
                        errors,
                        "$.scope.targetScope",
                        "exactly_one",
                        "Shutdown leases bind exactly one target.");
                }
                if (value.Scope == null
                    || value.Scope.MaximumActions != 1)
                {
                    Error(
                        errors,
                        "$.scope.maximumActions",
                        "constant",
                        "Shutdown leases are one-shot.");
                }
            }
            else
            {
                if (hasShutdownCapability)
                {
                    Error(
                        errors,
                        "$.capabilities",
                        "lease_kind_mismatch",
                        "session.shutdown requires a shutdown lease.");
                }
                if (hasShutdownOperationScope)
                {
                    Error(
                        errors,
                        "$.scope.operationScope",
                        "lease_kind_mismatch",
                        "session.shutdown requires a shutdown lease.");
                }
            }
            if (value.Purpose == LeasePurpose.StructuredAction)
            {
                if (value.SessionMode == SessionMode.PlayerAssist)
                {
                    Error(
                        errors,
                        "$.sessionMode",
                        "lease_kind_mismatch",
                        "Player-assist sessions cannot carry structured-action leases.");
                }
                if (value.Capabilities == null
                    || value.Capabilities.Count != 1
                    || !hasStructuredActionCapability)
                {
                    Error(
                        errors,
                        "$.capabilities",
                        "exactly_one",
                        "Structured-action lease capability must be exactly panel.open.");
                }
                if (value.Scope?.OperationScope == null
                    || value.Scope.OperationScope.Count != 1
                    || !hasStructuredActionOperationScope)
                {
                    Error(
                        errors,
                        "$.scope.operationScope",
                        "exactly_one",
                        "Structured-action operation scope must be exactly panel.open.");
                }
                if (value.Scope?.TargetScope == null
                    || value.Scope.TargetScope.Count != 1)
                {
                    Error(
                        errors,
                        "$.scope.targetScope",
                        "exactly_one",
                        "Structured-action leases bind exactly one target.");
                }
                if (value.Scope == null
                    || value.Scope.MaximumActions != 1)
                {
                    Error(
                        errors,
                        "$.scope.maximumActions",
                        "constant",
                        "Structured-action leases are one-shot.");
                }
            }
            else
            {
                if (hasStructuredActionCapability)
                {
                    Error(
                        errors,
                        "$.capabilities",
                        "lease_kind_mismatch",
                        "panel.open requires a structured-action lease.");
                }
                if (hasStructuredActionOperationScope)
                {
                    Error(
                        errors,
                        "$.scope.operationScope",
                        "lease_kind_mismatch",
                        "panel.open requires a structured-action lease.");
                }
            }
            ulong maximumDuration =
                value.Purpose == LeasePurpose.Shutdown
                ? ShutdownLeaseMilliseconds
                : value.Purpose == LeasePurpose.StructuredAction
                ? StructuredActionLeaseMilliseconds
                : value.SessionMode switch
            {
                SessionMode.PlayerAssist when value.Purpose == LeasePurpose.DomainTransaction =>
                    PlayerDomainLeaseMilliseconds,
                SessionMode.PlayerAssist => PlayerGuiLeaseMilliseconds,
                SessionMode.DeveloperInteractive => DeveloperLeaseMilliseconds,
                SessionMode.UnattendedTest => UnattendedLeaseMilliseconds,
                _ => 0
            };
            ValidateTimeRange(value.IssuedMonotonic, value.ExpiresMonotonic, maximumDuration, "$", errors);
            if (value.RenewAfter.HasValue &&
                (value.RenewAfter.Value <= value.IssuedMonotonic ||
                 value.RenewAfter.Value >= value.ExpiresMonotonic))
            {
                Error(errors, "$.renewAfter", "range", "renewAfter must fall strictly inside the lease.");
            }
            if ((value.Purpose == LeasePurpose.Shutdown
                 || value.Purpose == LeasePurpose.StructuredAction)
                && value.RenewAfter.HasValue)
            {
                Error(
                    errors,
                    "$.renewAfter",
                    "forbidden",
                    "Dedicated one-shot leases are not renewable.");
            }
            if (value.HumanOverridePolicy != HumanOverridePolicy.AlwaysPreempt)
            {
                Error(errors, "$.humanOverridePolicy", "constant", "Human input must always preempt.");
            }
            if (value.SessionMode == SessionMode.PlayerAssist)
            {
                Required(value.ConsentReceipt, "$.consentReceipt", 256, errors);
                if (value.Scope != null && value.Scope.TargetScope != null &&
                    value.Scope.TargetScope.Count != 1)
                {
                    Error(errors, "$.scope.targetScope", "exactly_one",
                        "Player-assist leases bind exactly one target.");
                }
                if (value.Scope != null && value.Purpose == LeasePurpose.GuiInput &&
                    value.Scope.MaximumActions > MaximumPlayerGuiActions)
                {
                    Error(errors, "$.scope.maximumActions", "maximum",
                        "Player-assist GUI leases permit at most eight actions.");
                }
                if (value.Scope != null && value.Purpose == LeasePurpose.DomainTransaction &&
                    value.Scope.MaximumActions != 1)
                {
                    Error(errors, "$.scope.maximumActions", "constant",
                        "Player-assist domain leases are one-shot.");
                }
            }
            if (value.State == LeaseState.Revoked)
                Required(value.RevokeReason, "$.revokeReason", 128, errors);
            return errors;
        }

        public static IReadOnlyList<ContractViolation> Validate(ObservationEnvelope value)
        {
            var errors = new List<ContractViolation>();
            if (value == null)
            {
                Error(errors, "$", "required", "Observation is required.");
                return errors;
            }

            OpaqueId(value.ObservationId, "$.observationId", errors);
            OpaqueId(value.ObservationGrantId, "$.observationGrantId", errors);
            OpaqueId(value.SessionId, "$.sessionId", errors);
            OpaqueId(value.TargetId, "$.targetId", errors);
            Positive(value.LifecycleGeneration, "$.lifecycleGeneration", errors);
            Positive(value.SurfaceEpoch, "$.surfaceEpoch", errors);
            Positive(value.CoordinateSpaceVersion, "$.coordinateSpaceVersion", errors);
            Positive(value.FocusEpoch, "$.focusEpoch", errors);
            Positive(value.ModalEpoch, "$.modalEpoch", errors);
            if (value.CapturedUtc == default)
                Error(errors, "$.capturedUtc", "required", "Capture time is required.");
            Positive(value.CapturedAtMonotonic, "$.capturedAtMonotonic", errors);
            if ((value.AttemptId == null) != !value.AttemptGeneration.HasValue)
                Error(errors, "$.attemptId", "pair_required", "Attempt ID and generation must be present together.");
            if (value.AttemptId != null)
            {
                OpaqueId(value.AttemptId, "$.attemptId", errors);
                Positive(value.AttemptGeneration.GetValueOrDefault(), "$.attemptGeneration", errors);
            }
            if ((value.SemanticSnapshotId == null) != !value.SemanticGeneration.HasValue)
            {
                Error(errors, "$.semanticSnapshotId", "pair_required",
                    "Semantic snapshot ID and generation must be present together.");
            }
            if (value.SemanticSnapshotId != null)
            {
                OpaqueId(value.SemanticSnapshotId, "$.semanticSnapshotId", errors);
                Positive(value.SemanticGeneration.GetValueOrDefault(), "$.semanticGeneration", errors);
            }
            if (value.Minimized && value.Active)
                Error(errors, "$.active", "state_conflict", "A minimized target cannot be active.");
            if (value.BlockingModalKind == BlockingModalKind.HumanOnlySecurity ||
                value.BlockingModalKind == BlockingModalKind.Foreign ||
                value.BlockingModalKind == BlockingModalKind.Unknown)
            {
                if (value.Frames != null && value.Frames.Count != 0)
                    Error(errors, "$.frames", "security_surface_redaction", "Blocking security/foreign state returns no frames.");
                if (value.Accessibility.HasValue || value.Focus.HasValue || value.Selection.HasValue)
                    Error(errors, "$.accessibility", "security_surface_redaction",
                        "Blocking security/foreign state returns no semantic metadata.");
            }

            if (value.Frames == null)
            {
                Error(errors, "$.frames", "required", "Frame list is required.");
            }
            else
            {
                var ids = new HashSet<string>(StringComparer.Ordinal);
                for (int i = 0; i < value.Frames.Count; i++)
                {
                    FrameEnvelope frame = value.Frames[i];
                    ValidateFrame(frame, value, "$.frames[" + i + "]", errors);
                    if (frame != null && frame.FrameId != null && !ids.Add(frame.FrameId))
                        Error(errors, "$.frames[" + i + "].frameId", "duplicate", "Frame IDs must be unique.");
                }
            }
            return errors;
        }

        public static IReadOnlyList<ContractViolation> Validate(ActionEnvelope value)
        {
            var errors = new List<ContractViolation>();
            if (value == null)
            {
                Error(errors, "$", "required", "Action is required.");
                return errors;
            }

            OpaqueId(value.ActionId, "$.actionId", errors);
            OpaqueId(value.IdempotencyKey, "$.idempotencyKey", errors);
            OpaqueId(value.SessionId, "$.sessionId", errors);
            OpaqueId(value.ObservationGrantId, "$.observationGrantId", errors);
            OpaqueId(value.LeaseId, "$.leaseId", errors);
            OpaqueId(value.ObservationId, "$.observationId", errors);
            OpaqueId(value.TargetId, "$.targetId", errors);
            Positive(value.ExpectedLifecycleGeneration, "$.expectedLifecycleGeneration", errors);
            Positive(value.ExpectedSurfaceEpoch, "$.expectedSurfaceEpoch", errors);
            Positive(value.ExpectedCoordinateSpaceVersion, "$.expectedCoordinateSpaceVersion", errors);
            Positive(value.ExpectedFocusEpoch, "$.expectedFocusEpoch", errors);
            Positive(value.ExpectedModalEpoch, "$.expectedModalEpoch", errors);
            if (value.DeadlineMs <= 0 || value.DeadlineMs > AgentProtocolV1.MaximumActionDeadlineMs)
            {
                Error(errors, "$.deadlineMs", "range",
                    "Action deadline must be between 1 and " + AgentProtocolV1.MaximumActionDeadlineMs + " ms.");
            }
            if (value.ExpectedAttemptId != null)
            {
                OpaqueId(value.ExpectedAttemptId, "$.expectedAttemptId", errors);
                if (!value.ExpectedAttemptGeneration.HasValue)
                    Error(errors, "$.expectedAttemptGeneration", "pair_required", "Attempt generation is required.");
            }
            else if (value.ExpectedAttemptGeneration.HasValue)
            {
                Error(errors, "$.expectedAttemptId", "pair_required", "Attempt ID is required.");
            }
            if (value.ExpectedPanelInstanceId != null)
                OpaqueId(value.ExpectedPanelInstanceId, "$.expectedPanelInstanceId", errors);
            if (value.ExpectedSemanticGeneration.HasValue)
                Positive(value.ExpectedSemanticGeneration.Value, "$.expectedSemanticGeneration", errors);
            if (value.ExpectedDocumentGeneration.HasValue)
                Positive(value.ExpectedDocumentGeneration.Value, "$.expectedDocumentGeneration", errors);
            if (!ExecutableOperations.Contains(value.Operation ?? string.Empty))
                Error(errors, "$.operation", "unknown_operation", "Operation is not executable in v1.");
            if (value.Arguments.ValueKind != JsonValueKind.Object)
            {
                Error(errors, "$.arguments", "object_required", "Action arguments must be a JSON object.");
            }
            else
            {
                try
                {
                    CanonicalJsonV1.Canonicalize(value.Arguments.GetRawText());
                }
                catch (Exception exception) when (
                    exception is InvalidDataException
                    || exception is JsonException
                    || exception is InvalidOperationException)
                {
                    Error(errors, "$.arguments", "canonical_json", exception.Message);
                }
            }
            Required(value.Reason, "$.reason", AgentProtocolV1.MaximumReasonCharacters, errors);

            bool semanticClick = value.Operation == AgentCapabilitiesV1.Click &&
                                 value.NodeId != null;
            bool coordinateAction =
                value.Operation == AgentCapabilitiesV1.Scroll ||
                value.Operation == AgentCapabilitiesV1.Drag ||
                (value.Operation == AgentCapabilitiesV1.Click && !semanticClick);
            if (coordinateAction)
            {
                OpaqueId(value.FrameId, "$.frameId", errors);
                RequireCoordinateSpace(value.Arguments, errors);
            }
            bool semanticAction =
                semanticClick ||
                value.Operation == AgentCapabilitiesV1.SetValue ||
                value.Operation == AgentCapabilitiesV1.PerformSecondaryAction;
            if (semanticAction)
            {
                OpaqueId(value.NodeId, "$.nodeId", errors);
                OpaqueId(value.SemanticSnapshotId, "$.semanticSnapshotId", errors);
                if (!value.ExpectedSemanticGeneration.HasValue)
                    Error(errors, "$.expectedSemanticGeneration", "required", "Semantic generation is required.");
            }
            return errors;
        }

        public static IReadOnlyList<ContractViolation> Validate(ActionReceipt value)
        {
            var errors = new List<ContractViolation>();
            if (value == null)
            {
                Error(errors, "$", "required", "Action receipt is required.");
                return errors;
            }

            OpaqueId(value.ActionId, "$.actionId", errors);
            Positive(value.AuditSequence, "$.auditSequence", errors);
            if (!value.Terminal)
                Error(errors, "$.terminal", "constant", "v1 action receipts are terminal.");
            if (!AgentReasonCodesV1.TryGet(value.ReasonCode, out ReasonCodeDefinition reason))
            {
                Error(errors, "$.reasonCode", "unknown_reason_code", "Reason code is not registered.");
            }
            else
            {
                if (!reason.AllowedOutcomes.Contains(value.Outcome))
                    Error(errors, "$.outcome", "reason_outcome_mismatch", "Outcome is not allowed for reason code.");
                if (!reason.AllowedReconcileKinds.Contains(value.ReconcileKind))
                    Error(errors, "$.reconcileKind", "reason_reconcile_mismatch",
                        "Reconcile kind is not allowed for reason code.");
                if (value.Retryable != reason.Retryable)
                    Error(errors, "$.retryable", "reason_retryable_mismatch",
                        "Retryability is registry-owned, not client-selected.");
            }
            if (value.Outcome == ActionOutcome.Unknown)
            {
                if (value.ReconcileKind == ReconcileKind.None)
                    Error(errors, "$.reconcileKind", "required", "Unknown outcomes require reconciliation.");
                if (value.Retryable)
                    Error(errors, "$.retryable", "constant", "Unknown outcomes are never blindly retryable.");
                if (value.EvidenceKind != EvidenceKind.ReconciliationRequired)
                    Error(errors, "$.evidenceKind", "constant", "Unknown outcomes require reconciliation evidence.");
            }
            if (value.Outcome == ActionOutcome.InputDispatched &&
                value.EvidenceKind != EvidenceKind.BrokerDispatch)
            {
                Error(errors, "$.evidenceKind", "constant", "Input dispatch requires broker-dispatch evidence.");
            }
            if (value.Outcome == ActionOutcome.EffectObserved)
            {
                if (value.EvidenceKind != EvidenceKind.PostObservation)
                    Error(errors, "$.evidenceKind", "constant", "Observed effect requires post-observation evidence.");
                OpaqueId(value.AfterObservationId, "$.afterObservationId", errors);
            }
            if (value.Outcome == ActionOutcome.DomainCommitted)
            {
                if (value.EvidenceKind != EvidenceKind.DomainAck)
                {
                    Error(errors, "$.evidenceKind", "constant",
                        "Domain commit requires authoritative domain ack.");
                }
                ValidateHairDomainResult(value.DomainResult, errors);
            }
            else if (value.DomainResult != null)
            {
                Error(errors, "$.domainResult", "prohibited",
                    "Domain result is only valid for a domain-committed receipt.");
            }
            OpaqueId(value.BeforeObservationId, "$.beforeObservationId", errors);
            if (value.ActualTargetId != null)
                OpaqueId(value.ActualTargetId, "$.actualTargetId", errors);
            return errors;
        }

        private static void ValidateHairDomainResult(
            HairDomainActionResult value,
            List<ContractViolation> errors)
        {
            if (value == null)
            {
                Error(errors, "$.domainResult", "required",
                    "Domain-committed receipts require a typed domain result.");
                return;
            }

            OpaqueId(
                value.TransactionId,
                "$.domainResult.transactionId",
                errors);
            Hash(
                value.PreviewHash,
                "$.domainResult.previewHash",
                errors);

            bool hasRestoreToken = value.RestoreToken != null;
            bool hasRestoreExpiry = value.RestoreExpiresAtUtc.HasValue;
            if (hasRestoreToken)
            {
                OpaqueId(
                    value.RestoreToken,
                    "$.domainResult.restoreToken",
                    errors);
            }
            if (hasRestoreToken != hasRestoreExpiry)
            {
                Error(errors, "$.domainResult", "paired_required",
                    "Restore token and restore expiry must be returned together.");
            }
            if (hasRestoreExpiry
                && value.RestoreExpiresAtUtc.Value == default)
            {
                Error(errors, "$.domainResult.restoreExpiresAtUtc", "required",
                    "Restore expiry must be a non-default timestamp.");
            }
        }

        private static void ValidateRuntimeQualification(
            SessionDescriptor value,
            List<ContractViolation> errors)
        {
            if (value.RuntimeQualification == null)
            {
                Error(errors, "$.runtimeQualification", "required", "Runtime qualification is required.");
                return;
            }
            if (value.RuntimeMode == RuntimeMode.UnqualifiedDev)
            {
                Required(value.RuntimeQualification.UnqualifiedReason,
                    "$.runtimeQualification.unqualifiedReason", 256, errors);
                if (value.RuntimeQualification.BuildIdentity != null ||
                    value.RuntimeQualification.PayloadClosure != null)
                {
                    Error(errors, "$.runtimeQualification", "qualification_conflict",
                        "Unqualified runtime cannot carry verified build identity.");
                }
            }
            else
            {
                Hash(value.RuntimeQualification.BuildIdentity,
                    "$.runtimeQualification.buildIdentity", errors);
                Hash(value.RuntimeQualification.PayloadClosure,
                    "$.runtimeQualification.payloadClosure", errors);
                if (value.RuntimeQualification.UnqualifiedReason != null)
                {
                    Error(errors, "$.runtimeQualification.unqualifiedReason", "qualification_conflict",
                        "Verified runtime cannot carry an unqualified reason.");
                }
            }
        }

        private static void ValidateSurface(
            SurfaceDescriptor value,
            string path,
            List<ContractViolation> errors)
        {
            if (value == null)
            {
                Error(errors, path, "required", "Surface is required.");
                return;
            }
            OpaqueId(value.TargetId, path + ".targetId", errors);
            Positive(value.SurfaceEpoch, path + ".surfaceEpoch", errors);
            ValidateRect(value.BoundsPhysical, path + ".boundsPhysical", false, errors);
            if (value.Dpi < 72 || value.Dpi > 960)
                Error(errors, path + ".dpi", "range", "DPI must be between 72 and 960.");
            Positive(value.CoordinateSpaceVersion, path + ".coordinateSpaceVersion", errors);
            Positive(value.FocusEpoch, path + ".focusEpoch", errors);
            Positive(value.ModalEpoch, path + ".modalEpoch", errors);
            if (value.SemanticGeneration.HasValue)
                Positive(value.SemanticGeneration.Value, path + ".semanticGeneration", errors);
            if (value.DocumentGeneration.HasValue)
            {
                Positive(value.DocumentGeneration.Value, path + ".documentGeneration", errors);
                if (value.Kind != SurfaceKind.WebOverlay)
                    Error(errors, path + ".documentGeneration", "surface_kind_mismatch",
                        "Only Web surfaces carry document generation.");
            }
            if (value.ObservationModes == null)
            {
                Error(
                    errors,
                    path + ".observationModes",
                    "required",
                    "Observation mode list is required.");
            }
            if (value.InputModes == null)
            {
                Error(errors, path + ".inputModes", "required", "Input mode list is required.");
            }
            else if (value.ObservationModes != null
                && value.ObservationModes.Count == 0)
            {
                if (value.Kind != SurfaceKind.Flash)
                {
                    Error(
                        errors,
                        path + ".observationModes",
                        "surface_kind_mismatch",
                        "Only Flash surfaces may be metadata-only.");
                }
                if (value.InputModes.Count != 0)
                {
                    Error(
                        errors,
                        path + ".inputModes",
                        "observation_required",
                        "Metadata-only surfaces cannot advertise input modes.");
                }
            }
        }

        private static void ValidateFrame(
            FrameEnvelope frame,
            ObservationEnvelope observation,
            string path,
            List<ContractViolation> errors)
        {
            if (frame == null)
            {
                Error(errors, path, "required", "Frame is required.");
                return;
            }
            OpaqueId(frame.FrameId, path + ".frameId", errors);
            if (!StringComparer.Ordinal.Equals(frame.ObservationId, observation.ObservationId))
                Error(errors, path + ".observationId", "binding_mismatch", "Frame must bind its observation.");
            // One observation may contain the requested surface plus multiple
            // Launcher-owned business modals/windows. Each frame therefore
            // binds its own target generations; only observationId is shared.
            // Gateway/session validation proves that every frame target belongs
            // to the same authorized logical session and is not human-only.
            OpaqueId(frame.TargetId, path + ".targetId", errors);
            Positive(frame.SurfaceEpoch, path + ".surfaceEpoch", errors);
            Positive(
                frame.CoordinateSpaceVersion,
                path + ".coordinateSpaceVersion",
                errors);
            Positive(frame.CapturedAtMonotonic, path + ".capturedAtMonotonic", errors);
            OpaqueId(frame.CoordinateSpaceId, path + ".coordinateSpaceId", errors);
            ValidateRect(frame.CaptureRectPhysical, path + ".captureRectPhysical", false, errors);
            ValidateRect(frame.ClientRectPhysical, path + ".clientRectPhysical", false, errors);
            ValidateRect(frame.ContentRectPhysical, path + ".contentRectPhysical", false, errors);
            if (frame.FrameToTargetContentTransform == null)
                Error(errors, path + ".frameToTargetContentTransform", "required", "Frame transform is required.");
            if (frame.Width <= 0 || frame.Height <= 0)
                Error(errors, path, "positive_required", "Frame dimensions must be positive.");
            if (frame.Dpi < 72 || frame.Dpi > 960)
                Error(errors, path + ".dpi", "range", "DPI must be between 72 and 960.");
            Hash(frame.ContentHash, path + ".contentHash", errors);
            OpaqueId(frame.OpaqueContentHandle, path + ".opaqueContentHandle", errors);
        }

        private static void ValidateSessionScope(
            SessionScopeDescriptor scope,
            string path,
            List<ContractViolation> errors)
        {
            if (scope == null)
            {
                Error(errors, path, "required", "Session scope is required.");
                return;
            }
            OpaqueId(scope.SessionId, path + ".sessionId", errors);
            Positive(scope.LifecycleGeneration, path + ".lifecycleGeneration", errors);
            if (scope.AttemptId != null)
            {
                OpaqueId(scope.AttemptId, path + ".attemptId", errors);
                if (!scope.AttemptGeneration.HasValue)
                    Error(errors, path + ".attemptGeneration", "pair_required", "Attempt generation is required.");
            }
            else if (scope.AttemptGeneration.HasValue)
            {
                Error(errors, path + ".attemptId", "pair_required", "Attempt ID is required.");
            }
            if (scope.CrossAttempt && scope.AttemptId != null)
                Error(errors, path + ".crossAttempt", "scope_conflict", "Cross-attempt scope cannot bind one attempt.");
        }

        private static void ValidateRect(
            PhysicalRect rect,
            string path,
            bool allowEmpty,
            List<ContractViolation> errors)
        {
            if (rect == null)
            {
                Error(errors, path, "required", "Rectangle is required.");
                return;
            }
            if (rect.Width < 0 || rect.Height < 0 || (!allowEmpty && (rect.Width == 0 || rect.Height == 0)))
                Error(errors, path, "positive_required", "Rectangle dimensions must be positive.");
        }

        private static void ValidateCapabilities(
            IReadOnlyList<string> capabilities,
            string path,
            bool nonEmpty,
            List<ContractViolation> errors)
        {
            if (capabilities == null)
            {
                Error(errors, path, "required", "Capability list is required.");
                return;
            }
            if (nonEmpty && capabilities.Count == 0)
                Error(errors, path, "non_empty", "Capability list must not be empty.");
            var seen = new HashSet<string>(StringComparer.Ordinal);
            for (int i = 0; i < capabilities.Count; i++)
            {
                string capability = capabilities[i];
                if (!AgentCapabilitiesV1.All.Contains(capability ?? string.Empty))
                    Error(errors, path + "[" + i + "]", "unknown_capability", "Capability is not registered.");
                if (!seen.Add(capability ?? string.Empty))
                    Error(errors, path + "[" + i + "]", "duplicate", "Capabilities must be unique.");
            }
        }

        private static void ValidateOpaqueIdList(
            IReadOnlyList<string> values,
            string path,
            bool nonEmpty,
            List<ContractViolation> errors)
        {
            if (values == null)
            {
                Error(errors, path, "required", "ID list is required.");
                return;
            }
            if (nonEmpty && values.Count == 0)
                Error(errors, path, "non_empty", "ID list must not be empty.");
            if (values.Count
                > AgentProtocolV1.MaximumTargetScopeItems)
            {
                Error(
                    errors,
                    path,
                    "maximum",
                    "ID list exceeds the frozen target-scope bound.");
            }
            var seen = new HashSet<string>(StringComparer.Ordinal);
            for (int i = 0; i < values.Count; i++)
            {
                OpaqueId(values[i], path + "[" + i + "]", errors);
                if (!seen.Add(values[i] ?? string.Empty))
                    Error(errors, path + "[" + i + "]", "duplicate", "IDs must be unique.");
            }
        }

        private static void ValidateStringSet(
            IReadOnlyList<string> values,
            string path,
            IReadOnlySet<string> allowed,
            bool nonEmpty,
            List<ContractViolation> errors)
        {
            if (values == null)
            {
                Error(errors, path, "required", "Value list is required.");
                return;
            }
            if (nonEmpty && values.Count == 0)
                Error(errors, path, "non_empty", "Value list must not be empty.");
            var seen = new HashSet<string>(StringComparer.Ordinal);
            for (int i = 0; i < values.Count; i++)
            {
                if (!allowed.Contains(values[i] ?? string.Empty))
                    Error(errors, path + "[" + i + "]", "unknown_value", "Value is not registered.");
                if (!seen.Add(values[i] ?? string.Empty))
                    Error(errors, path + "[" + i + "]", "duplicate", "Values must be unique.");
            }
        }

        private static void ValidateTimeRange(
            ulong issued,
            ulong expires,
            ulong maximumDuration,
            string path,
            List<ContractViolation> errors)
        {
            Positive(issued, path + ".issuedMonotonic", errors);
            if (expires <= issued)
            {
                Error(errors, path + ".expiresMonotonic", "range", "Expiry must be after issue time.");
                return;
            }
            if (maximumDuration == 0 || expires - issued > maximumDuration)
                Error(errors, path + ".expiresMonotonic", "maximum", "Lifetime exceeds the v1 hard cap.");
        }

        private static void RequireCoordinateSpace(JsonElement arguments, List<ContractViolation> errors)
        {
            if (arguments.ValueKind != JsonValueKind.Object ||
                !arguments.TryGetProperty("coordinateSpace", out JsonElement coordinateSpace) ||
                coordinateSpace.ValueKind != JsonValueKind.String ||
                coordinateSpace.GetString() != "observation_px")
            {
                Error(errors, "$.arguments.coordinateSpace", "constant",
                    "Coordinate actions use observation_px coordinates.");
            }
        }

        private static void ExactProtocol(string value, string path, List<ContractViolation> errors)
        {
            if (!StringComparer.Ordinal.Equals(value, AgentProtocolV1.Version))
                Error(errors, path, "constant", "Protocol version must be " + AgentProtocolV1.Version + ".");
        }

        private static void OpaqueId(string value, string path, List<ContractViolation> errors)
        {
            if (value == null || !OpaqueIdPattern.IsMatch(value))
            {
                Error(errors, path, "opaque_id",
                    "Opaque IDs are 22-128 characters of base64url-compatible text.");
            }
        }

        private static void Hash(string value, string path, List<ContractViolation> errors)
        {
            if (value == null || !Sha256Pattern.IsMatch(value))
                Error(errors, path, "sha256", "Expected a 64-character hexadecimal SHA-256.");
        }

        private static void Required(
            string value,
            string path,
            int maximumLength,
            List<ContractViolation> errors)
        {
            if (string.IsNullOrWhiteSpace(value))
                Error(errors, path, "required", "A non-empty value is required.");
            else if (value.Length > maximumLength)
                Error(errors, path, "maximum_length", "Value exceeds " + maximumLength + " characters.");
        }

        private static void Positive(ulong value, string path, List<ContractViolation> errors)
        {
            if (value == 0)
                Error(errors, path, "positive_required", "Generation/sequence values start at one.");
            else if (value > (ulong)CanonicalJsonV1.MaximumSafeInteger)
                Error(
                    errors,
                    path,
                    "safe_integer",
                    "Generation/sequence values must fit the v1 interoperable integer range.");
        }

        private static void Error(
            ICollection<ContractViolation> errors,
            string path,
            string code,
            string message)
        {
            errors.Add(new ContractViolation(path, code, message));
        }
    }
}
