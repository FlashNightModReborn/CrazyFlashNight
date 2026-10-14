using System;
using System.IO;
using System.Threading.Tasks;
using CF7Launcher.Save;
using Newtonsoft.Json.Linq;
using Xunit;

namespace CF7Launcher.Tests.Save
{
    public class SettingsRecoveryGateTests : IDisposable
    {
        private readonly string _root=Path.Combine(Path.GetTempPath(),"cf7-settings-recovery-"+Guid.NewGuid().ToString("N"));
        private sealed class MissingLocator : ISolFileLocator { internal int Reads; public string FindSolFile(string slot,string swf){ Reads++;return null; } }
        private sealed class RejectParser : ISolParser { public SolParseResult Parse(string path)=>throw new InvalidOperationException("No SOL should be parsed"); }
        public void Dispose() {
            string resolved=Path.GetFullPath(_root),temporary=Path.GetFullPath(Path.GetTempPath());
            if(resolved.StartsWith(temporary,StringComparison.OrdinalIgnoreCase) && Path.GetFileName(resolved).StartsWith("cf7-settings-recovery-",StringComparison.Ordinal)
                && Directory.Exists(resolved))Directory.Delete(resolved,true);
        }
        [Fact] public async Task PreparedOnlyProvesNotSentWithoutLaunchingOrReadingSol()
        {
            using var journal=new SettingsWriteJournal(_root); var locator=new MissingLocator();
            var gate=new SettingsRecoveryGate(journal,new SettingsRawSolReader(locator,new RejectParser(),Path.Combine(_root,"raw")),_root,"owned.swf");
            var context=gate.Context("cf7_agent_recovery");
            journal.Prepare(new SettingsWriteIntent(context,"owner","vm","op","base",7,new string('a',64)),"save.1");
            var result=await gate.InspectAsync(context.Slot);
            Assert.True(result.Allowed); Assert.Equal("NotSent",(string)result.Record["rootOperationState"]); Assert.Equal(0,locator.Reads);
        }
        [Fact] public async Task DispatchingWithoutExactReceiptStaysBlockedAndDoesNotAffectAnotherSlot()
        {
            using var journal=new SettingsWriteJournal(_root); var locator=new MissingLocator();
            var gate=new SettingsRecoveryGate(journal,new SettingsRawSolReader(locator,new RejectParser(),Path.Combine(_root,"raw")),_root,"owned.swf");
            var context=gate.Context("cf7_agent_unknown");
            var record=journal.Prepare(new SettingsWriteIntent(context,"owner","vm","op","base",7,new string('a',64)),"save.1");
            journal.ChangeAttempt(context.ContextId,"op","save.1",(long)record["sequence"],r=>r["currentAttempt"]["dispatchPhase"]="Dispatching");
            var result=await gate.InspectAsync(context.Slot);
            Assert.False(result.Allowed); Assert.Equal("settings_operation_unresolved",result.Error); Assert.False(gate.MayWrite(context.Slot));
            Assert.True((await gate.InspectAsync("cf7_agent_other")).Allowed); Assert.Equal(2,locator.Reads);
        }
        [Fact] public async Task RegisteredMissingRecordBlocksInsteadOfCallingResolverOrRepair()
        {
            using var journal=new SettingsWriteJournal(_root); var locator=new MissingLocator();
            var gate=new SettingsRecoveryGate(journal,new SettingsRawSolReader(locator,new RejectParser(),Path.Combine(_root,"raw")),_root,"owned.swf");
            var context=gate.Context("cf7_agent_missing");
            journal.Prepare(new SettingsWriteIntent(context,"owner","vm","op","base",7,new string('a',64)),"save.1");
            File.Delete(Path.Combine(_root,SettingsCanonical.Digest(context.ContextId)+".json"));
            var result=await gate.InspectAsync(context.Slot); Assert.False(result.Allowed); Assert.Equal("settings_metadata_unavailable",result.Error);
            Assert.Equal(0,locator.Reads);
        }
    }
}
