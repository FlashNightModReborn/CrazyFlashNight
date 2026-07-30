using System;
using System.Collections.Concurrent;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Threading;
using System.Threading.Tasks;
using CF7Launcher.Tasks;
using Newtonsoft.Json.Linq;
using Xunit;

namespace Launcher.Tests.Tasks
{
    public sealed class HairdresserTaskTests
    {
        private const string ExpectedHair = "发型-男式-平头";
        private const string OtherHair = "光头";

        [Theory]
        [InlineData("snapshot", "hairdresserSnapshot")]
        [InlineData("commit", "hairdresserCommit")]
        public void WebRequest_MapsOnlyFrozenCommands(string cmd, string expectedAction)
        {
            string sent = null;
            using (var task = new HairdresserTask(
                () => true,
                value =>
                {
                    sent = value;
                    return true;
                }))
            {
                task.HandleWebRequest(cmd, Request(cmd, "hair.command." + cmd));

                JObject flash = ParseSent(sent);
                Assert.Equal("cmd", (string)flash["task"]);
                Assert.Equal(expectedAction, (string)flash["action"]);
                Assert.Equal(1, (int)flash["v"]);
                Assert.True((int)flash["callId"] > 0);
                Assert.Null(flash["payload"]);
                if (cmd == "commit")
                {
                    Assert.Equal(ExpectedHair, (string)flash["hairIdentifier"]);
                    Assert.Equal(OtherHair, (string)flash["expectedCurrentHair"]);
                }
                else
                {
                    Assert.Null(flash["hairIdentifier"]);
                    Assert.Null(flash["expectedCurrentHair"]);
                }
            }
        }

        [Fact]
        public void RequestEnvelope_RejectsUnsupportedDomainAndCommand()
        {
            int sends = 0;
            var posted = new List<JObject>();
            using (var task = new HairdresserTask(
                () => true,
                _ =>
                {
                    sends++;
                    return true;
                }))
            {
                task.SetPostToWeb(value => posted.Add(JObject.Parse(value)));

                JObject wrongDomain = Request("snapshot", "hair.domain.bad");
                wrongDomain["domain"] = "crafting";
                task.HandleWebRequest("snapshot", wrongDomain);
                task.HandleWebRequest(
                    "preview",
                    Request("snapshot", "hair.command.bad"));

                Assert.Equal(0, sends);
                Assert.Equal("unsupported_domain", (string)posted[0]["error"]);
                Assert.Equal("unsupported_cmd", (string)posted[1]["error"]);
                Assert.All(posted, value => Assert.Equal("hairdresser", (string)value["domain"]));
            }
        }

        [Fact]
        public async Task AgentDomainPort_UsesSameStrictBridgeAndReturnsAuthoritativeSnapshot()
        {
            string sent = null;
            using (var task = new HairdresserTask(
                () => true,
                value =>
                {
                    sent = value;
                    return true;
                }))
            {
                Task<JObject> pending = task.ExecuteAgentRequestAsync(
                    "snapshot",
                    new JObject { ["v"] = 1 });
                JObject flash = ParseSent(sent);
                Assert.Equal("hairdresserSnapshot", (string)flash["action"]);

                task.HandleFlashResponse(
                    SnapshotResponse((int)flash["callId"], OtherHair),
                    null);
                JObject response = await pending;

                Assert.True(response.Value<bool>("success"));
                Assert.Equal(OtherHair, response.Value<string>("currentHair"));
                Assert.Equal("hairdresser", response.Value<string>("domain"));
                Assert.StartsWith(
                    "agent.hairdresser.",
                    response.Value<string>("callId"));
            }
        }

        [Fact]
        public async Task AgentDomainPort_RejectsMalformedCommitBeforeFlashDispatch()
        {
            int sends = 0;
            using (var task = new HairdresserTask(
                () => true,
                _ =>
                {
                    sends++;
                    return true;
                }))
            {
                JObject response = await task.ExecuteAgentRequestAsync(
                    "commit",
                    new JObject
                    {
                        ["v"] = 1,
                        ["hairIdentifier"] = ExpectedHair
                    });

                Assert.Equal(0, sends);
                Assert.False(response.Value<bool>("success"));
                Assert.Equal("invalid_payload", response.Value<string>("error"));
                Assert.Equal("idle", task.WriteState);
            }
        }

        [Theory]
        [InlineData("snapshot", "string-version")]
        [InlineData("snapshot", "wrong-version")]
        [InlineData("snapshot", "extra-field")]
        [InlineData("commit", "numeric-identifier")]
        [InlineData("commit", "empty-identifier")]
        [InlineData("commit", "missing-expected-current")]
        [InlineData("commit", "numeric-expected-current")]
        [InlineData("commit", "extra-field")]
        public void RequestPayload_RequiresExactV1ShapeAndStringIdentifier(
            string cmd,
            string mutation)
        {
            int sends = 0;
            string posted = null;
            using (var task = new HairdresserTask(
                () => true,
                _ =>
                {
                    sends++;
                    return true;
                }))
            {
                task.SetPostToWeb(value => posted = value);
                JObject request = Request(
                    cmd,
                    "hair.payload." + cmd + "." + mutation);
                JObject payload = (JObject)request["payload"];
                switch (mutation)
                {
                    case "string-version":
                        payload["v"] = "1";
                        break;
                    case "wrong-version":
                        payload["v"] = 2;
                        break;
                    case "numeric-identifier":
                        payload["hairIdentifier"] = 12;
                        break;
                    case "empty-identifier":
                        payload["hairIdentifier"] = "";
                        break;
                    case "missing-expected-current":
                        payload.Remove("expectedCurrentHair");
                        break;
                    case "numeric-expected-current":
                        payload["expectedCurrentHair"] = 12;
                        break;
                    case "extra-field":
                        payload["unexpected"] = true;
                        break;
                }

                task.HandleWebRequest(cmd, request);

                Assert.Equal(0, sends);
                Assert.Equal("invalid_payload", (string)JObject.Parse(posted)["error"]);
                Assert.Equal("idle", task.WriteState);
            }
        }

        [Fact]
        public void SnapshotResponse_PreservesSourceOrderAndDuplicateRows()
        {
            string sent = null;
            string posted = null;
            using (var task = NewCapturingTask(
                value => sent = value,
                value => posted = value))
            {
                task.HandleWebRequest("snapshot", Request("snapshot", "hair.snapshot.ok"));
                int fid = (int)ParseSent(sent)["callId"];

                JObject snapshot = SnapshotResponse(fid, ExpectedHair);
                snapshot["gender"] = "未知";
                task.HandleFlashResponse(snapshot, null);

                JObject response = JObject.Parse(posted);
                Assert.True((bool)response["success"]);
                Assert.Equal("未知", (string)response["gender"]);
                Assert.Equal("hairdresser", (string)response["domain"]);
                Assert.Equal("snapshot", (string)response["cmd"]);
                Assert.Equal("hair.snapshot.ok", (string)response["callId"]);
                Assert.Null(response["task"]);
                Assert.Equal(4, ((JArray)response["catalog"]).Count);
                Assert.Equal(
                    new[] { ExpectedHair, OtherHair, ExpectedHair, "发型-女式-短发" },
                    response["catalog"].Select(value => (string)value["identifier"]).ToArray());
                Assert.Equal("idle", task.WriteState);
            }
        }

        [Fact]
        public void SnapshotResponse_RejectsMalformedAuthorityShapes()
        {
            string sent = null;
            var posted = new List<JObject>();
            using (var task = NewCapturingTask(
                value => sent = value,
                value => posted.Add(JObject.Parse(value))))
            {
                var mutations = new Action<JObject>[]
                {
                    value => value["task"] = "crafting_response",
                    value => value["v"] = "1",
                    value => value["gender"] = 1,
                    value => value["face"] = 1,
                    value => value["currentHair"] = "目录外发型",
                    value => value["catalog"][0]["name"] = 3,
                    value => value["catalog"][0]["extra"] = true,
                    value => value["catalog"] = new JArray()
                };

                for (int i = 0; i < mutations.Length; i++)
                {
                    task.HandleWebRequest(
                        "snapshot",
                        Request("snapshot", "hair.snapshot.malformed." + i));
                    int fid = (int)ParseSent(sent)["callId"];
                    JObject response = SnapshotResponse(fid, ExpectedHair);
                    mutations[i](response);
                    task.HandleFlashResponse(response, null);
                }

                Assert.Equal(mutations.Length, posted.Count);
                Assert.All(
                    posted,
                    value =>
                    {
                        Assert.False((bool)value["success"]);
                        Assert.Equal("malformed_response", (string)value["error"]);
                        Assert.Null(value["requiresReconcile"]);
                    });
                Assert.Equal("idle", task.WriteState);
            }
        }

        [Fact]
        public void ReadFailure_DoesNotManufactureUnknownWriteState()
        {
            string sent = null;
            string posted = null;
            using (var task = NewCapturingTask(
                value => sent = value,
                value => posted = value))
            {
                task.HandleWebRequest("snapshot", Request("snapshot", "hair.read.failure"));
                task.HandleFlashResponse(
                    FailureResponse((int)ParseSent(sent)["callId"], "catalog_invalid"),
                    null);

                JObject response = JObject.Parse(posted);
                Assert.Equal("catalog_invalid", (string)response["error"]);
                Assert.Null(response["requiresReconcile"]);
                Assert.Equal("idle", task.WriteState);
            }
        }

        [Fact]
        public void CommitSuccess_RequiresExpectedHairAndClearsWriteGate()
        {
            string sent = null;
            string posted = null;
            using (var task = NewCapturingTask(
                value => sent = value,
                value => posted = value))
            {
                task.HandleWebRequest("commit", Request("commit", "hair.commit.ok"));
                int fid = (int)ParseSent(sent)["callId"];
                Assert.Equal("write_pending", task.WriteState);

                task.HandleFlashResponse(CommitResponse(fid, ExpectedHair), null);

                JObject response = JObject.Parse(posted);
                Assert.True((bool)response["success"]);
                Assert.Equal("commit", (string)response["operation"]);
                Assert.Equal(ExpectedHair, (string)response["currentHair"]);
                Assert.Null(response["requiresReconcile"]);
                Assert.Equal("idle", task.WriteState);
            }
        }

        [Theory]
        [InlineData("unsupported_cmd")]
        [InlineData("unsupported_version")]
        [InlineData("catalog_invalid")]
        [InlineData("pricing_unsupported")]
        [InlineData("invalid_payload")]
        [InlineData("hair_not_found")]
        [InlineData("stale_state")]
        [InlineData("actor_unavailable")]
        [InlineData("save_unavailable")]
        [InlineData("refresh_unavailable")]
        public void FrozenAs2Failures_AreDefinitiveAndZeroWrite(string error)
        {
            string sent = null;
            string posted = null;
            using (var task = NewCapturingTask(
                value => sent = value,
                value => posted = value))
            {
                task.HandleWebRequest(
                    "commit",
                    Request("commit", "hair.commit.definitive." + error));
                task.HandleFlashResponse(
                    FailureResponse((int)ParseSent(sent)["callId"], error),
                    null);

                JObject response = JObject.Parse(posted);
                Assert.Equal(error, (string)response["error"]);
                Assert.Null(response["requiresReconcile"]);
                Assert.Equal("idle", task.WriteState);
            }
        }

        [Fact]
        public void MismatchedOrMalformedCommitSuccess_EntersReconcile()
        {
            string sent = null;
            var posted = new List<JObject>();
            using (var task = NewCapturingTask(
                value => sent = value,
                value => posted.Add(JObject.Parse(value))))
            {
                task.HandleWebRequest(
                    "commit",
                    Request("commit", "hair.commit.mismatch"));
                task.HandleFlashResponse(
                    CommitResponse((int)ParseSent(sent)["callId"], OtherHair),
                    null);

                Assert.Equal("malformed_response", (string)posted[0]["error"]);
                Assert.True((bool)posted[0]["requiresReconcile"]);
                Assert.Equal("needs_reconcile", task.WriteState);
            }
        }

        [Fact]
        public void UnknownCommitFailure_EntersReconcile()
        {
            string sent = null;
            string posted = null;
            using (var task = NewCapturingTask(
                value => sent = value,
                value => posted = value))
            {
                task.HandleWebRequest(
                    "commit",
                    Request("commit", "hair.commit.unknown"));
                task.HandleFlashResponse(
                    FailureResponse(
                        (int)ParseSent(sent)["callId"],
                        "unrecognized_write_outcome"),
                    null);

                JObject response = JObject.Parse(posted);
                Assert.Equal("unrecognized_write_outcome", (string)response["error"]);
                Assert.True((bool)response["requiresReconcile"]);
                Assert.Equal("needs_reconcile", task.WriteState);
            }
        }

        [Theory]
        [InlineData("snapshot")]
        [InlineData("commit")]
        public void ClientNotReady_RejectsWithoutEnteringReconcile(string cmd)
        {
            int sends = 0;
            string posted = null;
            using (var task = new HairdresserTask(
                () => false,
                _ =>
                {
                    sends++;
                    return true;
                }))
            {
                task.SetPostToWeb(value => posted = value);

                task.HandleWebRequest(
                    cmd,
                    Request(cmd, "hair.not-ready." + cmd));

                JObject response = JObject.Parse(posted);
                Assert.Equal(0, sends);
                Assert.Equal("disconnected", (string)response["error"]);
                Assert.Null(response["requiresReconcile"]);
                Assert.Equal("idle", task.WriteState);
            }
        }

        [Theory]
        [InlineData("snapshot", false)]
        [InlineData("commit", true)]
        public void SendFailure_RequiresReconcileOnlyForWrites(
            string cmd,
            bool isWrite)
        {
            string posted = null;
            using (var task = new HairdresserTask(() => true, _ => false))
            {
                task.SetPostToWeb(value => posted = value);

                task.HandleWebRequest(
                    cmd,
                    Request(cmd, "hair.send-failure." + cmd));

                JObject response = JObject.Parse(posted);
                Assert.Equal("disconnected", (string)response["error"]);
                Assert.Equal(
                    isWrite,
                    response.Value<bool?>("requiresReconcile") == true);
                Assert.Equal(isWrite ? "needs_reconcile" : "idle", task.WriteState);
            }
        }

        [Theory]
        [InlineData("snapshot", false)]
        [InlineData("commit", true)]
        public void Timeout_RequiresReconcileOnlyForWrites(
            string cmd,
            bool isWrite)
        {
            JObject posted = null;
            using (var seen = new ManualResetEventSlim(false))
            using (var task = new HairdresserTask(() => true, _ => true, 20))
            {
                task.SetPostToWeb(value =>
                {
                    posted = JObject.Parse(value);
                    seen.Set();
                });

                task.HandleWebRequest(cmd, Request(cmd, "hair.timeout." + cmd));
                Assert.True(
                    seen.Wait(TimeSpan.FromSeconds(2)),
                    "Hairdresser timeout response was not posted.");

                Assert.Equal("timeout", (string)posted["error"]);
                Assert.Equal(
                    isWrite,
                    posted.Value<bool?>("requiresReconcile") == true);
                Assert.Equal(isWrite ? "needs_reconcile" : "idle", task.WriteState);
            }
        }

        [Fact]
        public void ActiveAndRecentDuplicateCallIds_DispatchAndRespondOnce()
        {
            var sent = new List<JObject>();
            var posted = new List<JObject>();
            using (var task = new HairdresserTask(
                () => true,
                value =>
                {
                    sent.Add(ParseSent(value));
                    return true;
                }))
            {
                task.SetPostToWeb(value => posted.Add(JObject.Parse(value)));
                JObject request = Request("snapshot", "hair.duplicate.1");

                task.HandleWebRequest("snapshot", request);
                task.HandleWebRequest("snapshot", request);
                Assert.Single(sent);

                task.HandleFlashResponse(
                    SnapshotResponse((int)sent[0]["callId"], ExpectedHair),
                    null);
                task.HandleWebRequest("snapshot", request);

                Assert.Single(sent);
                Assert.Single(posted);
            }
        }

        [Fact]
        public void DuplicateAndLateFlashResponses_PostOnce()
        {
            string sent = null;
            var posted = new List<JObject>();
            using (var task = NewCapturingTask(
                value => sent = value,
                value => posted.Add(JObject.Parse(value))))
            {
                task.HandleWebRequest(
                    "snapshot",
                    Request("snapshot", "hair.response.once"));
                int fid = (int)ParseSent(sent)["callId"];
                JObject response = SnapshotResponse(fid, ExpectedHair);

                task.HandleFlashResponse(response, null);
                task.HandleFlashResponse(response, null);

                Assert.Single(posted);
                Assert.True((bool)posted[0]["success"]);
            }
        }

        [Theory]
        [InlineData("snapshot")]
        [InlineData("commit")]
        public async Task ResponseAndTimeoutRace_HasOneWebTerminal(string cmd)
        {
            for (int i = 0; i < 8; i++)
            {
                string sent = null;
                var posted = new ConcurrentQueue<JObject>();
                using (var task = new HairdresserTask(
                    () => true,
                    value =>
                    {
                        sent = value;
                        return true;
                    },
                    25))
                {
                    task.SetPostToWeb(value => posted.Enqueue(JObject.Parse(value)));
                    task.HandleWebRequest(
                        cmd,
                        Request(cmd, "hair.race." + cmd + "." + i));
                    int fid = (int)ParseSent(sent)["callId"];

                    Task response = Task.Run(async delegate
                    {
                        await Task.Delay(25);
                        task.HandleFlashResponse(
                            cmd == "commit"
                                ? CommitResponse(fid, ExpectedHair)
                                : SnapshotResponse(fid, ExpectedHair),
                            null);
                    });
                    await response.WaitAsync(TimeSpan.FromSeconds(2));
                    await Task.Delay(60);

                    Assert.Single(posted);
                    JObject terminal = posted.Single();
                    if (terminal.Value<bool?>("success") == true)
                    {
                        Assert.Equal("idle", task.WriteState);
                    }
                    else
                    {
                        Assert.Equal("timeout", (string)terminal["error"]);
                        Assert.Equal(
                            cmd == "commit" ? "needs_reconcile" : "idle",
                            task.WriteState);
                    }
                }
            }
        }

        [Theory]
        [InlineData(false)]
        [InlineData(true)]
        public void ClearOrDispose_DrainsWriteAndLateResponseCannotReviveIt(
            bool dispose)
        {
            string sent = null;
            var posted = new List<JObject>();
            var task = NewCapturingTask(
                value => sent = value,
                value => posted.Add(JObject.Parse(value)));
            try
            {
                task.HandleWebRequest(
                    "commit",
                    Request("commit", "hair.drain." + dispose));
                int fid = (int)ParseSent(sent)["callId"];

                if (dispose) task.Dispose();
                else task.ClearPending();
                task.HandleFlashResponse(CommitResponse(fid, ExpectedHair), null);

                Assert.Equal("needs_reconcile", task.WriteState);
                Assert.Empty(posted);
            }
            finally
            {
                task.Dispose();
            }
        }

        [Theory]
        [InlineData(false)]
        [InlineData(true)]
        public async Task ClearOrDispose_CompletesAgentRequestAsDisconnected(
            bool dispose)
        {
            string sent = null;
            var task = NewCapturingTask(value => sent = value, _ => { });
            try
            {
                Task<JObject> pending = task.ExecuteAgentRequestAsync(
                    "snapshot",
                    new JObject { ["v"] = 1 });
                Assert.NotNull(sent);

                if (dispose) task.Dispose();
                else task.ClearPending();

                JObject response = await pending.WaitAsync(TimeSpan.FromSeconds(2));
                Assert.False(response.Value<bool>("success"));
                Assert.Equal("disconnected", response.Value<string>("error"));
                Assert.StartsWith(
                    "agent.hairdresser.",
                    response.Value<string>("callId"));
                Assert.Equal("idle", task.WriteState);
            }
            finally
            {
                task.Dispose();
            }
        }

        [Fact]
        public void ClearingPendingRead_DoesNotCreateUnknownWriteState()
        {
            string sent = null;
            using (var task = NewCapturingTask(value => sent = value, _ => { }))
            {
                task.HandleWebRequest(
                    "snapshot",
                    Request("snapshot", "hair.read.clear"));
                Assert.NotNull(sent);

                task.ClearPending();

                Assert.Equal("idle", task.WriteState);
            }
        }

        [Theory]
        [InlineData(ExpectedHair, true)]
        [InlineData(OtherHair, false)]
        public void CloseThenReopenSnapshot_ReconcilesWithoutLateWriteRevival(
            string currentHair,
            bool expectedApplied)
        {
            var flash = new List<JObject>();
            var posted = new List<JObject>();
            using (var task = new HairdresserTask(
                () => true,
                value =>
                {
                    flash.Add(ParseSent(value));
                    return true;
                }))
            {
                task.SetPostToWeb(value => posted.Add(JObject.Parse(value)));
                task.HandleWebRequest(
                    "commit",
                    Request("commit", "hair.close.commit." + expectedApplied));
                int lateCommitFid = (int)flash[0]["callId"];

                task.ClearPending();
                Assert.Equal("needs_reconcile", task.WriteState);
                task.HandleFlashResponse(
                    CommitResponse(lateCommitFid, ExpectedHair),
                    null);
                Assert.Empty(posted);

                task.HandleWebRequest(
                    "snapshot",
                    Request("snapshot", "hair.reopen.snapshot." + expectedApplied));
                task.HandleFlashResponse(
                    SnapshotResponse((int)flash[1]["callId"], currentHair),
                    null);

                JObject response = Assert.Single(posted);
                Assert.True((bool)response["reconciled"]);
                Assert.Equal(expectedApplied, (bool)response["writeApplied"]);
                Assert.Equal("idle", task.WriteState);
                Assert.Equal(
                    new[] { "hairdresserCommit", "hairdresserSnapshot" },
                    flash.Select(value => (string)value["action"]).ToArray());
            }
        }

        [Theory]
        [InlineData(ExpectedHair, true)]
        [InlineData(OtherHair, false)]
        public void FreshSnapshot_ReconcilesAppliedOrNotAppliedWithoutReplay(
            string currentHair,
            bool expectedApplied)
        {
            int sends = 0;
            var flash = new List<JObject>();
            var posted = new List<JObject>();
            using (var task = new HairdresserTask(
                () => true,
                value =>
                {
                    flash.Add(ParseSent(value));
                    sends++;
                    return sends != 1;
                }))
            {
                task.SetPostToWeb(value => posted.Add(JObject.Parse(value)));
                task.HandleWebRequest(
                    "commit",
                    Request("commit", "hair.reconcile.commit." + expectedApplied));
                Assert.Equal("needs_reconcile", task.WriteState);

                task.HandleWebRequest(
                    "commit",
                    Request("commit", "hair.reconcile.blocked." + expectedApplied));
                Assert.Equal("reconcile_required", (string)posted[1]["error"]);
                Assert.Single(flash);

                task.HandleWebRequest(
                    "snapshot",
                    Request("snapshot", "hair.reconcile.snapshot." + expectedApplied));
                task.HandleFlashResponse(
                    SnapshotResponse((int)flash[1]["callId"], currentHair),
                    null);

                JObject response = posted[posted.Count - 1];
                Assert.True((bool)response["success"]);
                Assert.True((bool)response["reconciled"]);
                Assert.Equal(expectedApplied, (bool)response["writeApplied"]);
                Assert.Equal("idle", task.WriteState);
                Assert.Equal(
                    new[] { "hairdresserCommit", "hairdresserSnapshot" },
                    flash.Select(value => (string)value["action"]).ToArray());
            }
        }

        [Fact]
        public void FailedOrMalformedSnapshot_DoesNotClearUnknownWrite()
        {
            int sends = 0;
            var flash = new List<JObject>();
            var posted = new List<JObject>();
            using (var task = new HairdresserTask(
                () => true,
                value =>
                {
                    flash.Add(ParseSent(value));
                    sends++;
                    return sends != 1;
                }))
            {
                task.SetPostToWeb(value => posted.Add(JObject.Parse(value)));
                task.HandleWebRequest(
                    "commit",
                    Request("commit", "hair.reconcile.failure.commit"));

                task.HandleWebRequest(
                    "snapshot",
                    Request("snapshot", "hair.reconcile.failure.read"));
                task.HandleFlashResponse(
                    FailureResponse((int)flash[1]["callId"], "catalog_invalid"),
                    null);
                Assert.Equal("needs_reconcile", task.WriteState);
                Assert.Null(posted[1]["reconciled"]);

                task.HandleWebRequest(
                    "snapshot",
                    Request("snapshot", "hair.reconcile.malformed.read"));
                JObject malformed =
                    SnapshotResponse((int)flash[2]["callId"], ExpectedHair);
                malformed["currentHair"] = "目录外发型";
                task.HandleFlashResponse(malformed, null);

                Assert.Equal("needs_reconcile", task.WriteState);
                Assert.Equal("malformed_response", (string)posted[2]["error"]);
                Assert.Null(posted[2]["reconciled"]);
            }
        }

        [Fact]
        public void SnapshotStartedBeforeUnknownCannotClearReconcile()
        {
            int sends = 0;
            var flash = new List<JObject>();
            var posted = new List<JObject>();
            using (var task = new HairdresserTask(
                () => true,
                value =>
                {
                    flash.Add(ParseSent(value));
                    sends++;
                    return sends != 2;
                }))
            {
                task.SetPostToWeb(value => posted.Add(JObject.Parse(value)));
                task.HandleWebRequest(
                    "snapshot",
                    Request("snapshot", "hair.stale.snapshot"));
                task.HandleWebRequest(
                    "commit",
                    Request("commit", "hair.stale.commit"));
                Assert.Equal("needs_reconcile", task.WriteState);

                task.HandleFlashResponse(
                    SnapshotResponse((int)flash[0]["callId"], ExpectedHair),
                    null);
                Assert.Equal("needs_reconcile", task.WriteState);
                Assert.Null(posted[1]["reconciled"]);

                task.HandleWebRequest(
                    "snapshot",
                    Request("snapshot", "hair.fresh.snapshot"));
                task.HandleFlashResponse(
                    SnapshotResponse((int)flash[2]["callId"], ExpectedHair),
                    null);

                Assert.Equal("idle", task.WriteState);
                Assert.True((bool)posted[2]["reconciled"]);
                Assert.True((bool)posted[2]["writeApplied"]);
            }
        }

        [Fact]
        public void SourceShape_ComposesSharedTrackerWithoutPrivatePendingMux()
        {
            string source = File.ReadAllText(FindTaskSource());

            Assert.Contains("PanelPendingCallTracker<PendingRequest>", source);
            Assert.Contains("PanelBridge.BuildFlashCommand", source);
            Assert.DoesNotContain("Dictionary<", source);
            Assert.DoesNotContain("new Timer", source);
            Assert.DoesNotContain("System.Threading.Timer", source);
            Assert.DoesNotContain("++_sequence", source);
            Assert.DoesNotContain("++_seq", source);
            Assert.DoesNotContain("Dictionary<int", source);
            Assert.Equal(
                1,
                CountOccurrences(
                    source,
                    "new PanelPendingCallTracker<PendingRequest>("));
        }

        private static HairdresserTask NewCapturingTask(
            Action<string> onSend,
            Action<string> onPost)
        {
            var task = new HairdresserTask(
                () => true,
                value =>
                {
                    onSend(value);
                    return true;
                });
            task.SetPostToWeb(onPost);
            return task;
        }

        private static JObject Request(
            string cmd,
            string callId,
            string hairIdentifier = ExpectedHair,
            string expectedCurrentHair = OtherHair)
        {
            var payload = new JObject { ["v"] = 1 };
            if (cmd == "commit")
            {
                payload["hairIdentifier"] = hairIdentifier;
                payload["expectedCurrentHair"] = expectedCurrentHair;
            }
            return new JObject
            {
                ["type"] = "panel",
                ["panel"] = "hairdresser",
                ["domain"] = "hairdresser",
                ["cmd"] = cmd,
                ["callId"] = callId,
                ["payload"] = payload
            };
        }

        private static JObject SnapshotResponse(int fid, string currentHair)
        {
            return new JObject
            {
                ["task"] = "hairdresser_response",
                ["callId"] = fid,
                ["success"] = true,
                ["v"] = 1,
                ["gender"] = "男",
                ["face"] = "脸型-男-默认",
                ["currentHair"] = currentHair,
                ["catalog"] = new JArray
                {
                    new JObject
                    {
                        ["identifier"] = ExpectedHair,
                        ["name"] = "男式平头"
                    },
                    new JObject
                    {
                        ["identifier"] = OtherHair,
                        ["name"] = "光头"
                    },
                    new JObject
                    {
                        ["identifier"] = ExpectedHair,
                        ["name"] = "男式平头（源重复行）"
                    },
                    new JObject
                    {
                        ["identifier"] = "发型-女式-短发",
                        ["name"] = "女式短发"
                    }
                }
            };
        }

        private static JObject CommitResponse(int fid, string currentHair)
        {
            return new JObject
            {
                ["task"] = "hairdresser_response",
                ["callId"] = fid,
                ["success"] = true,
                ["v"] = 1,
                ["operation"] = "commit",
                ["currentHair"] = currentHair
            };
        }

        private static JObject FailureResponse(int fid, string error)
        {
            return new JObject
            {
                ["task"] = "hairdresser_response",
                ["callId"] = fid,
                ["success"] = false,
                ["error"] = error
            };
        }

        private static JObject ParseSent(string value)
        {
            Assert.False(string.IsNullOrEmpty(value));
            return JObject.Parse(value.TrimEnd('\0'));
        }

        private static int CountOccurrences(string source, string value)
        {
            int count = 0;
            int offset = 0;
            while ((offset = source.IndexOf(value, offset, StringComparison.Ordinal)) >= 0)
            {
                count++;
                offset += value.Length;
            }
            return count;
        }

        private static string FindTaskSource()
        {
            DirectoryInfo current = new DirectoryInfo(AppContext.BaseDirectory);
            while (current != null)
            {
                string fromRepository = Path.Combine(
                    current.FullName,
                    "launcher",
                    "src",
                    "Tasks",
                    "HairdresserTask.cs");
                if (File.Exists(fromRepository)) return fromRepository;

                string fromLauncher = Path.Combine(
                    current.FullName,
                    "src",
                    "Tasks",
                    "HairdresserTask.cs");
                if (File.Exists(fromLauncher)) return fromLauncher;

                current = current.Parent;
            }
            throw new FileNotFoundException(
                "Unable to locate launcher/src/Tasks/HairdresserTask.cs.");
        }
    }
}
