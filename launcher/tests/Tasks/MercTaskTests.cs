using Newtonsoft.Json.Linq;
using Xunit;
using CF7Launcher.Tasks;

namespace CF7Launcher.Tests.Tasks
{
    public class MercTaskTests
    {
        [Fact]
        public void HandleWebRequest_Disconnected_ReturnsPanelError()
        {
            string posted = null;
            var task = new MercTask(() => false, _ => { });
            task.SetPostToWeb(json => posted = json);

            task.HandleWebRequest("snapshot", JObject.Parse("{\"callId\":\"web-1\"}"));

            var resp = JObject.Parse(posted);
            Assert.Equal("mercs", (string)resp["panel"]);
            Assert.Equal("disconnected", (string)resp["error"]);
        }

        [Theory]
        [InlineData("snapshot", "mercSnapshot")]
        [InlineData("hire_list", "mercHireList")]
        [InlineData("deploy", "mercDeploy")]
        [InlineData("dismiss", "mercDismiss")]
        [InlineData("hire", "mercHire")]
        [InlineData("revive", "mercRevive")]
        [InlineData("equip_tooltip", "mercEquipTooltip")]
        public void HandleWebRequest_KnownCommand_ForwardsTrustedAction(string cmd, string action)
        {
            string sent = null;
            var task = new MercTask(() => true, payload => sent = payload);

            task.HandleWebRequest(cmd, JObject.Parse("{\"callId\":\"web-2\",\"action\":\"evil\",\"task\":\"evil\",\"page\":2}"));

            var msg = JObject.Parse(sent.TrimEnd('\0'));
            Assert.Equal("cmd", (string)msg["task"]);
            Assert.Equal(action, (string)msg["action"]);
            Assert.Equal(2, (int)msg["page"]);
        }

        [Fact]
        public void HandleWebRequest_Unsupported_ReturnsError()
        {
            string posted = null;
            var task = new MercTask(() => true, _ => { });
            task.SetPostToWeb(json => posted = json);

            task.HandleWebRequest("bogus", JObject.Parse("{\"callId\":\"web-3\"}"));

            Assert.Equal("unsupported_cmd", (string)JObject.Parse(posted)["error"]);
        }

        [Fact]
        public void HandleFlashResponse_RestoresWebCallId()
        {
            string sent = null;
            string posted = null;
            var task = new MercTask(() => true, payload => sent = payload);
            task.SetPostToWeb(json => posted = json);
            task.HandleWebRequest("deploy", JObject.Parse("{\"callId\":\"web-4\",\"mercIndex\":1}"));
            int fid = (int)JObject.Parse(sent.TrimEnd('\0'))["callId"];

            task.HandleFlashResponse(JObject.Parse("{\"task\":\"merc_response\",\"callId\":" + fid + ",\"success\":true}"), _ => { });

            var resp = JObject.Parse(posted);
            Assert.Equal("mercs", (string)resp["panel"]);
            Assert.Equal("deploy", (string)resp["cmd"]);
            Assert.Equal("web-4", (string)resp["callId"]);
            Assert.Null(resp["task"]);
        }
    }
}
