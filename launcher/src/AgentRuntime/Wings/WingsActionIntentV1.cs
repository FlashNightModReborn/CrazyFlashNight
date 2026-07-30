using System;
using System.Collections.Generic;
using System.Collections.ObjectModel;
using System.IO;
using System.Linq;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using CF7Launcher.AgentRuntime.Contracts;
using CF7Launcher.AgentRuntime.Security;

namespace CF7Launcher.AgentRuntime.Wings
{
    internal enum WingsActionLeaseKind
    {
        GuiInput,
        DomainTransaction
    }

    internal sealed class WingsHairActionBinding
    {
        internal WingsHairActionBinding(
            string transactionId,
            string previewHash,
            string expectedRevision,
            ulong expectedGeneration,
            string snapshotHash,
            string before,
            string after,
            string panelName)
        {
            WingsProtocolValue.RequireOpaqueId(
                transactionId,
                nameof(transactionId));
            WingsProtocolValue.RequireSha256(
                previewHash,
                nameof(previewHash));
            WingsProtocolValue.RequireText(
                expectedRevision,
                256,
                nameof(expectedRevision));
            WingsProtocolValue.RequireSha256(
                snapshotHash,
                nameof(snapshotHash));
            WingsProtocolValue.RequireText(
                before,
                160,
                nameof(before));
            WingsProtocolValue.RequireText(
                after,
                160,
                nameof(after));
            WingsProtocolValue.RequireText(
                panelName,
                160,
                nameof(panelName));

            TransactionId = transactionId;
            PreviewHash = previewHash.ToLowerInvariant();
            ExpectedRevision = expectedRevision;
            ExpectedGeneration = expectedGeneration;
            SnapshotHash = snapshotHash.ToLowerInvariant();
            Before = before;
            After = after;
            PanelName = panelName;
        }

        public string TransactionId { get; }
        public string PreviewHash { get; }
        public string ExpectedRevision { get; }
        public ulong ExpectedGeneration { get; }
        public string SnapshotHash { get; }
        public string Before { get; }
        public string After { get; }
        public string PanelName { get; }
    }

    /// <summary>
    /// Exact Launcher-owned facts used to issue one structured intent. The
    /// Persona layer never builds this snapshot from dialogue or model text.
    /// </summary>
    internal sealed class WingsActionHostBindingSnapshot
    {
        internal WingsActionHostBindingSnapshot(
            string sessionId,
            ulong lifecycleGeneration,
            string attemptId,
            ulong? attemptGeneration,
            string slot,
            string saveBindingId,
            string saveSignature,
            long? saveRevision,
            string loreViewId,
            string targetId,
            ulong surfaceEpoch,
            string panelInstanceId,
            ulong? documentGeneration,
            string semanticSnapshotId,
            ulong? semanticGeneration,
            string nodeId,
            ulong coordinateSpaceVersion,
            ulong focusEpoch,
            ulong modalEpoch,
            string observationGrantId,
            string observationId,
            string frameId,
            WingsHairActionBinding hairBinding = null)
        {
            WingsProtocolValue.RequireOpaqueId(
                sessionId,
                nameof(sessionId));
            if (lifecycleGeneration == 0)
                throw new ArgumentOutOfRangeException(
                    nameof(lifecycleGeneration));
            ValidateOptionalOpaqueId(
                attemptId,
                nameof(attemptId));
            if (attemptGeneration == 0)
                throw new ArgumentOutOfRangeException(
                    nameof(attemptGeneration));
            WingsProtocolValue.RequireText(
                slot,
                160,
                nameof(slot));
            WingsProtocolValue.RequireOpaqueId(
                saveBindingId,
                nameof(saveBindingId));
            ValidateOptionalSha256(
                saveSignature,
                nameof(saveSignature));
            if (saveRevision < 0)
                throw new ArgumentOutOfRangeException(
                    nameof(saveRevision));
            WingsProtocolValue.RequireOpaqueId(
                loreViewId,
                nameof(loreViewId));
            WingsProtocolValue.RequireOpaqueId(
                targetId,
                nameof(targetId));
            if (surfaceEpoch == 0)
                throw new ArgumentOutOfRangeException(
                    nameof(surfaceEpoch));
            ValidateOptionalOpaqueId(
                panelInstanceId,
                nameof(panelInstanceId));
            ValidateOptionalOpaqueId(
                semanticSnapshotId,
                nameof(semanticSnapshotId));
            ValidateOptionalOpaqueId(
                nodeId,
                nameof(nodeId));
            if (coordinateSpaceVersion == 0)
                throw new ArgumentOutOfRangeException(
                    nameof(coordinateSpaceVersion));
            WingsProtocolValue.RequireOpaqueId(
                observationGrantId,
                nameof(observationGrantId));
            WingsProtocolValue.RequireOpaqueId(
                observationId,
                nameof(observationId));
            ValidateOptionalOpaqueId(
                frameId,
                nameof(frameId));

            SessionId = sessionId;
            LifecycleGeneration = lifecycleGeneration;
            AttemptId = attemptId;
            AttemptGeneration = attemptGeneration;
            Slot = slot;
            SaveBindingId = saveBindingId;
            SaveSignature = saveSignature?.ToLowerInvariant();
            SaveRevision = saveRevision;
            LoreViewId = loreViewId;
            TargetId = targetId;
            SurfaceEpoch = surfaceEpoch;
            PanelInstanceId = panelInstanceId;
            DocumentGeneration = documentGeneration;
            SemanticSnapshotId = semanticSnapshotId;
            SemanticGeneration = semanticGeneration;
            NodeId = nodeId;
            CoordinateSpaceVersion = coordinateSpaceVersion;
            FocusEpoch = focusEpoch;
            ModalEpoch = modalEpoch;
            ObservationGrantId = observationGrantId;
            ObservationId = observationId;
            FrameId = frameId;
            HairBinding = hairBinding;
        }

        public string SessionId { get; }
        public ulong LifecycleGeneration { get; }
        public string AttemptId { get; }
        public ulong? AttemptGeneration { get; }
        public string Slot { get; }
        public string SaveBindingId { get; }
        public string SaveSignature { get; }
        public long? SaveRevision { get; }
        public string LoreViewId { get; }
        public string TargetId { get; }
        public ulong SurfaceEpoch { get; }
        public string PanelInstanceId { get; }
        public ulong? DocumentGeneration { get; }
        public string SemanticSnapshotId { get; }
        public ulong? SemanticGeneration { get; }
        public string NodeId { get; }
        public ulong CoordinateSpaceVersion { get; }
        public ulong FocusEpoch { get; }
        public ulong ModalEpoch { get; }
        public string ObservationGrantId { get; }
        public string ObservationId { get; }
        public string FrameId { get; }
        public WingsHairActionBinding HairBinding { get; }

        private static void ValidateOptionalOpaqueId(
            string value,
            string parameterName)
        {
            if (value != null)
            {
                WingsProtocolValue.RequireOpaqueId(
                    value,
                    parameterName);
            }
        }

        private static void ValidateOptionalSha256(
            string value,
            string parameterName)
        {
            if (value != null)
            {
                WingsProtocolValue.RequireSha256(
                    value,
                    parameterName);
            }
        }
    }

    internal sealed class WingsActionTemplate
    {
        internal WingsActionTemplate(
            string templateKey,
            string operation,
            string reason,
            WingsActionLeaseKind leaseKind,
            int maximumLifetimeMs)
        {
            WingsProtocolValue.RequireStableKey(
                templateKey,
                nameof(templateKey));
            WingsProtocolValue.RequireStableKey(
                operation,
                nameof(operation));
            WingsProtocolValue.RequireText(
                reason,
                AgentProtocolV1.MaximumReasonCharacters,
                nameof(reason));
            if (!AllowedOperations.Contains(operation))
            {
                throw new ArgumentException(
                    "The operation is outside the phase-one Wings action set.",
                    nameof(operation));
            }
            if (maximumLifetimeMs <= 0
                || maximumLifetimeMs > 60_000)
            {
                throw new ArgumentOutOfRangeException(
                    nameof(maximumLifetimeMs));
            }
            bool domainOperation =
                operation == AgentMethodsV1.HairCommit
                || operation == AgentMethodsV1.HairRestore;
            if (domainOperation
                != (leaseKind
                    == WingsActionLeaseKind.DomainTransaction))
            {
                throw new ArgumentException(
                    "The operation and lease kind do not agree.",
                    nameof(leaseKind));
            }

            TemplateKey = templateKey;
            Operation = operation;
            Reason = reason;
            LeaseKind = leaseKind;
            MaximumLifetimeMs = maximumLifetimeMs;
        }

        public string TemplateKey { get; }
        public string Operation { get; }
        public string Reason { get; }
        public WingsActionLeaseKind LeaseKind { get; }
        public int MaximumLifetimeMs { get; }

        private static readonly IReadOnlySet<string>
            AllowedOperations = new HashSet<string>(
                new[]
                {
                    AgentCapabilitiesV1.Click,
                    AgentCapabilitiesV1.PressKey,
                    AgentCapabilitiesV1.TypeText,
                    AgentCapabilitiesV1.Scroll,
                    AgentCapabilitiesV1.Drag,
                    AgentCapabilitiesV1.ActivateWindow,
                    AgentMethodsV1.HairCommit,
                    AgentMethodsV1.HairRestore
                },
                StringComparer.Ordinal);
    }

    internal sealed class WingsActionTemplateCatalog
    {
        private readonly IReadOnlyDictionary<
            string,
            WingsActionTemplate> _templates;

        internal WingsActionTemplateCatalog(
            IEnumerable<WingsActionTemplate> templates)
        {
            WingsActionTemplate[] frozen =
                (templates ?? Array.Empty<WingsActionTemplate>())
                    .ToArray();
            if (frozen.Length == 0
                || frozen.Any(template => template == null))
            {
                throw new ArgumentException(
                    "At least one trusted action template is required.",
                    nameof(templates));
            }
            _templates = new ReadOnlyDictionary<
                string,
                WingsActionTemplate>(
                    frozen.ToDictionary(
                        template => template.TemplateKey,
                        StringComparer.Ordinal));
        }

        public bool TryResolve(
            string templateKey,
            out WingsActionTemplate template)
        {
            return _templates.TryGetValue(
                templateKey ?? string.Empty,
                out template);
        }
    }

    /// <summary>
    /// Immutable action intent. All IDs and argument hashes are minted by the
    /// Launcher-owned factory; there are no setters and no Persona/free-text
    /// constructor.
    /// </summary>
    internal sealed class WingsActionIntentV1
    {
        private WingsActionIntentV1(
            string intentId,
            string actionId,
            string idempotencyKey,
            WingsActionTemplate template,
            WingsActionHostBindingSnapshot binding,
            JsonElement canonicalArguments,
            string argumentBoundsHash,
            string bindingHash,
            long issuedMonotonic,
            long expiresMonotonic)
        {
            IntentId = intentId;
            ActionId = actionId;
            IdempotencyKey = idempotencyKey;
            TemplateKey = template.TemplateKey;
            Operation = template.Operation;
            Reason = template.Reason;
            LeaseKind = template.LeaseKind;
            SessionId = binding.SessionId;
            LifecycleGeneration = binding.LifecycleGeneration;
            AttemptId = binding.AttemptId;
            AttemptGeneration = binding.AttemptGeneration;
            Slot = binding.Slot;
            SaveBindingId = binding.SaveBindingId;
            SaveSignature = binding.SaveSignature;
            SaveRevision = binding.SaveRevision;
            LoreViewId = binding.LoreViewId;
            TargetId = binding.TargetId;
            SurfaceEpoch = binding.SurfaceEpoch;
            PanelInstanceId = binding.PanelInstanceId;
            DocumentGeneration = binding.DocumentGeneration;
            SemanticSnapshotId = binding.SemanticSnapshotId;
            SemanticGeneration = binding.SemanticGeneration;
            NodeId = binding.NodeId;
            CoordinateSpaceVersion =
                binding.CoordinateSpaceVersion;
            FocusEpoch = binding.FocusEpoch;
            ModalEpoch = binding.ModalEpoch;
            ObservationGrantId =
                binding.ObservationGrantId;
            ObservationId = binding.ObservationId;
            FrameId = binding.FrameId;
            CanonicalArguments = canonicalArguments.Clone();
            ArgumentBoundsHash = argumentBoundsHash;
            BindingHash = bindingHash;
            IssuedMonotonic = issuedMonotonic;
            ExpiresMonotonic = expiresMonotonic;
            HairBinding = binding.HairBinding;
        }

        public string IntentId { get; }
        public string ActionId { get; }
        public string IdempotencyKey { get; }
        public string TemplateKey { get; }
        public string SessionId { get; }
        public ulong LifecycleGeneration { get; }
        public string AttemptId { get; }
        public ulong? AttemptGeneration { get; }
        public string Slot { get; }
        public string SaveBindingId { get; }
        public string SaveSignature { get; }
        public long? SaveRevision { get; }
        public string LoreViewId { get; }
        public string TargetId { get; }
        public ulong SurfaceEpoch { get; }
        public string PanelInstanceId { get; }
        public ulong? DocumentGeneration { get; }
        public string SemanticSnapshotId { get; }
        public ulong? SemanticGeneration { get; }
        public string NodeId { get; }
        public ulong CoordinateSpaceVersion { get; }
        public ulong FocusEpoch { get; }
        public ulong ModalEpoch { get; }
        public string ObservationGrantId { get; }
        public string ObservationId { get; }
        public string FrameId { get; }
        public string Operation { get; }
        public JsonElement CanonicalArguments { get; }
        public string ArgumentBoundsHash { get; }
        public string Reason { get; }
        public long IssuedMonotonic { get; }
        public long ExpiresMonotonic { get; }
        public WingsActionLeaseKind LeaseKind { get; }
        public WingsHairActionBinding HairBinding { get; }
        public string BindingHash { get; }

        /// <summary>
        /// The sole constructor authority for WingsActionIntentV1. Callers
        /// can select only a Host-registered template and provide structured
        /// arguments alongside a Launcher-owned binding snapshot.
        /// </summary>
        internal sealed class HostFactory
        {
            private readonly IAgentRuntimeClock _clock;
            private readonly WingsActionTemplateCatalog _templates;

            internal HostFactory(
                IAgentRuntimeClock clock,
                WingsActionTemplateCatalog templates)
            {
                _clock = clock
                    ?? throw new ArgumentNullException(nameof(clock));
                _templates = templates
                    ?? throw new ArgumentNullException(
                        nameof(templates));
            }

            /// <summary>
            /// This entry accepts only a registered Host action key plus a
            /// Launcher-owned binding snapshot. Dialogue and generated text are
            /// deliberately absent from the API.
            /// </summary>
            public bool TryIssue(
                string registeredTemplateKey,
                WingsActionHostBindingSnapshot binding,
                JsonElement structuredArguments,
                out WingsActionIntentV1 intent,
                out string reasonCode)
            {
                intent = null;
                if (!_templates.TryResolve(
                        registeredTemplateKey,
                        out WingsActionTemplate template))
                {
                    reasonCode = "wings_action_template_unregistered";
                    return false;
                }
                if (binding == null)
                {
                    reasonCode = "wings_action_binding_required";
                    return false;
                }
                if (structuredArguments.ValueKind
                    != JsonValueKind.Object)
                {
                    reasonCode = "arguments_invalid";
                    return false;
                }

                bool hairOperation =
                    template.Operation == AgentMethodsV1.HairCommit
                    || template.Operation == AgentMethodsV1.HairRestore;
                if (hairOperation != (binding.HairBinding != null))
                {
                    reasonCode = "wings_hair_binding_mismatch";
                    return false;
                }

                long issued = _clock.MonotonicMilliseconds;
                if (issued < 0)
                {
                    reasonCode = "wings_action_time_invalid";
                    return false;
                }
                long expires;
                try
                {
                    expires = checked(
                        issued + template.MaximumLifetimeMs);
                }
                catch (OverflowException)
                {
                    reasonCode = "wings_action_time_invalid";
                    return false;
                }

                string canonicalArguments;
                JsonElement frozenArguments;
                try
                {
                    canonicalArguments = CanonicalJsonV1.Canonicalize(
                        structuredArguments.GetRawText());
                    using JsonDocument document =
                        JsonDocument.Parse(canonicalArguments);
                    frozenArguments =
                        document.RootElement.Clone();
                }
                catch (Exception exception)
                    when (exception is JsonException
                        || exception is InvalidDataException)
                {
                    reasonCode = "arguments_invalid";
                    return false;
                }

                string intentId =
                    OpaqueIdGenerator.Create("wint");
                string actionId =
                    OpaqueIdGenerator.Create("wact");
                string idempotencyKey =
                    OpaqueIdGenerator.Create("widm");
                string argumentBoundsHash =
                    CanonicalJsonV1
                        .ComputeArgumentBoundsSha256(
                            template.Operation,
                            frozenArguments)
                        .ToLowerInvariant();
                var provisional = CreateActionEnvelope(
                    actionId,
                    idempotencyKey,
                    template,
                    binding,
                    frozenArguments,
                    OpaqueIdGenerator.Create("lease"));
                JsonElement parameters =
                    JsonSerializer.SerializeToElement(
                        provisional,
                        AgentProtocolV1.JsonOptions);
                if (AgentMethodParameterValidatorV1.Validate(
                        template.Operation,
                        parameters).Count != 0)
                {
                    reasonCode = "arguments_invalid";
                    return false;
                }
                if (binding.HairBinding != null
                    && (!frozenArguments.TryGetProperty(
                            "transactionId",
                            out JsonElement transactionId)
                        || transactionId.ValueKind
                            != JsonValueKind.String
                        || !string.Equals(
                            transactionId.GetString(),
                            binding.HairBinding.TransactionId,
                            StringComparison.Ordinal)
                        || (template.Operation
                                == AgentMethodsV1.HairCommit
                            && (!frozenArguments.TryGetProperty(
                                    "previewHash",
                                    out JsonElement previewHash)
                                || previewHash.ValueKind
                                    != JsonValueKind.String
                                || !string.Equals(
                                    previewHash.GetString(),
                                    binding.HairBinding.PreviewHash,
                                    StringComparison
                                        .OrdinalIgnoreCase)))))
                {
                    reasonCode =
                        "wings_hair_binding_mismatch";
                    return false;
                }

                string bindingHash = ComputeBindingHash(
                    intentId,
                    actionId,
                    idempotencyKey,
                    template,
                    binding,
                    frozenArguments,
                    argumentBoundsHash,
                    issued,
                    expires);
                intent = new WingsActionIntentV1(
                    intentId,
                    actionId,
                    idempotencyKey,
                    template,
                    binding,
                    frozenArguments,
                    argumentBoundsHash,
                    bindingHash,
                    issued,
                    expires);
                reasonCode = null;
                return true;
            }

            internal static ActionEnvelope ToActionEnvelope(
                WingsActionIntentV1 intent,
                string leaseId,
                int deadlineMs)
            {
                if (intent == null)
                    throw new ArgumentNullException(nameof(intent));
                WingsProtocolValue.RequireOpaqueId(
                    leaseId,
                    nameof(leaseId));
                if (deadlineMs <= 0
                    || deadlineMs
                        > AgentProtocolV1.MaximumActionDeadlineMs)
                {
                    throw new ArgumentOutOfRangeException(
                        nameof(deadlineMs));
                }
                return new ActionEnvelope
                {
                    ActionId = intent.ActionId,
                    IdempotencyKey = intent.IdempotencyKey,
                    DeadlineMs = deadlineMs,
                    SessionId = intent.SessionId,
                    ObservationGrantId =
                        intent.ObservationGrantId,
                    LeaseId = leaseId,
                    ObservationId = intent.ObservationId,
                    ExpectedLifecycleGeneration =
                        intent.LifecycleGeneration,
                    TargetId = intent.TargetId,
                    ExpectedSurfaceEpoch =
                        intent.SurfaceEpoch,
                    ExpectedAttemptId = intent.AttemptId,
                    ExpectedAttemptGeneration =
                        intent.AttemptGeneration,
                    ExpectedPanelInstanceId =
                        intent.PanelInstanceId,
                    ExpectedSemanticGeneration =
                        intent.SemanticGeneration,
                    ExpectedDocumentGeneration =
                        intent.DocumentGeneration,
                    ExpectedCoordinateSpaceVersion =
                        intent.CoordinateSpaceVersion,
                    ExpectedFocusEpoch = intent.FocusEpoch,
                    ExpectedModalEpoch = intent.ModalEpoch,
                    FrameId = intent.FrameId,
                    SemanticSnapshotId =
                        intent.SemanticSnapshotId,
                    NodeId = intent.NodeId,
                    Operation = intent.Operation,
                    Arguments =
                        intent.CanonicalArguments.Clone(),
                    Reason = intent.Reason
                };
            }

            private static ActionEnvelope CreateActionEnvelope(
                string actionId,
                string idempotencyKey,
                WingsActionTemplate template,
                WingsActionHostBindingSnapshot binding,
                JsonElement arguments,
                string leaseId)
            {
                return new ActionEnvelope
                {
                    ActionId = actionId,
                    IdempotencyKey = idempotencyKey,
                    DeadlineMs = Math.Min(
                        template.MaximumLifetimeMs,
                        AgentProtocolV1
                            .MaximumActionDeadlineMs),
                    SessionId = binding.SessionId,
                    ObservationGrantId =
                        binding.ObservationGrantId,
                    LeaseId = leaseId,
                    ObservationId = binding.ObservationId,
                    ExpectedLifecycleGeneration =
                        binding.LifecycleGeneration,
                    TargetId = binding.TargetId,
                    ExpectedSurfaceEpoch =
                        binding.SurfaceEpoch,
                    ExpectedAttemptId = binding.AttemptId,
                    ExpectedAttemptGeneration =
                        binding.AttemptGeneration,
                    ExpectedPanelInstanceId =
                        binding.PanelInstanceId,
                    ExpectedSemanticGeneration =
                        binding.SemanticGeneration,
                    ExpectedDocumentGeneration =
                        binding.DocumentGeneration,
                    ExpectedCoordinateSpaceVersion =
                        binding.CoordinateSpaceVersion,
                    ExpectedFocusEpoch = binding.FocusEpoch,
                    ExpectedModalEpoch = binding.ModalEpoch,
                    FrameId = binding.FrameId,
                    SemanticSnapshotId =
                        binding.SemanticSnapshotId,
                    NodeId = binding.NodeId,
                    Operation = template.Operation,
                    Arguments = arguments.Clone(),
                    Reason = template.Reason
                };
            }

            private static string ComputeBindingHash(
                string intentId,
                string actionId,
                string idempotencyKey,
                WingsActionTemplate template,
                WingsActionHostBindingSnapshot binding,
                JsonElement arguments,
                string argumentBoundsHash,
                long issued,
                long expires)
            {
                string json = JsonSerializer.Serialize(
                    new
                    {
                        intentId,
                        actionId,
                        idempotencyKey,
                        templateKey = template.TemplateKey,
                        sessionId = binding.SessionId,
                        lifecycleGeneration =
                            binding.LifecycleGeneration,
                        attemptId = binding.AttemptId,
                        attemptGeneration =
                            binding.AttemptGeneration,
                        binding.Slot,
                        saveBindingId =
                            binding.SaveBindingId,
                        saveSignature =
                            binding.SaveSignature,
                        saveRevision =
                            binding.SaveRevision,
                        loreViewId = binding.LoreViewId,
                        targetId = binding.TargetId,
                        surfaceEpoch = binding.SurfaceEpoch,
                        panelInstanceId =
                            binding.PanelInstanceId,
                        documentGeneration =
                            binding.DocumentGeneration,
                        semanticSnapshotId =
                            binding.SemanticSnapshotId,
                        semanticGeneration =
                            binding.SemanticGeneration,
                        nodeId = binding.NodeId,
                        coordinateSpaceVersion =
                            binding.CoordinateSpaceVersion,
                        focusEpoch = binding.FocusEpoch,
                        modalEpoch = binding.ModalEpoch,
                        observationGrantId =
                            binding.ObservationGrantId,
                        observationId =
                            binding.ObservationId,
                        frameId = binding.FrameId,
                        operation = template.Operation,
                        arguments,
                        argumentBoundsHash,
                        template.Reason,
                        issuedMonotonic = issued,
                        expiresMonotonic = expires,
                        hairBinding =
                            binding.HairBinding == null
                                ? null
                                : new
                                {
                                    transactionId =
                                        binding.HairBinding
                                            .TransactionId,
                                    previewHash =
                                        binding.HairBinding
                                            .PreviewHash,
                                    expectedRevision =
                                        binding.HairBinding
                                            .ExpectedRevision,
                                    expectedGeneration =
                                        binding.HairBinding
                                            .ExpectedGeneration,
                                    snapshotHash =
                                        binding.HairBinding
                                            .SnapshotHash,
                                    before =
                                        binding.HairBinding.Before,
                                    after =
                                        binding.HairBinding.After
                                }
                    },
                    AgentProtocolV1.JsonOptions);
                return Hash(CanonicalJsonV1.Canonicalize(json));
            }

            private static string Hash(string canonicalJson)
            {
                return Convert.ToHexString(
                        SHA256.HashData(
                            Encoding.UTF8.GetBytes(
                                canonicalJson)))
                    .ToLowerInvariant();
            }
        }
    }
}
