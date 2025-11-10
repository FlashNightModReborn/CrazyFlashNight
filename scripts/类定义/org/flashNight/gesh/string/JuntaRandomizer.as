import org.flashNight.gesh.string.*;
import org.flashNight.naki.RandomNumberEngine.*;
import org.flashNight.neur.Event.*;

/**
 * 军阀部队名称随机器
 * 用于从军阀部队名称中随机选择，支持地图锁定机制
 *
 * 特殊机制：
 * - 同一张地图中，所有军阀部队使用同一个称号
 * - 切换地图后，才会获取新的称号
 * - 自动订阅SceneChanged事件以实现地图切换检测
 *
 * @class JuntaRandomizer
 * @package org.flashNight.gesh.string
 * @extends BaseNameRandomizer
 * @author [作者]
 * @version 1.0
 */
class org.flashNight.gesh.string.JuntaRandomizer extends BaseNameRandomizer {
    /** 单例实例 */
    private static var instance:JuntaRandomizer;

    /** 军阀部队名称数组（静态共享） */
    private static var juntaNames:Array;

    /** 静态初始化标志，确保名称数组只初始化一次 */
    private static var initialized:Boolean = false;

    /** 当前地图锁定的名称 */
    private var lockedName:String;

    /** 是否已锁定名称（同一地图内保持锁定） */
    private var isLocked:Boolean;

    /**
     * 确保军阀部队名称已初始化，并设置到目标实例
     * 同时订阅场景切换事件
     * @param target 目标JuntaRandomizer实例
     */
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

    /**
     * 场景切换事件处理器（静态方法）
     * 当场景切换时，解锁当前单例实例的名称锁定
     */
    private static function onSceneChanged():Void {
        if (instance != null) {
            instance.resetSceneLock();
        }
    }

    /**
     * 重置场景锁定状态
     * 清除锁定的名称和锁定标志，允许获取新名称
     */
    private function resetSceneLock():Void {
        isLocked = false;
        lockedName = null;
    }

    /**
     * 获取单例实例（线程安全）
     * 首次调用后会重写自身以优化后续调用性能
     * @return JuntaRandomizer实例
     */
    public static function getInstance():JuntaRandomizer {
        if (instance == null) {
            instance = new JuntaRandomizer();
            getInstance = function():JuntaRandomizer {
                return instance;
            };
        }
        return instance;
    }

    /**
     * 获取随机名称（重写基类方法以实现地图锁定）
     *
     * 行为：
     * - 如果当前地图已锁定名称，直接返回锁定的名称
     * - 否则，从基类获取新名称并锁定
     *
     * @return 军阀部队名称
     */
    public function getRandomName():String {
        if (isLocked && lockedName != null) {
            return lockedName;
        }

        lockedName = super.getRandomName();
        isLocked = true;
        return lockedName;
    }

    /**
     * 私有构造函数，防止外部实例化
     * 初始化锁定状态、随机引擎并配置为耗尽前不重复模式
     */
    private function JuntaRandomizer() {
        lockedName = null;
        isLocked = false;
        setRandomEngine(LinearCongruentialEngine.getInstance());
        setUniqueUntilExhaustion(true);
        ensureNames(this);
    }
}
