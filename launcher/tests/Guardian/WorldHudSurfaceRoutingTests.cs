using System;
using System.Collections.Generic;
using System.Drawing;
using System.Threading;
using System.Windows.Forms;
using CF7Launcher.Guardian.WorldCompositor;
using Xunit;

namespace CF7Launcher.Tests.Guardian;

public sealed class WorldHudSurfaceRoutingTests
{
    private sealed class Flash : IWorldPointerSink
    {
        internal readonly List<int> Messages=new();
        public PointerPostStatus Send(in PointerPacket packet,Point point) { Messages.Add(packet.Message);return PointerPostStatus.Posted; }
        public bool RaiseMinEpoch(uint epoch)=>true;
        public long EndpointConsumedSeq=>0;
    }
    private sealed class Hud : IWorldHudInput
    {
        internal readonly List<int> Messages=new();
        public object HitTest(Point screen)=>screen.X<100?this:null;
        public void Dispatch(int message,Point screen,uint data,object target)=>Messages.Add(message);
        public void Cancel() { }
    }
    [Fact]
    public void ProductionSurfaceRoutesEachGestureToOneConsumerIncludingBackendRetirement()
    {
        Exception failure=null;
        var thread=new Thread(()=> {
            try
            {
                using var source=new Form {ClientSize=new Size(1024,576)};_=source.Handle;
                var flash=new Flash();var hud=new Hud();int physical=0;IntPtr capture=IntPtr.Zero;
                using var surface=new WorldCompositionSurface(()=>source.Handle,()=>{},flash,physicalButtons:()=>physical,captureWindow:()=>capture);
                surface.ClientSize=new Size(320,180);surface.Show();surface.SetHudInput(hud);
                Point ui=new(10,20),world=new(200,20);
                physical=1;surface.IntakePointer(0x201,ui,0);
                physical=0;surface.IntakePointer(0x202,ui,0);Application.DoEvents();surface.Drain();
                Assert.Equal(new[]{0x201,0x202},hud.Messages);Assert.Empty(flash.Messages);
                physical=1;surface.IntakePointer(0x201,world,0);surface.Drain();
                surface.IntakePointer(0x200,ui,0);
                physical=0;surface.IntakePointer(0x202,ui,0);surface.Drain();Application.DoEvents();
                Assert.Equal(new[]{0x201,0x202,0x2A3},hud.Messages); // hover retires; no HUD button edge is added
                Assert.Equal(new[]{0x201,0x200,0x202},flash.Messages);
                flash.Messages.Clear();hud.Messages.Clear();
                physical=1;surface.IntakePointer(0x201,ui,0);surface.SetHudInput(null);
                physical=0;surface.IntakePointer(0x202,world,0);Application.DoEvents();surface.Drain();
                Assert.Empty(hud.Messages);
                Assert.DoesNotContain(0x201,flash.Messages);Assert.DoesNotContain(0x202,flash.Messages);
                physical=1;surface.IntakePointer(0x201,world,0);
                physical=0;surface.IntakePointer(0x202,world,0);surface.Drain();
                Assert.Contains(0x201,flash.Messages);Assert.Contains(0x202,flash.Messages);
                flash.Messages.Clear();hud.Messages.Clear();
                // A press started on the legacy HUD before it was hidden. Its
                // eventual release must reach neither a new HUD action nor Flash.
                physical=1;surface.RetireLegacyHudGesture();surface.SetHudInput(hud);
                physical=0;surface.IntakePointer(0x202,world,0);surface.Drain();Application.DoEvents();
                Assert.Empty(hud.Messages);
                Assert.DoesNotContain(0x201,flash.Messages);Assert.DoesNotContain(0x202,flash.Messages);
                physical=1;surface.IntakePointer(0x201,ui,0);
                physical=0;surface.IntakePointer(0x202,ui,0);Application.DoEvents();
                Assert.Equal(new[]{0x201,0x202},hud.Messages);
                flash.Messages.Clear();hud.Messages.Clear();capture=new IntPtr(99);
                Assert.False(surface.RouteCapturedPointer(ui.X,ui.Y,0x201,0));
                Assert.False(surface.RouteCapturedPointer(ui.X,ui.Y,0x202,0));
                Application.DoEvents();
                Assert.DoesNotContain(0x201,hud.Messages);Assert.DoesNotContain(0x202,hud.Messages);
                Assert.DoesNotContain(0x201,flash.Messages);Assert.DoesNotContain(0x202,flash.Messages);
            }
            catch(Exception error) { failure=error; }
        });
        thread.SetApartmentState(ApartmentState.STA);thread.Start();Assert.True(thread.Join(30000));
        if(failure!=null)System.Runtime.ExceptionServices.ExceptionDispatchInfo.Capture(failure).Throw();
    }
}
