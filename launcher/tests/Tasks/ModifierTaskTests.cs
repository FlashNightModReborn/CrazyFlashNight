using System;
using System.Collections.Generic;
using System.Threading;
using CF7Launcher.Tasks;
using Newtonsoft.Json.Linq;
using Xunit;

namespace Launcher.Tests.Tasks
{
    public sealed class ModifierTaskTests
    {
        private static JObject Request(string cmd, string id = "call.1", string operationId = "mod.test.1",
            string token = "modifier.test.1", long revision = 0)
        {
            var payload = new JObject { ["v"] = 1, ["token"] = token };
            if (cmd == "items" || cmd == "units")
            {
                payload["query"] = "";
                payload["page"] = 1;
            }
            if (cmd == "query") payload["operationId"] = operationId;
            if (cmd == "itemTooltip") payload["itemName"] = "普通hp药剂";
            if (cmd == "unitFrame") payload["spriteName"] = "敌人-金发女僵尸1";
            if (cmd == "grantMoney" || cmd == "grantKCoin" || cmd == "spawnItem" || cmd == "levelAction"
                || cmd == "grantTask" || cmd == "spawnUnit" || cmd == "spawnMerc")
            {
                payload["operationId"] = operationId;
                payload["expectedRevision"] = revision;
            }
            if (cmd == "spawnItem") { payload["itemName"] = "普通hp药剂"; payload["quantity"] = 1; }
            if (cmd == "levelAction") payload["levelAction"] = "kill_all";
            if (cmd == "grantTask") payload["taskId"] = 10;
            if (cmd == "spawnUnit") { payload["unitId"] = 1; payload["count"] = 1; payload["level"] = 2; payload["hostile"] = true; }
            if (cmd == "spawnMerc") { payload["unitId"] = 1; payload["level"] = 2; payload["hostile"] = false; }
            return new JObject
            {
                ["type"] = "panel",
                ["panel"] = "modifier",
                ["domain"] = "modifier",
                ["cmd"] = cmd,
                ["panelInstanceId"] = "modifier.panel.1",
                ["callId"] = id,
                ["payload"] = payload
            };
        }

        private static JObject Read(string text) => JObject.Parse(text.TrimEnd('\0'));

        private static string CmdForAction(string action)
        {
            switch (action)
            {
                case "modifierSnapshot": return "snapshot";
                case "modifierItems": return "items";
                case "modifierUnits": return "units";
                case "modifierItemTooltip": return "itemTooltip";
                case "modifierUnitFrame": return "unitFrame";
                case "modifierQuery": return "query";
                case "modifierGrantMoney": return "grantMoney";
                case "modifierGrantKCoin": return "grantKCoin";
                case "modifierSpawnItem": return "spawnItem";
                case "modifierLevelAction": return "levelAction";
                case "modifierGrantTask": return "grantTask";
                case "modifierSpawnUnit": return "spawnUnit";
                case "modifierSpawnMerc": return "spawnMerc";
                default: return action;
            }
        }

        private static JObject Response(JObject request, bool success = true, string error = null,
            bool requiresReconcile = false, int revision = 1)
        {
            string cmd = CmdForAction(request.Value<string>("action"));
            var response = new JObject
            {
                ["task"] = "modifier_response",
                ["callId"] = request["callId"],
                ["v"] = 1,
                ["operation"] = cmd,
                ["token"] = request["token"],
                ["success"] = success,
                ["revision"] = revision
            };
            if (cmd == "snapshot")
            {
                response["phase"] = "editing";
                response["state"] = new JObject
                {
                    ["money"] = 1000, ["kcoin"] = 2000, ["maxLevel"] = 60,
                    ["inWorld"] = true, ["stageActive"] = "Active",
                    ["challengeMode"] = false, ["saveAvailable"] = true
                };
                response["itemCount"] = 2; response["unitCount"] = 1;
                response["itemPageSize"] = 64; response["unitPageSize"] = 24;
            }
            else if (cmd == "items")
            {
                response["query"] = ""; response["page"] = 1; response["pageSize"] = 64;
                response["total"] = 1;
                response["items"] = new JArray(new JObject
                {
                    ["id"] = 1, ["name"] = "普通hp药剂", ["displayName"] = "普通HP药剂",
                    ["icon"] = "普通hp药剂", ["type"] = "消耗品", ["use"] = "药剂"
                });
            }
            else if (cmd == "units")
            {
                response["query"] = ""; response["page"] = 1; response["pageSize"] = 24;
                response["total"] = 1;
                response["units"] = new JArray(new JObject
                {
                    ["id"] = 1, ["name"] = "僵尸", ["spriteName"] = "敌人-金发女僵尸1",
                    ["key"] = "僵尸.金发女", ["level"] = 2, ["hostile"] = true
                });
            }
            else if (cmd == "itemTooltip")
            {
                response["itemName"] = "普通hp药剂";
                response["displayname"] = "普通HP药剂";
                response["introHTML"] = "<b>普通HP药剂</b>";
                response["descHTML"] = "<span>恢复生命</span>";
            }
            else if (cmd == "unitFrame")
            {
                response["spriteName"] = "敌人-金发女僵尸1";
                response["width"] = 1;
                response["height"] = 1;
                response["pixels"] = "AAAAAA==";
            }
            else
            {
                response["operationId"] = request["operationId"];
                if (cmd == "query") response["queriedOperation"] = request["operationId"];
                if (error != null) response["error"] = error;
                if (requiresReconcile) response["requiresReconcile"] = true;
            }
            return response;
        }

        [Theory]
        [InlineData("snapshot", "modifierSnapshot")]
        [InlineData("items", "modifierItems")]
        [InlineData("units", "modifierUnits")]
        [InlineData("itemTooltip", "modifierItemTooltip")]
        [InlineData("unitFrame", "modifierUnitFrame")]
        [InlineData("query", "modifierQuery")]
        [InlineData("grantMoney", "modifierGrantMoney")]
        [InlineData("grantKCoin", "modifierGrantKCoin")]
        [InlineData("spawnItem", "modifierSpawnItem")]
        [InlineData("levelAction", "modifierLevelAction")]
        [InlineData("grantTask", "modifierGrantTask")]
        [InlineData("spawnUnit", "modifierSpawnUnit")]
        [InlineData("spawnMerc", "modifierSpawnMerc")]
        public void MapsOnlyFrozenCommands(string cmd, string action)
        {
            JObject sent = null;
            using var task = new ModifierTask(() => true, value => { sent = Read(value); return true; });
            task.HandleWebRequest(cmd, Request(cmd));
            Assert.Equal(action, sent.Value<string>("action"));
            Assert.Equal("cmd", sent.Value<string>("task"));
        }

        [Fact]
        public void OpenRequiresExactSourceAndToken()
        {
            Assert.NotNull(ModifierTask.BuildOpenData("nativehud_modifier", "{\"token\":\"modifier.test.1\"}"));
            Assert.Null(ModifierTask.BuildOpenData("as2_request", "{\"token\":\"modifier.test.1\"}"));
            Assert.Null(ModifierTask.BuildOpenData("nativehud_modifier", "{\"token\":\"modifier.test.1\",\"extra\":1}"));
            Assert.Null(ModifierTask.BuildOpenData("nativehud_modifier", "{\"token\":\"wrong.1\"}"));
            Assert.Null(ModifierTask.BuildOpenData("nativehud_modifier", "garbage"));
        }

        [Theory]
        [InlineData("domain")]
        [InlineData("panel")]
        [InlineData("owner")]
        [InlineData("version")]
        [InlineData("operation")]
        [InlineData("revision")]
        [InlineData("extra")]
        [InlineData("levelAction")]
        public void RejectsMalformedInputBeforeDispatch(string defect)
        {
            int sends = 0;
            using var task = new ModifierTask(() => true, _ => { sends++; return true; });
            var request = Request("levelAction");
            if (defect == "domain") request["domain"] = "inventory";
            if (defect == "panel") request["panel"] = "settings";
            if (defect == "owner") request["panelInstanceId"] = "";
            if (defect == "version") request["payload"]["v"] = 2;
            if (defect == "operation") request["payload"]["operationId"] = "modifier.op.1";
            if (defect == "revision") request["payload"]["expectedRevision"] = -1;
            if (defect == "extra") request["payload"]["extra"] = true;
            if (defect == "levelAction") request["payload"]["levelAction"] = "rm_rf";
            task.HandleWebRequest("levelAction", request);
            Assert.Equal(0, sends);
        }

        [Fact]
        public void UnitFrameAndItemTooltipResponsesAreRebuiltForThePanel()
        {
            var sent = new List<JObject>(); var posted = new List<JObject>();
            using var task = new ModifierTask(() => true, value => { sent.Add(Read(value)); return true; });
            task.SetPostToWeb(value => posted.Add(Read(value)));
            task.HandleWebRequest("unitFrame", Request("unitFrame", "call.unit"));
            task.HandleWebRequest("itemTooltip", Request("itemTooltip", "call.tooltip"));
            task.HandleFlashResponse(Response(sent[0]), _ => { });
            task.HandleFlashResponse(Response(sent[1]), _ => { });
            Assert.Equal(2, posted.Count);
            Assert.True(posted[0].Value<bool>("success"));
            Assert.Equal("unitFrame", posted[0].Value<string>("cmd"));
            Assert.Equal("AAAAAA==", posted[0].Value<string>("pixels"));
            Assert.True(posted[1].Value<bool>("success"));
            Assert.Equal("itemTooltip", posted[1].Value<string>("cmd"));
            Assert.Equal("<b>普通HP药剂</b>", posted[1].Value<string>("introHTML"));
        }

        [Fact]
        public void SnapshotResponseIsRebuiltToExactWebEnvelope()
        {
            var sent = new List<JObject>(); var posted = new List<JObject>();
            using var task = new ModifierTask(() => true, value => { sent.Add(Read(value)); return true; });
            task.SetPostToWeb(value => posted.Add(Read(value)));
            task.HandleWebRequest("snapshot", Request("snapshot"));
            task.HandleFlashResponse(Response(sent[0]), _ => { });
            Assert.Single(posted);
            Assert.Equal("panel_resp", posted[0].Value<string>("type"));
            Assert.Equal("modifier", posted[0].Value<string>("panel"));
            Assert.Equal("modifier", posted[0].Value<string>("domain"));
            Assert.Equal("snapshot", posted[0].Value<string>("cmd"));
            Assert.Equal("call.1", posted[0].Value<string>("callId"));
            Assert.Equal("modifier.panel.1", posted[0].Value<string>("panelInstanceId"));
            Assert.False(posted[0].Value<bool>("requiresReconcile"));
        }

        [Fact]
        public void WriteSuccessClearsWatermarkAndDeduplicates()
        {
            var sent = new List<JObject>(); var posted = new List<JObject>();
            using var task = new ModifierTask(() => true, value => { sent.Add(Read(value)); return true; });
            task.SetPostToWeb(value => posted.Add(Read(value)));
            task.HandleWebRequest("grantMoney", Request("grantMoney"));
            task.HandleWebRequest("grantMoney", Request("grantMoney"));
            Assert.Single(sent);
            task.HandleFlashResponse(Response(sent[0]), _ => { });
            task.HandleFlashResponse(Response(sent[0]), _ => { });
            Assert.Single(posted);
            Assert.True(posted[0].Value<bool>("success"));
            Assert.False(posted[0].Value<bool>("requiresReconcile"));
            task.HandleWebRequest("grantMoney", Request("grantMoney", "call.2", "mod.test.2", revision: 1));
            Assert.Equal(2, sent.Count);
        }

        [Fact]
        public void AmbiguousWriteKeepsReconcileUntilQueryProvesNotApplied()
        {
            var sent = new List<JObject>(); var posted = new List<JObject>();
            using var task = new ModifierTask(() => true, value => { sent.Add(Read(value)); return true; });
            task.SetPostToWeb(value => posted.Add(Read(value)));
            task.HandleWebRequest("spawnItem", Request("spawnItem"));
            task.HandleFlashResponse(Response(sent[0], false, "apply_ambiguous", true, 0), _ => { });
            Assert.True(posted[0].Value<bool>("requiresReconcile"));
            task.HandleWebRequest("spawnItem", Request("spawnItem", "call.2", "mod.test.2"));
            Assert.Single(sent);
            Assert.Equal("reconcile_required", posted[1].Value<string>("error"));
            task.HandleWebRequest("query", Request("query", "call.3", "mod.test.1"));
            task.HandleFlashResponse(Response(sent[1], false, "not_applied", false, 0), _ => { });
            Assert.False(posted[2].Value<bool>("requiresReconcile"));
            task.HandleWebRequest("spawnItem", Request("spawnItem", "call.4", "mod.test.3"));
            Assert.Equal(3, sent.Count);
        }

        [Fact]
        public void QuerySuccessClearsTheUnknownWrite()
        {
            var sent = new List<JObject>(); var posted = new List<JObject>();
            using var task = new ModifierTask(() => true, value => { sent.Add(Read(value)); return true; });
            task.SetPostToWeb(value => posted.Add(Read(value)));
            task.HandleWebRequest("spawnUnit", Request("spawnUnit"));
            task.HandleFlashResponse(Response(sent[0], false, "apply_ambiguous", true, 0), _ => { });
            Assert.True(posted[0].Value<bool>("requiresReconcile"));
            task.HandleWebRequest("query", Request("query", "call.2", "mod.test.1"));
            task.HandleFlashResponse(Response(sent[1], true, null, false, 1), _ => { });
            Assert.False(posted[1].Value<bool>("requiresReconcile"));
            task.HandleWebRequest("spawnUnit", Request("spawnUnit", "call.3", "mod.test.2", revision:1));
            Assert.Equal(3, sent.Count);
        }

        [Fact]
        public void TimeoutIsOneTerminalAndLateResponseCannotUnlock()
        {
            using var ended = new ManualResetEventSlim();
            JObject sent = null, result = null;
            int posts = 0;
            using var task = new ModifierTask(() => true, value => { sent = Read(value); return true; }, 50);
            task.SetPostToWeb(value => { result = Read(value); Interlocked.Increment(ref posts); ended.Set(); });
            task.HandleWebRequest("grantKCoin", Request("grantKCoin"));
            Assert.True(ended.Wait(3000));
            Assert.True(result.Value<bool>("requiresReconcile"));
            task.HandleFlashResponse(Response(sent), _ => { });
            Assert.Equal(1, posts);
        }

        [Fact]
        public void ClearRetainsUnknownAndDisposeNeverRevives()
        {
            JObject sent = null; var posted = new List<JObject>();
            var task = new ModifierTask(() => true, value => { sent = Read(value); return true; });
            task.SetPostToWeb(value => posted.Add(Read(value)));
            task.HandleWebRequest("grantMoney", Request("grantMoney"));
            task.ClearPending();
            task.HandleFlashResponse(Response(sent), _ => { });
            Assert.Empty(posted);
            task.HandleWebRequest("grantMoney", Request("grantMoney", "call.2", "mod.test.2"));
            Assert.Equal("reconcile_required", posted[0].Value<string>("error"));
            task.Dispose();
            task.HandleWebRequest("snapshot", Request("snapshot", "call.3"));
            Assert.Single(posted);
        }

        [Fact]
        public void DisconnectedDoesNotSendOrCreateUnknownWrite()
        {
            int sends = 0; JObject posted = null;
            using var task = new ModifierTask(() => false, _ => { sends++; return true; });
            task.SetPostToWeb(value => posted = Read(value));
            task.HandleWebRequest("grantMoney", Request("grantMoney"));
            Assert.Equal(0, sends);
            Assert.False(posted.Value<bool>("requiresReconcile"));
            Assert.False(task.HasUnresolvedWrite);
        }
    }
}
