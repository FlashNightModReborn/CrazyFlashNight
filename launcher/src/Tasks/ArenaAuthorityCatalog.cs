using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Security.Cryptography;
using System.Text;
using System.Xml.Linq;
using Newtonsoft.Json;
using Newtonsoft.Json.Linq;

namespace CF7Launcher.Tasks
{
    /// <summary>
    /// P5 竞技场权威目录。标准/隐藏挑战只读 data/arena/arena_config.xml；
    /// 势力阵容与手作标定分别只读 meta_teams.json / arena_factions.json。
    /// Web 只选择 cardId/roster，经济、表达式与爬升池均由本类生成。
    /// </summary>
    internal sealed class ArenaAuthorityCatalog
    {
        internal const string SourceDescription = "data/arena/arena_config.xml+meta_teams.json+arena_factions.json+arena_calibrated_rosters.json+data/units/units.json";
        private const int StandardOpponentCap = 4;
        private const int FallenMinUnits = 4;
        private const int FallenBandWindow = 15;
        private const int MaximumCalibratedRosterEntries = 12;

        private readonly List<TierDefinition> _tiers;
        private readonly List<HiddenDefinition> _hidden;
        private readonly Dictionary<string, FactionDefinition> _factions;
        private readonly Dictionary<string, List<UnitDefinition>> _rosters;
        private readonly Dictionary<string, List<UnitDefinition>> _unitsByType;
        private readonly Dictionary<string, int> _mercenaryLevels;
        private readonly List<CalibratedRosterDefinition> _calibratedRosters;

        private ArenaAuthorityCatalog(
            List<TierDefinition> tiers,
            List<HiddenDefinition> hidden,
            Dictionary<string, FactionDefinition> factions,
            Dictionary<string, List<UnitDefinition>> rosters,
            Dictionary<string, int> mercenaryLevels,
            List<CalibratedRosterDefinition> calibratedRosters,
            string sourceDigest)
        {
            _tiers = tiers;
            _hidden = hidden;
            _factions = factions;
            _rosters = rosters;
            _mercenaryLevels = mercenaryLevels;
            _calibratedRosters = calibratedRosters;
            SourceDigest = sourceDigest;
            _unitsByType = new Dictionary<string, List<UnitDefinition>>(StringComparer.Ordinal);
            foreach (List<UnitDefinition> roster in rosters.Values)
            {
                foreach (UnitDefinition unit in roster)
                {
                    if (!_unitsByType.TryGetValue(unit.Type, out List<UnitDefinition> entries))
                    {
                        entries = new List<UnitDefinition>();
                        _unitsByType.Add(unit.Type, entries);
                    }
                    entries.Add(unit);
                }
            }
        }

        internal string SourceDigest { get; }

        internal static ArenaAuthorityCatalog Load(string projectRoot)
        {
            if (string.IsNullOrWhiteSpace(projectRoot))
                throw new InvalidDataException("Arena authority project root is required.");

            string root = Path.GetFullPath(projectRoot);
            string xmlPath = Path.Combine(root, "data", "arena", "arena_config.xml");
            string teamsPath = Path.Combine(root, "data", "arena", "meta_teams.json");
            string factionsPath = Path.Combine(root, "data", "arena", "arena_factions.json");
            string calibratedRostersPath = Path.Combine(root, "data", "arena", "arena_calibrated_rosters.json");
            string unitsPath = Path.Combine(root, "data", "units", "units.json");
            byte[] xmlBytes = ReadRequiredBytes(xmlPath);
            byte[] teamsBytes = ReadRequiredBytes(teamsPath);
            byte[] factionsBytes = ReadRequiredBytes(factionsPath);
            byte[] calibratedRostersBytes = ReadRequiredBytes(calibratedRostersPath);
            byte[] unitsBytes = ReadRequiredBytes(unitsPath);

            ParseXml(xmlBytes, out List<TierDefinition> tiers, out List<HiddenDefinition> hidden);
            ParseTeams(teamsBytes,
                out Dictionary<string, List<UnitDefinition>> rosters,
                out Dictionary<string, int> mercenaryLevels);
            Dictionary<string, FactionDefinition> factions = ParseFactions(factionsBytes, rosters);
            HashSet<string> knownUnitIdentities = ParseUnitIdentities(unitsBytes);
            List<CalibratedRosterDefinition> calibratedRosters = ParseCalibratedRosters(
                calibratedRostersBytes,
                tiers,
                knownUnitIdentities);
            string digest = ComputeDigest(xmlBytes, teamsBytes, factionsBytes, calibratedRostersBytes, unitsBytes);
            return new ArenaAuthorityCatalog(
                tiers,
                hidden,
                factions,
                rosters,
                mercenaryLevels,
                calibratedRosters,
                digest);
        }

        internal ArenaAuthoritySession CreateSession(
            int playerLevel,
            IEnumerable<string> knownEnemies,
            Func<int, int, int> randomInclusive = null)
        {
            Func<int, int, int> random = randomInclusive ?? SecureRandomInclusive;
            var known = new HashSet<string>(StringComparer.Ordinal);
            if (knownEnemies != null)
            {
                foreach (string value in knownEnemies)
                {
                    if (!string.IsNullOrWhiteSpace(value)) known.Add(value);
                }
            }

            var cards = new List<ArenaAuthorityCard>();
            int previewIndex = 0;
            foreach (TierDefinition tier in _tiers)
            {
                int count = random(tier.CountMin, Math.Min(tier.CountMax, StandardOpponentCap));
                cards.Add(ArenaAuthorityCard.CreateStandard(
                    tier.Id,
                    "standard",
                    tier.Index,
                    previewIndex++,
                    tier.LevelMin,
                    tier.LevelMax,
                    tier.CountMin,
                    Math.Min(tier.CountMax, StandardOpponentCap),
                    count,
                    1m,
                    string.Empty,
                    false));
            }

            int playerTier = FindPlayerTier(Math.Max(1, playerLevel));
            foreach (HiddenDefinition hidden in _hidden)
            {
                TierDefinition tier = _tiers[Math.Min(playerTier + hidden.Offset, _tiers.Count - 1)];
                int countMax = Math.Min(hidden.CountMax, StandardOpponentCap);
                int count = random(hidden.CountMin, countMax);
                if (hidden.RequiresMixedRoster && count < 2 && countMax >= 2) count = 2;
                cards.Add(ArenaAuthorityCard.CreateStandard(
                    hidden.Id,
                    "hidden",
                    previewIndex + 1,
                    previewIndex++,
                    tier.LevelMin,
                    tier.LevelMax,
                    hidden.CountMin,
                    countMax,
                    count,
                    hidden.EconomyMultiplier,
                    hidden.Label,
                    hidden.RequiresMixedRoster));
            }

            foreach (KeyValuePair<string, FactionDefinition> pair in _factions.OrderBy(p => p.Key, StringComparer.Ordinal))
            {
                string faction = pair.Key;
                FactionDefinition meta = pair.Value;
                if (!meta.Enabled || !_rosters.TryGetValue(faction, out List<UnitDefinition> allUnits)
                        || allUnits.Count < FallenMinUnits)
                {
                    continue;
                }

                HashSet<string> whitelist = meta.Units == null
                    ? null
                    : new HashSet<string>(meta.Units, StringComparer.Ordinal);
                List<UnitDefinition> units = allUnits
                    .Where(unit => (whitelist == null || whitelist.Contains(unit.Type))
                        && (unit.IsHumanoidTemplate || known.Contains(unit.SpriteName)))
                    .ToList();
                if (units.Count == 0) continue;

                int low = units.Min(unit => unit.MinLevel);
                int high = units.Max(unit => unit.MaxLevel);
                int levelMin = Math.Max(low, high - FallenBandWindow);
                int benchLevel = meta.BenchLevel ?? high;
                int count = Math.Clamp(3 + (high / 25), 4, 6);
                int maxWaves = WavesForScale(meta.Scale);
                JArray pool = BuildPool(units);

                cards.Add(ArenaAuthorityCard.CreateFaction(
                    "fallen-" + faction,
                    "fallen",
                    faction,
                    meta.DisplayName,
                    levelMin,
                    high,
                    benchLevel,
                    count,
                    maxWaves,
                    pool));
                cards.Add(ArenaAuthorityCard.CreateFaction(
                    "esc-" + faction,
                    "escalation",
                    faction,
                    meta.DisplayName,
                    levelMin,
                    high,
                    benchLevel,
                    count,
                    maxWaves,
                    pool));
            }

            List<CalibratedRosterDefinition> calibratedRosters = _calibratedRosters
                .Where(roster => roster.RequiredKnownEnemies.All(known.Contains))
                .ToList();

            return new ArenaAuthoritySession(
                SourceDigest,
                cards,
                calibratedRosters,
                known,
                _unitsByType,
                _mercenaryLevels);
        }

        private int FindPlayerTier(int playerLevel)
        {
            for (int index = 0; index < _tiers.Count; index++)
            {
                TierDefinition tier = _tiers[index];
                if (playerLevel >= tier.LevelMin
                        && (playerLevel < tier.LevelMax || index == _tiers.Count - 1))
                {
                    return index;
                }
            }
            return _tiers.Count - 1;
        }

        private static int SecureRandomInclusive(int minimum, int maximum)
        {
            if (minimum > maximum) throw new InvalidDataException("Arena count range is inverted.");
            return minimum == maximum ? minimum : RandomNumberGenerator.GetInt32(minimum, maximum + 1);
        }

        private static int WavesForScale(string scale)
        {
            return scale switch
            {
                "small" => 5,
                "large" => 10,
                "coalition" => 15,
                _ => throw new InvalidDataException("Unknown arena faction scale: " + scale)
            };
        }

        private static JArray BuildPool(IEnumerable<UnitDefinition> units)
        {
            var pool = new JArray();
            foreach (UnitDefinition unit in units.OrderBy(u => u.Type, StringComparer.Ordinal))
            {
                var item = new JObject
                {
                    ["type"] = unit.Type,
                    ["minLevel"] = unit.MinLevel,
                    ["maxLevel"] = unit.MaxLevel,
                    ["weight"] = unit.Weight
                };
                if (unit.Parameters != null) item["Parameters"] = unit.Parameters.DeepClone();
                pool.Add(item);
            }
            return pool;
        }

        private static byte[] ReadRequiredBytes(string path)
        {
            if (!File.Exists(path)) throw new FileNotFoundException("Arena authority source is missing.", path);
            return File.ReadAllBytes(path);
        }

        private static string ComputeDigest(params byte[][] sources)
        {
            using IncrementalHash hash = IncrementalHash.CreateHash(HashAlgorithmName.SHA256);
            foreach (byte[] source in sources)
            {
                hash.AppendData(BitConverter.GetBytes(source.Length));
                hash.AppendData(source);
            }
            return Convert.ToHexString(hash.GetHashAndReset());
        }

        private static void ParseXml(
            byte[] bytes,
            out List<TierDefinition> tiers,
            out List<HiddenDefinition> hidden)
        {
            XDocument document;
            try
            {
                using var stream = new MemoryStream(bytes, false);
                document = XDocument.Load(stream, LoadOptions.None);
            }
            catch (Exception error)
            {
                throw new InvalidDataException("arena_config.xml is not valid XML.", error);
            }

            XElement root = document.Root;
            if (root == null || root.Name.LocalName != "ArenaConfig")
                throw new InvalidDataException("arena_config.xml root must be ArenaConfig.");

            tiers = new List<TierDefinition>();
            var ids = new HashSet<string>(StringComparer.Ordinal);
            foreach (XElement element in root.Element("Cards")?.Elements("Card") ?? Enumerable.Empty<XElement>())
            {
                var tier = new TierDefinition
                {
                    Id = RequiredAttribute(element, "id"),
                    Index = PositiveIntAttribute(element, "index"),
                    LevelMin = PositiveIntAttribute(element, "levelMin"),
                    LevelMax = PositiveIntAttribute(element, "levelMax"),
                    CountMin = PositiveIntAttribute(element, "countMin"),
                    CountMax = PositiveIntAttribute(element, "countMax")
                };
                if (!ids.Add(tier.Id)) throw new InvalidDataException("Duplicate arena card id: " + tier.Id);
                if (tier.Index != tiers.Count + 1 || tier.LevelMax < tier.LevelMin
                        || tier.CountMax < tier.CountMin || tier.CountMax > StandardOpponentCap)
                {
                    throw new InvalidDataException("Invalid standard arena card: " + tier.Id);
                }
                string expectedTemplate = "#0@" + tier.LevelMin + "-" + tier.LevelMax + "%{count}";
                if (RequiredAttribute(element, "exprTemplate") != expectedTemplate)
                    throw new InvalidDataException("Arena exprTemplate does not match its numeric fields: " + tier.Id);
                tiers.Add(tier);
            }
            if (tiers.Count == 0) throw new InvalidDataException("arena_config.xml contains no standard cards.");

            hidden = new List<HiddenDefinition>();
            foreach (XElement element in root.Element("HiddenChallenges")?.Elements("HiddenChallenge")
                ?? Enumerable.Empty<XElement>())
            {
                var item = new HiddenDefinition
                {
                    Id = RequiredAttribute(element, "id"),
                    Label = RequiredAttribute(element, "label"),
                    Offset = PositiveIntAttribute(element, "offset"),
                    CountMin = PositiveIntAttribute(element, "countMin"),
                    CountMax = PositiveIntAttribute(element, "countMax"),
                    RequiresMixedRoster = BoolAttribute(element, "requiresMixedRoster"),
                    EconomyMultiplier = PositiveDecimalAttribute(element, "economyMultiplier")
                };
                if (!ids.Add(item.Id)) throw new InvalidDataException("Duplicate arena card id: " + item.Id);
                if (item.CountMax < item.CountMin || item.CountMax > StandardOpponentCap
                        || item.EconomyMultiplier > 10m)
                {
                    throw new InvalidDataException("Invalid hidden arena card: " + item.Id);
                }
                hidden.Add(item);
            }
        }

        private static void ParseTeams(
            byte[] bytes,
            out Dictionary<string, List<UnitDefinition>> rosters,
            out Dictionary<string, int> mercenaryLevels)
        {
            JObject root = ParseObject(bytes, "meta_teams.json");
            JObject rosterObject = root["rosters"] as JObject
                ?? throw new InvalidDataException("meta_teams.json rosters object is required.");
            rosters = new Dictionary<string, List<UnitDefinition>>(StringComparer.Ordinal);
            foreach (JProperty factionProperty in rosterObject.Properties())
            {
                if (string.IsNullOrWhiteSpace(factionProperty.Name) || factionProperty.Value is not JObject faction)
                    throw new InvalidDataException("meta_teams.json contains an invalid roster.");
                JArray units = faction["units"] as JArray
                    ?? throw new InvalidDataException("Roster units are required: " + factionProperty.Name);
                var parsedUnits = new List<UnitDefinition>();
                foreach (JToken token in units)
                {
                    if (token is not JObject item) throw new InvalidDataException("Roster unit must be an object.");
                    var unit = new UnitDefinition
                    {
                        Type = RequiredString(item, "type"),
                        SpriteName = RequiredString(item, "spritename"),
                        MinLevel = PositiveInt(item, "minLevel"),
                        MaxLevel = PositiveInt(item, "maxLevel"),
                        Weight = NonNegativeInt(item, "weight"),
                        Parameters = ReadParameters(item)
                    };
                    if (!unit.Type.StartsWith("兵种", StringComparison.Ordinal)
                            || unit.MaxLevel < unit.MinLevel)
                    {
                        throw new InvalidDataException("Invalid roster unit: " + unit.Type);
                    }
                    parsedUnits.Add(unit);
                }
                rosters.Add(factionProperty.Name, parsedUnits);
            }
            if (rosters.Count == 0) throw new InvalidDataException("meta_teams.json contains no rosters.");

            JArray mercenaries = root["mercenaries"] as JArray
                ?? throw new InvalidDataException("meta_teams.json mercenaries array is required.");
            mercenaryLevels = new Dictionary<string, int>(StringComparer.Ordinal);
            var ambiguousMercenaryIds = new HashSet<string>(StringComparer.Ordinal);
            foreach (JToken token in mercenaries)
            {
                if (token is not JObject item) throw new InvalidDataException("Mercenary entry must be an object.");
                string id = RequiredScalarId(item, "id");
                int level = PositiveInt(item, "level");
                if (ambiguousMercenaryIds.Contains(id)) continue;
                if (!mercenaryLevels.TryAdd(id, level))
                {
                    mercenaryLevels.Remove(id);
                    ambiguousMercenaryIds.Add(id);
                }
            }
        }

        private static Dictionary<string, FactionDefinition> ParseFactions(
            byte[] bytes,
            Dictionary<string, List<UnitDefinition>> rosters)
        {
            JObject root = ParseObject(bytes, "arena_factions.json");
            if (root.Value<int?>("schemaVersion") != 1)
                throw new InvalidDataException("arena_factions.json schemaVersion must be 1.");
            JObject source = root["factions"] as JObject
                ?? throw new InvalidDataException("arena_factions.json factions object is required.");
            var result = new Dictionary<string, FactionDefinition>(StringComparer.Ordinal);
            foreach (JProperty property in source.Properties())
            {
                if (!rosters.ContainsKey(property.Name) || property.Value is not JObject item)
                    throw new InvalidDataException("Faction metadata has no matching roster: " + property.Name);
                string scale = RequiredString(item, "scale");
                if (scale != "small" && scale != "large" && scale != "coalition")
                    throw new InvalidDataException("Invalid faction scale: " + property.Name);
                int? benchLevel = item["benchLevel"]?.Type == JTokenType.Null
                    ? null
                    : PositiveInt(item, "benchLevel");
                bool? enabled = item.Value<bool?>("enabled");
                if (enabled == null || item["enabled"].Type != JTokenType.Boolean)
                    throw new InvalidDataException("Faction enabled must be boolean: " + property.Name);
                string[] units = null;
                if (item["units"]?.Type != JTokenType.Null)
                {
                    if (item["units"] is not JArray array || array.Count == 0)
                        throw new InvalidDataException("Faction units must be null or non-empty: " + property.Name);
                    units = array.Select(token => token.Type == JTokenType.String ? token.Value<string>() : null).ToArray();
                    if (units.Any(string.IsNullOrWhiteSpace)
                            || units.Distinct(StringComparer.Ordinal).Count() != units.Length
                            || units.Any(type => !rosters[property.Name].Any(unit => unit.Type == type)))
                    {
                        throw new InvalidDataException("Faction units whitelist is invalid: " + property.Name);
                    }
                }
                result.Add(property.Name, new FactionDefinition
                {
                    DisplayName = RequiredString(item, "displayName"),
                    BenchLevel = benchLevel,
                    Scale = scale,
                    Enabled = enabled.Value,
                    Units = units
                });
            }
            if (result.Count == 0) throw new InvalidDataException("arena_factions.json contains no factions.");
            return result;
        }

        private static List<CalibratedRosterDefinition> ParseCalibratedRosters(
            byte[] bytes,
            IReadOnlyList<TierDefinition> tiers,
            HashSet<string> knownUnitIdentities)
        {
            JObject root = ParseObject(bytes, "arena_calibrated_rosters.json");
            if (root.Value<int?>("schemaVersion") != 1)
                throw new InvalidDataException("arena_calibrated_rosters.json schemaVersion must be 1.");
            JToken activeToken = root["active"];
            if (activeToken?.Type != JTokenType.Boolean)
                throw new InvalidDataException("arena_calibrated_rosters.json active must be boolean.");
            RequiredString(root, "catalogId");
            string expectedHash = RequiredString(root, "catalogHash");
            string actualHash = ComputeCatalogHash(root);
            if (!string.Equals(expectedHash, actualHash, StringComparison.Ordinal))
                throw new InvalidDataException("arena_calibrated_rosters.json catalogHash mismatch.");

            JArray source = root["rosters"] as JArray
                ?? throw new InvalidDataException("arena_calibrated_rosters.json rosters array is required.");
            bool active = activeToken.Value<bool>();
            if (!active)
            {
                if (source.Count != 0 || root["campaignId"]?.Type != JTokenType.Null
                        || root["cohortId"]?.Type != JTokenType.Null
                        || root["source"]?.Type != JTokenType.Null
                        || root["model"]?.Type != JTokenType.Null)
                {
                    throw new InvalidDataException("Inactive calibrated roster catalog must be empty and unbound.");
                }
                return new List<CalibratedRosterDefinition>();
            }

            RequiredString(root, "campaignId");
            RequiredString(root, "cohortId");
            if (root["source"] is not JObject || root["model"] is not JObject || source.Count == 0)
                throw new InvalidDataException("Active calibrated roster catalog requires source, model, and rosters.");

            var tiersById = tiers.ToDictionary(tier => tier.Id, StringComparer.Ordinal);
            var result = new List<CalibratedRosterDefinition>();
            var ids = new HashSet<string>(StringComparer.Ordinal);
            foreach (JToken token in source)
            {
                if (token is not JObject item)
                    throw new InvalidDataException("Calibrated roster entry must be an object.");
                string id = RequiredString(item, "id");
                if (!IsCalibratedRosterId(id) || !ids.Add(id))
                    throw new InvalidDataException("Calibrated roster id is invalid or duplicated: " + id);
                string tierId = RequiredString(item, "tierId");
                if (!tiersById.TryGetValue(tierId, out TierDefinition tier))
                    throw new InvalidDataException("Calibrated roster references unknown tier: " + tierId);
                int equivalentLevel = PositiveInt(item, "equivalentLevel");
                int equivalentLevelMin = PositiveInt(item, "equivalentLevelMin");
                int equivalentLevelMax = PositiveInt(item, "equivalentLevelMax");
                if (equivalentLevelMin > equivalentLevel || equivalentLevel > equivalentLevelMax
                        || equivalentLevelMin < tier.LevelMin || equivalentLevelMax > tier.LevelMax)
                {
                    throw new InvalidDataException("Calibrated roster equivalent level is outside its tier: " + id);
                }
                string assignmentBasis = RequiredString(item, "assignmentBasis");
                if (assignmentBasis != "workbook_source_band" && assignmentBasis != "exact_human_pve_override")
                    throw new InvalidDataException("Calibrated roster assignment basis is invalid: " + id);
                if (PositiveInt(item, "sourceCandidateMinSamples") < 30)
                    throw new InvalidDataException("Calibrated roster has fewer than 30 source samples: " + id);

                JObject machine = item["machineValidation"] as JObject
                    ?? throw new InvalidDataException("Calibrated roster machineValidation is required: " + id);
                double timeoutRate = RequiredFiniteNumber(machine, "sourceCandidateTimeoutRateMax");
                if (timeoutRate < 0d || timeoutRate > 0.1d
                        || NonNegativeInt(machine, "sourceCandidateErrorCount") != 0
                        || machine["sideSwapReviewed"]?.Type != JTokenType.Boolean
                        || machine.Value<bool>("sideSwapReviewed") != true)
                {
                    throw new InvalidDataException("Calibrated roster machine gate is not satisfied: " + id);
                }

                JArray members = item["members"] as JArray
                    ?? throw new InvalidDataException("Calibrated roster members are required: " + id);
                if (members.Count == 0) throw new InvalidDataException("Calibrated roster is empty: " + id);
                var canonicalRoster = new JArray();
                var expectedKnownEnemies = new HashSet<string>(StringComparer.Ordinal);
                var memberKeys = new HashSet<string>(StringComparer.Ordinal);
                foreach (JToken memberToken in members)
                {
                    if (memberToken is not JObject member)
                        throw new InvalidDataException("Calibrated roster member must be an object: " + id);
                    string type = RequiredString(member, "type");
                    string spriteName = RequiredString(member, "spritename");
                    RequiredString(member, "name");
                    int level = PositiveInt(member, "level");
                    int count = PositiveInt(member, "count");
                    if (!type.StartsWith("兵种", StringComparison.Ordinal)
                            || !knownUnitIdentities.Contains(type + "\0" + spriteName)
                            || member["humanoid"]?.Type != JTokenType.Boolean
                            || count > MaximumCalibratedRosterEntries)
                    {
                        throw new InvalidDataException("Calibrated roster member is invalid: " + id);
                    }
                    JObject parameters = null;
                    if (member["parameters"] != null && member["parameters"].Type != JTokenType.Null)
                    {
                        parameters = member["parameters"] as JObject
                            ?? throw new InvalidDataException("Calibrated roster parameters must be an object: " + id);
                        if (parameters.ToString(Formatting.None).Length > 8192)
                            throw new InvalidDataException("Calibrated roster parameters are too large: " + id);
                    }
                    string memberKey = type + "\0" + level.ToString(CultureInfo.InvariantCulture) + "\0"
                        + (parameters == null ? string.Empty : StableCloneToken(parameters).ToString(Formatting.None));
                    if (!memberKeys.Add(memberKey))
                        throw new InvalidDataException("Calibrated roster contains an uncollapsed duplicate member: " + id);
                    bool humanoid = member.Value<bool>("humanoid");
                    if (humanoid != spriteName.Contains("主角", StringComparison.Ordinal))
                        throw new InvalidDataException("Calibrated roster humanoid classification is invalid: " + id);
                    if (!humanoid) expectedKnownEnemies.Add(spriteName);
                    for (int index = 0; index < count; index++)
                    {
                        var canonical = new JObject
                        {
                            ["type"] = type,
                            ["level"] = level
                        };
                        if (parameters != null) canonical["Parameters"] = parameters.DeepClone();
                        canonicalRoster.Add(canonical);
                    }
                }
                if (canonicalRoster.Count == 0 || canonicalRoster.Count > MaximumCalibratedRosterEntries)
                    throw new InvalidDataException("Calibrated roster expanded count is invalid: " + id);

                string[] requiredKnownEnemies = RequiredStringArray(item, "requiredKnownEnemies");
                if (!expectedKnownEnemies.SetEquals(requiredKnownEnemies))
                    throw new InvalidDataException("Calibrated roster known-enemy closure is invalid: " + id);
                result.Add(new CalibratedRosterDefinition
                {
                    Id = id,
                    TierId = tierId,
                    DisplayName = RequiredString(item, "displayName"),
                    EquivalentLevel = equivalentLevel,
                    AssignmentBasis = assignmentBasis,
                    Members = (JArray)members.DeepClone(),
                    CanonicalRoster = canonicalRoster,
                    RequiredKnownEnemies = requiredKnownEnemies
                });
            }
            return result;
        }

        private static HashSet<string> ParseUnitIdentities(byte[] bytes)
        {
            JArray source;
            try
            {
                source = JArray.Parse(Encoding.UTF8.GetString(bytes));
            }
            catch (Exception error)
            {
                throw new InvalidDataException("data/units/units.json is not a valid JSON array.", error);
            }
            var result = new HashSet<string>(StringComparer.Ordinal);
            var ids = new HashSet<int>();
            foreach (JToken token in source)
            {
                if (token is not JObject item)
                    throw new InvalidDataException("data/units/units.json entry must be an object.");
                int id = NonNegativeInt(item, "id");
                string spriteName = RequiredString(item, "spritename");
                string identity = "兵种" + id.ToString(CultureInfo.InvariantCulture) + "\0" + spriteName;
                if (!ids.Add(id) || !result.Add(identity))
                    throw new InvalidDataException("data/units/units.json contains a duplicate unit identity: " + id);
            }
            if (result.Count == 0) throw new InvalidDataException("data/units/units.json contains no units.");
            return result;
        }

        internal static string ComputeCatalogHash(JObject root)
        {
            JObject clone = (JObject)root.DeepClone();
            clone.Remove("catalogHash");
            string canonical = StableCloneToken(clone).ToString(Formatting.None);
            using SHA256 sha256 = SHA256.Create();
            byte[] digest = sha256.ComputeHash(Encoding.UTF8.GetBytes(canonical));
            return "sha256:" + Convert.ToHexString(digest).ToLowerInvariant();
        }

        private static JToken StableCloneToken(JToken token)
        {
            if (token is JObject obj)
            {
                var result = new JObject();
                foreach (JProperty property in obj.Properties().OrderBy(property => property.Name, StringComparer.Ordinal))
                    result.Add(property.Name, StableCloneToken(property.Value));
                return result;
            }
            if (token is JArray array)
                return new JArray(array.Select(StableCloneToken));
            return token.DeepClone();
        }

        private static bool IsCalibratedRosterId(string value)
        {
            const string prefix = "roster-";
            if (value == null || value.Length != prefix.Length + 16
                    || !value.StartsWith(prefix, StringComparison.Ordinal)) return false;
            for (int index = prefix.Length; index < value.Length; index++)
            {
                char character = value[index];
                if (!((character >= '0' && character <= '9') || (character >= 'a' && character <= 'f')))
                    return false;
            }
            return true;
        }

        private static string[] RequiredStringArray(JObject item, string name)
        {
            if (item[name] is not JArray array)
                throw new InvalidDataException("Arena JSON string array is required: " + name);
            string[] values = array.Select(token => token.Type == JTokenType.String ? token.Value<string>() : null).ToArray();
            if (values.Any(string.IsNullOrWhiteSpace)
                    || values.Distinct(StringComparer.Ordinal).Count() != values.Length)
            {
                throw new InvalidDataException("Arena JSON string array is invalid: " + name);
            }
            return values;
        }

        private static double RequiredFiniteNumber(JObject item, string name)
        {
            JToken token = item[name];
            if (token == null || (token.Type != JTokenType.Integer && token.Type != JTokenType.Float))
                throw new InvalidDataException("Arena JSON finite number is required: " + name);
            double value = token.Value<double>();
            if (double.IsNaN(value) || double.IsInfinity(value))
                throw new InvalidDataException("Arena JSON finite number is required: " + name);
            return value;
        }

        private static JObject ParseObject(byte[] bytes, string name)
        {
            try
            {
                JToken token = JToken.Parse(Encoding.UTF8.GetString(bytes));
                return token as JObject ?? throw new InvalidDataException(name + " root must be an object.");
            }
            catch (JsonException error)
            {
                throw new InvalidDataException(name + " is not valid JSON.", error);
            }
        }

        private static JObject ReadParameters(JObject item)
        {
            JToken token = item["Parameters"] ?? item["parameters"] ?? item["参数"];
            if (token == null || token.Type == JTokenType.Null) return null;
            return token as JObject
                ?? throw new InvalidDataException("Arena unit Parameters must be an object.");
        }

        private static string RequiredAttribute(XElement element, string name)
        {
            string value = (string)element.Attribute(name);
            if (string.IsNullOrWhiteSpace(value))
                throw new InvalidDataException("Missing arena XML attribute: " + name);
            return value;
        }

        private static int PositiveIntAttribute(XElement element, string name)
        {
            if (!int.TryParse(RequiredAttribute(element, name), NumberStyles.None, CultureInfo.InvariantCulture, out int value)
                    || value < 1)
            {
                throw new InvalidDataException("Arena XML attribute must be a positive integer: " + name);
            }
            return value;
        }

        private static decimal PositiveDecimalAttribute(XElement element, string name)
        {
            if (!decimal.TryParse(RequiredAttribute(element, name), NumberStyles.AllowDecimalPoint,
                    CultureInfo.InvariantCulture, out decimal value) || value <= 0m)
            {
                throw new InvalidDataException("Arena XML attribute must be a positive decimal: " + name);
            }
            return value;
        }

        private static bool BoolAttribute(XElement element, string name)
        {
            if (!bool.TryParse(RequiredAttribute(element, name), out bool value))
                throw new InvalidDataException("Arena XML attribute must be boolean: " + name);
            return value;
        }

        private static string RequiredString(JObject item, string name)
        {
            JToken token = item[name];
            if (token?.Type != JTokenType.String || string.IsNullOrWhiteSpace(token.Value<string>()))
                throw new InvalidDataException("Arena JSON string is required: " + name);
            return token.Value<string>();
        }

        private static string RequiredScalarId(JObject item, string name)
        {
            JToken token = item[name];
            if (token == null || (token.Type != JTokenType.String && token.Type != JTokenType.Integer))
                throw new InvalidDataException("Arena JSON scalar id is required: " + name);
            string value = Convert.ToString(((JValue)token).Value, CultureInfo.InvariantCulture);
            if (string.IsNullOrWhiteSpace(value)) throw new InvalidDataException("Arena JSON id is blank: " + name);
            return value;
        }

        private static int PositiveInt(JObject item, string name)
        {
            JToken token = item[name];
            if (token?.Type != JTokenType.Integer || token.Value<long>() < 1 || token.Value<long>() > int.MaxValue)
                throw new InvalidDataException("Arena JSON positive integer is required: " + name);
            return token.Value<int>();
        }

        private static int NonNegativeInt(JObject item, string name)
        {
            JToken token = item[name];
            if (token?.Type != JTokenType.Integer || token.Value<long>() < 0 || token.Value<long>() > int.MaxValue)
                throw new InvalidDataException("Arena JSON non-negative integer is required: " + name);
            return token.Value<int>();
        }

        private sealed class TierDefinition
        {
            internal string Id;
            internal int Index;
            internal int LevelMin;
            internal int LevelMax;
            internal int CountMin;
            internal int CountMax;
        }

        private sealed class HiddenDefinition
        {
            internal string Id;
            internal string Label;
            internal int Offset;
            internal int CountMin;
            internal int CountMax;
            internal bool RequiresMixedRoster;
            internal decimal EconomyMultiplier;
        }

        private sealed class FactionDefinition
        {
            internal string DisplayName;
            internal int? BenchLevel;
            internal string Scale;
            internal bool Enabled;
            internal string[] Units;
        }

        internal sealed class CalibratedRosterDefinition
        {
            internal string Id;
            internal string TierId;
            internal string DisplayName;
            internal int EquivalentLevel;
            internal string AssignmentBasis;
            internal JArray Members;
            internal JArray CanonicalRoster;
            internal string[] RequiredKnownEnemies;

            internal JObject ToSnapshot(string scopedId, string scopedCardId)
            {
                return new JObject
                {
                    ["id"] = scopedId,
                    ["cardId"] = scopedCardId,
                    ["displayName"] = DisplayName,
                    ["equivalentLevel"] = EquivalentLevel,
                    ["assignmentBasis"] = AssignmentBasis,
                    ["members"] = Members.DeepClone()
                };
            }
        }

        internal sealed class UnitDefinition
        {
            internal string Type;
            internal string SpriteName;
            internal int MinLevel;
            internal int MaxLevel;
            internal int Weight;
            internal JObject Parameters;
            internal bool IsHumanoidTemplate => SpriteName?.Contains("主角", StringComparison.Ordinal) == true;
        }
    }

    internal sealed class ArenaAuthoritySession
    {
        private const int MaximumRosterEntries = 12;
        private readonly Dictionary<string, ArenaAuthorityCard> _cards;
        private readonly Dictionary<string, ArenaAuthorityCatalog.CalibratedRosterDefinition> _calibratedRosters;
        private readonly HashSet<string> _knownEnemies;
        private readonly Dictionary<string, List<ArenaAuthorityCatalog.UnitDefinition>> _unitsByType;
        private readonly Dictionary<string, int> _mercenaryLevels;

        internal ArenaAuthoritySession(
            string sourceDigest,
            IEnumerable<ArenaAuthorityCard> cards,
            IEnumerable<ArenaAuthorityCatalog.CalibratedRosterDefinition> calibratedRosters,
            HashSet<string> knownEnemies,
            Dictionary<string, List<ArenaAuthorityCatalog.UnitDefinition>> unitsByType,
            Dictionary<string, int> mercenaryLevels)
        {
            SourceDigest = sourceDigest;
            SessionId = Guid.NewGuid().ToString("N");
            Cards = cards.ToList();
            _cards = Cards.ToDictionary(
                card => ScopeCardId(card.Id),
                StringComparer.Ordinal);
            CalibratedRosters = calibratedRosters.ToList();
            _calibratedRosters = CalibratedRosters.ToDictionary(
                roster => ScopeCalibratedRosterId(roster.Id),
                StringComparer.Ordinal);
            _knownEnemies = knownEnemies;
            _unitsByType = unitsByType;
            _mercenaryLevels = mercenaryLevels;
        }

        internal string SourceDigest { get; }
        internal string SessionId { get; }
        internal IReadOnlyList<ArenaAuthorityCard> Cards { get; }
        internal IReadOnlyList<ArenaAuthorityCatalog.CalibratedRosterDefinition> CalibratedRosters { get; }

        internal JObject ToSnapshot()
        {
            return new JObject
            {
                ["schemaVersion"] = 1,
                ["source"] = ArenaAuthorityCatalog.SourceDescription,
                ["sourceDigest"] = SourceDigest,
                ["cards"] = new JArray(Cards.Select(ToSessionCardSnapshot)),
                ["calibratedRosters"] = new JArray(CalibratedRosters.Select(ToSessionCalibratedRosterSnapshot))
            };
        }

        private JObject ToSessionCardSnapshot(ArenaAuthorityCard card)
        {
            JObject snapshot = card.ToSnapshot();
            snapshot["id"] = ScopeCardId(card.Id);
            return snapshot;
        }

        private JObject ToSessionCalibratedRosterSnapshot(ArenaAuthorityCatalog.CalibratedRosterDefinition roster)
        {
            return roster.ToSnapshot(
                ScopeCalibratedRosterId(roster.Id),
                ScopeCardId(roster.TierId));
        }

        private string ScopeCardId(string authorityId)
        {
            return SessionId + ":" + authorityId;
        }

        private string ScopeCalibratedRosterId(string authorityId)
        {
            return SessionId + ":calibrated:" + authorityId;
        }

        internal bool TryGetCard(string cardId, out ArenaAuthorityCard card)
        {
            card = null;
            return !string.IsNullOrWhiteSpace(cardId) && _cards.TryGetValue(cardId, out card);
        }

        internal bool TryResolveCalibratedRoster(
            string calibratedRosterId,
            ArenaAuthorityCard card,
            out JArray roster,
            out string error)
        {
            roster = null;
            error = null;
            if (card == null || card.Mode != "standard")
            {
                error = "calibrated_roster_not_supported";
                return false;
            }
            if (string.IsNullOrWhiteSpace(calibratedRosterId)
                    || !_calibratedRosters.TryGetValue(calibratedRosterId, out ArenaAuthorityCatalog.CalibratedRosterDefinition definition))
            {
                error = "stale_calibrated_roster";
                return false;
            }
            if (!string.Equals(definition.TierId, card.Id, StringComparison.Ordinal))
            {
                error = "wrong_calibrated_roster_tier";
                return false;
            }
            roster = (JArray)definition.CanonicalRoster.DeepClone();
            return true;
        }

        internal bool TrySanitizeRoster(
            JToken rosterToken,
            ArenaAuthorityCard card,
            bool customPve,
            out JArray roster,
            out string error)
        {
            roster = null;
            error = null;
            if (rosterToken == null || rosterToken.Type == JTokenType.Null)
            {
                if (card != null && (card.Mode == "hidden" || card.Mode == "fallen"))
                {
                    error = "roster_required";
                    return false;
                }
                return true;
            }
            if (rosterToken is not JArray source || source.Count == 0 || source.Count > MaximumRosterEntries)
            {
                error = "invalid_roster";
                return false;
            }

            var output = new JArray();
            int humanoidCount = 0;
            int nonHumanCount = 0;
            foreach (JToken token in source)
            {
                if (token is not JObject item || item.ToString(Formatting.None).Length > 8192)
                {
                    error = "invalid_roster";
                    return false;
                }
                string kind = item.Value<string>("kind") ?? string.Empty;
                if (kind == "merc" || item["mercId"] != null)
                {
                    if (customPve || card == null || (card.Mode != "standard" && card.Mode != "hidden"))
                    {
                        error = "invalid_roster";
                        return false;
                    }
                    string mercId = ScalarId(item["mercId"]);
                    if (mercId == null || !_mercenaryLevels.TryGetValue(mercId, out int mercLevel))
                    {
                        error = "unknown_mercenary";
                        return false;
                    }
                    int requestedLevel = ReadPositiveInt(item["level"]);
                    if (requestedLevel != mercLevel)
                    {
                        error = "invalid_roster_level";
                        return false;
                    }
                    output.Add(new JObject
                    {
                        ["kind"] = "merc",
                        ["mercId"] = mercId,
                        ["level"] = mercLevel
                    });
                    humanoidCount++;
                    continue;
                }

                string type = item.Value<string>("type");
                int level = ReadPositiveInt(item["level"]);
                if (string.IsNullOrWhiteSpace(type) || level < 1 || level > 1000)
                {
                    error = "invalid_roster";
                    return false;
                }
                JToken parameters = item["Parameters"] ?? item["parameters"] ?? item["参数"];
                if (parameters?.Type == JTokenType.Null) parameters = null;
                if (parameters != null && parameters.Type != JTokenType.Object)
                {
                    error = "invalid_roster_parameters";
                    return false;
                }
                ArenaAuthorityCatalog.UnitDefinition matchedUnit = null;
                if (!customPve && !TryResolveKnownUnit(type, level, parameters, out matchedUnit))
                {
                    error = "unknown_or_out_of_band_roster_unit";
                    return false;
                }
                if (card != null && card.Mode == "fallen" && !card.AllowedTypes.Contains(type))
                {
                    error = "wrong_faction_unit";
                    return false;
                }
                var clean = new JObject { ["type"] = type, ["level"] = level };
                if (parameters != null)
                {
                    clean["Parameters"] = parameters.DeepClone();
                }
                output.Add(clean);
                if (!customPve && matchedUnit.IsHumanoidTemplate) humanoidCount++;
                else nonHumanCount++;
            }
            if (card != null && card.Mode == "fallen" && output.Count != card.OpponentCount)
            {
                error = "invalid_roster_count";
                return false;
            }
            if (card != null && card.RequiresMixedRoster
                    && (humanoidCount == 0 || nonHumanCount == 0))
            {
                error = "invalid_mixed_roster";
                return false;
            }
            roster = output;
            return true;
        }

        private bool TryResolveKnownUnit(
            string type,
            int level,
            JToken parameters,
            out ArenaAuthorityCatalog.UnitDefinition matched)
        {
            matched = null;
            if (!_unitsByType.TryGetValue(type, out List<ArenaAuthorityCatalog.UnitDefinition> entries))
                return false;
            matched = entries.FirstOrDefault(unit =>
                (unit.IsHumanoidTemplate || _knownEnemies.Contains(unit.SpriteName))
                && level >= unit.MinLevel && level <= unit.MaxLevel
                && ParametersEqual(unit.Parameters, parameters));
            return matched != null;
        }

        private static bool ParametersEqual(JObject expected, JToken actual)
        {
            if (expected == null) return actual == null;
            return actual != null && JToken.DeepEquals(expected, actual);
        }

        private static string ScalarId(JToken token)
        {
            if (token == null || (token.Type != JTokenType.String && token.Type != JTokenType.Integer)) return null;
            string value = Convert.ToString(((JValue)token).Value, CultureInfo.InvariantCulture);
            return string.IsNullOrWhiteSpace(value) ? null : value;
        }

        private static int ReadPositiveInt(JToken token)
        {
            return token?.Type == JTokenType.Integer && token.Value<long>() >= 1 && token.Value<long>() <= int.MaxValue
                ? token.Value<int>()
                : -1;
        }
    }

    internal sealed class ArenaAuthorityCard
    {
        private ArenaAuthorityCard() { }

        internal string Id { get; private set; }
        internal string Mode { get; private set; }
        internal int Index { get; private set; }
        internal int PreviewIndex { get; private set; }
        internal int LevelMin { get; private set; }
        internal int LevelMax { get; private set; }
        internal int CountMin { get; private set; }
        internal int CountMax { get; private set; }
        internal int OpponentCount { get; private set; }
        internal decimal EconomyMultiplier { get; private set; }
        internal string HiddenLabel { get; private set; }
        internal bool RequiresMixedRoster { get; private set; }
        internal string Faction { get; private set; }
        internal string DisplayName { get; private set; }
        internal int BenchLevel { get; private set; }
        internal int MaxWaves { get; private set; }
        internal long Deposit { get; private set; }
        internal long Reward { get; private set; }
        internal string Expression { get; private set; }
        internal JArray Pool { get; private set; }
        internal HashSet<string> AllowedTypes { get; private set; }

        internal static ArenaAuthorityCard CreateStandard(
            string id,
            string mode,
            int index,
            int previewIndex,
            int levelMin,
            int levelMax,
            int countMin,
            int countMax,
            int opponentCount,
            decimal multiplier,
            string hiddenLabel,
            bool requiresMixedRoster)
        {
            long baseReward = RoundTo((decimal)opponentCount * levelMin * (levelMin >= 40 ? 1250 : 1000), 1000);
            long reward = RoundTo(baseReward * multiplier, 1000);
            return new ArenaAuthorityCard
            {
                Id = id,
                Mode = mode,
                Index = index,
                PreviewIndex = previewIndex,
                LevelMin = levelMin,
                LevelMax = levelMax,
                CountMin = countMin,
                CountMax = countMax,
                OpponentCount = opponentCount,
                EconomyMultiplier = multiplier,
                HiddenLabel = hiddenLabel ?? string.Empty,
                RequiresMixedRoster = requiresMixedRoster,
                Reward = reward,
                Deposit = Math.Max(500, RoundTo(reward / 2m, 500)),
                Expression = BuildExpression(levelMin, levelMax, opponentCount),
                Pool = new JArray(),
                AllowedTypes = new HashSet<string>(StringComparer.Ordinal)
            };
        }

        internal static ArenaAuthorityCard CreateFaction(
            string id,
            string mode,
            string faction,
            string displayName,
            int levelMin,
            int levelMax,
            int benchLevel,
            int opponentCount,
            int maxWaves,
            JArray pool)
        {
            long reward;
            long deposit;
            if (mode == "escalation")
            {
                reward = RoundTo((decimal)benchLevel * opponentCount * 500m, 100);
                deposit = RoundTo(reward, 1000);
            }
            else
            {
                reward = RoundTo((decimal)benchLevel * opponentCount * 800m, 1000);
                deposit = RoundTo(reward * 0.4m, 1000);
            }
            return new ArenaAuthorityCard
            {
                Id = id,
                Mode = mode,
                Faction = faction,
                DisplayName = displayName,
                LevelMin = levelMin,
                LevelMax = levelMax,
                BenchLevel = benchLevel,
                OpponentCount = opponentCount,
                CountMin = opponentCount,
                CountMax = opponentCount,
                MaxWaves = maxWaves,
                EconomyMultiplier = 1m,
                Reward = reward,
                Deposit = deposit,
                Expression = BuildExpression(levelMin, levelMax, opponentCount),
                Pool = (JArray)pool.DeepClone(),
                AllowedTypes = new HashSet<string>(
                    pool.OfType<JObject>().Select(item => item.Value<string>("type")),
                    StringComparer.Ordinal)
            };
        }

        internal JObject ToSnapshot()
        {
            var result = new JObject
            {
                ["id"] = Id,
                ["mode"] = Mode,
                ["name"] = "DEATH MATCH角斗场",
                ["opponentCount"] = OpponentCount,
                ["countMin"] = CountMin,
                ["countMax"] = CountMax,
                ["levelMin"] = LevelMin,
                ["levelMax"] = LevelMax,
                ["deposit"] = Deposit,
                ["reward"] = Reward,
                ["expr"] = Expression
            };
            if (Index > 0) result["index"] = Index;
            if (Mode == "standard" || Mode == "hidden") result["previewIndex"] = PreviewIndex;
            if (Mode == "hidden")
            {
                result["economyMultiplier"] = EconomyMultiplier;
                result["hiddenLabel"] = HiddenLabel;
                result["isHiddenChallenge"] = true;
                result["requiresMixedRoster"] = RequiresMixedRoster;
            }
            if (Mode == "fallen" || Mode == "escalation")
            {
                result["faction"] = Faction;
                result["displayName"] = DisplayName;
                result["benchLevel"] = BenchLevel;
                result["maxWaves"] = MaxWaves;
                result["unitCount"] = Pool.Count;
                result["isFallen"] = true;
                if (Mode == "escalation") result["isEscalation"] = true;
            }
            return result;
        }

        internal void WriteAuthorityFields(JObject target)
        {
            target["authorityId"] = Id;
            target["authorityMode"] = Mode;
            target["levelMin"] = LevelMin;
            target["levelMax"] = LevelMax;
            target["opponentCount"] = OpponentCount;
            target["economyMultiplier"] = EconomyMultiplier;
            target["benchLevel"] = BenchLevel;
            target["expr"] = Expression;
            target["deposit"] = Deposit;
            target["reward"] = Reward;
        }

        private static string BuildExpression(int levelMin, int levelMax, int count)
        {
            return "#0@" + levelMin + "-" + levelMax + "%" + count;
        }

        private static long RoundTo(decimal value, long step)
        {
            decimal quotient = value / step;
            long rounded = checked((long)Math.Floor(quotient + 0.5m));
            return Math.Max(step, checked(rounded * step));
        }
    }
}
