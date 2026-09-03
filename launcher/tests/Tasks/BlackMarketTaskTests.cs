using System;
using System.Collections.Generic;
using Newtonsoft.Json.Linq;
using Xunit;
using CF7Launcher.Tasks;

namespace CF7Launcher.Tests.Tasks
{
    /// <summary>
    /// 黑市鉴定面板的 AS2 权威注释通道：只验证透传/包封/错误面，
    /// 物品数据本身由 AS2 Web物品注释HTML 权威提供，本 task 不持有副本。
    /// </summary>
    public class BlackMarketTaskTests : IDisposable
    {
        private readonly List<string> _posted = new List<string>();
        private readonly List<string> _flashed = new List<string>();
        private readonly BlackMarketTask _task;

        public BlackMarketTaskTests()
        {
            _task = new BlackMarketTask(delegate { return true; }, delegate(string payload) { _flashed.Add(payload); });
            _task.SetPostToWeb(delegate(string json) { _posted.Add(json); });
        }

        public void Dispose()
        {
            _task.Dispose();
        }

        [Fact]
        public void Tooltip_ForwardsItemNameToFlashAndWrapsResponse()
        {
            _task.HandleWebRequest("tooltip", JObject.Parse(
                "{\"callId\":\"web-1\",\"itemName\":\"RPG28\"}"));

            Assert.Single(_flashed);
            JObject flash = JObject.Parse(_flashed[0].TrimEnd('\0'));
            Assert.Equal("cmd", (string)flash["task"]);
            Assert.Equal("blackmarketTooltip", (string)flash["action"]);
            Assert.Equal("RPG28", (string)flash["itemName"]);
            Assert.Equal(JTokenType.Integer, flash["callId"].Type);

            // AS2 回包 → panel_resp 透传（descHTML/introHTML 原样转发给 web 注释层）
            _task.HandleFlashResponse(JObject.Parse(
                "{\"task\":\"blackmarket_response\",\"callId\":" + (int)flash["callId"]
                + ",\"success\":true,\"itemName\":\"RPG28\",\"displayname\":\"RPG28\""
                + ",\"descHTML\":\"<B>desc</B>\",\"introHTML\":\"intro\"}"),
                delegate(string ignored) { });

            Assert.Single(_posted);
            JObject resp = JObject.Parse(_posted[0]);
            Assert.Equal("panel_resp", (string)resp["type"]);
            Assert.Equal("blackmarket", (string)resp["panel"]);
            Assert.Equal("tooltip", (string)resp["cmd"]);
            Assert.Equal("web-1", (string)resp["callId"]);
            Assert.True((bool)resp["success"]);
            Assert.Equal("<B>desc</B>", (string)resp["descHTML"]);
            Assert.Equal("intro", (string)resp["introHTML"]);
        }

        [Fact]
        public void Tooltip_RejectsEmptyOrOverlongItemName()
        {
            _task.HandleWebRequest("tooltip", JObject.Parse("{\"callId\":\"web-2\",\"itemName\":\"\"}"));
            Assert.Empty(_flashed);
            JObject resp = JObject.Parse(_posted[0]);
            Assert.False((bool)resp["success"]);
            Assert.Equal("invalid_item_name", (string)resp["error"]);

            _task.HandleWebRequest("tooltip", JObject.Parse(
                "{\"callId\":\"web-3\",\"itemName\":\"" + new string('x', 200) + "\"}"));
            Assert.Equal(2, _posted.Count);
            Assert.Equal("invalid_item_name", (string)JObject.Parse(_posted[1])["error"]);
        }

        [Fact]
        public void Tooltip_ErrorsWhenFlashDisconnected()
        {
            var offline = new BlackMarketTask(delegate { return false; }, delegate(string payload) { });
            var posted = new List<string>();
            offline.SetPostToWeb(delegate(string json) { posted.Add(json); });

            offline.HandleWebRequest("tooltip", JObject.Parse(
                "{\"callId\":\"web-4\",\"itemName\":\"RPG28\"}"));
            JObject resp = JObject.Parse(posted[0]);
            Assert.False((bool)resp["success"]);
            Assert.Equal("disconnected", (string)resp["error"]);
            offline.Dispose();
        }

        [Fact]
        public void UnknownCmd_Rejected_AndOrphanFlashResponseDropped()
        {
            _task.HandleWebRequest("catalog", JObject.Parse("{\"callId\":\"web-5\"}"));
            JObject resp = JObject.Parse(_posted[0]);
            Assert.False((bool)resp["success"]);
            Assert.Equal("unsupported_cmd", (string)resp["error"]);

            // 无 pending 的迟到回包不得触发任何 web 消息
            _task.HandleFlashResponse(JObject.Parse(
                "{\"task\":\"blackmarket_response\",\"callId\":999,\"success\":true}"),
                delegate(string ignored) { });
            Assert.Single(_posted);
        }

        [Fact]
        public void Observation_UsesOneGenerationBoundReadOnlyProbeAndCapturesExactTuple()
        {
            var sends = new List<string>();
            var generations = new List<int>();

            BlackMarketObservationSnapshot first = _task.ObserveHeartbeat(
                7,
                delegate(string payload, int generation)
                {
                    sends.Add(payload);
                    generations.Add(generation);
                    return true;
                });

            Assert.Single(sends);
            Assert.Equal(7, generations[0]);
            JObject command = JObject.Parse(sends[0].TrimEnd('\0'));
            Assert.Equal("cmd", (string)command["task"]);
            Assert.Equal("blackmarketObservation", (string)command["action"]);
            Assert.Equal(3, command.Count);
            Assert.Equal(1, first.OutstandingCount);
            Assert.Equal(0, first.BusinessOutstandingCount);
            Assert.Equal("blackmarket.observation", first.OutstandingOwner);

            BlackMarketObservationSnapshot stillPending = _task.ObserveHeartbeat(
                7,
                delegate(string payload, int generation)
                {
                    sends.Add(payload);
                    return true;
                });
            Assert.Single(sends);
            Assert.Equal(first.RouteSequence, stillPending.RouteSequence);

            _task.HandleFlashResponse(JObject.Parse(
                "{\"task\":\"blackmarket_response\",\"callId\":"
                + (int)command["callId"]
                + ",\"success\":true,\"observationTuple\":{"
                + "\"v\":1,\"businessOwner\":\"blackmarket.observation\","
                + "\"pauseOwner\":\"webpanel\",\"sceneOwner\":\"base_scene\","
                + "\"frameSequence\":321}}"),
                delegate(string ignored) { });

            BlackMarketObservationSnapshot completed =
                _task.CaptureObservation();
            Assert.Equal(0, completed.OutstandingCount);
            Assert.Equal(first.RouteSequence,
                completed.LastCompletedRouteSequence);
            Assert.Equal("exact", completed.As2TupleState);
            Assert.Equal("blackmarket.observation", completed.BusinessOwner);
            Assert.Equal("webpanel", completed.PauseOwner);
            Assert.Equal("base_scene", completed.SceneOwner);
            Assert.Equal(321, completed.FrameSequence);
            Assert.Empty(_posted);
        }

        [Fact]
        public void Observation_MalformedTupleFailsClosedAndRetireHasNoControlAction()
        {
            string sent = null;
            BlackMarketObservationSnapshot pending = _task.ObserveHeartbeat(
                11,
                delegate(string payload, int generation)
                {
                    sent = payload;
                    return true;
                });
            JObject command = JObject.Parse(sent.TrimEnd('\0'));
            _task.HandleFlashResponse(JObject.Parse(
                "{\"task\":\"blackmarket_response\",\"callId\":"
                + (int)command["callId"]
                + ",\"success\":true,\"observationTuple\":{"
                + "\"v\":1,\"businessOwner\":\"blackmarket.observation\","
                + "\"pauseOwner\":\"webpanel\",\"sceneOwner\":\"base_scene\","
                + "\"frameSequence\":1,\"extra\":true}}"),
                null);
            BlackMarketObservationSnapshot invalid =
                _task.CaptureObservation();
            Assert.Equal("invalid", invalid.As2TupleState);
            Assert.Equal(-1, invalid.FrameSequence);

            _task.ObserveHeartbeat(11, delegate(string payload, int generation)
            {
                return true;
            });
            _task.RetireObservation();
            BlackMarketObservationSnapshot retired =
                _task.CaptureObservation();
            Assert.Equal(0, retired.OutstandingCount);
            Assert.Equal("missing", retired.As2TupleState);
            Assert.Equal("none", retired.OutstandingOwner);
            Assert.Equal(0, retired.BusinessOutstandingCount);
            Assert.True(pending.RouteSequence > 0);
        }

        [Theory]
        [InlineData("none", "base_scene", -1, true)]
        [InlineData("shop", "stage_run", 99, true)]
        [InlineData("secret", "base_scene", 1, false)]
        [InlineData("none", "unknown_scene", 1, false)]
        [InlineData("none", "base_scene", 1.5, false)]
        public void ObservationTuple_RequiresExactBoundedOwnerSet(
            string pauseOwner,
            string sceneOwner,
            double frameSequence,
            bool expected)
        {
            var tuple = new JObject
            {
                ["v"] = 1,
                ["businessOwner"] = "blackmarket.observation",
                ["pauseOwner"] = pauseOwner,
                ["sceneOwner"] = sceneOwner,
                ["frameSequence"] = frameSequence
            };
            Assert.Equal(expected,
                BlackMarketTask.IsExactAs2ObservationTuple(tuple));
        }
    }
}
