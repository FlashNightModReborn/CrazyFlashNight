using System.Collections.Generic;
using CF7Launcher.Guardian;
using CF7Launcher.Guardian.Hud;
using Xunit;

namespace CF7Launcher.Tests.Guardian
{
    public class AudioHudStateTests
    {
        [Fact]
        public void UiData_OwnsTitleAndVisualizerPreferenceInOneState()
        {
            AudioHudState state = new AudioHudState();
            Dictionary<string, string> snapshot = new Dictionary<string, string>
            {
                { "bgm", "bgm:Final Sky" },
                { "pl", "pl:2" }
            };

            Assert.True(state.ApplyUiData(snapshot, new HashSet<string> { "bgm", "pl" }));
            Assert.Equal("Final Sky", state.Title);
            Assert.True(state.DisableVisualizers);
            Assert.False(state.WantsTick);
        }

        [Fact]
        public void Samples_AreClampedAndChronological()
        {
            AudioHudState state = new AudioHudState();
            state.AddSampleForTest(-1f, 0.25f);
            state.AddSampleForTest(2f, 0.75f);

            float left0, right0, left1, right1;
            state.GetSample(0, out left0, out right0);
            state.GetSample(1, out left1, out right1);

            Assert.Equal(0f, left0);
            Assert.Equal(0.25f, right0);
            Assert.Equal(1f, left1);
            Assert.Equal(0.75f, right1);
        }

        [Fact]
        public void GameNotReady_ClearsNativeAudioHistoryAndStopsTick()
        {
            AudioHudState state = new AudioHudState();
            state.ApplyUiData(
                new Dictionary<string, string> { { "bgm", "bgm:Final Sky" } },
                new HashSet<string> { "bgm" });
            state.ForcePlayingForTest(true);
            state.AddSampleForTest(0.5f, 0.5f);

            Assert.True(state.ApplyUiData(
                new Dictionary<string, string> { { "s", "s:0" }, { "bgm", "bgm:Final Sky" } },
                new HashSet<string> { "s" }));
            Assert.Equal("", state.Title);
            Assert.False(state.HasSamples);
            Assert.False(state.WantsTick);
        }

        [Fact]
        public void NotchUtilityRow_ContainsMigratedLowFrequencyEntries()
        {
            Assert.Equal("JUKEBOX_EXPAND", ResolveUtilityRoute(0));
            Assert.Equal("MAPHUD_TOGGLE", ResolveUtilityRoute(1));
            Assert.Equal("SETTINGS", ResolveUtilityRoute(2));
            Assert.Equal("HELP", ResolveUtilityRoute(3));
        }

        private static string ResolveUtilityRoute(int index)
        {
            // NotchWidget 的实例依赖 WinForms 控件；这里直接使用其稳定 test seam。
            using (System.Windows.Forms.Control anchor = new System.Windows.Forms.Control())
            {
                FpsRingBuffer fps = new FpsRingBuffer(300);
                NotchWidget widget = new NotchWidget(anchor, fps, "", null, null, null, null);
                return widget.ResolveUtilityRouteForTest(index);
            }
        }
    }
}
