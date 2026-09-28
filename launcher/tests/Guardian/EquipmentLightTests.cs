using System;
using System.IO;
using System.Linq;
using CF7Launcher.Guardian.WorldCompositor;
using Xunit;

namespace CF7Launcher.Tests.Guardian
{
    public sealed class EquipmentLightTests
    {
        private static readonly Lazy<CombatFxCatalog> Loaded=new(()=>CombatFxCatalog.Load(ProjectRoot()));
        private static CombatFxCatalog Catalog=>Loaded.Value;
        private static int Muzzle=>Array.FindIndex(Catalog.Styles,s=>s.Linkage=="突击步枪枪火");
        private static int Impact=>Array.FindIndex(Catalog.Styles,s=>s.Linkage=="火花");
        private static string Flash()=>$"m,{Muzzle},300,200,-100,100,15,123,0";
        private static string Hit()=>$"i,{Impact},350,220,100,100,0,123,0";
        private static string Cone(int id,float x=100)=>$"l,{id},1,{x},200,1,0,300,20,1,1,0.5,0";
        private static string Torch(int id,float x=100)=>$"l,{id},1,{x},200,1,0,1000,280,1.8,1,0.6,0.4,{x},200,220,1.65";
        private static string Sphere(int id,float x=100)=>$"l,{id},0,{x},200,0,0,110,0,0.5,0.3,0.6,1,0,0,0,0";
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

        [Theory]
        [InlineData("1|1|1|0;l,0,1,100,200,1,0,300,20,1,1,0.5,0")]
        [InlineData("1|1|1|0;l,1000000001,1,100,200,1,0,300,20,1,1,0.5,0")]
        [InlineData("1|1|1|0;l,1,0,100,200,1,0,300,20,1,1,0.5,0")]
        [InlineData("1|1|1|0;l,1,3,100,200,1,0,300,20,1,1,0.5,0")]
        [InlineData("1|1|1|0;l,1,1,1000001,200,1,0,300,20,1,1,0.5,0")]
        [InlineData("1|1|1|0;l,1,1,100,NaN,1,0,300,20,1,1,0.5,0")]
        [InlineData("1|1|1|0;l,1,1,100,200,0.9,0.9,300,20,1,1,0.5,0")]
        [InlineData("1|1|1|0;l,1,1,100,200,0,0,300,20,1,1,0.5,0")]
        [InlineData("1|1|1|0;l,1,1,100,200,1,0,0,20,1,1,0.5,0")]
        [InlineData("1|1|1|0;l,1,1,100,200,1,0,1025,20,1,1,0.5,0")]
        [InlineData("1|1|1|0;l,1,1,100,200,1,0,300,0.4,1,1,0.5,0")]
        [InlineData("1|1|1|0;l,1,1,100,200,1,0,300,513,1,1,0.5,0")]
        [InlineData("1|1|1|0;l,1,1,100,200,1,0,300,20,2.1,1,0.5,0")]
        [InlineData("1|1|1|0;l,1,1,100,200,1,0,300,20,1,1.1,0.5,0")]
        [InlineData("1|1|1|0;l,1,1,100,200,1,0,300,20,1,1,0.5")]
        [InlineData("1|1|1|0;l,1,1,100,200,1,0,300,20,1,1,0.5,0;l,2,1,100,200,0.5,0.5,300,20,1,1,0.5,0")]
        [InlineData("1|1|1|0;s,0,100,200,100,100,300,1,123,0;l,1,1,100,200,1,0,300,20,1,9,0.5,0")]
        [InlineData("1|1|1|0;l,1,1,100,200,1,0,300,20,1,1,0.5,0,0,0,0")]
        [InlineData("1|1|1|0;l,1,1,100,200,1,0,300,20,1,1,0.5,0,0,0,0,0,0")]
        [InlineData("1|1|1|0;l,1,1,100,200,1,0,300,20,1,1,0.5,0,1000001,0,10,1")]
        [InlineData("1|1|1|0;l,1,1,100,200,1,0,300,20,1,1,0.5,0,0,NaN,10,1")]
        [InlineData("1|1|1|0;l,1,1,100,200,1,0,300,20,1,1,0.5,0,0,0,321,1")]
        [InlineData("1|1|1|0;l,1,1,100,200,1,0,300,20,1,1,0.5,0,0,0,10,0")]
        [InlineData("1|1|1|0;l,1,1,100,200,1,0,300,20,1,1,0.5,0,0,0,0,1")]
        [InlineData("1|1|1|0;l,1,1,100,200,1,0,300,20,1,1,0.5,0,5,0,0,0")]
        [InlineData("1|1|1|0;l,1,1,100,200,1,0,300,20,1,1,0.5,0,0,0,10,2.1")]
        [InlineData("1|1|1|0;l,1,2,100,200,1,0,300,20,1,1,0.5,0,1,1,10,1")]
        [InlineData("1|1|1|0;l,1,2,100,200,1,0,300,20,1,1,0.5,0,0,0,0,0.1")]
        public void MalformedEquipmentLightsRejectTheWholeFrame(string payload) =>
            Assert.False(CombatFxFrame.TryParse(payload,Catalog,out _));

        [Theory]
        [InlineData("l,1,0,100,200,0,0,0,0,0.5,0.3,0.6,1")]
        [InlineData("l,1,0,100,200,0,0,321,0,0.5,0.3,0.6,1")]
        [InlineData("l,1,0,100,200,1,0,110,0,0.5,0.3,0.6,1")]
        [InlineData("l,1,0,100,200,0,1,110,0,0.5,0.3,0.6,1")]
        [InlineData("l,1,0,100,200,0,0,110,0.5,0.5,0.3,0.6,1")]
        [InlineData("l,1,0,100,200,0,0,110,0,NaN,0.3,0.6,1")]
        [InlineData("l,1,0,100,200,0,0,110,0,0.5,0.3,0.6,1,100,200,30,0.5")]
        [InlineData("l,1,0,100,200,0,0,110,0,0.5,0.3,0.6,1,1,0,0,0")]
        public void RadialReservedFieldsAndBoundsRemainStrict(string malformed)
        {
            Assert.False(CombatFxFrame.TryParse("1|1|1|0;"+Flash()+";"+malformed,Catalog,out _));
        }

        [Fact]
        public void RadialThirteenAndSeventeenFieldRecordsUseTheExistingNativePointShape()
        {
            var e=new CombatFxEngine(Catalog);
            e.Apply(Frame(1,1,"l,1,0,100,200,0,0,110,0,0.5,0.3,0.6,1"),1);
            float[] expected={100,200,110,.5f,.3f,.6f,1,0,0,0,0,0,0,0,0,0};
            Assert.Equal(expected,e.BuildDraw().Lights.Take(CombatFxEngine.LightStride));
            e.Apply(Frame(2,2,Sphere(1)),1);
            Assert.Equal(expected,e.BuildDraw().Lights.Take(CombatFxEngine.LightStride));
            Assert.Equal(1,e.BuildDraw().LightCount);
        }

        [Fact]
        public void RadialResidentEnergyDoesNotBecomeAGunfirePulse()
        {
            var e=new CombatFxEngine(Catalog);
            e.Apply(Frame(1,1,Sphere(1)+";"+Flash()),1);
            for(int tick=2;tick<20;tick++)
            {
                e.Apply(Frame(tick,tick,Sphere(1)),1);
                Assert.Equal(.5f,e.BuildDraw().Lights[3]);
            }
            Assert.Equal(1,e.BuildDraw().LightCount);
            e.Apply(Frame(20,200,Sphere(1),paused:true),1);
            Assert.Equal(.5f,e.BuildDraw().Lights[3]);
            e.Apply(Frame(21,201,paused:true),1);
            Assert.Equal(0,e.BuildDraw().LightCount);
        }

        [Fact]
        public void As2AdmissionCanReplaceOneNpcWithALaterPlayerWithoutRotatingSurvivors()
        {
            var e=new CombatFxEngine(Catalog);
            e.Apply(Frame(1,1,string.Join(";",Enumerable.Range(1,16).Select(i=>Sphere(i,i*10)))),1);
            float[] first=(float[])e.BuildDraw().Lights.Clone();
            string admitted=string.Join(";",Enumerable.Range(1,15).Select(i=>Sphere(i,i*10)))+";"+Sphere(900,900);
            e.Apply(Frame(2,2,admitted),1);
            var draw=e.BuildDraw();
            Assert.Equal(16,draw.LightCount);
            Assert.Equal(first.Take(15*CombatFxEngine.LightStride),draw.Lights.Take(15*CombatFxEngine.LightStride));
            Assert.Equal(900f,draw.Lights[15*CombatFxEngine.LightStride]);
            Assert.Equal(0,e.LightDropped);
        }

        [Fact]
        public void CompositeSlotReusedForRadialHasNoNearTailAndEpochClearsIt()
        {
            var e=new CombatFxEngine(Catalog);
            e.Apply(Frame(1,1,Torch(1)),1);
            e.Apply(Frame(2,2,Sphere(2)),1);
            var draw=e.BuildDraw();
            Assert.Equal(0f,draw.Lights[7]);
            Assert.All(draw.Lights.Skip(8).Take(8),value=>Assert.Equal(0f,value));
            e.Apply(Frame(1,0,epoch:2),1);
            Assert.Equal(0,e.BuildDraw().LightCount);
        }

        [Fact]
        public void DuplicateOrOverflowingLightIdsRejectTheWholeFrame()
        {
            Assert.False(CombatFxFrame.TryParse($"1|1|1|0;{Cone(3)};{Cone(3,300)}",Catalog,out _));
            string cap=string.Join(";",Enumerable.Range(1,64).Select(i=>Cone(i)));
            Assert.True(CombatFxFrame.TryParse("1|1|1|0;"+cap,Catalog,out var f));
            Assert.Equal(64,f.EquipmentLights.Length);
            Assert.False(CombatFxFrame.TryParse("1|1|1|0;"+cap+";"+Cone(65),Catalog,out _));
        }

        [Fact]
        public void WireBudgetAdmitsSixtyFourLightsAlongsideExistingRecords()
        {
            var parts=Enumerable.Range(1,64).Select(i=>Cone(i))
                .Concat(Enumerable.Repeat(Flash(),32))
                .Concat(Enumerable.Repeat(Hit(),32))
                .Concat(Enumerable.Range(1,64).Select(i=>$"a,{i},1"));
            string body=string.Join(";",parts);
            Assert.True(CombatFxFrame.TryParse("1|1|1|0;"+body,Catalog,out var f));
            Assert.Equal(64,f.EquipmentLights.Length);
            Assert.Equal(64,f.Spawns.Length);
            Assert.False(CombatFxFrame.TryParse("1|1|1|0;"+body+";a,65,1",Catalog,out _));
        }

        [Fact]
        public void LightFieldsMapOntoTheSixteenFloatNativeStride()
        {
            Assert.Equal(16,CombatFxEngine.LightStride);
            var e=new CombatFxEngine(Catalog);
            e.Apply(Frame(1,1,"l,4,2,50,60,0,-1,400,2,1.5,0.25,0.5,0.75"),1);
            var draw=e.BuildDraw();
            Assert.Equal(1,draw.LightCount);
            float[] l=draw.Lights;
            Assert.Equal(50f,l[0]);Assert.Equal(60f,l[1]);Assert.Equal(400f,l[2]);Assert.Equal(1.5f,l[3]);
            Assert.Equal(.25f,l[4]);Assert.Equal(.5f,l[5]);Assert.Equal(.75f,l[6]);Assert.Equal(2f,l[7]);
            Assert.Equal(0f,l[8]);Assert.Equal(-1f,l[9]);Assert.Equal(2f,l[10]);Assert.Equal(0f,l[11]);
            Assert.Equal(0f,l[12]);Assert.Equal(0f,l[13]);Assert.Equal(0f,l[14]);Assert.Equal(0f,l[15]);
        }

        [Fact]
        public void MissingLightRecordsClearResidents()
        {
            var e=new CombatFxEngine(Catalog);
            e.Apply(Frame(1,1,Cone(1)+";"+Cone(2,300)),1);
            Assert.Equal(2,e.BuildDraw().LightCount);
            e.Apply(Frame(2,2),1);
            Assert.Equal(0,e.BuildDraw().LightCount);
            e.Apply(Frame(3,3,Cone(2,300)+";"+Cone(1)),1);
            var draw=e.BuildDraw();
            Assert.Equal(2,draw.LightCount);
            Assert.Equal(100f,draw.Lights[0]);Assert.Equal(300f,draw.Lights[16]);
        }

        [Fact]
        public void ReorderingASaturatedSnapshotCannotRotateSlots()
        {
            var e=new CombatFxEngine(Catalog);
            string Snapshot(bool reversed)=>string.Join(";",
                (reversed?Enumerable.Range(1,16).Select(i=>17-i):Enumerable.Range(1,16)).Select(i=>Cone(i,i*10)));
            e.Apply(Frame(1,1,Snapshot(false)),1);
            var first=(float[])e.BuildDraw().Lights.Clone();
            e.Apply(Frame(2,1,Snapshot(true)),1);
            Assert.Equal(first,e.BuildDraw().Lights);
            e.Apply(Frame(3,1,Snapshot(false)+";"+Cone(17,170)),1);
            Assert.Equal(first,e.BuildDraw().Lights);
            Assert.Equal(16,e.BuildDraw().LightCount);
            Assert.Equal(1,e.LightDropped);
        }

        [Fact]
        public void SurvivingIdsKeepSlotsAndNewIdsFillAscending()
        {
            var e=new CombatFxEngine(Catalog);
            e.Apply(Frame(1,1,Cone(5,50)+";"+Cone(8,80)),1);
            e.Apply(Frame(2,1,Cone(9,90)+";"+Cone(3,30)+";"+Cone(5,50)),1);
            var draw=e.BuildDraw();
            Assert.Equal(3,draw.LightCount);
            Assert.Equal(50f,draw.Lights[0]);Assert.Equal(30f,draw.Lights[16]);Assert.Equal(90f,draw.Lights[32]);
        }

        [Fact]
        public void SaturatedGunfireCannotDisplaceResidents()
        {
            var e=new CombatFxEngine(Catalog);
            e.Apply(Frame(1,1,Cone(1)+";"+Cone(2,300)+";"+string.Join(";",Enumerable.Repeat(Flash(),32))),1);
            var draw=e.BuildDraw();
            Assert.Equal(16,draw.LightCount);
            Assert.Equal(1f,draw.Lights[7]);Assert.Equal(100f,draw.Lights[0]);
            Assert.Equal(1f,draw.Lights[23]);Assert.Equal(300f,draw.Lights[16]);
            Assert.Equal(0f,draw.Lights[39]);Assert.Equal(300f,draw.Lights[32]);
            Assert.Equal(16,e.LightDropped);
        }

        [Fact]
        public void ResidentExitReleasesBudgetBackToGunfire()
        {
            var e=new CombatFxEngine(Catalog);
            e.Apply(Frame(1,1,Cone(1)+";"+Flash()+";"+Flash()),1);
            var draw=e.BuildDraw();
            Assert.Equal(3,draw.LightCount);
            Assert.Equal(1f,draw.Lights[7]);Assert.Equal(0f,draw.Lights[23]);
            e.Apply(Frame(2,1),1);
            draw=e.BuildDraw();
            Assert.Equal(2,draw.LightCount);
            Assert.Equal(0f,draw.Lights[7]);Assert.Equal(300f,draw.Lights[0]);
        }

        [Fact]
        public void EpochGenerationAndStallResetResidents()
        {
            var e=new CombatFxEngine(Catalog);
            e.Apply(Frame(1,1,Cone(1)),1);
            Assert.True(e.Apply(Frame(1,0,Cone(2,300),epoch:2),1));
            Assert.Equal(300f,e.BuildDraw().Lights[0]);
            Assert.False(e.Apply(Frame(2,2,Cone(3,500),epoch:1),1));
            Assert.Equal(300f,e.BuildDraw().Lights[0]);
            Assert.False(e.Apply(Frame(3,3,Cone(4,700),epoch:2),0));
            Assert.Equal(300f,e.BuildDraw().Lights[0]);
            Assert.True(e.Apply(Frame(2,20,epoch:2),1));
            Assert.Equal(0,e.BuildDraw().LightCount);
            Assert.True(e.Apply(Frame(3,30,Cone(9,900),epoch:2),1));
            Assert.Equal(900f,e.BuildDraw().Lights[0]);
        }

        [Fact]
        public void PausedFramesStillApplySnapshotsWithoutAdvancingGunfire()
        {
            var e=new CombatFxEngine(Catalog);
            e.Apply(Frame(1,1,Flash()+";"+Cone(1)),1);
            var draw=e.BuildDraw();
            Assert.Equal(2,draw.LightCount);
            float energy=draw.Lights[19];
            e.Apply(Frame(2,200,Cone(2,300),paused:true),1);
            draw=e.BuildDraw();
            Assert.Equal(2,draw.LightCount);
            Assert.Equal(300f,draw.Lights[0]);Assert.Equal(energy,draw.Lights[19]);
            e.Apply(Frame(3,201,paused:true),1);
            draw=e.BuildDraw();
            Assert.Equal(1,draw.LightCount);
            Assert.Equal(0f,draw.Lights[7]);Assert.Equal(energy,draw.Lights[3]);
        }

        [Fact]
        public void LegacyThirteenFieldRecordsParseWithAnEmptyNearTail()
        {
            Assert.True(CombatFxFrame.TryParse("1|1|1|0;"+Cone(1),Catalog,out var legacy));
            CombatFxEquipmentLight light=legacy.EquipmentLights[0];
            Assert.Equal(0f,light.NearX);Assert.Equal(0f,light.NearY);
            Assert.Equal(0f,light.NearRadius);Assert.Equal(0f,light.NearEnergy);
            Assert.True(CombatFxFrame.TryParse("1|1|1|0;l,2,2,50,60,0,-1,400,2,1.5,0.25,0.5,0.75,0,0,0,0",Catalog,out var padded));
            Assert.Equal(0f,padded.EquipmentLights[0].NearRadius);
            var e=new CombatFxEngine(Catalog);
            e.Apply(Frame(1,1,Cone(1)),1);
            float[] l=e.BuildDraw().Lights;
            Assert.Equal(0f,l[12]);Assert.Equal(0f,l[13]);Assert.Equal(0f,l[14]);Assert.Equal(0f,l[15]);
        }

        [Fact]
        public void NearFillTailMapsOntoTheStrideTail()
        {
            var e=new CombatFxEngine(Catalog);
            e.Apply(Frame(1,1,Torch(3,50)),1);
            var draw=e.BuildDraw();
            Assert.Equal(1,draw.LightCount);
            float[] l=draw.Lights;
            Assert.Equal(50f,l[0]);Assert.Equal(1000f,l[2]);Assert.Equal(1.8f,l[3]);
            Assert.Equal(1f,l[7]);Assert.Equal(280f,l[10]);
            Assert.Equal(50f,l[12]);Assert.Equal(200f,l[13]);
            Assert.Equal(220f,l[14]);Assert.Equal(1.65f,l[15]);
        }

        [Fact]
        public void SaturatedBudgetAdmitsOrDropsTheCompositeAsOneRecord()
        {
            var e=new CombatFxEngine(Catalog);
            string sixteen=string.Join(";",Enumerable.Range(1,16).Select(i=>Cone(i,i*10)));
            e.Apply(Frame(1,1,sixteen+";"+Torch(20,500)),1);
            var draw=e.BuildDraw();
            Assert.Equal(16,draw.LightCount);
            Assert.Equal(1,e.LightDropped);
            for (int i=0;i<16;i++)
            {
                Assert.NotEqual(500f,draw.Lights[i*16]);
                Assert.Equal(0f,draw.Lights[i*16+14]);Assert.Equal(0f,draw.Lights[i*16+15]);
            }
            string fifteen=string.Join(";",Enumerable.Range(1,15).Select(i=>Cone(i,i*10)));
            e.Apply(Frame(2,2,fifteen+";"+Torch(20,500)),1);
            draw=e.BuildDraw();
            Assert.Equal(16,draw.LightCount);
            Assert.Equal(500f,draw.Lights[15*16]);Assert.Equal(1f,draw.Lights[15*16+7]);
            Assert.Equal(500f,draw.Lights[15*16+12]);Assert.Equal(200f,draw.Lights[15*16+13]);
            Assert.Equal(220f,draw.Lights[15*16+14]);Assert.Equal(1.65f,draw.Lights[15*16+15]);
            e.Apply(Frame(3,3,fifteen),1);
            draw=e.BuildDraw();
            Assert.Equal(15,draw.LightCount);
            for (int i=0;i<15;i++) Assert.Equal(0f,draw.Lights[i*16+14]);
        }

        [Fact]
        public void EvictedCompositeLeavesNoStaleNearFieldsBehind()
        {
            var e=new CombatFxEngine(Catalog);
            e.Apply(Frame(1,1,Torch(1,500)),1);
            Assert.Equal(220f,e.BuildDraw().Lights[14]);
            e.Apply(Frame(2,2,Cone(1)+";"+Cone(2,300)),1);
            float[] l=e.BuildDraw().Lights;
            Assert.Equal(0f,l[12]);Assert.Equal(0f,l[13]);Assert.Equal(0f,l[14]);Assert.Equal(0f,l[15]);
            Assert.Equal(0f,l[16+12]);Assert.Equal(0f,l[16+13]);
            Assert.Equal(0f,l[16+14]);Assert.Equal(0f,l[16+15]);
            e.Apply(Frame(3,3,Flash()),1);
            var draw=e.BuildDraw();
            Assert.Equal(1,draw.LightCount);
            l=draw.Lights;
            Assert.Equal(0f,l[7]);
            Assert.Equal(0f,l[12]);Assert.Equal(0f,l[13]);Assert.Equal(0f,l[14]);Assert.Equal(0f,l[15]);
        }

        [Fact]
        public void CompositeIdsFillFreeSlotsInAscendingOrder()
        {
            var e=new CombatFxEngine(Catalog);
            e.Apply(Frame(1,1,Cone(5,50)+";"+Cone(8,80)),1);
            e.Apply(Frame(2,2,Torch(9,90)+";"+Cone(3,30)+";"+Cone(8,80)+";"+Cone(5,50)),1);
            var draw=e.BuildDraw();
            Assert.Equal(4,draw.LightCount);
            var first=(float[])draw.Lights.Clone();
            Assert.Equal(50f,first[0]);Assert.Equal(80f,first[16]);
            Assert.Equal(30f,first[32]);
            Assert.Equal(90f,first[48]);Assert.Equal(1f,first[48+7]);
            Assert.Equal(220f,first[48+14]);Assert.Equal(1.65f,first[48+15]);
            e.Apply(Frame(3,3,Torch(9,90)+";"+Cone(3,30)+";"+Cone(8,80)+";"+Cone(5,50)),1);
            Assert.Equal(first,e.BuildDraw().Lights);
        }
    }
}
