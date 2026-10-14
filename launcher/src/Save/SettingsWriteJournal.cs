using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Text;
using Newtonsoft.Json;
using Newtonsoft.Json.Linq;

namespace CF7Launcher.Save
{
    internal sealed class SettingsSaveContext
    {
        internal readonly string ContextId,OriginNamespaceDigest,Slot,SwfPath;
        internal SettingsSaveContext(string installRoot,string swfPath,string slot)
        {
            if(!SaveSlotKey.TryValidateExisting(slot,out var exactSlot)||slot.Any(char.IsControl))throw new ArgumentException("Invalid settings slot");
            Slot=exactSlot; SwfPath=Path.GetFullPath(Path.IsPathRooted(swfPath) ? swfPath : Path.Combine(installRoot,swfPath));
            OriginNamespaceDigest=SettingsCanonical.Digest("cf7.settings.origin.v1|"+SwfPath.Replace('\\','/').ToUpperInvariant());
            ContextId="ctx."+SettingsCanonical.Digest("cf7.settings.context.v1|"+Path.GetFullPath(installRoot).ToUpperInvariant()
                +"|"+OriginNamespaceDigest+"|"+slot);
        }
    }
    internal sealed class SettingsWriteIntent
    {
        internal readonly SettingsSaveContext Context;
        internal readonly string Owner,Epoch,Operation,BaseState,Digest,MutationDigest;
        internal readonly long BaseRevision;
        internal SettingsWriteIntent(SettingsSaveContext context,string owner,string epoch,string operation,string baseState,long baseRevision,string digest)
        {
            Context=context;Owner=owner;Epoch=epoch;Operation=operation;BaseState=baseState;BaseRevision=baseRevision;Digest=digest;
            MutationDigest=SettingsCanonical.MutationDigest(context.ContextId,owner,epoch,operation,baseState,baseRevision,digest);
        }
    }
    /// <summary>One exclusive Host writer; callers perform these disk operations outside Task/UI state locks.</summary>
    internal sealed class SettingsWriteJournal : IDisposable
    {
        private readonly string _directory;
        private readonly FileStream _ownership;
        private readonly object _gate=new();
        private readonly HashSet<string> _contexts=new(StringComparer.Ordinal);
        private readonly Action<string,string> _write;
        private string _indexStamp;
        private bool _disposed;
        internal SettingsWriteJournal(string directory,Action<string,string> writer=null)
        {
            _directory=Path.GetFullPath(directory); Directory.CreateDirectory(_directory);
            _ownership=new FileStream(Path.Combine(_directory,"writer.lock"),FileMode.OpenOrCreate,FileAccess.ReadWrite,FileShare.None);
            _write=writer ?? ((path,text)=>DurableFileWriter.WriteAllText(path,text,new UTF8Encoding(false)));
            try {
                string index=Path.Combine(_directory,"contexts.json");
                if(File.Exists(index)) {
                    var value=ReadBounded(index,64*1024,out var indexImage);
                    if(value["schema"]?.Type!=JTokenType.Integer || (long)value["schema"]!=1 || value.Count!=2
                        || value["contexts"] is not JArray entries)throw new InvalidDataException("Settings journal index invalid");
                    foreach(var entry in entries) {
                        if(entry.Type!=JTokenType.String || !SettingsCanonical.IsOpaque((string)entry) || !_contexts.Add((string)entry))
                            throw new InvalidDataException("Settings journal context index invalid");
                    }
                    _indexStamp=SettingsCanonical.Digest(indexImage);
                } else {
                    if(Directory.EnumerateFileSystemEntries(_directory).Any(p=>Path.GetFileName(p)!="writer.lock"))throw new InvalidDataException("Settings journal index missing beside existing evidence");
                    PersistIndex();
                }
            } catch { _ownership.Dispose(); throw; }
        }
        private string PathFor(string context)=>Path.Combine(_directory,SettingsCanonical.Digest(context)+".json");
        private void PersistIndex()
        {
            string text=new JObject { ["schema"]=1,["contexts"]=new JArray(_contexts.OrderBy(x=>x,StringComparer.Ordinal)) }.ToString(Formatting.None);
            _write(Path.Combine(_directory,"contexts.json"),text); _indexStamp=SettingsCanonical.Digest(text);
        }
        private void AssertIndexCurrent()
        {
            if(_indexStamp!=SettingsCanonical.Digest(File.ReadAllText(Path.Combine(_directory,"contexts.json"),new UTF8Encoding(false,true))))
                throw new InvalidDataException("Settings context index changed outside its writer");
        }
        private static JObject ReadBounded(string path,int limit)
            =>ReadBounded(path,limit,out _);
        private static JObject ReadBounded(string path,int limit,out string image)
        {
            var bytes=File.ReadAllBytes(path); if(bytes.Length>limit)throw new InvalidDataException("Settings metadata exceeds bound");
            image=new UTF8Encoding(false,true).GetString(bytes);
            using var reader=new JsonTextReader(new StringReader(image)) { MaxDepth=12,DateParseHandling=DateParseHandling.None };
            var value=JObject.Load(reader,new JsonLoadSettings { DuplicatePropertyNameHandling=DuplicatePropertyNameHandling.Error });
            if(reader.Read())throw new InvalidDataException("Trailing settings metadata"); return value;
        }
        private static readonly string[] Fields={"schema","recordId","contextId","saveOwnerId","originNamespaceDigest","slot",
            "sourceAuthorityEpoch","operationToken","baseStateToken","baseRevision","targetStateToken","targetRevision","settingsDigest",
            "originMutationRequestDigest","digestSchema","rootOperationState","currentAttempt","sequence","createdUtc","lastObservation","confirmation"};
        private static void Validate(JObject value,string context)
        {
            if(value==null || value.Count!=Fields.Length || Fields.Any(f=>value[f]==null) || (string)value["contextId"]!=context
                || !SettingsCanonical.Integer(value["schema"],1,1,false,out _) || !SettingsCanonical.Integer(value["digestSchema"],1,1,false,out _)
                || !SettingsCanonical.Integer(value["sequence"],1,SettingsCanonical.MaxSafeInteger,false,out _)
                || !SettingsCanonical.Integer(value["baseRevision"],0,SettingsCanonical.MaxSafeInteger,false,out _))throw new InvalidDataException("Settings journal record shape invalid");
            foreach(var field in new[] {"recordId","contextId","saveOwnerId","sourceAuthorityEpoch","operationToken","baseStateToken","targetStateToken"})
                if(value[field].Type!=JTokenType.String || !SettingsCanonical.IsOpaque((string)value[field]))throw new InvalidDataException("Settings journal identity invalid");
            foreach(var field in new[] {"originNamespaceDigest","settingsDigest","originMutationRequestDigest"})
                if(value[field].Type!=JTokenType.String || !SettingsCanonical.IsDigest((string)value[field]))throw new InvalidDataException("Settings journal digest invalid");
            if(value["slot"].Type!=JTokenType.String || !SaveSlotKey.IsValidExisting((string)value["slot"])
                || ((string)value["slot"]).Any(char.IsControl))throw new InvalidDataException("Settings journal slot invalid");
            string mutation=SettingsCanonical.MutationDigest(context,(string)value["saveOwnerId"],(string)value["sourceAuthorityEpoch"],
                (string)value["operationToken"],(string)value["baseStateToken"],(long)value["baseRevision"],(string)value["settingsDigest"]);
            if(mutation!=(string)value["originMutationRequestDigest"])throw new InvalidDataException("Settings journal intent digest mismatch");
            if(value["targetRevision"].Type!=JTokenType.Null && !SettingsCanonical.Integer(value["targetRevision"],0,SettingsCanonical.MaxSafeInteger,false,out _))
                throw new InvalidDataException("Settings journal target revision invalid");
            if(!new[] {"Prepared","Unknown","AppliedUnconfirmed","Confirmed","NotApplied","NotSent"}.Contains((string)value["rootOperationState"]))
                throw new InvalidDataException("Settings journal root state invalid");
            if(value["createdUtc"].Type!=JTokenType.String || !DateTimeOffset.TryParse((string)value["createdUtc"],out _))throw new InvalidDataException("Settings journal creation timestamp invalid");
            if(value["lastObservation"].Type is not (JTokenType.Null or JTokenType.Object))throw new InvalidDataException("Settings journal observation invalid");
            if(!new[] {"none","flush_true","cold_read_exact"}.Contains((string)value["confirmation"]))throw new InvalidDataException("Settings journal confirmation invalid");
            if(value["currentAttempt"] is not JObject attempt || attempt.Count!=7
                || !new[] {"saveAttemptId","command","dispatchAuthorityEpoch","expectedStateToken","expectedRevision","dispatchPhase","attemptOutcome"}.All(f=>attempt[f]!=null)
                || !SettingsCanonical.IsOpaque((string)attempt["saveAttemptId"]) || !SettingsCanonical.IsOpaque((string)attempt["dispatchAuthorityEpoch"])
                || !SettingsCanonical.IsOpaque((string)attempt["expectedStateToken"])
                || !SettingsCanonical.Integer(attempt["expectedRevision"],0,SettingsCanonical.MaxSafeInteger,false,out _)
                || !new[] {"apply","save"}.Contains((string)attempt["command"])
                || !new[] {"Prepared","Dispatching","Returned"}.Contains((string)attempt["dispatchPhase"])
                || !new[] {"none","NotSent","Unknown","ReturnedUnconfirmed","Confirmed"}.Contains((string)attempt["attemptOutcome"]))
                throw new InvalidDataException("Settings journal attempt invalid");
            foreach(var field in new[] {"saveAttemptId","command","dispatchAuthorityEpoch","expectedStateToken","dispatchPhase","attemptOutcome"})
                if(attempt[field].Type!=JTokenType.String)throw new InvalidDataException("Settings journal attempt field type invalid");
            if((string)value["rootOperationState"]=="Confirmed" && (value["targetRevision"].Type==JTokenType.Null || (string)value["confirmation"]=="none"))
                throw new InvalidDataException("Settings journal confirmed target incomplete");
        }
        internal JObject Read(string context)
        {
            lock(_gate) {
                if(_disposed)throw new ObjectDisposedException(nameof(SettingsWriteJournal));
                AssertIndexCurrent();
                if(!_contexts.Contains(context))return null;
                var value=ReadBounded(PathFor(context),4096); Validate(value,context); return value;
            }
        }
        private void Persist(JObject value)
        {
            string context=(string)value["contextId"]; Validate(value,context);
            string text=value.ToString(Formatting.None); if(Encoding.UTF8.GetByteCount(text)>4096)throw new InvalidDataException("Settings journal record exceeds 4 KiB");
            _write(PathFor(context),text);
        }
        private static bool Terminal(JObject value)=>new[] {"Confirmed","NotApplied","NotSent"}.Contains((string)value["rootOperationState"]);
        private static JObject Attempt(string id,string command,string epoch,string state,long revision)=>new() {
            ["saveAttemptId"]=id,["command"]=command,["dispatchAuthorityEpoch"]=epoch,["expectedStateToken"]=state,
            ["expectedRevision"]=revision,["dispatchPhase"]="Prepared",["attemptOutcome"]="none" };
        internal JObject Prepare(SettingsWriteIntent intent,string attemptId)
        {
            lock(_gate) {
                var prior=Read(intent.Context.ContextId);
                if(prior!=null) {
                    if(!Terminal(prior))throw new InvalidOperationException("Settings operation unresolved");
                    _write(Path.Combine(_directory,SettingsCanonical.Digest(intent.Context.ContextId)+".history."+(string)prior["recordId"]+".json"),prior.ToString(Formatting.None));
                }
                if(_contexts.Add(intent.Context.ContextId))PersistIndex();
                var value=new JObject {
                    ["schema"]=1,["recordId"]=Guid.NewGuid().ToString("N"),["contextId"]=intent.Context.ContextId,["saveOwnerId"]=intent.Owner,
                    ["originNamespaceDigest"]=intent.Context.OriginNamespaceDigest,["slot"]=intent.Context.Slot,["sourceAuthorityEpoch"]=intent.Epoch,
                    ["operationToken"]=intent.Operation,["baseStateToken"]=intent.BaseState,["baseRevision"]=intent.BaseRevision,
                    ["targetStateToken"]=intent.Operation,["targetRevision"]=JValue.CreateNull(),["settingsDigest"]=intent.Digest,
                    ["originMutationRequestDigest"]=intent.MutationDigest,["digestSchema"]=1,["rootOperationState"]="Prepared",
                    ["currentAttempt"]=Attempt(attemptId,"apply",intent.Epoch,intent.BaseState,intent.BaseRevision),["sequence"]=1,
                    ["createdUtc"]=DateTimeOffset.UtcNow.ToString("O"),["lastObservation"]=JValue.CreateNull(),["confirmation"]="none" };
                Persist(value); return (JObject)value.DeepClone();
            }
        }
        internal JObject ChangeAttempt(string context,string operation,string attemptId,long expectedSequence,Action<JObject> change)
        {
            lock(_gate) {
                var value=Read(context);
                if(value==null || (string)value["operationToken"]!=operation || (string)value["currentAttempt"]?["saveAttemptId"]!=attemptId
                    || (long)value["sequence"]!=expectedSequence)throw new InvalidOperationException("Settings journal compare failed");
                var original=(JObject)value.DeepClone(); change(value);
                foreach(var field in new[] {"recordId","contextId","saveOwnerId","originNamespaceDigest","slot","sourceAuthorityEpoch","operationToken",
                    "baseStateToken","baseRevision","targetStateToken","settingsDigest","originMutationRequestDigest","digestSchema","createdUtc"})
                    if(!JToken.DeepEquals(original[field],value[field]))throw new InvalidDataException("Immutable settings intent changed");
                if((string)original["rootOperationState"]=="Confirmed" && (string)value["rootOperationState"]!="Confirmed")
                    throw new InvalidOperationException("Confirmed settings cannot be downgraded");
                if((string)original["rootOperationState"]=="Confirmed" &&
                    (!JToken.DeepEquals(original["targetRevision"],value["targetRevision"])
                    || !JToken.DeepEquals(original["confirmation"],value["confirmation"])
                    || !JToken.DeepEquals(original["currentAttempt"],value["currentAttempt"])))
                    throw new InvalidOperationException("Confirmed settings receipt cannot be altered");
                var originalAttempt=(JObject)original["currentAttempt"]; var nextAttempt=(JObject)value["currentAttempt"];
                if(original["targetRevision"].Type!=JTokenType.Null && !JToken.DeepEquals(original["targetRevision"],value["targetRevision"]))
                    throw new InvalidDataException("Settings target revision changed");
                if((string)original["rootOperationState"] is "NotApplied" or "NotSent"
                    && !JToken.DeepEquals(original["rootOperationState"],value["rootOperationState"]))
                    throw new InvalidOperationException("Terminal settings operation changed");
                if((string)original["rootOperationState"]=="AppliedUnconfirmed" && (string)value["rootOperationState"] is "Unknown" or "NotApplied" or "NotSent" or "Prepared")
                    throw new InvalidOperationException("Known settings apply cannot be downgraded");
                if((string)originalAttempt["saveAttemptId"]==(string)nextAttempt["saveAttemptId"]) {
                    foreach(var field in new[] {"command","dispatchAuthorityEpoch","expectedStateToken","expectedRevision"})
                        if(!JToken.DeepEquals(originalAttempt[field],nextAttempt[field]))throw new InvalidDataException("Settings attempt identity changed");
                    if((string)originalAttempt["dispatchPhase"]=="Returned" && (string)nextAttempt["dispatchPhase"]!="Returned"
                        || (string)originalAttempt["dispatchPhase"]=="Dispatching" && (string)nextAttempt["dispatchPhase"]=="Prepared")
                        throw new InvalidOperationException("Settings attempt dispatch cannot regress");
                }
                else _write(Path.Combine(_directory,SettingsCanonical.Digest(context)+".attempt."+(string)original["recordId"]+"."
                    +expectedSequence.ToString(System.Globalization.CultureInfo.InvariantCulture)+".json"),original.ToString(Formatting.None));
                value["sequence"]=checked(expectedSequence+1); Persist(value); return (JObject)value.DeepClone();
            }
        }
        internal bool HasExactAttempt(JObject current,string attemptId)
        {
            lock(_gate) {
                bool matches(JObject record) => (string)record["currentAttempt"]?["saveAttemptId"]==attemptId
                    && (string)record["currentAttempt"]?["dispatchPhase"]!="Prepared"
                    && (string)record["currentAttempt"]?["attemptOutcome"]!="NotSent";
                if(matches(current))return true;
                string prefix=SettingsCanonical.Digest((string)current["contextId"])+".attempt."+(string)current["recordId"]+".";
                foreach(var path in Directory.EnumerateFiles(_directory,prefix+"*.json")) {
                    var prior=ReadBounded(path,4096); Validate(prior,(string)current["contextId"]);
                    if((long)prior["sequence"]>=(long)current["sequence"] || (string)prior["recordId"]!=(string)current["recordId"]
                        || (string)prior["originMutationRequestDigest"]!=(string)current["originMutationRequestDigest"])
                        throw new InvalidDataException("Settings attempt history mismatches root");
                    if(matches(prior))return true;
                }
                return false;
            }
        }
        internal JObject PrepareSave(string context,string operation,long sequence,string attemptId,string epoch)
        {
            var before=Read(context); string oldAttempt=(string)before?["currentAttempt"]?["saveAttemptId"];
            return ChangeAttempt(context,operation,oldAttempt,sequence,value=> {
                if((string)value["rootOperationState"]!="AppliedUnconfirmed" || value["targetRevision"].Type==JTokenType.Null
                    || new[] {"Unknown","none"}.Contains((string)value["currentAttempt"]?["attemptOutcome"]))throw new InvalidOperationException("Save target is unresolved");
                value["currentAttempt"]=Attempt(attemptId,"save",epoch,(string)value["targetStateToken"],(long)value["targetRevision"]);
            });
        }
        public void Dispose() { lock(_gate) { if(_disposed)return;_disposed=true;_ownership.Dispose(); } }
    }
}
