import org.flashNight.arki.unit.UnitComponent.Initializer.ElementComponent.*;

/**
 * 地图元件预设数据类
 * 定义地图元件的配置数据结构
 */
class org.flashNight.arki.unit.UnitComponent.Initializer.ElementComponent.ElementPreset {
    
    // 基础属性
    public var hitPoint:Number;
    public var maxFrame:Number;
    public var audio:String;
    
    // 进度限制
    public var 最小主线进度:Number;
    public var 最大主线进度:Number;
    
    // 数量设置
    public var 数量_min:Number;
    public var 数量_max:Number;
    
    // 战斗属性
    public var hp:Number;
    public var 防御力:Number;
    public var 躲闪率:Number;
    public var 击中效果:String;
    public var unitAIType:String;
    
    // 显示属性
    public var 是否为敌人:Boolean;
    public var obstacle:Boolean;
    
    // 染色属性
    public var stainedTarget:String;
    public var redMultiplier:Number;
    public var greenMultiplier:Number;
    public var blueMultiplier:Number;
    public var alphaMultiplier:Number;
    public var redOffset:Number;
    public var greenOffset:Number;
    public var blueOffset:Number;
    public var alphaOffset:Number;
    
    // 交互属性
    public var interactionEnabled:Boolean;
    public var pickupEnabled:Boolean;
    
    // 自定义属性扩展
    public var customProperties:Object;
    
    /**
     * 构造函数
     */
    public function ElementPreset() {
        // 设置默认值
        this.hitPoint = 10;
        this.maxFrame = 1;
        this.audio = "拾取音效";
        this.hp = 9999999;
        this.防御力 = 99999;
        this.躲闪率 = 100;
        this.击中效果 = "火花";
        this.unitAIType = "None";
        this.是否为敌人 = true;
        this.obstacle = false;
        this.interactionEnabled = true;
        this.pickupEnabled = true;
        this.customProperties = {};
        
        // 染色默认值
        this.redMultiplier = 1;
        this.greenMultiplier = 1;
        this.blueMultiplier = 1;
        this.alphaMultiplier = 1;
        this.redOffset = 0;
        this.greenOffset = 0;
        this.blueOffset = 0;
        this.alphaOffset = 0;
    }
    
    /**
     * 从对象创建预设
     * @param cfg 配置对象
     * @return ElementPreset 创建的预设实例
     */
    public static function fromObject(cfg:Object):ElementPreset {
        var preset:ElementPreset = new ElementPreset();
        
        // 复制所有属性
        for (var prop in cfg) {
            if (preset.hasOwnProperty(prop)) {
                preset[prop] = cfg[prop];
            } else if (prop != "customProperties") {
                // 未知属性放入customProperties
                preset.customProperties[prop] = cfg[prop];
            }
        }
        
        // 处理自定义属性
        if (cfg.customProperties) {
            for (var customProp in cfg.customProperties) {
                preset.customProperties[customProp] = cfg.customProperties[customProp];
            }
        }
        
        return preset;
    }
    
    /**
     * 应用预设到目标
     * @param target 目标MovieClip
     */
    public function applyTo(target:MovieClip):Void {
        // 应用基础属性
        if (!isNaN(this.hitPoint)) target.hitPoint = this.hitPoint;
        if (!isNaN(this.maxFrame)) target.maxFrame = this.maxFrame;
        if (this.audio) target.audio = this.audio;
        
        // 应用进度限制
        if (!isNaN(this.最小主线进度)) target.最小主线进度 = this.最小主线进度;
        if (!isNaN(this.最大主线进度)) target.最大主线进度 = this.最大主线进度;
        
        // 应用数量设置
        if (!isNaN(this.数量_min)) target.数量_min = this.数量_min;
        if (!isNaN(this.数量_max)) target.数量_max = this.数量_max;
        
        // 应用战斗属性
        if (!isNaN(this.hp)) target.hp = this.hp;
        if (!isNaN(this.防御力)) target.防御力 = this.防御力;
        if (!isNaN(this.躲闪率)) target.躲闪率 = this.躲闪率;
        if (this.击中效果) target.击中效果 = this.击中效果;
        if (this.unitAIType) target.unitAIType = this.unitAIType;
        
        // 应用显示属性
        if (this.是否为敌人 !== undefined) target.是否为敌人 = this.是否为敌人;
        if (this.obstacle !== undefined) target.obstacle = this.obstacle;
        
        // 应用染色属性
        if (this.stainedTarget) {
            target.stainedTarget = this.stainedTarget;
            target.redMultiplier = this.redMultiplier;
            target.greenMultiplier = this.greenMultiplier;
            target.blueMultiplier = this.blueMultiplier;
            target.alphaMultiplier = this.alphaMultiplier;
            target.redOffset = this.redOffset;
            target.greenOffset = this.greenOffset;
            target.blueOffset = this.blueOffset;
            target.alphaOffset = this.alphaOffset;
        }
        
        // 应用交互属性
        target.interactionEnabled = this.interactionEnabled;
        target.pickupEnabled = this.pickupEnabled;
        
        // 应用自定义属性
        for (var prop in this.customProperties) {
            target[prop] = this.customProperties[prop];
        }
    }
    
    /**
     * 克隆预设
     * @return ElementPreset 克隆的预设实例
     */
    public function clone():ElementPreset {
        var cloned:ElementPreset = new ElementPreset();
        
        // 复制所有属性
        for (var prop in this) {
            if (prop != "customProperties" && typeof(this[prop]) != "function") {
                cloned[prop] = this[prop];
            }
        }
        
        // 深度复制自定义属性
        cloned.customProperties = {};
        for (var customProp in this.customProperties) {
            cloned.customProperties[customProp] = this.customProperties[customProp];
        }
        
        return cloned;
    }
    
    /**
     * 合并另一个预设的属性
     * @param other 要合并的预设
     * @param overwrite 是否覆盖现有属性，默认为true
     */
    public function merge(other:ElementPreset, overwrite:Boolean):Void {
        if (overwrite === undefined) overwrite = true;
        
        for (var prop in other) {
            if (prop != "customProperties" && typeof(other[prop]) != "function") {
                if (overwrite || this[prop] === undefined || isNaN(this[prop])) {
                    this[prop] = other[prop];
                }
            }
        }
        
        // 合并自定义属性
        for (var customProp in other.customProperties) {
            if (overwrite || this.customProperties[customProp] === undefined) {
                this.customProperties[customProp] = other.customProperties[customProp];
            }
        }
    }
}