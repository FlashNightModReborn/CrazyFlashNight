using System;
using System.Collections.Generic;
using System.IO;
using System.Reflection;
using System.Windows.Forms;
using CF7Launcher.Guardian;
using Newtonsoft.Json.Linq;
using Xunit;

namespace CF7Launcher.Tests.Guardian;

public sealed class SceneTransitionResumeTests
{
    private sealed class Rig : IDisposable
    {
        internal readonly Form Owner=new();
        internal readonly SceneTransitionController Controller;
        internal readonly List<bool> Held=new();
        internal bool Presented=true, Current=true;
        internal int FreshRequests, FocusCalls;
        internal Rig() {
            string root=Path.GetFullPath(Path.Combine(AppContext.BaseDirectory,"..","..","..",".."));
            Controller=new SceneTransitionController(Owner,Owner,root,a=>a(),_=>true,()=>false,
                _=>Presented,_=>{FocusCalls++;return true;},Array.Empty<OverlayBase>(),Held.Add);
            Set(Controller,"_preparing",true); // This logic fixture never starts WebView2.
            Set(Controller,"_retainedScene",2L);
            Set(Controller.SettlementSurface,"_panelInstance","loot.resume");
            Controller.ConfigureSettlement(_=>true,s=>Current && s==2);
            Controller.ConfigurePresentationFence(_=>{FreshRequests++;Presented=false;});
        }
        internal void Close()=>Controller.ReleaseSettlement("{\"type\":\"panel_cmd\",\"panel\":\"loot\",\"cmd\":\"close\",\"panelInstanceId\":\"loot.resume\"}");
        internal void Tick()=>Call(Controller,"Tick");
        public void Dispose(){Controller.Dispose();Owner.Dispose();}
    }
    private static void Set(object target,string name,object value)=>target.GetType()
        .GetField(name,BindingFlags.Instance|BindingFlags.NonPublic).SetValue(target,value);
    private static void Call(object target,string name,params object[] args)=>target.GetType()
        .GetMethod(name,BindingFlags.Instance|BindingFlags.NonPublic).Invoke(target,args);
    private static JObject Projection(string phase,int revision=1,long scene=2)=>new() {
        ["requestId"]="tr:1",["targetScene"]=scene,["phase"]=phase,["revision"]=revision,["imageId"]="Andy"
    };

    [Fact] public void CloseRetainsViewAndOriginalTailUntilFreshWorldPresentation() {
        using var r=new Rig();r.Close();int tails=0;
        Assert.True(r.Controller.DeferSettlementResumeTail(()=>tails++));
        Assert.True(r.Controller.OwnsCurtain);Assert.Equal("loot.resume",r.Controller.SettlementSurface.SettlementInstance);
        r.Close();r.Tick();r.Tick();
        Assert.Equal(1,r.FreshRequests);Assert.Equal(0,tails);Assert.True(r.Held[^1]);
        r.Presented=true;r.Tick();
        Assert.False(r.Controller.SettlementResumePending);Assert.False(r.Controller.OwnsCurtain);
        Assert.Empty(r.Controller.SettlementSurface.SettlementInstance);Assert.False(r.Held[^1]);
        Assert.Equal(1,tails);Assert.Equal(0,r.FocusCalls);
        r.Tick();Assert.Equal(1,tails);
    }
    [Fact] public void FrameFromAnotherSceneCannotReleaseClosedSettlement() {
        using var r=new Rig();r.Close();r.Current=false;r.Presented=true;r.Tick();
        Assert.True(r.Controller.SettlementResumePending);Assert.True(r.Held[^1]);
        Assert.Equal("loot.resume",r.Controller.SettlementSurface.SettlementInstance);
    }
    [Fact] public void NewCurtainRetiresPendingViewWithoutReplayingItsCloseTail() {
        using var r=new Rig();r.Close();int tails=0;r.Controller.DeferSettlementResumeTail(()=>tails++);
        Call(r.Controller,"Present",Projection("cover",scene:3));
        Assert.False(r.Controller.SettlementResumePending);Assert.True(r.Controller.OwnsCurtain);
        Assert.Empty(r.Controller.SettlementSurface.SettlementInstance);Assert.Equal(1,tails);
        r.Presented=true;r.Tick();Assert.Equal(1,tails);
    }
    [Fact] public void RevealRequiresFreshFrameOncePerSceneAndNotPerHeartbeat() {
        using var r=new Rig();
        Call(r.Controller,"Present",Projection("loading"));
        Assert.Equal(0,r.FreshRequests);
        Call(r.Controller,"Present",Projection("reveal",2));
        Assert.Equal(1,r.FreshRequests);Assert.False(r.Presented);
        Call(r.Controller,"Present",Projection("reveal",3));
        Assert.Equal(1,r.FreshRequests);
        Call(r.Controller,"Present",Projection("reveal",4,3));Assert.Equal(2,r.FreshRequests);
    }
    [Fact] public void ForcedRetirementReleasesThePendingTailAndInput() {
        using var r=new Rig();r.Close();int tails=0;r.Controller.DeferSettlementResumeTail(()=>tails++);
        r.Controller.ReleaseSettlement();
        Assert.False(r.Controller.SettlementResumePending);Assert.False(r.Held[^1]);Assert.Equal(1,tails);
    }
}
