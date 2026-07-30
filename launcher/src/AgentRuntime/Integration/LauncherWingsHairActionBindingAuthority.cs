using System;
using System.Collections.Generic;
using System.Globalization;
using System.Linq;
using System.Text.Json;
using CF7Launcher.AgentRuntime.Contracts;
using CF7Launcher.AgentRuntime.Domain;
using CF7Launcher.AgentRuntime.Security;
using CF7Launcher.AgentRuntime.Sessions;
using CF7Launcher.AgentRuntime.Wings;

namespace CF7Launcher.AgentRuntime.Integration
{
    /// <summary>
    /// Process-local authority for the two immutable Hair intents belonging to
    /// one Wings product flow. It never accepts a caller-built binding and it
    /// retains action secrets only inside the already session-only immutable
    /// intent; its own comparison record stores only a SHA-256 token hash.
    /// </summary>
    internal sealed class LauncherWingsHairActionBindingAuthority
        : IWingsActionBindingAuthority
    {
        internal const string CommitTemplateKey =
            "wings.action.hair.commit.v1";
        internal const string RestoreTemplateKey =
            "wings.action.hair.restore.v1";

        private readonly object _sync = new object();
        private readonly IAgentRuntimeClock _clock;
        private readonly SessionSurfaceHostController _surfaces;
        private readonly PrincipalCredentialAuthority _credentials;
        private readonly ObservationGrantBroker _grants;
        private readonly string _sessionId;
        private readonly string _targetId;
        private readonly string _expectedPanelName;
        private readonly LoreView _loreView;
        private readonly HashSet<string> _exactCapabilities;
        private readonly Dictionary<string, BindingRecord> _records =
            new Dictionary<string, BindingRecord>(
                StringComparer.Ordinal);

        internal LauncherWingsHairActionBindingAuthority(
            IAgentRuntimeClock clock,
            SessionSurfaceHostController surfaces,
            PrincipalCredentialAuthority credentials,
            ObservationGrantBroker grants,
            string sessionId,
            string targetId,
            string expectedPanelName,
            LoreView loreView,
            IEnumerable<string> exactCapabilities)
        {
            _clock = clock
                ?? throw new ArgumentNullException(nameof(clock));
            _surfaces = surfaces
                ?? throw new ArgumentNullException(nameof(surfaces));
            _credentials = credentials
                ?? throw new ArgumentNullException(
                    nameof(credentials));
            _grants = grants
                ?? throw new ArgumentNullException(nameof(grants));
            WingsProtocolValue.RequireOpaqueId(
                sessionId,
                nameof(sessionId));
            WingsProtocolValue.RequireOpaqueId(
                targetId,
                nameof(targetId));
            WingsProtocolValue.RequireText(
                expectedPanelName,
                160,
                nameof(expectedPanelName));
            _loreView = loreView
                ?? throw new ArgumentNullException(nameof(loreView));
            _sessionId = sessionId;
            _targetId = targetId;
            _expectedPanelName = expectedPanelName;
            _exactCapabilities = new HashSet<string>(
                exactCapabilities ?? Array.Empty<string>(),
                StringComparer.Ordinal);
        }

        internal bool TryRegister(
            PrincipalCredential principal,
            WingsActionIntentV1 intent,
            ObservationEnvelope observation,
            FrameEnvelope frame,
            HairAppearancePreview preview,
            string actionSecret,
            out string reasonCode)
        {
            BindingRecord record;
            try
            {
                record = new BindingRecord(
                    principal,
                    intent,
                    observation,
                    frame,
                    preview,
                    HairAppearanceHashing.HashOpaqueToken(
                        actionSecret));
            }
            catch
            {
                reasonCode =
                    "wings_action_binding_unavailable";
                return false;
            }

            lock (_sync)
            {
                if (_records.ContainsKey(intent.IntentId))
                {
                    reasonCode = "lease_busy";
                    return false;
                }
                _records.Add(intent.IntentId, record);
            }
            if (!TryValidate(principal, intent, out reasonCode))
            {
                Remove(intent);
                return false;
            }
            reasonCode = null;
            return true;
        }

        internal bool TryMarkTerminal(
            PrincipalCredential principal,
            WingsActionIntentV1 intent,
            WingsBrokeredActionReceipt evidence,
            WingsActionReceiptTrustDomain trustDomain,
            out string reasonCode)
        {
            reasonCode = null;
            BindingRecord record = Resolve(intent);
            if (record == null
                || trustDomain == null
                || evidence == null
                || !ReferenceEquals(record.Principal, principal)
                || !ReferenceEquals(record.Intent, intent)
                || !trustDomain.Verify(evidence)
                || !WingsTerminalActionReceiptValidator.TryValidate(
                    intent,
                    evidence.ReceiptSnapshot(),
                    out reasonCode))
            {
                reasonCode ??=
                    "wings_terminal_receipt_required";
                return false;
            }
            lock (_sync)
            {
                if (!_records.TryGetValue(
                        intent.IntentId,
                        out BindingRecord current)
                    || !ReferenceEquals(current, record))
                {
                    reasonCode =
                        "wings_action_binding_unavailable";
                    return false;
                }
                current.Terminal = true;
            }
            reasonCode = null;
            return true;
        }

        public bool TryValidate(
            PrincipalCredential principal,
            WingsActionIntentV1 intent,
            out string reasonCode)
        {
            BindingRecord record = Resolve(intent);
            if (record == null
                || principal == null
                || intent == null
                || !ReferenceEquals(record.Principal, principal)
                || !ReferenceEquals(record.Intent, intent))
            {
                reasonCode =
                    "wings_action_binding_unavailable";
                return false;
            }
            if (!TryValidatePrincipal(principal, out reasonCode)
                || !IntentMatches(record))
            {
                reasonCode ??=
                    "wings_action_binding_unavailable";
                return false;
            }
            if (!GrantMatches(principal, intent, out reasonCode))
                return false;

            SessionSnapshot session =
                _surfaces.Registry.GetSnapshot()
                    .FindSession(_sessionId);
            SessionSurfaceSnapshot surface = FindTarget(session);
            if (!StableSessionAndTargetMatch(
                    session,
                    surface,
                    intent,
                    out reasonCode))
            {
                return false;
            }
            if (!record.Terminal
                && (session.SaveRevision != intent.SaveRevision
                    || surface.SurfaceEpoch != intent.SurfaceEpoch
                    || surface.CoordinateSpaceVersion
                        != intent.CoordinateSpaceVersion
                    || surface.DocumentGeneration
                        != intent.DocumentGeneration
                    || surface.SemanticGeneration
                        != intent.SemanticGeneration
                    || session.FocusEpoch != intent.FocusEpoch
                    || session.ModalEpoch != intent.ModalEpoch
                    || (intent.Operation
                            == AgentMethodsV1.HairCommit
                        && (!string.Equals(
                            session.PanelInstanceIdForTarget(
                                _targetId),
                            intent.PanelInstanceId,
                            StringComparison.Ordinal)
                        || !ActiveHairPanelMatches(
                            session,
                            intent,
                            out _)))
                    ))
            {
                reasonCode = "stale_observation";
                return false;
            }
            reasonCode = null;
            return true;
        }

        internal bool TryValidateStableExecutionIdentity(
            PrincipalCredential principal,
            WingsActionIntentV1 intent,
            out string reasonCode)
        {
            reasonCode = null;
            BindingRecord record = Resolve(intent);
            if (record == null
                || !ReferenceEquals(record.Principal, principal)
                || !ReferenceEquals(record.Intent, intent)
                || !TryValidatePrincipal(principal, out reasonCode)
                || !IntentMatches(record))
            {
                reasonCode ??=
                    "wings_action_binding_unavailable";
                return false;
            }
            SessionSnapshot session =
                _surfaces.Registry.GetSnapshot()
                    .FindSession(_sessionId);
            if (!StableSessionAndTargetMatch(
                    session,
                    FindTarget(session),
                    intent,
                    out reasonCode))
            {
                return false;
            }
            if (!record.Terminal
                && intent.Operation
                    == AgentMethodsV1.HairCommit
                && !ActiveHairPanelMatches(
                    session,
                    intent,
                    out reasonCode))
            {
                return false;
            }
            reasonCode = null;
            return true;
        }

        internal void Remove(WingsActionIntentV1 intent)
        {
            if (intent == null)
                return;
            lock (_sync)
                _records.Remove(intent.IntentId);
        }

        internal void Clear()
        {
            lock (_sync)
                _records.Clear();
        }

        private bool TryValidatePrincipal(
            PrincipalCredential principal,
            out string reasonCode)
        {
            reasonCode = null;
            if (principal == null
                || !_credentials.TryResolveActive(
                    principal.CredentialId,
                    principal.ClientInstanceId,
                    out PrincipalCredential active,
                    out reasonCode)
                || !ReferenceEquals(active, principal)
                || principal.PrincipalKind
                    != AgentPrincipalKind.WingsPersona
                || principal.SessionMode
                    != AgentSessionMode.PlayerAssist
                || !string.Equals(
                    principal.SelectedSessionId,
                    _sessionId,
                    StringComparison.Ordinal)
                || !principal.AllowedCapabilities
                    .ToHashSet(StringComparer.Ordinal)
                    .SetEquals(_exactCapabilities)
                || principal.AllowedTargets.Count != 1
                || !string.Equals(
                    principal.AllowedTargets[0],
                    _targetId,
                    StringComparison.Ordinal)
                || _clock.MonotonicMilliseconds
                    >= principal.ExpiresMonotonic)
            {
                reasonCode ??= "principal_mismatch";
                return false;
            }
            reasonCode = null;
            return true;
        }

        private bool GrantMatches(
            PrincipalCredential principal,
            WingsActionIntentV1 intent,
            out string reasonCode)
        {
            if (!_grants.TryAuthorize(
                    intent.ObservationGrantId,
                    principal.ClientInstanceId,
                    principal.SecurityPrincipalId,
                    _sessionId,
                    _targetId,
                    ObservationDataScopesV1.PlayerState,
                    out ObservationGrant playerStateGrant,
                    out reasonCode)
                || !_grants.TryAuthorize(
                    intent.ObservationGrantId,
                    principal.ClientInstanceId,
                    principal.SecurityPrincipalId,
                    _sessionId,
                    _targetId,
                    ObservationDataScopesV1.Pixels,
                    out ObservationGrant pixelGrant,
                    out reasonCode)
                || !ReferenceEquals(playerStateGrant, pixelGrant)
                || playerStateGrant.TargetScope.Count != 1
                || playerStateGrant.DataScope
                    .ToHashSet(StringComparer.Ordinal)
                    .SetEquals(
                        new[]
                        {
                            ObservationDataScopesV1.PlayerState,
                            ObservationDataScopesV1.Pixels
                        })
                    == false
                || !PrincipalCredentialAuthority
                    .IsExactIssuerReceipt(
                        principal,
                        playerStateGrant.ConsentReceipt)
                || !playerStateGrant.AllowEphemeralKeyframes
                || playerStateGrant.AllowPersistence
                || playerStateGrant.AllowExport)
            {
                reasonCode ??=
                    "observation_grant_revoked";
                return false;
            }
            reasonCode = null;
            return true;
        }

        private bool StableSessionAndTargetMatch(
            SessionSnapshot session,
            SessionSurfaceSnapshot surface,
            WingsActionIntentV1 intent,
            out string reasonCode)
        {
            if (session == null
                || surface == null
                || session.LifecycleGeneration
                    != intent.LifecycleGeneration
                || !string.Equals(
                    session.AttemptId,
                    intent.AttemptId,
                    StringComparison.Ordinal)
                || session.AttemptGeneration
                    != intent.AttemptGeneration
                || !string.Equals(
                    session.Slot,
                    intent.Slot,
                    StringComparison.Ordinal)
                || session.RuntimeQualification == null
                || session.RuntimeQualification.RuntimeMode
                    == RuntimeMode.UnqualifiedDev
                || !session.Capabilities.Contains(
                    AgentCapabilitiesV1.AppearanceHairChange,
                    StringComparer.Ordinal)
                || !session.DesktopAvailable
                || session.HumanReauthorizationRequired
                || session.BlockingModalKind
                    != BlockingModalKind.None
                || surface.Kind != SurfaceKind.WebOverlay
                || surface.SafetyKind
                    != AgentTargetSafetyKind.RuntimeOwned
                || !surface.Visible
                || surface.Minimized
                || !surface.ObservationModes.Contains(
                    ObservationMode.WindowGraphicsCapture)
                || !surface.InputModes.Contains(
                    InputMode.DomainTransaction)
                || !string.Equals(
                    intent.SaveBindingId,
                    _loreView.Progress.SaveBindingId,
                    StringComparison.Ordinal)
                || !string.Equals(
                    intent.SaveSignature,
                    _loreView.Progress.SaveSignature,
                    StringComparison.OrdinalIgnoreCase)
                || !string.Equals(
                    intent.LoreViewId,
                    _loreView.LoreViewId,
                    StringComparison.Ordinal)
                || !string.Equals(
                    intent.TargetId,
                    _targetId,
                    StringComparison.Ordinal))
            {
                reasonCode = "stale_observation";
                return false;
            }
            reasonCode = null;
            return true;
        }

        private bool ActiveHairPanelMatches(
            SessionSnapshot session,
            WingsActionIntentV1 intent,
            out string reasonCode)
        {
            if (session == null
                || intent?.HairBinding == null
                || !string.Equals(
                    intent.HairBinding.PanelName,
                    _expectedPanelName,
                    StringComparison.Ordinal)
                || !string.Equals(
                    session.ActivePanelName,
                    _expectedPanelName,
                    StringComparison.Ordinal)
                || !string.Equals(
                    session.ActivePanelTargetId,
                    _targetId,
                    StringComparison.Ordinal)
                || !string.Equals(
                    session.ActivePanelInstanceId,
                    intent.PanelInstanceId,
                    StringComparison.Ordinal))
            {
                reasonCode = "stale_panel_instance";
                return false;
            }
            reasonCode = null;
            return true;
        }

        private bool IntentMatches(BindingRecord record)
        {
            WingsActionIntentV1 intent = record.Intent;
            HairAppearancePreview preview = record.Preview;
            WingsHairActionBinding hair = intent.HairBinding;
            ObservationEnvelope observation = record.Observation;
            FrameEnvelope frame = record.Frame;
            string expectedTemplate =
                intent.Operation == AgentMethodsV1.HairCommit
                    ? CommitTemplateKey
                    : RestoreTemplateKey;
            if ((intent.Operation != AgentMethodsV1.HairCommit
                    && intent.Operation
                        != AgentMethodsV1.HairRestore)
                || !string.Equals(
                    intent.TemplateKey,
                    expectedTemplate,
                    StringComparison.Ordinal)
                || intent.LeaseKind
                    != WingsActionLeaseKind.DomainTransaction
                || hair == null
                || !HairAppearanceValidation
                    .PreviewHashIsAuthentic(preview)
                || !string.Equals(
                    hair.TransactionId,
                    preview.TransactionId,
                    StringComparison.Ordinal)
                || !string.Equals(
                    hair.PreviewHash,
                    preview.PreviewHash,
                    StringComparison.OrdinalIgnoreCase)
                || !string.Equals(
                    hair.ExpectedRevision,
                    preview.ExpectedRevision.ToString(
                        CultureInfo.InvariantCulture),
                    StringComparison.Ordinal)
                || hair.ExpectedGeneration
                    != checked((ulong)preview.ExpectedGeneration)
                || !string.Equals(
                    hair.SnapshotHash,
                    preview.ExpectedSnapshotHash,
                    StringComparison.OrdinalIgnoreCase)
                || !string.Equals(
                    hair.Before,
                    preview.BeforeHair,
                    StringComparison.Ordinal)
                || !string.Equals(
                    hair.After,
                    preview.AfterHair,
                    StringComparison.Ordinal)
                || !string.Equals(
                    hair.PanelName,
                    _expectedPanelName,
                    StringComparison.Ordinal)
                || intent.IssuedMonotonic
                    < record.Principal.IssuedMonotonic
                || intent.ExpiresMonotonic
                    > record.Principal.ExpiresMonotonic
                || !BindingMatchesPreview(intent, preview)
                || !ObservationMatches(
                    intent,
                    observation,
                    frame)
                || !ArgumentsMatch(record))
            {
                return false;
            }
            return true;
        }

        private bool BindingMatchesPreview(
            WingsActionIntentV1 intent,
            HairAppearancePreview preview)
        {
            HairSaveBinding binding = preview.Binding;
            return string.Equals(
                    intent.SessionId,
                    binding.SessionId,
                    StringComparison.Ordinal)
                && intent.LifecycleGeneration
                    == checked((ulong)binding.LifecycleGeneration)
                && string.Equals(
                    intent.AttemptId,
                    binding.AttemptId,
                    StringComparison.Ordinal)
                && intent.AttemptGeneration
                    == checked((ulong)binding.AttemptGeneration)
                && string.Equals(
                    intent.Slot,
                    binding.SlotId,
                    StringComparison.Ordinal)
                && string.Equals(
                    intent.SaveSignature,
                    binding.SaveSignature,
                    StringComparison.OrdinalIgnoreCase)
                && string.Equals(
                    intent.SaveBindingId,
                    _loreView.Progress.SaveBindingId,
                    StringComparison.Ordinal)
                && string.Equals(
                    intent.LoreViewId,
                    _loreView.LoreViewId,
                    StringComparison.Ordinal)
                && string.Equals(
                    intent.TargetId,
                    _targetId,
                    StringComparison.Ordinal);
        }

        private static bool ObservationMatches(
            WingsActionIntentV1 intent,
            ObservationEnvelope observation,
            FrameEnvelope frame)
        {
            return observation != null
                && frame != null
                && string.Equals(
                    intent.ObservationGrantId,
                    observation.ObservationGrantId,
                    StringComparison.Ordinal)
                && string.Equals(
                    intent.ObservationId,
                    observation.ObservationId,
                    StringComparison.Ordinal)
                && intent.LifecycleGeneration
                    == observation.LifecycleGeneration
                && string.Equals(
                    intent.AttemptId,
                    observation.AttemptId,
                    StringComparison.Ordinal)
                && intent.AttemptGeneration
                    == observation.AttemptGeneration
                && intent.SurfaceEpoch
                    == observation.SurfaceEpoch
                && intent.CoordinateSpaceVersion
                    == observation.CoordinateSpaceVersion
                && intent.FocusEpoch == observation.FocusEpoch
                && intent.ModalEpoch == observation.ModalEpoch
                && string.Equals(
                    intent.PanelInstanceId,
                    observation.PanelInstanceId,
                    StringComparison.Ordinal)
                && intent.DocumentGeneration
                    == observation.DocumentGeneration
                && string.Equals(
                    intent.SemanticSnapshotId,
                    observation.SemanticSnapshotId,
                    StringComparison.Ordinal)
                && intent.SemanticGeneration
                    == observation.SemanticGeneration
                && intent.NodeId == null
                && string.Equals(
                    intent.FrameId,
                    frame.FrameId,
                    StringComparison.Ordinal)
                && string.Equals(
                    frame.ObservationId,
                    observation.ObservationId,
                    StringComparison.Ordinal)
                && string.Equals(
                    frame.TargetId,
                    intent.TargetId,
                    StringComparison.Ordinal)
                && frame.SurfaceEpoch
                    == observation.SurfaceEpoch
                && frame.CoordinateSpaceVersion
                    == observation.CoordinateSpaceVersion
                && HairAppearanceValidation.IsSha256(
                    frame.ContentHash?.ToLowerInvariant())
                && !string.IsNullOrWhiteSpace(
                    frame.OpaqueContentHandle);
        }

        private static bool ArgumentsMatch(BindingRecord record)
        {
            JsonElement arguments =
                record.Intent.CanonicalArguments;
            if (arguments.ValueKind != JsonValueKind.Object)
                return false;
            JsonProperty[] properties =
                arguments.EnumerateObject().ToArray();
            if (!TryString(
                    arguments,
                    "transactionId",
                    out string transactionId)
                || !string.Equals(
                    transactionId,
                    record.Preview.TransactionId,
                    StringComparison.Ordinal))
            {
                return false;
            }
            if (record.Intent.Operation
                == AgentMethodsV1.HairCommit)
            {
                return properties.Length == 3
                    && TryString(
                        arguments,
                        "previewHash",
                        out string previewHash)
                    && string.Equals(
                        previewHash,
                        record.Preview.PreviewHash,
                        StringComparison.OrdinalIgnoreCase)
                    && TryString(
                        arguments,
                        "consentToken",
                        out string secret)
                    && string.Equals(
                        HairAppearanceHashing
                            .HashOpaqueToken(secret),
                        record.ActionSecretHash,
                        StringComparison.Ordinal);
            }
            return properties.Length == 2
                && TryString(
                    arguments,
                    "restoreToken",
                    out string restoreToken)
                && string.Equals(
                    HairAppearanceHashing
                        .HashOpaqueToken(restoreToken),
                    record.ActionSecretHash,
                    StringComparison.Ordinal);
        }

        private static bool TryString(
            JsonElement value,
            string propertyName,
            out string result)
        {
            result = null;
            return value.TryGetProperty(
                    propertyName,
                    out JsonElement property)
                && property.ValueKind == JsonValueKind.String
                && (result = property.GetString()) != null;
        }

        private SessionSurfaceSnapshot FindTarget(
            SessionSnapshot session)
        {
            return session?.Surfaces.FirstOrDefault(
                surface => string.Equals(
                    surface.TargetId,
                    _targetId,
                    StringComparison.Ordinal));
        }

        private BindingRecord Resolve(
            WingsActionIntentV1 intent)
        {
            if (intent == null)
                return null;
            lock (_sync)
            {
                _records.TryGetValue(
                    intent.IntentId,
                    out BindingRecord record);
                return record;
            }
        }

        private sealed class BindingRecord
        {
            internal BindingRecord(
                PrincipalCredential principal,
                WingsActionIntentV1 intent,
                ObservationEnvelope observation,
                FrameEnvelope frame,
                HairAppearancePreview preview,
                string actionSecretHash)
            {
                Principal = principal
                    ?? throw new ArgumentNullException(
                        nameof(principal));
                Intent = intent
                    ?? throw new ArgumentNullException(
                        nameof(intent));
                Observation = Clone(observation);
                Frame = Clone(frame);
                Preview = preview
                    ?? throw new ArgumentNullException(
                        nameof(preview));
                if (!HairAppearanceValidation.IsSha256(
                        actionSecretHash))
                {
                    throw new ArgumentException(
                        "A token hash is required.",
                        nameof(actionSecretHash));
                }
                ActionSecretHash = actionSecretHash;
            }

            internal PrincipalCredential Principal { get; }
            internal WingsActionIntentV1 Intent { get; }
            internal ObservationEnvelope Observation { get; }
            internal FrameEnvelope Frame { get; }
            internal HairAppearancePreview Preview { get; }
            internal string ActionSecretHash { get; }
            internal bool Terminal { get; set; }

            private static T Clone<T>(T value)
                where T : class
            {
                if (value == null)
                    throw new ArgumentNullException(nameof(value));
                return JsonSerializer.Deserialize<T>(
                        JsonSerializer.SerializeToUtf8Bytes(
                            value,
                            AgentProtocolV1.JsonOptions),
                        AgentProtocolV1.JsonOptions)
                    ?? throw new InvalidOperationException(
                        "wings_hair_binding_clone_failed");
            }
        }
    }
}
