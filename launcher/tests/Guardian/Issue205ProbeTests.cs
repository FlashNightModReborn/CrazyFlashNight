using System.Collections.Generic;
using CF7Launcher.Guardian;
using Xunit;

namespace CF7Launcher.Tests.Guardian
{
    public sealed class Issue205ProbeTests
    {
        private static readonly string[] Stages = { "update", "update_exit", "end", "end_exit", "build", "send", "send_exit", "fps_generated", "F_prefix", "consumer", "fps_source" };
        private static Dictionary<string,long> Values(int value, string frozen = null)
        {
            var result = new Dictionary<string,long>();
            foreach (string stage in Stages) result[stage] = stage == frozen ? 0 : value;
            return result;
        }
        [Theory]
        [InlineData("update")][InlineData("update_exit")][InlineData("end")][InlineData("end_exit")]
        [InlineData("build")][InlineData("send")][InlineData("send_exit")][InlineData("fps_generated")]
        [InlineData("F_prefix")][InlineData("consumer")][InlineData("fps_source")]
        public void R0SeparatesEachStoppedLayerWhileOtherLayersAdvance(string stopped)
        {
            var latch = new Issue205IncidentLatch();
            Assert.Null(latch.Observe(0,true,"owner1:g1",0,true,Values(0,stopped)));
            Assert.Null(latch.Observe(1000,true,"owner1:g1",0,true,Values(1,stopped)));
            var incident=latch.Observe(2000,true,"owner1:g1",0,true,Values(2,stopped));
            Assert.Equal(stopped+"_silent",(string)incident["reason"]);
            Assert.Equal("SUSPECT_ONLY",(string)incident["diagnosis"]);
        }
        [Fact]
        public void NormalHalfSecondFpsAndFrameProgressDoesNotTrigger()
        {
            var latch=new Issue205IncidentLatch();
            for(int i=0;i<300;i++) {
                var values=Values(i);values["fps_source"]=i/2;
                Assert.Null(latch.Observe(i*500,true,"owner1:g1",500,true,values));
            }
        }
        [Theory]
        [InlineData(2500,true,"root_http_pulse_silent")]
        [InlineData(0,false,"source_world_missing")]
        public void RootSilenceAndMissingWorldAreDifferent(double age,bool world,string reason)
        {
            var latch=new Issue205IncidentLatch();
            latch.Observe(0,true,"owner1:g1",0,true,Values(0));
            var incident=latch.Observe(2000,true,"owner1:g1",age,world,Values(1));
            Assert.Equal(reason,(string)incident["reason"]);
        }
        [Fact]
        public void IntentionalPauseOrFocusLossRestartsEligibilityBeforeAnIncident()
        {
            var latch=new Issue205IncidentLatch();
            latch.Observe(0,true,"owner1:g1",0,true,Values(0));
            Assert.Null(latch.Observe(3000,false,"owner1:g1",0,true,Values(0)));
            Assert.Null(latch.Observe(4000,true,"owner1:g1",0,true,Values(0)));
            Assert.Null(latch.Observe(5999,true,"owner1:g1",0,true,Values(0)));
            Assert.NotNull(latch.Observe(6000,true,"owner1:g1",0,true,Values(0)));
        }
        [Fact]
        public void RepeatedSameHideDoesNotExtendGraceAndLaterContextCannotEraseFirstIncident()
        {
            var latch=new Issue205IncidentLatch();
            latch.Observe(0,true,"owner1:g1",0,true,Values(0));
            latch.Observe(1000,true,"owner1:g1",0,true,Values(0));
            var first=latch.Observe(2000,true,"owner1:g1",0,true,Values(0));
            Assert.NotNull(first);
            Assert.Same(first,latch.Observe(3000,false,"owner2:g2",0,true,Values(4)));
            Assert.Same(first,latch.Observe(6000,true,"owner3:g3",0,true,Values(7)));
            Assert.Equal("owner1:g1",(string)first["context"]);
        }
        [Fact]
        public void VisualIdentitiesDoNotInventLegacySequenceOrNativeAcknowledgement()
        {
            var legacy=new BulletVisualFrameIdentity(3,4,88,88,false).Json();
            var q1=new BulletVisualFrameIdentity(3,4,88,7,true).Json();
            Assert.Null(legacy.Value<int?>("snapshotSequence"));
            Assert.Equal(88,q1.Value<int>("sourceFrame"));Assert.Equal(7,q1.Value<int>("snapshotSequence"));
            var chain=new Issue205ChainIdentity(3,4,9,88).Json();
            Assert.DoesNotContain("acknowledgement",chain.ToString());
            var native=new Issue205NativeIdentity(4,88,5,87).Json();
            Assert.Contains("not a presentation acknowledgement",(string)native["meaning"]);
        }
    }
}
