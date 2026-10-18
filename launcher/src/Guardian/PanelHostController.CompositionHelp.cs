using System;
using System.Drawing;
using Newtonsoft.Json.Linq;

namespace CF7Launcher.Guardian
{
    public partial class PanelHostController
    {
        private CompositionHelpSurface _compositionHelp;
        private bool _compositionHelpSelected;
        private bool _compositionHelpPreparing;
        private CompositionHelpSurface _compositionIntelligence;
        private bool _compositionIntelligenceSelected;
        private bool _compositionIntelligencePreparing;
        private Action<bool> _compositionPanelState;
        private Func<string, bool> _compositionRestoreFocus;
        private Action<Func<Action<string>>> _intelligenceAcquireResponseChannel;
        private Action _intelligenceRestoreResponseChannel;

        internal bool CompositionHelpOwnsInput => SelectedCompositionSurface!=null;

        // help 之外的第二个只读消费者：intelligence（情报档案）。
        // 它的关闭信封（含返回装备 reason）与只读查询都转发给 WebOverlayForm 的既有
        // HandlePanelMessage 权威；本控制器只负责实例绑定、暂停与几何，不复制业务判定。
        internal void ConfigureCompositionIntelligence(string webRoot, string profileRoot,
            Action<string> forwardPanelMessage,
            Action<Func<Action<string>>> acquireResponseChannel, Action restoreResponseChannel,
            bool deferPrewarm = false)
        {
            if (_compositionIntelligence != null)
                throw new InvalidOperationException("Intelligence surface already configured");
            if (forwardPanelMessage == null) throw new ArgumentNullException("forwardPanelMessage");
            if (acquireResponseChannel == null) throw new ArgumentNullException("acquireResponseChannel");
            if (restoreResponseChannel == null) throw new ArgumentNullException("restoreResponseChannel");
            _intelligenceAcquireResponseChannel = acquireResponseChannel;
            _intelligenceRestoreResponseChannel = restoreResponseChannel;
            _compositionIntelligence = new CompositionHelpSurface(_ownerForm, webRoot, profileRoot,
                CompositionPanelProfile.Intelligence);
            _compositionIntelligence.AttachHostLifetime(_hostLifetime);
            _compositionIntelligence.HostCloseRequested += context =>
            {
                if (_disposed || !_compositionIntelligenceSelected || _activePanel != "intelligence") return;
                if (!ExactCloseSource(context)) return;
                LogManager.Log("[CompositionIntelligence] close delegated reason="
                    + context.Cause);
                _web.HandleCompositionIntelligenceClose(context);
            };
            _compositionIntelligence.InboundPanelMessage += message =>
            {
                if (_disposed || !_compositionIntelligenceSelected || _activePanel != "intelligence") return;
                forwardPanelMessage(message.ToString(Newtonsoft.Json.Formatting.None));
            };
            if (!deferPrewarm) PrepareCompositionIntelligence();
        }

        internal void PrewarmCompositionIntelligence() => PrepareCompositionIntelligence();

        private async void PrepareCompositionIntelligence()
        {
            if (_disposed || _compositionIntelligence == null || _compositionIntelligencePreparing
                || _compositionIntelligence.Ready) return;
            _compositionIntelligencePreparing = true;
            try
            {
                await _compositionIntelligence.PrepareAsync();
                if (!_disposed) LogManager.Log("[CompositionIntelligence] ready; normal game backend");
            }
            catch (Exception ex)
            {
                LogManager.Log("[CompositionIntelligence] unavailable: " + ex.Message);
            }
            finally { _compositionIntelligencePreparing = false; }
        }

        internal void ConfigureHelpTutorialPreference(HelpTutorialPreferenceCommand command)
        {
            if (_compositionHelp == null) throw new InvalidOperationException("Help surface not configured");
            _compositionHelp.TutorialPreferenceRequested = (request, instance) =>
                !_disposed && _compositionHelpSelected && _activePanel == "help" && _activePanelInstanceId == instance
                    ? command.Handle(request, instance) : null;
        }

        internal void ConfigureCompositionHelp(string webRoot, string profileRoot,
            Action<bool> panelState, Func<string, bool> restoreFocus, bool deferPrewarm = false)
        {
            if (_compositionHelp != null) throw new InvalidOperationException("Help surface already configured");
            _compositionPanelState = panelState;
            _compositionRestoreFocus = restoreFocus;
            _compositionHelp = new CompositionHelpSurface(_ownerForm, webRoot, profileRoot);
            _compositionHelp.AttachHostLifetime(_hostLifetime);
            _compositionHelp.HostCloseRequested += context =>
            {
                if (_disposed || !_compositionHelpSelected || _activePanel != "help") return;
                TryCloseHostContext(context,true,()=>ExactCloseSource(context),null,null);
            };
            if (!deferPrewarm) PrepareCompositionHelp();
        }

        internal void PrewarmCompositionHelp() => PrepareCompositionHelp();

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

        private CompositionHelpSurface ResolveCompositionSurface(string name)
        {
            if (name == "help") return _compositionHelp;
            if (name == "intelligence") return _compositionIntelligence;
            return null;
        }

        private CompositionHelpSurface SelectedOwnedCompositionSurface
            => _compositionHelpSelected ? _compositionHelp
                : _compositionIntelligenceSelected ? _compositionIntelligence : null;

        internal bool AnyCompositionPanelSelected => SelectedOwnedCompositionSurface != null;

        private void PrepareCompositionSurface(CompositionHelpSurface surface)
        {
            if (ReferenceEquals(surface, _compositionIntelligence)) PrepareCompositionIntelligence();
            else PrepareCompositionHelp();
        }

        // 选中状态只由 DoOpen/Retire 写入；intelligence 选中即接管其只读查询的回包通道，
        // 退休时归还 WebOverlay，避免回包落入没有该页面的旧 Web 文档。
        private void SetCompositionSurfaceSelected(CompositionHelpSurface surface)
        {
            _compositionHelpSelected = surface != null && ReferenceEquals(surface, _compositionHelp);
            bool intelligence = surface != null && ReferenceEquals(surface, _compositionIntelligence);
            if (intelligence == _compositionIntelligenceSelected) return;
            _compositionIntelligenceSelected = intelligence;
            if (intelligence) _intelligenceAcquireResponseChannel?.Invoke(surface.CaptureResponseSink);
            else _intelligenceRestoreResponseChannel?.Invoke();
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

        // Composition surfaces do not own game/save decisions; the exact Lee adapter uses BookshelfTask. The separate,
        // exact-instance tutorial preference command only changes a local launcher
        // preference; intelligence closes/queries stay with the existing Web authority.
        private bool RetireCompositionPanel()
        {
            CompositionHelpSurface surface = SelectedOwnedCompositionSurface;
            if (surface == null) return false;
            bool restore = false;
            try { surface.Retire(); }
            finally
            {
                SetCompositionSurfaceSelected(null);
            }
            // A fresh endpoint is preheated; the retired controller can never own
            // later input. Preparation failure leaves the panel unavailable, not legacy.
            return restore;
        }
    }
}
