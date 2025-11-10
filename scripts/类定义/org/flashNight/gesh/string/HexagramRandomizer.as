import org.flashNight.gesh.string.*;
import org.flashNight.naki.RandomNumberEngine.*;

/**
 * 六十四卦名称随机器
 * 用于从六十四卦中随机选择卦名，确保在池耗尽前不重复
 *
 * @class HexagramRandomizer
 * @package org.flashNight.gesh.string
 * @extends BaseNameRandomizer
 * @author [作者]
 * @version 1.0
 */
class org.flashNight.gesh.string.HexagramRandomizer extends BaseNameRandomizer {
    /** 单例实例 */
    private static var instance:HexagramRandomizer;

    /** 六十四卦标准名称数组（静态共享） */
    private static var hexagramNames:Array;

    /** 静态初始化标志，确保名称数组只初始化一次 */
    private static var initialized:Boolean = false;

    /**
     * 确保六十四卦名称已初始化，并设置到目标实例
     * @param target 目标HexagramRandomizer实例
     */
    private static function ensureNames(target:HexagramRandomizer):Void {
        if (!initialized) {
            hexagramNames = [
                "乾为天", "坤为地", "水雷屯", "山水蒙", "水天需", "天水讼", "地水师",
                "水地比", "风天小畜", "天泽履", "地天泰", "天地否", "天火同人", "火天大有",
                "地山谦", "雷地豫", "泽雷随", "山风蛊", "地泽临", "风地观", "火雷噬嗑",
                "山火贲", "山地剥", "地雷复", "天雷无妄", "山天大畜", "山雷颐", "泽风大过",
                "坎为水", "离为火", "泽山咸", "雷风恒", "天山遯", "雷天大壮", "火地晋",
                "地火明夷", "风火家人", "火泽睽", "水山蹇", "雷水解", "山泽损", "风雷益",
                "泽天夬", "天风姤", "泽地萃", "地风升", "泽水困", "水风井", "泽火革",
                "火风鼎", "震为雷", "艮为山", "风山渐", "雷泽归妹", "雷火丰", "火山旅",
                "巽为风", "兑为泽", "风水涣", "水泽节", "风泽中孚", "雷山小过", "水火既济",
                "火水未济"
            ];

            initialized = true;
        }

        target.setNames(hexagramNames);
    }

    /**
     * 获取单例实例（线程安全）
     * 首次调用后会重写自身以优化后续调用性能
     * @return HexagramRandomizer实例
     */
    public static function getInstance():HexagramRandomizer {
        if (instance == null) {
            instance = new HexagramRandomizer();
            getInstance = function():HexagramRandomizer {
                return instance;
            };
        }
        return instance;
    }

    /**
     * 私有构造函数，防止外部实例化
     * 初始化随机引擎并配置为耗尽前不重复模式
     */
    private function HexagramRandomizer() {
        setRandomEngine(LinearCongruentialEngine.getInstance());
        setUniqueUntilExhaustion(true);
        ensureNames(this);
    }
}
