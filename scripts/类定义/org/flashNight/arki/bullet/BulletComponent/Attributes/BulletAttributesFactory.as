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
