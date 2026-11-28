using System;
using System.Threading;
using Newtonsoft.Json.Linq;

namespace CF7Launcher.Guardian
{
    public partial class PanelHostController
    {
        private WindowManager _closeFocusManager;
        private HostCloseContext _executingClose;
        private HostCloseContext _admittingClose;
        private EndpointLease _activeEndpointLease;
        private Func<bool> _additionalFocusGate=()=>true, _focusLifetime=()=>true;
        internal string HostLifetime => _hostLifetime;
        internal HostCloseContext ExecutingClose => _executingClose;
        internal void WithHostCloseContext(HostCloseContext context, Action action)
        { var previous=_admittingClose; _admittingClose=context; try { action(); } finally { _admittingClose=previous; } }
        internal HostCloseContext LastCloseOutcome { get; private set; }
#if CF7_TEST_SEAMS
        internal Action ReleaseClosePauseForTests;
#endif
        internal void ConfigureCloseFocus(WindowManager manager,Func<bool> additionalGate=null,Func<bool> lifetime=null)
        {
            _closeFocusManager=manager;
            _additionalFocusGate=additionalGate ?? (()=>true);
            _focusLifetime=lifetime ?? (()=>true);
        }
        private HostCloseContext CaptureHostClose(string panel, string instance, NativeCloseCause cause=NativeCloseCause.HostOperation)
        {
            EndpointLease endpoint=_activeEndpointLease?.Panel==panel && _activeEndpointLease.Instance==instance ? _activeEndpointLease : null;
            if(endpoint==null)endpoint=SelectedCompositionSurface?.CaptureEndpointLease();
            if(endpoint==null)endpoint=_web?.CaptureEndpointLease(panel,instance,_hostLifetime);
            if(endpoint==null)endpoint=new EndpointLease(null,null,null,panel,instance,_hostLifetime,0,0,0,IntPtr.Zero);
            if(cause==NativeCloseCause.HostOperation && endpoint.Surface is WebOverlayForm && _web?.LivePanelEndpointAvailable!=true)
                cause=NativeCloseCause.FailedOpen;
            var context=new HostCloseContext(endpoint,cause,new JObject { ["type"]="panel",["panel"]=panel,
                ["cmd"]="close",["panelInstanceId"]=instance },
                endpoint.Surface is CompositionHelpSurface surface ? surface.CaptureGameForeground() :
                _web?.CaptureTrustedCloseForeground() ?? IntPtr.Zero);
            context.AdmissionStamp=Interlocked.Read(ref _inputAdmissionStamp);
            return context;
        }
        internal bool TryCloseHostContext(HostCloseContext context, bool dismissReturnStack,
            Func<bool> gate, Action commit, Action<bool> completed)
        {
            if(!ExactCloseSource(context))return false;
            context.AdmissionStamp=Interlocked.Read(ref _inputAdmissionStamp);
            var command=new PanelCommand(PanelCommandKind.Close,context.Endpoint.Panel,null) {
                IsExactClose=true, ReservedPanelInstanceId=context.Endpoint.Instance,
                DismissReturnStackOnExactClose=dismissReturnStack, ExactCloseExecutionGate=gate,
                ExactCloseCommitNoFail=commit, ExactCloseCompleted=completed, CloseContext=context
            };
            return EnqueueAndPump(command);
        }
        private void RunCloseCleanup(HostCloseContext context, string stage, Action cleanup, bool requireActive=true)
        {
            if(requireActive && !OwnsClosingCleanup(context))return;
            try { cleanup(); } catch(Exception error) {
                context.CleanupFailed=true;
                try { LogManager.Log("[PanelClose] cleanup failed close="+context.CloseId+" stage="+stage+" type="+error.GetType().Name); } catch { }
            }
        }
        private void ReturnRootBeforeClose(HostCloseContext context)
        {
            if (_closeFocusManager != null && ClosingFocusIdentity(context)
                && context.SourceIdentity?.IsCurrent() == true)
                _closeFocusManager.ActivateSessionRootBeforeHide(context.SourceForeground);
        }
        private bool DoCloseTransaction(HostCloseContext context)
        {
            if (!OwnsClosingCleanup(context)) return false;
            string panel=context.Endpoint.Panel, instance=context.Endpoint.Instance;
            var surface=context.Endpoint.Surface as CompositionHelpSurface;
            bool settlement=_transitionSettlementSelected;
            var previous=_executingClose;
            _executingClose=context;
            bool tailQueued=false;
            IDisposable webScope=_web?.EnterManagedClose();
            try {
                Action before=_testBeforeDoClose;
                _testBeforeDoClose=null;
                before?.Invoke();
                if(!OwnsClosingCleanup(context)) { context.Outcome="Superseded"; return false; }
                // Every callback can admit or install another owner. Never use mutable
                // selection to retire a successor after a callback returns.
                RunCloseCleanup(context,"observer",()=>_panelCloseObserver?.Invoke(panel,instance));
                if(!OwnsClosingCleanup(context)) { context.Outcome="Superseded"; return false; }
                RunCloseCleanup(context,"geometry",()=>ClearCommittedGeometry("panel_close"));
                RunCloseCleanup(context,"owner_layout",UnsubscribeOwnerLayout);
                string payload=BuildPanelClosePayload(panel,instance);
                bool deferSettlementView=settlement && context.Plan==ClosePlanKind.ReturnGame
                    && context.Authority!=AuthorityCommitState.Unknown;
                if(!deferSettlementView && payload!=null && context.Endpoint.Core!=null && context.Plan!=ClosePlanKind.CleanupOnly)
                    RunCloseCleanup(context,"web_close",()=> {
                        if(surface!=null)surface.TryPostExact(payload,context.Endpoint);
                        else if(_web.IsEndpointCurrent(context.Endpoint))context.Endpoint.Core.PostWebMessageAsJson(payload);
                    });
                // A retiring editor releases its own lease before an exact return to
                // the Guardian root. A retained settlement view also drops capture here.
                if (_passiveInput != null && surface != null)
                    RunCloseCleanup(context, "retire_input", surface.RetireEndpointInput);
                // The root handoff occurs while the original source is still alive.
                // No later cleanup callback is allowed another foreground attempt.
                ReturnRootBeforeClose(context);
                RunCloseCleanup(context,"retire",()=> {
                    if(settlement)RetireTransitionSettlement(deferSettlementView ? payload : null);
                    else if(surface!=null) {
                        if(!surface.RetireExact(context.Endpoint))throw new InvalidOperationException("Source retirement lost its lease");
                        if(ReferenceEquals(SelectedOwnedCompositionSurface,surface) && surface.IsRetiredEndpoint(context.Endpoint))
                            SetCompositionSurfaceSelected(null);
                    } else if(_testPumpDispatcher==null) {
                        if(context.Plan==ClosePlanKind.CleanupOnly)_web.ForceIdleState(panel);
                        else _web.SuspendAfterPanel(panel);
                    }
                    context.SourceRetired=true;
                });
                RunCloseCleanup(context,"shield",()=>_shield?.ExitTelemetryMode());
                RunCloseCleanup(context,"backdrop",()=>_backdrop?.Hide());
                RunCloseCleanup(context,"hud",()=>_hud?.Resume());
                RunCloseCleanup(context,"companion",ResumeHudCompanion);
                RunCloseCleanup(context,"escape",()=>_escSource?.SetPanelEscapeEnabled(false));
                RunCloseCleanup(context,"cursor",()=> {
                    ReTopOverlay(_cursor as System.Windows.Forms.Form);
                    _web?.UpdateCursorFromScreenPoint(System.Windows.Forms.Cursor.Position);
                });
                if(!OwnsClosingCleanup(context)) { context.Outcome="Superseded"; return false; }
                // CommitAcceptedPanelCloseEffects normally releases its own domain pause.
                // Composition/help has no business callback; its generic pause is released here.
                if(context.ReleaseGenericPause || surface!=null && context.Authority==AuthorityCommitState.NotStarted)
                    RunCloseCleanup(context,"pause",()=> {
#if CF7_TEST_SEAMS
                        if(_testPumpDispatcher!=null && ReleaseClosePauseForTests!=null) {
                            ReleaseClosePauseForTests();
                            return;
                        }
#endif
                        _web?.ReleaseClosePause();
                    });
                if(!OwnsClosingCleanup(context)) { context.Outcome="Superseded"; return false; }
                ClearActiveSettingsPreview();
                _activePanel=null; _activePanelInstanceId=null;
                if(ReferenceEquals(_activeEndpointLease,context.Endpoint))_activeEndpointLease=null;
                context.SourceRetired=true;
                context.Outcome=context.CleanupFailed ? "CleanupFailed" :
                    context.Authority==AuthorityCommitState.Unknown ? "AuthorityUnknown" : "Closed";
                // Keep Closing published until the exact business close tail settles.
                try { PublishPanelChanged(null,null); } catch { context.CleanupFailed=true; }
                if(_web!=null) {
                    try { _web.PublishClosePanelState(); } catch { context.CleanupFailed=true; }
                }
                tailQueued=true;
                PostPanelClosed(panel,instance,()=> {
                    if(panel=="book-comic" && _sceneSettlement?.DeferIntroResumeTail(instance,()=>FinishClosingExact(context))==true)return;
                    if(settlement && _sceneSettlement?.DeferSettlementResumeTail(()=>FinishClosingExact(context))==true)return;
                    FinishClosingExact(context);
                },context);
                return !context.CleanupFailed && context.Authority!=AuthorityCommitState.Unknown;
            } finally {
                webScope?.Dispose();
                if(!tailQueued)FinishClosingExact(context);
                _executingClose=previous;
                if(surface!=null && !settlement && surface.IsRetiredEndpoint(context.Endpoint) && _ownerForm!=null)
                    try { _ownerForm.BeginInvoke((Action)(()=> {
                        if(!_disposed && surface.IsRetiredEndpoint(context.Endpoint))PrepareCompositionSurface(surface);
                    })); } catch { }
            }
        }
    }
}
