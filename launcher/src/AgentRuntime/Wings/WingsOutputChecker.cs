using System;
using System.Collections.Generic;
using System.Collections.ObjectModel;
using System.Linq;
using CF7Launcher.AgentRuntime.Contracts;

namespace CF7Launcher.AgentRuntime.Wings
{
    internal enum WingsOutputPurpose
    {
        Guidance,
        AuthorizationExplanation,
        ActionResult,
        SafeFallback
    }

    internal enum WingsFallbackReason
    {
        NoEligibleFacts,
        ConsentFactsUnavailable,
        ActionResultUnavailable,
        CloudNotAuthorized,
        CloudProviderFailed,
        CloudOutputRejected
    }

    internal enum NeutralRetentionMode
    {
        None,
        SessionOnly
    }

    internal sealed class WingsFactClaim
    {
        public WingsFactClaim(string factId, string sourceRevision)
        {
            WingsProtocolValue.RequireStableKey(
                factId,
                nameof(factId));
            WingsProtocolValue.RequireText(
                sourceRevision,
                128,
                nameof(sourceRevision));
            FactId = factId;
            SourceRevision = sourceRevision;
        }

        public string FactId { get; }
        public string SourceRevision { get; }
    }

    internal sealed class WingsDraftOutput
    {
        public WingsDraftOutput(
            string saveBindingId,
            string loreViewId,
            WingsOutputPurpose purpose,
            string text,
            IEnumerable<WingsFactClaim> factualClaims = null,
            IEnumerable<WingsFactClaim> presentationCues = null,
            string neutralPermissionReceiptId = null,
            string actionReceiptId = null,
            WingsFallbackReason? fallbackReason = null)
        {
            WingsProtocolValue.RequireOpaqueId(
                saveBindingId,
                nameof(saveBindingId));
            WingsProtocolValue.RequireOpaqueId(
                loreViewId,
                nameof(loreViewId));
            if (!Enum.IsDefined(purpose))
                throw new ArgumentOutOfRangeException(nameof(purpose));
            WingsProtocolValue.RequireText(text, 4096, nameof(text));
            if (fallbackReason.HasValue
                && !Enum.IsDefined(fallbackReason.Value))
            {
                throw new ArgumentOutOfRangeException(
                    nameof(fallbackReason));
            }

            SaveBindingId = saveBindingId;
            LoreViewId = loreViewId;
            Purpose = purpose;
            Text = text;
            FactualClaims = FreezeClaims(factualClaims);
            PresentationCues = FreezeClaims(presentationCues);
            NeutralPermissionReceiptId =
                ValidateOptionalOpaqueId(
                    neutralPermissionReceiptId,
                    nameof(neutralPermissionReceiptId));
            ActionReceiptId = ValidateOptionalOpaqueId(
                actionReceiptId,
                nameof(actionReceiptId));
            FallbackReason = fallbackReason;
        }

        public string SaveBindingId { get; }
        public string LoreViewId { get; }
        public WingsOutputPurpose Purpose { get; }
        public string Text { get; }
        public ReadOnlyCollection<WingsFactClaim> FactualClaims
        {
            get;
        }
        public ReadOnlyCollection<WingsFactClaim> PresentationCues
        {
            get;
        }
        public string NeutralPermissionReceiptId { get; }
        public string ActionReceiptId { get; }
        public WingsFallbackReason? FallbackReason { get; }

        private static ReadOnlyCollection<WingsFactClaim> FreezeClaims(
            IEnumerable<WingsFactClaim> claims)
        {
            WingsFactClaim[] values =
                (claims ?? Array.Empty<WingsFactClaim>()).ToArray();
            if (values.Any(value => value == null)
                || values.Length > 64)
            {
                throw new ArgumentException(
                    "Output claims are null or exceed the v1 bound.",
                    nameof(claims));
            }
            return Array.AsReadOnly(values);
        }

        private static string ValidateOptionalOpaqueId(
            string value,
            string parameterName)
        {
            if (value == null)
                return null;
            WingsProtocolValue.RequireOpaqueId(value, parameterName);
            return value;
        }
    }

    /// <summary>
    /// A neutral Launcher authority constructs this object. Persona text is
    /// deliberately not accepted as a constructor input by the backend.
    /// </summary>
    internal sealed class TrustedNeutralPermissionFacts
    {
        internal TrustedNeutralPermissionFacts(
            string receiptId,
            string sessionId,
            string saveBindingId,
            string loreViewId,
            string neutralDisplayName,
            IEnumerable<string> grantedScopes,
            NeutralRetentionMode retentionMode,
            DateTimeOffset issuedAtUtc,
            DateTimeOffset expiresAtUtc)
        {
            WingsProtocolValue.RequireOpaqueId(
                receiptId,
                nameof(receiptId));
            WingsProtocolValue.RequireOpaqueId(
                sessionId,
                nameof(sessionId));
            WingsProtocolValue.RequireOpaqueId(
                saveBindingId,
                nameof(saveBindingId));
            WingsProtocolValue.RequireOpaqueId(
                loreViewId,
                nameof(loreViewId));
            WingsProtocolValue.RequireText(
                neutralDisplayName,
                128,
                nameof(neutralDisplayName));
            if (!Enum.IsDefined(retentionMode))
                throw new ArgumentOutOfRangeException(
                    nameof(retentionMode));
            if (issuedAtUtc >= expiresAtUtc)
                throw new ArgumentException(
                    "Permission expiry must be after issuance.",
                    nameof(expiresAtUtc));
            string[] scopes =
                (grantedScopes ?? Array.Empty<string>())
                    .Select(scope =>
                    {
                        WingsProtocolValue.RequireStableKey(
                            scope,
                            nameof(grantedScopes));
                        return scope;
                    })
                    .Distinct(StringComparer.Ordinal)
                    .OrderBy(scope => scope, StringComparer.Ordinal)
                    .ToArray();
            if (scopes.Length == 0 || scopes.Length > 32)
                throw new ArgumentException(
                    "Permission facts need 1-32 neutral scopes.",
                    nameof(grantedScopes));

            ReceiptId = receiptId;
            SessionId = sessionId;
            SaveBindingId = saveBindingId;
            LoreViewId = loreViewId;
            NeutralDisplayName = neutralDisplayName;
            GrantedScopes = Array.AsReadOnly(scopes);
            RetentionMode = retentionMode;
            IssuedAtUtc = issuedAtUtc;
            ExpiresAtUtc = expiresAtUtc;
        }

        public string ReceiptId { get; }
        public string SessionId { get; }
        public string SaveBindingId { get; }
        public string LoreViewId { get; }
        public string NeutralDisplayName { get; }
        public ReadOnlyCollection<string> GrantedScopes { get; }
        public NeutralRetentionMode RetentionMode { get; }
        public DateTimeOffset IssuedAtUtc { get; }
        public DateTimeOffset ExpiresAtUtc { get; }
    }

    internal interface INeutralConsentFactsAuthority
    {
        bool TryResolve(
            string receiptId,
            out TrustedNeutralPermissionFacts facts,
            out string reasonCode);
    }

    internal sealed class TrustedActionResultFacts
    {
        internal TrustedActionResultFacts(
            string receiptId,
            string actionId,
            string sessionId,
            string saveBindingId,
            string loreViewId,
            ActionOutcome outcome)
        {
            WingsProtocolValue.RequireOpaqueId(
                receiptId,
                nameof(receiptId));
            WingsProtocolValue.RequireOpaqueId(
                actionId,
                nameof(actionId));
            WingsProtocolValue.RequireOpaqueId(
                sessionId,
                nameof(sessionId));
            WingsProtocolValue.RequireOpaqueId(
                saveBindingId,
                nameof(saveBindingId));
            WingsProtocolValue.RequireOpaqueId(
                loreViewId,
                nameof(loreViewId));
            if (!Enum.IsDefined(outcome))
                throw new ArgumentOutOfRangeException(nameof(outcome));

            ReceiptId = receiptId;
            ActionId = actionId;
            SessionId = sessionId;
            SaveBindingId = saveBindingId;
            LoreViewId = loreViewId;
            Outcome = outcome;
        }

        public string ReceiptId { get; }
        public string ActionId { get; }
        public string SessionId { get; }
        public string SaveBindingId { get; }
        public string LoreViewId { get; }
        public ActionOutcome Outcome { get; }
    }

    internal interface ITrustedActionResultAuthority
    {
        bool TryResolve(
            string receiptId,
            out TrustedActionResultFacts facts,
            out string reasonCode);
    }

    internal sealed class WingsOutputCheckContext
    {
        public WingsOutputCheckContext(
            string sessionId,
            LoreView loreView,
            WingsGuidanceDomain? guidanceDomain,
            string guidanceKey,
            DateTimeOffset nowUtc,
            TrustedNeutralPermissionFacts permissionFacts = null,
            TrustedActionResultFacts actionResultFacts = null)
        {
            WingsProtocolValue.RequireOpaqueId(
                sessionId,
                nameof(sessionId));
            LoreView = loreView
                ?? throw new ArgumentNullException(nameof(loreView));
            if (guidanceDomain.HasValue
                && !Enum.IsDefined(guidanceDomain.Value))
            {
                throw new ArgumentOutOfRangeException(
                    nameof(guidanceDomain));
            }
            if (guidanceKey != null)
            {
                WingsProtocolValue.RequireStableKey(
                    guidanceKey,
                    nameof(guidanceKey));
            }

            SessionId = sessionId;
            GuidanceDomain = guidanceDomain;
            GuidanceKey = guidanceKey;
            NowUtc = nowUtc;
            PermissionFacts = permissionFacts;
            ActionResultFacts = actionResultFacts;
        }

        public string SessionId { get; }
        public LoreView LoreView { get; }
        public WingsGuidanceDomain? GuidanceDomain { get; }
        public string GuidanceKey { get; }
        public DateTimeOffset NowUtc { get; }
        public TrustedNeutralPermissionFacts PermissionFacts { get; }
        public TrustedActionResultFacts ActionResultFacts { get; }
    }

    internal sealed class WingsCheckedOutput
    {
        private WingsCheckedOutput(
            bool accepted,
            string reasonCode,
            string text,
            WingsOutputPurpose purpose,
            IEnumerable<LoreFactProvenance> provenance)
        {
            Accepted = accepted;
            ReasonCode = reasonCode;
            Text = text;
            Purpose = purpose;
            Provenance = Array.AsReadOnly(
                (provenance ?? Array.Empty<LoreFactProvenance>())
                    .ToArray());
        }

        public bool Accepted { get; }
        public string ReasonCode { get; }
        public string Text { get; }
        public WingsOutputPurpose Purpose { get; }
        public ReadOnlyCollection<LoreFactProvenance> Provenance
        {
            get;
        }

        public static WingsCheckedOutput Accept(
            WingsDraftOutput draft,
            IEnumerable<LoreFactProvenance> provenance)
        {
            return new WingsCheckedOutput(
                true,
                "accepted",
                draft.Text,
                draft.Purpose,
                provenance);
        }

        public static WingsCheckedOutput Reject(
            WingsDraftOutput draft,
            string reasonCode)
        {
            return new WingsCheckedOutput(
                false,
                reasonCode,
                string.Empty,
                draft?.Purpose ?? WingsOutputPurpose.SafeFallback,
                Array.Empty<LoreFactProvenance>());
        }
    }

    internal sealed class WingsOutputChecker
    {
        public WingsCheckedOutput Check(
            WingsDraftOutput draft,
            WingsOutputCheckContext context)
        {
            if (draft == null)
                throw new ArgumentNullException(nameof(draft));
            if (context == null)
                throw new ArgumentNullException(nameof(context));
            LoreView view = context.LoreView;
            if (!string.Equals(
                    draft.SaveBindingId,
                    view.Progress.SaveBindingId,
                    StringComparison.Ordinal)
                || !string.Equals(
                    draft.LoreViewId,
                    view.LoreViewId,
                    StringComparison.Ordinal))
            {
                return WingsCheckedOutput.Reject(
                    draft,
                    "lore_view_binding_mismatch");
            }
            if (HasDuplicateClaims(draft.FactualClaims)
                || HasDuplicateClaims(draft.PresentationCues))
            {
                return WingsCheckedOutput.Reject(
                    draft,
                    "duplicate_fact_claim");
            }

            var provenance = new List<LoreFactProvenance>();
            foreach (WingsFactClaim claim in draft.FactualClaims)
            {
                if (!TryValidateClaim(
                        claim,
                        view,
                        LoreCanonClass.GameplayPublic,
                        out LoreFact fact,
                        out string reason))
                {
                    return WingsCheckedOutput.Reject(draft, reason);
                }
                provenance.Add(ToProvenance(fact));
            }
            foreach (WingsFactClaim cue in draft.PresentationCues)
            {
                if (!TryValidateClaim(
                        cue,
                        view,
                        LoreCanonClass.PresentationCue,
                        out LoreFact fact,
                        out string reason))
                {
                    return WingsCheckedOutput.Reject(draft, reason);
                }
                provenance.Add(ToProvenance(fact));
            }

            string shapeReason = ValidatePurposeShape(draft, context);
            if (shapeReason != null)
                return WingsCheckedOutput.Reject(draft, shapeReason);

            if (draft.Purpose == WingsOutputPurpose.Guidance)
            {
                foreach (WingsFactClaim claim in draft.FactualClaims)
                {
                    LoreFact fact = view.Facts[claim.FactId];
                    if (!fact.GuidanceDomains.Contains(
                            context.GuidanceDomain.Value)
                        || !fact.GuidanceKeys.Contains(
                            context.GuidanceKey,
                            StringComparer.Ordinal))
                    {
                        return WingsCheckedOutput.Reject(
                            draft,
                            "fact_outside_requested_guidance");
                    }
                }
            }
            if (draft.Purpose
                == WingsOutputPurpose.AuthorizationExplanation)
            {
                foreach (WingsFactClaim cue
                    in draft.PresentationCues)
                {
                    if (!view.Facts[cue.FactId]
                        .GuidanceKeys.Contains(
                            "cue.permission",
                            StringComparer.Ordinal))
                    {
                        return WingsCheckedOutput.Reject(
                            draft,
                            "presentation_cue_outside_authorization");
                    }
                }
            }

            string expected = WingsCanonicalOutputRenderer.Render(
                draft,
                context);
            if (!string.Equals(
                    draft.Text,
                    expected,
                    StringComparison.Ordinal))
            {
                return WingsCheckedOutput.Reject(
                    draft,
                    "noncanonical_or_ungrounded_text");
            }
            return WingsCheckedOutput.Accept(draft, provenance);
        }

        private static string ValidatePurposeShape(
            WingsDraftOutput draft,
            WingsOutputCheckContext context)
        {
            switch (draft.Purpose)
            {
                case WingsOutputPurpose.Guidance:
                    if (!context.GuidanceDomain.HasValue
                        || context.GuidanceKey == null
                        || draft.FactualClaims.Count == 0
                        || draft.PresentationCues.Count != 0
                        || draft.NeutralPermissionReceiptId != null
                        || draft.ActionReceiptId != null
                        || draft.FallbackReason.HasValue)
                    {
                        return "guidance_output_shape_invalid";
                    }
                    return null;

                case WingsOutputPurpose.AuthorizationExplanation:
                    if (draft.FactualClaims.Count != 0
                        || draft.ActionReceiptId != null
                        || draft.FallbackReason.HasValue
                        || context.PermissionFacts == null
                        || !string.Equals(
                            draft.NeutralPermissionReceiptId,
                            context.PermissionFacts.ReceiptId,
                            StringComparison.Ordinal))
                    {
                        return "authorization_output_shape_invalid";
                    }
                    if (!MatchesBinding(
                            context.PermissionFacts.SessionId,
                            context.PermissionFacts.SaveBindingId,
                            context.PermissionFacts.LoreViewId,
                            context)
                        || context.NowUtc
                            < context.PermissionFacts.IssuedAtUtc
                        || context.NowUtc
                            >= context.PermissionFacts.ExpiresAtUtc)
                    {
                        return "permission_facts_invalid_or_expired";
                    }
                    return null;

                case WingsOutputPurpose.ActionResult:
                    if (draft.FactualClaims.Count != 0
                        || draft.PresentationCues.Count != 0
                        || draft.NeutralPermissionReceiptId != null
                        || draft.FallbackReason.HasValue
                        || context.ActionResultFacts == null
                        || !string.Equals(
                            draft.ActionReceiptId,
                            context.ActionResultFacts.ReceiptId,
                            StringComparison.Ordinal))
                    {
                        return "action_result_output_shape_invalid";
                    }
                    return MatchesBinding(
                        context.ActionResultFacts.SessionId,
                        context.ActionResultFacts.SaveBindingId,
                        context.ActionResultFacts.LoreViewId,
                        context)
                            ? null
                            : "action_result_binding_mismatch";

                case WingsOutputPurpose.SafeFallback:
                    return draft.FactualClaims.Count == 0
                        && draft.PresentationCues.Count == 0
                        && draft.NeutralPermissionReceiptId == null
                        && draft.ActionReceiptId == null
                        && draft.FallbackReason.HasValue
                            ? null
                            : "fallback_output_shape_invalid";

                default:
                    return "output_purpose_unknown";
            }
        }

        private static bool MatchesBinding(
            string sessionId,
            string saveBindingId,
            string loreViewId,
            WingsOutputCheckContext context)
        {
            return string.Equals(
                    sessionId,
                    context.SessionId,
                    StringComparison.Ordinal)
                && string.Equals(
                    saveBindingId,
                    context.LoreView.Progress.SaveBindingId,
                    StringComparison.Ordinal)
                && string.Equals(
                    loreViewId,
                    context.LoreView.LoreViewId,
                    StringComparison.Ordinal);
        }

        private static bool TryValidateClaim(
            WingsFactClaim claim,
            LoreView view,
            LoreCanonClass expectedClass,
            out LoreFact fact,
            out string reasonCode)
        {
            if (!view.Facts.TryGetValue(claim.FactId, out fact))
            {
                reasonCode = "fact_not_in_lore_view";
                return false;
            }
            if (!string.Equals(
                    claim.SourceRevision,
                    fact.SourceRevision,
                    StringComparison.Ordinal))
            {
                reasonCode = "fact_source_revision_mismatch";
                return false;
            }
            if (fact.CanonClass != expectedClass)
            {
                reasonCode = "fact_canon_class_mismatch";
                return false;
            }
            reasonCode = null;
            return true;
        }

        private static bool HasDuplicateClaims(
            IEnumerable<WingsFactClaim> claims)
        {
            var seen = new HashSet<string>(StringComparer.Ordinal);
            return claims.Any(claim => !seen.Add(claim.FactId));
        }

        private static LoreFactProvenance ToProvenance(LoreFact fact)
        {
            return new LoreFactProvenance(
                fact.FactId,
                fact.SourceAuthority,
                fact.SourceRevision);
        }
    }

    internal static class WingsCanonicalOutputRenderer
    {
        public static string Render(
            WingsDraftOutput draft,
            WingsOutputCheckContext context)
        {
            switch (draft.Purpose)
            {
                case WingsOutputPurpose.Guidance:
                    return string.Join(
                        "\n",
                        draft.FactualClaims.Select(
                            claim => context.LoreView
                                .Facts[claim.FactId]
                                .Statement));

                case WingsOutputPurpose.AuthorizationExplanation:
                    TrustedNeutralPermissionFacts permission =
                        context.PermissionFacts;
                    string cueText = string.Join(
                        "\n",
                        draft.PresentationCues.Select(
                            cue => context.LoreView
                                .Facts[cue.FactId]
                                .Statement));
                    string retention = permission.RetentionMode switch
                    {
                        NeutralRetentionMode.None => "不保留",
                        NeutralRetentionMode.SessionOnly =>
                            "仅本次会话",
                        _ => throw new InvalidOperationException(
                            "Unknown neutral retention mode.")
                    };
                    string authorization =
                        "授权事实（以 Launcher 中性界面为准）："
                        + permission.NeutralDisplayName
                        + "；范围："
                        + string.Join("、", permission.GrantedScopes)
                        + "；保留："
                        + retention
                        + "；到期："
                        + permission.ExpiresAtUtc
                            .ToUniversalTime()
                            .ToString("O")
                        + "。";
                    return cueText.Length == 0
                        ? authorization
                        : cueText + "\n" + authorization;

                case WingsOutputPurpose.ActionResult:
                    return context.ActionResultFacts.Outcome switch
                    {
                        ActionOutcome.Rejected =>
                            "执行结果：请求已拒绝；没有执行输入，也不能宣称状态改变。",
                        ActionOutcome.InputDispatched =>
                            "执行结果：输入已发送；尚未观察到效果。",
                        ActionOutcome.EffectObserved =>
                            "执行结果：已观察到效果；这不等同于领域提交成功。",
                        ActionOutcome.DomainCommitted =>
                            "执行结果：领域权威已确认提交成功。",
                        ActionOutcome.Unknown =>
                            "执行结果：状态未知；需要重新观察或对账，不能自动重试。",
                        _ => throw new InvalidOperationException(
                            "Unknown action outcome.")
                    };

                case WingsOutputPurpose.SafeFallback:
                    return draft.FallbackReason.Value switch
                    {
                        WingsFallbackReason.NoEligibleFacts =>
                            "当前存档进度没有可公开的离线指导事实。",
                        WingsFallbackReason.ConsentFactsUnavailable =>
                            "Launcher 尚未提供可验证的中性授权事实。",
                        WingsFallbackReason.ActionResultUnavailable =>
                            "Launcher 尚未提供可验证的动作结果。",
                        WingsFallbackReason.CloudNotAuthorized =>
                            "云端传输未获独立授权，已使用离线指导。",
                        WingsFallbackReason.CloudProviderFailed =>
                            "云端服务不可用，已无惩罚地回退到离线指导。",
                        WingsFallbackReason.CloudOutputRejected =>
                            "云端输出未通过事实检查，已无惩罚地回退到离线指导。",
                        _ => throw new InvalidOperationException(
                            "Unknown fallback reason.")
                    };

                default:
                    throw new InvalidOperationException(
                        "Unknown output purpose.");
            }
        }
    }
}
