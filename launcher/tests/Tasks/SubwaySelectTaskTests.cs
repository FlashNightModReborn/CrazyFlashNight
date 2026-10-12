using System;
using System.Collections.Generic;
using CF7Launcher.Tasks;
using Newtonsoft.Json.Linq;
using Xunit;

namespace Launcher.Tests.Tasks
{
    public sealed class SubwaySelectTaskTests
    {
        private static JObject Request(string cmd, string id = "call.1", string entryId = "explore_stationD")
        {
            var payload = new JObject { ["v"] = 1 };
            if (cmd == "enter") payload["entryId"] = entryId;
            return new JObject { ["type"] = "panel", ["panel"] = "subway", ["domain"] = "subway", ["cmd"] = cmd,
                ["panelInstanceId"] = "subway.panel.1", ["callId"] = id, ["payload"] = payload };
        }
        private static JObject Read(string text) => JObject.Parse(text.TrimEnd('\0'));
        private static JObject SnapshotResponse(JObject request)
        {
            return new JObject
            {
                ["task"] = "subway_select_response", ["callId"] = request["callId"], ["v"] = 1,
                ["operation"] = "snapshot", ["success"] = true,
                ["progress"] = new JObject { ["main"] = 50, ["egg"] = 4 },
                ["stations"] = new JArray(
                    new JObject { ["id"] = "总备处站", ["name"] = "总备处站", ["frame"] = 4 },
                    new JObject { ["id"] = "新市场站", ["name"] = "新市场站", ["frame"] = 3 },
                    new JObject { ["id"] = "自由广场站", ["name"] = "自由广场站", ["frame"] = 2 },
                    new JObject { ["id"] = "环线东北站", ["name"] = "环线东北站", ["frame"] = 3 }),
                ["entries"] = new JArray(
                    new JObject { ["id"] = "clean_stationA", ["name"] = "清理总备处",
                        ["description"] = "清理总备处站，尝试搜寻神秘士兵的据点。", ["stageName"] = "总备处站清理",
                        ["difficulty"] = "简单", ["enterable"] = true, ["highlighted"] = true },
                    new JObject { ["id"] = "explore_stationD", ["name"] = "环线东北站探索",
                        ["description"] = "探索环线东北站", ["stageName"] = "环线东北站",
                        ["difficulty"] = "简单", ["enterable"] = true, ["highlighted"] = true })
            };
        }
        private static JObject EnterResponse(JObject request, bool success = true, string error = null)
        {
            var response = new JObject
            {
                ["task"] = "subway_select_response", ["callId"] = request["callId"], ["v"] = 1,
                ["operation"] = "enter", ["success"] = success
            };
            if (success)
            {
                response["closePanel"] = true;
                response["entryId"] = "explore_stationD";
                response["stageName"] = "环线东北站";
                response["difficulty"] = "简单";
            }
            else response["error"] = error ?? "locked";
            return response;
        }

        [Theory]
        [InlineData("snapshot", "subwaySelectSnapshot")]
        [InlineData("enter", "subwaySelectEnter")]
        public void MapsOnlyFrozenCommands(string cmd, string action)
        {
            JObject sent = null;
            using var task = new SubwaySelectTask(() => true, value => { sent = Read(value); return true; });
            task.HandleWebRequest(cmd, Request(cmd));
            Assert.Equal(action, sent.Value<string>("action"));
            Assert.Equal(cmd == "enter" ? "explore_stationD" : null, sent.Value<string>("entryId"));
        }
        [Theory]
        [InlineData("domain")][InlineData("extra")][InlineData("entry")][InlineData("version")]
        public void RejectsMalformedInput(string defect)
        {
            int sends = 0;
            using var task = new SubwaySelectTask(() => true, _ => { sends++; return true; });
            var request = Request("enter");
            if (defect == "domain") request["domain"] = "egg_stage_select";
            if (defect == "extra") request["payload"]["debug"] = true;
            if (defect == "entry") request["payload"]["entryId"] = "fly_stationX";
            if (defect == "version") request["payload"]["v"] = 2;
            task.HandleWebRequest("enter", request);
            Assert.Equal(0, sends);
        }
        [Fact]
        public void UnsupportedCmdIsRejected()
        {
            int sends = 0; JObject posted = null;
            using var task = new SubwaySelectTask(() => true, _ => { sends++; return true; });
            task.SetPostToWeb(value => posted = Read(value));
            task.HandleWebRequest("peek", Request("enter"));
            Assert.Equal(0, sends);
            Assert.Equal("unsupported_cmd", posted.Value<string>("error"));
        }
        [Fact]
        public void CompletedResponseRestoresWebCallIdAndInstance()
        {
            var sent = new List<JObject>(); var posted = new List<JObject>();
            using var task = new SubwaySelectTask(() => true, value => { sent.Add(Read(value)); return true; });
            task.SetPostToWeb(value => posted.Add(Read(value)));
            task.HandleWebRequest("snapshot", Request("snapshot"));
            task.HandleFlashResponse(SnapshotResponse(sent[0]), _ => { });
            Assert.Single(posted);
            Assert.Equal("call.1", posted[0].Value<string>("callId"));
            Assert.Equal("subway.panel.1", posted[0].Value<string>("panelInstanceId"));
            Assert.Equal("panel_resp", posted[0].Value<string>("type"));
            Assert.Equal(2, posted[0]["entries"].ToObject<JArray>().Count);
            Assert.Null(posted[0]["task"]);
        }
        [Fact]
        public void DuplicateAndLateResponsesAreDropped()
        {
            var sent = new List<JObject>(); var posted = new List<JObject>();
            using var task = new SubwaySelectTask(() => true, value => { sent.Add(Read(value)); return true; });
            task.SetPostToWeb(value => posted.Add(Read(value)));
            task.HandleWebRequest("enter", Request("enter")); task.HandleWebRequest("enter", Request("enter"));
            Assert.Single(sent);
            task.HandleFlashResponse(EnterResponse(sent[0]), _ => { });
            task.HandleFlashResponse(EnterResponse(sent[0]), _ => { });
            Assert.Single(posted);
            Assert.True(posted[0].Value<bool>("closePanel"));
        }
        [Fact]
        public void MalformedSuccessIsNormalized()
        {
            var sent = new List<JObject>(); var posted = new List<JObject>();
            using var task = new SubwaySelectTask(() => true, value => { sent.Add(Read(value)); return true; });
            task.SetPostToWeb(value => posted.Add(Read(value)));
            task.HandleWebRequest("enter", Request("enter"));
            var broken = EnterResponse(sent[0]);
            broken["stageName"] = "";
            task.HandleFlashResponse(broken, _ => { });
            Assert.False(posted[0].Value<bool>("success"));
            Assert.Equal("malformed_response", posted[0].Value<string>("error"));
        }
        [Fact]
        public void DefinitiveRejectionPassesThrough()
        {
            var sent = new List<JObject>(); var posted = new List<JObject>();
            using var task = new SubwaySelectTask(() => true, value => { sent.Add(Read(value)); return true; });
            task.SetPostToWeb(value => posted.Add(Read(value)));
            task.HandleWebRequest("enter", Request("enter"));
            task.HandleFlashResponse(EnterResponse(sent[0], success: false, error: "pending_stage_settlement"), _ => { });
            Assert.False(posted[0].Value<bool>("success"));
            Assert.Equal("pending_stage_settlement", posted[0].Value<string>("error"));
        }
        [Fact]
        public void EnterSingleFlightAndTimeoutUnlock()
        {
            var sent = new List<JObject>(); var posted = new List<JObject>();
            using var task = new SubwaySelectTask(() => true, value => { sent.Add(Read(value)); return true; }, timeoutMs: 50);
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
            using var task = new SubwaySelectTask(() => false, _ => { sends++; return true; });
            task.SetPostToWeb(value => posted = Read(value));
            task.HandleWebRequest("enter", Request("enter"));
            Assert.Equal(0, sends);
            Assert.Equal("disconnected", posted.Value<string>("error"));
        }
    }
}
