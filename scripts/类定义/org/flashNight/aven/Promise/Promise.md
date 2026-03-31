import org.flashNight.aven.Promise.*; // 包含 ListLoaderTest
import org.flashNight.gesh.xml.LoadXml.EnemyPropertiesLoader;
import org.flashNight.gesh.xml.LoadXml.ItemDataLoader;
import org.flashNight.gesh.xml.LoadXml.EquipModListLoader;
import org.flashNight.gesh.xml.LoadXml.StageInfoLoader;
import org.flashNight.gesh.xml.LoadXml.NpcDialogueLoader;
import org.flashNight.gesh.json.LoadJson.TaskTextLoader;
import org.flashNight.gesh.json.LoadJson.TaskDataLoader;
import org.flashNight.gesh.json.LoadJson.CraftingListLoader;

var PROMISE_TEST_MODE:String = "listloader"; // all | a_plus | bench | listloader | none

if (PROMISE_TEST_MODE == "all") {
    PromiseAPlusTest.main();

    var _promiseBenchStarter:MovieClip = _root.createEmptyMovieClip(
        "_promiseBenchStarter",
        _root.getNextHighestDepth()
    );
    var _promiseBenchFramesLeft:Number = 70;
    _promiseBenchStarter.onEnterFrame = function():Void {
        _promiseBenchFramesLeft--;
        if (_promiseBenchFramesLeft <= 0) {
            delete this.onEnterFrame;
            this.removeMovieClip();
            trace("");
            trace("=== Promise Bench Start ===");
            PromisePerformanceBench.run();
        }
    };
} else if (PROMISE_TEST_MODE == "a_plus") {
    PromiseAPlusTest.main();
} else if (PROMISE_TEST_MODE == "bench") {
    PromisePerformanceBench.run();
} else if (PROMISE_TEST_MODE == "listloader") {
    ListLoaderTest.main();
} else {
    trace("[TestLoader] PROMISE_TEST_MODE=none");
}



=== ListLoader Infrastructure Tests ===
[PathManager] [DEBUG] 正常模式：当前 URL: file:///C|/Program Files (x86)/Steam/steamapps/common/CRAZYFLASHER7StandAloneStarter/CrazyFlashNight/scripts/TestLoader.swf
[PathManager] [INFO] 检测到 Steam 环境，设置为 Steam 模式。
[PathManager] [INFO] 匹配基础路径 'CrazyFlashNight/'，基础路径设置为: file:///C|/Program Files (x86)/Steam/steamapps/common/CRAZYFLASHER7StandAloneStarter/CrazyFlashNight/
[PathManager] [INFO] 基础路径设置为 Steam 环境路径: file:///C|/Program Files (x86)/Steam/steamapps/common/CRAZYFLASHER7StandAloneStarter/CrazyFlashNight/
[PathManager] [DEBUG] 路径解析: 'data/enemy_properties/list.xml' -> 'file:///C|/Program Files (x86)/Steam/steamapps/common/CRAZYFLASHER7StandAloneStarter/CrazyFlashNight/data/enemy_properties/list.xml'
[PathManager] [DEBUG] 路径解析: 'data/nonexistent/fake.xml' -> 'file:///C|/Program Files (x86)/Steam/steamapps/common/CRAZYFLASHER7StandAloneStarter/CrazyFlashNight/data/nonexistent/fake.xml'
[PathManager] [DEBUG] 路径解析: 'data/task/general_tasks.json' -> 'file:///C|/Program Files (x86)/Steam/steamapps/common/CRAZYFLASHER7StandAloneStarter/CrazyFlashNight/data/task/general_tasks.json'
[PathManager] [DEBUG] 路径解析: 'data/enemy_properties/list.xml' -> 'file:///C|/Program Files (x86)/Steam/steamapps/common/CRAZYFLASHER7StandAloneStarter/CrazyFlashNight/data/enemy_properties/list.xml'
[PathManager] [DEBUG] 路径解析: 'data/items/list.xml' -> 'file:///C|/Program Files (x86)/Steam/steamapps/common/CRAZYFLASHER7StandAloneStarter/CrazyFlashNight/data/items/list.xml'
[PASS] normalizeToArray-scalar
[PASS] normalizeToArray-array
[PathManager] [DEBUG] 路径解析: 'data/enemy_properties/list.xml' -> 'file:///C|/Program Files (x86)/Steam/steamapps/common/CRAZYFLASHER7StandAloneStarter/CrazyFlashNight/data/enemy_properties/list.xml'
[PathManager] [DEBUG] 路径解析: 'data/enemy_properties/list.xml' -> 'file:///C|/Program Files (x86)/Steam/steamapps/common/CRAZYFLASHER7StandAloneStarter/CrazyFlashNight/data/enemy_properties/list.xml'
[PathManager] [DEBUG] 路径解析: 'data/fake_path/nonexistent_file_1.xml' -> 'file:///C|/Program Files (x86)/Steam/steamapps/common/CRAZYFLASHER7StandAloneStarter/CrazyFlashNight/data/fake_path/nonexistent_file_1.xml'
[PathManager] [DEBUG] 路径解析: 'data/fake_path/nonexistent_file_2.xml' -> 'file:///C|/Program Files (x86)/Steam/steamapps/common/CRAZYFLASHER7StandAloneStarter/CrazyFlashNight/data/fake_path/nonexistent_file_2.xml'
[PathManager] [DEBUG] 路径解析: 'data/items/list.xml' -> 'file:///C|/Program Files (x86)/Steam/steamapps/common/CRAZYFLASHER7StandAloneStarter/CrazyFlashNight/data/items/list.xml'
[PathManager] [DEBUG] 路径解析: 'data/items/equipment_mods/list.xml' -> 'file:///C|/Program Files (x86)/Steam/steamapps/common/CRAZYFLASHER7StandAloneStarter/CrazyFlashNight/data/items/equipment_mods/list.xml'
[PathManager] [DEBUG] 路径解析: 'data/stages/list.xml' -> 'file:///C|/Program Files (x86)/Steam/steamapps/common/CRAZYFLASHER7StandAloneStarter/CrazyFlashNight/data/stages/list.xml'
[PathManager] [DEBUG] 路径解析: 'data/dialogues/list.xml' -> 'file:///C|/Program Files (x86)/Steam/steamapps/common/CRAZYFLASHER7StandAloneStarter/CrazyFlashNight/data/dialogues/list.xml'
[PathManager] [DEBUG] 路径解析: 'data/task/text/list.xml' -> 'file:///C|/Program Files (x86)/Steam/steamapps/common/CRAZYFLASHER7StandAloneStarter/CrazyFlashNight/data/task/text/list.xml'
[PathManager] [DEBUG] 路径解析: 'data/task/list.xml' -> 'file:///C|/Program Files (x86)/Steam/steamapps/common/CRAZYFLASHER7StandAloneStarter/CrazyFlashNight/data/task/list.xml'
[PathManager] [DEBUG] 路径解析: 'data/crafting/list.xml' -> 'file:///C|/Program Files (x86)/Steam/steamapps/common/CRAZYFLASHER7StandAloneStarter/CrazyFlashNight/data/crafting/list.xml'
[compile] done
XMLLoader: Failed to load XML file.
[BaseXMLLoader] [ERROR] XML 文件加载失败！文件: 'file:///C|/Program Files (x86)/Steam/steamapps/common/CRAZYFLASHER7StandAloneStarter/CrazyFlashNight/data/nonexistent/fake.xml'，耗时: 92ms
[BaseXMLLoader] [ERROR] 可能的原因: 1)文件不存在 2)路径错误 3)网络问题 4)XML格式错误
打开 URL 'file:///C|/Program Files (x86)/Steam/steamapps/common/CRAZYFLASHER7StandAloneStarter/CrazyFlashNight/data/nonexistent/fake.xml' 时出错
XMLLoader: Failed to load XML file.
[BaseXMLLoader] [ERROR] XML 文件加载失败！文件: 'file:///C|/Program Files (x86)/Steam/steamapps/common/CRAZYFLASHER7StandAloneStarter/CrazyFlashNight/data/fake_path/nonexistent_file_1.xml'，耗时: 90ms
[BaseXMLLoader] [ERROR] 可能的原因: 1)文件不存在 2)路径错误 3)网络问题 4)XML格式错误
打开 URL 'file:///C|/Program Files (x86)/Steam/steamapps/common/CRAZYFLASHER7StandAloneStarter/CrazyFlashNight/data/fake_path/nonexistent_file_1.xml' 时出错
XMLLoader: Failed to load XML file.
[BaseXMLLoader] [ERROR] XML 文件加载失败！文件: 'file:///C|/Program Files (x86)/Steam/steamapps/common/CRAZYFLASHER7StandAloneStarter/CrazyFlashNight/data/fake_path/nonexistent_file_2.xml'，耗时: 91ms
[BaseXMLLoader] [ERROR] 可能的原因: 1)文件不存在 2)路径错误 3)网络问题 4)XML格式错误
打开 URL 'file:///C|/Program Files (x86)/Steam/steamapps/common/CRAZYFLASHER7StandAloneStarter/CrazyFlashNight/data/fake_path/nonexistent_file_2.xml' 时出错
[PASS] loadXML-failure
[PathManager] [DEBUG] 路径解析: 'data/enemy_properties/原版敌人 2011-2012.xml' -> 'file:///C|/Program Files (x86)/Steam/steamapps/common/CRAZYFLASHER7StandAloneStarter/CrazyFlashNight/data/enemy_properties/原版敌人 2011-2012.xml'
[PathManager] [DEBUG] 路径解析: 'data/enemy_properties/原版敌人 2013-2016.xml' -> 'file:///C|/Program Files (x86)/Steam/steamapps/common/CRAZYFLASHER7StandAloneStarter/CrazyFlashNight/data/enemy_properties/原版敌人 2013-2016.xml'
[PathManager] [DEBUG] 路径解析: 'data/enemy_properties/换皮敌人与战宠.xml' -> 'file:///C|/Program Files (x86)/Steam/steamapps/common/CRAZYFLASHER7StandAloneStarter/CrazyFlashNight/data/enemy_properties/换皮敌人与战宠.xml'
[PathManager] [DEBUG] 路径解析: 'data/enemy_properties/彩蛋支线.xml' -> 'file:///C|/Program Files (x86)/Steam/steamapps/common/CRAZYFLASHER7StandAloneStarter/CrazyFlashNight/data/enemy_properties/彩蛋支线.xml'
[PathManager] [DEBUG] 路径解析: 'data/items/消耗品_货币.xml' -> 'file:///C|/Program Files (x86)/Steam/steamapps/common/CRAZYFLASHER7StandAloneStarter/CrazyFlashNight/data/items/消耗品_货币.xml'
[PathManager] [DEBUG] 路径解析: 'data/items/消耗品_弹夹.xml' -> 'file:///C|/Program Files (x86)/Steam/steamapps/common/CRAZYFLASHER7StandAloneStarter/CrazyFlashNight/data/items/消耗品_弹夹.xml'
[PathManager] [DEBUG] 路径解析: 'data/items/消耗品_药剂.xml' -> 'file:///C|/Program Files (x86)/Steam/steamapps/common/CRAZYFLASHER7StandAloneStarter/CrazyFlashNight/data/items/消耗品_药剂.xml'
[PathManager] [DEBUG] 路径解析: 'data/items/消耗品_药剂_食品.xml' -> 'file:///C|/Program Files (x86)/Steam/steamapps/common/CRAZYFLASHER7StandAloneStarter/CrazyFlashNight/data/items/消耗品_药剂_食品.xml'
[PathManager] [DEBUG] 路径解析: 'data/items/equipment_mods/低级材料_防具专用.xml' -> 'file:///C|/Program Files (x86)/Steam/steamapps/common/CRAZYFLASHER7StandAloneStarter/CrazyFlashNight/data/items/equipment_mods/低级材料_防具专用.xml'
[PathManager] [DEBUG] 路径解析: 'data/items/equipment_mods/低级材料_枪械专用.xml' -> 'file:///C|/Program Files (x86)/Steam/steamapps/common/CRAZYFLASHER7StandAloneStarter/CrazyFlashNight/data/items/equipment_mods/低级材料_枪械专用.xml'
[PathManager] [DEBUG] 路径解析: 'data/items/equipment_mods/低级材料_刀专用.xml' -> 'file:///C|/Program Files (x86)/Steam/steamapps/common/CRAZYFLASHER7StandAloneStarter/CrazyFlashNight/data/items/equipment_mods/低级材料_刀专用.xml'
[PathManager] [DEBUG] 路径解析: 'data/items/equipment_mods/低级材料_拳专用.xml' -> 'file:///C|/Program Files (x86)/Steam/steamapps/common/CRAZYFLASHER7StandAloneStarter/CrazyFlashNight/data/items/equipment_mods/低级材料_拳专用.xml'
[PathManager] [DEBUG] 路径解析: 'data/stages/基地门口/__list__.xml' -> 'file:///C|/Program Files (x86)/Steam/steamapps/common/CRAZYFLASHER7StandAloneStarter/CrazyFlashNight/data/stages/基地门口/__list__.xml'
[PathManager] [DEBUG] 路径解析: 'data/stages/基地车库/__list__.xml' -> 'file:///C|/Program Files (x86)/Steam/steamapps/common/CRAZYFLASHER7StandAloneStarter/CrazyFlashNight/data/stages/基地车库/__list__.xml'
[PathManager] [DEBUG] 路径解析: 'data/stages/基地房顶/__list__.xml' -> 'file:///C|/Program Files (x86)/Steam/steamapps/common/CRAZYFLASHER7StandAloneStarter/CrazyFlashNight/data/stages/基地房顶/__list__.xml'
[PathManager] [DEBUG] 路径解析: 'data/stages/地下2层/__list__.xml' -> 'file:///C|/Program Files (x86)/Steam/steamapps/common/CRAZYFLASHER7StandAloneStarter/CrazyFlashNight/data/stages/地下2层/__list__.xml'
[PathManager] [DEBUG] 路径解析: 'data/dialogues/npc_dialogue_商人.xml' -> 'file:///C|/Program Files (x86)/Steam/steamapps/common/CRAZYFLASHER7StandAloneStarter/CrazyFlashNight/data/dialogues/npc_dialogue_商人.xml'
[PathManager] [DEBUG] 路径解析: 'data/dialogues/npc_dialogue_彩蛋.xml' -> 'file:///C|/Program Files (x86)/Steam/steamapps/common/CRAZYFLASHER7StandAloneStarter/CrazyFlashNight/data/dialogues/npc_dialogue_彩蛋.xml'
[PathManager] [DEBUG] 路径解析: 'data/dialogues/npc_dialogue_成员.xml' -> 'file:///C|/Program Files (x86)/Steam/steamapps/common/CRAZYFLASHER7StandAloneStarter/CrazyFlashNight/data/dialogues/npc_dialogue_成员.xml'
[PathManager] [DEBUG] 路径解析: 'data/dialogues/npc_dialogue_摇滚公园.xml' -> 'file:///C|/Program Files (x86)/Steam/steamapps/common/CRAZYFLASHER7StandAloneStarter/CrazyFlashNight/data/dialogues/npc_dialogue_摇滚公园.xml'
[PathManager] [DEBUG] 路径解析: 'data/task/text/text1.json' -> 'file:///C|/Program Files (x86)/Steam/steamapps/common/CRAZYFLASHER7StandAloneStarter/CrazyFlashNight/data/task/text/text1.json'
[PathManager] [DEBUG] 路径解析: 'data/task/text/text2.json' -> 'file:///C|/Program Files (x86)/Steam/steamapps/common/CRAZYFLASHER7StandAloneStarter/CrazyFlashNight/data/task/text/text2.json'
[PathManager] [DEBUG] 路径解析: 'data/task/text/general_texts.json' -> 'file:///C|/Program Files (x86)/Steam/steamapps/common/CRAZYFLASHER7StandAloneStarter/CrazyFlashNight/data/task/text/general_texts.json'
[PathManager] [DEBUG] 路径解析: 'data/task/text/guide_text.json' -> 'file:///C|/Program Files (x86)/Steam/steamapps/common/CRAZYFLASHER7StandAloneStarter/CrazyFlashNight/data/task/text/guide_text.json'
[PathManager] [DEBUG] 路径解析: 'data/task/tasks1.json' -> 'file:///C|/Program Files (x86)/Steam/steamapps/common/CRAZYFLASHER7StandAloneStarter/CrazyFlashNight/data/task/tasks1.json'
[PathManager] [DEBUG] 路径解析: 'data/task/tasks2.json' -> 'file:///C|/Program Files (x86)/Steam/steamapps/common/CRAZYFLASHER7StandAloneStarter/CrazyFlashNight/data/task/tasks2.json'
[PathManager] [DEBUG] 路径解析: 'data/task/general_tasks.json' -> 'file:///C|/Program Files (x86)/Steam/steamapps/common/CRAZYFLASHER7StandAloneStarter/CrazyFlashNight/data/task/general_tasks.json'
[PathManager] [DEBUG] 路径解析: 'data/task/guide_tasks.json' -> 'file:///C|/Program Files (x86)/Steam/steamapps/common/CRAZYFLASHER7StandAloneStarter/CrazyFlashNight/data/task/guide_tasks.json'
[PathManager] [DEBUG] 路径解析: 'data/crafting/铁枪会.json' -> 'file:///C|/Program Files (x86)/Steam/steamapps/common/CRAZYFLASHER7StandAloneStarter/CrazyFlashNight/data/crafting/铁枪会.json'
[PathManager] [DEBUG] 路径解析: 'data/crafting/属性武器.json' -> 'file:///C|/Program Files (x86)/Steam/steamapps/common/CRAZYFLASHER7StandAloneStarter/CrazyFlashNight/data/crafting/属性武器.json'
[PathManager] [DEBUG] 路径解析: 'data/crafting/烹饪.json' -> 'file:///C|/Program Files (x86)/Steam/steamapps/common/CRAZYFLASHER7StandAloneStarter/CrazyFlashNight/data/crafting/烹饪.json'
[PathManager] [DEBUG] 路径解析: 'data/crafting/化学生产.json' -> 'file:///C|/Program Files (x86)/Steam/steamapps/common/CRAZYFLASHER7StandAloneStarter/CrazyFlashNight/data/crafting/化学生产.json'
[PASS] loadXML-success
[PASS] loadJSON-success
[PathManager] [DEBUG] 路径解析: 'data/enemy_properties/原版敌人 2011-2012.xml' -> 'file:///C|/Program Files (x86)/Steam/steamapps/common/CRAZYFLASHER7StandAloneStarter/CrazyFlashNight/data/enemy_properties/原版敌人 2011-2012.xml'
[PathManager] [DEBUG] 路径解析: 'data/enemy_properties/原版敌人 2013-2016.xml' -> 'file:///C|/Program Files (x86)/Steam/steamapps/common/CRAZYFLASHER7StandAloneStarter/CrazyFlashNight/data/enemy_properties/原版敌人 2013-2016.xml'
[PathManager] [DEBUG] 路径解析: 'data/enemy_properties/换皮敌人与战宠.xml' -> 'file:///C|/Program Files (x86)/Steam/steamapps/common/CRAZYFLASHER7StandAloneStarter/CrazyFlashNight/data/enemy_properties/换皮敌人与战宠.xml'
[PathManager] [DEBUG] 路径解析: 'data/enemy_properties/彩蛋支线.xml' -> 'file:///C|/Program Files (x86)/Steam/steamapps/common/CRAZYFLASHER7StandAloneStarter/CrazyFlashNight/data/enemy_properties/彩蛋支线.xml'
[PathManager] [DEBUG] 路径解析: 'data/items/消耗品_货币.xml' -> 'file:///C|/Program Files (x86)/Steam/steamapps/common/CRAZYFLASHER7StandAloneStarter/CrazyFlashNight/data/items/消耗品_货币.xml'
[PathManager] [DEBUG] 路径解析: 'data/items/消耗品_弹夹.xml' -> 'file:///C|/Program Files (x86)/Steam/steamapps/common/CRAZYFLASHER7StandAloneStarter/CrazyFlashNight/data/items/消耗品_弹夹.xml'
[PathManager] [DEBUG] 路径解析: 'data/items/消耗品_药剂.xml' -> 'file:///C|/Program Files (x86)/Steam/steamapps/common/CRAZYFLASHER7StandAloneStarter/CrazyFlashNight/data/items/消耗品_药剂.xml'
[PathManager] [DEBUG] 路径解析: 'data/items/消耗品_药剂_食品.xml' -> 'file:///C|/Program Files (x86)/Steam/steamapps/common/CRAZYFLASHER7StandAloneStarter/CrazyFlashNight/data/items/消耗品_药剂_食品.xml'
[PathManager] [DEBUG] 路径解析: 'data/enemy_properties/原版敌人 2011-2012.xml' -> 'file:///C|/Program Files (x86)/Steam/steamapps/common/CRAZYFLASHER7StandAloneStarter/CrazyFlashNight/data/enemy_properties/原版敌人 2011-2012.xml'
[PASS] error-single-reject
[PathManager] [DEBUG] 路径解析: 'data/enemy_properties/诺亚新敌人.xml' -> 'file:///C|/Program Files (x86)/Steam/steamapps/common/CRAZYFLASHER7StandAloneStarter/CrazyFlashNight/data/enemy_properties/诺亚新敌人.xml'
[PathManager] [DEBUG] 路径解析: 'data/enemy_properties/魔神.xml' -> 'file:///C|/Program Files (x86)/Steam/steamapps/common/CRAZYFLASHER7StandAloneStarter/CrazyFlashNight/data/enemy_properties/魔神.xml'
[PathManager] [DEBUG] 路径解析: 'data/enemy_properties/天网.xml' -> 'file:///C|/Program Files (x86)/Steam/steamapps/common/CRAZYFLASHER7StandAloneStarter/CrazyFlashNight/data/enemy_properties/天网.xml'
[PathManager] [DEBUG] 路径解析: 'data/enemy_properties/boss重做.xml' -> 'file:///C|/Program Files (x86)/Steam/steamapps/common/CRAZYFLASHER7StandAloneStarter/CrazyFlashNight/data/enemy_properties/boss重做.xml'
[PathManager] [DEBUG] 路径解析: 'data/items/收集品_材料.xml' -> 'file:///C|/Program Files (x86)/Steam/steamapps/common/CRAZYFLASHER7StandAloneStarter/CrazyFlashNight/data/items/收集品_材料.xml'
[PathManager] [DEBUG] 路径解析: 'data/items/收集品_材料_插件.xml' -> 'file:///C|/Program Files (x86)/Steam/steamapps/common/CRAZYFLASHER7StandAloneStarter/CrazyFlashNight/data/items/收集品_材料_插件.xml'
[PathManager] [DEBUG] 路径解析: 'data/items/消耗品_手雷.xml' -> 'file:///C|/Program Files (x86)/Steam/steamapps/common/CRAZYFLASHER7StandAloneStarter/CrazyFlashNight/data/items/消耗品_手雷.xml'
[PathManager] [DEBUG] 路径解析: 'data/items/消耗品_材料_食材.xml' -> 'file:///C|/Program Files (x86)/Steam/steamapps/common/CRAZYFLASHER7StandAloneStarter/CrazyFlashNight/data/items/消耗品_材料_食材.xml'
[PathManager] [DEBUG] 路径解析: 'data/items/equipment_mods/低级材料_通用.xml' -> 'file:///C|/Program Files (x86)/Steam/steamapps/common/CRAZYFLASHER7StandAloneStarter/CrazyFlashNight/data/items/equipment_mods/低级材料_通用.xml'
[PathManager] [DEBUG] 路径解析: 'data/items/equipment_mods/低级材料_下挂武器.xml' -> 'file:///C|/Program Files (x86)/Steam/steamapps/common/CRAZYFLASHER7StandAloneStarter/CrazyFlashNight/data/items/equipment_mods/低级材料_下挂武器.xml'
[PathManager] [DEBUG] 路径解析: 'data/items/equipment_mods/中等材料_防具专用.xml' -> 'file:///C|/Program Files (x86)/Steam/steamapps/common/CRAZYFLASHER7StandAloneStarter/CrazyFlashNight/data/items/equipment_mods/中等材料_防具专用.xml'
[PathManager] [DEBUG] 路径解析: 'data/items/equipment_mods/中等材料_枪械专用.xml' -> 'file:///C|/Program Files (x86)/Steam/steamapps/common/CRAZYFLASHER7StandAloneStarter/CrazyFlashNight/data/items/equipment_mods/中等材料_枪械专用.xml'
[PathManager] [DEBUG] 路径解析: 'data/stages/副本任务/__list__.xml' -> 'file:///C|/Program Files (x86)/Steam/steamapps/common/CRAZYFLASHER7StandAloneStarter/CrazyFlashNight/data/stages/副本任务/__list__.xml'
[PathManager] [DEBUG] 路径解析: 'data/stages/黑铁会总部/__list__.xml' -> 'file:///C|/Program Files (x86)/Steam/steamapps/common/CRAZYFLASHER7StandAloneStarter/CrazyFlashNight/data/stages/黑铁会总部/__list__.xml'
[PathManager] [DEBUG] 路径解析: 'data/stages/诺亚前线基地深处/__list__.xml' -> 'file:///C|/Program Files (x86)/Steam/steamapps/common/CRAZYFLASHER7StandAloneStarter/CrazyFlashNight/data/stages/诺亚前线基地深处/__list__.xml'
[PathManager] [DEBUG] 路径解析: 'data/stages/诺亚前线基地深处第二层/__list__.xml' -> 'file:///C|/Program Files (x86)/Steam/steamapps/common/CRAZYFLASHER7StandAloneStarter/CrazyFlashNight/data/stages/诺亚前线基地深处第二层/__list__.xml'
[PathManager] [DEBUG] 路径解析: 'data/dialogues/npc_dialogue_联合大学.xml' -> 'file:///C|/Program Files (x86)/Steam/steamapps/common/CRAZYFLASHER7StandAloneStarter/CrazyFlashNight/data/dialogues/npc_dialogue_联合大学.xml'
[PathManager] [DEBUG] 路径解析: 'data/dialogues/npc_dialogue_军阀.xml' -> 'file:///C|/Program Files (x86)/Steam/steamapps/common/CRAZYFLASHER7StandAloneStarter/CrazyFlashNight/data/dialogues/npc_dialogue_军阀.xml'
[PathManager] [DEBUG] 路径解析: 'data/dialogues/npc_dialogue_黑铁会.xml' -> 'file:///C|/Program Files (x86)/Steam/steamapps/common/CRAZYFLASHER7StandAloneStarter/CrazyFlashNight/data/dialogues/npc_dialogue_黑铁会.xml'
[PathManager] [DEBUG] 路径解析: 'data/dialogues/npc_dialogue_A兵团.xml' -> 'file:///C|/Program Files (x86)/Steam/steamapps/common/CRAZYFLASHER7StandAloneStarter/CrazyFlashNight/data/dialogues/npc_dialogue_A兵团.xml'
[PathManager] [DEBUG] 路径解析: 'data/task/text/challenge_text.json' -> 'file:///C|/Program Files (x86)/Steam/steamapps/common/CRAZYFLASHER7StandAloneStarter/CrazyFlashNight/data/task/text/challenge_text.json'
[PathManager] [DEBUG] 路径解析: 'data/task/text/mercenary_text.json' -> 'file:///C|/Program Files (x86)/Steam/steamapps/common/CRAZYFLASHER7StandAloneStarter/CrazyFlashNight/data/task/text/mercenary_text.json'
[PathManager] [DEBUG] 路径解析: 'data/task/text/preview_text.json' -> 'file:///C|/Program Files (x86)/Steam/steamapps/common/CRAZYFLASHER7StandAloneStarter/CrazyFlashNight/data/task/text/preview_text.json'
[PathManager] [DEBUG] 路径解析: 'data/task/text/bonus_text.json' -> 'file:///C|/Program Files (x86)/Steam/steamapps/common/CRAZYFLASHER7StandAloneStarter/CrazyFlashNight/data/task/text/bonus_text.json'
[PathManager] [DEBUG] 路径解析: 'data/task/challenge_tasks.json' -> 'file:///C|/Program Files (x86)/Steam/steamapps/common/CRAZYFLASHER7StandAloneStarter/CrazyFlashNight/data/task/challenge_tasks.json'
[PathManager] [DEBUG] 路径解析: 'data/task/mercenary_tasks.json' -> 'file:///C|/Program Files (x86)/Steam/steamapps/common/CRAZYFLASHER7StandAloneStarter/CrazyFlashNight/data/task/mercenary_tasks.json'
[PathManager] [DEBUG] 路径解析: 'data/task/preview_tasks.json' -> 'file:///C|/Program Files (x86)/Steam/steamapps/common/CRAZYFLASHER7StandAloneStarter/CrazyFlashNight/data/task/preview_tasks.json'
[PathManager] [DEBUG] 路径解析: 'data/task/bonus_tasks.json' -> 'file:///C|/Program Files (x86)/Steam/steamapps/common/CRAZYFLASHER7StandAloneStarter/CrazyFlashNight/data/task/bonus_tasks.json'
[PathManager] [DEBUG] 路径解析: 'data/crafting/武器合成.json' -> 'file:///C|/Program Files (x86)/Steam/steamapps/common/CRAZYFLASHER7StandAloneStarter/CrazyFlashNight/data/crafting/武器合成.json'
[PathManager] [DEBUG] 路径解析: 'data/crafting/饰品合成.json' -> 'file:///C|/Program Files (x86)/Steam/steamapps/common/CRAZYFLASHER7StandAloneStarter/CrazyFlashNight/data/crafting/饰品合成.json'
[PathManager] [DEBUG] 路径解析: 'data/crafting/进阶防具.json' -> 'file:///C|/Program Files (x86)/Steam/steamapps/common/CRAZYFLASHER7StandAloneStarter/CrazyFlashNight/data/crafting/进阶防具.json'
[PathManager] [DEBUG] 路径解析: 'data/crafting/基础防具.json' -> 'file:///C|/Program Files (x86)/Steam/steamapps/common/CRAZYFLASHER7StandAloneStarter/CrazyFlashNight/data/crafting/基础防具.json'
[PathManager] [DEBUG] 路径解析: 'data/enemy_properties/诺亚新敌人.xml' -> 'file:///C|/Program Files (x86)/Steam/steamapps/common/CRAZYFLASHER7StandAloneStarter/CrazyFlashNight/data/enemy_properties/诺亚新敌人.xml'
[PathManager] [DEBUG] 路径解析: 'data/enemy_properties/魔神.xml' -> 'file:///C|/Program Files (x86)/Steam/steamapps/common/CRAZYFLASHER7StandAloneStarter/CrazyFlashNight/data/enemy_properties/魔神.xml'
[PathManager] [DEBUG] 路径解析: 'data/enemy_properties/天网.xml' -> 'file:///C|/Program Files (x86)/Steam/steamapps/common/CRAZYFLASHER7StandAloneStarter/CrazyFlashNight/data/enemy_properties/天网.xml'
[PathManager] [DEBUG] 路径解析: 'data/enemy_properties/boss重做.xml' -> 'file:///C|/Program Files (x86)/Steam/steamapps/common/CRAZYFLASHER7StandAloneStarter/CrazyFlashNight/data/enemy_properties/boss重做.xml'
[PathManager] [DEBUG] 路径解析: 'data/items/收集品_材料.xml' -> 'file:///C|/Program Files (x86)/Steam/steamapps/common/CRAZYFLASHER7StandAloneStarter/CrazyFlashNight/data/items/收集品_材料.xml'
[PathManager] [DEBUG] 路径解析: 'data/enemy_properties/原版敌人 2013-2016.xml' -> 'file:///C|/Program Files (x86)/Steam/steamapps/common/CRAZYFLASHER7StandAloneStarter/CrazyFlashNight/data/enemy_properties/原版敌人 2013-2016.xml'
[PathManager] [DEBUG] 路径解析: 'data/enemy_properties/下水道.xml' -> 'file:///C|/Program Files (x86)/Steam/steamapps/common/CRAZYFLASHER7StandAloneStarter/CrazyFlashNight/data/enemy_properties/下水道.xml'
[PathManager] [DEBUG] 路径解析: 'data/enemy_properties/军阀新人物.xml' -> 'file:///C|/Program Files (x86)/Steam/steamapps/common/CRAZYFLASHER7StandAloneStarter/CrazyFlashNight/data/enemy_properties/军阀新人物.xml'
[PathManager] [DEBUG] 路径解析: 'data/enemy_properties/大学.xml' -> 'file:///C|/Program Files (x86)/Steam/steamapps/common/CRAZYFLASHER7StandAloneStarter/CrazyFlashNight/data/enemy_properties/大学.xml'
[PathManager] [DEBUG] 路径解析: 'data/items/收集品_情报.xml' -> 'file:///C|/Program Files (x86)/Steam/steamapps/common/CRAZYFLASHER7StandAloneStarter/CrazyFlashNight/data/items/收集品_情报.xml'
[PathManager] [DEBUG] 路径解析: 'data/items/防具_颈部装备.xml' -> 'file:///C|/Program Files (x86)/Steam/steamapps/common/CRAZYFLASHER7StandAloneStarter/CrazyFlashNight/data/items/防具_颈部装备.xml'
[PathManager] [DEBUG] 路径解析: 'data/items/防具_0-19级.xml' -> 'file:///C|/Program Files (x86)/Steam/steamapps/common/CRAZYFLASHER7StandAloneStarter/CrazyFlashNight/data/items/防具_0-19级.xml'
[PathManager] [DEBUG] 路径解析: 'data/items/防具_20-39级.xml' -> 'file:///C|/Program Files (x86)/Steam/steamapps/common/CRAZYFLASHER7StandAloneStarter/CrazyFlashNight/data/items/防具_20-39级.xml'
[PathManager] [DEBUG] 路径解析: 'data/items/equipment_mods/中等材料_刀专用.xml' -> 'file:///C|/Program Files (x86)/Steam/steamapps/common/CRAZYFLASHER7StandAloneStarter/CrazyFlashNight/data/items/equipment_mods/中等材料_刀专用.xml'
[PathManager] [DEBUG] 路径解析: 'data/items/equipment_mods/中等材料_拳专用.xml' -> 'file:///C|/Program Files (x86)/Steam/steamapps/common/CRAZYFLASHER7StandAloneStarter/CrazyFlashNight/data/items/equipment_mods/中等材料_拳专用.xml'
[PathManager] [DEBUG] 路径解析: 'data/items/equipment_mods/中等材料_通用.xml' -> 'file:///C|/Program Files (x86)/Steam/steamapps/common/CRAZYFLASHER7StandAloneStarter/CrazyFlashNight/data/items/equipment_mods/中等材料_通用.xml'
[PathManager] [DEBUG] 路径解析: 'data/items/equipment_mods/中等材料_下挂武器.xml' -> 'file:///C|/Program Files (x86)/Steam/steamapps/common/CRAZYFLASHER7StandAloneStarter/CrazyFlashNight/data/items/equipment_mods/中等材料_下挂武器.xml'
[PathManager] [DEBUG] 路径解析: 'data/stages/沙漠虫洞/__list__.xml' -> 'file:///C|/Program Files (x86)/Steam/steamapps/common/CRAZYFLASHER7StandAloneStarter/CrazyFlashNight/data/stages/沙漠虫洞/__list__.xml'
[PathManager] [DEBUG] 路径解析: 'data/stages/试炼场深处/__list__.xml' -> 'file:///C|/Program Files (x86)/Steam/steamapps/common/CRAZYFLASHER7StandAloneStarter/CrazyFlashNight/data/stages/试炼场深处/__list__.xml'
[PathManager] [DEBUG] 路径解析: 'data/stages/诺亚前线基地深处第二层/__list__.xml' -> 'file:///C|/Program Files (x86)/Steam/steamapps/common/CRAZYFLASHER7StandAloneStarter/CrazyFlashNight/data/stages/诺亚前线基地深处第二层/__list__.xml'
[PathManager] [DEBUG] 路径解析: 'data/stages/亡灵沙漠/__list__.xml' -> 'file:///C|/Program Files (x86)/Steam/steamapps/common/CRAZYFLASHER7StandAloneStarter/CrazyFlashNight/data/stages/亡灵沙漠/__list__.xml'
[PathManager] [DEBUG] 路径解析: 'data/dialogues/npc_dialogue_A兵团元老.xml' -> 'file:///C|/Program Files (x86)/Steam/steamapps/common/CRAZYFLASHER7StandAloneStarter/CrazyFlashNight/data/dialogues/npc_dialogue_A兵团元老.xml'
[PathManager] [DEBUG] 路径解析: 'data/dialogues/npc_dialogue_禁区人员.xml' -> 'file:///C|/Program Files (x86)/Steam/steamapps/common/CRAZYFLASHER7StandAloneStarter/CrazyFlashNight/data/dialogues/npc_dialogue_禁区人员.xml'
[PathManager] [DEBUG] 路径解析: 'data/dialogues/npc_dialogue_闲杂人等.xml' -> 'file:///C|/Program Files (x86)/Steam/steamapps/common/CRAZYFLASHER7StandAloneStarter/CrazyFlashNight/data/dialogues/npc_dialogue_闲杂人等.xml'
[PathManager] [DEBUG] 路径解析: 'data/dialogues/npc_dialogue_探索者.xml' -> 'file:///C|/Program Files (x86)/Steam/steamapps/common/CRAZYFLASHER7StandAloneStarter/CrazyFlashNight/data/dialogues/npc_dialogue_探索者.xml'
[PathManager] [DEBUG] 路径解析: 'data/task/text/school_texts.json' -> 'file:///C|/Program Files (x86)/Steam/steamapps/common/CRAZYFLASHER7StandAloneStarter/CrazyFlashNight/data/task/text/school_texts.json'
[PathManager] [DEBUG] 路径解析: 'data/task/text/logistics_text.json' -> 'file:///C|/Program Files (x86)/Steam/steamapps/common/CRAZYFLASHER7StandAloneStarter/CrazyFlashNight/data/task/text/logistics_text.json'
[PathManager] [DEBUG] 路径解析: 'data/task/text/eastzone_text.json' -> 'file:///C|/Program Files (x86)/Steam/steamapps/common/CRAZYFLASHER7StandAloneStarter/CrazyFlashNight/data/task/text/eastzone_text.json'
[PathManager] [DEBUG] 路径解析: 'data/task/school_tasks.json' -> 'file:///C|/Program Files (x86)/Steam/steamapps/common/CRAZYFLASHER7StandAloneStarter/CrazyFlashNight/data/task/school_tasks.json'
[PathManager] [DEBUG] 路径解析: 'data/task/logistics_tasks.json' -> 'file:///C|/Program Files (x86)/Steam/steamapps/common/CRAZYFLASHER7StandAloneStarter/CrazyFlashNight/data/task/logistics_tasks.json'
[PathManager] [DEBUG] 路径解析: 'data/task/eastzone_tasks.json' -> 'file:///C|/Program Files (x86)/Steam/steamapps/common/CRAZYFLASHER7StandAloneStarter/CrazyFlashNight/data/task/eastzone_tasks.json'
[PathManager] [DEBUG] 路径解析: 'data/crafting/公社防具.json' -> 'file:///C|/Program Files (x86)/Steam/steamapps/common/CRAZYFLASHER7StandAloneStarter/CrazyFlashNight/data/crafting/公社防具.json'
[PathManager] [DEBUG] 路径解析: 'data/crafting/黑白契约.json' -> 'file:///C|/Program Files (x86)/Steam/steamapps/common/CRAZYFLASHER7StandAloneStarter/CrazyFlashNight/data/crafting/黑白契约.json'
[PathManager] [DEBUG] 路径解析: 'data/crafting/插件合成.json' -> 'file:///C|/Program Files (x86)/Steam/steamapps/common/CRAZYFLASHER7StandAloneStarter/CrazyFlashNight/data/crafting/插件合成.json'
[PathManager] [DEBUG] 路径解析: 'data/crafting/大学装备.json' -> 'file:///C|/Program Files (x86)/Steam/steamapps/common/CRAZYFLASHER7StandAloneStarter/CrazyFlashNight/data/crafting/大学装备.json'
[PathManager] [DEBUG] 路径解析: 'data/enemy_properties/下水道.xml' -> 'file:///C|/Program Files (x86)/Steam/steamapps/common/CRAZYFLASHER7StandAloneStarter/CrazyFlashNight/data/enemy_properties/下水道.xml'
[PathManager] [DEBUG] 路径解析: 'data/enemy_properties/军阀新人物.xml' -> 'file:///C|/Program Files (x86)/Steam/steamapps/common/CRAZYFLASHER7StandAloneStarter/CrazyFlashNight/data/enemy_properties/军阀新人物.xml'
[PathManager] [DEBUG] 路径解析: 'data/enemy_properties/大学.xml' -> 'file:///C|/Program Files (x86)/Steam/steamapps/common/CRAZYFLASHER7StandAloneStarter/CrazyFlashNight/data/enemy_properties/大学.xml'
[PathManager] [DEBUG] 路径解析: 'data/enemy_properties/换皮敌人与战宠.xml' -> 'file:///C|/Program Files (x86)/Steam/steamapps/common/CRAZYFLASHER7StandAloneStarter/CrazyFlashNight/data/enemy_properties/换皮敌人与战宠.xml'
[PASS] listloader-concatField
[PathManager] [DEBUG] 路径解析: 'data/items/防具_40+级.xml' -> 'file:///C|/Program Files (x86)/Steam/steamapps/common/CRAZYFLASHER7StandAloneStarter/CrazyFlashNight/data/items/防具_40+级.xml'
[PathManager] [DEBUG] 路径解析: 'data/items/武器_刀_默认.xml' -> 'file:///C|/Program Files (x86)/Steam/steamapps/common/CRAZYFLASHER7StandAloneStarter/CrazyFlashNight/data/items/武器_刀_默认.xml'
[PathManager] [DEBUG] 路径解析: 'data/items/武器_刀_直剑.xml' -> 'file:///C|/Program Files (x86)/Steam/steamapps/common/CRAZYFLASHER7StandAloneStarter/CrazyFlashNight/data/items/武器_刀_直剑.xml'
[PathManager] [DEBUG] 路径解析: 'data/items/武器_刀_长刀.xml' -> 'file:///C|/Program Files (x86)/Steam/steamapps/common/CRAZYFLASHER7StandAloneStarter/CrazyFlashNight/data/items/武器_刀_长刀.xml'
[PathManager] [DEBUG] 路径解析: 'data/items/equipment_mods/高等材料_防具专用.xml' -> 'file:///C|/Program Files (x86)/Steam/steamapps/common/CRAZYFLASHER7StandAloneStarter/CrazyFlashNight/data/items/equipment_mods/高等材料_防具专用.xml'
[PathManager] [DEBUG] 路径解析: 'data/items/equipment_mods/高等材料_枪械专用.xml' -> 'file:///C|/Program Files (x86)/Steam/steamapps/common/CRAZYFLASHER7StandAloneStarter/CrazyFlashNight/data/items/equipment_mods/高等材料_枪械专用.xml'
[PathManager] [DEBUG] 路径解析: 'data/items/equipment_mods/高等材料_刀专用.xml' -> 'file:///C|/Program Files (x86)/Steam/steamapps/common/CRAZYFLASHER7StandAloneStarter/CrazyFlashNight/data/items/equipment_mods/高等材料_刀专用.xml'
[PathManager] [DEBUG] 路径解析: 'data/items/equipment_mods/高等材料_拳专用.xml' -> 'file:///C|/Program Files (x86)/Steam/steamapps/common/CRAZYFLASHER7StandAloneStarter/CrazyFlashNight/data/items/equipment_mods/高等材料_拳专用.xml'
[PathManager] [DEBUG] 路径解析: 'data/stages/雪山/__list__.xml' -> 'file:///C|/Program Files (x86)/Steam/steamapps/common/CRAZYFLASHER7StandAloneStarter/CrazyFlashNight/data/stages/雪山/__list__.xml'
[PathManager] [DEBUG] 路径解析: 'data/stages/雪山第二层/__list__.xml' -> 'file:///C|/Program Files (x86)/Steam/steamapps/common/CRAZYFLASHER7StandAloneStarter/CrazyFlashNight/data/stages/雪山第二层/__list__.xml'
[PathManager] [DEBUG] 路径解析: 'data/stages/雪山/__list__.xml' -> 'file:///C|/Program Files (x86)/Steam/steamapps/common/CRAZYFLASHER7StandAloneStarter/CrazyFlashNight/data/stages/雪山/__list__.xml'
[PathManager] [DEBUG] 路径解析: 'data/stages/雪山内部/__list__.xml' -> 'file:///C|/Program Files (x86)/Steam/steamapps/common/CRAZYFLASHER7StandAloneStarter/CrazyFlashNight/data/stages/雪山内部/__list__.xml'
[PathManager] [DEBUG] 路径解析: 'data/dialogues/npc_dialogue_通缉犯.xml' -> 'file:///C|/Program Files (x86)/Steam/steamapps/common/CRAZYFLASHER7StandAloneStarter/CrazyFlashNight/data/dialogues/npc_dialogue_通缉犯.xml'
[PathManager] [DEBUG] 路径解析: 'data/enemy_properties/彩蛋支线.xml' -> 'file:///C|/Program Files (x86)/Steam/steamapps/common/CRAZYFLASHER7StandAloneStarter/CrazyFlashNight/data/enemy_properties/彩蛋支线.xml'
[PASS] repeat-load-cache
[PASS] tasktext-data-consistency
[PASS] taskdata-data-consistency
[PASS] crafting-data-consistency
[PASS] listloader-dictMerge
[PASS] enemy-data-consistency
[PathManager] [DEBUG] 路径解析: 'data/items/武器_刀_刀剑.xml' -> 'file:///C|/Program Files (x86)/Steam/steamapps/common/CRAZYFLASHER7StandAloneStarter/CrazyFlashNight/data/items/武器_刀_刀剑.xml'
[PathManager] [DEBUG] 路径解析: 'data/items/武器_刀_重斩.xml' -> 'file:///C|/Program Files (x86)/Steam/steamapps/common/CRAZYFLASHER7StandAloneStarter/CrazyFlashNight/data/items/武器_刀_重斩.xml'
[PathManager] [DEBUG] 路径解析: 'data/items/武器_刀_狂野.xml' -> 'file:///C|/Program Files (x86)/Steam/steamapps/common/CRAZYFLASHER7StandAloneStarter/CrazyFlashNight/data/items/武器_刀_狂野.xml'
[PathManager] [DEBUG] 路径解析: 'data/items/武器_刀_短兵.xml' -> 'file:///C|/Program Files (x86)/Steam/steamapps/common/CRAZYFLASHER7StandAloneStarter/CrazyFlashNight/data/items/武器_刀_短兵.xml'
[PathManager] [DEBUG] 路径解析: 'data/items/equipment_mods/高等材料_通用.xml' -> 'file:///C|/Program Files (x86)/Steam/steamapps/common/CRAZYFLASHER7StandAloneStarter/CrazyFlashNight/data/items/equipment_mods/高等材料_通用.xml'
[PathManager] [DEBUG] 路径解析: 'data/items/equipment_mods/高等材料_下挂武器.xml' -> 'file:///C|/Program Files (x86)/Steam/steamapps/common/CRAZYFLASHER7StandAloneStarter/CrazyFlashNight/data/items/equipment_mods/高等材料_下挂武器.xml'
[PathManager] [DEBUG] 路径解析: 'data/items/equipment_mods/特殊材料_防具专用.xml' -> 'file:///C|/Program Files (x86)/Steam/steamapps/common/CRAZYFLASHER7StandAloneStarter/CrazyFlashNight/data/items/equipment_mods/特殊材料_防具专用.xml'
[PathManager] [DEBUG] 路径解析: 'data/items/equipment_mods/特殊材料_通用.xml' -> 'file:///C|/Program Files (x86)/Steam/steamapps/common/CRAZYFLASHER7StandAloneStarter/CrazyFlashNight/data/items/equipment_mods/特殊材料_通用.xml'
[PathManager] [DEBUG] 路径解析: 'data/stages/雪山内部第二层/__list__.xml' -> 'file:///C|/Program Files (x86)/Steam/steamapps/common/CRAZYFLASHER7StandAloneStarter/CrazyFlashNight/data/stages/雪山内部第二层/__list__.xml'
[PathManager] [DEBUG] 路径解析: 'data/stages/异界战场/__list__.xml' -> 'file:///C|/Program Files (x86)/Steam/steamapps/common/CRAZYFLASHER7StandAloneStarter/CrazyFlashNight/data/stages/异界战场/__list__.xml'
[PathManager] [DEBUG] 路径解析: 'data/stages/坠毁战舰/__list__.xml' -> 'file:///C|/Program Files (x86)/Steam/steamapps/common/CRAZYFLASHER7StandAloneStarter/CrazyFlashNight/data/stages/坠毁战舰/__list__.xml'
[PathManager] [DEBUG] 路径解析: 'data/enemy_properties/诺亚新敌人.xml' -> 'file:///C|/Program Files (x86)/Steam/steamapps/common/CRAZYFLASHER7StandAloneStarter/CrazyFlashNight/data/enemy_properties/诺亚新敌人.xml'
[PASS] npc-data-consistency
[PathManager] [DEBUG] 路径解析: 'data/items/武器_刀_短柄.xml' -> 'file:///C|/Program Files (x86)/Steam/steamapps/common/CRAZYFLASHER7StandAloneStarter/CrazyFlashNight/data/items/武器_刀_短柄.xml'
[PathManager] [DEBUG] 路径解析: 'data/items/武器_刀_镰刀.xml' -> 'file:///C|/Program Files (x86)/Steam/steamapps/common/CRAZYFLASHER7StandAloneStarter/CrazyFlashNight/data/items/武器_刀_镰刀.xml'
[PathManager] [DEBUG] 路径解析: 'data/items/武器_刀_长枪.xml' -> 'file:///C|/Program Files (x86)/Steam/steamapps/common/CRAZYFLASHER7StandAloneStarter/CrazyFlashNight/data/items/武器_刀_长枪.xml'
[PathManager] [DEBUG] 路径解析: 'data/items/武器_刀_长柄.xml' -> 'file:///C|/Program Files (x86)/Steam/steamapps/common/CRAZYFLASHER7StandAloneStarter/CrazyFlashNight/data/items/武器_刀_长柄.xml'
[PathManager] [DEBUG] 路径解析: 'data/items/equipment_mods/特殊材料_下挂武器.xml' -> 'file:///C|/Program Files (x86)/Steam/steamapps/common/CRAZYFLASHER7StandAloneStarter/CrazyFlashNight/data/items/equipment_mods/特殊材料_下挂武器.xml'
[PathManager] [DEBUG] 路径解析: 'data/items/equipment_mods/特殊材料_刀专用.xml' -> 'file:///C|/Program Files (x86)/Steam/steamapps/common/CRAZYFLASHER7StandAloneStarter/CrazyFlashNight/data/items/equipment_mods/特殊材料_刀专用.xml'
[PathManager] [DEBUG] 路径解析: 'data/enemy_properties/魔神.xml' -> 'file:///C|/Program Files (x86)/Steam/steamapps/common/CRAZYFLASHER7StandAloneStarter/CrazyFlashNight/data/enemy_properties/魔神.xml'
[PASS] stage-data-consistency
[PathManager] [DEBUG] 路径解析: 'data/items/武器_刀_长棍.xml' -> 'file:///C|/Program Files (x86)/Steam/steamapps/common/CRAZYFLASHER7StandAloneStarter/CrazyFlashNight/data/items/武器_刀_长棍.xml'
[PathManager] [DEBUG] 路径解析: 'data/items/武器_刀_双刀.xml' -> 'file:///C|/Program Files (x86)/Steam/steamapps/common/CRAZYFLASHER7StandAloneStarter/CrazyFlashNight/data/items/武器_刀_双刀.xml'
[PathManager] [DEBUG] 路径解析: 'data/items/武器_刀_迅捷.xml' -> 'file:///C|/Program Files (x86)/Steam/steamapps/common/CRAZYFLASHER7StandAloneStarter/CrazyFlashNight/data/items/武器_刀_迅捷.xml'
[PathManager] [DEBUG] 路径解析: 'data/items/武器_刀_棍棒.xml' -> 'file:///C|/Program Files (x86)/Steam/steamapps/common/CRAZYFLASHER7StandAloneStarter/CrazyFlashNight/data/items/武器_刀_棍棒.xml'
[PathManager] [DEBUG] 路径解析: 'data/enemy_properties/天网.xml' -> 'file:///C|/Program Files (x86)/Steam/steamapps/common/CRAZYFLASHER7StandAloneStarter/CrazyFlashNight/data/enemy_properties/天网.xml'
EquipModListLoader: 合并后的配件数量 = 98
[PASS] mod-data-consistency
[PathManager] [DEBUG] 路径解析: 'data/items/武器_手枪_冲锋枪.xml' -> 'file:///C|/Program Files (x86)/Steam/steamapps/common/CRAZYFLASHER7StandAloneStarter/CrazyFlashNight/data/items/武器_手枪_冲锋枪.xml'
[PathManager] [DEBUG] 路径解析: 'data/items/武器_手枪_压制冲锋枪.xml' -> 'file:///C|/Program Files (x86)/Steam/steamapps/common/CRAZYFLASHER7StandAloneStarter/CrazyFlashNight/data/items/武器_手枪_压制冲锋枪.xml'
[PathManager] [DEBUG] 路径解析: 'data/items/武器_手枪_压制机枪.xml' -> 'file:///C|/Program Files (x86)/Steam/steamapps/common/CRAZYFLASHER7StandAloneStarter/CrazyFlashNight/data/items/武器_手枪_压制机枪.xml'
[PathManager] [DEBUG] 路径解析: 'data/items/武器_手枪_反器材武器.xml' -> 'file:///C|/Program Files (x86)/Steam/steamapps/common/CRAZYFLASHER7StandAloneStarter/CrazyFlashNight/data/items/武器_手枪_反器材武器.xml'
[PathManager] [DEBUG] 路径解析: 'data/enemy_properties/boss重做.xml' -> 'file:///C|/Program Files (x86)/Steam/steamapps/common/CRAZYFLASHER7StandAloneStarter/CrazyFlashNight/data/enemy_properties/boss重做.xml'
[PathManager] [DEBUG] 路径解析: 'data/items/武器_手枪_发射器.xml' -> 'file:///C|/Program Files (x86)/Steam/steamapps/common/CRAZYFLASHER7StandAloneStarter/CrazyFlashNight/data/items/武器_手枪_发射器.xml'
[PathManager] [DEBUG] 路径解析: 'data/items/武器_手枪_大威力手枪.xml' -> 'file:///C|/Program Files (x86)/Steam/steamapps/common/CRAZYFLASHER7StandAloneStarter/CrazyFlashNight/data/items/武器_手枪_大威力手枪.xml'
[PathManager] [DEBUG] 路径解析: 'data/items/武器_手枪_手枪.xml' -> 'file:///C|/Program Files (x86)/Steam/steamapps/common/CRAZYFLASHER7StandAloneStarter/CrazyFlashNight/data/items/武器_手枪_手枪.xml'
[PathManager] [DEBUG] 路径解析: 'data/items/武器_手枪_特殊.xml' -> 'file:///C|/Program Files (x86)/Steam/steamapps/common/CRAZYFLASHER7StandAloneStarter/CrazyFlashNight/data/items/武器_手枪_特殊.xml'
[PathManager] [DEBUG] 路径解析: 'data/enemy_properties/下水道.xml' -> 'file:///C|/Program Files (x86)/Steam/steamapps/common/CRAZYFLASHER7StandAloneStarter/CrazyFlashNight/data/enemy_properties/下水道.xml'
[PathManager] [DEBUG] 路径解析: 'data/items/武器_手枪_突击步枪.xml' -> 'file:///C|/Program Files (x86)/Steam/steamapps/common/CRAZYFLASHER7StandAloneStarter/CrazyFlashNight/data/items/武器_手枪_突击步枪.xml'
[PathManager] [DEBUG] 路径解析: 'data/items/武器_手枪_霰弹枪.xml' -> 'file:///C|/Program Files (x86)/Steam/steamapps/common/CRAZYFLASHER7StandAloneStarter/CrazyFlashNight/data/items/武器_手枪_霰弹枪.xml'
[PathManager] [DEBUG] 路径解析: 'data/items/武器_长枪_冲锋枪.xml' -> 'file:///C|/Program Files (x86)/Steam/steamapps/common/CRAZYFLASHER7StandAloneStarter/CrazyFlashNight/data/items/武器_长枪_冲锋枪.xml'
[PathManager] [DEBUG] 路径解析: 'data/items/武器_长枪_压制机枪.xml' -> 'file:///C|/Program Files (x86)/Steam/steamapps/common/CRAZYFLASHER7StandAloneStarter/CrazyFlashNight/data/items/武器_长枪_压制机枪.xml'
[PathManager] [DEBUG] 路径解析: 'data/enemy_properties/军阀新人物.xml' -> 'file:///C|/Program Files (x86)/Steam/steamapps/common/CRAZYFLASHER7StandAloneStarter/CrazyFlashNight/data/enemy_properties/军阀新人物.xml'
[PathManager] [DEBUG] 路径解析: 'data/items/武器_长枪_压制近战.xml' -> 'file:///C|/Program Files (x86)/Steam/steamapps/common/CRAZYFLASHER7StandAloneStarter/CrazyFlashNight/data/items/武器_长枪_压制近战.xml'
[PathManager] [DEBUG] 路径解析: 'data/items/武器_长枪_反器材武器.xml' -> 'file:///C|/Program Files (x86)/Steam/steamapps/common/CRAZYFLASHER7StandAloneStarter/CrazyFlashNight/data/items/武器_长枪_反器材武器.xml'
[PathManager] [DEBUG] 路径解析: 'data/items/武器_长枪_发射器.xml' -> 'file:///C|/Program Files (x86)/Steam/steamapps/common/CRAZYFLASHER7StandAloneStarter/CrazyFlashNight/data/items/武器_长枪_发射器.xml'
[PathManager] [DEBUG] 路径解析: 'data/items/武器_长枪_战斗步枪.xml' -> 'file:///C|/Program Files (x86)/Steam/steamapps/common/CRAZYFLASHER7StandAloneStarter/CrazyFlashNight/data/items/武器_长枪_战斗步枪.xml'
[PathManager] [DEBUG] 路径解析: 'data/enemy_properties/大学.xml' -> 'file:///C|/Program Files (x86)/Steam/steamapps/common/CRAZYFLASHER7StandAloneStarter/CrazyFlashNight/data/enemy_properties/大学.xml'
[PathManager] [DEBUG] 路径解析: 'data/items/武器_长枪_机枪.xml' -> 'file:///C|/Program Files (x86)/Steam/steamapps/common/CRAZYFLASHER7StandAloneStarter/CrazyFlashNight/data/items/武器_长枪_机枪.xml'
[PathManager] [DEBUG] 路径解析: 'data/items/武器_长枪_特殊.xml' -> 'file:///C|/Program Files (x86)/Steam/steamapps/common/CRAZYFLASHER7StandAloneStarter/CrazyFlashNight/data/items/武器_长枪_特殊.xml'
[PathManager] [DEBUG] 路径解析: 'data/items/武器_长枪_狙击步枪.xml' -> 'file:///C|/Program Files (x86)/Steam/steamapps/common/CRAZYFLASHER7StandAloneStarter/CrazyFlashNight/data/items/武器_长枪_狙击步枪.xml'
[PathManager] [DEBUG] 路径解析: 'data/items/武器_长枪_突击步枪.xml' -> 'file:///C|/Program Files (x86)/Steam/steamapps/common/CRAZYFLASHER7StandAloneStarter/CrazyFlashNight/data/items/武器_长枪_突击步枪.xml'
[PASS] listloader-concurrency1
[PathManager] [DEBUG] 路径解析: 'data/enemy_properties/原版敌人 2011-2012.xml' -> 'file:///C|/Program Files (x86)/Steam/steamapps/common/CRAZYFLASHER7StandAloneStarter/CrazyFlashNight/data/enemy_properties/原版敌人 2011-2012.xml'
[PathManager] [DEBUG] 路径解析: 'data/enemy_properties/原版敌人 2013-2016.xml' -> 'file:///C|/Program Files (x86)/Steam/steamapps/common/CRAZYFLASHER7StandAloneStarter/CrazyFlashNight/data/enemy_properties/原版敌人 2013-2016.xml'
[PathManager] [DEBUG] 路径解析: 'data/enemy_properties/换皮敌人与战宠.xml' -> 'file:///C|/Program Files (x86)/Steam/steamapps/common/CRAZYFLASHER7StandAloneStarter/CrazyFlashNight/data/enemy_properties/换皮敌人与战宠.xml'
[PathManager] [DEBUG] 路径解析: 'data/enemy_properties/彩蛋支线.xml' -> 'file:///C|/Program Files (x86)/Steam/steamapps/common/CRAZYFLASHER7StandAloneStarter/CrazyFlashNight/data/enemy_properties/彩蛋支线.xml'
[PathManager] [DEBUG] 路径解析: 'data/items/武器_长枪_近战.xml' -> 'file:///C|/Program Files (x86)/Steam/steamapps/common/CRAZYFLASHER7StandAloneStarter/CrazyFlashNight/data/items/武器_长枪_近战.xml'
[PathManager] [DEBUG] 路径解析: 'data/items/武器_长枪_霰弹枪.xml' -> 'file:///C|/Program Files (x86)/Steam/steamapps/common/CRAZYFLASHER7StandAloneStarter/CrazyFlashNight/data/items/武器_长枪_霰弹枪.xml'
[PathManager] [DEBUG] 路径解析: 'data/enemy_properties/诺亚新敌人.xml' -> 'file:///C|/Program Files (x86)/Steam/steamapps/common/CRAZYFLASHER7StandAloneStarter/CrazyFlashNight/data/enemy_properties/诺亚新敌人.xml'
[PathManager] [DEBUG] 路径解析: 'data/enemy_properties/魔神.xml' -> 'file:///C|/Program Files (x86)/Steam/steamapps/common/CRAZYFLASHER7StandAloneStarter/CrazyFlashNight/data/enemy_properties/魔神.xml'
[PathManager] [DEBUG] 路径解析: 'data/enemy_properties/天网.xml' -> 'file:///C|/Program Files (x86)/Steam/steamapps/common/CRAZYFLASHER7StandAloneStarter/CrazyFlashNight/data/enemy_properties/天网.xml'
[PathManager] [DEBUG] 路径解析: 'data/enemy_properties/boss重做.xml' -> 'file:///C|/Program Files (x86)/Steam/steamapps/common/CRAZYFLASHER7StandAloneStarter/CrazyFlashNight/data/enemy_properties/boss重做.xml'
[PASS] item-data-consistency
[PathManager] [DEBUG] 路径解析: 'data/items/list.xml' -> 'file:///C|/Program Files (x86)/Steam/steamapps/common/CRAZYFLASHER7StandAloneStarter/CrazyFlashNight/data/items/list.xml'
[PathManager] [DEBUG] 路径解析: 'data/items/消耗品_货币.xml' -> 'file:///C|/Program Files (x86)/Steam/steamapps/common/CRAZYFLASHER7StandAloneStarter/CrazyFlashNight/data/items/消耗品_货币.xml'
[PathManager] [DEBUG] 路径解析: 'data/enemy_properties/下水道.xml' -> 'file:///C|/Program Files (x86)/Steam/steamapps/common/CRAZYFLASHER7StandAloneStarter/CrazyFlashNight/data/enemy_properties/下水道.xml'
[PathManager] [DEBUG] 路径解析: 'data/enemy_properties/军阀新人物.xml' -> 'file:///C|/Program Files (x86)/Steam/steamapps/common/CRAZYFLASHER7StandAloneStarter/CrazyFlashNight/data/enemy_properties/军阀新人物.xml'
[PathManager] [DEBUG] 路径解析: 'data/enemy_properties/大学.xml' -> 'file:///C|/Program Files (x86)/Steam/steamapps/common/CRAZYFLASHER7StandAloneStarter/CrazyFlashNight/data/enemy_properties/大学.xml'
[PathManager] [DEBUG] 路径解析: 'data/items/消耗品_弹夹.xml' -> 'file:///C|/Program Files (x86)/Steam/steamapps/common/CRAZYFLASHER7StandAloneStarter/CrazyFlashNight/data/items/消耗品_弹夹.xml'
[PASS] reload-refresh
[PathManager] [DEBUG] 路径解析: 'data/items/消耗品_药剂.xml' -> 'file:///C|/Program Files (x86)/Steam/steamapps/common/CRAZYFLASHER7StandAloneStarter/CrazyFlashNight/data/items/消耗品_药剂.xml'
[PathManager] [DEBUG] 路径解析: 'data/items/消耗品_药剂_食品.xml' -> 'file:///C|/Program Files (x86)/Steam/steamapps/common/CRAZYFLASHER7StandAloneStarter/CrazyFlashNight/data/items/消耗品_药剂_食品.xml'
[PathManager] [DEBUG] 路径解析: 'data/items/收集品_材料.xml' -> 'file:///C|/Program Files (x86)/Steam/steamapps/common/CRAZYFLASHER7StandAloneStarter/CrazyFlashNight/data/items/收集品_材料.xml'
[PathManager] [DEBUG] 路径解析: 'data/items/收集品_材料_插件.xml' -> 'file:///C|/Program Files (x86)/Steam/steamapps/common/CRAZYFLASHER7StandAloneStarter/CrazyFlashNight/data/items/收集品_材料_插件.xml'
[PathManager] [DEBUG] 路径解析: 'data/items/消耗品_手雷.xml' -> 'file:///C|/Program Files (x86)/Steam/steamapps/common/CRAZYFLASHER7StandAloneStarter/CrazyFlashNight/data/items/消耗品_手雷.xml'
[PathManager] [DEBUG] 路径解析: 'data/items/消耗品_材料_食材.xml' -> 'file:///C|/Program Files (x86)/Steam/steamapps/common/CRAZYFLASHER7StandAloneStarter/CrazyFlashNight/data/items/消耗品_材料_食材.xml'
[PathManager] [DEBUG] 路径解析: 'data/items/收集品_情报.xml' -> 'file:///C|/Program Files (x86)/Steam/steamapps/common/CRAZYFLASHER7StandAloneStarter/CrazyFlashNight/data/items/收集品_情报.xml'
[PathManager] [DEBUG] 路径解析: 'data/items/防具_颈部装备.xml' -> 'file:///C|/Program Files (x86)/Steam/steamapps/common/CRAZYFLASHER7StandAloneStarter/CrazyFlashNight/data/items/防具_颈部装备.xml'
[PERF] 10 XML serial  (concurrency=1): 2035ms
[PASS] perf-serial-baseline
[PathManager] [DEBUG] 路径解析: 'data/items/消耗品_货币.xml' -> 'file:///C|/Program Files (x86)/Steam/steamapps/common/CRAZYFLASHER7StandAloneStarter/CrazyFlashNight/data/items/消耗品_货币.xml'
[PathManager] [DEBUG] 路径解析: 'data/items/消耗品_弹夹.xml' -> 'file:///C|/Program Files (x86)/Steam/steamapps/common/CRAZYFLASHER7StandAloneStarter/CrazyFlashNight/data/items/消耗品_弹夹.xml'
[PathManager] [DEBUG] 路径解析: 'data/items/消耗品_药剂.xml' -> 'file:///C|/Program Files (x86)/Steam/steamapps/common/CRAZYFLASHER7StandAloneStarter/CrazyFlashNight/data/items/消耗品_药剂.xml'
[PathManager] [DEBUG] 路径解析: 'data/items/消耗品_药剂_食品.xml' -> 'file:///C|/Program Files (x86)/Steam/steamapps/common/CRAZYFLASHER7StandAloneStarter/CrazyFlashNight/data/items/消耗品_药剂_食品.xml'
[PathManager] [DEBUG] 路径解析: 'data/items/收集品_材料.xml' -> 'file:///C|/Program Files (x86)/Steam/steamapps/common/CRAZYFLASHER7StandAloneStarter/CrazyFlashNight/data/items/收集品_材料.xml'
[PathManager] [DEBUG] 路径解析: 'data/items/收集品_材料_插件.xml' -> 'file:///C|/Program Files (x86)/Steam/steamapps/common/CRAZYFLASHER7StandAloneStarter/CrazyFlashNight/data/items/收集品_材料_插件.xml'
[PathManager] [DEBUG] 路径解析: 'data/items/消耗品_手雷.xml' -> 'file:///C|/Program Files (x86)/Steam/steamapps/common/CRAZYFLASHER7StandAloneStarter/CrazyFlashNight/data/items/消耗品_手雷.xml'
[PathManager] [DEBUG] 路径解析: 'data/items/消耗品_材料_食材.xml' -> 'file:///C|/Program Files (x86)/Steam/steamapps/common/CRAZYFLASHER7StandAloneStarter/CrazyFlashNight/data/items/消耗品_材料_食材.xml'
[PathManager] [DEBUG] 路径解析: 'data/items/收集品_情报.xml' -> 'file:///C|/Program Files (x86)/Steam/steamapps/common/CRAZYFLASHER7StandAloneStarter/CrazyFlashNight/data/items/收集品_情报.xml'
[PathManager] [DEBUG] 路径解析: 'data/items/防具_颈部装备.xml' -> 'file:///C|/Program Files (x86)/Steam/steamapps/common/CRAZYFLASHER7StandAloneStarter/CrazyFlashNight/data/items/防具_颈部装备.xml'
[PERF] 10 XML parallel(concurrency=4): 536ms | speedup: 3.8x
[PASS] perf-parallel-speedup

=== ListLoaderTest Results: 21/21 passed, 0 failed ===
ALL PASSED
