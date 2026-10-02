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

        public void Dispose()
        {
            string target = Path.GetFullPath(_root);
            Assert.StartsWith(Path.GetFullPath(Path.GetTempPath()).TrimEnd(Path.DirectorySeparatorChar)
                + Path.DirectorySeparatorChar,target,StringComparison.OrdinalIgnoreCase);
            if (Directory.Exists(target)) Directory.Delete(target,true);
        }
    }
}
