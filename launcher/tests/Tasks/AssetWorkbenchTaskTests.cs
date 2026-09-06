using CF7Launcher.Tasks;
using Newtonsoft.Json.Linq;
using Xunit;

namespace CF7Launcher.Tests.Tasks
{
    public class AssetWorkbenchTaskTests
    {
        private static JObject Message(string cmd = "start") => new JObject {
            ["type"] = "panel", ["panel"] = "asset-workbench", ["domain"] = "asset_workbench",
            ["cmd"] = cmd, ["callId"] = "asset.test.1", ["panelInstanceId"] = "instance.1",
            ["payload"] = new JObject { ["item"] = "mini14", ["kind"] = "all", ["jobId"] = new string('a', 32) }
        };
        private static bool Read(JObject message, string panel = "asset-workbench", string instance = "instance.1") =>
            AssetWorkbenchTask.TryReadRequest(message.ToString(), panel, instance, out _, out _);

        [Fact]
        public void ExactOwnerCanSubmitOnlyStructuredSelection()
        {
            Assert.True(AssetWorkbenchTask.TryReadRequest(Message().ToString(), "asset-workbench", "instance.1", out _, out var request));
            Assert.Equal("start", request.Value<string>("op"));
            Assert.Equal("mini14", request.Value<string>("item"));
        }

        [Theory]
        [InlineData("workbench", "instance.1")]
        [InlineData("asset-workbench", "instance.2")]
        [InlineData("asset-workbench", "")]
        public void ForeignAndExpiredOwnersCannotWrite(string panel, string instance) => Assert.False(Read(Message(), panel, instance));

        [Theory]
        [InlineData("path", "../../runtime")]
        [InlineData("command", "powershell")]
        [InlineData("ffdec", "other.exe")]
        public void CallerCannotSupplyPathsOrExecutables(string key, string value)
        {
            var message = Message(); ((JObject)message["payload"])[key] = value;
            Assert.False(Read(message));
        }

        [Theory]
        [InlineData("jobId", "../backup")]
        [InlineData("kind", "skills")]
        [InlineData("item", "")]
        public void InvalidSelectionIsRejected(string key, string value)
        {
            var message = Message(); message["payload"][key] = value;
            Assert.False(Read(message));
        }

        [Fact]
        public void DuplicateKeysAndLegacyEnvelopeCannotAcquireWriter()
        {
            Assert.False(AssetWorkbenchTask.TryReadRequest("{\"type\":\"panel\",\"type\":\"task\"}", "asset-workbench", "instance.1", out _, out _));
            var message = Message(); message["domain"] = "icon_bake"; Assert.False(Read(message));
            message = Message(); message["cmd"] = "bakeIcons"; Assert.False(Read(message));
        }

        [Theory]
        [InlineData("close")]
        [InlineData("catalog")]
        [InlineData("rescan")]
        public void NoArgumentCommandsHaveEmptyPayload(string cmd)
        {
            var message = Message(cmd); Assert.False(Read(message));
            message["payload"] = new JObject(); Assert.True(Read(message));
        }
    }
}
