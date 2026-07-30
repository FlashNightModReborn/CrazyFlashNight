using System;
using System.Collections.Generic;
using CF7Launcher.AgentRuntime.Contracts;
using CF7Launcher.AgentRuntime.Security;

namespace CF7Launcher.Tests.AgentRuntime.Security
{
    internal sealed class MutableAgentTargetAuthority
        : IAgentTargetAuthority,
          IAgentSessionModeAuthority
    {
        private readonly Dictionary<string, AgentTargetDescriptor> _targets =
            new Dictionary<string, AgentTargetDescriptor>(
                StringComparer.Ordinal);
        private readonly Dictionary<string, SessionMode> _sessionModes =
            new Dictionary<string, SessionMode>(
                StringComparer.Ordinal);

        public void Set(
            string sessionId,
            string targetId,
            AgentTargetSafetyKind safetyKind =
                AgentTargetSafetyKind.RuntimeOwned,
            SurfaceKind kind = SurfaceKind.Flash)
        {
            _targets[Key(sessionId, targetId)] =
                new AgentTargetDescriptor(
                    sessionId,
                    targetId,
                    safetyKind,
                    kind);
            if (!_sessionModes.ContainsKey(sessionId))
            {
                _sessionModes[sessionId] =
                    SessionMode.DeveloperInteractive;
            }
        }

        public void SetSessionMode(
            string sessionId,
            SessionMode sessionMode)
        {
            _sessionModes[sessionId] = sessionMode;
        }

        public bool TryResolve(
            string sessionId,
            string targetId,
            out AgentTargetDescriptor descriptor,
            out string reasonCode)
        {
            if (!_targets.TryGetValue(
                    Key(sessionId, targetId),
                    out descriptor))
            {
                descriptor = null;
                reasonCode = "target_not_authoritative";
                return false;
            }

            reasonCode = null;
            return true;
        }

        public bool TryResolveSessionMode(
            string sessionId,
            out SessionMode sessionMode,
            out string reasonCode)
        {
            if (!_sessionModes.TryGetValue(
                    sessionId ?? string.Empty,
                    out sessionMode))
            {
                reasonCode = "session_not_found";
                return false;
            }
            reasonCode = null;
            return true;
        }

        private static string Key(string sessionId, string targetId)
        {
            return sessionId + "\n" + targetId;
        }
    }
}
