using System;
using CF7Launcher.AgentRuntime.Audit;
using CF7Launcher.AgentRuntime.Security;
using CF7Launcher.AgentRuntime.Sessions;

namespace CF7Launcher.AgentRuntime.Integration
{
    /// <summary>
    /// Resolves audit scope only from the authenticated principal and the
    /// current host-owned session registry. Client parameters cannot create
    /// an audit namespace for a stale or foreign lifecycle.
    /// </summary>
    internal sealed class RegistryAgentAuditScopeAuthority
        : IAgentAuditScopeAuthority
    {
        private readonly SessionSurfaceRegistry _registry;

        public RegistryAgentAuditScopeAuthority(
            SessionSurfaceRegistry registry)
        {
            _registry = registry
                ?? throw new ArgumentNullException(
                    nameof(registry));
        }

        public bool TryAuthorize(
            PrincipalCredential principal,
            string sessionId,
            ulong lifecycleGeneration,
            string consentPurpose,
            out string reasonCode)
        {
            if (principal == null
                || string.IsNullOrWhiteSpace(sessionId)
                || lifecycleGeneration == 0
                || string.IsNullOrWhiteSpace(
                    consentPurpose))
            {
                reasonCode = "audit_scope_invalid";
                return false;
            }
            if (!principal.AllowsCapability(
                    consentPurpose))
            {
                reasonCode = "capability_denied";
                return false;
            }
            if (principal.SessionMode
                    == AgentSessionMode.PlayerAssist
                && !string.Equals(
                    principal.SelectedSessionId,
                    sessionId,
                    StringComparison.Ordinal))
            {
                reasonCode =
                    "session_scope_mismatch";
                return false;
            }
            SessionSnapshot session =
                _registry.GetSnapshot()
                    .FindSession(sessionId);
            if (session == null)
            {
                reasonCode = "session_not_found";
                return false;
            }
            if (session.LifecycleGeneration
                != lifecycleGeneration)
            {
                reasonCode = "stale_lifecycle";
                return false;
            }
            reasonCode = null;
            return true;
        }
    }
}
