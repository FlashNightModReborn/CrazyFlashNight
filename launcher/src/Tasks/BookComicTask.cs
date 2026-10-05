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
            public bool Retired, Finishing;
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
            if(source!="book_chapter"||!Exact(d,"v","presentationId","slot","sceneId","pageId")||!Version(d["v"])||!Regex.IsMatch(Text(d["presentationId"])??"","^bookcomic:[1-9][0-9]{0,14}$")||!Safe(Text(d["slot"]))||!Safe(Text(d["sceneId"]))||string.IsNullOrEmpty(Text(d["slot"]))||string.IsNullOrEmpty(Text(d["sceneId"]))||(Text(d["pageId"])!="prologue"&&Text(d["pageId"])!="boss"))return null;
            return d;
        }
        public bool Reserve(JObject data){
            lock(gate){
                if(disposed||!pending.IsReady()||retired.Count>=4096||retired.Contains(Key(data))||current!=null&&!current.Retired)return false;
                current=new Session{
                    Data=(JObject)data.DeepClone()
                }
                ;
                return true;
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
            lock(gate)return current!=null&&!current.Retired&&Tuple(d,current.Data)&&!retired.Contains(Key(d));
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
                if(disposed||s==null||s.Retired||Text(msg?["panel"])!="book-comic"||Text(msg?["domain"])!="book-comic"||Text(msg?["panelInstanceId"])!=s.Instance||!Exact(d,"v","presentationId","slot","sceneId","pageId")||!Version(d["v"])||!Tuple(d,s.Data))return;
                if(cmd!="prepared"&&cmd!="continue"&&cmd!="skip"&&cmd!="failed")return;
                if(s.Finishing)return;
                var call=Text(msg["callId"]);
                if(!Safe(call)||string.IsNullOrEmpty(call)||pending.IsKnownWebCallId(call))return;
                Send(s,cmd=="prepared"?"prepared":"finish",cmd,call);
            }
        }
        void Send(Session s,string operation,string reason,string webCall){
            int fid;
            var request=new Request{
                Session=s,Operation=operation,Reason=reason
            }
            ;
            if(!pending.TryBegin(webCall,request,out fid))return;
            if(operation=="finish")s.Finishing=true;
            var m=(JObject)s.Data.DeepClone();
            m["panelInstanceId"]=s.Instance??"";
            if(operation=="finish")m["reason"]=reason;
            m["task"]="cmd";
            m["action"]=operation=="prepared"?"bookComicPrepared":"bookComicFinish";
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
                        if(current!=null&&Tuple(current.Data,m))Retire(current);
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
                bool prepared=valid&&m.Value<bool>("success")&&Text(m["phase"])=="presenting"&&c.Context.Operation=="prepared";
                if(!s.Retired&&ReferenceEquals(current,s)){
                    if(terminal)Retire(s);
                    else{
                        s.Finishing=false;
                        Post(new JObject{
                            ["type"]="panel_resp",["panel"]="book-comic",["domain"]="book-comic",["panelInstanceId"]=s.Instance,["presentationId"]=s.Data["presentationId"],["callId"]=c.WebCallId,["cmd"]=c.Context.Reason,["success"]=prepared,["error"]=prepared?"":valid?Text(m["error"]):"malformed_response"
                        }
                        );
                    }
                }
            }
            respond?.Invoke(null);
        }
        void Retire(Session s){
            s.Retired=true;
            retired.Add(Key(s.Data));
            var instance=s.Instance;
            if(instance!=null)Dispatch(()=>close?.Invoke(instance));
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
                if(current!=null&&!current.Retired)Retire(current);
                pending.Clear();
            }
        }
        void Ended(PanelPendingCall<Request> c,PanelPendingCallEndReason r){
            lock(gate){
                var s=c.Context.Session;
                if(s.Retired||!ReferenceEquals(current,s)||r==PanelPendingCallEndReason.Cleared)return;
                s.Finishing=false;
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
                pending.Dispose();
            }
        }
    }
}
