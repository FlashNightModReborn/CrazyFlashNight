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
    }
}
