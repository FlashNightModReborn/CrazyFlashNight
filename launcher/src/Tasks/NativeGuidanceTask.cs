using System;
using System.Collections.Generic;
using System.Drawing;
using System.Globalization;
using System.Linq;
using System.Threading;
using CF7Launcher.Guardian.Hud.Guidance;
using Newtonsoft.Json;
using Newtonsoft.Json.Linq;

namespace CF7Launcher.Tasks
{
    public sealed class NativeGuidanceTask
    {
        public const string TaskKey = "native_guidance";
        private readonly NativeGuidanceWidget _widget;
        private readonly Action<Action> _dispatch;
        private readonly Func<string,bool> _send;
        private readonly Func<bool> _inputAllowed;
        private long _epoch, _maxSequence;
        private string _request, _scene, _guide;
        private int _revision;
        private float _opacity;
        private int _helpAttempts;
        private HelpPresentation _help;
        private IReadOnlyDictionary<string,string> _latestKeys;
        internal Action<string,Action<Bitmap>> LoadImage;
        internal Action<HelpPresentation,Action<bool>> OpenHelp;
        internal Action<string> CloseHelp;
        internal Action HelpUnavailable;
        internal Action<string> HelpReminder;
        internal Func<bool> CanOpenHelp = () => true;
        internal Func<bool> AutomaticHelpEnabled = () => true;
        internal sealed class HelpPresentation
        {
            internal string RequestId, SceneId, GuideId;
            internal readonly string PanelInstanceId = "u8-help-" + Guid.NewGuid().ToString("N");
            internal IReadOnlyDictionary<string,string> Keys;
            internal Func<bool> IsCurrent;
        }
        internal NativeGuidanceTask(NativeGuidanceWidget widget, Action<Action> dispatch, Func<string,bool> send, Func<bool> inputAllowed=null)
        {
            _widget=widget; _dispatch=dispatch; _send=send; _inputAllowed=inputAllowed ?? (()=>true);
            widget.CloseRequested=Close;
            widget.ImageRequested=Load;
        }
        public string Handle(JObject message)
        {
            var payload = message?["payload"] as JObject;
            if (payload == null) return null;
            var frozen = (JObject)payload.DeepClone();
            long epoch = Interlocked.Read(ref _epoch);
            _dispatch(()=> { if(epoch==Interlocked.Read(ref _epoch)) Adopt(frozen); });
            return null;
        }
        private static bool Exact(JObject p, params string[] fields) => p.Count==fields.Length && fields.All(f=>p.ContainsKey(f));
        private static bool Text(JObject p,string key,int max,out string value)
        {
            value = p[key]?.Type==JTokenType.String ? p.Value<string>(key) : null;
            return !string.IsNullOrWhiteSpace(value) && value.Length<=max && value.All(c=>!char.IsControl(c));
        }
        private static bool Positive(JToken t,out int value)
        {
            value=0;
            return t?.Type==JTokenType.Integer && int.TryParse(t.ToString(),out value) && value>0;
        }
        private void Adopt(JObject p)
        {
            if (!Positive(p["version"],out int version) || version!=1 || p["op"]?.Type!=JTokenType.String
                || !Text(p,"requestId",32,out string rid) || !rid.StartsWith("ng:",StringComparison.Ordinal)
                || !long.TryParse(rid.Substring(3),NumberStyles.None,CultureInfo.InvariantCulture,out long seq)
                || seq<=0 || seq>9007199254740991L || rid!="ng:"+seq.ToString(CultureInfo.InvariantCulture)
                || !Text(p,"sceneId",128,out string scene)) return;
            if (p.Value<string>("op")=="hide")
            {
                if (Exact(p,"version","op","requestId","sceneId") && rid==_request && scene==_scene) Retire();
                return;
            }
            if (p.Value<string>("op")!="show" || !Exact(p,"version","op","requestId","sceneId","revision","guideId","opacity","keys")
                || !Positive(p["revision"],out int rev) || !Text(p,"guideId",32,out string guide) || !_widget.KnowsGuide(guide)
                || p["opacity"]?.Type is not (JTokenType.Float or JTokenType.Integer) || p["keys"] is not JObject bindings
                || !Exact(bindings,GuidanceCatalog.KeyNames)) return;
            if (!double.TryParse(p["opacity"].ToString(Formatting.None),NumberStyles.Float,CultureInfo.InvariantCulture,out double opacity)
                || !double.IsFinite(opacity) || opacity<0 || opacity>1 || seq<_maxSequence) return;
            var keys = new Dictionary<string,string>();
            foreach(string key in GuidanceCatalog.KeyNames) { if(!Text(bindings,key,24,out string val))return; keys.Add(key,val); }
            if(seq==_maxSequence && (rid!=_request || scene!=_scene || guide!=_guide || rev<=_revision)) return;
            if (rid != _request) Retire();
            _maxSequence=seq; _request=rid; _scene=scene; _guide=guide; _revision=rev; _opacity=(float)opacity; _latestKeys=keys;
            if (_widget.UsesWebHelp(guide))
            {
                _widget.Clear();
                TryPresentHelp(keys);
            }
            else _widget.Show(rid,scene,rev,guide,(float)opacity,keys);
        }
        private void TryPresentHelp(IReadOnlyDictionary<string,string> keys)
        {
            if (!AutomaticHelpEnabled())
            {
                // A preference change retires our existing popup. Fresh triggers
                // wait for settlement/scene admission before showing one notice.
                if (_help == null)
                {
                    if (_opacity <= 0 || !CanOpenHelp()) return;
                    HelpReminder?.Invoke(_widget.GuideTitle(_guide));
                }
                SendClose(); Retire(); return;
            }
            if (OpenHelp == null || _help != null || _opacity <= 0 || _helpAttempts >= 3 || !CanOpenHelp()) return;
            long epoch = Interlocked.Read(ref _epoch);
            var presentation = new HelpPresentation { RequestId=_request, SceneId=_scene, GuideId=_guide,
                Keys=new System.Collections.ObjectModel.ReadOnlyDictionary<string,string>(new Dictionary<string,string>(keys)) };
            presentation.IsCurrent = () => epoch == Interlocked.Read(ref _epoch) && _help == presentation
                && _request == presentation.RequestId && _scene == presentation.SceneId && _opacity > 0
                && AutomaticHelpEnabled() && CanOpenHelp();
            _help = presentation; _helpAttempts++;
            try
            {
                OpenHelp(presentation, accepted => _dispatch(() => HelpOpenCompleted(presentation, accepted)));
            }
            catch { HelpOpenCompleted(presentation, false); }
        }
        private void HelpOpenCompleted(HelpPresentation presentation, bool accepted)
        {
            if (accepted || _help != presentation) return;
            _help = null;
            // A newly admitted business panel revoked this optional queued open.
            // Policy deferral is not a failed presentation attempt.
            if (!CanOpenHelp()) { _helpAttempts--; return; }
            if (_helpAttempts == 3) HelpUnavailable?.Invoke();
        }
        internal void NotifyHelpAvailabilityChanged()
        {
            long epoch = Interlocked.Read(ref _epoch);
            _dispatch(() => {
                if (epoch == Interlocked.Read(ref _epoch) && _request != null && _widget.UsesWebHelp(_guide))
                    TryPresentHelp(_latestKeys);
            });
        }
        internal void NotifyHelpClosed(string panelName, string panelInstanceId)
        {
            if (panelName == "help" && _help != null && _help.PanelInstanceId == panelInstanceId)
            {
                SendClose(); Retire(false);
            }
            else if (_request != null && _widget.UsesWebHelp(_guide)) TryPresentHelp(_latestKeys);
        }
        private void Close(string rid,string scene,int revision)
        {
            if(rid!=_request || scene!=_scene || revision!=_revision || !_inputAllowed())return;
            SendClose(); Retire();
        }
        private void SendClose()
        {
            var wire = new JObject { ["task"]="cmd",["action"]="nativeGuidanceAction",["requestId"]=_request,["sceneId"]=_scene,["revision"]=_revision,["verb"]="close" };
            // Read-only intent; AS2 keeps the trigger and scene authority. Retire once, never advance a task.
            _send(wire.ToString(Formatting.None)+"\0");
        }
        private void Retire(bool closeHelp=true)
        {
            var help = _help; _help=null;
            _request=_scene=_guide=null; _revision=0; _opacity=0; _helpAttempts=0; _latestKeys=null; _widget.Clear();
            if (closeHelp && help != null) CloseHelp?.Invoke(help.PanelInstanceId);
        }
        private void Load(string path,int imageEpoch)
        {
            if(LoadImage==null)return;
            string rid=_request, scene=_scene; long epoch=Interlocked.Read(ref _epoch);
            LoadImage(path, bitmap => {
                if(bitmap==null)return;
                try { _dispatch(()=> { using(bitmap) { if(epoch==Interlocked.Read(ref _epoch)) _widget.SetImage(rid,scene,imageEpoch,bitmap); } }); }
                catch { bitmap.Dispose(); }
            });
        }
        public void HandleTransportDisconnected()
        {
            Interlocked.Increment(ref _epoch);
            _dispatch(()=>{ _maxSequence=0; Retire(); });
        }
    }
}
