using System;
using System.Collections.Generic;
using System.Collections.ObjectModel;
using System.IO;
using System.Linq;
using System.Text;
using System.Text.Json;

namespace CF7Launcher.AgentRuntime.Wings
{
    internal enum WingsSaveClass
    {
        Legacy = 0,
        Standard = 1,
        NewGamePlus = 2,
        DeveloperUnlocked = 3
    }

    internal enum WingsGuidanceDomain
    {
        Task,
        Equipment,
        Route,
        Ui
    }

    internal enum LoreCanonClass
    {
        GameplayPublic,
        PresentationCue
    }

    internal sealed class LoreRevealPredicate
    {
        public LoreRevealPredicate(
            WingsSaveClass minimumSaveClass,
            IEnumerable<string> requiredProgressFlags,
            IEnumerable<string> forbiddenProgressFlags,
            IReadOnlyDictionary<string, string> branchEquals,
            bool requiresRevealGrant)
        {
            MinimumSaveClass = minimumSaveClass;
            RequiredProgressFlags = FreezeKeys(
                requiredProgressFlags,
                nameof(requiredProgressFlags));
            ForbiddenProgressFlags = FreezeKeys(
                forbiddenProgressFlags,
                nameof(forbiddenProgressFlags));
            if (RequiredProgressFlags.Intersect(
                    ForbiddenProgressFlags,
                    StringComparer.Ordinal).Any())
            {
                throw new InvalidDataException(
                    "A reveal predicate cannot require and forbid the same flag.");
            }
            BranchEquals = FreezeMap(branchEquals);
            RequiresRevealGrant = requiresRevealGrant;
        }

        public WingsSaveClass MinimumSaveClass { get; }
        public ReadOnlyCollection<string> RequiredProgressFlags { get; }
        public ReadOnlyCollection<string> ForbiddenProgressFlags { get; }
        public ReadOnlyDictionary<string, string> BranchEquals { get; }
        public bool RequiresRevealGrant { get; }

        public bool Matches(
            LoreProgressSnapshot progress,
            string factId)
        {
            if (progress.SaveClass < MinimumSaveClass)
                return false;
            if (RequiredProgressFlags.Any(flag =>
                    !progress.ProgressFlags.Contains(
                        flag,
                        StringComparer.Ordinal)))
            {
                return false;
            }
            if (ForbiddenProgressFlags.Any(flag =>
                    progress.ProgressFlags.Contains(
                        flag,
                        StringComparer.Ordinal)))
            {
                return false;
            }
            foreach (KeyValuePair<string, string> branch
                in BranchEquals)
            {
                if (!progress.BranchSelections.TryGetValue(
                        branch.Key,
                        out string selected)
                    || !string.Equals(
                        selected,
                        branch.Value,
                        StringComparison.Ordinal))
                {
                    return false;
                }
            }
            return !RequiresRevealGrant
                || progress.RevealedFactIds.Contains(
                    factId,
                    StringComparer.Ordinal);
        }

        private static ReadOnlyCollection<string> FreezeKeys(
            IEnumerable<string> values,
            string parameterName)
        {
            string[] result = (values ?? Array.Empty<string>())
                .Select(value =>
                {
                    WingsProtocolValue.RequireStableKey(
                        value,
                        parameterName);
                    return value;
                })
                .Distinct(StringComparer.Ordinal)
                .OrderBy(value => value, StringComparer.Ordinal)
                .ToArray();
            return Array.AsReadOnly(result);
        }

        private static ReadOnlyDictionary<string, string> FreezeMap(
            IReadOnlyDictionary<string, string> values)
        {
            var result = new SortedDictionary<string, string>(
                StringComparer.Ordinal);
            foreach (KeyValuePair<string, string> item
                in values ?? new Dictionary<string, string>())
            {
                WingsProtocolValue.RequireStableKey(
                    item.Key,
                    nameof(values));
                WingsProtocolValue.RequireStableKey(
                    item.Value,
                    nameof(values));
                if (!result.TryAdd(item.Key, item.Value))
                    throw new InvalidDataException(
                        "Duplicate branch predicate key.");
            }
            return new ReadOnlyDictionary<string, string>(result);
        }
    }

    internal sealed class LoreFact
    {
        public LoreFact(
            string factId,
            string sourceAuthority,
            LoreCanonClass canonClass,
            string sourceRevision,
            string statement,
            IEnumerable<WingsGuidanceDomain> guidanceDomains,
            IEnumerable<string> guidanceKeys,
            LoreRevealPredicate revealPredicate)
        {
            WingsProtocolValue.RequireStableKey(
                factId,
                nameof(factId));
            WingsProtocolValue.RequireText(
                sourceAuthority,
                256,
                nameof(sourceAuthority));
            WingsProtocolValue.RequireText(
                sourceRevision,
                128,
                nameof(sourceRevision));
            WingsProtocolValue.RequireText(
                statement,
                512,
                nameof(statement));
            if (sourceAuthority.Replace('\\', '/').StartsWith(
                    "docs/worldbuilding/",
                    StringComparison.OrdinalIgnoreCase))
            {
                throw new InvalidDataException(
                    "Runtime lore catalogs cannot source-scan worldbuilding documents.");
            }

            WingsGuidanceDomain[] domains =
                (guidanceDomains
                    ?? Array.Empty<WingsGuidanceDomain>())
                    .Distinct()
                    .OrderBy(value => value)
                    .ToArray();
            if (domains.Length == 0
                || domains.Any(value => !Enum.IsDefined(value)))
            {
                throw new InvalidDataException(
                    "Every lore fact needs a registered guidance domain.");
            }
            string[] keys = (guidanceKeys ?? Array.Empty<string>())
                .Select(value =>
                {
                    WingsProtocolValue.RequireStableKey(
                        value,
                        nameof(guidanceKeys));
                    return value;
                })
                .Distinct(StringComparer.Ordinal)
                .OrderBy(value => value, StringComparer.Ordinal)
                .ToArray();
            if (keys.Length == 0)
                throw new InvalidDataException(
                    "Every lore fact needs a registered guidance key.");

            FactId = factId;
            SourceAuthority = sourceAuthority;
            CanonClass = canonClass;
            SourceRevision = sourceRevision;
            Statement = statement;
            GuidanceDomains = Array.AsReadOnly(domains);
            GuidanceKeys = Array.AsReadOnly(keys);
            RevealPredicate = revealPredicate
                ?? throw new ArgumentNullException(
                    nameof(revealPredicate));
        }

        public string FactId { get; }
        public string SourceAuthority { get; }
        public LoreCanonClass CanonClass { get; }
        public string SourceRevision { get; }
        public string Statement { get; }
        public ReadOnlyCollection<WingsGuidanceDomain> GuidanceDomains
        {
            get;
        }
        public ReadOnlyCollection<string> GuidanceKeys { get; }
        public LoreRevealPredicate RevealPredicate { get; }
    }

    internal sealed class LoreCatalog
    {
        public LoreCatalog(
            string catalogRevision,
            IEnumerable<string> publicStoryPhaseIds,
            IEnumerable<LoreFact> facts)
        {
            WingsProtocolValue.RequireText(
                catalogRevision,
                128,
                nameof(catalogRevision));
            string[] phases =
                (publicStoryPhaseIds ?? Array.Empty<string>())
                    .Select(value =>
                    {
                        WingsProtocolValue.RequireOpaqueId(
                            value,
                            nameof(publicStoryPhaseIds));
                        return value;
                    })
                    .Distinct(StringComparer.Ordinal)
                    .OrderBy(value => value, StringComparer.Ordinal)
                    .ToArray();
            if (phases.Length == 0)
                throw new InvalidDataException(
                    "At least one public story phase is required.");

            var byId = new SortedDictionary<string, LoreFact>(
                StringComparer.Ordinal);
            foreach (LoreFact fact in facts ?? Array.Empty<LoreFact>())
            {
                if (fact == null || !byId.TryAdd(fact.FactId, fact))
                    throw new InvalidDataException(
                        "Lore fact IDs must be unique.");
            }
            if (byId.Count == 0 || byId.Count > 256)
                throw new InvalidDataException(
                    "The public companion catalog must contain 1-256 facts.");

            CatalogRevision = catalogRevision;
            PublicStoryPhaseIds = Array.AsReadOnly(phases);
            Facts = new ReadOnlyDictionary<string, LoreFact>(byId);
        }

        public string CatalogRevision { get; }
        public ReadOnlyCollection<string> PublicStoryPhaseIds { get; }
        public ReadOnlyDictionary<string, LoreFact> Facts { get; }
    }

    internal sealed class LoreProgressSnapshot
    {
        public LoreProgressSnapshot(
            string saveBindingId,
            string saveSignature,
            WingsSaveClass saveClass,
            string storyPhaseId,
            string progressRevision,
            IEnumerable<string> progressFlags,
            IReadOnlyDictionary<string, string> branchSelections,
            IEnumerable<string> revealedFactIds)
        {
            WingsProtocolValue.RequireOpaqueId(
                saveBindingId,
                nameof(saveBindingId));
            WingsProtocolValue.RequireSha256(
                saveSignature,
                nameof(saveSignature));
            if (!Enum.IsDefined(saveClass))
                throw new ArgumentOutOfRangeException(nameof(saveClass));
            WingsProtocolValue.RequireOpaqueId(
                storyPhaseId,
                nameof(storyPhaseId));
            WingsProtocolValue.RequireText(
                progressRevision,
                128,
                nameof(progressRevision));

            SaveBindingId = saveBindingId;
            SaveSignature = saveSignature.ToUpperInvariant();
            SaveClass = saveClass;
            StoryPhaseId = storyPhaseId;
            ProgressRevision = progressRevision;
            ProgressFlags = FreezeKeys(
                progressFlags,
                nameof(progressFlags));
            BranchSelections = FreezeMap(branchSelections);
            RevealedFactIds = FreezeKeys(
                revealedFactIds,
                nameof(revealedFactIds));
        }

        public string SaveBindingId { get; }
        public string SaveSignature { get; }
        public WingsSaveClass SaveClass { get; }
        public string StoryPhaseId { get; }
        public string ProgressRevision { get; }
        public ReadOnlyCollection<string> ProgressFlags { get; }
        public ReadOnlyDictionary<string, string> BranchSelections { get; }
        public ReadOnlyCollection<string> RevealedFactIds { get; }

        private static ReadOnlyCollection<string> FreezeKeys(
            IEnumerable<string> values,
            string parameterName)
        {
            return Array.AsReadOnly(
                (values ?? Array.Empty<string>())
                    .Select(value =>
                    {
                        WingsProtocolValue.RequireStableKey(
                            value,
                            parameterName);
                        return value;
                    })
                    .Distinct(StringComparer.Ordinal)
                    .OrderBy(value => value, StringComparer.Ordinal)
                    .ToArray());
        }

        private static ReadOnlyDictionary<string, string> FreezeMap(
            IReadOnlyDictionary<string, string> values)
        {
            var result = new SortedDictionary<string, string>(
                StringComparer.Ordinal);
            foreach (KeyValuePair<string, string> item
                in values ?? new Dictionary<string, string>())
            {
                WingsProtocolValue.RequireStableKey(
                    item.Key,
                    nameof(values));
                WingsProtocolValue.RequireStableKey(
                    item.Value,
                    nameof(values));
                if (!result.TryAdd(item.Key, item.Value))
                    throw new InvalidDataException(
                        "Branch selection keys must be unique.");
            }
            return new ReadOnlyDictionary<string, string>(result);
        }
    }

    internal static class LoreCatalogParser
    {
        private const int MaximumCatalogBytes = 1024 * 1024;
        private const int MaximumFixtureBytes = 64 * 1024;

        public static LoreCatalog Parse(ReadOnlySpan<byte> json)
        {
            if (json.Length == 0 || json.Length > MaximumCatalogBytes)
                throw new InvalidDataException(
                    "Lore catalog size is outside the v1 bound.");
            using JsonDocument document = ParseDocument(json);
            JsonElement root = document.RootElement;
            RequireObjectProperties(
                root,
                "schemaVersion",
                "catalogId",
                "catalogRevision",
                "publicStoryPhaseIds",
                "facts");
            if (ReadInt(root, "schemaVersion") != 1
                || ReadString(root, "catalogId") != "public-companion")
            {
                throw new InvalidDataException(
                    "Only public-companion catalog schema v1 is accepted.");
            }

            string revision = ReadString(root, "catalogRevision");
            string[] phases = ReadStringArray(
                root,
                "publicStoryPhaseIds");
            JsonElement factsValue = root.GetProperty("facts");
            if (factsValue.ValueKind != JsonValueKind.Array)
                throw new InvalidDataException("facts must be an array.");
            var facts = new List<LoreFact>();
            foreach (JsonElement fact in factsValue.EnumerateArray())
                facts.Add(ParseFact(fact));
            return new LoreCatalog(revision, phases, facts);
        }

        public static LoreProgressSnapshot ParseProgressFixture(
            ReadOnlySpan<byte> json)
        {
            if (json.Length == 0 || json.Length > MaximumFixtureBytes)
                throw new InvalidDataException(
                    "Lore fixture size is outside the v1 bound.");
            using JsonDocument document = ParseDocument(json);
            JsonElement root = document.RootElement;
            RequireObjectProperties(
                root,
                "saveBindingId",
                "saveSignature",
                "saveClass",
                "storyPhaseId",
                "progressRevision",
                "progressFlags",
                "branchSelections",
                "revealedFactIds");
            return new LoreProgressSnapshot(
                ReadString(root, "saveBindingId"),
                ReadString(root, "saveSignature"),
                ParseSaveClass(ReadString(root, "saveClass")),
                ReadString(root, "storyPhaseId"),
                ReadString(root, "progressRevision"),
                ReadStringArray(root, "progressFlags"),
                ReadStringMap(root, "branchSelections"),
                ReadStringArray(root, "revealedFactIds"));
        }

        private static LoreFact ParseFact(JsonElement value)
        {
            RequireObjectProperties(
                value,
                "factId",
                "sourceAuthority",
                "canonClass",
                "sourceRevision",
                "statement",
                "guidanceDomains",
                "guidanceKeys",
                "revealPredicate");
            return new LoreFact(
                ReadString(value, "factId"),
                ReadString(value, "sourceAuthority"),
                ParseCanonClass(ReadString(value, "canonClass")),
                ReadString(value, "sourceRevision"),
                ReadString(value, "statement"),
                ReadStringArray(value, "guidanceDomains")
                    .Select(ParseGuidanceDomain),
                ReadStringArray(value, "guidanceKeys"),
                ParsePredicate(value.GetProperty("revealPredicate")));
        }

        private static LoreRevealPredicate ParsePredicate(
            JsonElement value)
        {
            RequireObjectProperties(
                value,
                "minimumSaveClass",
                "requiredProgressFlags",
                "forbiddenProgressFlags",
                "branchEquals",
                "requiresRevealGrant");
            JsonElement reveal = value.GetProperty(
                "requiresRevealGrant");
            if (reveal.ValueKind != JsonValueKind.True
                && reveal.ValueKind != JsonValueKind.False)
            {
                throw new InvalidDataException(
                    "requiresRevealGrant must be boolean.");
            }
            return new LoreRevealPredicate(
                ParseSaveClass(
                    ReadString(value, "minimumSaveClass")),
                ReadStringArray(value, "requiredProgressFlags"),
                ReadStringArray(value, "forbiddenProgressFlags"),
                ReadStringMap(value, "branchEquals"),
                reveal.GetBoolean());
        }

        private static JsonDocument ParseDocument(
            ReadOnlySpan<byte> json)
        {
            try
            {
                return JsonDocument.Parse(
                    json.ToArray(),
                    new JsonDocumentOptions
                    {
                        AllowTrailingCommas = false,
                        CommentHandling =
                            JsonCommentHandling.Disallow,
                        MaxDepth = 32
                    });
            }
            catch (JsonException exception)
            {
                throw new InvalidDataException(
                    "Lore JSON is malformed.",
                    exception);
            }
        }

        private static void RequireObjectProperties(
            JsonElement value,
            params string[] required)
        {
            if (value.ValueKind != JsonValueKind.Object)
                throw new InvalidDataException(
                    "Lore value must be an object.");
            var expected = new HashSet<string>(
                required,
                StringComparer.Ordinal);
            var seen = new HashSet<string>(StringComparer.Ordinal);
            foreach (JsonProperty property
                in value.EnumerateObject())
            {
                if (!expected.Contains(property.Name)
                    || !seen.Add(property.Name))
                {
                    throw new InvalidDataException(
                        "Lore JSON contains an unknown or duplicate property.");
                }
            }
            if (!seen.SetEquals(expected))
                throw new InvalidDataException(
                    "Lore JSON is missing a required property.");
        }

        private static string ReadString(
            JsonElement value,
            string name)
        {
            JsonElement property = value.GetProperty(name);
            if (property.ValueKind != JsonValueKind.String
                || string.IsNullOrWhiteSpace(property.GetString()))
            {
                throw new InvalidDataException(
                    name + " must be a non-empty string.");
            }
            return property.GetString();
        }

        private static int ReadInt(
            JsonElement value,
            string name)
        {
            JsonElement property = value.GetProperty(name);
            if (property.ValueKind != JsonValueKind.Number
                || !property.TryGetInt32(out int result))
            {
                throw new InvalidDataException(
                    name + " must be an integer.");
            }
            return result;
        }

        private static string[] ReadStringArray(
            JsonElement value,
            string name)
        {
            JsonElement property = value.GetProperty(name);
            if (property.ValueKind != JsonValueKind.Array)
                throw new InvalidDataException(
                    name + " must be an array.");
            var result = new List<string>();
            foreach (JsonElement item in property.EnumerateArray())
            {
                if (item.ValueKind != JsonValueKind.String
                    || string.IsNullOrWhiteSpace(item.GetString()))
                {
                    throw new InvalidDataException(
                        name + " contains a non-string value.");
                }
                result.Add(item.GetString());
            }
            if (result.Distinct(StringComparer.Ordinal).Count()
                != result.Count)
            {
                throw new InvalidDataException(
                    name + " contains a duplicate value.");
            }
            return result.ToArray();
        }

        private static IReadOnlyDictionary<string, string> ReadStringMap(
            JsonElement value,
            string name)
        {
            JsonElement property = value.GetProperty(name);
            if (property.ValueKind != JsonValueKind.Object)
                throw new InvalidDataException(
                    name + " must be an object.");
            var result = new Dictionary<string, string>(
                StringComparer.Ordinal);
            foreach (JsonProperty item in property.EnumerateObject())
            {
                if (item.Value.ValueKind != JsonValueKind.String
                    || string.IsNullOrWhiteSpace(
                        item.Value.GetString())
                    || !result.TryAdd(
                        item.Name,
                        item.Value.GetString()))
                {
                    throw new InvalidDataException(
                        name + " contains an invalid or duplicate value.");
                }
            }
            return result;
        }

        private static WingsSaveClass ParseSaveClass(string value)
        {
            return value switch
            {
                "legacy" => WingsSaveClass.Legacy,
                "standard" => WingsSaveClass.Standard,
                "new_game_plus" => WingsSaveClass.NewGamePlus,
                "developer_unlocked" =>
                    WingsSaveClass.DeveloperUnlocked,
                _ => throw new InvalidDataException(
                    "Unknown save class.")
            };
        }

        private static LoreCanonClass ParseCanonClass(string value)
        {
            return value switch
            {
                "gameplay_public" =>
                    LoreCanonClass.GameplayPublic,
                "presentation_cue" =>
                    LoreCanonClass.PresentationCue,
                _ => throw new InvalidDataException(
                    "Unknown canon class.")
            };
        }

        private static WingsGuidanceDomain ParseGuidanceDomain(
            string value)
        {
            return value switch
            {
                "task" => WingsGuidanceDomain.Task,
                "equipment" => WingsGuidanceDomain.Equipment,
                "route" => WingsGuidanceDomain.Route,
                "ui" => WingsGuidanceDomain.Ui,
                _ => throw new InvalidDataException(
                    "Unknown guidance domain.")
            };
        }
    }
}
