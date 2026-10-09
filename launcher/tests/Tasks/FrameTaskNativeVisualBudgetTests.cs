using System;
using System.IO;
using System.Linq;
using CF7Launcher.Guardian.WorldCompositor;
using CF7Launcher.Tasks;
using Xunit;

namespace CF7Launcher.Tests.Tasks
{
    public sealed class FrameTaskNativeVisualBudgetTests
    {
        private static readonly Lazy<CombatFxCatalog> Loaded=new(()=>CombatFxCatalog.Load(ProjectRoot()));
        private static CombatFxCatalog Catalog=>Loaded.Value;
        private static string Payload(int sequence,int tick)=>$"1|{sequence}|{tick}|0;"+
            string.Join(';',Enumerable.Repeat($"s,{Array.FindIndex(Catalog.Styles,s=>s.Linkage=="步枪弹壳")},100,200,100,100,300,64,123,0",4));

        [Theory]
        [InlineData(true,0,256)]
        [InlineData(true,1,128)]
        [InlineData(true,2,64)]
        [InlineData(false,0,256)]
        [InlineData(false,1,128)]
        [InlineData(false,2,64)]
        public void ProductionDispatchUsesBudgetBeforeOrAfterCatalogLoad(bool configureFirst,int level,int expected)
        {
            var task=new FrameTask(null,null);
            if(configureFirst)task.ConfigureNativeVisualBudget(level);
            task.ConfigureCombatFx(Catalog);
            if(!configureFirst)task.ConfigureNativeVisualBudget(level);
            int casings=-1;
            task.CombatFxObserved=(draw,x,y,scale)=>casings=draw.CasingCount;
            task.HandleRaw("0,0,1","",null,null,connectionGeneration:1,combatFxPayload:Payload(1,1));
            Assert.Equal(expected,casings);

            task.ConfigureCombatFx(Catalog);
            task.HandleRaw("0,0,1","",null,null,connectionGeneration:2,combatFxPayload:Payload(1,1));
            Assert.Equal(expected,casings);
        }

        [Fact]
        public void InvalidBudgetLeavesAppliedBudgetAndResourceReloadStateUnchanged()
        {
            var task=new FrameTask(null,null);
            task.ConfigureCombatFx(Catalog);
            task.ConfigureNativeVisualBudget(2);
            Assert.Throws<ArgumentOutOfRangeException>(()=>task.ConfigureNativeVisualBudget(3));
            int casings=-1;
            task.CombatFxObserved=(draw,x,y,scale)=>casings=draw.CasingCount;
            task.HandleRaw("0,0,1","",null,null,connectionGeneration:1,combatFxPayload:Payload(1,1));
            Assert.Equal(64,casings);
            task.ConfigureCombatFx(null);
            task.ConfigureCombatFx(Catalog);
            task.HandleRaw("0,0,1","",null,null,connectionGeneration:2,combatFxPayload:Payload(1,1));
            Assert.Equal(64,casings);
        }

        private static string ProjectRoot()
        {
            var path=new DirectoryInfo(AppContext.BaseDirectory);
            while(path!=null && !File.Exists(Path.Combine(path.FullName,CombatFxCatalog.RelativePath)))path=path.Parent;
            return path?.FullName??throw new InvalidOperationException("Missing combat effect fixture catalog");
        }
    }
}
