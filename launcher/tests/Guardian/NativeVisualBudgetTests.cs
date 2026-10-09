using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using CF7Launcher.Guardian.WorldCompositor;
using Xunit;

namespace CF7Launcher.Tests.Guardian
{
    public sealed class NativeVisualBudgetTests
    {
        private static readonly Lazy<CombatFxCatalog> Loaded=new(()=>CombatFxCatalog.Load(ProjectRoot()));
        private static CombatFxCatalog Catalog=>Loaded.Value;
        private static int Style(string linkage)=>Array.FindIndex(Catalog.Styles,s=>s.Linkage==linkage);
        private static string Shell(int count=1)=>$"s,{Style("步枪弹壳")},100,200,100,100,300,{count},123,0";
        private static string Muzzle=>$"m,{Style("突击步枪枪火")},300,200,-100,100,15,123,0";
        private static string Impact=>$"i,{Style("火花")},350,220,100,100,0,123,0";
        private static string ShellBurst=>string.Join(';',Enumerable.Repeat(Shell(64),4));

        [Theory]
        [InlineData(0,256)]
        [InlineData(1,128)]
        [InlineData(2,64)]
        public void BudgetLimitsCreatedCasingsWhileKeepingCombatFeedback(int level,int expectedCasings)
        {
            var budget=NativeVisualBudget.FromEffectLevel(level);
            var engine=new CombatFxEngine(Catalog);
            engine.ConfigureVisualBudget(budget);
            Assert.True(engine.Apply(Frame(1,1,ShellBurst+";"+Muzzle+";"+Impact),1));
            CombatFxDrawFrame draw=engine.BuildDraw();
            Assert.Equal(expectedCasings,draw.CasingCount);
            Assert.Equal(expectedCasings+2,draw.Count);
            Assert.Equal(1,draw.ImpactCount);
            Assert.Equal(1,draw.LightCount);
            Assert.Equal(256-expectedCasings,engine.Dropped);
            Assert.Equal(0,engine.ImpactDropped);
            Assert.Equal(level,budget.WeatherQuality);
        }

        [Fact]
        public void LowerBudgetKeepsExistingParticlesAndBlocksNewCasingsUntilTheyDrain()
        {
            var engine=new CombatFxEngine(Catalog);
            engine.Apply(Frame(1,1,Shell(64)+";"+Shell()),1);
            float[] original=engine.BuildDraw().Data.Take(65*16).ToArray();
            engine.ConfigureVisualBudget(NativeVisualBudget.FromEffectLevel(2));
            engine.Apply(Frame(2,1,Shell()),1);
            Assert.Equal(65,engine.BuildDraw().CasingCount);
            Assert.Equal(original,engine.BuildDraw().Data.Take(65*16));
            Assert.Equal(1,engine.Dropped);

            engine.ConfigureVisualBudget(NativeVisualBudget.FromEffectLevel(0));
            engine.Apply(Frame(3,1,Shell()),1);
            Assert.Equal(66,engine.BuildDraw().CasingCount);
            Assert.Equal(original,engine.BuildDraw().Data.Take(65*16));
            Assert.Equal(1,engine.Dropped); // A raised budget does not replay the dropped spawn.
        }

        [Fact]
        public void BudgetChangeDoesNotLoseSettlementIdsOrOutstandingAcknowledgements()
        {
            var engine=new CombatFxEngine(Catalog);
            engine.Apply(Frame(1,1,Shell(64)+";"+Shell()),1);
            engine.ConfigureVisualBudget(NativeVisualBudget.FromEffectLevel(2));
            var settled=new HashSet<int>();
            string acknowledgements="";
            for(int tick=2;tick<180;tick++) {
                engine.Apply(Frame(tick,tick,acknowledgements),1);
                acknowledgements="";
                CombatFxEvents events=engine.TakeEvents();
                if(events==null)continue;
                Assert.InRange(events.Settled.Length,0,CombatFxEngine.StampBatchLimit);
                foreach(CombatFxSettlement casing in events.Settled)
                    Assert.True(settled.Add(casing.Id),"Each existing casing must settle once.");
                acknowledgements=string.Join(';',events.Settled.Select(casing=>$"a,{casing.Id},1"));
            }
            Assert.Equal(65,settled.Count);
            Assert.Contains(65,settled);
            Assert.Equal(0,engine.BuildDraw().Count);
            engine.Apply(Frame(180,180,ShellBurst),1);
            Assert.Equal(64,engine.BuildDraw().CasingCount);
        }

        [Fact]
        public void LowestCasingBudgetDoesNotReduceMuzzleImpactOrLightingCapacity()
        {
            var engine=new CombatFxEngine(Catalog);
            engine.ConfigureVisualBudget(NativeVisualBudget.FromEffectLevel(2));
            engine.Apply(Frame(1,1,ShellBurst),1);
            int seq=1;
            for(int n=0;n<4;n++)engine.Apply(Frame(++seq,1,string.Join(';',Enumerable.Repeat(Impact,32))),1);
            for(int n=0;n<2;n++)engine.Apply(Frame(++seq,1,string.Join(';',Enumerable.Repeat(Muzzle,32))),1);
            CombatFxDrawFrame draw=engine.BuildDraw();
            Assert.Equal(64,draw.CasingCount);
            Assert.Equal(128,draw.ImpactCount);
            Assert.Equal(64,draw.Count-draw.CasingCount-draw.ImpactCount);
            Assert.Equal(16,draw.LightCount);
        }

        [Fact]
        public void ResetAndNewSceneKeepHostBudgetWhilePausedPacketsCreateNothing()
        {
            var engine=new CombatFxEngine(Catalog);
            engine.ConfigureVisualBudget(NativeVisualBudget.FromEffectLevel(2));
            engine.Apply(Frame(1,1,ShellBurst,paused:true),1);
            Assert.Equal(0,engine.BuildDraw().Count);
            engine.Reset();
            engine.Apply(Frame(1,1,ShellBurst,epoch:2),2);
            Assert.Equal(64,engine.BuildDraw().CasingCount);
            Assert.False(engine.Apply(Frame(1,1,ShellBurst,epoch:2),2));
            Assert.Equal(64,engine.BuildDraw().CasingCount);
        }

        [Theory]
        [InlineData(-1)]
        [InlineData(3)]
        public void UnknownEffectLevelsAreRejected(int level)=>
            Assert.Throws<ArgumentOutOfRangeException>(()=>NativeVisualBudget.FromEffectLevel(level));

        private static CombatFxFrame Frame(int sequence,int tick,string events="",int epoch=1,bool paused=false)
        {
            Assert.True(CombatFxFrame.TryParse($"{epoch}|{sequence}|{tick}|{(paused?1:0)}"+
                (events.Length==0?"":";"+events),Catalog,out var frame));
            return frame;
        }
        private static string ProjectRoot()
        {
            var path=new DirectoryInfo(AppContext.BaseDirectory);
            while(path!=null && !File.Exists(Path.Combine(path.FullName,CombatFxCatalog.RelativePath)))path=path.Parent;
            return path?.FullName??throw new InvalidOperationException("Missing combat effect fixture catalog");
        }
    }
}
