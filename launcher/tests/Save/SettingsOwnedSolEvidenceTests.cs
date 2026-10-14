using System;
using System.IO;
using CF7Launcher.Save;
using Newtonsoft.Json.Linq;
using Xunit;

namespace CF7Launcher.Tests.Save
{
    public sealed class OwnedSettingsSolFactAttribute : FactAttribute
    {
        public OwnedSettingsSolFactAttribute()
        {
            if(string.IsNullOrEmpty(Environment.GetEnvironmentVariable("CF7_OWNED_SETTINGS_SOL_FIXTURE")))
                Skip="Requires this run's CS6 native owned-SOL fixture; scripts/run-settings-sol-boundary-tests.ps1";
        }
    }
    public sealed class SettingsOwnedSolEvidenceTests
    {
        private static JObject Fixture()
        {
            string file=Environment.GetEnvironmentVariable("CF7_OWNED_SETTINGS_SOL_FIXTURE");
            var value=JObject.Parse(File.ReadAllText(file));
            Assert.Matches(@"\Acf7_env_set_[0-9a-f]{20}\z",(string)value["slot"]);
            string dll=Path.Combine((string)value["installRoot"],"launcher","bin","Release","sol_parser.dll");
            Assert.True(File.Exists(dll),"Built native SOL parser is required");
            System.Runtime.InteropServices.NativeLibrary.Load(dll);
            File.WriteAllText(Path.Combine((string)value["evidenceDirectory"],"native-parser-identity.json"),
                new JObject { ["path"]=dll,["sha256"]=Convert.ToHexString(System.Security.Cryptography.SHA256.HashData(File.ReadAllBytes(dll))).ToLowerInvariant() }.ToString());
            return value;
        }
        [OwnedSettingsSolFact]
        public void NativeParserReadsActualFrozenPayloadReceiptAndUnknownFields()
        {
            var cfg=Fixture();var context=new SettingsSaveContext((string)cfg["installRoot"],(string)cfg["swfPath"],(string)cfg["slot"]);
            var reader=new SettingsRawSolReader(new SolFileLocator(),new NativeSolParser(),Path.Combine((string)cfg["evidenceDirectory"],"raw"));
            var observed=reader.Read(context);
            Assert.True(observed.Available,observed.Error);Assert.Equal((string)cfg["canonical"],observed.Canonical);
            Assert.Equal((string)cfg["settingsDigest"],observed.Digest);
            var parsed=new NativeSolParser().Parse(observed.SnapshotPath);
            Assert.Equal(SolParseResult.RC_OK,parsed.ReturnCode);
            Assert.Equal(9,(double)parsed.Data["__ownedTop"]["value"]);
            Assert.Equal(7,(double)parsed.Data["test"]["ext"]["__ownedUnknown"]["value"]);
            Assert.Equal(2,(double)parsed.Data["test"]["ext"]["ownProbe"]["value"]);
            Assert.Equal(2,(double)parsed.Data["test"]["infrastructure"]["__unknownCounter"]);
        }
        [OwnedSettingsSolFact]
        public void FreshHostRecoveryMatchesSameNativeReceiptAndCannotBorrowAnotherContext()
        {
            var cfg=Fixture();
            using var journal=new SettingsWriteJournal(Path.Combine((string)cfg["evidenceDirectory"],"journal"));
            var reader=new SettingsRawSolReader(new SolFileLocator(),new NativeSolParser(),Path.Combine((string)cfg["evidenceDirectory"],"raw"));
            var gate=new SettingsRecoveryGate(journal,reader,(string)cfg["installRoot"],(string)cfg["swfPath"]);
            var result=gate.Inspect((string)cfg["slot"]);
            Assert.True(result.Allowed,result.Error);Assert.Equal("cold_read_exact",result.RecoveryConfirmation);
            Assert.Equal("Confirmed",(string)result.Record["rootOperationState"]);Assert.Equal(1,(long)result.Record["targetRevision"]);
            Assert.Equal((string)cfg["metadata"]["saveOwnerId"],result.Owner);
            Assert.NotEqual((string)cfg["metadata"]["authorityEpoch"],result.Epoch);
            var observed=reader.Read(result.Context);var wrong=(JObject)result.Record.DeepClone();wrong["saveOwnerId"]="owner.foreign";
            Assert.False(SettingsRawSolReader.MatchesReceipt(observed,wrong,journal));
        }
    }
}
