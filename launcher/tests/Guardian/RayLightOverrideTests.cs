using System;
using System.Globalization;
using System.Linq;
using System.Text;
using CF7Launcher.Guardian.WorldCompositor;
using Xunit;

namespace CF7Launcher.Tests.Guardian
{
    public sealed class RayLightOverrideTests
    {
        private static float[] Values()
        {
            var values=new float[RayVisualCatalog.FieldNames.Length];
            values[0]=0xFF8800;values[1]=0xFFFFFF;values[2]=3;values[3]=4;values[4]=2;
            return values;
        }
        private static string Config(int id=1) => $"c,{id},1,"
            +string.Join(',',Values().Select(x=>x.ToString(CultureInfo.InvariantCulture)))+",-";
        private static string Spawn(int id=1) => $"s,{id},1,0,0,10,20,100,20,0,0,1,0,123,0,0,0,0,0,2,-,-,0";
        private static bool Parse(string records,out RayVisualFrame frame) =>
            RayVisualFrame.TryParse("1|1|1|0;"+records,out frame);

        [Fact]
        public void LegacyConfigPacketsAndOmittedConstructorArgumentHaveValidAutoLighting()
        {
            Assert.True(Parse(Config(),out var frame));
            Assert.Equal(RayLightOverrides.Default,Assert.Single(frame.Configs).Light);
            var direct=new RayVisualConfig(1,1,Values(),Array.Empty<int>());
            Assert.True(direct.Light.IsValid);
            Assert.Equal("auto",direct.Light.Profile);Assert.Equal(1,direct.Light.EnergyScale);
            Assert.Equal(1,direct.Light.WidthScale);Assert.Equal(-1,direct.Light.Color);Assert.Equal(-1,direct.Light.FadeTicks);
            Assert.Throws<ArgumentOutOfRangeException>(()=>new RayVisualConfig(1,1,Values(),Array.Empty<int>(),default(RayLightOverrides)));
        }

        [Theory]
        [InlineData("auto")]
        [InlineData("none")]
        [InlineData("flame")]
        [InlineData("beam")]
        [InlineData("heavy")]
        [InlineData("arc")]
        [InlineData("glyph")]
        public void ClosedProfilesAndPerWeaponOverridesSurviveTheWire(string profile)
        {
            Assert.True(Parse(Config()+$";l,1,{profile},1.5,0.75,16746496,12;"+Spawn(),out var frame));
            RayVisualConfig cfg=Assert.Single(frame.Configs);
            Assert.Equal(new RayLightOverrides(profile,1.5f,.75f,0xFF8800,12),cfg.Light);
            Assert.True(cfg.Light.IsValid);
            Assert.Equal(Values(),cfg.Values); // no body width, colour, life or gameplay projection was rewritten
            var shot=Assert.Single(frame.Events);Assert.Equal(100,shot.EndX);Assert.Equal(20,shot.EndY);
        }

        [Theory]
        [InlineData("l,1,auto,1,1,-1,-1")]
        [InlineData("l,1,none,0,0.25,0,0")]
        [InlineData("l,1,heavy,2,4,16777215,30")]
        public void OverrideEndpointsAndAutoSentinelsAreAccepted(string light)
        { Assert.True(Parse(Config()+";"+light,out var frame));Assert.True(frame.Configs[0].Light.IsValid); }

        [Theory]
        [InlineData("l,1,unknown,1,1,-1,-1")]
        [InlineData("l,1,Beam,1,1,-1,-1")]
        [InlineData("l,1,,1,1,-1,-1")]
        [InlineData("l,1,beam,NaN,1,-1,-1")]
        [InlineData("l,1,beam,Infinity,1,-1,-1")]
        [InlineData("l,1,beam,-0.1,1,-1,-1")]
        [InlineData("l,1,beam,2.01,1,-1,-1")]
        [InlineData("l,1,beam,1,0.24,-1,-1")]
        [InlineData("l,1,beam,1,4.01,-1,-1")]
        [InlineData("l,1,beam,1,NaN,-1,-1")]
        [InlineData("l,1,beam,1,1,-2,-1")]
        [InlineData("l,1,beam,1,1,16777216,-1")]
        [InlineData("l,1,beam,1,1,1.5,-1")]
        [InlineData("l,1,beam,1,1,0xFF,-1")]
        [InlineData("l,1,beam,1,1,-1,-2")]
        [InlineData("l,1,beam,1,1,-1,31")]
        [InlineData("l,1,beam,1,1,-1,1.5")]
        [InlineData("l,1,beam,1,1,-1,NaN")]
        [InlineData("l,1,beam,1,1,-1,-1,0")]
        public void InvalidOverridesRejectTheCompletePacket(string light) => Assert.False(Parse(Config()+";"+light,out _));

        [Fact]
        public void LightCannotPatchAnotherConfigRepeatOrSkipAnInterveningRecord()
        {
            const string light="l,1,beam,1,1,-1,-1";
            Assert.False(Parse(light,out _));
            Assert.False(Parse(light+";"+Config(),out _));
            Assert.False(Parse(Config()+";"+light+";"+light,out _));
            Assert.False(Parse(Config()+";"+Spawn()+";"+light,out _));
            Assert.False(Parse(Config()+";o,1,2;"+light,out _));
            Assert.False(Parse(Config()+";"+Config(2)+";"+light,out _));
            Assert.False(Parse(Config()+";l,2,beam,1,1,-1,-1",out _));
        }

        [Fact]
        public void OverridesAreScopedToEachImmutableDefinitionWithinAPacket()
        {
            Assert.True(Parse(Config()+";l,1,beam,1.5,2,-1,4;"+Config(2)+";"+Config(3)+";l,3,none,0,1,0,0",out var frame));
            Assert.Equal(3,frame.Configs.Length);
            Assert.Equal(new RayLightOverrides("beam",1.5f,2,-1,4),frame.Configs[0].Light);
            Assert.Equal(RayLightOverrides.Default,frame.Configs[1].Light);
            Assert.Equal("none",frame.Configs[2].Light.Profile);
        }

        [Fact]
        public void EqualityIncludesEveryLightingKnobForImmutableConfigChecks()
        {
            var a=new RayLightOverrides("beam",1,1,-1,-1);
            Assert.Equal(a,new RayLightOverrides("beam",1,1,-1,-1));
            Assert.Equal(a.GetHashCode(),new RayLightOverrides("beam",1,1,-1,-1).GetHashCode());
            Assert.NotEqual(a,new RayLightOverrides("arc",1,1,-1,-1));
            Assert.NotEqual(a,new RayLightOverrides("beam",2,1,-1,-1));
            Assert.NotEqual(a,new RayLightOverrides("beam",1,2,-1,-1));
            Assert.NotEqual(a,new RayLightOverrides("beam",1,1,0,-1));
            Assert.NotEqual(a,new RayLightOverrides("beam",1,1,-1,0));
        }

        [Fact]
        public void OptionalLightRecordsFitTheExistingConfigAndEventCapacityLimits()
        {
            var payload=new StringBuilder("1|1|1|0;o,0,0");
            for(int i=1;i<=256;i++) payload.Append(';').Append(Config(i)).Append($";l,{i},auto,1,1,-1,-1");
            for(int i=1;i<=128;i++) payload.Append(';').Append(Spawn(i));
            Assert.True(RayVisualFrame.TryParse(payload.ToString(),out var frame));
            Assert.Equal(256,frame.Configs.Length);Assert.Equal(128,frame.Events.Length);
            Assert.All(frame.Configs,cfg=>Assert.Equal(RayLightOverrides.Default,cfg.Light));
            // The ordered event stream is bounded by RayVisualCatalog.MaxEvents.
            var full=new StringBuilder("1|2|2|0;o,0,0");
            for(int i=0;i<RayVisualCatalog.MaxEvents;i++) full.Append(';').Append(Spawn(i+1));
            Assert.True(RayVisualFrame.TryParse(full.ToString(),out _));
            Assert.False(RayVisualFrame.TryParse(full+";"+Spawn(RayVisualCatalog.MaxEvents+1),out _));
        }
    }
}
