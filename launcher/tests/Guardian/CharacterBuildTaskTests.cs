using System;
using System.Collections;
using System.Collections.Generic;
using System.Reflection;
using System.Threading;
using System.Threading.Tasks;
using CF7Launcher.Guardian;
using Newtonsoft.Json;
using Newtonsoft.Json.Linq;
using Xunit;

namespace CF7Launcher.Tests.Guardian
{
    public sealed class CharacterBuildTaskTests
    {
        private const string Panel = "panel.workbench.build.1";
        private const long Generation = 7;
        private const long InitialDrugRevision = 11;

        private sealed class AcceptedCall
        {
            public int BackendCallId;
            public string WebCallId;
            public string Command;
            public int WriteEpoch;
        }

        private sealed class ProductionHarness : IDisposable
        {
            public readonly List<JObject> Flash = new List<JObject>();
            public readonly List<JObject> Web = new List<JObject>();
            public readonly CharacterBuildTask Task;
            public bool Ready = true;
            public bool SendSucceeds = true;

            public ProductionHarness(int timeoutMs = 1000)
            {
                Task = new CharacterBuildTask(
                    delegate { return Ready; },
                    delegate(string payload)
                    {
                        Flash.Add(JObject.Parse(payload.TrimEnd('\0')));
                        return SendSucceeds;
                    },
                    timeoutMs);
                Task.SetPostToWeb(delegate(string payload)
                {
                    Web.Add(JObject.Parse(payload));
                });
                Assert.True(Task.TryBindPanelInstance(Panel));
            }

            public void Dispose() { Task.Dispose(); }
        }

        private sealed class RecoveryHarness : IDisposable
        {
            public readonly List<JObject> GenericFlash =
                new List<JObject>();
            public readonly List<JObject> RecoveryFlash =
                new List<JObject>();
            public readonly List<int> RecoveryGenerations =
                new List<int>();
            public readonly List<int> ForcedGenerations =
                new List<int>();
            public readonly List<string> BlockedFailures =
                new List<string>();
            public readonly List<JObject> Web =
                new List<JObject>();
            public readonly CharacterBuildTask Task;
            public int ReadyGeneration = 31;
            public bool RecoverySendSucceeds = true;

            public RecoveryHarness(
                int timeoutMs = 1000)
            {
                Task = new CharacterBuildTask(
                    delegate
                    {
                        return ReadyGeneration > 0;
                    },
                    delegate(string payload)
                    {
                        GenericFlash.Add(
                            JObject.Parse(
                                payload.TrimEnd('\0')));
                        return true;
                    },
                    timeoutMs,
                    delegate { return ReadyGeneration; },
                    delegate(
                        string payload,
                        int generation)
                    {
                        RecoveryGenerations.Add(
                            generation);
                        RecoveryFlash.Add(
                            JObject.Parse(
                                payload.TrimEnd('\0')));
                        return RecoverySendSucceeds;
                    },
                    delegate(int generation)
                    {
                        ForcedGenerations.Add(
                            generation);
                        if (ReadyGeneration == generation)
                            ReadyGeneration = 0;
                        return true;
                    });
                Task.SetPostToWeb(delegate(string payload)
                {
                    Web.Add(JObject.Parse(payload));
                });
                Task.SetDetachRecoveryBlocked(
                    delegate(string status, string failure)
                    {
                        BlockedFailures.Add(
                            status + ":" + failure);
                    });
                Assert.True(
                    Task.TryBindPanelInstance(Panel));
            }

            public void OpenKnownSession()
            {
                Task.HandleWebRequest(
                    "snapshot",
                    WebRequest(
                        "snapshot",
                        "recovery.fixture.initial",
                        new JObject { ["v"] = 1 }));
                JObject request =
                    Assert.Single(GenericFlash);
                Task.HandleFlashResponse(
                    SuccessResponse(
                        request,
                        "snapshot",
                        Generation,
                        3,
                        3,
                        InitialDrugRevision,
                        false),
                    null);
                Assert.Equal(
                    Generation,
                    Task.SessionGeneration);
                GenericFlash.Clear();
                Web.Clear();
            }

            public void Dispose() { Task.Dispose(); }
        }

        [Fact]
        public void InitialSnapshotBindsGenerationAndSubsequentCallsRequireExactPair()
        {
            using (var task = NewTask())
            {
                Assert.True(task.BindPanelInstance(Panel));
                AcceptedCall initial = Begin(
                    task, Panel, null, "build.initial.1", "snapshot");
                CompleteSuccess(
                    task, initial, Panel, Generation, 3, 3, InitialDrugRevision, false);
                Assert.Equal(Generation, task.SessionGeneration);
                Assert.Equal(InitialDrugRevision, task.DrugRevision);

                AssertBeginFails(
                    task, Panel, null, "build.missing.1", "candidates",
                    null, "session_generation_required");
                AssertBeginFails(
                    task, Panel, Generation - 1, "build.stale.1", "candidates",
                    null, "session_generation_expired");

                AcceptedCall exact = Begin(
                    task, Panel, Generation, "build.exact.1", "candidates");
                CompleteKnownFailure(
                    task, exact, Panel, Generation, "stale_state");
                Assert.Equal("idle", task.WriteState);
            }
        }

        [Fact]
        public void BoundAndAcceptedSnapshotLogsExposeOnlyFixedScalarEvidence()
        {
            var logs = new List<string>();
            var logGate = new object();
            LogManager.SetSink(
                delegate(string message)
                {
                    lock (logGate)
                        logs.Add(message);
                });
            try
            {
                using (var task = NewTask())
                {
                    Assert.True(
                        task.TryBindPanelInstance(
                            Panel));
                    AcceptedCall initial = Begin(
                        task,
                        Panel,
                        null,
                        "build.log.initial",
                        "snapshot");
                    CompleteSuccess(
                        task,
                        initial,
                        Panel,
                        Generation,
                        3,
                        3,
                        InitialDrugRevision,
                        false);
                    AcceptedCall subsequent = Begin(
                        task,
                        Panel,
                        Generation,
                        "build.log.subsequent",
                        "snapshot");
                    CompleteSuccess(
                        task,
                        subsequent,
                        Panel,
                        Generation,
                        4,
                        4,
                        InitialDrugRevision + 1,
                        false);
                }
            }
            finally
            {
                LogManager.ResetSink();
            }

            string bound;
            string initialLog;
            string subsequentLog;
            lock (logGate)
            {
                bound = Assert.Single(
                    logs.FindAll(
                        value => value.StartsWith(
                            "event=character_build_panel_bound ",
                            StringComparison.Ordinal)
                            && value.Contains(
                                "panelInstanceId=" + Panel)));
                initialLog = Assert.Single(
                    logs.FindAll(
                        value => value.Contains(
                            "event=character_build_snapshot_accepted phase=initial")
                            && value.Contains(
                                "panelInstanceId=" + Panel)));
                subsequentLog = Assert.Single(
                    logs.FindAll(
                        value => value.Contains(
                            "event=character_build_snapshot_accepted phase=subsequent")
                            && value.Contains(
                                "panelInstanceId=" + Panel)));
            }
            Assert.Contains(
                "panelInstanceId=" + Panel,
                bound);
            Assert.Contains(
                "panelInstanceId=" + Panel,
                initialLog);
            Assert.Contains(
                "sessionGeneration=7",
                initialLog);
            Assert.Contains(
                "loadoutRevision=3 liveRevision=3 drugRevision=11",
                initialLog);
            Assert.Contains(
                "panelInstanceId=" + Panel,
                subsequentLog);
            Assert.Contains(
                "sessionGeneration=7",
                subsequentLog);
            Assert.Contains(
                "loadoutRevision=4 liveRevision=4 drugRevision=12",
                subsequentLog);
            Assert.DoesNotContain(
                "payload",
                initialLog);
            Assert.DoesNotContain(
                "equipment",
                subsequentLog);
        }

        [Fact]
        public void InitialDefinitiveFailureAllowsZeroOrMissingGeneration()
        {
            using (var zero = NewTask())
            {
                Assert.True(zero.BindPanelInstance(Panel));
                AcceptedCall initial = Begin(
                    zero, Panel, null, "build.initial.zero", "snapshot");
                CompleteKnownFailure(
                    zero, initial, Panel, 0, "service_not_ready");
                Assert.Null(zero.SessionGeneration);
                Assert.Equal("idle", zero.WriteState);
                Assert.Equal(0, zero.PendingCount);
            }

            using (var missing = NewTask())
            {
                Assert.True(missing.BindPanelInstance(Panel));
                AcceptedCall initial = Begin(
                    missing, Panel, null, "build.initial.missing", "snapshot");
                CompleteKnownFailure(
                    missing, initial, Panel, null, "invalid_loadout");
                Assert.Null(missing.SessionGeneration);
                Assert.Equal("idle", missing.WriteState);
                Assert.Equal(0, missing.PendingCount);
            }
        }

        [Fact]
        public void BrowserPreAcceptNotSentNeverEntersTrackerOrAdvancesEpoch()
        {
            using (var task = BoundTask())
            {
                Assert.True(task.TryClassifyBrowserPreAcceptNotSent(
                    Panel,
                    Generation,
                    "build.browser.not-sent.1",
                    "equipEquipment",
                    out string error));
                Assert.Equal("not_sent", error);
                Assert.Equal("idle", task.WriteState);
                Assert.Equal(0, task.WriteEpoch);
                Assert.Equal(0, task.PendingCount);
            }
        }

        [Fact]
        public void AcceptedSendFailureTimeoutAndDisconnectBecomeUnknown()
        {
            bool send = true;
            using (var deliveryUnknown = BoundTask(_ => send))
            {
                send = false;
                Begin(
                    deliveryUnknown,
                    Panel,
                    Generation,
                    "build.delivery-unknown.1",
                    "equipEquipment");
                Assert.Equal("needs_reconcile", deliveryUnknown.WriteState);
                Assert.Equal(1, deliveryUnknown.WriteEpoch);
                Assert.Equal(
                    "build.delivery-unknown.1",
                    deliveryUnknown.ReconcileAfterCallId);
            }

            using (var timed = BoundTask(_ => true, 20))
            {
                Begin(
                    timed, Panel, Generation, "build.timeout.1", "equipDrug");
                Assert.True(SpinWait.SpinUntil(
                    () => timed.WriteState == "needs_reconcile", 2000));
                Assert.Equal("build.timeout.1", timed.ReconcileAfterCallId);
            }

            using (var detached = BoundTask())
            {
                Begin(
                    detached,
                    Panel,
                    Generation,
                    "build.disconnect.1",
                    "unequipEquipment");
                detached.HandleDisconnect();
                Assert.Equal("needs_reconcile", detached.WriteState);
                Assert.Equal("build.disconnect.1", detached.ReconcileAfterCallId);
            }
        }

        [Fact]
        public async Task RebindEpochKeepsTakenOldCompletionOutOfReplacementAccounting()
        {
            using (var task = BoundTask(timeoutMs: 10000))
            {
                AcceptedCall oldWrite = Begin(
                    task,
                    Panel,
                    Generation,
                    "build.old.taken",
                    "equipEquipment");
                object stateGate = GetPrivateField(task, "_gate");
                Task completionTask = null;
                bool completionResult = true;
                string completionError = null;
                AcceptedCall replacementInitial = null;
                const string replacement = "panel.workbench.build.2";

                lock (stateGate)
                {
                    completionTask = Task.Run(delegate
                    {
                        completionResult = task.TryCompleteSuccess(
                            oldWrite.BackendCallId,
                            Panel,
                            Generation,
                            oldWrite.WebCallId,
                            oldWrite.Command,
                            oldWrite.WriteEpoch,
                            4,
                            3,
                            InitialDrugRevision,
                            true,
                            true,
                            null,
                            null,
                            out string localError);
                        completionError = localError;
                    });
                    Assert.True(SpinWait.SpinUntil(
                        () => GetTrackerPendingCount(task) == 0, 2000));

                    Assert.True(task.BindPanelInstance(replacement));
                    replacementInitial = Begin(
                        task,
                        replacement,
                        null,
                        "build.replacement.initial",
                        "snapshot");
                }

                await completionTask.WaitAsync(TimeSpan.FromSeconds(2));
                Assert.False(completionResult);
                Assert.Equal("stale_session", completionError);
                Assert.Equal(1, task.PendingCount);
                Assert.Equal("idle", task.WriteState);
                Assert.Null(task.ReconcileAfterCallId);

                CompleteSuccess(
                    task,
                    replacementInitial,
                    replacement,
                    Generation + 1,
                    5,
                    5,
                    InitialDrugRevision + 1,
                    false);
                Assert.Equal(Generation + 1, task.SessionGeneration);
            }
        }

        [Theory]
        [InlineData("snapshot", 4, 4, true)]
        [InlineData("statsSnapshot", 4, 4, true)]
        [InlineData("snapshot", 4, 3, false)]
        [InlineData("snapshot", 4, 5, true)]
        public void SnapshotShapeRequiresDirtyExactlyWhenLoadoutAndLiveDiverge(
            string command,
            long loadoutRevision,
            long liveRevision,
            bool dirty)
        {
            using (var task = BoundTask())
            {
                AcceptedCall read = Begin(
                    task, Panel, Generation, "build.shape." + command, command);
                Assert.False(task.TryCompleteSuccess(
                    read.BackendCallId,
                    Panel,
                    Generation,
                    read.WebCallId,
                    read.Command,
                    read.WriteEpoch,
                    loadoutRevision,
                    liveRevision,
                    InitialDrugRevision,
                    dirty,
                    true,
                    null,
                    null,
                    out string error));
                Assert.Equal("malformed_response", error);
                Assert.Equal(3, task.LoadoutRevision);
                Assert.Equal(3, task.LiveRevision);
                Assert.Equal(InitialDrugRevision, task.DrugRevision);
            }
        }

        [Fact]
        public void ConcurrentReadResponsesCannotRollBackAnyRevision()
        {
            using (var task = BoundTask())
            {
                AcceptedCall slow = Begin(
                    task, Panel, Generation, "build.snapshot.slow", "snapshot");
                AcceptedCall fast = Begin(
                    task, Panel, Generation, "build.snapshot.fast", "snapshot");

                CompleteSuccess(
                    task, fast, Panel, Generation, 10, 9, 20, true);
                Assert.False(task.TryCompleteSuccess(
                    slow.BackendCallId,
                    Panel,
                    Generation,
                    slow.WebCallId,
                    slow.Command,
                    slow.WriteEpoch,
                    4,
                    4,
                    12,
                    false,
                    true,
                    null,
                    null,
                    out string error));
                Assert.Equal("stale_snapshot", error);
                Assert.Equal(10, task.LoadoutRevision);
                Assert.Equal(9, task.LiveRevision);
                Assert.Equal(20, task.DrugRevision);
                Assert.True(task.LiveRefreshDirty);
            }
        }

        [Fact]
        public void WriteResponseBelowAcceptedOrCurrentBaselineNeedsReconcile()
        {
            using (var task = BoundTask())
            {
                AcceptedCall write = Begin(
                    task,
                    Panel,
                    Generation,
                    "build.write.rollback",
                    "equipEquipment");
                Assert.False(task.TryCompleteSuccess(
                    write.BackendCallId,
                    Panel,
                    Generation,
                    write.WebCallId,
                    write.Command,
                    write.WriteEpoch,
                    2,
                    2,
                    InitialDrugRevision,
                    false,
                    true,
                    null,
                    null,
                    out string error));
                Assert.Equal("needs_reconcile", error);
                Assert.Equal("needs_reconcile", task.WriteState);
                Assert.Equal("build.write.rollback", task.ReconcileAfterCallId);
                Assert.Equal(3, task.LoadoutRevision);
            }
        }

        [Fact]
        public void EquipmentAndDrugMutationsRequireTheirOwnRevisionToAdvance()
        {
            using (var equipment = BoundTask())
            {
                AcceptedCall write = Begin(
                    equipment,
                    Panel,
                    Generation,
                    "build.equipment.no-advance",
                    "equipEquipment");
                Assert.False(equipment.TryCompleteSuccess(
                    write.BackendCallId,
                    Panel,
                    Generation,
                    write.WebCallId,
                    write.Command,
                    write.WriteEpoch,
                    3,
                    3,
                    InitialDrugRevision + 1,
                    false,
                    true,
                    null,
                    null,
                    out string error));
                Assert.Equal("needs_reconcile", error);
                Assert.Equal("needs_reconcile", equipment.WriteState);
            }

            using (var drug = BoundTask())
            {
                AcceptedCall write = Begin(
                    drug,
                    Panel,
                    Generation,
                    "build.drug.no-advance",
                    "equipDrug");
                Assert.False(drug.TryCompleteSuccess(
                    write.BackendCallId,
                    Panel,
                    Generation,
                    write.WebCallId,
                    write.Command,
                    write.WriteEpoch,
                    4,
                    3,
                    InitialDrugRevision,
                    true,
                    true,
                    null,
                    null,
                    out string error));
                Assert.Equal("needs_reconcile", error);
                Assert.Equal("needs_reconcile", drug.WriteState);
            }

            using (var successful = BoundTask())
            {
                AcceptedCall equipmentWrite = Begin(
                    successful,
                    Panel,
                    Generation,
                    "build.equipment.advance",
                    "equipEquipment");
                CompleteSuccess(
                    successful,
                    equipmentWrite,
                    Panel,
                    Generation,
                    4,
                    3,
                    InitialDrugRevision,
                    true);
                Assert.Equal("idle", successful.WriteState);

                AcceptedCall drugWrite = Begin(
                    successful,
                    Panel,
                    Generation,
                    "build.drug.advance",
                    "equipDrug");
                CompleteSuccess(
                    successful,
                    drugWrite,
                    Panel,
                    Generation,
                    4,
                    3,
                    InitialDrugRevision + 1,
                    true);
                Assert.Equal("idle", successful.WriteState);
                Assert.Equal(4, successful.LoadoutRevision);
                Assert.Equal(InitialDrugRevision + 1, successful.DrugRevision);
            }
        }

        [Fact]
        public void FreshPostWatermarkSnapshotReconcilesUnknownMutation()
        {
            bool send = true;
            using (var task = BoundTask(_ => send))
            {
                send = false;
                Begin(
                    task,
                    Panel,
                    Generation,
                    "build.mutation.unknown",
                    "equipEquipment");
                send = true;

                AcceptedCall reconcile = Begin(
                    task,
                    Panel,
                    Generation,
                    "build.mutation.reconcile",
                    "snapshot",
                    "build.mutation.unknown");
                CompleteSuccess(
                    task,
                    reconcile,
                    Panel,
                    Generation,
                    4,
                    3,
                    InitialDrugRevision,
                    true);
                Assert.Equal("idle", task.WriteState);
                Assert.Null(task.ReconcileAfterCallId);
                Assert.True(task.LiveRefreshDirty);
            }
        }

        [Fact]
        public void UnknownFlushRejectsOldCleanProofAfterNewerDirtySnapshot()
        {
            bool send = true;
            using (var task = BoundTask(_ => send))
            {
                send = false;
                Begin(
                    task, Panel, Generation, "build.flush.unknown", "flushLive");
                send = true;

                AcceptedCall dirty = Begin(
                    task,
                    Panel,
                    Generation,
                    "build.flush.dirty-proof",
                    "snapshot",
                    "build.flush.unknown");
                CompleteSuccess(
                    task, dirty, Panel, Generation, 8, 7, 12, true);
                Assert.Equal("needs_reconcile", task.WriteState);

                AcceptedCall oldClean = Begin(
                    task,
                    Panel,
                    Generation,
                    "build.flush.old-clean",
                    "snapshot",
                    "build.flush.unknown");
                Assert.False(task.TryCompleteSuccess(
                    oldClean.BackendCallId,
                    Panel,
                    Generation,
                    oldClean.WebCallId,
                    oldClean.Command,
                    oldClean.WriteEpoch,
                    3,
                    3,
                    InitialDrugRevision,
                    false,
                    true,
                    null,
                    null,
                    out string staleError));
                Assert.Equal("stale_snapshot", staleError);
                Assert.Equal("needs_reconcile", task.WriteState);
                Assert.Equal(8, task.LoadoutRevision);
                Assert.Equal(7, task.LiveRevision);
                Assert.Equal(12, task.DrugRevision);

                AcceptedCall freshClean = Begin(
                    task,
                    Panel,
                    Generation,
                    "build.flush.fresh-clean",
                    "snapshot",
                    "build.flush.unknown");
                CompleteSuccess(
                    task, freshClean, Panel, Generation, 8, 8, 12, false);
                Assert.Equal("idle", task.WriteState);
                Assert.False(task.LiveRefreshDirty);
            }
        }

        [Fact]
        public void NeedsReconcileFailureKeepsOriginalAcceptedCallWatermark()
        {
            using (var task = BoundTask())
            {
                AcceptedCall write = Begin(
                    task,
                    Panel,
                    Generation,
                    "build.failure.needs-reconcile",
                    "equipEquipment");
                CompleteKnownFailure(
                    task,
                    write,
                    Panel,
                    Generation,
                    "needs_reconcile",
                    4,
                    3,
                    InitialDrugRevision,
                    true);
                Assert.Equal("needs_reconcile", task.WriteState);
                Assert.Equal(
                    "build.failure.needs-reconcile",
                    task.ReconcileAfterCallId);
                Assert.Equal(4, task.LoadoutRevision);
                Assert.Equal(3, task.LiveRevision);
            }
        }

        [Fact]
        public void FlushFailedMayCarryFreshCleanLiveStateAndRemainRetryable()
        {
            using (var task = BoundTask())
            {
                AcceptedCall dirtySnapshot = Begin(
                    task,
                    Panel,
                    Generation,
                    "build.flush-failed.dirty",
                    "snapshot");
                CompleteSuccess(
                    task,
                    dirtySnapshot,
                    Panel,
                    Generation,
                    4,
                    3,
                    InitialDrugRevision,
                    true);

                AcceptedCall failed = Begin(
                    task,
                    Panel,
                    Generation,
                    "build.flush-failed.response",
                    "flushLive");
                CompleteKnownFailure(
                    task,
                    failed,
                    Panel,
                    Generation,
                    "flush_failed",
                    4,
                    4,
                    InitialDrugRevision,
                    false);
                Assert.Equal("flush_failed", task.WriteState);
                Assert.False(task.LiveRefreshDirty);
                Assert.Equal(4, task.LiveRevision);
                Assert.False(task.CanClose);

                AcceptedCall retry = Begin(
                    task,
                    Panel,
                    Generation,
                    "build.flush-failed.retry",
                    "flushLive");
                CompleteSuccess(
                    task,
                    retry,
                    Panel,
                    Generation,
                    4,
                    4,
                    InitialDrugRevision,
                    false);
                Assert.Equal("idle", task.WriteState);
                Assert.False(task.CanClose);
            }
        }

        [Fact]
        public void FinalizeRequiresExactProofThenBecomesTerminalUntilClose()
        {
            using (var task = BoundTask())
            {
                AcceptedCall finalize = Begin(
                    task,
                    Panel,
                    Generation,
                    "build.finalize.proven",
                    "finalize");
                CompleteSuccess(
                    task,
                    finalize,
                    Panel,
                    Generation,
                    3,
                    3,
                    InitialDrugRevision,
                    false);
                Assert.Equal("finalized", task.WriteState);
                Assert.True(task.CanClose);

                AssertBeginFails(
                    task,
                    Panel,
                    Generation,
                    "build.finalized.read",
                    "snapshot",
                    null,
                    "session_finalized");
                AssertBeginFails(
                    task,
                    Panel,
                    Generation,
                    "build.finalized.write",
                    "equipDrug",
                    null,
                    "session_finalized");

                Assert.True(task.TryClosePanelInstance(Panel));
                Assert.Null(task.PanelInstanceId);
                Assert.Null(task.SessionGeneration);
                Assert.Equal("idle", task.WriteState);
                Assert.Equal(0, task.DrugRevision);
                Assert.False(task.CanClose);

                Assert.True(task.BindPanelInstance(Panel));
                AcceptedCall reopened = Begin(
                    task, Panel, null, "build.after-close.initial", "snapshot");
                CompleteSuccess(
                    task,
                    reopened,
                    Panel,
                    Generation + 1,
                    5,
                    5,
                    InitialDrugRevision + 1,
                    false);
                Assert.Equal(Generation + 1, task.SessionGeneration);
                Assert.Equal("idle", task.WriteState);
            }
        }

        [Fact]
        public void RebindToDifferentPanelResetsFinalizedTerminal()
        {
            using (var task = BoundTask())
            {
                AcceptedCall finalize = Begin(
                    task,
                    Panel,
                    Generation,
                    "build.finalize.before-rebind",
                    "finalize");
                CompleteSuccess(
                    task,
                    finalize,
                    Panel,
                    Generation,
                    3,
                    3,
                    InitialDrugRevision,
                    false);
                Assert.True(task.CanClose);

                const string replacement = "panel.workbench.build.rebound";
                Assert.True(task.BindPanelInstance(replacement));
                Assert.Equal("idle", task.WriteState);
                Assert.Null(task.SessionGeneration);
                Assert.False(task.CanClose);

                AcceptedCall initial = Begin(
                    task,
                    replacement,
                    null,
                    "build.rebound.initial",
                    "snapshot");
                CompleteSuccess(
                    task,
                    initial,
                    replacement,
                    Generation + 1,
                    6,
                    6,
                    InitialDrugRevision + 1,
                    false);
                Assert.Equal(Generation + 1, task.SessionGeneration);
            }
        }

        [Fact]
        public void ProductionBindCannotReplaceFinalizedAuthorityBeforeAcknowledgedClose()
        {
            using (var task = BoundTask())
            {
                AcceptedCall finalize = Begin(
                    task,
                    Panel,
                    Generation,
                    "build.finalize.production-rebind",
                    "finalize");
                CompleteSuccess(
                    task,
                    finalize,
                    Panel,
                    Generation,
                    3,
                    3,
                    InitialDrugRevision,
                    false);
                Assert.True(task.CanRebind);

                const string replacement =
                    "panel.workbench.build.production-rebound";
                Assert.False(
                    task.TryBindPanelInstance(replacement));
                Assert.True(task.IsBoundTo(Panel));
                Assert.Equal(
                    "finalized",
                    task.WriteState);
            }
        }

        [Theory]
        [InlineData(true, true, true)]
        [InlineData(false, false, true)]
        [InlineData(false, true, false)]
        public void FinalizeRejectsMissingClosedInactiveOrPersistenceProof(
            bool active,
            bool closed,
            bool persistence)
        {
            using (var task = BoundTask())
            {
                AcceptedCall finalize = Begin(
                    task,
                    Panel,
                    Generation,
                    "build.finalize.bad-envelope."
                        + active + "." + closed + "." + persistence,
                    "finalize");
                Assert.False(task.TryCompleteSuccess(
                    finalize.BackendCallId,
                    Panel,
                    Generation,
                    finalize.WebCallId,
                    finalize.Command,
                    finalize.WriteEpoch,
                    3,
                    3,
                    InitialDrugRevision,
                    false,
                    active,
                    closed,
                    persistence,
                    out string error));
                Assert.Equal("malformed_response", error);
                Assert.Equal("needs_reconcile", task.WriteState);
                Assert.False(task.CanClose);
            }
        }

        [Theory]
        [InlineData(2, 2)]
        [InlineData(4, 4)]
        public void FinalizeAtLowerOrDifferentLoadoutRevisionNeedsReconcile(
            long loadoutRevision,
            long liveRevision)
        {
            using (var task = BoundTask())
            {
                AcceptedCall finalize = Begin(
                    task,
                    Panel,
                    Generation,
                    "build.finalize.wrong-revision." + loadoutRevision,
                    "finalize");
                Assert.False(task.TryCompleteSuccess(
                    finalize.BackendCallId,
                    Panel,
                    Generation,
                    finalize.WebCallId,
                    finalize.Command,
                    finalize.WriteEpoch,
                    loadoutRevision,
                    liveRevision,
                    InitialDrugRevision,
                    false,
                    false,
                    true,
                    true,
                    out string error));
                Assert.Equal("needs_reconcile", error);
                Assert.Equal("needs_reconcile", task.WriteState);
                Assert.Equal(
                    finalize.WebCallId,
                    task.ReconcileAfterCallId);
                Assert.False(task.CanClose);
            }
        }

        [Fact]
        public void UnknownFinalizeNeedsExplicitSameGenerationRetryAndExactFreshProof()
        {
            bool send = true;
            using (var task = BoundTask(_ => send))
            {
                send = false;
                Begin(
                    task,
                    Panel,
                    Generation,
                    "build.finalize.unknown",
                    "finalize");
                send = true;

                AcceptedCall snapshot = Begin(
                    task,
                    Panel,
                    Generation,
                    "build.finalize.clean-observation",
                    "snapshot",
                    "build.finalize.unknown");
                CompleteSuccess(
                    task, snapshot, Panel, Generation, 6, 6, 12, false);
                Assert.Equal("needs_reconcile", task.WriteState);
                Assert.False(task.CanClose);

                AssertBeginFails(
                    task,
                    Panel,
                    Generation - 1,
                    "build.finalize.stale-retry",
                    "finalize",
                    "build.finalize.unknown",
                    "session_generation_expired");
                AcceptedCall retry = Begin(
                    task,
                    Panel,
                    Generation,
                    "build.finalize.retry",
                    "finalize",
                    "build.finalize.unknown");
                CompleteSuccess(
                    task, retry, Panel, Generation, 6, 6, 12, false);
                Assert.Equal("finalized", task.WriteState);
                Assert.True(task.CanClose);
            }
        }

        [Fact]
        public void ResponseCallAndCommandMustMatchAcceptedEntry()
        {
            using (var task = BoundTask())
            {
                AcceptedCall write = Begin(
                    task,
                    Panel,
                    Generation,
                    "build.response-binding",
                    "equipEquipment");
                Assert.False(task.TryCompleteSuccess(
                    write.BackendCallId,
                    Panel,
                    Generation,
                    "build.response-binding.other",
                    "equipDrug",
                    write.WriteEpoch,
                    4,
                    3,
                    InitialDrugRevision,
                    true,
                    true,
                    null,
                    null,
                    out string error));
                Assert.Equal("malformed_response", error);
                Assert.Equal("needs_reconcile", task.WriteState);
                Assert.Equal(write.WebCallId, task.ReconcileAfterCallId);
            }
        }

        [Fact]
        public void KnownDefinitiveMutationFailureEndsWriteWithoutInventingUnknown()
        {
            using (var task = BoundTask())
            {
                AcceptedCall write = Begin(
                    task,
                    Panel,
                    Generation,
                    "build.failure.definitive",
                    "equipEquipment");
                CompleteKnownFailure(
                    task, write, Panel, Generation, "stale_state");
                Assert.Equal("idle", task.WriteState);
                Assert.Null(task.ReconcileAfterCallId);
                Assert.Equal(3, task.LoadoutRevision);
            }
        }

        [Fact]
        public void PendingCapacityRemainsBounded()
        {
            using (var task = BoundTask())
            {
                for (int i = 0; i < 24; i++)
                {
                    Begin(
                        task,
                        Panel,
                        Generation,
                        "build.pending." + i,
                        "candidates");
                }
                Assert.Equal(24, task.PendingCount);
                AssertBeginFails(
                    task,
                    Panel,
                    Generation,
                    "build.pending.overflow",
                    "candidates",
                    null,
                    "busy");
            }
        }

        [Fact]
        public void ProductionInitialSnapshotUsesStrictWireAndHostStampedWebIdentity()
        {
            using (var harness = new ProductionHarness())
            {
                JObject request = WebRequest(
                    "snapshot", "prod.snapshot.1", new JObject { ["v"] = 1 });
                harness.Task.HandleWebRequest("snapshot", request);

                JObject flash = Assert.Single(harness.Flash);
                AssertExactKeys(
                    flash,
                    "task", "action", "callId", "v", "panelInstanceId",
                    "requestCallId", "writeEpoch");
                Assert.Equal("cmd", flash.Value<string>("task"));
                Assert.Equal(
                    "characterBuildSnapshot", flash.Value<string>("action"));
                Assert.Equal(
                    "prod.snapshot.1", flash.Value<string>("requestCallId"));
                Assert.Null(flash["sessionGeneration"]);

                harness.Task.HandleFlashResponse(
                    SuccessResponse(
                        flash, "snapshot", Generation, 3, 3,
                        InitialDrugRevision, false),
                    null);
                JObject web = Assert.Single(harness.Web);
                Assert.Equal("panel_resp", web.Value<string>("type"));
                Assert.Equal("workbench", web.Value<string>("panel"));
                Assert.Equal("loadout", web.Value<string>("domain"));
                Assert.Equal("snapshot", web.Value<string>("cmd"));
                Assert.Equal("prod.snapshot.1", web.Value<string>("callId"));
                Assert.Equal(Panel, web.Value<string>("panelInstanceId"));
                Assert.Null(web["task"]);
                Assert.Null(web["command"]);
                Assert.Null(web["requestCallId"]);
                Assert.IsType<JObject>(web["payload"]);
                Assert.Equal(Generation, harness.Task.SessionGeneration);
            }
        }

        [Theory]
        [InlineData("candidates", "characterBuildCandidates")]
        [InlineData("tooltip", "characterBuildTooltip")]
        [InlineData("flushLive", "characterBuildFlushLive")]
        [InlineData("statsSnapshot", "characterBuildStatsSnapshot")]
        [InlineData("finalize", "characterBuildFinalize")]
        public void ProductionWhitelistMapsToFixedFlashActions(
            string command,
            string expectedAction)
        {
            using (var harness = OpenProductionHarness())
            {
                harness.Flash.Clear();
                JObject payload = ProductionPayload(command);
                harness.Task.HandleWebRequest(
                    command,
                    WebRequest(
                        command,
                        "prod." + command,
                        payload));
                JObject flash = Assert.Single(harness.Flash);
                Assert.Equal(expectedAction, flash.Value<string>("action"));
                Assert.Equal(
                    "prod." + command, flash.Value<string>("requestCallId"));
                Assert.Equal(Generation, flash.Value<long>("sessionGeneration"));
                Assert.Equal(Panel, flash.Value<string>("panelInstanceId"));
                Assert.False(flash.ContainsKey("payload"));
            }
        }

        [Fact]
        public void TooltipIngressForwardsExactEquipmentAndDrugSelectors()
        {
            using (var equipment = OpenProductionHarness())
            {
                equipment.Flash.Clear();
                equipment.Web.Clear();
                equipment.Task.HandleWebRequest(
                    "tooltip",
                    WebRequest(
                        "tooltip",
                        "prod.tooltip.equipment",
                        ProductionPayload("tooltip")));
                JObject flash = Assert.Single(equipment.Flash);
                AssertExactKeys(
                    flash,
                    "task", "action", "callId", "v", "panelInstanceId",
                    "requestCallId", "writeEpoch", "sessionGeneration",
                    "expectedLoadoutRevision", "expectedDrugRevision", "slotKey");
                Assert.Equal(
                    "characterBuildTooltip", flash.Value<string>("action"));
                Assert.Equal(3, flash.Value<long>("expectedLoadoutRevision"));
                Assert.Equal(
                    InitialDrugRevision,
                    flash.Value<long>("expectedDrugRevision"));
                Assert.Equal("手枪2", flash.Value<string>("slotKey"));
                Assert.Null(flash["drugSlot"]);
            }

            using (var drug = OpenProductionHarness())
            {
                drug.Flash.Clear();
                drug.Web.Clear();
                JObject payload = ProductionPayload("tooltip");
                payload.Remove("slotKey");
                payload["drugSlot"] = 2;
                drug.Task.HandleWebRequest(
                    "tooltip",
                    WebRequest("tooltip", "prod.tooltip.drug", payload));
                JObject flash = Assert.Single(drug.Flash);
                AssertExactKeys(
                    flash,
                    "task", "action", "callId", "v", "panelInstanceId",
                    "requestCallId", "writeEpoch", "sessionGeneration",
                    "expectedLoadoutRevision", "expectedDrugRevision", "drugSlot");
                Assert.Equal(2, flash.Value<int>("drugSlot"));
                Assert.Null(flash["slotKey"]);
            }
        }

        [Theory]
        [InlineData("missing_selector")]
        [InlineData("both_selectors")]
        [InlineData("extra_key")]
        [InlineData("invalid_equipment_slot")]
        [InlineData("invalid_drug_slot")]
        [InlineData("missing_drug_revision")]
        public void TooltipIngressRejectsNonExactPayloads(string mutation)
        {
            using (var harness = OpenProductionHarness())
            {
                harness.Flash.Clear();
                harness.Web.Clear();
                JObject payload = ProductionPayload("tooltip");
                switch (mutation)
                {
                    case "missing_selector":
                        payload.Remove("slotKey");
                        break;
                    case "both_selectors":
                        payload["drugSlot"] = 1;
                        break;
                    case "extra_key":
                        payload["candidateScope"] = "compatible";
                        break;
                    case "invalid_equipment_slot":
                        payload["slotKey"] = "不存在的槽位";
                        break;
                    case "invalid_drug_slot":
                        payload.Remove("slotKey");
                        payload["drugSlot"] = 4;
                        break;
                    case "missing_drug_revision":
                        payload.Remove("expectedDrugRevision");
                        break;
                }
                harness.Task.HandleWebRequest(
                    "tooltip",
                    WebRequest(
                        "tooltip",
                        "prod.tooltip.invalid." + mutation,
                        payload));
                Assert.Empty(harness.Flash);
                Assert.Equal(
                    "invalid_payload",
                    Assert.Single(harness.Web).Value<string>("error"));
            }
        }

        [Theory]
        [InlineData(false)]
        [InlineData(true)]
        public void TooltipSuccessRequiresExactTargetAndRichProjection(bool drug)
        {
            using (var harness = OpenProductionHarness())
            {
                harness.Flash.Clear();
                harness.Web.Clear();
                JObject request = ProductionPayload("tooltip");
                if (drug)
                {
                    request.Remove("slotKey");
                    request["drugSlot"] = 2;
                }
                harness.Task.HandleWebRequest(
                    "tooltip",
                    WebRequest(
                        "tooltip",
                        drug ? "prod.tooltip.success.drug"
                            : "prod.tooltip.success.equipment",
                        request));
                JObject response = SuccessResponse(
                    Assert.Single(harness.Flash),
                    "tooltip",
                    Generation,
                    3,
                    3,
                    InitialDrugRevision,
                    false);
                harness.Task.HandleFlashResponse(response, null);

                JObject web = Assert.Single(harness.Web);
                Assert.True(web.Value<bool>("success"));
                JObject projection = Assert.IsType<JObject>(web["payload"]);
                AssertExactKeys(
                    projection,
                    "v", "target", "itemName", "displayName", "iconName",
                    "itemType", "descHTML", "introHTML");
                Assert.Equal("权威简介", projection.Value<string>("introHTML"));
                Assert.Equal("权威说明", projection.Value<string>("descHTML"));
                JObject target = Assert.IsType<JObject>(projection["target"]);
                Assert.Equal(drug ? "drug" : "equipment",
                    target.Value<string>("kind"));
                if (drug) Assert.Equal(2, target.Value<int>("drugSlot"));
                else Assert.Equal("手枪2", target.Value<string>("slotKey"));
                Assert.Equal("idle", harness.Task.WriteState);
            }
        }

        [Theory]
        [InlineData("payload_extra")]
        [InlineData("target_mismatch")]
        [InlineData("target_extra")]
        [InlineData("missing_field")]
        [InlineData("oversized_html")]
        [InlineData("both_html_empty")]
        [InlineData("legacy_displayname")]
        [InlineData("undefined_identity")]
        [InlineData("revision_mismatch")]
        public void TooltipResponseRejectsMalformedOrStaleProjection(string mutation)
        {
            using (var harness = OpenProductionHarness())
            {
                harness.Flash.Clear();
                harness.Web.Clear();
                harness.Task.HandleWebRequest(
                    "tooltip",
                    WebRequest(
                        "tooltip",
                        "prod.tooltip.malformed." + mutation,
                        ProductionPayload("tooltip")));
                JObject response = SuccessResponse(
                    Assert.Single(harness.Flash),
                    "tooltip",
                    Generation,
                    3,
                    3,
                    InitialDrugRevision,
                    false);
                JObject payload = Assert.IsType<JObject>(response["payload"]);
                switch (mutation)
                {
                    case "payload_extra":
                        payload["success"] = true;
                        break;
                    case "target_mismatch":
                        payload["target"] = new JObject
                        {
                            ["kind"] = "drug",
                            ["drugSlot"] = 1
                        };
                        break;
                    case "target_extra":
                        payload["target"]["extra"] = true;
                        break;
                    case "missing_field":
                        payload.Remove("introHTML");
                        break;
                    case "oversized_html":
                        payload["descHTML"] = new string('x', 131073);
                        break;
                    case "both_html_empty":
                        payload["descHTML"] = "";
                        payload["introHTML"] = "";
                        break;
                    case "legacy_displayname":
                        payload["displayname"] = payload["displayName"];
                        payload.Remove("displayName");
                        break;
                    case "undefined_identity":
                        payload["iconName"] = " Undefined ";
                        break;
                    case "revision_mismatch":
                        response["loadoutRevision"] = 4;
                        response["liveRefreshDirty"] = true;
                        break;
                }
                harness.Task.HandleFlashResponse(response, null);

                JObject web = Assert.Single(harness.Web);
                Assert.Equal(
                    "malformed_response", web.Value<string>("error"));
                Assert.False(web.Value<bool?>("requiresReconcile") == true);
                Assert.Null(web["reconcileAfterCallId"]);
                Assert.Equal("idle", harness.Task.WriteState);
            }
        }

        [Fact]
        public void TooltipTimeoutDoesNotRequireReconcile()
        {
            using (var harness = OpenProductionHarness(20))
            {
                harness.Flash.Clear();
                harness.Web.Clear();
                harness.Task.HandleWebRequest(
                    "tooltip",
                    WebRequest(
                        "tooltip",
                        "prod.tooltip.timeout",
                        ProductionPayload("tooltip")));
                Assert.True(SpinWait.SpinUntil(
                    () => harness.Web.Count == 1,
                    2000));
                JObject web = Assert.Single(harness.Web);
                Assert.Equal("timeout", web.Value<string>("error"));
                Assert.False(web.Value<bool?>("requiresReconcile") == true);
                Assert.Null(web["reconcileAfterCallId"]);
                Assert.Equal("idle", harness.Task.WriteState);
                Assert.Null(harness.Task.ReconcileAfterCallId);
            }
        }

        [Fact]
        public void CandidateProjectionAcceptsExactEquipmentGrenadeAndDrugRows()
        {
            using (var equipment = OpenProductionHarness())
            {
                JObject item = CandidateItem("手枪", "equipment", 1);
                item["balanceSummary"] = new JObject
                {
                    ["state"] = "confirmed",
                    ["weightLayers"] = -0.25,
                    ["formula"] = 1,
                    ["level"] = 3
                };
                JObject web = CompleteCandidateResponse(
                    equipment,
                    ProductionPayload("candidates"),
                    new JObject
                    {
                        ["kind"] = "equipment",
                        ["slotKey"] = "手枪2"
                    },
                    new JArray(CandidateRow(2, item, false, "")));
                Assert.True(web.Value<bool>("success"));
                Assert.Equal(
                    "手枪",
                    web["payload"]["candidates"][0]["item"].Value<string>("use"));
            }

            using (var grenade = OpenProductionHarness())
            {
                JObject request = ProductionPayload("candidates");
                request["slotKey"] = "手雷";
                JObject web = CompleteCandidateResponse(
                    grenade,
                    request,
                    new JObject
                    {
                        ["kind"] = "equipment",
                        ["slotKey"] = "手雷"
                    },
                    new JArray(
                        CandidateRow(
                            4,
                            CandidateItem("手雷", "stack", 1.5),
                            true,
                            "level_locked")));
                Assert.True(web.Value<bool>("success"));
            }

            using (var drug = OpenProductionHarness())
            {
                JObject request = ProductionPayload("candidates");
                request.Remove("slotKey");
                request["drugSlot"] = 1;
                JObject web = CompleteCandidateResponse(
                    drug,
                    request,
                    new JObject
                    {
                        ["kind"] = "drug",
                        ["drugSlot"] = 1
                    },
                    new JArray(
                        CandidateRow(
                            6,
                            CandidateItem("药剂", "stack", 0.5),
                            true,
                            "cooldown_active")));
                Assert.True(web.Value<bool>("success"));
            }

            using (var backpack = OpenProductionHarness())
            {
                JObject request = ProductionPayload("candidates");
                request["candidateScope"] = "backpack";
                JObject web = CompleteCandidateResponse(
                    backpack,
                    request,
                    new JObject
                    {
                        ["kind"] = "equipment",
                        ["slotKey"] = "手枪2"
                    },
                    new JArray(
                        CandidateRow(
                            2,
                            CandidateItem("手枪", "equipment", 1),
                            false,
                            "",
                            new JArray("手枪", "手枪2"),
                            ""),
                        CandidateRow(
                            3,
                            CandidateItem("刀", "equipment", 1),
                            true,
                            "incompatible_item",
                            new JArray("刀"),
                            ""),
                        CandidateRow(
                            4,
                            CandidateItem("药剂", "stack", 2),
                            true,
                            "incompatible_item",
                            new JArray(),
                            ""),
                        CandidateRow(
                            5,
                            CandidateItem("手雷", "stack", 1.5),
                            true,
                            "incompatible_item",
                            new JArray("手雷"),
                            "")));
                Assert.True(web.Value<bool>("success"));
                Assert.Equal(
                    "backpack",
                    web["payload"].Value<string>("candidateScope"));
            }
        }

        [Theory]
        [InlineData("scope_mismatch")]
        [InlineData("enabled_incompatible")]
        [InlineData("compatible_misreported")]
        public void BackpackCandidateProjectionRejectsScopeOrCompatibilityMismatch(
            string mutation)
        {
            using (var harness = OpenProductionHarness())
            {
                harness.Flash.Clear();
                harness.Web.Clear();
                JObject request = ProductionPayload("candidates");
                request["candidateScope"] = "backpack";
                harness.Task.HandleWebRequest(
                    "candidates",
                    WebRequest(
                        "candidates",
                        "prod.candidates.backpack.invalid." + mutation,
                        request));
                JObject response = SuccessResponse(
                    Assert.Single(harness.Flash),
                    "candidates",
                    Generation,
                    3,
                    3,
                    InitialDrugRevision,
                    false);
                JObject payload = (JObject)response["payload"];
                if (mutation == "scope_mismatch")
                {
                    payload["candidateScope"] = "compatible";
                }
                else if (mutation == "enabled_incompatible")
                {
                    payload["candidates"] = new JArray(
                        CandidateRow(
                            3,
                            CandidateItem("刀", "equipment", 1),
                            false,
                            "",
                            new JArray("刀"),
                            ""));
                }
                else
                {
                    payload["candidates"] = new JArray(
                        CandidateRow(
                            2,
                            CandidateItem("手枪", "equipment", 1),
                            true,
                            "incompatible_item",
                            new JArray("手枪", "手枪2"),
                            ""));
                }
                harness.Task.HandleFlashResponse(response, null);
                Assert.Equal(
                    "malformed_response",
                    Assert.Single(harness.Web).Value<string>("error"));
            }
        }

        [Theory]
        [InlineData("missing")]
        [InlineData("unknown_slot")]
        [InlineData("duplicate_slot")]
        [InlineData("wrong_order")]
        [InlineData("wrong_reason")]
        [InlineData("null_reason")]
        [InlineData("numeric_reason")]
        [InlineData("bad_declared_equipment_shape")]
        [InlineData("unknown_equipment_use")]
        [InlineData("empty_slots_level_locked")]
        [InlineData("omitted_alias")]
        [InlineData("target_state_mismatch")]
        public void UniversalEquipmentBackpackEligibilityFailsClosed(string mutation)
        {
            using (var harness = OpenProductionHarness())
            {
                harness.Flash.Clear();
                harness.Web.Clear();
                JObject request = ProductionPayload("candidates");
                request["candidateScope"] = "backpack";
                harness.Task.HandleWebRequest(
                    "candidates",
                    WebRequest(
                        "candidates",
                        "prod.candidates.eligibility.invalid." + mutation,
                        request));
                JObject response = SuccessResponse(
                    Assert.Single(harness.Flash),
                    "candidates",
                    Generation,
                    3,
                    3,
                    InitialDrugRevision,
                    false);
                JObject row = CandidateRow(
                    2,
                    CandidateItem("手枪", "equipment", 1),
                    false,
                    "",
                    new JArray("手枪", "手枪2"),
                    "");
                JObject eligibility = (JObject)row["equipmentEligibility"];
                JArray slots = (JArray)eligibility["slots"];
                switch (mutation)
                {
                    case "missing":
                        row.Remove("equipmentEligibility");
                        break;
                    case "unknown_slot":
                        slots[1] = "未知槽位";
                        break;
                    case "duplicate_slot":
                        slots[1] = "手枪";
                        break;
                    case "wrong_order":
                        slots[0] = "手枪2";
                        slots[1] = "手枪";
                        break;
                    case "wrong_reason":
                        eligibility["blockedReason"] = "cooldown_active";
                        break;
                    case "null_reason":
                        eligibility["blockedReason"] = JValue.CreateNull();
                        break;
                    case "numeric_reason":
                        eligibility["blockedReason"] = 7;
                        break;
                    case "bad_declared_equipment_shape":
                        row["item"] = CandidateItem("手枪", "stack", 2);
                        eligibility["slots"] = new JArray();
                        row["disabled"] = true;
                        row["blockedReason"] = "incompatible_item";
                        break;
                    case "unknown_equipment_use":
                        row["item"] = CandidateItem("未知用途", "equipment", 1);
                        eligibility["slots"] = new JArray();
                        row["disabled"] = true;
                        row["blockedReason"] = "incompatible_item";
                        break;
                    case "empty_slots_level_locked":
                        row["item"] = CandidateItem("药剂", "stack", 2);
                        eligibility["slots"] = new JArray();
                        eligibility["blockedReason"] = "level_locked";
                        row["disabled"] = true;
                        row["blockedReason"] = "incompatible_item";
                        break;
                    case "omitted_alias":
                        eligibility["slots"] = new JArray("手枪");
                        break;
                    case "target_state_mismatch":
                        row["disabled"] = true;
                        row["blockedReason"] = "level_locked";
                        break;
                }
                response["payload"]["candidates"] = new JArray(row);
                harness.Task.HandleFlashResponse(response, null);
                Assert.Equal(
                    "malformed_response",
                    Assert.Single(harness.Web).Value<string>("error"));
            }
        }

        [Theory]
        [InlineData("payload_extra")]
        [InlineData("target_mismatch")]
        [InlineData("target_extra")]
        [InlineData("too_many")]
        [InlineData("row_extra")]
        [InlineData("duplicate_slot")]
        [InlineData("unstable_order")]
        [InlineData("physical_out_of_range")]
        [InlineData("source_mismatch")]
        [InlineData("source_extra")]
        [InlineData("bad_lease")]
        [InlineData("enabled_reason")]
        [InlineData("disabled_empty")]
        [InlineData("equipment_cooldown_reason")]
        [InlineData("wrong_use")]
        [InlineData("wrong_major_type")]
        [InlineData("wrong_kind")]
        [InlineData("wrong_quantity")]
        [InlineData("item_extra")]
        [InlineData("item_nan")]
        [InlineData("item_name_undefined")]
        [InlineData("item_display_blank")]
        [InlineData("item_icon_undefined")]
        [InlineData("mod_slot_display_undefined")]
        [InlineData("mod_meta_icon_blank")]
        [InlineData("health_mismatch")]
        public void CandidateProjectionRejectsMalformedOrInconsistentRows(
            string mutation)
        {
            using (var harness = OpenProductionHarness())
            {
                harness.Flash.Clear();
                harness.Web.Clear();
                JObject request = ProductionPayload("candidates");
                harness.Task.HandleWebRequest(
                    "candidates",
                    WebRequest(
                        "candidates",
                        "prod.candidates.invalid." + mutation,
                        request));
                JObject response = SuccessResponse(
                    Assert.Single(harness.Flash),
                    "candidates",
                    Generation,
                    3,
                    3,
                    InitialDrugRevision,
                    false);
                JObject payload = (JObject)response["payload"];
                JObject row = CandidateRow(
                    2,
                    CandidateItem("手枪", "equipment", 1),
                    false,
                    "");
                var candidates = new JArray(row);
                payload["candidates"] = candidates;

                switch (mutation)
                {
                    case "payload_extra":
                        payload["__proto__"] = "polluted";
                        break;
                    case "target_mismatch":
                        payload["target"]["slotKey"] = "手枪";
                        break;
                    case "target_extra":
                        payload["target"]["extra"] = true;
                        break;
                    case "too_many":
                        candidates.Clear();
                        for (int i = 0; i < 51; i++)
                            candidates.Add((JObject)row.DeepClone());
                        break;
                    case "row_extra":
                        row["extra"] = true;
                        break;
                    case "duplicate_slot":
                        candidates.Add((JObject)row.DeepClone());
                        break;
                    case "unstable_order":
                        candidates.Clear();
                        candidates.Add(CandidateRow(
                            3,
                            CandidateItem("手枪", "equipment", 1),
                            false,
                            ""));
                        candidates.Add((JObject)row.DeepClone());
                        break;
                    case "physical_out_of_range":
                        row["physicalSlot"] = 50;
                        row["source"]["slot"] = 50;
                        break;
                    case "source_mismatch":
                        row["source"]["slot"] = 3;
                        break;
                    case "source_extra":
                        row["source"]["__proto__"] = "polluted";
                        break;
                    case "bad_lease":
                        row["source"]["expectedLease"] = "bad lease";
                        break;
                    case "enabled_reason":
                        row["blockedReason"] = "level_locked";
                        break;
                    case "disabled_empty":
                        row["disabled"] = true;
                        break;
                    case "equipment_cooldown_reason":
                        row["disabled"] = true;
                        row["blockedReason"] = "cooldown_active";
                        break;
                    case "wrong_use":
                        row["item"]["use"] = "刀";
                        break;
                    case "wrong_major_type":
                        row["item"]["majorType"] = "消耗品";
                        break;
                    case "wrong_kind":
                        row["item"]["itemKind"] = "stack";
                        break;
                    case "wrong_quantity":
                        row["item"]["quantity"] = 2;
                        break;
                    case "item_extra":
                        row["item"]["__proto__"] = "polluted";
                        break;
                    case "item_nan":
                        row["item"]["quantity"] = double.NaN;
                        break;
                    case "item_name_undefined":
                        row["item"]["name"] = " Undefined ";
                        break;
                    case "item_display_blank":
                        row["item"]["displayName"] = "   ";
                        break;
                    case "item_icon_undefined":
                        row["item"]["icon"] = "uNdEfInEd";
                        break;
                    case "mod_slot_display_undefined":
                        row["item"]["modSlots"] = new JArray(ModProjection(
                            "插件内部名", " Undefined ", "插件图标"));
                        row["item"]["modSlotCapacity"] = 1;
                        row["item"]["modSlotUsed"] = 1;
                        break;
                    case "mod_meta_icon_blank":
                        row["item"]["modMeta"] = ModProjection(
                            "插件内部名", "插件展示名", "   ");
                        break;
                    case "health_mismatch":
                        payload["diagnostics"] = new JArray("candidate_invalid");
                        break;
                    default:
                        throw new Xunit.Sdk.XunitException(
                            "unknown mutation " + mutation);
                }

                harness.Task.HandleFlashResponse(response, null);

                JObject web = Assert.Single(harness.Web);
                Assert.False(web.Value<bool>("success"));
                Assert.Equal(
                    "malformed_response",
                    web.Value<string>("error"));
            }
        }

        [Theory]
        [InlineData("level_locked")]
        [InlineData("")]
        [InlineData("unknown_reason")]
        public void DrugCandidateRejectsNonCooldownBlockedReason(string reason)
        {
            using (var harness = OpenProductionHarness())
            {
                harness.Flash.Clear();
                harness.Web.Clear();
                JObject request = ProductionPayload("candidates");
                request.Remove("slotKey");
                request["drugSlot"] = 0;
                harness.Task.HandleWebRequest(
                    "candidates",
                    WebRequest(
                        "candidates",
                        "prod.candidates.drug.reason."
                            + (reason.Length == 0 ? "empty" : reason),
                        request));
                JObject response = SuccessResponse(
                    Assert.Single(harness.Flash),
                    "candidates",
                    Generation,
                    3,
                    3,
                    InitialDrugRevision,
                    false);
                response["payload"]["target"] = new JObject
                {
                    ["kind"] = "drug",
                    ["drugSlot"] = 0
                };
                response["payload"]["candidates"] = new JArray(
                    CandidateRow(
                        1,
                        CandidateItem("药剂", "stack", 2.25),
                        true,
                        reason));

                harness.Task.HandleFlashResponse(response, null);

                Assert.Equal(
                    "malformed_response",
                    Assert.Single(harness.Web).Value<string>("error"));
            }
        }

        [Theory]
        [InlineData("grenade_equipment")]
        [InlineData("grenade_zero")]
        [InlineData("drug_equipment")]
        [InlineData("drug_wrong_use")]
        public void StackCandidateTargetsRejectWrongKindUseOrQuantity(
            string mutation)
        {
            using (var harness = OpenProductionHarness())
            {
                harness.Flash.Clear();
                harness.Web.Clear();
                bool drug = mutation.StartsWith(
                    "drug_",
                    System.StringComparison.Ordinal);
                JObject request = ProductionPayload("candidates");
                JObject target;
                JObject item;
                if (drug)
                {
                    request.Remove("slotKey");
                    request["drugSlot"] = 2;
                    target = new JObject
                    {
                        ["kind"] = "drug",
                        ["drugSlot"] = 2
                    };
                    item = CandidateItem("药剂", "stack", 1.25);
                }
                else
                {
                    request["slotKey"] = "手雷";
                    target = new JObject
                    {
                        ["kind"] = "equipment",
                        ["slotKey"] = "手雷"
                    };
                    item = CandidateItem("手雷", "stack", 1.25);
                }
                if (mutation.EndsWith(
                    "equipment",
                    System.StringComparison.Ordinal))
                {
                    item = CandidateItem(
                        drug ? "药剂" : "手雷",
                        "equipment",
                        1);
                }
                else if (mutation == "grenade_zero")
                {
                    item["quantity"] = 0;
                }
                else if (mutation == "drug_wrong_use")
                {
                    item["use"] = "手雷";
                }

                harness.Task.HandleWebRequest(
                    "candidates",
                    WebRequest(
                        "candidates",
                        "prod.candidates.stack." + mutation,
                        request));
                JObject response = SuccessResponse(
                    Assert.Single(harness.Flash),
                    "candidates",
                    Generation,
                    3,
                    3,
                    InitialDrugRevision,
                    false);
                response["payload"]["target"] = target;
                response["payload"]["candidates"] = new JArray(
                    CandidateRow(3, item, false, ""));

                harness.Task.HandleFlashResponse(response, null);

                Assert.Equal(
                    "malformed_response",
                    Assert.Single(harness.Web).Value<string>("error"));
            }
        }

        [Theory]
        [InlineData("equipEquipment", "characterBuildEquipEquipment")]
        [InlineData("unequipEquipment", "characterBuildUnequipEquipment")]
        [InlineData("equipDrug", "characterBuildEquipDrug")]
        [InlineData("unequipDrug", "characterBuildUnequipDrug")]
        public void ProductionMutationRequestsAreRebuiltFromFourExactShapes(
            string command,
            string expectedAction)
        {
            using (var harness = OpenProductionHarness())
            {
                harness.Flash.Clear();
                harness.Web.Clear();
                JObject payload = MutationPayload(command);
                harness.Task.HandleWebRequest(
                    command,
                    WebRequest(
                        command,
                        "prod.b2." + command,
                        payload));
                JObject flash = Assert.Single(harness.Flash);
                Assert.Equal(expectedAction, flash.Value<string>("action"));
                Assert.Equal(
                    "prod.b2." + command,
                    flash.Value<string>("requestCallId"));
                Assert.Equal(Panel, flash.Value<string>("panelInstanceId"));
                Assert.Equal(Generation, flash.Value<long>("sessionGeneration"));
                Assert.Equal(1, flash.Value<int>("writeEpoch"));
                Assert.False(flash.ContainsKey("payload"));
                if (command.Contains("Equipment"))
                {
                    Assert.Equal(3, flash.Value<long>("expectedLoadoutRevision"));
                    Assert.Equal("手枪2", flash.Value<string>("slotKey"));
                    Assert.False(flash.ContainsKey("expectedDrugRevision"));
                }
                else
                {
                    Assert.Equal(
                        InitialDrugRevision,
                        flash.Value<long>("expectedDrugRevision"));
                    Assert.Equal(1, flash.Value<int>("drugSlot"));
                    Assert.False(flash.ContainsKey("expectedLoadoutRevision"));
                }
                if (command.StartsWith("equip", StringComparison.Ordinal))
                {
                    AssertExactKeys(
                        (JObject)flash["source"],
                        "containerId", "slot", "expectedLease");
                    Assert.Equal("背包", flash["source"].Value<string>("containerId"));
                    Assert.Equal(6, flash["source"].Value<int>("slot"));
                    Assert.Equal(
                        "lease.bag.6",
                        flash["source"].Value<string>("expectedLease"));
                }
                else
                {
                    Assert.Null(flash["source"]);
                }
            }
        }

        [Theory]
        [InlineData("equipEquipment", 4L, 3L, 11L, true)]
        [InlineData("unequipEquipment", 4L, 3L, 11L, true)]
        [InlineData("equipDrug", 3L, 3L, 12L, false)]
        [InlineData("unequipDrug", 3L, 3L, 12L, false)]
        public void ProductionFourMutationSuccessesAdoptCompleteAuthority(
            string command,
            long expectedLoadoutRevision,
            long expectedLiveRevision,
            long expectedDrugRevision,
            bool expectedDirty)
        {
            using (var harness = OpenProductionHarness())
            {
                harness.Flash.Clear();
                harness.Web.Clear();
                harness.Task.HandleWebRequest(
                    command,
                    WebRequest(
                        command,
                        "prod.success." + command,
                        MutationPayload(command)));
                JObject flash = Assert.Single(harness.Flash);
                harness.Task.HandleFlashResponse(
                    MutationSuccessResponse(flash, command),
                    null);

                JObject web = Assert.Single(harness.Web);
                Assert.True(web.Value<bool>("success"));
                Assert.True(web.Value<bool>("changed"));
                Assert.Equal(command, web.Value<string>("operation"));
                Assert.Equal(command, web.Value<string>("cmd"));
                Assert.Equal(
                    expectedLoadoutRevision,
                    web.Value<long>("loadoutRevision"));
                Assert.Equal(
                    expectedLiveRevision,
                    web.Value<long>("liveRevision"));
                Assert.Equal(
                    expectedDrugRevision,
                    web.Value<long>("drugRevision"));
                Assert.Equal(
                    expectedDirty,
                    web.Value<bool>("liveRefreshDirty"));
                Assert.IsType<JObject>(web["payload"]);
                Assert.Single((JArray)web["inventorySnapshots"]);
                Assert.Equal("idle", harness.Task.WriteState);
                Assert.Null(harness.Task.ReconcileAfterCallId);
            }
        }

        [Fact]
        public void ProductionMutationNoOpKeepsAllRevisionsAndDirtyState()
        {
            using (var harness = OpenProductionHarness())
            {
                harness.Flash.Clear();
                harness.Web.Clear();
                const string command = "unequipDrug";
                harness.Task.HandleWebRequest(
                    command,
                    WebRequest(
                        command,
                        "prod.noop.unequip-drug",
                        MutationPayload(command)));
                JObject flash = Assert.Single(harness.Flash);
                harness.Task.HandleFlashResponse(
                    MutationSuccessResponse(
                        flash,
                        command,
                        false),
                    null);

                JObject web = Assert.Single(harness.Web);
                Assert.True(web.Value<bool>("success"));
                Assert.False(web.Value<bool>("changed"));
                Assert.Equal(3, harness.Task.LoadoutRevision);
                Assert.Equal(3, harness.Task.LiveRevision);
                Assert.Equal(
                    InitialDrugRevision,
                    harness.Task.DrugRevision);
                Assert.False(harness.Task.LiveRefreshDirty);
                Assert.Equal("idle", harness.Task.WriteState);
            }
        }

        [Theory]
        [InlineData("equipEquipment", "extra")]
        [InlineData("unequipEquipment", "extra")]
        [InlineData("equipDrug", "extra")]
        [InlineData("unequipDrug", "extra")]
        [InlineData("equipEquipment", "missing_source")]
        [InlineData("unequipEquipment", "source_on_unequip")]
        [InlineData("equipEquipment", "wrong_revision_type")]
        [InlineData("equipDrug", "negative_revision")]
        [InlineData("equipDrug", "zero_generation")]
        [InlineData("equipEquipment", "unknown_slot")]
        [InlineData("equipDrug", "drug_slot_out_of_range")]
        [InlineData("equipEquipment", "source_extra")]
        [InlineData("equipEquipment", "source_container")]
        [InlineData("equipEquipment", "source_slot_out_of_range")]
        [InlineData("equipEquipment", "source_bad_lease")]
        public void ProductionMutationIngressRejectsExtraMissingTypeAndRange(
            string command,
            string mutation)
        {
            using (var harness = OpenProductionHarness())
            {
                harness.Flash.Clear();
                harness.Web.Clear();
                JObject payload = MutationPayload(command);
                switch (mutation)
                {
                    case "extra":
                        payload["reconcileAfterCallId"] = "forbidden";
                        break;
                    case "missing_source":
                        payload.Remove("source");
                        break;
                    case "source_on_unequip":
                        payload["source"] = new JObject
                        {
                            ["containerId"] = "背包",
                            ["slot"] = 6,
                            ["expectedLease"] = "lease.bag.6"
                        };
                        break;
                    case "wrong_revision_type":
                        payload["expectedLoadoutRevision"] = "3";
                        break;
                    case "negative_revision":
                        payload["expectedDrugRevision"] = -1;
                        break;
                    case "zero_generation":
                        payload["sessionGeneration"] = 0;
                        break;
                    case "unknown_slot":
                        payload["slotKey"] = "披风";
                        break;
                    case "drug_slot_out_of_range":
                        payload["drugSlot"] = 4;
                        break;
                    case "source_extra":
                        payload["source"]["count"] = 1;
                        break;
                    case "source_container":
                        payload["source"]["containerId"] = "战备箱";
                        break;
                    case "source_slot_out_of_range":
                        payload["source"]["slot"] = 50;
                        break;
                    case "source_bad_lease":
                        payload["source"]["expectedLease"] = "bad lease";
                        break;
                    default:
                        throw new Xunit.Sdk.XunitException(
                            "unknown request mutation " + mutation);
                }

                harness.Task.HandleWebRequest(
                    command,
                    WebRequest(
                        command,
                        "prod.invalid." + command + "." + mutation,
                        payload));

                Assert.Empty(harness.Flash);
                JObject web = Assert.Single(harness.Web);
                Assert.False(web.Value<bool>("success"));
                Assert.Equal(
                    "invalid_payload",
                    web.Value<string>("error"));
                Assert.Equal("idle", harness.Task.WriteState);
            }
        }

        [Theory]
        [InlineData("root_extra")]
        [InlineData("missing_changed")]
        [InlineData("changed_type")]
        [InlineData("operation_mismatch")]
        [InlineData("affected_out_of_range")]
        [InlineData("affected_source_mismatch")]
        [InlineData("payload_extra")]
        [InlineData("target_postcondition")]
        [InlineData("loadout_item_extra")]
        [InlineData("loadout_item_nan")]
        [InlineData("drug_remaining_nan")]
        [InlineData("inventory_missing")]
        [InlineData("inventory_multiple")]
        [InlineData("snapshot_extra")]
        [InlineData("snapshot_non_full")]
        [InlineData("slot_duplicate")]
        [InlineData("slot_extra")]
        [InlineData("slot_bad_lease")]
        [InlineData("inventory_item_extra")]
        [InlineData("confirm_mismatch")]
        [InlineData("unhealthy_success")]
        public void ProductionMutationMalformedSuccessNeedsReconcile(
            string mutation)
        {
            string command =
                mutation == "drug_remaining_nan"
                    ? "equipDrug"
                    : mutation == "inventory_item_extra"
                        || mutation == "confirm_mismatch"
                    ? "unequipEquipment"
                    : "equipEquipment";
            using (var harness = OpenProductionHarness())
            {
                harness.Flash.Clear();
                harness.Web.Clear();
                string callId = "prod.malformed." + mutation;
                harness.Task.HandleWebRequest(
                    command,
                    WebRequest(
                        command,
                        callId,
                        MutationPayload(command)));
                JObject flash = Assert.Single(harness.Flash);
                JObject response =
                    MutationSuccessResponse(flash, command);
                JObject payload = (JObject)response["payload"];
                JObject snapshot =
                    (JObject)response["inventorySnapshots"][0];
                JArray slots = (JArray)snapshot["slots"];

                switch (mutation)
                {
                    case "root_extra":
                        response["__proto__"] = "polluted";
                        break;
                    case "missing_changed":
                        response.Remove("changed");
                        break;
                    case "changed_type":
                        response["changed"] = "true";
                        break;
                    case "operation_mismatch":
                        response["operation"] = "unequipEquipment";
                        break;
                    case "affected_out_of_range":
                        response["affectedBackpackSlot"] = 50;
                        break;
                    case "affected_source_mismatch":
                        response["affectedBackpackSlot"] = 5;
                        break;
                    case "payload_extra":
                        payload["extra"] = true;
                        break;
                    case "target_postcondition":
                        payload["equipment"][8]["occupied"] = false;
                        ((JObject)payload["equipment"][8]).Remove("item");
                        break;
                    case "loadout_item_extra":
                        payload["equipment"][8]["item"]["extra"] = true;
                        break;
                    case "loadout_item_nan":
                        payload["equipment"][8]["item"]["quantity"] =
                            double.NaN;
                        break;
                    case "drug_remaining_nan":
                        payload["drugs"][1]["remainingMs"] = double.NaN;
                        break;
                    case "inventory_missing":
                        response.Remove("inventorySnapshots");
                        break;
                    case "inventory_multiple":
                        ((JArray)response["inventorySnapshots"]).Add(
                            snapshot.DeepClone());
                        break;
                    case "snapshot_extra":
                        snapshot["scope"] = "all";
                        break;
                    case "snapshot_non_full":
                        slots.RemoveAt(49);
                        snapshot["limit"] = 49;
                        break;
                    case "slot_duplicate":
                        slots[1]["physicalSlot"] = 0;
                        break;
                    case "slot_extra":
                        slots[0]["item"] = CandidateItem(
                            "药剂", "stack", 1);
                        break;
                    case "slot_bad_lease":
                        slots[0]["slotLease"] = "bad lease";
                        break;
                    case "inventory_item_extra":
                        slots[8]["item"]["extra"] = true;
                        break;
                    case "confirm_mismatch":
                        slots[8]["confirmProjection"]["name"] =
                            "另一个物品";
                        break;
                    case "unhealthy_success":
                        payload["stateHealth"] = "degraded";
                        payload["diagnostics"] =
                            new JArray("projection_failed");
                        break;
                    default:
                        throw new Xunit.Sdk.XunitException(
                            "unknown response mutation " + mutation);
                }

                harness.Task.HandleFlashResponse(response, null);

                JObject web = Assert.Single(harness.Web);
                Assert.False(web.Value<bool>("success"));
                Assert.Equal(
                    "malformed_response",
                    web.Value<string>("error"));
                Assert.True(web.Value<bool>("requiresReconcile"));
                Assert.Equal(
                    callId,
                    web.Value<string>("reconcileAfterCallId"));
                Assert.Equal(
                    "needs_reconcile",
                    harness.Task.WriteState);
                Assert.Equal(
                    callId,
                    harness.Task.ReconcileAfterCallId);
                Assert.Single(harness.Flash);
            }
        }

        [Theory]
        [InlineData("equipment_no_advance")]
        [InlineData("equipment_noop_advanced")]
        [InlineData("equipment_unrelated_advanced")]
        [InlineData("equipment_below_baseline")]
        [InlineData("drug_no_advance")]
        [InlineData("drug_unrelated_advanced")]
        public void ProductionMutationRevisionPostconditionsAreExact(
            string mutation)
        {
            bool drug = mutation.StartsWith(
                "drug_", StringComparison.Ordinal);
            string command = drug ? "equipDrug" : "equipEquipment";
            bool changed = mutation != "equipment_noop_advanced";
            using (var harness = OpenProductionHarness())
            {
                harness.Flash.Clear();
                harness.Web.Clear();
                string callId = "prod.revision." + mutation;
                harness.Task.HandleWebRequest(
                    command,
                    WebRequest(
                        command,
                        callId,
                        MutationPayload(command)));
                JObject response = MutationSuccessResponse(
                    Assert.Single(harness.Flash),
                    command,
                    changed);
                switch (mutation)
                {
                    case "equipment_no_advance":
                        response["loadoutRevision"] = 3;
                        response["liveRefreshDirty"] = false;
                        break;
                    case "equipment_noop_advanced":
                        response["loadoutRevision"] = 4;
                        response["liveRefreshDirty"] = true;
                        break;
                    case "equipment_unrelated_advanced":
                        response["drugRevision"] =
                            InitialDrugRevision + 1;
                        break;
                    case "equipment_below_baseline":
                        response["loadoutRevision"] = 2;
                        response["liveRevision"] = 2;
                        response["liveRefreshDirty"] = false;
                        break;
                    case "drug_no_advance":
                        response["drugRevision"] =
                            InitialDrugRevision;
                        break;
                    case "drug_unrelated_advanced":
                        response["loadoutRevision"] = 4;
                        response["liveRefreshDirty"] = true;
                        break;
                    default:
                        throw new Xunit.Sdk.XunitException(
                            "unknown revision mutation " + mutation);
                }

                harness.Task.HandleFlashResponse(response, null);

                JObject web = Assert.Single(harness.Web);
                Assert.False(web.Value<bool>("success"));
                Assert.Equal(
                    "needs_reconcile",
                    web.Value<string>("error"));
                Assert.True(web.Value<bool>("requiresReconcile"));
                Assert.Equal(
                    callId,
                    web.Value<string>("reconcileAfterCallId"));
                Assert.Equal(
                    "needs_reconcile",
                    harness.Task.WriteState);
                Assert.Equal(3, harness.Task.LoadoutRevision);
                Assert.Equal(3, harness.Task.LiveRevision);
                Assert.Equal(
                    InitialDrugRevision,
                    harness.Task.DrugRevision);
            }
        }

        [Theory]
        [InlineData("invalid_payload")]
        [InlineData("invalid_slot")]
        [InlineData("stale_state")]
        [InlineData("level_locked")]
        [InlineData("cooldown_active")]
        [InlineData("cooldown_unavailable")]
        [InlineData("incompatible_item")]
        [InlineData("backpack_full")]
        [InlineData("write_failed")]
        [InlineData("write_busy")]
        public void ProductionMutationDefinitiveFailuresKeepOldAuthority(
            string failure)
        {
            using (var harness = OpenProductionHarness())
            {
                harness.Flash.Clear();
                harness.Web.Clear();
                const string command = "equipEquipment";
                string callId = "prod.failure." + failure;
                harness.Task.HandleWebRequest(
                    command,
                    WebRequest(
                        command,
                        callId,
                        MutationPayload(command)));
                harness.Task.HandleFlashResponse(
                    MutationFailureResponse(
                        Assert.Single(harness.Flash),
                        command,
                        failure),
                    null);

                JObject web = Assert.Single(harness.Web);
                Assert.False(web.Value<bool>("success"));
                Assert.Equal(failure, web.Value<string>("error"));
                Assert.False(web.Value<bool?>("requiresReconcile") == true);
                Assert.Null(web["reconcileAfterCallId"]);
                Assert.Equal("idle", harness.Task.WriteState);
                Assert.Equal(3, harness.Task.LoadoutRevision);
                Assert.Equal(3, harness.Task.LiveRevision);
                Assert.Equal(
                    InitialDrugRevision,
                    harness.Task.DrugRevision);
            }
        }

        [Theory]
        [InlineData("equipEquipment", false, "invalid_slot")]
        [InlineData("unequipEquipment", false, "invalid_slot")]
        [InlineData("equipDrug", false, "invalid_slot")]
        [InlineData("unequipDrug", false, "invalid_slot")]
        [InlineData("equipEquipment", true, "stats_failed")]
        [InlineData("unequipEquipment", true, "stats_failed")]
        [InlineData("equipDrug", true, "stats_failed")]
        [InlineData("unequipDrug", true, "stats_failed")]
        public void ProductionMutationFailureRequiresActiveSessionAndMutationCode(
            string command,
            bool active,
            string failure)
        {
            using (var harness = OpenProductionHarness())
            {
                harness.Flash.Clear();
                harness.Web.Clear();
                string callId = "prod.failure.contract." + command
                    + "." + (active ? "active" : "inactive");
                harness.Task.HandleWebRequest(
                    command,
                    WebRequest(
                        command,
                        callId,
                        MutationPayload(command)));
                JObject response = MutationFailureResponse(
                    Assert.Single(harness.Flash),
                    command,
                    failure);
                response["active"] = active;

                harness.Task.HandleFlashResponse(response, null);

                JObject web = Assert.Single(harness.Web);
                Assert.False(web.Value<bool>("success"));
                Assert.Equal(
                    "needs_reconcile",
                    web.Value<string>("error"));
                Assert.True(web.Value<bool>("requiresReconcile"));
                Assert.Equal(
                    callId,
                    web.Value<string>("reconcileAfterCallId"));
                Assert.Equal(
                    "needs_reconcile",
                    harness.Task.WriteState);
                Assert.Equal(
                    callId,
                    harness.Task.ReconcileAfterCallId);
                Assert.Equal(3, harness.Task.LoadoutRevision);
                Assert.Equal(3, harness.Task.LiveRevision);
                Assert.Equal(
                    InitialDrugRevision,
                    harness.Task.DrugRevision);
                Assert.Single(harness.Flash);
            }
        }

        [Fact]
        public void ProductionMutationReconcileFailureAndChangedFailureStayUnknown()
        {
            using (var explicitUnknown = OpenProductionHarness())
            {
                explicitUnknown.Flash.Clear();
                explicitUnknown.Web.Clear();
                const string command = "equipEquipment";
                const string callId = "prod.failure.needs-reconcile";
                explicitUnknown.Task.HandleWebRequest(
                    command,
                    WebRequest(
                        command,
                        callId,
                        MutationPayload(command)));
                explicitUnknown.Task.HandleFlashResponse(
                    MutationFailureResponse(
                        Assert.Single(explicitUnknown.Flash),
                        command,
                        "needs_reconcile",
                        4,
                        3),
                    null);

                JObject web = Assert.Single(explicitUnknown.Web);
                Assert.Equal(
                    "needs_reconcile",
                    explicitUnknown.Task.WriteState);
                Assert.Equal(
                    callId,
                    explicitUnknown.Task.ReconcileAfterCallId);
                Assert.True(web.Value<bool>("requiresReconcile"));
            }

            using (var falseDefinitive = OpenProductionHarness())
            {
                falseDefinitive.Flash.Clear();
                falseDefinitive.Web.Clear();
                const string command = "equipEquipment";
                const string callId = "prod.failure.changed";
                falseDefinitive.Task.HandleWebRequest(
                    command,
                    WebRequest(
                        command,
                        callId,
                        MutationPayload(command)));
                falseDefinitive.Task.HandleFlashResponse(
                    MutationFailureResponse(
                        Assert.Single(falseDefinitive.Flash),
                        command,
                        "write_failed",
                        4,
                        3),
                    null);

                JObject web = Assert.Single(falseDefinitive.Web);
                Assert.Equal(
                    "needs_reconcile",
                    web.Value<string>("error"));
                Assert.True(web.Value<bool>("requiresReconcile"));
                Assert.Equal(
                    "needs_reconcile",
                    falseDefinitive.Task.WriteState);
                Assert.Equal(3, falseDefinitive.Task.LoadoutRevision);
            }
        }

        [Fact]
        public void ProductionAcceptedMutationTransportFailuresBecomeUnknownWithoutReplay()
        {
            using (var failedSend = OpenProductionHarness())
            {
                failedSend.Flash.Clear();
                failedSend.Web.Clear();
                failedSend.SendSucceeds = false;
                const string callId = "prod.transport.send-false";

                failedSend.Task.HandleWebRequest(
                    "equipEquipment",
                    WebRequest(
                        "equipEquipment",
                        callId,
                        MutationPayload("equipEquipment")));

                JObject web = Assert.Single(failedSend.Web);
                Assert.Equal(
                    "delivery_unknown",
                    web.Value<string>("error"));
                Assert.True(web.Value<bool>("requiresReconcile"));
                Assert.Equal(
                    callId,
                    web.Value<string>("reconcileAfterCallId"));
                Assert.Equal(
                    "needs_reconcile",
                    failedSend.Task.WriteState);
                Assert.Equal(
                    callId,
                    failedSend.Task.ReconcileAfterCallId);
                Assert.Single(failedSend.Flash);
            }

            using (var timedOut = OpenProductionHarness(20))
            {
                timedOut.Flash.Clear();
                timedOut.Web.Clear();
                const string callId = "prod.transport.timeout";

                timedOut.Task.HandleWebRequest(
                    "equipDrug",
                    WebRequest(
                        "equipDrug",
                        callId,
                        MutationPayload("equipDrug")));

                Assert.True(SpinWait.SpinUntil(
                    () => timedOut.Web.Count == 1,
                    2000));
                JObject web = Assert.Single(timedOut.Web);
                Assert.Equal("timeout", web.Value<string>("error"));
                Assert.True(web.Value<bool>("requiresReconcile"));
                Assert.Equal(
                    callId,
                    web.Value<string>("reconcileAfterCallId"));
                Assert.Equal(
                    "needs_reconcile",
                    timedOut.Task.WriteState);
                Thread.Sleep(50);
                Assert.Single(timedOut.Flash);
                Assert.Single(timedOut.Web);
            }

            using (var disconnected = OpenProductionHarness())
            {
                disconnected.Flash.Clear();
                disconnected.Web.Clear();
                const string callId = "prod.transport.disconnect";

                disconnected.Task.HandleWebRequest(
                    "unequipEquipment",
                    WebRequest(
                        "unequipEquipment",
                        callId,
                        MutationPayload("unequipEquipment")));
                disconnected.Ready = false;
                disconnected.Task.HandleDisconnect();

                JObject web = Assert.Single(disconnected.Web);
                Assert.Equal(
                    "disconnected",
                    web.Value<string>("error"));
                Assert.True(web.Value<bool>("requiresReconcile"));
                Assert.Equal(
                    callId,
                    web.Value<string>("reconcileAfterCallId"));
                Assert.Equal(
                    "needs_reconcile",
                    disconnected.Task.WriteState);
                Assert.Single(disconnected.Flash);
            }
        }

        [Fact]
        public void ProductionMutationUnknownClearsOnlyWithExactFreshFullSnapshot()
        {
            using (var harness = OpenProductionHarness())
            {
                harness.Flash.Clear();
                harness.Web.Clear();
                harness.SendSucceeds = false;
                const string mutationCallId = "prod.reconcile.mutation";
                harness.Task.HandleWebRequest(
                    "equipEquipment",
                    WebRequest(
                        "equipEquipment",
                        mutationCallId,
                        MutationPayload("equipEquipment")));
                JObject originalMutation =
                    (JObject)Assert.Single(harness.Flash).DeepClone();
                Assert.Equal(
                    "needs_reconcile",
                    harness.Task.WriteState);

                harness.SendSucceeds = true;
                harness.Web.Clear();
                harness.Task.HandleWebRequest(
                    "snapshot",
                    WebRequest(
                        "snapshot",
                        "prod.reconcile.ordinary",
                        new JObject
                        {
                            ["v"] = 1,
                            ["sessionGeneration"] = Generation
                        }));
                JObject ordinary = Assert.Single(harness.Web);
                Assert.Equal(
                    "reconcile_required",
                    ordinary.Value<string>("error"));
                Assert.True(
                    ordinary.Value<bool>("requiresReconcile"));
                Assert.Equal(
                    mutationCallId,
                    ordinary.Value<string>("reconcileAfterCallId"));
                Assert.Single(harness.Flash);
                Assert.Equal(
                    "needs_reconcile",
                    harness.Task.WriteState);

                harness.Web.Clear();
                harness.Task.HandleWebRequest(
                    "snapshot",
                    WebRequest(
                        "snapshot",
                        "prod.reconcile.wrong-watermark",
                        new JObject
                        {
                            ["v"] = 1,
                            ["sessionGeneration"] = Generation,
                            ["reconcileAfterCallId"] =
                                "prod.reconcile.not-the-mutation"
                        }));
                JObject wrongWatermark = Assert.Single(harness.Web);
                Assert.Equal(
                    "invalid_reconcile_watermark",
                    wrongWatermark.Value<string>("error"));
                Assert.True(
                    wrongWatermark.Value<bool>("requiresReconcile"));
                Assert.Equal(
                    mutationCallId,
                    wrongWatermark.Value<string>("reconcileAfterCallId"));
                Assert.Single(harness.Flash);

                harness.Web.Clear();
                harness.Task.HandleWebRequest(
                    "snapshot",
                    WebRequest(
                        "snapshot",
                        "prod.reconcile.malformed",
                        new JObject
                        {
                            ["v"] = 1,
                            ["sessionGeneration"] = Generation,
                            ["reconcileAfterCallId"] = mutationCallId
                        }));
                Assert.Equal(2, harness.Flash.Count);
                JObject malformedRequest = harness.Flash[1];
                Assert.Equal(
                    mutationCallId,
                    malformedRequest.Value<string>(
                        "reconcileAfterCallId"));
                Assert.Equal(
                    originalMutation.Value<int>("writeEpoch"),
                    malformedRequest.Value<int>("writeEpoch"));
                JObject malformedResponse =
                    MutationReconcileResponse(
                        malformedRequest,
                        mutationCallId,
                        true);
                malformedResponse.Remove("inventorySnapshots");
                harness.Task.HandleFlashResponse(
                    malformedResponse,
                    null);

                JObject malformed = Assert.Single(harness.Web);
                Assert.Equal(
                    "malformed_response",
                    malformed.Value<string>("error"));
                Assert.True(
                    malformed.Value<bool>("requiresReconcile"));
                Assert.Equal(
                    mutationCallId,
                    malformed.Value<string>("reconcileAfterCallId"));
                Assert.Equal(
                    "needs_reconcile",
                    harness.Task.WriteState);
                Assert.Equal(3, harness.Task.LoadoutRevision);

                harness.Web.Clear();
                harness.Task.HandleWebRequest(
                    "snapshot",
                    WebRequest(
                        "snapshot",
                        "prod.reconcile.full",
                        new JObject
                        {
                            ["v"] = 1,
                            ["sessionGeneration"] = Generation,
                            ["reconcileAfterCallId"] = mutationCallId
                        }));
                Assert.Equal(3, harness.Flash.Count);
                JObject fullRequest = harness.Flash[2];
                Assert.Equal(
                    originalMutation.Value<int>("writeEpoch"),
                    fullRequest.Value<int>("writeEpoch"));
                harness.Task.HandleFlashResponse(
                    MutationReconcileResponse(
                        fullRequest,
                        mutationCallId,
                        true),
                    null);

                JObject reconciled = Assert.Single(harness.Web);
                Assert.True(reconciled.Value<bool>("success"));
                Assert.Equal(
                    mutationCallId,
                    reconciled.Value<string>("reconcileAfterCallId"));
                Assert.IsType<JObject>(reconciled["payload"]);
                Assert.Single(
                    Assert.IsType<JArray>(
                        reconciled["inventorySnapshots"]));
                Assert.Equal("idle", harness.Task.WriteState);
                Assert.Null(harness.Task.ReconcileAfterCallId);
                Assert.Equal(4, harness.Task.LoadoutRevision);
                Assert.Equal(3, harness.Task.LiveRevision);
                Assert.True(harness.Task.LiveRefreshDirty);
                Assert.Equal(
                    "characterBuildEquipEquipment",
                    harness.Flash[0].Value<string>("action"));
                Assert.Equal(
                    "characterBuildSnapshot",
                    harness.Flash[1].Value<string>("action"));
                Assert.Equal(
                    "characterBuildSnapshot",
                    harness.Flash[2].Value<string>("action"));

                harness.Web.Clear();
                harness.Task.HandleFlashResponse(
                    MutationSuccessResponse(
                        originalMutation,
                        "equipEquipment"),
                    null);
                Assert.Empty(harness.Web);
                Assert.Equal(3, harness.Flash.Count);
                Assert.Equal("idle", harness.Task.WriteState);
                Assert.Equal(4, harness.Task.LoadoutRevision);
            }
        }

        [Fact]
        public void ProductionFlushUnknownReconcileSnapshotAcceptsBarrierExtras()
        {
            using (var harness = OpenProductionHarness())
            {
                harness.Flash.Clear();
                harness.Web.Clear();
                harness.SendSucceeds = false;
                const string flushCallId = "prod.flush-extras.unknown";
                harness.Task.HandleWebRequest(
                    "flushLive",
                    WebRequest(
                        "flushLive",
                        flushCallId,
                        ProductionPayload("flushLive")));
                Assert.Equal("needs_reconcile", harness.Task.WriteState);

                harness.SendSucceeds = true;
                harness.Web.Clear();
                harness.Task.HandleWebRequest(
                    "snapshot",
                    WebRequest(
                        "snapshot",
                        "prod.flush-extras.reconcile",
                        new JObject
                        {
                            ["v"] = 1,
                            ["sessionGeneration"] = Generation,
                            ["reconcileAfterCallId"] = flushCallId
                        }));
                Assert.Equal(2, harness.Flash.Count);
                // 与生产 AS2 一致：任何 unknown 种类的 reconcile 快照都携带
                // barrier 与整包背包证明；Host 校验后只向 Web 转发 payload。
                JObject response = SuccessResponse(
                    harness.Flash[1],
                    "snapshot",
                    Generation,
                    3,
                    3,
                    InitialDrugRevision,
                    false);
                response["reconcileAfterCallId"] = flushCallId;
                response["inventorySnapshots"] =
                    FullBackpackSnapshots("equipEquipment", -1, false);
                harness.Task.HandleFlashResponse(response, null);

                JObject web = Assert.Single(harness.Web);
                Assert.True(web.Value<bool>("success"));
                Assert.IsType<JObject>(web["payload"]);
                Assert.Null(web["reconcileAfterCallId"]);
                Assert.Null(web["inventorySnapshots"]);
                Assert.Equal("idle", harness.Task.WriteState);
                Assert.Null(harness.Task.ReconcileAfterCallId);
            }
        }

        [Fact]
        public void ProductionFlushUnknownReconcileSnapshotRejectsMismatchedBarrier()
        {
            using (var harness = OpenProductionHarness())
            {
                harness.Flash.Clear();
                harness.Web.Clear();
                harness.SendSucceeds = false;
                const string flushCallId = "prod.flush-foreign.unknown";
                harness.Task.HandleWebRequest(
                    "flushLive",
                    WebRequest(
                        "flushLive",
                        flushCallId,
                        ProductionPayload("flushLive")));
                Assert.Equal("needs_reconcile", harness.Task.WriteState);

                harness.SendSucceeds = true;
                harness.Web.Clear();
                harness.Task.HandleWebRequest(
                    "snapshot",
                    WebRequest(
                        "snapshot",
                        "prod.flush-foreign.reconcile",
                        new JObject
                        {
                            ["v"] = 1,
                            ["sessionGeneration"] = Generation,
                            ["reconcileAfterCallId"] = flushCallId
                        }));
                Assert.Equal(2, harness.Flash.Count);
                JObject response = SuccessResponse(
                    harness.Flash[1],
                    "snapshot",
                    Generation,
                    3,
                    3,
                    InitialDrugRevision,
                    false);
                response["reconcileAfterCallId"] = "prod.flush-foreign.other";
                response["inventorySnapshots"] =
                    FullBackpackSnapshots("equipEquipment", -1, false);
                harness.Task.HandleFlashResponse(response, null);

                JObject web = Assert.Single(harness.Web);
                Assert.Equal(
                    "malformed_response",
                    web.Value<string>("error"));
                Assert.True(web.Value<bool>("requiresReconcile"));
                Assert.Equal(
                    flushCallId,
                    web.Value<string>("reconcileAfterCallId"));
                Assert.Equal("needs_reconcile", harness.Task.WriteState);
            }
        }

        [Fact]
        public void ProductionStatsUnavailableFailurePassesThrough()
        {
            using (var harness = OpenProductionHarness())
            {
                harness.Flash.Clear();
                harness.Web.Clear();
                harness.Task.HandleWebRequest(
                    "statsSnapshot",
                    WebRequest(
                        "statsSnapshot",
                        "prod.failure.stats_unavailable",
                        ProductionPayload("statsSnapshot")));
                JObject response = SuccessResponse(
                    Assert.Single(harness.Flash),
                    "statsSnapshot",
                    Generation,
                    3,
                    3,
                    InitialDrugRevision,
                    false);
                response.Remove("payload");
                response["success"] = false;
                response["error"] = "stats_unavailable";
                harness.Task.HandleFlashResponse(response, null);

                JObject web = Assert.Single(harness.Web);
                Assert.False(web.Value<bool>("success"));
                Assert.Equal(
                    "stats_unavailable",
                    web.Value<string>("error"));
                Assert.False(web.Value<bool?>("requiresReconcile") == true);
            }
        }

        [Fact]
        public void ProductionInitialPauseLeaseMissingReleasesUnopenedBarrier()
        {
            using (var harness = new ProductionHarness())
            {
                harness.Task.HandleWebRequest(
                    "snapshot",
                    WebRequest(
                        "snapshot",
                        "prod.initial.pause-lease",
                        new JObject { ["v"] = 1 }));
                JObject flash = Assert.Single(harness.Flash);
                var response = new JObject
                {
                    ["task"] = "loadout_response",
                    ["callId"] = flash.Value<int>("callId"),
                    ["v"] = 1,
                    ["success"] = false,
                    ["command"] = "snapshot",
                    ["requestCallId"] = "prod.initial.pause-lease",
                    ["panelInstanceId"] = Panel,
                    ["writeEpoch"] = 0,
                    ["active"] = false,
                    ["sessionGeneration"] = 0,
                    ["loadoutRevision"] = 0,
                    ["liveRevision"] = 0,
                    ["liveRefreshDirty"] = false,
                    ["drugRevision"] = 0,
                    ["error"] = "pause_lease_missing"
                };

                harness.Task.HandleFlashResponse(response, null);

                JObject web = Assert.Single(harness.Web);
                Assert.False(web.Value<bool>("success"));
                Assert.Equal(
                    "pause_lease_missing",
                    web.Value<string>("error"));
                Assert.Null(harness.Task.SessionGeneration);
                Assert.True(harness.Task.CanRebind);
            }
        }

        [Fact]
        public void ProductionIngressRejectsUnknownTopLevelAndPayloadKeys()
        {
            using (var harness = new ProductionHarness())
            {
                JObject top = WebRequest(
                    "snapshot", "prod.bad.top", new JObject { ["v"] = 1 });
                top["sessionGeneration"] = Generation;
                harness.Task.HandleWebRequest("snapshot", top);

                JObject payload = WebRequest(
                    "snapshot", "prod.bad.payload",
                    new JObject { ["v"] = 1, ["panelInstanceId"] = Panel });
                harness.Task.HandleWebRequest("snapshot", payload);

                Assert.Empty(harness.Flash);
                Assert.Equal(2, harness.Web.Count);
                Assert.All(
                    harness.Web,
                    response => Assert.Equal(
                        "invalid_payload", response.Value<string>("error")));
            }
        }

        [Fact]
        public void InitialTimeoutAllowsNewCallIdWithoutGenerationButSameCallIdStaysDuplicate()
        {
            using (var harness = new ProductionHarness(20))
            {
                harness.Task.HandleWebRequest(
                    "snapshot",
                    WebRequest(
                        "snapshot", "prod.initial.timeout",
                        new JObject { ["v"] = 1 }));
                Assert.True(SpinWait.SpinUntil(
                    () => harness.Web.Count == 1, 2000));
                Assert.Equal(
                    "timeout", harness.Web[0].Value<string>("error"));
                Assert.True(harness.Task.BlocksPauseReleaseAfterDisconnect);

                harness.Task.HandleWebRequest(
                    "snapshot",
                    WebRequest(
                        "snapshot", "prod.initial.timeout",
                        new JObject { ["v"] = 1 }));
                Assert.Single(harness.Flash);
                Assert.Single(harness.Web);

                harness.Task.HandleWebRequest(
                    "snapshot",
                    WebRequest(
                        "snapshot", "prod.initial.recovery",
                        new JObject { ["v"] = 1 }));
                Assert.Equal(2, harness.Flash.Count);
                Assert.Null(harness.Flash[1]["sessionGeneration"]);
                Assert.Equal(
                    "prod.initial.recovery",
                    harness.Flash[1].Value<string>("requestCallId"));
            }
        }

        [Fact]
        public void ConcurrentNewCallIdCannotStartSecondInitialSnapshot()
        {
            using (var harness = new ProductionHarness())
            {
                harness.Task.HandleWebRequest(
                    "snapshot",
                    WebRequest(
                        "snapshot",
                        "prod.initial.pending.first",
                        new JObject { ["v"] = 1 }));
                harness.Task.HandleWebRequest(
                    "snapshot",
                    WebRequest(
                        "snapshot",
                        "prod.initial.pending.second",
                        new JObject { ["v"] = 1 }));

                Assert.Single(harness.Flash);
                JObject rejection = Assert.Single(harness.Web);
                Assert.Equal("busy", rejection.Value<string>("error"));
                Assert.Equal(
                    "prod.initial.pending.second",
                    rejection.Value<string>("callId"));
            }
        }

        [Fact]
        public void LostInitialWebResponseRecoversWithoutGenerationOnSameBoundPanel()
        {
            using (var harness = OpenProductionHarness())
            {
                // Host consumed the first AS2 success and bound Generation, but the browser may
                // have lost that posted response. Simulate the loss before its new-call retry.
                harness.Flash.Clear();
                harness.Web.Clear();
                harness.Task.HandleWebRequest(
                    "snapshot",
                    WebRequest(
                        "snapshot",
                        "prod.initial.post-lost.recovery",
                        new JObject { ["v"] = 1 }));

                JObject retry = Assert.Single(harness.Flash);
                Assert.Equal(
                    "characterBuildSnapshot",
                    retry.Value<string>("action"));
                Assert.Null(retry["sessionGeneration"]);
                Assert.Equal(
                    "prod.initial.post-lost.recovery",
                    retry.Value<string>("requestCallId"));
                harness.Task.HandleFlashResponse(
                    SuccessResponse(
                        retry,
                        "snapshot",
                        Generation,
                        3,
                        3,
                        InitialDrugRevision,
                        false),
                    null);
                JObject recovered = Assert.Single(harness.Web);
                Assert.True(recovered.Value<bool>("success"));
                Assert.Equal(
                    Generation,
                    recovered.Value<long>("sessionGeneration"));
                Assert.Equal(Generation, harness.Task.SessionGeneration);

                JObject foreign = WebRequest(
                    "snapshot",
                    "prod.initial.foreign",
                    new JObject { ["v"] = 1 });
                foreign["panelInstanceId"] = "panel.workbench.foreign";
                harness.Task.HandleWebRequest("snapshot", foreign);
                Assert.Equal(
                    "panel_instance_expired",
                    harness.Web[1].Value<string>("error"));
                Assert.Single(harness.Flash);
            }
        }

        [Fact]
        public void StrictResponseRejectsInternalFieldsAndDoesNotLeakThemToWeb()
        {
            using (var harness = new ProductionHarness())
            {
                harness.Task.HandleWebRequest(
                    "snapshot",
                    WebRequest(
                        "snapshot", "prod.internal.field",
                        new JObject { ["v"] = 1 }));
                JObject response = SuccessResponse(
                    harness.Flash[0],
                    "snapshot",
                    Generation,
                    3,
                    3,
                    InitialDrugRevision,
                    false);
                response["loadoutChanged"] = false;
                harness.Task.HandleFlashResponse(response, null);

                JObject web = Assert.Single(harness.Web);
                Assert.Equal(
                    "malformed_response", web.Value<string>("error"));
                Assert.Null(web["loadoutChanged"]);
                Assert.Null(harness.Task.SessionGeneration);
            }
        }

        [Fact]
        public void ProductionSnapshotRequiresExactCompleteLoadoutProjection()
        {
            using (var harness = new ProductionHarness())
            {
                harness.Task.HandleWebRequest(
                    "snapshot",
                    WebRequest(
                        "snapshot",
                        "prod.snapshot.incomplete",
                        new JObject { ["v"] = 1 }));
                JObject response = SuccessResponse(
                    Assert.Single(harness.Flash),
                    "snapshot",
                    Generation,
                    3,
                    3,
                    InitialDrugRevision,
                    false);
                ((JObject)response["payload"]["equipment"][0])
                    .Remove("occupied");

                harness.Task.HandleFlashResponse(response, null);

                JObject web = Assert.Single(harness.Web);
                Assert.Equal(
                    "malformed_response",
                    web.Value<string>("error"));
                Assert.Null(harness.Task.SessionGeneration);
            }
        }

        [Fact]
        public void SnapshotCandidateFacetsAreOptionalButForwardedExactlyWhenValid()
        {
            using (var legacy = new ProductionHarness())
            {
                legacy.Task.HandleWebRequest(
                    "snapshot",
                    WebRequest(
                        "snapshot",
                        "prod.snapshot.facets.legacy",
                        new JObject { ["v"] = 1 }));
                legacy.Task.HandleFlashResponse(
                    SuccessResponse(
                        Assert.Single(legacy.Flash),
                        "snapshot",
                        Generation,
                        3,
                        3,
                        InitialDrugRevision,
                        false),
                    null);
                JObject web = Assert.Single(legacy.Web);
                Assert.True(web.Value<bool>("success"));
                Assert.Null(web["payload"]["candidateFacets"]);
            }

            using (var current = new ProductionHarness())
            {
                current.Task.HandleWebRequest(
                    "snapshot",
                    WebRequest(
                        "snapshot",
                        "prod.snapshot.facets.current",
                        new JObject { ["v"] = 1 }));
                JObject response = SuccessResponse(
                    Assert.Single(current.Flash),
                    "snapshot",
                    Generation,
                    3,
                    3,
                    InitialDrugRevision,
                    false);
                JObject facets = CandidateFacetProjection();
                response["payload"]["candidateFacets"] =
                    facets.DeepClone();
                current.Task.HandleFlashResponse(response, null);

                JObject web = Assert.Single(current.Web);
                Assert.True(web.Value<bool>("success"));
                Assert.True(
                    JToken.DeepEquals(
                        facets,
                        web["payload"]["candidateFacets"]));
            }
        }

        [Fact]
        public void SnapshotCandidateFacetsRejectMalformedOrInconsistentShapes()
        {
            AssertCandidateFacetRejected(
                delegate(JObject value) { value["scope"] = "equipment"; });
            AssertCandidateFacetRejected(
                delegate(JObject value) { value.Remove("scope"); });
            AssertCandidateFacetRejected(
                delegate(JObject value) { value["extra"] = true; });
            AssertCandidateFacetRejected(
                delegate(JObject value) { value["filterItemCount"] = -1; });
            AssertCandidateFacetRejected(
                delegate(JObject value) { value["filterItemCount"] = 4; });
            AssertCandidateFacetRejected(
                delegate(JObject value)
                {
                    ((JObject)value["filterFacets"][0])["count"] = 1;
                });
            AssertCandidateFacetRejected(
                delegate(JObject value)
                {
                    JArray roots = (JArray)value["filterFacets"];
                    roots.Add(roots[0].DeepClone());
                });
            AssertCandidateFacetRejected(
                delegate(JObject value)
                {
                    ((JObject)value["filterFacets"][0]["children"][0])["id"] =
                        "头部\u0001装备";
                });
        }

        [Fact]
        public void FinalizeKeepsNestedPersistenceProofAndEnablesExactClose()
        {
            using (var harness = OpenProductionHarness())
            {
                harness.Flash.Clear();
                harness.Web.Clear();
                harness.Task.HandleWebRequest(
                    "finalize",
                    WebRequest(
                        "finalize",
                        "prod.finalize",
                        ProductionPayload("finalize")));
                JObject flash = Assert.Single(harness.Flash);
                harness.Task.HandleFlashResponse(
                    SuccessResponse(
                        flash,
                        "finalize",
                        Generation,
                        3,
                        3,
                        InitialDrugRevision,
                        false),
                    null);

                JObject web = Assert.Single(harness.Web);
                Assert.True(web.Value<bool>("closed"));
                Assert.False(web.Value<bool>("active"));
                JObject persistence = Assert.IsType<JObject>(web["persistence"]);
                Assert.True(persistence.Value<bool>("success"));
                Assert.True(persistence.Value<bool>("changed"));
                Assert.Null(web["persistenceSucceeded"]);
                Assert.True(harness.Task.CanClose);
                Assert.True(harness.Task.TryClosePanelInstance(Panel));
            }
        }

        [Fact]
        public void StatsProjectionIsExactAndRequiresHealthyPlayerInfoPayload()
        {
            using (var harness = OpenProductionHarness())
            {
                harness.Flash.Clear();
                harness.Web.Clear();
                harness.Task.HandleWebRequest(
                    "statsSnapshot",
                    WebRequest(
                        "statsSnapshot",
                        "prod.stats",
                        ProductionPayload("statsSnapshot")));
                JObject response = SuccessResponse(
                    harness.Flash[0],
                    "statsSnapshot",
                    Generation,
                    3,
                    3,
                    InitialDrugRevision,
                    false);
                ((JObject)response["payload"])["success"] = true;
                harness.Task.HandleFlashResponse(response, null);
                Assert.Equal(
                    "malformed_response",
                    Assert.Single(harness.Web).Value<string>("error"));
            }
        }

        [Fact]
        public void ProductionInitialDefinitiveFailureReleasesUnopenedBarrier()
        {
            using (var harness = new ProductionHarness())
            {
                harness.Task.HandleWebRequest(
                    "snapshot",
                    WebRequest(
                        "snapshot",
                        "prod.initial.failure",
                        new JObject { ["v"] = 1 }));
                JObject flash = Assert.Single(harness.Flash);
                var response = new JObject
                {
                    ["task"] = "loadout_response",
                    ["callId"] = flash.Value<int>("callId"),
                    ["v"] = 1,
                    ["success"] = false,
                    ["command"] = "snapshot",
                    ["requestCallId"] = "prod.initial.failure",
                    ["panelInstanceId"] = Panel,
                    ["writeEpoch"] = 0,
                    ["active"] = false,
                    ["sessionGeneration"] = 0,
                    ["loadoutRevision"] = 0,
                    ["liveRevision"] = 0,
                    ["liveRefreshDirty"] = false,
                    ["drugRevision"] = 0,
                    ["error"] = "service_not_ready"
                };

                harness.Task.HandleFlashResponse(response, null);

                JObject web = Assert.Single(harness.Web);
                Assert.False(web.Value<bool>("success"));
                Assert.Equal("service_not_ready", web.Value<string>("error"));
                Assert.Null(harness.Task.SessionGeneration);
                Assert.True(harness.Task.CanRebind);
                Assert.False(harness.Task.BlocksPauseReleaseAfterDisconnect);
            }
        }

        [Fact]
        public void ProductionInitialFailureClaimingActiveIsUnknownMalformed()
        {
            using (var harness = new ProductionHarness())
            {
                harness.Task.HandleWebRequest(
                    "snapshot",
                    WebRequest(
                        "snapshot",
                        "prod.initial.failure.active",
                        new JObject { ["v"] = 1 }));
                JObject flash = Assert.Single(harness.Flash);
                var response = new JObject
                {
                    ["task"] = "loadout_response",
                    ["callId"] = flash.Value<int>("callId"),
                    ["v"] = 1,
                    ["success"] = false,
                    ["command"] = "snapshot",
                    ["requestCallId"] = "prod.initial.failure.active",
                    ["panelInstanceId"] = Panel,
                    ["writeEpoch"] = 0,
                    ["active"] = true,
                    ["sessionGeneration"] = 0,
                    ["loadoutRevision"] = 0,
                    ["liveRevision"] = 0,
                    ["liveRefreshDirty"] = false,
                    ["drugRevision"] = 0,
                    ["error"] = "service_not_ready"
                };

                harness.Task.HandleFlashResponse(response, null);

                JObject web = Assert.Single(harness.Web);
                Assert.Equal("malformed_response", web.Value<string>("error"));
                Assert.Null(harness.Task.SessionGeneration);
                Assert.False(harness.Task.CanRebind);
                Assert.True(harness.Task.BlocksPauseReleaseAfterDisconnect);
            }
        }

        [Fact]
        public void PreSendFinalizeRetryRejectionPreservesOriginalUnknownWatermark()
        {
            using (var harness = OpenProductionHarness())
            {
                harness.Flash.Clear();
                harness.Web.Clear();
                harness.Task.HandleWebRequest(
                    "finalize",
                    WebRequest(
                        "finalize",
                        "prod.finalize.unknown",
                        ProductionPayload("finalize")));
                Assert.Single(harness.Flash);

                harness.Task.HandleDisconnect();
                Assert.Equal("needs_reconcile", harness.Task.WriteState);
                harness.Ready = false;
                JObject retryPayload = ProductionPayload("finalize");
                retryPayload["reconcileAfterCallId"] =
                    "prod.finalize.unknown";
                harness.Task.HandleWebRequest(
                    "finalize",
                    WebRequest(
                        "finalize",
                        "prod.finalize.retry.offline",
                        retryPayload));

                JObject rejection = harness.Web[harness.Web.Count - 1];
                Assert.Equal("disconnected", rejection.Value<string>("error"));
                Assert.True(rejection.Value<bool>("requiresReconcile"));
                Assert.Equal(
                    "prod.finalize.unknown",
                    rejection.Value<string>("reconcileAfterCallId"));
                Assert.Single(harness.Flash);
            }
        }

        [Fact]
        public void HostShutdownFencePassesImmediatelyWithoutBindingOrSession()
        {
            using (var unbound =
                new CharacterBuildTask(_ => true))
            {
                Assert.True(
                    unbound
                        .TryCompleteHostShutdownPersistence(
                            20,
                            out string unboundOutcome));
                Assert.Equal(
                    "no_binding",
                    unboundOutcome);
            }

            using (var bound =
                new RecoveryHarness())
            {
                Assert.True(
                    bound.Task
                        .TryCompleteHostShutdownPersistence(
                            20,
                            out string boundOutcome));
                Assert.Equal(
                    "no_session",
                    boundOutcome);
                Assert.Empty(
                    bound.RecoveryFlash);
            }
        }

        [Fact]
        public void HostShutdownFencePassesImmediatelyForExactFinalizeProof()
        {
            using (var harness =
                new RecoveryHarness())
            {
                harness.OpenKnownSession();
                harness.Task.HandleWebRequest(
                    "finalize",
                    WebRequest(
                        "finalize",
                        "shutdown.finalized",
                        ProductionPayload(
                            "finalize")));
                JObject finalize =
                    Assert.Single(
                        harness.GenericFlash);
                harness.Task.HandleFlashResponse(
                    SuccessResponse(
                        finalize,
                        "finalize",
                        Generation,
                        3,
                        3,
                        InitialDrugRevision,
                        false),
                    null);
                harness.GenericFlash.Clear();

                Assert.True(
                    harness.Task
                        .TryCompleteHostShutdownPersistence(
                            20,
                            out string outcome));
                Assert.Equal(
                    "finalize_proven",
                    outcome);
                Assert.Empty(
                    harness.RecoveryFlash);
            }
        }

        [Theory]
        [InlineData(false)]
        [InlineData(true)]
        public async Task HostShutdownFenceSettlesCleanOrDirtySessionThroughExactRecovery(
            bool dirty)
        {
            using (var harness =
                new RecoveryHarness())
            {
                harness.OpenKnownSession();
                if (dirty)
                {
                    harness.Task.HandleWebRequest(
                        "equipEquipment",
                        WebRequest(
                            "equipEquipment",
                            "shutdown.dirty",
                            MutationPayload(
                                "equipEquipment")));
                    JObject mutation =
                        Assert.Single(
                            harness.GenericFlash);
                    harness.Task.HandleFlashResponse(
                        MutationSuccessResponse(
                            mutation,
                            "equipEquipment"),
                        null);
                    harness.GenericFlash.Clear();
                    harness.Web.Clear();
                    Assert.True(
                        harness.Task.LiveRefreshDirty);
                }

                string outcome = null;
                Task<bool> fence =
                    System.Threading.Tasks.Task.Run(
                        delegate
                        {
                            return harness.Task
                                .TryCompleteHostShutdownPersistence(
                                    1000,
                                    out outcome);
                        });
                Assert.True(
                    SpinWait.SpinUntil(
                        () => harness
                            .RecoveryFlash.Count == 1,
                        2000));
                JObject recovery =
                    Assert.Single(
                        harness.RecoveryFlash);
                Assert.Equal(
                    "characterBuildRecoverDetach",
                    recovery.Value<string>(
                        "action"));
                Assert.Equal(
                    harness.ReadyGeneration,
                    Assert.Single(
                        harness.RecoveryGenerations));

                long settledRevision =
                    dirty ? 4 : 3;
                harness.Task.HandleFlashResponse(
                    RecoveryResponse(
                        recovery,
                        "settled",
                        Generation,
                        settledRevision,
                        settledRevision,
                        InitialDrugRevision),
                    null);

                Assert.True(
                    await fence);
                Assert.Equal(
                    "recovery_settled",
                    outcome);
                Assert.False(
                    harness.Task.HasBoundPanel);
                Assert.False(
                    harness.Task
                        .RequiresDetachRecovery);
                Assert.Empty(
                    harness.Web);
            }
        }

        [Fact]
        public async Task HostShutdownFenceRetriesFlushFailedThroughExactRecovery()
        {
            using (var harness =
                new RecoveryHarness())
            {
                harness.OpenKnownSession();
                harness.Task.HandleWebRequest(
                    "flushLive",
                    WebRequest(
                        "flushLive",
                        "shutdown.flush.failed",
                        ProductionPayload(
                            "flushLive")));
                JObject flush =
                    Assert.Single(
                        harness.GenericFlash);
                JObject failed =
                    SuccessResponse(
                        flush,
                        "flushLive",
                        Generation,
                        3,
                        3,
                        InitialDrugRevision,
                        false);
                failed["success"] =
                    false;
                failed["error"] =
                    "flush_failed";
                harness.Task.HandleFlashResponse(
                    failed,
                    null);
                harness.GenericFlash.Clear();
                harness.Web.Clear();
                Assert.Equal(
                    "flush_failed",
                    harness.Task.WriteState);

                string outcome = null;
                Task<bool> fence =
                    System.Threading.Tasks.Task.Run(
                        delegate
                        {
                            return harness.Task
                                .TryCompleteHostShutdownPersistence(
                                    1000,
                                    out outcome);
                        });
                Assert.True(
                    SpinWait.SpinUntil(
                        () => harness
                            .RecoveryFlash.Count == 1,
                        2000));
                JObject recovery =
                    Assert.Single(
                        harness.RecoveryFlash);
                harness.Task.HandleFlashResponse(
                    RecoveryResponse(
                        recovery,
                        "settled",
                        Generation,
                        3,
                        3,
                        InitialDrugRevision),
                    null);

                Assert.True(
                    await fence);
                Assert.Equal(
                    "recovery_settled",
                    outcome);
                Assert.False(
                    harness.Task.HasBoundPanel);
            }
        }

        [Fact]
        public void HostShutdownFenceRejectsPendingAndUnknownWithoutStartingRecovery()
        {
            using (var pending =
                new RecoveryHarness())
            {
                pending.OpenKnownSession();
                pending.Task.HandleWebRequest(
                    "candidates",
                    WebRequest(
                        "candidates",
                        "shutdown.pending",
                        ProductionPayload(
                            "candidates")));
                Assert.Equal(
                    1,
                    pending.Task.PendingCount);

                Assert.False(
                    pending.Task
                        .TryCompleteHostShutdownPersistence(
                            20,
                            out string pendingOutcome));
                Assert.Equal(
                    "pending_calls",
                    pendingOutcome);
                Assert.Empty(
                    pending.RecoveryFlash);
            }

            using (var unknown =
                new ProductionHarness())
            {
                unknown.Task.HandleWebRequest(
                    "snapshot",
                    WebRequest(
                        "snapshot",
                        "shutdown.unknown.initial",
                        new JObject
                        {
                            ["v"] = 1
                        }));
                JObject initial =
                    Assert.Single(
                        unknown.Flash);
                unknown.Task.HandleFlashResponse(
                    SuccessResponse(
                        initial,
                        "snapshot",
                        Generation,
                        3,
                        3,
                        InitialDrugRevision,
                        false),
                    null);
                unknown.Flash.Clear();
                unknown.Web.Clear();
                unknown.SendSucceeds =
                    false;
                unknown.Task.HandleWebRequest(
                    "equipEquipment",
                    WebRequest(
                        "equipEquipment",
                        "shutdown.unknown.write",
                        MutationPayload(
                            "equipEquipment")));
                Assert.Equal(
                    "needs_reconcile",
                    unknown.Task.WriteState);
                int sentBeforeFence =
                    unknown.Flash.Count;

                Assert.False(
                    unknown.Task
                        .TryCompleteHostShutdownPersistence(
                            20,
                            out string unknownOutcome));
                Assert.Equal(
                    "write_state_needs_reconcile",
                    unknownOutcome);
                Assert.Equal(
                    sentBeforeFence,
                    unknown.Flash.Count);
            }
        }

        [Fact]
        public async Task HostShutdownFenceTimeoutAndRetryDoNotDuplicateRecoveryAndLateProofSettles()
        {
            using (var harness =
                new RecoveryHarness(
                    timeoutMs: 1000))
            {
                harness.OpenKnownSession();
                string firstOutcome = null;
                Task<bool> first =
                    System.Threading.Tasks.Task.Run(
                        delegate
                        {
                            return harness.Task
                                .TryCompleteHostShutdownPersistence(
                                    20,
                                    out firstOutcome);
                        });
                Assert.True(
                    SpinWait.SpinUntil(
                        () => harness
                            .RecoveryFlash.Count == 1,
                        2000));
                Assert.False(
                    await first);
                Assert.Equal(
                    "timeout",
                    firstOutcome);

                string retryOutcome = null;
                Task<bool> retry =
                    System.Threading.Tasks.Task.Run(
                        delegate
                        {
                            return harness.Task
                                .TryCompleteHostShutdownPersistence(
                                    20,
                                    out retryOutcome);
                        });
                Assert.False(
                    await retry);
                Assert.Equal(
                    "timeout",
                    retryOutcome);
                JObject recovery =
                    Assert.Single(
                        harness.RecoveryFlash);

                harness.Task.HandleFlashResponse(
                    RecoveryResponse(
                        recovery,
                        "settled",
                        Generation,
                        3,
                        3,
                        InitialDrugRevision),
                    null);
                Assert.False(
                    harness.Task.HasBoundPanel);
                Assert.True(
                    harness.Task
                        .TryCompleteHostShutdownPersistence(
                            20,
                            out string lateOutcome));
                Assert.Equal(
                    "no_binding",
                    lateOutcome);
                Assert.Single(
                    harness.RecoveryFlash);
            }
        }

        [Fact]
        public void HostShutdownFenceFailsClosedWhenExactRecoverySendIsUnknown()
        {
            using (var harness =
                new RecoveryHarness())
            {
                harness.OpenKnownSession();
                harness.RecoverySendSucceeds =
                    false;

                Assert.False(
                    harness.Task
                        .TryCompleteHostShutdownPersistence(
                            100,
                            out string outcome));
                Assert.Equal(
                    "recovery_awaiting_reconnect",
                    outcome);
                Assert.Single(
                    harness.RecoveryFlash);
                Assert.Equal(
                    new[] { 31 },
                    harness.ForcedGenerations);
                Assert.True(
                    harness.Task.HasBoundPanel);
            }
        }

        [Fact]
        public void KnownDetachRecoveryUsesExactGenerationBoundHostOnlyEnvelope()
        {
            using (var harness = new RecoveryHarness())
            {
                harness.OpenKnownSession();
                harness.ReadyGeneration = 0;
                harness.Task.HandleDisconnect(30);
                Assert.True(
                    harness.Task.RequiresDetachRecovery);
                Assert.False(harness.Task.CanRebind);

                harness.ReadyGeneration = 31;
                Assert.True(
                    harness.Task.OnSocketReconnected(31));
                JObject request =
                    Assert.Single(
                        harness.RecoveryFlash);
                Assert.Equal(
                    31,
                    Assert.Single(
                        harness.RecoveryGenerations));
                AssertExactKeys(
                    request,
                    "task",
                    "action",
                    "callId",
                    "v",
                    "panelInstanceId",
                    "requestCallId",
                    "writeEpoch",
                    "knownGeneration");
                Assert.Equal(
                    "characterBuildRecoverDetach",
                    request.Value<string>("action"));
                Assert.Equal(
                    Generation,
                    request.Value<long>(
                        "knownGeneration"));
                Assert.Empty(harness.Web);

                harness.Task.HandleFlashResponse(
                    RecoveryResponse(
                        request,
                        "settled",
                        Generation,
                        3,
                        3,
                        InitialDrugRevision),
                    null);

                Assert.False(
                    harness.Task
                        .RequiresDetachRecovery);
                Assert.False(
                    harness.Task.HasBoundPanel);
                Assert.True(
                    harness.Task.CanRebind);
                Assert.Empty(harness.Web);
            }
        }

        [Fact]
        public void RepeatedWebNavigationDetachPreservesFirstRecoveryAttempt()
        {
            using (var harness = new RecoveryHarness())
            {
                harness.OpenKnownSession();

                Assert.True(
                    harness.Task.BeginWebViewDetach(
                        harness.ReadyGeneration));
                JObject first =
                    Assert.Single(
                        harness.RecoveryFlash);
                int firstCallId =
                    first.Value<int>("callId");
                string firstRequestCallId =
                    first.Value<string>(
                        "requestCallId");

                Assert.True(
                    harness.Task.BeginWebViewDetach(
                        harness.ReadyGeneration));
                Assert.Single(
                    harness.RecoveryFlash);
                Assert.Equal(
                    firstCallId,
                    harness.RecoveryFlash[0]
                        .Value<int>("callId"));
                Assert.Equal(
                    firstRequestCallId,
                    harness.RecoveryFlash[0]
                        .Value<string>(
                            "requestCallId"));

                harness.Task.HandleFlashResponse(
                    RecoveryResponse(
                        first,
                        "settled",
                        Generation,
                        3,
                        3,
                        InitialDrugRevision),
                    null);

                Assert.False(
                    harness.Task.HasBoundPanel);
                Assert.False(
                    harness.Task
                        .RequiresDetachRecovery);
            }
        }

        [Fact]
        public void VisualRetireBarrierWithholdsRecoveryAcrossReconnectUntilHostCompletion()
        {
            using (var harness = new RecoveryHarness())
            {
                harness.OpenKnownSession();

                Assert.True(
                    harness.Task.BeginWebViewDetachBarrier());
                Assert.True(
                    harness.Task.RequiresDetachRecovery);
                Assert.Equal(
                    "awaiting_visual_retire",
                    harness.Task.DetachRecoveryStatus);
                Assert.Empty(
                    harness.RecoveryFlash);

                Assert.True(
                    harness.Task.OnSocketReconnected(
                        harness.ReadyGeneration));
                Assert.Empty(
                    harness.RecoveryFlash);

                Assert.True(
                    harness.Task
                        .ContinueDetachRecoveryAfterVisualRetired(
                            harness.ReadyGeneration));
                Assert.Single(
                    harness.RecoveryFlash);
                Assert.Equal(
                    new[] { harness.ReadyGeneration },
                    harness.RecoveryGenerations);
            }
        }

        [Fact]
        public void NormalCloseBarrierSendsNoRecoveryBeforeExactCloseCompletion()
        {
            using (var harness = new RecoveryHarness())
            {
                harness.OpenKnownSession();

                Assert.True(
                    harness.Task.BeginNormalCloseBarrier(
                        Panel));
                Assert.Equal(
                    "awaiting_visual_retire",
                    harness.Task.DetachRecoveryStatus);
                Assert.Empty(
                    harness.RecoveryFlash);

                Assert.True(
                    harness.Task.OnSocketReconnected(
                        harness.ReadyGeneration));
                Assert.Empty(
                    harness.RecoveryFlash);

                Assert.True(
                    harness.Task
                        .ContinueDetachRecoveryAfterVisualRetired(
                            harness.ReadyGeneration));
                Assert.Single(
                    harness.RecoveryFlash);
                Assert.Equal(
                    new[] { harness.ReadyGeneration },
                    harness.RecoveryGenerations);
            }
        }

        [Fact]
        public void SocketBarrierSendsNoRecoveryBeforePanelClosedEvenAfterReconnect()
        {
            using (var harness = new RecoveryHarness())
            {
                harness.OpenKnownSession();

                Assert.True(
                    harness.Task.BeginSocketDetachBarrier(
                        harness.ReadyGeneration));
                Assert.Equal(
                    "awaiting_visual_retire",
                    harness.Task.DetachRecoveryStatus);
                Assert.Empty(
                    harness.RecoveryFlash);

                harness.ReadyGeneration = 32;
                Assert.True(
                    harness.Task.OnSocketReconnected(32));
                Assert.Empty(
                    harness.RecoveryFlash);

                // This continuation models PanelHost's exact visual-retire/idle proof.
                // Reconnect alone is deliberately insufficient.
                Assert.True(
                    harness.Task
                        .ContinueDetachRecoveryAfterVisualRetired(
                            32));
                Assert.Single(
                    harness.RecoveryFlash);
                Assert.Equal(
                    new[] { 32 },
                    harness.RecoveryGenerations);
            }
        }

        [Fact]
        public void UnknownGenerationCanConsumeOnlyProvenAuthorityAbsent()
        {
            using (var exact = new RecoveryHarness())
            {
                exact.Task.HandleWebRequest(
                    "snapshot",
                    WebRequest(
                        "snapshot",
                        "recovery.unknown.exact.initial",
                        new JObject { ["v"] = 1 }));
                exact.ReadyGeneration = 0;
                exact.Task.HandleDisconnect(30);
                exact.Web.Clear();
                exact.ReadyGeneration = 32;
                Assert.True(
                    exact.Task.OnSocketReconnected(
                        32));
                JObject request =
                    Assert.Single(
                        exact.RecoveryFlash);
                Assert.Null(
                    request["knownGeneration"]);

                exact.Task.HandleFlashResponse(
                    RecoveryResponse(
                        request,
                        "settled",
                        Generation,
                        4,
                        4,
                        InitialDrugRevision),
                    null);

                Assert.False(
                    exact.Task.HasBoundPanel);
                Assert.False(
                    exact.Task
                        .RequiresDetachRecovery);
            }

            using (var harness = new RecoveryHarness())
            {
                harness.Task.HandleWebRequest(
                    "snapshot",
                    WebRequest(
                        "snapshot",
                        "recovery.unknown.initial",
                        new JObject { ["v"] = 1 }));
                Assert.Single(
                    harness.GenericFlash);
                harness.ReadyGeneration = 0;
                harness.Task.HandleDisconnect(30);
                harness.Web.Clear();

                harness.ReadyGeneration = 32;
                Assert.True(
                    harness.Task.OnSocketReconnected(32));
                JObject request =
                    Assert.Single(
                        harness.RecoveryFlash);
                Assert.Null(
                    request["knownGeneration"]);
                AssertExactKeys(
                    request,
                    "task",
                    "action",
                    "callId",
                    "v",
                    "panelInstanceId",
                    "requestCallId",
                    "writeEpoch");

                harness.Task.HandleFlashResponse(
                    RecoveryResponse(
                        request,
                        "authority_absent",
                        0,
                        0,
                        0,
                        0),
                    null);

                Assert.False(
                    harness.Task.HasBoundPanel);
                Assert.False(
                    harness.Task
                        .RequiresDetachRecovery);
                Assert.Empty(harness.Web);
            }

            using (var known = new RecoveryHarness())
            {
                known.OpenKnownSession();
                Assert.True(
                    known.Task.BeginWebViewDetach(
                        known.ReadyGeneration));
                JObject request =
                    Assert.Single(
                        known.RecoveryFlash);
                known.Task.HandleFlashResponse(
                    RecoveryResponse(
                        request,
                        "authority_absent",
                        0,
                        0,
                        0,
                        0),
                    null);

                Assert.True(
                    known.Task.HasBoundPanel);
                Assert.True(
                    known.Task
                        .RequiresDetachRecovery);
                Assert.Equal(
                    new[] { 31 },
                    known.ForcedGenerations);
            }
        }

        [Theory]
        [InlineData("dirty")]
        [InlineData("persistence")]
        [InlineData("extra")]
        [InlineData("generation")]
        public void RecoveryStrictTerminalProofRejectsMalformedOrStaleShape(
            string mutation)
        {
            using (var harness = new RecoveryHarness())
            {
                harness.OpenKnownSession();
                Assert.True(
                    harness.Task.BeginWebViewDetach(
                        harness.ReadyGeneration));
                JObject request =
                    Assert.Single(
                        harness.RecoveryFlash);
                JObject response = RecoveryResponse(
                    request,
                    "settled",
                    Generation,
                    3,
                    3,
                    InitialDrugRevision);
                if (mutation == "dirty")
                {
                    response["liveRevision"] = 2;
                    response["liveRefreshDirty"] =
                        true;
                }
                else if (mutation == "persistence")
                {
                    ((JObject)response["persistence"])
                        ["success"] = false;
                }
                else if (mutation == "extra")
                {
                    response["internal"] = true;
                }
                else
                {
                    response["sessionGeneration"] =
                        Generation + 1;
                }

                harness.Task.HandleFlashResponse(
                    response, null);

                Assert.True(
                    harness.Task.HasBoundPanel);
                Assert.True(
                    harness.Task
                        .RequiresDetachRecovery);
                Assert.Equal(
                    new[] { 31 },
                    harness.ForcedGenerations);
            }
        }

        [Fact]
        public void RecoveryRecognizesInvalidLoadoutAsKnownFailure()
        {
            using (var harness = new RecoveryHarness())
            {
                harness.OpenKnownSession();
                Assert.True(
                    harness.Task.BeginWebViewDetach(
                        31));
                JObject request =
                    Assert.Single(
                        harness.RecoveryFlash);

                harness.Task.HandleFlashResponse(
                    RecoveryResponse(
                        request,
                        "unsettled",
                        Generation,
                        3,
                        3,
                        InitialDrugRevision,
                        success: false,
                        error: "invalid_loadout"),
                    null);

                Assert.Equal(
                    "invalid_loadout",
                    harness.Task.DetachRecoveryFailure);
                Assert.Equal(
                    "awaiting_reconnect",
                    harness.Task.DetachRecoveryStatus);
                Assert.Equal(
                    new[] { 31 },
                    harness.ForcedGenerations);
            }
        }

        [Fact]
        public void NormalCloseConsumesBindingOnlyAfterAcknowledgedPauseReleaseProof()
        {
            using (var harness = new RecoveryHarness())
            {
                harness.OpenKnownSession();
                Assert.True(
                    harness.Task.BeginNormalClose(
                        31));
                JObject first =
                    Assert.Single(
                        harness.RecoveryFlash);
                Assert.True(
                    harness.Task.HasBoundPanel);

                // The Host-only request was delivered, but AS2 could not release the captured
                // lease. A successful TCP write is not permission to consume the binding.
                harness.Task.HandleFlashResponse(
                    RecoveryResponse(
                        first,
                        "unsettled",
                        Generation,
                        3,
                        3,
                        InitialDrugRevision,
                        success: false,
                        error: "pause_release_failed"),
                    null);
                Assert.True(
                    harness.Task.HasBoundPanel);
                Assert.True(
                    harness.Task.RequiresDetachRecovery);
                Assert.Equal(
                    new[] { 31 },
                    harness.ForcedGenerations);

                harness.Task.HandleDisconnect(31);
                harness.ReadyGeneration = 32;
                Assert.True(
                    harness.Task.OnSocketReconnected(
                        32));
                JObject retry =
                    harness.RecoveryFlash[1];
                harness.Task.HandleFlashResponse(
                    RecoveryResponse(
                        retry,
                        "settled",
                        Generation,
                        3,
                        3,
                        InitialDrugRevision),
                    null);

                Assert.False(
                    harness.Task.HasBoundPanel);
                Assert.False(
                    harness.Task.RequiresDetachRecovery);
            }
        }

        [Fact]
        public void RecoverySendFalseAndTimeoutRetainBindingAndCloseOnlyCapturedGeneration()
        {
            using (var failedSend =
                new RecoveryHarness())
            {
                failedSend.OpenKnownSession();
                failedSend.RecoverySendSucceeds =
                    false;
                Assert.True(
                    failedSend.Task
                        .BeginWebViewDetach(31));
                Assert.True(
                    failedSend.Task.HasBoundPanel);
                Assert.True(
                    failedSend.Task
                        .RequiresDetachRecovery);
                Assert.Equal(
                    new[] { 31 },
                    failedSend.ForcedGenerations);
            }

            using (var timed =
                new RecoveryHarness(
                    timeoutMs: 20))
            {
                timed.OpenKnownSession();
                Assert.True(
                    timed.Task
                        .BeginWebViewDetach(31));
                Assert.True(
                    SpinWait.SpinUntil(
                        () => timed
                            .ForcedGenerations.Count
                            == 1,
                        2000));
                Assert.Equal(
                    new[] { 31 },
                    timed.ForcedGenerations);
                Assert.True(
                    timed.Task.HasBoundPanel);
                Assert.True(
                    timed.Task
                        .RequiresDetachRecovery);
            }
        }

        [Fact]
        public void RecoveryFailureAttemptsOncePerGenerationAndCapsAutomaticReconnect()
        {
            using (var harness = new RecoveryHarness())
            {
                harness.OpenKnownSession();
                Assert.True(
                    harness.Task.BeginWebViewDetach(
                        31));
                JObject first =
                    Assert.Single(
                        harness.RecoveryFlash);
                JObject failed = RecoveryResponse(
                    first,
                    "unsettled",
                    Generation,
                    3,
                    3,
                    InitialDrugRevision,
                    success: false,
                    error: "flush_failed");
                harness.Task.HandleFlashResponse(
                    failed, null);

                Assert.Equal(
                    new[] { 31 },
                    harness.RecoveryGenerations);
                Assert.Equal(
                    new[] { 31 },
                    harness.ForcedGenerations);
                Assert.Equal(
                    "awaiting_reconnect",
                    harness.Task.DetachRecoveryStatus);
                harness.ReadyGeneration = 31;
                Assert.True(
                    harness.Task.OnSocketReconnected(
                        31));
                Assert.Single(
                    harness.RecoveryFlash);

                harness.ReadyGeneration = 0;
                harness.Task.HandleDisconnect(31);
                harness.ReadyGeneration = 32;
                Assert.True(
                    harness.Task.OnSocketReconnected(
                        32));
                JObject retry =
                    harness.RecoveryFlash[1];
                harness.Task.HandleFlashResponse(
                    RecoveryResponse(
                        first,
                        "settled",
                        Generation,
                        3,
                        3,
                        InitialDrugRevision),
                    null);
                Assert.True(
                    harness.Task.HasBoundPanel);

                harness.Task.HandleFlashResponse(
                    RecoveryResponse(
                        retry,
                        "unsettled",
                        Generation,
                        3,
                        3,
                        InitialDrugRevision,
                        success: false,
                        error: "flush_failed"),
                    null);
                Assert.True(
                    harness.Task.HasBoundPanel);
                Assert.Equal(
                    "fatal_blocked",
                    harness.Task.DetachRecoveryStatus);
                Assert.Equal(
                    "flush_failed",
                    harness.Task.DetachRecoveryFailure);
                Assert.Equal(
                    new[] { 31 },
                    harness.ForcedGenerations);
                Assert.Equal(
                    new[] { "fatal_blocked:flush_failed" },
                    harness.BlockedFailures);
            }
        }

        [Fact]
        public void ReconnectEpochIsolatesLateOldGenerationRecovery()
        {
            using (var harness = new RecoveryHarness())
            {
                harness.OpenKnownSession();
                Assert.True(
                    harness.Task.BeginWebViewDetach(
                        31));
                JObject old =
                    Assert.Single(
                        harness.RecoveryFlash);

                // Replacement is already current, but its UI disconnect callback has not yet
                // drained the old pending entry. The old response must not consume it.
                harness.ReadyGeneration = 32;
                harness.Task.HandleFlashResponse(
                    RecoveryResponse(
                        old,
                        "settled",
                        Generation,
                        3,
                        3,
                        InitialDrugRevision),
                    null);
                Assert.Equal(
                    1,
                    GetTrackerPendingCount(
                        harness.Task));

                harness.Task.HandleDisconnect(31);
                Assert.True(
                    harness.Task.OnSocketReconnected(
                        32));
                JObject fresh =
                    harness.RecoveryFlash[1];

                harness.Task.HandleFlashResponse(
                    RecoveryResponse(
                        fresh,
                        "settled",
                        Generation,
                        3,
                        3,
                        InitialDrugRevision),
                    null);
                Assert.False(
                    harness.Task.HasBoundPanel);
                Assert.Equal(
                    new[] { 31, 32 },
                    harness.RecoveryGenerations);
            }
        }

        [Fact]
        public void StaleProductionPendingEntriesAreRemovedOnRebindAndDispose()
        {
            var rebind = new ProductionHarness();
            try
            {
                rebind.Task.HandleWebRequest(
                    "snapshot",
                    WebRequest(
                        "snapshot",
                        "prod.pending.rebind",
                        new JObject { ["v"] = 1 }));
                Assert.Equal(
                    1,
                    GetProductionPendingCount(
                        rebind.Task));
                Assert.True(
                    rebind.Task.BindPanelInstance(
                        "panel.workbench.build.2"));
                Assert.Equal(
                    0,
                    GetProductionPendingCount(
                        rebind.Task));
            }
            finally
            {
                rebind.Dispose();
            }

            var disposed = new ProductionHarness();
            disposed.Task.HandleWebRequest(
                "snapshot",
                WebRequest(
                    "snapshot",
                    "prod.pending.dispose",
                    new JObject { ["v"] = 1 }));
            Assert.Equal(
                1,
                GetProductionPendingCount(
                    disposed.Task));
            disposed.Dispose();
            Assert.Equal(
                0,
                GetProductionPendingCount(
                    disposed.Task));
        }

        [Fact]
        public void CandidateTooltipFenceAllowsOnlyLatestValidatedSourcesIncludingBlockedRows()
        {
            using (var harness = OpenProductionHarness())
            {
                JObject request = ProductionPayload("candidates");
                request["candidateScope"] = "backpack";
                JObject item = CandidateItem("手枪", "equipment", 1);
                JObject web = CompleteCandidateResponse(
                    harness,
                    request,
                    new JObject
                    {
                        ["kind"] = "equipment",
                        ["slotKey"] = "手枪2"
                    },
                    new JArray(
                        CandidateRow(
                            2, item, false, "",
                            new JArray("手枪", "手枪2"), ""),
                        CandidateRow(
                            4,
                            (JObject)item.DeepClone(),
                            true,
                            "level_locked",
                            new JArray("手枪", "手枪2"),
                            "level_locked"),
                        CandidateRow(
                            6,
                            CandidateItem("刀", "equipment", 1),
                            true,
                            "incompatible_item",
                            new JArray("刀"),
                            "")));

                JObject allowed = (JObject)web["payload"]["candidates"][1]["source"];
                JObject normalized;
                Func<bool> fence;
                Assert.True(harness.Task.TryCaptureCandidateTooltipFence(
                    Panel, Generation, allowed, out normalized, out fence));
                Assert.Equal(4, normalized.Value<int>("slot"));
                Assert.True(fence());
                Func<bool> allowedFence = fence;

                JObject crossSlot =
                    (JObject)web["payload"]["candidates"][2]["source"];
                Assert.True(harness.Task.TryCaptureCandidateTooltipFence(
                    Panel,
                    Generation,
                    crossSlot,
                    out JObject crossSlotNormalized,
                    out Func<bool> crossSlotFence));
                Assert.Equal(6, crossSlotNormalized.Value<int>("slot"));
                Assert.True(crossSlotFence());

                JObject forged = (JObject)allowed.DeepClone();
                forged["expectedLease"] = "inv.candidate.forged";
                Assert.False(harness.Task.TryCaptureCandidateTooltipFence(
                    Panel, Generation, forged, out normalized, out fence));
                Assert.False(harness.Task.TryCaptureCandidateTooltipFence(
                    "panel.workbench.replaced",
                    Generation,
                    allowed,
                    out normalized,
                    out fence));
                Assert.False(harness.Task.TryCaptureCandidateTooltipFence(
                    Panel,
                    Generation + 1,
                    allowed,
                    out normalized,
                    out fence));

                JObject secondRequest = ProductionPayload("candidates");
                secondRequest["candidateScope"] = "backpack";
                harness.Task.HandleWebRequest(
                    "candidates",
                    WebRequest(
                        "candidates",
                        "prod.tooltip.second-candidates.invalidate",
                        secondRequest));
                Assert.False(allowedFence());
                Assert.False(crossSlotFence());
            }
        }

        [Fact]
        public void CandidateTooltipFenceExpiresOnSnapshotWriteAndPanelReplacement()
        {
            using (var snapshotHarness = OpenProductionHarness())
            {
                JObject source = CaptureCandidateTooltipSource(
                    snapshotHarness, out Func<bool> snapshotFence);
                long snapshotEpoch =
                    snapshotHarness.Task.CandidateTooltipEpoch;
                snapshotHarness.Task.HandleWebRequest(
                    "snapshot",
                    WebRequest(
                        "snapshot",
                        "prod.tooltip.snapshot.invalidate",
                        new JObject
                        {
                            ["v"] = 1,
                            ["sessionGeneration"] = Generation
                        }));
                Assert.True(
                    snapshotHarness.Task.CandidateTooltipEpoch > snapshotEpoch);
                Assert.False(snapshotFence());
                Assert.False(snapshotHarness.Task.TryCaptureCandidateTooltipFence(
                    Panel,
                    Generation,
                    source,
                    out _,
                    out _));
            }

            using (var writeHarness = OpenProductionHarness())
            {
                CaptureCandidateTooltipSource(
                    writeHarness, out Func<bool> writeFence);
                writeHarness.Task.HandleWebRequest(
                    "equipEquipment",
                    WebRequest(
                        "equipEquipment",
                        "prod.tooltip.write.invalidate",
                        MutationPayload("equipEquipment")));
                Assert.False(writeFence());
            }

            using (var replaceHarness = OpenProductionHarness())
            {
                CaptureCandidateTooltipSource(
                    replaceHarness, out Func<bool> replaceFence);
                Assert.True(replaceHarness.Task.BindPanelInstance(
                    "panel.workbench.replaced"));
                Assert.False(replaceFence());
            }
        }

        private static ProductionHarness OpenProductionHarness(
            int timeoutMs = 1000)
        {
            var harness = new ProductionHarness(timeoutMs);
            harness.Task.HandleWebRequest(
                "snapshot",
                WebRequest(
                    "snapshot",
                    "prod.fixture.initial",
                    new JObject { ["v"] = 1 }));
            JObject flash = Assert.Single(harness.Flash);
            harness.Task.HandleFlashResponse(
                SuccessResponse(
                    flash,
                    "snapshot",
                    Generation,
                    3,
                    3,
                    InitialDrugRevision,
                    false),
                null);
            Assert.Equal(Generation, harness.Task.SessionGeneration);
            return harness;
        }

        private static JObject CaptureCandidateTooltipSource(
            ProductionHarness harness,
            out Func<bool> fence)
        {
            JObject web = CompleteCandidateResponse(
                harness,
                ProductionPayload("candidates"),
                new JObject
                {
                    ["kind"] = "equipment",
                    ["slotKey"] = "手枪2"
                },
                new JArray(CandidateRow(
                    2,
                    CandidateItem("手枪", "equipment", 1),
                    false,
                    "")));
            JObject source =
                (JObject)web["payload"]["candidates"][0]["source"];
            JObject normalized;
            Assert.True(harness.Task.TryCaptureCandidateTooltipFence(
                Panel,
                Generation,
                source,
                out normalized,
                out fence));
            return normalized;
        }

        private static JObject WebRequest(
            string command,
            string callId,
            JObject payload)
        {
            return new JObject
            {
                ["type"] = "panel",
                ["panel"] = "workbench",
                ["domain"] = "loadout",
                ["cmd"] = command,
                ["callId"] = callId,
                ["panelInstanceId"] = Panel,
                ["payload"] = payload
            };
        }

        private static JObject ProductionPayload(string command)
        {
            if (command == "tooltip")
            {
                return new JObject
                {
                    ["v"] = 1,
                    ["sessionGeneration"] = Generation,
                    ["expectedLoadoutRevision"] = 3,
                    ["expectedDrugRevision"] = InitialDrugRevision,
                    ["slotKey"] = "手枪2"
                };
            }
            if (command == "candidates")
            {
                return new JObject
                {
                    ["v"] = 1,
                    ["sessionGeneration"] = Generation,
                    ["expectedLoadoutRevision"] = 3,
                    ["expectedDrugRevision"] = InitialDrugRevision,
                    ["candidateScope"] = "compatible",
                    ["slotKey"] = "手枪2"
                };
            }
            if (command == "statsSnapshot")
            {
                return new JObject
                {
                    ["v"] = 1,
                    ["sessionGeneration"] = Generation,
                    ["expectedLoadoutRevision"] = 3,
                    ["expectedLiveRevision"] = 3
                };
            }
            return new JObject
            {
                ["v"] = 1,
                ["sessionGeneration"] = Generation,
                ["expectedLoadoutRevision"] = 3
            };
        }

        private static JObject MutationPayload(string command)
        {
            bool equipment = command.EndsWith(
                "Equipment", StringComparison.Ordinal);
            bool equip = command.StartsWith(
                "equip", StringComparison.Ordinal);
            var payload = new JObject
            {
                ["v"] = 1,
                ["sessionGeneration"] = Generation
            };
            if (equipment)
            {
                payload["expectedLoadoutRevision"] = 3;
                payload["slotKey"] = "手枪2";
            }
            else
            {
                payload["expectedDrugRevision"] = InitialDrugRevision;
                payload["drugSlot"] = 1;
            }
            if (equip)
            {
                payload["source"] = new JObject
                {
                    ["containerId"] = "背包",
                    ["slot"] = 6,
                    ["expectedLease"] = "lease.bag.6"
                };
            }
            return payload;
        }

        private static JObject MutationSuccessResponse(
            JObject flash,
            string command,
            bool changed = true)
        {
            bool equipment = command.EndsWith(
                "Equipment", StringComparison.Ordinal);
            int affectedSlot = command.StartsWith(
                "equip", StringComparison.Ordinal)
                ? 6 : equipment ? 8 : 9;
            long loadoutRevision = equipment && changed ? 4 : 3;
            long drugRevision = !equipment && changed
                ? InitialDrugRevision + 1 : InitialDrugRevision;
            JObject response = SuccessResponse(
                flash,
                command,
                Generation,
                loadoutRevision,
                3,
                drugRevision,
                loadoutRevision != 3);
            response["changed"] = changed;
            response["operation"] = command;
            response["affectedBackpackSlot"] = affectedSlot;
            response["payload"] = FullLoadoutPayload(command, changed);
            response["inventorySnapshots"] =
                FullBackpackSnapshots(command, affectedSlot, changed);
            return response;
        }

        private static JObject MutationFailureResponse(
            JObject flash,
            string command,
            string error,
            long loadoutRevision = 3,
            long liveRevision = 3,
            long drugRevision = InitialDrugRevision)
        {
            JObject response = SuccessResponse(
                flash,
                command,
                Generation,
                loadoutRevision,
                liveRevision,
                drugRevision,
                loadoutRevision != liveRevision);
            response["success"] = false;
            response["error"] = error;
            return response;
        }

        private static JObject MutationReconcileResponse(
            JObject flash,
            string reconcileAfterCallId,
            bool mutationApplied)
        {
            JObject response = SuccessResponse(
                flash,
                "snapshot",
                Generation,
                mutationApplied ? 4 : 3,
                3,
                InitialDrugRevision,
                mutationApplied);
            response["reconcileAfterCallId"] =
                reconcileAfterCallId;
            response["payload"] = FullLoadoutPayload(
                "equipEquipment",
                mutationApplied);
            response["inventorySnapshots"] =
                FullBackpackSnapshots(
                    "equipEquipment",
                    6,
                    mutationApplied);
            return response;
        }

        private static JObject FullLoadoutPayload(
            string command,
            bool changed)
        {
            string[] slotKeys = {
                "头部装备", "上装装备", "下装装备", "手部装备", "脚部装备", "颈部装备",
                "长枪", "手枪", "手枪2", "刀", "手雷"
            };
            string[] labels = {
                "头部", "上装", "下装", "手部", "脚部", "颈部",
                "长枪", "主手手枪", "副手手枪", "刀", "手雷"
            };
            var equipment = new JArray();
            for (int i = 0; i < slotKeys.Length; i++)
            {
                equipment.Add(new JObject
                {
                    ["slotKey"] = slotKeys[i],
                    ["label"] = labels[i],
                    ["occupied"] = false
                });
            }

            bool equipmentCommand = command.EndsWith(
                "Equipment", StringComparison.Ordinal);
            bool equip = command.StartsWith(
                "equip", StringComparison.Ordinal);
            var portraitEquipment = new JObject();
            if (equipmentCommand && equip && changed)
            {
                JObject target = (JObject)equipment[8];
                target["occupied"] = true;
                target["item"] = CandidateItem(
                    "手枪", "equipment", 1);
                portraitEquipment["手枪2"] =
                    target["item"].Value<string>("name");
            }

            var drugs = new JArray();
            for (int slot = 0; slot < 4; slot++)
            {
                drugs.Add(new JObject
                {
                    ["slot"] = slot,
                    ["keyLabel"] = (slot + 1).ToString(),
                    ["ready"] = true,
                    ["totalSteps"] = 0,
                    ["currentStep"] = 0,
                    ["progressPercent"] = 0,
                    ["animationFrame"] = 1,
                    ["remainingMs"] = 0,
                    ["occupied"] = false,
                    ["quantity"] = 0
                });
            }
            if (!equipmentCommand && equip && changed)
            {
                JObject target = (JObject)drugs[1];
                target["occupied"] = true;
                target["quantity"] = 3;
                target["item"] = CandidateItem(
                    "药剂", "stack", 3);
            }

            return new JObject
            {
                ["equipment"] = equipment,
                ["drugs"] = drugs,
                ["portrait"] = new JObject
                {
                    ["gender"] = "男",
                    ["equipment"] = portraitEquipment,
                    ["appearance"] = new JObject
                    {
                        ["脸型"] = "默认脸型",
                        ["发型"] = "默认发型"
                    }
                },
                ["stateHealth"] = "ok",
                ["diagnostics"] = new JArray()
            };
        }

        private static JArray FullBackpackSnapshots(
            string command,
            int affectedSlot,
            bool changed)
        {
            bool unequip = command.StartsWith(
                "unequip", StringComparison.Ordinal);
            bool equipment = command.EndsWith(
                "Equipment", StringComparison.Ordinal);
            JObject affectedItem = null;
            if (changed && unequip)
            {
                affectedItem = equipment
                    ? CandidateItem("手枪", "equipment", 1)
                    : CandidateItem("药剂", "stack", 3);
            }
            else if (changed && command == "equipDrug")
            {
                affectedItem = CandidateItem("药剂", "stack", 2);
            }

            var slots = new JArray();
            for (int slot = 0; slot < 50; slot++)
            {
                bool occupied = slot == affectedSlot
                    && affectedItem != null;
                var row = new JObject
                {
                    ["physicalSlot"] = slot,
                    ["occupied"] = occupied,
                    ["slotLease"] = "lease.post.1." + slot
                };
                if (occupied)
                {
                    row["item"] = affectedItem.DeepClone();
                    row["confirmProjection"] =
                        ConfirmProjection((JObject)row["item"]);
                }
                slots.Add(row);
            }

            var facets = new JArray();
            if (affectedItem != null)
            {
                bool itemEquipment =
                    affectedItem.Value<string>("itemKind") == "equipment";
                string major = itemEquipment ? "weapon" : "consumable";
                string majorLabel = itemEquipment ? "武器" : "消耗品";
                string use = affectedItem.Value<string>("use");
                var useChildren = new JArray();
                if (itemEquipment)
                {
                    useChildren.Add(Facet(
                        "其他", "其他", 1, new JArray()));
                }
                facets.Add(Facet(
                    major,
                    majorLabel,
                    1,
                    new JArray(Facet(
                        use,
                        use,
                        1,
                        useChildren))));
            }

            return new JArray(new JObject
            {
                ["containerId"] = "背包",
                ["capacity"] = 50,
                ["accessibleCapacity"] = 50,
                ["viewCapacity"] = 50,
                ["filterKey"] = "all",
                ["pageSizeHint"] = 50,
                ["locked"] = false,
                ["snapshotSeq"] = 2,
                ["containerEpoch"] = 1,
                ["containerVersion"] = changed ? 2 : 1,
                ["offset"] = 0,
                ["limit"] = 50,
                ["slots"] = slots,
                ["filterFacets"] = facets,
                ["filterItemCount"] = affectedItem == null ? 0 : 1,
                ["setFacets"] = new JArray(),
                ["setFilterItemCount"] = 0
            });
        }

        private static JObject ConfirmProjection(JObject item)
        {
            return new JObject
            {
                ["itemKind"] = item.Value<string>("itemKind"),
                ["name"] = item.Value<string>("name"),
                ["displayName"] = item.Value<string>("displayName"),
                ["quantity"] = item.Value<double>("quantity"),
                ["enhancementLevel"] =
                    item.Value<int>("enhancementLevel"),
                ["rarity"] = item.Value<string>("rarity"),
                ["tier"] = "",
                ["modSignature"] = "",
                ["lastUpdate"] = 0
            };
        }

        private static JObject Facet(
            string id,
            string label,
            int count,
            JArray children)
        {
            return new JObject
            {
                ["id"] = id,
                ["label"] = label,
                ["order"] = 0,
                ["count"] = count,
                ["children"] = children
            };
        }

        private static JObject CandidateFacetProjection()
        {
            return new JObject
            {
                ["scope"] = "all",
                ["filterFacets"] = new JArray(
                    Facet(
                        "armor",
                        "防具",
                        2,
                        new JArray(
                            Facet(
                                "头部装备",
                                "头部装备",
                                2,
                                new JArray()))),
                    Facet(
                        "weapon",
                        "武器",
                        3,
                        new JArray(
                            Facet(
                                "手枪",
                                "手枪",
                                2,
                                new JArray(
                                    Facet(
                                        "自动手枪",
                                        "自动手枪",
                                        2,
                                        new JArray()))),
                            Facet(
                                "刀",
                                "刀",
                                1,
                                new JArray())))),
                ["filterItemCount"] = 5
            };
        }

        private static void AssertCandidateFacetRejected(
            Action<JObject> mutate)
        {
            using (var harness = new ProductionHarness())
            {
                harness.Task.HandleWebRequest(
                    "snapshot",
                    WebRequest(
                        "snapshot",
                        "prod.snapshot.facets.invalid",
                        new JObject { ["v"] = 1 }));
                JObject response = SuccessResponse(
                    Assert.Single(harness.Flash),
                    "snapshot",
                    Generation,
                    3,
                    3,
                    InitialDrugRevision,
                    false);
                JObject facets = CandidateFacetProjection();
                mutate(facets);
                response["payload"]["candidateFacets"] = facets;
                harness.Task.HandleFlashResponse(response, null);

                JObject web = Assert.Single(harness.Web);
                Assert.Equal(
                    "malformed_response",
                    web.Value<string>("error"));
                Assert.Null(harness.Task.SessionGeneration);
            }
        }

        private static JObject CandidateItem(
            string use,
            string itemKind,
            double quantity)
        {
            bool equipment = itemKind == "equipment";
            return new JObject
            {
                ["name"] = use + "测试物品",
                ["displayName"] = use + "测试物品",
                ["icon"] = use + "测试图标",
                ["majorType"] = equipment ? "武器" : "消耗品",
                ["use"] = use,
                ["actionType"] = "",
                ["weaponType"] = "",
                ["setId"] = "",
                ["setName"] = "",
                ["setOrder"] = 0,
                ["itemKind"] = itemKind,
                ["quantity"] = quantity,
                ["enhancementLevel"] = 0,
                ["maxEnhancementLevel"] = 12,
                ["isMaxEnhancement"] = false,
                ["tierSlotAvailable"] = false,
                ["tierSlotUsed"] = false,
                ["modSlotCapacity"] = 0,
                ["modSlotUsed"] = 0,
                ["modSlots"] = new JArray(),
                ["modMeta"] = JValue.CreateNull(),
                ["rarity"] = ""
            };
        }

        private static JObject ModProjection(
            string name,
            string displayName,
            string icon)
        {
            return new JObject
            {
                ["name"] = name,
                ["displayName"] = displayName,
                ["icon"] = icon,
                ["grade"] = "common",
                ["gradeLabel"] = "普通",
                ["gradeColor"] = "#FFFFFF",
                ["role"] = "utility",
                ["roleLabel"] = "功能",
                ["symbol"] = "diamond-outline",
                ["scope"] = "all"
            };
        }

        private static JObject CandidateRow(
            int physicalSlot,
            JObject item,
            bool disabled,
            string blockedReason,
            JArray equipmentSlots = null,
            string equipmentBlockedReason = null)
        {
            var row = new JObject
            {
                ["physicalSlot"] = physicalSlot,
                ["disabled"] = disabled,
                ["blockedReason"] = blockedReason,
                ["item"] = item,
                ["source"] = new JObject
                {
                    ["containerId"] = "背包",
                    ["slot"] = physicalSlot,
                    ["expectedLease"] = "inv.candidate." + physicalSlot
                }
            };
            if (equipmentSlots != null)
            {
                row["equipmentEligibility"] = new JObject
                {
                    ["slots"] = equipmentSlots,
                    ["blockedReason"] = equipmentBlockedReason ?? ""
                };
            }
            return row;
        }

        private static JObject CompleteCandidateResponse(
            ProductionHarness harness,
            JObject request,
            JObject target,
            JArray candidates)
        {
            harness.Flash.Clear();
            harness.Web.Clear();
            harness.Task.HandleWebRequest(
                "candidates",
                WebRequest(
                    "candidates",
                    "prod.candidates.valid." + target.Value<string>("kind"),
                    request));
            JObject response = SuccessResponse(
                Assert.Single(harness.Flash),
                "candidates",
                Generation,
                3,
                3,
                InitialDrugRevision,
                false);
            response["payload"]["target"] = target;
            response["payload"]["candidates"] = candidates;
            harness.Task.HandleFlashResponse(response, null);
            return Assert.Single(harness.Web);
        }

        private static JObject SuccessResponse(
            JObject flash,
            string command,
            long generation,
            long loadoutRevision,
            long liveRevision,
            long drugRevision,
            bool dirty)
        {
            bool finalize = command == "finalize";
            var result = new JObject
            {
                ["task"] = "loadout_response",
                ["callId"] = flash.Value<int>("callId"),
                ["v"] = 1,
                ["success"] = true,
                ["command"] = command,
                ["requestCallId"] = flash.Value<string>("requestCallId"),
                ["panelInstanceId"] = flash.Value<string>("panelInstanceId"),
                ["writeEpoch"] = flash.Value<int>("writeEpoch"),
                ["active"] = !finalize,
                ["sessionGeneration"] = generation,
                ["loadoutRevision"] = loadoutRevision,
                ["liveRevision"] = liveRevision,
                ["liveRefreshDirty"] = dirty,
                ["drugRevision"] = drugRevision
            };
            if (command == "snapshot")
            {
                result["payload"] =
                    FullLoadoutPayload(command, false);
            }
            else if (command == "candidates")
            {
                result["payload"] = new JObject
                {
                    ["target"] = new JObject
                    {
                        ["kind"] = "equipment",
                        ["slotKey"] = "手枪2"
                    },
                    ["candidateScope"] = flash.Value<string>("candidateScope"),
                    ["candidates"] = new JArray(),
                    ["backpackVersion"] = 5,
                    ["stateHealth"] = "ok",
                    ["diagnostics"] = new JArray()
                };
            }
            else if (command == "tooltip")
            {
                JObject target;
                if (flash["slotKey"] != null)
                {
                    target = new JObject
                    {
                        ["kind"] = "equipment",
                        ["slotKey"] = flash.Value<string>("slotKey")
                    };
                }
                else
                {
                    target = new JObject
                    {
                        ["kind"] = "drug",
                        ["drugSlot"] = flash.Value<int>("drugSlot")
                    };
                }
                result["payload"] = new JObject
                {
                    ["v"] = 1,
                    ["target"] = target,
                    ["itemName"] = "权威内部名",
                    ["displayName"] = "权威展示名",
                    ["iconName"] = "权威图标名",
                    ["itemType"] = "武器",
                    ["descHTML"] = "权威说明",
                    ["introHTML"] = "权威简介"
                };
            }
            else if (command == "statsSnapshot")
            {
                result["payload"] = new JObject
                {
                    ["v"] = 1,
                    ["stateHealth"] = "ok",
                    ["diagnostics"] = new JArray(),
                    ["groups"] = new JArray()
                };
            }
            else if (command == "flushLive")
            {
                result["changed"] = false;
            }
            else if (command == "finalize")
            {
                result["closed"] = true;
                result["liveChanged"] = false;
                result["persistence"] = new JObject
                {
                    ["success"] = true,
                    ["changed"] = true
                };
            }
            return result;
        }

        private static JObject RecoveryResponse(
            JObject flash,
            string recoveryState,
            long generation,
            long loadoutRevision,
            long liveRevision,
            long drugRevision,
            bool success = true,
            string error = null)
        {
            var result = new JObject
            {
                ["task"] = "loadout_response",
                ["callId"] =
                    flash.Value<int>("callId"),
                ["v"] = 1,
                ["success"] = success,
                ["command"] = "recoverDetach",
                ["requestCallId"] =
                    flash.Value<string>(
                        "requestCallId"),
                ["panelInstanceId"] =
                    flash.Value<string>(
                        "panelInstanceId"),
                ["writeEpoch"] =
                    flash.Value<int>("writeEpoch"),
                ["active"] = !success,
                ["sessionGeneration"] =
                    generation,
                ["loadoutRevision"] =
                    loadoutRevision,
                ["liveRevision"] =
                    liveRevision,
                ["liveRefreshDirty"] =
                    loadoutRevision != liveRevision,
                ["drugRevision"] =
                    drugRevision,
                ["recoveryState"] =
                    recoveryState,
                ["closed"] = success,
                ["pauseReleased"] = success,
                ["persistence"] =
                    new JObject
                    {
                        ["success"] = success,
                        ["changed"] =
                            success
                                && recoveryState
                                    == "settled"
                    }
            };
            if (!success)
                result["error"] =
                    error ?? "internal_error";
            return result;
        }

        private static void AssertExactKeys(
            JObject value,
            params string[] expected)
        {
            var actual = new HashSet<string>(StringComparer.Ordinal);
            foreach (JProperty property in value.Properties())
                actual.Add(property.Name);
            Assert.Equal(expected.Length, actual.Count);
            foreach (string key in expected) Assert.Contains(key, actual);
        }

        [Fact]
        public void ShutdownAdmissionGateRejectsNewBindingAndBackendRequest()
        {
            bool admissionOpen = true;
            using (var task =
                new CharacterBuildTask(
                    delegate { return true; }))
            {
                task.SetAdmissionGate(
                    delegate
                    {
                        return admissionOpen;
                    });
                const string instance =
                    "panel.workbench.shutdown.gate";
                Assert.True(
                    task.TryBindPanelInstance(
                        instance));

                admissionOpen = false;
                Assert.False(
                    task.TryBindPanelInstance(
                        instance));
                Assert.False(
                    task.TryBeginHostAccepted(
                        instance,
                        null,
                        "shutdown.gate.snapshot",
                        "snapshot",
                        null,
                        out int backendCallId,
                        out string error));
                Assert.Equal(0, backendCallId);
                Assert.Equal(
                    "host_closing",
                    error);
                Assert.Equal(
                    0,
                    task.PendingCount);
            }
        }

        private static CharacterBuildTask NewTask(
            Func<string, bool> send = null,
            int timeoutMs = 1000)
        {
            return new CharacterBuildTask(send ?? (_ => true), timeoutMs);
        }

        private static CharacterBuildTask BoundTask(
            Func<string, bool> send = null,
            int timeoutMs = 1000)
        {
            CharacterBuildTask task = NewTask(send, timeoutMs);
            Assert.True(task.BindPanelInstance(Panel));
            AcceptedCall initial = Begin(
                task, Panel, null, "build.fixture.initial", "snapshot");
            CompleteSuccess(
                task,
                initial,
                Panel,
                Generation,
                3,
                3,
                InitialDrugRevision,
                false);
            return task;
        }

        private static AcceptedCall Begin(
            CharacterBuildTask task,
            string panel,
            long? generation,
            string callId,
            string command,
            string reconcileAfterCallId = null)
        {
            Assert.True(task.TryBeginHostAccepted(
                panel,
                generation,
                callId,
                command,
                reconcileAfterCallId,
                out int backendCallId,
                out string error),
                error);
            return new AcceptedCall
            {
                BackendCallId = backendCallId,
                WebCallId = callId,
                Command = command,
                WriteEpoch = task.WriteEpoch
            };
        }

        private static void AssertBeginFails(
            CharacterBuildTask task,
            string panel,
            long? generation,
            string callId,
            string command,
            string reconcileAfterCallId,
            string expectedError)
        {
            Assert.False(task.TryBeginHostAccepted(
                panel,
                generation,
                callId,
                command,
                reconcileAfterCallId,
                out int backendCallId,
                out string error));
            Assert.Equal(0, backendCallId);
            Assert.Equal(expectedError, error);
        }

        private static void CompleteSuccess(
            CharacterBuildTask task,
            AcceptedCall call,
            string panel,
            long? generation,
            long loadoutRevision,
            long liveRevision,
            long drugRevision,
            bool liveRefreshDirty,
            bool? responseActive = null,
            bool? responseClosed = null,
            bool? persistenceSucceeded = null)
        {
            bool finalize = call.Command == "finalize";
            Assert.True(task.TryCompleteSuccess(
                call.BackendCallId,
                panel,
                generation,
                call.WebCallId,
                call.Command,
                call.WriteEpoch,
                loadoutRevision,
                liveRevision,
                drugRevision,
                liveRefreshDirty,
                responseActive ?? !finalize,
                responseClosed ?? (finalize ? true : (bool?)null),
                persistenceSucceeded ?? (finalize ? true : (bool?)null),
                out string error),
                error);
        }

        private static void CompleteKnownFailure(
            CharacterBuildTask task,
            AcceptedCall call,
            string panel,
            long? generation,
            string failureCode,
            long? loadoutRevision = null,
            long? liveRevision = null,
            long? drugRevision = null,
            bool? liveRefreshDirty = null)
        {
            Assert.True(task.TryCompleteKnownFailure(
                call.BackendCallId,
                panel,
                generation,
                call.WebCallId,
                call.Command,
                call.WriteEpoch,
                true,
                failureCode,
                loadoutRevision,
                liveRevision,
                drugRevision,
                liveRefreshDirty,
                out string error),
                error);
        }

        private static object GetPrivateField(object instance, string name)
        {
            FieldInfo field = instance.GetType().GetField(
                name, BindingFlags.Instance | BindingFlags.NonPublic);
            Assert.NotNull(field);
            object value = field.GetValue(instance);
            Assert.NotNull(value);
            return value;
        }

        private static int GetTrackerPendingCount(CharacterBuildTask task)
        {
            object tracker = GetPrivateField(task, "_pendingCalls");
            object trackerGate = GetPrivateField(tracker, "_gate");
            IDictionary pending = Assert.IsAssignableFrom<IDictionary>(
                GetPrivateField(tracker, "_pending"));
            lock (trackerGate) return pending.Count;
        }

        private static int GetProductionPendingCount(
            CharacterBuildTask task)
        {
            IDictionary pending = Assert.IsAssignableFrom<IDictionary>(
                GetPrivateField(task, "_productionPending"));
            return pending.Count;
        }
    }
}
