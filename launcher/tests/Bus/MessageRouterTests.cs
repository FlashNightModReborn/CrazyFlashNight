// MessageRouter 的当前行为锁定测试。
// 明确不测试"应然"行为（去重 / 异常包装）——未来若要改契约，
// 先改 MessageRouter.cs 再同步改这里的测试。

using System;
using CF7Launcher.Bus;
using Newtonsoft.Json.Linq;
using Xunit;

namespace CF7Launcher.Tests.Bus
{
    public class MessageRouterTests
    {
        // ─────── 正常路径 ───────

        [Fact]
        public void RegisterSync_NormalCmd_WrapsCallId()
        {
            var router = new MessageRouter();
            router.RegisterSync("hello", msg => "{\"ok\":true}");

            string result = router.ProcessMessage("{\"task\":\"hello\",\"callId\":42}", null);

            JObject obj = JObject.Parse(result);
            Assert.True(obj.Value<bool>("ok"));
            Assert.Equal(42, obj.Value<int>("callId"));
        }

        [Fact]
        public void RegisterSync_NoCallId_ResponseUnwrapped()
        {
            var router = new MessageRouter();
            router.RegisterSync("hello", msg => "{\"ok\":true}");

            string result = router.ProcessMessage("{\"task\":\"hello\"}", null);

            JObject obj = JObject.Parse(result);
            Assert.DoesNotContain("callId", obj);
        }

        [Fact]
        public void RegisterAsync_NormalCmd_HandlerCalled_ReturnsNull()
        {
            var router = new MessageRouter();
            string respondResult = null;
            router.RegisterAsync("slow", (msg, respond) => respond("{\"done\":true}"));

            string syncResult = router.ProcessMessage(
                "{\"task\":\"slow\",\"callId\":99}",
                s => respondResult = s);

            Assert.Null(syncResult);
            Assert.NotNull(respondResult);
            JObject obj = JObject.Parse(respondResult);
            Assert.Equal(99, obj.Value<int>("callId"));
            Assert.True(obj.Value<bool>("done"));
        }

        [Fact]
        public void RegisterAsync_NoCallId_ResponseUnwrapped()
        {
            var router = new MessageRouter();
            string respondResult = null;
            router.RegisterAsync("slow", (msg, respond) => respond("{\"done\":true}"));

            router.ProcessMessage("{\"task\":\"slow\"}", s => respondResult = s);

            Assert.NotNull(respondResult);
            JObject obj = JObject.Parse(respondResult);
            Assert.DoesNotContain("callId", obj);
        }

        // ─────── 错误路径 ───────

        [Fact]
        public void UnknownCmd_ReturnsJsonError_WithCallId()
        {
            var router = new MessageRouter();

            string result = router.ProcessMessage("{\"task\":\"nope\",\"callId\":7}", null);

            JObject obj = JObject.Parse(result);
            Assert.False(obj.Value<bool>("success"));
            Assert.Equal("Unknown task type", obj.Value<string>("error"));
            Assert.Equal(7, obj.Value<int>("callId"));
        }

        [Fact]
        public void NoTaskField_ReturnsJsonError_CallIdNotInjected()
        {
            // 当前行为：no-task 走 early return（L59-60），不经过 WrapResponse，
            // 即便原消息含 callId 也不注入。锁定此行为——未来若要改先改 router。
            var router = new MessageRouter();

            string result = router.ProcessMessage("{\"callId\":5}", null);

            JObject obj = JObject.Parse(result);
            Assert.Equal("No task type provided", obj.Value<string>("error"));
            Assert.DoesNotContain("callId", obj);
        }

        [Fact]
        public void InvalidJson_ReturnsParseError()
        {
            var router = new MessageRouter();

            string result = router.ProcessMessage("{not json", null);

            JObject obj = JObject.Parse(result);
            Assert.False(obj.Value<bool>("success"));
            Assert.Equal("Expected JSON format", obj.Value<string>("error"));
        }

        // ─────── console_result 特殊路径 ───────

        [Fact]
        public void ConsoleResult_TriggersEvent_ReturnsNull()
        {
            var router = new MessageRouter();
            string received = null;
            router.OnConsoleResult += s => received = s;
            string json = "{\"task\":\"console_result\",\"value\":1}";

            string result = router.ProcessMessage(json, null);

            Assert.Null(result);
            Assert.Equal(json, received);
        }

        [Fact]
        public void ConsoleResult_NoSubscriber_NoThrow()
        {
            var router = new MessageRouter();

            string result = router.ProcessMessage("{\"task\":\"console_result\"}", null);

            Assert.Null(result);
        }

        // ─────── 异常冒泡（当前行为，无 try/catch 包装） ───────

        [Fact]
        public void SyncHandler_Throws_Propagates()
        {
            var router = new MessageRouter();
            router.RegisterSync("boom",
                msg => { throw new InvalidOperationException("bang"); });

            Assert.Throws<InvalidOperationException>(() =>
                router.ProcessMessage("{\"task\":\"boom\"}", null));
        }

        [Fact]
        public void AsyncHandler_Throws_Propagates()
        {
            var router = new MessageRouter();
            router.RegisterAsync("boom",
                (msg, respond) => { throw new InvalidOperationException("bang"); });

            Assert.Throws<InvalidOperationException>(() =>
                router.ProcessMessage("{\"task\":\"boom\"}", s => { }));
        }

        // ─────── respond 多次调用（当前不防护） ───────

        [Fact]
        public void AsyncRespond_CalledMultipleTimes_NotGuarded()
        {
            // 锁定当前行为：router 不去重 respond 回调。
            // 每次 respond() 都会走一遍 WrapResponse + asyncRespond。
            var router = new MessageRouter();
            int calls = 0;
            router.RegisterAsync("multi", (msg, respond) =>
            {
                respond("{\"n\":1}");
                respond("{\"n\":2}");
                respond("{\"n\":3}");
            });

            router.ProcessMessage("{\"task\":\"multi\"}", s => calls++);

            Assert.Equal(3, calls);
        }

        // ─────── 注册优先级 ───────

        [Fact]
        public void SyncHandler_TakesPriorityOverAsync()
        {
            // 当前行为：ProcessMessage L75 先查 sync 字典
            var router = new MessageRouter();
            router.RegisterSync("both", msg => "{\"from\":\"sync\"}");
            router.RegisterAsync("both", (msg, respond) => respond("{\"from\":\"async\"}"));

            string result = router.ProcessMessage("{\"task\":\"both\"}", null);

            JObject obj = JObject.Parse(result);
            Assert.Equal("sync", obj.Value<string>("from"));
        }
    }
}
