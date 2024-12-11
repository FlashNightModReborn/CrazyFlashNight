// 文件路径：org.flashNight.arki.bullet.BulletComponent.Type.BulletTypesetter.as

import org.flashNight.arki.bullet.BulletComponent.Type.ITypesetter;
import org.flashNight.gesh.object.ObjectUtil;

class org.flashNight.arki.bullet.BulletComponent.Type.BulletTypesetter implements ITypesetter {
    // 定义位标志，每个标志对应一个唯一的二进制位
    private static var FLAG_MELEE:Number         = 1 << 0; // 近战
    private static var FLAG_CHAIN:Number         = 1 << 1; // 联弹
    private static var FLAG_PIERCE:Number        = 1 << 2; // 穿刺
    private static var FLAG_TRANSPARENCY:Number  = 1 << 3; // 透明
    private static var FLAG_GRENADE:Number       = 1 << 4; // 手雷
    private static var FLAG_EXPLOSIVE:Number     = 1 << 5; // 爆炸
    private static var FLAG_NORMAL:Number        = 1 << 6; // 普通
    private static var FLAG_ENERGY:Number        = 1 << 7; // 能量子弹
    private static var FLAG_REFINED:Number       = 1 << 8; // 精制子弹

    // 缓存对象：key为子弹种类字符串，value为flags整型标志
    private static var typeCache:Object = {};

    // 透明类型字符串，使用 "|" 作为分隔符，避免部分匹配
    private static var transparency:String = "|" + ["近战子弹", "近战联弹", "透明子弹"].join("|") + "|";

    /**
     * 构造函数。
     * 由于所有方法和属性都是静态的，不需要实例化。
     */
    public function BulletTypesetter() {
        // 不需要初始化任何内容
    }

    /**
     * 静态方法，设置子弹的类型标志。
     * 使用位标志优化缓存，并用位运算设置检测标志。
     * @param bullet:Object 子弹对象，需要 bullet.子弹种类 字符串。
     */
    public static function setTypeFlags(bullet:Object):Void {
        // 检查 bullet 对象和子弹种类属性是否存在
        if (bullet == undefined || bullet.子弹种类 == undefined) {
            trace("Warning: Bullet object or 子弹种类 is undefined.");
            return;
        }

        var 子弹种类:String = bullet.子弹种类;
        var flags:Number = typeCache[子弹种类];

        // 如果缓存中没有该子弹种类的标记，则计算并缓存
        if (flags == undefined) {
            var isMelee:Boolean         = (子弹种类.indexOf("近战") != -1);
            var isChain:Boolean         = (子弹种类.indexOf("联弹") != -1);
            var isPierce:Boolean        = (子弹种类.indexOf("穿刺") != -1);
            var isTransparency:Boolean  = (transparency.indexOf("|" + 子弹种类 + "|") != -1);
            var isGrenade:Boolean       = (子弹种类.indexOf("手雷") != -1);
            var isExplosive:Boolean     = (子弹种类.indexOf("爆炸") != -1);
            var isNormal:Boolean        = (子弹种类.indexOf("普通") != -1);
            var isEnergy:Boolean        = (子弹种类.indexOf("能量子弹") != -1);
            var isRefined:Boolean       = (子弹种类 == "精制子弹");

            // 将所有条件的结果通过位或运算赋给flags
            flags = ((isMelee         ? FLAG_MELEE         : 0)
                  | (isChain         ? FLAG_CHAIN         : 0)
                  | (isPierce        ? FLAG_PIERCE        : 0)
                  | (isTransparency  ? FLAG_TRANSPARENCY  : 0)
                  | (isGrenade       ? FLAG_GRENADE       : 0)
                  | (isExplosive     ? FLAG_EXPLOSIVE     : 0)
                  | (isNormal        ? FLAG_NORMAL        : 0)
                  | (isEnergy        ? FLAG_ENERGY        : 0)
                  | (isRefined       ? FLAG_REFINED       : 0));

            // 将计算结果存入缓存
            typeCache[子弹种类] = flags;
        }

        // 根据flags设置bullet检测标志
        bullet.近战检测 = ((flags & FLAG_MELEE) != 0);
        bullet.联弹检测 = ((flags & FLAG_CHAIN) != 0);
        bullet.穿刺检测 = bullet.穿刺检测 || ((flags & FLAG_PIERCE) != 0);
        bullet.透明检测 = bullet.透明检测 || ((flags & FLAG_TRANSPARENCY) != 0);
        bullet.手雷检测 = bullet.手雷检测 || ((flags & FLAG_GRENADE) != 0);
        bullet.爆炸检测 = bullet.爆炸检测 || ((flags & FLAG_EXPLOSIVE) != 0);

        // 普通检测逻辑：
        // 非穿刺、非爆炸，且(近战或透明或普通标志或能量子弹或精制子弹)
        var hasNormalFlag:Boolean = ((flags & FLAG_NORMAL) != 0);
        var hasEnergyFlag:Boolean = ((flags & FLAG_ENERGY) != 0);
        var hasRefinedFlag:Boolean = ((flags & FLAG_REFINED) != 0);

        bullet.普通检测 = !bullet.穿刺检测 && !bullet.爆炸检测 && !bullet.联弹检测 &&
                          (bullet.近战检测 || bullet.透明检测 ||
                           hasNormalFlag || hasEnergyFlag || hasRefinedFlag);

        // 调试输出（可选）
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
