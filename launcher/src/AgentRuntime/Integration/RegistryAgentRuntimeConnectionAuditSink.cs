using System;
using CF7Launcher.AgentRuntime.Audit;
using CF7Launcher.AgentRuntime.Security;
using CF7Launcher.AgentRuntime.Sessions;

namespace CF7Launcher.AgentRuntime.Integration
{
    /// <summary>
    /// Binds connection/authentication facts to the single current
    /// Launcher-owned lifecycle. A client cannot name the session or
    /// lifecycle used to open an exportable audit scope.
    /// </summary>
    internal sealed class RegistryAgentRuntimeConnectionAuditSink
        : IAgentRuntimeConnectionAuditSink
    {
        private readonly SessionSurfaceRegistry _registry;
        private readonly ScopedAgentRuntimeAuditLedgerManager
            _ledger;

        public RegistryAgentRuntimeConnectionAuditSink(
            SessionSurfaceRegistry registry,
            ScopedAgentRuntimeAuditLedgerManager ledger)
        {
            _registry = registry
                ?? throw new ArgumentNullException(
                    nameof(registry));
            _ledger = ledger
                ?? throw new ArgumentNullException(
                    nameof(ledger));
        }

        public bool TryRegisterAuthenticatedConnection(
            string connectionId,
            PrincipalCredential principal,
            out string reasonCode)
        {
            SessionSurfaceRegistrySnapshot snapshot =
                _registry.GetSnapshot();
            SessionSnapshot session =
                snapshot.Sessions.Count == 1
                    ? snapshot.Sessions[0]
                    : null;
            if (session == null)
            {
                reasonCode = "session_not_found";
                return false;
            }
            if (principal.SessionMode
                    == AgentSessionMode.PlayerAssist
                && !string.Equals(
                    principal.SelectedSessionId,
                    session.SessionId,
                    StringComparison.Ordinal))
            {
                reasonCode = "session_scope_mismatch";
                return false;
            }
            return _ledger.TryRegisterAuthenticatedConnection(
                connectionId,
                principal,
                session.SessionId,
                session.LifecycleGeneration,
                out reasonCode);
        }

        public void RecordConnectionTermination(
            string connectionId,
            string reasonCode)
        {
            _ledger.RecordConnectionTermination(
                connectionId,
                string.IsNullOrWhiteSpace(reasonCode)
                    ? "connection_closed"
                    : reasonCode);
        }
    }
}
