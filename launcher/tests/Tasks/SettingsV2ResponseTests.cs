using CF7Launcher.Tasks;
using Newtonsoft.Json.Linq;
using Xunit;

namespace CF7Launcher.Tests.Tasks
{
    public class SettingsV2ResponseTests
    {
        internal static JObject SaveResponse()=>new() {
            ["v"]=2,["task"]="settings_response",["operation"]="save",["callId"]=73,
            ["contextId"]="ctx.demo",["saveOwnerId"]="owner.demo",["authorityEpoch"]="vm.2",
            ["success"]=false,["requiresReconcile"]=false,["writeAdmission"]="allowed",
            ["state"]=new JObject { ["revision"]=8,["stateToken"]="op.1",["persistenceState"]="unconfirmed",
                ["durable"]=false,["confirmation"]="none",["needsSaveRetry"]=true,["migrationPending"]=false },
            ["outcome"]=new JObject { ["operationToken"]="op.1",["sourceAuthorityEpoch"]="vm.2",
                ["originMutationRequestDigest"]="af8bc4415f182363388034e249e8299b8da9534310912787fccb136b8953f31f",
                ["targetStateToken"]="op.1",["saveAttemptId"]="save.2",["applyState"]="applied",["applied"]=true,
                ["attemptState"]="returned_unconfirmed",["durable"]=false,["confirmation"]="none",["error"]="save_failed",["resolution"]="applied" },
            ["snapshot"]=JValue.CreateNull(),["warnings"]=new JArray()
        };
        [Fact] public void AppliedUnconfirmedSaveKeepsItsExactHistoricalFact()
        {
            var response=SaveResponse(); Assert.True(SettingsV2Response.TryParse(response,"save",out var result));
            Assert.True((bool)result.Outcome["applied"]); Assert.False((bool)result.Outcome["durable"]);
            response["outcome"]["applied"]=false; Assert.True((bool)result.Outcome["applied"]);
        }
        [Theory][InlineData("success")][InlineData("requiresReconcile")]
        public void EveryEnvelopeControlRequiresLiteralBoolean(string name)
        {
            var response=SaveResponse(); response[name]="false";
            Assert.False(SettingsV2Response.TryParse(response,"save",out _));
        }
        [Theory][InlineData("durable")][InlineData("needsSaveRetry")][InlineData("migrationPending")]
        public void StateControlsRejectNullAndNumericCoercion(string name)
        {
            var response=SaveResponse(); response["state"][name]=0;
            Assert.False(SettingsV2Response.TryParse(response,"save",out _));
            response["state"][name]=JValue.CreateNull(); Assert.False(SettingsV2Response.TryParse(response,"save",out _));
        }
        [Fact] public void ReconcileAndRetryCannotBothGrantAdmission()
        {
            var response=SaveResponse(); response["requiresReconcile"]=true;
            Assert.False(SettingsV2Response.TryParse(response,"save",out _));
        }
        [Fact] public void ConfirmedOutcomeMayCoexistWithANewerUnconfirmedState()
        {
            var response=SaveResponse(); response["outcome"]["durable"]=true; response["outcome"]["attemptState"]="confirmed";
            response["outcome"]["confirmation"]="flush_true"; response["state"]["stateToken"]="observe.new";
            Assert.True(SettingsV2Response.TryParse(response,"save",out _));
            response["state"]["stateToken"]="op.1"; Assert.False(SettingsV2Response.TryParse(response,"save",out _));
        }
        [Fact] public void UnknownApplyCannotReportFalseAndMissingFieldsNeverDefault()
        {
            var response=SaveResponse(); response["outcome"]["applyState"]="unknown";response["outcome"]["applied"]=false;
            Assert.False(SettingsV2Response.TryParse(response,"save",out _));
            response=SaveResponse(); ((JObject)response["outcome"]).Remove("saveAttemptId");
            Assert.False(SettingsV2Response.TryParse(response,"save",out _));
        }
        [Fact] public void SuccessfulSnapshotRequiresCurrentBodyWhileHistoricalReconcileMayLackObservation()
        {
            var response=SaveResponse();response["operation"]="snapshot";response["success"]=true;
            response["state"]=JValue.CreateNull();response["snapshot"]=JValue.CreateNull();
            response["warnings"]=new JArray("current_authority_unavailable");
            Assert.False(SettingsV2Response.TryParse(response,"snapshot",out _));
            response["operation"]="reconcile";
            Assert.True(SettingsV2Response.TryParse(response,"reconcile",out _));
        }
    }
}
