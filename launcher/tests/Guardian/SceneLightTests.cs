using System;
using System.Globalization;
using System.IO;
using CF7Launcher.Guardian.WorldCompositor;
using Newtonsoft.Json.Linq;
using Xunit;

namespace Launcher.Tests.Guardian
{
    public sealed class SceneLightTests
    {
        private static SceneLightCatalog Catalog()
        {
            var d=new DirectoryInfo(AppContext.BaseDirectory);
            while(d!=null && !File.Exists(Path.Combine(d.FullName,SceneLightCatalog.RelativePath)))d=d.Parent;
            Assert.NotNull(d);return SceneLightCatalog.Load(d.FullName);
        }
        private static SceneLightSnapshot Snapshot(params JObject[] definitions)
        {
            var poses=new SceneLightPose[definitions.Length];
            for(int i=0;i<poses.Length;i++)poses[i]=new(i+1,200+i*300,200,1,0,1,1);
            return new(1,"test",definitions,poses);
        }
        [Fact] public void PresetsResolveAndEverySupportedFieldCanOverride()
        {
            var c=Catalog();var d=c.Resolve(new JObject { ["Key"]="lamp",["Preset"]="lamp",["Radius"]=260,["Energy"]=1.2,["Color"]="0x80C0FF",["Priority"]=91,["BudgetPool"]="shared"},1);
            Assert.Equal(260,d.Extent);Assert.Equal(1.2f,d.Energy);Assert.Equal(0x80c0ff,d.Color);Assert.Equal(91,d.Priority);Assert.False(d.Reserved);
            foreach(string p in new[]{"lamp","street","fire","flicker","concert","spawn"})Assert.NotNull(c.Resolve(new JObject{["Key"]="x",["Preset"]=p},1));
        }
        [Theory]
        [InlineData("Radius",0)][InlineData("Radius",1025)][InlineData("Energy",-1)][InlineData("Energy",3)][InlineData("Priority",101)][InlineData("Priority",1.5)][InlineData("Rate",31)]
        public void InvalidAuthoringIsRejected(string field,double value)
        {Assert.Throws<InvalidDataException>(()=>Catalog().Resolve(new JObject{["Key"]="x",[field]=value},1));}
        [Fact] public void CachedAnimationAndInconsistentHybridAreRejected()
        {
            var c=Catalog();Assert.Throws<InvalidDataException>(()=>c.Resolve(new JObject{["Key"]="x",["Animation"]="pulse"},1));
            Assert.Throws<InvalidDataException>(()=>c.Resolve(new JObject{["Key"]="x",["Preset"]="fire",["BaseEnergy"]=2},1));
            Assert.Throws<InvalidDataException>(()=>c.Resolve(new JObject{["Key"]="x",["Unexpected"]=1},1));
        }
        [Fact] public void ConstantFieldDoesNotRebuildForClockAndPauses()
        {
            var e=new SceneLightEngine(Catalog());e.Configure(1,Snapshot(new JObject{["Key"]="lamp"}));long v=e.StaticVersion;
            for(int i=0;i<120;i++)e.Tick(i,false);
            Assert.Equal(v,e.StaticVersion);Assert.Equal(1,e.CachedCount);Assert.Equal(0,e.RealtimeCount);
            Assert.True(e.Adopt(new(1,1,1,new[]{new SceneLightPose(1,200,200,1,0,1,0)})));
            Assert.Equal(0,e.CachedCount);Assert.True(e.StaticVersion>v);
        }
        [Fact] public void HybridFlickerLeavesBaseCacheUntouched()
        {
            var e=new SceneLightEngine(Catalog());e.Configure(1,Snapshot(new JObject{["Key"]="fire",["Preset"]="fire"}));long v=e.StaticVersion;
            float energy=e.Realtime[0].Energy;e.Tick(13,false);Assert.NotEqual(energy,e.Realtime[0].Energy);Assert.Equal(v,e.StaticVersion);
            energy=e.Realtime[0].Energy;e.Tick(45,true);Assert.Equal(energy,e.Realtime[0].Energy);
            Assert.Equal(.82f,e.Cached[3]);Assert.Equal(1,e.RealtimeCount);
        }
        [Fact] public void FutureSparseStateIsMergedAndOldRevisionCannotRelight()
        {
            var e=new SceneLightEngine(Catalog());
            Assert.True(e.Adopt(new(2,1,1,new[]{new SceneLightPose(1,100,100,1,0,1,0)})));
            Assert.True(e.Adopt(new(2,1,2,new[]{new SceneLightPose(2,400,100,1,0,1,0)})));
            e.Configure(2,Snapshot(new JObject{["Key"]="a"},new JObject{["Key"]="b"}));Assert.Equal(0,e.CachedCount);
            Assert.False(e.Adopt(new(1,1,50,new[]{new SceneLightPose(1,100,100,1,0,1,1)})));
            Assert.False(e.Adopt(new(2,1,1,new[]{new SceneLightPose(1,100,100,1,0,1,1)})));
            var next=Snapshot(new JObject{["Key"]="a"});e.Configure(2,next with{Revision=2});
            Assert.False(e.Adopt(new(2,1,99,new[]{new SceneLightPose(1,100,100,1,0,1,0)})));Assert.Equal(1,e.CachedCount);
        }
        [Fact] public void MirroredBasisPreservesAuthoredDirection()
        {
            var e=new SceneLightEngine(Catalog());var s=Snapshot(new JObject{["Key"]="beam",["Preset"]="street"});
            s.Poses[0]=new(1,200,200,-1,0,1,1,-1);e.Configure(1,s);
            Assert.InRange(e.Cached[8],-.0001f,.0001f);Assert.InRange(e.Cached[9],.9999f,1.0001f);
        }
        [Theory]
        [InlineData("1|1|1;1,200,200,1,0,1,1,1",true)]
        [InlineData("1|1|1;1,200,200,1,0,1,1,1;1,300,300,1,0,1,1,1",false)]
        [InlineData("1|1|1;1,NaN,200,1,0,1,1,1",false)]
        [InlineData("1|1|1;1,200,200,0,0,1,1,1",false)]
        [InlineData("1|1|1;129,200,200,1,0,1,1,1",false)]
        [InlineData("1|1|1;1,200,200,1,0,1,1,0",false)]
        [InlineData("1|1;1,200,200,1,0,1,1,1",false)]
        public void StateWireIsBoundedAndCultureIndependent(string text,bool ok)
        {var old=CultureInfo.CurrentCulture;try{CultureInfo.CurrentCulture=new("fr-FR");Assert.Equal(ok,SceneLightState.TryParse(text,out _));}finally{CultureInfo.CurrentCulture=old;}}
        [Fact] public void SceneReservationSharesSixteenSlotsAndUnusedCapacityIsBorrowed()
        {
            var composer=new WorldLightComposer(.78f,2);var rays=new RayVisualDrawFrame();
            for(int i=0;i<16;i++)rays.Lights[i]=new WorldLightCandidate(i+1,90,500,280,120,1,1,1,1,0);
            rays.LightCount=16;composer.SetRays(rays);
            var scene=new[]{new WorldLightCandidate(100,30,200,280,120,1,1,1,1,0,sceneReserved:true),new WorldLightCandidate(101,30,800,280,120,1,1,1,1,0,sceneReserved:true)};
            composer.SetSceneLights(scene,2);var draw=composer.Compose(0,0,1);Assert.Equal(16,draw.LightCount);Assert.Contains(100,draw.LightIds);Assert.Contains(101,draw.LightIds);
            composer.SetSceneLights(scene,0);Assert.Equal(16,composer.Compose(0,0,1).LightCount);
            composer.ClearRays();composer.SetSceneLights(scene,2);Assert.Equal(2,composer.Compose(0,0,1).LightCount);
            composer.Reset();Assert.Equal(0,composer.Compose(0,0,1).LightCount);
        }
    }
}
