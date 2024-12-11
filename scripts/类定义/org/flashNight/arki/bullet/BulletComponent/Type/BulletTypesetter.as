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

    public function BulletTypesetter() {
        // 不需要初始化任何内容
    }

    public static function setTypeFlags(bullet:Object):Void {
        if (bullet == undefined || bullet.子弹种类 == undefined) {
            trace("Warning: Bullet object or 子弹种类 is undefined.");
            return;
        }

        var 子弹种类:String = bullet.子弹种类;
        var flags:Number = typeCache[子弹种类];

        if (flags == undefined) {
            var isMelee:Boolean         = (子弹种类.indexOf("近战") != -1);
            var isChain:Boolean         = (子弹种类.indexOf("联弹") != -1);
            var isPierce:Boolean        = (子弹种类.indexOf("穿刺") != -1);
            var isTransparency:Boolean  = (transparency.indexOf("|" + 子弹种类 + "|") != -1);
            var isGrenade:Boolean       = (子弹种类.indexOf("手雷") != -1);
            var isExplosive:Boolean     = (子弹种类.indexOf("爆炸") != -1);
            var isEnergy:Boolean        = (子弹种类.indexOf("能量子弹") != -1);
            var isRefined:Boolean       = (子弹种类 == "精制子弹");

            // 根据普通检测逻辑，计算 isNormal 标志
            var isNormal:Boolean = !isPierce && !isExplosive && !isChain && 
                                   (isMelee || isTransparency || (子弹种类.indexOf("普通") != -1) || isEnergy || isRefined);

            flags = ((isMelee         ? FLAG_MELEE         : 0)
                  | (isChain         ? FLAG_CHAIN         : 0)
                  | (isPierce        ? FLAG_PIERCE        : 0)
                  | (isTransparency  ? FLAG_TRANSPARENCY  : 0)
                  | (isGrenade       ? FLAG_GRENADE       : 0)
                  | (isExplosive     ? FLAG_EXPLOSIVE     : 0)
                  | (isNormal        ? FLAG_NORMAL        : 0)
                  | (isEnergy        ? FLAG_ENERGY        : 0)
                  | (isRefined       ? FLAG_REFINED       : 0));

            typeCache[子弹种类] = flags;
        }

        bullet.近战检测 = ((flags & FLAG_MELEE) != 0);
        bullet.联弹检测 = ((flags & FLAG_CHAIN) != 0);
        bullet.穿刺检测 = bullet.穿刺检测 || ((flags & FLAG_PIERCE) != 0);
        bullet.透明检测 = bullet.透明检测 || ((flags & FLAG_TRANSPARENCY) != 0);
        bullet.手雷检测 = bullet.手雷检测 || ((flags & FLAG_GRENADE) != 0);
        bullet.爆炸检测 = bullet.爆炸检测 || ((flags & FLAG_EXPLOSIVE) != 0);

        // 根据 flags 的普通标志更新普通检测逻辑
        bullet.普通检测 = ((flags & FLAG_NORMAL) != 0);

        // 调试输出（可选）
        // _root.服务器.发布服务器消息(" bts " + ObjectUtil.toString(bullet));
    }

    public static function clearCache():Void {
        for (var key:String in typeCache) {
            delete typeCache[key];
        }
    }
}
