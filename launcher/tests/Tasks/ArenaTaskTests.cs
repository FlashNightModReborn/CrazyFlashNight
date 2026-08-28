using CF7Launcher.Tasks;
using Newtonsoft.Json.Linq;
using Xunit;

namespace CF7Launcher.Tests.Tasks
{
    public sealed class ArenaTaskTests
    {
        [Fact]
        public void HandleFlashResponse_MalformedOrUnknownCallId_PreservesExactPendingRequest()
        {
            string sent = null;
            string posted = null;
            using var task = new ArenaTask(() => true, payload => sent = payload);
            task.SetPostToWeb(json => posted = json);
            task.HandleWebRequest(
                "equip_tooltip",
                JObject.Parse("{\"callId\":\"arena-exact\",\"itemName\":\"绷带\"}"));
            int flashCallId = (int)JObject.Parse(sent.TrimEnd('\0'))["callId"];

            JObject[] invalidResponses =
            {
                JObject.Parse("{\"task\":\"arena_response\",\"success\":true}"),
                JObject.Parse("{\"task\":\"arena_response\",\"callId\":\"" + flashCallId + "\",\"success\":true}"),
                JObject.Parse("{\"task\":\"arena_response\",\"callId\":true,\"success\":true}"),
                JObject.Parse("{\"task\":\"arena_response\",\"callId\":1.0,\"success\":true}"),
                JObject.Parse("{\"task\":\"arena_response\",\"callId\":0,\"success\":true}"),
                JObject.Parse("{\"task\":\"arena_response\",\"callId\":-1,\"success\":true}"),
                JObject.Parse("{\"task\":\"arena_response\",\"callId\":999999,\"success\":true}")
            };
            foreach (JObject response in invalidResponses)
                task.HandleFlashResponse(response, _ => { });

            Assert.Null(posted);
            task.HandleFlashResponse(
                JObject.Parse("{\"task\":\"arena_response\",\"callId\":" + flashCallId + ",\"success\":true,\"itemName\":\"绷带\"}"),
                _ => { });
            JObject exact = JObject.Parse(posted);
            Assert.Equal("arena-exact", exact.Value<string>("callId"));
            Assert.True(exact.Value<bool>("success"));
        }
    }
}
