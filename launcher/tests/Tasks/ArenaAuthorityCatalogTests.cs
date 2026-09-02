using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using CF7Launcher.Tasks;
using Newtonsoft.Json.Linq;
using Xunit;

namespace CF7Launcher.Tests.Tasks
{
    public sealed class ArenaAuthorityCatalogTests
    {
        [Fact]
        public void XmlAuthority_MaterializesCanonicalStandardAndHiddenQuotes()
        {
            ArenaAuthorityCatalog catalog = ArenaAuthorityCatalog.Load(FindProjectRoot());
            ArenaAuthoritySession session = catalog.CreateSession(
                28,
                Array.Empty<string>(),
                delegate(int minimum, int maximum) { return maximum; });

            Assert.Equal(12, session.Cards.Count);
            ArenaAuthorityCard publicCard = Assert.Single(session.Cards, card => card.Id == "arena-2");
            Assert.Equal("standard", publicCard.Mode);
            Assert.Equal(2, publicCard.OpponentCount);
            Assert.Equal("#0@5-10%2", publicCard.Expression);
            Assert.Equal(10000, publicCard.Reward);
            Assert.Equal(5000, publicCard.Deposit);

            ArenaAuthorityCard hidden = Assert.Single(session.Cards, card => card.Id == "arena-hidden-1");
            Assert.Equal("hidden", hidden.Mode);
            Assert.Equal(3, hidden.OpponentCount);
            Assert.Equal("#0@30-35%3", hidden.Expression);
            Assert.Equal(135000, hidden.Reward);
            Assert.Equal(67500, hidden.Deposit);
            Assert.Matches("^[0-9A-F]{64}$", session.SourceDigest);
            JObject authority = session.ToSnapshot();
            Assert.Equal(ArenaAuthorityCatalog.SourceDescription, authority.Value<string>("source"));
            Assert.IsType<JArray>(authority["calibratedRosters"]);
        }

        [Fact]
        public void CalibratedRoster_IsKnownEnemyFilteredSessionScopedAndHostCanonical()
        {
            string fixtureRoot = CreateActiveCalibratedFixture(out string requiredEnemy, out JObject expectedRosterEntry);
            try
            {
                ArenaAuthorityCatalog catalog = ArenaAuthorityCatalog.Load(fixtureRoot);
                ArenaAuthoritySession unknownSession = catalog.CreateSession(
                    10,
                    Array.Empty<string>(),
                    delegate(int minimum, int maximum) { return minimum; });
                Assert.Empty(unknownSession.CalibratedRosters);
                Assert.Empty(Assert.IsType<JArray>(unknownSession.ToSnapshot()["calibratedRosters"]));

                ArenaAuthoritySession knownSession = catalog.CreateSession(
                    10,
                    new[] { requiredEnemy },
                    delegate(int minimum, int maximum) { return minimum; });
                JObject knownSnapshot = knownSession.ToSnapshot();
                JObject calibrated = Assert.Single(Assert.IsType<JArray>(knownSnapshot["calibratedRosters"]).OfType<JObject>());
                Assert.EndsWith(":calibrated:roster-0123456789abcdef", calibrated.Value<string>("id"), StringComparison.Ordinal);
                Assert.EndsWith(":arena-1", calibrated.Value<string>("cardId"), StringComparison.Ordinal);
                ArenaAuthorityCard arena1 = knownSession.Cards.Single(card => card.Id == "arena-1");
                ArenaAuthorityCard arena2 = knownSession.Cards.Single(card => card.Id == "arena-2");
                Assert.True(knownSession.TryResolveCalibratedRoster(
                    calibrated.Value<string>("id"), arena1, out JArray directRoster, out string directError));
                Assert.Null(directError);
                Assert.True(JToken.DeepEquals(expectedRosterEntry, directRoster[0]));
                Assert.False(knownSession.TryResolveCalibratedRoster(
                    calibrated.Value<string>("id"), arena2, out _, out string wrongTierError));
                Assert.Equal("wrong_calibrated_roster_tier", wrongTierError);

                var sent = new List<string>();
                var posted = new List<JObject>();
                using var task = new ArenaTask(delegate { return true; }, payload => sent.Add(payload), catalog);
                task.SetPostToWeb(json => posted.Add(JObject.Parse(json)));
                EstablishSnapshot(task, sent, "arena.snapshot.calibrated", new[] { requiredEnemy });
                JObject authority = (JObject)posted[^1]["snapshot"]["arenaAuthority"];
                JObject card = authority["cards"].OfType<JObject>()
                    .Single(item => item.Value<string>("mode") == "standard" && item.Value<int>("index") == 1);
                JObject scopedRoster = Assert.Single(Assert.IsType<JArray>(authority["calibratedRosters"]).OfType<JObject>());

                int before = sent.Count;
                task.HandleWebRequest("enter", new JObject
                {
                    ["callId"] = "arena.enter.calibrated.forged-id",
                    ["cardId"] = card.Value<string>("id"),
                    ["cardIndex"] = card.Value<int>("previewIndex"),
                    ["calibratedRosterId"] = "forged"
                });
                Assert.Equal(before, sent.Count);
                Assert.Equal("stale_calibrated_roster", posted[^1].Value<string>("error"));

                task.HandleWebRequest("enter", new JObject
                {
                    ["callId"] = "arena.enter.calibrated.forged-roster",
                    ["cardId"] = card.Value<string>("id"),
                    ["cardIndex"] = card.Value<int>("previewIndex"),
                    ["calibratedRosterId"] = scopedRoster.Value<string>("id"),
                    ["roster"] = new JArray(new JObject { ["type"] = "兵种999999", ["level"] = 999 })
                });
                Assert.Equal(before, sent.Count);
                Assert.Equal("invalid_calibrated_roster_payload", posted[^1].Value<string>("error"));

                task.HandleWebRequest("enter", new JObject
                {
                    ["callId"] = "arena.enter.calibrated.valid",
                    ["cardId"] = card.Value<string>("id"),
                    ["cardIndex"] = card.Value<int>("previewIndex"),
                    ["calibratedRosterId"] = scopedRoster.Value<string>("id")
                });
                Assert.Equal(before + 1, sent.Count);
                JObject enter = ParseWire(sent[^1]);
                JArray canonicalRoster = Assert.IsType<JArray>(enter["roster"]);
                Assert.Single(canonicalRoster);
                Assert.True(JToken.DeepEquals(expectedRosterEntry, canonicalRoster[0]));
                Assert.Null(enter["calibratedRosterId"]);
            }
            finally
            {
                Directory.Delete(fixtureRoot, true);
            }
        }

        [Fact]
        public void CalibratedRoster_RejectsUnknownUnitEvenWithRecomputedCatalogHash()
        {
            string fixtureRoot = CreateActiveCalibratedFixture(out _, out _);
            try
            {
                string catalogPath = Path.Combine(fixtureRoot, "data", "arena", "arena_calibrated_rosters.json");
                JObject catalog = JObject.Parse(File.ReadAllText(catalogPath));
                JObject roster = Assert.Single(Assert.IsType<JArray>(catalog["rosters"]).OfType<JObject>());
                JObject member = Assert.Single(Assert.IsType<JArray>(roster["members"]).OfType<JObject>());
                member["type"] = "兵种999999";
                catalog["catalogHash"] = ArenaAuthorityCatalog.ComputeCatalogHash(catalog);
                File.WriteAllText(catalogPath, catalog.ToString());

                InvalidDataException error = Assert.Throws<InvalidDataException>(() => ArenaAuthorityCatalog.Load(fixtureRoot));
                Assert.Contains("member is invalid", error.Message, StringComparison.Ordinal);
            }
            finally
            {
                Directory.Delete(fixtureRoot, true);
            }
        }

        [Fact]
        public void Task_IgnoresForgedClientEconomyAndBuildsFlashCommandFromSnapshotCard()
        {
            ArenaAuthorityCatalog catalog = ArenaAuthorityCatalog.Load(FindProjectRoot());
            var sent = new List<string>();
            var posted = new List<JObject>();
            using var task = new ArenaTask(
                delegate { return true; },
                payload => sent.Add(payload),
                catalog);
            task.SetPostToWeb(json => posted.Add(JObject.Parse(json)));

            task.HandleWebRequest("snapshot", new JObject
            {
                ["callId"] = "arena.snapshot.1",
                ["expr"] = "client-must-not-pass"
            });
            JObject snapshotCommand = ParseWire(sent[0]);
            task.HandleFlashResponse(new JObject
            {
                ["task"] = "arena_response",
                ["callId"] = snapshotCommand.Value<int>("callId"),
                ["success"] = true,
                ["snapshot"] = new JObject
                {
                    ["money"] = 1000000,
                    ["playerLevel"] = 28,
                    ["knownEnemies"] = new JArray()
                }
            }, _ => { });

            JObject authority = (JObject)posted[0]["snapshot"]["arenaAuthority"];
            JObject card = authority["cards"].OfType<JObject>()
                .Single(item => item.Value<int>("index") == 2);
            string scopedCardId = card.Value<string>("id");
            Assert.EndsWith(":arena-2", scopedCardId, StringComparison.Ordinal);
            int beforePreview = sent.Count;
            task.HandleWebRequest("preview", new JObject
            {
                ["callId"] = "arena.preview.1",
                ["cardId"] = scopedCardId,
                ["cardIndex"] = card.Value<int>("previewIndex"),
                ["expr"] = "#0@999-999%999",
                ["deposit"] = 1,
                ["reward"] = 999999999
            });
            Assert.Equal(beforePreview + 1, sent.Count);
            JObject preview = ParseWire(sent[^1]);
            Assert.Equal("arenaRollPreview", preview.Value<string>("action"));
            Assert.Equal(card.Value<string>("expr"), preview.Value<string>("expr"));
            Assert.Equal(card.Value<long>("deposit"), preview.Value<long>("deposit"));
            Assert.Equal(card.Value<long>("reward"), preview.Value<long>("reward"));
            Assert.NotEqual("#0@999-999%999", preview.Value<string>("expr"));
            Assert.Equal(authority.Value<string>("sourceDigest"), preview.Value<string>("authoritySourceDigest"));

            task.HandleWebRequest("enter", new JObject
            {
                ["callId"] = "arena.enter.1",
                ["cardId"] = scopedCardId,
                ["cardIndex"] = card.Value<int>("previewIndex"),
                ["expr"] = "forged",
                ["deposit"] = 0,
                ["reward"] = 0,
                ["difficulty"] = "冒险"
            });
            JObject enter = ParseWire(sent[^1]);
            Assert.Equal("arenaEnter", enter.Value<string>("action"));
            Assert.Equal(card.Value<string>("expr"), enter.Value<string>("expr"));
            Assert.Equal(card.Value<long>("deposit"), enter.Value<long>("deposit"));
            Assert.Equal(card.Value<long>("reward"), enter.Value<long>("reward"));
            Assert.Equal("冒险", enter.Value<string>("difficulty"));
        }

        [Fact]
        public void Task_RejectsUnknownOrStaleCardBeforeFlashDispatch()
        {
            ArenaAuthorityCatalog catalog = ArenaAuthorityCatalog.Load(FindProjectRoot());
            var sent = new List<string>();
            var posted = new List<JObject>();
            using var task = new ArenaTask(
                delegate { return true; },
                payload => sent.Add(payload),
                catalog);
            task.SetPostToWeb(json => posted.Add(JObject.Parse(json)));

            task.HandleWebRequest("enter", new JObject
            {
                ["callId"] = "arena.enter.before-snapshot",
                ["cardId"] = "arena-1",
                ["cardIndex"] = 0
            });
            Assert.Empty(sent);
            Assert.Equal("authority_snapshot_required", posted[0].Value<string>("error"));

            EstablishSnapshot(task, sent, "arena.snapshot.2", Array.Empty<string>());
            int before = sent.Count;
            task.HandleWebRequest("preview", new JObject
            {
                ["callId"] = "arena.preview.unknown",
                ["cardId"] = "arena-client-invented",
                ["cardIndex"] = 0
            });
            Assert.Equal(before, sent.Count);
            Assert.Equal("stale_authority", posted[^1].Value<string>("error"));

            JObject firstAuthority = (JObject)posted[^2]["snapshot"]["arenaAuthority"];
            JObject firstCard = firstAuthority["cards"].OfType<JObject>()
                .Single(item => item.Value<int>("index") == 1);
            string retiredCardId = firstCard.Value<string>("id");
            EstablishSnapshot(task, sent, "arena.snapshot.reopen", Array.Empty<string>());
            JObject reopenedAuthority = (JObject)posted[^1]["snapshot"]["arenaAuthority"];
            JObject reopenedCard = reopenedAuthority["cards"].OfType<JObject>()
                .Single(item => item.Value<int>("index") == 1);
            Assert.NotEqual(retiredCardId, reopenedCard.Value<string>("id"));

            before = sent.Count;
            task.HandleWebRequest("preview", new JObject
            {
                ["callId"] = "arena.preview.retired-session",
                ["cardId"] = retiredCardId,
                ["cardIndex"] = firstCard.Value<int>("previewIndex")
            });
            Assert.Equal(before, sent.Count);
            Assert.Equal("stale_authority", posted[^1].Value<string>("error"));
        }

        [Fact]
        public void Escalation_InjectsCanonicalPoolAndDropsAllClientAuthorityFields()
        {
            string root = FindProjectRoot();
            ArenaAuthorityCatalog catalog = ArenaAuthorityCatalog.Load(root);
            JArray known = ReadAllKnownEnemies(root);
            var sent = new List<string>();
            var posted = new List<JObject>();
            using var task = new ArenaTask(
                delegate { return true; },
                payload => sent.Add(payload),
                catalog);
            task.SetPostToWeb(json => posted.Add(JObject.Parse(json)));
            EstablishSnapshot(task, sent, "arena.snapshot.3", known.Values<string>());

            JObject authority = (JObject)posted[^1]["snapshot"]["arenaAuthority"];
            JObject card = authority["cards"].OfType<JObject>()
                .Single(item => item.Value<string>("mode") == "escalation"
                    && item.Value<string>("faction") == "波斯军");
            task.HandleWebRequest("enter", new JObject
            {
                ["callId"] = "arena.enter.escalation",
                ["cardId"] = card.Value<string>("id"),
                ["cardIndex"] = 0,
                ["mode"] = "client-mode",
                ["faction"] = "伪造势力",
                ["baseCount"] = 999,
                ["maxWaves"] = 999,
                ["deposit"] = 1,
                ["reward"] = 1,
                ["pool"] = new JArray(new JObject { ["type"] = "兵种999999" })
            });

            JObject enter = ParseWire(sent[^1]);
            Assert.Equal("escalation", enter.Value<string>("mode"));
            Assert.Equal("波斯军", enter.Value<string>("faction"));
            Assert.Equal(card.Value<int>("opponentCount"), enter.Value<int>("baseCount"));
            Assert.Equal(card.Value<int>("maxWaves"), enter.Value<int>("maxWaves"));
            Assert.Equal(card.Value<long>("deposit"), enter.Value<long>("deposit"));
            Assert.Equal(card.Value<long>("reward"), enter.Value<long>("reward"));
            JArray pool = Assert.IsType<JArray>(enter["pool"]);
            Assert.NotEmpty(pool);
            Assert.DoesNotContain(pool.OfType<JObject>(), item => item.Value<string>("type") == "兵种999999");
        }

        [Fact]
        public void RosterAuthority_RejectsAmbiguousMercenaryAndForgedUnitVariant()
        {
            string root = FindProjectRoot();
            ArenaAuthoritySession session = ArenaAuthorityCatalog.Load(root).CreateSession(
                60,
                ReadAllKnownEnemies(root).Values<string>(),
                delegate(int minimum, int maximum) { return maximum; });

            ArenaAuthorityCard standard = session.Cards.Single(card => card.Id == "arena-8");
            Assert.False(session.TrySanitizeRoster(
                new JArray(new JObject
                {
                    ["kind"] = "merc",
                    ["mercId"] = 5528,
                    ["level"] = 31
                }),
                standard,
                false,
                out _,
                out string ambiguousError));
            Assert.Equal("unknown_mercenary", ambiguousError);

            ArenaAuthorityCard fallen = session.Cards.Single(card => card.Id == "fallen-黑铁会");
            JObject poolUnit = fallen.Pool.OfType<JObject>().First(unit =>
                unit.Value<int>("minLevel") <= fallen.LevelMax
                && unit.Value<int>("maxLevel") >= fallen.LevelMin);
            int level = Math.Max(poolUnit.Value<int>("minLevel"), fallen.LevelMin);
            var canonicalRoster = new JArray();
            for (int index = 0; index < fallen.OpponentCount; index++)
            {
                var unit = new JObject
                {
                    ["type"] = poolUnit.Value<string>("type"),
                    ["level"] = level
                };
                if (poolUnit["Parameters"] != null)
                    unit["Parameters"] = poolUnit["Parameters"].DeepClone();
                canonicalRoster.Add(unit);
            }
            Assert.True(session.TrySanitizeRoster(
                canonicalRoster,
                fallen,
                false,
                out JArray sanitized,
                out string validError));
            Assert.Null(validError);
            Assert.Equal(fallen.OpponentCount, sanitized.Count);

            JArray forgedVariant = (JArray)canonicalRoster.DeepClone();
            ((JObject)forgedVariant[0])["Parameters"] = new JObject { ["forged"] = true };
            Assert.False(session.TrySanitizeRoster(
                forgedVariant,
                fallen,
                false,
                out _,
                out string forgedError));
            Assert.Equal("unknown_or_out_of_band_roster_unit", forgedError);

            JArray wrongCount = new JArray(canonicalRoster.Take(fallen.OpponentCount - 1));
            Assert.False(session.TrySanitizeRoster(
                wrongCount,
                fallen,
                false,
                out _,
                out string countError));
            Assert.Equal("invalid_roster_count", countError);
        }

        private static void EstablishSnapshot(
            ArenaTask task,
            List<string> sent,
            string webCallId,
            IEnumerable<string> knownEnemies)
        {
            task.HandleWebRequest("snapshot", new JObject { ["callId"] = webCallId });
            JObject command = ParseWire(sent[^1]);
            task.HandleFlashResponse(new JObject
            {
                ["task"] = "arena_response",
                ["callId"] = command.Value<int>("callId"),
                ["success"] = true,
                ["snapshot"] = new JObject
                {
                    ["money"] = 10000000,
                    ["playerLevel"] = 60,
                    ["knownEnemies"] = new JArray(knownEnemies)
                }
            }, _ => { });
        }

        private static JObject ParseWire(string wire)
        {
            return JObject.Parse(wire.TrimEnd('\0'));
        }

        private static JArray ReadAllKnownEnemies(string root)
        {
            JObject teams = JObject.Parse(File.ReadAllText(
                Path.Combine(root, "data", "arena", "meta_teams.json")));
            return new JArray(
                ((JObject)teams["rosters"]).Properties()
                    .SelectMany(property => ((JArray)property.Value["units"]).OfType<JObject>())
                    .Select(unit => unit.Value<string>("spritename"))
                    .Where(value => !string.IsNullOrWhiteSpace(value))
                    .Distinct(StringComparer.Ordinal));
        }

        private static string CreateActiveCalibratedFixture(
            out string requiredEnemy,
            out JObject expectedRosterEntry)
        {
            string sourceRoot = FindProjectRoot();
            string fixtureRoot = Path.Combine(Path.GetTempPath(), "cf7-arena-calibrated-" + Guid.NewGuid().ToString("N"));
            string arenaRoot = Path.Combine(fixtureRoot, "data", "arena");
            Directory.CreateDirectory(arenaRoot);
            foreach (string name in new[] { "arena_config.xml", "meta_teams.json", "arena_factions.json" })
            {
                File.Copy(
                    Path.Combine(sourceRoot, "data", "arena", name),
                    Path.Combine(arenaRoot, name));
            }
            string unitsRoot = Path.Combine(fixtureRoot, "data", "units");
            Directory.CreateDirectory(unitsRoot);
            File.Copy(
                Path.Combine(sourceRoot, "data", "units", "units.json"),
                Path.Combine(unitsRoot, "units.json"));

            JObject teams = JObject.Parse(File.ReadAllText(Path.Combine(arenaRoot, "meta_teams.json")));
            JObject unit = ((JObject)teams["rosters"]).Properties()
                .SelectMany(property => ((JArray)property.Value["units"]).OfType<JObject>())
                .First(item => item.Value<int>("minLevel") <= 5
                    && item.Value<int>("maxLevel") >= 1
                    && !item.Value<string>("spritename").Contains("主角", StringComparison.Ordinal));
            int level = Math.Max(1, unit.Value<int>("minLevel"));
            requiredEnemy = unit.Value<string>("spritename");
            var member = new JObject
            {
                ["type"] = unit.Value<string>("type"),
                ["level"] = level,
                ["count"] = 1,
                ["name"] = unit.Value<string>("name") ?? unit.Value<string>("type"),
                ["spritename"] = requiredEnemy,
                ["humanoid"] = false
            };
            JToken parameters = unit["Parameters"] ?? unit["parameters"] ?? unit["参数"];
            expectedRosterEntry = new JObject
            {
                ["type"] = unit.Value<string>("type"),
                ["level"] = level
            };
            if (parameters != null && parameters.Type != JTokenType.Null)
            {
                member["parameters"] = parameters.DeepClone();
                expectedRosterEntry["Parameters"] = parameters.DeepClone();
            }

            var catalog = new JObject
            {
                ["schemaVersion"] = 1,
                ["active"] = true,
                ["catalogId"] = "arena-calibrated-rosters-test-v1",
                ["campaignId"] = "test-campaign",
                ["cohortId"] = "test-cohort",
                ["source"] = new JObject(),
                ["model"] = new JObject(),
                ["rosters"] = new JArray(new JObject
                {
                    ["id"] = "roster-0123456789abcdef",
                    ["displayName"] = "标定 fixture",
                    ["equivalentLevel"] = level,
                    ["equivalentLevelMin"] = level,
                    ["equivalentLevelMax"] = level,
                    ["tierId"] = "arena-1",
                    ["assignmentBasis"] = "workbook_source_band",
                    ["sourceBands"] = new JArray("1-5级"),
                    ["sourceCells"] = new JArray("T1"),
                    ["candidateIds"] = new JArray("candidate-test"),
                    ["samples"] = 60,
                    ["sourceCandidateMinSamples"] = 60,
                    ["machineValidation"] = new JObject
                    {
                        ["component"] = 0,
                        ["withinComponentStrength"] = 0.0,
                        ["lower95"] = -0.1,
                        ["upper95"] = 0.1,
                        ["sourceCandidateTimeoutRateMax"] = 0.0,
                        ["sourceCandidateErrorCount"] = 0,
                        ["sideSwapReviewed"] = true
                    },
                    ["members"] = new JArray(member),
                    ["requiredKnownEnemies"] = new JArray(requiredEnemy)
                }),
                ["catalogHash"] = string.Empty
            };
            catalog["catalogHash"] = ArenaAuthorityCatalog.ComputeCatalogHash(catalog);
            File.WriteAllText(Path.Combine(arenaRoot, "arena_calibrated_rosters.json"), catalog.ToString());
            return fixtureRoot;
        }

        private static string FindProjectRoot()
        {
            foreach (string start in new[] { Environment.CurrentDirectory, AppContext.BaseDirectory })
            {
                DirectoryInfo directory = new DirectoryInfo(start);
                while (directory != null)
                {
                    if (File.Exists(Path.Combine(directory.FullName, "data", "arena", "arena_config.xml"))
                            && File.Exists(Path.Combine(directory.FullName, "launcher", "CRAZYFLASHER7MercenaryEmpire.csproj")))
                    {
                        return directory.FullName;
                    }
                    directory = directory.Parent;
                }
            }
            throw new DirectoryNotFoundException("Cannot locate CF7 project root for Arena authority tests.");
        }
    }
}
