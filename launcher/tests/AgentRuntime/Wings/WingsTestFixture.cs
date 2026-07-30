using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using CF7Launcher.AgentRuntime.Contracts;
using CF7Launcher.AgentRuntime.Wings;

namespace CF7Launcher.Tests.AgentRuntime.Wings
{
    internal static class WingsTestFixture
    {
        public const string SessionId =
            "ss_7Qm2vL8aR4nK9xT1cY6uP";
        public const string OtherSessionId =
            "ss_2Dp8wR4mN7xK1qV9cL5hT";
        public const string PermissionReceiptId =
            "pr_6Nx2mT9qR4vK8cL1wH7dP";
        public const string ActionReceiptId =
            "ar_9Qv3mL7xT1cK5nR8pD2hF";
        public const string ActionId =
            "ac_4Hm8qX2vN7rL1tK9cP5dB";
        public const string EgressReceiptId =
            "eg_1Kp6tR9mV3xQ8nL2cH7wD";
        public const string PauseReceiptId =
            "pp_8Rc2mN5qT1vK7xL4pD9hF";

        public static string AssetDirectory
        {
            get
            {
                var current = new DirectoryInfo(
                    AppContext.BaseDirectory);
                while (current != null)
                {
                    string candidate = Path.Combine(
                        current.FullName,
                        "launcher",
                        "agent-assets",
                        "lore");
                    if (Directory.Exists(candidate))
                        return candidate;
                    current = current.Parent;
                }
                throw new DirectoryNotFoundException(
                    "Could not locate launcher/agent-assets/lore.");
            }
        }

        public static LoreCatalog Catalog()
        {
            return LoreCatalogParser.Parse(
                File.ReadAllBytes(Path.Combine(
                    AssetDirectory,
                    "public-companion.v1.json")));
        }

        public static LoreProgressSnapshot Progress(string fixture)
        {
            return LoreCatalogParser.ParseProgressFixture(
                File.ReadAllBytes(Path.Combine(
                    AssetDirectory,
                    "fixtures",
                    fixture)));
        }

        public static LoreView View(
            string fixture = "ng-plus.json")
        {
            return new LoreProjectionService().Project(
                Catalog(),
                Progress(fixture));
        }

        public static LoreView ReboundView(
            LoreView source,
            string saveBindingId,
            string signature = null,
            string progressRevision = null)
        {
            LoreProgressSnapshot old = source.Progress;
            var rebound = new LoreProgressSnapshot(
                saveBindingId,
                signature
                    ?? new string('A', 64),
                old.SaveClass,
                old.StoryPhaseId,
                progressRevision ?? old.ProgressRevision,
                old.ProgressFlags,
                old.BranchSelections,
                old.RevealedFactIds);
            return new LoreProjectionService().Project(
                Catalog(),
                rebound);
        }

        public static DateTimeOffset Now =>
            new DateTimeOffset(
                2026,
                7,
                30,
                12,
                0,
                0,
                TimeSpan.Zero);

        public static TrustedNeutralPermissionFacts Permission(
            LoreView view,
            string sessionId = SessionId,
            string receiptId = PermissionReceiptId,
            DateTimeOffset? expiresAt = null)
        {
            return new TrustedNeutralPermissionFacts(
                receiptId,
                sessionId,
                view.Progress.SaveBindingId,
                view.LoreViewId,
                "观察与建议",
                new[]
                {
                    "observation.screen",
                    "guidance.read-only"
                },
                NeutralRetentionMode.SessionOnly,
                Now.AddMinutes(-1),
                expiresAt ?? Now.AddMinutes(30));
        }

        public static TrustedActionResultFacts ActionResult(
            LoreView view,
            ActionOutcome outcome,
            string sessionId = SessionId,
            string receiptId = ActionReceiptId)
        {
            return new TrustedActionResultFacts(
                receiptId,
                ActionId,
                sessionId,
                view.Progress.SaveBindingId,
                view.LoreViewId,
                outcome);
        }

        public static WingsFactClaim Claim(
            LoreView view,
            string factId)
        {
            LoreFact fact = view.Facts[factId];
            return new WingsFactClaim(
                fact.FactId,
                fact.SourceRevision);
        }

        public static WingsVisibleGuidanceContext VisibleContext(
            WingsGuidanceDomain domain)
        {
            KeyValuePair<string, string> field = domain switch
            {
                WingsGuidanceDomain.Task =>
                    new KeyValuePair<string, string>(
                        "task.visible-state",
                        "available"),
                WingsGuidanceDomain.Equipment =>
                    new KeyValuePair<string, string>(
                        "equipment.visible-slot",
                        "primary"),
                WingsGuidanceDomain.Route =>
                    new KeyValuePair<string, string>(
                        "route.visible-location-id",
                        "base"),
                WingsGuidanceDomain.Ui =>
                    new KeyValuePair<string, string>(
                        "ui.visible-panel-id",
                        "hairdresser"),
                _ => throw new ArgumentOutOfRangeException(
                    nameof(domain))
            };
            return new WingsVisibleGuidanceContext(
                domain,
                "context.fixture.v1",
                new Dictionary<string, string>
                {
                    [field.Key] = field.Value
                });
        }

        public static string[] FactIds(LoreView view)
        {
            return view.Facts.Keys
                .OrderBy(value => value, StringComparer.Ordinal)
                .ToArray();
        }
    }

    internal sealed class StubConsentAuthority
        : INeutralConsentFactsAuthority
    {
        private readonly TrustedNeutralPermissionFacts _facts;

        public StubConsentAuthority(
            TrustedNeutralPermissionFacts facts)
        {
            _facts = facts;
        }

        public bool TryResolve(
            string receiptId,
            out TrustedNeutralPermissionFacts facts,
            out string reasonCode)
        {
            facts = string.Equals(
                receiptId,
                _facts?.ReceiptId,
                StringComparison.Ordinal)
                    ? _facts
                    : null;
            reasonCode = facts == null ? "not_found" : null;
            return facts != null;
        }
    }

    internal sealed class StubActionResultAuthority
        : ITrustedActionResultAuthority
    {
        private readonly TrustedActionResultFacts _facts;

        public StubActionResultAuthority(
            TrustedActionResultFacts facts)
        {
            _facts = facts;
        }

        public bool TryResolve(
            string receiptId,
            out TrustedActionResultFacts facts,
            out string reasonCode)
        {
            facts = string.Equals(
                receiptId,
                _facts?.ReceiptId,
                StringComparison.Ordinal)
                    ? _facts
                    : null;
            reasonCode = facts == null ? "not_found" : null;
            return facts != null;
        }
    }
}
