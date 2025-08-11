// 文件路径：org/flashNight/arki/unit/UnitUtil.as
/**
 * 单位工具类
 * 提供单位相关的通用计算方法
 */
class org.flashNight.arki.unit.UnitUtil {
    
    /** 标准身高基准值 */
    public static var STANDARD_HEIGHT:Number = 175;
    
    /** 默认中心高度 */
    public static var DEFAULT_CENTER_HEIGHT:Number = 75;
    
    /** 倒地状态中心高度 */
    public static var PRONE_CENTER_HEIGHT:Number = 35;
    
    /**
     * 计算单位中心垂直偏移量
     * @param unit 目标单位对象
     * @return Number 中心垂直偏移量
     */
    public static function calculateCenterOffset(unit:MovieClip):Number {
        // 如果单位无效，返回默认值
        if (!unit) {
            return DEFAULT_CENTER_HEIGHT;
        }
        
        // 计算身高系数
        var coefficient:Number = 1.0;
        if (unit.身高 != undefined) {
            coefficient = unit.身高 / STANDARD_HEIGHT;
        }
        
        // 如果单位定义了中心高度，使用该值乘以身高系数
        if (unit.中心高度 != undefined) {
            return unit.中心高度 * coefficient;
        }
        
        // 根据单位状态返回不同的默认值
        if (unit.状态 == "倒地") {
            return PRONE_CENTER_HEIGHT;
        }
        
        return DEFAULT_CENTER_HEIGHT;
    }
    
    /**
     * 计算单位瞄准点
     * @param unit 目标单位对象
     * @return Object 包含x, y坐标的对象
     */
    public static function getAimPoint(unit:MovieClip):Object {
        if (!unit) {
            return null;
        }
        
        var yOffset:Number = calculateCenterOffset(unit);
        
        return {
            x: unit._x,
            y: unit._y - yOffset
        };
    }
    
    /**
     * 计算身高百分比
     * @param heightCM 身高厘米数
     * @return Number 相对于标准身高(175cm)的百分比值
     */
    public static function getHeightPercentage(heightCM:Number):Number {
        return (heightCM * 100 / STANDARD_HEIGHT) | 0;
    }
    
    /**
     * 判定单位的精英等级
     * @param unit 目标单位对象
     * @return Number 精英等级：-1=凡俗, 0=普通, 1=精英, 2=首领
     */
    public static function getEliteLevel(unit:MovieClip):Number {
        // 如果单位无效，返回0（普通）
        if (!unit) {
            return 0;
        }
        
        // 获取魔法抗性表
        var resistTbl:Object = unit.魔法抗性;
        if (!resistTbl) {
            return 0;
        }
        
        var level:Number = 0;
        
        // 检查各种精英标签，取最高值
        if (resistTbl.凡俗 != undefined && resistTbl.凡俗 > 0) {
            level = Math.max(level, -1);
        }
        
        if (resistTbl.精英 != undefined && resistTbl.精英 > 0) {
            level = Math.max(level, 1);
        }
        
        if (resistTbl.首领 != undefined && resistTbl.首领 > 0) {
            level = Math.max(level, 2);
        }
        
        return level;
    }
}