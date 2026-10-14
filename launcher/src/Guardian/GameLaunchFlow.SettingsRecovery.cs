using System;
using System.Threading;
using CF7Launcher.Save;
using Newtonsoft.Json.Linq;

namespace CF7Launcher.Guardian
{
    public partial class GameLaunchFlow
    {
        private long _settingsRecoveryRequest;
        private readonly object _settingsRecoveryDispatchLock=new();
        private Action _settingsRecoveryCancel;
        private SettingsRecoveryAdmission _settingsAdmission;
        private bool _settingsBackendV2;
        internal bool SettingsBackendV2=>_settingsBackendV2;
        private string _settingsBoundAttempt;
#if CF7_TEST_SEAMS
        internal Action<Action> SettingsRecoveryUiDispatchForTests;
#endif
        private bool DispatchSettingsRecovery(Action action)
        {
#if CF7_TEST_SEAMS
            if(SettingsRecoveryUiDispatchForTests!=null) { SettingsRecoveryUiDispatchForTests(action);return true; }
#endif
            if(_form==null || _form.IsDisposed || _form.Disposing)return false;
            return RunOnUiNextTick(action);
        }
        private long NewSettingsRecoveryRequest(Action cancel=null)
        {
            Action previous;long request;
            lock(_settingsRecoveryDispatchLock) {
                previous=_settingsRecoveryCancel;_settingsRecoveryCancel=cancel;
                request=Interlocked.Increment(ref _settingsRecoveryRequest);
            }
            previous?.Invoke();return request;
        }
        internal async System.Threading.Tasks.Task<(bool ok,string attempt,string slot,string error)> OpenCharacterCreateWithRecoveryAsync(
            string mode,string slot,string openRequest)
        {
            if(_saveCtx?.SettingsRecovery==null) {
                bool ok=OpenCharacterCreate(mode,slot,openRequest,out string attempt,out string exact,out string error);
                return (ok,attempt,exact,error);
            }
            if(!TryValidateCharacterCreateOpenRequestId(openRequest,out _))return (false,null,slot,"open_request_id_invalid");
            if(mode is not ("new" or "rebuild"))return (false,null,slot,"invalid_mode");
            if(mode=="new" && !string.IsNullOrEmpty(slot))return (false,null,slot,"new_slot_key_must_be_host_generated");
            if(mode=="rebuild" && !SaveSlotKey.IsValidExisting(slot))return (false,null,slot,"invalid_slot_key");
            lock(_stateLock) {
                if(_prewarmAborting || _pendingSlot!=null || _state is not (State.Idle or State.WaitingConnect
                    or State.WaitingHandshake or State.PrewarmHandshakeHeld))return (false,null,slot,"not_idle");
            }
            var completion=new System.Threading.Tasks.TaskCompletionSource<(bool,string,string,string)>(System.Threading.Tasks.TaskCreationOptions.RunContinuationsAsynchronously);
            Action cancel=()=>completion.TrySetResult((false,null,slot,"launch_cancelled"));
            long request=NewSettingsRecoveryRequest(cancel);
            EventHandler ended=(_,_)=>cancel();
            var owner=_form;
            try {
                if(owner!=null) { owner.Disposed+=ended;owner.HandleDestroyed+=ended; }
                var checkedContext=await System.Threading.Tasks.Task.Run(()=> {
                    string target=slot;
                    if(mode=="new" && !TryCreateUnusedSlotKey(out target,out string error))return (admission:(SettingsRecoveryAdmission)null,error);
                    return (admission:_saveCtx.SettingsRecovery.Inspect(target),error:(string)null);
                }).ConfigureAwait(false);
                if(completion.Task.IsCompleted)return await completion.Task.ConfigureAwait(false);
                if(!DispatchSettingsRecovery(()=> {
                    try {
                        if(completion.Task.IsCompleted || request!=Interlocked.Read(ref _settingsRecoveryRequest)) { cancel();return; }
                        if(checkedContext.admission==null || !checkedContext.admission.Allowed) {
                            completion.TrySetResult((false,null,slot,checkedContext.error ?? checkedContext.admission?.Error ?? "settings_recovery_required"));return;
                        }
                        _settingsAdmission=checkedContext.admission.AsReplacement();
                        bool ok=OpenCharacterCreate(mode,slot,openRequest,out string attempt,out string exact,out string error,true,
                            mode=="new" ? checkedContext.admission.Context.Slot : null);
                        completion.TrySetResult((ok,attempt,exact,error));
                    } catch { completion.TrySetResult((false,null,slot,"settings_launch_failed")); }
                }))cancel();
                return await completion.Task.ConfigureAwait(false);
            } catch { return (false,null,slot,"settings_metadata_unavailable"); }
            finally {
                if(owner!=null) { owner.Disposed-=ended;owner.HandleDestroyed-=ended; }
                lock(_settingsRecoveryDispatchLock)if(ReferenceEquals(_settingsRecoveryCancel,cancel))_settingsRecoveryCancel=null;
            }
        }
        internal event Action<SettingsRecoveryAdmission,bool> SettingsSourceBound;
        private void BeginSettingsRecovery(string slot,Action continueLaunch,bool replacement=false)
        {
            long request=NewSettingsRecoveryRequest();
            _=InspectSettingsBeforeLaunch(slot,request,continueLaunch,replacement);
        }
        private async System.Threading.Tasks.Task InspectSettingsBeforeLaunch(string slot,long request,Action continueLaunch,bool replacement)
        {
            SettingsRecoveryAdmission admission;
            try { admission=await _saveCtx.SettingsRecovery.InspectAsync(slot).ConfigureAwait(false); }
            catch { RunOnUi(()=> { if(request==Interlocked.Read(ref _settingsRecoveryRequest))TransitionToError("settings_metadata_unavailable"); });return; }
            DispatchSettingsRecovery(()=> {
                if(request!=Interlocked.Read(ref _settingsRecoveryRequest))return;
                _settingsAdmission=replacement && admission.Allowed ? admission.AsReplacement() : admission;
                if(!admission.Allowed) { lock(_stateLock)TransitionToError(admission.Error ?? "settings_recovery_required");return; }
                continueLaunch();
            });
        }
        private void ReadSettingsCapabilities(JObject message)
        {
            var payload=message?["payload"] as JObject ?? message;
            var versions=payload?["settingsProtocolVersions"] as JArray;
            _settingsBackendV2=versions!=null && versions.Count<=4 && versions.Count>0
                && SettingsCanonical.Integer(payload["settingsReceiptSchema"],1,1,false,out _)
                && SettingsCanonical.Integer(payload["settingsCanonicalSchema"],1,1,false,out _);
            bool version2=false;
            var seen=new System.Collections.Generic.HashSet<long>();
            if(versions!=null)foreach(var version in versions) {
                if(!SettingsCanonical.Integer(version,1,2,false,out long parsed) || !seen.Add(parsed)) { _settingsBackendV2=false;break; }
                if(parsed==2)version2=true;
            }
            _settingsBackendV2&=version2;
        }
    }
}
