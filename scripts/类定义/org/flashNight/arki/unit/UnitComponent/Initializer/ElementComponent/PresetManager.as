import org.flashNight.arki.unit.UnitComponent.Initializer.ElementComponent.*;
/**
 * 预设管理器
 * 负责管理和加载地图元件预设
 */
class org.flashNight.arki.unit.UnitComponent.Initializer.ElementComponent.PresetManager {
    
    // 预设存储
    private static var presets:Object = {};
    private static var initialized:Boolean = false;
    
    /**
     * 初始化预设管理器
     */
    public static function initialize():Void {
        if (initialized) return;
        
        PresetManager.loadDefaultPresets();
        initialized = true;
    }
    
    /**
     * 加载默认预设
     */
    private static function loadDefaultPresets():Void {
        // 保险柜预设
        PresetManager.registerPreset("保险柜", {
            hitPoint: 100,
            maxFrame: 12,
            audio: "保险柜打开.wav",
            obstacle: false,
            hp: 9999999,
            防御力: 99999,
            躲闪率: 100,
            击中效果: "火花",
            是否为敌人: true,
            interactionEnabled: true,
            pickupEnabled: true,
            row: 4,
            col: 8
        });
        
        // 生存箱预设
        PresetManager.registerPreset("生存箱", {
            hitPoint: 50,
            maxFrame: 12,
            row: 4,
            col: 4
        });

        // 资源箱预设
        PresetManager.registerPreset("装备箱", {
            hitPoint: 30,
            maxFrame: 12,
            row: 2,
            col: 4
        });

        // 资源箱预设
        PresetManager.registerPreset("资源箱", {
            hitPoint: 10,
            maxFrame: 12,
            row: 0,
            col: 0
        });

        // 纸箱预设
        PresetManager.registerPreset("纸箱", {
            hitPoint: 1,
            maxFrame: 1,
            row: 0,
            col: 0
        });
        
    }
    
    /**
     * 注册新预设
     * @param name 预设名称
     * @param cfg 预设配置对象或ElementPreset实例
     */
    public static function registerPreset(name:String, cfg:Object):Void {
        if (!name) return;
        
        var preset;
        if (cfg instanceof ElementPreset) {
            preset = cfg;
        } else {
            preset = ElementPreset.fromObject(cfg);
        }
        
        presets[name] = preset;
    }
    
    /**
     * 获取预设
     * @param name 预设名称
     * @return ElementPreset 预设实例，如果不存在则返回null
     */
    public static function getPreset(name:String):ElementPreset {
        if (!initialized) {
            PresetManager.initialize();
        }
        
        var preset:ElementPreset = presets[name];
        return preset ? preset.clone() : null;
    }
    
    /**
     * 检查预设是否存在
     * @param name 预设名称
     * @return Boolean 如果存在返回true
     */
    public static function hasPreset(name:String):Boolean {
        if (!initialized) {
            PresetManager.initialize();
        }
        return presets[name] !== undefined;
    }
    
    /**
     * 删除预设
     * @param name 预设名称
     * @return Boolean 如果成功删除返回true
     */
    public static function removePreset(name:String):Boolean {
        if (!PresetManager.hasPreset(name)) {
            return false;
        }
        
        delete presets[name];
        return true;
    }
    
    /**
     * 获取所有预设名称
     * @return Array 预设名称数组
     */
    public static function getAllPresetNames():Array {
        if (!initialized) {
            PresetManager.initialize();
        }
        
        var names:Array = [];
        for (var name in presets) {
            names.push(name);
        }
        return names;
    }
    
    /**
     * 创建基于现有预设的变体
     * @param baseName 基础预设名称
     * @param variantName 变体预设名称
     * @param modifications 要修改的属性
     */
    public static function createVariant(baseName:String, variantName:String, modifications:Object):Boolean {
        var basePreset:ElementPreset = PresetManager.getPreset(baseName);
        if (!basePreset) return false;
        
        var variantPreset:ElementPreset = ElementPreset.fromObject(modifications);
        basePreset.merge(variantPreset, true);
        
        PresetManager.registerPreset(variantName, basePreset);
        return true;
    }
    
    /**
     * 从外部文件加载预设配置（JSON格式）
     * @param filePath 配置文件路径
     */
    public static function loadPresetsFromFile(filePath:String):Void {
        // 这里可以实现从外部文件加载预设的逻辑
        // 由于AS2的限制，实际实现可能需要使用LoadVars或XML
        trace("加载预设文件: " + filePath);
    }
    
    /**
     * 保存当前预设到外部文件
     * @param filePath 保存文件路径
     */
    public static function savePresetsToFile(filePath:String):Void {
        // 这里可以实现保存预设到外部文件的逻辑
        trace("保存预设到文件: " + filePath);
    }
    
    /**
     * 清空所有预设
     */
    public static function clearAllPresets():Void {
        presets = {};
        initialized = false;
    }
    
    /**
     * 获取预设统计信息
     * @return Object 包含预设数量等统计信息
     */
    public static function getStatistics():Object {
        if (!initialized) {
            PresetManager.initialize();
        }
        
        var count:Number = 0;
        for (var name in presets) {
            count++;
        }
        
        return {
            totalPresets: count,
            presetNames: PresetManager.getAllPresetNames()
        };
    }
}