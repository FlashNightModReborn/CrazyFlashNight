using Newtonsoft.Json.Linq;
using Xunit;
using CF7Launcher.Bus;

namespace CF7Launcher.Tests.Bus
{
    public class MessageRouterStrictJsonTests
    {
        [Fact]
        public void DuplicateTaskKey_IsRejectedBeforeAnyHandlerRuns()
        {
            var router = new MessageRouter();
            int dispatchCount = 0;
            router.RegisterSync("probe", delegate(JObject message)
            {
                dispatchCount++;
                return "{\"ok\":true}";
            });

            string result = router.ProcessMessage(
                "{\"task\":\"probe\",\"task\":\"probe\"}",
                null);

            JObject error = JObject.Parse(result);
            Assert.False((bool)error["success"]);
            Assert.Equal("Expected JSON format", (string)error["error"]);
            Assert.Equal(0, dispatchCount);
        }

        [Fact]
        public void DuplicatePayloadKey_IsRejectedBeforeAsyncHandlerRuns()
        {
            var router = new MessageRouter();
            int dispatchCount = 0;
            router.RegisterAsync("probe", delegate(
                JObject message,
                System.Action<string> respond)
            {
                dispatchCount++;
                respond("{\"ok\":true}");
            });

            string result = router.ProcessMessage(
                "{\"task\":\"probe\",\"value\":1,\"value\":2}",
                delegate(string ignored) { });

            JObject error = JObject.Parse(result);
            Assert.False((bool)error["success"]);
            Assert.Equal("Expected JSON format", (string)error["error"]);
            Assert.Equal(0, dispatchCount);
        }

        [Fact]
        public void UniqueJsonKeepsExistingRoutingBehavior()
        {
            var router = new MessageRouter();
            int dispatchCount = 0;
            router.RegisterSync("probe", delegate(JObject message)
            {
                dispatchCount++;
                return "{\"ok\":true}";
            });

            JObject result = JObject.Parse(router.ProcessMessage(
                "{\"task\":\"probe\",\"value\":1}",
                null));

            Assert.True((bool)result["ok"]);
            Assert.Equal(1, dispatchCount);
        }
    }
}
