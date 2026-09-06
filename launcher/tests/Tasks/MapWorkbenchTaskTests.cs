using CF7Launcher.Tasks;
using Newtonsoft.Json.Linq;
using Xunit;

namespace CF7Launcher.Tests.Tasks
{
    public class MapWorkbenchTaskTests
    {
        private static JObject Message() => new JObject { ["type"]="panel", ["panel"]="map-workbench", ["domain"]="map_workbench", ["cmd"]="read", ["callId"]="map.1", ["panelInstanceId"]="owner.1", ["payload"]=new JObject() };
        private static bool Read(JObject m, string panel="map-workbench", string owner="owner.1") => MapWorkbenchTask.TryReadRequest(m.ToString(),panel,owner,out _,out _);
        [Fact] public void ActiveOwnerCanRead() { Assert.True(Read(Message())); }
        [Theory] [InlineData("map", "owner.1")] [InlineData("map-workbench","owner.2")] [InlineData("map-workbench","")]
        public void OtherOwnersCannotReadOrWrite(string panel,string owner) { Assert.False(Read(Message(),panel,owner)); }
        [Theory] [InlineData("path")] [InlineData("command")] [InlineData("script")]
        public void ForeignFieldsAreRejected(string field) { var m=Message();m["payload"][field]="../../runtime";Assert.False(Read(m)); }
        [Theory] [InlineData("navigate")] [InlineData("unlock")] [InlineData("save_game")]
        public void GameplayCommandsAreNotAuthoringOperations(string cmd) { var m=Message();m["cmd"]=cmd;Assert.False(Read(m)); }
        [Fact] public void PreviewRequiresTypedChangesAndDigest()
        {
            var m=Message();m["cmd"]="preview";m["payload"]=new JObject { ["changes"]=new JArray(),["expectedDigest"]="digest" };Assert.True(Read(m));
            m["payload"]["changes"]="wrong";Assert.False(Read(m));
        }
        [Fact] public void DuplicateEnvelopeIsRejected() { Assert.False(MapWorkbenchTask.TryReadRequest("{\"type\":\"panel\",\"type\":\"task\"}","map-workbench","owner.1",out _,out _)); }
    }
}
