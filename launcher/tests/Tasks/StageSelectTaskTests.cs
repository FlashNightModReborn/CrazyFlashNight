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

            task.HandleWebRequest("snapshot", JObject.Parse("{\"callId\":\"web-2\",\"frameLabel\":\"基地车库\",\"returnFrameLabel\":\"基地门口\",\"stageNames\":[\"新手练习场\",\"超市废墟\"]}"));

            Assert.EndsWith("\0", sent);
            var msg = JObject.Parse(sent.TrimEnd('\0'));
            Assert.Equal("cmd", (string)msg["task"]);
            Assert.Equal("stageSelectSnapshot", (string)msg["action"]);
            Assert.Equal(1, (int)msg["callId"]);
            Assert.Equal("基地车库", (string)msg["frameLabel"]);
            Assert.Equal("基地门口", (string)msg["returnFrameLabel"]);
            Assert.Equal("新手练习场", (string)msg["stageNames"][0]);
        }

        [Fact]
        public void HandleWebRequest_WebSuppliedActionTask_CannotOverrideTrustedAction()
        {
            // 安全反向用例：Web 夹带 action/task 不得覆盖 C# 由 cmd 派生的可信 action/信封
            // （AS2 裸分发 _root.gameCommands[action]，无白名单，否则可绕过 cmd→action 映射）。
            string sent = null;
            var task = new StageSelectTask(delegate { return true; }, delegate(string payload) { sent = payload; });

            task.HandleWebRequest("snapshot",
                JObject.Parse("{\"callId\":\"web-evil\",\"action\":\"stageSelectEnter\",\"task\":\"evil\",\"frameLabel\":\"基地车库\"}"));

            var msg = JObject.Parse(sent.TrimEnd('\0'));
            Assert.Equal("cmd", (string)msg["task"]);
            Assert.Equal("stageSelectSnapshot", (string)msg["action"]);
            Assert.Equal("基地车库", (string)msg["frameLabel"]); // 其它字段照常透传，仅 action/task 被守卫
        }

        [Fact]
        public void HandleWebRequest_Enter_SendsStageSelectEnterAction()
        {
            string sent = null;
            var task = new StageSelectTask(delegate { return true; }, delegate(string payload) { sent = payload; });

            task.HandleWebRequest("enter", JObject.Parse("{\"callId\":\"web-3\",\"stageName\":\"新手练习场\",\"difficulty\":\"简单\",\"entryKind\":\"difficulty\"}"));

            var msg = JObject.Parse(sent.TrimEnd('\0'));
            Assert.Equal("stageSelectEnter", (string)msg["action"]);
            Assert.Equal("新手练习场", (string)msg["stageName"]);
            Assert.Equal("简单", (string)msg["difficulty"]);
            Assert.Equal("difficulty", (string)msg["entryKind"]);
        }

        [Fact]
        public void HandleWebRequest_JumpFrame_SendsStageSelectJumpFrameAction()
        {
            string sent = null;
            var task = new StageSelectTask(delegate { return true; }, delegate(string payload) { sent = payload; });

            task.HandleWebRequest("jump_frame", JObject.Parse("{\"callId\":\"web-5\",\"frameLabel\":\"基地车库\"}"));

            var msg = JObject.Parse(sent.TrimEnd('\0'));
            Assert.Equal("stageSelectJumpFrame", (string)msg["action"]);
            Assert.Equal("基地车库", (string)msg["frameLabel"]);
        }

        [Fact]
        public void HandleWebRequest_ReturnFrame_SendsStageSelectReturnFrameAction()
        {
            string sent = null;
            var task = new StageSelectTask(delegate { return true; }, delegate(string payload) { sent = payload; });

            task.HandleWebRequest("return_frame", JObject.Parse("{\"callId\":\"web-6\",\"returnFrameLabel\":\"基地门口\"}"));

            var msg = JObject.Parse(sent.TrimEnd('\0'));
            Assert.Equal("stageSelectReturnFrame", (string)msg["action"]);
            Assert.Equal("基地门口", (string)msg["returnFrameLabel"]);
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

        // ── P3 协议加固：exact instance 绑定 / 会话回显 / stateRevision ─────────────

        [Fact]
        public void BindPanelInstance_RejectsMalformedIds()
        {
            var task = new StageSelectTask(delegate { return true; }, delegate(string payload) { });
            Assert.False(task.BindPanelInstance(null));
            Assert.False(task.BindPanelInstance(""));
            Assert.False(task.BindPanelInstance("bad id with spaces"));
            Assert.Null(task.PanelInstanceId);
            Assert.True(task.BindPanelInstance("panel.stage-select.1"));
            Assert.Equal("panel.stage-select.1", task.PanelInstanceId);
        }

        [Fact]
        public void HandleWebRequest_BoundInstance_RejectsForeignOrMissingInstance()
        {
            string sent = null;
            string posted = null;
            var task = new StageSelectTask(delegate { return true; }, delegate(string payload) { sent = payload; });
            task.SetPostToWeb(delegate(string json) { posted = json; });
            Assert.True(task.BindPanelInstance("panel.ss.1"));

            task.HandleWebRequest("snapshot", JObject.Parse("{\"callId\":\"web-f\",\"panelInstanceId\":\"panel.ss.2\"}"));
            Assert.Null(sent);
            var resp = JObject.Parse(posted);
            Assert.False((bool)resp["success"]);
            Assert.Equal("panel_instance_expired", (string)resp["error"]);

            posted = null;
            task.HandleWebRequest("snapshot", JObject.Parse("{\"callId\":\"web-m\"}"));
            Assert.Null(sent);
            Assert.Equal("panel_instance_expired", (string)JObject.Parse(posted)["error"]);

            posted = null;
            task.HandleWebRequest("snapshot", JObject.Parse("{\"callId\":\"web-ok\",\"panelInstanceId\":\"panel.ss.1\"}"));
            Assert.Null(posted);
            Assert.NotNull(sent);
        }

        [Fact]
        public void HandleWebRequest_Unbound_KeepsLegacyNoInstanceFlow()
        {
            // 未绑定（旧客户端 / 未路由绑定）不强制 instance：保持 P3 前行为。
            string sent = null;
            var task = new StageSelectTask(delegate { return true; }, delegate(string payload) { sent = payload; });
            task.HandleWebRequest("snapshot", JObject.Parse("{\"callId\":\"web-legacy\",\"stageNames\":[\"新手练习场\"]}"));
            Assert.NotNull(sent);
            var msg = JObject.Parse(sent.TrimEnd('\0'));
            Assert.Equal("stageSelectSnapshot", (string)msg["action"]);
        }

        [Fact]
        public void HandleWebRequest_GuardKeysNotForwardedToFlash()
        {
            // 会话守卫键由 C# 代封回显，绝不进入 AS2 面（AS2 输入与 P3 前逐字节一致）。
            string sent = null;
            var task = new StageSelectTask(delegate { return true; }, delegate(string payload) { sent = payload; });
            Assert.True(task.BindPanelInstance("panel.ss.1"));
            task.HandleWebRequest("snapshot", JObject.Parse(
                "{\"callId\":\"web-g\",\"panelInstanceId\":\"panel.ss.1\",\"sessionGeneration\":3,"
                + "\"catalogVersion\":1,\"catalogSchema\":\"stage-select-manifest-v1\",\"stageNames\":[\"新手练习场\"]}"));

            var msg = JObject.Parse(sent.TrimEnd('\0'));
            Assert.Null(msg["panelInstanceId"]);
            Assert.Null(msg["sessionGeneration"]);
            Assert.Null(msg["catalogVersion"]);
            Assert.Null(msg["catalogSchema"]);
            Assert.Equal("新手练习场", (string)msg["stageNames"][0]);
        }

        [Fact]
        public void HandleFlashResponse_AttachesSessionEnvelopeAndSnapshotRevision()
        {
            string posted = null;
            var task = new StageSelectTask(delegate { return true; }, delegate(string payload) { });
            task.SetPostToWeb(delegate(string json) { posted = json; });
            Assert.True(task.BindPanelInstance("panel.ss.1"));

            task.HandleWebRequest("snapshot", JObject.Parse(
                "{\"callId\":\"web-s1\",\"panelInstanceId\":\"panel.ss.1\",\"sessionGeneration\":3,\"catalogVersion\":1}"));
            task.HandleFlashResponse(JObject.Parse("{\"task\":\"stage_select_response\",\"callId\":1,\"success\":true,\"snapshot\":{}}"),
                delegate(string json) { });

            var resp = JObject.Parse(posted);
            Assert.Equal("panel.ss.1", (string)resp["panelInstanceId"]);
            Assert.Equal(3, (long)resp["sessionGeneration"]);
            Assert.Equal(1, (long)resp["stateRevision"]);
            Assert.Equal(1, (long)resp["catalogVersion"]);

            task.HandleWebRequest("snapshot", JObject.Parse(
                "{\"callId\":\"web-s2\",\"panelInstanceId\":\"panel.ss.1\",\"sessionGeneration\":3,\"catalogVersion\":1}"));
            task.HandleFlashResponse(JObject.Parse("{\"task\":\"stage_select_response\",\"callId\":2,\"success\":true,\"snapshot\":{}}"),
                delegate(string json) { });
            resp = JObject.Parse(posted);
            Assert.Equal(2, (long)resp["stateRevision"]);

            // enter 回包带 instance/session，但不带 snapshot 专属的 stateRevision/catalogVersion。
            task.HandleWebRequest("enter", JObject.Parse(
                "{\"callId\":\"web-e\",\"panelInstanceId\":\"panel.ss.1\",\"sessionGeneration\":3,\"stageName\":\"新手练习场\",\"difficulty\":\"简单\"}"));
            task.HandleFlashResponse(JObject.Parse("{\"task\":\"stage_select_response\",\"callId\":3,\"success\":true,\"closePanel\":true}"),
                delegate(string json) { });
            resp = JObject.Parse(posted);
            Assert.Equal("panel.ss.1", (string)resp["panelInstanceId"]);
            Assert.Equal(3, (long)resp["sessionGeneration"]);
            Assert.Null(resp["stateRevision"]);
            Assert.Null(resp["catalogVersion"]);
        }

        [Fact]
        public void HandleFlashResponse_LegacyRequestWithoutSession_StillForwards()
        {
            // 旧客户端请求不携带会话字段：回包不附加守卫字段，Web 端守卫退化关闭。
            string posted = null;
            var task = new StageSelectTask(delegate { return true; }, delegate(string payload) { });
            task.SetPostToWeb(delegate(string json) { posted = json; });
            task.HandleWebRequest("enter", JObject.Parse("{\"callId\":\"web-old\",\"stageName\":\"新手练习场\",\"difficulty\":\"简单\"}"));
            task.HandleFlashResponse(JObject.Parse("{\"task\":\"stage_select_response\",\"callId\":1,\"success\":true}"),
                delegate(string json) { });
            var resp = JObject.Parse(posted);
            Assert.Null(resp["panelInstanceId"]);
            Assert.Null(resp["sessionGeneration"]);
            Assert.True((bool)resp["success"]);
        }

        [Fact]
        public void BindPanelInstance_RebindInvalidatesInflightRequests()
        {
            string posted = null;
            var task = new StageSelectTask(delegate { return true; }, delegate(string payload) { });
            task.SetPostToWeb(delegate(string json) { posted = json; });
            Assert.True(task.BindPanelInstance("panel.ss.1"));
            task.HandleWebRequest("snapshot", JObject.Parse("{\"callId\":\"web-r\",\"panelInstanceId\":\"panel.ss.1\"}"));

            Assert.True(task.BindPanelInstance("panel.ss.2"));
            string asyncResponse = "not-called";
            task.HandleFlashResponse(JObject.Parse("{\"task\":\"stage_select_response\",\"callId\":1,\"success\":true,\"snapshot\":{}}"),
                delegate(string json) { asyncResponse = json; });
            Assert.Null(asyncResponse);
            Assert.Null(posted); // 旧实例迟到回包无处可投
        }

        [Fact]
        public void HandlePanelClosed_ExactMatchClears_MismatchKeeps()
        {
            int postCount = 0;
            var task = new StageSelectTask(delegate { return true; }, delegate(string payload) { });
            task.SetPostToWeb(delegate(string json) { postCount++; });
            Assert.True(task.BindPanelInstance("panel.ss.1"));
            task.HandleWebRequest("snapshot", JObject.Parse("{\"callId\":\"web-c1\",\"panelInstanceId\":\"panel.ss.1\"}"));

            Assert.False(task.HandlePanelClosed("panel.ss.2"));   // 异实例关闭不得误清
            Assert.False(task.HandlePanelClosed(null));
            task.HandleFlashResponse(JObject.Parse("{\"task\":\"stage_select_response\",\"callId\":1,\"success\":true,\"snapshot\":{}}"),
                delegate(string json) { });
            Assert.Equal(1, postCount);   // 在途请求仍正常回投

            task.HandleWebRequest("snapshot", JObject.Parse("{\"callId\":\"web-c2\",\"panelInstanceId\":\"panel.ss.1\"}"));
            Assert.True(task.HandlePanelClosed("panel.ss.1"));
            Assert.Null(task.PanelInstanceId);
            task.HandleFlashResponse(JObject.Parse("{\"task\":\"stage_select_response\",\"callId\":2,\"success\":true,\"snapshot\":{}}"),
                delegate(string json) { });
            Assert.Equal(1, postCount);   // 关闭后在途回包被丢弃
        }

        [Fact]
        public void HandleAuthoritativePanelClosed_IdempotentForRepeatedEvent()
        {
            var task = new StageSelectTask(delegate { return true; }, delegate(string payload) { });
            Assert.True(task.BindPanelInstance("panel.ss.1"));
            Assert.True(task.HandleAuthoritativePanelClosed("panel.ss.1"));
            Assert.True(task.HandleAuthoritativePanelClosed("panel.ss.1"));  // 观察器重放幂等
            Assert.Null(task.PanelInstanceId);
            // 未绑定过的实例关闭事件：绑定后立即按精确匹配关闭，状态回到未绑定。
            Assert.True(task.HandleAuthoritativePanelClosed("panel.ss.9"));
            Assert.Null(task.PanelInstanceId);
        }

        [Fact]
        public void ClearPending_UnbindsInstance()
        {
            string sent = null;
            var task = new StageSelectTask(delegate { return true; }, delegate(string payload) { sent = payload; });
            Assert.True(task.BindPanelInstance("panel.ss.1"));
            task.ClearPending();
            Assert.Null(task.PanelInstanceId);
            // 断线重连后旧绑定不得拦截新会话的第一帧请求（由路由层重新 BindPanelInstance）。
            task.HandleWebRequest("snapshot", JObject.Parse("{\"callId\":\"web-re\",\"stageNames\":[\"新手练习场\"]}"));
            Assert.NotNull(sent);
        }
    }
}
