using System;
using System.Collections;
using System.Collections.Generic;
using System.Reflection;
using CF7Launcher.Tasks;
using Newtonsoft.Json.Linq;
using Xunit;

namespace CF7Launcher.Tests.Tasks
{
    public sealed class MapTaskResponseTests
    {
        // 只装入已有等待项，直接验真实回包消费者；不为测试修改生产桥或连接游戏。
        private static MapTask Waiting(List<JObject> posted, string command, params int[] ids)
        {
            var task = new MapTask(null);
            task.SetInvoker(action => action());
            task.SetPostToWeb(json => posted.Add(JObject.Parse(json)));
            var pending = (IDictionary)typeof(MapTask).GetField("_pending", BindingFlags.Instance | BindingFlags.NonPublic).GetValue(task);
            var entryType = typeof(MapTask).GetNestedType("PendingRequest", BindingFlags.NonPublic);
            foreach (int id in ids)
            {
                var entry = Activator.CreateInstance(entryType, true);
                entryType.GetField("WebCallId").SetValue(entry, "map-web-" + id);
                entryType.GetField("WebCmd").SetValue(entry, command);
                pending.Add(id, entry);
            }
            return task;
        }

        [Fact]
        public void MissingIdCannotConsumeWaitingRequest_ThenRealNumericWireCompletesIt()
        {
            var posted = new List<JObject>();
            using var task = Waiting(posted, "snapshot", 71);
            task.HandleFlashResponse(JObject.Parse("{\"task\":\"map_response\",\"success\":true,\"snapshot\":{\"version\":4}}"), _ => { });
            Assert.Empty(posted);
            task.HandleFlashResponse(JObject.Parse("{\"snapshot\":{\"version\":4,\"currentHotspotId\":\"alpha\"},\"task\":\"map_response\",\"callId\":71,\"success\":true,\"error\":\"\"}"), _ => { });
            Assert.Single(posted);
            Assert.Equal("map-web-71", (string)posted[0]["callId"]);
            Assert.Equal("panel_resp", (string)posted[0]["type"]);
            Assert.Equal("map", (string)posted[0]["panel"]);
            Assert.Equal("snapshot", (string)posted[0]["cmd"]);
            Assert.Equal(4, (int)posted[0]["snapshot"]["version"]);
            Assert.Null(posted[0]["task"]);
        }

        [Fact]
        public void OutOfOrderResponsesKeepTheirOwners_AndDuplicatesDoNotRepeatDelivery()
        {
            var posted = new List<JObject>();
            using var task = Waiting(posted, "snapshot", 71, 72);
            foreach (int id in new[] { 72, 71, 72 })
                task.HandleFlashResponse(new JObject { ["task"] = "map_response", ["callId"] = id, ["success"] = true }, _ => { });
            Assert.Equal(2, posted.Count);
            Assert.Equal("map-web-72", (string)posted[0]["callId"]);
            Assert.Equal("map-web-71", (string)posted[1]["callId"]);
        }

        [Theory]
        [InlineData(true)]
        [InlineData(false)]
        public void NavigationPreservesConfirmedSuccessAndCloseFlag(bool success)
        {
            var posted = new List<JObject>();
            using var task = Waiting(posted, "navigate", 74);
            task.HandleFlashResponse(new JObject { ["task"] = "map_response", ["callId"] = 74,
                ["success"] = success, ["closePanel"] = success, ["error"] = success ? "" : "not_navigable" }, _ => { });
            Assert.Single(posted);
            Assert.Equal("map-web-74", (string)posted[0]["callId"]);
            Assert.Equal("navigate", (string)posted[0]["cmd"]);
            Assert.Equal(success, (bool)posted[0]["success"]);
            Assert.Equal(success, (bool)posted[0]["closePanel"]);
        }

        [Fact]
        public void MaximumPositiveHostIdIsCorrelatedWithoutTruncation()
        {
            var posted = new List<JObject>();
            using var task = Waiting(posted, "snapshot", int.MaxValue);
            task.HandleFlashResponse(new JObject { ["task"] = "map_response", ["callId"] = int.MaxValue, ["success"] = true }, _ => { });
            Assert.Single(posted);
            Assert.Equal("map-web-2147483647", (string)posted[0]["callId"]);
        }
    }
}
