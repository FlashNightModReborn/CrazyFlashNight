using System;
using System.Collections.Generic;
using System.Collections.ObjectModel;
using System.Linq;
using System.Text.Json;
using System.Threading;
using System.Threading.Tasks;

namespace CF7Launcher.AgentRuntime.Wings
{
    internal sealed class TrustedDataEgressGrant
    {
        internal TrustedDataEgressGrant(
            string receiptId,
            string sessionId,
            string saveBindingId,
            string loreViewId,
            string providerId,
            IEnumerable<string> disclosedFieldKeys,
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
            WingsProtocolValue.RequireStableKey(
                providerId,
                nameof(providerId));
            if (issuedAtUtc >= expiresAtUtc)
                throw new ArgumentException(
                    "Data-egress expiry must be after issuance.",
                    nameof(expiresAtUtc));
            string[] suppliedFields =
                (disclosedFieldKeys ?? Array.Empty<string>())
                    .Select(field =>
                    {
                        WingsProtocolValue.RequireStableKey(
                            field,
                            nameof(disclosedFieldKeys));
                        return field;
                    })
                    .ToArray();
            if (suppliedFields
                    .Distinct(StringComparer.Ordinal)
                    .Count() != suppliedFields.Length)
            {
                throw new ArgumentException(
                    "Data-egress fields must be unique.",
                    nameof(disclosedFieldKeys));
            }
            string[] fields = suppliedFields
                    .OrderBy(field => field, StringComparer.Ordinal)
                    .ToArray();
            if (fields.Length == 0 || fields.Length > 16)
                throw new ArgumentException(
                    "Data-egress facts need 1-16 exact fields.",
                    nameof(disclosedFieldKeys));

            ReceiptId = receiptId;
            SessionId = sessionId;
            SaveBindingId = saveBindingId;
            LoreViewId = loreViewId;
            ProviderId = providerId;
            DisclosedFieldKeys = Array.AsReadOnly(fields);
            IssuedAtUtc = issuedAtUtc;
            ExpiresAtUtc = expiresAtUtc;
        }

        public string ReceiptId { get; }
        public string SessionId { get; }
        public string SaveBindingId { get; }
        public string LoreViewId { get; }
        public string ProviderId { get; }
        public ReadOnlyCollection<string> DisclosedFieldKeys { get; }
        public DateTimeOffset IssuedAtUtc { get; }
        public DateTimeOffset ExpiresAtUtc { get; }
    }

    internal interface IDataEgressGrantAuthority
    {
        bool TryResolve(
            string receiptId,
            out TrustedDataEgressGrant grant,
            out string reasonCode);
    }

    internal sealed class WingsCloudProviderRequest
    {
        internal WingsCloudProviderRequest(
            IReadOnlyDictionary<string, string> disclosedFields)
        {
            var frozen = new SortedDictionary<string, string>(
                StringComparer.Ordinal);
            foreach (KeyValuePair<string, string> field
                in disclosedFields)
            {
                WingsProtocolValue.RequireStableKey(
                    field.Key,
                    nameof(disclosedFields));
                if (field.Value == null || field.Value.Length > 32768)
                    throw new ArgumentException(
                        "A disclosed cloud field exceeds its bound.",
                        nameof(disclosedFields));
                frozen.Add(field.Key, field.Value);
            }
            DisclosedFields =
                new ReadOnlyDictionary<string, string>(frozen);
        }

        /// <summary>
        /// This dictionary is the provider's entire request surface. Host
        /// authority binding details not listed here are not passed through.
        /// </summary>
        public ReadOnlyDictionary<string, string> DisclosedFields
        {
            get;
        }
    }

    internal interface IWingsCloudProvider
    {
        string ProviderId { get; }

        Task<WingsDraftOutput> GenerateAsync(
            WingsCloudProviderRequest request,
            CancellationToken cancellationToken);
    }

    internal sealed class OptionalCloudWingsBackend
    {
        public const string LoreBindingField = "lore.binding";
        public const string LoreFactSetField = "lore.fact-set";
        public const string GuidanceIntentField = "guidance.intent";
        public const string VisibleContextField = "visible.context";

        private static readonly HashSet<string> AllowedFields =
            new HashSet<string>(
                new[]
                {
                    LoreBindingField,
                    LoreFactSetField,
                    GuidanceIntentField,
                    VisibleContextField
                },
                StringComparer.Ordinal);

        private readonly IWingsReferenceBackend _offline;
        private readonly IWingsCloudProvider _provider;
        private readonly IDataEgressGrantAuthority _grantAuthority;
        private readonly WingsOutputChecker _checker;
        private readonly LoreModelInputBuilder _inputBuilder;
        private readonly Func<DateTimeOffset> _utcNow;

        public OptionalCloudWingsBackend(
            IWingsReferenceBackend offline,
            IWingsCloudProvider provider,
            IDataEgressGrantAuthority grantAuthority,
            WingsOutputChecker checker = null,
            LoreModelInputBuilder inputBuilder = null,
            Func<DateTimeOffset> utcNow = null)
        {
            _offline = offline
                ?? throw new ArgumentNullException(nameof(offline));
            _provider = provider
                ?? throw new ArgumentNullException(nameof(provider));
            _grantAuthority = grantAuthority
                ?? throw new ArgumentNullException(
                    nameof(grantAuthority));
            WingsProtocolValue.RequireStableKey(
                _provider.ProviderId,
                nameof(provider));
            _checker = checker ?? new WingsOutputChecker();
            _inputBuilder =
                inputBuilder ?? new LoreModelInputBuilder();
            _utcNow = utcNow ?? (() => DateTimeOffset.UtcNow);
        }

        public async Task<WingsBackendResult> GenerateAsync(
            WingsGuidanceRequest request,
            string dataEgressGrantReceiptId,
            IEnumerable<string> disclosedFieldKeys,
            CancellationToken cancellationToken = default)
        {
            if (request == null)
                throw new ArgumentNullException(nameof(request));
            if (request.Kind != WingsRequestKind.Guidance)
                throw new ArgumentException(
                    "Cloud v1 only wraps guidance requests.",
                    nameof(request));
            if (!TryValidateFields(
                    disclosedFieldKeys,
                    out string[] fields))
            {
                return OfflineFallback(
                    request,
                    "cloud_disclosure_fields_invalid");
            }
            if (!IsOpaqueId(dataEgressGrantReceiptId)
                || !_grantAuthority.TryResolve(
                    dataEgressGrantReceiptId,
                    out TrustedDataEgressGrant grant,
                    out _)
                || !GrantMatches(
                    grant,
                    dataEgressGrantReceiptId,
                    request,
                    fields,
                    _utcNow()))
            {
                return OfflineFallback(
                    request,
                    "cloud_data_egress_not_authorized");
            }

            LoreModelInput modelInput = _inputBuilder.Build(
                request.LoreView,
                request.Domain.Value,
                request.GuidanceKey,
                request.VisibleContext);
            WingsCloudProviderRequest providerRequest =
                BuildProviderRequest(modelInput, fields);
            WingsDraftOutput cloudDraft;
            try
            {
                cloudDraft = await _provider.GenerateAsync(
                    providerRequest,
                    cancellationToken).ConfigureAwait(false);
            }
            catch (OperationCanceledException)
                when (cancellationToken.IsCancellationRequested)
            {
                throw;
            }
            catch
            {
                return OfflineFallback(
                    request,
                    "cloud_provider_failed",
                    fields);
            }

            if (cloudDraft == null
                || cloudDraft.Purpose
                    != WingsOutputPurpose.Guidance)
            {
                return OfflineFallback(
                    request,
                    "cloud_output_rejected",
                    fields);
            }
            var context = new WingsOutputCheckContext(
                request.SessionId,
                request.LoreView,
                request.Domain,
                request.GuidanceKey,
                _utcNow());
            WingsCheckedOutput checkedOutput =
                _checker.Check(cloudDraft, context);
            if (!checkedOutput.Accepted)
            {
                return OfflineFallback(
                    request,
                    "cloud_output_rejected:"
                    + checkedOutput.ReasonCode,
                    fields);
            }

            return new WingsBackendResult(
                checkedOutput,
                WingsBackendSource.CloudProvider,
                _provider.ProviderId,
                fields);
        }

        private WingsBackendResult OfflineFallback(
            WingsGuidanceRequest request,
            string reasonCode,
            IEnumerable<string> disclosedFields = null)
        {
            WingsBackendResult offline = _offline.Generate(request);
            return new WingsBackendResult(
                offline.Output,
                WingsBackendSource.OfflineReference,
                disclosedFields == null
                    ? null
                    : _provider.ProviderId,
                disclosedFields,
                reasonCode);
        }

        private static bool TryValidateFields(
            IEnumerable<string> fields,
            out string[] result)
        {
            try
            {
                string[] supplied =
                    (fields ?? Array.Empty<string>())
                        .Select(field =>
                        {
                            WingsProtocolValue.RequireStableKey(
                                field,
                                nameof(fields));
                            return field;
                        })
                        .ToArray();
                if (supplied.Distinct(StringComparer.Ordinal).Count()
                    != supplied.Length)
                {
                    result = Array.Empty<string>();
                    return false;
                }
                result = supplied.OrderBy(
                            field => field,
                            StringComparer.Ordinal)
                        .ToArray();
            }
            catch (ArgumentException)
            {
                result = Array.Empty<string>();
                return false;
            }
            if (result.Any(field => !AllowedFields.Contains(field))
                || !result.Contains(
                    LoreBindingField,
                    StringComparer.Ordinal)
                || !result.Contains(
                    LoreFactSetField,
                    StringComparer.Ordinal)
                || !result.Contains(
                    GuidanceIntentField,
                    StringComparer.Ordinal))
            {
                result = Array.Empty<string>();
                return false;
            }
            return true;
        }

        private static bool IsOpaqueId(string value)
        {
            try
            {
                WingsProtocolValue.RequireOpaqueId(
                    value,
                    nameof(value));
                return true;
            }
            catch (ArgumentException)
            {
                return false;
            }
        }

        private bool GrantMatches(
            TrustedDataEgressGrant grant,
            string requestedReceiptId,
            WingsGuidanceRequest request,
            IEnumerable<string> fields,
            DateTimeOffset now)
        {
            return grant != null
                && string.Equals(
                    grant.ReceiptId,
                    requestedReceiptId,
                    StringComparison.Ordinal)
                && string.Equals(
                    grant.ProviderId,
                    _provider.ProviderId,
                    StringComparison.Ordinal)
                && string.Equals(
                    grant.SessionId,
                    request.SessionId,
                    StringComparison.Ordinal)
                && string.Equals(
                    grant.SaveBindingId,
                    request.LoreView.Progress.SaveBindingId,
                    StringComparison.Ordinal)
                && string.Equals(
                    grant.LoreViewId,
                    request.LoreView.LoreViewId,
                    StringComparison.Ordinal)
                && now >= grant.IssuedAtUtc
                && now < grant.ExpiresAtUtc
                && grant.DisclosedFieldKeys.ToHashSet(
                    StringComparer.Ordinal).SetEquals(fields);
        }

        private static WingsCloudProviderRequest BuildProviderRequest(
            LoreModelInput input,
            IEnumerable<string> fields)
        {
            var payload = new Dictionary<string, string>(
                StringComparer.Ordinal);
            foreach (string field in fields)
            {
                payload.Add(
                    field,
                    field switch
                    {
                        LoreBindingField => JsonSerializer.Serialize(
                            new
                            {
                                input.SaveBindingId,
                                input.LoreViewId,
                                input.FactSetHash
                            }),
                        LoreFactSetField => JsonSerializer.Serialize(
                            input.Facts.Select(fact => new
                            {
                                fact.FactId,
                                fact.SourceRevision,
                                fact.Statement
                            })),
                        GuidanceIntentField =>
                            input.Domain.ToString().ToLowerInvariant()
                            + ":"
                            + input.GuidanceKey,
                        VisibleContextField =>
                            input.VisibleContext.ToCanonicalJson(),
                        _ => throw new InvalidOperationException(
                            "Unknown cloud disclosure field.")
                    });
            }
            return new WingsCloudProviderRequest(payload);
        }
    }
}
