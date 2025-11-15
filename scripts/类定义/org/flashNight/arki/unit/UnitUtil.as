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
     * @return Number 精英等级：0=普通其他, 1=精英, 2=首领
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

        
        if (!isNaN(resistTbl.精英)) {
            return 1; // 精英直接返回1
        }
        
        if (!isNaN(resistTbl.首领)) {
            return 2; // 首领直接返回2
        }
        
        return 0;
    }
    
    /**
     * 健壮地判断单位是否为敌人
     * 处理多种情况：true, "true", null, "null", undefined, "undefined" 等
     * @param unit 目标单位对象
     * @return Boolean true表示是敌人或中立单位，false表示是友方单位
     */
    public static function isEnemy(unit:MovieClip):Boolean {
        // 如果单位无效，视为敌人（保守处理）
        if (!unit) {
            return true;
        }
        
        var enemyFlag = unit.是否为敌人;
        
        // 明确为 false 或 "false" 时，表示友方
        if (enemyFlag === false || enemyFlag === "false") {
            return false;
        }
        
        // 明确为 true 或 "true" 时，表示敌人
        if (enemyFlag === true || enemyFlag === "true") {
            return true;
        }
        
        // null, "null", undefined, "undefined" 或其他值都视为中立/敌人
        // 这样处理是因为中立单位死亡后也应该计算经验值
        return true;
    }

    /**
     * 获取单位的类型标识键（用于统计、图鉴等系统）
     * 按优先级尝试不同字段，确保获得有意义的标识
     * @param unit 目标单位对象
     * @return String 单位类型标识，永不返回null
     */
    public static function getUnitTypeKey(unit:MovieClip):String {
        if (!unit) {
            return "未知单位";
        }

        // 优先级1：兵种字段（最准确的类型标识）
        if (unit.兵种 != undefined && unit.兵种 != "") {
            return String(unit.兵种);
        }

        // 优先级2：兵种名（WaveSpawner/StageInfo中使用）
        if (unit.兵种名 != undefined && unit.兵种名 != "") {
            return String(unit.兵种名);
        }

        // 优先级3：名字字段（备用标识）
        if (unit.名字 != undefined && unit.名字 != "") {
            return String(unit.名字);
        }

        // 优先级4：实例名（最后的退化方案）
        // 注意：实例名可能包含数字后缀如"僵尸123"
        return String(unit._name);
    }
}