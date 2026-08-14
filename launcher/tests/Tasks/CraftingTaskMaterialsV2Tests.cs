using System;
using System.Collections.Generic;
using System.Globalization;
using Newtonsoft.Json.Linq;
using Xunit;
using CF7Launcher.Tasks;

namespace Launcher.Tests.Tasks
{
    public sealed class CraftingTaskMaterialsV2Tests
    {
        private const string PanelInstanceId = "panel.crafting.materials.v2";
        private const string MaterialName = "战术握把";

        internal sealed class Harness : IDisposable
        {
            public readonly List<JObject> Sent = new List<JObject>();
            public readonly CraftingTask Task;
            public string Web;

            public Harness()
            {
                Task = new CraftingTask(() => true, value =>
                {
                    Sent.Add(JObject.Parse(value.TrimEnd('\0')));
                    return true;
                });
                Task.SetPostToWeb(value => Web = value);
            }

            public int Send(
                string cmd, string callId, JObject payload,
                string panelInstanceId = PanelInstanceId)
            {
                int before = Sent.Count;
                Task.HandleWebRequest(cmd, Request(cmd, callId, payload, panelInstanceId));
                return Sent.Count == before ? -1 : (int)Sent[Sent.Count - 1]["callId"];
            }

            public JObject LastWeb()
            {
                return Web == null ? null : JObject.Parse(Web);
            }

            public void Dispose() { Task.Dispose(); }
        }

        [Fact]
        public void Requests_UseCommandSpecificVersionShapes()
        {
            using (var harness = new Harness())
            {
                int fid = harness.Send("materials", "v2.materials", new JObject { ["v"] = 2 });
                Assert.True(fid > 0);
                Assert.Equal(2, (int)harness.Sent[0]["v"]);
                Assert.Equal("craftingMaterials", (string)harness.Sent[0]["action"]);

                int sentBefore = harness.Sent.Count;
                JObject snapshotV2 = new JObject { ["v"] = 2, ["category"] = "武器合成" };
                Assert.Equal(-1, harness.Send("snapshot", "v2.snapshot.rejected", snapshotV2));
                Assert.Equal(sentBefore, harness.Sent.Count);
                Assert.Equal("invalid_payload", (string)harness.LastWeb()["error"]);
                Assert.Null(harness.LastWeb()["v"]);

                JObject detailV2 = new JObject
                {
                    ["v"] = 2, ["itemName"] = MaterialName,
                    ["snapshotId"] = "materials.snapshot.unbound"
                };
                Assert.Equal(-1, harness.Send("materialDetail", "v2.detail.unbound", detailV2));
                Assert.Equal("stale_snapshot", (string)harness.LastWeb()["error"]);
                Assert.Null(harness.LastWeb()["v"]);

                JObject materialsExtra = new JObject { ["v"] = 2, ["extra"] = true };
                Assert.Equal(-1, harness.Send("materials", "v2.materials.extra", materialsExtra));
                Assert.Equal("invalid_payload", (string)harness.LastWeb()["error"]);
            }
        }

        [Fact]
        public void Requests_RejectUnknownOrNonIntegerVersionsAndCrossVersionKeys()
        {
            JToken[] versions =
            {
                new JValue(0), new JValue(3), new JValue(1.0),
                new JValue("2"), JValue.CreateNull(), new JValue(true)
            };
            using (var harness = new Harness())
            {
                for (int index = 0; index < versions.Length; index++)
                {
                    Assert.Equal(-1, harness.Send(
                        "materials", "version.materials." + index,
                        new JObject { ["v"] = versions[index].DeepClone() }));
                    Assert.Equal("invalid_payload", (string)harness.LastWeb()["error"]);

                    Assert.Equal(-1, harness.Send(
                        "materialDetail", "version.detail." + index,
                        new JObject
                        {
                            ["v"] = versions[index].DeepClone(), ["itemName"] = MaterialName
                        }));
                    Assert.Equal("invalid_payload", (string)harness.LastWeb()["error"]);
                }

                Assert.Equal(-1, harness.Send(
                    "materials", "version.v1-mixed",
                    new JObject { ["v"] = 1, ["snapshotId"] = "forbidden" }));
                Assert.Equal(-1, harness.Send(
                    "materialDetail", "version.detail-v1-mixed",
                    new JObject
                    {
                        ["v"] = 1, ["itemName"] = MaterialName,
                        ["snapshotId"] = "forbidden"
                    }));
                Assert.Equal("invalid_payload", (string)harness.LastWeb()["error"]);
            }
        }

        [Fact]
        public void MaterialRecipeNavigation_BindsExistingV2SnapshotWithoutChangingOrdinarySnapshot()
        {
            const string snapshotId = "materials.snapshot.navigation";
            using (var harness = OpenV2Session(snapshotId))
            {
                int ordinaryFid = harness.Send(
                    "snapshot", "navigation.ordinary",
                    new JObject { ["v"] = 1, ["category"] = "武器合成" });
                Assert.True(ordinaryFid > 0);
                Assert.Null(harness.Sent[harness.Sent.Count - 1]["materialSnapshotId"]);
                harness.Task.HandleFlashResponse(Failure(ordinaryFid, "category_not_found"), null);

                int sentBefore = harness.Sent.Count;
                Assert.Equal(-1, harness.Send(
                    "snapshot", "navigation.stale",
                    new JObject
                    {
                        ["v"] = 1, ["category"] = "武器合成",
                        ["materialSnapshotId"] = "materials.snapshot.other"
                    }));
                Assert.Equal(sentBefore, harness.Sent.Count);
                Assert.Equal("stale_snapshot", (string)harness.LastWeb()["error"]);

                int deniedFid = harness.Send(
                    "snapshot", "navigation.denied",
                    new JObject
                    {
                        ["v"] = 1, ["category"] = "武器合成",
                        ["materialSnapshotId"] = snapshotId
                    });
                Assert.True(deniedFid > 0);
                Assert.Equal(snapshotId,
                    (string)harness.Sent[harness.Sent.Count - 1]["materialSnapshotId"]);
                harness.Task.HandleFlashResponse(Failure(deniedFid, "access_denied"), null);
                Assert.Equal("access_denied", (string)harness.LastWeb()["error"]);

                int staleFid = harness.Send(
                    "snapshot", "navigation.flash-stale",
                    new JObject
                    {
                        ["v"] = 1, ["category"] = "武器合成",
                        ["materialSnapshotId"] = snapshotId
                    });
                harness.Task.HandleFlashResponse(Failure(staleFid, "stale_snapshot"), null);
                Assert.Equal("stale_snapshot", (string)harness.LastWeb()["error"]);

                Assert.Equal(-1, harness.Send(
                    "snapshot", "navigation.bad-token",
                    new JObject
                    {
                        ["v"] = 1, ["category"] = "武器合成",
                        ["materialSnapshotId"] = 7
                    }));
                Assert.Equal("invalid_payload", (string)harness.LastWeb()["error"]);
            }
        }

        [Fact]
        public void V2Catalog_RequiresExactNavigationAccessBooleans()
        {
            Action<JObject>[] mutations =
            {
                value => value.Remove("navigationAccess"),
                value => ((JObject)value["navigationAccess"]).Remove("shop"),
                value => value["navigationAccess"]["crafting"] = 1,
                value => value["navigationAccess"]["extra"] = false
            };
            for (int index = 0; index < mutations.Length; index++)
            {
                using (var harness = new Harness())
                {
                    int fid = harness.Send(
                        "materials", "navigation.catalog." + index,
                        new JObject { ["v"] = 2 });
                    JObject response = CatalogResponse(
                        fid, "materials.snapshot.navigation." + index,
                        CatalogMaterial(0, 2, 4, 1, 2));
                    mutations[index](response);
                    harness.Task.HandleFlashResponse(response, null);
                    Assert.Equal("malformed_response", (string)harness.LastWeb()["error"]);
                }
            }
        }

        [Fact]
        public void InitialMaterialsSuccess_RejectsMissingUnknownAndWrongDirectionVersion()
        {
            Action<JObject>[] mutations =
            {
                value => value.Remove("v"),
                value => value["v"] = 3,
                value => value["v"] = 1
            };
            for (int index = 0; index < mutations.Length; index++)
            {
                using (var harness = new Harness())
                {
                    int fid = harness.Send(
                        "materials", "response.version." + index,
                        new JObject { ["v"] = 2 });
                    JObject response = CatalogResponse(
                        fid, "materials.snapshot.response-version." + index,
                        CatalogMaterial(0, 2, 4, 1, 2));
                    mutations[index](response);
                    harness.Task.HandleFlashResponse(response, null);
                    Assert.Equal("malformed_response", (string)harness.LastWeb()["error"]);
                }
            }

            using (var harness = new Harness())
            {
                int fid = harness.Send(
                    "materials", "response.v1-to-v2", new JObject { ["v"] = 1 });
                harness.Task.HandleFlashResponse(CatalogResponse(
                    fid, "materials.snapshot.wrong-upgrade",
                    CatalogMaterial(0, 2, 4, 1, 2)), null);
                Assert.Equal("malformed_response", (string)harness.LastWeb()["error"]);
            }
        }

        [Fact]
        public void InitialV2Request_CanSelectExactV1LegacySessionOnly()
        {
            using (var harness = new Harness())
            {
                int fid = harness.Send("materials", "fallback.catalog", new JObject { ["v"] = 2 });
                harness.Task.HandleFlashResponse(V1Catalog(fid), null);
                JObject catalog = harness.LastWeb();
                Assert.True((bool)catalog["success"]);
                Assert.Equal(1, (int)catalog["v"]);
                Assert.Null(catalog["snapshotId"]);

                JObject v2Detail = new JObject
                {
                    ["v"] = 2, ["itemName"] = MaterialName,
                    ["snapshotId"] = "materials.snapshot.not-selected"
                };
                Assert.Equal(-1, harness.Send("materialDetail", "fallback.v2.detail", v2Detail));
                Assert.Equal("invalid_payload", (string)harness.LastWeb()["error"]);

                Assert.True(harness.Send("materialDetail", "fallback.v1.detail",
                    new JObject { ["v"] = 1, ["itemName"] = MaterialName }) > 0);
                Assert.Equal(-1, harness.Send("materials", "fallback.reshake",
                    new JObject { ["v"] = 2 }));
                Assert.Equal("invalid_payload", (string)harness.LastWeb()["error"]);
            }
        }

        [Fact]
        public void V2CatalogAndDetail_AreStrictAndSnapshotBound()
        {
            using (var harness = new Harness())
            {
                const string snapshotId = "materials.snapshot.42";
                JObject catalog = CatalogResponse(0, snapshotId, CatalogMaterial(0, 2, 4, 1, 2));
                int catalogFid = harness.Send("materials", "v2.catalog", new JObject { ["v"] = 2 });
                catalog["callId"] = catalogFid;
                harness.Task.HandleFlashResponse(catalog, null);
                Assert.True((bool)harness.LastWeb()["success"]);
                Assert.Equal(snapshotId, (string)harness.LastWeb()["snapshotId"]);

                JObject detailPayload = new JObject
                {
                    ["v"] = 2, ["itemName"] = MaterialName, ["snapshotId"] = snapshotId
                };
                int detailFid = harness.Send("materialDetail", "v2.detail", detailPayload);
                JObject detail = EnemyDetailResponse(detailFid, snapshotId);
                harness.Task.HandleFlashResponse(detail, null);
                JObject web = harness.LastWeb();
                Assert.True((bool)web["success"]);
                Assert.Equal(2, ((JArray)web["sources"]).Count);
                Assert.Equal(4, (int)web["dropVariantCount"]);

                int malformedFid = harness.Send("materialDetail", "v2.detail.extra", detailPayload);
                JObject malformed = EnemyDetailResponse(malformedFid, snapshotId);
                malformed["extra"] = true;
                harness.Task.HandleFlashResponse(malformed, null);
                Assert.Equal("malformed_response", (string)harness.LastWeb()["error"]);

                const string refreshedSnapshot = "materials.snapshot.43";
                int refreshFid = harness.Send("materials", "v2.refresh", new JObject { ["v"] = 2 });
                JObject refresh = CatalogResponse(
                    refreshFid, refreshedSnapshot, CatalogMaterial(0, 2, 4, 1, 2));
                harness.Task.HandleFlashResponse(refresh, null);
                Assert.True((bool)harness.LastWeb()["success"]);
                Assert.Equal(-1, harness.Send("materialDetail", "v2.stale.local", detailPayload));
                Assert.Equal("stale_snapshot", (string)harness.LastWeb()["error"]);
                Assert.Null(harness.LastWeb()["v"]);
            }
        }

        [Fact]
        public void V2Detail_InfrastructureUses_AreConditionalAndExact()
        {
            const string snapshotId = "materials.snapshot.infrastructure";
            using (var harness = OpenInfrastructureV2Session(snapshotId))
            {
                int fid = harness.Send(
                    "materialDetail", "infrastructure.valid", V2DetailPayload(snapshotId));
                harness.Task.HandleFlashResponse(
                    InfrastructureDetailResponse(fid, snapshotId), null);
                JObject web = harness.LastWeb();
                Assert.True((bool)web["success"]);
                Assert.Equal(2, ((JArray)web["infrastructureUses"]).Count);
                Assert.Equal("current",
                    (string)web["infrastructureUses"][0]["levels"][1]["status"]);

                int emptyFid = harness.Send(
                    "materialDetail", "infrastructure.empty", V2DetailPayload(snapshotId));
                JObject empty = InfrastructureDetailResponse(emptyFid, snapshotId);
                empty["infrastructureUses"] = new JArray();
                harness.Task.HandleFlashResponse(empty, null);
                Assert.True((bool)harness.LastWeb()["success"]);
            }

            using (var harness = OpenV2Session("materials.snapshot.historical"))
            {
                int fid = harness.Send("materialDetail", "infrastructure.historical-extra",
                    V2DetailPayload("materials.snapshot.historical"));
                JObject historical = EnemyDetailResponse(
                    fid, "materials.snapshot.historical");
                historical["infrastructureUses"] = new JArray();
                harness.Task.HandleFlashResponse(historical, null);
                Assert.Equal("malformed_response", (string)harness.LastWeb()["error"]);
            }

            Action<JObject>[] mutations =
            {
                value => value.Remove("infrastructureUses"),
                value => value["infrastructureUses"][0]["legacyId"] = 1,
                value => value["infrastructureUses"][1]["projectOrder"] = 0,
                value => value["infrastructureUses"][0]["currentLevel"] = 4,
                value => value["infrastructureUses"][0]["levels"][1]["targetLevel"] = 3,
                value => value["infrastructureUses"][0]["levels"][1]["status"] = "future",
                value => value["infrastructureUses"][0]["levels"][0]["missing"] = 31,
                value => value["infrastructureUses"][0]["levels"][1]["missing"] = 10,
                value => value["infrastructureUses"][0]["levels"][1]["owned"] = 470,
                value => value["infrastructureUses"][0]["levels"][2]["levelIndex"] = 1
            };
            for (int index = 0; index < mutations.Length; index++)
            {
                using (var harness = OpenInfrastructureV2Session(snapshotId + "." + index))
                {
                    int fid = harness.Send("materialDetail", "infrastructure.invalid." + index,
                        V2DetailPayload(snapshotId + "." + index));
                    JObject malformed = InfrastructureDetailResponse(
                        fid, snapshotId + "." + index);
                    mutations[index](malformed);
                    harness.Task.HandleFlashResponse(malformed, null);
                    Assert.Equal("malformed_response", (string)harness.LastWeb()["error"]);
                }
            }
        }

        [Theory]
        [InlineData(256, true)]
        [InlineData(257, false)]
        public void V2Detail_InfrastructureUses_EnforceProjectBoundary(
            int count, bool accepted)
        {
            const string snapshotId = "materials.snapshot.infrastructure-project-cap";
            using (var harness = OpenInfrastructureV2Session(snapshotId))
            {
                int fid = harness.Send(
                    "materialDetail", "infrastructure.projects." + count,
                    V2DetailPayload(snapshotId));
                JObject detail = InfrastructureDetailResponse(fid, snapshotId);
                var projects = new JArray();
                for (int index = 0; index < count; index++)
                {
                    projects.Add(InfrastructureProject(
                        "测试基建" + index, index, 0, 1, 470));
                }
                detail["infrastructureUses"] = projects;
                harness.Task.HandleFlashResponse(detail, null);
                Assert.Equal(accepted, (bool)harness.LastWeb()["success"]);
                if (!accepted)
                    Assert.Equal("malformed_response", (string)harness.LastWeb()["error"]);
            }
        }

        [Theory]
        [InlineData(128, true)]
        [InlineData(129, false)]
        public void V2Detail_InfrastructureUses_EnforceLevelBoundary(
            int count, bool accepted)
        {
            const string snapshotId = "materials.snapshot.infrastructure-level-cap";
            using (var harness = OpenInfrastructureV2Session(snapshotId))
            {
                int fid = harness.Send(
                    "materialDetail", "infrastructure.levels." + count,
                    V2DetailPayload(snapshotId));
                JObject detail = InfrastructureDetailResponse(fid, snapshotId);
                var requirements = new int[count];
                for (int index = 0; index < requirements.Length; index++)
                    requirements[index] = 470;
                detail["infrastructureUses"] = new JArray(
                    InfrastructureProject("测试基建", 0, 0, count, requirements));
                harness.Task.HandleFlashResponse(detail, null);
                Assert.Equal(accepted, (bool)harness.LastWeb()["success"]);
                if (!accepted)
                    Assert.Equal("malformed_response", (string)harness.LastWeb()["error"]);
            }
        }

        [Theory]
        [InlineData("snapshot")]
        [InlineData("preview")]
        [InlineData("tooltip")]
        [InlineData("commit")]
        public void OtherCraftingCommands_RemainV1Only(string cmd)
        {
            using (var harness = new Harness())
            {
                JObject payload = LegacyPayload(cmd);
                payload["v"] = 2;
                Assert.Equal(-1, harness.Send(cmd, "v2.rejected." + cmd, payload));
                Assert.Equal("invalid_payload", (string)harness.LastWeb()["error"]);
            }
        }

        [Fact]
        public void V2Detail_RejectsCorrelationCountsOrderAndOccurrenceDrift()
        {
            Action<JObject>[] mutations =
            {
                value => value["snapshotId"] = "materials.snapshot.foreign",
                value => value["sourceCount"] = 3,
                value => value["dropVariantCount"] = 3,
                value => value["material"]["owned"] = 470,
                value => value["material"]["sourceSummary"] = "",
                value => value["sources"][0]["sourceOrder"] = 1,
                value => value["sources"][0]["sourceKey"] = "lp1|5:enemy|1:x",
                value => value["sources"][0]["variants"][1]["occurrenceIndex"] = 0,
                value => value["sources"][0]["variants"][0]["chanceRaw"] = 4,
                value =>
                {
                    value["sources"][0]["enemyType"] = "军阀精英突击兵";
                    value["sources"][0]["sourceKey"] =
                        SourceKey("enemy", "军阀精英突击兵");
                },
                value => value["uses"][0]["recipeIndex"] = 1000,
                value => value["uses"][0]["ingredients"][0]["required"] = 2,
                value => value["uses"][0]["ingredients"][0]["icon"] = "",
                value => ((JArray)value["directPurposes"]).Add(
                    ((JObject)value["directPurposes"][0]).DeepClone())
            };
            for (int index = 0; index < mutations.Length; index++)
            {
                using (var harness = OpenV2Session("materials.snapshot.mutation"))
                {
                    JObject payload = V2DetailPayload("materials.snapshot.mutation");
                    int fid = harness.Send("materialDetail", "v2.mutation." + index, payload);
                    JObject detail = EnemyDetailResponse(fid, "materials.snapshot.mutation");
                    mutations[index](detail);
                    harness.Task.HandleFlashResponse(detail, null);
                    Assert.Equal("malformed_response", (string)harness.LastWeb()["error"]);
                }
            }
        }

        [Fact]
        public void V2ShopSource_AllowsOnlyFrozenUnavailableAccessPair()
        {
            using (var harness = new Harness())
            {
                const string snapshotId = "materials.snapshot.shop";
                JObject material = CatalogMaterial(0, 1, 0, 0, 1);
                material["recipePurposeIds"] = new JArray();
                int catalogFid = harness.Send("materials", "shop.catalog", new JObject { ["v"] = 2 });
                harness.Task.HandleFlashResponse(CatalogResponse(catalogFid, snapshotId, material), null);
                Assert.True((bool)harness.LastWeb()["success"]);

                int fid = harness.Send("materialDetail", "shop.detail", V2DetailPayload(snapshotId));
                JObject detail = EmptyDetailResponse(fid, snapshotId, 1, 0, 0, 1);
                ((JArray)detail["sources"]).Add(ShopSource(0));
                harness.Task.HandleFlashResponse(detail, null);
                Assert.True((bool)harness.LastWeb()["success"]);

                int refreshedFid = harness.Send(
                    "materialDetail", "shop.detail.refreshed", V2DetailPayload(snapshotId));
                JObject refreshed = EmptyDetailResponse(refreshedFid, snapshotId, 1, 0, 0, 1);
                JObject refreshedSource = ShopSource(0);
                refreshedSource["basePrice"] = 75000;
                refreshedSource["unitPriceAtSnapshot"] = 62500;
                refreshedSource["requiredInfo"] = "需要已记录的情报";
                refreshedSource["locked"] = true;
                ((JArray)refreshed["sources"]).Add(refreshedSource);
                harness.Task.HandleFlashResponse(refreshed, null);
                Assert.True((bool)harness.LastWeb()["success"]);
                Assert.True((bool)harness.LastWeb()["sources"][0]["locked"]);

                int badFid = harness.Send("materialDetail", "shop.detail.bad", V2DetailPayload(snapshotId));
                JObject bad = EmptyDetailResponse(badFid, snapshotId, 1, 0, 0, 1);
                JObject source = ShopSource(0);
                source["shopAccessMode"] = "full";
                ((JArray)bad["sources"]).Add(source);
                harness.Task.HandleFlashResponse(bad, null);
                Assert.Equal("malformed_response", (string)harness.LastWeb()["error"]);
            }
        }

        [Fact]
        public void StaleSnapshotFailure_IsVersionlessAndCommandSpecific()
        {
            using (var harness = OpenV2Session("materials.snapshot.failure"))
            {
                int fid = harness.Send("materialDetail", "failure.v2",
                    V2DetailPayload("materials.snapshot.failure"));
                harness.Task.HandleFlashResponse(Failure(fid, "stale_snapshot"), null);
                JObject failure = harness.LastWeb();
                Assert.Equal("stale_snapshot", (string)failure["error"]);
                Assert.Null(failure["v"]);

                harness.Task.ClearPending();
                int v1Fid = harness.Send("materialDetail", "failure.v1",
                    new JObject { ["v"] = 1, ["itemName"] = MaterialName });
                harness.Task.HandleFlashResponse(Failure(v1Fid, "stale_snapshot"), null);
                Assert.Equal("malformed_response", (string)harness.LastWeb()["error"]);
            }
        }

        [Theory]
        [InlineData(1, " ")]
        [InlineData(2, " ")]
        [InlineData(1, " Undefined ")]
        [InlineData(2, "uNdEfInEd")]
        [InlineData(1, "bad\u0001name")]
        [InlineData(2, "bad\u0001name")]
        public void MaterialDetailItemName_RejectsInvalidIdentityForBothVersions(
            int version, string itemName)
        {
            using (var harness = new Harness())
            {
                JObject payload = new JObject { ["v"] = version, ["itemName"] = itemName };
                if (version == 2) payload["snapshotId"] = "materials.snapshot.any";
                Assert.Equal(-1, harness.Send("materialDetail", "identity." + version, payload));
                Assert.Equal("invalid_payload", (string)harness.LastWeb()["error"]);
            }
        }

        [Fact]
        public void MaterialDetailItemName_UsesUtf16CodeUnitBoundary()
        {
            using (var harness = new Harness())
            {
                string atBoundary = new string('材', 128);
                Assert.True(harness.Send("materialDetail", "identity.128",
                    new JObject { ["v"] = 1, ["itemName"] = atBoundary }) > 0);
                Assert.Equal(-1, harness.Send("materialDetail", "identity.129",
                    new JObject { ["v"] = 1, ["itemName"] = atBoundary + "料" }));
                Assert.Equal("invalid_payload", (string)harness.LastWeb()["error"]);
            }
        }

        [Fact]
        public void V2Session_RejectsSuccessVersionShakeAndKeepsPriorSnapshot()
        {
            const string snapshotId = "materials.snapshot.locked";
            using (var harness = OpenV2Session(snapshotId))
            {
                int refreshFid = harness.Send(
                    "materials", "session.version-shake", new JObject { ["v"] = 2 });
                harness.Task.HandleFlashResponse(V1Catalog(refreshFid), null);
                Assert.Equal("malformed_response", (string)harness.LastWeb()["error"]);
                Assert.Null(harness.LastWeb()["v"]);

                int detailFid = harness.Send(
                    "materialDetail", "session.prior-detail", V2DetailPayload(snapshotId));
                harness.Task.HandleFlashResponse(
                    EnemyDetailResponse(detailFid, snapshotId), null);
                Assert.True((bool)harness.LastWeb()["success"]);

                Assert.Equal(-1, harness.Send(
                    "materials", "session.request-shake", new JObject { ["v"] = 1 }));
                Assert.Equal("invalid_payload", (string)harness.LastWeb()["error"]);
            }
        }

        [Fact]
        public void ClearPending_DropsSnapshotLockAndIgnoresRetiredCatalogResponse()
        {
            const string oldSnapshot = "materials.snapshot.retired";
            const string freshSnapshot = "materials.snapshot.fresh";
            using (var harness = OpenV2Session(oldSnapshot))
            {
                int retiredFid = harness.Send(
                    "materials", "session.retiring", new JObject { ["v"] = 2 });
                string beforeClear = harness.Web;
                harness.Task.ClearPending();
                harness.Task.HandleFlashResponse(CatalogResponse(
                    retiredFid, "materials.snapshot.late",
                    CatalogMaterial(0, 2, 4, 1, 2)), null);
                Assert.Equal(beforeClear, harness.Web);

                int freshFid = harness.Send(
                    "materials", "session.fresh", new JObject { ["v"] = 2 });
                harness.Task.HandleFlashResponse(CatalogResponse(
                    freshFid, freshSnapshot, CatalogMaterial(0, 2, 4, 1, 2)), null);
                Assert.True((bool)harness.LastWeb()["success"]);
                Assert.Equal(freshSnapshot, (string)harness.LastWeb()["snapshotId"]);

                Assert.Equal(-1, harness.Send(
                    "materialDetail", "session.retired-detail", V2DetailPayload(oldSnapshot)));
                Assert.Equal("stale_snapshot", (string)harness.LastWeb()["error"]);
            }
        }

        [Fact]
        public void LatestMaterialsRequest_AloneCanReplaceTheHostSnapshotProof()
        {
            const string initialSnapshot = "materials.snapshot.epoch.initial";
            const string supersededSnapshot = "materials.snapshot.epoch.superseded";
            const string latestSnapshot = "materials.snapshot.epoch.latest";
            using (var harness = OpenV2Session(initialSnapshot))
            {
                int supersededFid = harness.Send(
                    "materials", "epoch.superseded", new JObject { ["v"] = 2 });
                int latestFid = harness.Send(
                    "materials", "epoch.latest", new JObject { ["v"] = 2 });

                harness.Task.HandleFlashResponse(CatalogResponse(
                    supersededFid, supersededSnapshot,
                    CatalogMaterial(0, 2, 4, 1, 2)), null);
                Assert.True((bool)harness.LastWeb()["success"]);
                Assert.Equal(supersededSnapshot, (string)harness.LastWeb()["snapshotId"]);
                Assert.Equal(-1, harness.Send(
                    "materialDetail", "epoch.superseded-detail",
                    V2DetailPayload(supersededSnapshot)));
                Assert.Equal("stale_snapshot", (string)harness.LastWeb()["error"]);

                harness.Task.HandleFlashResponse(CatalogResponse(
                    latestFid, latestSnapshot, CatalogMaterial(0, 2, 4, 1, 2)), null);
                Assert.True((bool)harness.LastWeb()["success"]);
                int detailFid = harness.Send(
                    "materialDetail", "epoch.latest-detail", V2DetailPayload(latestSnapshot));
                harness.Task.HandleFlashResponse(
                    EnemyDetailResponse(detailFid, latestSnapshot), null);
                Assert.True((bool)harness.LastWeb()["success"]);
            }
        }

        [Fact]
        public void RefreshMakesAnAlreadyPendingOldDetailSuccessNonAuthoritative()
        {
            const string oldSnapshot = "materials.snapshot.flight.old";
            const string freshSnapshot = "materials.snapshot.flight.fresh";
            using (var harness = OpenV2Session(oldSnapshot))
            {
                int oldDetailFid = harness.Send(
                    "materialDetail", "flight.old-detail", V2DetailPayload(oldSnapshot));
                int refreshFid = harness.Send(
                    "materials", "flight.refresh", new JObject { ["v"] = 2 });
                harness.Task.HandleFlashResponse(CatalogResponse(
                    refreshFid, freshSnapshot, CatalogMaterial(0, 2, 4, 1, 2)), null);
                Assert.True((bool)harness.LastWeb()["success"]);

                harness.Task.HandleFlashResponse(
                    EnemyDetailResponse(oldDetailFid, oldSnapshot), null);
                Assert.Equal("malformed_response", (string)harness.LastWeb()["error"]);
                Assert.Equal("flight.old-detail", (string)harness.LastWeb()["callId"]);
                Assert.Null(harness.LastWeb()["snapshotId"]);
            }
        }

        [Fact]
        public void MaterialsSession_CannotCrossPanelInstanceRebind()
        {
            const string oldSnapshot = "materials.snapshot.instance.old";
            const string newSnapshot = "materials.snapshot.instance.new";
            const string newInstance = "panel.crafting.materials.v2.rebound";
            using (var harness = OpenV2Session(oldSnapshot))
            {
                Assert.Equal(-1, harness.Send(
                    "materialDetail", "instance.foreign-detail",
                    V2DetailPayload(oldSnapshot), newInstance));
                Assert.Equal("stale_snapshot", (string)harness.LastWeb()["error"]);
                Assert.Equal(newInstance, (string)harness.LastWeb()["panelInstanceId"]);

                int catalogFid = harness.Send(
                    "materials", "instance.new-catalog",
                    new JObject { ["v"] = 2 }, newInstance);
                harness.Task.HandleFlashResponse(CatalogResponse(
                    catalogFid, newSnapshot, CatalogMaterial(0, 2, 4, 1, 2)), null);
                Assert.True((bool)harness.LastWeb()["success"]);
                Assert.Equal(newInstance, (string)harness.LastWeb()["panelInstanceId"]);
            }
        }

        [Fact]
        public void V2FailureEnvelope_IsExactVersionlessAndCorrelationBound()
        {
            const string snapshotId = "materials.snapshot.failure-shape";
            using (var harness = OpenV2Session(snapshotId))
            {
                int acceptedFid = harness.Send(
                    "materialDetail", "failure.accepted", V2DetailPayload(snapshotId));
                harness.Task.HandleFlashResponse(Failure(acceptedFid, "busy"), null);
                JObject accepted = harness.LastWeb();
                Assert.False((bool)accepted["success"]);
                Assert.Equal("busy", (string)accepted["error"]);
                Assert.Null(accepted["v"]);
                Assert.Null(accepted["task"]);
                Assert.Equal(8, accepted.Count);

                Action<JObject>[] mutations =
                {
                    value => value["v"] = 2,
                    value => value["extra"] = true,
                    value => value["task"] = "other_response",
                    value => value["success"] = "false",
                    value => value["error"] = "bad\u0001error"
                };
                for (int index = 0; index < mutations.Length; index++)
                {
                    int fid = harness.Send("materialDetail", "failure.malformed." + index,
                        V2DetailPayload(snapshotId));
                    JObject failure = Failure(fid, "busy");
                    mutations[index](failure);
                    harness.Task.HandleFlashResponse(failure, null);
                    Assert.Equal("malformed_response", (string)harness.LastWeb()["error"]);
                    Assert.Null(harness.LastWeb()["v"]);
                }

                int correlatedFid = harness.Send(
                    "materialDetail", "failure.correlation", V2DetailPayload(snapshotId));
                string beforeMismatch = harness.Web;
                harness.Task.HandleFlashResponse(Failure(correlatedFid + 100000, "busy"), null);
                Assert.Equal(beforeMismatch, harness.Web);
                harness.Task.HandleFlashResponse(Failure(correlatedFid, "busy"), null);
                Assert.Equal("busy", (string)harness.LastWeb()["error"]);
            }
        }

        [Theory]
        [InlineData(4096, true)]
        [InlineData(4097, false)]
        public void V2Catalog_EnforcesMaterialCountBoundary(int count, bool accepted)
        {
            using (var harness = new Harness())
            {
                var materials = new JObject[count];
                for (int index = 0; index < count; index++)
                    materials[index] = GeneralCatalogMaterial(
                        "边界材料." + index, index, 0, 0, 0, null, null, false);
                int fid = harness.Send(
                    "materials", "limits.materials." + count, new JObject { ["v"] = 2 });
                harness.Task.HandleFlashResponse(CatalogResponse(
                    fid, "materials.snapshot.count." + count, materials), null);
                Assert.Equal(accepted, (bool)harness.LastWeb()["success"]);
                if (!accepted)
                    Assert.Equal("malformed_response", (string)harness.LastWeb()["error"]);
            }
        }

        [Theory]
        [InlineData(512, true)]
        [InlineData(513, false)]
        public void V2Detail_EnforcesSourceCountBoundary(int count, bool accepted)
        {
            const string snapshotId = "materials.snapshot.source-limit";
            using (var harness = OpenV2Session(
                snapshotId,
                GeneralCatalogMaterial(
                    MaterialName, 0, count, 0, 0, new JArray(),
                    new JArray("system:equipment_tuning"), true)))
            {
                int fid = harness.Send(
                    "materialDetail", "limits.sources." + count, V2DetailPayload(snapshotId));
                JObject detail = EmptyDetailResponse(fid, snapshotId, count, 0, 0, 1);
                for (int index = 0; index < count; index++)
                    ((JArray)detail["sources"]).Add(KShopSource(index));
                harness.Task.HandleFlashResponse(detail, null);
                Assert.Equal(accepted, (bool)harness.LastWeb()["success"]);
                if (!accepted)
                    Assert.Equal("malformed_response", (string)harness.LastWeb()["error"]);
            }
        }

        [Theory]
        [InlineData(128, true)]
        [InlineData(129, false)]
        public void V2Detail_EnforcesDropVariantBoundary(int count, bool accepted)
        {
            const string snapshotId = "materials.snapshot.variant-limit";
            using (var harness = OpenV2Session(
                snapshotId,
                GeneralCatalogMaterial(
                    MaterialName, 0, 1, count, 0, new JArray(),
                    new JArray("system:equipment_tuning"), true)))
            {
                int fid = harness.Send(
                    "materialDetail", "limits.variants." + count, V2DetailPayload(snapshotId));
                JObject detail = EmptyDetailResponse(fid, snapshotId, 1, count, 0, 1);
                ((JArray)detail["sources"]).Add(
                    EnemySource(0, "敌人-边界目标", "边界目标", count));
                harness.Task.HandleFlashResponse(detail, null);
                Assert.Equal(accepted, (bool)harness.LastWeb()["success"]);
                if (!accepted)
                    Assert.Equal("malformed_response", (string)harness.LastWeb()["error"]);
            }
        }

        [Theory]
        [InlineData(1024, true)]
        [InlineData(1025, false)]
        public void V2Detail_EnforcesRecipeUseBoundary(int count, bool accepted)
        {
            const string snapshotId = "materials.snapshot.use-limit";
            JArray recipePurposeIds = count <= 1000
                ? new JArray("recipe:铁枪会")
                : new JArray("recipe:铁枪会", "recipe:属性武器");
            using (var harness = OpenV2Session(
                snapshotId,
                GeneralCatalogMaterial(
                    MaterialName, 0, 0, 0, count, recipePurposeIds,
                    new JArray("system:equipment_tuning"), true)))
            {
                int fid = harness.Send(
                    "materialDetail", "limits.uses." + count, V2DetailPayload(snapshotId));
                JObject detail = EmptyDetailResponse(fid, snapshotId, 0, 0, count, count + 1);
                for (int index = 0; index < count; index++)
                {
                    string category = index < 1000 ? "铁枪会" : "属性武器";
                    int recipeIndex = index < 1000 ? index : index - 1000;
                    ((JArray)detail["uses"]).Add(RecipeUse(category, recipeIndex));
                }
                harness.Task.HandleFlashResponse(detail, null);
                Assert.Equal(accepted, (bool)harness.LastWeb()["success"]);
                if (!accepted)
                    Assert.Equal("malformed_response", (string)harness.LastWeb()["error"]);
            }
        }

        [Theory]
        [InlineData(128, true)]
        [InlineData(129, false)]
        public void V2Catalog_EnforcesPerMaterialDirectPurposeBoundary(
            int count, bool accepted)
        {
            using (var harness = new Harness())
            {
                int fid = harness.Send(
                    "materials", "limits.direct." + count, new JObject { ["v"] = 2 });
                JObject response = CatalogResponse(
                    fid, "materials.snapshot.direct." + count,
                    GeneralCatalogMaterial(
                        MaterialName, 0, 0, 0, 0, new JArray(),
                        DirectPurposeIds(count), true));
                response["taxonomy"] = Taxonomy(count);
                harness.Task.HandleFlashResponse(response, null);
                Assert.Equal(accepted, (bool)harness.LastWeb()["success"]);
                if (!accepted)
                    Assert.Equal("malformed_response", (string)harness.LastWeb()["error"]);
                else
                {
                    int detailFid = harness.Send(
                        "materialDetail", "limits.direct.detail." + count,
                        V2DetailPayload("materials.snapshot.direct." + count));
                    JObject detail = EmptyDetailResponse(
                        detailFid, "materials.snapshot.direct." + count,
                        0, 0, 0, count);
                    detail["directPurposes"] = DirectPurposeEntries(count);
                    harness.Task.HandleFlashResponse(detail, null);
                    Assert.True((bool)harness.LastWeb()["success"]);
                    Assert.Equal(count, ((JArray)harness.LastWeb()["directPurposes"]).Count);
                }
            }
        }

        [Theory]
        [InlineData(987, true)]
        [InlineData(988, false)]
        public void V2Catalog_EnforcesTaxonomyEntryBoundary(
            int directRegistryCount, bool accepted)
        {
            using (var harness = new Harness())
            {
                int fid = harness.Send(
                    "materials", "limits.taxonomy." + directRegistryCount,
                    new JObject { ["v"] = 2 });
                JObject response = CatalogResponse(
                    fid, "materials.snapshot.taxonomy." + directRegistryCount);
                response["taxonomy"] = Taxonomy(directRegistryCount);
                harness.Task.HandleFlashResponse(response, null);
                Assert.Equal(accepted, (bool)harness.LastWeb()["success"]);
                if (!accepted)
                    Assert.Equal("malformed_response", (string)harness.LastWeb()["error"]);
            }
        }

        [Fact]
        public void V2Detail_AcceptsEverySourceKindAndUtf16LengthPrefixedIdentity()
        {
            const string snapshotId = "materials.snapshot.source-union";
            using (var harness = OpenV2Session(
                snapshotId,
                GeneralCatalogMaterial(
                    MaterialName, 0, 6, 2, 0, new JArray(),
                    new JArray("system:equipment_tuning"), true)))
            {
                int fid = harness.Send(
                    "materialDetail", "source.union", V2DetailPayload(snapshotId));
                JObject detail = EmptyDetailResponse(fid, snapshotId, 6, 2, 0, 1);
                var sources = (JArray)detail["sources"];
                sources.Add(CraftSource(0));
                sources.Add(ShopSource(1));
                sources.Add(KShopSource(2, 0));
                JObject quest = QuestSource(3, "q:|😀");
                Assert.Equal("lp1|5:quest|5:q:|😀|4:base|1:0", (string)quest["sourceKey"]);
                sources.Add(quest);
                sources.Add(StageSource(4, "关卡:|😀", 8));
                sources.Add(EnemySource(5, "敌人-边界", "边界敌人", 1));
                harness.Task.HandleFlashResponse(detail, null);
                Assert.True((bool)harness.LastWeb()["success"]);
                Assert.Equal(6, ((JArray)harness.LastWeb()["sources"]).Count);
            }
        }

        [Fact]
        public void V2Detail_RejectsCraftSourceForAnotherMaterial()
        {
            const string snapshotId = "materials.snapshot.foreign-craft";
            using (var harness = OpenV2Session(
                snapshotId,
                GeneralCatalogMaterial(
                    MaterialName, 0, 1, 0, 0, new JArray(),
                    new JArray("system:equipment_tuning"), true)))
            {
                int fid = harness.Send(
                    "materialDetail", "source.foreign-craft", V2DetailPayload(snapshotId));
                JObject detail = EmptyDetailResponse(fid, snapshotId, 1, 0, 0, 1);
                JObject source = CraftSource(0);
                source["productName"] = "另一材料";
                ((JArray)detail["sources"]).Add(source);
                harness.Task.HandleFlashResponse(detail, null);
                Assert.Equal("malformed_response", (string)harness.LastWeb()["error"]);
            }
        }

        [Fact]
        public void V2Detail_AllowsMultilineTextButRejectsOtherControlCharacters()
        {
            const string snapshotId = "materials.snapshot.text";
            using (var harness = OpenV2Session(snapshotId))
            {
                int acceptedFid = harness.Send(
                    "materialDetail", "text.multiline", V2DetailPayload(snapshotId));
                JObject accepted = EnemyDetailResponse(acceptedFid, snapshotId);
                accepted["material"]["description"] = "第一行\r\n第二行\t说明";
                accepted["material"]["sourceSummary"] = "摘要一\n摘要二\t尾";
                harness.Task.HandleFlashResponse(accepted, null);
                Assert.True((bool)harness.LastWeb()["success"]);

                int controlFid = harness.Send(
                    "materialDetail", "text.control", V2DetailPayload(snapshotId));
                JObject control = EnemyDetailResponse(controlFid, snapshotId);
                control["material"]["description"] = "非法\u0001控制";
                harness.Task.HandleFlashResponse(control, null);
                Assert.Equal("malformed_response", (string)harness.LastWeb()["error"]);

                int identityFid = harness.Send(
                    "materialDetail", "text.identity", V2DetailPayload(snapshotId));
                JObject identity = EnemyDetailResponse(identityFid, snapshotId);
                identity["material"]["displayName"] = " Undefined ";
                harness.Task.HandleFlashResponse(identity, null);
                Assert.Equal("malformed_response", (string)harness.LastWeb()["error"]);
            }
        }

        [Theory]
        [InlineData(128, true)]
        [InlineData(129, false)]
        public void V2Catalog_EnforcesNameUtf16Boundary(int length, bool accepted)
        {
            using (var harness = new Harness())
            {
                string name = new string('材', length);
                int fid = harness.Send(
                    "materials", "text.name." + length, new JObject { ["v"] = 2 });
                harness.Task.HandleFlashResponse(CatalogResponse(
                    fid, "materials.snapshot.name." + length,
                    GeneralCatalogMaterial(name, 0, 0, 0, 0, null, null, false)), null);
                Assert.Equal(accepted, (bool)harness.LastWeb()["success"]);
                if (!accepted)
                    Assert.Equal("malformed_response", (string)harness.LastWeb()["error"]);
            }
        }

        [Theory]
        [InlineData(256, true)]
        [InlineData(257, false)]
        public void V2Catalog_EnforcesSnapshotIdUtf16Boundary(int length, bool accepted)
        {
            using (var harness = new Harness())
            {
                int fid = harness.Send(
                    "materials", "text.snapshot." + length, new JObject { ["v"] = 2 });
                harness.Task.HandleFlashResponse(CatalogResponse(
                    fid, new string('s', length), CatalogMaterial(0, 2, 4, 1, 2)), null);
                Assert.Equal(accepted, (bool)harness.LastWeb()["success"]);
                if (!accepted)
                    Assert.Equal("malformed_response", (string)harness.LastWeb()["error"]);
            }
        }

        [Fact]
        public void V2Detail_EnforcesDescriptionAndSummaryBoundaries()
        {
            const string snapshotId = "materials.snapshot.long-text";
            using (var harness = OpenV2Session(snapshotId))
            {
                int boundaryFid = harness.Send(
                    "materialDetail", "text.boundary", V2DetailPayload(snapshotId));
                JObject boundary = EnemyDetailResponse(boundaryFid, snapshotId);
                boundary["material"]["description"] = new string('述', 12000);
                boundary["material"]["sourceSummary"] = new string('摘', 20000);
                harness.Task.HandleFlashResponse(boundary, null);
                Assert.True((bool)harness.LastWeb()["success"]);

                int descriptionFid = harness.Send(
                    "materialDetail", "text.description-over", V2DetailPayload(snapshotId));
                JObject description = EnemyDetailResponse(descriptionFid, snapshotId);
                description["material"]["description"] = new string('述', 12001);
                harness.Task.HandleFlashResponse(description, null);
                Assert.Equal("malformed_response", (string)harness.LastWeb()["error"]);

                int summaryFid = harness.Send(
                    "materialDetail", "text.summary-over", V2DetailPayload(snapshotId));
                JObject summary = EnemyDetailResponse(summaryFid, snapshotId);
                summary["material"]["sourceSummary"] = new string('摘', 20001);
                harness.Task.HandleFlashResponse(summary, null);
                Assert.Equal("malformed_response", (string)harness.LastWeb()["error"]);
            }
        }

        [Theory]
        [InlineData(9007199254740991L, true)]
        [InlineData(9007199254740992L, false)]
        public void V2Catalog_EnforcesSafeIntegerBoundary(long owned, bool accepted)
        {
            using (var harness = new Harness())
            {
                int fid = harness.Send(
                    "materials", "number.safe." + accepted, new JObject { ["v"] = 2 });
                JObject material = CatalogMaterial(0, 2, 4, 1, 2);
                material["owned"] = owned;
                harness.Task.HandleFlashResponse(CatalogResponse(
                    fid, "materials.snapshot.safe." + accepted, material), null);
                Assert.Equal(accepted, (bool)harness.LastWeb()["success"]);
                if (!accepted)
                    Assert.Equal("malformed_response", (string)harness.LastWeb()["error"]);
            }
        }

        [Theory]
        [InlineData(0.0, true)]
        [InlineData(100.0, true)]
        [InlineData(-0.000001, false)]
        [InlineData(100.000001, false)]
        public void V2EnemyChance_EnforcesFiniteClosedRange(double chance, bool accepted)
        {
            const string snapshotId = "materials.snapshot.chance";
            using (var harness = OpenV2Session(
                snapshotId,
                GeneralCatalogMaterial(
                    MaterialName, 0, 1, 1, 0, new JArray(),
                    new JArray("system:equipment_tuning"), true)))
            {
                int fid = harness.Send(
                    "materialDetail", "chance." + chance.ToString(CultureInfo.InvariantCulture),
                    V2DetailPayload(snapshotId));
                JObject detail = EmptyDetailResponse(fid, snapshotId, 1, 1, 0, 1);
                JObject source = EnemySource(0, "敌人-概率边界", "概率边界", 1);
                source["variants"][0]["chanceRaw"] = chance;
                source["variants"][0]["nominalChancePercent"] = chance;
                ((JArray)detail["sources"]).Add(source);
                harness.Task.HandleFlashResponse(detail, null);
                Assert.Equal(accepted, (bool)harness.LastWeb()["success"]);
                if (!accepted)
                    Assert.Equal("malformed_response", (string)harness.LastWeb()["error"]);
            }
        }

        [Theory]
        [InlineData(false)]
        [InlineData(true)]
        public void V2EnemyChance_RejectsNonFiniteNumbers(bool positiveInfinity)
        {
            const string snapshotId = "materials.snapshot.nonfinite";
            using (var harness = OpenV2Session(
                snapshotId,
                GeneralCatalogMaterial(
                    MaterialName, 0, 1, 1, 0, new JArray(),
                    new JArray("system:equipment_tuning"), true)))
            {
                int fid = harness.Send(
                    "materialDetail", "chance.nonfinite." + positiveInfinity,
                    V2DetailPayload(snapshotId));
                JObject detail = EmptyDetailResponse(fid, snapshotId, 1, 1, 0, 1);
                JObject source = EnemySource(0, "敌人-非有限", "非有限", 1);
                double value = positiveInfinity ? double.PositiveInfinity : double.NaN;
                source["variants"][0]["chanceRaw"] = value;
                source["variants"][0]["nominalChancePercent"] = value;
                ((JArray)detail["sources"]).Add(source);
                harness.Task.HandleFlashResponse(detail, null);
                Assert.Equal("malformed_response", (string)harness.LastWeb()["error"]);
            }
        }

        [Theory]
        [InlineData("absent_defaulted")]
        [InlineData("invalid_defaulted")]
        public void V2EnemyChance_AcceptsCanonicalDefaultedStates(string state)
        {
            const string snapshotId = "materials.snapshot.defaulted";
            using (var harness = OpenV2Session(
                snapshotId,
                GeneralCatalogMaterial(
                    MaterialName, 0, 1, 1, 0, new JArray(),
                    new JArray("system:equipment_tuning"), true)))
            {
                int fid = harness.Send(
                    "materialDetail", "chance.defaulted." + state,
                    V2DetailPayload(snapshotId));
                JObject detail = EmptyDetailResponse(fid, snapshotId, 1, 1, 0, 1);
                JObject source = EnemySource(0, "敌人-缺省概率", "缺省概率", 1);
                source["variants"][0]["chanceRaw"] = JValue.CreateNull();
                source["variants"][0]["chanceInputState"] = state;
                source["variants"][0]["nominalChancePercent"] = 100;
                ((JArray)detail["sources"]).Add(source);
                harness.Task.HandleFlashResponse(detail, null);
                Assert.True((bool)harness.LastWeb()["success"]);
            }
        }

        [Theory]
        [InlineData(1, 100.0)]
        [InlineData(2, 50.0)]
        [InlineData(8, 12.5)]
        [InlineData(50, 2.0)]
        public void V2StageChance_AcceptsCanonicalRoundSix(int divisor, double expectedChance)
        {
            const string snapshotId = "materials.snapshot.stage";
            using (var harness = OpenV2Session(
                snapshotId,
                GeneralCatalogMaterial(
                    MaterialName, 0, 1, 1, 0, new JArray(),
                    new JArray("system:equipment_tuning"), true)))
            {
                int fid = harness.Send(
                    "materialDetail", "stage." + divisor, V2DetailPayload(snapshotId));
                JObject detail = EmptyDetailResponse(fid, snapshotId, 1, 1, 0, 1);
                JObject source = StageSource(0, "关卡-概率边界", divisor);
                Assert.Equal(expectedChance,
                    (double)source["variants"][0]["defaultBranchChancePercent"]);
                ((JArray)detail["sources"]).Add(source);
                harness.Task.HandleFlashResponse(detail, null);
                Assert.True((bool)harness.LastWeb()["success"]);
            }
        }

        [Fact]
        public void V2StageChance_RejectsZeroDivisorAndRoundSixDrift()
        {
            const string snapshotId = "materials.snapshot.stage-invalid";
            using (var harness = OpenV2Session(
                snapshotId,
                GeneralCatalogMaterial(
                    MaterialName, 0, 1, 1, 0, new JArray(),
                    new JArray("system:equipment_tuning"), true)))
            {
                int divisorFid = harness.Send(
                    "materialDetail", "stage.zero-divisor", V2DetailPayload(snapshotId));
                JObject divisorDetail = EmptyDetailResponse(
                    divisorFid, snapshotId, 1, 1, 0, 1);
                JObject zeroDivisor = StageSource(0, "关卡-非法分母", 1);
                zeroDivisor["variants"][0]["rollDivisor"] = 0;
                ((JArray)divisorDetail["sources"]).Add(zeroDivisor);
                harness.Task.HandleFlashResponse(divisorDetail, null);
                Assert.Equal("malformed_response", (string)harness.LastWeb()["error"]);

                int driftFid = harness.Send(
                    "materialDetail", "stage.round-drift", V2DetailPayload(snapshotId));
                JObject driftDetail = EmptyDetailResponse(
                    driftFid, snapshotId, 1, 1, 0, 1);
                JObject drift = StageSource(0, "关卡-舍入漂移", 8);
                drift["variants"][0]["defaultBranchChancePercent"] = 12.500001;
                ((JArray)driftDetail["sources"]).Add(drift);
                harness.Task.HandleFlashResponse(driftDetail, null);
                Assert.Equal("malformed_response", (string)harness.LastWeb()["error"]);
            }
        }

        [Fact]
        public void MaterialShopLease_RequiresExactV2OwnerAndFencesAllDomainRequests()
        {
            const string snapshotId = "materials.snapshot.lease";
            using (var harness = OpenV2Session(snapshotId))
            {
                harness.Task.BindMaterialShopNavigationOwner(
                    "crafting", PanelInstanceId);
                Assert.False(harness.Task.TryAcquireMaterialShopNavigationLease(
                    "crafting", PanelInstanceId, "lease.wrong-snapshot",
                    "materials.snapshot.stale", MaterialName, out _));
                Assert.False(harness.Task.TryAcquireMaterialShopNavigationLease(
                    "crafting", PanelInstanceId, "lease.wrong-material",
                    snapshotId, "不存在材料", out _));

                Assert.True(harness.Task.TryAcquireMaterialShopNavigationLease(
                    "crafting", PanelInstanceId, "lease.current",
                    snapshotId, MaterialName,
                    out MaterialShopSettlementWitness witness));
                Assert.True(harness.Task.IsMaterialShopNavigationLeaseCurrent(witness));
                int sends = harness.Sent.Count;

                harness.Task.HandleWebRequest(
                    "materialDetail",
                    Request(
                        "materialDetail",
                        "lease.blocked.request",
                        V2DetailPayload(snapshotId)));

                Assert.Equal(sends, harness.Sent.Count);
                Assert.Equal("busy", (string)harness.LastWeb()["error"]);
                Assert.True(harness.Task.IsMaterialShopNavigationLeaseCurrent(witness));
                JObject rejectedBeforeParsing = Request(
                    "materialDetail",
                    "lease.rejected.not-recorded",
                    V2DetailPayload(snapshotId));
                rejectedBeforeParsing["domain"] = "wrong-domain";
                harness.Task.HandleWebRequest(
                    "materialDetail",
                    rejectedBeforeParsing);
                Assert.Equal("busy", (string)harness.LastWeb()["error"]);
                Assert.True(harness.Task.ReleaseMaterialShopNavigationLease(witness));
                Assert.False(harness.Task.IsMaterialShopNavigationLeaseCurrent(witness));
                harness.Task.HandleWebRequest(
                    "materialDetail",
                    Request(
                        "materialDetail",
                        "lease.rejected.not-recorded",
                        V2DetailPayload(snapshotId)));
                Assert.Equal(sends + 1, harness.Sent.Count);
            }
        }

        [Fact]
        public void MaterialShopLease_OwnerGenerationDriftInvalidatesAndCleansLease()
        {
            const string snapshotId = "materials.snapshot.owner-drift";
            using (var harness = OpenV2Session(snapshotId))
            {
                harness.Task.BindMaterialShopNavigationOwner(
                    "crafting", PanelInstanceId);
                Assert.True(harness.Task.TryAcquireMaterialShopNavigationLease(
                    "crafting", PanelInstanceId, "lease.owner-drift",
                    snapshotId, MaterialName,
                    out MaterialShopSettlementWitness witness));

                harness.Task.BindMaterialShopNavigationOwner(
                    "npcshop", "panel.npc.replacement");

                Assert.False(harness.Task.IsMaterialShopNavigationLeaseCurrent(witness));
                Assert.False(harness.Task.ReleaseMaterialShopNavigationLease(witness));
                harness.Task.BindMaterialShopNavigationOwner(
                    "crafting", PanelInstanceId);
                Assert.True(harness.Task.TryAcquireMaterialShopNavigationLease(
                    "crafting", PanelInstanceId, "lease.after-drift",
                    snapshotId, MaterialName, out _));
            }
        }

        internal static Harness OpenV2Session(
            string snapshotId,
            JObject material = null,
            string panelInstanceId = PanelInstanceId)
        {
            var harness = new Harness();
            int fid = harness.Send("materials", "session." + snapshotId,
                new JObject { ["v"] = 2 }, panelInstanceId);
            harness.Task.HandleFlashResponse(CatalogResponse(
                fid, snapshotId, material ?? CatalogMaterial(0, 2, 4, 1, 2)), null);
            Assert.True((bool)harness.LastWeb()["success"]);
            return harness;
        }

        private static Harness OpenInfrastructureV2Session(string snapshotId)
        {
            var harness = new Harness();
            int fid = harness.Send("materials", "session." + snapshotId,
                new JObject { ["v"] = 2 });
            JObject material = GeneralCatalogMaterial(
                MaterialName, 0, 0, 0, 0, new JArray(),
                new JArray("system:infrastructure_upgrade"), true);
            JObject response = CatalogResponse(fid, snapshotId, material);
            response["taxonomy"]["directPurposes"] = new JArray(
                Registry("system:equipment_tuning", "装备改装", 0),
                Registry("system:infrastructure_upgrade", "基建升级", 1));
            harness.Task.HandleFlashResponse(response, null);
            Assert.True((bool)harness.LastWeb()["success"]);
            return harness;
        }

        private static JObject Request(
            string cmd, string callId, JObject payload,
            string panelInstanceId = PanelInstanceId)
        {
            return new JObject
            {
                ["type"] = "panel", ["panel"] = "crafting", ["domain"] = "crafting",
                ["cmd"] = cmd, ["callId"] = callId,
                ["panelInstanceId"] = panelInstanceId, ["payload"] = payload
            };
        }

        private static JObject LegacyPayload(string cmd)
        {
            var payload = new JObject { ["v"] = 1 };
            if (cmd == "tooltip" || cmd == "materialDetail") payload["itemName"] = MaterialName;
            else if (cmd != "materials")
            {
                payload["category"] = "武器合成";
                if (cmd == "preview")
                {
                    payload["recipeIndex"] = 0;
                    payload["craftCount"] = 1;
                }
                if (cmd == "commit") payload["expectedCraftToken"] = "craft.token.1";
            }
            return payload;
        }

        private static JObject V2DetailPayload(string snapshotId)
        {
            return new JObject
            {
                ["v"] = 2, ["itemName"] = MaterialName, ["snapshotId"] = snapshotId
            };
        }

        private static JObject Failure(int fid, string error)
        {
            return new JObject
            {
                ["task"] = "crafting_response", ["callId"] = fid,
                ["success"] = false, ["error"] = error
            };
        }

        private static JObject V1Catalog(int fid)
        {
            return new JObject
            {
                ["task"] = "crafting_response", ["callId"] = fid,
                ["success"] = true, ["v"] = 1, ["view"] = "materials",
                ["materials"] = new JArray
                {
                    new JObject
                    {
                        ["name"] = MaterialName, ["displayName"] = MaterialName,
                        ["icon"] = MaterialName, ["owned"] = 469,
                        ["sourceCount"] = 2, ["useCount"] = 1,
                        ["hasSourceSummary"] = true
                    }
                }
            };
        }

        private static JObject CatalogResponse(
            int fid, string snapshotId, params JObject[] materials)
        {
            return new JObject
            {
                ["task"] = "crafting_response", ["callId"] = fid,
                ["success"] = true, ["v"] = 2, ["view"] = "materials",
                ["snapshotId"] = snapshotId,
                ["navigationAccess"] = new JObject
                {
                    ["shop"] = true, ["crafting"] = true
                },
                ["taxonomy"] = Taxonomy(),
                ["materials"] = new JArray(materials)
            };
        }

        private static JObject CatalogMaterial(
            int archiveOrder, int sourceCount, int dropVariantCount,
            int useCount, int structuredPurposeCount)
        {
            return new JObject
            {
                ["name"] = MaterialName, ["displayName"] = MaterialName,
                ["icon"] = MaterialName, ["owned"] = 469,
                ["archiveOrder"] = archiveOrder, ["typeId"] = "equipment_mod",
                ["modFacetIds"] = new JObject
                {
                    ["grade"] = "high", ["scope"] = "firearm", ["role"] = "mechanism"
                },
                ["recipePurposeIds"] = new JArray("recipe:武器合成"),
                ["directPurposeIds"] = new JArray("system:equipment_tuning"),
                ["structuredPurposeCount"] = structuredPurposeCount,
                ["sourceCount"] = sourceCount, ["dropVariantCount"] = dropVariantCount,
                ["useCount"] = useCount, ["hasSourceSummary"] = true
            };
        }

        private static JObject GeneralCatalogMaterial(
            string name,
            int archiveOrder,
            int sourceCount,
            int dropVariantCount,
            int useCount,
            JArray recipePurposeIds,
            JArray directPurposeIds,
            bool hasSourceSummary)
        {
            recipePurposeIds = recipePurposeIds ?? new JArray();
            directPurposeIds = directPurposeIds ?? new JArray();
            return new JObject
            {
                ["name"] = name, ["displayName"] = name, ["icon"] = name,
                ["owned"] = 469, ["archiveOrder"] = archiveOrder, ["typeId"] = "general",
                ["recipePurposeIds"] = recipePurposeIds,
                ["directPurposeIds"] = directPurposeIds,
                ["structuredPurposeCount"] = useCount + directPurposeIds.Count,
                ["sourceCount"] = sourceCount, ["dropVariantCount"] = dropVariantCount,
                ["useCount"] = useCount, ["hasSourceSummary"] = hasSourceSummary
            };
        }

        private static JObject Taxonomy(int directPurposeCount = 1)
        {
            string[] categories =
            {
                "铁枪会", "属性武器", "烹饪", "化学生产", "武器合成", "饰品合成",
                "进阶防具", "基础防具", "公社防具", "黑白契约", "插件合成", "大学装备"
            };
            var recipes = new JArray();
            for (int index = 0; index < categories.Length; index++)
                recipes.Add(Registry("recipe:" + categories[index], categories[index], index));
            var directs = new JArray();
            for (int index = 0; index < directPurposeCount; index++)
            {
                directs.Add(index == 0
                    ? Registry("system:equipment_tuning", "装备改装", index)
                    : Registry("system:direct." + index, "直接用途" + index, index));
            }
            return new JObject
            {
                ["version"] = 1,
                ["roots"] = new JArray(Registry("type", "类型", 0), Registry("purpose", "用途", 1)),
                ["types"] = new JArray(
                    Registry("equipment_mod", "改装材料", 0), Registry("food", "食材", 1),
                    Registry("general", "通用材料", 2)),
                ["modAxes"] = new JArray(
                    Axis("grade", "档级", 0, new JArray(
                        Grade("low", "低级", 0, "#006600"),
                        Grade("medium", "中等", 1, "#996600"),
                        Grade("high", "高等", 2, "#0099FF"),
                        Grade("special", "特殊", 3, "#FFFF00"))),
                    Axis("scope", "适用范围", 1, new JArray(
                        Registry("armor", "防具", 0), Registry("firearm", "枪械", 1),
                        Registry("blade", "刀具", 2), Registry("fist", "拳套", 3),
                        Registry("universal", "通用", 4), Registry("underbarrel", "下挂武器", 5))),
                    Axis("role", "定位", 2, new JArray(
                        Role("firepower", "火力", 0, "triangle-solid"),
                        Role("precision", "精准与操控", 1, "triangle-outline"),
                        Role("stability", "稳定与防护", 2, "square-outline"),
                        Role("sustain", "续航", 3, "circle-outline"),
                        Role("utility", "结构与功能", 4, "diamond-outline"),
                        Role("mechanism", "特殊机制", 5, "star-solid")))),
                ["recipePurposes"] = recipes,
                ["directPurposes"] = directs,
                ["fallback"] = Registry("unstructured", "尚未结构化用途", 2147483647)
            };
        }

        private static JArray DirectPurposeIds(int count)
        {
            var values = new JArray();
            for (int index = 0; index < count; index++)
                values.Add(index == 0
                    ? "system:equipment_tuning"
                    : "system:direct." + index);
            return values;
        }

        private static JArray DirectPurposeEntries(int count)
        {
            var values = new JArray();
            for (int index = 0; index < count; index++)
            {
                values.Add(index == 0
                    ? Registry("system:equipment_tuning", "装备改装", index)
                    : Registry("system:direct." + index, "直接用途" + index, index));
            }
            return values;
        }

        private static JObject EnemyDetailResponse(int fid, string snapshotId)
        {
            JObject detail = EmptyDetailResponse(fid, snapshotId, 2, 4, 1, 2);
            ((JArray)detail["sources"]).Add(EnemySource(
                0, "敌人-军阀精英突击兵", "军阀精英突击兵", 2));
            ((JArray)detail["sources"]).Add(EnemySource(
                1, "敌人-重型改造僵尸", "重型改造僵尸", 2));
            ((JArray)detail["uses"]).Add(new JObject
            {
                ["category"] = "武器合成", ["recipeIndex"] = 7,
                ["productName"] = "XM1014战术版", ["displayName"] = "XM1014战术版",
                ["icon"] = "XM1014战术版", ["itemKind"] = "equipment", ["required"] = 1,
                ["ingredients"] = new JArray(Ingredient(MaterialName, 1))
            });
            return detail;
        }

        private static JObject EmptyDetailResponse(
            int fid, string snapshotId, int sourceCount,
            int dropVariantCount, int useCount, int structuredPurposeCount)
        {
            return new JObject
            {
                ["task"] = "crafting_response", ["callId"] = fid,
                ["success"] = true, ["v"] = 2, ["view"] = "materials",
                ["snapshotId"] = snapshotId,
                ["material"] = new JObject
                {
                    ["name"] = MaterialName, ["displayName"] = MaterialName,
                    ["icon"] = MaterialName, ["description"] = "用于装备改装。",
                    ["owned"] = 469, ["sourceSummary"] = "结构化来源已记录。"
                },
                ["sourceCount"] = sourceCount, ["dropVariantCount"] = dropVariantCount,
                ["useCount"] = useCount, ["structuredPurposeCount"] = structuredPurposeCount,
                ["sources"] = new JArray(),
                ["directPurposes"] = new JArray(
                    Registry("system:equipment_tuning", "装备改装", 0)),
                ["uses"] = new JArray()
            };
        }

        private static JObject InfrastructureDetailResponse(int fid, string snapshotId)
        {
            JObject detail = EmptyDetailResponse(fid, snapshotId, 0, 0, 0, 1);
            detail["directPurposes"] = new JArray(
                Registry("system:infrastructure_upgrade", "基建升级", 1));
            detail["infrastructureUses"] = new JArray(
                InfrastructureProject("测试基建甲", 0, 1, 3, 500, 480, 400),
                new JObject
                {
                    ["infrastructureName"] = "测试基建丙", ["projectOrder"] = 2,
                    ["currentLevel"] = 0, ["maximumLevel"] = 2,
                    ["levels"] = new JArray(
                        InfrastructureLevel(1, 0, 470))
                });
            return detail;
        }

        private static JObject InfrastructureProject(
            string name, int projectOrder, int currentLevel,
            int maximumLevel, params int[] requirements)
        {
            var levels = new JArray();
            for (int levelIndex = 0; levelIndex < requirements.Length; levelIndex++)
                levels.Add(InfrastructureLevel(levelIndex, currentLevel, requirements[levelIndex]));
            return new JObject
            {
                ["infrastructureName"] = name, ["projectOrder"] = projectOrder,
                ["currentLevel"] = currentLevel, ["maximumLevel"] = maximumLevel,
                ["levels"] = levels
            };
        }

        private static JObject InfrastructureLevel(
            int levelIndex, int currentLevel, int required)
        {
            const int owned = 469;
            string status = currentLevel > levelIndex
                ? "completed" : currentLevel == levelIndex ? "current" : "future";
            int missing = status == "completed" ? 0 : Math.Max(required - owned, 0);
            return new JObject
            {
                ["levelIndex"] = levelIndex, ["targetLevel"] = levelIndex + 1,
                ["required"] = required, ["owned"] = owned,
                ["missing"] = missing, ["status"] = status
            };
        }

        private static JObject EnemySource(
            int sourceOrder, string enemyType, string displayName, int variantCount)
        {
            var variants = new JArray();
            for (int index = 0; index < variantCount; index++)
            {
                int chance = index == 0 ? 3 : 5;
                variants.Add(new JObject
                {
                    ["occurrenceIndex"] = index, ["chanceRaw"] = chance,
                    ["chanceInputState"] = "explicit", ["nominalChancePercent"] = chance,
                    ["minReverseLevel"] = index == 0 ? JValue.CreateNull() : new JValue(3),
                    ["maxReverseLevel"] = index == 0 ? new JValue(2) : JValue.CreateNull(),
                    ["quantityMin"] = 1, ["quantityMax"] = 1
                });
            }
            return new JObject
            {
                ["kind"] = "enemy", ["sourceKey"] = SourceKey("enemy", enemyType),
                ["sourceOrder"] = sourceOrder, ["enemyType"] = enemyType,
                ["displayName"] = displayName,
                ["chanceModel"] = "enemy_prd_with_reverse_bonus", ["variants"] = variants
            };
        }

        private static JObject ShopSource(int sourceOrder)
        {
            return new JObject
            {
                ["kind"] = "shop",
                ["sourceKey"] = SourceKey("shop", "迷之盔甲君", "57"),
                ["sourceOrder"] = sourceOrder, ["shopId"] = "迷之盔甲君",
                ["itemName"] = MaterialName, ["catalogIndex"] = 57,
                ["basePrice"] = 50000, ["unitPriceAtSnapshot"] = 50000,
                ["requiredInfo"] = "", ["locked"] = false,
                ["shopAccessMode"] = "unavailable",
                ["shopAccessReason"] = "no_authoritative_remote_access_capability"
            };
        }

        private static JObject CraftSource(int sourceOrder)
        {
            return new JObject
            {
                ["kind"] = "craft", ["sourceKey"] = SourceKey("craft", "铁枪会", "0"),
                ["sourceOrder"] = sourceOrder, ["category"] = "铁枪会",
                ["recipeIndex"] = 0, ["productName"] = MaterialName,
                ["price"] = 0, ["kpoints"] = 0
            };
        }

        private static JObject KShopSource(int sourceOrder, int catalogIndex = -1)
        {
            if (catalogIndex < 0) catalogIndex = sourceOrder;
            return new JObject
            {
                ["kind"] = "kshop",
                ["sourceKey"] = SourceKey(
                    "kshop", catalogIndex.ToString(CultureInfo.InvariantCulture)),
                ["sourceOrder"] = sourceOrder, ["catalogIndex"] = catalogIndex,
                ["entryId"] = "kshop.entry." + catalogIndex,
                ["category"] = "材料", ["priceK"] = 1
            };
        }

        private static JObject QuestSource(int sourceOrder, string questId)
        {
            return new JObject
            {
                ["kind"] = "quest",
                ["sourceKey"] = SourceKey("quest", questId, "base", "0"),
                ["sourceOrder"] = sourceOrder, ["questId"] = questId,
                ["rewardSet"] = "base", ["authoredIndex"] = 0,
                ["title"] = "边界任务", ["quantity"] = 1
            };
        }

        private static JObject StageSource(int sourceOrder, string stageName, int divisor)
        {
            double chance = Math.Round(
                (100.0 / divisor) * 1000000.0, MidpointRounding.AwayFromZero) / 1000000.0;
            return new JObject
            {
                ["kind"] = "stage", ["sourceKey"] = SourceKey("stage", stageName),
                ["sourceOrder"] = sourceOrder, ["stageName"] = stageName,
                ["chanceModel"] = "stage_roll_divisor_with_legacy_domain_branch",
                ["legacyConditionId"] = "andylaw_domain_bonus",
                ["variants"] = new JArray(new JObject
                {
                    ["occurrenceIndex"] = 0, ["rollDivisor"] = divisor,
                    ["defaultBranchChancePercent"] = chance,
                    ["quantityMin"] = 1, ["quantityMax"] = 1
                })
            };
        }

        private static JObject RecipeUse(string category, int recipeIndex)
        {
            return new JObject
            {
                ["category"] = category, ["recipeIndex"] = recipeIndex,
                ["productName"] = "边界产物." + category + "." + recipeIndex,
                ["displayName"] = "边界产物." + category + "." + recipeIndex,
                ["icon"] = "边界产物." + category + "." + recipeIndex,
                ["itemKind"] = "stack", ["required"] = 1,
                ["ingredients"] = new JArray(Ingredient(MaterialName, 1))
            };
        }

        private static JObject Ingredient(string name, int required)
        {
            return new JObject
            {
                ["name"] = name, ["displayName"] = name, ["icon"] = name + "图标",
                ["required"] = required, ["isQuantity"] = true
            };
        }

        private static string SourceKey(params string[] segments)
        {
            string result = "lp1";
            foreach (string segment in segments)
                result += "|" + segment.Length.ToString(CultureInfo.InvariantCulture) + ":" + segment;
            return result;
        }

        private static JObject Registry(string id, string label, int order)
        {
            return new JObject { ["id"] = id, ["label"] = label, ["order"] = order };
        }

        private static JObject Axis(string id, string label, int order, JArray values)
        {
            return new JObject
            {
                ["id"] = id, ["label"] = label, ["order"] = order, ["values"] = values
            };
        }

        private static JObject Grade(string id, string label, int order, string color)
        {
            JObject value = Registry(id, label, order);
            value["color"] = color;
            return value;
        }

        private static JObject Role(string id, string label, int order, string symbol)
        {
            JObject value = Registry(id, label, order);
            value["symbol"] = symbol;
            return value;
        }
    }
}
