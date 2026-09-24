using System;
using System.Drawing;

namespace CF7Launcher.Guardian
{
    public partial class PanelHostController
    {
        private CompositionHelpSurface _compositionHelp;
        private bool _compositionHelpSelected;
        private bool _compositionHelpPreparing;
        private Action<bool> _compositionPanelState;
        private Func<string, bool> _compositionRestoreFocus;

        internal bool CompositionHelpOwnsInput => _compositionHelpSelected;

        internal void ConfigureCompositionHelp(string webRoot, string profileRoot,
            Action<bool> panelState, Func<string, bool> restoreFocus)
        {
            if (_compositionHelp != null) throw new InvalidOperationException("Help surface already configured");
            _compositionPanelState = panelState;
            _compositionRestoreFocus = restoreFocus;
            _compositionHelp = new CompositionHelpSurface(_ownerForm, webRoot, profileRoot);
            _compositionHelp.CloseRequested += reason =>
            {
                if (_disposed || !_compositionHelpSelected || _activePanel != "help") return;
                LogManager.Log("[CompositionHelp] close requested reason=" + reason);
                TryClosePanelExact("help", _activePanelInstanceId, true, null);
            };
            PrepareCompositionHelp();
        }

        private async void PrepareCompositionHelp()
        {
            if (_disposed || _compositionHelp == null || _compositionHelpPreparing || _compositionHelp.Ready) return;
            _compositionHelpPreparing = true;
            try
            {
                await _compositionHelp.PrepareAsync();
                if (!_disposed) LogManager.Log("[CompositionHelp] ready; normal game backend");
            }
            catch (Exception ex)
            {
                LogManager.Log("[CompositionHelp] unavailable: " + ex.Message);
            }
            finally { _compositionHelpPreparing = false; }
        }

        private int PanelSurfaceGeneration => _compositionHelpSelected
            ? _compositionHelp.SessionGeneration : _web.PanelSessionGeneration;
        private IntPtr PanelSurfaceHandle => _compositionHelpSelected
            ? _compositionHelp.Handle : (_web.IsHandleCreated ? _web.Handle : IntPtr.Zero);
        private bool ResumePanelSurface(Rectangle rect)
        {
            if (!_compositionHelpSelected) return _web.ResumeForPanel(rect);
            bool resumed = _compositionHelp.ResumePanel(rect);
            if (resumed) _compositionPanelState?.Invoke(true);
            return resumed;
        }
        private bool TryPostToPanelSurface(string json) => _compositionHelpSelected
            ? _compositionHelp.TryPost(json) : _web.TryPostToWeb(json);
        private void PostToPanelSurface(string json)
        {
            if (_compositionHelpSelected) _compositionHelp.TryPost(json);
            else _web.PostToWeb(json);
        }
        private void RepositionPanelSurface(Rectangle rect, bool ensureVisible)
        {
            if (_compositionHelpSelected) _compositionHelp.RepositionPanel(rect, ensureVisible);
            else _web.RepositionForPanel(rect, ensureVisible);
        }
        private bool CommitPanelSurfaceGeometry(Rectangle rect, int generation)
            => _compositionHelpSelected ? _compositionHelp.CommitGeometry(rect, generation)
                : _web.CommitPanelGeometry(rect, generation);
        private void ClearPanelSurfaceGeometry(string reason)
        {
            if (_compositionHelpSelected) _compositionHelp.ClearGeometry(reason);
            else _web?.ClearCommittedPanelGeometry(reason);
        }
        private bool ReplayPanelSurface(Rectangle rect, int generation, string reason)
            => _compositionHelpSelected ? _compositionHelp.Replay(rect, generation, reason)
                : _web.ReplayCommittedPanelPresentation(rect, generation, reason);

        // Only the read-only help pilot uses this lifecycle. No task or save authority
        // is exposed, and no AVM1 cancellation receipt is fabricated.
        private bool RetireCompositionHelp()
        {
            if (!_compositionHelpSelected) return false;
            bool restore = _compositionHelp.CanRestoreGameFocus;
            try { _compositionHelp.Retire(); }
            finally
            {
                _compositionHelpSelected = false;
                _compositionPanelState?.Invoke(false);
                if (!_web.ReleaseWebPanelPauseAfterFailedOpen())
                    LogManager.Log("[CompositionHelp] pause release not delivered");
            }
            // A fresh endpoint is preheated; the retired controller can never own
            // later input. Preparation failure leaves help unavailable, not legacy.
            if (!_disposed) PrepareCompositionHelp();
            return restore;
        }
    }
}
