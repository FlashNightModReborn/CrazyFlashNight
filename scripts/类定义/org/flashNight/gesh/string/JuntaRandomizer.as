import org.flashNight.gesh.string.*;
import org.flashNight.naki.RandomNumberEngine.*;
import org.flashNight.neur.Event.*;

class org.flashNight.gesh.string.JuntaRandomizer extends BaseNameRandomizer {
    private static var instance:JuntaRandomizer;
    private static var juntaNames:Array;
    private static var initialized:Boolean = false;

    private var lockedName:String;
    private var isLocked:Boolean;
    private static function ensureNames(target:JuntaRandomizer):Void {
        if (!initialized) {
            juntaNames = [
                "赤龙小组", "镇爆部队", "金色军团", "核武小组", "114合成营", "第一近卫军团", "长生军",
                "烈火小组", "快速机动部队", "独狼之师", "铁锤小组", "尘都治安部队", "整编CSSF部队", "11空降部队",
                "沙地组织", "卫国旅", "荒漠秩序部队", "太平洋协作部队", "东南A洲维和部队", "高原突击部队", "破垒专业小组",
                "长枪旅", "橙色军团", "商队护卫部队", "猛虎军团", "曼陀罗旅", "霸王花小组", "黻城治安部队"
            ];

            EventBus.getInstance().subscribe("SceneChanged", onSceneChanged, JuntaRandomizer);
            initialized = true;
        }

        target.setNames(juntaNames);
    }

    private static function onSceneChanged():Void {
        if (instance != null) {
            instance.resetSceneLock();
        }
    }

    private function resetSceneLock():Void {
        isLocked = false;
        lockedName = null;
    }

    public static function getInstance():JuntaRandomizer {
        if (instance == null) {
            instance = new JuntaRandomizer();
            getInstance = function():JuntaRandomizer {
                return instance;
            };
        }
        return instance;
    }


    public function getRandomName():String {
        if (isLocked && lockedName != null) {
            return lockedName;
        }

        lockedName = super.getRandomName();
        isLocked = true;
        return lockedName;
    }

    private function JuntaRandomizer() {
        lockedName = null;
        isLocked = false;
        setRandomEngine(LinearCongruentialEngine.getInstance());
        setUniqueUntilExhaustion(true);
        ensureNames(this);
    }
}
