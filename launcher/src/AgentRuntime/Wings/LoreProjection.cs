using System;
using System.Collections.Generic;
using System.Collections.ObjectModel;
using System.IO;
using System.Linq;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;

namespace CF7Launcher.AgentRuntime.Wings
{
    internal sealed class LoreFactProvenance
    {
        public LoreFactProvenance(
            string factId,
            string sourceAuthority,
            string sourceRevision)
        {
            FactId = factId;
            SourceAuthority = sourceAuthority;
            SourceRevision = sourceRevision;
        }

        public string FactId { get; }
        public string SourceAuthority { get; }
        public string SourceRevision { get; }
    }

    internal sealed class LoreView
    {
        public LoreView(
            string loreViewId,
            string factSetHash,
            string catalogRevision,
            LoreProgressSnapshot progress,
            bool publicCompanionEligible,
            IEnumerable<LoreFact> facts)
        {
            WingsProtocolValue.RequireOpaqueId(
                loreViewId,
                nameof(loreViewId));
            WingsProtocolValue.RequireSha256(
                factSetHash,
                nameof(factSetHash));
            Progress = progress
                ?? throw new ArgumentNullException(nameof(progress));

            var factMap = new SortedDictionary<string, LoreFact>(
                StringComparer.Ordinal);
            foreach (LoreFact fact in facts ?? Array.Empty<LoreFact>())
            {
                if (fact == null || !factMap.TryAdd(fact.FactId, fact))
                    throw new InvalidDataException(
                        "A lore view must contain unique facts.");
            }
            if (!publicCompanionEligible && factMap.Count != 0)
                throw new InvalidDataException(
                    "An ineligible lore view cannot expose facts.");

            LoreViewId = loreViewId;
            FactSetHash = factSetHash.ToUpperInvariant();
            CatalogRevision = catalogRevision;
            PublicCompanionEligible = publicCompanionEligible;
            Facts = new ReadOnlyDictionary<string, LoreFact>(factMap);
            Provenance = Array.AsReadOnly(
                factMap.Values
                    .Select(fact => new LoreFactProvenance(
                        fact.FactId,
                        fact.SourceAuthority,
                        fact.SourceRevision))
                    .ToArray());
        }

        public string LoreViewId { get; }
        public string FactSetHash { get; }
        public string CatalogRevision { get; }
        public LoreProgressSnapshot Progress { get; }
        public bool PublicCompanionEligible { get; }
        public ReadOnlyDictionary<string, LoreFact> Facts { get; }
        public ReadOnlyCollection<LoreFactProvenance> Provenance
        {
            get;
        }
    }

    internal interface ILoreProjection
    {
        LoreView Project(
            LoreCatalog catalog,
            LoreProgressSnapshot progress);
    }

    internal sealed class LoreProjectionService : ILoreProjection
    {
        public LoreView Project(
            LoreCatalog catalog,
            LoreProgressSnapshot progress)
        {
            if (catalog == null)
                throw new ArgumentNullException(nameof(catalog));
            if (progress == null)
                throw new ArgumentNullException(nameof(progress));

            bool eligible = catalog.PublicStoryPhaseIds.Contains(
                progress.StoryPhaseId,
                StringComparer.Ordinal);
            LoreFact[] facts = eligible
                ? catalog.Facts.Values
                    .Where(fact => fact.RevealPredicate.Matches(
                        progress,
                        fact.FactId))
                    .OrderBy(fact => fact.FactId, StringComparer.Ordinal)
                    .ToArray()
                : Array.Empty<LoreFact>();

            string factSetHash = ComputeFactSetHash(facts);
            string viewId = ComputeLoreViewId(
                catalog,
                progress,
                eligible,
                facts,
                factSetHash);
            return new LoreView(
                viewId,
                factSetHash,
                catalog.CatalogRevision,
                progress,
                eligible,
                facts);
        }

        private static string ComputeFactSetHash(
            IEnumerable<LoreFact> facts)
        {
            using var canonical = new CanonicalHashWriter();
            foreach (LoreFact fact in facts)
            {
                canonical.Write(fact.FactId);
                canonical.Write(fact.SourceAuthority);
                canonical.Write(fact.SourceRevision);
            }
            return canonical.GetHexDigest();
        }

        private static string ComputeLoreViewId(
            LoreCatalog catalog,
            LoreProgressSnapshot progress,
            bool eligible,
            IEnumerable<LoreFact> facts,
            string factSetHash)
        {
            using var canonical = new CanonicalHashWriter();
            canonical.Write("cf7.wings.lore-view.v1");
            canonical.Write(catalog.CatalogRevision);
            canonical.Write(progress.SaveBindingId);
            canonical.Write(progress.SaveSignature);
            canonical.Write(progress.StoryPhaseId);
            canonical.Write(progress.ProgressRevision);
            canonical.Write(progress.SaveClass.ToString());
            canonical.Write(eligible ? "eligible" : "ineligible");
            canonical.Write(factSetHash);
            foreach (string flag in progress.ProgressFlags)
                canonical.Write("flag:" + flag);
            foreach (KeyValuePair<string, string> branch
                in progress.BranchSelections)
            {
                canonical.Write(
                    "branch:" + branch.Key + "=" + branch.Value);
            }
            foreach (string factId in progress.RevealedFactIds)
                canonical.Write("reveal:" + factId);
            foreach (LoreFact fact in facts)
                canonical.Write("fact:" + fact.FactId);
            return canonical.GetBase64UrlDigest();
        }

        private sealed class CanonicalHashWriter : IDisposable
        {
            private readonly IncrementalHash _hash =
                IncrementalHash.CreateHash(HashAlgorithmName.SHA256);
            private bool _finalized;

            public void Write(string value)
            {
                if (_finalized)
                    throw new InvalidOperationException(
                        "Hash writer is finalized.");
                byte[] payload = Encoding.UTF8.GetBytes(
                    value ?? string.Empty);
                byte[] length = BitConverter.GetBytes(payload.Length);
                if (BitConverter.IsLittleEndian)
                    Array.Reverse(length);
                _hash.AppendData(length);
                _hash.AppendData(payload);
            }

            public string GetHexDigest()
            {
                return Convert.ToHexString(FinalizeDigest());
            }

            public string GetBase64UrlDigest()
            {
                return Convert.ToBase64String(FinalizeDigest())
                    .TrimEnd('=')
                    .Replace('+', '-')
                    .Replace('/', '_');
            }

            private byte[] FinalizeDigest()
            {
                if (_finalized)
                    throw new InvalidOperationException(
                        "Hash writer is finalized.");
                _finalized = true;
                return _hash.GetHashAndReset();
            }

            public void Dispose()
            {
                _hash.Dispose();
            }
        }
    }

    internal sealed class LoreModelFact
    {
        public LoreModelFact(LoreFact fact)
        {
            FactId = fact.FactId;
            SourceRevision = fact.SourceRevision;
            Statement = fact.Statement;
        }

        public string FactId { get; }
        public string SourceRevision { get; }
        public string Statement { get; }
    }

    internal sealed class WingsVisibleGuidanceContext
    {
        private static readonly IReadOnlyDictionary<
            WingsGuidanceDomain,
            HashSet<string>> AllowedFields =
                new Dictionary<WingsGuidanceDomain, HashSet<string>>
                {
                    [WingsGuidanceDomain.Task] = Set(
                        "task.visible-id",
                        "task.visible-state"),
                    [WingsGuidanceDomain.Equipment] = Set(
                        "equipment.visible-item-id",
                        "equipment.visible-slot"),
                    [WingsGuidanceDomain.Route] = Set(
                        "route.visible-location-id",
                        "route.visible-destination-id"),
                    [WingsGuidanceDomain.Ui] = Set(
                        "ui.visible-panel-id",
                        "ui.visible-focus-id")
                };

        public WingsVisibleGuidanceContext(
            WingsGuidanceDomain domain,
            string contextRevision,
            IReadOnlyDictionary<string, string> fields)
        {
            if (!Enum.IsDefined(domain))
                throw new ArgumentOutOfRangeException(nameof(domain));
            WingsProtocolValue.RequireStableKey(
                contextRevision,
                nameof(contextRevision));
            var frozen = new SortedDictionary<string, string>(
                StringComparer.Ordinal);
            foreach (KeyValuePair<string, string> field
                in fields ?? new Dictionary<string, string>())
            {
                WingsProtocolValue.RequireStableKey(
                    field.Key,
                    nameof(fields));
                if (!AllowedFields[domain].Contains(field.Key))
                {
                    throw new ArgumentException(
                        "Visible context contains an unregistered field.",
                        nameof(fields));
                }
                WingsProtocolValue.RequireText(
                    field.Value,
                    256,
                    nameof(fields));
                if (field.Value.Any(char.IsControl))
                {
                    throw new ArgumentException(
                        "Visible context contains control characters.",
                        nameof(fields));
                }
                frozen.Add(field.Key, field.Value);
            }
            if (frozen.Count > 8)
                throw new ArgumentException(
                    "Visible context exceeds the v1 field bound.",
                    nameof(fields));

            Domain = domain;
            ContextRevision = contextRevision;
            Fields = new ReadOnlyDictionary<string, string>(frozen);
        }

        public WingsGuidanceDomain Domain { get; }
        public string ContextRevision { get; }
        public ReadOnlyDictionary<string, string> Fields { get; }

        public string ToCanonicalJson()
        {
            return JsonSerializer.Serialize(
                new
                {
                    domain = Domain.ToString().ToLowerInvariant(),
                    contextRevision = ContextRevision,
                    fields = Fields
                });
        }

        public static WingsVisibleGuidanceContext Empty(
            WingsGuidanceDomain domain)
        {
            return new WingsVisibleGuidanceContext(
                domain,
                "context.empty.v1",
                null);
        }

        private static HashSet<string> Set(params string[] values)
        {
            return new HashSet<string>(
                values,
                StringComparer.Ordinal);
        }
    }

    internal sealed class LoreModelInput
    {
        public LoreModelInput(
            string saveBindingId,
            string loreViewId,
            string factSetHash,
            WingsGuidanceDomain domain,
            string guidanceKey,
            WingsVisibleGuidanceContext visibleContext,
            IEnumerable<LoreModelFact> facts)
        {
            SaveBindingId = saveBindingId;
            LoreViewId = loreViewId;
            FactSetHash = factSetHash;
            Domain = domain;
            GuidanceKey = guidanceKey;
            VisibleContext = visibleContext
                ?? throw new ArgumentNullException(
                    nameof(visibleContext));
            Facts = Array.AsReadOnly(
                (facts ?? Array.Empty<LoreModelFact>()).ToArray());
        }

        public string SaveBindingId { get; }
        public string LoreViewId { get; }
        public string FactSetHash { get; }
        public WingsGuidanceDomain Domain { get; }
        public string GuidanceKey { get; }
        public WingsVisibleGuidanceContext VisibleContext { get; }
        public ReadOnlyCollection<LoreModelFact> Facts { get; }
    }

    internal sealed class LoreRetriever
    {
        public ReadOnlyCollection<LoreFact> Retrieve(
            LoreView view,
            WingsGuidanceDomain domain,
            string guidanceKey)
        {
            if (view == null)
                throw new ArgumentNullException(nameof(view));
            if (!Enum.IsDefined(domain))
                throw new ArgumentOutOfRangeException(nameof(domain));
            WingsProtocolValue.RequireStableKey(
                guidanceKey,
                nameof(guidanceKey));
            if (!view.PublicCompanionEligible)
                return Array.AsReadOnly(Array.Empty<LoreFact>());

            return Array.AsReadOnly(
                view.Facts.Values
                    .Where(fact =>
                        fact.CanonClass
                            == LoreCanonClass.GameplayPublic
                        && fact.GuidanceDomains.Contains(domain)
                        && fact.GuidanceKeys.Contains(
                            guidanceKey,
                            StringComparer.Ordinal))
                    .OrderBy(fact => fact.FactId, StringComparer.Ordinal)
                    .ToArray());
        }
    }

    internal sealed class LoreModelInputBuilder
    {
        private readonly LoreRetriever _retriever;

        public LoreModelInputBuilder(LoreRetriever retriever = null)
        {
            _retriever = retriever ?? new LoreRetriever();
        }

        public LoreModelInput Build(
            LoreView view,
            WingsGuidanceDomain domain,
            string guidanceKey,
            WingsVisibleGuidanceContext visibleContext)
        {
            if (view == null)
                throw new ArgumentNullException(nameof(view));
            visibleContext ??=
                WingsVisibleGuidanceContext.Empty(domain);
            if (visibleContext.Domain != domain)
                throw new ArgumentException(
                    "Visible context domain does not match the intent.",
                    nameof(visibleContext));

            ReadOnlyCollection<LoreFact> facts =
                _retriever.Retrieve(view, domain, guidanceKey);
            return new LoreModelInput(
                view.Progress.SaveBindingId,
                view.LoreViewId,
                view.FactSetHash,
                domain,
                guidanceKey,
                visibleContext,
                facts.Select(fact => new LoreModelFact(fact)));
        }
    }

    internal sealed class LoreBoundCache<T>
    {
        private readonly object _sync = new object();
        private readonly int _capacity;
        private readonly Dictionary<string, T> _values =
            new Dictionary<string, T>(StringComparer.Ordinal);
        private readonly Queue<string> _insertionOrder =
            new Queue<string>();

        public LoreBoundCache(int capacity = 64)
        {
            if (capacity <= 0 || capacity > 1024)
                throw new ArgumentOutOfRangeException(nameof(capacity));
            _capacity = capacity;
        }

        public void Put(
            LoreView view,
            string cacheKey,
            T value)
        {
            if (view == null)
                throw new ArgumentNullException(nameof(view));
            WingsProtocolValue.RequireStableKey(
                cacheKey,
                nameof(cacheKey));
            string boundKey = Bind(view, cacheKey);
            lock (_sync)
            {
                if (!_values.ContainsKey(boundKey))
                    _insertionOrder.Enqueue(boundKey);
                _values[boundKey] = value;
                while (_values.Count > _capacity)
                {
                    string oldest = _insertionOrder.Dequeue();
                    _values.Remove(oldest);
                }
            }
        }

        public bool TryGet(
            LoreView view,
            string cacheKey,
            out T value)
        {
            if (view == null)
                throw new ArgumentNullException(nameof(view));
            WingsProtocolValue.RequireStableKey(
                cacheKey,
                nameof(cacheKey));
            lock (_sync)
            {
                return _values.TryGetValue(
                    Bind(view, cacheKey),
                    out value);
            }
        }

        private static string Bind(
            LoreView view,
            string cacheKey)
        {
            return view.Progress.SaveBindingId
                + "\n"
                + view.LoreViewId
                + "\n"
                + cacheKey;
        }
    }
}
