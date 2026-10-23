using System.Collections.Generic;
using System.Threading;
using System.Threading.Tasks;
using CF7Launcher.Tasks;
using Newtonsoft.Json.Linq;
using Xunit;

namespace CF7Launcher.Tests.Tasks
{
    /// <summary>
    /// Host→AS2 物品交接桥：命令形状、requestId 关联、超时/断线失败面。
    /// 不启动 socket、不构造窗口。
    /// </summary>
    public sealed class NpcItemExchangeTaskTests
    {
        private static JObject ParseSent(string wire)
        {
            Assert.EndsWith("\0", wire);
            return JObject.Parse(wire.TrimEnd('\0'));
        }

        [Fact]
        public void RequestSendsCmdAndMatchesResponseByRequestId()
        {
            var sent = new List<string>();
            var task = new NpcItemExchangeTask(wire => { sent.Add(wire); return true; },
                () => "fixed");

            Task<JObject> pending = task.RequestAsync("npcItemCount",
                new JObject { ["name"] = "苹果" }, CancellationToken.None);

            Assert.Single(sent);
            JObject command = ParseSent(sent[0]);
            Assert.Equal("cmd", command.Value<string>("task"));
            Assert.Equal("npcItemCount", command.Value<string>("action"));
            Assert.Equal("npcitem:fixed", command.Value<string>("requestId"));
            Assert.Equal("苹果", command.Value<string>("name"));

            task.Handle(new JObject
            {
                ["task"] = "npc_item_response",
                ["requestId"] = "npcitem:fixed",
                ["op"] = "count",
                ["success"] = true,
                ["count"] = 3
            });

            JObject result = pending.GetAwaiter().GetResult();
            Assert.NotNull(result);
            Assert.Equal(3, result.Value<int>("count"));
        }

        [Fact]
        public void ArgsCannotOverrideEnvelopeFields()
        {
            var sent = new List<string>();
            var task = new NpcItemExchangeTask(wire => { sent.Add(wire); return true; },
                () => "fixed");
            Task<JObject> pending = task.RequestAsync("npcItemGrant", new JObject
            {
                ["task"] = "hijack",
                ["action"] = "hijack",
                ["requestId"] = "hijack",
                ["name"] = "苹果",
                ["quantity"] = 2
            }, CancellationToken.None);

            JObject command = ParseSent(sent[0]);
            Assert.Equal("cmd", command.Value<string>("task"));
            Assert.Equal("npcItemGrant", command.Value<string>("action"));
            Assert.Equal("npcitem:fixed", command.Value<string>("requestId"));
            Assert.Equal("苹果", command.Value<string>("name"));

            task.Handle(new JObject
            {
                ["requestId"] = "npcitem:fixed",
                ["op"] = "grant",
                ["success"] = true
            });
            Assert.NotNull(pending.GetAwaiter().GetResult());
        }

        [Fact]
        public void NestedPayloadEnvelopeIsAccepted()
        {
            var task = new NpcItemExchangeTask(wire => true, () => "fixed");
            Task<JObject> pending = task.RequestAsync("npcItemSummary", null, CancellationToken.None);

            task.Handle(new JObject
            {
                ["task"] = "npc_item_response",
                ["payload"] = new JObject
                {
                    ["requestId"] = "npcitem:fixed",
                    ["op"] = "summary",
                    ["success"] = true
                }
            });

            JObject result = pending.GetAwaiter().GetResult();
            Assert.NotNull(result);
            Assert.True(result.Value<bool>("success"));
        }

        [Fact]
        public void UnknownRequestIdIsIgnored()
        {
            var task = new NpcItemExchangeTask(wire => true, () => "fixed");
            Task<JObject> pending = task.RequestAsync("npcItemCount",
                new JObject { ["name"] = "苹果" }, CancellationToken.None);
            Assert.False(pending.IsCompleted);

            task.Handle(new JObject
            {
                ["requestId"] = "npcitem:other",
                ["success"] = true
            });
            Assert.False(pending.IsCompleted);

            task.Handle(new JObject
            {
                ["requestId"] = "npcitem:fixed",
                ["success"] = true,
                ["count"] = 1
            });
            JObject result = pending.GetAwaiter().GetResult();
            Assert.Equal(1, result.Value<int>("count"));
        }

        [Fact]
        public void TimeoutReturnsNull()
        {
            var task = new NpcItemExchangeTask(wire => true, () => "fixed");
            task.TimeoutMs = 20;

            JObject result = task.RequestAsync("npcItemTake",
                new JObject { ["name"] = "苹果", ["quantity"] = 1, ["operationId"] = "op" },
                CancellationToken.None).GetAwaiter().GetResult();

            Assert.Null(result);
        }

        [Fact]
        public void SendFailureReturnsNullImmediately()
        {
            var task = new NpcItemExchangeTask(wire => false, () => "fixed");
            task.TimeoutMs = 20;

            JObject result = task.RequestAsync("npcItemCount",
                new JObject { ["name"] = "苹果" }, CancellationToken.None)
                .GetAwaiter().GetResult();

            Assert.Null(result);
        }

        [Fact]
        public void TransportDisconnectFailsAllPending()
        {
            var task = new NpcItemExchangeTask(wire => true, () => "fixed");
            task.TimeoutMs = 5000;
            Task<JObject> first = task.RequestAsync("npcItemCount",
                new JObject { ["name"] = "苹果" }, CancellationToken.None);
            Task<JObject> second = task.RequestAsync("npcItemSummary", null, CancellationToken.None);

            task.HandleTransportDisconnected();

            Assert.Null(first.GetAwaiter().GetResult());
            Assert.Null(second.GetAwaiter().GetResult());
        }
    }
}
