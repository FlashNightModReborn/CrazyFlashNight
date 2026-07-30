using System;
using CF7Launcher.AgentRuntime.Contracts;

namespace CF7Launcher.AgentRuntime.Security
{
    public enum AgentTargetSafetyKind
    {
        RuntimeOwned,
        HumanOnlySecuritySurface
    }

    public sealed record AgentTargetDescriptor(
        string SessionId,
        string TargetId,
        AgentTargetSafetyKind SafetyKind,
        SurfaceKind Kind);

    /// <summary>
    /// Resolves target identity and safety from host-owned session state.
    /// Wire requests must never supply their own safety classification.
    /// </summary>
    public interface IAgentTargetAuthority
    {
        bool TryResolve(
            string sessionId,
            string targetId,
            out AgentTargetDescriptor descriptor,
            out string reasonCode);
    }

    /// <summary>
    /// Host-authoritative current mode for a registered session. Credential
    /// mode is never sufficient on its own because unattended and
    /// player-assist principals must not be interleaved in one lifecycle.
    /// </summary>
    internal interface IAgentSessionModeAuthority
    {
        bool TryResolveSessionMode(
            string sessionId,
            out SessionMode sessionMode,
            out string reasonCode);
    }

    internal static class AgentSessionModeCompatibility
    {
        internal static bool IsCompatible(
            AgentSessionMode credentialMode,
            SessionMode sessionMode)
        {
            return sessionMode switch
            {
                SessionMode.UnattendedTest =>
                    credentialMode
                        == AgentSessionMode.UnattendedTest,
                SessionMode.PlayerAssist =>
                    credentialMode
                        == AgentSessionMode.PlayerAssist,
                SessionMode.DeveloperInteractive =>
                    credentialMode
                            == AgentSessionMode
                                .DeveloperInteractive
                        || credentialMode
                            == AgentSessionMode.PlayerAssist,
                _ => false
            };
        }
    }
}
