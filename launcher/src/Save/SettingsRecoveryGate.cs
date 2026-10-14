using System;
using System.Collections.Concurrent;
using System.Threading.Tasks;
using Newtonsoft.Json.Linq;

namespace CF7Launcher.Save
{
    internal sealed class SettingsRecoveryAdmission
    {
        internal SettingsSaveContext Context;
        internal bool Allowed;
        internal string Error,Owner,Epoch,RecoveryConfirmation;
        internal JObject Record;
        internal SettingsRawSolObservation Observation;
        internal SettingsRecoveryAdmission AsReplacement()=>new() { Context=Context,Allowed=Allowed,Error=Error,
            Record=Record==null ? null : (JObject)Record.DeepClone(),Owner="owner."+Guid.NewGuid().ToString("N"),Epoch="vm."+Guid.NewGuid().ToString("N") };
        private JToken RecoveryMapping()
        {
            if(RecoveryConfirmation!="cold_read_exact" || Record==null || Observation?.Receipt==null)return JValue.CreateNull();
            // The receipt may certify a dispatched historical attempt while a later retry was only Prepared.
            // This is a source recovery mapping, never a rewrite of the journal's current attempt.
            var mapping=new JObject();
            foreach(string field in new[] { "contextId","saveOwnerId","originNamespaceDigest","slot","sourceAuthorityEpoch",
                "operationToken","originMutationRequestDigest","settingsDigest","targetStateToken","targetRevision" })
                mapping[field]=Record[field].DeepClone();
            mapping["currentAttempt"]=new JObject { ["saveAttemptId"]=Observation.Receipt["saveAttemptId"].DeepClone() };
            return mapping;
        }
        internal JObject BootstrapMetadata()=>new JObject {
            ["protocol"]=2,["contextId"]=Context.ContextId,["saveOwnerId"]=Owner,["originNamespaceDigest"]=Context.OriginNamespaceDigest,
            ["authorityEpoch"]=Epoch,["slot"]=Context.Slot,["writeAdmission"]=Allowed ? "allowed" : "blocked_by_operation",
            ["recoveryConfirmation"]=RecoveryConfirmation ?? "none",
            ["rawCanonical"]=Observation?.Available==true ? Observation.Canonical : null,
            ["recoveryMapping"]=RecoveryMapping() };
    }
    internal sealed class SettingsRecoveryGate
    {
        private readonly SettingsWriteJournal _journal;
        private readonly SettingsRawSolReader _reader;
        private readonly string _installRoot,_swfPath;
        private readonly string _initialError;
        private readonly ConcurrentDictionary<string,SettingsRecoveryAdmission> _admissions=new(StringComparer.Ordinal);
        internal SettingsRecoveryGate(SettingsWriteJournal journal,SettingsRawSolReader reader,string installRoot,string swfPath,string initialError=null)
        { _journal=journal;_reader=reader;_installRoot=installRoot;_swfPath=swfPath;_initialError=initialError; }
        internal SettingsSaveContext Context(string slot)=>new(_installRoot,_swfPath,slot);
        internal Task<SettingsRecoveryAdmission> InspectAsync(string slot)=>Task.Run(()=>Inspect(slot));
        internal SettingsRecoveryAdmission Inspect(string slot)
        {
            var result=new SettingsRecoveryAdmission { Context=Context(slot),Owner="owner."+Guid.NewGuid().ToString("N"),
                Epoch="vm."+Guid.NewGuid().ToString("N") };
            try {
                if(_initialError!=null || _journal==null)throw new InvalidOperationException("Settings metadata unavailable");
                var record=_journal.Read(result.Context.ContextId); result.Record=record;
                if(record!=null && ((string)record["originNamespaceDigest"]!=result.Context.OriginNamespaceDigest
                    || (string)record["slot"]!=result.Context.Slot))throw new InvalidOperationException("Settings origin changed");
                if(record==null || (string)record["rootOperationState"] is "Confirmed" or "NotApplied" or "NotSent") {
                    result.Allowed=true;result.Observation=_reader.Read(result.Context);
                    if(record!=null && SettingsRawSolReader.MatchesReceipt(result.Observation,record,_journal)) {
                        result.Owner=(string)record["saveOwnerId"];result.RecoveryConfirmation="cold_read_exact";
                    } else if(result.Observation.Available)result.RecoveryConfirmation="cold_read_current";
                }
                else if((string)record["currentAttempt"]?["dispatchPhase"]=="Prepared"
                    && (string)record["currentAttempt"]?["command"]=="apply") {
                    result.Record=_journal.ChangeAttempt(result.Context.ContextId,(string)record["operationToken"],
                        (string)record["currentAttempt"]["saveAttemptId"],(long)record["sequence"],value=> {
                            value["rootOperationState"]="NotSent"; value["currentAttempt"]["dispatchPhase"]="Returned";
                            value["currentAttempt"]["attemptOutcome"]="NotSent";
                        });
                    result.Allowed=true;
                } else {
                    result.Observation=_reader.Read(result.Context);
                    if(SettingsRawSolReader.MatchesReceipt(result.Observation,record,_journal)) {
                        result.Record=_journal.ChangeAttempt(result.Context.ContextId,(string)record["operationToken"],
                            (string)record["currentAttempt"]["saveAttemptId"],(long)record["sequence"],value=> {
                                value["rootOperationState"]="Confirmed";value["confirmation"]="cold_read_exact";
                                SettingsCanonical.Integer(result.Observation.Receipt["revision"],0,SettingsCanonical.MaxSafeInteger,true,out long revision);
                                value["targetRevision"]=revision;
                                value["lastObservation"]=new JObject { ["kind"]="cold_read_exact",["sourceSha256"]=result.Observation.SourceSha256,
                                    ["receiptAttemptId"]=result.Observation.Receipt["saveAttemptId"] };
                            });
                        result.Allowed=true;result.Owner=(string)record["saveOwnerId"];result.RecoveryConfirmation="cold_read_exact";
                    } else result.Error="settings_operation_unresolved";
                }
            } catch { result.Error="settings_metadata_unavailable";result.Allowed=false; }
            if(result.Allowed && result.Observation?.Receipt is JObject receipt
                && !SettingsCanonical.Integer(receipt["schema"],1,1,true,out _)) {
                result.Allowed=false;result.Error="settings_receipt_schema_unsupported";
            }
            _admissions[result.Context.ContextId]=result; return result;
        }
        internal bool MayWrite(string slot)
        {
            try {
                if(_initialError!=null || _journal==null)return false;
                string context=Context(slot).ContextId;
                if(_admissions.TryGetValue(context,out var admission) && !admission.Allowed)return false;
                var record=_journal.Read(context);
                return record==null || (string)record["rootOperationState"] is "Confirmed" or "NotApplied" or "NotSent";
            } catch { return false; }
        }
        internal SettingsRecoveryAdmission PrepareReplacement(string slot)
        {
            if(!MayWrite(slot))throw new InvalidOperationException("settings_recovery_required");
            var context=Context(slot);
            return new SettingsRecoveryAdmission { Context=context,Allowed=true,Record=_journal.Read(context.ContextId),
                Owner="owner."+Guid.NewGuid().ToString("N"),Epoch="vm."+Guid.NewGuid().ToString("N") };
        }
        internal bool MayWriteCached(string slot)
        {
            try { return _initialError==null && _journal!=null && _admissions.TryGetValue(Context(slot).ContextId,out var admission) && admission.Allowed; }
            catch { return false; }
        }
        internal void Invalidate(string slot,string error)
        {
            var context=Context(slot);
            _admissions[context.ContextId]=new SettingsRecoveryAdmission { Context=context,Allowed=false,Error=error };
        }
    }
}
