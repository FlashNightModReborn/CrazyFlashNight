using System;
using System.Collections.Generic;
using CF7Launcher.Tasks;
using Newtonsoft.Json.Linq;
using Xunit;

namespace Launcher.Tests.Tasks
{
    public sealed class EggStageSelectTaskTests
    {
        private static JObject Request(string cmd, string id = "call.1", string destinationId = "forest_depth")
        {
            var payload = new JObject { ["v"] = 1 };
            if (cmd == "enter") payload["destinationId"] = destinationId;
            return new JObject { ["type"] = "panel", ["panel"] = "egg-stage-select", ["domain"] = "egg_stage_select",
                ["cmd"] = cmd, ["panelInstanceId"] = "egg.panel.1", ["callId"] = id, ["payload"] = payload };
        }
        private static JObject Read(string text) => JObject.Parse(text.TrimEnd('\0'));
        private static JObject SnapshotResponse(JObject request)
        {
            return new JObject
            {
                ["task"] = "egg_select_response", ["callId"] = request["callId"], ["v"] = 1,
                ["operation"] = "snapshot", ["success"] = true,
                ["progress"] = new JObject { ["main"] = 67, ["egg"] = 11 },
                ["destinations"] = new JArray(
                    new JObject { ["id"] = "forest_depth", ["name"] = "密林深处", ["stageName"] = "密林深处",
                        ["difficulty"] = "简单", ["unlocked"] = true, ["hintLocked"] = false, ["lockReason"] = "" },
                    new JObject { ["id"] = "machine_zone", ["name"] = "机器游荡区", ["stageName"] = "机器游荡区",
                        ["difficulty"] = "简单", ["unlocked"] = true, ["hintLocked"] = false, ["lockReason"] = "" },
                    new JObject { ["id"] = "forest_center", ["name"] = "密林中央", ["stageName"] = "密林中央",
                        ["difficulty"] = "冒险", ["unlocked"] = true, ["hintLocked"] = false, ["lockReason"] = "" })
            };
        }
        private static JObject EnterResponse(JObject request, bool success = true, string error = null)
        {
            var response = new JObject
            {
                ["task"] = "egg_select_response", ["callId"] = request["callId"], ["v"] = 1,
                ["operation"] = "enter", ["success"] = success
            };
            if (success)
            {
                response["closePanel"] = true;
                response["destinationId"] = "forest_center";
                response["stageName"] = "密林中央";
                response["difficulty"] = "冒险";
            }
            else response["error"] = error ?? "locked";
            return response;
        }

        [Theory]
        [InlineData("snapshot", "eggSelectSnapshot")]
        [InlineData("enter", "eggSelectEnter")]
        public void MapsOnlyFrozenCommands(string cmd, string action)
        {
            JObject sent = null;
            using var task = new EggStageSelectTask(() => true, value => { sent = Read(value); return true; });
            task.HandleWebRequest(cmd, Request(cmd, destinationId: "forest_center"));
            Assert.Equal(action, sent.Value<string>("action"));
            Assert.Equal(cmd == "enter" ? "forest_center" : null, sent.Value<string>("destinationId"));
        }
        [Theory]
        [InlineData("domain")][InlineData("extra")][InlineData("destination")][InlineData("version")]
        public void RejectsMalformedInput(string defect)
        {
            int sends = 0;
            using var task = new EggStageSelectTask(() => true, _ => { sends++; return true; });
            var request = Request("enter");
            if (defect == "domain") request["domain"] = "subway";
            if (defect == "extra") request["payload"]["debug"] = true;
            if (defect == "destination") request["payload"]["destinationId"] = "candy_land";
            if (defect == "version") request["payload"]["v"] = 2;
            task.HandleWebRequest("enter", request);
            Assert.Equal(0, sends);
        }
        [Fact]
        public void CompletedResponseRestoresWebCallIdAndInstance()
        {
            var sent = new List<JObject>(); var posted = new List<JObject>();
            using var task = new EggStageSelectTask(() => true, value => { sent.Add(Read(value)); return true; });
            task.SetPostToWeb(value => posted.Add(Read(value)));
            task.HandleWebRequest("snapshot", Request("snapshot"));
            task.HandleFlashResponse(SnapshotResponse(sent[0]), _ => { });
            Assert.Single(posted);
            Assert.Equal("call.1", posted[0].Value<string>("callId"));
            Assert.Equal("egg.panel.1", posted[0].Value<string>("panelInstanceId"));
            Assert.Equal(3, posted[0]["destinations"].ToObject<JArray>().Count);
        }
        [Fact]
        public void EnterSuccessCarriesFixedDifficultyAndClosePanel()
        {
            var sent = new List<JObject>(); var posted = new List<JObject>();
            using var task = new EggStageSelectTask(() => true, value => { sent.Add(Read(value)); return true; });
            task.SetPostToWeb(value => posted.Add(Read(value)));
            task.HandleWebRequest("enter", Request("enter", destinationId: "forest_center"));
            task.HandleFlashResponse(EnterResponse(sent[0]), _ => { });
            Assert.True(posted[0].Value<bool>("success"));
            Assert.True(posted[0].Value<bool>("closePanel"));
            Assert.Equal("冒险", posted[0].Value<string>("difficulty"));
        }
        [Fact]
        public void MalformedSuccessIsNormalized()
        {
            var sent = new List<JObject>(); var posted = new List<JObject>();
            using var task = new EggStageSelectTask(() => true, value => { sent.Add(Read(value)); return true; });
            task.SetPostToWeb(value => posted.Add(Read(value)));
            task.HandleWebRequest("enter", Request("enter"));
            var broken = EnterResponse(sent[0]);
            broken["difficulty"] = "无尽";
            task.HandleFlashResponse(broken, _ => { });
            Assert.False(posted[0].Value<bool>("success"));
            Assert.Equal("malformed_response", posted[0].Value<string>("error"));
        }
        [Fact]
        public void DefinitiveLockedPassesThrough()
        {
            var sent = new List<JObject>(); var posted = new List<JObject>();
            using var task = new EggStageSelectTask(() => true, value => { sent.Add(Read(value)); return true; });
            task.SetPostToWeb(value => posted.Add(Read(value)));
            task.HandleWebRequest("enter", Request("enter"));
            task.HandleFlashResponse(EnterResponse(sent[0], success: false, error: "locked"), _ => { });
            Assert.False(posted[0].Value<bool>("success"));
            Assert.Equal("locked", posted[0].Value<string>("error"));
        }
        [Fact]
        public void EnterSingleFlightAndTimeoutUnlock()
        {
            var sent = new List<JObject>(); var posted = new List<JObject>();
            using var task = new EggStageSelectTask(() => true, value => { sent.Add(Read(value)); return true; }, timeoutMs: 50);
            task.SetPostToWeb(value => posted.Add(Read(value)));
            task.HandleWebRequest("enter", Request("enter"));
            task.HandleWebRequest("enter", Request("enter", id: "call.2"));
            Assert.Single(sent);
            Assert.Equal("busy", posted[0].Value<string>("error"));
            var deadline = DateTime.UtcNow.AddSeconds(5);
            while (posted.Count < 2 && DateTime.UtcNow < deadline) System.Threading.Thread.Sleep(10);
            Assert.Equal(2, posted.Count);
            Assert.Equal("timeout", posted[1].Value<string>("error"));
            Assert.True(posted[1].Value<bool>("enterUnknown"));
            task.HandleWebRequest("enter", Request("enter", id: "call.3"));
            Assert.Equal(2, sent.Count);
        }
        [Fact]
        public void DisconnectedDoesNotSend()
        {
            int sends = 0; JObject posted = null;
            using var task = new EggStageSelectTask(() => false, _ => { sends++; return true; });
            task.SetPostToWeb(value => posted = Read(value));
            task.HandleWebRequest("enter", Request("enter"));
            Assert.Equal(0, sends);
            Assert.Equal("disconnected", posted.Value<string>("error"));
        }
    }
}
