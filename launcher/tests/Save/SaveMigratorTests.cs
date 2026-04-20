// SaveMigrator 的 C# 镜像测试，与 SaveManagerTest.as 的对应用例同源。
// 仅覆盖 SaveMigrator 4 个 public API（IsAbsent / Migrate_2_7_to_3_0 /
// MergeTopLevelKeys / ValidateResolvedSnapshot）。
// AS2 测试里 prefetch / loadAll / tombstone / loadFromMydata 等属 SaveManager
// 运行时状态，不在 SaveMigrator 职责范围，不移植。

using CF7Launcher.Save;
using Newtonsoft.Json.Linq;
using Xunit;

namespace CF7Launcher.Tests.Save
{
    public class SaveMigratorTests
    {
        // ─────────────── helpers ───────────────

        /// <summary>构造一个通过 ValidateResolvedSnapshot 的最小 3.0 快照。</summary>
        private static JObject BuildValidMydata()
        {
            // 对齐 SaveManagerTest.as buildValidMydata()（L450-L472）
            JObject md = new JObject();
            md["version"] = "3.0";
            md["lastSaved"] = "2026-01-01 00:00:00";

            JArray slot0 = new JArray();
            slot0.Add("测试角色"); slot0.Add("男"); slot0.Add(1000); slot0.Add(10);
            slot0.Add(500); slot0.Add(170); slot0.Add(5); slot0.Add("无");
            slot0.Add(10000); slot0.Add(0); slot0.Add(new JArray()); slot0.Add(0);
            slot0.Add(new JArray()); slot0.Add("");
            md["0"] = slot0;

            JArray slot1 = new JArray();
            for (int i = 0; i < 28; i++) slot1.Add(0);
            md["1"] = slot1;

            md["2"] = JValue.CreateNull();
            md["3"] = 0;

            JArray slot4 = new JArray();
            slot4.Add(new JArray()); slot4.Add(0);
            md["4"] = slot4;

            md["5"] = new JArray();
            md["6"] = JValue.CreateNull();

            JArray slot7 = new JArray();
            for (int i = 0; i < 5; i++) slot7.Add(0);
            md["7"] = slot7;

            JObject inv = new JObject();
            inv["背包"] = new JArray();
            inv["装备栏"] = new JObject();
            inv["药剂栏"] = new JArray();
            inv["仓库"] = new JArray();
            inv["战备箱"] = new JArray();
            md["inventory"] = inv;

            JObject col = new JObject();
            col["材料"] = new JObject();
            col["情报"] = new JObject();
            md["collection"] = col;

            md["infrastructure"] = new JObject();

            JObject tasks = new JObject();
            tasks["tasks_to_do"] = new JArray();
            tasks["tasks_finished"] = new JObject();
            tasks["task_chains_progress"] = new JObject();
            md["tasks"] = tasks;

            JObject pets = new JObject();
            JArray petInfo = new JArray();
            for (int i = 0; i < 5; i++) petInfo.Add(new JArray());
            pets["宠物信息"] = petInfo;
            pets["宠物领养限制"] = 5;
            md["pets"] = pets;

            JObject shop = new JObject();
            shop["商城已购买物品"] = new JArray();
            shop["商城购物车"] = new JArray();
            md["shop"] = shop;

            return md;
        }

        // ─────────────── IsAbsent ───────────────

        [Fact]
        public void IsAbsent_NullToken_True()
        {
            Assert.True(SaveMigrator.IsAbsent(null));
        }

        [Fact]
        public void IsAbsent_JsonNull_True()
        {
            Assert.True(SaveMigrator.IsAbsent(JValue.CreateNull()));
        }

        [Fact]
        public void IsAbsent_MissingKey_True()
        {
            JObject o = new JObject();
            Assert.True(SaveMigrator.IsAbsent(o["nope"]));
        }

        [Fact]
        public void IsAbsent_Value_False()
        {
            Assert.False(SaveMigrator.IsAbsent(new JValue(0)));
            Assert.False(SaveMigrator.IsAbsent(new JValue("")));
            Assert.False(SaveMigrator.IsAbsent(new JArray()));
            Assert.False(SaveMigrator.IsAbsent(new JObject()));
        }

        // ─────────────── Migrate_2_7_to_3_0 ───────────────

        [Fact]
        public void Migrate_2_7_to_3_0_BasicFields()
        {
            // 对齐 test_migrate_2_7_to_3_0
            JObject mydata = new JObject();
            mydata["version"] = "2.7";
            JObject soData = new JObject();
            soData["test"] = mydata;
            JArray tasksToDo = new JArray(); tasksToDo.Add("a"); tasksToDo.Add("b");
            soData["tasks_to_do"] = tasksToDo;
            soData["tasks_finished"] = new JObject();
            soData["task_chains_progress"] = new JObject();

            JArray pets = new JArray();
            for (int i = 0; i < 5; i++) pets.Add(new JArray());
            soData["战宠"] = pets;
            soData["宠物领养限制"] = 5;

            JArray purchased = new JArray(); purchased.Add("item1");
            soData["商城已购买物品"] = purchased;
            soData["商城购物车"] = new JArray();

            SaveMigrator.Migrate_2_7_to_3_0(mydata, soData);

            Assert.Equal("3.0", mydata.Value<string>("version"));
            Assert.Equal(2, ((JArray)mydata["tasks"]["tasks_to_do"]).Count);
            Assert.Equal("item1",
                ((JArray)mydata["shop"]["商城已购买物品"])[0].Value<string>());
        }

        [Fact]
        public void Migrate_2_7_to_3_0_PreservesLegacyMainline()
        {
            // 对齐 test_migrate_2_7_to_3_0_preserves_legacy_mainline
            JObject mydata = new JObject();
            mydata["version"] = "2.7";
            mydata["3"] = 17;
            JObject soData = new JObject();
            soData["test"] = mydata;
            soData["tasks_to_do"] = new JArray();
            soData["tasks_finished"] = new JObject();
            soData["task_chains_progress"] = new JObject();
            JArray pets = new JArray();
            for (int i = 0; i < 5; i++) pets.Add(new JArray());
            soData["战宠"] = pets;
            soData["宠物领养限制"] = 5;
            soData["商城已购买物品"] = new JArray();
            soData["商城购物车"] = new JArray();

            SaveMigrator.Migrate_2_7_to_3_0(mydata, soData);

            Assert.Equal(17,
                mydata["tasks"]["task_chains_progress"]["主线"].Value<int>());
        }

        [Fact]
        public void Migrate_2_7_to_3_0_TasksFinishedIsObject()
        {
            // 对齐 test_tasks_finished_is_object
            JObject mydata = new JObject();
            mydata["version"] = "2.7";
            JObject soData = new JObject();
            soData["test"] = mydata;

            SaveMigrator.Migrate_2_7_to_3_0(mydata, soData);

            JToken tf = mydata["tasks"]["tasks_finished"];
            Assert.IsType<JObject>(tf);
            ((JObject)tf)["123"] = 1;
            Assert.Equal(1, tf["123"].Value<int>());
        }

        // ─────────────── MergeTopLevelKeys ───────────────

        [Fact]
        public void MergeTopLevelKeys_EmptyTopLevel_KeepsNestedTasks()
        {
            // 对齐 test_loadAll_sol_empty_top_level_keeps_nested_tasks
            JObject mydata = BuildValidMydata();
            mydata["3"] = 12;
            JObject nestedTasks = (JObject)mydata["tasks"];
            JArray nestedTodo = new JArray();
            nestedTodo.Add(new JObject(new JProperty("id", "nested_task")));
            nestedTasks["tasks_to_do"] = nestedTodo;
            JObject nestedFinished = new JObject();
            nestedFinished["500"] = 1;
            nestedTasks["tasks_finished"] = nestedFinished;
            JObject nestedProgress = new JObject();
            nestedProgress["主线"] = 12;
            nestedProgress["挑战"] = 3;
            nestedTasks["task_chains_progress"] = nestedProgress;

            JObject soData = new JObject();
            soData["test"] = mydata;
            soData["tasks_to_do"] = new JArray();
            soData["tasks_finished"] = new JObject();
            soData["task_chains_progress"] = new JObject();

            SaveMigrator.MergeTopLevelKeys(mydata, soData);

            Assert.Equal("nested_task",
                mydata["tasks"]["tasks_to_do"][0]["id"].Value<string>());
            Assert.Equal(1,
                mydata["tasks"]["tasks_finished"]["500"].Value<int>());
            Assert.Equal(12,
                mydata["tasks"]["task_chains_progress"]["主线"].Value<int>());
            Assert.Equal(3,
                mydata["tasks"]["task_chains_progress"]["挑战"].Value<int>());
        }

        [Fact]
        public void MergeTopLevelKeys_RepairsMainlineFromSlot3()
        {
            // 对齐 test_loadAll_sol_repairs_mainline_from_slot3
            JObject mydata = BuildValidMydata();
            mydata["3"] = 9;
            ((JObject)mydata["tasks"])["task_chains_progress"] = new JObject();

            JObject soData = new JObject();
            soData["test"] = mydata;
            soData["tasks_to_do"] = new JArray();
            soData["tasks_finished"] = new JObject();
            soData["task_chains_progress"] = new JObject();

            SaveMigrator.MergeTopLevelKeys(mydata, soData);

            Assert.Equal(9,
                mydata["tasks"]["task_chains_progress"]["主线"].Value<int>());
        }

        [Fact]
        public void MergeTopLevelKeys_EmptyTopLevel_KeepsNestedPets()
        {
            // 对齐 test_loadAll_sol_empty_top_level_keeps_nested_pets
            JObject mydata = BuildValidMydata();
            JArray petInfo = new JArray();
            JArray slot0 = new JArray(); slot0.Add("petA");
            petInfo.Add(slot0);
            for (int i = 0; i < 4; i++) petInfo.Add(new JArray());
            ((JObject)mydata["pets"])["宠物信息"] = petInfo;
            ((JObject)mydata["pets"])["宠物领养限制"] = 9;

            JObject soData = new JObject();
            soData["test"] = mydata;
            JArray emptyPets = new JArray();
            for (int i = 0; i < 5; i++) emptyPets.Add(new JArray());
            soData["战宠"] = emptyPets;
            soData["宠物领养限制"] = 5;

            SaveMigrator.MergeTopLevelKeys(mydata, soData);

            Assert.Equal("petA",
                mydata["pets"]["宠物信息"][0][0].Value<string>());
            Assert.Equal(9,
                mydata["pets"]["宠物领养限制"].Value<int>());
        }

        [Fact]
        public void MergeTopLevelKeys_EmptyTopLevel_KeepsNestedShop()
        {
            // 对齐 test_loadAll_sol_empty_top_level_keeps_nested_shop
            JObject mydata = BuildValidMydata();
            JArray purchased = new JArray(); purchased.Add("nested_item");
            ((JObject)mydata["shop"])["商城已购买物品"] = purchased;
            JArray cart = new JArray(); cart.Add("nested_cart");
            ((JObject)mydata["shop"])["商城购物车"] = cart;

            JObject soData = new JObject();
            soData["test"] = mydata;
            soData["商城已购买物品"] = new JArray();
            soData["商城购物车"] = new JArray();

            SaveMigrator.MergeTopLevelKeys(mydata, soData);

            Assert.Equal("nested_item",
                mydata["shop"]["商城已购买物品"][0].Value<string>());
            Assert.Equal("nested_cart",
                mydata["shop"]["商城购物车"][0].Value<string>());
        }

        [Fact]
        public void MergeTopLevelKeys_NonEmptyTopLevel_OverridesShop()
        {
            // 对齐 test_syncTopLevel_overwrite 语义（逆向：顶层有数据 → nested 被覆盖）
            JObject mydata = BuildValidMydata();
            JArray oldCart = new JArray(); oldCart.Add("old_cart");
            ((JObject)mydata["shop"])["商城购物车"] = oldCart;

            JObject soData = new JObject();
            soData["test"] = mydata;
            JArray newCart = new JArray(); newCart.Add("new_cart");
            soData["商城购物车"] = newCart;
            soData["商城已购买物品"] = new JArray();

            SaveMigrator.MergeTopLevelKeys(mydata, soData);

            Assert.Equal("new_cart",
                mydata["shop"]["商城购物车"][0].Value<string>());
        }

        [Fact]
        public void MergeTopLevelKeys_NestedPetsEmpty_UsesTopLevel()
        {
            // 顶层 pets 有数据，nested 为空 → 取顶层
            JObject mydata = BuildValidMydata();
            // nested pets.宠物信息 默认是 5 个空 array → HasPetEntries(nested) = false

            JObject soData = new JObject();
            soData["test"] = mydata;
            JArray pets = new JArray();
            JArray slot0 = new JArray(); slot0.Add("top_pet");
            pets.Add(slot0);
            for (int i = 0; i < 4; i++) pets.Add(new JArray());
            soData["战宠"] = pets;
            soData["宠物领养限制"] = 7;

            SaveMigrator.MergeTopLevelKeys(mydata, soData);

            Assert.Equal("top_pet",
                mydata["pets"]["宠物信息"][0][0].Value<string>());
            Assert.Equal(7,
                mydata["pets"]["宠物领养限制"].Value<int>());
        }

        // ─────────────── ValidateResolvedSnapshot ───────────────

        [Fact]
        public void Validate_BaselineValidSnapshot_True()
        {
            Assert.True(SaveMigrator.ValidateResolvedSnapshot(BuildValidMydata()));
        }

        [Fact]
        public void Validate_NullInput_False()
        {
            Assert.False(SaveMigrator.ValidateResolvedSnapshot(null));
        }

        [Theory]
        [InlineData("version")]          // version field missing / not "3.0"
        [InlineData("lastSaved")]         // 必须存在
        public void Validate_MissingTopLevelScalar_False(string key)
        {
            JObject md = BuildValidMydata();
            md.Remove(key);
            Assert.False(SaveMigrator.ValidateResolvedSnapshot(md));
        }

        [Fact]
        public void Validate_WrongVersion_False()
        {
            JObject md = BuildValidMydata();
            md["version"] = "2.7";
            Assert.False(SaveMigrator.ValidateResolvedSnapshot(md));
        }

        [Theory]
        [InlineData("0", 13)]   // mydata[0].Count < 14 → 拒绝（边界：13 不够）
        [InlineData("1", 27)]   // mydata[1].Count < 28
        [InlineData("4", 1)]    // mydata[4].Count < 2
        [InlineData("7", 4)]    // mydata[7].Count < 5
        public void Validate_ShortSlotArray_False(string key, int length)
        {
            JObject md = BuildValidMydata();
            JArray shorter = new JArray();
            for (int i = 0; i < length; i++) shorter.Add(0);
            md[key] = shorter;
            Assert.False(SaveMigrator.ValidateResolvedSnapshot(md));
        }

        [Theory]
        [InlineData("0")]
        [InlineData("1")]
        [InlineData("4")]
        [InlineData("7")]
        public void Validate_SlotArrayReplacedByObject_False(string key)
        {
            JObject md = BuildValidMydata();
            md[key] = new JObject();
            Assert.False(SaveMigrator.ValidateResolvedSnapshot(md));
        }

        [Fact]
        public void Validate_MissingSlot3_False()
        {
            // mydata[3] 只检 IsAbsent（非数组）
            JObject md = BuildValidMydata();
            md.Remove("3");
            Assert.False(SaveMigrator.ValidateResolvedSnapshot(md));
        }

        [Fact]
        public void Validate_Slot5NotArray_False()
        {
            JObject md = BuildValidMydata();
            md["5"] = new JObject();  // 不是 JArray
            Assert.False(SaveMigrator.ValidateResolvedSnapshot(md));
        }

        [Theory]
        [InlineData("背包")]
        [InlineData("装备栏")]
        [InlineData("药剂栏")]
        [InlineData("仓库")]
        [InlineData("战备箱")]
        public void Validate_MissingInventoryField_False(string field)
        {
            JObject md = BuildValidMydata();
            ((JObject)md["inventory"]).Remove(field);
            Assert.False(SaveMigrator.ValidateResolvedSnapshot(md));
        }

        [Fact]
        public void Validate_MissingInventoryObject_False()
        {
            JObject md = BuildValidMydata();
            md.Remove("inventory");
            Assert.False(SaveMigrator.ValidateResolvedSnapshot(md));
        }

        [Theory]
        [InlineData("材料")]
        [InlineData("情报")]
        public void Validate_MissingCollectionField_False(string field)
        {
            JObject md = BuildValidMydata();
            ((JObject)md["collection"]).Remove(field);
            Assert.False(SaveMigrator.ValidateResolvedSnapshot(md));
        }

        [Fact]
        public void Validate_MissingCollectionObject_False()
        {
            JObject md = BuildValidMydata();
            md.Remove("collection");
            Assert.False(SaveMigrator.ValidateResolvedSnapshot(md));
        }

        [Fact]
        public void Validate_MissingInfrastructure_False()
        {
            JObject md = BuildValidMydata();
            md.Remove("infrastructure");
            Assert.False(SaveMigrator.ValidateResolvedSnapshot(md));
        }

        [Theory]
        [InlineData("tasks_to_do")]
        [InlineData("tasks_finished")]
        [InlineData("task_chains_progress")]
        public void Validate_MissingTasksField_False(string field)
        {
            JObject md = BuildValidMydata();
            ((JObject)md["tasks"]).Remove(field);
            Assert.False(SaveMigrator.ValidateResolvedSnapshot(md));
        }

        [Fact]
        public void Validate_MissingTasksObject_False()
        {
            JObject md = BuildValidMydata();
            md.Remove("tasks");
            Assert.False(SaveMigrator.ValidateResolvedSnapshot(md));
        }

        [Theory]
        [InlineData("宠物信息")]
        [InlineData("宠物领养限制")]
        public void Validate_MissingPetsField_False(string field)
        {
            JObject md = BuildValidMydata();
            ((JObject)md["pets"]).Remove(field);
            Assert.False(SaveMigrator.ValidateResolvedSnapshot(md));
        }

        [Fact]
        public void Validate_MissingPetsObject_False()
        {
            JObject md = BuildValidMydata();
            md.Remove("pets");
            Assert.False(SaveMigrator.ValidateResolvedSnapshot(md));
        }

        [Theory]
        [InlineData("商城已购买物品")]
        [InlineData("商城购物车")]
        public void Validate_MissingShopField_False(string field)
        {
            JObject md = BuildValidMydata();
            ((JObject)md["shop"]).Remove(field);
            Assert.False(SaveMigrator.ValidateResolvedSnapshot(md));
        }

        [Fact]
        public void Validate_MissingShopObject_False()
        {
            JObject md = BuildValidMydata();
            md.Remove("shop");
            Assert.False(SaveMigrator.ValidateResolvedSnapshot(md));
        }
    }
}
