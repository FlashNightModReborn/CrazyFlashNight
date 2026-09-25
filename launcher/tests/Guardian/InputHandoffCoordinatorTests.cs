using System;
using System.Collections.Generic;
using CF7Launcher.Guardian.InputOwnership;
using Xunit;

namespace CF7Launcher.Tests.Guardian;

public sealed class InputHandoffCoordinatorTests
{
    [Fact] public void RetainedConstructionSurvivesGeometryButCannotGrantWithoutFreshCoverageAndNeutral()
    {
        var (ledger, owner) = Create(); var gesture = owner.Begin(M, Edge(ledger, true), 1).Value;
        var intent = owner.CompleteAndHandoff(gesture, Edge(ledger, false), 1, Web, "surgery").Value;
        Assert.False(owner.ConsumeIntentForRetainedPreparation(intent)); CancelAll(owner);
        Assert.True(owner.ConsumeIntentForRetainedPreparation(intent));
        Assert.False(owner.ConsumeIntentForRetainedPreparation(intent));
        var stale = owner.Round; Edge(ledger, true, 2); owner.SetEnvironment(true, 2);
        Assert.Null(owner.Owner); Assert.Equal(Web, owner.PreparingOwner);
        Assert.False(owner.AcceptCancelled(new(stale, Web, true, true)));
        Assert.False(owner.TryGrant(true)); CancelAll(owner); Assert.False(owner.TryPrepare(out _));
        Edge(ledger, false, 2); PrepareAndGrant(owner); Assert.Equal(Web, owner.Owner);
        Assert.Null(owner.HandoffCompleted(gesture, Web, "surgery"));
    }
    [Fact] public void RetainedConstructionFailureBlocksInsteadOfGrantingWorldBehindPage()
    {
        var (ledger, owner) = Create(); var gesture = owner.Begin(M, Edge(ledger, true), 1).Value;
        var intent = owner.CompleteAndHandoff(gesture, Edge(ledger, false), 1, Web, "surgery").Value;
        CancelAll(owner); Assert.True(owner.ConsumeIntentForRetainedPreparation(intent));
        owner.Fail("page_construction_failed"); CancelAll(owner);
        Assert.Equal(InputHandoffPhase.Blocked, owner.Phase); Assert.Null(owner.Owner);
        Assert.False(owner.TryPrepare(out _)); Assert.False(owner.TryGrant(true));
        Assert.False(owner.ConsumeIntentForRetainedPreparation(intent));
    }
    [Fact] public void ReadOnlyHoverCanCloseImmediatelyButCannotGrantWhileKeyIsHeld()
    {
        var (ledger, owner) = Create(); Edge(ledger, true, 2);
        Assert.True(owner.SelectReadOnlyHover(Native));
        Assert.Equal(ObservedKeyState.Down, ledger[2]); CancelAll(owner);
        Assert.False(owner.TryPrepare(out _)); Edge(ledger, false, 2);
        PrepareAndGrant(owner); Assert.Equal(Native, owner.Owner);
    }
    [Fact] public void RetiredEndpointNeedsNewIncarnationAndNewCoverageAcknowledgements()
    {
        var (_, owner) = Create(false); var nextWeb = new InputScope("Web", 2);
        Assert.False(owner.ReplaceRetiredScope(Web, nextWeb, M, false));
        CancelAll(owner); var oldRound = owner.Round;
        Assert.True(owner.ReplaceRetiredScope(Web, nextWeb, M, false));
        Assert.False(owner.AcceptCancelled(new(oldRound, Web, true, true)));
        Assert.False(owner.AcceptCancelled(new(owner.Round, Web, true, true)));
        foreach (var scope in new[] { M, nextWeb, Native }) Assert.True(owner.AcceptCancelled(new(owner.Round, scope, true, true)));
        Assert.True(owner.TryPrepare(out var prefix));
        foreach (var scope in new[] { M, nextWeb, Native }) Assert.True(owner.AcceptPrepared(new(owner.Round, scope, prefix)));
        Assert.True(owner.TryGrant(true)); Assert.Equal(M, owner.Owner);
    }
    [Fact] public void FastSourceRecoveryCannotHideGenerationChangeBetweenCoordinatorTurns()
    {
        var (ledger, owner) = Create(); var oldRound = owner.Round;
        ledger.Invalidate("source_restarted"); ledger.ConfirmSources(ledger.Prefix);
        ledger.TryReconcile(ledger.Prefix, Snapshot(), Snapshot(), true, true);
        owner.ObservationChanged();
        Assert.Equal(InputHandoffPhase.Revoking, owner.Phase); Assert.NotEqual(oldRound, owner.Round);
        CancelAll(owner); PrepareAndGrant(owner);
        Assert.NotNull(owner.Begin(M, Edge(ledger, true), 1));
    }
    [Fact] public void RealEndWaitsForQualifiedReconciliationWithoutInventingAnotherRelease()
    {
        var (ledger, owner) = Create(); var gesture = owner.Begin(M, Edge(ledger, true), 1).Value;
        ledger.RequireReconciliation("device_snapshot_conflict"); var up = Edge(ledger, false);
        Assert.False(owner.Complete(gesture, up, 1)); Assert.True(owner.DeferCompletion(gesture, up, 1));
        Assert.False(owner.TryCompleteDeferred(out _, out _));
        ledger.TryReconcile(ledger.Prefix, Snapshot(), Snapshot(), true, true);
        Assert.True(owner.TryCompleteDeferred(out var completed, out var actualEnd));
        Assert.Equal(gesture, completed); Assert.Equal(up, actualEnd);
        Assert.False(owner.TryCompleteDeferred(out _, out _));
        Assert.NotNull(owner.HandoffCompleted(gesture, Web, "surgery"));
    }

    [Theory] [InlineData(true)] [InlineData(false)]
    public void DeferredEndCannotSurviveNewInputOrCancellation(bool newInput)
    {
        var (ledger, owner) = Create(); var gesture = owner.Begin(M, Edge(ledger, true), 1).Value;
        ledger.RequireReconciliation("pending"); Assert.True(owner.DeferCompletion(gesture, Edge(ledger, false), 1));
        if (newInput) { owner.ObservationChanged(Edge(ledger, true)); Edge(ledger, false); }
        else owner.Revoke("cancel");
        ledger.TryReconcile(ledger.Prefix, Snapshot(), Snapshot(), true, true);
        Assert.False(owner.TryCompleteDeferred(out _, out _));
        Assert.Null(owner.HandoffCompleted(gesture, Web, "surgery"));
    }
    [Fact] public void ActualEndpointCanConsumeCompletedGestureOnceBeforeRevocation()
    {
        var (ledger, owner) = Create(); var gesture = owner.Begin(M, Edge(ledger, true), 1).Value;
        Assert.True(owner.Complete(gesture, Edge(ledger, false), 1));
        Assert.Equal(InputHandoffPhase.Ready, owner.Phase);
        var intent = owner.HandoffCompleted(gesture, Web, "surgery");
        Assert.NotNull(intent); Assert.Equal(InputHandoffPhase.Revoking, owner.Phase);
        Assert.Null(owner.HandoffCompleted(gesture, Web, "surgery"));
        CancelAll(owner); Assert.True(owner.ConsumeIntentForPreparation(intent.Value));
        PrepareAndGrant(owner); Assert.Equal(Web, owner.Owner);
    }

    [Theory] [InlineData("input")] [InlineData("geometry")] [InlineData("source")]
    public void LateOpenerCannotUseCompletionAcrossAnotherObservationOrEnvironment(string conflict)
    {
        var (ledger, owner) = Create(); var gesture = owner.Begin(M, Edge(ledger, true), 1).Value;
        Assert.True(owner.Complete(gesture, Edge(ledger, false), 1));
        if (conflict == "input") { Edge(ledger, true); Edge(ledger, false); }
        if (conflict == "geometry") owner.SetEnvironment(true, 2);
        if (conflict == "source") ledger.Invalidate("removed");
        Assert.Null(owner.HandoffCompleted(gesture, Web, "surgery"));
        Assert.False(owner.HasPendingIntent);
    }
    private static readonly InputScope M = new("M", 1), Web = new("Web", 1), Native = new("Native", 1);
    private static readonly InputScope[] Scopes = { M, Web, Native };
    private static Dictionary<int, bool> Snapshot(bool down = false) => new() { [1] = down, [2] = false };
    private static (PhysicalInputLedger ledger, InputHandoffCoordinator owner) Create(bool ready = true)
    {
        var ledger = new PhysicalInputLedger(new[] { 1, 2 });
        ledger.ConfirmSources(ledger.Prefix); ledger.TryReconcile(ledger.Prefix, Snapshot(), Snapshot(), true, true);
        var owner = new InputHandoffCoordinator(ledger, "session", "closure", Scopes);
        owner.SetEnvironment(true, 1); owner.Start(M);
        if (ready) { CancelAll(owner); PrepareAndGrant(owner); }
        return (ledger, owner);
    }
    private static void CancelAll(InputHandoffCoordinator owner)
    {
        foreach (var scope in Scopes) Assert.True(owner.AcceptCancelled(new(owner.Round, scope, true, true)));
    }
    private static void PrepareAndGrant(InputHandoffCoordinator owner)
    {
        Assert.True(owner.TryPrepare(out var prefix));
        foreach (var scope in Scopes) Assert.True(owner.AcceptPrepared(new(owner.Round, scope, prefix)));
        Assert.Equal(InputHandoffPhase.Preparing, owner.Phase); Assert.Null(owner.Owner);
        Assert.True(owner.TryGrant(true));
    }
    private static ObservedInputEdge Edge(PhysicalInputLedger ledger, bool down, int key = 1) =>
        ledger.Observe(ledger.Prefix.Generation, key, down, InputObservationSource.Unmarked).Value;

    [Fact] public void CoverageIsExactNotCountAndAReceiptCannotStandInForChildCleanup()
    {
        var (_, owner) = Create(false); var round = owner.Round;
        Assert.False(owner.AcceptCancelled(new(round, new("unknown", 1), true, true)));
        Assert.False(owner.AcceptCancelled(new(round, new("M", 2), true, true)));
        Assert.False(owner.AcceptCancelled(new(round, M, true, false)));
        Assert.False(owner.AcceptCancelled(new(round with { Ticket = round.Ticket + 1 }, M, true, true)));
        Assert.True(owner.AcceptCancelled(new(round, M, true, true)));
        Assert.False(owner.AcceptCancelled(new(round, M, true, true)));
        Assert.True(owner.AcceptCancelled(new(round, Web, true, true)));
        Assert.False(owner.TryPrepare(out _));
        Assert.True(owner.AcceptCancelled(new(round, Native, true, true))); PrepareAndGrant(owner);
    }

    [Fact] public void PrepareConflictRequiresFreshRoundAndDoesNotReplayInput()
    {
        var (ledger, owner) = Create(false); CancelAll(owner);
        Assert.True(owner.TryPrepare(out var prefix)); var stale = owner.Round;
        owner.AcceptPrepared(new(stale, M, prefix));
        Edge(ledger, true); owner.ObservationChanged(); Edge(ledger, false); owner.ObservationChanged();
        Assert.False(owner.AcceptPrepared(new(stale, Web, prefix))); Assert.False(owner.TryGrant(true));
        PrepareAndGrant(owner); Assert.NotEqual(stale.Ticket, owner.Round.Ticket);
        Assert.Null(owner.Begin(M, Edge(ledger, false), 1));
        Assert.NotNull(owner.Begin(M, Edge(ledger, true), 1));
    }

    [Fact] public void FinalGrantRechecksPrefixEvenWhenObservationNotificationIsLate()
    {
        var (ledger, owner) = Create(false); CancelAll(owner);
        owner.TryPrepare(out var prefix);
        foreach (var scope in Scopes) owner.AcceptPrepared(new(owner.Round, scope, prefix));
        Edge(ledger, true); Edge(ledger, false);
        Assert.False(owner.TryGrant(true)); Assert.Equal(InputHandoffPhase.WaitNeutral, owner.Phase);
        PrepareAndGrant(owner);
    }

    [Fact] public void DataFailureAlwaysDispatchesControlButCannotSelfCertifyCancellation()
    {
        var (ledger, owner) = Create(); var gesture = owner.Begin(M, Edge(ledger, true), 1);
        int controls = 0; owner.CancelRequired += (_, scopes) => { controls++; Assert.Equal(3, scopes.Count); };
        owner.Fail("queue_overflow"); Assert.Equal(1, controls); Assert.Null(owner.Owner);
        Assert.Equal(ObservedKeyState.Down, ledger[1]); Assert.False(owner.TryPrepare(out _));
        CancelAll(owner); Assert.Equal(InputHandoffPhase.Blocked, owner.Phase);
        owner.TransportRecovered(); Assert.False(owner.TryPrepare(out _));
        Assert.False(owner.Complete(gesture.Value, Edge(ledger, false), 1));
        PrepareAndGrant(owner);
    }

    [Fact] public void IntentIsMintedBeforeEpochChangesAndConsumedOnceBehindCancellation()
    {
        var (ledger, owner) = Create(); var gesture = owner.Begin(M, Edge(ledger, true), 1).Value;
        var up = Edge(ledger, false); var intent = owner.CompleteAndHandoff(gesture, up, 1, Web, "surgery").Value;
        Assert.True(owner.Round.Epoch > intent.Gesture.Round.Epoch);
        Assert.Null(owner.CompleteAndHandoff(gesture, up, 1, Web, "surgery"));
        Assert.False(owner.ConsumeIntentForPreparation(intent)); CancelAll(owner);
        Assert.True(owner.ConsumeIntentForPreparation(intent)); Assert.False(owner.ConsumeIntentForPreparation(intent));
        PrepareAndGrant(owner); Assert.Equal(Web, owner.Owner);
        Assert.Null(owner.Begin(Web, up, 1)); Assert.NotNull(owner.Begin(Web, Edge(ledger, true), 1));
    }

    [Fact] public void GeometryAndInstanceAndSessionChangesCannotReuseReceiptsOrHeldGesture()
    {
        var (ledger, owner) = Create(); var gesture = owner.Begin(M, Edge(ledger, true), 1).Value;
        var stale = owner.Round; owner.SetEnvironment(true, 2);
        Assert.False(owner.AcceptCancelled(new(stale, M, true, true)));
        Assert.False(owner.AcceptCancelled(new(owner.Round with { Session = "old" }, M, true, true)));
        Assert.False(owner.Complete(gesture, Edge(ledger, false), 2)); CancelAll(owner); PrepareAndGrant(owner);
        Assert.Null(owner.Begin(new("M", 2), Edge(ledger, true), 2));
    }

    [Fact] public void SecondButtonCancelsFirstAndItsReleaseCannotBecomeANewGesture()
    {
        var (ledger, owner) = Create(); var gesture = owner.Begin(M, Edge(ledger, true), 1).Value;
        owner.ObservationChanged(Edge(ledger, true, 2)); Assert.Equal(InputHandoffPhase.Revoking, owner.Phase);
        Assert.False(owner.Complete(gesture, Edge(ledger, false), 1)); Edge(ledger, false, 2);
        CancelAll(owner); PrepareAndGrant(owner); Assert.NotNull(owner.Begin(M, Edge(ledger, true), 1));
    }

    [Fact] public void SourceLossAndOutsideForegroundBlockGrantsUntilSeparateRecovery()
    {
        var (ledger, owner) = Create(); ledger.Invalidate("device_removed"); owner.ObservationChanged();
        CancelAll(owner); Assert.False(owner.TryPrepare(out _));
        ledger.ConfirmSources(ledger.Prefix); ledger.TryReconcile(ledger.Prefix, Snapshot(), Snapshot(), true, true);
        owner.SetEnvironment(false, 1); CancelAll(owner); Assert.False(owner.TryPrepare(out _));
        owner.SetEnvironment(true, 1); CancelAll(owner); PrepareAndGrant(owner);
    }

    [Theory]
    [InlineData(false)] [InlineData(true)]
    public void InvalidatedHandoffCannotGrantDestinationAfterItsIntentWasDiscarded(bool consumed)
    {
        var (ledger, owner) = Create(); var gesture = owner.Begin(M, Edge(ledger, true), 1).Value;
        var intent = owner.CompleteAndHandoff(gesture, Edge(ledger, false), 1, Web, "surgery").Value;
        CancelAll(owner);
        if (consumed) Assert.True(owner.ConsumeIntentForPreparation(intent));
        owner.SetEnvironment(true, 2); CancelAll(owner);
        Assert.False(owner.ConsumeIntentForPreparation(intent)); PrepareAndGrant(owner);
        Assert.Equal(M, owner.Owner); Assert.False(owner.HasPendingIntent);
    }

    [Fact] public void StartupFaultDoesNotInventAnOwnerOrBypassStartupCancellation()
    {
        var ledger = new PhysicalInputLedger(new[] { 1 });
        var owner = new InputHandoffCoordinator(ledger, "session", "closure", Scopes);
        owner.ObservationChanged(); owner.Fail("not_connected");
        Assert.Equal(InputHandoffPhase.BootClosed, owner.Phase);
        owner.Start(M); CancelAll(owner); Assert.Equal(InputHandoffPhase.Blocked, owner.Phase);
        owner.TransportRecovered(); Assert.False(owner.TryPrepare(out _));
    }
}
