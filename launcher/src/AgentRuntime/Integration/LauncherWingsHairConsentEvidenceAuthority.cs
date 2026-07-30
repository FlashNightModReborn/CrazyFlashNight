using System;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using System.Threading;
using System.Threading.Tasks;
using CF7Launcher.AgentRuntime.Contracts;
using CF7Launcher.AgentRuntime.Domain;
using CF7Launcher.AgentRuntime.Gateway;
using CF7Launcher.AgentRuntime.Security;
using CF7Launcher.AgentRuntime.Wings;

namespace CF7Launcher.AgentRuntime.Integration
{
    /// <summary>
    /// Process-local proof that the shared Hair consent method returned from
    /// its real Launcher-owned human-only flow. It deliberately adds nothing
    /// to the public wire descriptor: the public consent token remains the
    /// domain capability, while this HMAC-authenticated object is the only
    /// bridge allowed to authorize a Wings immutable action intent.
    /// </summary>
    internal sealed class LauncherWingsHairConsentEvidenceAuthority
    {
        private readonly IAgentRuntimeClock _clock;
        private readonly string _sessionId;
        private readonly string _targetId;
        private readonly byte[] _key =
            RandomNumberGenerator.GetBytes(32);

        internal LauncherWingsHairConsentEvidenceAuthority(
            IAgentRuntimeClock clock,
            string sessionId,
            string targetId)
        {
            _clock = clock
                ?? throw new ArgumentNullException(nameof(clock));
            WingsProtocolValue.RequireOpaqueId(
                sessionId,
                nameof(sessionId));
            WingsProtocolValue.RequireOpaqueId(
                targetId,
                nameof(targetId));
            _sessionId = sessionId;
            _targetId = targetId;
        }

        internal async Task<
            LauncherWingsHairConsentDispatchEvidence>
            DispatchAndCaptureAsync(
            WingsVirtualAuthenticatedConnection connection,
            HairAppearancePreview preview,
            string observationGrantId,
            LauncherTrustedHumanInteractionTicket interaction,
            CancellationToken cancellationToken)
        {
            if (connection == null
                || preview == null
                || !HairAppearanceValidation
                    .PreviewHashIsAuthentic(preview)
                || interaction == null
                || interaction.Phase
                    != LauncherTrustedHumanInteractionPhase
                        .HairCommitConsent
                || !string.Equals(
                    preview.Binding.SessionId,
                    _sessionId,
                    StringComparison.Ordinal))
            {
                return LauncherWingsHairConsentDispatchEvidence
                    .Rejected("consent_mismatch");
            }
            try
            {
                WingsProtocolValue.RequireOpaqueId(
                    observationGrantId,
                    nameof(observationGrantId));
            }
            catch (ArgumentException)
            {
                return LauncherWingsHairConsentDispatchEvidence
                    .Rejected("observation_grant_invalid");
            }

            AgentRuntimeDispatchResult dispatchResult;
            using (LauncherTrustedHumanInteractionContext.Enter(
                interaction))
            {
                dispatchResult = await connection.DispatchAsync(
                        AgentMethodsV1.HairConsent,
                        JsonSerializer.SerializeToElement(
                            new HairConsentParametersV1
                            {
                                ObservationGrantId =
                                    observationGrantId,
                                TargetId = _targetId,
                                SessionId = _sessionId,
                                LifecycleGeneration =
                                    checked((ulong)preview
                                        .Binding
                                        .LifecycleGeneration),
                                TransactionId =
                                    preview.TransactionId,
                                PreviewHash =
                                    preview.PreviewHash
                            },
                            AgentProtocolV1.JsonOptions),
                        cancellationToken)
                    .ConfigureAwait(false);
            }
            if (!TryCaptureSuccessfulDispatch(
                    connection,
                    preview,
                    dispatchResult,
                    out LauncherWingsHairConsentEvidence evidence,
                    out HairConsentDescriptorV1 descriptor,
                    out string reasonCode))
            {
                return LauncherWingsHairConsentDispatchEvidence
                    .Rejected(reasonCode);
            }
            return LauncherWingsHairConsentDispatchEvidence
                .Completed(evidence, descriptor);
        }

        private bool TryCaptureSuccessfulDispatch(
            WingsVirtualAuthenticatedConnection connection,
            HairAppearancePreview preview,
            AgentRuntimeDispatchResult dispatchResult,
            out LauncherWingsHairConsentEvidence evidence,
            out HairConsentDescriptorV1 descriptor,
            out string reasonCode)
        {
            evidence = null;
            descriptor = null;
            if (connection == null
                || preview == null
                || dispatchResult == null
                || !dispatchResult.Success
                || !HairAppearanceValidation
                    .PreviewHashIsAuthentic(preview))
            {
                reasonCode = dispatchResult?.ReasonCode
                    ?? "consent_required";
                return false;
            }

            try
            {
                descriptor =
                    dispatchResult.Result
                        .Deserialize<HairConsentDescriptorV1>(
                            AgentProtocolV1.JsonOptions);
            }
            catch (JsonException)
            {
                descriptor = null;
            }
            if (!TryValidateDescriptor(
                    preview,
                    descriptor,
                    out reasonCode))
            {
                descriptor = null;
                return false;
            }

            PrincipalCredential principal = connection.Principal;
            if (principal == null
                || principal.State != CredentialState.Active
                || principal.PrincipalKind
                    != AgentPrincipalKind.WingsPersona
                || principal.SessionMode
                    != AgentSessionMode.PlayerAssist
                || !string.Equals(
                    principal.SelectedSessionId,
                    preview.Binding.SessionId,
                    StringComparison.Ordinal))
            {
                descriptor = null;
                reasonCode = "principal_mismatch";
                return false;
            }

            string tokenHash =
                HairAppearanceHashing.HashOpaqueToken(
                    descriptor.ConsentToken);
            string reauthorizationReceiptId =
                OpaqueIdGenerator.Create("hairreauth");
            long issued = _clock.MonotonicMilliseconds;
            long expires;
            try
            {
                expires = checked(
                    issued + descriptor.ExpiresInMs);
            }
            catch (OverflowException)
            {
                descriptor = null;
                reasonCode = "consent_expired";
                return false;
            }
            byte[] tag = Sign(
                connection.ConnectionId,
                principal,
                preview,
                descriptor.ConsentReceipt,
                reauthorizationReceiptId,
                tokenHash,
                issued,
                expires);
            evidence =
                new LauncherWingsHairConsentEvidence(
                    connection,
                    principal,
                    preview,
                    descriptor.ConsentReceipt,
                    reauthorizationReceiptId,
                    tokenHash,
                    issued,
                    expires,
                    tag);
            reasonCode = null;
            return true;
        }

        internal bool TryConsume(
            LauncherWingsHairConsentEvidence evidence,
            WingsVirtualAuthenticatedConnection connection,
            PrincipalCredential principal,
            HairAppearancePreview preview,
            HairConsentDescriptorV1 descriptor,
            out string humanInteractionReceiptId,
            out string reauthorizationReceiptId,
            out string reasonCode)
        {
            humanInteractionReceiptId = null;
            reauthorizationReceiptId = null;
            reasonCode = null;
            if (evidence == null
                || principal == null
                || preview == null
                || descriptor == null
                || connection == null
                || principal.State != CredentialState.Active
                || !ReferenceEquals(
                    connection,
                    evidence.Connection)
                || !ReferenceEquals(
                    principal,
                    evidence.Principal)
                || !ReferenceEquals(
                    preview,
                    evidence.Preview)
                || !TryValidateDescriptor(
                    preview,
                    descriptor,
                    out reasonCode)
                || !string.Equals(
                    evidence.TokenHash,
                    HairAppearanceHashing.HashOpaqueToken(
                        descriptor.ConsentToken),
                    StringComparison.Ordinal)
                || !string.Equals(
                    evidence.HumanInteractionReceiptId,
                    descriptor.ConsentReceipt,
                    StringComparison.Ordinal)
                || _clock.MonotonicMilliseconds
                    < evidence.IssuedMonotonic
                || _clock.MonotonicMilliseconds
                    >= evidence.ExpiresMonotonic)
            {
                reasonCode ??= "consent_expired";
                return false;
            }

            byte[] expected = Sign(
                connection.ConnectionId,
                principal,
                preview,
                evidence.HumanInteractionReceiptId,
                evidence.ReauthorizationReceiptId,
                evidence.TokenHash,
                evidence.IssuedMonotonic,
                evidence.ExpiresMonotonic);
            if (!CryptographicOperations.FixedTimeEquals(
                    expected,
                    evidence.AuthenticationTag)
                || !evidence.TryConsume())
            {
                reasonCode = "consent_replayed";
                return false;
            }

            humanInteractionReceiptId =
                evidence.HumanInteractionReceiptId;
            reauthorizationReceiptId =
                evidence.ReauthorizationReceiptId;
            reasonCode = null;
            return true;
        }

        private static bool TryValidateDescriptor(
            HairAppearancePreview preview,
            HairConsentDescriptorV1 descriptor,
            out string reasonCode)
        {
            try
            {
                if (descriptor == null
                    || !string.Equals(
                        descriptor.TransactionId,
                        preview.TransactionId,
                        StringComparison.Ordinal)
                    || !string.Equals(
                        descriptor.PreviewHash,
                        preview.PreviewHash,
                        StringComparison.OrdinalIgnoreCase)
                    || !HairAppearanceValidation.IsSafeString(
                        descriptor.ConsentToken,
                        256,
                        false)
                    || descriptor.ExpiresInMs <= 0
                    || descriptor.ExpiresInMs
                        > checked((int)
                            HairAppearanceConsentBroker
                                .MaximumConsentTtl
                                .TotalMilliseconds))
                {
                    reasonCode = "consent_mismatch";
                    return false;
                }
                WingsProtocolValue.RequireOpaqueId(
                    descriptor.ConsentReceipt,
                    nameof(descriptor.ConsentReceipt));
                reasonCode = null;
                return true;
            }
            catch (ArgumentException)
            {
                reasonCode = "consent_mismatch";
                return false;
            }
        }

        private byte[] Sign(
            string connectionId,
            PrincipalCredential principal,
            HairAppearancePreview preview,
            string humanInteractionReceiptId,
            string reauthorizationReceiptId,
            string tokenHash,
            long issuedMonotonic,
            long expiresMonotonic)
        {
            string canonical = CanonicalJsonV1.Canonicalize(
                JsonSerializer.Serialize(
                    new
                    {
                        connectionId,
                        principal.SecurityPrincipalId,
                        principal.ClientInstanceId,
                        principal.CredentialId,
                        principal.Generation,
                        principal.IssuerReceipt,
                        preview.Binding.SessionId,
                        preview.Binding.LifecycleGeneration,
                        preview.Binding.AttemptId,
                        preview.Binding.AttemptGeneration,
                        preview.Binding.SlotId,
                        preview.Binding.SaveSignature,
                        preview.TransactionId,
                        preview.PreviewHash,
                        humanInteractionReceiptId,
                        reauthorizationReceiptId,
                        tokenHash,
                        issuedMonotonic,
                        expiresMonotonic
                    },
                    AgentProtocolV1.JsonOptions));
            using var hmac = new HMACSHA256(_key);
            return hmac.ComputeHash(
                Encoding.UTF8.GetBytes(canonical));
        }
    }

    internal sealed class
        LauncherWingsHairConsentDispatchEvidence
    {
        private LauncherWingsHairConsentDispatchEvidence(
            LauncherWingsHairConsentEvidence evidence,
            HairConsentDescriptorV1 descriptor,
            string reasonCode)
        {
            Evidence = evidence;
            Descriptor = descriptor;
            ReasonCode = reasonCode;
        }

        internal bool Success =>
            Evidence != null && Descriptor != null;
        internal LauncherWingsHairConsentEvidence
            Evidence { get; }
        internal HairConsentDescriptorV1 Descriptor { get; }
        internal string ReasonCode { get; }

        internal static LauncherWingsHairConsentDispatchEvidence
            Completed(
                LauncherWingsHairConsentEvidence evidence,
                HairConsentDescriptorV1 descriptor)
        {
            return new LauncherWingsHairConsentDispatchEvidence(
                evidence
                    ?? throw new ArgumentNullException(
                        nameof(evidence)),
                descriptor
                    ?? throw new ArgumentNullException(
                        nameof(descriptor)),
                null);
        }

        internal static LauncherWingsHairConsentDispatchEvidence
            Rejected(string reasonCode)
        {
            return new LauncherWingsHairConsentDispatchEvidence(
                null,
                null,
                string.IsNullOrWhiteSpace(reasonCode)
                    ? "consent_required"
                    : reasonCode);
        }
    }

    internal sealed class LauncherWingsHairConsentEvidence
    {
        private readonly byte[] _authenticationTag;
        private int _consumed;

        internal LauncherWingsHairConsentEvidence(
            WingsVirtualAuthenticatedConnection connection,
            PrincipalCredential principal,
            HairAppearancePreview preview,
            string humanInteractionReceiptId,
            string reauthorizationReceiptId,
            string tokenHash,
            long issuedMonotonic,
            long expiresMonotonic,
            byte[] authenticationTag)
        {
            Connection = connection
                ?? throw new ArgumentNullException(
                    nameof(connection));
            Principal = principal
                ?? throw new ArgumentNullException(nameof(principal));
            Preview = preview
                ?? throw new ArgumentNullException(nameof(preview));
            HumanInteractionReceiptId =
                humanInteractionReceiptId;
            ReauthorizationReceiptId =
                reauthorizationReceiptId;
            TokenHash = tokenHash;
            IssuedMonotonic = issuedMonotonic;
            ExpiresMonotonic = expiresMonotonic;
            _authenticationTag =
                authenticationTag == null
                    ? null
                    : (byte[])authenticationTag.Clone()
                ?? throw new ArgumentNullException(
                    nameof(authenticationTag));
        }

        internal WingsVirtualAuthenticatedConnection
            Connection { get; }
        internal PrincipalCredential Principal { get; }
        internal HairAppearancePreview Preview { get; }
        internal string HumanInteractionReceiptId { get; }
        internal string ReauthorizationReceiptId { get; }
        internal string TokenHash { get; }
        internal long IssuedMonotonic { get; }
        internal long ExpiresMonotonic { get; }
        internal ReadOnlySpan<byte> AuthenticationTag =>
            _authenticationTag;

        internal bool TryConsume()
        {
            return Interlocked.CompareExchange(
                    ref _consumed,
                    1,
                    0)
                == 0;
        }
    }
}
