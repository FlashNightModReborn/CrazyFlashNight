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
