using Newtonsoft.Json.Linq;
using Xunit;
using CF7Launcher.Tasks;

namespace CF7Launcher.Tests.Tasks
{
    // 面板桥共用信封构造器 PanelBridge 的单测。全部 8 个 panel 桥的 Web→Flash 透传都收口到
    // BuildFlashCommand，故此处集中验证「保留键守卫 + 信封」一次，等价于覆盖全桥的安全不变量。
    public class PanelBridgeTests
    {
        [Fact]
        public void BuildFlashCommand_SetsEnvelopeAndForwardsBusinessParams()
        {
            var parsed = JObject.Parse("{\"type\":\"panel\",\"panel\":\"tasks\",\"cmd\":\"detail\",\"callId\":\"web-1\",\"taskId\":106,\"index\":3}");

            var msg = PanelBridge.BuildFlashCommand("taskDetail", 42, parsed);

            // 信封：task/action/callId 由调用方提供，权威
            Assert.Equal("cmd", (string)msg["task"]);
            Assert.Equal("taskDetail", (string)msg["action"]);
            Assert.Equal(42, (int)msg["callId"]);
            // 业务参数照常透传
            Assert.Equal(106, (int)msg["taskId"]);
            Assert.Equal(3, (int)msg["index"]);
            // 信封/路由保留键不透传给 Flash（用 web 的字符串 callId 不应覆盖 int callId）
            Assert.Null(msg["type"]);
            Assert.Null(msg["panel"]);
            Assert.Null(msg["cmd"]);
        }

        [Fact]
        public void BuildFlashCommand_WebSuppliedActionTask_CannotOverrideTrustedEnvelope()
        {
            // 安全核心：Web 夹带 action/task 绝不能覆盖 C# 派生的可信 action / 信封 task。
            // 否则 cmd→action 映射可被绕过，触达 AS2 裸分发 _root.gameCommands[action]。
            var parsed = JObject.Parse("{\"action\":\"taskDelete\",\"task\":\"evil\",\"taskId\":106}");

            var msg = PanelBridge.BuildFlashCommand("taskSnapshot", 1, parsed);

            Assert.Equal("cmd", (string)msg["task"]);
            Assert.Equal("taskSnapshot", (string)msg["action"]);
            Assert.Equal(106, (int)msg["taskId"]); // 非保留键照常透传，守卫是外科级
        }

        [Fact]
        public void BuildFlashCommand_NullParsed_ReturnsEnvelopeOnly()
        {
            var msg = PanelBridge.BuildFlashCommand("petSnapshot", 7, null);

            Assert.Equal("cmd", (string)msg["task"]);
            Assert.Equal("petSnapshot", (string)msg["action"]);
            Assert.Equal(7, (int)msg["callId"]);
        }
    }
}
