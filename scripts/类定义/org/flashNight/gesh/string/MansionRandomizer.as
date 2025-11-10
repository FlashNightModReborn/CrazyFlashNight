import org.flashNight.gesh.string.*;
import org.flashNight.naki.RandomNumberEngine.*;

/**
 * 二十八宿名称随机器
 * 用于从二十八宿星官中随机选择名称，确保在池耗尽前不重复
 * 二十八宿是中国古代天文学中黄道附近的二十八个星座
 *
 * @class MansionRandomizer
 * @package org.flashNight.gesh.string
 * @extends BaseNameRandomizer
 * @author [作者]
 * @version 1.0
 */
class org.flashNight.gesh.string.MansionRandomizer extends BaseNameRandomizer {
    /** 单例实例 */
    private static var instance:MansionRandomizer;

    /** 二十八宿标准名称数组（静态共享） */
    private static var mansionNames:Array;

    /** 静态初始化标志，确保名称数组只初始化一次 */
    private static var initialized:Boolean = false;

    /**
     * 确保二十八宿名称已初始化，并设置到目标实例
     * @param target 目标MansionRandomizer实例
     */
    private static function ensureNames(target:MansionRandomizer):Void {
        if (!initialized) {
            mansionNames = [
                "角木蛟", "亢金龙", "氐土貉", "房日兔", "心月狐", "尾火虎", "箕水豹", 
                "斗木獬", "牛金牛", "女土蝠", "虚日鼠", "危月燕", "室火猪", "壁水獺", 
                "奎木狼", "娄金狗", "胃土雉", "昴日鸡", "毕月乌", "觜火猴", "参水猿", 
                "井土狗", "鬼金羊", "柳木猴", "星日马", "张月鹿", "翼火蛇", "轸水蚓"
            ];

            initialized = true;
        }

        target.setNames(mansionNames);
    }

    /**
     * 获取单例实例（线程安全）
     * 首次调用后会重写自身以优化后续调用性能
     * @return MansionRandomizer实例
     */
    public static function getInstance():MansionRandomizer {
        if (instance == null) {
            instance = new MansionRandomizer();
            getInstance = function():MansionRandomizer {
                return instance;
            };
        }
        return instance;
    }

    /**
     * 私有构造函数，防止外部实例化
     * 初始化随机引擎并配置为耗尽前不重复模式
     */
    private function MansionRandomizer() {
        setRandomEngine(LinearCongruentialEngine.getInstance());
        setUniqueUntilExhaustion(true);
        ensureNames(this);
    }
}
