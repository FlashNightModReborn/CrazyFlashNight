using System;
using System.Collections.Generic;
using System.Threading;
using Newtonsoft.Json.Linq;
using Xunit;
using CF7Launcher.Guardian;
using CF7Launcher.Tasks;

namespace CF7Launcher.Tests.Tasks
{
    public class InventoryTaskTests
    {
        private static JObject ParseSent(string payload)
        {
            return JObject.Parse(payload.TrimEnd('\0'));
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

        private static JObject Request(string cmd, string callId = "wb.inventory.1.1")
        {
            var payload = new JObject { ["v"] = 1 };
            if (cmd == "snapshot")
            {
                payload["requests"] = new JArray
                {
                    new JObject { ["containerId"] = "背包", ["offset"] = 0, ["limit"] = 50, ["filterKey"] = "all" },
                    new JObject { ["containerId"] = "仓库", ["offset"] = 50, ["limit"] = 50, ["filterKey"] = "material" }
                };
            }
            else if (cmd == "sortAndMerge")
            {
                payload["container"] = new JObject
                {
                    ["containerId"] = "仓库",
                    ["offset"] = 50,
                    ["limit"] = 50,
                    ["filterKey"] = "all"
                };
                payload["methodName"] = "byType";
            }
            else if (cmd == "autoTransfer")
            {
                payload["source"] = SlotRef("背包", 2, "inv100.2");
                payload["targetContainerId"] = "仓库";
                payload["policy"] = "mergeThenEmpty";
                payload["windows"] = new JArray
                {
                    new JObject { ["containerId"] = "背包", ["offset"] = 0, ["limit"] = 50, ["filterKey"] = "all" },
                    new JObject { ["containerId"] = "仓库", ["offset"] = 50, ["limit"] = 50, ["filterKey"] = "material" }
                };
            }
            else
            {
                payload["source"] = SlotRef("背包", 2, "inv100.2");
                if (cmd != "discard" && cmd != "tooltip") payload["target"] = SlotRef("仓库", 52, "inv100.52");
            }
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

        private static JObject ItemProjection(bool includeBalanceSummary = false)
        {
            var item = new JObject
            {
                ["name"] = "测试步枪",
                ["displayName"] = "测试步枪",
                ["icon"] = "测试步枪图标",
                ["majorType"] = "武器",
                ["use"] = "长枪",
                ["actionType"] = "枪械",
                ["weaponType"] = "突击步枪",
                ["setId"] = "test_set",
                ["setName"] = "测试套装",
                ["setOrder"] = 1,
                ["itemKind"] = "equipment",
                ["quantity"] = 1,
                ["enhancementLevel"] = 3,
                ["maxEnhancementLevel"] = 13,
                ["isMaxEnhancement"] = false,
                ["tierSlotAvailable"] = true,
                ["tierSlotUsed"] = false,
                ["modSlotCapacity"] = 2,
                ["modSlotUsed"] = 1,
                ["modSlots"] = new JArray
                {
                    new JObject
                    {
                        ["name"] = "辅助握持板",
                        ["displayName"] = "人体工学握持板",
                        ["icon"] = "握持板专用图标",
                        ["grade"] = "low",
                        ["gradeLabel"] = "低级",
                        ["gradeColor"] = "#44AA66",
                        ["role"] = "handling",
                        ["roleLabel"] = "精准与操控",
                        ["symbol"] = "grip",
                        ["scope"] = "weapon"
                    }
                },
                ["modMeta"] = JValue.CreateNull(),
                ["rarity"] = "稀有"
            };
            if (includeBalanceSummary)
            {
                item["balanceSummary"] = new JObject
                {
                    ["state"] = "confirmed",
                    ["weightLayers"] = -1,
                    ["formula"] = 1,
                    ["level"] = 30
                };
            }
            return item;
        }

        private static JObject ConfirmProjection()
        {
            return new JObject
            {
                ["itemKind"] = "equipment",
                ["name"] = "测试步枪",
                ["displayName"] = "测试步枪",
                ["quantity"] = 1,
                ["enhancementLevel"] = 3,
                ["rarity"] = "稀有",
                ["tier"] = "",
                ["modSignature"] = "5:辅助握持板;",
                ["lastUpdate"] = 10
            };
        }

        private static JObject Facet(
            string id,
            string label,
            int count)
        {
            return new JObject
            {
                ["id"] = id,
                ["label"] = label,
                ["order"] = 1,
                ["count"] = count,
                ["children"] = new JArray()
            };
        }

        private static JObject Snapshot(
            string containerId,
            int capacity,
            int offset,
            int limit,
            int snapshotSeq,
            bool includeBalanceSummary = false)
        {
            var slots = new JArray();
            for (int i = 0; i < limit; i++)
            {
                int physicalSlot = offset + i;
                if (i == 0)
                {
                    slots.Add(new JObject
                    {
                        ["physicalSlot"] = physicalSlot,
                        ["occupied"] = true,
                        ["slotLease"] = "inv.test." + snapshotSeq + "." + physicalSlot,
                        ["item"] = ItemProjection(includeBalanceSummary),
                        ["confirmProjection"] = ConfirmProjection()
                    });
                }
                else
                {
                    slots.Add(new JObject
                    {
                        ["physicalSlot"] = physicalSlot,
                        ["occupied"] = false,
                        ["slotLease"] = "inv.test." + snapshotSeq + "." + physicalSlot
                    });
                }
            }
            return new JObject
            {
                ["containerId"] = containerId,
                ["capacity"] = capacity,
                ["accessibleCapacity"] = capacity,
                ["viewCapacity"] = capacity,
                ["filterKey"] = "all",
                ["pageSizeHint"] = containerId == "战备箱" ? 40 : 50,
                ["locked"] = false,
                ["snapshotSeq"] = snapshotSeq,
                ["containerEpoch"] = 1,
                ["containerVersion"] = snapshotSeq,
                ["offset"] = offset,
                ["limit"] = limit,
                ["slots"] = slots,
                ["filterFacets"] = new JArray(Facet("all", "全部", 1)),
                ["filterItemCount"] = 1,
                ["setFacets"] = new JArray(Facet("test_set", "测试套装", 1)),
                ["setFilterItemCount"] = 1
            };
        }

        private static JObject SnapshotResponse(JObject flash, params JObject[] snapshots)
        {
            return new JObject
            {
                ["task"] = "inventory_response",
                ["callId"] = flash.Value<int>("callId"),
                ["success"] = true,
                ["v"] = 1,
                ["sessionNonce"] = "inv.test.session",
                ["snapshots"] = new JArray(snapshots)
            };
        }

        private static JObject StrictWriteRequest(string cmd, string callId)
        {
            JObject request = Request(cmd, callId);
            if (cmd == "autoTransfer")
            {
                request["payload"]["windows"] = new JArray
                {
                    new JObject
                    {
                        ["containerId"] = "背包", ["offset"] = 0,
                        ["limit"] = 1, ["filterKey"] = "all"
                    },
                    new JObject
                    {
                        ["containerId"] = "仓库", ["offset"] = 0,
                        ["limit"] = 1, ["filterKey"] = "all"
                    }
                };
            }
            else if (cmd == "sortAndMerge")
            {
                request["payload"]["container"]["offset"] = 0;
                request["payload"]["container"]["limit"] = 1;
            }
            return request;
        }

        private static JObject StrictWriteSuccess(string cmd, JObject flash)
        {
            var response = new JObject
            {
                ["task"] = "inventory_response",
                ["callId"] = flash.Value<int>("callId"),
                ["success"] = true,
                ["v"] = 1
            };
            if (cmd == "discard")
            {
                response["operation"] = "discard";
                response["discarded"] = ItemProjection();
                response["snapshots"] = new JArray(
                    Snapshot("背包", 50, 2, 1, 101));
            }
            else if (cmd == "move" || cmd == "merge" || cmd == "swap")
            {
                response["operation"] = cmd;
                response["snapshots"] = new JArray
                {
                    Snapshot("背包", 50, 2, 1, 102),
                    Snapshot("仓库", 1200, 52, 1, 103)
                };
            }
            else if (cmd == "autoTransfer")
            {
                response["operation"] = "move";
                response["policy"] = "mergeThenEmpty";
                response["destination"] = new JObject
                {
                    ["containerId"] = "仓库",
                    ["slot"] = 0
                };
                response["snapshots"] = new JArray
                {
                    Snapshot("背包", 50, 0, 1, 104),
                    Snapshot("仓库", 1200, 0, 1, 105)
                };
            }
            else if (cmd == "sortAndMerge")
            {
                response["operation"] = "sortAndMerge";
                response["methodName"] = "byType";
                response["sortedCapacity"] = 1200;
                response["snapshots"] = new JArray(
                    Snapshot("仓库", 1200, 0, 1, 106));
            }
            return response;
        }

        private static JObject FirstSnapshot(JObject response)
        {
            return (JObject)response["snapshots"][0];
        }

        private static JObject FirstItem(JObject response)
        {
            return (JObject)FirstSnapshot(response)["slots"][0]["item"];
        }

        private static JObject FirstConfirm(JObject response)
        {
            return (JObject)FirstSnapshot(response)["slots"][0]
                ["confirmProjection"];
        }

        private static void MakeValidStack(JObject response)
        {
            JObject item = FirstItem(response);
            JObject confirm = FirstConfirm(response);
            item["itemKind"] = "stack";
            item["quantity"] = 1;
            item["enhancementLevel"] = 0;
            item["isMaxEnhancement"] = false;
            item["tierSlotAvailable"] = false;
            item["tierSlotUsed"] = false;
            item["modSlotCapacity"] = 0;
            item["modSlotUsed"] = 0;
            item["modSlots"] = new JArray();
            confirm["itemKind"] = "stack";
            confirm["quantity"] = 1;
            confirm["enhancementLevel"] = 0;
        }

        private static void MutateStrictWriteSnapshot(
            JObject response,
            string mutation)
        {
            JObject snapshot = FirstSnapshot(response);
            JObject item = FirstItem(response);
            JObject confirm = FirstConfirm(response);
            switch (mutation)
            {
                case "duplicate_container":
                    ((JArray)response["snapshots"]).Add(snapshot.DeepClone());
                    break;
                case "snapshot_seq_zero":
                    snapshot["snapshotSeq"] = 0;
                    break;
                case "container_epoch_zero":
                    snapshot["containerEpoch"] = 0;
                    break;
                case "window_out_of_range":
                    snapshot["viewCapacity"] = 0;
                    break;
                case "window_limit_exceeds_view":
                    snapshot["limit"] = 2;
                    break;
                case "facet_total_mismatch":
                    snapshot["filterItemCount"] = 0;
                    snapshot["setFilterItemCount"] = 0;
                    snapshot["setFacets"] = new JArray();
                    break;
                case "set_count_exceeds_filter":
                    snapshot["setFilterItemCount"] = 2;
                    snapshot["setFacets"][0]["count"] = 2;
                    break;
                case "facet_child_exceeds_parent":
                    snapshot["filterItemCount"] = 0;
                    snapshot["filterFacets"] = new JArray(
                        new JObject
                        {
                            ["id"] = "root", ["label"] = "根", ["order"] = 1,
                            ["count"] = 0,
                            ["children"] = new JArray(Facet("child", "子项", 1))
                        });
                    snapshot["setFilterItemCount"] = 0;
                    snapshot["setFacets"] = new JArray();
                    break;
                case "set_facet_has_children":
                    snapshot["setFacets"][0]["children"] =
                        new JArray(Facet("child_set", "子套装", 1));
                    break;
                case "name_empty":
                    item["name"] = "";
                    confirm["name"] = "";
                    break;
                case "display_name_empty":
                    item["displayName"] = "";
                    confirm["displayName"] = "";
                    break;
                case "icon_empty":
                    item["icon"] = "";
                    break;
                case "set_order_negative":
                    item["setOrder"] = -1;
                    break;
                case "stack_quantity_zero":
                    MakeValidStack(response);
                    item["quantity"] = 0;
                    confirm["quantity"] = 0;
                    break;
                case "stack_enhancement_nonzero":
                    MakeValidStack(response);
                    item["enhancementLevel"] = 1;
                    confirm["enhancementLevel"] = 1;
                    break;
                case "stack_tier_available":
                    MakeValidStack(response);
                    item["tierSlotAvailable"] = true;
                    break;
                case "stack_mod_capacity":
                    MakeValidStack(response);
                    item["modSlotCapacity"] = 1;
                    break;
                case "tier_used_without_available":
                    item["tierSlotAvailable"] = false;
                    item["tierSlotUsed"] = true;
                    break;
                case "mod_count_exceeds_used":
                    item["modSlotUsed"] = 0;
                    break;
                case "more_than_three_mods":
                    JObject mod = (JObject)item["modSlots"][0];
                    item["modSlots"] = new JArray(
                        mod.DeepClone(), mod.DeepClone(), mod.DeepClone(), mod.DeepClone());
                    item["modSlotCapacity"] = 4;
                    item["modSlotUsed"] = 4;
                    break;
                case "empty_set_filter_id":
                    snapshot["filterSpec"] = new JObject
                    {
                        ["branch"] = "set",
                        ["setId"] = ""
                    };
                    break;
                case "explicit_scope_all":
                    snapshot["scope"] = "all";
                    break;
                case "null_filter_spec":
                    snapshot["filterSpec"] = JValue.CreateNull();
                    break;
                case "identity_control_character":
                    item["name"] = "测试\n步枪";
                    confirm["name"] = "测试\n步枪";
                    break;
                default:
                    throw new ArgumentOutOfRangeException(nameof(mutation));
            }
        }

        public static IEnumerable<object[]> StrictWriteSnapshotMutationCases()
        {
            string[] commands =
            {
                "discard", "move", "merge", "swap", "autoTransfer", "sortAndMerge"
            };
            string[] mutations =
            {
                "duplicate_container", "snapshot_seq_zero", "container_epoch_zero",
                "window_out_of_range", "window_limit_exceeds_view",
                "facet_total_mismatch", "set_count_exceeds_filter",
                "facet_child_exceeds_parent", "set_facet_has_children",
                "name_empty", "display_name_empty", "icon_empty",
                "set_order_negative", "stack_quantity_zero",
                "stack_enhancement_nonzero", "stack_tier_available",
                "stack_mod_capacity", "tier_used_without_available",
                "mod_count_exceeds_used", "more_than_three_mods",
                "empty_set_filter_id", "explicit_scope_all",
                "null_filter_spec", "identity_control_character"
            };
            foreach (string command in commands)
            foreach (string mutation in mutations)
                yield return new object[] { command, mutation };
        }

        [Theory]
        [InlineData("discard")]
        [InlineData("move")]
        [InlineData("merge")]
        [InlineData("swap")]
        [InlineData("autoTransfer")]
        [InlineData("sortAndMerge")]
        public void StrictWriteSnapshotBaselineIsAcceptedForEveryMutationCommand(
            string cmd)
        {
            string sent = null;
            string posted = null;
            var task = new InventoryTask(
                () => true,
                payload => { sent = payload; return true; });
            task.SetPostToWeb(json => posted = json);
            task.HandleWebRequest(
                cmd,
                StrictWriteRequest(
                    cmd,
                    "inventory.strict.baseline." + cmd));

            task.HandleFlashResponse(
                StrictWriteSuccess(cmd, ParseSent(sent)),
                _ => { });

            Assert.True(JObject.Parse(posted).Value<bool>("success"));
            Assert.Equal("idle", task.WriteState);
            task.Dispose();
        }

        [Theory]
        [MemberData(nameof(StrictWriteSnapshotMutationCases))]
        public void EveryMalformedWriteSnapshotFailsClosedWithoutReplay(
            string cmd,
            string mutation)
        {
            var sent = new List<JObject>();
            var posted = new List<JObject>();
            var task = new InventoryTask(
                () => true,
                payload =>
                {
                    sent.Add(ParseSent(payload));
                    return true;
                });
            task.SetPostToWeb(json => posted.Add(JObject.Parse(json)));
            string suffix = cmd + "." + mutation;
            task.HandleWebRequest(
                cmd,
                StrictWriteRequest(
                    cmd,
                    "inventory.strict.malformed." + suffix));
            Assert.Single(sent);
            JObject malformed = StrictWriteSuccess(cmd, sent[0]);
            MutateStrictWriteSnapshot(malformed, mutation);

            task.HandleFlashResponse(malformed, _ => { });

            Assert.Equal("needs_reconcile", task.WriteState);
            Assert.True(posted[posted.Count - 1].Value<bool>("requiresReconcile"));
            Assert.Equal(
                "malformed_response",
                posted[posted.Count - 1].Value<string>("error"));
            Assert.Single(sent);

            task.HandleWebRequest(
                "discard",
                StrictWriteRequest(
                    "discard",
                    "inventory.strict.blocked." + suffix));
            Assert.Equal(
                "reconcile_required",
                posted[posted.Count - 1].Value<string>("error"));
            Assert.Single(sent);
            int responseCount = posted.Count;

            task.HandleFlashResponse(malformed, _ => { });

            Assert.Equal(responseCount, posted.Count);
            Assert.Single(sent);
            Assert.Equal("needs_reconcile", task.WriteState);
            task.Dispose();
        }

        [Theory]
        [InlineData("discard", "source")]
        [InlineData("move", "target")]
        [InlineData("merge", "source")]
        [InlineData("swap", "target")]
        [InlineData("autoTransfer", "window")]
        [InlineData("sortAndMerge", "container")]
        public void UnknownContainerWriteIsRejectedBeforeAdmission(
            string cmd,
            string location)
        {
            int sends = 0;
            string posted = null;
            var task = new InventoryTask(
                () => true,
                _ => { sends++; return true; });
            task.SetPostToWeb(json => posted = json);
            JObject request = StrictWriteRequest(
                cmd,
                "inventory.unknown-container." + cmd);
            if (location == "source")
                request["payload"]["source"]["containerId"] = "秘密容器";
            else if (location == "target")
                request["payload"]["target"]["containerId"] = "秘密容器";
            else if (location == "window")
                request["payload"]["windows"][0]["containerId"] = "秘密容器";
            else
                request["payload"]["container"]["containerId"] = "秘密容器";

            task.HandleWebRequest(cmd, request);

            Assert.Equal("invalid_payload", JObject.Parse(posted).Value<string>("error"));
            Assert.Equal(0, sends);
            Assert.Equal("idle", task.WriteState);
            task.Dispose();
        }

        [Theory]
        [InlineData("snapshot", false)]
        [InlineData("autoTransfer", true)]
        public void InvalidSnapshotWindowSetIsRejectedBeforeTransport(
            string cmd,
            bool duplicate)
        {
            int sends = 0;
            string posted = null;
            var task = new InventoryTask(
                () => true,
                _ => { sends++; return true; });
            task.SetPostToWeb(json => posted = json);
            JObject request = cmd == "snapshot"
                ? Request(cmd, "inventory.window.unknown")
                : StrictWriteRequest(cmd, "inventory.window.duplicate");
            JArray windows = (JArray)request["payload"]
                [cmd == "snapshot" ? "requests" : "windows"];
            if (duplicate)
                windows[1]["containerId"] = windows[0].Value<string>("containerId");
            else
                windows[0]["containerId"] = "秘密容器";

            task.HandleWebRequest(cmd, request);

            Assert.Equal("invalid_payload", JObject.Parse(posted).Value<string>("error"));
            Assert.Equal(0, sends);
            Assert.Equal("idle", task.WriteState);
            task.Dispose();
        }

        [Theory]
        [InlineData("snapshot", "inventorySnapshot")]
        [InlineData("tooltip", "inventoryTooltip")]
        [InlineData("discard", "inventoryDiscard")]
        [InlineData("move", "inventoryMove")]
        [InlineData("merge", "inventoryMerge")]
        [InlineData("swap", "inventorySwap")]
        [InlineData("autoTransfer", "inventoryAutoTransfer")]
        [InlineData("sortAndMerge", "inventorySortAndMerge")]
        public void KnownCommands_MapToTrustedActionAndUnwrapNormalizedPayload(string cmd, string action)
        {
            string sent = null;
            var task = new InventoryTask(() => true, payload => { sent = payload; return true; });
            JObject request = Request(cmd);
            request["action"] = "evil";
            request["task"] = "evil";
            request["op"] = "evil";
            ((JObject)request["payload"])["unknown"] = "drop-me";

            task.HandleWebRequest(cmd, request);

            JObject message = ParseSent(sent);
            Assert.Equal("cmd", (string)message["task"]);
            Assert.Equal(action, (string)message["action"]);
            Assert.Equal(1, (int)message["v"]);
            Assert.Null(message["payload"]);
            Assert.Null(message["domain"]);
            Assert.Null(message["panel"]);
            Assert.Null(message["cmd"]);
            Assert.Null(message["op"]);
            Assert.Null(message["unknown"]);
        }

        [Fact]
        public void Snapshot_RebuildsOnlyRangeWhitelist()
        {
            string sent = null;
            var task = new InventoryTask(() => true, payload => { sent = payload; return true; });
            JObject request = Request("snapshot");
            ((JObject)((JArray)request["payload"]["requests"])[0])["action"] = "evil";

            task.HandleWebRequest("snapshot", request);

            JObject message = ParseSent(sent);
            Assert.Equal(2, ((JArray)message["requests"]).Count);
            Assert.Equal("仓库", (string)message["requests"][1]["containerId"]);
            Assert.Equal(50, (int)message["requests"][1]["offset"]);
            Assert.Equal("material", (string)message["requests"][1]["filterKey"]);
            Assert.Null(message["requests"][0]["action"]);
            Assert.Null(message["requests"][0]["scope"]);
        }

        [Fact]
        public void Snapshot_EquipmentScopeIsWhitelistedForBackpackOnly()
        {
            string sent = null;
            var task = new InventoryTask(() => true, payload => { sent = payload; return true; });
            JObject request = Request("snapshot", "wb.inventory.scope.equipment");
            request["payload"]["requests"][0]["scope"] = "equipment";

            task.HandleWebRequest("snapshot", request);

            JObject message = ParseSent(sent);
            Assert.Equal("equipment", (string)message["requests"][0]["scope"]);
            Assert.Null(message["requests"][1]["scope"]);
        }

        [Theory]
        [InlineData("背包", "developer")]
        [InlineData("仓库", "equipment")]
        [InlineData("战备箱", "equipment")]
        public void Snapshot_RejectsUnknownOrNonBackpackEquipmentScope(string containerId, string scope)
        {
            int sends = 0;
            string posted = null;
            var task = new InventoryTask(() => true, _ => { sends++; return true; });
            task.SetPostToWeb(json => posted = json);
            JObject request = Request("snapshot", "wb.inventory.scope.bad");
            request["payload"]["requests"][0]["containerId"] = containerId;
            request["payload"]["requests"][0]["scope"] = scope;

            task.HandleWebRequest("snapshot", request);

            Assert.Equal(0, sends);
            Assert.Equal("invalid_payload", (string)JObject.Parse(posted)["error"]);
        }

        [Fact]
        public void Snapshot_FilterWhitelistRejectsUnknownCategory()
        {
            int sends = 0;
            string posted = null;
            var task = new InventoryTask(() => true, _ => { sends++; return true; });
            task.SetPostToWeb(json => posted = json);
            JObject request = Request("snapshot", "wb.inventory.filter.bad");
            request["payload"]["requests"][0]["filterKey"] = "developer-secret";

            task.HandleWebRequest("snapshot", request);

            Assert.Equal(0, sends);
            Assert.Equal("invalid_payload", (string)JObject.Parse(posted)["error"]);
        }

        [Fact]
        public void Snapshot_StructuredFilterRebuildsBoundedWhitelist()
        {
            string sent = null;
            var task = new InventoryTask(() => true, payload => { sent = payload; return true; });
            JObject request = Request("snapshot", "wb.inventory.filter.structured");
            var window = (JObject)request["payload"]["requests"][0];
            window["filterKey"] = "weapon";
            window["filterSpec"] = new JObject
            {
                ["major"] = "weapon", ["use"] = "长枪", ["subtype"] = "突击步枪", ["predicate"] = "evil"
            };

            task.HandleWebRequest("snapshot", request);

            JObject message = ParseSent(sent);
            JObject spec = (JObject)message["requests"][0]["filterSpec"];
            Assert.Equal("weapon", (string)spec["major"]);
            Assert.Equal("长枪", (string)spec["use"]);
            Assert.Equal("突击步枪", (string)spec["subtype"]);
            Assert.Null(spec["predicate"]);
        }

        [Theory]
        [InlineData("weapon", "", "突击步枪")]
        [InlineData("all", "长枪", "")]
        [InlineData("developer-secret", "", "")]
        public void Snapshot_StructuredFilterRejectsInvalidPaths(string major, string use, string subtype)
        {
            int sends = 0;
            string posted = null;
            var task = new InventoryTask(() => true, _ => { sends++; return true; });
            task.SetPostToWeb(json => posted = json);
            JObject request = Request("snapshot", "wb.inventory.filter.structured.bad." + major);
            request["payload"]["requests"][0]["filterSpec"] = new JObject
            {
                ["major"] = major, ["use"] = use, ["subtype"] = subtype
            };

            task.HandleWebRequest("snapshot", request);

            Assert.Equal(0, sends);
            Assert.Equal("invalid_payload", (string)JObject.Parse(posted)["error"]);
        }

        [Fact]
        public void Snapshot_SetFilterRebuildsBoundedWhitelist()
        {
            string sent = null;
            var task = new InventoryTask(() => true, payload => { sent = payload; return true; });
            JObject request = Request("snapshot", "wb.inventory.filter.set");
            var window = (JObject)request["payload"]["requests"][0];
            window["filterKey"] = "all";
            window["filterSpec"] = new JObject
            {
                ["branch"] = "set", ["setId"] = "hazmat_b", ["predicate"] = "evil"
            };

            task.HandleWebRequest("snapshot", request);

            JObject spec = (JObject)ParseSent(sent)["requests"][0]["filterSpec"];
            Assert.Equal("set", (string)spec["branch"]);
            Assert.Equal("hazmat_b", (string)spec["setId"]);
            Assert.Null(spec["predicate"]);
            Assert.Null(spec["major"]);
        }

        [Theory]
        [InlineData("all", "weapon")]
        [InlineData("weapon", "armor")]
        [InlineData("material", "collection")]
        public void Snapshot_StructuredFilterRejectsFilterKeyMismatch(string filterKey, string major)
        {
            int sends = 0;
            string posted = null;
            var task = new InventoryTask(() => true, _ => { sends++; return true; });
            task.SetPostToWeb(json => posted = json);
            JObject request = Request("snapshot", "wb.inventory.filter.mismatch." + filterKey);
            var window = (JObject)request["payload"]["requests"][0];
            window["filterKey"] = filterKey;
            window["filterSpec"] = new JObject { ["major"] = major };

            task.HandleWebRequest("snapshot", request);

            Assert.Equal(0, sends);
            Assert.Equal("invalid_payload", (string)JObject.Parse(posted)["error"]);
        }

        [Fact]
        public void Snapshot_CollectionFilterUsesLegacyOtherKey()
        {
            string sent = null;
            var task = new InventoryTask(() => true, payload => { sent = payload; return true; });
            JObject request = Request("snapshot", "wb.inventory.filter.collection");
            var window = (JObject)request["payload"]["requests"][0];
            window["filterKey"] = "other";
            window["filterSpec"] = new JObject { ["major"] = "collection", ["use"] = "材料" };

            task.HandleWebRequest("snapshot", request);

            JObject message = ParseSent(sent);
            Assert.Equal("other", (string)message["requests"][0]["filterKey"]);
            Assert.Equal("collection", (string)message["requests"][0]["filterSpec"]["major"]);
        }

        [Fact]
        public void BattleboxWorkbench_NormalizesSnapshotAndCrossContainerTransfer()
        {
            var sent = new List<JObject>();
            var task = new InventoryTask(() => true, payload => { sent.Add(ParseSent(payload)); return true; });
            JObject snapshot = Request("snapshot", "wb.battlebox.snapshot.1");
            snapshot["panel"] = "workbench";
            snapshot["payload"]["requests"] = new JArray
            {
                new JObject { ["containerId"] = "背包", ["offset"] = 0, ["limit"] = 50 },
                new JObject { ["containerId"] = "战备箱", ["offset"] = 40, ["limit"] = 40 }
            };
            task.HandleWebRequest("snapshot", snapshot);

            JObject move = Request("move", "wb.battlebox.move.1");
            move["panel"] = "workbench";
            move["payload"]["target"] = SlotRef("战备箱", 41, "inv200.41");
            task.HandleWebRequest("move", move);

            Assert.Equal("战备箱", (string)sent[0]["requests"][1]["containerId"]);
            Assert.Equal(40, (int)sent[0]["requests"][1]["limit"]);
            Assert.Equal("inventoryMove", (string)sent[1]["action"]);
            Assert.Equal("战备箱", (string)sent[1]["target"]["containerId"]);
        }

        [Fact]
        public void Tooltip_IsLeaseBoundAndDropsSpoofedItemIdentity()
        {
            string sent = null;
            var task = new InventoryTask(() => true, payload => { sent = payload; return true; });
            JObject request = Request("tooltip", "wb.inventory.tooltip.1");
            request["payload"]["itemName"] = "伪造物品";
            request["payload"]["raw"] = "伪造存档串";

            task.HandleWebRequest("tooltip", request);

            JObject message = ParseSent(sent);
            Assert.Equal("inventoryTooltip", (string)message["action"]);
            Assert.Equal("背包", (string)message["source"]["containerId"]);
            Assert.Equal(2, (int)message["source"]["slot"]);
            Assert.Equal("inv100.2", (string)message["source"]["expectedLease"]);
            Assert.Null(message["itemName"]);
            Assert.Null(message["raw"]);
            Assert.Null(message["target"]);
        }

        [Fact]
        public void CharacterCandidateTooltipEnvelopeRequiresExactInstanceContextAndSource()
        {
            JObject request = Request(
                "tooltip", "character.tooltip.envelope.1");
            request["panel"] = "workbench";
            request["panelInstanceId"] = "panel.workbench.build.1";
            request["payload"]["context"] = new JObject
            {
                ["kind"] = "character_build_candidate",
                ["sessionGeneration"] = 7
            };

            JObject source;
            long generation;
            Assert.True(WebOverlayForm
                .TryValidateCharacterBuildCandidateTooltipEnvelope(
                    request,
                    "workbench",
                    "panel.workbench.build.1",
                    out source,
                    out generation));
            Assert.Equal(7, generation);
            Assert.Equal(2, source.Value<int>("slot"));
            Assert.False(WebOverlayForm
                .TryValidateCharacterBuildCandidateTooltipEnvelope(
                    request,
                    "workbench",
                    "panel.workbench.replaced",
                    out source,
                    out generation));

            request["cmd"] = "move";
            Assert.False(WebOverlayForm
                .TryValidateCharacterBuildCandidateTooltipEnvelope(
                    request,
                    "workbench",
                    "panel.workbench.build.1",
                    out source,
                    out generation));
            request["cmd"] = "tooltip";
            request["payload"]["context"]["extra"] = true;
            Assert.False(WebOverlayForm
                .TryValidateCharacterBuildCandidateTooltipEnvelope(
                    request,
                    "workbench",
                    "panel.workbench.build.1",
                    out source,
                    out generation));

            request["payload"]["context"] = new JObject
            {
                ["kind"] = "character_build_candidates",
                ["sessionGeneration"] = 7
            };
            Assert.True(WebOverlayForm.HasInventoryPayloadContext(request));
            Assert.False(WebOverlayForm
                .TryValidateCharacterBuildCandidateTooltipEnvelope(
                    request,
                    "workbench",
                    "panel.workbench.build.1",
                    out source,
                    out generation));
            request["payload"]["context"] = new JObject
            {
                ["sessionGeneration"] = 7
            };
            Assert.True(WebOverlayForm.HasInventoryPayloadContext(request));
            Assert.False(WebOverlayForm
                .TryValidateCharacterBuildCandidateTooltipEnvelope(
                    request,
                    "workbench",
                    "panel.workbench.build.1",
                    out source,
                    out generation));
            request["payload"]["context"] = "candidate";
            Assert.True(WebOverlayForm.HasInventoryPayloadContext(request));
            Assert.False(WebOverlayForm
                .TryValidateCharacterBuildCandidateTooltipEnvelope(
                    request,
                    "workbench",
                    "panel.workbench.build.1",
                    out source,
                    out generation));
            ((JObject)request["payload"]).Remove("context");
            Assert.False(WebOverlayForm.HasInventoryPayloadContext(request));
        }

        [Fact]
        public void CharacterCandidateTooltipStrictlyRebuildsValidRichResponse()
        {
            string sent = null;
            string posted = null;
            var task = new InventoryTask(
                () => true,
                payload => { sent = payload; return true; });
            task.SetPostToWeb(json => posted = json);
            JObject request = Request(
                "tooltip", "character.tooltip.strict.valid");
            request["panel"] = "workbench";
            request["panelInstanceId"] = "panel.workbench.build.1";
            task.HandleCharacterCandidateTooltip(request, () => true);
            JObject flash = ParseSent(sent);

            task.HandleFlashResponse(
                CharacterTooltipSuccess(flash),
                _ => { });

            JObject response = JObject.Parse(posted);
            Assert.True(response.Value<bool>("success"));
            Assert.Equal("workbench", response.Value<string>("panel"));
            Assert.Equal(
                "panel.workbench.build.1",
                response.Value<string>("panelInstanceId"));
            Assert.Equal("<b>候选</b>", response.Value<string>("introHTML"));
            Assert.Null(response["task"]);
        }

        [Fact]
        public void CharacterCandidateTooltipRejectsExtraKeysAndControlMarkup()
        {
            Action<Action<JObject>> assertMalformed = mutate =>
            {
                string sent = null;
                string posted = null;
                var task = new InventoryTask(
                    () => true,
                    payload => { sent = payload; return true; });
                task.SetPostToWeb(json => posted = json);
                JObject request = Request(
                    "tooltip",
                    "character.tooltip.malformed."
                        + Guid.NewGuid().ToString("N"));
                request["panel"] = "workbench";
                request["panelInstanceId"] = "panel.workbench.build.1";
                task.HandleCharacterCandidateTooltip(request, () => true);
                JObject response = CharacterTooltipSuccess(ParseSent(sent));
                mutate(response);
                task.HandleFlashResponse(response, _ => { });
                JObject web = JObject.Parse(posted);
                Assert.Equal(
                    "malformed_response",
                    web.Value<string>("error"));
                Assert.Null(web["introHTML"]);
                task.Dispose();
            };

            assertMalformed(response => response["extra"] = true);
            assertMalformed(response => response["descHTML"] = "说明\0注入");
        }

        [Fact]
        public void CharacterCandidateTooltipDropsRichDataWhenCompletionFenceExpires()
        {
            string sent = null;
            string posted = null;
            bool current = true;
            var task = new InventoryTask(
                () => true,
                payload => { sent = payload; return true; });
            task.SetPostToWeb(json => posted = json);
            JObject request = Request(
                "tooltip", "character.tooltip.stale.1");
            request["panel"] = "workbench";
            request["panelInstanceId"] = "panel.workbench.build.1";
            task.HandleCharacterCandidateTooltip(
                request, () => current);
            JObject flash = ParseSent(sent);
            current = false;

            task.HandleFlashResponse(
                CharacterTooltipSuccess(flash),
                _ => { });

            JObject response = JObject.Parse(posted);
            Assert.Equal("stale_state", response.Value<string>("error"));
            Assert.Null(response["introHTML"]);
            Assert.Null(response["descHTML"]);
        }

        [Fact]
        public void GenericInventoryTooltipStrictlyRebuildsResponse()
        {
            string sent = null;
            string posted = null;
            var task = new InventoryTask(
                () => true,
                payload => { sent = payload; return true; });
            task.SetPostToWeb(json => posted = json);
            JObject request = Request(
                "tooltip", "inventory.tooltip.legacy.1");
            task.HandleWebRequest("tooltip", request);
            JObject response = CharacterTooltipSuccess(ParseSent(sent));
            task.HandleFlashResponse(response, _ => { });

            JObject web = JObject.Parse(posted);
            Assert.True(web.Value<bool>("success"));
            Assert.Equal("候选图标", web.Value<string>("iconName"));
            Assert.Null(web["task"]);
            Assert.Null(web["legacyProjection"]);
        }

        [Fact]
        public void GenericInventoryTooltipRejectsUnprovedExtraField()
        {
            string sent = null;
            string posted = null;
            var task = new InventoryTask(
                () => true,
                payload => { sent = payload; return true; });
            task.SetPostToWeb(json => posted = json);
            JObject request = Request(
                "tooltip", "inventory.tooltip.strict.extra");
            task.HandleWebRequest("tooltip", request);
            JObject response = CharacterTooltipSuccess(ParseSent(sent));
            response["legacyProjection"] = "unproved";

            task.HandleFlashResponse(response, _ => { });

            JObject web = JObject.Parse(posted);
            Assert.Equal("malformed_response", web.Value<string>("error"));
            Assert.Null(web["legacyProjection"]);
        }

        [Fact]
        public void SortAndMerge_RebuildsContainerAndStrictMethodWhitelist()
        {
            string sent = null;
            var posted = new List<JObject>();
            var task = new InventoryTask(() => true, payload => { sent = payload; return true; });
            task.SetPostToWeb(json => posted.Add(JObject.Parse(json)));
            JObject request = Request("sortAndMerge", "wb.inventory.sort.1");
            request["payload"]["container"]["action"] = "evil";
            request["payload"]["unknown"] = "drop-me";

            task.HandleWebRequest("sortAndMerge", request);

            JObject message = ParseSent(sent);
            Assert.Equal("inventorySortAndMerge", (string)message["action"]);
            Assert.Equal("仓库", (string)message["container"]["containerId"]);
            Assert.Equal(50, (int)message["container"]["offset"]);
            Assert.Equal("byType", (string)message["methodName"]);
            Assert.Equal("all", (string)message["container"]["filterKey"]);
            Assert.Null(message["container"]["action"]);
            Assert.Null(message["unknown"]);

            JObject bad = Request("sortAndMerge", "wb.inventory.sort.2");
            bad["payload"]["methodName"] = "fallback-please";
            task.HandleWebRequest("sortAndMerge", bad);
            Assert.Equal("invalid_payload", (string)posted[0]["error"]);
        }

        [Theory]
        [InlineData("背包", "weapon")]
        [InlineData("仓库", "material")]
        [InlineData("战备箱", "other")]
        public void SortAndMerge_AllInventoryContainersPreserveTrustedFilterWindow(string containerId, string filterKey)
        {
            string sent = null;
            var task = new InventoryTask(() => true, payload => { sent = payload; return true; });
            JObject request = Request("sortAndMerge", "wb.inventory.sort.scope");
            request["payload"]["container"]["containerId"] = containerId;
            request["payload"]["container"]["filterKey"] = filterKey;

            task.HandleWebRequest("sortAndMerge", request);

            JObject message = ParseSent(sent);
            Assert.Equal(containerId, (string)message["container"]["containerId"]);
            Assert.Equal(filterKey, (string)message["container"]["filterKey"]);
            Assert.Equal("inventorySortAndMerge", (string)message["action"]);
        }

        [Fact]
        public void SortAndMerge_RejectsScopedProjectionToAvoidSortingHiddenFullInventory()
        {
            int sends = 0;
            string posted = null;
            var task = new InventoryTask(() => true, _ => { sends++; return true; });
            task.SetPostToWeb(json => posted = json);
            JObject request = Request("sortAndMerge", "wb.inventory.sort.equipment-scope");
            request["payload"]["container"]["containerId"] = "背包";
            request["payload"]["container"]["scope"] = "equipment";

            task.HandleWebRequest("sortAndMerge", request);

            Assert.Equal(0, sends);
            Assert.Equal("invalid_payload", (string)JObject.Parse(posted)["error"]);
        }

        [Fact]
        public void AutoTransfer_RebuildsSourceTargetPolicyAndVisibleWindowsOnly()
        {
            string sent = null;
            var task = new InventoryTask(() => true, payload => { sent = payload; return true; });
            JObject request = Request("autoTransfer", "wb.inventory.auto.1");
            request["payload"]["target"] = SlotRef("仓库", 999, "spoofed.target");
            request["payload"]["windows"][0]["action"] = "evil";

            task.HandleWebRequest("autoTransfer", request);

            JObject message = ParseSent(sent);
            Assert.Equal("inventoryAutoTransfer", (string)message["action"]);
            Assert.Equal("仓库", (string)message["targetContainerId"]);
            Assert.Equal("mergeThenEmpty", (string)message["policy"]);
            Assert.Equal("背包", (string)message["source"]["containerId"]);
            Assert.Equal(2, ((JArray)message["windows"]).Count);
            Assert.Equal("material", (string)message["windows"][1]["filterKey"]);
            Assert.Null(message["target"]);
            Assert.Null(message["windows"][0]["action"]);
        }

        [Fact]
        public void AutoTransfer_PreservesTrustedEquipmentWindowScope()
        {
            string sent = null;
            var task = new InventoryTask(() => true, payload => { sent = payload; return true; });
            JObject request = Request("autoTransfer", "wb.inventory.auto.scope");
            request["payload"]["windows"][0]["scope"] = "equipment";

            task.HandleWebRequest("autoTransfer", request);

            JObject message = ParseSent(sent);
            Assert.Equal("equipment", (string)message["windows"][0]["scope"]);
            Assert.Null(message["windows"][1]["scope"]);
        }

        [Theory]
        [InlineData("swapThenEmpty", "仓库")]
        [InlineData("mergeThenEmpty", "秘密容器")]
        public void AutoTransfer_RejectsUntrustedPolicyAndTargetContainer(string policy, string targetContainerId)
        {
            int sends = 0;
            string posted = null;
            var task = new InventoryTask(() => true, _ => { sends++; return true; });
            task.SetPostToWeb(json => posted = json);
            JObject request = Request("autoTransfer", "wb.inventory.auto.bad." + sends + policy.Length);
            request["payload"]["policy"] = policy;
            request["payload"]["targetContainerId"] = targetContainerId;

            task.HandleWebRequest("autoTransfer", request);

            Assert.Equal(0, sends);
            Assert.Equal("invalid_payload", (string)JObject.Parse(posted)["error"]);
        }

        [Fact]
        public void TransferRejectsPartialCountAndMalformedLease()
        {
            int sends = 0;
            var posted = new List<JObject>();
            var task = new InventoryTask(() => true, _ => { sends++; return true; });
            task.SetPostToWeb(json => posted.Add(JObject.Parse(json)));

            JObject withCount = Request("move", "wb.inventory.1.1");
            withCount["payload"]["count"] = 1;
            task.HandleWebRequest("move", withCount);

            JObject badLease = Request("swap", "wb.inventory.1.2");
            badLease["payload"]["target"]["expectedLease"] = "bad lease";
            task.HandleWebRequest("swap", badLease);

            Assert.Equal(0, sends);
            Assert.All(posted, response => Assert.Equal("invalid_payload", (string)response["error"]));
        }

        [Fact]
        public void SameContainerTransferPreservesDistinctPhysicalSlotRefs()
        {
            string sent = null;
            var task = new InventoryTask(() => true, payload => { sent = payload; return true; });
            JObject request = Request("move", "wb.inventory.same.1");
            request["payload"]["target"] = SlotRef("背包", 7, "inv100.7");

            task.HandleWebRequest("move", request);

            JObject message = ParseSent(sent);
            Assert.Equal("背包", (string)message["source"]["containerId"]);
            Assert.Equal("背包", (string)message["target"]["containerId"]);
            Assert.Equal(2, (int)message["source"]["slot"]);
            Assert.Equal(7, (int)message["target"]["slot"]);
            Assert.Equal("inv100.2", (string)message["source"]["expectedLease"]);
            Assert.Equal("inv100.7", (string)message["target"]["expectedLease"]);
        }

        [Theory]
        [InlineData("bogus", 1, "unsupported_cmd")]
        [InlineData("snapshot", 2, "unsupported_version")]
        public void LocalRejectsPreserveInventoryRoutingShape(string cmd, int version, string error)
        {
            string posted = null;
            var task = new InventoryTask(() => true, _ => true);
            task.SetPostToWeb(json => posted = json);
            JObject request = Request("snapshot");
            request["cmd"] = cmd;
            request["payload"]["v"] = version;

            task.HandleWebRequest(cmd, request);

            JObject response = JObject.Parse(posted);
            Assert.Equal("panel_resp", (string)response["type"]);
            Assert.Equal("inventory", (string)response["domain"]);
            Assert.Equal(cmd, (string)response["cmd"]);
            Assert.Equal("wb.inventory.1.1", (string)response["callId"]);
            Assert.Equal(error, (string)response["error"]);
        }

        [Fact]
        public void DisconnectedAndInvalidCallIdNeverReachFlash()
        {
            int sends = 0;
            var posted = new List<JObject>();
            var task = new InventoryTask(() => false, _ => { sends++; return true; });
            task.SetPostToWeb(json => posted.Add(JObject.Parse(json)));

            task.HandleWebRequest("snapshot", Request("snapshot", "wb.inventory.1.1"));
            task.HandleWebRequest("snapshot", Request("snapshot", "bad call id"));

            Assert.Equal(0, sends);
            Assert.Equal("disconnected", (string)posted[0]["error"]);
            Assert.Equal("invalid_call_id", (string)posted[1]["error"]);
        }

        [Fact]
        public void FlashResponseRestoresDomainCmdAndWebCallId()
        {
            string sent = null;
            string posted = null;
            var task = new InventoryTask(() => true, payload => { sent = payload; return true; });
            task.SetPostToWeb(json => posted = json);
            JObject request = Request("move", "wb.inventory.4.9");
            request["panelInstanceId"] = "panel.kshop.inventory.4.9";
            task.HandleWebRequest("move", request);
            JObject flashRequest = ParseSent(sent);

            task.HandleFlashResponse(new JObject
            {
                ["task"] = "inventory_response",
                ["callId"] = (int)flashRequest["callId"],
                ["success"] = true,
                ["operation"] = "move",
                ["snapshots"] = new JArray()
            }, _ => { });

            JObject response = JObject.Parse(posted);
            Assert.Null(response["task"]);
            Assert.Equal("inventory", (string)response["domain"]);
            Assert.Equal("kshop", (string)response["panel"]);
            Assert.Equal("panel.kshop.inventory.4.9", (string)response["panelInstanceId"]);
            Assert.Equal("move", (string)response["cmd"]);
            Assert.Equal("wb.inventory.4.9", (string)response["callId"]);
        }

        [Fact]
        public void FlashCannotInjectPanelCapabilityWhenRequestHadNoBinding()
        {
            string sent = null;
            string posted = null;
            var task = new InventoryTask(() => true, payload => { sent = payload; return true; });
            task.SetPostToWeb(json => posted = json);
            JObject request = Request("snapshot", "wb.inventory.unbound.1");
            request.Remove("panel");
            task.HandleWebRequest("snapshot", request);
            JObject flashRequest = ParseSent(sent);

            task.HandleFlashResponse(new JObject
            {
                ["task"] = "inventory_response",
                ["callId"] = (int)flashRequest["callId"],
                ["success"] = true,
                ["panel"] = "loot",
                ["panelInstanceId"] = "panel.loot.injected",
                ["snapshots"] = new JArray()
            }, _ => { });

            JObject response = JObject.Parse(posted);
            Assert.Null(response["panel"]);
            Assert.Null(response["panelInstanceId"]);
        }

        [Fact]
        public void OrdinarySnapshotStrictlyRebuildsRecursiveProjectionAndOptionalBalanceSummary()
        {
            string sent = null;
            string posted = null;
            var task = new InventoryTask(
                () => true,
                payload => { sent = payload; return true; });
            task.SetPostToWeb(json => posted = json);
            JObject request = Request(
                "snapshot", "inventory.snapshot.strict.valid");
            request["payload"]["requests"] = new JArray
            {
                new JObject
                {
                    ["containerId"] = "背包", ["offset"] = 0,
                    ["limit"] = 2, ["filterKey"] = "all"
                }
            };
            task.HandleWebRequest("snapshot", request);
            JObject flash = ParseSent(sent);

            task.HandleFlashResponse(
                SnapshotResponse(
                    flash,
                    Snapshot("背包", 50, 0, 2, 11, true)),
                _ => { });

            JObject response = JObject.Parse(posted);
            Assert.True(response.Value<bool>("success"));
            Assert.Null(response["task"]);
            Assert.Equal(
                "confirmed",
                response["snapshots"][0]["slots"][0]["item"]
                    ["balanceSummary"].Value<string>("state"));
            Assert.Equal(
                "inv.test.11.0",
                response["snapshots"][0]["slots"][0]
                    .Value<string>("slotLease"));
            JObject mod = (JObject)response["snapshots"][0]["slots"][0]
                ["item"]["modSlots"][0];
            Assert.Equal("辅助握持板", mod.Value<string>("name"));
            Assert.Equal("人体工学握持板", mod.Value<string>("displayName"));
            Assert.Equal("握持板专用图标", mod.Value<string>("icon"));
        }

        [Fact]
        public void OrdinarySnapshotRejectsMalformedRecursiveLeavesAtomically()
        {
            Action<JObject>[] mutations =
            {
                response => response["snapshots"][0]["slots"][0]["extra"] = true,
                response => response["snapshots"][0]["slots"][1]["physicalSlot"] = 0,
                response => response["snapshots"][0]["slots"][1]["item"] = ItemProjection(),
                response => response["snapshots"][0]["slots"][0]["item"]["quantity"] = "1",
                response => response["snapshots"][0]["slots"][0]["item"]
                    ["modSlots"][0]["extra"] = "unproved",
                response => ((JObject)response["snapshots"][0]["slots"][0]["item"]
                    ["modSlots"][0]).Remove("displayName"),
                response => response["snapshots"][0]["slots"][0]["item"]
                    ["modSlots"][0]["icon"] = 7,
                response => response["snapshots"][0]["slots"][0]["item"]
                    ["modSlots"][0]["displayName"] = "   ",
                response => response["snapshots"][0]["slots"][0]["item"]
                    ["modSlots"][0]["icon"] = " Undefined ",
                response => response["snapshots"][0]["slots"][0]["item"]
                    ["name"] = " Undefined ",
                response => response["snapshots"][0]["slots"][0]["item"]
                    ["displayName"] = "   ",
                response => response["snapshots"][0]["slots"][0]["item"]
                    ["icon"] = "uNdEfInEd",
                response => response["snapshots"][0]["slots"][0]
                    ["confirmProjection"]["name"] = "错位物品",
                response => response["snapshots"][0]["slots"][0]["item"]
                    ["balanceSummary"]["formula"] = "1",
                response => response["snapshots"][0]["filterFacets"] = new JArray
                {
                    new JObject { ["id"] = "weapon", ["label"] = "武器" }
                }
            };

            foreach (Action<JObject> mutate in mutations)
            {
                string sent = null;
                string posted = null;
                var task = new InventoryTask(
                    () => true,
                    payload => { sent = payload; return true; });
                task.SetPostToWeb(json => posted = json);
                JObject request = Request(
                    "snapshot",
                    "inventory.snapshot.strict.bad."
                        + Guid.NewGuid().ToString("N"));
                request["payload"]["requests"] = new JArray
                {
                    new JObject
                    {
                        ["containerId"] = "背包", ["offset"] = 0,
                        ["limit"] = 2, ["filterKey"] = "all"
                    }
                };
                task.HandleWebRequest("snapshot", request);
                JObject response = SnapshotResponse(
                    ParseSent(sent),
                    Snapshot("背包", 50, 0, 2, 12, true));
                mutate(response);

                task.HandleFlashResponse(response, _ => { });

                JObject web = JObject.Parse(posted);
                Assert.Equal(
                    "malformed_response",
                    web.Value<string>("error"));
                Assert.Null(web["snapshots"]);
                task.Dispose();
            }
        }

        [Fact]
        public void FilteredSnapshotAllowsNonContiguousAuthoritativePhysicalSlots()
        {
            string sent = null;
            string posted = null;
            var task = new InventoryTask(
                () => true,
                payload => { sent = payload; return true; });
            task.SetPostToWeb(json => posted = json);
            JObject request = Request(
                "snapshot", "inventory.snapshot.filtered.noncontiguous");
            request["payload"]["requests"] = new JArray
            {
                new JObject
                {
                    ["containerId"] = "背包", ["offset"] = 0,
                    ["limit"] = 2, ["filterKey"] = "weapon"
                }
            };
            task.HandleWebRequest("snapshot", request);
            JObject snapshot = Snapshot("背包", 50, 0, 2, 13);
            snapshot["filterKey"] = "weapon";
            snapshot["viewCapacity"] = 2;
            snapshot["filterItemCount"] = 2;
            snapshot["filterFacets"][0]["count"] = 2;
            snapshot["slots"][0]["physicalSlot"] = 10;
            snapshot["slots"][0]["slotLease"] = "inv.test.13.10";
            snapshot["slots"][1] = new JObject
            {
                ["physicalSlot"] = 42,
                ["occupied"] = true,
                ["slotLease"] = "inv.test.13.42",
                ["item"] = ItemProjection(),
                ["confirmProjection"] = ConfirmProjection()
            };

            task.HandleFlashResponse(
                SnapshotResponse(ParseSent(sent), snapshot), _ => { });

            JObject response = JObject.Parse(posted);
            Assert.True(response.Value<bool>("success"));
            Assert.Equal(
                42,
                response["snapshots"][0]["slots"][1]
                    .Value<int>("physicalSlot"));
        }

        [Fact]
        public void LocalErrorEchoesPanelBindingForExactMuxRejection()
        {
            string posted = null;
            var task = new InventoryTask(() => true, _ => true);
            task.SetPostToWeb(json => posted = json);
            JObject request = Request("snapshot", "loot.inventory.invalid.1");
            request["panel"] = "loot";
            request["panelInstanceId"] = "panel.loot.exact.1";
            request["payload"]["v"] = 2;

            task.HandleWebRequest("snapshot", request);

            JObject response = JObject.Parse(posted);
            Assert.Equal("unsupported_version", (string)response["error"]);
            Assert.Equal("loot", (string)response["panel"]);
            Assert.Equal("panel.loot.exact.1", (string)response["panelInstanceId"]);
        }

        [Fact]
        public void TimeoutIsRoutableAndWriteIsNotReplayed()
        {
            int sends = 0;
            string posted = null;
            using var signaled = new ManualResetEventSlim(false);
            var task = new InventoryTask(() => true, _ => { sends++; return true; }, 20);
            task.SetPostToWeb(json => { posted = json; signaled.Set(); });
            JObject request = Request("discard", "wb.inventory.timeout.1");
            request["panel"] = "loot";
            request["panelInstanceId"] = "panel.loot.timeout.1";

            task.HandleWebRequest("discard", request);
            Assert.True(signaled.Wait(TimeSpan.FromSeconds(2)));
            task.HandleWebRequest("discard", request);

            JObject response = JObject.Parse(posted);
            Assert.Equal("timeout", (string)response["error"]);
            Assert.Equal("discard", (string)response["cmd"]);
            Assert.Equal("loot", (string)response["panel"]);
            Assert.Equal("panel.loot.timeout.1", (string)response["panelInstanceId"]);
            Assert.True(response.Value<bool>("requiresReconcile"));
            Assert.Equal("needs_reconcile", task.WriteState);
            Assert.Equal(1, sends);
        }

        [Fact]
        public void SendFailureEchoesExactPanelBinding()
        {
            string posted = null;
            var task = new InventoryTask(() => true, _ => false);
            task.SetPostToWeb(json => posted = json);
            JObject request = Request("snapshot", "loot.inventory.send-failure.1");
            request["panel"] = "loot";
            request["panelInstanceId"] = "panel.loot.send-failure.1";

            task.HandleWebRequest("snapshot", request);

            JObject response = JObject.Parse(posted);
            Assert.Equal("disconnected", (string)response["error"]);
            Assert.Equal("loot", (string)response["panel"]);
            Assert.Equal("panel.loot.send-failure.1", (string)response["panelInstanceId"]);
        }

        [Fact]
        public void SendThrowIsUnknownAndBlocksNextWrite()
        {
            var posted = new List<JObject>();
            var task = new InventoryTask(
                () => true,
                _ => throw new InvalidOperationException("transport failed"));
            task.SetPostToWeb(json => posted.Add(JObject.Parse(json)));

            Exception failure = Record.Exception(() => task.HandleWebRequest(
                "move", Request("move", "inventory.write.send-throw")));

            Assert.Null(failure);
            Assert.Equal("disconnected", posted[0].Value<string>("error"));
            Assert.True(posted[0].Value<bool>("requiresReconcile"));
            Assert.Equal("needs_reconcile", task.WriteState);

            task.HandleWebRequest(
                "swap", Request("swap", "inventory.write.after-send-throw"));
            Assert.Equal(
                "reconcile_required",
                posted[1].Value<string>("error"));
        }

        [Theory]
        [InlineData("discard", "背包")]
        [InlineData("move", "背包,仓库")]
        [InlineData("merge", "背包,仓库")]
        [InlineData("swap", "背包,仓库")]
        [InlineData("autoTransfer", "背包,仓库")]
        [InlineData("sortAndMerge", "仓库")]
        public void EveryMutationUsesThreeStateGateAndExactAffectedSet(
            string cmd,
            string affectedCsv)
        {
            var sent = new List<JObject>();
            var posted = new List<JObject>();
            var task = new InventoryTask(
                () => true,
                payload =>
                {
                    sent.Add(ParseSent(payload));
                    return true;
                });
            task.SetPostToWeb(json => posted.Add(JObject.Parse(json)));
            string suffix = cmd + "." + Guid.NewGuid().ToString("N");

            task.HandleWebRequest(
                cmd, Request(cmd, "inventory.matrix.start." + suffix));
            Assert.Equal("write_pending", task.WriteState);
            Assert.Single(sent);
            JObject oldWrite = sent[0];

            task.ClearPending();
            Assert.Equal("needs_reconcile", task.WriteState);
            task.HandleFlashResponse(new JObject
            {
                ["task"] = "inventory_response",
                ["callId"] = oldWrite.Value<int>("callId"),
                ["success"] = false,
                ["error"] = "stale_state"
            }, _ => { });
            Assert.Equal("needs_reconcile", task.WriteState);
            Assert.Single(sent);

            task.HandleWebRequest(
                cmd, Request(cmd, "inventory.matrix.blocked." + suffix));
            Assert.Equal(
                "reconcile_required",
                posted[posted.Count - 1].Value<string>("error"));
            Assert.Single(sent);

            string[] affected = affectedCsv.Split(',');
            var requests = new JArray();
            var snapshots = new List<JObject>();
            for (int i = 0; i < affected.Length; i++)
            {
                string containerId = affected[i];
                requests.Add(new JObject
                {
                    ["containerId"] = containerId,
                    ["offset"] = 0,
                    ["limit"] = 1,
                    ["filterKey"] = "all"
                });
                snapshots.Add(Snapshot(
                    containerId,
                    containerId == "仓库" ? 1200 : 50,
                    0,
                    1,
                    50 + i));
            }
            JObject reconcile = Request(
                "snapshot", "inventory.matrix.reconcile." + suffix);
            reconcile["payload"]["requests"] = requests;
            task.HandleWebRequest("snapshot", reconcile);
            Assert.Equal(2, sent.Count);
            task.HandleFlashResponse(
                SnapshotResponse(sent[1], snapshots.ToArray()), _ => { });
            Assert.Equal("idle", task.WriteState);

            task.HandleWebRequest(
                cmd, Request(cmd, "inventory.matrix.resumed." + suffix));
            Assert.Equal(3, sent.Count);
            Assert.Equal("write_pending", task.WriteState);
            task.Dispose();
        }

        [Fact]
        public void SendFailureWriteBlocksNextWriteUntilCoveredPostUnknownSnapshot()
        {
            bool sendSucceeds = false;
            var sent = new List<JObject>();
            var posted = new List<JObject>();
            var task = new InventoryTask(
                () => true,
                payload =>
                {
                    sent.Add(ParseSent(payload));
                    return sendSucceeds;
                });
            task.SetPostToWeb(json => posted.Add(JObject.Parse(json)));

            task.HandleWebRequest(
                "move", Request("move", "inventory.write.send-false"));

            Assert.Equal("needs_reconcile", task.WriteState);
            Assert.True(posted[0].Value<bool>("requiresReconcile"));
            task.HandleWebRequest(
                "swap", Request("swap", "inventory.write.blocked"));
            Assert.Equal("reconcile_required", posted[1].Value<string>("error"));
            Assert.Single(sent);

            sendSucceeds = true;
            JObject reconcile = Request(
                "snapshot", "inventory.reconcile.covered");
            reconcile["payload"]["requests"] = new JArray
            {
                new JObject
                {
                    ["containerId"] = "背包", ["offset"] = 0,
                    ["limit"] = 1, ["filterKey"] = "all"
                },
                new JObject
                {
                    ["containerId"] = "仓库", ["offset"] = 0,
                    ["limit"] = 1, ["filterKey"] = "all"
                }
            };
            task.HandleWebRequest("snapshot", reconcile);
            JObject reconcileFlash = sent[sent.Count - 1];
            task.HandleFlashResponse(
                SnapshotResponse(
                    reconcileFlash,
                    Snapshot("背包", 50, 0, 1, 21),
                    Snapshot("仓库", 1200, 0, 1, 22)),
                _ => { });

            Assert.Equal("idle", task.WriteState);
            task.HandleWebRequest(
                "swap", Request("swap", "inventory.write.after-reconcile"));
            Assert.Equal(3, sent.Count);
        }

        [Fact]
        public void PartialPostUnknownSnapshotCannotUnlockAffectedContainerSet()
        {
            bool sendSucceeds = false;
            var sent = new List<JObject>();
            var posted = new List<JObject>();
            var task = new InventoryTask(
                () => true,
                payload =>
                {
                    sent.Add(ParseSent(payload));
                    return sendSucceeds;
                });
            task.SetPostToWeb(json => posted.Add(JObject.Parse(json)));
            task.HandleWebRequest(
                "move", Request("move", "inventory.write.partial-origin"));
            sendSucceeds = true;

            JObject partial = Request(
                "snapshot", "inventory.reconcile.partial");
            partial["payload"]["requests"] = new JArray
            {
                new JObject
                {
                    ["containerId"] = "背包", ["offset"] = 0,
                    ["limit"] = 1, ["filterKey"] = "all"
                }
            };
            task.HandleWebRequest("snapshot", partial);
            task.HandleFlashResponse(
                SnapshotResponse(
                    sent[sent.Count - 1],
                    Snapshot("背包", 50, 0, 1, 23)),
                _ => { });

            Assert.Equal("needs_reconcile", task.WriteState);
            task.HandleWebRequest(
                "merge", Request("merge", "inventory.write.partial-blocked"));
            Assert.Equal(
                "reconcile_required",
                posted[posted.Count - 1].Value<string>("error"));
        }

        [Fact]
        public void SnapshotIssuedBeforeUnknownWaterlineCannotUnlockAfterMalformedWrite()
        {
            var sent = new List<JObject>();
            var task = new InventoryTask(
                () => true,
                payload => { sent.Add(ParseSent(payload)); return true; });
            task.HandleWebRequest(
                "move", Request("move", "inventory.write.malformed.waterline"));
            JObject earlyProbe = Request(
                "snapshot", "inventory.reconcile.too-early");
            earlyProbe["payload"]["requests"] = new JArray
            {
                new JObject
                {
                    ["containerId"] = "背包", ["offset"] = 0,
                    ["limit"] = 1, ["filterKey"] = "all"
                },
                new JObject
                {
                    ["containerId"] = "仓库", ["offset"] = 0,
                    ["limit"] = 1, ["filterKey"] = "all"
                }
            };
            task.HandleWebRequest("snapshot", earlyProbe);
            JObject earlyFlash = sent[1];

            task.HandleFlashResponse(new JObject
            {
                ["task"] = "inventory_response",
                ["callId"] = sent[0].Value<int>("callId"),
                ["success"] = true,
                ["operation"] = "move"
            }, _ => { });
            Assert.Equal("needs_reconcile", task.WriteState);
            task.HandleFlashResponse(
                SnapshotResponse(
                    earlyFlash,
                    Snapshot("背包", 50, 0, 1, 24),
                    Snapshot("仓库", 1200, 0, 1, 25)),
                _ => { });

            Assert.Equal("needs_reconcile", task.WriteState);
        }

        [Fact]
        public void MalformedWriteSuccessAndCommitFailedRemainUnknown()
        {
            Action<JObject>[] mutateResponses =
            {
                response => response["snapshots"][0]["slots"][0]
                    ["item"]["quantity"] = "1",
                response => response["operation"] = "swap",
                response =>
                {
                    response.Remove("v");
                    response.Remove("operation");
                    response.Remove("snapshots");
                    response["success"] = false;
                    response["error"] = "commit_failed";
                }
            };
            foreach (Action<JObject> mutate in mutateResponses)
            {
                string sent = null;
                string posted = null;
                var task = new InventoryTask(
                    () => true,
                    payload => { sent = payload; return true; });
                task.SetPostToWeb(json => posted = json);
                task.HandleWebRequest(
                    "move",
                    Request(
                        "move",
                        "inventory.write.unknown."
                            + Guid.NewGuid().ToString("N")));
                JObject flash = ParseSent(sent);
                JObject response = new JObject
                {
                    ["task"] = "inventory_response",
                    ["callId"] = flash.Value<int>("callId"),
                    ["success"] = true,
                    ["v"] = 1,
                    ["operation"] = "move",
                    ["snapshots"] = new JArray
                    {
                        Snapshot("背包", 50, 2, 1, 26),
                        Snapshot("仓库", 1200, 52, 1, 27)
                    }
                };
                mutate(response);

                task.HandleFlashResponse(response, _ => { });

                JObject web = JObject.Parse(posted);
                Assert.True(web.Value<bool>("requiresReconcile"));
                Assert.Equal("needs_reconcile", task.WriteState);
                task.Dispose();
            }
        }

        [Fact]
        public void ExactWriteSuccessAndDefinitiveFailureReturnGateToIdle()
        {
            Action<bool> exercise = successful =>
            {
                string sent = null;
                string posted = null;
                var task = new InventoryTask(
                    () => true,
                    payload => { sent = payload; return true; });
                task.SetPostToWeb(json => posted = json);
                task.HandleWebRequest(
                    "move",
                    Request(
                        "move",
                        "inventory.write.definitive."
                            + successful + "." + Guid.NewGuid().ToString("N")));
                JObject flash = ParseSent(sent);
                JObject response = successful
                    ? new JObject
                    {
                        ["task"] = "inventory_response",
                        ["callId"] = flash.Value<int>("callId"),
                        ["success"] = true,
                        ["v"] = 1,
                        ["operation"] = "move",
                        ["snapshots"] = new JArray
                        {
                            Snapshot("背包", 50, 2, 1, 28),
                            Snapshot("仓库", 1200, 52, 1, 29)
                        }
                    }
                    : new JObject
                    {
                        ["task"] = "inventory_response",
                        ["callId"] = flash.Value<int>("callId"),
                        ["success"] = false,
                        ["error"] = "stale_state"
                    };

                task.HandleFlashResponse(response, _ => { });

                JObject web = JObject.Parse(posted);
                Assert.Equal(successful, web.Value<bool>("success"));
                Assert.Null(web["requiresReconcile"]);
                Assert.Equal("idle", task.WriteState);
                task.Dispose();
            };

            exercise(true);
            exercise(false);
        }

        [Theory]
        [InlineData("autoTransfer")]
        [InlineData("sortAndMerge")]
        public void SpecializedWriteSuccessBindsFrozenSelector(string cmd)
        {
            foreach (bool selectorMatches in new[] { true, false })
            {
                string sent = null;
                string posted = null;
                var task = new InventoryTask(
                    () => true,
                    payload => { sent = payload; return true; });
                task.SetPostToWeb(json => posted = json);
                JObject request = Request(
                    cmd,
                    "inventory.write.selector." + cmd + "."
                        + selectorMatches);
                if (cmd == "autoTransfer")
                {
                    request["payload"]["windows"] = new JArray
                    {
                        new JObject
                        {
                            ["containerId"] = "背包", ["offset"] = 0,
                            ["limit"] = 1, ["filterKey"] = "all"
                        },
                        new JObject
                        {
                            ["containerId"] = "仓库", ["offset"] = 0,
                            ["limit"] = 1, ["filterKey"] = "all"
                        }
                    };
                }
                else
                {
                    request["payload"]["container"]["offset"] = 0;
                    request["payload"]["container"]["limit"] = 1;
                }
                task.HandleWebRequest(cmd, request);
                JObject flash = ParseSent(sent);
                JObject response = cmd == "autoTransfer"
                    ? new JObject
                    {
                        ["task"] = "inventory_response",
                        ["callId"] = flash.Value<int>("callId"),
                        ["success"] = true,
                        ["v"] = 1,
                        ["operation"] = "merge",
                        ["policy"] = "mergeThenEmpty",
                        ["destination"] = new JObject
                        {
                            ["containerId"] = selectorMatches ? "仓库" : "战备箱",
                            ["slot"] = 0
                        },
                        ["snapshots"] = new JArray
                        {
                            Snapshot("背包", 50, 0, 1, 32),
                            Snapshot("仓库", 1200, 0, 1, 33)
                        }
                    }
                    : new JObject
                    {
                        ["task"] = "inventory_response",
                        ["callId"] = flash.Value<int>("callId"),
                        ["success"] = true,
                        ["v"] = 1,
                        ["operation"] = "sortAndMerge",
                        ["methodName"] = selectorMatches ? "byType" : "byPrice",
                        ["sortedCapacity"] = 1200,
                        ["snapshots"] = new JArray
                        {
                            Snapshot("仓库", 1200, 0, 1, 34)
                        }
                    };

                task.HandleFlashResponse(response, _ => { });

                JObject web = JObject.Parse(posted);
                Assert.Equal(selectorMatches, web.Value<bool>("success"));
                Assert.Equal(
                    selectorMatches ? "idle" : "needs_reconcile",
                    task.WriteState);
                Assert.Equal(
                    !selectorMatches,
                    web.Value<bool?>("requiresReconcile") == true);
                task.Dispose();
            }
        }

        [Fact]
        public void ClearPendingPreservesUnknownWriteAndLateResponseCannotReviveIt()
        {
            var sent = new List<JObject>();
            var task = new InventoryTask(
                () => true,
                payload => { sent.Add(ParseSent(payload)); return true; });
            task.HandleWebRequest(
                "move", Request("move", "inventory.write.close"));
            JObject oldFlash = sent[0];

            task.ClearPending();
            task.HandleFlashResponse(new JObject
            {
                ["task"] = "inventory_response",
                ["callId"] = oldFlash.Value<int>("callId"),
                ["success"] = false,
                ["error"] = "stale_state"
            }, _ => { });

            Assert.Equal("needs_reconcile", task.WriteState);

            JObject reconcile = Request(
                "snapshot", "inventory.write.close.reconcile");
            reconcile["payload"]["requests"] = new JArray
            {
                new JObject
                {
                    ["containerId"] = "背包", ["offset"] = 0,
                    ["limit"] = 1, ["filterKey"] = "all"
                },
                new JObject
                {
                    ["containerId"] = "仓库", ["offset"] = 0,
                    ["limit"] = 1, ["filterKey"] = "all"
                }
            };
            task.HandleWebRequest("snapshot", reconcile);
            JObject reconcileFlash = sent[sent.Count - 1];
            task.HandleFlashResponse(
                SnapshotResponse(
                    reconcileFlash,
                    Snapshot("背包", 50, 0, 1, 35),
                    Snapshot("仓库", 1200, 0, 1, 36)),
                _ => { });

            Assert.Equal("idle", task.WriteState);
        }

        [Fact]
        public void ForeignAndDuplicateFlashResponsesCannotCompleteOrReviveWrite()
        {
            string sent = null;
            var posted = new List<JObject>();
            var task = new InventoryTask(
                () => true,
                payload => { sent = payload; return true; });
            task.SetPostToWeb(json => posted.Add(JObject.Parse(json)));
            task.HandleWebRequest(
                "move", Request("move", "inventory.write.response-identity"));
            JObject flash = ParseSent(sent);
            JObject success = new JObject
            {
                ["task"] = "inventory_response",
                ["callId"] = flash.Value<int>("callId"),
                ["success"] = true,
                ["v"] = 1,
                ["operation"] = "move",
                ["snapshots"] = new JArray
                {
                    Snapshot("背包", 50, 2, 1, 30),
                    Snapshot("仓库", 1200, 52, 1, 31)
                }
            };
            JObject foreign = (JObject)success.DeepClone();
            foreign["callId"] = flash.Value<int>("callId") + 999;
            JObject malformedForeign = (JObject)success.DeepClone();
            malformedForeign["callId"] = JToken.Parse(
                "999999999999999999999999999999");

            task.HandleFlashResponse(foreign, _ => { });
            Exception malformedFailure = Record.Exception(
                () => task.HandleFlashResponse(malformedForeign, _ => { }));

            Assert.Null(malformedFailure);
            Assert.Empty(posted);
            Assert.Equal("write_pending", task.WriteState);

            task.HandleFlashResponse(success, _ => { });
            Assert.Single(posted);
            Assert.True(posted[0].Value<bool>("success"));
            Assert.Equal("idle", task.WriteState);

            task.HandleFlashResponse(success, _ => { });
            Assert.Single(posted);
            Assert.Equal("idle", task.WriteState);
        }

        [Fact]
        public void DuplicateActiveAndRecentCallIdAreNeverForwardedTwice()
        {
            var sent = new List<string>();
            var task = new InventoryTask(() => true, payload => { sent.Add(payload); return true; });
            JObject request = Request("snapshot");
            task.HandleWebRequest("snapshot", request);
            task.HandleWebRequest("snapshot", request);
            Assert.Single(sent);

            JObject flashRequest = ParseSent(sent[0]);
            task.HandleFlashResponse(new JObject
            {
                ["task"] = "inventory_response",
                ["callId"] = (int)flashRequest["callId"],
                ["success"] = true,
                ["snapshots"] = new JArray()
            }, _ => { });
            task.HandleWebRequest("snapshot", request);
            Assert.Single(sent);
        }

        [Fact]
        public void DomainRoutingKeepsCloseFirstAndNeverFallsBackToLegacy()
        {
            Assert.Equal(WebOverlayForm.PanelDomainRoute.Inventory,
                WebOverlayForm.ResolvePanelDomainRoute("snapshot", "inventory"));
            Assert.Equal(WebOverlayForm.PanelDomainRoute.NpcShop,
                WebOverlayForm.ResolvePanelDomainRoute("snapshot", "npcshop"));
            Assert.Equal(WebOverlayForm.PanelDomainRoute.Close,
                WebOverlayForm.ResolvePanelDomainRoute("close", "inventory"));
            Assert.Equal(WebOverlayForm.PanelDomainRoute.Unsupported,
                WebOverlayForm.ResolvePanelDomainRoute("claim", "unknown"));
            Assert.Equal(WebOverlayForm.PanelDomainRoute.Legacy,
                WebOverlayForm.ResolvePanelDomainRoute("snapshot", null));
            Assert.Equal(WebOverlayForm.PanelDomainRoute.Unsupported,
                WebOverlayForm.ResolvePanelDomainRoute("snapshot", ""));

            var absent = new JObject();
            Assert.Equal(WebOverlayForm.PanelDomainRoute.Legacy,
                WebOverlayForm.ResolvePanelDomainRouteFromEnvelope("snapshot", absent));
            absent["domain"] = JValue.CreateNull();
            Assert.Equal(WebOverlayForm.PanelDomainRoute.Unsupported,
                WebOverlayForm.ResolvePanelDomainRouteFromEnvelope("snapshot", absent));
            absent["domain"] = new JObject();
            Assert.Equal(WebOverlayForm.PanelDomainRoute.Unsupported,
                WebOverlayForm.ResolvePanelDomainRouteFromEnvelope("snapshot", absent));
            absent["domain"] = "";
            Assert.Equal(WebOverlayForm.PanelDomainRoute.Unsupported,
                WebOverlayForm.ResolvePanelDomainRouteFromEnvelope("snapshot", absent));
            absent["domain"] = "inventory";
            Assert.Equal(WebOverlayForm.PanelDomainRoute.Inventory,
                WebOverlayForm.ResolvePanelDomainRouteFromEnvelope("snapshot", absent));
            absent["domain"] = new JObject();
            Assert.Equal(WebOverlayForm.PanelDomainRoute.Close,
                WebOverlayForm.ResolvePanelDomainRouteFromEnvelope("close", absent));
        }

        [Fact]
        public void Move_LogManagerCaptureNeverContainsRawAuthorityLeases()
        {
            const string sourceLease = "inventory.log.source.lease";
            const string targetLease = "inventory.log.target.lease";
            string sent = null;
            var logs = new List<string>();
            var task = new InventoryTask(
                () => true,
                payload =>
                {
                    sent = payload;
                    return false;
                });
            JObject request = Request(
                "move",
                "inventory.log.move");
            request["panelInstanceId"] = "panel.kshop.inventory.log";
            request["payload"]["source"]["expectedLease"] = sourceLease;
            request["payload"]["target"]["expectedLease"] = targetLease;

            LogManager.SetSink(logs.Add);
            try
            {
                task.HandleWebRequest("move", request);
            }
            finally
            {
                LogManager.ResetSink();
            }

            Assert.NotNull(sent);
            Assert.Contains(sourceLease, sent);
            Assert.Contains(targetLease, sent);
            JObject command = ParseSent(sent);
            string binding = Assert.Single(
                logs.FindAll(line => line.StartsWith(
                    "event=authority_flash_call_bound ",
                    StringComparison.Ordinal)));
            Assert.Equal(
                "event=authority_flash_call_bound domain=inventory"
                + " webCallId=inventory.log.move"
                + " flashCallId=" + (int)command["callId"]
                + " panel=kshop panelInstanceId=panel.kshop.inventory.log"
                + " cmd=move action=inventoryMove",
                binding);
            string flashLog = Assert.Single(
                logs.FindAll(line =>
                    line.Contains("[InventoryTask] -> Flash:")
                    && line.Contains("cmd=inventoryMove")));
            Assert.DoesNotContain(sourceLease, flashLog);
            Assert.DoesNotContain(targetLease, flashLog);
            Assert.Contains(
                AuthorityLogFormatter.CreateReference(sourceLease),
                flashLog);
            Assert.Contains(
                AuthorityLogFormatter.CreateReference(targetLease),
                flashLog);
            Assert.All(logs, line =>
            {
                Assert.DoesNotContain(sourceLease, line);
                Assert.DoesNotContain(targetLease, line);
            });
        }

        private static JObject CharacterTooltipSuccess(JObject flash)
        {
            return new JObject
            {
                ["task"] = "inventory_response",
                ["callId"] = flash.Value<int>("callId"),
                ["success"] = true,
                ["v"] = 1,
                ["itemName"] = "候选",
                ["displayname"] = "候选",
                ["iconName"] = "候选图标",
                ["itemType"] = "武器",
                ["descHTML"] = "候选说明",
                ["introHTML"] = "<b>候选</b>"
            };
        }

        [Fact]
        public void LootOrganizerInventoryEnvelopeRequiresExactTrackedPanelInstance()
        {
            var windows = new JArray
            {
                new JObject
                {
                    ["containerId"] = "背包", ["offset"] = 0,
                    ["limit"] = 50, ["filterKey"] = "all"
                },
                new JObject
                {
                    ["containerId"] = "战备箱", ["offset"] = 0,
                    ["limit"] = 40, ["filterKey"] = "all"
                }
            };
            var request = new JObject
            {
                ["type"] = "panel",
                ["domain"] = "inventory",
                ["panel"] = "loot",
                ["cmd"] = "snapshot",
                ["callId"] = "loot.inventory.snapshot.1",
                ["panelInstanceId"] = "panel.loot.exact.1",
                ["payload"] = new JObject
                {
                    ["v"] = 1,
                    ["requests"] = windows.DeepClone()
                }
            };

            Assert.True(WebOverlayForm.IsValidLootInventoryEnvelope(
                request, "loot", "panel.loot.exact.1"));
            Assert.False(WebOverlayForm.IsValidLootInventoryEnvelope(
                request, "loot", "panel.loot.replaced.2"));
            Assert.False(WebOverlayForm.IsValidLootInventoryEnvelope(
                request, "workbench", "panel.loot.exact.1"));

            request["panel"] = "workbench";
            Assert.False(WebOverlayForm.IsValidLootInventoryEnvelope(
                request, "loot", "panel.loot.exact.1"));
            request["panel"] = "loot";
            request["extra"] = true;
            Assert.False(WebOverlayForm.IsValidLootInventoryEnvelope(
                request, "loot", "panel.loot.exact.1"));
            request.Remove("extra");

            request["callId"] = 7;
            Assert.False(WebOverlayForm.IsValidLootInventoryEnvelope(
                request, "loot", "panel.loot.exact.1"));
            request["callId"] = "loot.inventory.snapshot.1";
            request["payload"]["v"] = JToken.Parse("999999999999999999999999999999");
            Assert.False(WebOverlayForm.IsValidLootInventoryEnvelope(
                request, "loot", "panel.loot.exact.1"));
            request["payload"]["v"] = 1;

            request["cmd"] = "autoTransfer";
            request["payload"] = new JObject
            {
                ["v"] = 1,
                ["source"] = new JObject
                {
                    ["containerId"] = "背包", ["slot"] = 7,
                    ["expectedLease"] = "inventory.lease.7"
                },
                ["targetContainerId"] = "战备箱",
                ["policy"] = "mergeThenEmpty",
                ["windows"] = windows.DeepClone()
            };
            Assert.True(WebOverlayForm.IsValidLootInventoryEnvelope(
                request, "loot", "panel.loot.exact.1"));
            request["payload"]["source"]["expectedLease"] = 7;
            Assert.False(WebOverlayForm.IsValidLootInventoryEnvelope(
                request, "loot", "panel.loot.exact.1"));
            request["payload"]["source"]["expectedLease"] = "inventory.lease.7";
            request["payload"]["source"]["slot"] = JToken.Parse(
                "999999999999999999999999999999");
            Assert.False(WebOverlayForm.IsValidLootInventoryEnvelope(
                request, "loot", "panel.loot.exact.1"));
            request["payload"]["source"]["slot"] = 7;
            request["payload"]["policy"] = true;
            Assert.False(WebOverlayForm.IsValidLootInventoryEnvelope(
                request, "loot", "panel.loot.exact.1"));
            request["payload"]["policy"] = "mergeThenEmpty";
            request["payload"]["targetContainerId"] = "仓库";
            Assert.False(WebOverlayForm.IsValidLootInventoryEnvelope(
                request, "loot", "panel.loot.exact.1"));

            request["cmd"] = "discard";
            request["payload"] = new JObject
            {
                ["v"] = 1,
                ["source"] = new JObject
                {
                    ["containerId"] = "背包", ["slot"] = 7,
                    ["expectedLease"] = "inventory.lease.7"
                }
            };
            Assert.True(WebOverlayForm.IsValidLootInventoryEnvelope(
                request, "loot", "panel.loot.exact.1"));
            request["payload"]["source"]["containerId"] = "战备箱";
            Assert.False(WebOverlayForm.IsValidLootInventoryEnvelope(
                request, "loot", "panel.loot.exact.1"));
        }
    }
}
