using System;
using Newtonsoft.Json.Linq;
using Xunit;
using CF7Launcher.Tasks;

namespace CF7Launcher.Tests.Tasks
{
    public class StageSelectTaskTests
    {
        [Fact]
        public void HandleWebRequest_Disconnected_ReturnsPanelError()
        {
            string posted = null;
            var task = new StageSelectTask(delegate { return false; }, delegate(string payload) { });
            task.SetPostToWeb(delegate(string json) { posted = json; });

            task.HandleWebRequest("snapshot", JObject.Parse("{\"callId\":\"web-1\"}"));

            var resp = JObject.Parse(posted);
            Assert.Equal("panel_resp", (string)resp["type"]);
            Assert.Equal("stage-select", (string)resp["panel"]);
            Assert.Equal("snapshot", (string)resp["cmd"]);
            Assert.Equal("web-1", (string)resp["callId"]);
            Assert.False((bool)resp["success"]);
            Assert.Equal("disconnected", (string)resp["error"]);
        }

        [Fact]
        public void HandleWebRequest_Snapshot_SendsStageSelectSnapshotAction()
        {
            string sent = null;
            var task = new StageSelectTask(delegate { return true; }, delegate(string payload) { sent = payload; });

            task.HandleWebRequest("snapshot", JObject.Parse("{\"callId\":\"web-2\",\"stageNames\":[\"新手练习场\",\"超市废墟\"]}"));

            Assert.EndsWith("\0", sent);
            var msg = JObject.Parse(sent.TrimEnd('\0'));
            Assert.Equal("cmd", (string)msg["task"]);
            Assert.Equal("stageSelectSnapshot", (string)msg["action"]);
            Assert.Equal(1, (int)msg["callId"]);
            Assert.Equal("新手练习场", (string)msg["stageNames"][0]);
        }

        [Fact]
        public void HandleWebRequest_Enter_SendsStageSelectEnterAction()
        {
            string sent = null;
            var task = new StageSelectTask(delegate { return true; }, delegate(string payload) { sent = payload; });

            task.HandleWebRequest("enter", JObject.Parse("{\"callId\":\"web-3\",\"stageName\":\"新手练习场\",\"difficulty\":\"简单\"}"));

            var msg = JObject.Parse(sent.TrimEnd('\0'));
            Assert.Equal("stageSelectEnter", (string)msg["action"]);
            Assert.Equal("新手练习场", (string)msg["stageName"]);
            Assert.Equal("简单", (string)msg["difficulty"]);
        }

        [Fact]
        public void HandleFlashResponse_RewritesToStageSelectPanelResponse()
        {
            string posted = null;
            string sent = null;
            string asyncResponse = "not-called";
            var task = new StageSelectTask(delegate { return true; }, delegate(string payload) { sent = payload; });
            task.SetPostToWeb(delegate(string json) { posted = json; });

            task.HandleWebRequest("enter", JObject.Parse("{\"callId\":\"web-4\",\"stageName\":\"新手练习场\",\"difficulty\":\"简单\"}"));
            Assert.NotNull(sent);
            task.HandleFlashResponse(JObject.Parse("{\"task\":\"stage_select_response\",\"callId\":1,\"success\":true,\"closePanel\":true}"),
                delegate(string json) { asyncResponse = json; });

            Assert.Null(asyncResponse);
            var resp = JObject.Parse(posted);
            Assert.Equal("panel_resp", (string)resp["type"]);
            Assert.Equal("stage-select", (string)resp["panel"]);
            Assert.Equal("enter", (string)resp["cmd"]);
            Assert.Equal("web-4", (string)resp["callId"]);
            Assert.True((bool)resp["success"]);
            Assert.True((bool)resp["closePanel"]);
        }
    }
}
