using System;
using System.Collections.Generic;
using System.Drawing;
using System.IO;
using System.Linq;
using System.Windows.Forms;
using CF7Launcher.Tasks;
using CF7Launcher.Diagnostic;
using Newtonsoft.Json;
using Newtonsoft.Json.Linq;

namespace CF7Launcher.Guardian
{
    // Owns display admission, HWND order and an already-existing capture fence.
    // A settlement may lend this same endpoint to PanelHost while scene capture continues.
    internal sealed class SceneTransitionController : IDisposable
    {
        private readonly Form _owner;
        private readonly Control _anchor;
        private readonly Func<bool> _admitted;
        private readonly Func<long,bool> _scenePresented;
        private readonly Func<IntPtr,bool> _handoffFocus;
        private readonly Action<bool> _holdWorldInput;
        private readonly CompositionHelpSurface _surface;
        private readonly Form _fallback;
        private readonly OverlayBase[] _overlays;
        private readonly Timer _timer = new() { Interval=25 };
        private JObject _latest, _pendingAction;
        private string _posted, _identity;
        private long _projectionEpoch=-1;
        private bool _disposed, _preparing, _revealed, _recovering, _covered, _orderQueued;
        private int _attempts;
        private DateTime _retryAt;
        internal readonly SceneTransitionTask Task;
        internal bool OwnsCurtain => _latest!=null && !_revealed;
        internal event Action CurtainReleased;
        internal event Action SceneCompleted;
        internal event Action<JObject> SettlementRequest;
        internal event Action SettlementTransportFailed;
        internal CompositionHelpSurface SettlementSurface => _surface;
        private bool _handoffSent;
        internal bool CanAdmitSettlement(string initJson) {
            if(_disposed || !_surface.Ready || !Task.Connected || _latest?.Value<bool?>("reportHandoff")!=true
                || _latest.Value<bool?>("reportVisible")!=true || _surface.SettlementInstance.Length>0) return false;
            try {
                var init=JObject.Parse(initJson);
                return init.Value<string>("sourceKind")=="stage_settlement"
                    && JToken.DeepEquals(init["report"],_latest["report"]);
            } catch { return false; }
        }
        internal void ReleaseSettlement() {
            _surface.ReleaseSettlementBinding();
            if(_latest!=null && !_handoffSent) Task.ReportClosed();
            if(_latest==null || _handoffSent) HidePresentation(handoff:true);
        }

        internal SceneTransitionController(Form owner, Control anchor, string projectRoot,
            Action<Action> dispatch, Func<string,bool> send, Func<bool> admitted,
            Func<long,bool> scenePresented, Func<IntPtr,bool> handoffFocus, IEnumerable<OverlayBase> overlays, Action<bool> holdWorldInput,
            string profileRoot = null)
        {
            _owner=owner; _anchor=anchor; _admitted=admitted; _scenePresented=scenePresented; _handoffFocus=handoffFocus;
            _holdWorldInput=holdWorldInput;
            _overlays=overlays.Where(o=>o!=null).Distinct().ToArray();
            _surface=new CompositionHelpSurface(owner,Path.Combine(projectRoot,"launcher","web"),
                profileRoot ?? Path.Combine(projectRoot,"tmp","unified-live-entry","web-profile"),transition:true);
            _fallback=new Form {Owner=owner,FormBorderStyle=FormBorderStyle.None,ShowInTaskbar=false,
                StartPosition=FormStartPosition.Manual,BackColor=Color.Black,KeyPreview=true,Text="CF7 Transition Recovery"};
            _fallback.Controls.Add(new Label {Dock=DockStyle.Fill,TextAlign=ContentAlignment.MiddleCenter,
                ForeColor=Color.White,BackColor=Color.Black,Font=new Font("Microsoft YaHei",14),
                Text="正在准备加载画面…\n请稍候"});
            _fallback.KeyDown+=(_,e)=>{e.Handled=true;e.SuppressKeyPress=true;};
            Task=new SceneTransitionTask(dispatch,Present,Hide,send);
            _surface.TransitionMessage+=OnMessage;
            _surface.SettlementMessage+=p=> {
                if(p.Value<string>("type")=="scene_transition_report_presented") ObserveSettlementPresented(p);
                else if(!_disposed && Task.Connected && _admitted()) SettlementRequest?.Invoke(p);
            };
            _surface.TransitionFailed+=()=> {
                if(_surface.SettlementInstance.Length>0) SettlementTransportFailed?.Invoke();
                // COM callback only marks failure. Rebuild is deferred to the next UI tick.
                _recovering=true; _posted=null; _revealed=false; _covered=false; _retryAt=DateTime.UtcNow.AddMilliseconds(750);
            };
            foreach(var overlay in _overlays) overlay.PresentationChanged+=OnOverlayPresented;
            _timer.Tick+=(_,_)=>Tick(); _timer.Start();
        }
        private void Present(JObject p) {
            if(_latest?.Value<long>("targetScene")!=p.Value<long>("targetScene") || _projectionEpoch!=Task.Epoch
                || _latest?.Value<string>("requestId")!=p.Value<string>("requestId")) {
                _preparedScene=0;
                if(Task.Connected) _revealed=false;
            }
            string identity=p.Value<string>("requestId");
            if(identity!=_identity || _projectionEpoch!=Task.Epoch) {
                InputLatencyProbe.Current?.BeginTransition(identity, Task.Epoch, p.Value<string>("phase"));
                if(_surface.SettlementInstance.Length==0 || _settlementReceipt?.Value<string>("runId")!=p["report"]?.Value<string>("runId"))
                    _settlementReceipt=null;
                if(identity!=_identity || Task.Connected) _covered=false;
                _identity=identity; _projectionEpoch=Task.Epoch;
                if(Task.Connected || identity!=_latest?.Value<string>("requestId")) _revealed=false;
                _posted=null; _pendingAction=null;
                _handoffSent=false;
                if(!_surface.Ready) { _attempts=0; _retryAt=DateTime.MinValue; }
                LogManager.Log("event=scene_transition_begin id="+identity+" image="+p.Value<string>("imageId"));
            }
            if(_revealed && p.Value<string>("phase")!="reveal") _revealed=false;
            InputLatencyProbe.Current?.SetPhase(p.Value<string>("phase"));
            _latest=p; _holdWorldInput(OwnsCurtain); Tick();
        }
        private long _preparedScene;
        private JObject _settlementReceipt;
        private Func<JObject,bool> _validateSettlementReceipt=_=>false;
        private Func<long,bool> _currentScene=_=>false;
        internal void ConfigureSettlement(Func<JObject,bool> validate,Func<long,bool> currentScene) {
            _validateSettlementReceipt=validate; _currentScene=currentScene;
        }
        internal void ObserveSettlementPresented(JObject p) {
            if(_disposed || _latest?.Value<bool?>("reportHandoff")!=true || !_validateSettlementReceipt(p)
                || p.Value<string>("runId")!=_latest["report"]?.Value<string>("runId")) return;
            _settlementReceipt=(JObject)p.DeepClone(); TryCompleteReportHandoff();
        }
        private bool TryCompleteReportHandoff() {
            if(_revealed || _latest?.Value<bool?>("reportHandoff")!=true || _settlementReceipt==null || !Task.Connected
                || _preparedScene!=_latest.Value<long>("targetScene") || !_currentScene(_preparedScene)
                || _settlementReceipt.Value<string>("runId")!=_latest["report"]?.Value<string>("runId")
                || !_validateSettlementReceipt(_settlementReceipt)) return false;
            if(!Task.CompleteReportHandoff()) return false;
            _handoffSent=true; _revealed=true;
            LogManager.Log("event=scene_transition_settlement_ready id="+_identity+" panel="+_settlementReceipt.Value<string>("panelInstanceId"));
            return true;
        }
        private async void Prepare() {
            if(_disposed || _preparing || _surface.Ready || _surface.SettlementInstance.Length>0 || _attempts>=3 || DateTime.UtcNow<_retryAt) return;
            _preparing=true; _attempts++;
            try {
                await _surface.PrepareAsync();
                if(!_disposed) { _posted=null; _recovering=false; _attempts=0; }
            } catch(Exception e) {
                if(!_disposed) { _recovering=true; _retryAt=DateTime.UtcNow.AddSeconds(2);
                    LogManager.Log("event=scene_transition_prepare_failed attempt="+_attempts+" error="+e.Message); }
            } finally { _preparing=false; }
        }
        private Rectangle Bounds() => _anchor.RectangleToScreen(_anchor.ClientRectangle);
        private void Tick() {
            using var latency = InputLatencyProbe.Measure("transition_tick");
            if(_disposed || _owner.IsDisposed || _anchor.IsDisposed) return;
            Prepare();
            if(_latest==null || _revealed) {
                if(_surface.SettlementInstance.Length>0 && _surface.Ready) {
                    if(_admitted() && _owner.Visible && _owner.WindowState!=FormWindowState.Minimized && _surface.CanRestoreGameFocus)
                        _surface.PresentTransition(Bounds());
                    else _surface.SuppressTransition();
                }
                return;
            }
            if(TryCompleteReportHandoff()) return;
            bool visible=_admitted() && _owner.Visible && _owner.WindowState!=FormWindowState.Minimized
                && _surface.CanRestoreGameFocus;
            if(!visible) { if(_fallback.Visible)_fallback.Hide(); _surface.SuppressTransition(); return; }
            Rectangle bounds=Bounds();
            if(bounds.Width<1 || bounds.Height<1) return;
            // Admission precedes Web delivery/decode. Keep an opaque backing until the
            // current endpoint has painted this curtain, even when it was already warm.
            if(!_covered || !_surface.Ready || _recovering) {
                if(_fallback.Bounds!=bounds) _fallback.Bounds=bounds;
                if(!_fallback.Visible) { _fallback.Show(); _fallback.Activate(); }
            }
            if(!_surface.Ready || _recovering) { RestoreWindowOrder(); return; }
            if(!_surface.PresentTransition(bounds)) return;
            var projection=(JObject)_latest.DeepClone();
            projection["type"]="scene_transition"; projection["connected"]=Task.Connected;
            projection["generation"]=Task.Epoch;
            projection["revealAllowed"]=Task.Connected && projection.Value<string>("phase")=="reveal"
                && _scenePresented(projection.Value<long>("targetScene"));
            if(projection.Value<bool>("revealAllowed") && projection.Value<bool?>("reportVisible")==true) {
                _preparedScene=projection.Value<long>("targetScene"); Task.ScenePrepared();
            }
            projection["reportReady"]=Task.Connected && _preparedScene==projection.Value<long>("targetScene")
                && _currentScene(_preparedScene);
            projection["rewardReady"]=Task.Connected && _covered;
            string signature=projection.ToString(Formatting.None);
            if(signature!=_posted && _surface.PostTransition(projection)) {
                _posted=signature;
                LogManager.Log("event=scene_transition_project id="+_identity+" phase="+projection.Value<string>("phase")
                    +" revision="+projection.Value<int>("revision")+" reveal="+projection.Value<bool>("revealAllowed"));
            }
            RestoreWindowOrder();
            if(_pendingAction!=null && _surface.TransitionInputReleased) {
                var action=_pendingAction; _pendingAction=null; Task.Action(action);
            }
        }
        private void OnMessage(JObject p) {
            if(_disposed || _latest==null || !Task.Connected) return;
            string type=p["type"]?.Type==JTokenType.String?p.Value<string>("type"):null;
            if(type=="scene_transition_action" ? !Task.MatchesWebAction(p) : !Task.MatchesWeb(p)) return;
            if(type=="scene_transition_report_view") {
                // Optional bounded diagnostics; the live DOM already owns its reading state.
                return;
            }
            // Automatic reward admission can arrive during Alt+Tab. Queue it until Tick's
            // existing foreground gate is satisfied; never open the ordinary panel while away.
            if(type=="scene_transition_action") {
                if(_surface.Visible || p["verb"]?.Type==JTokenType.String && p.Value<string>("verb")=="manageReport") _pendingAction=p;
                return;
            }
            if(!_surface.Visible) return;
            if(type!="scene_transition_presented") return;
            string kind=p["kind"]?.Type==JTokenType.String?p.Value<string>("kind"):null;
            if(kind=="covered") { if(Task.Presented(p)) { _covered=true; _fallback.Hide(); } }
            else if(kind=="revealed" && _latest.Value<bool?>("reportVisible")!=true && _latest.Value<string>("phase")=="reveal"
                && _scenePresented(_latest.Value<long>("targetScene"))) {
                if(!Task.Presented(p)) return;
                _revealed=true; HidePresentation(handoff:true);
                CurtainReleased?.Invoke();
                LogManager.Log("event=scene_transition_revealed id="+_identity+" scene="+_latest.Value<long>("targetScene"));
            }
        }
        private void OnOverlayPresented() {
            if(_disposed || _orderQueued || _latest==null || _revealed || !_owner.IsHandleCreated || _owner.IsDisposed) return;
            _orderQueued=true;
            try {
                _owner.BeginInvoke((Action)(()=> {
                    _orderQueued=false;
                    // A hide, disconnect or Alt+Tab may happen before this callback.
                    if(!_disposed && _latest!=null && !_revealed && _admitted()
                        && _owner.Visible && _owner.WindowState!=FormWindowState.Minimized && _surface.CanRestoreGameFocus)
                        RestoreWindowOrder();
                }));
            } catch(InvalidOperationException) { _orderQueued=false; }
        }
        private void RestoreWindowOrder() {
            bool showSurface=_surface.Active && !_recovering;
            if(_fallback.Visible) SceneTransitionWindowOrder.RaiseIfCovered(_fallback,_owner,
                showSurface && _surface.Visible ? _surface.Handle : IntPtr.Zero);
            if(showSurface) _surface.RaiseTransition();
        }
        private void HidePresentation(bool handoff) {
            // Hiding the active curtain first lets another application become foreground.
            // Pin the live foreground and hand it to the game root before any Hide call.
            // The existing primitive checks that exact HWND again and never retries against
            // a foreign foreground window; an intentional Alt+Tab remains untouched.
            if(handoff && _admitted()) {
                IntPtr foreground=_surface.CaptureGameForeground();
                if(foreground!=IntPtr.Zero && !_handoffFocus(foreground))
                    LogManager.Log("event=scene_transition_handoff_failed id="+_identity);
            }
            _surface.HideTransition(); _fallback.Hide();
            _holdWorldInput(false);
        }
        private void Hide() {
            if(_disposed || _latest==null) return;
            using var latency = InputLatencyProbe.Measure("transition_hide");
            bool retained=_surface.SettlementInstance.Length>0;
            bool complete=_handoffSent && _preparedScene>0 && _currentScene(_preparedScene);
            bool held=_latest!=null && !_revealed;
            bool handoff=held && (_surface.Visible || _fallback.Visible);
            _latest=null; _identity=null; _pendingAction=null; _posted=null; _revealed=false; _covered=false;
            _preparedScene=0;
            if(!retained) _settlementReceipt=null;
            if(retained) {
                _fallback.Hide(); _holdWorldInput(!complete);
                if(complete) {
                    _surface.TryPostTransitionPanel("{\"type\":\"scene_transition_complete\"}");
                    SceneCompleted?.Invoke();
                }
            } else HidePresentation(handoff);
            InputLatencyProbe.Current?.SetPhase(complete ? "base_ready" : "hidden", finished: true);
            if(held) CurtainReleased?.Invoke();
        }
        public void Dispose() {
            if(_disposed)return; _disposed=true;
            foreach(var overlay in _overlays) overlay.PresentationChanged-=OnOverlayPresented;
            _holdWorldInput(false);
            _timer.Dispose(); _surface.Dispose(); _fallback.Dispose();
        }
    }
}
