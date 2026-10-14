using System;
using System.Collections.Generic;
using System.Globalization;
using System.Linq;
using System.Security.Cryptography;
using System.Text;
using System.Text.RegularExpressions;
using Newtonsoft.Json.Linq;

namespace CF7Launcher.Save
{
    /// <summary>Encodes an already canonical projection; admission quantization happens elsewhere.</summary>
    internal static class SettingsCanonical
    {
        internal const long MaxSafeInteger=9007199254740991;
        private static readonly Regex Opaque=new("\\A[A-Za-z0-9._~-]{1,160}\\z",RegexOptions.CultureInvariant);
        private static readonly Regex Hex=new("\\A[0-9a-f]{64}\\z",RegexOptions.CultureInvariant);
        internal static bool IsOpaque(string value)=>value!=null && Opaque.IsMatch(value);
        internal static bool IsDigest(string value)=>value!=null && Hex.IsMatch(value);
        internal static string Digest(string canonical)=>Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes(canonical))).ToLowerInvariant();
        internal static bool Integer(JToken value,long minimum,long maximum,bool rawAmf,out long number)
        {
            number=0;
            try {
                if(value?.Type==JTokenType.Integer) {
                    decimal candidate=value.Value<decimal>();
                    if(candidate<minimum || candidate>maximum)return false;
                    number=(long)candidate; return true;
                }
                if(rawAmf && value?.Type==JTokenType.Float) {
                    double candidate=value.Value<double>();
                    if(!double.IsFinite(candidate) || Math.Truncate(candidate)!=candidate || candidate<minimum || candidate>maximum)return false;
                    number=(long)candidate; return true;
                }
            } catch { }
            return false;
        }
        internal static bool TryEncode(JObject settings,JArray keys,bool rawAmf,out string canonical)
        {
            canonical=null;
            try {
                if(settings==null || settings.Count!=14 || keys==null || keys.Count!=36)return false;
                var values=new long[14];
                for(int i=0;i<14;i++) {
                    var value=settings[SettingsCanonicalSchema.Settings[i]];
                    if(SettingsCanonicalSchema.BooleanIndexes.Contains(i)) {
                        if(value?.Type!=JTokenType.Boolean)return false;
                        values[i]=value.Value<bool>() ? 1 : 0;
                    } else if(i==6) {
                        if(value?.Type is not (JTokenType.Integer or JTokenType.Float))return false;
                        double zoom=value.Value<double>();
                        if(!double.IsFinite(zoom) || zoom<0.5 || zoom>3)return false;
                        long tenths=(long)Math.Round(zoom*10);
                        if(zoom!=tenths/10.0)return false;
                        values[i]=tenths;
                    } else if(i==13) {
                        if(value?.Type!=JTokenType.String)return false;
                        int mode=Array.IndexOf(SettingsCanonicalSchema.PlayModes,value.Value<string>());
                        if(mode<0)return false; values[i]=mode;
                    } else if(!Integer(value,i==10 ? 1 : 0,i is 0 or 1 ? 100 : i==10 ? 2 : 1,rawAmf,out values[i]))return false;
                }
                var builder=new StringBuilder("cf7.settings.payload.v1");
                for(int i=0;i<14;i++)builder.Append("|s").Append(i).Append('=').Append(values[i].ToString(CultureInfo.InvariantCulture));
                var seen=new HashSet<long>();
                for(int i=0;i<36;i++) {
                    var row=keys[i] as JObject;
                    if(row==null || row["id"]?.Type!=JTokenType.String
                        || row["id"].Value<string>()!=SettingsCanonicalSchema.KeyIds[i]
                        || !Integer(row["keyCode"],0,255,rawAmf,out long code) || !seen.Add(code))return false;
                    builder.Append("|k").Append(i).Append('=').Append(code.ToString(CultureInfo.InvariantCulture));
                }
                canonical=builder.ToString(); return true;
            } catch { return false; }
        }
        internal static string MutationDigest(string context,string owner,string epoch,string operation,string baseState,long revision,string settingsDigest)
        {
            if(!IsOpaque(context)||!IsOpaque(owner)||!IsOpaque(epoch)||!IsOpaque(operation)||!IsOpaque(baseState)
                ||revision<0||revision>MaxSafeInteger||!IsDigest(settingsDigest))throw new ArgumentException("Invalid settings intent identity");
            var builder=new StringBuilder("cf7.settings.apply.v1|");
            foreach(var value in new[] {context,owner,epoch,operation,baseState,revision.ToString(CultureInfo.InvariantCulture),settingsDigest})
                builder.Append(Encoding.UTF8.GetByteCount(value).ToString(CultureInfo.InvariantCulture)).Append(':').Append(value);
            return Digest(builder.ToString());
        }
        internal static bool TryEncodeRawSave(JObject mydata,out string canonical)
        {
            canonical=null;
            try {
            if(mydata?["others"]?["设置"] is not JObject settings || mydata["0"] is not JArray actor
                || actor.Count<=10 || actor[10] is not JArray rows || rows.Count!=36)return false;
            var keys=new JArray();
            foreach(var entry in rows) {
                if(entry is not JArray row || row.Count<3)return false;
                keys.Add(new JObject { ["id"]=row[1].DeepClone(),["keyCode"]=row[2].DeepClone() });
            }
            return TryEncode(settings,keys,true,out canonical);
            } catch { return false; }
        }
    }
}
