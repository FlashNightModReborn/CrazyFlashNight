using System;
using System.IO;
using System.Linq;
using CF7Launcher.Save;
using Newtonsoft.Json.Linq;
using Xunit;

namespace CF7Launcher.Tests.Save
{
    public class SettingsRawSolReaderTests : IDisposable
    {
        private readonly string _root=Path.Combine(Path.GetTempPath(),"cf7-settings-cold-"+Guid.NewGuid().ToString("N"));
        private sealed class Locator : ISolFileLocator { internal string Path; public string FindSolFile(string slot,string swf)=>Path; }
        private sealed class Parser : ISolParser {
            internal JObject Data; internal string Original; internal bool UsedCopy;
            public SolParseResult Parse(string path) { UsedCopy=path!=Original && File.ReadAllBytes(path).SequenceEqual(File.ReadAllBytes(Original));
                return new SolParseResult { ReturnCode=SolParseResult.RC_OK,Data=(JObject)Data.DeepClone() }; }
        }
        private JObject Data()
        {
            var v=SettingsCanonicalTests.Vector(); var rows=new JArray(v.keys.Select(k=>new JArray("label",k["id"].DeepClone(),k["keyCode"].DeepClone())));
            var actor=new JArray(); for(int i=0;i<=10;i++)actor.Add(i==10 ? rows : JValue.CreateNull());
            return new JObject { ["test"]=new JObject { ["0"]=actor,["others"]=new JObject { ["设置"]=v.settings },["ext"]=new JObject() } };
        }
        private (SettingsRawSolReader reader,SettingsSaveContext context,Parser parser) Fixture()
        {
            Directory.CreateDirectory(_root); string original=Path.Combine(_root,"original.sol"); File.WriteAllBytes(original,new byte[] {1,2,3,4});
            var parser=new Parser {Data=Data(),Original=original};
            return (new SettingsRawSolReader(new Locator { Path=original },parser,Path.Combine(_root,"raw")),
                new SettingsSaveContext(_root,"owned.swf","cf7_agent_cold"),parser);
        }
        public void Dispose() {
            var resolved=Path.GetFullPath(_root); var temporary=Path.GetFullPath(Path.GetTempPath());
            if(resolved.StartsWith(temporary,StringComparison.OrdinalIgnoreCase) && Path.GetFileName(resolved).StartsWith("cf7-settings-cold-",StringComparison.Ordinal)
                && Directory.Exists(resolved))Directory.Delete(resolved,true);
        }
        [Fact] public void ParserReadsOnlyDetachedOriginalBytesWithoutResolverOrNormalization()
        {
            var f=Fixture(); var observed=f.reader.Read(f.context);
            Assert.True(observed.Available); Assert.True(f.parser.UsedCopy); Assert.NotEqual(observed.SourcePath,observed.SnapshotPath);
            Assert.Equal("4fb6357741c1110d8f82c10b1e0c93e09359d1a84e5b81cea42e070d5fdaa13a",observed.Digest);
            Assert.Null(observed.Receipt);
        }
        [Theory][InlineData(1.24)][InlineData(1.25)]
        public void RawZoomIsRejectedInsteadOfRoundedIntoAReceipt(double zoom)
        {
            var f=Fixture(); f.parser.Data["test"]["others"]["设置"]["basicZoomScale"]=zoom;
            var observed=f.reader.Read(f.context); Assert.False(observed.Available); Assert.Equal("raw_projection_not_canonical",observed.Error);
        }
        [Fact] public void ExactReceiptRequiresActualRawPayloadOwnerEpochAndKnownAttempt()
        {
            var f=Fixture(); using var journal=new SettingsWriteJournal(Path.Combine(_root,"journal"));
            SettingsCanonical.TryEncodeRawSave((JObject)f.parser.Data["test"],out var canonical);
            var intent=new SettingsWriteIntent(f.context,"owner.1","vm.1","op.1","base.1",7,SettingsCanonical.Digest(canonical));
            var record=journal.Prepare(intent,"save.1");
            record=journal.ChangeAttempt(intent.Context.ContextId,intent.Operation,"save.1",(long)record["sequence"],
                value=>value["currentAttempt"]["dispatchPhase"]="Dispatching");
            var receipt=new JObject { ["schema"]=1.0,["digestSchema"]=1.0,["revision"]=8.0,["stateToken"]="op.1",["saveAttemptId"]="save.1" };
            foreach(var field in new[] {"contextId","saveOwnerId","originNamespaceDigest","sourceAuthorityEpoch","operationToken","originMutationRequestDigest","settingsDigest"})
                receipt[field]=record[field].DeepClone();
            f.parser.Data["test"]["ext"]["settingsReceipt"]=receipt;
            Assert.True(SettingsRawSolReader.MatchesReceipt(f.reader.Read(f.context),record,journal));
            receipt["saveAttemptId"]="unknown.attempt"; Assert.False(SettingsRawSolReader.MatchesReceipt(f.reader.Read(f.context),record,journal));
            receipt["saveAttemptId"]="save.1"; receipt["saveOwnerId"]="other.owner";
            Assert.False(SettingsRawSolReader.MatchesReceipt(f.reader.Read(f.context),record,journal));
            receipt["saveOwnerId"]="owner.1"; f.parser.Data["test"]["others"]["设置"]["setGlobalVolume"]=43;
            Assert.False(SettingsRawSolReader.MatchesReceipt(f.reader.Read(f.context),record,journal));
        }
        [Fact] public void UnknownReceiptSchemaIsPreservedAndCannotConfirm()
        {
            var f=Fixture(); var unknown=new JObject { ["schema"]=77,["future"]="preserve" };
            f.parser.Data["test"]["ext"]["settingsReceipt"]=unknown;
            var observed=f.reader.Read(f.context); Assert.True(JToken.DeepEquals(unknown,observed.Receipt));
        }
        [Fact] public void HistoricalReceiptRecoveryKeepsItsAttemptWithoutRewritingLatestJournalIdentity()
        {
            var f=Fixture();using var journal=new SettingsWriteJournal(Path.Combine(_root,"journal"));
            SettingsCanonical.TryEncodeRawSave((JObject)f.parser.Data["test"],out string canonical);
            var intent=new SettingsWriteIntent(f.context,"owner.1","vm.1","op.1","base.1",7,SettingsCanonical.Digest(canonical));
            var record=journal.Prepare(intent,"save.original");
            record=journal.ChangeAttempt(f.context.ContextId,"op.1","save.original",(long)record["sequence"],r=> {
                r["rootOperationState"]="AppliedUnconfirmed";r["targetRevision"]=8;
                r["currentAttempt"]["dispatchPhase"]="Returned";r["currentAttempt"]["attemptOutcome"]="ReturnedUnconfirmed";
            });
            var receipt=new JObject { ["schema"]=1.0,["digestSchema"]=1.0,["revision"]=8.0,["stateToken"]="op.1",["saveAttemptId"]="save.original" };
            foreach(string field in new[] { "contextId","saveOwnerId","originNamespaceDigest","sourceAuthorityEpoch","operationToken","originMutationRequestDigest","settingsDigest" })
                receipt[field]=record[field].DeepClone();
            f.parser.Data["test"]["ext"]["settingsReceipt"]=receipt;
            journal.PrepareSave(f.context.ContextId,"op.1",(long)record["sequence"],"save.retry.prepared","vm.1");
            var gate=new SettingsRecoveryGate(journal,f.reader,_root,"owned.swf");var admission=gate.Inspect(f.context.Slot);
            Assert.True(admission.Allowed,admission.Error);Assert.Equal("cold_read_exact",admission.RecoveryConfirmation);
            Assert.Equal("save.retry.prepared",(string)admission.Record["currentAttempt"]["saveAttemptId"]);
            Assert.Equal("save.original",(string)admission.BootstrapMetadata()["recoveryMapping"]["currentAttempt"]["saveAttemptId"]);
            Assert.Equal(8,(long)admission.BootstrapMetadata()["recoveryMapping"]["targetRevision"]);
        }
        [Fact] public void FutureReceiptStillBlocksBeforeLaunchWhenRawSettingsCannotBeCanonicalized()
        {
            var f=Fixture();using var journal=new SettingsWriteJournal(Path.Combine(_root,"journal"));
            f.parser.Data["test"]["others"]["设置"]["basicZoomScale"]=1.25;
            f.parser.Data["test"]["ext"]["settingsReceipt"]=new JObject { ["schema"]=77,["future"]="preserve" };
            var gate=new SettingsRecoveryGate(journal,f.reader,_root,"owned.swf");var admission=gate.Inspect(f.context.Slot);
            Assert.False(admission.Allowed);Assert.Equal("settings_receipt_schema_unsupported",admission.Error);
            Assert.Equal(77,(int)admission.Observation.Receipt["schema"]);Assert.False(gate.MayWrite(f.context.Slot));
        }
    }
}
