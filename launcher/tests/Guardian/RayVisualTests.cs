using System;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Text.RegularExpressions;
using CF7Launcher.Guardian.WorldCompositor;
using Xunit;

namespace CF7Launcher.Tests.Guardian
{
    public sealed class RayVisualTests
    {
        private static float[] Values()
        {
            float[] v=Enumerable.Repeat(1f,RayVisualCatalog.FieldNames.Length).ToArray();
            v[0]=0xFF8800;v[1]=0xFFDD88;v[2]=4;v[3]=20;v[4]=3;v[5]=0;
            v[6]=70;v[7]=100;v[10]=35;v[11]=40;v[14]=.7f;v[20]=60;v[24]=15;
            v[25]=50;v[37]=1;v[41]=0x7A6F66;v[42]=0xFFB347;v[49]=0x34302A;
            return v;
        }
        private static string Config(int style=0,int id=1,float[] values=null,string palette="-") =>
            $"c,{id},{style},"+string.Join(',',(values??Values()).Select(v=>v.ToString(CultureInfo.InvariantCulture)))+","+palette;
        private static string Spawn(int id=1,int cfg=1,int born=0,int delay=0,int kind=0,int key=0,int serial=0,
            string operation="s",string points="-",string damage="-",int flags=2,float end=200,int seed=123) =>
            FormattableString.Invariant($"{operation},{id},{cfg},{born},{delay},100,50,{end},50,{kind},0,1,0,{seed},{key},{serial},500,1,5,{flags},{points},{damage},0");
        private static RayVisualFrame Frame(int seq,int tick,string events="",int epoch=1,bool paused=false,float ox=0,float oy=0)
        {
            string payload=FormattableString.Invariant($"{epoch}|{seq}|{tick}|{(paused?1:0)};o,{ox},{oy}")+(events.Length==0?"":";"+events);
            Assert.True(RayVisualFrame.TryParse(payload,out var frame),payload);
            return frame;
        }

        [Fact]
        public void AllResolvedStyleParametersCrossTheProtocolAndStayDistinct()
        {
            var e=new RayVisualEngine();
            string events=string.Join(';',Enumerable.Range(0,12).Select(i=>Config(i,i+1)+";"+Spawn(i+1,i+1,kind:i==11?4:0)));
            Assert.True(e.Apply(Frame(1,1,events),1));
            var draw=e.BuildDraw();
            Assert.Equal(12,e.ActiveCount);Assert.Equal(12,draw.Count);
            for (int i=0;i<12;i++)
            {
                Assert.Equal(i,draw.Data[i*32+15]);
                int[] fields=RayVisualCatalog.ParameterFields[i];
                for (int k=0;k<fields.Length;k++) Assert.Equal(Values()[fields[k]],draw.Data[i*32+20+k]);
            }
        }

        [Theory]
        [InlineData(3,3,0x0066FF)]
        [InlineData(4,5,0x8800FF)]
        public void MissingPaletteUsesTheOriginalRenderersColdColours(int style,int count,int third)
        {
            var engine=new RayVisualEngine();
            Assert.True(engine.Apply(Frame(1,1,Config(style)+";"+Spawn()),1));
            var data=engine.BuildDraw().Data;
            Assert.Equal(count,data[24]);Assert.Equal(0xFF00FF,data[25]);
            Assert.Equal(0x00FFFF,data[26]);Assert.Equal(third,data[27]);
            if(style==4) {Assert.Equal(0x0088FF,data[28]);Assert.Equal(0xFF66FF,data[29]);}
        }

        [Fact]
        public void ExplicitResonancePaletteRemainsAnAuthoredOverride()
        {
            var engine=new RayVisualEngine();
            Assert.True(engine.Apply(Frame(1,1,Config(4,palette:"16711680:65280:255")+";"+Spawn()),1));
            var data=engine.BuildDraw().Data;
            Assert.Equal(3,data[24]);Assert.Equal(0xFF0000,data[25]);
            Assert.Equal(0x00FF00,data[26]);Assert.Equal(0x0000FF,data[27]);
        }

        [Fact]
        public void BaguaKeepsOneGeometryAndItsAuthoredBurstDurationThroughFade()
        {
            var values=Values();values[3]=9;values[4]=4;
            values[32]=8;values[33]=75;values[34]=35;values[35]=.5f;
            values[41]=0xAB9876;values[42]=0xFFCC55;values[45]=3;values[46]=2;
            var engine=new RayVisualEngine();
            Assert.True(engine.Apply(Frame(1,7,Config(10,values:values)+";"+Spawn(born:0)),1));
            Assert.True(engine.Apply(Frame(2,11),1));
            var draw=engine.BuildDraw();Assert.Equal(1,draw.Count);
            Assert.Equal(10,draw.Data[15]);Assert.Equal(11,draw.Data[12]);
            Assert.Equal(9,draw.Data[13]);Assert.Equal(.5f,draw.Data[7]);
            Assert.Equal(0xFFCC55,draw.Data[14]);Assert.Equal(3,draw.Data[17]);
            Assert.Equal(2,draw.Data[18]);Assert.Equal(0xAB9876,draw.Data[19]);
            Assert.Equal(8,draw.Data[20]);Assert.Equal(75,draw.Data[21]);
            Assert.Equal(35,draw.Data[22]);Assert.Equal(.5f,draw.Data[23]);
        }

        [Theory]
        [InlineData(0)]
        [InlineData(4)]
        public void OriginalRetainedDrawingFreezesWhileItsFadeAndLifetimeAdvance(int style)
        {
            var values=Values();values[3]=3;values[4]=6;
            var engine=new RayVisualEngine();
            Assert.True(engine.Apply(Frame(1,2,Config(style,values:values)+";"+Spawn()),1));
            Assert.Equal(2,engine.BuildDraw().Data[12]);
            Assert.True(engine.Apply(Frame(2,5),1));
            Assert.Equal(3,engine.BuildDraw().Data[12]);Assert.Equal(2f/3,engine.BuildDraw().Data[7],5);
            Assert.True(engine.Apply(Frame(3,7),1));
            Assert.Equal(3,engine.BuildDraw().Data[12]);Assert.Equal(1f/3,engine.BuildDraw().Data[7],5);
            Assert.True(engine.Apply(Frame(4,10),1));Assert.Equal(0,engine.BuildDraw().Count);
        }

        [Theory]
        [InlineData("1|1|1|2")]
        [InlineData("1|1|1|0;")]
        [InlineData("1|1|1|0;o,NaN,0")]
        [InlineData("1|1|1|0;o,0,0;o,1,2")]
        [InlineData("1|1|1|0;x,-1,0")]
        [InlineData("1|1|1|0;x,1,-1")]
        public void MalformedPacketsAreRejectedBeforeStateExists(string payload) => Assert.False(RayVisualFrame.TryParse(payload,out _));

        [Fact]
        public void MalformedSpawnAndPaletteAreRejected()
        {
            Assert.False(RayVisualFrame.TryParse("1|1|1|0;"+Spawn().Replace(",100,50,",",NaN,50,"),out _));
            Assert.False(RayVisualFrame.TryParse("1|1|1|0;"+Config(palette:"16777216"),out _));
            Assert.False(RayVisualFrame.TryParse("1|1|1|0;"+Spawn(operation:"u"),out _));
            Assert.False(RayVisualFrame.TryParse("1|1|1|0;"+Spawn(points:"1:2/3"),out _));
            float[] v=Values();v[2]=float.PositiveInfinity;
            Assert.False(RayVisualFrame.TryParse("1|1|1|0;"+Config(values:v),out _));
        }

        [Fact]
        public void OrderedEventsCannotBeReplayedOrReplacedByAnOlderConnection()
        {
            var e=new RayVisualEngine();var first=Frame(1,1,Config()+";"+Spawn());
            Assert.True(e.Apply(first,2));Assert.False(e.Apply(first,2));
            Assert.False(e.Apply(Frame(2,2,Spawn(id:2,born:1)),1));
            Assert.True(e.Apply(Frame(2,2,Spawn(id:2,born:1)),2));
            Assert.Equal(2,e.BuildDraw().Count);
        }

        [Fact]
        public void PauseFreezesAgeAndResumeNeverIntegratesWallTime()
        {
            var e=new RayVisualEngine();e.Apply(Frame(1,1,Config()+";"+Spawn()),1);
            float phase=e.BuildDraw().Data[12];
            e.Apply(Frame(2,200,paused:true),1);Assert.Equal(phase,e.BuildDraw().Data[12]);
            e.Apply(Frame(3,201),1);Assert.Equal(phase+1,e.BuildDraw().Data[12]);
        }

        [Fact]
        public void DelayedSegmentUsesTheSceneOffsetWhenItMaterializesExactlyOnce()
        {
            var e=new RayVisualEngine();
            e.Apply(Frame(1,1,Config()+";"+Spawn(delay:3,kind:3,points:"140:50"),ox:10,oy:20),1);
            Assert.Equal(0,e.BuildDraw().Count);
            e.Apply(Frame(2,2,ox:30,oy:40),1);Assert.Equal(0,e.BuildDraw().Count);
            e.Apply(Frame(3,3,ox:50,oy:70),1);
            Assert.Equal(2,e.BuildDraw().Count);
            Assert.Equal(140,e.BuildDraw().Data[0]);Assert.Equal(100,e.BuildDraw().Data[1]);
            Assert.Equal(180,e.BuildDraw().Data[32]);Assert.Equal(100,e.BuildDraw().Data[33]);
            e.Apply(Frame(4,4,ox:100,oy:200),1);Assert.Equal(140,e.BuildDraw().Data[0]);
        }

        [Fact]
        public void MissingConfigAndChangedImmutableIdRejectAtomically()
        {
            var e=new RayVisualEngine();e.Apply(Frame(1,1,Config()+";"+Spawn()),1);
            var before=e.BuildDraw().Data.Take(32).ToArray();
            Assert.False(e.Apply(Frame(2,2,Spawn(id:2,cfg:2,born:1)),1));
            Assert.Equal(before,e.BuildDraw().Data.Take(32).ToArray());
            var altered=Values();altered[2]=100;
            Assert.False(e.Apply(Frame(2,2,Config(values:altered)),1));
            Assert.True(e.Apply(Frame(2,2,Config(id:2,values:altered)+";"+Spawn(id:2,cfg:2,born:1)),1));
            Assert.Equal(2,e.ActiveCount);Assert.Equal(100,e.BuildDraw().Data[32+11]);
        }

        [Fact]
        public void SceneAndGenerationChangesClearArcsAndRequireFreshConfigDefinitions()
        {
            var e=new RayVisualEngine();e.Apply(Frame(1,1,Config()+";"+Spawn()),1);
            Assert.False(e.Apply(Frame(1,0,Spawn(),epoch:2),1));
            Assert.Equal(1,e.ActiveCount);
            Assert.True(e.Apply(Frame(1,0,epoch:2),1));Assert.Equal(0,e.ActiveCount);
            Assert.False(e.Apply(Frame(9,9,Config()+";"+Spawn(),epoch:1),1));
            Assert.True(e.Apply(Frame(1,1,Config()+";"+Spawn()),2));Assert.Equal(1,e.ActiveCount);
            e.Reset();Assert.Equal(0,e.BuildDraw().Count);
        }

        [Fact]
        public void LargeTickGapRetiresStaleArcsAndAcceptsCurrentPersistentUpdates()
        {
            var e=new RayVisualEngine();e.Apply(Frame(1,1,Config(11)+";"+Spawn(kind:4,key:1,serial:1)),1);
            e.Apply(Frame(2,30,Spawn(born:29,kind:4,key:1,serial:2,operation:"u",end:350)),1);
            Assert.Equal(1,e.ActiveCount);Assert.Equal(350,e.BuildDraw().Data[2]);
            Assert.Equal(1,e.BuildDraw().Data[12]);
        }

        [Fact]
        public void FlameRefreshPreservesPhaseSeedAndIgnoresOlderSerialAndStop()
        {
            var e=new RayVisualEngine();e.Apply(Frame(1,1,Config(11)+";"+Spawn(kind:4,key:1,serial:3)),1);
            float seed=e.BuildDraw().Data[14];
            e.Apply(Frame(2,2,Spawn(born:1,kind:4,key:1,serial:4,operation:"u",end:350,seed:999)),1);
            Assert.Equal(350,e.BuildDraw().Data[2]);Assert.Equal(2,e.BuildDraw().Data[12]);
            Assert.Equal(seed,e.BuildDraw().Data[14]);
            e.Apply(Frame(3,3,Spawn(born:2,kind:4,key:1,serial:3,operation:"u",end:50)+";x,1,3"),1);
            Assert.Equal(350,e.BuildDraw().Data[2]);
            e.Apply(Frame(4,4,"x,1,4"),1);
            e.Apply(Frame(5,5,Spawn(born:4,kind:4,key:1,serial:4,operation:"u",end:90)),1);
            Assert.Equal(350,e.BuildDraw().Data[2]);
        }

        [Fact]
        public void FlameMarksDamagePointsOnlyDuringActualDamagePulses()
        {
            var e=new RayVisualEngine();
            e.Apply(Frame(1,1,Config(11)+";"+Spawn(kind:4,key:1,serial:1,points:"110:50",damage:"180:50",flags:3)),1);
            Assert.Equal(2,e.BuildDraw().Count);Assert.Equal(180,e.BuildDraw().Data[32]);
            Assert.Equal(1,e.BuildDraw().Data[29]);Assert.Equal(1,e.BuildDraw().Data[30]);
            e.Apply(Frame(2,2,Spawn(born:1,kind:4,key:1,serial:1,operation:"u",points:"110:50",flags:4)),1);
            Assert.Equal(1,e.BuildDraw().Count);Assert.Equal(1,e.BuildDraw().Data[31]);
        }

        [Fact]
        public void DecorationPressureNeverConsumesThePrimaryBeamBudget()
        {
            var e=new RayVisualEngine();string points=string.Join('/',Enumerable.Range(0,128).Select(i=>$"{i}:50"));
            e.Apply(Frame(1,1,Config()+";"+string.Join(';',Enumerable.Range(1,128).Select(i=>Spawn(i,points:points)))),1);
            e.Apply(Frame(2,2,string.Join(';',Enumerable.Range(129,128).Select(i=>Spawn(i,born:1,points:points)))),1);
            var d=e.BuildDraw();Assert.Equal(RayVisualCatalog.DrawLimit,d.Count);Assert.Equal(256,e.ActiveCount);
            for (int i=0;i<256;i++) Assert.Equal(0,d.Data[i*32+15]);
            Assert.True(e.DecorationDropped>0);
            for (int batch=0;batch<6;batch++)
            {
                int first=257+batch*128,tick=3+batch;
                Assert.True(e.Apply(Frame(tick,tick,string.Join(';',Enumerable.Range(first,128)
                    .Select(i=>Spawn(i,born:tick-1)))),1));
            }
            Assert.Equal(RayVisualCatalog.ArcLimit,e.ActiveCount);
            Assert.False(e.Apply(Frame(9,9,Spawn(2000,born:8)),1));Assert.Equal(RayVisualCatalog.ArcLimit,e.ActiveCount);
        }

        [Theory]
        [InlineData(0)] [InlineData(1)] [InlineData(2)] [InlineData(3)] [InlineData(4)]
        [InlineData(5)] [InlineData(6)] [InlineData(7)] [InlineData(8)] [InlineData(9)]
        public void GenericChannelsReuseOneBodyAndKeepPhaseAndSeedAcrossDistinctShots(int style)
        {
            var values=Values();values[3]=2;values[4]=3;
            var engine=new RayVisualEngine();
            Assert.True(engine.Apply(Frame(1,0,Config(style,values:values)+";"+Spawn(key:7,serial:1)),1));
            float seed=engine.BuildDraw().Data[14];
            for(int tick=1;tick<=40;tick++)
            {
                Assert.True(engine.Apply(Frame(tick+1,tick,Spawn(born:tick,key:7,serial:tick+1,
                    operation:"u",end:200+tick,seed:999)),1));
                var draw=engine.BuildDraw();
                Assert.Equal(1,draw.Count);Assert.Equal(1,engine.ActiveCount);
                Assert.Equal(200+tick,draw.Data[2]);Assert.Equal(1f,draw.Data[7]);
                Assert.Equal(tick,draw.Data[12]);Assert.Equal(seed,draw.Data[14]);
                if(style==0)Assert.Equal(0,draw.Data[27]); // ABI 12 fresh emission pulse
            }
        }

        [Theory]
        [InlineData(0)] [InlineData(1)] [InlineData(2)] [InlineData(3)] [InlineData(4)]
        [InlineData(5)] [InlineData(6)] [InlineData(7)] [InlineData(8)] [InlineData(9)]
        public void ChannelPhaseFreezesOnlyAfterTheLastEmissionHoldAndResumesOnANewShot(int style)
        {
            var values=Values();values[3]=2;values[4]=4;
            var engine=new RayVisualEngine();
            engine.Apply(Frame(1,0,Config(style,values:values)+";"+Spawn(key:7,serial:1)),1);
            engine.Apply(Frame(2,2,Spawn(born:2,key:7,serial:2,operation:"u")),1);
            Assert.Equal(2,engine.BuildDraw().Data[12]);
            engine.Apply(Frame(3,5),1);
            Assert.Equal(4,engine.BuildDraw().Data[12]);Assert.Equal(.75f,engine.BuildDraw().Data[7]);
            if(style==0)Assert.Equal(3,engine.BuildDraw().Data[27]);
            engine.Apply(Frame(4,6),1);Assert.Equal(4,engine.BuildDraw().Data[12]);
            engine.Apply(Frame(5,6,Spawn(born:6,key:7,serial:3,operation:"u")),1);
            Assert.Equal(4,engine.BuildDraw().Data[12]);Assert.Equal(1,engine.BuildDraw().Data[7]);
            engine.Apply(Frame(6,7),1);Assert.Equal(5,engine.BuildDraw().Data[12]);
        }

        [Theory]
        [InlineData(0)] [InlineData(1)] [InlineData(2)] [InlineData(3)] [InlineData(4)]
        [InlineData(5)] [InlineData(6)] [InlineData(7)] [InlineData(8)] [InlineData(9)]
        public void PhaseMatchesAs2WhenAFreshShotIsBornBeforeTheFlushTickAfterAnOldFade(int style)
        {
            var values=Values();values[3]=2;values[4]=5;
            var engine=new RayVisualEngine();
            engine.Apply(Frame(1,1,Config(style,values:values)+";"+Spawn(key:7,serial:1)),1);
            Assert.Equal(1,engine.BuildDraw().Data[12]);
            engine.Apply(Frame(2,4),1);Assert.Equal(2,engine.BuildDraw().Data[12]);
            engine.Apply(Frame(3,5,Spawn(born:4,key:7,serial:2,operation:"u")),1);
            Assert.Equal(3,engine.BuildDraw().Data[12]);
            engine.Apply(Frame(4,6,Spawn(born:5,key:7,serial:3,operation:"u")),1);
            Assert.Equal(4,engine.BuildDraw().Data[12]);
            engine.Apply(Frame(5,9),1);Assert.Equal(5,engine.BuildDraw().Data[12]);
        }

        [Fact]
        public void SameSerialGeometrySnapshotsCannotRefreshTheGenericPulseOrItsLifetime()
        {
            var values=Values();values[3]=2;values[4]=3;
            var engine=new RayVisualEngine();
            engine.Apply(Frame(1,0,Config(values:values)+";"+Spawn(key:7,serial:1)),1);
            engine.Apply(Frame(2,4,Spawn(born:4,key:7,serial:1,operation:"u",end:350)),1);
            var draw=engine.BuildDraw();Assert.Equal(350,draw.Data[2]);Assert.Equal(4,draw.Data[27]);
            Assert.Equal(1f/3,draw.Data[7],5);Assert.Equal(2,draw.Data[12]);
            engine.Apply(Frame(3,6),1);Assert.Equal(0,engine.ActiveCount);Assert.Equal(0,engine.BuildDraw().Count);
        }

        [Fact]
        public void RetiredGenericSerialCannotRestartAtExpiryOrAfterTheLastBodyHasGone()
        {
            var values=Values();values[3]=1;values[4]=1;
            var engine=new RayVisualEngine();
            engine.Apply(Frame(1,0,Config(values:values)+";"+Spawn(key:7,serial:4)),1);
            engine.Apply(Frame(2,3,Spawn(born:3,key:7,serial:4,operation:"u")),1);
            Assert.Equal(0,engine.ActiveCount);
            engine.Apply(Frame(3,4,Spawn(id:2,born:4,key:7,serial:3)),1);Assert.Equal(0,engine.ActiveCount);
            engine.Apply(Frame(4,5,Spawn(id:2,born:5,key:7,serial:4)),1);Assert.Equal(0,engine.ActiveCount);
            engine.Apply(Frame(5,6,Spawn(id:2,born:6,key:7,serial:5)),1);Assert.Equal(1,engine.ActiveCount);
            Assert.Equal(0,engine.BuildDraw().Data[12]);
        }

        [Theory]
        [InlineData("config")] [InlineData("style")] [InlineData("key")] [InlineData("kind")]
        public void AnArcIdCannotChangeItsImmutableBindingEvenAfterEarlierValidEventsInThePacket(string change)
        {
            var engine=new RayVisualEngine();
            engine.Apply(Frame(1,0,Config()+";"+Config(0,2)+";"+Config(1,3)+";"+Spawn(key:7,serial:1)),1);
            var before=engine.BuildDraw().Data.Take(32).ToArray();
            string invalid=Spawn(cfg:change=="config"?2:change=="style"?3:1,kind:change=="kind"?1:0,
                key:change=="key"?9:7,serial:2,born:1,operation:"u");
            Assert.False(engine.Apply(Frame(2,1,Spawn(id:2,key:8,serial:1,born:1)+";"+invalid),1));
            Assert.Equal(before,engine.BuildDraw().Data.Take(32));Assert.Equal(1,engine.ActiveCount);
            Assert.True(engine.Apply(Frame(2,1,Spawn(key:7,serial:2,born:1,operation:"u",end:300)),1));
            Assert.Equal(300,engine.BuildDraw().Data[2]);
        }

        [Fact]
        public void SamePacketBindingsAndStopSerialFloorsApplyInWireOrder()
        {
            var engine=new RayVisualEngine();
            Assert.True(engine.Apply(Frame(1,0,Config()+";"+Spawn(key:7,serial:1)+";"
                +Spawn(key:7,serial:2,operation:"u",end:300)+";x,1,8;"
                +Spawn(key:7,serial:7,operation:"u",end:400)),1));
            Assert.Equal(1,engine.ActiveCount);Assert.Equal(300,engine.BuildDraw().Data[2]);
            engine.Apply(Frame(2,1,Spawn(key:7,serial:7,operation:"u",born:1,end:500)),1);
            Assert.Equal(300,engine.BuildDraw().Data[2]);
            engine.Apply(Frame(3,2,Spawn(key:7,serial:9,operation:"u",born:2,end:600)),1);
            Assert.Equal(600,engine.BuildDraw().Data[2]);Assert.Equal(1,engine.ActiveCount);
            float[] before=engine.BuildDraw().Data.Take(32).ToArray();
            Assert.False(engine.Apply(Frame(4,3,Spawn(id:2,key:8,serial:1,born:3)+";"
                +Spawn(id:2,key:9,serial:2,born:3,operation:"u")),1));
            Assert.Equal(before,engine.BuildDraw().Data.Take(32));
        }

        [Theory]
        [InlineData(0)] [InlineData(1)] [InlineData(2)] [InlineData(3)]
        public void GenericSegmentKindsCanReuseButDelayedUpdatesCannotRewriteAnInFlightEmission(int kind)
        {
            var engine=new RayVisualEngine();
            Assert.True(engine.Apply(Frame(1,0,Config(2)+";"+Spawn(kind:kind,key:7,serial:1)),1));
            Assert.True(engine.Apply(Frame(2,1,Spawn(kind:kind,key:7,serial:2,born:1,operation:"u")),1));
            Assert.False(engine.Apply(Frame(3,2,Spawn(kind:kind,key:7,serial:3,born:2,delay:2,operation:"u")),1));
            Assert.Equal(1,engine.ActiveCount);
        }

        [Fact]
        public void BaguaStaysIndependentAndLegacyFlameKeepsItsCompatibleSerialZero()
        {
            var bagua=new RayVisualEngine();
            Assert.False(bagua.Apply(Frame(1,0,Config(10)+";"+Spawn(key:7,serial:1)),1));
            Assert.True(bagua.Apply(Frame(1,0,Config(10)+";"+Spawn()+";"+Spawn(id:2)),1));
            Assert.Equal(2,bagua.ActiveCount);
            Assert.False(bagua.Apply(Frame(2,1,Spawn(born:1,key:7,serial:2,operation:"u")),1));
            var generic=new RayVisualEngine();
            Assert.False(generic.Apply(Frame(1,0,Config()+";"+Spawn(key:7,serial:0)),1));
            var flame=new RayVisualEngine();
            Assert.True(flame.Apply(Frame(1,0,Config(11)+";"+Spawn(kind:4,key:7,serial:0)),1));
            Assert.True(flame.Apply(Frame(2,1,Spawn(kind:4,key:7,serial:0,born:1,operation:"u")),1));
            Assert.Equal(1,flame.ActiveCount);
        }

        [Fact]
        public void ChannelPauseEpochAndGenerationDoNotReuseRetiredBindingsOrPhase()
        {
            var engine=new RayVisualEngine();engine.Apply(Frame(1,1,Config()+";"+Spawn(key:7,serial:4)),2);
            float[] before=engine.BuildDraw().Data.Take(32).ToArray();
            engine.Apply(Frame(2,500,paused:true),2);Assert.Equal(before,engine.BuildDraw().Data.Take(32));
            Assert.False(engine.Apply(Frame(3,501,Spawn(key:7,serial:5,born:501,operation:"u")),1));
            engine.Apply(Frame(3,501,Spawn(key:7,serial:5,born:501,operation:"u")),2);
            Assert.Equal(2,engine.BuildDraw().Data[12]);
            Assert.True(engine.Apply(Frame(1,0,Config(1)+";"+Spawn(key:7,serial:1),epoch:2),2));
            Assert.Equal(0,engine.BuildDraw().Data[12]);Assert.Equal(1,engine.ActiveCount);
            Assert.False(engine.Apply(Frame(4,502,Spawn(key:7,serial:6,born:502,operation:"u")),2));
            engine.Reset();Assert.Equal(0,engine.BuildDraw().Count);
            Assert.True(engine.Apply(Frame(1,0,Config()+";"+Spawn(key:7,serial:1)),3));
            Assert.Equal(0,engine.BuildDraw().Data[12]);
        }

        [Fact]
        public void FullChannelCapacityAcceptsUpdatesAndRetiresAllIdIndexesBeforeReuse()
        {
            var engine=new RayVisualEngine();
            engine.Apply(Frame(1,0,Config()+";"+string.Join(';',Enumerable.Range(1,128)
                .Select(id=>Spawn(id,key:id,serial:1)))),1);
            engine.Apply(Frame(2,1,string.Join(';',Enumerable.Range(129,128)
                .Select(id=>Spawn(id,born:1,key:id,serial:1)))),1);
            for(int tick=2;tick<10;tick++)
                Assert.True(engine.Apply(Frame(tick+1,tick,string.Join(';',Enumerable.Range(1,128)
                    .Select(id=>Spawn(id,born:tick,key:id,serial:tick,operation:"u",end:tick+200)))),1));
            Assert.Equal(256,engine.ActiveCount);Assert.Equal(209,engine.BuildDraw().Data[2]);
            engine.Apply(Frame(11,40),1);Assert.Equal(0,engine.ActiveCount);
            Assert.True(engine.Apply(Frame(12,41,Spawn(key:1,serial:1,born:41,operation:"u")),1));
            Assert.Equal(1,engine.ActiveCount);Assert.Equal(200,engine.BuildDraw().Data[2]);
        }

        [Fact]
        public void WireFieldOrderAndRendererFieldCoverageAreBoundToTheAs2Sources()
        {
            string root=ProjectRoot();
            string bridge=File.ReadAllText(Path.Combine(root,"scripts/类定义/org/flashNight/arki/render/RayVisualBridge.as"));
            var fields=Regex.Match(bridge,@"fields:Array\s*=\s*\[([\s\S]*?)\];").Groups[1].Value;
            Assert.Equal(RayVisualCatalog.FieldNames,Regex.Matches(fields,"\"([^\"]+)\"").Select(m=>m.Groups[1].Value).ToArray());
            string program=File.ReadAllText(Path.Combine(root,"launcher/src/Program.cs"));
            Assert.Matches(@"task\s*=\s*""ray_visual_caps""[\s\S]{0,600}channelVersion\s*=\s*\S*RayVisualCatalog\.ChannelVersion",program);
            string native=File.ReadAllText(Path.Combine(root,"launcher/src/Guardian/WorldCompositor/NativeCompositorSession.cs"));
            Assert.Matches(@"ProbeGetAbiVersion""\)\(\)\s*!=\s*12",native);
            // 32-float records reserve seven packed palette colours. More colours must
            // remain in Flash instead of silently changing an authored custom palette.
            Assert.Matches(@"if\s*\(palette\.length\s*>\s*7\)\s*return 0;",bridge);
            foreach (string path in Directory.GetFiles(Path.Combine(root,"scripts/类定义/org/flashNight/arki/render/renderer"),"*Renderer.as"))
                foreach (Match match in Regex.Matches(File.ReadAllText(path),"cfgNum\\(config,\\s*\"([^\"]+)\""))
                    Assert.Contains(match.Groups[1].Value,RayVisualCatalog.FieldNames);
        }
        [Fact]
        public void FallbackRenderersCannotConsumeTheGameplayMathRandomStream()
        {
            string directory=Path.Combine(ProjectRoot(),"scripts/类定义/org/flashNight/arki/render");
            string[] paths=Directory.GetFiles(Path.Combine(directory,"renderer"),"*Renderer.as")
                .Append(Path.Combine(directory,"RayVfxManager.as")).ToArray();
            foreach (string path in paths) Assert.DoesNotMatch(@"\bMath\.random\s*\(",File.ReadAllText(path));
        }
        private static string ProjectRoot()
        {
            var dir=new DirectoryInfo(AppContext.BaseDirectory);
            while (dir!=null && !File.Exists(Path.Combine(dir.FullName,"scripts/类定义/org/flashNight/arki/render/RayVfxManager.as"))) dir=dir.Parent;
            return dir?.FullName??throw new InvalidOperationException("Missing ray source contract");
        }
    }
}
