using System;
using System.Linq;
using CF7Launcher.AgentRuntime.Contracts;
using CF7Launcher.AgentRuntime.Security;
using CF7Launcher.AgentRuntime.Sessions;

namespace CF7Launcher.AgentRuntime.Gateway
{
    /// <summary>
    /// Resolves the single Runtime-owned WebOverlay surface that is allowed to
    /// carry a Hair domain transaction. Every stage of the protocol uses this
    /// same authority so a client cannot switch the preview, consent, lease,
    /// commit, or restore to a different surface.
    /// </summary>
    internal interface IAgentHairDomainTargetAuthority
    {
        bool TryAuthorize(
            string sessionId,
            string targetId,
            out string reasonCode);
    }

    internal sealed class RegistryAgentHairDomainTargetAuthority
        : IAgentHairDomainTargetAuthority
    {
        private readonly SessionSurfaceRegistry _sessions;

        public RegistryAgentHairDomainTargetAuthority(
            SessionSurfaceRegistry sessions)
        {
            _sessions = sessions
                ?? throw new ArgumentNullException(nameof(sessions));
        }

        public bool TryAuthorize(
            string sessionId,
            string targetId,
            out string reasonCode)
        {
            if (string.IsNullOrWhiteSpace(sessionId)
                || string.IsNullOrWhiteSpace(targetId))
            {
                reasonCode = "arguments_invalid";
                return false;
            }

            SessionSnapshot session = _sessions.GetSnapshot()
                .FindSession(sessionId);
            if (session == null)
            {
                reasonCode = "session_not_found";
                return false;
            }

            SessionSurfaceSnapshot[] eligible = session.Surfaces
                .Where(surface =>
                    surface.SafetyKind
                        == AgentTargetSafetyKind.RuntimeOwned
                    && surface.Kind == SurfaceKind.WebOverlay
                    && surface.InputModes.Contains(
                        InputMode.DomainTransaction))
                .ToArray();
            if (eligible.Length != 1
                || !string.Equals(
                    eligible[0].TargetId,
                    targetId,
                    StringComparison.Ordinal))
            {
                reasonCode = "unsupported_for_surface";
                return false;
            }

            reasonCode = null;
            return true;
        }
    }
}
