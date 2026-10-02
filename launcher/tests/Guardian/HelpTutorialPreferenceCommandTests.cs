using System;
using System.IO;
using CF7Launcher.Config;
using CF7Launcher.Guardian;
using Newtonsoft.Json.Linq;
using Xunit;

namespace CF7Launcher.Tests.Guardian
{
    public sealed class HelpTutorialPreferenceCommandTests : IDisposable
    {
        private readonly string _root = Path.Combine(Path.GetTempPath(), "cf7-help-pref-" + Guid.NewGuid().ToString("N"));
        private UserPrefs Load() => new(Path.Combine(_root, "project"), Path.Combine(_root, "prefs"));
        private static JObject Request(string call = "call-1", string instance = "help-1") => new()
        {
            ["type"] = "tutorial_preference", ["cmd"] = "disable_auto_open", ["version"] = 1,
            ["callId"] = call, ["panelInstanceId"] = instance
        };

        [Fact] public void DisableIsGlobalDurableAndDoesNotChangeOtherPreferences()
        {
            var prefs = Load();prefs.MapDisplayPreference = "expanded";prefs.LastPlayedSlot = "keep";
            int saves = 0;var command = new HelpTutorialPreferenceCommand(prefs, () => { saves++;return prefs.Save(); });
            var reply = command.Handle(Request(), "help-1");Assert.True(reply.Value<bool>("ok"));
            Assert.False(reply.Value<bool>("tutorialsAutoOpen"));Assert.Equal("call-1",reply.Value<string>("callId"));
            Assert.False(Load().TutorialsAutoOpen);Assert.Equal("expanded",Load().MapDisplayPreference);
            Assert.Equal("keep",Load().LastPlayedSlot);
            reply["ok"] = false;Assert.True(command.Handle(Request(),"help-1").Value<bool>("ok"));
            command.Handle(Request("call-2"),"help-1");Assert.Equal(1,saves);
        }

        [Theory][InlineData(false)][InlineData(true)]
        public void SaveFailureOrExceptionRollsBackAndDuplicateDoesNotReplay(bool throws)
        {
            var prefs = Load();int saves = 0;
            var command = new HelpTutorialPreferenceCommand(prefs, () => { saves++;if(throws)throw new IOException();return false; });
            var reply = command.Handle(Request(),"help-1");Assert.False(reply.Value<bool>("ok"));
            Assert.Equal("save_failed",reply.Value<string>("error"));Assert.True(prefs.TutorialsAutoOpen);
            command.Handle(Request(),"help-1");Assert.Equal(1,saves);
        }

        [Theory][InlineData(null)][InlineData("")][InlineData("help-new")]
        public void RetiredOrForeignInstanceCannotWrite(string active)
        {
            var prefs = Load();int saves = 0;
            var command = new HelpTutorialPreferenceCommand(prefs, () => { saves++;return true; });
            Assert.Equal("panel_instance_expired",command.Handle(Request(),active).Value<string>("error"));
            Assert.True(prefs.TutorialsAutoOpen);Assert.Equal(0,saves);
        }

        [Theory]
        [InlineData("cmd", "\"host_set\"")]
        [InlineData("type", "\"task\"")]
        [InlineData("version", "\"1\"")]
        [InlineData("callId", "[]")]
        [InlineData("callId", "\"call-1\\n\"")]
        [InlineData("panelInstanceId", "null")]
        [InlineData("value", "false")]
        public void ClosedSchemaRejectsBroaderPreferenceOrMalformedInput(string field,string json)
        {
            var prefs = Load();var command = new HelpTutorialPreferenceCommand(prefs, () => throw new Exception("must not save"));
            var request = Request();request[field] = JToken.Parse(json);
            Assert.Null(command.Handle(request,"help-1"));Assert.True(prefs.TutorialsAutoOpen);
        }

        [Fact] public void CompositionReplyGateAllowsOnlyCurrentExactPreferenceResults()
        {
            var command = new HelpTutorialPreferenceCommand(Load(),()=>true);
            var reply = command.Handle(Request(),"help-1");
            Assert.True(HelpTutorialPreferenceCommand.IsResultFor(reply,"help-1"));
            Assert.False(HelpTutorialPreferenceCommand.IsResultFor(reply,"help-new"));
            Assert.False(HelpTutorialPreferenceCommand.IsResultFor(reply,null));
            foreach (var field in new[]{"type","version","callId","ok","tutorialsAutoOpen","error"})
            {
                var invalid = (JObject)reply.DeepClone();invalid[field] = new JArray();
                Assert.False(HelpTutorialPreferenceCommand.IsResultFor(invalid,"help-1"));
            }
            reply["payload"] = new JObject();Assert.False(HelpTutorialPreferenceCommand.IsResultFor(reply,"help-1"));
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
