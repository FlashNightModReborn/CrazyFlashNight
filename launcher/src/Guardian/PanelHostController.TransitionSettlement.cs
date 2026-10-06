using System;
using System.Drawing;

namespace CF7Launcher.Guardian
{
    public partial class PanelHostController
    {
        private SceneTransitionController _sceneSettlement;
        private bool _transitionSettlementSelected, _transitionSettlementPaused;
        internal bool SceneSettlementLoading => _transitionSettlementSelected && !_transitionSettlementPaused;
        internal bool BookshelfReturnLoading => _sceneSettlement?.BookshelfReturnLoading == true;
        internal bool UsesTransitionSettlement => _transitionSettlementSelected;
        internal SceneTransitionController SceneTransition => _sceneSettlement;
        private CompositionHelpSurface SelectedCompositionSurface => _transitionSettlementSelected
            ? _sceneSettlement.SettlementSurface : _compositionHelpSelected ? _compositionHelp : null;

        internal void ConfigureTransitionSettlement(SceneTransitionController controller)
        {
            _sceneSettlement=controller;
            controller.ConfigureExclusivePresentation(() => SceneTransitionController.IsExclusivePresentation(_activePanel, _activePanelInstanceId));
            controller.SettlementRequest+=p=>_web.HandleTransitionSettlementMessage(p);
            controller.SettlementTransportFailed+=()=>_web.HandleTransitionSettlementFailure();
            controller.SceneCompleted+=()=> {
                if(!_transitionSettlementSelected || _disposed) return;
                // AS2 has retired its loading timeline. Pause only now; loading and
                // the already-bound reward session ran together on the same endpoint.
                if(!_transitionSettlementPaused) _transitionSettlementPaused=_web.AssertWebPanelPause();
                if(!_transitionSettlementPaused)
                    LogManager.Log("event=scene_settlement_pause_failed instance="+_activePanelInstanceId);
            };
        }

        private bool OpenTransitionSettlement(PanelGeometrySnapshot geometry,string initJson,
            string instance,bool tracked,Action posted)
        {
            var surface=_sceneSettlement.SettlementSurface;
            if(!surface.PresentTransition(geometry.PanelRect)) return false;
            _transitionSettlementSelected=true;
            try {
                SuspendHudCompanion(); _hud.Suspend();
                initJson=ApplyInitDataEnrichers("loot",initJson,instance);
                if(!surface.TryPostTransitionPanel(BuildPanelOpenPayload("loot",initJson,instance)))
                    throw new InvalidOperationException("settlement open not delivered");
                _activePanel="loot"; _activePanelInstanceId=instance;
                if(!CommitGeometry(geometry,surface.SessionGeneration))
                    throw new InvalidOperationException("settlement geometry rejected");
                _shield?.EnterTelemetryMode(geometry.PanelRect,_ownerForm.Handle,
                    geometry.AnchorRect,surface.Handle);
                _compositionPanelState?.Invoke(true);
                _escSource?.SetPanelEscapeEnabled(false);
                SubscribeOwnerLayout();
                PublishPanelChanged("loot",instance);
                if(tracked) posted?.Invoke();
                LogManager.Log("event=scene_settlement_bound instance="+instance+" generation="+surface.SessionGeneration);
                return true;
            } catch(Exception ex) {
                LogManager.Log("event=scene_settlement_open_failed reason="+ex.Message);
                AbortOpenAttempt(false,"scene_settlement_open_failed"); return false;
            }
        }

        internal bool TryPostTransitionSettlement(string json)
            => _transitionSettlementSelected && _sceneSettlement.SettlementSurface.TryPostTransitionPanel(json);

        private bool RetireTransitionSettlement()
        {
            if(!_transitionSettlementSelected) return false;
            bool restore=_transitionSettlementPaused && _sceneSettlement.SettlementSurface.CanRestoreGameFocus;
            _transitionSettlementSelected=false; _transitionSettlementPaused=false;
            _compositionPanelState?.Invoke(false);
            _sceneSettlement.ReleaseSettlement();
            return restore;
        }
    }
}
