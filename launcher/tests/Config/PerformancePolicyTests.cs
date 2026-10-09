using System;
using System.Collections.Generic;
using System.IO;
using CF7Launcher.Config;
using CF7Launcher.Tasks;
using Newtonsoft.Json.Linq;
using Xunit;

namespace CF7Launcher.Tests.Config
{
    public class PerformancePolicyTests
    {
        [Theory]
        [InlineData("balanced","auto",0)]
        [InlineData("performance","fixed",540)]
        [InlineData("quality","fixed",2160)]
        public void ValidPoliciesRoundTrip(string preset,string mode,int height)
        {
            var policy=new PerformancePolicy(preset,mode,height);
            Assert.True(PerformancePolicy.TryParse(policy.ToJson(),out var result)); Assert.Equal(policy,result);
        }
        [Theory]
        [InlineData("{\"preset\":\"fast\",\"mode\":\"auto\",\"maxRenderHeight\":0}")]
        [InlineData("{\"preset\":\"balanced\",\"mode\":\"auto\",\"maxRenderHeight\":540.5}")]
        [InlineData("{\"preset\":\"balanced\",\"mode\":\"auto\",\"maxRenderHeight\":541}")]
        [InlineData("{\"preset\":\"balanced\",\"mode\":\"auto\",\"maxRenderHeight\":540,\"extra\":true}")]
        public void InvalidPoliciesAreRejectedAsAWhole(string json)
            => Assert.False(PerformancePolicy.TryParse(JObject.Parse(json),out _));

        private sealed class Fixture : IDisposable
        {
            internal readonly string Root=Path.Combine(Path.GetTempPath(),"cf7-performance-"+Guid.NewGuid().ToString("N"));
            internal readonly UserPrefs Prefs;
            internal readonly SettingsTask Task;
            internal readonly List<JObject> Replies=new();
            internal int SentToFlash,Observed;
            internal bool SaveOk=true;
            internal Fixture()
            {
                Prefs=new UserPrefs(Root,Root);
                Task=new SettingsTask(()=>true,_=>{SentToFlash++;return true;},Prefs,()=>SaveOk && Prefs.Save());
                Task.SetPostToWeb(s=>Replies.Add(JObject.Parse(s)));
                Task.SetHostPreferenceApplied((_,__)=>Observed++);
                Task.BindPanelInstance("performance.test");
            }
            internal void Send(string key,JToken value,string id) => Task.HandleWebRequest("host_set",new JObject {
                ["domain"]="settings",["panelInstanceId"]="performance.test",["callId"]=id,
                ["payload"]=new JObject {["v"]=1,["key"]=key,["value"]=value}
            });
            public void Dispose() {Task.Dispose(); Directory.Delete(Root,true);}
        }
        [Fact] public void ApplyUndoAndRestartUseOnlyMachinePreferenceAndKeepUnrelatedValues()
        {
            using var f=new Fixture(); f.Prefs.UiFontScale=1.7;
            var next=new PerformancePolicy("performance","fixed",540);
            f.Send("performance",next.ToJson(),"apply.1");
            Assert.True(f.Replies[0].Value<bool>("success")); Assert.Equal(next,f.Prefs.Performance);
            Assert.Equal(PerformancePolicy.Default,f.Prefs.PreviousPerformance);
            var loaded=new UserPrefs(f.Root,f.Root);
            Assert.Equal(next,loaded.Performance); Assert.Equal(PerformancePolicy.Default,loaded.PreviousPerformance);
            f.Send("performance",next.ToJson(),"same.2");
            Assert.Equal(PerformancePolicy.Default,f.Prefs.PreviousPerformance);
            f.Send("performanceUndo",true,"undo.3");
            Assert.Equal(PerformancePolicy.Default,f.Prefs.Performance); Assert.Null(f.Prefs.PreviousPerformance);
            f.Send("performanceUndo",true,"undo.3"); // exact call replay is not another write
            Assert.Equal(3,f.Observed); Assert.Equal(0,f.SentToFlash); Assert.Equal(1.7,f.Prefs.UiFontScale);
            Assert.Equal(JTokenType.Null,f.Replies[2]["currentValue"]["previous"].Type);
        }
        [Fact] public void FailedSaveRestoresBothCurrentAndUndoAndDoesNotNotifyRuntime()
        {
            using var f=new Fixture(); var first=new PerformancePolicy("quality","auto",720);
            f.Send("performance",first.ToJson(),"first"); f.SaveOk=false;
            f.Send("performance",new PerformancePolicy("performance","fixed",540).ToJson(),"fail");
            Assert.Equal("save_failed",f.Replies[1].Value<string>("error"));
            Assert.Equal(first,f.Prefs.Performance); Assert.Equal(PerformancePolicy.Default,f.Prefs.PreviousPerformance);
            f.Send("performanceUndo",true,"undo.fail");
            Assert.Equal(first,f.Prefs.Performance); Assert.Equal(PerformancePolicy.Default,f.Prefs.PreviousPerformance);
            Assert.Equal(1,f.Observed); Assert.Equal(0,f.SentToFlash);
        }
    }
}
