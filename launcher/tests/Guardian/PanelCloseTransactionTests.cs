using System;
using System.Collections.Generic;
using System.Reflection;
using CF7Launcher.Guardian;
using Xunit;

namespace CF7Launcher.Tests.Guardian
{
    public class PanelCloseTransactionTests
    {
        private sealed class Harness : IDisposable
        {
            internal readonly Queue<Action> Queue=new();
            internal readonly PanelHostController Host;
            internal Harness() { Host=new PanelHostController(a=>Queue.Enqueue(a),a=>a()); Host.OpenPanel("help","{}"); Pump(); }
            internal void Pump() { while(Queue.Count>0)Queue.Dequeue()(); }
            public void Dispose() { Host.Dispose(); }
        }
        [Fact] public void LegalClosePublishesGameOnlyAfterCleanup()
        {
            using var h=new Harness(); string instance=h.Host.ActivePanelInstanceId;
            bool? result=null; bool publishedAsClosing=false;
            h.Host.PanelChanged+=(panel,id)=> { if(panel==null) { publishedAsClosing=!h.Host.GameOwnsInput;
                Assert.Equal(EffectiveInputOwnerKind.Closing,h.Host.EffectiveInputOwner.Kind); } };
            Assert.True(h.Host.TryClosePanelExact("help",instance,r=>result=r)); h.Pump();
            Assert.True(result); Assert.True(publishedAsClosing); Assert.True(h.Host.GameOwnsInput);
        }
        [Fact] public void GateAdmissionOfAnotherOwnerPreventsAuthorityCommit()
        {
            using var h=new Harness(); int commits=0; bool? closed=null;
            h.Host.TryClosePanelExact("help",h.Host.ActivePanelInstanceId,true,
                ()=> { h.Host.OpenPanel("intelligence","{}"); return true; },()=>commits++,r=>closed=r);
            h.Pump(); Assert.Equal(0,commits); Assert.False(closed); Assert.Equal("intelligence",h.Host.ActivePanelName);
        }
        [Fact] public void CommitAdmissionOfAnotherOwnerRetainsCommittedSupersededReceipt()
        {
            using var h=new Harness(); int commits=0; HostCloseContext receipt=null;
            h.Host.TryClosePanelExact("help",h.Host.ActivePanelInstanceId,true,()=>true,
                ()=> { commits++; h.Host.OpenPanel("intelligence","{}"); },r=>receipt=h.Host.LastCloseOutcome);
            h.Pump(); Assert.Equal(1,commits); Assert.Equal("CommittedSuperseded",receipt.Outcome);
            Assert.Equal(AuthorityCommitState.Committed,receipt.Authority); Assert.Equal("intelligence",h.Host.ActivePanelName);
        }
        [Fact] public void UnknownCommitRetiresSourceWithoutSuccessfulCompletion()
        {
            using var h=new Harness(); bool? result=null;
            h.Host.TryClosePanelExact("help",h.Host.ActivePanelInstanceId,true,()=>true,
                ()=>throw new InvalidOperationException("partial"),r=>result=r);
            h.Pump(); Assert.False(result); Assert.False(h.Host.IsPanelOpen);
            Assert.Equal(AuthorityCommitState.Unknown,h.Host.LastCloseOutcome.Authority);
            Assert.Equal(ClosePlanKind.CleanupOnly,h.Host.LastCloseOutcome.Plan);
        }
        [Fact] public void SubscriberAdmissionKeepsGameBlockedUntilReplacementPublishes()
        {
            using var h=new Harness(); bool during=false;
            h.Host.PanelChanged+=(panel,id)=> { if(panel==null) { h.Host.OpenPanel("intelligence","{}"); during=h.Host.GameOwnsInput; } };
            h.Host.TryClosePanelExact("help",h.Host.ActivePanelInstanceId,null); h.Pump();
            Assert.False(during); Assert.Equal("intelligence",h.Host.ActivePanelName); Assert.False(h.Host.GameOwnsInput);
        }
        [Fact] public void FailedCleanupNeverPublishesGameOwner()
        {
            using var h=new Harness(); h.Host.PanelChanged+=(panel,id)=> { if(panel==null)throw new InvalidOperationException("notify"); };
            h.Host.TryClosePanelExact("help",h.Host.ActivePanelInstanceId,null); h.Pump();
            Assert.True(h.Host.LastCloseOutcome.CleanupFailed); Assert.False(h.Host.GameOwnsInput);
            Assert.Equal(EffectiveInputOwnerKind.Unavailable,h.Host.EffectiveInputOwner.Kind);
        }
        [Fact] public void RejectedOpeningReleasesOnlyItsPendingOwner()
        {
            var queue=new Queue<Action>(); using var host=new PanelHostController(a=>queue.Enqueue(a),a=>a());
            host.SetDocumentUnavailableGate(()=>true); host.OpenPanel("help","{}"); Assert.False(host.GameOwnsInput);
            while(queue.Count>0)queue.Dequeue()(); Assert.True(host.GameOwnsInput);
        }
        [Fact] public void IdleCloseDoesNotAcquireTheOwnerThatOpensBeforeItsPump()
        {
            var queue=new Queue<Action>(); using var host=new PanelHostController(a=>queue.Enqueue(a),a=>a());
            host.OpenPanel("help","{}"); host.ClosePanel(); while(queue.Count>0)queue.Dequeue()();
            Assert.Equal("help",host.ActivePanelName);
        }
        [Fact] public void NativeEditOwnerBlocksGameAndTransitionReleaseCannotClearFailedCleanup()
        {
            var queue=new Queue<Action>(); using var host=new PanelHostController(a=>queue.Enqueue(a),a=>a());
            bool editing=true; host.NativeInputOwnerPresent=()=>editing;
            Assert.False(host.GameOwnsInput); Assert.Equal(EffectiveInputOwnerKind.NativeOwned,host.EffectiveInputOwner.Kind);
            editing=false; Assert.True(host.GameOwnsInput);
            host.OpenPanel("help","{}"); while(queue.Count>0)queue.Dequeue()();
            host.PanelChanged+=(panel,id)=> { if(panel==null)throw new InvalidOperationException("cleanup"); };
            host.ClosePanel(); while(queue.Count>0)queue.Dequeue()(); host.SetTransitionInputHeld(false);
            Assert.False(host.GameOwnsInput); Assert.Equal(EffectiveInputOwnerKind.Unavailable,host.EffectiveInputOwner.Kind);
        }
        [Fact] public void LegacyCloseWaitsForReleaseWithoutConsumingItsAuthorityGate()
        {
            using var h=new Harness(); bool held=true; int commits=0; bool? result=null;
            h.Host.CloseInputHeldForTests=()=>held;
            h.Host.TryClosePanelExact("help",h.Host.ActivePanelInstanceId,true,()=>true,()=>commits++,r=>result=r);
            h.Pump(); Assert.Equal(0,commits); Assert.Null(result); Assert.True(h.Host.IsPanelOpen);
            held=false; h.Host.PollPhysicalClosesForTests(); h.Pump();
            Assert.Equal(1,commits); Assert.True(result); Assert.True(h.Host.GameOwnsInput);
        }
        [Fact] public void WaitingLegacyCloseCannotBeRelabeledAfterReplacement()
        {
            using var h=new Harness(); bool held=true; bool? result=null; h.Host.CloseInputHeldForTests=()=>held;
            h.Host.TryClosePanelExact("help",h.Host.ActivePanelInstanceId,r=>result=r); h.Pump();
            h.Host.OpenPanel("intelligence","{}"); h.Pump();
            held=false; h.Host.PollPhysicalClosesForTests(); h.Pump();
            Assert.False(result); Assert.Equal("intelligence",h.Host.ActivePanelName);
        }
    }
}
