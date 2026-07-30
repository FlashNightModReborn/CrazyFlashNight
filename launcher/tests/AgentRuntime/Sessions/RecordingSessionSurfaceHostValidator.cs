using CF7Launcher.AgentRuntime.Sessions;

namespace CF7Launcher.Tests.AgentRuntime.Sessions
{
    internal sealed class RecordingSessionSurfaceHostValidator
        : ISessionSurfaceHostValidator
    {
        public int SessionValidationCount { get; private set; }
        public int AttemptValidationCount { get; private set; }
        public int SurfaceValidationCount { get; private set; }
        public string RejectionReason { get; set; }

        public bool ValidateSession(
            SessionRegistryHostOwner hostOwner,
            SessionHostRegistration registration,
            out string reasonCode)
        {
            SessionValidationCount++;
            return Complete(out reasonCode);
        }

        public bool ValidateAttemptProcess(
            SessionRegistryHostOwner hostOwner,
            SessionProcessIdentity flashProcess,
            out string reasonCode)
        {
            AttemptValidationCount++;
            return Complete(out reasonCode);
        }

        public bool ValidateSurface(
            SessionRegistryHostOwner hostOwner,
            SessionSurfaceValidationContext context,
            SessionSurfaceHostRegistration registration,
            out string reasonCode)
        {
            SurfaceValidationCount++;
            return Complete(out reasonCode);
        }

        private bool Complete(out string reasonCode)
        {
            reasonCode = RejectionReason;
            return RejectionReason == null;
        }
    }
}
