using System;
using System.Collections.Generic;
using System.Drawing;
using System.IO;
using System.Linq;
using System.Reflection;
using System.Runtime.InteropServices;
using System.Windows.Forms;
using CF7Launcher.Guardian;
using CF7Launcher.Guardian.WorldCompositor;
using Xunit;

namespace CF7Launcher.Tests.Guardian
{
    public class WorldPointerBridgeBoundaryTests
    {
        private const int Move=0x200,Down=0x201,Up=0x202,Wheel=0x20A,CancelMode=0x1F;
        private sealed class FakeSink : IWorldPointerSink
        {
            internal readonly List<string> Calls=new List<string>();
            internal readonly List<PointerPacket> Sent=new List<PointerPacket>();
            internal readonly List<Point> Points=new List<Point>();
            internal PointerPostStatus Next=PointerPostStatus.Posted;
            internal uint Floor;
            internal long Consumed=-1;
            public PointerPostStatus Send(in PointerPacket packet,Point point)
            {
                Calls.Add("send:"+packet.Message+"#"+packet.Sequence);
                var status=Next; Next=PointerPostStatus.Posted;
                if(status==PointerPostStatus.Posted) { Sent.Add(packet); Points.Add(point); }
                return status;
            }
            public bool RaiseMinEpoch(uint epoch) { Calls.Add("floor:"+epoch); Floor=epoch; return true; }
            public long EndpointConsumedSeq => Consumed;
        }
        private static PointerPacket Packet(int message=Down,uint epoch=1,uint gesture=0,uint geometry=0,long seq=1)
            => new PointerPacket(message,Point.Empty,Point.Empty,0,0,epoch,gesture,geometry,seq);
        private static WorldCompositionSurface Surface(FakeSink sink,Func<IntPtr> flash)
        {
            var surface=new WorldCompositionSurface(flash,()=>{},sink);
            _=surface.Handle; // create the handle so PointToClient works without a pump
            return surface;
        }
        private static Form FakeSource(int w=1600,int h=900)
        {
            var form=new Form { ClientSize=new Size(w,h) };
            _=form.Handle;
            return form;
        }

        [Fact] public void WireEnvelopeCarriesEpochGeometryAndSequence()
        {
            // v3: epoch occupies WPARAM [32:56) as a 24-bit serial, geometry sits
            // at [56:64); the v2 gesture field no longer exists on the wire.
            long wp=WorldPointerMapper.PackWParam(Down,0x51,0xABCD0000,0x123456,0x2A);
            long lp=WorldPointerMapper.PackLParam(new Point(-30,700),0x11223344);
            WorldPointerMapper.UnpackWire(wp,lp,
                out uint kind,out uint flags,out uint extra,out uint epoch,out uint geo,
                out int x,out int y,out uint seq);
            Assert.Equal(0x01u,kind);
            Assert.Equal(0x51u,flags);
            Assert.Equal(0xABCDu,extra);
            Assert.Equal(0x123456u,epoch); // wider than 16 bits: the v3 epoch field
            Assert.Equal(0x2Au,geo);
            Assert.Equal(-30,x); Assert.Equal(700,y);
            Assert.Equal(0x11223344u,seq);
            // The cancel packet keeps its own (raised) epoch so it passes the receiver's floor.
            long cw=WorldPointerMapper.PackWParam(CancelMode,0,0,9,0);
            WorldPointerMapper.UnpackWire(cw,0,out kind,out _,out _,out epoch,out _,out _,out _,out _);
            Assert.Equal(0xFEu,kind); Assert.Equal(9u,epoch);
        }
        [Theory]
        [InlineData(1u,0u,false)]
        [InlineData(1u,1u,false)]
        [InlineData(1u,2u,true)]
        // Serial comparison mod 2^24: 0xFFFFFF is 4 behind floor 3, so it is stale.
        [InlineData(0xFFFFFFu,3u,true)]
        // ...while 2 is 3 ahead of floor 0xFFFFFF, so it is fresh.
        [InlineData(2u,0xFFFFFFu,false)]
        [InlineData(0u,0xFFFFFFu,false)]
        [InlineData(0xFFFFFEu,0xFFFFFFu,true)]
        // Half-window edge: floor+8388607 is still admissible, floor+8388608 is not.
        [InlineData(0x7FFFFFu,0u,false)]
        [InlineData(0x800000u,0u,true)]
        // Same edges against a mid-range floor, matching the native selftest.
        [InlineData(0x800007u,8u,false)]
        [InlineData(0x800008u,8u,true)]
        public void StaleEpochPredicateMatchesNativeFloor(uint epoch,uint floor,bool stale)
        {
            Assert.Equal(stale,WorldPointerMapper.IsStaleEpoch(epoch,floor));
        }
        [Fact] public void OutOfDomainEpochAndSequenceCannotBeEncoded()
        {
            foreach(uint epoch in new[]{0u,WorldPointerMapper.EpochLimit+1,0x800000u,0x1000000u})
                Assert.Throws<ArgumentOutOfRangeException>(()=>WorldPointerMapper.PackWParam(Down,1,0,epoch,0));
            Assert.Throws<ArgumentOutOfRangeException>(()=>WorldPointerMapper.PackLParam(Point.Empty,0));
            Assert.Throws<ArgumentOutOfRangeException>(()=>WorldPointerMapper.PackLParam(Point.Empty,WorldPointerMapper.SequenceLimit+1));
        }
        [Fact] public void SharedStateViewReadsAndWritesRealMappedPage()
        {
            // Real mapping smoke: this test process creates the section the
            // broker would create, then the thin view opens/validates/uses it.
            string name="Local\\CF7.WorldPointer.Test."+Environment.ProcessId+"."+Guid.NewGuid().ToString("N");
            IntPtr mapping=CreateFileMappingW(new IntPtr(-1),IntPtr.Zero,4,0,(uint)SharedInputStateView.Size,name);
            Assert.NotEqual(IntPtr.Zero,mapping);
            IntPtr page=MapViewOfFile(mapping,0x0002|0x0004,0,0,(UIntPtr)SharedInputStateView.Size);
            Assert.NotEqual(IntPtr.Zero,page);
            try {
                Marshal.WriteInt32(page,0,unchecked((int)NativePointerBridge.InputMagic));
                Marshal.WriteInt32(page,4,unchecked((int)NativePointerBridge.ProtocolVersion));
                using(var view=SharedInputStateView.Open(name,NativePointerBridge.InputMagic,NativePointerBridge.ProtocolVersion)) {
                    // Writes through the view are visible through the raw map.
                    // Both epoch fields carry the low 24 bits of the host counter.
                    view.WriteMinEpoch(0x1234);
                    view.WriteMinEpoch(1);
                    Assert.Equal(0x1234,Marshal.ReadInt32(page,56));
                    Assert.Throws<ArgumentOutOfRangeException>(()=>view.WriteMinEpoch(0x1FFFFFF));
                    view.WriteIssuedEpoch(0x1235);
                    view.WriteIssuedEpoch(3);
                    Assert.Equal(0x1235,Marshal.ReadInt32(page,80));
                    Assert.Throws<ArgumentOutOfRangeException>(()=>view.WriteIssuedEpoch(0x1ABCDEF));
                    // Writes through the raw map are visible through the view.
                    Marshal.WriteInt32(page,60,12345678);
                    Assert.Equal(12345678,view.ReadConsumedSeq());
                }
                // Wrong magic and wrong version are both refused.
                Marshal.WriteInt32(page,0,0x11111111);
                Assert.Throws<InvalidOperationException>(()=>SharedInputStateView.Open(name,NativePointerBridge.InputMagic,NativePointerBridge.ProtocolVersion));
                Marshal.WriteInt32(page,0,unchecked((int)NativePointerBridge.InputMagic));
                Marshal.WriteInt32(page,4,99);
                Assert.Throws<InvalidOperationException>(()=>SharedInputStateView.Open(name,NativePointerBridge.InputMagic,NativePointerBridge.ProtocolVersion));
            } finally { UnmapViewOfFile(page); CloseHandle(mapping); }
        }
        [Fact] public void SendPublishesIssuedEpochToSharedPage()
        {
            // RCE-1 contract: every send publishes its epoch into the shared page
            // before posting, so a focus loss processed afterwards revokes the
            // packet even while it is still queued. A real mapped page and a real
            // window handle stand in for the broker section and the projector.
            string name="Local\\CF7.WorldPointer.Test."+Environment.ProcessId+"."+Guid.NewGuid().ToString("N");
            IntPtr mapping=CreateFileMappingW(new IntPtr(-1),IntPtr.Zero,4,0,(uint)SharedInputStateView.Size,name);
            Assert.NotEqual(IntPtr.Zero,mapping);
            IntPtr page=MapViewOfFile(mapping,0x0002|0x0004,0,0,(UIntPtr)SharedInputStateView.Size);
            Assert.NotEqual(IntPtr.Zero,page);
            try {
                Marshal.WriteInt32(page,0,unchecked((int)NativePointerBridge.InputMagic));
                Marshal.WriteInt32(page,4,unchecked((int)NativePointerBridge.ProtocolVersion));
                using var view=SharedInputStateView.Open(name,NativePointerBridge.InputMagic,NativePointerBridge.ProtocolVersion);
                using var source=new Form();
                _=source.Handle;
                var ctor=typeof(NativePointerBridge).GetConstructor(
                    BindingFlags.NonPublic|BindingFlags.Instance,null,new[]{typeof(IntPtr)},null);
                var bridge=(NativePointerBridge)ctor.Invoke(new object[]{source.Handle});
                typeof(NativePointerBridge).GetField("_state",BindingFlags.NonPublic|BindingFlags.Instance)
                    .SetValue(bridge,view);
                var down=new PointerPacket(Down,Point.Empty,Point.Empty,0,0,0x123,1,0,7);
                Assert.Equal(PointerPostStatus.Posted,bridge.Send(down,new Point(3,4)));
                Assert.Equal(0x123,Marshal.ReadInt32(page,80));
                var move=new PointerPacket(Move,Point.Empty,Point.Empty,0,0,0x124,1,0,8);
                Assert.Equal(PointerPostStatus.Posted,bridge.Send(move,new Point(4,5)));
                Assert.Equal(0x124,Marshal.ReadInt32(page,80));
            } finally { UnmapViewOfFile(page); CloseHandle(mapping); }
        }
        [Fact] public void OwnerDeactivateCancelsPointerAndUnsubscribesOnDispose()
        {
            var sink=new FakeSink();
            var logs=new List<string>(); LogManager.SetSink(logs.Add);
            try {
                string root=Path.GetFullPath(Path.Combine(AppContext.BaseDirectory,"..","..","..",".."));
                using var owner=new TestOwnerForm();
                using var anchor=new Control();
                using var flash=FakeSource();
                using var surface=Surface(sink,()=>flash.Handle);
                surface.Bounds=new Rectangle(10,10,50,40);
                surface.Show();
                var controller=new WorldCompositorController(owner,anchor,()=>IntPtr.Zero,()=>false,_=>{},root,()=>false,_=>{},()=>{});
                SetSurface(controller,surface);
                surface.IntakePointer(Down,new Point(5,5),0); // in-flight gesture mints epoch 2
                owner.RaiseDeactivated();
                Assert.Contains("floor:3",sink.Calls);
                Assert.Single(sink.Sent);
                Assert.Equal(CancelMode,sink.Sent[0].Message);
                Assert.Equal(3u,sink.Sent[0].Epoch);
                Assert.Contains(logs,l=>l.Contains("event=world_pointer_cancel")&&l.Contains("owner_deactivate"));
                // Recovery in the same scenario: the next physical down mints a
                // fresh epoch (no other path needs to advance it) and is
                // admissible under the new floor.
                surface.IntakePointer(Down,new Point(6,6),0);
                surface.Drain();
                Assert.Equal(2,sink.Sent.Count);
                Assert.Equal(4u,sink.Sent[1].Epoch);
                Assert.False(WorldPointerMapper.IsStaleEpoch(sink.Sent[1].Epoch,sink.Floor));
                controller.Dispose(); // StopCapture cancels once more, then unsubscribes
                int afterDispose=sink.Sent.Count;
                owner.RaiseDeactivated();
                Assert.Equal(afterDispose,sink.Sent.Count);
            } finally { LogManager.ResetSink(); }
        }
        private sealed class TestOwnerForm : Form { internal void RaiseDeactivated() => OnDeactivate(EventArgs.Empty); }
        private static void SetSurface(WorldCompositorController controller,WorldCompositionSurface surface)
            => typeof(WorldCompositorController).GetField("_surface",BindingFlags.NonPublic|BindingFlags.Instance).SetValue(controller,surface);
        [Fact] public void OwnerTranslationKeepsPresentationVisibleWithoutWaitingForRenderTimer()
        {
            using var owner=new Form {StartPosition=FormStartPosition.Manual,Bounds=new Rectangle(100,100,640,400)};
            using var anchor=new Panel {Dock=DockStyle.Fill};owner.Controls.Add(anchor);owner.Show();
            var sink=new FakeSink();
            using var source=FakeSource(429,241);
            using var surface=new WorldCompositionSurface(()=>source.Handle,()=>{},sink) {Owner=owner};
            surface.Bounds=anchor.RectangleToScreen(anchor.ClientRectangle);surface.Show();
            string root=Path.GetFullPath(Path.Combine(AppContext.BaseDirectory,"..","..","..",".."));
            using var controller=new WorldCompositorController(owner,anchor,()=>source.Handle,()=>true,_=>{},root,()=>false,_=>{},()=>{});
            SetSurface(controller,surface);
            IntPtr handle=surface.Handle;int hidden=0;
            surface.VisibleChanged+=(_,__)=>{if(!surface.Visible)hidden++;};
            // No Application.DoEvents or controller Tick: this is the move-loop gap.
            owner.Location=new Point(235,164);
            Assert.True(surface.Visible);Assert.Equal(0,hidden);
            Assert.Equal(handle,surface.Handle);
            Assert.Equal(anchor.RectangleToScreen(anchor.ClientRectangle),surface.Bounds);
            Assert.Contains(sink.Calls,c=>c.StartsWith("floor:"));
        }
        [DllImport("kernel32.dll",CharSet=CharSet.Unicode,SetLastError=true)] private static extern IntPtr CreateFileMappingW(IntPtr file,IntPtr attributes,uint protect,uint maxHigh,uint maxLow,string name);
        [DllImport("kernel32.dll",SetLastError=true)] private static extern IntPtr MapViewOfFile(IntPtr mapping,uint access,uint offsetHigh,uint offsetLow,UIntPtr size);
        [DllImport("kernel32.dll")] private static extern bool UnmapViewOfFile(IntPtr address);
        [DllImport("kernel32.dll")] private static extern bool CloseHandle(IntPtr handle);
        [Fact] public void SoftLimitSealsNewInputWithoutRevokingTheAlreadyPostedUp()
        {
            using var source=FakeSource();var sink=new FakeSink();
            using var surface=new WorldCompositionSurface(()=>source.Handle,()=>{},sink,8,128,()=>0);
            surface.Show();var handle=surface.Handle;Point p=surface.PointToScreen(new Point(10,10));
            for(int i=0;i<5;i++){surface.IntakePointer(Down,p,0);surface.Drain();surface.IntakePointer(Up,p,0);surface.Drain();}
            int before=sink.Sent.Count;
            surface.IntakePointer(Down,p,0);surface.Drain();
            Assert.True(surface.InputRenewing);Assert.True(surface.GracefulRenewal);
            Assert.Equal(before,sink.Sent.Count);Assert.Equal(Up,sink.Sent.Last().Message);
            Assert.Equal(0u,sink.Floor); // no terminal floor before graceful completion
            var next=new FakeSink();surface.Rebind(next);
            Assert.Equal(handle,surface.Handle);
            surface.IntakePointer(Up,p,0);surface.Drain();Assert.Empty(next.Sent);
            surface.IntakePointer(Down,p,0);surface.Drain();
            Assert.Single(next.Sent);Assert.Equal(2u,next.Sent[0].Epoch);
        }
        [Fact] public void RepeatedCancelDoesNotInvalidateTheQueuedRenewalNotification()
        {
            using var source=FakeSource();var sink=new FakeSink();
            using var surface=new WorldCompositionSurface(()=>source.Handle,()=>{},sink,8,128,()=>0);
            surface.Show();int requests=0;surface.RenewalRequested+=()=>requests++;
            for(int i=0;i<9;i++)surface.CancelPointer("hide");
            Assert.True(surface.InputRenewing);
            Application.DoEvents();Assert.Equal(1,requests);
        }
        [Fact] public void HardSequenceLimitExplicitlyCancelsAHeldGesture()
        {
            using var source=FakeSource();var sink=new FakeSink();
            using var surface=new WorldCompositionSurface(()=>source.Handle,()=>{},sink,32,16);
            surface.Show();Point p=surface.PointToScreen(new Point(10,10));
            surface.IntakePointer(Down,p,0);surface.Drain();
            for(int i=0;i<20;i++){surface.IntakePointer(Move,p,0);surface.FlushMove();}
            Assert.True(surface.InputRenewing);Assert.False(surface.GracefulRenewal);
            Assert.Equal(WorldPointerMapper.EpochLimit+1,sink.Floor);
            Assert.All(sink.Sent,packet=>Assert.InRange(packet.Sequence,1,16));
        }

        [Fact] public void BoundedQueueReportsOverflowInsteadOfDroppingEdges()
        {
            var queue=new PointerQueue();
            for(int i=0;i<PointerQueue.Capacity;i++) Assert.True(queue.Enqueue(Packet(seq:i)));
            Assert.False(queue.Enqueue(Packet(seq:999)));
            Assert.Equal(PointerQueue.Capacity,queue.Count);
            queue.Clear();
            Assert.True(queue.Enqueue(Packet(seq:999)));
            Assert.Equal(1,queue.Count);
        }
        [Fact] public void MotionCoalescesAndFlushesAheadOfTheNextEdge()
        {
            var queue=new PointerQueue();
            for(int i=0;i<PointerQueue.Capacity*2;i++) Assert.True(queue.Enqueue(Packet(Move,seq:i)));
            Assert.Equal(0,queue.Count);
            queue.Enqueue(Packet(Move,seq:100));
            queue.Enqueue(Packet(Down,seq:101));
            Assert.True(queue.TryDequeue(out var first));
            Assert.Equal(100,first.Sequence);
            Assert.True(queue.TryDequeue(out var second));
            Assert.Equal(101,second.Sequence);
        }
        [Fact] public void RenderTickCannotSendTailMotionBeforeQueuedButtonEdges()
        {
            using var source=FakeSource();var sink=new FakeSink();
            using var surface=Surface(sink,()=>source.Handle);surface.Show();
            Point p=surface.PointToScreen(new Point(20,20));
            surface.IntakePointer(Down,p,0);
            surface.IntakePointer(Up,p,0);
            surface.IntakePointer(Move,new Point(p.X+100,p.Y+100),0);
            surface.FlushMove(); // render timer runs before BeginInvoke(Drain)
            Assert.Equal(new[]{Down,Up,Move},sink.Sent.Select(packet=>packet.Message));
            Assert.Equal(new long[]{1,2,3},sink.Sent.Select(packet=>packet.Sequence));
            Assert.Equal(sink.Points[0],sink.Points[1]);
            Assert.NotEqual(sink.Points[1],sink.Points[2]);
        }
        [Fact] public void CancelRaisesSharedFloorBeforePostingTheCancelPacket()
        {
            var sink=new FakeSink();
            using var surface=Surface(sink,()=>IntPtr.Zero);
            surface.IntakePointer(Move,new Point(5,5),0); // mark the pointer inside
            surface.CancelPointer("test");
            // The shared floor write must precede the cancel post: the receiver can
            // already see the new epoch before the cancel message is dequeued.
            Assert.Equal(2,sink.Calls.Count);
            Assert.Equal("floor:2",sink.Calls[0]);
            Assert.StartsWith("send:"+CancelMode+"#",sink.Calls[1]);
            Assert.Single(sink.Sent);
            Assert.Equal(CancelMode,sink.Sent[0].Message);
            Assert.Equal(2u,sink.Sent[0].Epoch);
            Assert.Equal(2u,sink.Floor);
        }
        [Fact] public void StaleQueuedDownIsClearedBeforeItCanBePosted()
        {
            var sink=new FakeSink();
            using var surface=Surface(sink,()=>IntPtr.Zero);
            surface.IntakePointer(Down,new Point(5,5),0); // gesture opens at epoch 2; down sits in the queue
            surface.CancelPointer("test");
            surface.Drain();
            // Only the cancel packet was ever posted; the stale down never left.
            Assert.Single(sink.Sent);
            Assert.Equal(CancelMode,sink.Sent[0].Message);
            Assert.False(surface.IsDragging);
            // Anything stamped with a pre-floor epoch is stale — including the
            // revoked gesture's own epoch 2. The cancel's epoch (the floor) stays
            // admissible.
            Assert.True(WorldPointerMapper.IsStaleEpoch(1,sink.Floor));
            Assert.True(WorldPointerMapper.IsStaleEpoch(2,sink.Floor));
            Assert.False(WorldPointerMapper.IsStaleEpoch(3,sink.Floor));
        }
        [Fact] public void CancelFloorStillRevokesWhenCancelPacketPostFails()
        {
            var sink=new FakeSink();
            var logs=new List<string>(); LogManager.SetSink(logs.Add);
            try {
                using var flash=FakeSource();
                using var surface=Surface(sink,()=>flash.Handle);
                surface.Bounds=new Rectangle(10,10,50,40);
                surface.Show();
                surface.IntakePointer(Down,new Point(5,5),0); // gesture at epoch 2
                surface.Drain();
                Assert.Single(sink.Sent);
                // The cancel packet's own post fails; the shared floor raised
                // before it still revokes every pre-floor packet on its own.
                sink.Next=PointerPostStatus.PostFailed;
                surface.CancelPointer("test");
                Assert.Equal(3u,sink.Floor);
                Assert.Contains("floor:3",sink.Calls);
                Assert.Single(sink.Sent); // the cancel never left the queue
                Assert.StartsWith("send:"+CancelMode+"#",sink.Calls[sink.Calls.Count-1]);
                Assert.True(WorldPointerMapper.IsStaleEpoch(2,sink.Floor));
                Assert.False(WorldPointerMapper.IsStaleEpoch(3,sink.Floor));
                Assert.Contains(logs,l=>l.Contains("event=world_pointer_cancel") && l.Contains("post=post_failed"));
            } finally { LogManager.ResetSink(); }
        }
        [Fact] public void EachNewGestureMintsAFreshEpoch()
        {
            // The epoch advances exactly at a new physical gesture: a down with
            // no buttons held. Motions and releases inside a gesture share its
            // epoch; the next gesture carries a strictly newer one, which is
            // what re-admits input after a receiver-side focus-loss floor.
            var sink=new FakeSink();
            using var flash=FakeSource();
            using var surface=Surface(sink,()=>flash.Handle);
            surface.Bounds=new Rectangle(10,10,50,40);
            surface.Show();
            surface.IntakePointer(Down,new Point(5,5),0);
            surface.IntakePointer(Up,new Point(5,5),0);
            surface.Drain();
            surface.IntakePointer(Down,new Point(6,6),0);
            surface.Drain();
            var downs=sink.Sent.Where(p=>p.Message==Down).ToList();
            Assert.Equal(2,downs.Count);
            Assert.Equal(2u,downs[0].Epoch); // surface starts at 1; first gesture mints 2
            Assert.Equal(3u,downs[1].Epoch);
            Assert.True(downs[1].Gesture>downs[0].Gesture);
            Assert.Equal(2u,sink.Sent[1].Epoch); // the up shares its gesture's epoch
        }
        [Fact] public void PostFailureCancelsTheGestureAndNeverClaimsDelivery()
        {
            var sink=new FakeSink();
            var logs=new List<string>(); LogManager.SetSink(logs.Add);
            try {
                using var flash=FakeSource();
                using var surface=Surface(sink,()=>flash.Handle);
                surface.Bounds=new Rectangle(10,10,50,40);
                surface.Show();
                surface.IntakePointer(Down,new Point(15,15),0);
                sink.Next=PointerPostStatus.PostFailed;
                surface.Drain();
                Assert.False(surface.IsDragging);
                // The failed down is not 'posted'; the follow-up cancel is the only packet out.
                Assert.Single(sink.Sent);
                Assert.Equal(CancelMode,sink.Sent[0].Message);
                Assert.Equal(3u,sink.Floor);
                Assert.Contains(logs,l=>l.Contains("event=world_pointer_cancel") && l.Contains("post_post_failed"));
                Assert.DoesNotContain(logs,l=>l.Contains("world_pointer") && l.Contains("delivered"));
            } finally { LogManager.ResetSink(); }
        }
        [Fact] public void QueueOverflowCancelsTheOpenGesture()
        {
            var sink=new FakeSink();
            var logs=new List<string>(); LogManager.SetSink(logs.Add);
            try {
                using var surface=Surface(sink,()=>IntPtr.Zero);
                surface.IntakePointer(Down,new Point(5,5),0);
                for(int i=0;i<PointerQueue.Capacity;i++) surface.IntakePointer(Wheel,new Point(5,5),0x00780000u);
                Assert.False(surface.IsDragging);
                Assert.Single(sink.Sent);
                Assert.Equal(CancelMode,sink.Sent[0].Message);
                Assert.Contains(logs,l=>l.Contains("event=world_pointer_cancel") && l.Contains("queue_full"));
            } finally { LogManager.ResetSink(); }
        }
        [Fact] public void StaleGeometryPacketRemapsFromItsScreenPoint()
        {
            var sink=new FakeSink();
            var logs=new List<string>(); LogManager.SetSink(logs.Add);
            try {
                using var flash=FakeSource();
                using var surface=Surface(sink,()=>flash.Handle);
                surface.Bounds=new Rectangle(400,300,200,100);
                surface.Show();
                var screen=new Point(450,350);
                surface.IntakePointer(Down,screen,0);
                // Geometry changes before the queued packet drains: the stored client
                // point is stale, but the physical screen point still remaps correctly.
                surface.ClientSize=new Size(400,200);
                surface.Drain();
                Assert.Single(sink.Sent);
                var expected=WorldPointerMapper.Map(surface.PointToClient(screen),surface.ClientSize,flash.ClientSize);
                Assert.Equal(expected,sink.Points[0]);
                Assert.Equal(1u,sink.Sent[0].Geometry);
                Assert.Contains(logs,l=>l.Contains("event=world_pointer_remap") && l.Contains("geo=0->1"));
            } finally { LogManager.ResetSink(); }
        }
        [Fact] public void UnownedUpIsPostedWithGestureZeroAndSynthesizesNothing()
        {
            var sink=new FakeSink();
            using var flash=FakeSource();
            using var surface=Surface(sink,()=>flash.Handle);
            surface.Bounds=new Rectangle(10,10,50,40);
            surface.Show();
            surface.IntakePointer(Up,new Point(15,15),0); // up with no open gesture
            surface.Drain();
            Assert.Single(sink.Sent);
            Assert.Equal(Up,sink.Sent[0].Message);
            Assert.Equal(0u,sink.Sent[0].Gesture); // receiver classifies it as unowned, no click
            Assert.False(surface.IsDragging);
        }
        [Fact] public void RebuiltTargetNeverReceivesPacketsChosenForTheOldTarget()
        {
            var sink=new FakeSink();
            using var oldFlash=FakeSource();
            using var newFlash=FakeSource();
            IntPtr target=oldFlash.Handle;
            using var surface=Surface(sink,()=>target);
            surface.Bounds=new Rectangle(10,10,50,40);
            surface.Show();
            surface.IntakePointer(Down,new Point(15,15),0);
            surface.Drain();
            Assert.Single(sink.Sent);
            Assert.Equal(Down,sink.Sent[0].Message);
            target=newFlash.Handle; // source HWND destroyed and recreated
            surface.IntakePointer(Up,new Point(15,15),0);
            surface.Drain();
            // The stale gesture's up is not posted to the new target; only the cancel leaves.
            Assert.Equal(2,sink.Sent.Count);
            Assert.Equal(CancelMode,sink.Sent[1].Message);
            Assert.False(surface.IsDragging);
        }
    }
}
