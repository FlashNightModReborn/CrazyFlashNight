// 保存为 org/flashNight/gesh/string/JuntaRandomizer.as
import org.flashNight.neur.Event.EventBus;

class org.flashNight.gesh.string.JuntaRandomizer {
    private static var juntaNames:Array;
    private static var currentPool:Array;
    private static var initialized:Boolean = false;

    // 地图锁定机制：同一张地图中所有军阀部队使用同一个称号
    private static var lockedName:String = null;
    private static var isLocked:Boolean = false;
    
    private static function initialize():Void {
        if (!initialized) {
            // 军阀巨大多部队名称
            juntaNames = [
                "赤龙小组", "镇爆部队", "金色军团", "核武小组", "114合成营", "第一近卫军团", "长生军",
                "烈火小组", "快速机动部队", "独狼之师", "铁锤小组", "尘都治安部队", "整编CSSF部队", "11空降部队",
                "沙地组织", "卫国旅", "荒漠秩序部队", "太平洋协作部队", "东南A洲维和部队", "高原突击部队", "破垒专业小组",
                "长枪旅", "橙色军团", "商队护卫部队", "猛虎军团", "曼陀罗旅", "霸王花小组", "黻城治安部队"
            ];
            resetPool();

            // 订阅场景切换事件，用于解锁名称
            EventBus.getInstance().subscribe("SceneChanged", onSceneChanged, JuntaRandomizer);
    
            initialized = true;
        }
    }
    
    private static function resetPool():Void {
        currentPool = juntaNames.slice();
        // Fisher-Yates洗牌算法
        var i:Number = currentPool.length;
        while (--i) {
            var j:Number = Math.floor(Math.random() * (i + 1));
            var temp = currentPool[i];
            currentPool[i] = currentPool[j];
            currentPool[j] = temp;
        }
    }

    /**
     * 场景切换事件处理：解锁名称，允许下次获取新名称
     */
    private static function onSceneChanged():Void {
        isLocked = false;
        lockedName = null;
    }

    /**
     * 获取随机名称（地图内保持一致）
     * 每张地图中，所有军阀部队使用同一个称号
     * 只有在切换地图后，才会获取新的称号
     */
    public static function getRandomName():String {
        initialize();

        // 如果已锁定，返回锁定的名称
        if (isLocked && lockedName != null) {
            return lockedName;
        }

        // 未锁定：获取新名称并锁定
        if (currentPool.length < 1) {
            resetPool();
        }

        lockedName = String(currentPool.pop());
        isLocked = true;

        return lockedName;
    }
    
    // 防止实例化
    private function JuntaRandomizer() {} 
}