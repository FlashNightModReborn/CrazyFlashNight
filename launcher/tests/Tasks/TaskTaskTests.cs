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
        public void HandleWebRequest_WebSuppliedActionTask_CannotOverrideTrustedAction()
        {
            // 安全反向用例：Web 消息夹带 action/task 不得覆盖 C# 由 cmd 派生的可信 action/信封。
            // 否则 cmd:"snapshot" + action:"taskDelete" 可绕过前端确认弹窗，并触达 AS2 裸分发
            // _root.gameCommands[action]（无白名单）→ 调用任意已注册全局命令。
            string sent = null;
            var task = new TaskTask(delegate { return true; }, delegate(string payload) { sent = payload; });

            task.HandleWebRequest("snapshot",
                JObject.Parse("{\"callId\":\"web-evil\",\"action\":\"taskDelete\",\"task\":\"evil\",\"taskId\":106}"));

            var msg = JObject.Parse(sent.TrimEnd('\0'));
            Assert.Equal("cmd", (string)msg["task"]);            // 信封 task 仍是可信的 "cmd"，未被 "evil" 覆盖
            Assert.Equal("taskSnapshot", (string)msg["action"]); // action 仍由 cmd=snapshot 派生，未被 "taskDelete" 劫持
            Assert.Equal(106, (int)msg["taskId"]);               // 其它字段照常透传——守卫是外科级，仅拦 action/task
        }

        [Fact]
        public void HandleWebRequest_NavigateFinish_SendsTaskNavigateFinishActionAndTaskId()
        {
            string sent = null;
            var task = new TaskTask(delegate { return true; }, delegate(string payload) { sent = payload; });

            task.HandleWebRequest("navigateFinish", JObject.Parse("{\"callId\":\"web-nav\",\"taskId\":40013}"));

            var msg = JObject.Parse(sent.TrimEnd('\0'));
            Assert.Equal("cmd", (string)msg["task"]);
            Assert.Equal("taskNavigateFinish", (string)msg["action"]);
            Assert.Equal(40013, (int)msg["taskId"]);
            Assert.Null(msg["panel"]);
        }

        [Fact]
        public void HandleFlashResponse_NavigateFinish_PreservesClosePanelFlag()
        {
            // 前往交付成功回 closePanel:true（与地图 navigate 同语义）；C# 改写信封后须原样保留。
            string sent = null;
            string posted = null;
            var task = new TaskTask(delegate { return true; }, delegate(string payload) { sent = payload; });
            task.SetPostToWeb(delegate(string json) { posted = json; });

            task.HandleWebRequest("navigateFinish", JObject.Parse("{\"callId\":\"web-nav2\",\"taskId\":40013}"));
            int flashCallId = (int)JObject.Parse(sent.TrimEnd('\0'))["callId"];

            task.HandleFlashResponse(
                JObject.Parse("{\"task\":\"task_response\",\"callId\":" + flashCallId + ",\"success\":true,\"closePanel\":true}"),
                delegate(string json) { });

            var resp = JObject.Parse(posted);
            Assert.Equal("panel_resp", (string)resp["type"]);
            Assert.Equal("navigateFinish", (string)resp["cmd"]);
            Assert.True((bool)resp["success"]);
            Assert.True((bool)resp["closePanel"]);
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
        public void HandleWebRequest_TreeState_SendsTaskTreeStateAction()
        {
            string sent = null;
            var task = new TaskTask(delegate { return true; }, delegate(string payload) { sent = payload; });

            task.HandleWebRequest("treeState", JObject.Parse("{\"callId\":\"web-tr\"}"));

            var msg = JObject.Parse(sent.TrimEnd('\0'));
            Assert.Equal("cmd", (string)msg["task"]);
            Assert.Equal("taskTreeState", (string)msg["action"]);
            Assert.Null(msg["panel"]);
            Assert.Null(msg["cmd"]);
        }

        [Fact]
        public void HandleFlashResponse_TreeState_PreservesProgressOverlay()
        {
            // WS6 进度小叠加：AS2 回 chainsProgress + finished + active；C# 改写信封后须原样保留。
            string sent = null;
            string posted = null;
            var task = new TaskTask(delegate { return true; }, delegate(string payload) { sent = payload; });
            task.SetPostToWeb(delegate(string json) { posted = json; });

            task.HandleWebRequest("treeState", JObject.Parse("{\"callId\":\"web-tr2\"}"));
            int flashCallId = (int)JObject.Parse(sent.TrimEnd('\0'))["callId"];

            task.HandleFlashResponse(
                JObject.Parse("{\"task\":\"task_response\",\"callId\":" + flashCallId + ",\"success\":true,\"chainsProgress\":{\"主线\":14},\"finished\":[\"0\",\"10014\"],\"active\":[10021]}"),
                delegate(string json) { });

            var resp = JObject.Parse(posted);
            Assert.Equal("panel_resp", (string)resp["type"]);
            Assert.Equal("treeState", (string)resp["cmd"]);
            Assert.True((bool)resp["success"]);
            Assert.Equal(14, (int)resp["chainsProgress"]["主线"]);
            Assert.Equal(2, ((JArray)resp["finished"]).Count);
            Assert.Equal(10021, (int)((JArray)resp["active"])[0]);
        }

        [Fact]
        public void HandleWebRequest_ReplayDialogue_SendsActionTaskIdAndWhich()
        {
            string sent = null;
            var task = new TaskTask(delegate { return true; }, delegate(string payload) { sent = payload; });

            task.HandleWebRequest("replayDialogue", JObject.Parse("{\"callId\":\"web-rp\",\"taskId\":10014,\"which\":\"finish\"}"));

            var msg = JObject.Parse(sent.TrimEnd('\0'));
            Assert.Equal("taskReplayDialogue", (string)msg["action"]);
            Assert.Equal(10014, (int)msg["taskId"]);
            Assert.Equal("finish", (string)msg["which"]);
            Assert.Null(msg["panel"]);
        }

        [Fact]
        public void HandleFlashResponse_ReplayDialogue_PreservesDialogueLines()
        {
            // 对话回放回传单任务对话文本行（{speaker,sub,text}）供 web 内联渲染；C# 改写信封后须原样保留 lines。
            string sent = null;
            string posted = null;
            var task = new TaskTask(delegate { return true; }, delegate(string payload) { sent = payload; });
            task.SetPostToWeb(delegate(string json) { posted = json; });

            task.HandleWebRequest("replayDialogue", JObject.Parse("{\"callId\":\"web-rp2\",\"taskId\":10014,\"which\":\"get\"}"));
            int flashCallId = (int)JObject.Parse(sent.TrimEnd('\0'))["callId"];

            task.HandleFlashResponse(
                JObject.Parse("{\"task\":\"task_response\",\"callId\":" + flashCallId + ",\"success\":true,\"which\":\"get\",\"lines\":[{\"speaker\":\"Andy Law\",\"sub\":\"东区最强战士\",\"text\":\"独行者，欢迎。\"}]}"),
                delegate(string json) { });

            var resp = JObject.Parse(posted);
            Assert.Equal("replayDialogue", (string)resp["cmd"]);
            Assert.True((bool)resp["success"]);
            var lines = (JArray)resp["lines"];
            Assert.Single(lines);
            Assert.Equal("Andy Law", (string)lines[0]["speaker"]);
            Assert.Equal("独行者，欢迎。", (string)lines[0]["text"]);
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
        public void HandleWebRequest_AchievementState_SendsAchievementStateAction()
        {
            string sent = null;
            var task = new TaskTask(delegate { return true; }, delegate(string payload) { sent = payload; });

            task.HandleWebRequest("achievementState", JObject.Parse("{\"callId\":\"web-as\"}"));

            var msg = JObject.Parse(sent.TrimEnd('\0'));
            Assert.Equal("cmd", (string)msg["task"]);
            Assert.Equal("achievementState", (string)msg["action"]);
            Assert.Null(msg["panel"]);
            Assert.Null(msg["cmd"]);
        }

        [Fact]
        public void HandleWebRequest_AchievementClaim_SendsActionAndAchievementId()
        {
            string sent = null;
            var task = new TaskTask(delegate { return true; }, delegate(string payload) { sent = payload; });

            task.HandleWebRequest("achievementClaim", JObject.Parse("{\"callId\":\"web-ac\",\"achievementId\":700101}"));

            var msg = JObject.Parse(sent.TrimEnd('\0'));
            Assert.Equal("cmd", (string)msg["task"]);
            Assert.Equal("achievementClaim", (string)msg["action"]);
            // 写操作透传 achievementId（稳定主键，绝不传 index）
            Assert.Equal(700101, (int)msg["achievementId"]);
            Assert.Null(msg["index"]);
            Assert.Null(msg["panel"]);
        }

        [Fact]
        public void HandleFlashResponse_AchievementState_PreservesStateOverlay()
        {
            // 成就状态叠加：AS2 回 unlocked/claimed/progress/hiddenReveals/dataReady；C# 改写信封后须原样保留。
            string sent = null;
            string posted = null;
            var task = new TaskTask(delegate { return true; }, delegate(string payload) { sent = payload; });
            task.SetPostToWeb(delegate(string json) { posted = json; });

            task.HandleWebRequest("achievementState", JObject.Parse("{\"callId\":\"web-as2\"}"));
            int flashCallId = (int)JObject.Parse(sent.TrimEnd('\0'))["callId"];

            task.HandleFlashResponse(
                JObject.Parse("{\"task\":\"task_response\",\"callId\":" + flashCallId + ",\"success\":true,\"unlocked\":[\"700101\",\"700204\"],\"claimed\":[\"700101\"],\"progress\":{\"700201\":3},\"hiddenReveals\":[{\"id\":700204,\"title\":\"一骑当千\",\"description\":\"成就启用后累计击杀 5000 名敌人\",\"rewards\":[{\"name\":\"K点\",\"count\":300}]}],\"dataReady\":true}"),
                delegate(string json) { });

            var resp = JObject.Parse(posted);
            Assert.Equal("panel_resp", (string)resp["type"]);
            Assert.Equal("tasks", (string)resp["panel"]);
            Assert.Equal("achievementState", (string)resp["cmd"]);
            Assert.True((bool)resp["success"]);
            Assert.Equal(2, ((JArray)resp["unlocked"]).Count);
            Assert.Single((JArray)resp["claimed"]);
            Assert.Equal(3, (int)resp["progress"]["700201"]);
            Assert.Equal("一骑当千", (string)((JArray)resp["hiddenReveals"])[0]["title"]);
            Assert.True((bool)resp["dataReady"]);
        }

        [Fact]
        public void HandleFlashResponse_AchievementClaim_PreservesRewardsAndOverlay()
        {
            // 领取成功回包：rewards（web 内渲染奖励 toast，不走 AS2 弹窗）+ 完整状态叠加（原子重渲）。
            string sent = null;
            string posted = null;
            var task = new TaskTask(delegate { return true; }, delegate(string payload) { sent = payload; });
            task.SetPostToWeb(delegate(string json) { posted = json; });

            task.HandleWebRequest("achievementClaim", JObject.Parse("{\"callId\":\"web-ac2\",\"achievementId\":700101}"));
            int flashCallId = (int)JObject.Parse(sent.TrimEnd('\0'))["callId"];

            task.HandleFlashResponse(
                JObject.Parse("{\"task\":\"task_response\",\"callId\":" + flashCallId + ",\"success\":true,\"rewards\":[{\"name\":\"金币\",\"count\":5000}],\"unlocked\":[\"700101\"],\"claimed\":[\"700101\"],\"progress\":{\"700101\":1},\"hiddenReveals\":[],\"dataReady\":true}"),
                delegate(string json) { });

            var resp = JObject.Parse(posted);
            Assert.Equal("achievementClaim", (string)resp["cmd"]);
            Assert.True((bool)resp["success"]);
            Assert.Equal("金币", (string)((JArray)resp["rewards"])[0]["name"]);
            Assert.Equal(5000, (int)((JArray)resp["rewards"])[0]["count"]);
            Assert.Single((JArray)resp["claimed"]);
        }

        [Fact]
        public void HandleWebRequest_AchievementClaim_WebSuppliedActionTask_CannotOverrideTrustedAction()
        {
            // 安全反向用例（PanelBridge 保留键守卫在新 cmd 上的继承）：夹带 action/task 不得覆盖可信 action。
            string sent = null;
            var task = new TaskTask(delegate { return true; }, delegate(string payload) { sent = payload; });

            task.HandleWebRequest("achievementClaim",
                JObject.Parse("{\"callId\":\"web-evil2\",\"action\":\"taskDelete\",\"task\":\"evil\",\"achievementId\":700101}"));

            var msg = JObject.Parse(sent.TrimEnd('\0'));
            Assert.Equal("cmd", (string)msg["task"]);
            Assert.Equal("achievementClaim", (string)msg["action"]);
            Assert.Equal(700101, (int)msg["achievementId"]);
        }

        [Fact]
        public void HandleWebRequest_BareAchievementOrClaimCmd_Unsupported()
        {
            // 命名契约反例：成就命令必须全称（achievementState/achievementClaim）。
            // 裸名 "claim" 在 WebOverlayForm 会在 panel 判别前被无条件路由 ShopTask，
            // 即便到达 TaskTask 也必须拒绝，防止有人误把缩写接进映射表。
            string posted = null;
            var task = new TaskTask(delegate { return true; }, delegate(string payload) { });
            task.SetPostToWeb(delegate(string json) { posted = json; });

            task.HandleWebRequest("claim", JObject.Parse("{\"callId\":\"web-bare\"}"));
            Assert.Equal("unsupported_cmd", (string)JObject.Parse(posted)["error"]);

            posted = null;
            task.HandleWebRequest("achievement", JObject.Parse("{\"callId\":\"web-bare2\"}"));
            Assert.Equal("unsupported_cmd", (string)JObject.Parse(posted)["error"]);
        }

        [Fact]
        public void HandleWebRequest_AchievementState_Disconnected_ReturnsPanelError()
        {
            string posted = null;
            var task = new TaskTask(delegate { return false; }, delegate(string payload) { });
            task.SetPostToWeb(delegate(string json) { posted = json; });

            task.HandleWebRequest("achievementState", JObject.Parse("{\"callId\":\"web-as3\"}"));

            var resp = JObject.Parse(posted);
            Assert.Equal("panel_resp", (string)resp["type"]);
            Assert.Equal("achievementState", (string)resp["cmd"]);
            Assert.False((bool)resp["success"]);
            Assert.Equal("disconnected", (string)resp["error"]);
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
