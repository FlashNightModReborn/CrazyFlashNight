using System;
using System.Collections.Generic;
using System.Linq;
using System.Text.RegularExpressions;
using Newtonsoft.Json;
using Newtonsoft.Json.Linq;
using CF7Launcher.Bus;
namespace CF7Launcher.Tasks {
    public sealed class BookComicTask : IDisposable {
        sealed class Session {
            public JObject Data;
            public string Instance;
            public bool Retired, Finishing, DocumentInvalidated;
            public bool AwaitingClose, SuccessorAllowed;
            public JObject Successor;
            public Func<JObject,bool> OpenSuccessor;
        }
        sealed class Request {
            public Session Session;
            public string Operation, Reason;
        }
        readonly object gate=new object();
        readonly HashSet<string> retired=new HashSet<string>(StringComparer.Ordinal);
        readonly PanelPendingCallTracker<Request> pending;
        Session current;
        Action<string> post,close;
        Action<Action> invoke;
        bool disposed;
        internal Func<JObject,bool> IntroAdmission;
        internal Action<JObject,string,Action> IntroPrepared;
        internal Action<JObject,string> IntroClosing;
        public BookComicTask(XmlSocketServer socket):this(()=>socket!=null&&socket.IsClientReady,text=>socket!=null&&socket.TrySend(text)){
        }
        public BookComicTask(Func<bool> ready,Func<string,bool> send,int timeoutMs=10000){
            pending=new PanelPendingCallTracker<Request>(ready,send,timeoutMs,Ended);
        }
        public void SetPostToWeb(Action<string> p,Action<Action> i,Action<string> c){
            post=p;
            invoke=i;
            close=c;
        }
        static readonly HashSet<string> Pages=new HashSet<string>(StringComparer.Ordinal){"prologue","boss","lee-ambush","lee-breakout","lee-ending-normal","lee-ending-hidden","cf6-s1","cf6-s2","cf6-s3","cf6-s4","cf6-s5","cf6-s6","cf6-s7","cf6-end"};
        static string Text(JToken t)=>t?.Type==JTokenType.String?t.Value<string>():null;
        static bool Exact(JObject o,params string[] k)=>o!=null&&o.Count==k.Length&&k.All(x=>o.Property(x,StringComparison.Ordinal)!=null);
        static bool CallId(JToken t){
            if(t?.Type!=JTokenType.Integer)return false;
            try{
                long n=t.Value<long>();
                return n>=0&&n<=int.MaxValue;
            }
            catch{
                return false;
            }
        }
        static bool Version(JToken t)=>t?.Type==JTokenType.Integer&&t.ToString()=="1";
        static bool Safe(string t)=>t!=null&&t.Length<=160&&!t.Any(char.IsControl);
        static string Key(JObject d)=>string.Join("\n",new[]{
            "presentationId","slot","sceneId","pageId"
        }
        .Select(k=>Text(d?[k])??""));
        static bool Tuple(JObject a,JObject b)=>a!=null&&b!=null&&new[]{
            "presentationId","slot","sceneId","pageId"
        }
        .All(k=>Text(a[k])==Text(b[k]));
        public static JObject BuildOpenData(string source,string json){
            JObject d;
            try{
                d=JObject.Parse(json??"");
            }
            catch(JsonException){
                return null;
            }
            if(source!="book_chapter"||!(Exact(d,"v","presentationId","slot","sceneId","pageId")&&Version(d["v"])
                ||Exact(d,"v","presentationId","slot","sceneId","pageId","introId")&&d["v"]?.Type==JTokenType.Integer&&d.Value<int>("v")==2
                    &&Regex.IsMatch(Text(d["introId"])??"","^intro:[1-9][0-9]{0,14}$"))||!Regex.IsMatch(Text(d["presentationId"])??"","^bookcomic:[1-9][0-9]{0,14}$")||!Safe(Text(d["slot"]))||!Safe(Text(d["sceneId"]))||string.IsNullOrEmpty(Text(d["slot"]))||string.IsNullOrEmpty(Text(d["sceneId"]))||!Pages.Contains(Text(d["pageId"])??""))return null;
            return d;
        }
        public bool Reserve(JObject data){
            if(data?.Value<int?>("v")==2 && IntroAdmission?.Invoke(data)!=true)return false;
            lock(gate){
                if(disposed||!pending.IsReady()||retired.Count>=4096||retired.Contains(Key(data))||current!=null&&(!current.Retired||current.AwaitingClose))return false;
                current=new Session{
                    Data=(JObject)data.DeepClone()
                }
                ;
                return true;
            }
        }
        // The AS2 sequence owns content ordering. An acknowledged successful
        // predecessor may queue one successor until its exact surface closes.
        public bool TryQueueSuccessor(JObject data,string activePanel,string activeInstance,Func<JObject,bool> open){
            lock(gate){
                var s=current;
                if(disposed||!pending.IsReady()||s==null||!s.Retired||!s.AwaitingClose||!s.SuccessorAllowed
                    ||s.Successor!=null||open==null||activePanel!="book-comic"||activeInstance!=s.Instance
                    ||string.IsNullOrEmpty(s.Instance)||data==null
                    ||BuildOpenData("book_chapter",data.ToString(Formatting.None))==null||retired.Contains(Key(data))
                    ||Text(data["presentationId"])==Text(s.Data["presentationId"])
                    ||Text(data["slot"])!=Text(s.Data["slot"])||Text(data["sceneId"])!=Text(s.Data["sceneId"]))return false;
                s.Successor=(JObject)data.DeepClone();s.OpenSuccessor=open;
                return true;
            }
        }
        public void OnPresentationClosed(string instance,bool closed){
            lock(gate){
                var s=current;
                if(s==null||s.Instance!=instance||!s.AwaitingClose)return;
                var next=s.Successor;var open=s.OpenSuccessor;
                s.AwaitingClose=false;s.SuccessorAllowed=false;s.Successor=null;s.OpenSuccessor=null;
                if(next==null)return;
                if(disposed||!closed||!pending.IsReady()||retired.Contains(Key(next))){retired.Add(Key(next));return;}
                // The router rechecks idle admission and then uses its original
                // Reserve/Open/Bind path. No successor can rebind the old instance.
                if(!open(next))retired.Add(Key(next));
            }
        }
        public bool CanOpen(string json){
            JObject d;
            try{
                d=JObject.Parse(json??"");
            }
            catch{
                return false;
            }
            lock(gate)return current!=null&&!current.Retired&&!current.DocumentInvalidated&&Tuple(d,current.Data)&&d.Value<int?>("v")==current.Data.Value<int?>("v")
                &&Text(d["introId"])==Text(current.Data["introId"])&&!retired.Contains(Key(d));
        }
        public bool Bind(string instance,string json){
            lock(gate){
                if(!CanOpen(json)||!Safe(instance)||string.IsNullOrEmpty(instance))return false;
                if(current.Instance!=null&&current.Instance!=instance)return false;
                current.Instance=instance;
                return true;
            }
        }
        public void RejectOpen(JObject data){
            lock(gate){
                if(current!=null&&Tuple(current.Data,data)){
                    current.Retired=true;
                    retired.Add(Key(data));
                }
            }
        }
        public void HandleWebRequest(string cmd,JObject msg){
            lock(gate){
                var s=current;
                var d=msg?["payload"] as JObject;
                if(disposed||s==null||s.Retired||Text(msg?["panel"])!="book-comic"||Text(msg?["domain"])!="book-comic"||Text(msg?["panelInstanceId"])!=s.Instance||(cmd=="cue"?!Exact(d,"v","presentationId","slot","sceneId","pageId","cueIndex"):!Exact(d,"v","presentationId","slot","sceneId","pageId"))||!Version(d["v"])||!Tuple(d,s.Data))return;
                if(cmd!="prepared"&&cmd!="continue"&&cmd!="skip"&&cmd!="failed"&&cmd!="cue")return;
                if(cmd=="cue" && (!CallId(d["cueIndex"])
                    || d.Value<int>("cueIndex")>4
                    || !(Text(d["pageId"])??"").StartsWith("lee-",StringComparison.Ordinal)))return;
                if(s.Finishing||s.DocumentInvalidated)return;
                var call=Text(msg["callId"]);
                if(!Safe(call)||string.IsNullOrEmpty(call)||pending.IsKnownWebCallId(call))return;
                Send(s,cmd=="prepared"?"prepared":cmd=="cue"?"cue":"finish",cmd,call,cmd=="cue"?d.Value<int>("cueIndex"):-1);
            }
        }
        void Send(Session s,string operation,string reason,string webCall,int cueIndex=-1){
            int fid;
            var request=new Request{
                Session=s,Operation=operation,Reason=reason
            }
            ;
            if(!pending.TryBegin(webCall,request,out fid))return;
            if(operation=="finish")s.Finishing=true;
            var m=(JObject)s.Data.DeepClone();
            // Open v2 adds the Host handoff identity; existing business RPCs remain v1.
            m["v"]=1; m.Remove("introId");
            m["panelInstanceId"]=s.Instance??"";
            if(operation=="finish")m["reason"]=reason;
            if(operation=="cue")m["cueIndex"]=cueIndex;
            m["task"]="cmd";
            m["action"]=operation=="prepared"?"bookComicPrepared":operation=="cue"?"bookComicCue":"bookComicFinish";
            m["callId"]=fid;
            pending.Send(fid,m.ToString(Formatting.None)+"\0");
        }
        public void HandleFlashResponse(JObject m,Action<string> respond){
            // AS2 sendTaskToNode wraps business response in payload.
            m = m?["payload"] as JObject ?? m;
            lock(gate){
                if(!Version(m?["v"])||!CallId(m?["callId"])){
                    respond?.Invoke(null);
                    return;
                }
                if(m.Value<int>("callId")==0){
                    if(Text(m["operation"])=="finish"&&m["success"]?.Type==JTokenType.Boolean&&m.Value<bool>("success")&&Text(m["phase"])=="expired"&&Safe(Text(m["presentationId"]))&&Safe(Text(m["slot"]))&&Safe(Text(m["sceneId"]))&&Safe(Text(m["pageId"]))){
                        if(current!=null&&Tuple(current.Data,m)&&!string.IsNullOrEmpty(Text(m["panelInstanceId"]))&&Text(m["panelInstanceId"])!=current.Instance){
                            respond?.Invoke(null);
                            return;
                        }
                        retired.Add(Key(m));
                        if(current!=null&&Tuple(current.Data,m)){
                            if(current.Successor!=null)retired.Add(Key(current.Successor));
                            current.SuccessorAllowed=false;current.AwaitingClose=false;
                            current.Successor=null;current.OpenSuccessor=null;
                            Retire(current);
                        }
                    }
                    respond?.Invoke(null);
                    return;
                }
                PanelPendingCall<Request> c;
                if(!pending.TryComplete(m.Value<int>("callId"),out c)){
                    respond?.Invoke(null);
                    return;
                }
                var s=c.Context.Session;
                bool valid=Tuple(m,s.Data)&&Text(m["panelInstanceId"])==(s.Instance??"")&&Text(m["operation"])==c.Context.Operation&&m["success"]?.Type==JTokenType.Boolean&&m["phase"]?.Type==JTokenType.String&&m["error"]?.Type==JTokenType.String;
                bool terminal=valid&&m.Value<bool>("success")&&(Text(m["phase"])=="finished"||Text(m["phase"])=="expired")&&c.Context.Operation=="finish";
                bool prepared=valid&&m.Value<bool>("success")&&Text(m["phase"])=="presenting"&&(c.Context.Operation=="prepared"||c.Context.Operation=="cue");
                if(!s.Retired&&ReferenceEquals(current,s)){
                    if(terminal){
                        s.SuccessorAllowed=Text(m["phase"])=="finished"
                            &&(c.Context.Reason=="continue"||c.Context.Reason=="skip");
                        Retire(s);
                    }
                    else if(!s.DocumentInvalidated){
                        if(c.Context.Operation!="cue")s.Finishing=false;
                        PostPrepared(s,prepared && c.Context.Operation=="prepared",new JObject{
                            ["type"]="panel_resp",["panel"]="book-comic",["domain"]="book-comic",["panelInstanceId"]=s.Instance,["presentationId"]=s.Data["presentationId"],["callId"]=c.WebCallId,["cmd"]=c.Context.Reason,["success"]=prepared,["error"]=valid?Text(m["error"]):"malformed_response"
                        }
                        );
                    }
                }
            }
            respond?.Invoke(null);
        }
        void PostPrepared(Session s,bool prepared,JObject message){
            if(!prepared || s.Data.Value<int>("v")!=2) { Post(message); return; }
            string json=message.ToString(Formatting.None);
            Dispatch(()=> {
                if(disposed || s.Retired || s.DocumentInvalidated || !ReferenceEquals(current,s))return;
                IntroPrepared?.Invoke((JObject)s.Data.DeepClone(),s.Instance,()=> {
                    lock(gate)if(!disposed && !s.Retired && !s.DocumentInvalidated && ReferenceEquals(current,s))post?.Invoke(json);
                });
            });
        }
        public void OnDocumentInvalidated(){
            lock(gate){
                var s=current;
                if(disposed || s==null || s.Retired || s.Instance==null || s.DocumentInvalidated)return;
                s.DocumentInvalidated=true;
                if(s.Data.Value<int>("v")==2)Dispatch(()=>IntroClosing?.Invoke((JObject)s.Data.DeepClone(),s.Instance));
                Send(s,"finish","failed","document-lost-"+Guid.NewGuid().ToString("N"));
            }
        }
        void Retire(Session s){
            s.Retired=true;
            retired.Add(Key(s.Data));
            var instance=s.Instance;
            s.AwaitingClose=instance!=null&&s.SuccessorAllowed;
            if(instance!=null)Dispatch(()=> {
                if(s.Data.Value<int>("v")==2)IntroClosing?.Invoke((JObject)s.Data.DeepClone(),instance);
                close?.Invoke(instance);
            });
        }
        public void OnHostClosed(string instance){
            lock(gate){
                if(current==null||current.Instance!=instance||current.Retired)return;
                var s=current;
                Send(s,"finish","closed","host-close-"+Guid.NewGuid().ToString("N"));
                s.Retired=true;
                retired.Add(Key(s.Data));
            }
        }
        public void OnDisconnected(){
            lock(gate){
                if(current!=null){
                    if(current.Successor!=null)retired.Add(Key(current.Successor));
                    current.SuccessorAllowed=false;current.AwaitingClose=false;
                    current.Successor=null;current.OpenSuccessor=null;
                }
                if(current!=null&&!current.Retired)Retire(current);
                pending.Clear();
            }
        }
        void Ended(PanelPendingCall<Request> c,PanelPendingCallEndReason r){
            lock(gate){
                var s=c.Context.Session;
                if(s.Retired||!ReferenceEquals(current,s)||r==PanelPendingCallEndReason.Cleared)return;
                if(c.Context.Operation!="cue")s.Finishing=false;
                Post(new JObject{
                    ["type"]="panel_resp",["panel"]="book-comic",["domain"]="book-comic",["panelInstanceId"]=s.Instance,["presentationId"]=s.Data["presentationId"],["callId"]=c.WebCallId,["cmd"]=c.Context.Reason,["success"]=false,["error"]=r==PanelPendingCallEndReason.Timeout?"timeout":"disconnected"
                }
                );
            }
        }
        void Dispatch(Action a){
            if(invoke!=null)invoke(a);
            else a();
        }
        void Post(JObject m){
            var json=m.ToString(Formatting.None);
            Dispatch(()=>{
                if(!disposed)post?.Invoke(json);
            }
            );
        }
        public void Dispose(){
            lock(gate){
                disposed=true;
                if(current!=null){current.Successor=null;current.OpenSuccessor=null;current.AwaitingClose=false;}
                pending.Dispose();
            }
        }
    }
}
