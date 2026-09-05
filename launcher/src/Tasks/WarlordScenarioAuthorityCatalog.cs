using System;
using System.Collections.Generic;
using System.Text.RegularExpressions;

namespace CF7Launcher.Tasks
{
    /// <summary>
    /// Host-owned strategic scenario identities and faction relationships.
    /// Browser state may echo this data, but it cannot introduce scenario authority.
    /// </summary>
    internal sealed class WarlordScenarioAuthorityCatalog
    {
        private readonly Dictionary<string, WarlordScenarioAuthorityDefinition>
            _digestDefinitions;
        private readonly Dictionary<string, WarlordScenarioAuthorityDefinition>
            _versionedDefinitions;

        internal WarlordScenarioAuthorityCatalog(
            IEnumerable<WarlordScenarioAuthorityDefinition> definitions)
        {
            if (definitions == null) throw new ArgumentNullException(nameof(definitions));
            _digestDefinitions =
                new Dictionary<string, WarlordScenarioAuthorityDefinition>(
                    StringComparer.Ordinal);
            _versionedDefinitions =
                new Dictionary<string, WarlordScenarioAuthorityDefinition>(
                StringComparer.Ordinal);
            foreach (WarlordScenarioAuthorityDefinition definition in definitions)
            {
                if (definition == null)
                    throw new ArgumentException("scenario authority definition cannot be null", nameof(definitions));
                string versionedKey = VersionedIdentityKey(
                    definition.ScenarioId,
                    definition.RulesVersion,
                    definition.MapDefinitionId);
                if (definition.HasConfigDigestAuthority)
                {
                    string digestKey = IdentityKey(
                        definition.ScenarioId,
                        definition.RulesVersion,
                        definition.MapDefinitionId,
                        definition.ConfigDigest);
                    if (_versionedDefinitions.ContainsKey(versionedKey)
                        || _digestDefinitions.ContainsKey(digestKey))
                        throw new ArgumentException("duplicate scenario authority identity", nameof(definitions));
                    _digestDefinitions[digestKey] = definition;
                }
                else
                {
                    if (_versionedDefinitions.ContainsKey(versionedKey)
                        || ContainsDigestDefinition(versionedKey))
                        throw new ArgumentException("duplicate scenario authority identity", nameof(definitions));
                    _versionedDefinitions[versionedKey] = definition;
                }
            }
            if (_digestDefinitions.Count + _versionedDefinitions.Count == 0)
                throw new ArgumentException("scenario authority catalog cannot be empty", nameof(definitions));
        }

        internal static WarlordScenarioAuthorityCatalog CreateDefault()
        {
            return new WarlordScenarioAuthorityCatalog(
                new[]
                {
                    new WarlordScenarioAuthorityDefinition(
                        "warlord_tutorial_v1",
                        "wargame-demo-v0.1.1",
                        "demo-nine-node",
                        "sha256:9DA8013D3B7D1C1F5C5B27BDA813F1ADC9E2C8C5C80F3680B9FFDF773A9B76B0",
                        new[] { "red", "blue" },
                        new[]
                        {
                            new WarlordScenarioRelationDefinition("red", "blue", "hostile")
                        }),
                    // Demo 2 authoring does not yet publish a canonical strategic
                    // config digest. Until it does, the exact versioned scenario
                    // and map identities are the explicit Host authority boundary;
                    // faction membership and every relation pair remain Host-owned.
                    new WarlordScenarioAuthorityDefinition(
                        "warlord_demo_02_v1",
                        "wargame-demo-v0.1.1",
                        "demo2-thick-x-80",
                        new[]
                        {
                            "player",
                            "boss-pact-a",
                            "boss-independent",
                            "boss-pact-b"
                        },
                        new[]
                        {
                            new WarlordScenarioRelationDefinition(
                                "player", "boss-pact-a", "hostile"),
                            new WarlordScenarioRelationDefinition(
                                "player", "boss-independent", "hostile"),
                            new WarlordScenarioRelationDefinition(
                                "player", "boss-pact-b", "hostile"),
                            new WarlordScenarioRelationDefinition(
                                "boss-pact-a", "boss-independent", "hostile"),
                            new WarlordScenarioRelationDefinition(
                                "boss-pact-a", "boss-pact-b", "allied"),
                            new WarlordScenarioRelationDefinition(
                                "boss-independent", "boss-pact-b", "hostile")
                        })
                });
        }

        internal bool TryResolve(
            string scenarioId,
            string rulesVersion,
            string mapDefinitionId,
            string configDigest,
            out WarlordScenarioAuthorityDefinition definition)
        {
            if (_digestDefinitions.TryGetValue(
                    IdentityKey(
                        scenarioId,
                        rulesVersion,
                        mapDefinitionId,
                        configDigest),
                    out definition))
                return true;

            // A digest-less prototype definition deliberately does not treat a
            // browser-supplied digest as verified. Its authority is the exact,
            // versioned scenarioRef + rulesVersion + mapId tuple only.
            return _versionedDefinitions.TryGetValue(
                VersionedIdentityKey(scenarioId, rulesVersion, mapDefinitionId),
                out definition);
        }

        private bool ContainsDigestDefinition(string versionedKey)
        {
            foreach (WarlordScenarioAuthorityDefinition definition
                in _digestDefinitions.Values)
            {
                if (string.Equals(
                        VersionedIdentityKey(
                            definition.ScenarioId,
                            definition.RulesVersion,
                            definition.MapDefinitionId),
                        versionedKey,
                        StringComparison.Ordinal))
                    return true;
            }
            return false;
        }

        private static string IdentityKey(
            string scenarioId,
            string rulesVersion,
            string mapDefinitionId,
            string configDigest)
        {
            return (scenarioId ?? "") + "\u001f"
                + (rulesVersion ?? "") + "\u001f"
                + (mapDefinitionId ?? "") + "\u001f"
                + (configDigest ?? "");
        }

        private static string VersionedIdentityKey(
            string scenarioId,
            string rulesVersion,
            string mapDefinitionId)
        {
            return (scenarioId ?? "") + "\u001f"
                + (rulesVersion ?? "") + "\u001f"
                + (mapDefinitionId ?? "");
        }
    }

    internal sealed class WarlordScenarioAuthorityDefinition
    {
        private static readonly Regex FactionIdPattern =
            new Regex("^[A-Za-z0-9][A-Za-z0-9._~-]{0,159}$", RegexOptions.Compiled);
        private static readonly Regex DigestPattern =
            new Regex("^sha256:[A-Fa-f0-9]{64}$", RegexOptions.Compiled);
        private static readonly HashSet<string> AllowedRelations =
            new HashSet<string>(StringComparer.Ordinal)
            {
                "allied", "neutral", "hostile"
            };

        private readonly List<string> _factionIds;
        private readonly HashSet<string> _factionIdSet;
        private readonly Dictionary<string, string> _relations;

        internal WarlordScenarioAuthorityDefinition(
            string scenarioId,
            string rulesVersion,
            string mapDefinitionId,
            string configDigest,
            IEnumerable<string> factionIds,
            IEnumerable<WarlordScenarioRelationDefinition> relations)
            : this(
                scenarioId,
                rulesVersion,
                mapDefinitionId,
                configDigest,
                true,
                factionIds,
                relations)
        {
        }

        internal WarlordScenarioAuthorityDefinition(
            string scenarioId,
            string rulesVersion,
            string mapDefinitionId,
            IEnumerable<string> factionIds,
            IEnumerable<WarlordScenarioRelationDefinition> relations)
            : this(
                scenarioId,
                rulesVersion,
                mapDefinitionId,
                null,
                false,
                factionIds,
                relations)
        {
        }

        private WarlordScenarioAuthorityDefinition(
            string scenarioId,
            string rulesVersion,
            string mapDefinitionId,
            string configDigest,
            bool hasConfigDigestAuthority,
            IEnumerable<string> factionIds,
            IEnumerable<WarlordScenarioRelationDefinition> relations)
        {
            ScenarioId = RequiredIdentity(scenarioId, nameof(scenarioId));
            RulesVersion = RequiredIdentity(rulesVersion, nameof(rulesVersion));
            MapDefinitionId = RequiredIdentity(mapDefinitionId, nameof(mapDefinitionId));
            if (hasConfigDigestAuthority
                && !DigestPattern.IsMatch(configDigest ?? ""))
                throw new ArgumentException("scenario config digest is invalid", nameof(configDigest));
            ConfigDigest = hasConfigDigestAuthority ? configDigest : null;
            HasConfigDigestAuthority = hasConfigDigestAuthority;

            if (factionIds == null) throw new ArgumentNullException(nameof(factionIds));
            _factionIds = new List<string>();
            _factionIdSet = new HashSet<string>(StringComparer.Ordinal);
            foreach (string factionId in factionIds)
            {
                if (!FactionIdPattern.IsMatch(factionId ?? ""))
                    throw new ArgumentException("scenario faction id is invalid", nameof(factionIds));
                if (!_factionIdSet.Add(factionId))
                    throw new ArgumentException("scenario faction id is duplicated", nameof(factionIds));
                _factionIds.Add(factionId);
            }
            if (_factionIds.Count < 2)
                throw new ArgumentException("scenario authority requires at least two factions", nameof(factionIds));

            if (relations == null) throw new ArgumentNullException(nameof(relations));
            _relations = new Dictionary<string, string>(StringComparer.Ordinal);
            foreach (WarlordScenarioRelationDefinition relation in relations)
            {
                if (relation == null)
                    throw new ArgumentException("scenario relation cannot be null", nameof(relations));
                if (!_factionIdSet.Contains(relation.LeftFactionId)
                    || !_factionIdSet.Contains(relation.RightFactionId)
                    || string.Equals(
                        relation.LeftFactionId,
                        relation.RightFactionId,
                        StringComparison.Ordinal))
                {
                    throw new ArgumentException("scenario relation faction pair is invalid", nameof(relations));
                }
                if (!AllowedRelations.Contains(relation.Relation))
                    throw new ArgumentException("scenario relation value is invalid", nameof(relations));
                string key = RelationKey(relation.LeftFactionId, relation.RightFactionId);
                if (_relations.ContainsKey(key))
                    throw new ArgumentException("scenario relation pair is duplicated", nameof(relations));
                _relations[key] = relation.Relation;
            }

            int expectedRelationCount = _factionIds.Count * (_factionIds.Count - 1) / 2;
            if (_relations.Count != expectedRelationCount)
                throw new ArgumentException("scenario relation set is incomplete", nameof(relations));
        }

        internal string ScenarioId { get; }
        internal string RulesVersion { get; }
        internal string MapDefinitionId { get; }
        internal string ConfigDigest { get; }
        internal bool HasConfigDigestAuthority { get; }
        internal IReadOnlyList<string> FactionIds => _factionIds;

        internal bool ContainsFaction(string factionId)
        {
            return _factionIdSet.Contains(factionId ?? "");
        }

        internal bool TryGetRelation(string leftFactionId, string rightFactionId, out string relation)
        {
            relation = null;
            if (!ContainsFaction(leftFactionId) || !ContainsFaction(rightFactionId)) return false;
            if (string.Equals(leftFactionId, rightFactionId, StringComparison.Ordinal))
            {
                relation = "allied";
                return true;
            }
            return _relations.TryGetValue(RelationKey(leftFactionId, rightFactionId), out relation);
        }

        private static string RequiredIdentity(string value, string fieldName)
        {
            if (string.IsNullOrEmpty(value) || value.Length > 160)
                throw new ArgumentException("scenario identity is invalid", fieldName);
            for (int i = 0; i < value.Length; i++)
                if (char.IsControl(value[i]))
                    throw new ArgumentException("scenario identity is invalid", fieldName);
            return value;
        }

        private static string RelationKey(string leftFactionId, string rightFactionId)
        {
            return string.CompareOrdinal(leftFactionId, rightFactionId) < 0
                ? leftFactionId + "\u001f" + rightFactionId
                : rightFactionId + "\u001f" + leftFactionId;
        }
    }

    internal sealed class WarlordScenarioRelationDefinition
    {
        internal WarlordScenarioRelationDefinition(
            string leftFactionId,
            string rightFactionId,
            string relation)
        {
            LeftFactionId = leftFactionId;
            RightFactionId = rightFactionId;
            Relation = relation;
        }

        internal string LeftFactionId { get; }
        internal string RightFactionId { get; }
        internal string Relation { get; }
    }
}
