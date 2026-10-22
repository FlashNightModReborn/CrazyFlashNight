using System;
using System.IO;
using CF7Launcher.Config;
using Newtonsoft.Json.Linq;
using Xunit;

namespace CF7Launcher.Tests.Config
{
    public sealed class UserPrefsTests : IDisposable
    {
        private readonly string _root = Path.Combine(Path.GetTempPath(), "cf7-u8-prefs-" + Guid.NewGuid().ToString("N"));
        private string PreferenceDirectory => Path.Combine(_root, "prefs");
        private string PreferenceFile => Path.Combine(PreferenceDirectory, "launcher_user_prefs.json");
        private UserPrefs Reload() => new UserPrefs(Path.Combine(_root,"project"), PreferenceDirectory);

        [Theory]
        [InlineData(false,false)]
        [InlineData(false,true)]
        [InlineData(true,false)]
        [InlineData(true,true)]
        public void ImageOptionsDefaultAndRoundTripIndependently(bool cas,bool feedback)
        {
            var prefs=Reload();Assert.True(prefs.CasEnabled);Assert.False(prefs.MotionFeedbackEnabled);
            prefs.CasEnabled=cas;prefs.MotionFeedbackEnabled=feedback;
            prefs.Performance=new PerformancePolicy("quality","fixed",720);
            prefs.IntroEnabled=true;Assert.True(prefs.Save());
            var next=Reload();Assert.Equal(cas,next.CasEnabled);Assert.Equal(feedback,next.MotionFeedbackEnabled);
            Assert.Equal(prefs.Performance,next.Performance);Assert.True(next.IntroEnabled);
            next.Performance=PerformancePolicy.Default;Assert.True(next.Save());
            Assert.Equal(cas,Reload().CasEnabled);Assert.Equal(feedback,Reload().MotionFeedbackEnabled);
        }
        [Theory]
        [InlineData("{}")]
        [InlineData("{\"casEnabled\":\"false\",\"motionFeedbackEnabled\":1}")]
        [InlineData("{\"casEnabled\":null,\"motionFeedbackEnabled\":null}")]
        public void OldAndMalformedImageOptionsUseDefaults(string json)
        {
            Directory.CreateDirectory(PreferenceDirectory);File.WriteAllText(PreferenceFile,json);
            var prefs=Reload();Assert.True(prefs.CasEnabled);Assert.False(prefs.MotionFeedbackEnabled);
        }

        [Fact]
        public void RagTerminalAutoStartDefaultsOffAndSurvivesRestart()
        {
            var first = Reload();
            Assert.False(first.RagTerminalAutoStart);
            first.RagTerminalAutoStart = true;
            Assert.True(first.Save());
            Assert.Equal(JTokenType.Boolean,
                JObject.Parse(File.ReadAllText(PreferenceFile))["ragTerminalAutoStart"].Type);
            Assert.True(Reload().RagTerminalAutoStart);
        }

        [Fact]
        public void TutorialOptOutSurvivesRestartAndPreservesOtherPreferences()
        {
            var first = Reload();Assert.True(first.TutorialsAutoOpen);
            first.TutorialsAutoOpen = false;first.IntroEnabled = true;first.SfxEnabled = false;
            first.MapDisplayPreference = "expanded";first.HitNumberMode = "detail";
            Assert.True(first.Save());
            Assert.Equal(JTokenType.Boolean, JObject.Parse(File.ReadAllText(PreferenceFile))["tutorialsAutoOpen"].Type);
            var restarted = Reload();Assert.False(restarted.TutorialsAutoOpen);
            Assert.True(restarted.IntroEnabled);Assert.False(restarted.SfxEnabled);
            Assert.Equal("expanded",restarted.MapDisplayPreference);Assert.Equal("detail",restarted.HitNumberMode);
        }

        [Theory]
        [InlineData("{}")]
        [InlineData("{\"tutorialsAutoOpen\":\"false\",\"introEnabled\":true}")]
        [InlineData("{\"tutorialsAutoOpen\":null,\"introEnabled\":true}")]
        public void OlderOrMalformedTutorialFieldDefaultsOnWithoutResettingOtherPreferences(string json)
        {
            Directory.CreateDirectory(PreferenceDirectory);File.WriteAllText(PreferenceFile,json);
            var loaded = Reload();Assert.True(loaded.TutorialsAutoOpen);
            Assert.Equal(JObject.Parse(json).Value<bool?>("introEnabled") ?? false,loaded.IntroEnabled);
        }

        [Fact]
        public void ReducedPresentationSurvivesRestartAndDefaultsOff()
        {
            var first = Reload();
            Assert.False(first.ReducedPresentation);
            first.ReducedPresentation = true;
            Assert.True(first.Save());
            Assert.Equal(JTokenType.Boolean,
                JObject.Parse(File.ReadAllText(PreferenceFile))["reducedPresentation"].Type);
            Assert.True(Reload().ReducedPresentation);
            Directory.CreateDirectory(PreferenceDirectory);
            File.WriteAllText(PreferenceFile, "{\"introEnabled\":true}");
            var legacy = Reload();
            Assert.False(legacy.ReducedPresentation);
            Assert.True(legacy.IntroEnabled);
        }

        public void Dispose()
        {
            string target = Path.GetFullPath(_root);
            Assert.StartsWith(Path.GetFullPath(Path.GetTempPath()).TrimEnd(Path.DirectorySeparatorChar)
                + Path.DirectorySeparatorChar,target,StringComparison.OrdinalIgnoreCase);
            if (Directory.Exists(target)) Directory.Delete(target,true);
        }
    }
}
