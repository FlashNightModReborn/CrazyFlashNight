// 文件路径：org.flashNight.arki.bullet.BulletComponent.Type.BulletTypesetter.as

import org.flashNight.arki.bullet.BulletComponent.Type.ITypesetter;
import org.flashNight.gesh.object.ObjectUtil;

class org.flashNight.arki.bullet.BulletComponent.Type.BulletTypesetter implements ITypesetter {
    // 缓存对象，用于存储每种子弹种类的条件结果
    private static var typeCache:Object = {};

    // 透明类型数组
    private static var 透明类型:Array = ["近战子弹", "近战联弹", "透明子弹"];

    /**
     * 构造函数。
     * 由于所有方法和属性都是静态的，不需要实例化。
     */
    public function BulletTypesetter() {
        // 不需要初始化任何内容
    }

    /**
     * 静态方法，设置子弹的类型标志。
     * @param bullet:Object 子弹对象。
     */
    public static function setTypeFlags(bullet:Object):Void {
        var 子弹种类:String = bullet.子弹种类;

        // 从缓存中获取条件结果
        var cachedFlags:Object = typeCache[子弹种类];

        // 如果缓存中不存在该子弹种类的条件结果，则计算并存入缓存
        if (cachedFlags == undefined) {
            cachedFlags = {};

            cachedFlags.contains_近战 = 子弹种类.indexOf("近战") != -1;
            cachedFlags.contains_联弹 = 子弹种类.indexOf("联弹") != -1;
            cachedFlags.contains_穿刺 = 子弹种类.indexOf("穿刺") != -1;
            cachedFlags.is_透明类型 = 透明类型.indexOf(子弹种类) != -1;
            cachedFlags.contains_手雷 = 子弹种类.indexOf("手雷") != -1;
            cachedFlags.contains_爆炸 = 子弹种类.indexOf("爆炸") != -1;
            cachedFlags.contains_普通 = 子弹种类.indexOf("普通") != -1;
            cachedFlags.contains_能量子弹 = 子弹种类.indexOf("能量子弹") != -1;
            cachedFlags.is_精制子弹 = (子弹种类 == "精制子弹");

            // 将计算结果存入缓存
            typeCache[子弹种类] = cachedFlags;
        }

        // 应用缓存的条件结果
        bullet.近战检测 = cachedFlags.contains_近战;
        bullet.联弹检测 = cachedFlags.contains_联弹;

        // 穿刺检测：保持原有值或更新
        bullet.穿刺检测 = bullet.穿刺检测 || cachedFlags.contains_穿刺;

        // 透明检测：保持原有值或更新
        bullet.透明检测 = bullet.透明检测 || cachedFlags.is_透明类型;

        // 手雷检测：保持原有值或更新
        bullet.手雷检测 = bullet.手雷检测 || cachedFlags.contains_手雷;

        // 爆炸检测：保持原有值或更新
        bullet.爆炸检测 = bullet.爆炸检测 || cachedFlags.contains_爆炸;

        // 普通检测
        bullet.普通检测 = !bullet.穿刺检测 && !bullet.爆炸检测 &&
                           (bullet.近战检测 || bullet.透明检测 ||
                            cachedFlags.contains_普通 ||
                            cachedFlags.contains_能量子弹 ||
                            cachedFlags.is_精制子弹);

        _root.服务器.发布服务器消息(" bts " + ObjectUtil.toString(bullet));
    }

    /**
     * 清理缓存中的所有条件结果。
     * 该方法用于在适当的时机清空缓存，防止内存泄漏或数据不一致。
     */
    public static function clearCache():Void {
        for (var key:String in typeCache) {
            delete typeCache[key];
        }
    }
}
