using System;
using System.Linq;
using CF7Launcher.Save;
using Newtonsoft.Json.Linq;

namespace CF7Launcher.Tasks
{
    internal sealed class SettingsV2Response
    {
        internal JObject Envelope,State,Outcome,Snapshot;
        internal string Context,Owner,Epoch,Operation,WriteAdmission;
        internal bool Success,RequiresReconcile;
        private static bool Strings(JObject value,params string[] fields)=>fields.All(f=>value[f]?.Type==JTokenType.String);
        private static bool Booleans(JObject value,params string[] fields)=>fields.All(f=>value[f]?.Type==JTokenType.Boolean);
        private static bool Enum(JToken value,params string[] values)=>value?.Type==JTokenType.String && values.Contains((string)value);
        private static bool Opaque(JToken value)=>value?.Type==JTokenType.String && SettingsCanonical.IsOpaque((string)value);
        private static bool Digest(JToken value)=>value?.Type==JTokenType.String && SettingsCanonical.IsDigest((string)value);
        private static bool Null(JToken value)=>value?.Type==JTokenType.Null;
        private static bool Confirmation(JToken value)=>Enum(value,"none","flush_true","cold_read_exact","cold_read_current");
        internal static bool TryParse(JObject input,string operation,out SettingsV2Response result)
        {
            result=null;
            try {
                if(input==null || !SettingsCanonical.Integer(input["v"],2,2,false,out _)
                    || !SettingsCanonical.Integer(input["callId"],1,int.MaxValue,false,out _)
                    || (string)input["task"]!="settings_response" || !Strings(input,"operation","contextId","saveOwnerId","authorityEpoch","writeAdmission")
                    || (string)input["operation"]!=operation || !Opaque(input["contextId"]) || !Opaque(input["saveOwnerId"]) || !Opaque(input["authorityEpoch"])
                    || !Booleans(input,"success","requiresReconcile") || !Enum(input["writeAdmission"],"allowed","blocked_by_operation","blocked_by_metadata","blocked_by_context")
                    || input["warnings"] is not JArray warnings || warnings.Count>32
                    || warnings.Any(w=>w.Type!=JTokenType.String || ((string)w).Length>100 || ((string)w).Any(c=>!(c>='a'&&c<='z'||c>='0'&&c<='9'||c=='_')))
                    || input["outcome"] is not JObject outcome)return false;
                if(input["holdActive"]!=null && input["holdActive"].Type!=JTokenType.Boolean)return false;
                if(!Strings(outcome,"applyState","attemptState","confirmation","resolution") || !Booleans(outcome,"durable")
                    || !Enum(outcome["applyState"],"none","not_applied","applied","unknown")
                    || !Enum(outcome["attemptState"],"none","not_sent","in_flight","returned_unconfirmed","confirmed","unknown")
                    || !Enum(outcome["resolution"],"none","applied","not_applied","unresolved") || !Confirmation(outcome["confirmation"])
                    || outcome["error"]==null || outcome["error"].Type is not (JTokenType.Null or JTokenType.String))return false;
                string apply=(string)outcome["applyState"],attempt=(string)outcome["attemptState"];
                bool durable=(bool)outcome["durable"];
                if(apply=="none") {
                    foreach(var f in new[] {"operationToken","sourceAuthorityEpoch","originMutationRequestDigest","targetStateToken","saveAttemptId","applied"})
                        if(!Null(outcome[f]))return false;
                    if(attempt!="none" || durable || (string)outcome["confirmation"]!="none")return false;
                } else {
                    if(!Opaque(outcome["operationToken"]) || !Opaque(outcome["sourceAuthorityEpoch"]) || !Opaque(outcome["targetStateToken"])
                        || !Opaque(outcome["saveAttemptId"]) || !Digest(outcome["originMutationRequestDigest"]))return false;
                    if(apply=="unknown") { if(!Null(outcome["applied"]) || durable || (string)outcome["resolution"]!="unresolved")return false; }
                    else if(outcome["applied"]?.Type!=JTokenType.Boolean || (bool)outcome["applied"]!=(apply=="applied"))return false;
                    if(durable && (apply!="applied" || attempt is not ("confirmed" or "not_sent") || (string)outcome["confirmation"]=="none"))return false;
                    if(!durable && (attempt=="confirmed" || (string)outcome["confirmation"]!="none"))return false;
                    if(apply=="not_applied" && attempt is not ("none" or "not_sent"))return false;
                    if(apply=="not_applied" && (string)outcome["resolution"]!="not_applied"
                        || apply=="applied" && (string)outcome["resolution"]!="applied")return false;
                }
                JObject state=input["state"] as JObject,snapshot=input["snapshot"] as JObject;
                if(operation=="snapshot" && (bool)input["success"] && (state==null || snapshot==null))return false;
                if(state==null) {
                    if(!Null(input["state"]) || !Null(input["snapshot"]) || !warnings.Any(w=>(string)w=="current_authority_unavailable"))return false;
                } else {
                    if(!SettingsCanonical.Integer(state["revision"],0,SettingsCanonical.MaxSafeInteger,false,out _)
                        || !Opaque(state["stateToken"]) || !Booleans(state,"durable","needsSaveRetry","migrationPending")
                        || !Enum(state["persistenceState"],"confirmed","unconfirmed","unknown") || !Confirmation(state["confirmation"]))return false;
                    bool stateDurable=(bool)state["durable"],retry=(bool)state["needsSaveRetry"];
                    if(stateDurable!=((string)state["persistenceState"]=="confirmed") || stateDurable==((string)state["confirmation"]=="none")
                        || (bool)input["requiresReconcile"] && retry || (string)input["writeAdmission"]!="allowed" && retry)return false;
                    if((string)state["stateToken"]==(string)outcome["targetStateToken"] && stateDurable!=durable && apply!="none")return false;
                    if(snapshot==null) {
                        if(!Null(input["snapshot"]) || operation!="save" && !warnings.Any(w=>(string)w=="current_authority_unavailable"))return false;
                    } else if(!ValidateSnapshot(snapshot) || !SettingsCanonical.Integer(snapshot["revision"],0,SettingsCanonical.MaxSafeInteger,false,out long snapshotRevision)
                        || snapshotRevision!=(long)state["revision"])return false;
                }
                var cloned=(JObject)input.DeepClone();
                result=new SettingsV2Response { Envelope=cloned,State=cloned["state"] as JObject,Outcome=(JObject)cloned["outcome"],Snapshot=cloned["snapshot"] as JObject,
                    Context=(string)cloned["contextId"],Owner=(string)cloned["saveOwnerId"],Epoch=(string)cloned["authorityEpoch"],Operation=operation,
                    WriteAdmission=(string)cloned["writeAdmission"],Success=(bool)cloned["success"],RequiresReconcile=(bool)cloned["requiresReconcile"] };
                return true;
            } catch { return false; }
        }
        private static bool ValidateSnapshot(JObject snapshot)
        {
            if(!SettingsCanonical.Integer(snapshot["keySchemaVersion"],2,2,false,out _)
                || !Booleans(snapshot,"challengeMode","previewActive") || !Strings(snapshot,"modeLabel","keyMigrationNotice")
                || snapshot["settings"] is not JObject settings || snapshot["keys"] is not JArray keys || keys.Count!=36
                || snapshot["defaultKeys"] is not JArray defaults || defaults.Count!=36 || snapshot["allowedKeyCodes"] is not JArray allowed
                || snapshot["cheatHelp"] is not JArray || snapshot["forceControls"] is not JObject)return false;
            if(!Booleans((JObject)snapshot["forceControls"],"returnBaseAvailable","tryReviveAvailable","resurrectionRestricted"))return false;
            if(!SettingsCanonical.TryEncode(settings,keys,false,out _) || ((string)snapshot["keyMigrationNotice"]).Length>160
                || ((string)snapshot["keyMigrationNotice"]).Any(char.IsControl) || ((string)snapshot["modeLabel"]).Length>64
                || allowed.Count>256 || ((JArray)snapshot["cheatHelp"]).Count>64)return false;
            foreach(var index in SettingsCanonicalSchema.BooleanIndexes)
                if(settings[SettingsCanonicalSchema.Settings[index]]?.Type!=JTokenType.Boolean)return false;
            foreach(var field in SettingsCanonicalSchema.Settings)if(settings[field]==null)return false;
            for(int i=0;i<36;i++) {
                if(keys[i] is not JObject row || defaults[i] is not JObject baseline || (string)row["id"]!=SettingsCanonicalSchema.KeyIds[i]
                    || (string)baseline["id"]!=SettingsCanonicalSchema.KeyIds[i] || !SettingsCanonical.Integer(row["keyCode"],0,255,false,out _)
                    || !SettingsCanonical.Integer(baseline["keyCode"],0,255,false,out _)
                    || !SettingsCanonical.Integer(row["index"],i,i,false,out _) || !Strings(row,"label","keyName"))return false;
            }
            return allowed.All(code=>code is JObject entry && SettingsCanonical.Integer(entry["code"],0,255,false,out _)
                && entry["name"]?.Type==JTokenType.String && ((string)entry["name"]).Length<=64)
                && allowed.Select(code=>(long)code["code"]).Distinct().Count()==allowed.Count
                && ((JArray)snapshot["cheatHelp"]).All(row=>row is JObject help && Strings(help,"command","description","effectScope")
                    && Enum(help["effectScope"],"read","session","save") && ((string)help["command"]).Length<=160
                    && ((string)help["description"]).Length<=512);
        }
    }
}
