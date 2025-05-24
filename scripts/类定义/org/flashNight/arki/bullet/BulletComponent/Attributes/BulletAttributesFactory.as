import org.flashNight.sara.util.*;
import org.flashNight.arki.bullet.BulletComponent.Attributes.*;

class org.flashNight.arki.bullet.BulletComponent.Attributes.BulletAttributesFactory {
    // 静态对象池实例，用于管理 BulletAttributes 实例
    private static var pool:LightObjectPool = new LightObjectPool(BulletAttributesFactory.createInstance);
    
    /**
     * 创建新的 BulletAttributes 实例（私有方法，用于对象池）
     * 
     * @return 新的 BulletAttributes 实例
     */
    private static function createInstance():BulletAttributes {
        return new BulletAttributes({});
    }

    /**
     * 静态工厂方法，用于从对象池获取一个 BulletAttributes 实例
     * 并初始化为默认值
     * 
     * @return BulletAttributes 实例
     */
    public static function createDefault():BulletAttributes {
        var instance:BulletAttributes = pool.getObject();
        // 初始化实例为默认值
        instance.initialize({
            声音: "",
            霰弹值: 1,
            子弹散射度: 1,
            发射效果: "",
            子弹种类: "普通子弹",
            子弹威力: 10,
            子弹速度: 10,
            Z轴攻击范围: 10,
            击中地图效果: "火花",
            发射者: "",
            shootX: 0,
            shootY: 0,
            转换中间y: 0,
            shootZ: 0,
            子弹敌我属性: false,
            击倒率: 10,
            击中后子弹的效果: "",
            水平击退速度: NaN,
            垂直击退速度: NaN,
            命中率: NaN,
            固伤: NaN,
            百分比伤害: NaN,
            血量上限击溃: NaN,
            防御粉碎: NaN,
            吸血: NaN,
            毒: NaN,
            最小霰弹值: 1,
            不硬直: false,
            area: undefined,
            伤害类型: undefined,
            魔法伤害属性: undefined,
            速度X: undefined,
            速度Y: undefined,
            ZY比例: undefined,
            斩杀: undefined,
            暴击: undefined,
            水平击退反向: false,
            角度偏移: 0
        });
        return instance;
    }

    /**
     * 静态方法：从 MovieClip 初始化 BulletAttributes
     * 
     * @param 子弹元件 子弹的 MovieClip 实例
     * @param 子弹种类 子弹的种类字符串
     * @param 发射者 发射者的 MovieClip 实例
     * @return 初始化后的 BulletAttributes 实例
     */
    public static function initializeFromMovieClip(子弹元件:MovieClip, 子弹种类:String, 发射者:MovieClip):BulletAttributes {
        // 获取一个默认的 BulletAttributes 实例
        var instance:BulletAttributes = BulletAttributesFactory.createDefault();

        // 坐标转换
        var myPoint:Object = {x:子弹元件._x, y:子弹元件._y};
        子弹元件._parent.localToGlobal(myPoint);
        var 转换中间y:Number = myPoint.y;
        _root.gameworld.globalToLocal(myPoint);
        var shootX:Number = myPoint.x;
        var shootY:Number = myPoint.y;

        // 确认发射者
        if (!发射者) {
            发射者 = 子弹元件._parent._parent;
        }

        // 覆盖特定属性
        instance.子弹种类 = (子弹种类 == undefined) ? "普通子弹" : 子弹种类;
        instance.发射者 = 发射者._name;
        instance.shootX = shootX;
        instance.shootY = shootY;
        instance.转换中间y = 转换中间y;
        instance.shootZ = 发射者.Z轴坐标;
        instance.子弹敌我属性 = !发射者.是否为敌人;

        return instance;
    }

    /**
     * 新增方法：创建并发射子弹
     * 
     * 该方法的参数与 _root.子弹区域shoot 完全一致，确保功能等价。
     * 
     * @param 声音:String
     * @param 霰弹值:Number
     * @param 子弹散射度:Number
     * @param 发射效果:String
     * @param 子弹种类:String
     * @param 子弹威力:Number
     * @param 子弹速度:Number
     * @param Z轴攻击范围:Number
     * @param 击中地图效果:String
     * @param 发射者:String
     * @param shootX:Number
     * @param shootY:Number
     * @param shootZ:Number
     * @param 子弹敌我属性:Boolean
     * @param 击倒率:Number
     * @param 击中后子弹的效果:String
     * @param 水平击退速度:Number
     * @param 垂直击退速度:Number
     * @param 命中率:Number
     * @param 固伤:Number
     * @param 百分比伤害:Number
     * @param 血量上限击溃:Number
     * @param 防御粉碎:Number
     * @param area:Object
     * @param 吸血:Number
     * @param 毒:Number
     * @param 最小霰弹值:Number
     * @param 不硬直:Boolean
     * @param 伤害类型:Object
     * @param 魔法伤害属性:Object
     * @param 速度X:Number
     * @param 速度Y:Number
     * @param ZY比例:Number
     * @param 斩杀:Object
     * @param 暴击:Object
     * @param 水平击退反向:Boolean
     * @param 角度偏移:Number
     */
    public static function createAndShoot(
        声音:String,
        霰弹值:Number,
        子弹散射度:Number,
        发射效果:String,
        子弹种类:String,
        子弹威力:Number,
        子弹速度:Number,
        Z轴攻击范围:Number,
        击中地图效果:String,
        发射者:String,
        shootX:Number,
        shootY:Number,
        shootZ:Number,
        子弹敌我属性:Boolean,
        击倒率:Number,
        击中后子弹的效果:String,
        水平击退速度:Number,
        垂直击退速度:Number,
        命中率:Number,
        固伤:Number,
        百分比伤害:Number,
        血量上限击溃:Number,
        防御粉碎:Number,
        area:Object,
        吸血:Number,
        毒:Number,
        最小霰弹值:Number,
        不硬直:Boolean,
        伤害类型:Object,
        魔法伤害属性:Object,
        速度X:Number,
        速度Y:Number,
        ZY比例:Number,
        斩杀:Object,
        暴击:Object,
        水平击退反向:Boolean,
        角度偏移:Number
    ):Void {
        // 创建 BulletAttributes 实例
        var bulletAttributes:BulletAttributes = createDefault();

        // 初始化属性
        bulletAttributes.initialize({
            声音: 声音,
            霰弹值: 霰弹值,
            子弹散射度: 子弹散射度,
            发射效果: 发射效果,
            子弹种类: 子弹种类,
            子弹威力: 子弹威力,
            子弹速度: 子弹速度,
            Z轴攻击范围: Z轴攻击范围,
            击中地图效果: 击中地图效果,
            发射者: 发射者,
            shootX: shootX,
            shootY: shootY,
            shootZ: shootZ,
            子弹敌我属性: 子弹敌我属性,
            击倒率: 击倒率,
            击中后子弹的效果: 击中后子弹的效果,
            水平击退速度: 水平击退速度,
            垂直击退速度: 垂直击退速度,
            命中率: 命中率,
            固伤: 固伤,
            百分比伤害: 百分比伤害,
            血量上限击溃: 血量上限击溃,
            防御粉碎: 防御粉碎,
            吸血: 吸血,
            毒: 毒,
            最小霰弹值: 最小霰弹值,
            不硬直: 不硬直,
            伤害类型: 伤害类型,
            魔法伤害属性: 魔法伤害属性,
            速度X: 速度X,
            速度Y: 速度Y,
            ZY比例: ZY比例,
            斩杀: 斩杀,
            暴击: 暴击,
            水平击退反向: 水平击退反向,
            角度偏移: 角度偏移
        });

        // 传递给 _root.子弹区域shoot传递
        _root.子弹区域shoot传递(bulletAttributes);
    }

    /**
     * 释放 BulletAttributes 实例回对象池
     * 
     * @param instance 要释放的 BulletAttributes 实例
     */
    public static function releaseInstance(instance:BulletAttributes):Void {
        if (instance != undefined) {
            pool.releaseObject(instance);
        }
    }
}
