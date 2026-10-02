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

        internal bool CompositionHelpOwnsInput => SelectedCompositionSurface!=null;

        internal void ConfigureHelpTutorialPreference(HelpTutorialPreferenceCommand command)
        {
            if (_compositionHelp == null) throw new InvalidOperationException("Help surface not configured");
            _compositionHelp.TutorialPreferenceRequested = (request, instance) =>
                !_disposed && _compositionHelpSelected && _activePanel == "help" && _activePanelInstanceId == instance
                    ? command.Handle(request, instance) : null;
        }

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

        private int PanelSurfaceGeneration => SelectedCompositionSurface?.SessionGeneration ?? _web.PanelSessionGeneration;
        private IntPtr PanelSurfaceHandle => SelectedCompositionSurface?.Handle ?? (_web.IsHandleCreated ? _web.Handle : IntPtr.Zero);
        private bool ResumePanelSurface(Rectangle rect)
        {
            if (SelectedCompositionSurface==null) return _web.ResumeForPanel(rect);
            bool resumed = SelectedCompositionSurface.ResumePanel(rect);
            if (resumed) _compositionPanelState?.Invoke(true);
            return resumed;
        }
        private bool TryPostToPanelSurface(string json) => SelectedCompositionSurface!=null
            ? SelectedCompositionSurface.TryPost(json) : _web.TryPostToWeb(json);
        private void PostToPanelSurface(string json)
        {
            if (SelectedCompositionSurface!=null) SelectedCompositionSurface.TryPost(json);
            else _web.PostToWeb(json);
        }
        private void RepositionPanelSurface(Rectangle rect, bool ensureVisible)
        {
            if (SelectedCompositionSurface!=null) SelectedCompositionSurface.RepositionPanel(rect, ensureVisible);
            else _web.RepositionForPanel(rect, ensureVisible);
        }
        private bool CommitPanelSurfaceGeometry(Rectangle rect, int generation)
            => SelectedCompositionSurface!=null ? SelectedCompositionSurface.CommitGeometry(rect, generation)
                : _web.CommitPanelGeometry(rect, generation);
        private void ClearPanelSurfaceGeometry(string reason)
        {
            if (SelectedCompositionSurface!=null) SelectedCompositionSurface.ClearGeometry(reason);
            else _web?.ClearCommittedPanelGeometry(reason);
        }
        private bool ReplayPanelSurface(Rectangle rect, int generation, string reason)
            => SelectedCompositionSurface!=null ? SelectedCompositionSurface.Replay(rect, generation, reason)
                : _web.ReplayCommittedPanelPresentation(rect, generation, reason);

        // Help exposes no game task or save authority. The separate, exact-instance
        // tutorial preference command only changes a local launcher preference.
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
