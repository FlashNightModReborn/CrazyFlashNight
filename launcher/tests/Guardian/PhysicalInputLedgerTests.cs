using System;
using System.Collections.Generic;
using CF7Launcher.Guardian.InputOwnership;
using Xunit;

namespace CF7Launcher.Tests.Guardian;

public sealed class PhysicalInputLedgerTests
{
    private static readonly int[] Keys={1,2,4,5,6,160,161,162,163,164,165};
    private static Dictionary<int,bool> Snapshot(params int[] down)
    {
        var result=new Dictionary<int,bool>();foreach(int key in Keys)result[key]=Array.IndexOf(down,key)>=0;return result;
    }
    private static PhysicalInputLedger Ready(params int[] held)
    {
        var ledger=new PhysicalInputLedger(Keys);Assert.True(ledger.ConfirmSources(ledger.Prefix));
        Assert.True(ledger.TryReconcile(ledger.Prefix,Snapshot(held),Snapshot(held),true,true));return ledger;
    }
    [Fact] public void ColdStartRequiresQualifiedCompleteSnapshotWithoutSyntheticEdges()
    {
        var l=new PhysicalInputLedger(Keys);Assert.Null(l.TryProveNeutral());
        Assert.False(l.TryReconcile(l.Prefix,Snapshot(),Snapshot(),true,true));
        Assert.True(l.ConfirmSources(l.Prefix));
        Assert.False(l.TryReconcile(l.Prefix,Snapshot(),Snapshot(),false,true));
        Assert.True(l.ConfirmSources(l.Prefix));
        Assert.False(l.TryReconcile(l.Prefix,Snapshot(),Snapshot(),true,false));
        Assert.True(l.ConfirmSources(l.Prefix));
        var incomplete=Snapshot();incomplete.Remove(165);
        Assert.False(l.TryReconcile(l.Prefix,incomplete,incomplete,true,true));
        Assert.True(l.ConfirmSources(l.Prefix));
        Assert.True(l.TryReconcile(l.Prefix,Snapshot(),Snapshot(),true,true));
        Assert.NotNull(l.TryProveNeutral());
    }
    [Fact] public void PreheldAndExternalUpRemainIndependentOfEndpointLifetime()
    {
        var l=Ready(1,162);Assert.Null(l.TryProveNeutral());
        // There is deliberately no owner-cancel/reset-held API.
        l.Observe(l.Prefix.Generation,1,false,InputObservationSource.Hardware);
        Assert.Null(l.TryProveNeutral());Assert.Equal(ObservedKeyState.Down,l[162]);
        l.Observe(l.Prefix.Generation,162,false,InputObservationSource.Hardware);
        Assert.NotNull(l.TryProveNeutral());
    }
    [Fact] public void SnapshotRaceAndEvenDownUpInvalidateOldNeutralProof()
    {
        var l=Ready();var proof=l.TryProveNeutral().Value;var fence=l.Prefix;
        var down=l.Observe(fence.Generation,1,true,InputObservationSource.Hardware).Value;
        Assert.True(down.WasNeutral);Assert.False(down.Duplicate);
        l.Observe(fence.Generation,1,false,InputObservationSource.Hardware);
        Assert.False(l.IsCurrent(proof));
        Assert.False(l.TryReconcile(fence,Snapshot(),Snapshot(),true,true));
        Assert.False(l.TryReconcile(l.Prefix,Snapshot(),Snapshot(1),true,true));
        Assert.False(l.IsNeutral);
    }
    [Fact] public void LossRejectsOldGenerationAndCannotBeRepairedByZeroOrOneUp()
    {
        var l=Ready();var old=l.Prefix;var reset=l.Invalidate("observer_gap");
        Assert.False(l.ConfirmSources(old));Assert.Null(l.Observe(old.Generation,1,false,InputObservationSource.Hardware));
        Assert.False(l.TryReconcile(reset,Snapshot(),Snapshot(),true,true));
        l.Observe(reset.Generation,1,false,InputObservationSource.Hardware);
        Assert.False(l.IsNeutral);
        Assert.True(l.ConfirmSources(l.Prefix));
        Assert.True(l.TryReconcile(l.Prefix,Snapshot(),Snapshot(),true,true));
        Assert.NotNull(l.TryProveNeutral());
    }
    [Fact] public void SourceAndDuplicateArePreservedWithoutMintingAnotherGesture()
    {
        var l=Ready();var first=l.Observe(l.Prefix.Generation,1,true,InputObservationSource.Injected).Value;
        var repeated=l.Observe(l.Prefix.Generation,1,true,InputObservationSource.Injected).Value;
        Assert.Equal(InputObservationSource.Injected,first.Source);Assert.True(first.WasNeutral);
        Assert.True(repeated.Duplicate);Assert.False(repeated.WasNeutral);
    }
    [Fact] public void ReconciliationCopiesSnapshotAndInvalidatesPreviouslyGrantedPrefix()
    {
        var l=Ready();var old=l.TryProveNeutral().Value;var snapshot=Snapshot();
        Assert.True(l.TryReconcile(l.Prefix,snapshot,snapshot,true,true));snapshot[1]=true;
        Assert.True(l.IsNeutral);Assert.False(l.IsCurrent(old));
    }
    [Fact] public void PendingPrefixInvalidatesGrantButFreshSnapshotRecoversWithoutRegisteringAgain()
    {
        // Human sample record 30: eligible=true, registered=true, drained=false.
        // This used to kill source health and reject all later samples forever.
        var l=Ready();var old=l.TryProveNeutral().Value;long generation=l.Prefix.Generation;
        Assert.False(l.TryReconcile(l.Prefix,Snapshot(),Snapshot(),true,false));
        Assert.True(l.SourcesHealthy);Assert.False(l.IsNeutral);Assert.False(l.IsCurrent(old));
        Assert.Equal(generation,l.Prefix.Generation);
        Assert.True(l.TryReconcile(l.Prefix,Snapshot(1),Snapshot(1),true,true));
        Assert.Null(l.TryProveNeutral()); // recovery is not an invented release
        l.Observe(generation,1,false,InputObservationSource.Unmarked);
        Assert.NotNull(l.TryProveNeutral());Assert.False(l.IsCurrent(old));
    }
    [Fact] public void SnapshotRaceCanRetryButRealSourceLossCannotBeHealedByPolling()
    {
        var l=Ready();
        Assert.False(l.TryReconcile(l.Prefix,Snapshot(),Snapshot(162),true,true));
        Assert.False(l.IsNeutral);Assert.True(l.SourcesHealthy);
        l.Observe(l.Prefix.Generation,162,false,InputObservationSource.Unmarked);
        Assert.False(l.IsNeutral); // an Up cannot substitute for the deferred snapshot
        Assert.True(l.TryReconcile(l.Prefix,Snapshot(),Snapshot(),true,true));
        Assert.NotNull(l.TryProveNeutral());
        l.Invalidate("raw_registration_lost");
        for(int i=0;i<3;i++)Assert.False(l.TryReconcile(l.Prefix,Snapshot(),Snapshot(),true,true));
        Assert.Null(l.TryProveNeutral());
    }
}
