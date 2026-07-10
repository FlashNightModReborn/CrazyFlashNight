using CF7Launcher.Config;
using CF7Launcher.Guardian.Hud;
using Xunit;

namespace CF7Launcher.Tests.Guardian
{
    public class MapDisplayPolicyTests
    {
        [Theory]
        [InlineData(null, MapDisplayPreference.Auto)]
        [InlineData("", MapDisplayPreference.Auto)]
        [InlineData("garbage", MapDisplayPreference.Auto)]
        [InlineData("AUTO", MapDisplayPreference.Auto)]
        [InlineData("off", MapDisplayPreference.Off)]
        [InlineData(" compact ", MapDisplayPreference.Compact)]
        [InlineData("expanded", MapDisplayPreference.Expanded)]
        public void ParsePreference_NormalizesInput(string raw, MapDisplayPreference expected)
        {
            Assert.Equal(expected, MapDisplayPolicy.ParsePreference(raw));
        }

        [Theory]
        [InlineData(EffectiveMapDisplayMode.Hidden, MapDisplayPreference.Compact)]
        [InlineData(EffectiveMapDisplayMode.Compact, MapDisplayPreference.Off)]
        [InlineData(EffectiveMapDisplayMode.Expanded, MapDisplayPreference.Off)]
        public void VisibilityToggle_IsOwnedByNotch(
            EffectiveMapDisplayMode current,
            MapDisplayPreference expected)
        {
            Assert.Equal(expected, MapDisplayPolicy.ToggleVisibility(current));
        }

        [Theory]
        [InlineData(EffectiveMapDisplayMode.Hidden, MapDisplayPreference.Compact)]
        [InlineData(EffectiveMapDisplayMode.Compact, MapDisplayPreference.Expanded)]
        [InlineData(EffectiveMapDisplayMode.Expanded, MapDisplayPreference.Compact)]
        public void SizeToggle_OnlyMovesBetweenCompactAndExpanded(
            EffectiveMapDisplayMode current,
            MapDisplayPreference expected)
        {
            Assert.Equal(expected, MapDisplayPolicy.ToggleSize(current));
        }

        [Fact]
        public void Resolve_AutoRequiresTacticalCapability()
        {
            Assert.Equal(
                EffectiveMapDisplayMode.Hidden,
                MapDisplayPolicy.Resolve(RuntimeMapMode.Navigation, MapDisplayPreference.Auto, true, false));
            Assert.Equal(
                EffectiveMapDisplayMode.Compact,
                MapDisplayPolicy.Resolve(RuntimeMapMode.Navigation, MapDisplayPreference.Auto, true, true));
        }

        [Theory]
        [InlineData(RuntimeMapMode.None)]
        [InlineData(RuntimeMapMode.Combat)]
        [InlineData(RuntimeMapMode.Unknown)]
        public void Resolve_RuntimeModeCanHardHideWithoutMutatingPreference(RuntimeMapMode runtime)
        {
            MapDisplayPreference preference = MapDisplayPreference.Expanded;
            Assert.Equal(
                EffectiveMapDisplayMode.Hidden,
                MapDisplayPolicy.Resolve(runtime, preference, true, true));
            Assert.Equal(MapDisplayPreference.Expanded, preference);
        }

        [Theory]
        [InlineData(null, "auto")]
        [InlineData("invalid", "auto")]
        [InlineData("COMPACT", "compact")]
        [InlineData(" expanded ", "expanded")]
        public void UserPrefs_NormalizeMapDisplayPreference(string raw, string expected)
        {
            Assert.Equal(expected, UserPrefs.NormalizeMapDisplayPreference(raw));
        }

        [Theory]
        [InlineData(MapDisplayPreference.Auto, "自动")]
        [InlineData(MapDisplayPreference.Off, "关闭")]
        [InlineData(MapDisplayPreference.Compact, "紧凑")]
        [InlineData(MapDisplayPreference.Expanded, "展开")]
        public void DisplayLabel_IsUserReadable(MapDisplayPreference preference, string expected)
        {
            Assert.Equal(expected, MapDisplayPolicy.ToDisplayLabel(preference));
        }
    }
}
