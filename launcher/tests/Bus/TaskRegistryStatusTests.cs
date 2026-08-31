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
            Assert.Contains("loot", names);
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
            Assert.Contains("item_use_response", names);
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
        public void ItemUseResponse_IsAsyncSocketOnlyMetadata()
        {
            JObject itemUse = null;
            var status = JObject.Parse(
                TaskRegistry.ToStatusJson(true, 3000, 3001));
            foreach (JObject task in (JArray)status["tasks"])
                if ((string)task["name"] == "item_use_response")
                    itemUse = task;

            Assert.NotNull(itemUse);
            Assert.Equal("json_async", (string)itemUse["transport"]);
            Assert.Equal("AS2<->C#", (string)itemUse["direction"]);
            Assert.False((bool)itemUse["httpCallable"]);
            Assert.False(TaskRegistry.IsHttpCallable("item_use_response"));
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

        [Fact]
        public void NativeTuningOpenRequestId_RequiresExactTupleAndOpaqueToken()
        {
            JObject request =
                JObject.Parse(
                    "{\"task\":\"panel_request\","
                    + "\"panel\":\"workbench\","
                    + "\"source\":\"nativehud_equipment_tuning\","
                    + "\"initData\":{\"profile\":\"battlebox\",\"view\":\"tuning\"},"
                    + "\"openRequestId\":\"tuning.open.1.valid\"}");

            string openRequestId;
            string rejectionReason;
            Assert.True(
                TaskRegistry.TryReadPanelOpenRequestId(
                    request,
                    "workbench",
                    "nativehud_equipment_tuning",
                    out openRequestId,
                    out rejectionReason));
            Assert.Equal(
                "tuning.open.1.valid",
                openRequestId);
            Assert.Null(rejectionReason);

            request.Remove("openRequestId");
            Assert.False(
                TaskRegistry.TryReadPanelOpenRequestId(
                    request,
                    "workbench",
                    "nativehud_equipment_tuning",
                    out openRequestId,
                    out rejectionReason));
            Assert.Equal(
                "missing_open_request_id",
                rejectionReason);
        }

        [Theory]
        [InlineData(
            "{\"task\":\"panel_request\",\"panel\":\"workbench\",\"source\":\"nativehud_equipment_tunin\",\"initData\":{\"profile\":\"battlebox\",\"view\":\"tuning\"},\"openRequestId\":\"tuning.open.1.valid\"}")]
        [InlineData(
            "{\"task\":\"panel_request\",\"panel\":\"workbench\",\"source\":\"nativehud_equipment_tuning\",\"initData\":{\"profile\":\"battlebox\",\"view\":\"tuning\"},\"openRequestId\":\"tuning.open.1.valid\",\"extra\":true}")]
        [InlineData(
            "{\"task\":\"panel_request\",\"panel\":\"workbench\",\"source\":\"nativehud_equipment_tuning\",\"initData\":{\"profile\":\"battlebox\",\"view\":\"tuning\",\"extra\":true},\"openRequestId\":\"tuning.open.1.valid\"}")]
        [InlineData(
            "{\"task\":\"panel_request\",\"panel\":\"workbench\",\"source\":\"nativehud_equipment_tuning\",\"initData\":{\"profile\":\"battlebox\",\"view\":\"build\"},\"openRequestId\":\"tuning.open.1.valid\"}")]
        [InlineData(
            "{\"task\":\"panel_request\",\"panel\":\"crafting\",\"source\":\"nativehud_equipment_tuning\",\"initData\":{\"profile\":\"battlebox\",\"view\":\"tuning\"},\"openRequestId\":\"tuning.open.1.valid\"}")]
        public void NativeTuningOpenRequestId_RejectsForgedSourceAndNearShapes(
            string json)
        {
            JObject request =
                JObject.Parse(json);

            string openRequestId;
            string rejectionReason;
            Assert.False(
                TaskRegistry.TryReadPanelOpenRequestId(
                    request,
                    request.Value<string>("panel"),
                    request.Value<string>("source"),
                    out openRequestId,
                    out rejectionReason));
            Assert.Null(openRequestId);
            Assert.Equal(
                "native_equipment_tuning_contract",
                rejectionReason);
        }

        [Theory]
        [InlineData("bad token")]
        [InlineData("bad/token")]
        [InlineData("")]
        public void NativeTuningOpenRequestId_RejectsMalformedToken(
            string value)
        {
            JObject request =
                new JObject
                {
                    ["task"] = "panel_request",
                    ["panel"] = "workbench",
                    ["source"] =
                        "nativehud_equipment_tuning",
                    ["initData"] =
                        new JObject
                        {
                            ["profile"] = "battlebox",
                            ["view"] = "tuning"
                        },
                    ["openRequestId"] = value
                };

            string openRequestId;
            string rejectionReason;
            Assert.False(
                TaskRegistry.TryReadPanelOpenRequestId(
                    request,
                    "workbench",
                    "nativehud_equipment_tuning",
                    out openRequestId,
                    out rejectionReason));
            Assert.Null(openRequestId);
            Assert.Equal(
                "invalid_open_request_id",
                rejectionReason);
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

        [Fact]
        public void MaterialsOpenRequestId_AllowsOnlyExactWireAndLegacyMissingToken()
        {
            string openRequestId;
            string rejectionReason;
            JObject legacy =
                JObject.Parse(
                    "{\"task\":\"panel_request\","
                    + "\"panel\":\"crafting\","
                    + "\"source\":\"nativehud_materials\","
                    + "\"initData\":{\"view\":\"materials\"}}");
            Assert.True(
                TaskRegistry.TryReadPanelOpenRequestId(
                    legacy,
                    "crafting",
                    "nativehud_materials",
                    out openRequestId,
                    out rejectionReason));
            Assert.Null(openRequestId);
            Assert.Null(rejectionReason);

            JObject correlated =
                JObject.Parse(
                    "{\"task\":\"panel_request\","
                    + "\"panel\":\"crafting\","
                    + "\"source\":\"nativehud_materials\","
                    + "\"openRequestId\":\"material.open.1.Valid_-~\","
                    + "\"initData\":{\"view\":\"materials\"}}");
            Assert.True(
                TaskRegistry.TryReadPanelOpenRequestId(
                    correlated,
                    "crafting",
                    "nativehud_materials",
                    out openRequestId,
                    out rejectionReason));
            Assert.Equal(
                "material.open.1.Valid_-~",
                openRequestId);
            Assert.Null(rejectionReason);
        }

        [Theory]
        [InlineData("{\"task\":\"panel_request\",\"panel\":\"crafting\",\"source\":\"nativehud_materials\",\"openRequestId\":\"material.open.1.valid\",\"view\":\"materials\",\"initData\":{}}")]
        [InlineData("{\"task\":\"panel_request\",\"panel\":\"crafting\",\"source\":\"nativehud_materials\",\"openRequestId\":\"material.open.1.valid\",\"initData\":{\"view\":\"materials\",\"extra\":true}}")]
        [InlineData("{\"task\":\"panel_request\",\"panel\":\"crafting\",\"source\":\"nativehud_materials\",\"openRequestId\":\"material.open.1.valid\",\"initData\":{\"view\":\"material\"}}")]
        [InlineData("{\"task\":\"panel_request\",\"panel\":\"Crafting\",\"source\":\"nativehud_materials\",\"openRequestId\":\"material.open.1.valid\",\"initData\":{\"view\":\"materials\"}}")]
        [InlineData("{\"task\":\"panel_request\",\"panel\":\"crafting\",\"source\":\"nativehud_material\",\"openRequestId\":\"material.open.1.valid\",\"initData\":{\"view\":\"materials\"}}")]
        [InlineData("{\"task\":\"panel_request\",\"panel\":\"crafting\",\"source\":\"nativehud_materials\",\"openRequestId\":\"material.open.1.valid\",\"initData\":{\"view\":\"materials\"},\"returnTo\":\"workbench\"}")]
        [InlineData("{\"task\":\"panel_request\",\"panel\":\"crafting\",\"source\":\"nativehud_materials\",\"openRequestId\":\"bad/token\",\"initData\":{\"view\":\"materials\"}}")]
        [InlineData("{\"task\":\"panel_request\",\"panel\":\"crafting\",\"source\":\"nativehud_materials\",\"openRequestId\":7,\"initData\":{\"view\":\"materials\"}}")]
        public void MaterialsOpenRequestId_RejectsNearWrongLayerAndExtraShape(
            string json)
        {
            JObject request =
                JObject.Parse(json);
            string openRequestId;
            string rejectionReason;

            Assert.False(
                TaskRegistry.TryReadPanelOpenRequestId(
                    request,
                    request.Value<string>("panel"),
                    request.Value<string>("source"),
                    out openRequestId,
                    out rejectionReason));
            Assert.Null(openRequestId);
            Assert.False(
                string.IsNullOrEmpty(
                    rejectionReason));
        }

        [Fact]
        public void MaterialsOpenRequestId_RejectsOverlongToken()
        {
            JObject request =
                new JObject
                {
                    ["task"] = "panel_request",
                    ["panel"] = "crafting",
                    ["source"] = "nativehud_materials",
                    ["openRequestId"] =
                        new string('a', 161),
                    ["initData"] =
                        new JObject
                        {
                            ["view"] = "materials"
                        }
                };
            string openRequestId;
            string rejectionReason;

            Assert.False(
                TaskRegistry.TryReadPanelOpenRequestId(
                    request,
                    "crafting",
                    "nativehud_materials",
                    out openRequestId,
                    out rejectionReason));
            Assert.Equal(
                "invalid_open_request_id",
                rejectionReason);
        }
    }
}
