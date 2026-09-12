using System;
using System.Collections.Generic;
using Newtonsoft.Json.Linq;
using Xunit;
using CF7Launcher.Tasks;

namespace CF7Launcher.Tests.Tasks
{
    /// <summary>
    /// 共享收纳工作台 contract（tmp/stash-shared-20260912/contract.md）的 Host 侧边界测试：
    /// stashPage 可选 filterSpec 全局查询与严格回显、stashTake 顶层定点 target 与逐项
    /// placement 回执、普通库存来源 slotRef 的可选 quantity 白名单。
    /// </summary>
    public sealed class StashSharedContractTests
    {
        private const string Panel = "panel.workbench.item.use.1";
        private const long Generation = 17;
        private const string StoreId = "stash.store.1";
        private const string TakeOperation = "stash.contract.take";

        private sealed class ItemUseHarness : IDisposable
        {
            public readonly List<JObject> Flash = new List<JObject>();
            public readonly List<JObject> Web = new List<JObject>();
            public readonly ItemUseTask Task;
            public bool Ready = true;
            public bool SendSucceeds = true;
            public bool BindingCurrent = true;

            public ItemUseHarness(int timeoutMs = 1000)
            {
                Task = new ItemUseTask(
                    delegate { return Ready; },
                    delegate(string payload)
                    {
                        Flash.Add(JObject.Parse(payload.TrimEnd('\0')));
                        return SendSucceeds;
                    },
                    delegate(string panel, long generation)
                    {
                        return BindingCurrent
                            && panel == Panel
                            && generation == Generation;
                    },
                    timeoutMs);
                Task.SetPostToWeb(value => Web.Add(JObject.Parse(value)));
            }

            public void Dispose() { Task.Dispose(); }
        }

        private sealed class InventoryHarness : IDisposable
        {
            public readonly List<JObject> Sent = new List<JObject>();
            public readonly List<JObject> Posted = new List<JObject>();
            public readonly InventoryTask Task;

            public InventoryHarness()
            {
                Task = new InventoryTask(
                    () => true,
                    payload =>
                    {
                        Sent.Add(JObject.Parse(payload.TrimEnd('\0')));
                        return true;
                    });
                Task.SetPostToWeb(json => Posted.Add(JObject.Parse(json)));
            }

            public void Dispose() { Task.Dispose(); }
        }

        // ---------- stashPage ----------

        [Fact]
        public void StashPage_FilterSpecRoundTripsNormalizedEcho()
        {
            using (var h = new ItemUseHarness())
            {
                h.Task.HandleWebRequest("stashPage", StashPageRequest(
                    "stash.page.filter.ok",
                    new JObject { ["branch"] = "category", ["major"] = "weapon", ["use"] = "长枪" }));
                JObject sent = Assert.Single(h.Flash);
                Assert.Equal("itemUseStashPage", sent.Value<string>("action"));
                JObject spec = (JObject)sent["filterSpec"];
                Assert.Equal(3, spec.Count);
                Assert.Equal("category", spec.Value<string>("branch"));
                Assert.Equal("weapon", spec.Value<string>("major"));
                Assert.Equal("长枪", spec.Value<string>("use"));

                JObject data = FilteredStashPageData(spec, 1,
                    new JArray(StashEntry("stash.store.1.e1", 2, 3)));
                h.Task.HandleFlashResponse(
                    StashResponse(sent.Value<int>("callId"), "stashPage", null, data), null);

                JObject web = Assert.Single(h.Web);
                Assert.True(web.Value<bool>("success"));
                Assert.Equal(7, web["data"].Value<int>("unfilteredTotal"));
                Assert.Equal(7, web["data"].Value<int>("filterItemCount"));
                Assert.Equal(1, web["data"].Value<int>("setFilterItemCount"));
                Assert.Equal("长枪", web["data"]["filterSpec"].Value<string>("use"));
                Assert.Equal("idle", h.Task.WriteState);
            }
        }

        [Fact]
        public void StashPage_SetBranchSpecNormalizes()
        {
            using (var h = new ItemUseHarness())
            {
                h.Task.HandleWebRequest("stashPage", StashPageRequest(
                    "stash.page.filter.set",
                    new JObject { ["branch"] = "set", ["setId"] = "hazmat_b" }));
                JObject sent = Assert.Single(h.Flash);
                JObject spec = (JObject)sent["filterSpec"];
                Assert.Equal(2, spec.Count);
                Assert.Equal("set", spec.Value<string>("branch"));
                Assert.Equal("hazmat_b", spec.Value<string>("setId"));

                JObject data = FilteredStashPageData(spec, 0, new JArray());
                data["unfilteredTotal"] = 4;
                data["filterItemCount"] = 4;
                data["filterFacets"] = new JArray(Facet("weapon", 4));
                h.Task.HandleFlashResponse(
                    StashResponse(sent.Value<int>("callId"), "stashPage", null, data), null);
                Assert.True(Assert.Single(h.Web).Value<bool>("success"));
            }
        }

        public static IEnumerable<object[]> MalformedFilterSpecs()
        {
            yield return new object[] { "spec_string", (JToken)new JValue("weapon") };
            yield return new object[] { "bad_branch", new JObject { ["branch"] = "bogus" } };
            yield return new object[] { "bad_major", new JObject { ["major"] = "bogus" } };
            yield return new object[] { "all_with_use", new JObject { ["major"] = "all", ["use"] = "长枪" } };
            yield return new object[] { "subtype_no_use", new JObject { ["major"] = "weapon", ["subtype"] = "突击步枪" } };
            yield return new object[] { "extra_key", new JObject { ["major"] = "weapon", ["junk"] = 1 } };
            yield return new object[] { "set_with_major", new JObject { ["branch"] = "set", ["major"] = "weapon" } };
            yield return new object[] { "set_control", new JObject { ["branch"] = "set", ["setId"] = "ab" } };
            yield return new object[] { "use_over64", new JObject { ["major"] = "weapon", ["use"] = new string('x', 65) } };
        }

        [Theory]
        [MemberData(nameof(MalformedFilterSpecs))]
        public void StashPage_MalformedFilterSpecRejectedBeforeSend(string name, JToken spec)
        {
            using (var h = new ItemUseHarness())
            {
                h.Task.HandleWebRequest("stashPage", StashPageRequest("stash.page.bad." + name, spec));
                Assert.Empty(h.Flash);
                Assert.Equal("invalid_payload", Assert.Single(h.Web).Value<string>("error"));
                Assert.Equal("idle", h.Task.WriteState);
            }
        }

        [Fact]
        public void StashPage_NullFilterSpecRejectedBeforeSend()
        {
            using (var h = new ItemUseHarness())
            {
                JObject request = StashPageRequest("stash.page.filter.null", null);
                ((JObject)request["payload"])["filterSpec"] = JValue.CreateNull();
                h.Task.HandleWebRequest("stashPage", request);
                Assert.Empty(h.Flash);
                Assert.Equal("invalid_payload", Assert.Single(h.Web).Value<string>("error"));
                Assert.Equal("idle", h.Task.WriteState);
            }
        }

        [Fact]
        public void StashPage_UnmaterializedEmptyStoreAccepted()
        {
            using (var h = new ItemUseHarness())
            {
                h.Task.HandleWebRequest("stashPage", StashPageRequest("stash.page.empty", null));
                JObject data = new JObject
                {
                    ["success"] = true,
                    ["storeId"] = "",
                    ["revision"] = 0,
                    ["offset"] = 0,
                    ["total"] = 0,
                    ["entries"] = new JArray(),
                    ["migrationRequired"] = false,
                    ["pendingOperationId"] = ""
                };
                h.Task.HandleFlashResponse(
                    StashResponse(h.Flash[0].Value<int>("callId"), "stashPage", null, data), null);
                Assert.True(Assert.Single(h.Web).Value<bool>("success"));
                Assert.Equal("idle", h.Task.WriteState);
            }

            // 旧迁移分支兼容：空 storeId + migrationRequired:true 仍放行
            using (var h = new ItemUseHarness())
            {
                h.Task.HandleWebRequest("stashPage", StashPageRequest("stash.page.empty.mig", null));
                JObject data = new JObject
                {
                    ["success"] = true,
                    ["storeId"] = "",
                    ["revision"] = 0,
                    ["offset"] = 0,
                    ["total"] = 0,
                    ["entries"] = new JArray(),
                    ["migrationRequired"] = true,
                    ["pendingOperationId"] = ""
                };
                h.Task.HandleFlashResponse(
                    StashResponse(h.Flash[0].Value<int>("callId"), "stashPage", null, data), null);
                Assert.True(Assert.Single(h.Web).Value<bool>("success"));
            }
        }

        [Theory]
        [InlineData("revision_nonzero")]
        [InlineData("total_nonzero")]
        [InlineData("pending_id")]
        public void StashPage_EmptyStoreIdRejectsNonZeroShape(string mutation)
        {
            using (var h = new ItemUseHarness())
            {
                h.Task.HandleWebRequest("stashPage",
                    StashPageRequest("stash.page.empty.bad." + mutation, null));
                var data = new JObject
                {
                    ["success"] = true,
                    ["storeId"] = "",
                    ["revision"] = 0,
                    ["offset"] = 0,
                    ["total"] = 0,
                    ["entries"] = new JArray(),
                    ["migrationRequired"] = false,
                    ["pendingOperationId"] = ""
                };
                switch (mutation)
                {
                    case "revision_nonzero": data["revision"] = 1; break;
                    case "total_nonzero":
                        data["total"] = 1;
                        data["entries"] = new JArray(StashEntry("stash.store.1.e1", 2, 3));
                        break;
                    case "pending_id": data["pendingOperationId"] = "stash.op.1"; break;
                }
                h.Task.HandleFlashResponse(
                    StashResponse(h.Flash[0].Value<int>("callId"), "stashPage", null, data), null);
                Assert.Equal("malformed_response", Assert.Single(h.Web).Value<string>("error"));
                Assert.Equal("idle", h.Task.WriteState);
            }
        }

        [Fact]
        public void StashPage_LegacyRequestKeepsExactResponseShape()
        {
            using (var h = new ItemUseHarness())
            {
                h.Task.HandleWebRequest("stashPage", StashPageRequest("stash.page.legacy", null));
                JObject sent = Assert.Single(h.Flash);
                Assert.Null(sent["filterSpec"]);
                h.Task.HandleFlashResponse(
                    StashResponse(sent.Value<int>("callId"), "stashPage", null,
                        StashPageData(1, new JArray(StashEntry("stash.store.1.e1", 2, 3)))), null);
                JObject web = Assert.Single(h.Web);
                Assert.True(web.Value<bool>("success"));
                Assert.Null(web["data"]["filterFacets"]);
                Assert.Equal("idle", h.Task.WriteState);
            }

            using (var h = new ItemUseHarness())
            {
                h.Task.HandleWebRequest("stashPage", StashPageRequest("stash.page.legacy.extra", null));
                JObject data = StashPageData(0, new JArray());
                data["unfilteredTotal"] = 0;
                h.Task.HandleFlashResponse(
                    StashResponse(h.Flash[0].Value<int>("callId"), "stashPage", null, data), null);
                Assert.Equal("malformed_response", Assert.Single(h.Web).Value<string>("error"));
            }

            using (var h = new ItemUseHarness())
            {
                h.Task.HandleWebRequest("stashPage", StashPageRequest(
                    "stash.page.filter.short", new JObject { ["major"] = "material" }));
                h.Task.HandleFlashResponse(
                    StashResponse(h.Flash[0].Value<int>("callId"), "stashPage", null,
                        StashPageData(0, new JArray())), null);
                Assert.Equal("malformed_response", Assert.Single(h.Web).Value<string>("error"));
            }
        }

        [Theory]
        [InlineData("echo_mismatch")]
        [InlineData("missing_fields")]
        [InlineData("count_mismatch")]
        [InlineData("facet_sum_mismatch")]
        [InlineData("set_sum_mismatch")]
        [InlineData("total_over_unfiltered")]
        [InlineData("extra_key")]
        public void StashPage_FilteredResponseFailsClosed(string mutation)
        {
            using (var h = new ItemUseHarness())
            {
                h.Task.HandleWebRequest("stashPage", StashPageRequest(
                    "stash.page.resp." + mutation,
                    new JObject { ["major"] = "weapon" }));
                JObject sent = Assert.Single(h.Flash);
                JObject spec = (JObject)sent["filterSpec"];
                Assert.Equal("weapon", spec.Value<string>("major"));
                Assert.Null(spec["branch"]);

                JObject data = FilteredStashPageData(spec, 1,
                    new JArray(StashEntry("stash.store.1.e1", 2, 3)));
                switch (mutation)
                {
                    case "echo_mismatch": data["filterSpec"]["major"] = "armor"; break;
                    case "missing_fields": data.Remove("filterFacets"); break;
                    case "count_mismatch": data["filterItemCount"] = 3; break;
                    case "facet_sum_mismatch":
                        data["filterFacets"] = new JArray(Facet("weapon", 6));
                        break;
                    case "set_sum_mismatch":
                        data["setFacets"] = new JArray(Facet("hazmat_b", 2));
                        break;
                    case "total_over_unfiltered":
                        data["unfilteredTotal"] = 0;
                        data["filterItemCount"] = 0;
                        data["filterFacets"] = new JArray();
                        data["setFilterItemCount"] = 0;
                        data["setFacets"] = new JArray();
                        break;
                    case "extra_key": data["bogus"] = 1; break;
                }
                h.Task.HandleFlashResponse(
                    StashResponse(sent.Value<int>("callId"), "stashPage", null, data), null);
                Assert.Equal("malformed_response", Assert.Single(h.Web).Value<string>("error"));
                Assert.Equal("idle", h.Task.WriteState);
            }
        }

        // ---------- stashTake target ----------

        [Fact]
        public void StashTake_TargetNormalizesAndForwardsExactly()
        {
            using (var h = new ItemUseHarness())
            {
                h.Task.HandleWebRequest("stashTake", StashTakeRequest(
                    "stash.take.target.fwd",
                    new JArray(TakeRow("stash.store.1.e1", 2, 3)),
                    BackpackTarget(7)));
                JObject sent = Assert.Single(h.Flash);
                Assert.Equal("itemUseStashTake", sent.Value<string>("action"));
                JObject target = (JObject)sent["target"];
                Assert.Equal(3, target.Count);
                Assert.Equal("背包", target.Value<string>("containerId"));
                Assert.Equal(7, target.Value<int>("slot"));
                Assert.Equal("inv.contract.7", target.Value<string>("expectedLease"));
            }
        }

        [Fact]
        public void StashTake_TargetRequiresExactlyOneEntry()
        {
            using (var h = new ItemUseHarness())
            {
                h.Task.HandleWebRequest("stashTake", StashTakeRequest(
                    "stash.take.target.two",
                    new JArray(
                        TakeRow("stash.store.1.e1", 2, 3),
                        TakeRow("stash.store.1.e2", 1, 1)),
                    BackpackTarget(7)));
                Assert.Empty(h.Flash);
                Assert.Equal("invalid_payload", Assert.Single(h.Web).Value<string>("error"));
                Assert.Equal("idle", h.Task.WriteState);
            }
        }

        [Theory]
        [InlineData("container_warehouse")]
        [InlineData("slot_over")]
        [InlineData("slot_negative")]
        [InlineData("lease_shape")]
        [InlineData("lease_missing")]
        [InlineData("extra_key")]
        [InlineData("with_quantity")]
        [InlineData("not_object")]
        [InlineData("explicit_null")]
        public void StashTake_MalformedTargetRejectedBeforeSend(string mutation)
        {
            using (var h = new ItemUseHarness())
            {
                JObject request = StashTakeRequest(
                    "stash.take.target." + mutation,
                    new JArray(TakeRow("stash.store.1.e1", 2, 3)),
                    null);
                JObject payload = (JObject)request["payload"];
                JObject target = BackpackTarget(7);
                switch (mutation)
                {
                    case "container_warehouse": target["containerId"] = "仓库"; break;
                    case "slot_over": target["slot"] = 50; break;
                    case "slot_negative": target["slot"] = -1; break;
                    case "lease_shape": target["expectedLease"] = "bad lease"; break;
                    case "lease_missing": target.Remove("expectedLease"); break;
                    case "extra_key": target["note"] = "x"; break;
                    case "with_quantity": target["quantity"] = 2; break;
                    case "not_object": payload["target"] = "背包"; target = null; break;
                    case "explicit_null": payload["target"] = JValue.CreateNull(); target = null; break;
                }
                if (target != null) payload["target"] = target;
                h.Task.HandleWebRequest("stashTake", request);
                Assert.Empty(h.Flash);
                Assert.Equal("invalid_payload", Assert.Single(h.Web).Value<string>("error"));
                Assert.Equal("idle", h.Task.WriteState);
            }
        }

        [Fact]
        public void StashTake_TargetedAcceptEchoesBackpackSlot()
        {
            using (var h = new ItemUseHarness())
            {
                h.Task.HandleWebRequest("stashTake", StashTakeRequest(
                    "stash.take.echo.ok",
                    new JArray(TakeRow("stash.store.1.e1", 2, 3)),
                    BackpackTarget(7)));
                JObject data = StashTakeData(
                    new JArray(new JObject
                    {
                        ["entryId"] = "stash.store.1.e1",
                        ["quantity"] = 3,
                        ["destination"] = "背包",
                        ["slot"] = 7
                    }),
                    new JArray());
                h.Task.HandleFlashResponse(
                    StashResponse(h.Flash[0].Value<int>("callId"), "stashTake", TakeOperation, data), null);
                JObject web = Assert.Single(h.Web);
                Assert.True(web.Value<bool>("success"));
                Assert.Equal("背包", web["data"]["accepted"][0].Value<string>("destination"));
                Assert.Equal(7, web["data"]["accepted"][0].Value<int>("slot"));
                Assert.Equal("idle", h.Task.WriteState);
            }
        }

        [Theory]
        [InlineData("slot_mismatch")]
        [InlineData("destination_routed")]
        [InlineData("destination_unknown")]
        [InlineData("slot_out_of_range")]
        [InlineData("slot_string")]
        [InlineData("destination_with_foreign_slot")]
        public void StashTake_PlacementFieldsFailClosed(string mutation)
        {
            using (var h = new ItemUseHarness())
            {
                h.Task.HandleWebRequest("stashTake", StashTakeRequest(
                    "stash.take.echo." + mutation,
                    new JArray(TakeRow("stash.store.1.e1", 2, 3)),
                    BackpackTarget(7)));
                var row = new JObject
                {
                    ["entryId"] = "stash.store.1.e1",
                    ["quantity"] = 3,
                    ["destination"] = "背包",
                    ["slot"] = 7
                };
                switch (mutation)
                {
                    case "slot_mismatch": row["slot"] = 8; break;
                    case "destination_routed": row["destination"] = "材料"; row.Remove("slot"); break;
                    case "destination_unknown": row["destination"] = "秘境"; break;
                    case "slot_out_of_range": row["slot"] = 50; break;
                    case "slot_string": row["slot"] = "7"; break;
                    case "destination_with_foreign_slot": row["destination"] = "材料"; break;
                }
                JObject data = StashTakeData(new JArray(row), new JArray());
                h.Task.HandleFlashResponse(
                    StashResponse(h.Flash[0].Value<int>("callId"), "stashTake", TakeOperation, data), null);
                JObject web = Assert.Single(h.Web);
                Assert.False(web.Value<bool>("success"));
                Assert.Equal("malformed_response", web.Value<string>("error"));
                Assert.True(web.Value<bool>("requiresReconcile"));
                Assert.Equal("needs_reconcile", h.Task.WriteState);
            }
        }

        [Theory]
        [InlineData("inventory_full")]
        [InlineData("target_stale")]
        [InlineData("target_occupied")]
        [InlineData("target_incompatible")]
        public void StashTake_BlockedReasonsAreEnumerable(string reason)
        {
            using (var h = new ItemUseHarness())
            {
                h.Task.HandleWebRequest("stashTake", StashTakeRequest(
                    "stash.take.blocked." + reason,
                    new JArray(TakeRow("stash.store.1.e1", 2, 3)),
                    null));
                JObject data = StashTakeData(
                    new JArray(),
                    new JArray(new JObject
                    {
                        ["entryId"] = "stash.store.1.e1",
                        ["reason"] = reason
                    }));
                h.Task.HandleFlashResponse(
                    StashResponse(h.Flash[0].Value<int>("callId"), "stashTake", TakeOperation, data), null);
                JObject web = Assert.Single(h.Web);
                Assert.True(web.Value<bool>("success"));
                Assert.Equal(reason, web["data"]["blocked"][0].Value<string>("reason"));
                Assert.Equal("idle", h.Task.WriteState);
            }
        }

        [Fact]
        public void StashTake_LegacyRowsAndAutoDestinationStillPass()
        {
            using (var h = new ItemUseHarness())
            {
                h.Task.HandleWebRequest("stashTake", StashTakeRequest(
                    "stash.take.legacy",
                    new JArray(TakeRow("stash.store.1.e1", 2, 3)),
                    null));
                JObject sent = Assert.Single(h.Flash);
                Assert.Null(sent["target"]);
                JObject data = StashTakeData(
                    new JArray(new JObject
                    {
                        ["entryId"] = "stash.store.1.e1",
                        ["quantity"] = 3,
                        ["destination"] = "材料"
                    }),
                    new JArray());
                h.Task.HandleFlashResponse(
                    StashResponse(sent.Value<int>("callId"), "stashTake", TakeOperation, data), null);
                Assert.True(Assert.Single(h.Web).Value<bool>("success"));
                Assert.Equal("idle", h.Task.WriteState);
            }
        }

        [Fact]
        public void StashTake_DefinitiveTargetErrorClosesGateUnknownErrorReconciles()
        {
            using (var h = new ItemUseHarness())
            {
                h.Task.HandleWebRequest("stashTake", StashTakeRequest(
                    "stash.take.err.stale",
                    new JArray(TakeRow("stash.store.1.e1", 2, 3)),
                    BackpackTarget(7)));
                h.Task.HandleFlashResponse(
                    StashErrorResponse(h.Flash[0].Value<int>("callId"), "target_stale"), null);
                JObject web = Assert.Single(h.Web);
                Assert.False(web.Value<bool>("success"));
                Assert.Equal("target_stale", web.Value<string>("error"));
                Assert.Null(web["requiresReconcile"]);
                Assert.Equal("idle", h.Task.WriteState);
            }

            using (var h = new ItemUseHarness())
            {
                h.Task.HandleWebRequest("stashTake", StashTakeRequest(
                    "stash.take.err.unknown",
                    new JArray(TakeRow("stash.store.1.e1", 2, 3)),
                    BackpackTarget(7)));
                h.Task.HandleFlashResponse(
                    StashErrorResponse(h.Flash[0].Value<int>("callId"), "mystery_failure"), null);
                JObject web = Assert.Single(h.Web);
                Assert.Equal("mystery_failure", web.Value<string>("error"));
                Assert.True(web.Value<bool>("requiresReconcile"));
                Assert.Equal("needs_reconcile", h.Task.WriteState);
            }
        }

        [Fact]
        public void StashTake_UnknownReasonEntersReconcileAndQueryRecovers()
        {
            using (var h = new ItemUseHarness())
            {
                h.Task.HandleWebRequest("stashTake", StashTakeRequest(
                    "stash.take.bad.reason",
                    new JArray(TakeRow("stash.store.1.e1", 2, 3)),
                    null));
                JObject bad = StashTakeData(
                    new JArray(),
                    new JArray(new JObject
                    {
                        ["entryId"] = "stash.store.1.e1",
                        ["reason"] = "mystery"
                    }));
                h.Task.HandleFlashResponse(
                    StashResponse(h.Flash[0].Value<int>("callId"), "stashTake", TakeOperation, bad), null);
                Assert.Equal("needs_reconcile", h.Task.WriteState);
                Assert.Equal("malformed_response", h.Web[0].Value<string>("error"));

                h.Task.HandleWebRequest("stashQuery", StashQueryRequest("stash.take.recover"));
                Assert.Equal(2, h.Flash.Count);
                JObject query = h.Flash[1];
                Assert.Equal("itemUseStashQuery", query.Value<string>("action"));
                JObject queryData = new JObject
                {
                    ["success"] = true,
                    ["state"] = "committed",
                    ["result"] = StashTakeData(
                        new JArray(),
                        new JArray(new JObject
                        {
                            ["entryId"] = "stash.store.1.e1",
                            ["reason"] = "inventory_full"
                        }))
                };
                h.Task.HandleFlashResponse(
                    StashResponse(query.Value<int>("callId"), "stashQuery", TakeOperation, queryData), null);
                Assert.Equal("idle", h.Task.WriteState);
                Assert.True(h.Web[h.Web.Count - 1].Value<bool>("success"));
            }
        }

        [Fact]
        public void StashTake_CommittedQueryPlacementMustMatchOriginalTarget()
        {
            using (var h = new ItemUseHarness())
            {
                h.SendSucceeds = false;
                h.Task.HandleWebRequest("stashTake", StashTakeRequest(
                    "stash.take.reconcile.target",
                    new JArray(TakeRow("stash.store.1.e1", 2, 3)),
                    BackpackTarget(7)));
                Assert.Equal("needs_reconcile", h.Task.WriteState);
                h.SendSucceeds = true;

                h.Task.HandleWebRequest("stashQuery", StashQueryRequest("stash.take.reconcile.forged"));
                JObject forgedData = new JObject
                {
                    ["success"] = true,
                    ["state"] = "committed",
                    ["result"] = StashTakeData(
                        new JArray(new JObject
                        {
                            ["entryId"] = "stash.store.1.e1",
                            ["quantity"] = 3,
                            ["destination"] = "背包",
                            ["slot"] = 8
                        }),
                        new JArray())
                };
                h.Task.HandleFlashResponse(
                    StashResponse(h.Flash[1].Value<int>("callId"), "stashQuery", TakeOperation, forgedData), null);
                Assert.Equal("needs_reconcile", h.Task.WriteState);
                Assert.Equal("malformed_response", h.Web[h.Web.Count - 1].Value<string>("error"));

                h.Task.HandleWebRequest("stashQuery", StashQueryRequest("stash.take.reconcile.good"));
                JObject goodData = new JObject
                {
                    ["success"] = true,
                    ["state"] = "committed",
                    ["result"] = StashTakeData(
                        new JArray(new JObject
                        {
                            ["entryId"] = "stash.store.1.e1",
                            ["quantity"] = 3,
                            ["destination"] = "背包",
                            ["slot"] = 7
                        }),
                        new JArray())
                };
                h.Task.HandleFlashResponse(
                    StashResponse(h.Flash[2].Value<int>("callId"), "stashQuery", TakeOperation, goodData), null);
                Assert.Equal("idle", h.Task.WriteState);
                Assert.True(h.Web[h.Web.Count - 1].Value<bool>("success"));
            }
        }

        // ---------- inventory source quantity ----------

        [Theory]
        [InlineData("move")]
        [InlineData("merge")]
        [InlineData("autoTransfer")]
        public void SourceQuantity_ForwardsOnAllowedCommands(string cmd)
        {
            using (var h = new InventoryHarness())
            {
                h.Task.HandleWebRequest(cmd, InventoryWriteRequest(cmd, "inv.qty.fwd." + cmd, 5, null));
                JObject sent = Assert.Single(h.Sent);
                Assert.Equal(4, ((JObject)sent["source"]).Count);
                Assert.Equal(5, sent["source"].Value<int>("quantity"));
                if (cmd == "autoTransfer") Assert.Null(sent["target"]);
                else Assert.Null(sent["target"]["quantity"]);
            }
        }

        [Fact]
        public void AutoTransferBatch_ForwardsPerSourceQuantity()
        {
            using (var h = new InventoryHarness())
            {
                JObject first = SlotRef("背包", 2, "inv100.2");
                first["quantity"] = 3;
                JObject second = SlotRef("背包", 3, "inv100.3");
                var payload = new JObject
                {
                    ["v"] = 1,
                    ["sources"] = new JArray(first, second),
                    ["targetContainerId"] = "仓库",
                    ["policy"] = "mergeThenEmpty",
                    ["windows"] = new JArray
                    {
                        new JObject { ["containerId"] = "背包", ["offset"] = 0, ["limit"] = 50, ["filterKey"] = "all" },
                        new JObject { ["containerId"] = "仓库", ["offset"] = 0, ["limit"] = 50, ["filterKey"] = "all" }
                    }
                };
                h.Task.HandleWebRequest("autoTransferBatch",
                    InventoryEnvelope("autoTransferBatch", "inv.qty.batch", payload));
                JObject sent = Assert.Single(h.Sent);
                JArray sources = (JArray)sent["sources"];
                Assert.Equal(2, sources.Count);
                Assert.Equal(3, sources[0].Value<int>("quantity"));
                Assert.Null(sources[1]["quantity"]);
            }
        }

        [Theory]
        [InlineData("discard", "source")]
        [InlineData("tooltip", "source")]
        [InlineData("swap", "source")]
        [InlineData("swap", "target")]
        [InlineData("move", "target")]
        [InlineData("merge", "target")]
        public void SourceQuantity_RejectedOutsideAllowedSources(string cmd, string location)
        {
            using (var h = new InventoryHarness())
            {
                JObject request = InventoryWriteRequest(cmd, "inv.qty.reject." + cmd + "." + location, null, null);
                JObject payload = (JObject)request["payload"];
                if (location == "source") ((JObject)payload["source"])["quantity"] = 2;
                else ((JObject)payload["target"])["quantity"] = 2;
                h.Task.HandleWebRequest(cmd, request);
                Assert.Empty(h.Sent);
                Assert.Equal("invalid_payload", Assert.Single(h.Posted).Value<string>("error"));
                Assert.Equal("idle", h.Task.WriteState);
            }
        }

        [Fact]
        public void SourceQuantity_RejectsNonPositiveNonInteger()
        {
            using (var h = new InventoryHarness())
            {
                var bad = new JToken[]
                {
                    new JValue(0),
                    new JValue(-5),
                    new JValue(1.5),
                    new JValue("3"),
                    new JValue(true),
                    JValue.CreateNull(),
                    new JValue(9007199254740992L)
                };
                for (int i = 0; i < bad.Length; i++)
                {
                    h.Task.HandleWebRequest("move",
                        InventoryWriteRequest("move", "inv.qty.shape." + i, bad[i], null));
                }
                Assert.Empty(h.Sent);
                Assert.Equal(bad.Length, h.Posted.Count);
                foreach (JObject web in h.Posted)
                {
                    Assert.Equal("invalid_payload", web.Value<string>("error"));
                }
                Assert.Equal("idle", h.Task.WriteState);
            }
        }

        [Fact]
        public void AutoTransferBatch_TopLevelQuantityRejected()
        {
            using (var h = new InventoryHarness())
            {
                var payload = new JObject
                {
                    ["v"] = 1,
                    ["quantity"] = 3,
                    ["sources"] = new JArray(SlotRef("背包", 2, "inv100.2")),
                    ["targetContainerId"] = "仓库",
                    ["policy"] = "mergeThenEmpty",
                    ["windows"] = new JArray
                    {
                        new JObject { ["containerId"] = "背包", ["offset"] = 0, ["limit"] = 50, ["filterKey"] = "all" },
                        new JObject { ["containerId"] = "仓库", ["offset"] = 0, ["limit"] = 50, ["filterKey"] = "all" }
                    }
                };
                h.Task.HandleWebRequest("autoTransferBatch",
                    InventoryEnvelope("autoTransferBatch", "inv.qty.batch.top", payload));
                Assert.Empty(h.Sent);
                Assert.Equal("invalid_payload", Assert.Single(h.Posted).Value<string>("error"));
            }
        }

        [Fact]
        public void Move_WithSourceQuantity_CompletesWriteGate()
        {
            using (var h = new InventoryHarness())
            {
                h.Task.HandleWebRequest("move",
                    InventoryWriteRequest("move", "inv.qty.move.ok", 3, null));
                JObject sent = Assert.Single(h.Sent);
                Assert.Equal(3, sent["source"].Value<int>("quantity"));
                var response = new JObject
                {
                    ["task"] = "inventory_response",
                    ["callId"] = sent.Value<int>("callId"),
                    ["success"] = true,
                    ["v"] = 1,
                    ["operation"] = "move",
                    ["snapshots"] = new JArray
                    {
                        InventorySnapshot("背包", 50, 0, 3, 101),
                        InventorySnapshot("仓库", 1200, 52, 3, 102)
                    }
                };
                h.Task.HandleFlashResponse(response, _ => { });
                Assert.True(h.Posted[h.Posted.Count - 1].Value<bool>("success"));
                Assert.Equal("idle", h.Task.WriteState);
            }
        }

        [Fact]
        public void Move_WithoutQuantity_KeepsLegacyWireShape()
        {
            using (var h = new InventoryHarness())
            {
                h.Task.HandleWebRequest("move",
                    InventoryWriteRequest("move", "inv.qty.legacy", null, null));
                JObject sent = Assert.Single(h.Sent);
                Assert.Equal(3, ((JObject)sent["source"]).Count);
                Assert.Null(sent["source"]["quantity"]);
            }
        }

        // ---------- builders ----------

        private static JObject StashEnvelope(string command, string callId)
        {
            return new JObject
            {
                ["type"] = "panel",
                ["panel"] = "workbench",
                ["domain"] = "item_use",
                ["cmd"] = command,
                ["callId"] = callId,
                ["panelInstanceId"] = Panel,
                ["payload"] = new JObject
                {
                    ["v"] = 2,
                    ["panelInstanceId"] = Panel,
                    ["sessionGeneration"] = Generation
                }
            };
        }

        private static JObject StashPageRequest(string callId, JToken filterSpec)
        {
            JObject envelope = StashEnvelope("stashPage", callId);
            JObject payload = (JObject)envelope["payload"];
            payload["offset"] = 0;
            if (filterSpec != null) payload["filterSpec"] = filterSpec;
            return envelope;
        }

        private static JObject StashTakeRequest(string callId, JArray entries, JObject target)
        {
            JObject envelope = StashEnvelope("stashTake", callId);
            JObject payload = (JObject)envelope["payload"];
            payload["operationId"] = TakeOperation;
            payload["storeId"] = StoreId;
            payload["expectedRevision"] = 5;
            payload["entries"] = entries;
            if (target != null) payload["target"] = target;
            return envelope;
        }

        private static JObject StashQueryRequest(string callId)
        {
            JObject envelope = StashEnvelope("stashQuery", callId);
            JObject payload = (JObject)envelope["payload"];
            payload["operationId"] = TakeOperation;
            payload["storeId"] = StoreId;
            payload["expectedRevision"] = 5;
            return envelope;
        }

        private static JObject BackpackTarget(int slot)
        {
            return new JObject
            {
                ["containerId"] = "背包",
                ["slot"] = slot,
                ["expectedLease"] = "inv.contract.7"
            };
        }

        private static JObject TakeRow(string entryId, long revision, long quantity)
        {
            return new JObject
            {
                ["entryId"] = entryId,
                ["revision"] = revision,
                ["quantity"] = quantity
            };
        }

        private static JObject StashTakeData(JArray accepted, JArray blocked)
        {
            return new JObject
            {
                ["success"] = true,
                ["accepted"] = accepted,
                ["blocked"] = blocked
            };
        }

        private static JObject StashPageData(int total, JArray entries)
        {
            return new JObject
            {
                ["success"] = true,
                ["storeId"] = StoreId,
                ["revision"] = 5,
                ["offset"] = 0,
                ["total"] = total,
                ["entries"] = entries ?? new JArray(),
                ["migrationRequired"] = false,
                ["pendingOperationId"] = ""
            };
        }

        /// <summary>
        /// contract 语义：filterItemCount 与全局未筛选总数相同，total 才是筛选命中数；
        /// setFacets 只许叶级（children 必空）。
        /// </summary>
        private static JObject FilteredStashPageData(JToken spec, int total, JArray entries)
        {
            JObject data = StashPageData(total, entries);
            data["filterSpec"] = spec != null ? spec.DeepClone() : JValue.CreateNull();
            data["unfilteredTotal"] = 7;
            data["filterItemCount"] = 7;
            data["filterFacets"] = new JArray(Facet("weapon", 5), Facet("material", 2));
            data["setFilterItemCount"] = 1;
            data["setFacets"] = new JArray(Facet("hazmat_b", 1));
            return data;
        }

        private static JObject StashEntry(string entryId, long revision, long quantity)
        {
            return new JObject
            {
                ["entryId"] = entryId,
                ["revision"] = revision,
                ["quantity"] = quantity,
                ["item"] = StackItem(quantity)
            };
        }

        private static JObject StackItem(long quantity)
        {
            return new JObject
            {
                ["name"] = "测试材料",
                ["displayName"] = "测试材料",
                ["icon"] = "icon.mat",
                ["majorType"] = "材料",
                ["use"] = "材料",
                ["actionType"] = "",
                ["weaponType"] = "",
                ["setId"] = "",
                ["setName"] = "",
                ["setOrder"] = 0,
                ["itemKind"] = "stack",
                ["quantity"] = quantity,
                ["enhancementLevel"] = 0,
                ["maxEnhancementLevel"] = 0,
                ["isMaxEnhancement"] = false,
                ["tierSlotAvailable"] = false,
                ["tierSlotUsed"] = false,
                ["modSlotCapacity"] = 0,
                ["modSlotUsed"] = 0,
                ["modSlots"] = new JArray(),
                ["modMeta"] = JValue.CreateNull(),
                ["rarity"] = ""
            };
        }

        private static JObject Facet(string id, int count)
        {
            return new JObject
            {
                ["id"] = id,
                ["label"] = id,
                ["order"] = 1,
                ["count"] = count,
                ["children"] = new JArray()
            };
        }

        private static JObject StashResponse(int callId, string command, string operationId, JObject data)
        {
            var response = new JObject
            {
                ["task"] = "item_use_response",
                ["callId"] = callId,
                ["v"] = 2,
                ["success"] = true,
                ["command"] = command,
                ["panelInstanceId"] = Panel,
                ["sessionGeneration"] = Generation
            };
            if (operationId != null) response["operationId"] = operationId;
            response["data"] = data;
            return response;
        }

        private static JObject StashErrorResponse(int callId, string error)
        {
            return new JObject
            {
                ["task"] = "item_use_response",
                ["callId"] = callId,
                ["v"] = 2,
                ["success"] = false,
                ["command"] = "stashTake",
                ["operationId"] = TakeOperation,
                ["panelInstanceId"] = Panel,
                ["sessionGeneration"] = Generation,
                ["error"] = error
            };
        }

        private static JObject InventoryEnvelope(string cmd, string callId, JObject payload)
        {
            return new JObject
            {
                ["type"] = "panel",
                ["panel"] = "kshop",
                ["domain"] = "inventory",
                ["cmd"] = cmd,
                ["callId"] = callId,
                ["payload"] = payload
            };
        }

        private static JObject SlotRef(string containerId, int slot, string lease)
        {
            return new JObject
            {
                ["containerId"] = containerId,
                ["slot"] = slot,
                ["expectedLease"] = lease
            };
        }

        private static JObject InventoryWriteRequest(
            string cmd, string callId, JToken sourceQuantity, JToken targetQuantity)
        {
            JObject source = SlotRef("背包", 2, "inv100.2");
            if (sourceQuantity != null) source["quantity"] = sourceQuantity;
            var payload = new JObject { ["v"] = 1, ["source"] = source };
            if (cmd == "autoTransfer")
            {
                payload["targetContainerId"] = "仓库";
                payload["policy"] = "mergeThenEmpty";
                payload["windows"] = new JArray
                {
                    new JObject { ["containerId"] = "背包", ["offset"] = 0, ["limit"] = 50, ["filterKey"] = "all" },
                    new JObject { ["containerId"] = "仓库", ["offset"] = 50, ["limit"] = 50, ["filterKey"] = "material" }
                };
            }
            else if (cmd != "discard" && cmd != "tooltip")
            {
                JObject target = SlotRef("仓库", 52, "inv100.52");
                if (targetQuantity != null) target["quantity"] = targetQuantity;
                payload["target"] = target;
            }
            return InventoryEnvelope(cmd, callId, payload);
        }

        private static JObject InventorySnapshot(
            string containerId, int capacity, int offset, int limit, int seq)
        {
            var slots = new JArray();
            for (int i = 0; i < limit; i++)
            {
                slots.Add(new JObject
                {
                    ["physicalSlot"] = offset + i,
                    ["occupied"] = false,
                    ["slotLease"] = "inv.contract." + seq + "." + (offset + i)
                });
            }
            return new JObject
            {
                ["containerId"] = containerId,
                ["capacity"] = capacity,
                ["accessibleCapacity"] = capacity,
                ["viewCapacity"] = capacity,
                ["filterKey"] = "all",
                ["pageSizeHint"] = 50,
                ["locked"] = false,
                ["snapshotSeq"] = seq,
                ["containerEpoch"] = 1,
                ["containerVersion"] = seq,
                ["offset"] = offset,
                ["limit"] = limit,
                ["slots"] = slots,
                ["filterFacets"] = new JArray(),
                ["filterItemCount"] = 0,
                ["setFacets"] = new JArray(),
                ["setFilterItemCount"] = 0
            };
        }
    }
}
