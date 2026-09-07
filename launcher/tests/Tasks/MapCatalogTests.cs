using System;
using System.Threading;
using CF7Launcher.Data;
using CF7Launcher.Tasks;
using Newtonsoft.Json.Linq;
using Xunit;

namespace CF7Launcher.Tests.Tasks
{
    public class MapCatalogTests
    {
        [Theory]
        [InlineData("map_catalog")]
        [InlineData("task_npc_registry")]
        public void RetiredMapSidecarsCannotBeQueried(string dataType)
        {
            var task = new DataQueryTask(new DataCache(AppContext.BaseDirectory));
            string captured = null;
            using var done = new ManualResetEventSlim(false);
            task.HandleAsync(new JObject { ["payload"] = new JObject { ["dataType"] = dataType } },
                response => { captured = response; done.Set(); });
            Assert.True(done.Wait(TimeSpan.FromSeconds(5)));
            var result = JObject.Parse(captured);
            Assert.False(result.Value<bool>("success"));
            Assert.Contains("unknown dataType", result.Value<string>("error"));
        }
    }
}
