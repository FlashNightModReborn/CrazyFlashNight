using CF7Launcher.AgentRuntime.Security;

namespace CF7Launcher.Tests.AgentRuntime.Security
{
    internal sealed class TestPrincipalEnrollmentVerifier
        : IPrincipalEnrollmentVerifier
    {
        public bool AcceptDeveloper { get; set; } = true;
        public bool AcceptUnattended { get; set; } = true;
        public bool AcceptPlayerAssist { get; set; } = true;

        public bool TryVerifyDeveloper(
            DeveloperEnrollmentEvidence evidence,
            out VerifiedPrincipalAuthorization authorization,
            out string reasonCode)
        {
            return Complete(
                AcceptDeveloper,
                evidence.AllowedCapabilities,
                evidence.AllowedTargets,
                evidence.EnrollmentReceipt,
                "developer_enrollment_evidence_invalid",
                out authorization,
                out reasonCode);
        }

        public bool TryVerifyUnattended(
            UnattendedCredentialEvidence evidence,
            out VerifiedPrincipalAuthorization authorization,
            out string reasonCode)
        {
            return Complete(
                AcceptUnattended,
                evidence.AllowedCapabilities,
                evidence.AllowedTargets,
                "allow-list:" + evidence.BuildIdentity
                    + ":" + evidence.AttemptId,
                "unattended_allow_list_evidence_invalid",
                out authorization,
                out reasonCode);
        }

        public bool TryVerifyPlayerAssist(
            PlayerAssistCredentialEvidence evidence,
            out VerifiedPrincipalAuthorization authorization,
            out string reasonCode)
        {
            return Complete(
                AcceptPlayerAssist,
                evidence.AllowedCapabilities,
                evidence.AllowedTargets,
                evidence.ConsentReceipt,
                "player_consent_evidence_invalid",
                out authorization,
                out reasonCode);
        }

        private static bool Complete(
            bool accepted,
            System.Collections.Generic.IEnumerable<string> capabilities,
            System.Collections.Generic.IEnumerable<string> targets,
            string receipt,
            string rejection,
            out VerifiedPrincipalAuthorization authorization,
            out string reasonCode)
        {
            if (!accepted)
            {
                authorization = null;
                reasonCode = rejection;
                return false;
            }

            authorization =
                VerifiedPrincipalAuthorization.CreateTrusted(
                    capabilities,
                    targets,
                    receipt);
            reasonCode = null;
            return true;
        }
    }
}
