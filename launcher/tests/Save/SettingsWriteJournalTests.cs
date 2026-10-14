using System;
using System.IO;
using System.Linq;
using CF7Launcher.Save;
using Newtonsoft.Json.Linq;
using Xunit;

namespace CF7Launcher.Tests.Save
{
    public class SettingsWriteJournalTests : IDisposable
    {
        private readonly string _directory=Path.Combine(Path.GetTempPath(),"cf7-settings-journal-"+Guid.NewGuid().ToString("N"));
        private SettingsWriteIntent Intent(string op="op.1")=>new(new SettingsSaveContext(_directory,"owned.swf","cf7_agent_settings"),
            "owner.1","vm.1",op,"base.1",7,new string('a',64));
        public void Dispose() {
            string resolved=Path.GetFullPath(_directory),temporary=Path.GetFullPath(Path.GetTempPath());
            if(resolved.StartsWith(temporary,StringComparison.OrdinalIgnoreCase) && Path.GetFileName(resolved).StartsWith("cf7-settings-journal-",StringComparison.Ordinal)
                && Directory.Exists(resolved))Directory.Delete(resolved,true);
        }
        [Fact] public void PreparedRecordIsDurablyRegisteredAndCarriesNoPlayerProjection()
        {
            using var journal=new SettingsWriteJournal(_directory); var intent=Intent(); var record=journal.Prepare(intent,"save.1");
            Assert.Equal("Prepared",(string)record["rootOperationState"]); Assert.Equal(intent.MutationDigest,(string)record["originMutationRequestDigest"]);
            Assert.DoesNotContain("settingsCanonical",record.ToString()); Assert.Null(record["settings"]);
            Assert.Equal(record.ToString(),journal.Read(intent.Context.ContextId).ToString());
            Assert.Single(Directory.GetFiles(_directory,"contexts.json"));
        }
        [Fact] public void RegisteredMissingOrCorruptRecordCannotBecomeACleanSlot()
        {
            var intent=Intent(); using(var journal=new SettingsWriteJournal(_directory))journal.Prepare(intent,"save.1");
            string record=Directory.GetFiles(_directory,"*.json").Single(x=>Path.GetFileName(x)!="contexts.json");
            File.Delete(record);
            using(var journal=new SettingsWriteJournal(_directory))Assert.Throws<FileNotFoundException>(()=>journal.Read(intent.Context.ContextId));
            File.WriteAllText(record,"{}");
            using(var journal=new SettingsWriteJournal(_directory))Assert.Throws<InvalidDataException>(()=>journal.Read(intent.Context.ContextId));
        }
        [Fact] public void IndexFailureOccursBeforeAnyRootOrDispatchRecord()
        {
            int writes=0;
            using var journal=new SettingsWriteJournal(_directory,(path,text)=> {
                writes++; if(writes==2)throw new IOException("index disk fault");
                DurableFileWriter.WriteAllText(path,text,new System.Text.UTF8Encoding(false));
            });
            Assert.Throws<IOException>(()=>journal.Prepare(Intent(),"save.1"));
            Assert.Single(Directory.GetFiles(_directory,"*.json"));
        }
        [Fact] public void SecondHostCannotAcquireSameJournalWriter()
        {
            using var first=new SettingsWriteJournal(_directory);
            Assert.Throws<IOException>(()=>new SettingsWriteJournal(_directory));
        }
        [Fact] public void RetryNotSentKeepsAppliedRootAndConfirmedCannotDowngrade()
        {
            using var journal=new SettingsWriteJournal(_directory); var intent=Intent(); var r=journal.Prepare(intent,"save.1");
            r=journal.ChangeAttempt(intent.Context.ContextId,intent.Operation,"save.1",(long)r["sequence"],value=> {
                value["targetRevision"]=8; value["rootOperationState"]="AppliedUnconfirmed";
                value["currentAttempt"]["dispatchPhase"]="Returned"; value["currentAttempt"]["attemptOutcome"]="ReturnedUnconfirmed";
            });
            r=journal.PrepareSave(intent.Context.ContextId,intent.Operation,(long)r["sequence"],"save.2","vm.1");
            r=journal.ChangeAttempt(intent.Context.ContextId,intent.Operation,"save.2",(long)r["sequence"],value=> {
                value["currentAttempt"]["dispatchPhase"]="Returned"; value["currentAttempt"]["attemptOutcome"]="NotSent";
            });
            Assert.Equal("AppliedUnconfirmed",(string)r["rootOperationState"]);
            r=journal.ChangeAttempt(intent.Context.ContextId,intent.Operation,"save.2",(long)r["sequence"],value=> {
                value["rootOperationState"]="Confirmed";value["confirmation"]="flush_true";value["currentAttempt"]["attemptOutcome"]="Confirmed";
            });
            Assert.Throws<InvalidOperationException>(()=>journal.ChangeAttempt(intent.Context.ContextId,intent.Operation,"save.2",(long)r["sequence"],
                value=>value["rootOperationState"]="Unknown"));
        }
        [Fact] public void OldAttemptAndSequenceCannotOverwriteANewRetry()
        {
            using var journal=new SettingsWriteJournal(_directory); var intent=Intent(); var r=journal.Prepare(intent,"save.1");
            Assert.Throws<InvalidOperationException>(()=>journal.ChangeAttempt(intent.Context.ContextId,intent.Operation,"save.0",1,value=>{}));
            Assert.Throws<InvalidOperationException>(()=>journal.ChangeAttempt(intent.Context.ContextId,intent.Operation,"save.1",2,value=>{}));
            Assert.Throws<InvalidDataException>(()=>journal.ChangeAttempt(intent.Context.ContextId,intent.Operation,"save.1",1,
                value=>value["saveOwnerId"]="other"));
        }
    }
}
