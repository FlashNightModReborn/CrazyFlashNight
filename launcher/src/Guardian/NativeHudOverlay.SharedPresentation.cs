using System;
using System.Drawing;
using System.Drawing.Imaging;
using CF7Launcher.Guardian.WorldCompositor;

namespace CF7Launcher.Guardian
{
    public partial class NativeHudOverlay
    {
        private WorldRasterPresentation _sharedPresentation;
        private bool _sharedSubmitted;
        private long _sharedBinding;

        // A hidden fallback Form still owns the existing painter and widget lifecycle.
        // It does not receive input or submit a layered bitmap in this mode.
        internal bool SharedInputAvailable => _sharedSubmitted && _sharedPresentation?.IsAvailable == true
            && _ready && !_suspendedForPanel && (base.CanShowOverlayNow || IsOwnerSessionForeground());
        internal bool HasLegacyPointerGesture => _sharedPresentation==null && (_leftDownWidget!=null || Capture);
        internal bool UsesSharedPresentation => _sharedPresentation!=null;

        internal void SetSharedPresentation(WorldRasterPresentation presentation)
        {
            if(InvokeRequired)throw new InvalidOperationException("HUD presentation belongs to its UI thread.");
            if(ReferenceEquals(_sharedPresentation,presentation))return;
            if(_sharedPresentation!=null)_sharedPresentation.Changed-=OnSharedPresentationChanged;
            DismissHudPresentation();
            CancelPointerGesture("presentation_changed");
            _sharedPresentation=presentation;++_sharedBinding;
            if(presentation!=null)presentation.Changed+=OnSharedPresentationChanged;
            OnSharedPresentationChanged();
        }

        private void OnSharedPresentationChanged()
        {
            if(IsDisposed || Disposing)return;
            if(_sharedPresentation!=null && !_sharedPresentation.IsAvailable)DismissHudPresentation();
            // Fault notification can run inside a locked bitmap upload. Repaint only
            // after that transaction returns, with the current binding and geometry.
            long binding=_sharedBinding;
            if(IsHandleCreated)BeginInvoke(new Action(()=> {
                if(!IsDisposed && !Disposing && binding==_sharedBinding)RecomputeBounds();
            }));
        }

        private void DismissHudPresentation()
        {
            _sharedSubmitted=false;
            _sharedPresentation?.Hide();
            DismissOverlay();
        }

        private bool TryCommitSharedBitmap()
        {
            var presentation=_sharedPresentation;
            if(presentation==null)return false;
            if(!presentation.IsAvailable || !(base.CanShowOverlayNow || IsOwnerSessionForeground()))
            {
                DismissHudPresentation();return true;
            }
            Exception failure=null;
            bool accepted=false;
            BitmapData locked=null;
            try
            {
                locked=_composedBitmap.LockBits(new Rectangle(Point.Empty,_composedBitmap.Size),
                    ImageLockMode.ReadOnly,PixelFormat.Format32bppPArgb);
                accepted=presentation.TryPresent(locked.Scan0,_composedBitmap.Width,_composedBitmap.Height,
                    locked.Stride,_hudOrigin);
                if(!accepted)failure=new InvalidOperationException("HUD raster extent is unsupported.");
            }
            catch(Exception error) { failure=error; }
            finally { if(locked!=null)_composedBitmap.UnlockBits(locked); }
            if(failure!=null)presentation.Reject(failure);
            _sharedSubmitted=accepted && ReferenceEquals(presentation,_sharedPresentation) && presentation.IsAvailable;
            // Do not let an owner activation resurrect the old display/input window.
            DismissOverlay();
            return true;
        }

        private void DisposeSharedPresentation()
        {
            ++_sharedBinding;
            if(_sharedPresentation!=null)_sharedPresentation.Changed-=OnSharedPresentationChanged;
            DismissHudPresentation();_sharedPresentation=null;
        }
    }
}
