using System;
using Newtonsoft.Json.Linq;

namespace CF7Launcher.Guardian
{
    // Only presentation ownership. Narrative completion and simulation permission stay in AS2.
    internal sealed class IntroPresentationHandoff
    {
        internal readonly string Id, RequestId;
        internal readonly long Scene, Epoch;
        private volatile string _state;
        internal string State { get => _state; private set => _state=value; }
        internal string Instance { get; private set; }
        internal volatile bool TimelineRetired;
        internal bool Presented, NativeClosed, SurfaceReady;
        internal bool Closing { get; private set; }
        internal bool FocusHandoffAttempted { get; private set; }
        internal bool FocusRootVerified { get; private set; }
        private bool _foregroundAdmitted, _focusFailureLogged;
        private Action _activation, _closeTail;
        private JObject _comic;
        internal bool CoverRequired => !Presented && !SurfaceReady;
        internal bool HasActivation => _activation != null;
        internal bool HasPresentationForeground(bool curtainOwnsForeground,Func<string,bool> endpointOwnsForeground)
            => curtainOwnsForeground || !string.IsNullOrEmpty(Instance) && endpointOwnsForeground(Instance);
        internal IntroPresentationHandoff(JObject p,long epoch)
        { Id=p.Value<string>("introId"); RequestId=p.Value<string>("requestId"); Scene=p.Value<long>("targetScene"); Epoch=epoch; State=p.Value<string>("introState"); }
        internal bool Matches(JObject p,long epoch) => p?.Value<long?>("version")==3 && Epoch==epoch
            && Id==p.Value<string>("introId") && RequestId==p.Value<string>("requestId") && Scene==p.Value<long>("targetScene");
        internal void Observe(string state,bool retired)
        {
            if(State=="failed" && state=="opening") {
                Instance=null; Presented=false; NativeClosed=false; SurfaceReady=false; Closing=false; _activation=null; _comic=null;
            }
            State=state; TimelineRetired|=retired;
            if(state=="failed") { Presented=false; SurfaceReady=false; _activation=null; }
        }
        internal void ObserveForegroundAdmission(bool admitted)
        {
            if(!admitted) { _foregroundAdmitted=false; return; }
            if(_foregroundAdmitted)return;
            _foregroundAdmitted=true; FocusHandoffAttempted=false; FocusRootVerified=false; _focusFailureLogged=false;
        }
        internal bool TryBeginFocusHandoff()
        {
            if(!_foregroundAdmitted || FocusHandoffAttempted)return false;
            FocusHandoffAttempted=true; return true;
        }
        internal void CompleteFocusHandoff(bool rootVerified) => FocusRootVerified=rootVerified;
        internal bool ShouldLogFocusFailure()
        {
            if(_focusFailureLogged)return false;
            _focusFailureLogged=true; return true;
        }
        // The UI already granted covered retirement before AS2 can send open. Its
        // next projection may still be queued behind that open on the Host UI loop.
        private bool MatchesComic(JObject data) => data?.Value<int?>("v")==2
            && data.Value<string>("introId")==Id
            && Tasks.BookComicTask.BuildOpenData("book_chapter",data.ToString())!=null
            && (_comic==null || JToken.DeepEquals(_comic,data));
        internal bool Admits(JObject data) => TimelineRetired && State is "loading" or "opening"
            && MatchesComic(data);
        internal bool QueueActivation(JObject data,string instance,Action activation)
        {
            if(!TimelineRetired || State is not ("loading" or "opening" or "narrative") || SurfaceReady || Closing
                || !MatchesComic(data)
                || string.IsNullOrEmpty(instance) || activation==null || Instance!=null && Instance!=instance || _activation!=null) return false;
            _comic=(JObject)data.DeepClone(); Instance=instance; _activation=activation; return true;
        }
        internal bool TryActivate(Func<string,bool> present)
        {
            if(_activation==null || State is not ("opening" or "narrative") || Closing || !present(Instance)) return false;
            var activate=_activation; _activation=null; Presented=true; activate(); return true;
        }
        internal bool BeginClose(string instance)
        {
            if(Instance!=instance || string.IsNullOrEmpty(instance) || SurfaceReady) return false;
            Closing=true; Presented=false; _activation=null; return true;
        }
        internal void BindClosing(JObject data,string instance)
        {
            if(MatchesComic(data) && !string.IsNullOrEmpty(instance) && (Instance==null || Instance==instance)) {
                _comic=(JObject)data.DeepClone(); Instance=instance;
            }
        }
        internal bool Closed(string instance)
        { if(!Closing || Instance!=instance) return false; NativeClosed=true; return true; }
        internal bool CanResume(bool exactScene,bool freshFrame,bool admitted) => Closing && NativeClosed && !SurfaceReady
            && State is "narrative" or "resume" && exactScene && freshFrame && admitted;
        internal bool DeferTail(string instance,Action tail)
        { if(!Closing || SurfaceReady || Instance!=instance || tail==null)return false; _closeTail+=tail; return true; }
        internal void ConsumeCloseTail()
        { var tail=_closeTail; _closeTail=null; tail?.Invoke(); }
        internal void Resumed() => SurfaceReady=true;
        internal void FinishFailedClose()
        { if(State!="failed" || !NativeClosed)return; ConsumeCloseTail(); }
        internal void Retire()
        { _activation=null; ConsumeCloseTail(); }
    }
}
