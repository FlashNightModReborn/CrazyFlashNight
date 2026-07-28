using System.Collections.Generic;
using Newtonsoft.Json.Linq;
using Xunit;
using CF7Launcher.Bus;

namespace CF7Launcher.Tests.Bus
{
    public class TaskRegistryStatusTests
    {
        [Fact]
        public void ToStatusJson_IncludesRegisteredPanelResponseTasks()
        {
            var status = JObject.Parse(TaskRegistry.ToStatusJson(true, 3000, 3001));
            var names = new HashSet<string>();
            foreach (JObject task in (JArray)status["tasks"])
            {
                names.Add((string)task["name"]);
            }

            Assert.Contains("shop_response", names);
            Assert.Contains("map_response", names);
            Assert.Contains("stage_select_response", names);
            Assert.Contains("arena_response", names);
            Assert.Contains("arena_calibration", names);
            Assert.Contains("arena_calibration_response", names);
            Assert.Contains("agent_control", names);
            Assert.Contains("pet_response", names);
            Assert.Contains("merc_response", names);
            Assert.Contains("task_response", names);
            Assert.Contains("intelligence_response", names);
            Assert.Contains("skill_response", names);
            Assert.Contains("hairdresser_response", names);
            Assert.Contains("loadout_response", names);
        }

        [Fact]
        public void ToStatusJson_DeclaresArenaCalibrationHttpCallableMetadata()
        {
            var status = JObject.Parse(TaskRegistry.ToStatusJson(true, 3000, 3001));
            JObject control = null;
            JObject response = null;
            JObject agentControl = null;
            foreach (JObject task in (JArray)status["tasks"])
            {
                if ((string)task["name"] == "arena_calibration")
                    control = task;
                if ((string)task["name"] == "arena_calibration_response")
                    response = task;
                if ((string)task["name"] == "agent_control")
                    agentControl = task;
            }

            Assert.NotNull(control);
            Assert.NotNull(response);
            Assert.NotNull(agentControl);
            Assert.True((bool)control["httpCallable"]);
            Assert.False((bool)response["httpCallable"]);
            Assert.True((bool)agentControl["httpCallable"]);
        }

        [Fact]
        public void LoadoutResponse_IsAsyncSocketOnlyMetadata()
        {
            JObject loadout = null;
            var status = JObject.Parse(
                TaskRegistry.ToStatusJson(true, 3000, 3001));
            foreach (JObject task in (JArray)status["tasks"])
                if ((string)task["name"] == "loadout_response")
                    loadout = task;

            Assert.NotNull(loadout);
            Assert.Equal("json_async", (string)loadout["transport"]);
            Assert.Equal("AS2<->C#", (string)loadout["direction"]);
            Assert.False((bool)loadout["httpCallable"]);
            Assert.False(TaskRegistry.IsHttpCallable("loadout_response"));
        }

        [Fact]
        public void WorkbenchOpenRequestId_IsAcceptedOnlyForExactNativeBuildTuple()
        {
            JObject request =
                JObject.Parse(
                    "{\"panel\":\"workbench\","
                    + "\"source\":\"nativehud_equipment\","
                    + "\"initData\":{\"profile\":\"battlebox\",\"view\":\"build\"},"
                    + "\"openRequestId\":\"workbench.open.1.valid\"}");

            string openRequestId;
            string rejectionReason;
            Assert.True(
                TaskRegistry.TryReadPanelOpenRequestId(
                    request,
                    "workbench",
                    "nativehud_equipment",
                    out openRequestId,
                    out rejectionReason));
            Assert.Equal(
                "workbench.open.1.valid",
                openRequestId);
            Assert.Null(rejectionReason);
        }

        [Theory]
        [InlineData("{\"initData\":{\"profile\":\"battlebox\",\"view\":\"build\"}}")]
        [InlineData("{\"initData\":{\"profile\":\"battlebox\",\"view\":\"storage\"},\"openRequestId\":\"workbench.open.1\"}")]
        [InlineData("{\"initData\":{\"profile\":\"warehouse\",\"view\":\"build\"},\"openRequestId\":\"workbench.open.1\"}")]
        [InlineData("{\"initData\":{\"profile\":\"battlebox\",\"view\":\"build\",\"extra\":true},\"openRequestId\":\"workbench.open.1\"}")]
        [InlineData("{\"initData\":{\"profile\":7,\"view\":\"build\"},\"openRequestId\":\"workbench.open.1\"}")]
        [InlineData("{\"initData\":{\"profile\":\"battlebox\",\"view\":\"build\"},\"openRequestId\":7}")]
        [InlineData("{\"initData\":{\"profile\":\"battlebox\",\"view\":\"build\"},\"openRequestId\":\"bad token\"}")]
        public void WorkbenchOpenRequestId_RejectsMissingMalformedOrUnsupportedTuple(
            string fields)
        {
            JObject request =
                JObject.Parse(
                    "{\"panel\":\"workbench\","
                    + "\"source\":\"nativehud_equipment\","
                    + fields.Substring(1));

            string openRequestId;
            string rejectionReason;
            Assert.False(
                TaskRegistry.TryReadPanelOpenRequestId(
                    request,
                    "workbench",
                    "nativehud_equipment",
                    out openRequestId,
                    out rejectionReason));
            Assert.Null(openRequestId);
            Assert.False(
                string.IsNullOrEmpty(
                    rejectionReason));
        }

        [Fact]
        public void SkillsOpenRequestId_RetainsTrainerOptionalAndValidManageTokenRules()
        {
            string openRequestId;
            string rejectionReason;
            Assert.True(
                TaskRegistry.TryReadPanelOpenRequestId(
                    JObject.Parse(
                        "{\"panel\":\"skills\","
                        + "\"source\":\"world_skill_trainer\","
                        + "\"initData\":{\"view\":\"trainer\"}}"),
                    "skills",
                    "world_skill_trainer",
                    out openRequestId,
                    out rejectionReason));
            Assert.Null(openRequestId);

            Assert.True(
                TaskRegistry.TryReadPanelOpenRequestId(
                    JObject.Parse(
                        "{\"panel\":\"skills\","
                        + "\"source\":\"nativehud\","
                        + "\"initData\":{\"view\":\"manage\"},"
                        + "\"openRequestId\":\"skill.open.1.valid\"}"),
                    "skills",
                    "nativehud",
                    out openRequestId,
                    out rejectionReason));
            Assert.Equal(
                "skill.open.1.valid",
                openRequestId);
        }
    }
}
