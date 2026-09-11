using System;
using System.Reflection;
using System.Runtime.CompilerServices;
using CF7Launcher.Guardian;
using CF7Launcher.Tasks;
using Newtonsoft.Json.Linq;
using Xunit;

namespace CF7Launcher.Tests.Guardian
{
    public class StageReturnWebIngressTests
    {
        private static void Set(object value, string field, object data) =>
            value.GetType().GetField(field, BindingFlags.NonPublic | BindingFlags.Instance).SetValue(value, data);

        [Theory]
        [InlineData("stageReturnSnapshot")]
        [InlineData("stageReturnConfirm")]
        public void ActualWebMessageIngress_ForwardsExactChoiceAndStripsHostEnvelope(string command)
        {
            // 无需启动 WebView2：直接执行真实 HandlePanelMessage → TaskTask → PanelBridge。
            // 只提供该窄入口读取的已就绪文档与当前面板身份，传输结果由 socket delegate 接收。
            var form = (WebOverlayForm)RuntimeHelpers.GetUninitializedObject(typeof(WebOverlayForm));
            GC.SuppressFinalize(form);
            var host = (PanelHostController)RuntimeHelpers.GetUninitializedObject(typeof(PanelHostController));
            Set(host, "_activePanel", "tasks"); Set(host, "_activePanelInstanceId", "tasks.current");
            Set(form, "_webReady", true); Set(form, "_panelHost", host);
            string sent = null;
            using var task = new TaskTask(() => true, wire => sent = wire);
            Set(form, "_taskTask", task);
            var request = new JObject { ["type"] = "panel", ["panel"] = "tasks", ["cmd"] = command,
                ["callId"] = "web.1", ["panelInstanceId"] = "tasks.current", ["token"] = "choice.current" };
            if (command == "stageReturnConfirm")
            {
                request["taskId"] = "40002"; request["npcId"] = "bat";
                request["placementId"] = "bat.university"; request["locationId"] = "university";
            }
            typeof(WebOverlayForm).GetMethod("HandlePanelMessage", BindingFlags.NonPublic | BindingFlags.Instance)
                .Invoke(form, new object[] { request.ToString() });
            Assert.NotNull(sent);
            var flash = JObject.Parse(sent.TrimEnd('\0'));
            Assert.Equal(command, (string)flash["action"]);
            Assert.Equal("choice.current", (string)flash["token"]);
            if (command == "stageReturnConfirm")
            {
                Assert.Equal("40002", (string)flash["taskId"]);
                Assert.Equal("bat.university", (string)flash["placementId"]);
                Assert.Equal(8, flash.Count);
            }
            else
            {
                Assert.Null(flash["taskId"]);
                Assert.Equal(4, flash.Count); // AS2 snapshot 只接受 task/action/callId/token。
            }
            Assert.Null(flash["panelInstanceId"]); Assert.Null(flash["panel"]);
        }
    }
}
