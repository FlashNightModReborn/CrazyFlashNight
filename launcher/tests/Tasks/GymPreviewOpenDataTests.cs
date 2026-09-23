using CF7Launcher.Tasks;
using Newtonsoft.Json;
using Newtonsoft.Json.Linq;
using Xunit;

namespace Launcher.Tests.Tasks
{
    public sealed class GymPreviewOpenDataTests
    {
        private static JObject Snapshot()
        {
            return new JObject
            {
                ["v"] = 2, ["openToken"] = "gym.open.1.1",
                ["stationId"] = "dummy",
                ["pendingSession"] = JValue.CreateNull(),
                ["balances"] = new JObject { ["money"] = 60000, ["kpoint"] = 5000 },
                ["portrait"] = new JObject
                {
                    ["gender"] = "male", ["equipment"] = new JObject { ["上装装备"] = "浅灰背心" },
                    ["hair"] = "男变装-短发", ["face"] = "男变装-基本脸型"
                },
                ["projects"] = new JArray
                {
                    new JObject
                    {
                        ["id"] = "dummy.0", ["index"] = 0, ["rewardLabel"] = "空手攻击力",
                        ["rewardAmount"] = 3, ["currency"] = "money", ["cost"] = 60000,
                        ["durationMs"] = 10000, ["current"] = 0, ["cap"] = 500,
                        ["baseExperience"] = 10000, ["capExperience"] = 50000
                    }
                }
            };
        }

        private static string Extras(JObject snapshot)
        {
            return new JObject
            { ["stationId"] = "dummy", ["snapshotJson"] = snapshot.ToString(Formatting.None) }
                .ToString(Formatting.None);
        }

        [Fact]
        public void OnlyExactWorldGymV2SnapshotOpensPanel()
        {
            JObject opened = GymPreviewOpenData.Build("world_gym", Extras(Snapshot()));
            Assert.NotNull(opened);
            Assert.Equal("preview", opened.Value<string>("mode"));
            Assert.Equal("dummy", opened.Value<string>("stationId"));
            Assert.Equal("dummy.0", opened["snapshot"]["projects"][0].Value<string>("id"));
            Assert.Null(opened["command"]);
            Assert.Null(GymPreviewOpenData.Build("as2_request", Extras(Snapshot())));
            JObject legacy = Snapshot();
            legacy["v"] = 1;
            Assert.Null(GymPreviewOpenData.Build("world_gym", Extras(legacy)));
        }

        [Fact]
        public void RejectsForeignStationAndUnlistedOpenFields()
        {
            JObject snapshot = Snapshot();
            snapshot["stationId"] = "squat";
            Assert.Null(GymPreviewOpenData.Build("world_gym", Extras(snapshot)));
            JObject extras = JObject.Parse(Extras(Snapshot()));
            extras["commit"] = true;
            Assert.Null(GymPreviewOpenData.Build("world_gym", extras.ToString(Formatting.None)));
        }

        [Fact]
        public void RejectsDuplicateProjectAndInvalidPaymentProjection()
        {
            JObject snapshot = Snapshot();
            ((JArray)snapshot["projects"]).Add(snapshot["projects"][0].DeepClone());
            Assert.Null(GymPreviewOpenData.Build("world_gym", Extras(snapshot)));
            snapshot = Snapshot();
            snapshot["balances"]["kpoint"] = -1;
            Assert.Null(GymPreviewOpenData.Build("world_gym", Extras(snapshot)));
            snapshot = Snapshot();
            snapshot["projects"][0]["currency"] = "虚拟币";
            Assert.Null(GymPreviewOpenData.Build("world_gym", Extras(snapshot)));
        }

        [Fact]
        public void RuntimeSnapshotRequiresExactOpenTokenAndExperienceProjection()
        {
            JObject snapshot = Snapshot();
            snapshot["v"] = 2;
            snapshot["openToken"] = "gym.open.1.1";
            snapshot["projects"][0]["baseExperience"] = 10000;
            snapshot["projects"][0]["capExperience"] = 50000;
            Assert.NotNull(GymPreviewOpenData.Build("world_gym", Extras(snapshot)));

            snapshot["openToken"] = "bad token";
            Assert.Null(GymPreviewOpenData.Build("world_gym", Extras(snapshot)));
            snapshot["openToken"] = "gym.open.1.1";
            ((JObject)snapshot["projects"][0]).Remove("capExperience");
            Assert.Null(GymPreviewOpenData.Build("world_gym", Extras(snapshot)));
            snapshot = Snapshot();
            snapshot["projects"][0]["capExperience"] = 70000;
            Assert.Null(GymPreviewOpenData.Build("world_gym", Extras(snapshot)));
            snapshot = Snapshot();
            snapshot["pendingSession"] = new JObject {
                ["sessionToken"] = "gym.session.1.1", ["stationId"] = "dummy",
                ["projectId"] = "dummy.0", ["phase"] = "save_pending"
            };
            Assert.NotNull(GymPreviewOpenData.Build("world_gym", Extras(snapshot)));
            snapshot["pendingSession"]["projectId"] = "dummy.99";
            Assert.Null(GymPreviewOpenData.Build("world_gym", Extras(snapshot)));
        }
    }
}
