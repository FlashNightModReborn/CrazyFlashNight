using System;
using System.Collections.Generic;
using CF7Launcher.Tasks;
using CF7Launcher.Save;
using Newtonsoft.Json.Linq;
using Xunit;

namespace Launcher.Tests.Tasks
{
    public sealed class BookshelfTaskTests
    {
        [Fact]
        public void ReturnPresentationIsAdmittedByValidatedReceiptAndKeepsRecoveryIdentity()
        {
            var sent = new List<JObject>(); var posted = new List<JObject>(); var phases = new List<string>();
            using var task = Create(sent, posted);
            task.SetReturnPresentation((instance, receipt) => { Assert.Equal("bookshelf.panel.1", instance); phases.Add(receipt.Value<string>("phase")); });
            task.HandleWebRequest("commit", Request("commit", kind:"return"));
            Assert.True(task.IsReturning); Assert.Empty(phases);
            task.HandleFlashResponse(Response(sent[0], "switching", active:"bookrun_fixture", kind:"return"), _ => { });
            Assert.Equal(new[] { "switching" }, phases); Assert.True(task.IsReturning);
            task.HandleWebRequest("query", Request("query", "call.2"));
            task.HandleFlashResponse(Response(sent[1], "applied", kind:"return"), _ => { });
            Assert.Equal(new[] { "switching", "applied" }, phases); Assert.False(task.IsReturning);
        }
        [Theory]
        [InlineData("foreign_kind")][InlineData("foreign_token")][InlineData("bad_record")]
        public void MalformedReturnCannotSuppressLoadingOrReleaseItsWriteFence(string fault)
        {
            var sent = new List<JObject>(); var posted = new List<JObject>(); int projections = 0;
            using var task = Create(sent, posted); task.SetReturnPresentation((_, _) => projections++);
            task.HandleWebRequest("commit", Request("commit", kind:"return"));
            var receipt = Response(sent[0], "switching", kind:"return");
            if (fault == "foreign_kind") receipt["kind"] = "switch";
            else if (fault == "foreign_token") receipt["token"] = "bookshelf.foreign";
            else receipt["records"] = new JObject { ["bestMs"] = -1, ["clears"] = 1, ["history"] = new JArray() };
            task.HandleFlashResponse(receipt, _ => { });
            Assert.Equal(0, projections); Assert.True(task.IsReturning);
            Assert.True(posted[0].Value<bool>("requiresReconcile"));
        }
        [Fact]
        public void HistoryIsOnlyAReadProjectionAndPendingResultCannotClaimPaidSP()
        {
            var sent = new List<JObject>(); var posted = new List<JObject>();
            using var task = Create(sent, posted);
            task.HandleWebRequest("commit", Request("commit", kind:"return"));
            var receipt = Response(sent[0], "switching", kind:"return");
            receipt["records"] = new JObject { ["bestMs"] = 600000, ["clears"] = 3, ["history"] = new JArray() };
            receipt["returningResult"] = new JObject { ["runId"] = "bookrun_fixture", ["bookId"] = "repair-campus",
                ["outcome"] = "victory", ["elapsedMs"] = 700000, ["completedAt"] = 0, ["debug"] = false,
                ["sp"] = 45, ["reason"] = "pending" };
            task.HandleFlashResponse(receipt, _ => { });
            Assert.Equal("malformed_response", posted[0].Value<string>("error")); Assert.True(task.IsReturning);
        }
        private static JObject Read(string text) => JObject.Parse(text.TrimEnd('\0'));
        private static JObject Request(string cmd, string call = "call.1", string token = "bookshelf.test.1", string kind = "switch", string target = "slot_b")
        {
            var payload = new JObject { ["v"] = 1, ["token"] = token };
            if (cmd == "commit") { payload["kind"] = kind; payload["target"] = target; }
            return new JObject { ["type"] = "panel", ["panel"] = "bookshelf", ["domain"] = "bookshelf", ["cmd"] = cmd,
                ["panelInstanceId"] = "bookshelf.panel.1", ["callId"] = call, ["payload"] = payload };
        }
        private static BookshelfTask Create(List<JObject> sent, List<JObject> posted, Func<string, SolResolveResult> resolve = null)
        {
            var task = new BookshelfTask(() => true, text => { sent.Add(Read(text)); return true; }, 10000,
                () => new JArray(new JObject { ["slot"] = "slot_b", ["name"] = "B" }),
                resolve ?? (_ => SolResolveResult.NewSnapshot(new JObject { ["version"] = "3.0" }, "sol")));
            task.SetPostToWeb(text => posted.Add(Read(text)));
            return task;
        }
        private static JObject Response(JObject wire, string phase = "applied", string active = "slot_b", string kind = "switch", string target = "slot_b")
            => new JObject { ["task"] = "bookshelf_response", ["callId"] = wire["callId"], ["v"] = 1,
                ["operation"] = wire.Value<string>("action") == "bookshelfQuery" ? "query" : "commit",
                ["token"] = wire["token"], ["phase"] = phase, ["success"] = phase != "expired" && phase != "save_pending",
                ["activeSlot"] = active, ["role"] = "B", ["inRun"] = kind == "play", ["unlocked"] = true,
                ["canSwitch"] = phase == "applied", ["kind"] = kind, ["target"] = target };

        [Theory]
        [InlineData("slot_b", true)][InlineData("cf7_a12", true)][InlineData("bookrun_test", false)]
        [InlineData("BOOKRUN_test", false)][InlineData("../slot", false)][InlineData(null, false)]
        public void PermanentCatalogRejectsInternalAndUnsafeSlots(string slot, bool valid)
            => Assert.Equal(valid, BookshelfTask.IsPermanentSlot(slot));

        [Fact]
        public void OpenRequiresExactWorldSession()
        {
            Assert.NotNull(BookshelfTask.BuildOpenData("world_bookshelf", "{\"token\":\"bookshelf.test.1\"}"));
            Assert.Null(BookshelfTask.BuildOpenData("world_sleep", "{\"token\":\"bookshelf.test.1\"}"));
            Assert.Null(BookshelfTask.BuildOpenData("world_bookshelf", "{\"token\":\"bookshelf.test.1\",\"snapshot\":{}}"));
        }
        [Fact]
        public void CanonicalSaveIsInjectedWithoutAcceptingWebSaveContent()
        {
            var sent = new List<JObject>(); var posted = new List<JObject>();
            using var task = Create(sent, posted);
            var bad = Request("commit"); bad["payload"]["snapshot"] = new JObject();
            task.HandleWebRequest("commit", bad); Assert.Empty(sent);
            task.HandleWebRequest("commit", Request("commit", "call.2"));
            Assert.Equal("3.0", sent[0]["snapshot"].Value<string>("version"));
            Assert.Equal("bookshelfCommit", sent[0].Value<string>("action"));
        }
        [Theory]
        [InlineData(DecisionKind.Empty)][InlineData(DecisionKind.Deleted)][InlineData(DecisionKind.Corrupt)]
        [InlineData(DecisionKind.Repairable)][InlineData(DecisionKind.NeedsMigration)]
        public void SwitchNeverAdoptsUnresolvedSave(DecisionKind kind)
        {
            var sent = new List<JObject>(); var posted = new List<JObject>();
            using var task = Create(sent, posted, _ => new SolResolveResult { Kind = kind, WireDecision = kind.ToString() });
            task.HandleWebRequest("commit", Request("commit")); Assert.Empty(sent);
            Assert.False(posted[0].Value<bool>("requiresReconcile"));
        }
        [Fact]
        public void MissingTemporaryResultHasExplicitRecoveryProof()
        {
            var sent = new List<JObject>(); var posted = new List<JObject>();
            using var task = Create(sent, posted, _ => SolResolveResult.NewEmpty());
            task.HandleWebRequest("commit", Request("commit", kind:"settle", target:"bookrun_missing"));
            Assert.True(sent[0].Value<bool>("missingRun")); Assert.Null(sent[0]["snapshot"]);
        }
        [Fact]
        public void PlayUsesHostGeneratedRunSlotAndDeduplicates()
        {
            var sent = new List<JObject>(); var posted = new List<JObject>();
            using var task = Create(sent, posted);
            task.HandleWebRequest("commit", Request("commit", kind:"play", target:"repair-campus"));
            task.HandleWebRequest("commit", Request("commit", kind:"play", target:"repair-campus"));
            Assert.Single(sent); Assert.StartsWith("bookrun_", sent[0].Value<string>("runSlot"));
            Assert.True(SaveSlotKey.IsValid(sent[0].Value<string>("runSlot")));
        }
        [Fact]
        public void RepeatedPlayTokenKeepsTheSamePhysicalRunIdentity()
        {
            var sent = new List<JObject>(); var posted = new List<JObject>();
            using var task = Create(sent, posted);
            task.HandleWebRequest("commit", Request("commit", kind:"play", target:"repair-campus"));
            string slot = sent[0].Value<string>("runSlot");
            task.HandleFlashResponse(Response(sent[0], active:slot, kind:"play", target:"repair-campus"), _ => { });
            task.HandleWebRequest("commit", Request("commit", "call.2", kind:"play", target:"repair-campus"));
            Assert.Equal(slot, sent[1].Value<string>("runSlot"));
        }
        [Theory]
        [InlineData("switching")][InlineData("save_pending")]
        public void AcceptedButUnfinishedSwitchKeepsLockAcrossClose(string phase)
        {
            var sent = new List<JObject>(); var posted = new List<JObject>();
            using var task = Create(sent, posted);
            task.HandleWebRequest("commit", Request("commit")); task.HandleFlashResponse(Response(sent[0],phase), _ => { });
            Assert.True(posted[0].Value<bool>("requiresReconcile")); task.ClearPending();
            task.HandleWebRequest("snapshot", Request("snapshot", "call.2", "bookshelf.new")); Assert.Single(sent);
            task.HandleWebRequest("query", Request("query", "call.3"));
            task.HandleFlashResponse(Response(sent[1]), _ => { });
            Assert.False(posted[posted.Count - 1].Value<bool>("requiresReconcile"));
        }
        [Theory]
        [InlineData("slot_c", "switch", "slot_b")][InlineData("slot_b", "return", "slot_b")]
        [InlineData("slot_b", "switch", "slot_c")]
        public void WrongSuccessfulIdentityCannotReleaseUnknownWrite(string slot, string kind, string target)
        {
            var sent = new List<JObject>(); var posted = new List<JObject>();
            using var task = Create(sent, posted);
            task.HandleWebRequest("commit", Request("commit"));
            task.HandleFlashResponse(Response(sent[0], active:slot,kind:kind,target:target), _ => { });
            Assert.Equal("malformed_response", posted[0].Value<string>("error"));
            Assert.True(posted[0].Value<bool>("requiresReconcile"));
            task.HandleWebRequest("query", Request("query", "call.2")); task.HandleFlashResponse(Response(sent[1]), _ => { });
            Assert.False(posted[1].Value<bool>("requiresReconcile"));
        }
        [Fact]
        public void LastPlayedProjectionRequiresConfirmedPermanentArrival()
        {
            var sent = new List<JObject>(); var posted = new List<JObject>(); var applied = new List<string>();
            using var task = Create(sent, posted);
            task.SetPermanentSlotApplied(applied.Add);
            task.HandleWebRequest("commit", Request("commit"));
            task.HandleFlashResponse(Response(sent[0], "switching"), _ => { }); Assert.Empty(applied);
            task.HandleWebRequest("query", Request("query", "call.2"));
            task.HandleFlashResponse(Response(sent[1]), _ => { }); Assert.Equal(new[] { "slot_b" }, applied);
            task.HandleWebRequest("commit", Request("commit", "call.3", "bookshelf.run", "play", "repair-campus"));
            task.HandleFlashResponse(Response(sent[2], active:sent[2].Value<string>("runSlot"), kind:"play", target:"repair-campus"), _ => { });
            Assert.Single(applied);
        }
        [Fact]
        public void UnknownDeliveryQueryCarriesRetirementProofAndAcceptsExactNegativeReceipt()
        {
            var sent = new List<JObject>(); var posted = new List<JObject>();
            using var task = Create(sent, posted);
            task.HandleWebRequest("commit", Request("commit")); task.ClearPending();
            task.HandleWebRequest("query", Request("query", "call.2"));
            Assert.Equal("switch", sent[1].Value<string>("reconcileKind"));
            Assert.Equal("slot_b", sent[1].Value<string>("reconcileTarget"));
            task.HandleFlashResponse(Response(sent[1], "expired", "slot_a"), _ => { });
            Assert.False(posted[0].Value<bool>("requiresReconcile"));
            task.HandleWebRequest("snapshot", Request("snapshot", "call.3", "bookshelf.new"));
            Assert.Equal(3, sent.Count);
        }
        [Fact]
        public void ClearPendingDoesNotTurnUnknownIntoNotExecuted()
        {
            var sent = new List<JObject>(); var posted = new List<JObject>();
            using var task = Create(sent, posted);
            task.HandleWebRequest("commit", Request("commit")); task.ClearPending();
            task.HandleFlashResponse(Response(sent[0]), _ => { }); Assert.Empty(posted);
            task.HandleWebRequest("commit", Request("commit", "call.2")); Assert.Single(sent);
            Assert.True(posted[0].Value<bool>("requiresReconcile"));
        }

        [Theory]
        [InlineData("\"pending\"")][InlineData("{}")] [InlineData("null")][InlineData("0")]
        public void MalformedCleanupHintCannotInterruptCanonicalOperationResponse(string hint)
        {
            var sent = new List<JObject>(); var posted = new List<JObject>();
            using var task = Create(sent, posted);
            task.HandleWebRequest("commit", Request("commit"));
            var response = Response(sent[0]); response["outcomePending"] = JToken.Parse(hint);
            task.HandleFlashResponse(response, _ => { });
            Assert.Single(posted);
            Assert.True(posted[0].Value<bool>("success"));
        }

        [Fact]
        public void SettledJourneyCanAdoptFreshEditingTokenWithoutClosingPanel()
        {
            var sent = new List<JObject>(); var posted = new List<JObject>();
            using var task = Create(sent, posted);
            task.HandleWebRequest("commit", Request("commit", kind:"settle", target:"bookrun_old"));
            var done = Response(sent[0], active:"slot_a", kind:"settle", target:"bookrun_old");
            done["nextToken"] = "bookshelf.next"; done["exitRequired"] = false;
            task.HandleFlashResponse(done, _ => { });
            Assert.False(posted[0].Value<bool>("requiresReconcile"));
            Assert.Equal("bookshelf.next", posted[0].Value<string>("nextToken"));
            task.HandleWebRequest("snapshot", Request("snapshot", "call.2", "bookshelf.next"));
            Assert.Equal("bookshelf.next", sent[1].Value<string>("token"));
            task.HandleWebRequest("commit", Request("commit", "call.3", "bookshelf.next", "play", "repair-campus"));
            Assert.Equal("bookshelfCommit", sent[2].Value<string>("action"));
        }

        [Fact]
        public void OriginalAccessRequiresExactCurrentEditingSnapshotAndIsRevokedOnWriteOrClose()
        {
            var sent = new List<JObject>(); var posted = new List<JObject>();
            using var task = Create(sent, posted);
            Assert.False(task.CanOpenOriginal("bookshelf.panel.1", "bookshelf.test.1"));
            task.HandleWebRequest("snapshot", Request("snapshot"));
            var state = Response(sent[0], "editing", kind:null, target:null);
            state["operation"] = "snapshot"; state["inRun"] = false; state["pendingRun"] = ""; state["outcomePending"] = false;
            state["canSwitch"] = true;
            task.HandleFlashResponse(state, _ => {});
            Assert.True(task.CanOpenOriginal("bookshelf.panel.1", "bookshelf.test.1"));
            Assert.False(task.CanOpenOriginal("bookshelf.other", "bookshelf.test.1"));
            Assert.False(task.CanOpenOriginal("bookshelf.panel.1", "bookshelf.old"));
            task.HandleWebRequest("commit", Request("commit", "call.2"));
            Assert.False(task.CanOpenOriginal("bookshelf.panel.1", "bookshelf.test.1"));
            task.ClearPending(); Assert.False(task.CanOpenOriginal("bookshelf.panel.1", "bookshelf.test.1"));
            Assert.True(posted.Count == 1); // no original request reached the AS2 write protocol
        }

        [Theory]
        [InlineData("inRun")][InlineData("pendingRun")][InlineData("outcomePending")][InlineData("canSwitch")]
        public void OriginalAccessCannotBypassJourneyOrContextAdmission(string blocked)
        {
            var sent = new List<JObject>(); var posted = new List<JObject>();
            using var task = Create(sent, posted);
            task.HandleWebRequest("snapshot", Request("snapshot"));
            var state = Response(sent[0], "editing", kind:null, target:null);
            state["operation"] = "snapshot"; state["inRun"] = blocked == "inRun";
            state["pendingRun"] = blocked == "pendingRun" ? "bookrun_previous" : "";
            state["outcomePending"] = blocked == "outcomePending"; state["canSwitch"] = blocked != "canSwitch";
            task.HandleFlashResponse(state, _ => {});
            Assert.False(task.CanOpenOriginal("bookshelf.panel.1", "bookshelf.test.1"));
        }

        [Theory]
        [InlineData("save_pending", "bookshelf.next")]
        [InlineData("applied", "bookshelf.test.1")]
        [InlineData("applied", "../forged")]
        public void SuccessorCannotBypassUnfinishedOrMalformedOperation(string phase, string next)
        {
            var sent = new List<JObject>(); var posted = new List<JObject>();
            using var task = Create(sent, posted);
            task.HandleWebRequest("commit", Request("commit"));
            var response = Response(sent[0],phase); response["nextToken"] = next;
            task.HandleFlashResponse(response, _ => { });
            Assert.True(posted[0].Value<bool>("requiresReconcile"));
            Assert.Equal("malformed_response",posted[0].Value<string>("error"));
        }
    }
}
