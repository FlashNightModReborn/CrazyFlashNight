using System;
using System.IO;
using System.Linq;
using System.Xml.Linq;
using CF7Launcher.Guardian.WorldCompositor;
using Xunit;

namespace CF7Launcher.Tests.Guardian
{
    public sealed class CombatFxTests
    {
        private static readonly Lazy<CombatFxCatalog> Loaded=new(()=>CombatFxCatalog.Load(ProjectRoot()));
        private static CombatFxCatalog Catalog=>Loaded.Value;
        private static int Casing=>Array.FindIndex(Catalog.Styles,s=>s.Linkage=="步枪弹壳");
        private static int Muzzle=>Array.FindIndex(Catalog.Styles,s=>s.Linkage=="突击步枪枪火");
        private static int Impact=>Array.FindIndex(Catalog.Styles,s=>s.Linkage=="火花");
        private static string Shell(int count=1)=>$"s,{Casing},100,200,100,100,300,{count},123,0";
        private static string Flash()=> $"m,{Muzzle},300,200,-100,100,15,123,0";
        private static string Hit()=> $"i,{Impact},350,220,100,100,0,123,0";
        private static CombatFxFrame Frame(int seq,int tick,string events="",int epoch=1,bool paused=false)
        {
            Assert.True(CombatFxFrame.TryParse($"{epoch}|{seq}|{tick}|{(paused?1:0)}"+(events.Length==0?"":";"+events),Catalog,out var f));
            return f;
        }
        private static string ProjectRoot()
        {
            var path=new DirectoryInfo(AppContext.BaseDirectory);
            while(path!=null && !File.Exists(Path.Combine(path.FullName,CombatFxCatalog.RelativePath))) path=path.Parent;
            return path?.FullName??throw new InvalidOperationException("Missing combat effect fixture catalog");
        }

        [Fact]
        public void RuntimeCasingMappingsResolveToStaticAuthoredStamps()
        {
            var data=XDocument.Load(Path.Combine(ProjectRoot(),"data/items/bullets_cases.xml"));
            foreach(string name in data.Descendants("casing").Select(x=>x.Value).Distinct())
            {
                var style=Assert.Single(Catalog.Styles,s=>s.Linkage==name);
                Assert.True(style.IsCasing);Assert.Single(style.Frames);Assert.Single(style.Variants);
            }
            Assert.Equal(Catalog.Width*Catalog.Height*4,Catalog.PremultipliedBgra.Length);
            Assert.Equal(3,Catalog.Styles.Single(s=>s.Linkage=="枪火").Variants.Length);
        }

        [Theory]
        [InlineData("1|1|1|0;s,0,NaN,200,100,100,300,1,123,0")]
        [InlineData("1|1|1|0;s,0,100,200,100,100,300,65,123,0")]
        [InlineData("1|1|1|0;a,-1,1")]
        [InlineData("1|1|1|2")]
        [InlineData("1|1|1|0;")]
        [InlineData("1|1|1|0;m,0,100,200,100,100,0,123,0")]
        public void MalformedFramesCannotCreateNativeInstances(string payload) =>
            Assert.False(CombatFxFrame.TryParse(payload,Catalog,out _));

        [Fact]
        public void ReplayedEventsAndOlderConnectionsDoNotDuplicateParticles()
        {
            var e=new CombatFxEngine(Catalog);var f=Frame(1,1,Shell());
            Assert.True(e.Apply(f,2));Assert.False(e.Apply(f,2));
            Assert.False(e.Apply(Frame(2,2,Shell()),1));
            Assert.Equal(1,e.BuildDraw().Count);
        }

        [Fact]
        public void PauseFreezesMotionAndResumeDoesNotCatchUpWallTime()
        {
            var e=new CombatFxEngine(Catalog);e.Apply(Frame(1,1,Shell()),1);
            float x=e.BuildDraw().Data[0],y=e.BuildDraw().Data[1];
            e.Apply(Frame(2,200,paused:true),1);
            Assert.Equal(x,e.BuildDraw().Data[0]);Assert.Equal(y,e.BuildDraw().Data[1]);
            e.Apply(Frame(3,201),1);
            Assert.InRange(Math.Abs(e.BuildDraw().Data[0]-x),2,7);
            Assert.True(e.BuildDraw().Data[1]<y);
        }

        [Fact]
        public void SceneChangeClearsOldEffectsAndRejectsOldEpoch()
        {
            var e=new CombatFxEngine(Catalog);e.Apply(Frame(1,1,Shell()),1);
            Assert.True(e.Apply(Frame(1,0,epoch:2),1));Assert.Equal(0,e.BuildDraw().Count);
            Assert.False(e.Apply(Frame(9,9,Shell(),epoch:1),1));Assert.Equal(0,e.BuildDraw().Count);
        }

        [Fact]
        public void CasingTouchesGroundOnceSettlesAndRetiresAfterStampAck()
        {
            var e=new CombatFxEngine(Catalog);e.Apply(Frame(1,1,Shell()),1);
            int hits=0,tick=1;CombatFxSettlement? settled=null;
            for(tick=2;tick<120;tick++)
            {
                e.Apply(Frame(tick,tick),1);var ev=e.TakeEvents();
                if(ev==null)continue;hits+=ev.GroundHits;
                if(ev.Settled.Length>0) { settled=Assert.Single(ev.Settled);break; }
            }
            Assert.Equal(1,hits);Assert.True(settled.HasValue);Assert.Equal(300f,settled.Value.Y);
            e.Apply(Frame(++tick,tick,$"a,{settled.Value.Id},1"),1);
            for(int i=0;i<6;i++)e.Apply(Frame(++tick,tick),1);
            Assert.Equal(0,e.BuildDraw().Count);
        }

        [Fact]
        public void MissingStampAckHasABoundedVisualLifetime()
        {
            var e=new CombatFxEngine(Catalog);e.Apply(Frame(1,1,Shell(64)),1);
            for(int tick=2;tick<200;tick++) {
                e.Apply(Frame(tick,tick),1);var ev=e.TakeEvents();
                if(ev!=null)Assert.InRange(ev.Settled.Length,0,CombatFxEngine.StampBatchLimit);
            }
            Assert.Equal(0,e.BuildDraw().Count);
        }

        [Fact]
        public void DecorativeBudgetsAreIndependentAndCasingsPrecedeMuzzles()
        {
            var e=new CombatFxEngine(Catalog);
            e.Apply(Frame(1,1,string.Join(";",Enumerable.Repeat(Shell(64),5))),1);
            e.Apply(Frame(2,1,string.Join(";",Enumerable.Repeat(Flash(),32))),1);
            e.Apply(Frame(3,1,string.Join(";",Enumerable.Repeat(Flash(),32))),1);
            e.Apply(Frame(4,1,Flash()),1);
            var draw=e.BuildDraw();
            Assert.Equal(256,draw.CasingCount);Assert.Equal(320,draw.Count);Assert.Equal(65,e.Dropped);
            Assert.Equal(1f,draw.Data[7]);Assert.Equal(0f,draw.Data[draw.CasingCount*16+7]);
        }

        [Fact]
        public void MuzzleUsesAuthoredFrameLifetimeAndLargeGapsDoNotReplayIt()
        {
            var e=new CombatFxEngine(Catalog);e.Apply(Frame(1,1,Flash()),1);
            Assert.Equal(1,e.BuildDraw().Count);
            e.Apply(Frame(2,2),1);e.Apply(Frame(3,3),1);Assert.Equal(1,e.BuildDraw().Count);
            e.Apply(Frame(4,4),1);Assert.Equal(0,e.BuildDraw().Count);
            e.Apply(Frame(5,5,Flash()),1);e.Apply(Frame(6,100),1);Assert.Equal(0,e.BuildDraw().Count);
        }

        [Fact]
        public void ImpactWireBudgetCannotDisplaceShootingAndKindsAreStrict()
        {
            string maximum=string.Join(";",Enumerable.Repeat(Flash(),32).Concat(Enumerable.Repeat(Hit(),32)));
            Assert.Equal(64,Frame(1,1,maximum).Spawns.Length);
            Assert.False(CombatFxFrame.TryParse("1|1|1|0;"+maximum+";"+Hit(),Catalog,out _));
            Assert.False(CombatFxFrame.TryParse("1|1|1|0;"+maximum+";"+Flash(),Catalog,out _));
            Assert.False(CombatFxFrame.TryParse($"1|1|1|0;i,{Muzzle},0,1,100,100,0,1,0",Catalog,out _));
            Assert.False(CombatFxFrame.TryParse($"1|1|1|0;m,{Impact},0,1,100,100,0,1,0",Catalog,out _));
        }

        [Fact]
        public void ImpactsHaveIndependentCapacityAndRenderBelowMuzzles()
        {
            var e=new CombatFxEngine(Catalog);
            e.Apply(Frame(1,1,string.Join(";",Enumerable.Repeat(Shell(64),4))),1);
            int seq=1;
            for(int n=0;n<4;n++)e.Apply(Frame(++seq,1,string.Join(";",Enumerable.Repeat(Hit(),32))),1);
            for(int n=0;n<2;n++)e.Apply(Frame(++seq,1,string.Join(";",Enumerable.Repeat(Flash(),32))),1);
            var draw=e.BuildDraw();
            Assert.Equal(448,draw.Count);Assert.Equal(256,draw.CasingCount);Assert.Equal(128,draw.ImpactCount);
            Assert.Equal(350f,draw.Data[256*16]);Assert.Equal(300f,draw.Data[384*16]);
            e.Apply(Frame(++seq,1,Hit()+";"+Flash()),1);
            Assert.Equal(2,e.Dropped);Assert.Equal(1,e.ImpactDropped);Assert.Equal(448,e.BuildDraw().Count);
        }

        [Fact]
        public void EmptyAuthoredMuzzleVariantStillEmitsLightAndPauseFreezesIt()
        {
            int generic=Array.FindIndex(Catalog.Styles,s=>s.Linkage=="枪火");
            var e=new CombatFxEngine(Catalog);
            e.Apply(Frame(1,1,$"m,{generic},300,200,100,100,0,1,0"),1);
            var draw=e.BuildDraw();Assert.Equal(1,draw.LightCount);
            float energy=draw.Lights[3];
            Assert.Equal(.5f,draw.Data[10]); // source a0 is a transparent 1-pixel frame at 2x.
            e.Apply(Frame(2,200,paused:true),1);
            Assert.Equal(energy,e.BuildDraw().Lights[3]);
            e.Apply(Frame(3,201),1);
            Assert.Equal(0,e.BuildDraw().Count);Assert.Equal(1,e.BuildDraw().LightCount);
            Assert.Equal(energy,e.BuildDraw().Lights[3]);
            e.Apply(Frame(4,202),1);Assert.InRange(e.BuildDraw().Lights[3],0,energy*.8f);
            int remaining=Catalog.Styles[generic].Light.Ticks;
            for(int n=3;n<=remaining;n++)e.Apply(Frame(n+2,200+n),1);
            Assert.Equal(0,e.BuildDraw().LightCount);
        }

        [Fact]
        public void LightBudgetAndSceneLifetimeAreIndependentOfImpactAndSpriteCapacity()
        {
            var e=new CombatFxEngine(Catalog);
            e.Apply(Frame(1,1,string.Join(";",Enumerable.Repeat(Flash(),32))),1);
            Assert.Equal(CombatFxEngine.LightLimit,e.BuildDraw().LightCount);
            Assert.Equal(16,e.LightDropped);Assert.Equal(32,e.BuildDraw().Count);
            e.Apply(Frame(2,1,string.Join(";",Enumerable.Repeat(Hit(),32))),1);
            Assert.Equal(16,e.BuildDraw().LightCount);Assert.Equal(16,e.LightDropped);
            e.Apply(Frame(3,20),1);Assert.Equal(0,e.BuildDraw().LightCount);
            e.Apply(Frame(4,21,Flash()),1);Assert.Equal(1,e.BuildDraw().LightCount);
            e.Apply(Frame(1,0,epoch:2),1);Assert.Equal(0,e.BuildDraw().LightCount);
            Assert.False(e.Apply(Frame(5,22,Flash(),epoch:1),1));
            Assert.Equal(0,e.BuildDraw().LightCount);
        }
    }
}
