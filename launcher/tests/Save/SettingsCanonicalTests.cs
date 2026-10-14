using System;
using System.Linq;
using System.Text;
using CF7Launcher.Save;
using Newtonsoft.Json.Linq;
using Xunit;

namespace CF7Launcher.Tests.Save
{
    public class SettingsCanonicalTests
    {
        internal static (JObject settings,JArray keys) Vector()
        {
            long[] s={42,55,1,1,1,1,12,1,0,1,1,0,0,1};
            long[] k={87,83,65,68,74,75,82,49,50,51,52,53,54,55,56,57,48,32,85,73,79,80,76,72,71,67,66,78,77,47,69,70,18,81,16,17};
            var settings=new JObject(); var keys=new JArray();
            for(int i=0;i<14;i++)settings[SettingsCanonicalSchema.Settings[i]]=SettingsCanonicalSchema.BooleanIndexes.Contains(i)
                ? new JValue(s[i]==1) : i==6 ? new JValue(s[i]/10.0) : i==13 ? new JValue(SettingsCanonicalSchema.PlayModes[s[i]]) : new JValue(s[i]);
            for(int i=0;i<36;i++)keys.Add(new JObject { ["id"]=SettingsCanonicalSchema.KeyIds[i],["keyCode"]=k[i] });
            return (settings,keys);
        }
        [Fact] public void FixedPayloadAndMutationMatchIndependentPublishedVectors()
        {
            var v=Vector(); Assert.True(SettingsCanonical.TryEncode(v.settings,v.keys,false,out var canonical));
            Assert.Equal(342,Encoding.UTF8.GetByteCount(canonical));
            string digest=SettingsCanonical.Digest(canonical);
            Assert.Equal("4fb6357741c1110d8f82c10b1e0c93e09359d1a84e5b81cea42e070d5fdaa13a",digest);
            Assert.Equal("af8bc4415f182363388034e249e8299b8da9534310912787fccb136b8953f31f",
                SettingsCanonical.MutationDigest("ctx.demo","owner.demo","vm.2","op.1","base.7",7,digest));
        }
        [Theory][InlineData(1.24)][InlineData(1.25)][InlineData(0.49)][InlineData(3.01)]
        public void EncoderNeverRoundsOrClampsRawZoom(double value)
        {
            var v=Vector(); v.settings["basicZoomScale"]=value;
            Assert.False(SettingsCanonical.TryEncode(v.settings,v.keys,true,out _));
        }
        [Fact] public void AmfNumbersAcceptExactIntegerValuesButWireNumbersStayStrict()
        {
            var v=Vector(); v.settings["setGlobalVolume"]=42.0; v.keys[0]["keyCode"]=87.0;
            Assert.True(SettingsCanonical.TryEncode(v.settings,v.keys,true,out _));
            Assert.False(SettingsCanonical.TryEncode(v.settings,v.keys,false,out _));
            v.keys[0]["keyCode"]=87.5; Assert.False(SettingsCanonical.TryEncode(v.settings,v.keys,true,out _));
        }
        [Theory][InlineData("1")][InlineData("\"true\"")][InlineData("null")]
        public void CanonicalBooleanCannotBeNormalizedFromAnotherType(string text)
        {
            var v=Vector(); v.settings["是否阴影"]=JToken.Parse(text);
            Assert.False(SettingsCanonical.TryEncode(v.settings,v.keys,true,out _));
        }
        [Fact] public void KeysCannotBeReorderedOrDuplicatedToManufactureAMatch()
        {
            var v=Vector(); var first=v.keys[0]; v.keys[0]=v.keys[1]; v.keys[1]=first;
            Assert.False(SettingsCanonical.TryEncode(v.settings,v.keys,true,out _));
            v=Vector(); v.keys[1]["keyCode"]=v.keys[0]["keyCode"];
            Assert.False(SettingsCanonical.TryEncode(v.settings,v.keys,true,out _));
        }
        [Fact] public void OpaqueIdentityRejectsTrailingNewlineAndUnsafeRevision()
        {
            Assert.False(SettingsCanonical.IsOpaque("op.1\n"));
            Assert.False(SettingsCanonical.IsDigest(new string('a',64)+"\n"));
            Assert.Throws<ArgumentException>(()=>SettingsCanonical.MutationDigest("ctx","owner","vm","op","state",
                SettingsCanonical.MaxSafeInteger+1,new string('a',64)));
        }
    }
}
