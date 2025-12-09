import org.flashNight.sara.util.*;
import org.flashNight.arki.bullet.BulletComponent.Attributes.*;

class org.flashNight.arki.bullet.BulletComponent.Attributes.BulletAttributes {
    // 属性定义
    public var 声音:String;
    public var 霰弹值:Number;
    public var 子弹散射度:Number;
    public var 发射效果:String;
    public var 子弹种类:String;
    public var 子弹威力:Number;
    public var 子弹速度:Number;
    public var Z轴攻击范围:Number;
    public var 击中地图效果:String;
    public var 发射者:String;
    public var shootX:Number;
    public var shootY:Number;
    public var 转换中间y:Number;
    public var shootZ:Number;
    public var 子弹敌我属性:Boolean;
    public var 击倒率:Number;
    public var 击中后子弹的效果:String;
    public var 水平击退速度:Number;
    public var 垂直击退速度:Number;
    public var 命中率:Number;
    public var 固伤:Number;
    public var 百分比伤害:Number;
    public var 血量上限击溃:Number;
    public var 防御粉碎:Number;
    public var 吸血:Number;
    public var 毒:Number;
    public var 最小霰弹值:Number;
    public var 不硬直:Boolean;
    public var area:Object;
    public var 伤害类型:Object;
    public var 魔法伤害属性:Object;
    public var 速度X:Number;
    public var 速度Y:Number;
    public var ZY比例:Number;
    public var 斩杀:Object;
    public var 暴击:Object;
    public var 水平击退反向:Boolean;
    public var 角度偏移:Number;

    /**
     * 实例状态标志位
     * 与 flags（类型标志位）分离，存储实例层面的布尔属性
     * 通过位运算压缩多个布尔属性，节省内存
     *
     * 位分配参见 macros/StateFlags.as:
     * • bit 0: STATE_NO_STUN           - 不硬直
     * • bit 1: STATE_REVERSE_KNOCKBACK - 水平击退反向
     * • bit 2: STATE_FRIENDLY_FIRE     - 友军伤害
     * • bit 3: STATE_LONG_RANGE        - 远距离不消失
     * • bit 4: STATE_GRENADE_XML       - XML配置的手雷标记
     */
    public var stateFlags:Number;

    /**
     * 构造函数
     * 注意：构造函数应为私有的，以防止外部直接实例化对象。
     * 但由于 AS2 不支持真正的私有构造函数，我们通过约定避免外部直接实例化。
     */
    public function BulletAttributes(initParams:Object) {
        this.initialize(initParams);
    }

    /**
     * 初始化方法，用于设置属性值
     * 
     * @param initParams 初始化参数对象
     */
    public function initialize(initParams:Object):Void {
        this.声音 = (initParams.声音 != undefined) ? initParams.声音 : "";
        this.霰弹值 = (initParams.霰弹值 != undefined) ? initParams.霰弹值 : 1;
        this.子弹散射度 = (initParams.子弹散射度 != undefined) ? initParams.子弹散射度 : 1;
        this.发射效果 = (initParams.发射效果 != undefined) ? initParams.发射效果 : "";
        this.子弹种类 = (initParams.子弹种类 != undefined) ? initParams.子弹种类 : "普通子弹";
        this.子弹威力 = (initParams.子弹威力 != undefined) ? initParams.子弹威力 : 10;
        this.子弹速度 = (initParams.子弹速度 != undefined) ? initParams.子弹速度 : 10;
        this.Z轴攻击范围 = (initParams.Z轴攻击范围 != undefined) ? initParams.Z轴攻击范围 : 10;
        this.击中地图效果 = (initParams.击中地图效果 != undefined) ? initParams.击中地图效果 : "火花";
        this.发射者 = (initParams.发射者 != undefined) ? initParams.发射者 : "";
        this.shootX = (initParams.shootX != undefined) ? initParams.shootX : 0;
        this.shootY = (initParams.shootY != undefined) ? initParams.shootY : 0;
        this.转换中间y = (initParams.转换中间y != undefined) ? initParams.转换中间y : 0;
        this.shootZ = (initParams.shootZ != undefined) ? initParams.shootZ : 0;
        this.击倒率 = (initParams.击倒率 != undefined) ? initParams.击倒率 : 10;
        this.击中后子弹的效果 = (initParams.击中后子弹的效果 != undefined) ? initParams.击中后子弹的效果 : "";
        this.水平击退速度 = (initParams.水平击退速度 != undefined) ? initParams.水平击退速度 : NaN;
        this.垂直击退速度 = (initParams.垂直击退速度 != undefined) ? initParams.垂直击退速度 : NaN;
        this.命中率 = (initParams.命中率 != undefined) ? initParams.命中率 : NaN;
        this.固伤 = (initParams.固伤 != undefined) ? initParams.固伤 : NaN;
        this.百分比伤害 = (initParams.百分比伤害 != undefined) ? initParams.百分比伤害 : NaN;
        this.血量上限击溃 = (initParams.血量上限击溃 != undefined) ? initParams.血量上限击溃 : NaN;
        this.防御粉碎 = (initParams.防御粉碎 != undefined) ? initParams.防御粉碎 : NaN;
        this.吸血 = (initParams.吸血 != undefined) ? initParams.吸血 : NaN;
        this.毒 = (initParams.毒 != undefined) ? initParams.毒 : NaN;
        this.最小霰弹值 = (initParams.最小霰弹值 != undefined) ? initParams.最小霰弹值 : 1;
        this.不硬直 = (initParams.不硬直 != undefined) ? initParams.不硬直 : false;
        this.area = (initParams.area != undefined) ? initParams.area : undefined;
        this.伤害类型 = (initParams.伤害类型 != undefined) ? initParams.伤害类型 : undefined;
        this.魔法伤害属性 = (initParams.魔法伤害属性 != undefined) ? initParams.魔法伤害属性 : undefined;
        this.速度X = (initParams.速度X != undefined) ? initParams.速度X : undefined;
        this.速度Y = (initParams.速度Y != undefined) ? initParams.速度Y : undefined;
        this.ZY比例 = (initParams.ZY比例 != undefined) ? initParams.ZY比例 : undefined;
        this.斩杀 = (initParams.斩杀 != undefined) ? initParams.斩杀 : undefined;
        this.暴击 = (initParams.暴击 != undefined) ? initParams.暴击 : undefined;
        this.水平击退反向 = (initParams.水平击退反向 != undefined) ? initParams.水平击退反向 : false;
        this.角度偏移 = (initParams.角度偏移 != undefined) ? initParams.角度偏移 : 0;
        this.stateFlags = (initParams.stateFlags != undefined) ? initParams.stateFlags : 0;
    }

    /**
     * 克隆当前 BulletAttributes 实例（浅拷贝）
     * 
     * @return 新的 BulletAttributes 实例
     */
    public function clone():BulletAttributes {
        // 通过工厂获取一个新的实例
        var clonedInstance:BulletAttributes = BulletAttributesFactory.createDefault();
        clonedInstance.initialize({
            声音: this.声音,
            霰弹值: this.霰弹值,
            子弹散射度: this.子弹散射度,
            发射效果: this.发射效果,
            子弹种类: this.子弹种类,
            子弹威力: this.子弹威力,
            子弹速度: this.子弹速度,
            Z轴攻击范围: this.Z轴攻击范围,
            击中地图效果: this.击中地图效果,
            发射者: this.发射者,
            shootX: this.shootX,
            shootY: this.shootY,
            转换中间y: this.转换中间y,
            shootZ: this.shootZ,
            子弹敌我属性: null,
            击倒率: this.击倒率,
            击中后子弹的效果: this.击中后子弹的效果,
            水平击退速度: this.水平击退速度,
            垂直击退速度: this.垂直击退速度,
            命中率: this.命中率,
            固伤: this.固伤,
            百分比伤害: this.百分比伤害,
            血量上限击溃: this.血量上限击溃,
            防御粉碎: this.防御粉碎,
            吸血: this.吸血,
            毒: this.毒,
            最小霰弹值: this.最小霰弹值,
            不硬直: this.不硬直,
            area: this.area, // 浅拷贝，引用类型
            伤害类型: this.伤害类型, // 浅拷贝，引用类型
            魔法伤害属性: this.魔法伤害属性, // 浅拷贝，引用类型
            速度X: this.速度X,
            速度Y: this.速度Y,
            ZY比例: this.ZY比例,
            斩杀: this.斩杀, // 浅拷贝，引用类型
            暴击: this.暴击, // 浅拷贝，引用类型
            水平击退反向: this.水平击退反向,
            角度偏移: this.角度偏移,
            stateFlags: this.stateFlags
        });
        return clonedInstance;
    }

    /**
     * 释放当前 BulletAttributes 实例回对象池
     */
    public function release():Void {
        BulletAttributesFactory.releaseInstance(this);
    }
}
