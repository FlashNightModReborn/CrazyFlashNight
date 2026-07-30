using System;
using System.Collections.Generic;
using System.Collections.ObjectModel;
using System.Linq;
using System.Security.Cryptography;
using System.Text;
using CF7Launcher.AgentRuntime.Contracts;
using CF7Launcher.AgentRuntime.Security;
using CF7Launcher.AgentRuntime.Transport;

namespace CF7Launcher.AgentRuntime.Gateway
{
    /// <summary>
    /// Host-owned binding gate for unattended evidence and live principals.
    /// Implementations derive authority from the current Launcher session,
    /// never from a client request body.
    /// </summary>
    internal interface IUnattendedCredentialBindingAuthority
    {
        bool TryAuthorizeEvidence(
            UnattendedCredentialEvidence evidence,
            AgentProcessSecurityIdentity peerIdentity,
            out string reasonCode);

        void BindPrincipal(
            PrincipalCredential principal,
            UnattendedCredentialEvidence evidence);

        bool IsPrincipalAuthorized(
            PrincipalCredential principal);
    }

    /// <summary>
    /// Uniform connection-authentication result. Credential proofs are never
    /// retained in this object or included in its reason.
    /// </summary>
    internal sealed class AgentConnectionAuthenticationResult
    {
        private AgentConnectionAuthenticationResult(
            PrincipalCredential principal,
            IEnumerable<string> grantedCapabilities,
            string reasonCode)
        {
            Principal = principal;
            GrantedCapabilities = Array.AsReadOnly(
                (grantedCapabilities
                    ?? Array.Empty<string>())
                .Distinct(StringComparer.Ordinal)
                .OrderBy(
                    value => value,
                    StringComparer.Ordinal)
                .ToArray());
            ReasonCode = reasonCode;
        }

        public bool Success
        {
            get { return Principal != null; }
        }

        public PrincipalCredential Principal { get; }
        public ReadOnlyCollection<string>
            GrantedCapabilities { get; }
        public string ReasonCode { get; }

        internal static AgentConnectionAuthenticationResult
            Authenticated(
                PrincipalCredential principal,
                IEnumerable<string> grantedCapabilities)
        {
            return new AgentConnectionAuthenticationResult(
                principal
                    ?? throw new ArgumentNullException(
                        nameof(principal)),
                grantedCapabilities,
                null);
        }

        internal static AgentConnectionAuthenticationResult
            Rejected(string reasonCode)
        {
            if (string.IsNullOrWhiteSpace(reasonCode))
            {
                reasonCode = "authentication_failed";
            }
            return new AgentConnectionAuthenticationResult(
                null,
                Array.Empty<string>(),
                reasonCode);
        }
    }

    /// <summary>
    /// Host-owned production authentication boundary.
    ///
    /// JSONL CLI and MCP stdio can only authenticate through the persistent
    /// neutral-UI developer enrollment store. TestHarness and WingsInternal
    /// can only consume a one-shot proof registered by trusted host code for
    /// exact unattended/player evidence. Hello can narrow capabilities but
    /// never supplies or expands targets.
    /// </summary>
    internal sealed class AgentConnectionAuthenticator : IDisposable
    {
        private static readonly byte[] DummyProofHash =
            SHA256.HashData(
                Encoding.UTF8.GetBytes(
                    "cf7-agent-runtime-missing-host-proof"));
        private static readonly HashSet<string>
            InternalSecurityCapabilities =
                new HashSet<string>(
                    ObservationDataScopesV1.All
                        .Select(scope => "observe:" + scope)
                        .Concat(
                            new[]
                            {
                                "observation.persist",
                                "observation.export"
                            }),
                    StringComparer.Ordinal);

        private readonly object _sync = new object();
        private readonly PersistentDeveloperEnrollmentStore _developers;
        private readonly HostPrincipalEnrollmentVerifier _hostVerifier;
        private readonly PrincipalCredentialAuthority _credentials;
        private readonly IUnattendedCredentialBindingAuthority
            _unattendedBindings;
        private readonly Dictionary<string, PendingUnattendedProof>
            _unattended =
                new Dictionary<string, PendingUnattendedProof>(
                    StringComparer.Ordinal);
        private readonly Dictionary<string, PendingPlayerProof>
            _players =
                new Dictionary<string, PendingPlayerProof>(
                    StringComparer.Ordinal);
        private bool _disposed;

        public AgentConnectionAuthenticator(
            PersistentDeveloperEnrollmentStore developers,
            HostPrincipalEnrollmentVerifier hostVerifier,
            PrincipalCredentialAuthority credentials,
            IUnattendedCredentialBindingAuthority
                unattendedBindings)
        {
            _developers = developers
                ?? throw new ArgumentNullException(
                    nameof(developers));
            _hostVerifier = hostVerifier
                ?? throw new ArgumentNullException(
                    nameof(hostVerifier));
            _credentials = credentials
                ?? throw new ArgumentNullException(
                    nameof(credentials));
            _unattendedBindings = unattendedBindings
                ?? throw new ArgumentNullException(
                    nameof(unattendedBindings));
        }

        /// <summary>
        /// Registers one exact immutable runner decision. The plaintext proof
        /// is immediately reduced to a SHA-256 verifier and is never exposed
        /// by this component.
        /// </summary>
        public void RegisterUnattendedProof(
            string credentialProof,
            UnattendedCredentialEvidence exactEvidence,
            string issuerReceipt)
        {
            if (exactEvidence == null)
            {
                throw new ArgumentNullException(
                    nameof(exactEvidence));
            }
            RequireValue(
                credentialProof,
                nameof(credentialProof));
            RequireValue(
                issuerReceipt,
                nameof(issuerReceipt));
            PendingUnattendedProof pending =
                PendingUnattendedProof.Create(
                    credentialProof,
                    exactEvidence,
                    issuerReceipt);
            try
            {
                lock (_sync)
                {
                    ThrowIfDisposed();
                    _unattended.Add(
                        pending.Evidence.ClientInstanceId,
                        pending);
                }
            }
            catch
            {
                pending.Dispose();
                throw;
            }
        }

        public bool RemoveUnattendedProof(
            string clientInstanceId)
        {
            PendingUnattendedProof removed = null;
            lock (_sync)
            {
                if (_disposed
                    || string.IsNullOrWhiteSpace(
                        clientInstanceId)
                    || !_unattended.Remove(
                        clientInstanceId,
                        out removed))
                {
                    return false;
                }
            }
            removed.Dispose();
            return true;
        }

        /// <summary>
        /// Registers one exact host-issued player consent decision. The
        /// consent receipt remains evidence; the separate connection proof is
        /// hashed immediately and consumed only by WingsInternal.
        /// </summary>
        public void RegisterPlayerProof(
            string credentialProof,
            PlayerAssistCredentialEvidence exactEvidence)
        {
            if (exactEvidence == null)
            {
                throw new ArgumentNullException(
                    nameof(exactEvidence));
            }
            RequireValue(
                credentialProof,
                nameof(credentialProof));
            PendingPlayerProof pending =
                PendingPlayerProof.Create(
                    credentialProof,
                    exactEvidence);
            try
            {
                lock (_sync)
                {
                    ThrowIfDisposed();
                    _players.Add(
                        pending.Evidence.ClientInstanceId,
                        pending);
                }
            }
            catch
            {
                pending.Dispose();
                throw;
            }
        }

        public AgentConnectionAuthenticationResult Authenticate(
            HelloMessage hello)
        {
            return Authenticate(hello, null);
        }

        public AgentConnectionAuthenticationResult Authenticate(
            HelloMessage hello,
            AgentProcessSecurityIdentity peerIdentity)
        {
            if (hello == null)
            {
                FixedTimeDummyComparison(null);
                return AgentConnectionAuthenticationResult
                    .Rejected("authentication_failed");
            }
            lock (_sync)
            {
                if (_disposed)
                {
                    FixedTimeDummyComparison(
                        hello.CredentialProof);
                    return AgentConnectionAuthenticationResult
                        .Rejected("authentication_failed");
                }
            }

            switch (hello.ClientKind)
            {
                case ClientKind.JsonlCli:
                case ClientKind.McpStdio:
                    return AuthenticateDeveloper(hello);
                case ClientKind.TestHarness:
                    return AuthenticateUnattended(
                        hello,
                        peerIdentity);
                case ClientKind.WingsInternal:
                    return AuthenticatePlayer(hello);
                default:
                    FixedTimeDummyComparison(
                        hello.CredentialProof);
                    return AgentConnectionAuthenticationResult
                        .Rejected("authentication_failed");
            }
        }

        private AgentConnectionAuthenticationResult
            AuthenticateDeveloper(HelloMessage hello)
        {
            try
            {
                if (!TryValidateWireCapabilities(
                        hello.RequestedCapabilities,
                        out string[] requestedMethods))
                {
                    FixedTimeDummyComparison(
                        hello.CredentialProof);
                    return AgentConnectionAuthenticationResult
                        .Rejected("capability_denied");
                }
                if (!_developers.TryAuthenticate(
                        hello.ClientInstanceId,
                        hello.CredentialProof,
                        requestedMethods,
                        out DeveloperEnrollmentEvidence evidence,
                        out string reasonCode))
                {
                    return AgentConnectionAuthenticationResult
                        .Rejected(
                            NormalizeAuthenticationReason(
                                reasonCode));
                }
                if (!TryPreserveDeveloperSecurityScope(
                        hello,
                        evidence,
                        out DeveloperEnrollmentEvidence
                            selectedEvidence))
                {
                    return AgentConnectionAuthenticationResult
                        .Rejected("authentication_failed");
                }
                PrincipalCredential principal =
                    _credentials.IssueDeveloper(
                        selectedEvidence);
                return AgentConnectionAuthenticationResult
                    .Authenticated(
                        principal,
                        requestedMethods);
            }
            catch (Exception exception) when (
                exception is ArgumentException
                || exception is InvalidOperationException
                || exception is OverflowException)
            {
                return AgentConnectionAuthenticationResult
                    .Rejected("authentication_failed");
            }
        }

        private AgentConnectionAuthenticationResult
            AuthenticateUnattended(
                HelloMessage hello,
                AgentProcessSecurityIdentity peerIdentity)
        {
            if (!TryConsumeUnattended(
                    hello,
                    out PendingUnattendedProof pending,
                    out string[] selectedCapabilities,
                    out string reasonCode))
            {
                return AgentConnectionAuthenticationResult
                    .Rejected(reasonCode);
            }

            UnattendedCredentialEvidence selected =
                pending.Select(selectedCapabilities);
            bool registered = false;
            PrincipalCredential principal = null;
            try
            {
                if (!_unattendedBindings.TryAuthorizeEvidence(
                        selected,
                        peerIdentity,
                        out _))
                {
                    return AgentConnectionAuthenticationResult
                        .Rejected("authentication_failed");
                }
                _hostVerifier.RegisterUnattended(
                    selected,
                    pending.IssuerReceipt);
                registered = true;
                principal =
                    _credentials.IssueUnattended(selected);
                _unattendedBindings.BindPrincipal(
                    principal,
                    selected);
                return AgentConnectionAuthenticationResult
                    .Authenticated(
                        principal,
                        selectedCapabilities);
            }
            catch (Exception exception) when (
                exception is ArgumentException
                || exception is InvalidOperationException
                || exception is OverflowException)
            {
                if (registered)
                {
                    _hostVerifier.TryVerifyUnattended(
                        selected,
                        out _,
                        out _);
                }
                if (principal != null)
                {
                    _credentials.Revoke(
                        principal.CredentialId,
                        "unattended_binding_failed");
                }
                return AgentConnectionAuthenticationResult
                    .Rejected("authentication_failed");
            }
            finally
            {
                pending.Dispose();
            }
        }

        private AgentConnectionAuthenticationResult
            AuthenticatePlayer(HelloMessage hello)
        {
            if (!TryConsumePlayer(
                    hello,
                    out PendingPlayerProof pending,
                    out string[] selectedCapabilities,
                    out string reasonCode))
            {
                return AgentConnectionAuthenticationResult
                    .Rejected(reasonCode);
            }

            PlayerAssistCredentialEvidence selected =
                pending.Select(selectedCapabilities);
            bool registered = false;
            try
            {
                _hostVerifier.RegisterPlayerConsent(selected);
                registered = true;
                PrincipalCredential principal =
                    _credentials.IssuePlayerAssist(selected);
                return AgentConnectionAuthenticationResult
                    .Authenticated(
                        principal,
                        selectedCapabilities);
            }
            catch (Exception exception) when (
                exception is ArgumentException
                || exception is InvalidOperationException
                || exception is OverflowException)
            {
                if (registered)
                {
                    _hostVerifier.TryVerifyPlayerAssist(
                        selected,
                        out _,
                        out _);
                }
                return AgentConnectionAuthenticationResult
                    .Rejected("authentication_failed");
            }
            finally
            {
                pending.Dispose();
            }
        }

        private bool TryConsumeUnattended(
            HelloMessage hello,
            out PendingUnattendedProof pending,
            out string[] selectedCapabilities,
            out string reasonCode)
        {
            pending = null;
            selectedCapabilities = null;
            byte[] presented = HashProof(
                hello.CredentialProof);
            try
            {
                lock (_sync)
                {
                    PendingUnattendedProof candidate = null;
                    bool found = !_disposed
                        && !string.IsNullOrWhiteSpace(
                            hello.ClientInstanceId)
                        && _unattended.TryGetValue(
                            hello.ClientInstanceId,
                            out candidate);
                    byte[] expected = found
                        ? candidate.ProofHash
                        : DummyProofHash;
                    bool proofMatches =
                        CryptographicOperations.FixedTimeEquals(
                            expected,
                            presented);
                    if (!found || !proofMatches)
                    {
                        reasonCode =
                            "authentication_failed";
                        return false;
                    }
                    _unattended.Remove(
                        hello.ClientInstanceId);
                    if (!TrySelectCapabilities(
                            candidate.AllowedCapabilities,
                            hello.RequestedCapabilities,
                            out selectedCapabilities))
                    {
                        candidate.Dispose();
                        reasonCode = "capability_denied";
                        return false;
                    }
                    pending = candidate;
                    reasonCode = null;
                    return true;
                }
            }
            finally
            {
                CryptographicOperations.ZeroMemory(presented);
            }
        }

        private bool TryConsumePlayer(
            HelloMessage hello,
            out PendingPlayerProof pending,
            out string[] selectedCapabilities,
            out string reasonCode)
        {
            pending = null;
            selectedCapabilities = null;
            byte[] presented = HashProof(
                hello.CredentialProof);
            try
            {
                lock (_sync)
                {
                    PendingPlayerProof candidate = null;
                    bool found = !_disposed
                        && !string.IsNullOrWhiteSpace(
                            hello.ClientInstanceId)
                        && _players.TryGetValue(
                            hello.ClientInstanceId,
                            out candidate);
                    byte[] expected = found
                        ? candidate.ProofHash
                        : DummyProofHash;
                    bool proofMatches =
                        CryptographicOperations.FixedTimeEquals(
                            expected,
                            presented);
                    if (!found || !proofMatches)
                    {
                        reasonCode =
                            "authentication_failed";
                        return false;
                    }
                    if (!TrySelectCapabilities(
                            candidate.AllowedCapabilities,
                            hello.RequestedCapabilities,
                            out selectedCapabilities))
                    {
                        reasonCode = "capability_denied";
                        return false;
                    }
                    _players.Remove(
                        hello.ClientInstanceId);
                    pending = candidate;
                    reasonCode = null;
                    return true;
                }
            }
            finally
            {
                CryptographicOperations.ZeroMemory(presented);
            }
        }

        private static bool TrySelectCapabilities(
            IReadOnlyCollection<string> allowed,
            IEnumerable<string> requested,
            out string[] selected)
        {
            if (!TryValidateWireCapabilities(
                    requested,
                    out selected)
                || !selected.All(
                    new HashSet<string>(
                        allowed ?? Array.Empty<string>(),
                        StringComparer.Ordinal)
                        .Contains))
            {
                selected = null;
                return false;
            }
            return true;
        }

        private bool TryPreserveDeveloperSecurityScope(
            HelloMessage hello,
            DeveloperEnrollmentEvidence methodEvidence,
            out DeveloperEnrollmentEvidence selectedEvidence)
        {
            selectedEvidence = null;
            var capabilities = new HashSet<string>(
                methodEvidence.AllowedCapabilities
                    ?? Array.Empty<string>(),
                StringComparer.Ordinal);
            TimeSpan lifetime =
                methodEvidence.RequestedLifetime;
            foreach (string securityCapability
                in InternalSecurityCapabilities
                    .OrderBy(
                        value => value,
                        StringComparer.Ordinal))
            {
                if (_developers.TryAuthenticate(
                        hello.ClientInstanceId,
                        hello.CredentialProof,
                        new[] { securityCapability },
                        out DeveloperEnrollmentEvidence
                            scopeEvidence,
                        out string reasonCode))
                {
                    if (!SameDeveloperEnrollment(
                            methodEvidence,
                            scopeEvidence))
                    {
                        return false;
                    }
                    capabilities.Add(
                        securityCapability);
                    if (scopeEvidence.RequestedLifetime
                        < lifetime)
                    {
                        lifetime =
                            scopeEvidence.RequestedLifetime;
                    }
                }
                else if (!string.Equals(
                    reasonCode,
                    "capability_denied",
                    StringComparison.Ordinal))
                {
                    return false;
                }
            }

            selectedEvidence =
                new DeveloperEnrollmentEvidence
                {
                    ClientInstanceId =
                        methodEvidence.ClientInstanceId,
                    EnrollmentReceipt =
                        methodEvidence.EnrollmentReceipt,
                    AllowedCapabilities =
                        capabilities
                            .OrderBy(
                                value => value,
                                StringComparer.Ordinal)
                            .ToArray(),
                    AllowedTargets =
                        methodEvidence.AllowedTargets
                            .ToArray(),
                    RequestedLifetime = lifetime
                };
            return true;
        }

        private static bool SameDeveloperEnrollment(
            DeveloperEnrollmentEvidence left,
            DeveloperEnrollmentEvidence right)
        {
            return right != null
                && string.Equals(
                    left.ClientInstanceId,
                    right.ClientInstanceId,
                    StringComparison.Ordinal)
                && string.Equals(
                    left.EnrollmentReceipt,
                    right.EnrollmentReceipt,
                    StringComparison.Ordinal)
                && new HashSet<string>(
                        left.AllowedTargets
                            ?? Array.Empty<string>(),
                        StringComparer.Ordinal)
                    .SetEquals(
                        right.AllowedTargets
                            ?? Array.Empty<string>());
        }

        private static bool TryValidateWireCapabilities(
            IEnumerable<string> requested,
            out string[] selected)
        {
            string[] raw = (requested
                    ?? Array.Empty<string>())
                .ToArray();
            selected = raw
                .Where(value =>
                    !string.IsNullOrWhiteSpace(value))
                .Distinct(StringComparer.Ordinal)
                .OrderBy(value => value, StringComparer.Ordinal)
                .ToArray();
            if (selected.Length == 0
                || selected.Length != raw.Length
                || selected.Any(capability =>
                    !AgentCapabilitiesV1.All.Contains(
                        capability)))
            {
                selected = null;
                return false;
            }
            return true;
        }

        private static string[] SelectPrincipalCapabilities(
            IEnumerable<string> requestedMethods,
            IEnumerable<string> hostCapabilities)
        {
            return (requestedMethods
                    ?? Array.Empty<string>())
                .Concat(
                    (hostCapabilities
                        ?? Array.Empty<string>())
                    .Where(
                        InternalSecurityCapabilities
                            .Contains))
                .Distinct(StringComparer.Ordinal)
                .OrderBy(
                    value => value,
                    StringComparer.Ordinal)
                .ToArray();
        }

        private static string NormalizeAuthenticationReason(
            string reasonCode)
        {
            return reasonCode switch
            {
                "capability_denied" =>
                    "capability_denied",
                "credential_revoked" =>
                    "credential_revoked",
                _ => "authentication_failed"
            };
        }

        private static void FixedTimeDummyComparison(
            string presentedProof)
        {
            byte[] presented = HashProof(presentedProof);
            try
            {
                _ = CryptographicOperations.FixedTimeEquals(
                    DummyProofHash,
                    presented);
            }
            finally
            {
                CryptographicOperations.ZeroMemory(presented);
            }
        }

        private static byte[] HashProof(string proof)
        {
            return SHA256.HashData(
                Encoding.UTF8.GetBytes(
                    proof ?? string.Empty));
        }

        private static string[] FreezeCapabilities(
            IEnumerable<string> values)
        {
            string[] capabilities = FreezeRequired(
                values,
                nameof(values));
            if (capabilities.Any(capability =>
                !AgentCapabilitiesV1.All.Contains(capability)
                && !InternalSecurityCapabilities.Contains(
                    capability)))
            {
                throw new ArgumentException(
                    "A host proof contains an unknown capability.",
                    nameof(values));
            }
            return capabilities;
        }

        private static string[] FreezeTargets(
            IEnumerable<string> values)
        {
            string[] targets = FreezeRequired(
                values,
                nameof(values));
            if (targets.Contains(
                "*",
                StringComparer.Ordinal))
            {
                throw new ArgumentException(
                    "Host connection proofs require exact targets.",
                    nameof(values));
            }
            return targets;
        }

        private static string[] FreezeRequired(
            IEnumerable<string> values,
            string parameterName)
        {
            string[] result = (values
                    ?? Array.Empty<string>())
                .Where(value =>
                    !string.IsNullOrWhiteSpace(value))
                .Distinct(StringComparer.Ordinal)
                .OrderBy(value => value, StringComparer.Ordinal)
                .ToArray();
            if (result.Length == 0)
            {
                throw new ArgumentException(
                    "At least one host-owned scope is required.",
                    parameterName);
            }
            return result;
        }

        private static void RequireValue(
            string value,
            string parameterName)
        {
            PrincipalCredentialAuthority.RequireValue(
                value,
                parameterName);
        }

        private void ThrowIfDisposed()
        {
            if (_disposed)
                throw new ObjectDisposedException(
                    GetType().Name);
        }

        public void Dispose()
        {
            lock (_sync)
            {
                if (_disposed)
                    return;
                _disposed = true;
                foreach (PendingUnattendedProof pending
                    in _unattended.Values)
                {
                    pending.Dispose();
                }
                foreach (PendingPlayerProof pending
                    in _players.Values)
                {
                    pending.Dispose();
                }
                _unattended.Clear();
                _players.Clear();
            }
        }

        private abstract class PendingProof : IDisposable
        {
            protected PendingProof(
                string credentialProof,
                IEnumerable<string> capabilities)
            {
                ProofHash = HashProof(credentialProof);
                AllowedCapabilities =
                    FreezeCapabilities(capabilities);
            }

            public byte[] ProofHash { get; }
            public string[] AllowedCapabilities { get; }

            public void Dispose()
            {
                CryptographicOperations.ZeroMemory(
                    ProofHash);
            }
        }

        private sealed class PendingUnattendedProof
            : PendingProof
        {
            private PendingUnattendedProof(
                string credentialProof,
                UnattendedCredentialEvidence evidence,
                string issuerReceipt)
                : base(
                    credentialProof,
                    evidence.AllowedCapabilities)
            {
                Evidence = evidence;
                IssuerReceipt = issuerReceipt;
            }

            public UnattendedCredentialEvidence Evidence
            {
                get;
            }
            public string IssuerReceipt { get; }

            public static PendingUnattendedProof Create(
                string credentialProof,
                UnattendedCredentialEvidence evidence,
                string issuerReceipt)
            {
                RequireValue(
                    evidence.ClientInstanceId,
                    nameof(evidence.ClientInstanceId));
                RequireValue(
                    evidence.RunnerPolicyId,
                    nameof(evidence.RunnerPolicyId));
                if (evidence.RunnerProcessId == 0
                    || evidence.RunnerProcessStartTimeUtc
                        == default)
                {
                    throw new ArgumentOutOfRangeException(
                        nameof(evidence.RunnerProcessId));
                }
                RequireValue(
                    evidence.RunnerExecutablePath,
                    nameof(evidence.RunnerExecutablePath));
                RequireValue(
                    evidence.RunnerExecutableSha256,
                    nameof(evidence.RunnerExecutableSha256));
                if (evidence.RunnerExecutableSize <= 0)
                {
                    throw new ArgumentOutOfRangeException(
                        nameof(evidence
                            .RunnerExecutableSize));
                }
                RequireValue(
                    evidence.RuntimeExecutablePath,
                    nameof(evidence.RuntimeExecutablePath));
                RequireValue(
                    evidence.RequestNonce,
                    nameof(evidence.RequestNonce));
                RequireValue(
                    evidence.BuildIdentity,
                    nameof(evidence.BuildIdentity));
                RequireValue(
                    evidence.PayloadClosure,
                    nameof(evidence.PayloadClosure));
                RequireValue(
                    evidence.SessionId,
                    nameof(evidence.SessionId));
                RequireValue(
                    evidence.AttemptId,
                    nameof(evidence.AttemptId));
                if (evidence.AttemptGeneration == 0)
                {
                    throw new ArgumentOutOfRangeException(
                        nameof(evidence.AttemptGeneration));
                }
                RequireValue(
                    evidence.Slot,
                    nameof(evidence.Slot));
                RequireValue(
                    evidence.CanonicalSavePath,
                    nameof(evidence.CanonicalSavePath));
                string[] targets = FreezeTargets(
                    evidence.AllowedTargets);
                string[] capabilities =
                    FreezeCapabilities(
                        evidence.AllowedCapabilities);
                var snapshot =
                    new UnattendedCredentialEvidence
                    {
                        ClientInstanceId =
                            evidence.ClientInstanceId,
                        RunnerPolicyId =
                            evidence.RunnerPolicyId,
                        RunnerProcessId =
                            evidence.RunnerProcessId,
                        RunnerProcessStartTimeUtc =
                            evidence
                                .RunnerProcessStartTimeUtc,
                        RunnerExecutablePath =
                            evidence.RunnerExecutablePath,
                        RunnerExecutableSha256 =
                            evidence.RunnerExecutableSha256,
                        RunnerExecutableSize =
                            evidence.RunnerExecutableSize,
                        RuntimeExecutablePath =
                            evidence.RuntimeExecutablePath,
                        RequestNonce =
                            evidence.RequestNonce,
                        BuildIdentity =
                            evidence.BuildIdentity,
                        PayloadClosure =
                            evidence.PayloadClosure,
                        SessionId = evidence.SessionId,
                        AttemptId = evidence.AttemptId,
                        AttemptGeneration =
                            evidence.AttemptGeneration,
                        Slot = evidence.Slot,
                        CanonicalSavePath =
                            evidence.CanonicalSavePath,
                        RunnerDeadlineMonotonic =
                            evidence
                                .RunnerDeadlineMonotonic,
                        AllowedCapabilities =
                            capabilities,
                        AllowedTargets = targets
                    };
                return new PendingUnattendedProof(
                    credentialProof,
                    snapshot,
                    issuerReceipt);
            }

            public UnattendedCredentialEvidence Select(
                IReadOnlyCollection<string> capabilities)
            {
                return new UnattendedCredentialEvidence
                {
                    ClientInstanceId =
                        Evidence.ClientInstanceId,
                    RunnerPolicyId =
                        Evidence.RunnerPolicyId,
                    RunnerProcessId =
                        Evidence.RunnerProcessId,
                    RunnerProcessStartTimeUtc =
                        Evidence.RunnerProcessStartTimeUtc,
                    RunnerExecutablePath =
                        Evidence.RunnerExecutablePath,
                    RunnerExecutableSha256 =
                        Evidence.RunnerExecutableSha256,
                    RunnerExecutableSize =
                        Evidence.RunnerExecutableSize,
                    RuntimeExecutablePath =
                        Evidence.RuntimeExecutablePath,
                    RequestNonce =
                        Evidence.RequestNonce,
                    BuildIdentity = Evidence.BuildIdentity,
                    PayloadClosure = Evidence.PayloadClosure,
                    SessionId = Evidence.SessionId,
                    AttemptId = Evidence.AttemptId,
                    AttemptGeneration =
                        Evidence.AttemptGeneration,
                    Slot = Evidence.Slot,
                    CanonicalSavePath =
                        Evidence.CanonicalSavePath,
                    RunnerDeadlineMonotonic =
                        Evidence.RunnerDeadlineMonotonic,
                    AllowedCapabilities =
                        SelectPrincipalCapabilities(
                            capabilities,
                            AllowedCapabilities),
                    AllowedTargets =
                        Evidence.AllowedTargets.ToArray()
                };
            }
        }

        private sealed class PendingPlayerProof
            : PendingProof
        {
            private PendingPlayerProof(
                string credentialProof,
                PlayerAssistCredentialEvidence evidence)
                : base(
                    credentialProof,
                    evidence.AllowedCapabilities)
            {
                Evidence = evidence;
            }

            public PlayerAssistCredentialEvidence Evidence
            {
                get;
            }

            public static PendingPlayerProof Create(
                string credentialProof,
                PlayerAssistCredentialEvidence evidence)
            {
                RequireValue(
                    evidence.ClientInstanceId,
                    nameof(evidence.ClientInstanceId));
                RequireValue(
                    evidence.ConsentReceipt,
                    nameof(evidence.ConsentReceipt));
                RequireValue(
                    evidence.SelectedSessionId,
                    nameof(evidence.SelectedSessionId));
                if (evidence.RequestedLifetime <= TimeSpan.Zero)
                {
                    throw new ArgumentOutOfRangeException(
                        nameof(evidence.RequestedLifetime));
                }
                string[] targets = FreezeTargets(
                    evidence.AllowedTargets);
                string[] capabilities =
                    FreezeCapabilities(
                        evidence.AllowedCapabilities);
                var snapshot =
                    new PlayerAssistCredentialEvidence
                    {
                        ClientInstanceId =
                            evidence.ClientInstanceId,
                        ConsentReceipt =
                            evidence.ConsentReceipt,
                        SelectedSessionId =
                            evidence.SelectedSessionId,
                        AllowedCapabilities =
                            capabilities,
                        AllowedTargets = targets,
                        RequestedLifetime =
                            evidence.RequestedLifetime
                    };
                return new PendingPlayerProof(
                    credentialProof,
                    snapshot);
            }

            public PlayerAssistCredentialEvidence Select(
                IReadOnlyCollection<string> capabilities)
            {
                return new PlayerAssistCredentialEvidence
                {
                    ClientInstanceId =
                        Evidence.ClientInstanceId,
                    ConsentReceipt =
                        Evidence.ConsentReceipt,
                    SelectedSessionId =
                        Evidence.SelectedSessionId,
                    AllowedCapabilities =
                        SelectPrincipalCapabilities(
                            capabilities,
                            AllowedCapabilities),
                    AllowedTargets =
                        Evidence.AllowedTargets.ToArray(),
                    RequestedLifetime =
                        Evidence.RequestedLifetime
                };
            }
        }
    }
}
