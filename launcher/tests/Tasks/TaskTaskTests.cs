using Newtonsoft.Json.Linq;
using Xunit;
using CF7Launcher.Tasks;

namespace CF7Launcher.Tests.Tasks
{
    public class TaskTaskTests
    {
        [Fact]
        public void HandleWebRequest_Disconnected_ReturnsPanelError()
        {
            string posted = null;
            var task = new TaskTask(delegate { return false; }, delegate(string payload) { });
            task.SetPostToWeb(delegate(string json) { posted = json; });

            task.HandleWebRequest("snapshot", JObject.Parse("{\"callId\":\"web-1\"}"));

            var resp = JObject.Parse(posted);
            Assert.Equal("panel_resp", (string)resp["type"]);
            Assert.Equal("tasks", (string)resp["panel"]);
            Assert.Equal("snapshot", (string)resp["cmd"]);
            Assert.Equal("web-1", (string)resp["callId"]);
            Assert.False((bool)resp["success"]);
            Assert.Equal("disconnected", (string)resp["error"]);
        }

        [Fact]
        public void HandleWebRequest_Snapshot_SendsTaskSnapshotAction()
        {
            string sent = null;
            var task = new TaskTask(delegate { return true; }, delegate(string payload) { sent = payload; });

            task.HandleWebRequest("snapshot", JObject.Parse("{\"callId\":\"web-2\"}"));

            Assert.EndsWith("\0", sent);
            var msg = JObject.Parse(sent.TrimEnd('\0'));
            Assert.Equal("cmd", (string)msg["task"]);
            Assert.Equal("taskSnapshot", (string)msg["action"]);
            Assert.Equal(1, (int)msg["callId"]);
            Assert.Null(msg["panel"]);
            Assert.Null(msg["cmd"]);
        }

        [Fact]
        public void HandleWebRequest_Detail_SendsTaskDetailActionAndIndex()
        {
            string sent = null;
            var task = new TaskTask(delegate { return true; }, delegate(string payload) { sent = payload; });

            task.HandleWebRequest("detail", JObject.Parse("{\"callId\":\"web-3\",\"index\":2}"));

            var msg = JObject.Parse(sent.TrimEnd('\0'));
            Assert.Equal("taskDetail", (string)msg["action"]);
            Assert.Equal(2, (int)msg["index"]);
        }

        [Fact]
        public void HandleWebRequest_UnsupportedCmd_ReturnsErrorWithoutSending()
        {
            string sent = null;
            string posted = null;
            var task = new TaskTask(delegate { return true; }, delegate(string payload) { sent = payload; });
            task.SetPostToWeb(delegate(string json) { posted = json; });

            task.HandleWebRequest("save", JObject.Parse("{\"callId\":\"web-4\"}"));

            Assert.Null(sent);
            var resp = JObject.Parse(posted);
            Assert.Equal("tasks", (string)resp["panel"]);
            Assert.Equal("save", (string)resp["cmd"]);
            Assert.False((bool)resp["success"]);
            Assert.Equal("unsupported_cmd", (string)resp["error"]);
        }

        [Fact]
        public void HandleFlashResponse_RewritesToTaskPanelResponseAndPreservesTaskData()
        {
            string sent = null;
            string posted = null;
            string asyncResponse = "not-called";
            var task = new TaskTask(delegate { return true; }, delegate(string payload) { sent = payload; });
            task.SetPostToWeb(delegate(string json) { posted = json; });

            task.HandleWebRequest("detail", JObject.Parse("{\"callId\":\"web-5\",\"index\":0}"));
            int flashCallId = (int)JObject.Parse(sent.TrimEnd('\0'))["callId"];

            task.HandleFlashResponse(
                JObject.Parse("{\"task\":\"task_response\",\"callId\":" + flashCallId + ",\"success\":true,\"taskData\":{\"title\":\"清理街区\"}}"),
                delegate(string json) { asyncResponse = json; });

            Assert.Null(asyncResponse);
            var resp = JObject.Parse(posted);
            Assert.Equal("panel_resp", (string)resp["type"]);
            Assert.Equal("tasks", (string)resp["panel"]);
            Assert.Equal("detail", (string)resp["cmd"]);
            Assert.Equal("web-5", (string)resp["callId"]);
            Assert.True((bool)resp["success"]);
            Assert.Null(resp["task"]);
            Assert.Equal("清理街区", (string)resp["taskData"]["title"]);
        }

        [Fact]
        public void ClearPending_DropsStaleFlashResponse()
        {
            string sent = null;
            string posted = null;
            string asyncResponse = "not-called";
            var task = new TaskTask(delegate { return true; }, delegate(string payload) { sent = payload; });
            task.SetPostToWeb(delegate(string json) { posted = json; });

            task.HandleWebRequest("snapshot", JObject.Parse("{\"callId\":\"web-6\"}"));
            int flashCallId = (int)JObject.Parse(sent.TrimEnd('\0'))["callId"];
            task.ClearPending();

            task.HandleFlashResponse(
                JObject.Parse("{\"task\":\"task_response\",\"callId\":" + flashCallId + ",\"success\":true,\"tasks\":[]}"),
                delegate(string json) { asyncResponse = json; });

            Assert.Null(asyncResponse);
            Assert.Null(posted);
        }
    }
}
