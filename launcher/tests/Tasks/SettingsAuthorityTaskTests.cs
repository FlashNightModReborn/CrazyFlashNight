using System;
using System.Collections.Concurrent;
using System.IO;
using System.Linq;
using System.Threading;
using System.Threading.Tasks;
using CF7Launcher.Config;
using CF7Launcher.Save;
using CF7Launcher.Tasks;
using CF7Launcher.Tests.Save;
using Newtonsoft.Json;
using Newtonsoft.Json.Linq;
using Xunit;

namespace CF7Launcher.Tests.Tasks
{
    public sealed class SettingsAuthorityTaskTests
    {
        private sealed class Harness : IDisposable
        {
            internal readonly string DirectoryPath=Path.Combine(Path.GetTempPath(),"cf7-settings-authority-"+Guid.NewGuid().ToString("N"));
            internal readonly ConcurrentQueue<JObject> Flash=new(),Web=new();
            internal readonly SettingsWriteJournal Journal;
            internal readonly SettingsTask Task;
            internal readonly SettingsSaveContext Context;
            internal bool SendResult=true,FailTerminal,FailPrepared,FailWebDelivery;
            internal Harness(int timeout=10000)
            {
                Journal=new SettingsWriteJournal(DirectoryPath,(path,text)=> {
                    if(FailTerminal && text.Contains("\"rootOperationState\":\"Confirmed\""))throw new IOException("owned metadata injection");
                    if(FailPrepared && text.Contains("\"rootOperationState\":\"Prepared\""))throw new IOException("owned prepare injection");
                    DurableFileWriter.WriteAllText(path,text,new System.Text.UTF8Encoding(false));
                });
                Context=new SettingsSaveContext(DirectoryPath,"owned.swf","cf7_agent_settings");
                Task=new SettingsTask(()=>true,message=> { Flash.Enqueue(JObject.Parse(message.TrimEnd('\0')));return SendResult; },
                    new UserPrefs(DirectoryPath,DirectoryPath),()=>true,timeout);
                Task.SetPostToWeb(json=>Web.Enqueue(JObject.Parse(json)));
                Task.SetAuthorityResponseLeaseProvider(()=> {
                    string panel=Task.PanelInstanceId;
                    return json=> { if(FailWebDelivery)throw new InvalidOperationException("owned UI delivery failure");
                        if(Task.PanelInstanceId==panel)Web.Enqueue(JObject.Parse(json)); };
                });
                Task.ConfigureAuthority(Journal,null);
                Task.BindAuthoritySource(new SettingsRecoveryAdmission { Context=Context,Allowed=true,Owner="owner.fixture",Epoch="vm.fixture" },true);
                Task.BindPanelInstance("settings.A");
            }
            internal void Request(string command,JObject payload,string id)
                =>Task.HandleWebRequest(command,new JObject { ["domain"]="settings",["cmd"]=command,["callId"]=id,
                    ["panelInstanceId"]=Task.PanelInstanceId,["payload"]=payload });
            internal JObject LastFlash()=>Flash.ToArray().Last();
            internal JObject Record()=>Journal.Read(Context.ContextId);
            internal async Task Drain()
            {
                Task observed;
                do { observed=Task.DrainAuthorityIoForTests();await observed; }
                while(!ReferenceEquals(observed,Task.DrainAuthorityIoForTests()));
            }
            internal async Task Snapshot(string id="web.snapshot")
            {
                Request("snapshot",new JObject { ["v"]=1 },id);
                Reply(LastFlash(),"snapshot",false);await Drain();
            }
            internal JObject ApplyPayload()
            {
                var vector=SettingsCanonicalTests.Vector();
                return new JObject { ["v"]=1,["keySchemaVersion"]=2,["expectedRevision"]=7,["settings"]=vector.settings,["keys"]=vector.keys };
            }
            internal void Reply(JObject request,string command,bool confirmed,bool applied=true,long? revisionOverride=null)
            {
                var vector=SettingsCanonicalTests.Vector();
                bool target=command is "apply" or "save" or "reconcile";
                string token=target ? (string)request["operationToken"] : "base.fixture";
                var response=SettingsV2ResponseTests.SaveResponse();
                response["operation"]=command;response["callId"]=request["callId"].DeepClone();
                response["contextId"]=Context.ContextId;response["saveOwnerId"]="owner.fixture";response["authorityEpoch"]="vm.fixture.1";
                response["success"]=!target || confirmed;response["state"]["stateToken"]=token;
                response["holdActive"]=false;
                response["state"]["revision"]=revisionOverride ?? (target ? 8 : 7);
                response["state"]["durable"]=confirmed;response["state"]["persistenceState"]=confirmed ? "confirmed" : "unconfirmed";
                response["state"]["confirmation"]=confirmed ? "flush_true" : "none";
                response["state"]["needsSaveRetry"]=target && !confirmed;
                var outcome=(JObject)response["outcome"];
                if(target) {
                    outcome["operationToken"]=token;outcome["targetStateToken"]=token;
                    outcome["sourceAuthorityEpoch"]=request["sourceAuthorityEpoch"]?.DeepClone() ?? request["authorityEpoch"].DeepClone();
                    outcome["originMutationRequestDigest"]=request["originMutationRequestDigest"].DeepClone();outcome["saveAttemptId"]=request["saveAttemptId"].DeepClone();
                    outcome["durable"]=confirmed;outcome["confirmation"]=confirmed ? "flush_true" : "none";
                    outcome["attemptState"]=confirmed ? "confirmed" : "returned_unconfirmed";outcome["error"]=confirmed ? JValue.CreateNull() : new JValue("save_failed");
                } else {
                    foreach(var field in new[] {"operationToken","sourceAuthorityEpoch","originMutationRequestDigest","targetStateToken","saveAttemptId","applied"})outcome[field]=JValue.CreateNull();
                    outcome["applyState"]="none";outcome["attemptState"]="none";outcome["resolution"]="none";outcome["error"]=JValue.CreateNull();
                }
                if(command!="save") {
                    for(int i=0;i<vector.keys.Count;i++) { vector.keys[i]["index"]=i;vector.keys[i]["label"]="label";vector.keys[i]["keyName"]="key"; }
                    response["snapshot"]=new JObject { ["keySchemaVersion"]=2,["revision"]=response["state"]["revision"].DeepClone(),
                        ["settings"]=vector.settings,["keys"]=vector.keys,["defaultKeys"]=vector.keys.DeepClone(),
                        ["allowedKeyCodes"]=new JArray(vector.keys.Select(k=>new JObject { ["code"]=k["keyCode"].DeepClone(),["name"]="key" })),
                        ["challengeMode"]=false,["modeLabel"]="standard",["cheatHelp"]=new JArray(),["previewActive"]=false,["keyMigrationNotice"]="",
                        ["forceControls"]=new JObject { ["returnBaseAvailable"]=false,["tryReviveAvailable"]=false,["resurrectionRestricted"]=false } };
                }
                Task.HandleFlashResponse(response,null);
            }
            public void Dispose() { Task.Dispose();Task.DrainAuthorityIoForTests().GetAwaiter().GetResult();Journal.Dispose(); }
        }
        [Fact] public async Task ReliableDispatchPrecedesTransportAndSaveOnlyKeepsOriginalIntent()
        {
            using var h=new Harness();await h.Snapshot();
            h.Request("apply",h.ApplyPayload(),"web.apply");await h.Drain();
            var apply=h.LastFlash();Assert.Equal("Dispatching",(string)h.Record()["currentAttempt"]["dispatchPhase"]);
            h.Reply(apply,"apply",false);await h.Drain();Assert.Equal("AppliedUnconfirmed",(string)h.Record()["rootOperationState"]);
            h.Request("save",new JObject { ["v"]=1 },"web.save");await h.Drain();var save=h.LastFlash();
            Assert.Equal("settingsSave",(string)save["action"]);Assert.Null(save["settings"]);Assert.Null(save["keys"]);
            Assert.Equal((string)apply["operationToken"],(string)save["operationToken"]);
            Assert.NotEqual((string)apply["saveAttemptId"],(string)save["saveAttemptId"]);
            h.Reply(save,"save",true);await h.Drain();Assert.Equal("Confirmed",(string)h.Record()["rootOperationState"]);
            Assert.Equal(0,h.Task.RetainedAuthorityCallsForTests);
        }
        [Fact] public async Task TransportFalseIsUnknownAndSuccessfulOrdinarySnapshotCannotUnlock()
        {
            using var h=new Harness();await h.Snapshot();h.SendResult=false;
            h.Request("apply",h.ApplyPayload(),"web.apply");await h.Drain();await h.Drain();
            Assert.Equal("Unknown",(string)h.Record()["rootOperationState"]);
            h.SendResult=true;await h.Snapshot("web.snapshot.after");
            var snapshot=h.Web.ToArray().Last();Assert.True((bool)snapshot["requiresReconcile"]);
            Assert.Equal("blocked_by_operation",(string)snapshot["writeAdmission"]);
            int sent=h.Flash.Count;h.Request("save",new JObject { ["v"]=1 },"web.blocked");Assert.Equal(sent,h.Flash.Count);
        }
        [Fact] public async Task PreparedMetadataFailureStillClosesSourceWritersWithoutDispatchingBusiness()
        {
            using var h=new Harness();await h.Snapshot();h.FailPrepared=true;
            h.Request("apply",h.ApplyPayload(),"web.prepare.failure");await h.Drain();
            Assert.DoesNotContain(h.Flash,m=>(string)m["action"]=="settingsApply");
            var hold=h.LastFlash();Assert.Equal("settingsAuthorityGate",(string)hold["action"]);Assert.Equal("hold",(string)hold["admission"]);
            Assert.True(SettingsCanonical.IsOpaque((string)hold["operationToken"]));Assert.True(h.Task.HasUnresolvedAuthority);
            Assert.Equal(0,h.Task.RetainedAuthorityCallsForTests);
            await h.Snapshot("web.after.prepare.failure");
            Assert.Equal("blocked_by_metadata",(string)h.Web.ToArray().Last()["writeAdmission"]);
        }
        [Fact] public async Task LateSuccessSettlesOriginalJournalAndCannotEnterReplacementPanel()
        {
            using var h=new Harness();await h.Snapshot();h.Request("apply",h.ApplyPayload(),"web.apply");await h.Drain();
            var apply=h.LastFlash();h.Task.BindPanelInstance("settings.B");int before=h.Web.Count;
            Assert.Equal(1,h.Task.RetainedAuthorityCallsForTests);
            h.Reply(apply,"apply",true);await h.Drain();
            Assert.Equal("Confirmed",(string)h.Record()["rootOperationState"]);Assert.Equal(before,h.Web.Count);
            Assert.Equal(0,h.Task.RetainedAuthorityCallsForTests);
        }
        [Fact] public async Task ConfirmedSaveRetiresAllEarlierAttemptsWithoutReplayingApply()
        {
            using var h=new Harness();await h.Snapshot();
            h.Request("apply",h.ApplyPayload(),"web.apply");await h.Drain();var apply=h.LastFlash();
            h.Reply(apply,"apply",false);await h.Drain();
            for(int i=0;i<3;i++) {
                h.Request("save",new JObject { ["v"]=1 },"web.save."+i);await h.Drain();
                h.Reply(h.LastFlash(),"save",i==2);await h.Drain();
            }
            Assert.Equal(0,h.Task.RetainedAuthorityCallsForTests);
            Assert.Single(h.Flash.Where(m=>(string)m["action"]=="settingsApply"));
            long sequence=(long)h.Record()["sequence"];
            h.Reply(apply,"apply",false);await h.Drain();
            Assert.Equal(sequence,(long)h.Record()["sequence"]);
            Assert.Equal("Confirmed",(string)h.Record()["rootOperationState"]);
        }
        [Fact] public async Task UiDeliveryFailureCannotRetainConfirmedCallsOrPoisonNextJournalWork()
        {
            using var h=new Harness();await h.Snapshot();
            h.Request("apply",h.ApplyPayload(),"web.apply");await h.Drain();
            h.FailWebDelivery=true;h.Reply(h.LastFlash(),"apply",true);await h.Drain();
            Assert.Equal("Confirmed",(string)h.Record()["rootOperationState"]);
            Assert.Equal(0,h.Task.RetainedAuthorityCallsForTests);
            h.FailWebDelivery=false;await h.Snapshot("web.next");
            Assert.Equal("web.next",(string)h.Web.ToArray().Last()["callId"]);
            Assert.Equal(0,h.Task.RetainedAuthorityCallsForTests);
        }
        [Fact] public async Task DisposeReleasesCallbacksWithoutErasingUnknownJournal()
        {
            using var h=new Harness();await h.Snapshot();h.SendResult=false;
            h.Request("apply",h.ApplyPayload(),"web.unknown");await h.Drain();
            Assert.Equal(1,h.Task.RetainedAuthorityCallsForTests);
            h.Task.Dispose();await h.Drain();
            Assert.Equal(0,h.Task.RetainedAuthorityCallsForTests);
            Assert.Equal("Unknown",(string)h.Record()["rootOperationState"]);
        }
        [Fact] public async Task SameTargetWrongRevisionCannotConfirmOriginalIntent()
        {
            using var h=new Harness();await h.Snapshot();h.Request("apply",h.ApplyPayload(),"web.bad.revision");await h.Drain();
            h.Reply(h.LastFlash(),"apply",true,revisionOverride:99);await h.Drain();
            Assert.Equal("Unknown",(string)h.Record()["rootOperationState"]);Assert.True(h.Task.HasUnresolvedAuthority);
            Assert.Equal("hold",(string)h.LastFlash()["admission"]);
        }
        [Fact] public async Task TerminalMetadataFailurePreservesDurableAndExactQueryCanFinishIt()
        {
            using var h=new Harness();await h.Snapshot();h.Request("apply",h.ApplyPayload(),"web.apply");await h.Drain();
            var apply=h.LastFlash();h.FailTerminal=true;h.Reply(apply,"apply",true);await h.Drain();
            var result=h.Web.ToArray().Last();Assert.True((bool)result["outcome"]["durable"]);Assert.True((bool)result["state"]["durable"]);
            Assert.Equal("blocked_by_metadata",(string)result["writeAdmission"]);
            Assert.Contains("metadata_warning",((JArray)result["warnings"]).Select(w=>(string)w));
            h.FailTerminal=false;h.Request("reconcile",new JObject { ["v"]=1 },"web.query");h.Reply(h.LastFlash(),"reconcile",true);await h.Drain();
            Assert.Equal("Confirmed",(string)h.Record()["rootOperationState"]);
            await h.Snapshot("web.control.ack");
            Assert.Equal("allowed",(string)h.Web.ToArray().Last()["writeAdmission"]);
        }
    }
}
