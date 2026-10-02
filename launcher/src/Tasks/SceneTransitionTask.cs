using System;
using System.Globalization;
using System.Linq;
using System.Threading;
using CF7Launcher.Guardian;
using Newtonsoft.Json;
using Newtonsoft.Json.Linq;

namespace CF7Launcher.Tasks
{
    // Closed AS2 projection channel. No panel RPC, save access or navigation authority.
    public sealed class SceneTransitionTask
    {
        public const string TaskKey = "scene_transition";
        private readonly Action<Action> _dispatch;
        private readonly Action<JObject> _present;
        private readonly Action _hide;
        private readonly Func<string, bool> _send;
        private long _epoch, _maxSequence;
        private JObject _current;
        private bool _actionSent, _reportCovered;
        private string _receipt;
        private string _automaticReportAttempt;
        internal bool Connected { get; private set; } = true;
        internal long Epoch => Interlocked.Read(ref _epoch);
        internal SceneTransitionTask(Action<Action> dispatch, Action<JObject> present, Action hide, Func<string, bool> send)
        { _dispatch=dispatch; _present=present; _hide=hide; _send=send; }
        internal JObject Current => _current == null ? null : (JObject)_current.DeepClone();
        private static bool Exact(JObject p, params string[] keys) => p.Count == keys.Length && keys.All(p.ContainsKey);
        private static bool Positive(JToken token, out long value) {
            value=0;
            return token?.Type == JTokenType.Integer && long.TryParse(token.ToString(), out value)
                && value > 0 && value <= 9007199254740991L;
        }
        private static bool Text(JObject p,string key,int limit,out string text) {
            text=p[key]?.Type==JTokenType.String ? p.Value<string>(key) : null;
            return text != null && text.Length<=limit && text.All(c=>!char.IsControl(c) || c=='\n' || c=='\r' || c=='\t');
        }
        private static bool ValidVersion(JObject p) {
            string[] common={"version","requestId","revision","phase","imageId","tip","targetScene","actionPending"};
            if(!Positive(p["version"],out long version)) return false;
            if(version==1) return Exact(p,common);
            if(version!=2 || !Exact(p,common.Concat(new[]{"report","reportVisible","reportHandoff"}).ToArray())
                || p["reportVisible"]?.Type!=JTokenType.Boolean || p["reportHandoff"]?.Type!=JTokenType.Boolean
                || !LootPanelCoordinator.TryNormalizeSettlementReport(p["report"] as JObject,out var report)
                || report.Value<bool?>("rewardStashed")!=true || p.Value<bool>("reportHandoff") && !p.Value<bool>("reportVisible")) return false;
            p["report"]=report;
            return true;
        }
        public string Handle(JObject message) {
            if (message?["payload"] is not JObject payload) return null;
            var copy=(JObject)payload.DeepClone(); long epoch=Interlocked.Read(ref _epoch);
            _dispatch(()=> { if(epoch==Interlocked.Read(ref _epoch)) Adopt(copy); });
            return null;
        }
        private void Adopt(JObject p) {
            if(!ValidVersion(p)
                || !Positive(p["revision"],out long revision) || revision>int.MaxValue
                || !Positive(p["targetScene"],out long scene)
                || !Text(p,"requestId",32,out string rid) || !rid.StartsWith("tr:",StringComparison.Ordinal)
                || !long.TryParse(rid.Substring(3),NumberStyles.None,CultureInfo.InvariantCulture,out long seq)
                || seq<=0 || seq>9007199254740991L || rid!="tr:"+seq.ToString(CultureInfo.InvariantCulture)
                || !Text(p,"phase",16,out string phase) || phase is not ("cover" or "loading" or "reveal" or "error" or "hide")
                || !Text(p,"imageId",32,out string image) || !SceneTransitionCatalog.Assets.ContainsKey(image)
                || !Text(p,"tip",2048,out _) || p["actionPending"]?.Type!=JTokenType.Boolean || seq<_maxSequence) return;
            if(seq==_maxSequence) {
                if(_current==null || rid!=_current.Value<string>("requestId")
                    || image!=_current.Value<string>("imageId") || revision<_current.Value<int>("revision")
                    || p.Value<long>("version")!=_current.Value<long>("version")
                    || !JToken.DeepEquals(p["report"],_current["report"])
                    || _current.Value<bool?>("reportVisible")==false && p.Value<bool?>("reportVisible")==true) return;
                if(revision==_current.Value<int>("revision")) {
                    if(JToken.DeepEquals(p,_current)) { _present((JObject)p.DeepClone()); ResendReceipt(); }
                    return;
                }
                // A stale source cannot regress a revealed/error projection within one identity.
                var before=_current.Value<string>("phase");
                if(before=="error" && phase is not ("error" or "hide")
                    || before=="reveal" && phase is "cover" or "loading") return;
            }
            if(phase=="hide") {
                // Tombstones are accepted even when an earlier show was lost.
                _maxSequence=seq; _current=null; _receipt=null; _actionSent=false; _reportCovered=false; Connected=true; _hide(); return;
            }
            if(seq>_maxSequence) { _receipt=null; _actionSent=false; _reportCovered=false; }
            if(phase=="error" && _current?.Value<string>("phase")!="error") _actionSent=false;
            if(_current?.Value<string>("phase")!=phase || _current?.Value<long>("targetScene")!=scene) _receipt=null;
            if(_current?.Value<bool?>("reportVisible")==true && p.Value<bool?>("reportVisible")==false
                || _current?.Value<bool?>("reportHandoff")==true && p.Value<bool?>("reportHandoff")==false) _actionSent=false;
            _maxSequence=seq; _current=p; Connected=true;
            _actionSent |= p.Value<bool>("actionPending");
            _present((JObject)p.DeepClone());
        }
        internal bool Presented(JObject p) {
            if(!Connected || _current==null || !Exact(p,"type","requestId","revision","generation","kind")
                || !Text(p,"type",40,out string type) || type!="scene_transition_presented"
                || !MatchesWeb(p) || !Text(p,"kind",16,out string kind)) return false;
            string phase=_current.Value<string>("phase");
            bool report=_current.Value<bool?>("reportVisible")==true;
            if(kind=="covered" && (phase is "cover" or "loading" or "error" || phase=="reveal" && report)
                || kind=="revealed" && phase=="reveal" && !report) {
                if(kind=="covered" && report) _reportCovered=true;
                if(kind!="covered" || _receipt!="prepared") _receipt=kind;
                ResendReceipt(); return true;
            }
            return false;
        }
        internal bool MatchesWeb(JObject p) => _current!=null && p["requestId"]?.Type==JTokenType.String
            && p.Value<string>("requestId")==_current.Value<string>("requestId")
            && Positive(p["revision"],out long revision) && revision==_current.Value<int>("revision")
            && p["generation"]?.Type==JTokenType.Integer && long.TryParse(p["generation"].ToString(),out long generation)
            && generation==Epoch;
        // Report intents name the immutable report in this request. Loading/tip revisions
        // can advance in either transport queue; they are not reward authority revisions.
        // Navigation and world-presentation receipts still require the exact revision.
        internal bool MatchesWebAction(JObject p) {
            if(p==null || !Exact(p,"type","requestId","revision","generation","verb")
                || !Text(p,"type",40,out string type) || type!="scene_transition_action"
                || !Text(p,"verb",16,out string verb)) return false;
            if(MatchesWeb(p)) return true;
            return verb is "manageReport" or "closeReport"
                && _current?.Value<long>("version")==2 && _current.Value<bool>("reportVisible")
                && !_current.Value<bool>("reportHandoff") && _current.Value<string>("phase")!="error"
                && p["requestId"]?.Type==JTokenType.String && p.Value<string>("requestId")==_current.Value<string>("requestId")
                && Positive(p["revision"],out long revision) && revision<=_current.Value<int>("revision")
                && p["generation"]?.Type==JTokenType.Integer && long.TryParse(p["generation"].ToString(),out long generation)
                && generation==Epoch;
        }
        private void ResendReceipt() {
            if(_current==null || _receipt==null) return;
            Send("sceneTransitionPresented","kind",_receipt);
        }
        // Native target capture is checked by the controller; this never trusts a page's readiness claim.
        internal void ScenePrepared() {
            if(!Connected || _current?.Value<long>("version")!=2 || _current.Value<string>("phase")!="reveal"
                || _current.Value<bool>("reportVisible")!=true || _receipt=="prepared") return;
            _receipt="prepared"; ResendReceipt();
        }
        internal bool CompleteReportHandoff() {
            if(!Connected || _current?.Value<long>("version")!=2 || _current.Value<string>("phase")!="reveal"
                || !_current.Value<bool>("reportHandoff")) return false;
            _receipt="handoff"; return Send("sceneTransitionPresented","kind","handoff");
        }
        internal static bool TryNormalizeReportPresentation(JObject p,out JObject normalized) {
            normalized=null;
            if(p==null || !Exact(p,"scrollTop","density","rightTab","materialSearch")
                || p["scrollTop"]?.Type!=JTokenType.Integer || !long.TryParse(p["scrollTop"].ToString(),out long scroll)
                || scroll<0 || scroll>1000000
                || !Text(p,"density",16,out string density) || density is not ("compact" or "full")
                || !Text(p,"rightTab",16,out string tab) || tab is not ("rewards" or "materials")
                || !Text(p,"materialSearch",64,out string search) || search.Any(char.IsControl)) return false;
            normalized=new JObject { ["scrollTop"]=scroll,["density"]=density,["rightTab"]=tab,["materialSearch"]=search };
            return true;
        }
        internal bool TryReportPresentation(JObject p,out JObject normalized) {
            normalized=null;
            return Connected && _current?.Value<long>("version")==2 && _current.Value<bool>("reportVisible")
                && _current.Value<string>("phase")!="error"
                && p!=null && Exact(p,"type","requestId","revision","generation","viewState")
                && Text(p,"type",48,out string type) && type=="scene_transition_report_view" && MatchesWeb(p)
                && TryNormalizeReportPresentation(p["viewState"] as JObject,out normalized);
        }
        internal static bool MatchesSettlementReceipt(JObject p,LootPanelCoordinator.Binding binding,
            bool bound,string activePanel,string activeInstance) {
            if(p==null || !Positive(p["version"],out long version) || version is not (1 or 2)
                || version==1 && !Exact(p,"type","version","panelInstanceId","chestSessionId","lootContainerId","containerEpoch","runId")
                || version==2 && (!Exact(p,"type","version","panelInstanceId","chestSessionId","lootContainerId","containerEpoch","runId","viewState")
                    || !TryNormalizeReportPresentation(p["viewState"] as JObject,out _))) return false;
            return p!=null && binding!=null && bound && activePanel=="loot"
                && Text(p,"type",48,out string type) && type=="scene_transition_report_presented"
                && Text(p,"panelInstanceId",128,out string panel) && panel==activeInstance && panel==binding.PanelInstanceId
                && Text(p,"chestSessionId",128,out string chest) && chest==binding.ChestSessionId
                && Text(p,"lootContainerId",128,out string container) && container==binding.LootContainerId
                && Positive(p["containerEpoch"],out long epoch) && epoch==binding.ContainerEpoch
                && Text(p,"runId",128,out string run) && run==binding.SettlementReport?.Value<string>("runId")
                && binding.SourceKind==LootPanelCoordinator.StageSettlementSource
                && binding.SettlementReport?.Value<bool?>("rewardStashed")==true;
        }
        internal void Action(JObject p) {
            if(!Connected || _current==null || _actionSent
                || !Exact(p,"type","requestId","revision","generation","verb")
                || !Text(p,"type",40,out string type) || type!="scene_transition_action" || !MatchesWebAction(p)
                || !Text(p,"verb",16,out string verb)) return;
            bool report= _current.Value<long>("version")==2 && _current.Value<bool>("reportVisible")
                && !_current.Value<bool>("reportHandoff") && _current.Value<string>("phase")!="error";
            if(verb is "closeReport" or "manageReport") {
                if(!report || verb=="manageReport" && !_reportCovered && _receipt!="prepared") return;
                if(verb=="manageReport") {
                    string attempt=_current.Value<string>("requestId")+"/"+_current["report"]?.Value<string>("runId");
                    if(_automaticReportAttempt==attempt) return;
                    _automaticReportAttempt=attempt;
                }
            } else if(_current.Value<string>("phase")!="error" || verb is not ("retry" or "return")) return;
            _actionSent=true; Send("sceneTransitionAction","verb",verb);
        }
        // Called only after the exact Host loot owner has retired through its existing
        // authority/recovery contract. It does not unlock or replay a pending write.
        internal void ReportClosed() {
            if(!Connected || _current?.Value<long>("version")!=2 || !_current.Value<bool>("reportVisible")) return;
            Send("sceneTransitionAction","verb","closeReport");
        }
        private bool Send(string action,string key,string value) {
            var wire=new JObject { ["task"]="cmd",["action"]=action,["requestId"]=_current["requestId"],
                ["revision"]=_current["revision"],[key]=value };
            bool sent=_send(wire.ToString(Formatting.None)+"\0");
            LogManager.Log("event=scene_transition_reply action="+action+" id="+_current.Value<string>("requestId")
                +" revision="+_current.Value<int>("revision")+" "+key+"="+value+" sent="+sent);
            return sent;
        }
        public void HandleTransportDisconnected() {
            long epoch=Interlocked.Increment(ref _epoch);
            _dispatch(()=> { if(epoch==Interlocked.Read(ref _epoch)) {
                Connected=false; _maxSequence=0; _receipt=null; _actionSent=false; _reportCovered=false;
                if(_current!=null) _present((JObject)_current.DeepClone());
            }});
        }
    }
}
