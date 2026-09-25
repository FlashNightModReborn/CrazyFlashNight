using System;
using System.Collections.Generic;
using CF7Launcher.Guardian.InputOwnership;
using Xunit;

namespace CF7Launcher.Tests.Guardian;

public sealed class ContinuousInputOwnershipTests
{
    private static readonly InputScope M = new("M", 1), Web = new("Web", 1), Native = new("Native", 1);
    private static readonly InputScope[] Scopes = { M, Web, Native };
    private static readonly int[] Keys = { 1, 3, 65, 87 };
    private const int Pointer = 1, Other = 3, A = 65, W = 87;

    [Fact] public void TwoHeldMovementKeysCoexistWithClickAndOpenerWaitsForRealRelease()
    {
        var (ledger, owner) = Create(policy: ContinuousInputPolicy.Declare(M, W, A));
        var wDown = Edge(ledger, true, W);
        var wEvent = Deliver(owner, wDown).Value;
        Assert.Equal(owner.Round, wEvent.Round); Assert.Equal(M, wEvent.Scope);
        Assert.Equal(W, wEvent.Key); Assert.True(wEvent.Down); Assert.Equal(wDown.Prefix.Sequence, wEvent.Sequence);
        Assert.Null(owner.AcceptContinuousEdge(wDown, 1)); // the same edge cannot be admitted twice
        var aEvent = Deliver(owner, Edge(ledger, true, A)).Value;
        Assert.Equal(A, aEvent.Key); Assert.True(aEvent.Sequence > wEvent.Sequence);
        var gesture = owner.Begin(M, Edge(ledger, true, Pointer), 1).Value; // admitted holds do not defeat Begin
        Assert.Equal(InputHandoffPhase.Held, owner.Phase);
        var up = Edge(ledger, false, Pointer);
        Assert.True(owner.Complete(gesture, up, 1));
        var intent = owner.HandoffCompleted(gesture, Web, "surgery");
        Assert.NotNull(intent); Assert.Equal(InputHandoffPhase.Revoking, owner.Phase);
        Assert.Null(owner.HandoffCompleted(gesture, Web, "surgery")); // opener mints exactly once
        Assert.Null(owner.AcceptContinuousEdge(Edge(ledger, false, W), 1)); // no owner mid-revoke
        CancelAll(owner); Assert.Equal(InputHandoffPhase.WaitNeutral, owner.Phase);
        Assert.True(owner.ConsumeIntentForPreparation(intent.Value));
        Assert.Equal(ObservedKeyState.Down, ledger[A]);
        Assert.False(owner.TryPrepare(out _)); // real held keys still block the next owner
        owner.ObservationChanged(Edge(ledger, false, A));
        PrepareAndGrant(owner); Assert.Equal(Web, owner.Owner);
    }

    [Fact] public void HeldContinuousKeysAreNeverInheritedByAnotherOwner()
    {
        var (ledger, owner) = Create(policy: ContinuousInputPolicy.Declare(M, W, A));
        Assert.NotNull(Deliver(owner, Edge(ledger, true, W)));
        Assert.True(owner.SelectReadOnlyHover(Native));
        Assert.Null(Deliver(owner, Edge(ledger, true, A))); // mid-revoke edges are never admitted
        CancelAll(owner); Assert.Equal(InputHandoffPhase.WaitNeutral, owner.Phase);
        Assert.False(owner.TryPrepare(out _)); // W and A are still physically held
        owner.ObservationChanged(Edge(ledger, false, A));
        Assert.False(owner.TryPrepare(out _)); // W alone still blocks the next owner
        owner.ObservationChanged(Edge(ledger, false, W));
        PrepareAndGrant(owner); Assert.Equal(Native, owner.Owner);
        Assert.Null(owner.AcceptContinuousEdge(Edge(ledger, true, A), 1)); // A is not declared for Native
    }

    [Fact] public void UndeclaredAndUnsupportedKeysBlockBusinessAndRevokeHeldGestures()
    {
        var (ledger, owner) = Create(policy: ContinuousInputPolicy.Declare(M, W));
        var xDown = Edge(ledger, true, Other);
        owner.ObservationChanged(xDown);
        Assert.Equal(InputHandoffPhase.Ready, owner.Phase); // held undeclared input blocks, not yet revokes
        Assert.Null(owner.AcceptContinuousEdge(xDown, 1)); // never admitted
        Assert.Null(owner.Begin(M, Edge(ledger, true, Pointer), 1));
        Assert.Null(ledger.Observe(ledger.Prefix.Generation, 200, true, InputObservationSource.Unmarked));
        owner.ObservationChanged(Edge(ledger, false, Other));
        owner.ObservationChanged(Edge(ledger, false, Pointer)); // rejected Down still needs its real Up
        var gesture = owner.Begin(M, Edge(ledger, true, Pointer), 1).Value;
        owner.ObservationChanged(Edge(ledger, true, Other)); // undeclared key inside a gesture still conflicts
        Assert.Equal(InputHandoffPhase.Revoking, owner.Phase); Assert.Equal("gesture_conflict", owner.BlockReason);
        Assert.False(owner.Complete(gesture, Edge(ledger, false, Pointer), 1));
    }

    [Fact] public void DuplicateAndStaleEdgesMintNoContinuousBusiness()
    {
        var (ledger, owner) = Create(policy: ContinuousInputPolicy.Declare(M, W));
        var first = Deliver(owner, Edge(ledger, true, W)).Value;
        var repeated = Edge(ledger, true, W); Assert.True(repeated.Duplicate);
        Assert.Null(Deliver(owner, repeated)); // key repeat is not a second press
        Assert.NotNull(Deliver(owner, Edge(ledger, false, W)));
        var stale = Edge(ledger, true, W); Assert.NotNull(Deliver(owner, stale));
        owner.Revoke("cancel"); CancelAll(owner);
        Assert.False(owner.TryPrepare(out _)); // real hold survives cancellation
        owner.ObservationChanged(Edge(ledger, false, W));
        PrepareAndGrant(owner); Assert.Equal(M, owner.Owner);
        Assert.Null(owner.AcceptContinuousEdge(stale, 1)); // old-round edge cannot mint business
        var fresh = Deliver(owner, Edge(ledger, true, W)).Value;
        Assert.Equal(owner.Round, fresh.Round); Assert.True(fresh.Sequence > first.Sequence);
    }

    [Fact] public void SourceGenerationRevokesAndSnapshotHeldKeysAreNotAdmitted()
    {
        var (ledger, owner) = Create(policy: ContinuousInputPolicy.Declare(M, W));
        Assert.NotNull(Deliver(owner, Edge(ledger, true, W)));
        ledger.Invalidate("source_restarted"); owner.ObservationChanged();
        Assert.Equal(InputHandoffPhase.Revoking, owner.Phase);
        CancelAll(owner);
        Assert.True(ledger.ConfirmSources(ledger.Prefix));
        Assert.True(ledger.TryReconcile(ledger.Prefix, Snapshot(W), Snapshot(W), true, true));
        Assert.False(owner.TryPrepare(out _)); // snapshot-held keys are not an admission and block grants
        owner.ObservationChanged(Edge(ledger, false, W));
        PrepareAndGrant(owner); Assert.Equal(M, owner.Owner);
        var fresh = Deliver(owner, Edge(ledger, true, W)).Value;
        Assert.Equal(owner.Round, fresh.Round);
    }

    [Fact] public void CancellationKeepsRealHeldStateWithoutSyntheticRelease()
    {
        var (ledger, owner) = Create(policy: ContinuousInputPolicy.Declare(M, W));
        Assert.NotNull(Deliver(owner, Edge(ledger, true, W)));
        owner.Revoke("cancel");
        Assert.Equal(ObservedKeyState.Down, ledger[W]); Assert.Null(ledger.TryProveNeutral());
        CancelAll(owner); Assert.False(owner.TryPrepare(out _));
        owner.ObservationChanged(Edge(ledger, false, W));
        PrepareAndGrant(owner); Assert.Equal(M, owner.Owner);
    }

    [Fact] public void DefaultC1PolicyIsNotRelaxed()
    {
        var (ledger, owner) = Create();
        var xDown = Edge(ledger, true, Other);
        owner.ObservationChanged(xDown);
        Assert.Null(owner.AcceptContinuousEdge(xDown, 1)); // nothing is ever declared
        Assert.Null(owner.Begin(M, Edge(ledger, true, Pointer), 1)); // held keys still defeat Begin
        owner.ObservationChanged(Edge(ledger, false, Other));
        owner.ObservationChanged(Edge(ledger, false, Pointer)); // rejected Down still needs its real Up
        var gesture = owner.Begin(M, Edge(ledger, true, Pointer), 1).Value;
        var heldAgain = Edge(ledger, true, Other);
        Assert.False(owner.Complete(gesture, Edge(ledger, false, Pointer), 1)); // strict neutral stays
        owner.ObservationChanged(heldAgain);
        Assert.Equal(InputHandoffPhase.Revoking, owner.Phase); Assert.Equal("gesture_conflict", owner.BlockReason);
    }

    [Fact] public void DeclaredContinuousKeyCannotBecomeThePointerGesture()
    {
        var (ledger, owner) = Create(policy: ContinuousInputPolicy.Declare(M, W));
        var wDown = Edge(ledger, true, W);
        owner.ObservationChanged(wDown);
        Assert.Null(owner.Begin(M, wDown, 1)); // a movement key is not a gesture
        Assert.Equal(InputHandoffPhase.Ready, owner.Phase);
        Assert.NotNull(owner.AcceptContinuousEdge(wDown, 1));
    }

    [Fact] public void DeferredEndCannotAdmitNewMovementThroughUnknownBaseline()
    {
        var (ledger, owner) = Create(policy: ContinuousInputPolicy.Declare(M, W, A));
        Assert.NotNull(Deliver(owner, Edge(ledger, true, W)));
        var gesture = owner.Begin(M, Edge(ledger, true, Pointer), 1).Value;
        ledger.RequireReconciliation("device_snapshot_conflict");
        var up = Edge(ledger, false, Pointer);
        Assert.False(owner.Complete(gesture, up, 1));
        Assert.True(owner.DeferCompletion(gesture, up, 1));
        var aDown = Edge(ledger, true, A);
        owner.ObservationChanged(aDown);
        Assert.Equal(InputHandoffPhase.Revoking, owner.Phase);
        Assert.Null(owner.AcceptContinuousEdge(aDown, 1));
        Assert.True(ledger.TryReconcile(ledger.Prefix, Snapshot(W, A), Snapshot(W, A), true, true));
        Assert.False(owner.TryCompleteDeferred(out _, out _));
        Assert.Null(owner.HandoffCompleted(gesture, Web, "surgery"));
        Assert.Equal(ObservedKeyState.Down, ledger[W]);
    }

    [Fact] public void ValidCompletedPointerSurvivesFreshAdmittedMovementBeforeItsIntentReply()
    {
        var (ledger, owner) = Create(policy: ContinuousInputPolicy.Declare(M, W, A));
        Assert.NotNull(Deliver(owner, Edge(ledger, true, W)));
        var gesture = owner.Begin(M, Edge(ledger, true, Pointer), 1).Value;
        Assert.True(owner.Complete(gesture, Edge(ledger, false, Pointer), 1));
        Assert.NotNull(Deliver(owner, Edge(ledger, true, A)));
        Assert.NotNull(owner.HandoffCompleted(gesture, Web, "surgery"));
        CancelAll(owner); Assert.False(owner.TryPrepare(out _));
    }

    [Fact] public void DeferredEndIsStillRevokedByUndeclaredInput()
    {
        var (ledger, owner) = Create(policy: ContinuousInputPolicy.Declare(M, W));
        var gesture = owner.Begin(M, Edge(ledger, true, Pointer), 1).Value;
        ledger.RequireReconciliation("device_snapshot_conflict");
        Assert.True(owner.DeferCompletion(gesture, Edge(ledger, false, Pointer), 1));
        owner.ObservationChanged(Edge(ledger, true, Other));
        Assert.Equal(InputHandoffPhase.Revoking, owner.Phase); Assert.Equal("input_after_deferred_end", owner.BlockReason);
        Assert.False(owner.TryCompleteDeferred(out _, out _));
    }

    [Fact] public void PolicyIsAClosedExactDeclaration()
    {
        var ledger = new PhysicalInputLedger(Keys);
        Assert.Throws<ArgumentException>(() => new InputHandoffCoordinator(ledger, "s", "c", Scopes,
            ContinuousInputPolicy.Declare(M, 200))); // key outside the ledger's supported set
        Assert.Throws<ArgumentException>(() => new InputHandoffCoordinator(ledger, "s", "c", Scopes,
            ContinuousInputPolicy.Declare(new InputScope("Elsewhere", 1), W))); // scope outside coverage
        Assert.Throws<ArgumentException>(() => new InputHandoffCoordinator(ledger, "s", "c", Scopes,
            ContinuousInputPolicy.Declare(M))); // empty declaration is not a permit
    }

    private static Dictionary<int, bool> Snapshot(params int[] down)
    {
        var result = new Dictionary<int, bool>(); foreach (int key in Keys) result[key] = Array.IndexOf(down, key) >= 0;
        return result;
    }
    private static (PhysicalInputLedger ledger, InputHandoffCoordinator owner) Create(
        bool ready = true, ContinuousInputPolicy policy = default)
    {
        var ledger = new PhysicalInputLedger(Keys);
        ledger.ConfirmSources(ledger.Prefix); ledger.TryReconcile(ledger.Prefix, Snapshot(), Snapshot(), true, true);
        var owner = new InputHandoffCoordinator(ledger, "session", "closure", Scopes, policy);
        owner.SetEnvironment(true, 1); owner.Start(M);
        if (ready) { CancelAll(owner); PrepareAndGrant(owner); }
        return (ledger, owner);
    }
    // Adapter order per drained edge: ObservationChanged first, then route.
    private static ContinuousKeyEvent? Deliver(InputHandoffCoordinator owner, ObservedInputEdge edge)
    {
        owner.ObservationChanged(edge);
        return owner.AcceptContinuousEdge(edge, 1);
    }
    private static void CancelAll(InputHandoffCoordinator owner)
    {
        foreach (var scope in Scopes) Assert.True(owner.AcceptCancelled(new(owner.Round, scope, true, true)));
    }
    private static void PrepareAndGrant(InputHandoffCoordinator owner)
    {
        Assert.True(owner.TryPrepare(out var prefix));
        foreach (var scope in Scopes) Assert.True(owner.AcceptPrepared(new(owner.Round, scope, prefix)));
        Assert.True(owner.TryGrant(true));
    }
    private static ObservedInputEdge Edge(PhysicalInputLedger ledger, bool down, int key = Pointer) =>
        ledger.Observe(ledger.Prefix.Generation, key, down, InputObservationSource.Unmarked).Value;
}
