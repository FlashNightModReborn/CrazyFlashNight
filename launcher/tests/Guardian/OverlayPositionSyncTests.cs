using System;
using System.Drawing;
using System.Threading;
using System.Windows.Forms;
using CF7Launcher.Guardian;
using Xunit;

namespace CF7Launcher.Tests.Guardian;

public class OverlayPositionSyncTests
{
    private sealed class Probe : OverlayBase
    {
        internal Point MeasuredOrigin;internal int Measurements;
        private readonly Control _probeAnchor;
        internal Probe(Form owner,Control anchor):base(owner,anchor,1024,576){_probeAnchor=anchor;}
        protected override void OnPositionChanged(){Measurements++;MeasuredOrigin=_probeAnchor.PointToScreen(Point.Empty);}
    }
    [Fact] public void AnchorTranslationWithoutResizeImmediatelyRemeasuresNativeOverlay()
    {
        Sta(()=>{
            using var owner=new Form();using var anchor=new Panel {Bounds=new Rectangle(0,0,400,240)};
            owner.Controls.Add(anchor);_=owner.Handle;_=anchor.Handle;
            using var overlay=new Probe(owner,anchor);overlay.RequestPositionSync();
            int count=overlay.Measurements;anchor.Location=new Point(15,29);
            Assert.True(overlay.Measurements>count);
            Assert.Equal(anchor.PointToScreen(Point.Empty),overlay.MeasuredOrigin);
            Assert.Equal(new Size(400,240),anchor.Size);
        });
    }
    [Fact] public void SettledRefreshRemeasuresCurrentAnchorWithoutGrantingVisibility()
    {
        Sta(()=>{
            using var owner=new Form();using var container=new Panel {Bounds=new Rectangle(0,0,600,400)};
            using var anchor=new Panel {Bounds=new Rectangle(0,0,400,240)};
            owner.Controls.Add(container);container.Controls.Add(anchor);_=owner.Handle;_=anchor.Handle;
            using var overlay=new Probe(owner,anchor);overlay.RequestPositionSync();
            // Model a projection retained from the early WM_SIZE measurement.
            // Seed a stale cached origin without relying on WinForms notification
            // ordering or lazy creation of hidden ancestor handles.
            var current=anchor.PointToScreen(Point.Empty);
            overlay.MeasuredOrigin=new Point(current.X,current.Y-9);
            Assert.NotEqual(overlay.MeasuredOrigin,current);
            Assert.Equal(1,GuardianForm.SyncNativeOwnedSurfaces(owner));
            Assert.Equal(anchor.PointToScreen(Point.Empty),overlay.MeasuredOrigin);
            Assert.False(overlay.Visible); // a geometry refresh never grants visibility
            overlay.Dispose();Assert.Equal(0,GuardianForm.SyncNativeOwnedSurfaces(owner));
        });
    }
    private static void Sta(Action action)
    {
        Exception error=null;var thread=new Thread(()=>{try{action();}catch(Exception e){error=e;}});
        thread.SetApartmentState(ApartmentState.STA);thread.Start();Assert.True(thread.Join(15000));
        if(error!=null)System.Runtime.ExceptionServices.ExceptionDispatchInfo.Capture(error).Throw();
    }
}
