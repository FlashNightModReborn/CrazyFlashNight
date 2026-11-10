using System;
using System.Drawing;
using System.Windows.Forms;
using Newtonsoft.Json.Linq;

namespace CF7Launcher.Guardian
{
    internal sealed partial class SceneTransitionController
    {
        private volatile IntroPresentationHandoff _intro;
        private Func<string,bool> _presentIntroComic = _ => false;
        private Func<string,bool> _introOwnsForeground = _ => false;
        private Func<string,bool> _introFocusAdmission = _ => false;
        private Func<bool> _introFlashInputFocused = () => false;
        private static Button IntroActionButton(string text) => new() { Text=text,AutoSize=true,
            ForeColor=Color.White,BackColor=Color.FromArgb(45,45,45),FlatStyle=FlatStyle.Flat,
            Font=new Font("Microsoft YaHei",10.5f),MinimumSize=new Size(128,36) };
        private readonly Button _introRetry = IntroActionButton("重试漫画");
        private readonly Button _introReturn = IntroActionButton("返回书架");
        private FlowLayoutPanel _introActions;
        internal void ConfigureIntroPresentation(Func<string,bool> present,Func<string,bool> ownsForeground,
            Func<string,bool> focusAdmission=null,Func<bool> flashInputFocused=null)
        {
            _presentIntroComic=present;
            _introOwnsForeground=ownsForeground;
            _introFocusAdmission=focusAdmission ?? (_=>false);
            _introFlashInputFocused=flashInputFocused ?? (()=>false);
            _introActions=new FlowLayoutPanel { Dock=DockStyle.Bottom,Height=64,Padding=new Padding(12,8,12,8),
                FlowDirection=FlowDirection.LeftToRight,BackColor=Color.Black,Visible=false };
            _introActions.Controls.AddRange(new Control[]{_introRetry,_introReturn});
            _fallback.Controls.Add(_introActions); _introActions.BringToFront();
            _introRetry.Click+=(_,_)=>Task.IntroAction("retry");
            _introReturn.Click+=(_,_)=>Task.IntroAction("return");
        }
        private void ObserveIntro(JObject p)
        {
            if(p.Value<long>("version")!=3) { RetireIntro(); return; }
            if(_intro==null || !_intro.Matches(p,Task.Epoch)) {
                RetireIntro(); _intro=new IntroPresentationHandoff(p,Task.Epoch);
            }
            _intro.Observe(p.Value<string>("introState"),p.Value<string>("phase")=="intro");
        }
        private void RetireIntro()
        {
            var old=_intro; _intro=null; old?.Retire();
            if(_introActions!=null)_introActions.Visible=false;
        }
        internal bool CanAdmitIntroComic(JObject data) => !_disposed && Task.Connected && _intro!=null
            && _currentScene(_intro.Scene) && _intro.Admits(data);
        internal void QueueIntroActivation(JObject data,string instance,Action activation)
        {
            if(_disposed || !Task.Connected || _intro?.QueueActivation(data,instance,activation)!=true) return;
            Tick();
        }
        internal void BindIntroClosing(JObject data,string instance) => _intro?.BindClosing(data,instance);
        internal void BeginIntroComicClose(string instance)
        {
            if(_disposed || _intro?.BeginClose(instance)!=true) return;
            _holdWorldInput(true);
            PresentIntroCover();
        }
        internal void IntroComicClosed(string instance,bool closed)
        {
            if(!closed || _intro?.Closed(instance)!=true) return;
            _requireFreshFrame(_intro.Scene);
            Tick();
        }
        internal bool DeferIntroResumeTail(string instance,Action tail) => _intro?.DeferTail(instance,tail)==true;
        private bool IntroCanPresent => _admitted() && _owner.Visible && _owner.WindowState!=FormWindowState.Minimized
            && (_intro?.HasPresentationForeground(_surface.CanRestoreGameFocus,_introOwnsForeground)
                ?? _surface.CanRestoreGameFocus);
        private void PresentIntroCover()
        {
            if(_intro==null || !IntroCanPresent) { _fallback.Hide(); _surface.SuppressTransition(); return; }
            Rectangle bounds=Bounds();
            bool failed=_intro.State=="failed";
            if(_introActions!=null) {
                _introActions.Visible=failed;
                _introRetry.Enabled=_introReturn.Enabled=failed && !_exclusivePresentation() && Task.Connected;
            }
            if(failed || !_surface.Ready || _recovering) {
                _surface.SuppressTransition();
                _fallback.Bounds=bounds;
                foreach(Control child in _fallback.Controls)
                    if(child is Label label) label.Text=failed ? "漫画暂时未能打开。\n可以重试，或安全返回书架。" : "正在准备加载画面…\n请稍候";
                if(!_fallback.Visible)_fallback.Show();
                SceneTransitionWindowOrder.RaiseIfCovered(_fallback,_owner);
            } else {
                _surface.PresentTransition(bounds);
                var projection=(JObject)_latest.DeepClone();
                projection["type"]="scene_transition";projection["generation"]=Task.Epoch;
                projection["connected"]=Task.Connected;projection["revealAllowed"]=false;
                string signature=projection.ToString(Newtonsoft.Json.Formatting.None);
                if(signature!=_posted && _surface.PostTransition(projection))_posted=signature;
                if(!_covered) {
                    _fallback.Bounds=bounds;
                    if(!_fallback.Visible)_fallback.Show();
                    SceneTransitionWindowOrder.RaiseIfCovered(_fallback,_owner);
                    return;
                }
                _fallback.Hide();
                _surface.RaiseTransition();
            }
        }
        private bool ExactIntroResume(IntroPresentationHandoff intro,string id,string instance,long scene,long epoch)
            => ReferenceEquals(_intro,intro) && Task.Epoch==epoch && intro.Id==id && intro.Instance==instance
                && intro.Matches(_latest,epoch) && _latest?.Value<string>("phase")=="intro"
                && (intro.State is "narrative" or "resume") && _currentScene(scene) && _scenePresented(scene);
        private bool TickIntro()
        {
            if(_intro==null || _latest?.Value<string>("phase")!="intro")return false;
            Prepare();
            _intro.FinishFailedClose();
            bool admitted=IntroCanPresent;
            _intro.ObserveForegroundAdmission(admitted);
            if(!Task.Connected || !admitted) { _fallback.Hide(); _surface.SuppressTransition(); return true; }
            if(_intro.CanResume(_currentScene(_intro.Scene),_scenePresented(_intro.Scene),admitted)) {
                var intro=_intro;
                string id=intro.Id, instance=intro.Instance;
                long scene=intro.Scene, epoch=Task.Epoch;
                bool focused=_presentationPolicy.NonActivating || _introFlashInputFocused();
                if(!focused && !intro.FocusHandoffAttempted) {
                    IntPtr foreground=_surface.CaptureGameForeground();
                    bool coverAlive=!_fallback.IsDisposed && _fallback.Visible || !_surface.IsDisposed && _surface.Visible;
                    if(foreground!=IntPtr.Zero && coverAlive && _introFocusAdmission(instance) && intro.TryBeginFocusHandoff()) {
                        intro.CompleteFocusHandoff(_handoffFocus(foreground));
                        focused=_introFlashInputFocused();
                    }
                }
                bool waitingForRoot=!_presentationPolicy.NonActivating && !focused
                    && (!intro.FocusHandoffAttempted || !intro.FocusRootVerified);
                if(!_introFocusAdmission(instance) || waitingForRoot) {
                    if(!focused && intro.FocusHandoffAttempted && !intro.FocusRootVerified && intro.ShouldLogFocusFailure())
                        LogManager.Log("event=stage_intro_focus_restore_failed id="+id+" instance="+instance);
                    _holdWorldInput(true); PresentIntroCover(); return true;
                }
                _surface.HideTransition(); _fallback.Hide();
                intro.ConsumeCloseTail();
                bool nativeFocused=_presentationPolicy.NonActivating || _introFlashInputFocused();
                if(!ExactIntroResume(intro,id,instance,scene,epoch) || !IntroCanPresent || !_introFocusAdmission(instance)
                    || !nativeFocused) {
                    if(!nativeFocused && intro.FocusHandoffAttempted && intro.ShouldLogFocusFailure())
                        LogManager.Log("event=stage_intro_focus_restore_failed id="+id+" instance="+instance);
                    _holdWorldInput(true); return true;
                }
                _holdWorldInput(false);
                intro.Resumed();
                Task.IntroSurfaceReady();
                LogManager.Log("event=stage_intro_surface_ready id="+id+" scene="+scene);
                return true;
            }
            if(_intro.SurfaceReady || _intro.Presented) {
                _surface.SuppressTransition(); _fallback.Hide(); _holdWorldInput(false); return true;
            }
            if(_intro.HasActivation && _currentScene(_intro.Scene) && _intro.TryActivate(_presentIntroComic)) {
                // New opaque endpoint is above the old cover before that cover is withdrawn.
                _surface.SuppressTransition(); _fallback.Hide(); _holdWorldInput(false);
                LogManager.Log("event=stage_intro_comic_presented id="+_intro.Id+" instance="+_intro.Instance);
                return true;
            }
            _holdWorldInput(true); PresentIntroCover(); return true;
        }
        private void TryRetireIntroUnderCover()
        {
            if(_intro==null || _intro.TimelineRetired || _latest?.Value<string>("phase")!="reveal"
                || !_covered || !_surface.Visible || !IntroCanPresent || !_currentScene(_intro.Scene)
                || !_scenePresented(_intro.Scene)) return;
            if(Task.RetireIntroUnderCover()) {
                _intro.TimelineRetired=true;
                LogManager.Log("event=stage_intro_timeline_retired_under_cover id="+_intro.Id);
            }
        }
    }
}
