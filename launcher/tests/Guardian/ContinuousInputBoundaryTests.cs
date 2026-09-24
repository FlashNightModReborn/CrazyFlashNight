using System.Collections.Generic;
using CF7Launcher.Guardian.InputOwnership;
using Xunit;

namespace CF7Launcher.Tests.Guardian;

// Independent admission counterexamples: these are protocol/ledger tests,
// not proof of keyboard hardware or the Flash movement consumer.
public sealed class ContinuousInputBoundaryTests
{
    private static readonly InputScope World = new("M", 1);
    private static (PhysicalInputLedger Ledger, InputHandoffCoordinator Owner) Ready()
    {
        var ledger = new PhysicalInputLedger(new[] { 1, 65, 87, 88 });
        ledger.ConfirmSources(ledger.Prefix);
        var up = new Dictionary<int, bool> { [1] = false, [65] = false, [87] = false, [88] = false };
        Assert.True(ledger.TryReconcile(ledger.Prefix, up, up, true, true));
        var owner = new InputHandoffCoordinator(ledger, "session", "coverage", new[] { World },
            ContinuousInputPolicy.Declare(World, 65, 87));
        owner.SetEnvironment(true, 1); owner.Start(World);
        Assert.True(owner.AcceptCancelled(new(owner.Round, World, true, true)));
        Assert.True(owner.TryPrepare(out var prefix));
        Assert.True(owner.AcceptPrepared(new(owner.Round, World, prefix)));
        Assert.True(owner.TryGrant(true));
        return (ledger, owner);
    }
    private static ObservedInputEdge Edge(PhysicalInputLedger ledger, int key, bool down) =>
        ledger.Observe(ledger.Prefix.Generation, key, down, InputObservationSource.Unmarked)!.Value;

    [Fact] public void StaleDownCannotBeAdmittedAfterItsPhysicalRelease()
    {
        var (ledger, owner) = Ready();
        var stale = Edge(ledger, 87, true); owner.ObservationChanged(stale);
        var released = Edge(ledger, 87, false); owner.ObservationChanged(released);
        Assert.Null(owner.AcceptContinuousEdge(stale, 1));
        Assert.Equal(ObservedKeyState.Up, ledger[87]);
    }

    [Fact] public void UnqualifiedBaselineCannotStartContinuousBusiness()
    {
        var (ledger, owner) = Ready();
        ledger.RequireReconciliation("snapshot_raced");
        var edge = Edge(ledger, 87, true); owner.ObservationChanged(edge);
        Assert.Null(owner.AcceptContinuousEdge(edge, 1));
        Assert.Equal(ObservedKeyState.Down, ledger[87]);
    }

    [Fact] public void UnadmittedForeignHoldCannotBeExemptedByADeclaredMovementDown()
    {
        var (ledger, owner) = Ready();
        var foreign = Edge(ledger, 88, true); owner.ObservationChanged(foreign);
        var movement = Edge(ledger, 87, true); owner.ObservationChanged(movement);
        Assert.Null(owner.AcceptContinuousEdge(movement, 1));
        Assert.Equal(ObservedKeyState.Down, ledger[88]);
    }

    [Theory] [InlineData(false)] [InlineData(true)]
    public void RunningMovementCancelsOnForeignHoldOrBaselineLoss(bool baselineLost)
    {
        var (ledger, owner) = Ready();
        var down = Edge(ledger, 87, true); owner.ObservationChanged(down);
        Assert.NotNull(owner.AcceptContinuousEdge(down, 1));
        if (baselineLost) { ledger.RequireReconciliation("snapshot_raced"); owner.ObservationChanged(); }
        else owner.ObservationChanged(Edge(ledger, 88, true));
        Assert.Null(owner.Owner);
        Assert.Equal(InputHandoffPhase.Revoking, owner.Phase);
        Assert.Equal(ObservedKeyState.Down, ledger[87]);
    }

    [Fact] public void SnapshotReleaseCannotLeaveAnOldLogicalAdmissionAlive()
    {
        var (ledger, owner) = Ready();
        var down = Edge(ledger, 87, true); owner.ObservationChanged(down);
        Assert.NotNull(owner.AcceptContinuousEdge(down, 1));
        var up = new Dictionary<int, bool> { [1] = false, [65] = false, [87] = false, [88] = false };
        Assert.True(ledger.TryReconcile(ledger.Prefix, up, up, true, true));
        owner.ObservationChanged();
        Assert.Null(owner.Owner);
        Assert.Null(owner.AcceptContinuousEdge(Edge(ledger, 87, true), 1));
    }

    [Fact] public void ReplacingContinuousScopeRequiresASeparatePolicyQualification()
    {
        var (_, owner) = Ready(); owner.Revoke("replace");
        Assert.True(owner.AcceptCancelled(new(owner.Round, World, true, true)));
        Assert.False(owner.ReplaceRetiredScope(World, new("M", 2), World, true));
        Assert.Equal(World, owner.PreparingOwner);
    }

    [Theory] [InlineData(false)] [InlineData(true)]
    public void DuplicateReleaseSettlesOnlyTheExistingGesture(bool deferred)
    {
        var (ledger, owner) = Ready();
        var down = Edge(ledger, 1, true); owner.ObservationChanged(down);
        var gesture = owner.Begin(World, down, 1)!.Value;
        if (deferred) ledger.RequireReconciliation("raw_snapshot_race");
        var up = Edge(ledger, 1, false); owner.ObservationChanged(up);
        if (deferred) Assert.True(owner.DeferCompletion(gesture, up, 1));
        else Assert.True(owner.Complete(gesture, up, 1));
        var duplicate = Edge(ledger, 1, false); Assert.True(duplicate.Duplicate);
        owner.ObservationChanged(duplicate);
        if (deferred) {
            var allUp = new Dictionary<int, bool> { [1] = false, [65] = false, [87] = false, [88] = false };
            Assert.True(ledger.TryReconcile(ledger.Prefix, allUp, allUp, true, true));
            Assert.True(owner.TryCompleteDeferred(out var completed, out var physicalEnd));
            Assert.Equal(gesture, completed); Assert.Equal(up, physicalEnd);
        }
        Assert.NotNull(owner.HandoffCompleted(gesture, World, "one_real_opener"));
        Assert.Null(owner.HandoffCompleted(gesture, World, "one_real_opener"));
    }
}
