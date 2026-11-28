using System;
using System.Drawing;
using System.Threading;
using System.Windows.Forms;
using Newtonsoft.Json.Linq;

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
        internal static bool IsIntroComicEndpointPresented(string panel,string currentInstance,string expectedInstance,
            bool documentReady,Form endpoint) => panel=="book-comic" && !string.IsNullOrEmpty(expectedInstance)
            && currentInstance==expectedInstance && documentReady && SceneTransitionWindowOrder.IsPresented(endpoint);
        private CompositionHelpSurface SelectedCompositionSurface => _transitionSettlementSelected
            ? _sceneSettlement.SettlementSurface
            : _compositionHelpSelected ? _compositionHelp
            : _compositionIntelligenceSelected ? _compositionIntelligence : null;

        internal Microsoft.Web.WebView2.Core.CoreWebView2 TryGetActiveHarnessWebCore(out string surfaceKind)
        {
            var s = SelectedCompositionSurface;
            if (s != null && s.Active && s.InternalCoreWebView2 != null)
            {
                surfaceKind = _transitionSettlementSelected
                    ? "settlement"
                    : (_compositionHelpSelected ? "composition_help"
                        : (_compositionIntelligenceSelected ? "composition_intelligence" : ("composition_" + (_activePanel ?? "unknown"))));
                return s.InternalCoreWebView2;
            }
            surfaceKind = null;
            return null;
        }

        internal void ConfigureTransitionSettlement(SceneTransitionController controller)
        {
            _sceneSettlement=controller;
            controller.PanelAdmissionAvailable+=OnTransitionPanelAdmissionAvailable;
            controller.SettlementSurface.AttachHostLifetime(_hostLifetime);
            controller.ConfigureExclusivePresentation(() => SceneTransitionController.IsExclusivePresentation(_activePanel, _activePanelInstanceId));
            bool ExactIntroEndpoint(string instance) => !_disposed && IsIntroComicEndpointPresented(
                _activePanel,_activePanelInstanceId,instance,_web?.CanAcceptPanelDocumentMessages==true,_web);
            controller.ConfigureIntroPresentation(instance => {
                if(!ExactIntroEndpoint(instance))return false;
                EnsurePanelZOrder();
                return SceneTransitionWindowOrder.IsPresented(_web);
            // Document loss revokes activation, but the exact native panel still
            // owns foreground while the recovery cover replaces it.
            },instance => !_disposed && IsIntroComicEndpointPresented(_activePanel,_activePanelInstanceId,
                instance,true,_web) && SceneTransitionWindowOrder.OwnsForeground(_web),
            instance => {
                var context=LastCloseOutcome;
                if(_disposed || context?.Endpoint.Panel!="book-comic" || context.Endpoint.Instance!=instance)return false;
                if(EffectiveInputOwner.ClosingId==context.CloseId)
                    return ClosingFocusEligible(context) && (context.SourceRetired || context.SourceIdentity?.IsCurrent()==true);
                return _executingClose==null && !context.CleanupFailed && context.Plan==ClosePlanKind.ReturnGame
                    && context.Authority!=AuthorityCommitState.Unknown
                    && Interlocked.Read(ref _inputAdmissionStamp)==context.AdmissionStamp
                    && _activePanel==null && !AnyCompositionPanelSelected && !_transitionSettlementSelected
                    && Volatile.Read(ref _pendingInputOwner)==null
                    && _additionalFocusGate() && !NativeInputBlocksGame()
                    && (EffectiveInputOwner.Kind==EffectiveInputOwnerKind.Game
                        || EffectiveInputOwner.Kind==EffectiveInputOwnerKind.Transition && Volatile.Read(ref _transitionInputHeld)!=0);
            });
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

        private void OnTransitionPanelAdmissionAvailable()
        {
            if(!_disposed && _sceneSettlement?.BlocksOrdinaryPanelOpen==false)
                FlushDeferredBarrierOpen();
        }

        private bool SceneTransitionBlocksOpen(string panel,string initJson)
        {
            if(_sceneSettlement?.BlocksOrdinaryPanelOpen!=true) return false;
            // These two endpoints participate in the transition itself. Their
            // existing exact authority checks, rather than panel names, grant entry.
            if(panel=="loot" && _sceneSettlement.CanAdmitSettlement(initJson)) return false;
            if(panel=="book-comic") {
                try { if(_sceneSettlement.CanAdmitIntroComic(JObject.Parse(initJson ?? ""))) return false; }
                catch(Newtonsoft.Json.JsonException) { }
            }
            return true;
        }

        private bool OpenTransitionSettlement(PanelGeometrySnapshot geometry,string initJson,
            string instance,bool tracked,Action posted)
        {
            var surface=_sceneSettlement.SettlementSurface;
            if(!surface.PresentTransition(geometry.PanelRect, _sceneSettlement.AllowsHeadlessPresentation)) return false;
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

        private bool RetireTransitionSettlement(string closePayload=null)
        {
            if(!_transitionSettlementSelected) return false;
            _transitionSettlementSelected=false; _transitionSettlementPaused=false;
            _sceneSettlement.ReleaseSettlement(closePayload);
            return false;
        }
    }
}
