using System;
using System.IO;
using System.Security.Cryptography;
using Newtonsoft.Json.Linq;

namespace CF7Launcher.Save
{
    internal sealed class SettingsRawSolObservation
    {
        internal string SourcePath,SnapshotPath,SourceSha256,Canonical,Digest,Error;
        internal JObject Receipt;
        internal bool Available=>Error==null && Canonical!=null;
    }
    /// <summary>Copies immutable raw bytes before parsing; it never invokes Resolver, migration or shadow recovery.</summary>
    internal sealed class SettingsRawSolReader
    {
        private readonly ISolFileLocator _locator;
        private readonly ISolParser _parser;
        private readonly string _evidenceDirectory;
        internal SettingsRawSolReader(ISolFileLocator locator,ISolParser parser,string evidenceDirectory)
        { _locator=locator; _parser=parser; _evidenceDirectory=Path.GetFullPath(evidenceDirectory); }
        internal SettingsRawSolObservation Read(SettingsSaveContext context)
        {
            var result=new SettingsRawSolObservation();
            try {
                string source=_locator is SolFileLocator exact ? exact.FindUnambiguousRawSol(context.Slot,context.SwfPath)
                    : _locator.FindSolFile(context.Slot,context.SwfPath);
                if(source==null) { result.Error="raw_sol_unavailable"; return result; }
                byte[] bytes;
                using(var stream=new FileStream(source,FileMode.Open,FileAccess.Read,FileShare.Read)) {
                    if(stream.Length>16*1024*1024)throw new InvalidDataException("Raw SOL exceeds read budget");
                    bytes=new byte[checked((int)stream.Length)]; stream.ReadExactly(bytes);
                }
                result.SourcePath=Path.GetFullPath(source);
                result.SourceSha256=Convert.ToHexString(SHA256.HashData(bytes)).ToLowerInvariant();
                Directory.CreateDirectory(_evidenceDirectory);
                result.SnapshotPath=Path.Combine(_evidenceDirectory,"raw-"+Guid.NewGuid().ToString("N")+".sol");
                using(var output=new FileStream(result.SnapshotPath,FileMode.CreateNew,FileAccess.Write,FileShare.None)) {
                    output.Write(bytes);output.Flush(true);
                }
                var parsed=_parser.Parse(result.SnapshotPath);
                if(parsed.ReturnCode!=SolParseResult.RC_OK || parsed.Data?["test"] is not JObject mydata) {
                    result.Error="raw_sol_parse_failed";return result;
                }
                // Preserve the receipt even when its payload cannot be canonicalized; a future schema still blocks writes.
                result.Receipt=mydata["ext"]?["settingsReceipt"] is JObject receipt ? (JObject)receipt.DeepClone() : null;
                if(!SettingsCanonical.TryEncodeRawSave(mydata,out result.Canonical)) { result.Error="raw_projection_not_canonical";return result; }
                result.Digest=SettingsCanonical.Digest(result.Canonical);
                return result;
            } catch { result.Error="raw_sol_read_unavailable"; return result; }
        }
        internal static bool MatchesReceipt(SettingsRawSolObservation observed,JObject record,SettingsWriteJournal journal)
        {
            try {
                var r=observed.Receipt;
                if(!observed.Available || r==null || r.Count!=12
                    || !SettingsCanonical.Integer(r["schema"],1,1,true,out _) || !SettingsCanonical.Integer(r["digestSchema"],1,1,true,out _)
                    || !SettingsCanonical.Integer(r["revision"],0,SettingsCanonical.MaxSafeInteger,true,out long revision))return false;
                foreach(var field in new[] {"contextId","saveOwnerId","originNamespaceDigest","sourceAuthorityEpoch","operationToken",
                    "originMutationRequestDigest","settingsDigest"})
                    if(r[field]?.Type!=JTokenType.String || (string)r[field]!=(string)record[field])return false;
                if(r["stateToken"]?.Type!=JTokenType.String || (string)r["stateToken"]!=(string)record["targetStateToken"]
                    || r["saveAttemptId"]?.Type!=JTokenType.String || !SettingsCanonical.IsOpaque((string)r["saveAttemptId"])
                    || !journal.HasExactAttempt(record,(string)r["saveAttemptId"]) || observed.Digest!=(string)record["settingsDigest"]
                    || revision!=(long)record["baseRevision"]+1
                    || record["targetRevision"].Type!=JTokenType.Null && revision!=(long)record["targetRevision"])return false;
                return true;
            } catch { return false; }
        }
    }
}
