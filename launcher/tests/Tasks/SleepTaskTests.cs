using System;
using System.Collections.Generic;
using System.Threading;
using CF7Launcher.Tasks;
using Newtonsoft.Json.Linq;
using Xunit;

namespace Launcher.Tests.Tasks
{
    public sealed class SleepTaskTests
    {
        private static JObject Request(string cmd, string id = "call.1", int minute = 390, string token = "sleep.test.1")
        {
            var payload = new JObject { ["v"] = 1, ["token"] = token };
            if (cmd == "commit") payload["targetMinutes"] = minute;
            return new JObject { ["type"] = "panel", ["panel"] = "sleep", ["domain"] = "sleep", ["cmd"] = cmd,
                ["panelInstanceId"] = "sleep.panel.1", ["callId"] = id, ["payload"] = payload };
        }
        private static JObject Read(string text) => JObject.Parse(text.TrimEnd('\0'));
        private static JObject Response(JObject request, string phase = "applied", int minute = 390)
        {
            string action = request.Value<string>("action");
            return new JObject { ["task"] = "sleep_response", ["callId"] = request["callId"], ["v"] = 1,
                ["operation"] = action == "sleepSnapshot" ? "snapshot" : action == "sleepQuery" ? "query" : "commit",
                ["token"] = request["token"], ["phase"] = phase, ["success"] = phase != "expired", ["changed"] = phase == "applied",
                ["currentMinutes"] = minute, ["targetMinutes"] = minute, ["cycleEnabled"] = true, ["cyclePaused"] = false,
                ["canSleep"] = phase == "editing", ["reason"] = phase == "expired" ? "context_changed" : "" };
        }
        [Theory]
        [InlineData("snapshot", "sleepSnapshot")]
        [InlineData("commit", "sleepCommit")]
        [InlineData("query", "sleepQuery")]
        public void MapsOnlyFrozenCommands(string cmd, string action)
        {
            JObject sent = null;
            using var task = new SleepTask(() => true, value => { sent = Read(value); return true; });
            task.HandleWebRequest(cmd, Request(cmd));
            Assert.Equal(action, sent.Value<string>("action")); Assert.Null(sent["payload"]);
        }
        [Theory]
        [InlineData(-1)][InlineData(1440)][InlineData(int.MaxValue)]
        public void RejectsOutOfRangeBeforeDispatch(int value)
        {
            int sends = 0;
            using var task = new SleepTask(() => true, _ => { sends++; return true; });
            task.HandleWebRequest("commit", Request("commit", minute:value)); Assert.Equal(0, sends);
        }
        [Theory]
        [InlineData("string")][InlineData("fraction")][InlineData("extra")][InlineData("owner")][InlineData("domain")][InlineData("token")]
        public void RejectsMalformedInput(string defect)
        {
            int sends = 0;
            using var task = new SleepTask(() => true, _ => { sends++; return true; });
            var request = Request("commit");
            if (defect == "string") request["payload"]["targetMinutes"] = "390";
            if (defect == "fraction") request["payload"]["targetMinutes"] = 390.5;
            if (defect == "extra") request["payload"]["heal"] = true;
            if (defect == "owner") request["panelInstanceId"] = "";
            if (defect == "domain") request["domain"] = "surgery";
            if (defect == "token") request["payload"]["token"] = "other.1";
            task.HandleWebRequest("commit", request); Assert.Equal(0, sends);
        }
        [Fact]
        public void OpenRequiresExactBedSourceAndToken()
        {
            Assert.NotNull(SleepTask.BuildOpenData("world_sleep", "{\"token\":\"sleep.test.1\"}"));
            Assert.Null(SleepTask.BuildOpenData("as2_request", "{\"token\":\"sleep.test.1\"}"));
            Assert.Null(SleepTask.BuildOpenData("world_sleep", "{\"token\":\"sleep.test.1\",\"time\":6}"));
            Assert.Null(SleepTask.BuildOpenData("world_sleep", "garbage"));
        }
        [Fact]
        public void CompletedResponseUsesExactInstanceAndDeduplicates()
        {
            var sent = new List<JObject>(); var posted = new List<JObject>();
            using var task = new SleepTask(() => true, value => { sent.Add(Read(value)); return true; });
            task.SetPostToWeb(value => posted.Add(Read(value)));
            task.HandleWebRequest("commit", Request("commit")); task.HandleWebRequest("commit", Request("commit"));
            Assert.Single(sent);
            task.HandleFlashResponse(Response(sent[0]), _ => { }); task.HandleFlashResponse(Response(sent[0]), _ => { });
            Assert.Single(posted); Assert.Equal("sleep.panel.1", posted[0].Value<string>("panelInstanceId"));
            Assert.False(posted[0].Value<bool>("requiresReconcile"));
            task.HandleWebRequest("commit", Request("commit")); Assert.Single(sent);
        }
        [Fact]
        public void WrongSuccessCannotUnlockAndQueryMustProveOriginalTarget()
        {
            var sent = new List<JObject>(); var posted = new List<JObject>();
            using var task = new SleepTask(() => true, value => { sent.Add(Read(value)); return true; });
            task.SetPostToWeb(value => posted.Add(Read(value)));
            task.HandleWebRequest("commit", Request("commit")); task.HandleFlashResponse(Response(sent[0],minute:600), _ => { });
            Assert.True(posted[0].Value<bool>("requiresReconcile"));
            task.ClearPending(); task.HandleWebRequest("snapshot", Request("snapshot", "call.2", token:"sleep.test.2"));
            Assert.Single(sent); Assert.Equal("reconcile_required", posted[1].Value<string>("error"));
            task.HandleWebRequest("query", Request("query", "call.3")); task.HandleFlashResponse(Response(sent[1],minute:600), _ => { });
            Assert.True(posted[2].Value<bool>("requiresReconcile"));
            task.HandleWebRequest("query", Request("query", "call.4")); task.HandleFlashResponse(Response(sent[2]), _ => { });
            Assert.False(posted[3].Value<bool>("requiresReconcile"));
        }
        [Theory]
        [InlineData("editing")][InlineData("expired")]
        public void QueryCanProveNotApplied(string phase)
        {
            bool send = false; JObject last = null; var posted = new List<JObject>();
            using var task = new SleepTask(() => true, value => { last = Read(value); return send; });
            task.SetPostToWeb(value => posted.Add(Read(value)));
            task.HandleWebRequest("commit", Request("commit")); Assert.True(posted[0].Value<bool>("requiresReconcile"));
            send = true; task.HandleWebRequest("query", Request("query", "call.2")); task.HandleFlashResponse(Response(last,phase,360), _ => { });
            Assert.False(posted[1].Value<bool>("requiresReconcile"));
        }
        [Fact]
        public void DisconnectedDoesNotSendOrCreateUnknownWrite()
        {
            int sends = 0; JObject posted = null;
            using var task = new SleepTask(() => false, _ => { sends++; return true; });
            task.SetPostToWeb(value => posted = Read(value)); task.HandleWebRequest("commit", Request("commit"));
            Assert.Equal(0,sends); Assert.False(posted.Value<bool>("requiresReconcile"));
        }
        [Fact]
        public void TimeoutIsOneTerminalAndLateResponseCannotUnlock()
        {
            using var ended = new ManualResetEventSlim(); JObject sent = null; JObject result = null; int posts = 0;
            using var task = new SleepTask(() => true, value => { sent = Read(value); return true; }, 50);
            task.SetPostToWeb(value => { result = Read(value); Interlocked.Increment(ref posts); ended.Set(); });
            task.HandleWebRequest("commit", Request("commit")); Assert.True(ended.Wait(3000));
            Assert.True(result.Value<bool>("requiresReconcile")); task.HandleFlashResponse(Response(sent), _ => { }); Assert.Equal(1,posts);
        }
        [Fact]
        public void ClearRetainsUnknownAndDisposeNeverRevives()
        {
            JObject sent = null; var posted = new List<JObject>();
            var task = new SleepTask(() => true, value => { sent = Read(value); return true; });
            task.SetPostToWeb(value => posted.Add(Read(value))); task.HandleWebRequest("commit", Request("commit"));
            task.ClearPending(); task.HandleFlashResponse(Response(sent), _ => { }); Assert.Empty(posted);
            task.HandleWebRequest("commit", Request("commit","call.2")); Assert.Equal("reconcile_required",posted[0].Value<string>("error"));
            task.Dispose(); task.HandleWebRequest("snapshot",Request("snapshot","call.3")); Assert.Single(posted);
        }
    }
}
