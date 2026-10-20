using CF7Launcher.Data;
using CF7Launcher.Tasks;
using Newtonsoft.Json.Linq;
using Xunit;

namespace CF7Launcher.Tests.Tasks
{
    /// <summary>
    /// P4 / G4：任务插话上下文（协议 4.2）。只读任务目录 + 影子存档，
    /// 覆盖显式 next_task_id 配对、chain 回退、歧义省略、任务后 next 映射、
    /// 目标/奖励合并与 $ 文本键解引用、fail-closed 边界。
    /// </summary>
    public sealed class DialogueTaskContextTests
    {
        private static JObject Task(int id, string title, string chain = "",
            string getNpc = "Andy Law", string finishNpc = "Andy Law",
            JToken nextTaskId = null, JArray objectives = null, JArray rewards = null)
        {
            var task = new JObject
            {
                ["id"] = id,
                ["title"] = title,
                ["chain"] = chain,
                ["get_npc"] = getNpc,
                ["finish_npc"] = finishNpc,
                ["finish_requirements"] = objectives ?? new JArray(),
                ["finish_submit_items"] = new JArray(),
                ["finish_contain_items"] = new JArray(),
                ["rewards"] = rewards ?? new JArray()
            };
            if (nextTaskId != null) task["next_task_id"] = nextTaskId;
            return task;
        }

        private static MapTaskCatalog Catalog(params JObject[] tasks)
        {
            var catalog = new MapTaskCatalog();
            foreach (JObject task in tasks)
                catalog.Tasks[task.Value<int>("id").ToString()] = task;
            catalog.Texts["$TITLE"] = "北边仓库失窃";
            catalog.Texts["$ITEM"] = "失窃货物";
            return catalog;
        }

        private static JObject Save(params string[] finishedIds)
        {
            var finished = new JObject();
            foreach (string id in finishedIds) finished[id] = 1;
            return new JObject
            {
                ["mydata"] = new JObject
                {
                    ["tasks"] = new JObject
                    {
                        ["tasks_to_do"] = new JArray(),
                        ["tasks_finished"] = finished
                    }
                }
            };
        }

        [Fact]
        public void TaskPreUsesExplicitNextTaskIdPairing()
        {
            var catalog = Catalog(
                Task(200123, "南边哨站补给", nextTaskId: new JValue(200124),
                    objectives: new JArray("送回 3 箱弹药")),
                Task(200124, "北边仓库失窃"));
            JObject context = DialogueTaskContext.Build(catalog, Save("200123"), "200124", "task_pre");

            Assert.NotNull(context);
            Assert.Equal(200124, context["upcoming"].Value<int>("task_id"));
            Assert.Equal(200123, context["completed"].Value<int>("task_id"));
            Assert.Equal("南边哨站补给", context["completed"].Value<string>("title"));
            Assert.False(string.IsNullOrEmpty(context["completed"].Value<string>("outcome")));
        }

        [Fact]
        public void TaskPreFallsBackToChainPredecessor()
        {
            var catalog = Catalog(
                Task(1, "第一环", chain: "委托#1"),
                Task(2, "第二环", chain: "委托#2"),
                Task(3, "第三环", chain: "委托#3"));
            JObject context = DialogueTaskContext.Build(catalog, Save("1", "2"), "3", "task_pre");

            Assert.Equal(2, context["completed"].Value<int>("task_id"));
            Assert.Equal(3, context["upcoming"].Value<int>("task_id"));
        }

        [Fact]
        public void TaskPreOmitsCompletedWhenPairingIsAmbiguous()
        {
            var catalog = Catalog(
                Task(1, "甲", nextTaskId: new JValue(9)),
                Task(2, "乙", nextTaskId: new JValue(9)),
                Task(9, "当前"));
            JObject context = DialogueTaskContext.Build(catalog, Save("1", "2"), "9", "task_pre");

            Assert.NotNull(context);
            Assert.Null(context["completed"]);
        }

        [Fact]
        public void TaskPreOmitsCompletedWhenPredecessorNotFinished()
        {
            var catalog = Catalog(Task(1, "第一环", chain: "委托#1"), Task(2, "第二环", chain: "委托#2"));
            JObject context = DialogueTaskContext.Build(catalog, Save(), "2", "task_pre");

            Assert.Null(context["completed"]);
        }

        [Fact]
        public void TaskPostAddsNextTaskAsUpcoming()
        {
            var catalog = Catalog(
                Task(200124, "北边仓库失窃", nextTaskId: new JValue(200125),
                    objectives: new JArray("找回失窃货物")),
                Task(200125, "东边关卡增援"));
            JObject context = DialogueTaskContext.Build(catalog, Save(), "200124", "task_post");

            Assert.Equal(200124, context["completed"].Value<int>("task_id"));
            Assert.Equal(200125, context["upcoming"].Value<int>("task_id"));
            Assert.Equal("找回失窃货物", (string)context["completed"]["objectives"][0]);
        }

        [Fact]
        public void TaskPostOmitsUpcomingWhenNoPairing()
        {
            var catalog = Catalog(Task(200124, "北边仓库失窃"));
            JObject context = DialogueTaskContext.Build(catalog, Save(), "200124", "task_post");

            Assert.NotNull(context["completed"]);
            Assert.Null(context["upcoming"]);
        }

        [Fact]
        public void ObjectivesMergeAndDerefTextKeys()
        {
            var task = Task(7, "$TITLE",
                objectives: new JArray("废城环线#简单"),
                rewards: new JArray("金币#1200"));
            ((JArray)task["finish_submit_items"]).Add("$ITEM");
            ((JArray)task["finish_contain_items"]).Add("情报文件#2");
            var catalog = Catalog(task);
            JObject context = DialogueTaskContext.Build(catalog, Save(), "7", "task_post");

            var objectives = (JArray)context["completed"]["objectives"];
            Assert.Equal(3, objectives.Count);
            Assert.Equal("废城环线#简单", (string)objectives[0]);
            Assert.Equal("失窃货物", (string)objectives[1]);
            Assert.Equal("情报文件#2", (string)objectives[2]);
            Assert.Equal("北边仓库失窃", context["completed"].Value<string>("title"));
            Assert.Equal("金币#1200", (string)context["completed"]["rewards"][0]);
        }

        [Fact]
        public void NpcFallsBackToOtherRole()
        {
            var catalog = Catalog(Task(7, "任务", getNpc: "卫兵", finishNpc: ""));
            JObject context = DialogueTaskContext.Build(catalog, Save(), "7", "task_post");
            Assert.Equal("卫兵", context["completed"].Value<string>("npc"));
        }

        [Fact]
        public void MissingTaskSaveOrIdReturnsNull()
        {
            var catalog = Catalog(Task(7, "任务"));
            Assert.Null(DialogueTaskContext.Build(catalog, Save(), "999", "task_pre"));
            Assert.Null(DialogueTaskContext.Build(catalog, new JObject(), "7", "task_pre"));
            Assert.Null(DialogueTaskContext.Build(catalog, Save(), "", "task_pre"));
            Assert.Null(DialogueTaskContext.Build(null, Save(), "7", "task_pre"));
            Assert.Null(DialogueTaskContext.Build(catalog, Save(), "7", "gossip"));
        }
    }
}
