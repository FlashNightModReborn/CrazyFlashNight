using System;
using System.Collections.Generic;
using System.Threading;
using System.Threading.Tasks;
using CF7Launcher.Guardian;
using CF7Launcher.Save;
using Newtonsoft.Json;
using Newtonsoft.Json.Linq;

namespace CF7Launcher.Tasks
{
    public sealed partial class SettingsTask
    {
        private sealed class AuthorityCall
        {
            internal int Id;
            internal string WebId,Command,Panel,Binding,Owner,Epoch,EpochPrefix,Attempt,Canonical;
            internal SettingsSaveContext Context;
            internal SettingsWriteIntent Intent;
            internal JObject Root,Payload;
            internal Action<string> Sink;
            internal bool Write;
            internal int TransportCalled;
            internal int ReplySeen;
        }
        private bool _authorityConfigured,_backendV2,_metadataBlocked;
        private SettingsWriteJournal _settingsJournal;
        private SettingsRecoveryGate _settingsRecovery;
        private SettingsSaveContext _settingsContext;
        private string _authorityBinding,_authorityOwner,_authorityEpoch,_authorityEpochPrefix;
        private JObject _authorityState,_authorityRoot;
        private JObject _authoritySnapshot;
        private int _authorityWriteId;
        private bool _authorityBusy;
        private bool _authorityControlPending;
        private readonly object _authorityIoLock=new();
        private Task _authorityIoTail=Task.CompletedTask;
        private Task AuthorityIo(Action action)
        {
            lock(_authorityIoLock) {
                Task previous=_authorityIoTail;
                return _authorityIoTail=Task.Run(async()=> { await previous.ConfigureAwait(false);action(); });
            }
        }
#if CF7_TEST_SEAMS
        internal Task DrainAuthorityIoForTests() { lock(_authorityIoLock)return _authorityIoTail; }
        internal int RetainedAuthorityCallsForTests { get { lock(_lock)return _authorityCalls.Count; } }
#endif
        private Func<Action<string>> _authoritySinkProvider;
        private readonly Dictionary<int,AuthorityCall> _authorityCalls=new();
        internal bool HasUnresolvedAuthority { get { lock(_lock)return _requiresReconcile || _metadataBlocked || _authorityBusy || _authorityControlPending; } }
        internal void ConfigureAuthority(SettingsWriteJournal journal,SettingsRecoveryGate recovery)
        { _settingsJournal=journal;_settingsRecovery=recovery;_authorityConfigured=true; }
        internal void SetAuthorityResponseLeaseProvider(Func<Action<string>> provider) { _authoritySinkProvider=provider; }
        internal void BindAuthoritySource(SettingsRecoveryAdmission admission,bool supportsV2)
        {
            lock(_lock) {
                _pendingCalls.Clear();
                _settingsContext=admission.Context;_authorityOwner=admission.Owner;_authorityEpochPrefix=admission.Epoch;
                _authorityEpoch=admission.Epoch+".1";_authorityBinding=Guid.NewGuid().ToString("N");_backendV2=supportsV2;
                _authorityRoot=admission.Record==null ? null : (JObject)admission.Record.DeepClone();_authorityState=null;_authoritySnapshot=null;
                _metadataBlocked=!admission.Allowed;_requiresReconcile=!admission.Allowed;_nonPreviewWritePending=false;_authorityBusy=false;
                _authorityControlPending=false;
            }
        }
        private Action<string> FreezeAuthoritySink()=>_authoritySinkProvider?.Invoke() ?? _postToWeb;
        private static void DeliverAuthorityResponse(AuthorityCall call,string response)
        {
            // A retired or failing UI cannot poison the serialized journal queue.
            try { call.Sink?.Invoke(response); }
            catch(Exception error) { LogManager.Log("[SettingsTask] authority response delivery failed: "+error.Message); }
        }
        private void RetireSettledAuthorityCalls(AuthorityCall settled,JObject root)
        {
            if(root==null || (string)root["rootOperationState"] is not ("Confirmed" or "NotApplied" or "NotSent"))return;
            string operation=(string)root["operationToken"];
            lock(_lock) {
                var retired=new List<int>();
                foreach(var entry in _authorityCalls) {
                    var call=entry.Value;
                    if(call.Write && call.Context.ContextId==settled.Context.ContextId && call.Owner==settled.Owner
                        && ((string)call.Root?["operationToken"] ?? call.Intent?.Operation)==operation)
                        retired.Add(entry.Key);
                }
                foreach(int id in retired)_authorityCalls.Remove(id);
            }
        }
        private void AuthorityOnUi(Action action)
        { if(_invokeOnUI!=null)_invokeOnUI(action);else action(); }
        private bool IsCurrentAuthorityCall(AuthorityCall call)=>!_disposed && call.Binding==_authorityBinding
            && _settingsContext?.ContextId==call.Context.ContextId;
        private void HandleAuthorityRequest(string webId,string command,string panel,string action,JObject normalized,bool isWrite)
        {
            AuthorityCall call;
            lock(_lock) {
                if(_pendingCalls.IsKnownWebCallId(webId))return;
                if(_settingsContext==null || !_backendV2 || command is "apply" or "save" && (_metadataBlocked || _requiresReconcile || _authorityControlPending)
                    || command is "apply" or "save" && _authorityBusy
                    || command=="reconcile" && _authorityBusy && _pendingCalls.TryPeek(_authorityWriteId,out _)
                    || command is "apply" or "save" or "preview" && _authorityState==null) {
                    if(_pendingCalls.TryRememberRejected(webId))RespondError(webId,command,panel,
                        _metadataBlocked ? "settings_metadata_unavailable" : "reconcile_required");
                    return;
                }
                call=new AuthorityCall { WebId=webId,Command=command,Panel=panel,Binding=_authorityBinding,Owner=_authorityOwner,
                    Epoch=_authorityEpoch,EpochPrefix=_authorityEpochPrefix,Context=_settingsContext,Sink=FreezeAuthoritySink(),Write=command is "apply" or "save",
                    Payload=(JObject)normalized.DeepClone(),Root=_authorityRoot==null ? null : (JObject)_authorityRoot.DeepClone() };
                call.Payload["v"]=2;call.Payload["contextId"]=call.Context.ContextId;call.Payload["saveOwnerId"]=call.Owner;call.Payload["authorityEpoch"]=call.Epoch;
                if(command=="apply") {
                    if(!SettingsCanonical.Integer(normalized["expectedRevision"],0,SettingsCanonical.MaxSafeInteger,false,out long revision)
                        || revision!=(long)_authorityState["revision"]
                        || !SettingsCanonical.TryEncode(normalized["settings"] as JObject,normalized["keys"] as JArray,false,out call.Canonical)
                        || call.Root!=null && (string)call.Root["rootOperationState"] is not ("Confirmed" or "NotApplied" or "NotSent")) {
                        if(_pendingCalls.TryRememberRejected(webId))RespondError(webId,command,panel,"stale_revision");return;
                    }
                    call.Attempt="save."+Guid.NewGuid().ToString("N");
                    call.Intent=new SettingsWriteIntent(call.Context,call.Owner,call.Epoch,"op."+Guid.NewGuid().ToString("N"),
                        (string)_authorityState["stateToken"],revision,SettingsCanonical.Digest(call.Canonical));
                    call.Payload["baseStateToken"]=call.Intent.BaseState;call.Payload["operationToken"]=call.Intent.Operation;
                    call.Payload["saveAttemptId"]=call.Attempt;call.Payload["settingsDigest"]=call.Intent.Digest;
                    call.Payload["originMutationRequestDigest"]=call.Intent.MutationDigest;call.Payload["expectedCanonical"]=call.Canonical;
                } else if(command=="save" || command=="reconcile") {
                    if(call.Root==null) { if(_pendingCalls.TryRememberRejected(webId))RespondError(webId,command,panel,"reconcile_required");return; }
                    call.Attempt=command=="save" ? "save."+Guid.NewGuid().ToString("N") : (string)call.Root["currentAttempt"]?["saveAttemptId"];
                    call.Payload["operationToken"]=call.Root["operationToken"].DeepClone();call.Payload["sourceAuthorityEpoch"]=call.Root["sourceAuthorityEpoch"].DeepClone();
                    call.Payload["originMutationRequestDigest"]=call.Root["originMutationRequestDigest"].DeepClone();
                    call.Payload["saveAttemptId"]=call.Attempt;
                    if(command=="save") {
                        if((string)call.Root["rootOperationState"]!="AppliedUnconfirmed" || call.Root["targetRevision"].Type==JTokenType.Null
                            || (string)_authorityState["stateToken"]!=(string)call.Root["targetStateToken"]) {
                            if(_pendingCalls.TryRememberRejected(webId))RespondError(webId,command,panel,"stale_save_target");return;
                        }
                        call.Payload["stateToken"]=call.Root["targetStateToken"].DeepClone();call.Payload["expectedRevision"]=call.Root["targetRevision"].DeepClone();
                        call.Payload["settingsDigest"]=call.Root["settingsDigest"].DeepClone();
                    }
                } else if(command=="preview")call.Payload["stateToken"]=_authorityState["stateToken"].DeepClone();
                var pending=new PendingRequest { WebCmd=command,PanelInstanceId=panel,IsWrite=isWrite,ReconcileEpoch=_reconcileEpoch,Authority=call };
                if(!_pendingCalls.TryBegin(webId,pending,out call.Id))return;
                _authorityCalls.Add(call.Id,call);if(call.Write) { _authorityBusy=true;_nonPreviewWritePending=true;_authorityWriteId=call.Id; }
            }
            if(!call.Write) { SendAuthorityCall(call,action);return; }
            _=AuthorityIo(()=> {
                try {
                    call.Root=call.Command=="apply" ? _settingsJournal.Prepare(call.Intent,call.Attempt)
                        : _settingsJournal.PrepareSave(call.Context.ContextId,(string)call.Root["operationToken"],(long)call.Root["sequence"],call.Attempt,call.Epoch);
                    call.Root=_settingsJournal.ChangeAttempt(call.Context.ContextId,(string)call.Root["operationToken"],call.Attempt,(long)call.Root["sequence"],
                        root=>root["currentAttempt"]["dispatchPhase"]="Dispatching");
                    AuthorityOnUi(()=> {
                        if(!IsCurrentAuthorityCall(call) || _panelInstanceId!=call.Panel || !_pendingCalls.TryPeek(call.Id,out _)) { SettleAuthorityNotSent(call);return; }
                        lock(_lock)_authorityRoot=(JObject)call.Root.DeepClone();
                        SendAuthorityCall(call,action);
                    });
                } catch {
                    AuthorityOnUi(()=> { lock(_lock)if(IsCurrentAuthorityCall(call)) { _metadataBlocked=true;_requiresReconcile=true;_authorityBusy=false;_nonPreviewWritePending=false; }
                        SendAuthorityGate(call,"hold");
                        _pendingCalls.TryComplete(call.Id,out _);
                        lock(_lock)_authorityCalls.Remove(call.Id); // Transport was never called.
                        PostAuthorityError(call,"settings_metadata_unavailable"); });
                }
            });
        }
        private void SendAuthorityCall(AuthorityCall call,string action)
        {
            try {
                if(!IsCurrentAuthorityCall(call) || _panelInstanceId!=call.Panel || !_pendingCalls.TryPeek(call.Id,out _)) {
                    if(call.Write)SettleAuthorityNotSent(call);return;
                }
                var message=PanelBridge.BuildFlashCommand(action,call.Id,call.Payload);
                Interlocked.Exchange(ref call.TransportCalled,1);
                if(!_trySend(message.ToString(Formatting.None)+"\0")) {
                    if(_pendingCalls.TryComplete(call.Id,out var ended))HandleAuthorityPendingEnded(call,ended,PanelPendingCallEndReason.DeliveryUnknown);
                }
            } catch {
                if(_pendingCalls.TryComplete(call.Id,out var ended))HandleAuthorityPendingEnded(call,ended,PanelPendingCallEndReason.DeliveryUnknown);
            }
        }
        private void SettleAuthorityNotSent(AuthorityCall call)
        {
            if(Volatile.Read(ref call.TransportCalled)!=0)return;
            _=AuthorityIo(()=> {
                try {
                    var latest=_settingsJournal.Read(call.Context.ContextId);
                    if(latest==null || (string)latest["operationToken"]!=(string)call.Root?["operationToken"]
                        || (string)latest["currentAttempt"]?["saveAttemptId"]!=call.Attempt || (string)latest["rootOperationState"]=="Confirmed")return;
                    call.Root=_settingsJournal.ChangeAttempt(call.Context.ContextId,(string)latest["operationToken"],call.Attempt,(long)latest["sequence"],root=> {
                        root["currentAttempt"]["dispatchPhase"]="Returned";root["currentAttempt"]["attemptOutcome"]="NotSent";
                        if(call.Command=="apply")root["rootOperationState"]="NotSent";
                    });
                    AuthorityOnUi(()=> { lock(_lock)if(IsCurrentAuthorityCall(call) && _authorityWriteId==call.Id) {
                        _authorityRoot=(JObject)call.Root.DeepClone();_authorityBusy=false;_requiresReconcile=false;
                    } });
                } catch { lock(_lock)if(IsCurrentAuthorityCall(call))_metadataBlocked=true; }
                finally { lock(_lock)_authorityCalls.Remove(call.Id); } // No transport can produce a late response.
            });
        }
        private void HandleAuthorityPendingEnded(AuthorityCall call,PanelPendingCall<PendingRequest> pending,PanelPendingCallEndReason reason)
        {
            lock(_lock) { if(call.Write && IsCurrentAuthorityCall(call)) { _requiresReconcile=true;_nonPreviewWritePending=false;_authorityBusy=false; } }
            if(call.Write) {
                if(Volatile.Read(ref call.TransportCalled)==0)SettleAuthorityNotSent(call);
                else {
                    SendAuthorityGate(call,"hold");
                    _=AuthorityIo(()=> {
                    try {
                        if(Volatile.Read(ref call.ReplySeen)!=0)return;
                        var latest=_settingsJournal.Read(call.Context.ContextId);
                        if(latest==null || (string)latest["operationToken"]!=(string)call.Root?["operationToken"]
                            || (string)latest["currentAttempt"]?["saveAttemptId"]!=call.Attempt || (string)latest["rootOperationState"]=="Confirmed")return;
                        _settingsJournal.ChangeAttempt(call.Context.ContextId,(string)latest["operationToken"],call.Attempt,(long)latest["sequence"],root=> {
                            root["currentAttempt"]["attemptOutcome"]="Unknown";
                            if(call.Command=="apply")root["rootOperationState"]="Unknown";
                        });
                    } catch { lock(_lock)if(IsCurrentAuthorityCall(call))_metadataBlocked=true; }
                    });
                }
            }
            if(reason!=PanelPendingCallEndReason.Cleared && !_disposed)PostAuthorityError(call,reason==PanelPendingCallEndReason.Timeout ? "timeout" : "delivery_unknown");
            if(!call.Write)lock(_lock)_authorityCalls.Remove(call.Id);
        }
        private bool SendAuthorityGate(AuthorityCall call,string admission)
        {
            if(!IsCurrentAuthorityCall(call) || call.Root==null && call.Intent==null)return false;
            lock(_lock)_authorityControlPending=true;
            var payload=new JObject { ["v"]=2,["contextId"]=call.Context.ContextId,["saveOwnerId"]=call.Owner,["authorityEpoch"]=call.Epoch,
                ["sourceAuthorityEpoch"]=call.Root?["sourceAuthorityEpoch"]?.DeepClone() ?? new JValue(call.Intent.Epoch),
                ["operationToken"]=call.Root?["operationToken"]?.DeepClone() ?? new JValue(call.Intent.Operation),
                ["saveAttemptId"]=call.Attempt,["originMutationRequestDigest"]=call.Root?["originMutationRequestDigest"]?.DeepClone()
                    ?? new JValue(call.Intent.MutationDigest),["admission"]=admission };
            try { return _trySend(PanelBridge.BuildFlashCommand("settingsAuthorityGate",0,payload).ToString(Formatting.None)+"\0"); }
            catch { return false; }
        }
        private void PostAuthorityError(AuthorityCall call,string error)
        {
            JObject response;
            lock(_lock) {
                var root=call.Write || call.Command=="reconcile" ? call.Root : null;
                bool knownApplied=root!=null && (string)root["rootOperationState"] is "AppliedUnconfirmed" or "Confirmed";
                bool confirmed=root!=null && (string)root["rootOperationState"]=="Confirmed";
                var outcome=new JObject {
                    ["operationToken"]=root?["operationToken"]?.DeepClone() ?? JValue.CreateNull(),
                    ["sourceAuthorityEpoch"]=root?["sourceAuthorityEpoch"]?.DeepClone() ?? JValue.CreateNull(),
                    ["originMutationRequestDigest"]=root?["originMutationRequestDigest"]?.DeepClone() ?? JValue.CreateNull(),
                    ["targetStateToken"]=root?["targetStateToken"]?.DeepClone() ?? JValue.CreateNull(),
                    ["saveAttemptId"]=root==null ? JValue.CreateNull() : new JValue(call.Attempt),
                    ["applyState"]=root==null ? "none" : knownApplied ? "applied" : "unknown",
                    ["applied"]=knownApplied ? new JValue(true) : JValue.CreateNull(),["attemptState"]=root==null ? "none" : confirmed ? "confirmed" : "unknown",
                    ["durable"]=confirmed,["confirmation"]=confirmed ? root["confirmation"].DeepClone() : new JValue("none"),
                    ["error"]=error,["resolution"]=root==null ? "none" : knownApplied ? "applied" : "unresolved" };
                response=BuildError(call.WebId,call.Command,call.Panel,error);response["v"]=2;response["operation"]=call.Command;
                response["contextId"]=call.Context.ContextId;response["saveOwnerId"]=call.Owner;response["authorityEpoch"]=call.Epoch;
                response["requiresReconcile"]=call.Write || _requiresReconcile;
                response["writeAdmission"]=_metadataBlocked ? "blocked_by_metadata" : "blocked_by_operation";
                response["state"]=_authoritySnapshot!=null && IsCurrentAuthorityCall(call) ? _authorityState?.DeepClone() : JValue.CreateNull();
                if(response["state"] is JObject state)state["needsSaveRetry"]=false;
                response["snapshot"]=response["state"].Type==JTokenType.Null ? JValue.CreateNull() : _authoritySnapshot.DeepClone();
                response["outcome"]=outcome;response["warnings"]=new JArray("current_authority_unavailable");
            }
            AuthorityOnUi(()=>DeliverAuthorityResponse(call,response.ToString(Formatting.None)));
        }
        private bool HandleAuthorityResponse(int id,JObject message)
        {
            AuthorityCall call;
            lock(_lock)if(!_authorityCalls.TryGetValue(id,out call))return false;
            if(!SettingsV2Response.TryParse(message,call.Command,out var parsed) || parsed.Context!=call.Context.ContextId || parsed.Owner!=call.Owner
                || (call.Command=="snapshot" ? !ValidAuthorityEpoch(parsed.Epoch,call.EpochPrefix) : parsed.Epoch!=call.Epoch)) {
                if(_pendingCalls.TryComplete(id,out var malformed))HandleAuthorityPendingEnded(call,malformed,PanelPendingCallEndReason.DeliveryUnknown);
                return true;
            }
            if(call.Write || call.Command=="reconcile") {
                if((string)parsed.Outcome["operationToken"]!=(string)call.Root?["operationToken"]
                    || (string)parsed.Outcome["originMutationRequestDigest"]!=(string)call.Root?["originMutationRequestDigest"]
                    || (string)parsed.Outcome["sourceAuthorityEpoch"]!=(string)call.Root?["sourceAuthorityEpoch"]
                    || (string)parsed.Outcome["targetStateToken"]!=(string)call.Root?["targetStateToken"]
                    || (string)parsed.Outcome["saveAttemptId"]!=call.Attempt
                    || parsed.State!=null && parsed.Epoch==(string)call.Root?["sourceAuthorityEpoch"]
                        && (string)parsed.State["stateToken"]==(string)call.Root?["targetStateToken"]
                        && (long)parsed.State["revision"]!=(long)call.Root["baseRevision"]+1) {
                    if(_pendingCalls.TryComplete(id,out var mismatch))HandleAuthorityPendingEnded(call,mismatch,PanelPendingCallEndReason.DeliveryUnknown);
                    return true;
                }
            }
            if(call.Command=="apply" && (string)parsed.Outcome["applyState"]=="applied" && parsed.Snapshot!=null
                && (!SettingsCanonical.TryEncode((JObject)parsed.Snapshot["settings"],(JArray)parsed.Snapshot["keys"],false,out string actual)
                    || actual!=call.Canonical)) {
                if(_pendingCalls.TryComplete(id,out var projectionMismatch))HandleAuthorityPendingEnded(call,projectionMismatch,PanelPendingCallEndReason.DeliveryUnknown);
                return true;
            }
            Interlocked.Exchange(ref call.ReplySeen,1);
            _pendingCalls.TryComplete(id,out _);
            _=AuthorityIo(()=> {
                bool metadataOk=true,suppressOldFailure=false;JObject updated=call.Root;
                if(call.Write || call.Command=="reconcile") {
                    try {
                        var latest=_settingsJournal.Read(call.Context.ContextId);
                        if(latest==null || (string)latest["operationToken"]!=(string)call.Root["operationToken"]
                            || (string)latest["currentAttempt"]?["saveAttemptId"]!=call.Attempt) {
                            suppressOldFailure=true; updated=null;
                        } else if((string)latest["rootOperationState"]=="Confirmed") {
                            updated=latest;suppressOldFailure=!(bool)parsed.Outcome["durable"];
                        } else updated=_settingsJournal.ChangeAttempt(call.Context.ContextId,
                            (string)latest["operationToken"],call.Attempt,(long)latest["sequence"],root=> {
                                string apply=(string)parsed.Outcome["applyState"],attempt=(string)parsed.Outcome["attemptState"];
                                bool confirmed=(bool)parsed.Outcome["durable"];
                                root["rootOperationState"]=confirmed ? "Confirmed" : apply=="not_applied" ? "NotApplied" : apply=="applied" ? "AppliedUnconfirmed" : "Unknown";
                                if(apply=="applied" && root["targetRevision"].Type==JTokenType.Null)
                                    root["targetRevision"]=(long)root["baseRevision"]+1;
                                root["confirmation"]=confirmed ? parsed.Outcome["confirmation"].DeepClone() : new JValue("none");
                                root["currentAttempt"]["dispatchPhase"]="Returned";
                                root["currentAttempt"]["attemptOutcome"]=confirmed ? "Confirmed" : attempt=="not_sent" ? "NotSent" : attempt=="returned_unconfirmed" ? "ReturnedUnconfirmed" : "Unknown";
                            });
                    } catch { metadataOk=false; }
                }
                AuthorityOnUi(()=> {
                    if(call.Write || call.Command=="reconcile") {
                        bool known=updated!=null && (string)updated["rootOperationState"] is "Confirmed" or "AppliedUnconfirmed" or "NotApplied" or "NotSent";
                        if(metadataOk && known && !parsed.RequiresReconcile && !suppressOldFailure && _authorityControlPending)SendAuthorityGate(call,"release");
                        else if(!metadataOk)SendAuthorityGate(call,"hold");
                    }
                    lock(_lock)if(IsCurrentAuthorityCall(call) && (!call.Write || call.Id==_authorityWriteId)) {
                        if(call.Write || call.Command=="reconcile")_metadataBlocked=!metadataOk;
                        if(call.Write || call.Command=="reconcile") { _nonPreviewWritePending=false;_authorityBusy=false; }
                        bool wouldDowngrade=_authorityState!=null && parsed.State!=null && (string)_authorityState["stateToken"]==(string)parsed.State["stateToken"]
                            && (bool)_authorityState["durable"] && !(bool)parsed.State["durable"];
                        if(!wouldDowngrade && parsed.State!=null && (_authorityState==null || parsed.Epoch!=_authorityEpoch || (long)parsed.State["revision"]>=(long)_authorityState["revision"])) {
                            _authorityState=(JObject)parsed.State.DeepClone();_authorityEpoch=parsed.Epoch;
                            if(parsed.Snapshot!=null)_authoritySnapshot=(JObject)parsed.Snapshot.DeepClone();
                        }
                        if(updated!=null && (call.Write || call.Command=="reconcile"))_authorityRoot=(JObject)updated.DeepClone();
                        if(call.Command=="snapshot" && parsed.Envelope["holdActive"]?.Type==JTokenType.Boolean
                            && !(bool)parsed.Envelope["holdActive"] && !_metadataBlocked && !_requiresReconcile)_authorityControlPending=false;
                        if((call.Write || call.Command=="reconcile") && metadataOk && !parsed.RequiresReconcile)_requiresReconcile=false;
                        else _requiresReconcile|=parsed.RequiresReconcile;
                    }
                    var web=(JObject)parsed.Envelope.DeepClone();web.Remove("task");web["type"]="panel_resp";web["panel"]="settings";web["domain"]="settings";
                    web["cmd"]=call.Command;web["callId"]=call.WebId;web["panelInstanceId"]=call.Panel;
                    if(call.Command is "snapshot" or "reconcile")web["hostPrefs"]=BuildHostPrefs();
                    lock(_lock)if(IsCurrentAuthorityCall(call)) {
                        web["requiresReconcile"]=_requiresReconcile;
                        if(_metadataBlocked)web["writeAdmission"]="blocked_by_metadata";
                        else if(_requiresReconcile)web["writeAdmission"]="blocked_by_operation";
                        else if(_authorityControlPending)web["writeAdmission"]="blocked_by_operation";
                        if((bool)web["requiresReconcile"] || (string)web["writeAdmission"]!="allowed")
                            if(web["state"] is JObject blockedState)blockedState["needsSaveRetry"]=false;
                    }
                    if(!metadataOk) { ((JArray)web["warnings"]).Add("metadata_warning");web["writeAdmission"]="blocked_by_metadata"; }
                    if(metadataOk)RetireSettledAuthorityCalls(call,updated);
                    if(!call.Write || metadataOk && suppressOldFailure)
                        lock(_lock)_authorityCalls.Remove(id);
                    if(!suppressOldFailure)DeliverAuthorityResponse(call,web.ToString(Formatting.None));
                });
            });
            return true;
        }
        private static bool ValidAuthorityEpoch(string epoch,string prefix)
        {
            return epoch.StartsWith(prefix+".",StringComparison.Ordinal)
                && long.TryParse(epoch.Substring(prefix.Length+1),out long generation) && generation>0;
        }
    }
}
