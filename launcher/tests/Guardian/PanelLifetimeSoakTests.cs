using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Threading.Tasks;
using CF7Launcher.Guardian;
using Newtonsoft.Json.Linq;
using Xunit;

namespace CF7Launcher.Tests.Guardian
{
    public sealed class PanelLifetimeSoakFactAttribute : FactAttribute
    {
        public PanelLifetimeSoakFactAttribute()
        {
            if(Environment.GetEnvironmentVariable("CF7_PANEL_LIFETIME_SOAK")!="1")Skip="Requires dedicated five-minute production-controller fixture run";
        }
    }
    public sealed class PanelLifetimeSoakTests
    {
        [PanelLifetimeSoakFact]
        public async Task ThousandOwnedTransitionsDrainCallbacksAndKeepAdmissionStableForFiveMinutes()
        {
            var queue=new Queue<Action>();using var host=new PanelHostController(a=>queue.Enqueue(a),a=>a());
            void Pump() { while(queue.Count>0)queue.Dequeue()(); }
            long before=GC.GetTotalMemory(true);var times=new List<double>();var clock=Stopwatch.StartNew();
            for(int i=0;i<1000;i++) {
                var lap=Stopwatch.StartNew();host.OpenPanel(i%2==0 ? "help" : "intelligence","{}");Pump();
                string panel=host.ActivePanelName,id=host.ActivePanelInstanceId;bool? accepted=null;
                Assert.True(host.TryClosePanelExact(panel,id,result=>accepted=result));Pump();
                Assert.True(accepted);Assert.True(host.GameOwnsInput);Assert.Equal(0,queue.Count);times.Add(lap.Elapsed.TotalMilliseconds);
                long due=(i+1)*300;long delay=due-clock.ElapsedMilliseconds;
                if(delay>0)await Task.Delay((int)delay);
            }
            Assert.True(clock.Elapsed>=TimeSpan.FromMinutes(5));Pump();Assert.Equal(0,queue.Count);
            long after=GC.GetTotalMemory(true);times.Sort();
            string evidence=Environment.GetEnvironmentVariable("CF7_EVIDENCE_ROOT");Assert.False(string.IsNullOrEmpty(evidence));
            File.WriteAllText(Path.Combine(evidence,"panel-lifetime-soak.json"),new JObject { ["cycles"]=1000,
                ["elapsedMs"]=clock.ElapsedMilliseconds,["queuedAfterDrain"]=queue.Count,["managedBytesBefore"]=before,["managedBytesAfter"]=after,
                ["transitionP50Ms"]=times[499],["transitionP95Ms"]=times[949],["transitionMaxMs"]=times[999],
                ["evidenceKind"]="real production controller; headless surfaces; no physical focus, WebView2 registrations or player input proof" }.ToString());
            Assert.True(after-before<4*1024*1024,"Controller managed memory did not return near baseline");
        }
    }
}
