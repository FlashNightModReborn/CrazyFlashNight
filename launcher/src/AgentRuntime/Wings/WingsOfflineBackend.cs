using System;
using System.Collections.Generic;
using System.Collections.ObjectModel;
using System.Linq;

namespace CF7Launcher.AgentRuntime.Wings
{
    internal enum WingsRequestKind
    {
        Guidance,
        AuthorizationExplanation,
        ActionResult
    }

    internal enum WingsBackendSource
    {
        OfflineReference,
        CloudProvider
    }

    internal sealed class WingsGuidanceRequest
    {
        private WingsGuidanceRequest(
            WingsRequestKind kind,
            string sessionId,
            LoreView loreView,
            WingsGuidanceDomain? domain,
            string guidanceKey,
            WingsVisibleGuidanceContext visibleContext,
            string neutralPermissionReceiptId,
            string actionReceiptId,
            string untrustedPersonaAuthorizationNarrative)
        {
            WingsProtocolValue.RequireOpaqueId(
                sessionId,
                nameof(sessionId));
            LoreView = loreView
                ?? throw new ArgumentNullException(nameof(loreView));
            if (!Enum.IsDefined(kind))
                throw new ArgumentOutOfRangeException(nameof(kind));
            if (domain.HasValue && !Enum.IsDefined(domain.Value))
                throw new ArgumentOutOfRangeException(nameof(domain));
            if (guidanceKey != null)
            {
                WingsProtocolValue.RequireStableKey(
                    guidanceKey,
                    nameof(guidanceKey));
            }
            if (kind == WingsRequestKind.Guidance
                && (visibleContext == null
                    || visibleContext.Domain != domain))
            {
                throw new ArgumentException(
                    "Guidance needs a matching structured visible context.",
                    nameof(visibleContext));
            }
            if (kind != WingsRequestKind.Guidance
                && visibleContext != null)
            {
                throw new ArgumentException(
                    "Only guidance accepts visible context.",
                    nameof(visibleContext));
            }
            ValidateOptionalOpaqueId(
                neutralPermissionReceiptId,
                nameof(neutralPermissionReceiptId));
            ValidateOptionalOpaqueId(
                actionReceiptId,
                nameof(actionReceiptId));
            if ((untrustedPersonaAuthorizationNarrative
                    ?? string.Empty).Length > 512)
            {
                throw new ArgumentException(
                    "Untrusted persona narrative exceeds the v1 bound.",
                    nameof(untrustedPersonaAuthorizationNarrative));
            }

            Kind = kind;
            SessionId = sessionId;
            Domain = domain;
            GuidanceKey = guidanceKey;
            VisibleContext = visibleContext;
            NeutralPermissionReceiptId =
                neutralPermissionReceiptId;
            ActionReceiptId = actionReceiptId;
            UntrustedPersonaAuthorizationNarrative =
                untrustedPersonaAuthorizationNarrative
                ?? string.Empty;
        }

        public WingsRequestKind Kind { get; }
        public string SessionId { get; }
        public LoreView LoreView { get; }
        public WingsGuidanceDomain? Domain { get; }
        public string GuidanceKey { get; }
        public WingsVisibleGuidanceContext VisibleContext { get; }
        public string NeutralPermissionReceiptId { get; }
        public string ActionReceiptId { get; }

        /// <summary>
        /// Presentation-only input. It is never consulted for permission
        /// resolution or output facts.
        /// </summary>
        public string UntrustedPersonaAuthorizationNarrative { get; }

        public static WingsGuidanceRequest ForGuidance(
            string sessionId,
            LoreView loreView,
            WingsGuidanceDomain domain,
            string guidanceKey,
            WingsVisibleGuidanceContext visibleContext = null)
        {
            return new WingsGuidanceRequest(
                WingsRequestKind.Guidance,
                sessionId,
                loreView,
                domain,
                guidanceKey,
                visibleContext
                    ?? WingsVisibleGuidanceContext.Empty(domain),
                null,
                null,
                null);
        }

        public static WingsGuidanceRequest ForAuthorizationExplanation(
            string sessionId,
            LoreView loreView,
            string neutralPermissionReceiptId,
            string untrustedPersonaAuthorizationNarrative = null)
        {
            return new WingsGuidanceRequest(
                WingsRequestKind.AuthorizationExplanation,
                sessionId,
                loreView,
                null,
                null,
                null,
                neutralPermissionReceiptId,
                null,
                untrustedPersonaAuthorizationNarrative);
        }

        public static WingsGuidanceRequest ForActionResult(
            string sessionId,
            LoreView loreView,
            string actionReceiptId)
        {
            return new WingsGuidanceRequest(
                WingsRequestKind.ActionResult,
                sessionId,
                loreView,
                null,
                null,
                null,
                null,
                actionReceiptId,
                null);
        }

        private static void ValidateOptionalOpaqueId(
            string value,
            string parameterName)
        {
            if (value != null)
                WingsProtocolValue.RequireOpaqueId(
                    value,
                    parameterName);
        }
    }

    internal sealed class WingsBackendResult
    {
        public WingsBackendResult(
            WingsCheckedOutput output,
            WingsBackendSource source,
            string providerId = null,
            IEnumerable<string> disclosedFieldKeys = null,
            string fallbackReasonCode = null)
        {
            Output = output
                ?? throw new ArgumentNullException(nameof(output));
            if (!output.Accepted)
                throw new ArgumentException(
                    "A backend cannot expose a rejected output.",
                    nameof(output));
            if (!Enum.IsDefined(source))
                throw new ArgumentOutOfRangeException(nameof(source));
            if (providerId != null)
            {
                WingsProtocolValue.RequireStableKey(
                    providerId,
                    nameof(providerId));
            }

            Source = source;
            ProviderId = providerId;
            DisclosedFieldKeys = Array.AsReadOnly(
                (disclosedFieldKeys ?? Array.Empty<string>())
                    .OrderBy(value => value, StringComparer.Ordinal)
                    .ToArray());
            FallbackReasonCode = fallbackReasonCode;
        }

        public WingsCheckedOutput Output { get; }
        public WingsBackendSource Source { get; }
        public string ProviderId { get; }
        public ReadOnlyCollection<string> DisclosedFieldKeys { get; }
        public string FallbackReasonCode { get; }

        /// <summary>
        /// Cloud rejection and provider failure never mutate affinity,
        /// rewards, or refusal state.
        /// </summary>
        public int PenaltyDelta => 0;
    }

    internal interface IWingsReferenceBackend
    {
        WingsBackendResult Generate(WingsGuidanceRequest request);
    }

    internal sealed class DeterministicOfflineWingsBackend
        : IWingsReferenceBackend
    {
        private readonly LoreRetriever _retriever;
        private readonly WingsOutputChecker _checker;
        private readonly INeutralConsentFactsAuthority
            _consentAuthority;
        private readonly ITrustedActionResultAuthority
            _actionResultAuthority;
        private readonly Func<DateTimeOffset> _utcNow;

        public DeterministicOfflineWingsBackend(
            INeutralConsentFactsAuthority consentAuthority = null,
            ITrustedActionResultAuthority actionResultAuthority = null,
            LoreRetriever retriever = null,
            WingsOutputChecker checker = null,
            Func<DateTimeOffset> utcNow = null)
        {
            _consentAuthority = consentAuthority;
            _actionResultAuthority = actionResultAuthority;
            _retriever = retriever ?? new LoreRetriever();
            _checker = checker ?? new WingsOutputChecker();
            _utcNow = utcNow ?? (() => DateTimeOffset.UtcNow);
        }

        public WingsBackendResult Generate(
            WingsGuidanceRequest request)
        {
            if (request == null)
                throw new ArgumentNullException(nameof(request));
            DateTimeOffset now = _utcNow();
            switch (request.Kind)
            {
                case WingsRequestKind.Guidance:
                    return Guidance(request, now);
                case WingsRequestKind.AuthorizationExplanation:
                    return Authorization(request, now);
                case WingsRequestKind.ActionResult:
                    return ActionResult(request, now);
                default:
                    throw new InvalidOperationException(
                        "Unknown Wings request kind.");
            }
        }

        private WingsBackendResult Guidance(
            WingsGuidanceRequest request,
            DateTimeOffset now)
        {
            ReadOnlyCollection<LoreFact> facts =
                _retriever.Retrieve(
                    request.LoreView,
                    request.Domain.Value,
                    request.GuidanceKey);
            var context = Context(request, now);
            if (facts.Count == 0)
            {
                return Checked(
                    WingsCanonicalDraftFactory.SafeFallback(
                        context,
                        WingsFallbackReason.NoEligibleFacts),
                    context);
            }
            WingsFactClaim[] claims = facts
                .Select(fact => new WingsFactClaim(
                    fact.FactId,
                    fact.SourceRevision))
                .ToArray();
            return Checked(
                WingsCanonicalDraftFactory.Guidance(
                    context,
                    claims),
                context);
        }

        private WingsBackendResult Authorization(
            WingsGuidanceRequest request,
            DateTimeOffset now)
        {
            if (request.NeutralPermissionReceiptId == null
                || _consentAuthority == null
                || !_consentAuthority.TryResolve(
                    request.NeutralPermissionReceiptId,
                    out TrustedNeutralPermissionFacts permission,
                    out _)
                || permission == null
                || !string.Equals(
                    permission.ReceiptId,
                    request.NeutralPermissionReceiptId,
                    StringComparison.Ordinal))
            {
                WingsOutputCheckContext fallbackContext =
                    Context(request, now);
                return Checked(
                    WingsCanonicalDraftFactory.SafeFallback(
                        fallbackContext,
                        WingsFallbackReason
                            .ConsentFactsUnavailable),
                    fallbackContext);
            }

            var context = Context(
                request,
                now,
                permissionFacts: permission);
            WingsFactClaim[] cues = request.LoreView.Facts.Values
                .Where(fact =>
                    fact.CanonClass == LoreCanonClass.PresentationCue
                    && fact.GuidanceKeys.Contains(
                        "cue.permission",
                        StringComparer.Ordinal))
                .OrderBy(fact => fact.FactId, StringComparer.Ordinal)
                .Select(fact => new WingsFactClaim(
                    fact.FactId,
                    fact.SourceRevision))
                .ToArray();
            WingsDraftOutput draft =
                WingsCanonicalDraftFactory.Authorization(
                    context,
                    permission.ReceiptId,
                    cues);
            WingsCheckedOutput checkedOutput =
                _checker.Check(draft, context);
            if (!checkedOutput.Accepted)
            {
                WingsOutputCheckContext fallbackContext =
                    Context(request, now);
                return Checked(
                    WingsCanonicalDraftFactory.SafeFallback(
                        fallbackContext,
                        WingsFallbackReason
                            .ConsentFactsUnavailable),
                    fallbackContext);
            }
            return new WingsBackendResult(
                checkedOutput,
                WingsBackendSource.OfflineReference);
        }

        private WingsBackendResult ActionResult(
            WingsGuidanceRequest request,
            DateTimeOffset now)
        {
            if (request.ActionReceiptId == null
                || _actionResultAuthority == null
                || !_actionResultAuthority.TryResolve(
                    request.ActionReceiptId,
                    out TrustedActionResultFacts result,
                    out _)
                || result == null
                || !string.Equals(
                    result.ReceiptId,
                    request.ActionReceiptId,
                    StringComparison.Ordinal))
            {
                WingsOutputCheckContext fallbackContext =
                    Context(request, now);
                return Checked(
                    WingsCanonicalDraftFactory.SafeFallback(
                        fallbackContext,
                        WingsFallbackReason
                            .ActionResultUnavailable),
                    fallbackContext);
            }

            var context = Context(
                request,
                now,
                actionResultFacts: result);
            WingsDraftOutput draft =
                WingsCanonicalDraftFactory.ActionResult(
                    context,
                    result.ReceiptId);
            WingsCheckedOutput checkedOutput =
                _checker.Check(draft, context);
            if (!checkedOutput.Accepted)
            {
                WingsOutputCheckContext fallbackContext =
                    Context(request, now);
                return Checked(
                    WingsCanonicalDraftFactory.SafeFallback(
                        fallbackContext,
                        WingsFallbackReason
                            .ActionResultUnavailable),
                    fallbackContext);
            }
            return new WingsBackendResult(
                checkedOutput,
                WingsBackendSource.OfflineReference);
        }

        private WingsBackendResult Checked(
            WingsDraftOutput draft,
            WingsOutputCheckContext context)
        {
            WingsCheckedOutput output =
                _checker.Check(draft, context);
            if (!output.Accepted)
            {
                throw new InvalidOperationException(
                    "offline_reference_output_rejected:"
                    + output.ReasonCode);
            }
            return new WingsBackendResult(
                output,
                WingsBackendSource.OfflineReference);
        }

        private static WingsOutputCheckContext Context(
            WingsGuidanceRequest request,
            DateTimeOffset now,
            TrustedNeutralPermissionFacts permissionFacts = null,
            TrustedActionResultFacts actionResultFacts = null)
        {
            return new WingsOutputCheckContext(
                request.SessionId,
                request.LoreView,
                request.Domain,
                request.GuidanceKey,
                now,
                permissionFacts,
                actionResultFacts);
        }
    }

    internal static class WingsCanonicalDraftFactory
    {
        public static WingsDraftOutput Guidance(
            WingsOutputCheckContext context,
            IEnumerable<WingsFactClaim> claims)
        {
            WingsFactClaim[] frozen = claims.ToArray();
            return Canonicalize(
                context,
                WingsOutputPurpose.Guidance,
                frozen,
                null,
                null,
                null,
                null);
        }

        public static WingsDraftOutput Authorization(
            WingsOutputCheckContext context,
            string receiptId,
            IEnumerable<WingsFactClaim> presentationCues)
        {
            return Canonicalize(
                context,
                WingsOutputPurpose.AuthorizationExplanation,
                null,
                presentationCues.ToArray(),
                receiptId,
                null,
                null);
        }

        public static WingsDraftOutput ActionResult(
            WingsOutputCheckContext context,
            string receiptId)
        {
            return Canonicalize(
                context,
                WingsOutputPurpose.ActionResult,
                null,
                null,
                null,
                receiptId,
                null);
        }

        public static WingsDraftOutput SafeFallback(
            WingsOutputCheckContext context,
            WingsFallbackReason reason)
        {
            return Canonicalize(
                context,
                WingsOutputPurpose.SafeFallback,
                null,
                null,
                null,
                null,
                reason);
        }

        private static WingsDraftOutput Canonicalize(
            WingsOutputCheckContext context,
            WingsOutputPurpose purpose,
            IEnumerable<WingsFactClaim> claims,
            IEnumerable<WingsFactClaim> cues,
            string permissionReceipt,
            string actionReceipt,
            WingsFallbackReason? fallbackReason)
        {
            var shape = new WingsDraftOutput(
                context.LoreView.Progress.SaveBindingId,
                context.LoreView.LoreViewId,
                purpose,
                "pending",
                claims,
                cues,
                permissionReceipt,
                actionReceipt,
                fallbackReason);
            string text = WingsCanonicalOutputRenderer.Render(
                shape,
                context);
            return new WingsDraftOutput(
                shape.SaveBindingId,
                shape.LoreViewId,
                shape.Purpose,
                text,
                shape.FactualClaims,
                shape.PresentationCues,
                shape.NeutralPermissionReceiptId,
                shape.ActionReceiptId,
                shape.FallbackReason);
        }
    }
}
