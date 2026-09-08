using System;
using System.Collections.Generic;
using System.Threading;
using CF7Launcher.Tasks;
using Newtonsoft.Json.Linq;
using Xunit;

namespace Launcher.Tests.Tasks
{
    public sealed class PlasticSurgeryTaskTests
    {
        private static JObject Profile() => new JObject { ["characterName"] = "新名字", ["gender"] = "female", ["height"] = 180 };
        private static JObject Request(string cmd, string id, string token = "surgery.1")
        {
            var payload = new JObject { ["v"] = 1 };
            if (cmd != "snapshot") payload["token"] = token;
            if (cmd == "commit") payload["draft"] = Profile();
            return new JObject { ["type"] = "panel", ["panel"] = "surgery", ["domain"] = "surgery", ["cmd"] = cmd,
                ["callId"] = id, ["panelInstanceId"] = "panel.1", ["payload"] = payload };
        }
        private static JObject Sent(string text) => JObject.Parse(text.TrimEnd('\0'));
        private static JObject Response(JObject sent, string phase = "applied")
        {
            var result = new JObject
            {
                ["task"] = "plastic_surgery_response", ["v"] = 1, ["callId"] = sent["callId"],
                ["operation"] = sent.Value<string>("action") == "plasticSurgerySnapshot" ? "snapshot"
                    : sent.Value<string>("action") == "plasticSurgeryQuery" ? "query" : "commit",
                ["token"] = sent["token"] ?? "surgery.1", ["phase"] = phase,
                ["success"] = phase != "save_pending", ["saved"] = phase == "applied", ["changed"] = phase != "editing",
                ["current"] = Profile(), ["draft"] = Profile(), ["cost"] = 5, ["balance"] = 15,
                ["portrait"] = new JObject { ["equipment"] = new JObject { ["上装装备"] = "短袖运动衫" }, ["hair"] = "光头", ["face"] = "女变装-基本脸型" }
            };
            if (phase == "save_pending") result["error"] = "save_pending";
            return result;
        }

        [Theory]
        [InlineData("snapshot", "plasticSurgerySnapshot")]
        [InlineData("query", "plasticSurgeryQuery")]
        [InlineData("commit", "plasticSurgeryCommit")]
        public void MapsFrozenCommands(string cmd, string action)
        {
            string sent = null;
            using var task = new PlasticSurgeryTask(() => true, text => { sent = text; return true; });
            task.HandleWebRequest(cmd, Request(cmd, "call.1"));
            var message = Sent(sent);
            Assert.Equal(action, message.Value<string>("action"));
            Assert.Null(message["payload"]);
            Assert.True(message.Value<int>("callId") > 0);
        }

        [Theory]
        [InlineData("name")]
        [InlineData("gender")]
        [InlineData("height")]
        [InlineData("cost")]
        [InlineData("extraDraft")]
        [InlineData("token")]
        [InlineData("version")]
        [InlineData("domain")]
        public void RejectsMalformedWritesBeforeDispatch(string defect)
        {
            int sends = 0;
            var posted = new List<JObject>();
            using var task = new PlasticSurgeryTask(() => true, _ => { sends++; return true; });
            task.SetPostToWeb(text => posted.Add(JObject.Parse(text)));
            var request = Request("commit", "call.1");
            switch (defect)
            {
                case "name": request["payload"]["draft"]["characterName"] = " "; break;
                case "gender": request["payload"]["draft"]["gender"] = "x"; break;
                case "height": request["payload"]["draft"]["height"] = 170.5; break;
                case "cost": request["payload"]["cost"] = 0; break;
                case "extraDraft": request["payload"]["draft"]["money"] = 9999; break;
                case "token": request["payload"]["token"] = "../token"; break;
                case "version": request["payload"]["v"] = 2; break;
                case "domain": request["domain"] = new JObject(); break;
            }
            task.HandleWebRequest("commit", request);
            Assert.Equal(0, sends);
            Assert.Single(posted);
            Assert.False(posted[0].Value<bool>("success"));
        }

        [Theory]
        [InlineData("foreignToken")]
        [InlineData("wrongDraft")]
        [InlineData("falseSaved")]
        [InlineData("price")]
        [InlineData("fractionalBalance")]
        [InlineData("unknownPhase")]
        public void MalformedSuccessRequiresExactQuery(string defect)
        {
            var sent = new List<JObject>(); var posted = new List<JObject>();
            using var task = new PlasticSurgeryTask(() => true, text => { sent.Add(Sent(text)); return true; });
            task.SetPostToWeb(text => posted.Add(JObject.Parse(text)));
            task.HandleWebRequest("commit", Request("commit", "write.1"));
            var response = Response(sent[0]);
            switch (defect)
            {
                case "foreignToken": response["token"] = "surgery.foreign"; break;
                case "wrongDraft": response["draft"]["height"] = 181; break;
                case "falseSaved": response["saved"] = false; break;
                case "price": response["cost"] = 0; break;
                case "fractionalBalance": response["balance"] = 15.5; break;
                case "unknownPhase": response["phase"] = "done"; break;
            }
            task.HandleFlashResponse(response, null);
            Assert.Equal("malformed_response", posted[0].Value<string>("error"));
            Assert.True(posted[0].Value<bool>("requiresReconcile"));
            task.HandleWebRequest("commit", Request("commit", "write.2", "surgery.other"));
            Assert.Single(sent);
            task.HandleWebRequest("commit", Request("commit", "write.3"));
            Assert.Single(sent);
            task.HandleWebRequest("query", Request("query", "read.1"));
            task.HandleFlashResponse(Response(sent[1]), null);
            Assert.True(posted[3].Value<bool>("saved"));
        }

        [Fact]
        public void PendingSaveAllowsOnlyOriginalDraftAndReadOnlyRecovery()
        {
            var sent = new List<JObject>(); var posted = new List<JObject>();
            using var task = new PlasticSurgeryTask(() => true, text => { sent.Add(Sent(text)); return true; });
            task.SetPostToWeb(text => posted.Add(JObject.Parse(text)));
            task.HandleWebRequest("commit", Request("commit", "write.1"));
            task.HandleFlashResponse(Response(sent[0], "save_pending"), null);
            var conflict = Request("commit", "write.2"); conflict["payload"]["draft"]["height"] = 181;
            task.HandleWebRequest("commit", conflict);
            Assert.Single(sent);
            task.ClearPending();
            task.HandleWebRequest("snapshot", Request("snapshot", "open.2"));
            Assert.Equal("reconcile_required", posted[2].Value<string>("error"));
            Assert.Equal("surgery.1", posted[2].Value<string>("token"));
            Assert.Single(sent);
            task.HandleWebRequest("query", Request("query", "query.2"));
            task.HandleFlashResponse(Response(sent[1], "save_pending"), null);
            task.HandleWebRequest("commit", Request("commit", "retry.1"));
            Assert.Equal("plasticSurgeryCommit", sent[2].Value<string>("action"));
            Assert.True(JToken.DeepEquals(sent[0]["draft"], sent[2]["draft"]));
            task.HandleFlashResponse(Response(sent[2]), null);
            Assert.True(posted[4].Value<bool>("saved"));
        }

        [Theory]
        [InlineData("false")]
        [InlineData("throw")]
        [InlineData("timeout")]
        [InlineData("clear")]
        public void LostWritesRetainTokenAcrossCloseAndDoNotAutoResubmit(string failure)
        {
            int sends = 0;
            var posted = new List<JObject>();
            using var task = new PlasticSurgeryTask(() => true, text =>
            {
                sends++;
                if (failure == "throw") throw new InvalidOperationException("transport");
                return failure != "false";
            }, 30);
            task.SetPostToWeb(text => { lock (posted) posted.Add(JObject.Parse(text)); });
            task.HandleWebRequest("commit", Request("commit", "write.1"));
            if (failure == "timeout") Assert.True(SpinWait.SpinUntil(() => { lock (posted) return posted.Count > 0; }, 1000));
            task.ClearPending();
            task.HandleWebRequest("snapshot", Request("snapshot", "reopen.1"));
            Assert.Equal(1, sends);
            lock (posted)
            {
                Assert.Equal("reconcile_required", posted[posted.Count - 1].Value<string>("error"));
                Assert.Equal("surgery.1", posted[posted.Count - 1].Value<string>("token"));
            }
        }

        [Fact]
        public void DuplicateAndLateResponsesCannotCompleteAnotherCall()
        {
            var sent = new List<JObject>(); var posted = new List<JObject>();
            using var task = new PlasticSurgeryTask(() => true, text => { sent.Add(Sent(text)); return true; });
            task.SetPostToWeb(text => posted.Add(JObject.Parse(text)));
            task.HandleWebRequest("commit", Request("commit", "write.1"));
            task.HandleWebRequest("commit", Request("commit", "write.1"));
            Assert.Single(sent);
            var response = Response(sent[0]);
            task.HandleFlashResponse(response, null); task.HandleFlashResponse(response, null);
            Assert.Single(posted);
            Assert.Equal("write.1", posted[0].Value<string>("callId"));
            Assert.Equal("panel.1", posted[0].Value<string>("panelInstanceId"));
            task.ClearPending();
            task.HandleFlashResponse(response, null);
            Assert.Single(posted);
        }
    }
}
