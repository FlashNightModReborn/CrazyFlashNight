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
        public void HandleWebRequest_Tooltip_SendsTasksTooltipActionAndItemName()
        {
            string sent = null;
            var task = new TaskTask(delegate { return true; }, delegate(string payload) { sent = payload; });

            task.HandleWebRequest("tooltip", JObject.Parse("{\"callId\":\"web-t\",\"itemName\":\"强化核心\"}"));

            var msg = JObject.Parse(sent.TrimEnd('\0'));
            Assert.Equal("cmd", (string)msg["task"]);
            Assert.Equal("tasksTooltip", (string)msg["action"]);
            Assert.Equal("强化核心", (string)msg["itemName"]);
            Assert.Null(msg["panel"]);
        }

        [Fact]
        public void HandleFlashResponse_Tooltip_RewritesEnvelopeTypeAndPreservesItemType()
        {
            // 协议契约：AS2 用 itemType 承载物品类型；C# 回包必须把信封 type 设为 panel_resp，
            // 且 itemType 字段原样保留（不能用 type 命名物品类型——会与信封 type 冲突，Web 端丢包）。
            string sent = null;
            string posted = null;
            var task = new TaskTask(delegate { return true; }, delegate(string payload) { sent = payload; });
            task.SetPostToWeb(delegate(string json) { posted = json; });

            task.HandleWebRequest("tooltip", JObject.Parse("{\"callId\":\"web-t2\",\"itemName\":\"绷带\"}"));
            int flashCallId = (int)JObject.Parse(sent.TrimEnd('\0'))["callId"];

            task.HandleFlashResponse(
                JObject.Parse("{\"task\":\"task_response\",\"callId\":" + flashCallId + ",\"success\":true,\"itemName\":\"绷带\",\"introHTML\":\"<b>绷带</b>\",\"descHTML\":\"恢复生命\",\"itemType\":\"消耗品\"}"),
                delegate(string json) { });

            var resp = JObject.Parse(posted);
            Assert.Equal("panel_resp", (string)resp["type"]);
            Assert.Equal("tasks", (string)resp["panel"]);
            Assert.Equal("tooltip", (string)resp["cmd"]);
            Assert.Equal("web-t2", (string)resp["callId"]);
            Assert.True((bool)resp["success"]);
            Assert.Equal("消耗品", (string)resp["itemType"]);
            Assert.Equal("<b>绷带</b>", (string)resp["introHTML"]);
        }

        [Fact]
        public void HandleWebRequest_FinishTask_SendsTaskFinishActionAndTaskId()
        {
            string sent = null;
            var task = new TaskTask(delegate { return true; }, delegate(string payload) { sent = payload; });

            task.HandleWebRequest("finishTask", JObject.Parse("{\"callId\":\"web-f\",\"taskId\":106}"));

            var msg = JObject.Parse(sent.TrimEnd('\0'));
            Assert.Equal("cmd", (string)msg["task"]);
            Assert.Equal("taskFinish", (string)msg["action"]);
            Assert.Equal(106, (int)msg["taskId"]);
            // 写操作必须透传 taskId（不传 index）：AS2 splice 后 index 偏移，taskId 才是稳定主键。
            Assert.Null(msg["index"]);
            Assert.Null(msg["panel"]);
        }

        [Fact]
        public void HandleWebRequest_DeleteTask_SendsTaskDeleteActionAndTaskId()
        {
            string sent = null;
            var task = new TaskTask(delegate { return true; }, delegate(string payload) { sent = payload; });

            task.HandleWebRequest("deleteTask", JObject.Parse("{\"callId\":\"web-d\",\"taskId\":103}"));

            var msg = JObject.Parse(sent.TrimEnd('\0'));
            Assert.Equal("taskDelete", (string)msg["action"]);
            Assert.Equal(103, (int)msg["taskId"]);
        }

        [Fact]
        public void HandleFlashResponse_FinishTask_RewritesEnvelopeAndPreservesFreshTasks()
        {
            // 写操作回包契约：AS2 在 splice 后回 success + 刷新后的 tasks 概要；C# 须改写信封为
            // panel_resp 且原样保留 tasks，让 Web 端 applyWriteSnapshot 原子重渲。
            string sent = null;
            string posted = null;
            var task = new TaskTask(delegate { return true; }, delegate(string payload) { sent = payload; });
            task.SetPostToWeb(delegate(string json) { posted = json; });

            task.HandleWebRequest("finishTask", JObject.Parse("{\"callId\":\"web-f2\",\"taskId\":104}"));
            int flashCallId = (int)JObject.Parse(sent.TrimEnd('\0'))["callId"];

            task.HandleFlashResponse(
                JObject.Parse("{\"task\":\"task_response\",\"callId\":" + flashCallId + ",\"success\":true,\"tasks\":[{\"taskId\":101,\"title\":\"斩杀大boss僵尸\",\"satisfied\":true}]}"),
                delegate(string json) { });

            var resp = JObject.Parse(posted);
            Assert.Equal("panel_resp", (string)resp["type"]);
            Assert.Equal("tasks", (string)resp["panel"]);
            Assert.Equal("finishTask", (string)resp["cmd"]);
            Assert.Equal("web-f2", (string)resp["callId"]);
            Assert.True((bool)resp["success"]);
            Assert.Null(resp["task"]);
            var tasks = (JArray)resp["tasks"];
            Assert.Single(tasks);
            Assert.Equal(101, (int)tasks[0]["taskId"]);
        }

        [Fact]
        public void HandleFlashResponse_DeleteTask_PreservesErrorAndTasksOnFailure()
        {
            // 失败回包（如主线拒绝）也带 tasks：Web 端据此重同步。
            string sent = null;
            string posted = null;
            var task = new TaskTask(delegate { return true; }, delegate(string payload) { sent = payload; });
            task.SetPostToWeb(delegate(string json) { posted = json; });

            task.HandleWebRequest("deleteTask", JObject.Parse("{\"callId\":\"web-d2\",\"taskId\":101}"));
            int flashCallId = (int)JObject.Parse(sent.TrimEnd('\0'))["callId"];

            task.HandleFlashResponse(
                JObject.Parse("{\"task\":\"task_response\",\"callId\":" + flashCallId + ",\"success\":false,\"error\":\"cannot_delete_main\",\"tasks\":[{\"taskId\":101}]}"),
                delegate(string json) { });

            var resp = JObject.Parse(posted);
            Assert.Equal("panel_resp", (string)resp["type"]);
            Assert.Equal("deleteTask", (string)resp["cmd"]);
            Assert.False((bool)resp["success"]);
            Assert.Equal("cannot_delete_main", (string)resp["error"]);
            Assert.Single((JArray)resp["tasks"]);
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
