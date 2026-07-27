import org.flashNight.arki.unit.UnitComponent.Targetcache.*;
import org.flashNight.arki.component.StatHandler.*;
import org.flashNight.arki.unit.Action.Shoot.*;
import org.flashNight.arki.unit.UnitUtil;
import org.flashNight.arki.bullet.BulletComponent.Type.BulletTypeUtil;
import org.flashNight.arki.unit.UnitAI.combat.WeaponDpsEstimator;
import org.flashNight.arki.unit.UnitAI.core.AIEnvironment;

/**
 * 玩家信息提供者类
 *
 * 职责：
 * - 提供玩家单位的各类属性计算和格式化功能
 * - 为UI层提供统一的数据接口
 * - 封装复杂的计算逻辑（防御、韧性、威力等）
 *
 * 使用场景：
 * - 个人信息界面
 * - 角色详细信息面板
 * - 单位对比系统
 *
 */
class org.flashNight.arki.unit.PlayerInfoProvider {

    // ========================================
    // 防御系统
    // ========================================

    /**
     * 获得综合防御力（取整）
     * @param unit 目标单位
     * @return Number 综合防御力数值（取整后）
     */
    public static function getTotalDefense(unit:MovieClip):Number {
        return Math.floor(unit.防御力);
    }

    /**
     * 获得减伤率原始百分比值（保留一位小数）。
     * 综合考虑防御减伤和系数减伤（damageTakenMultiplier）。
     */
    public static function getDamageReductionValue(unit:MovieClip):Number {
        // 防御减伤系数
        var defenseDamageRatio:Number = DamageResistanceHandler.defenseDamageRatio(unit.防御力);

        // 承伤系数（霸体减伤等效果），默认为1
        var damageTakenMultiplier:Number = unit.damageTakenMultiplier;
        if (isNaN(damageTakenMultiplier) || damageTakenMultiplier <= 0) {
            damageTakenMultiplier = 1;
        }

        // 综合伤害系数 = 防御减伤系数 × 承伤系数
        var totalDamageRatio:Number = defenseDamageRatio * damageTakenMultiplier;

        // 减伤率 = 1 - 综合伤害系数
        var reductionRate:Number = (1 - totalDamageRatio) * 100;
        return Math.floor(reductionRate * 10) / 10;
    }

    /** 获得 legacy 百分比字符串（如 "45.3%"）。 */
    public static function getDamageReductionRate(unit:MovieClip):String {
        return getDamageReductionValue(unit) + "%";
    }

    /**
     * 获得基本防御
     * @param unit 目标单位
     * @return Number 基本防御力
     */
    public static function getBaseDefense(unit:MovieClip):Number {
        return Math.floor(unit.基本防御力);
    }

    /** 获得装备防御的原始基础值。 */
    public static function getEquipmentDefenseBase(unit:MovieClip):Number {
        return Math.floor(unit.装备防御力);
    }

    /** 获得装备防御的原始加成值。 */
    public static function getEquipmentDefenseBonus(unit:MovieClip):Number {
        return unit.装备防御力加成 ? Math.floor(unit.装备防御力加成) : 0;
    }

    /** 获得 legacy 装备防御显示（如 "100 + 20" 或 100）。 */
    public static function getEquipmentDefense(unit:MovieClip) {
        return formatEquipmentDefenseValues(
            getEquipmentDefenseBase(unit), getEquipmentDefenseBonus(unit));
    }

    // ========================================
    // 生命与能量
    // ========================================

    /**
     * 获得最大HP
     * @param unit 目标单位
     * @return Number 最大生命值
     */
    public static function getMaxHP(unit:MovieClip):Number {
        return unit.hp满血值;
    }

    /**
     * 获得最大MP
     * @param unit 目标单位
     * @return Number 最大魔法值
     */
    public static function getMaxMP(unit:MovieClip):Number {
        return unit.mp满血值;
    }

    /**
     * 获得内力
     * @param unit 目标单位
     * @return Number 内力数值
     */
    public static function getInnerPower(unit:MovieClip):Number {
        return unit.内力;
    }

    // ========================================
    // 基础属性
    // ========================================

    /**
     * 获得空手攻击力
     * @param unit 目标单位
     * @return Number 空手攻击力
     */
    public static function getUnarmedAttack(unit:MovieClip):Number {
        return unit.空手攻击力;
    }

    /**
     * 获得命中力
     * @param unit 目标单位
     * @return Number 命中力数值
     */
    public static function getAccuracy(unit:MovieClip):Number {
        return Math.floor(unit.命中率 * 10);
    }

    /** 获得速度原始值（单位 m/s，保留一位小数）。 */
    public static function getMovementSpeedValue(unit:MovieClip):Number {
        return Math.floor(unit.行走X速度 * 20) / 10;
    }

    /** 获得只含领域语义、不含颜色的负重状态。 */
    public static function getEncumbranceState(unit:MovieClip):String {
        var currentWeight:Number = unit.重量;
        var lightThreshold:Number = getBaseEncumbranceValue(unit);
        var heavyThreshold:Number = getMediumHeavyEncumbranceValue(unit);

        if (currentWeight < lightThreshold) return "light";
        if (currentWeight > heavyThreshold) return "heavy";
        return "normal";
    }

    /** 获得带负重颜色标识的 legacy 速度字符串。 */
    public static function getMovementSpeed(unit:MovieClip):String {
        return formatMovementSpeedValues(
            getMovementSpeedValue(unit), getEncumbranceState(unit));
    }

    // ========================================
    // 魔法抗性
    // ========================================

    /**
     * 获得能量抗性
     * @param unit 目标单位
     * @return Number 能量抗性数值
     */
    public static function getEnergyResistance(unit:MovieClip):Number {
        var baseResist:Number = unit.魔法抗性["基础"];
        if (isNaN(baseResist)) baseResist = 10 + (unit.等级 >> 1);
        return Math.floor(baseResist);
    }

    /**
     * 获得热抗性
     * @param unit 目标单位
     * @return Number 热抗性数值
     */
    public static function getHeatResistance(unit:MovieClip):Number {
        var heatResist:Number = unit.魔法抗性["热"];
        if (isNaN(heatResist)) heatResist = 10 + (unit.等级 >> 1);
        return Math.floor(heatResist);
    }

    /**
     * 获得蚀抗性
     * @param unit 目标单位
     * @return Number 蚀抗性数值
     */
    public static function getCorrosionResistance(unit:MovieClip):Number {
        var corrosionResist:Number = unit.魔法抗性["蚀"];
        if (isNaN(corrosionResist)) corrosionResist = 10 + (unit.等级 >> 1);
        return Math.floor(corrosionResist);
    }

    /**
     * 获得毒抗性
     * @param unit 目标单位
     * @return Number 毒抗性数值
     */
    public static function getPoisonResistance(unit:MovieClip):Number {
        var poisonResist:Number = unit.魔法抗性["毒"];
        if (isNaN(poisonResist)) poisonResist = 10 + (unit.等级 >> 1);
        return Math.floor(poisonResist);
    }

    /**
     * 获得冷抗性
     * @param unit 目标单位
     * @return Number 冷抗性数值
     */
    public static function getColdResistance(unit:MovieClip):Number {
        var coldResist:Number = unit.魔法抗性["冷"];
        if (isNaN(coldResist)) coldResist = 10 + (unit.等级 >> 1);
        return Math.floor(coldResist);
    }

    /**
     * 获得电抗性
     * @param unit 目标单位
     * @return Number 电抗性数值
     */
    public static function getLightningResistance(unit:MovieClip):Number {
        var lightningResist:Number = unit.魔法抗性["电"];
        if (isNaN(lightningResist)) lightningResist = 10 + (unit.等级 >> 1);
        return Math.floor(lightningResist);
    }

    /**
     * 获得波抗性
     * @param unit 目标单位
     * @return Number 波抗性数值
     */
    public static function getWaveResistance(unit:MovieClip):Number {
        var waveResist:Number = unit.魔法抗性["波"];
        if (isNaN(waveResist)) waveResist = 10 + (unit.等级 >> 1);
        return Math.floor(waveResist);
    }

    /**
     * 获得冲抗性
     * @param unit 目标单位
     * @return Number 冲抗性数值
     */
    public static function getImpactResistance(unit:MovieClip):Number {
        var impactResist:Number = unit.魔法抗性["冲"];
        if (isNaN(impactResist)) impactResist = 10 + (unit.等级 >> 1);
        return Math.floor(impactResist);
    }

    // ========================================
    // 韧性系统
    // ========================================

    /**
     * 格式化数值（大数值转换为k单位）
     * @param value 要格式化的数值
     * @return String 格式化后的字符串（如 "123.4k"）
     */
    public static function formatLargeNumber(value:Number):String {
        // 当数值 >= 100000 (6位数)时，转换为k单位显示
        if (value >= 100000) {
            var kValue:Number = value / 1000;
            return Math.floor(kValue * 10) / 10 + "k"; // 保留一位小数
        }
        return String(Math.floor(value)); // 修复：转换为字符串类型
    }

    /** 获得未经 k 单位格式化的韧性上限。 */
    public static function getTenacityLimitValue(unit:MovieClip):Number {
        return unit.韧性系数 * unit.hp
            / DamageResistanceHandler.defenseDamageRatio(unit.防御力 / 1000);
    }

    public static function getTenacityLimit(unit:MovieClip):String {
        return formatLargeNumber(getTenacityLimitValue(unit));
    }

    /** 获得未经 k 单位格式化的踉跄韧性。 */
    public static function getStaggerTenacityValue(unit:MovieClip):Number {
        // 踉跄判定阈值 = 韧性上限 / 2 / 躲闪率
        return getTenacityLimitValue(unit) / 2 / unit.躲闪率;
    }

    public static function getStaggerTenacity(unit:MovieClip):String {
        return formatLargeNumber(getStaggerTenacityValue(unit));
    }

    /**
     * 获得拆挡能力
     * @param unit 目标单位
     * @return Number 拆挡能力数值
     */
    public static function getGuardBreakAbility(unit:MovieClip):Number {
        return Math.floor(50 / unit.躲闪率);
    }

    /**
     * 获得坚稳能力
     * @param unit 目标单位
     * @return Number 坚稳能力数值
     */
    public static function getStabilityAbility(unit:MovieClip):Number {
        return Math.floor(100 * unit.韧性系数);
    }

    // ========================================
    // 闪避系统
    // ========================================

    /**
     * 获得闪避负荷
     * @param unit 目标单位
     * @return Number 闪避负荷数值
     */
    public static function getEvasionCost(unit:MovieClip):Number {
        return Math.floor(unit.躲闪率 * 10);
    }

    /**
     * 获得懒闪避
     * @param unit 目标单位
     * @return Number 懒闪避百分比值
     */
    public static function getLazyDodge(unit:MovieClip):Number {
        // 懒闪避值，通常是一个系数
        var lazyDodgeValue:Number = unit.懒闪避 ? unit.懒闪避 : 0;
        return Math.floor(lazyDodgeValue * 100);
    }

    // ========================================
    // 伤害加成
    // ========================================

    /**
     * 获得伤害加成
     * @param unit 目标单位
     * @return Number 伤害加成数值
     */
    public static function getDamageBonus(unit:MovieClip):Number {
        var damageBonus:Number = unit.伤害加成 ? unit.伤害加成 : 0;
        return Math.floor(damageBonus);
    }

    // ========================================
    // 武器威力
    // ========================================

    /**
     * 获得空手威力
     * @param unit 目标单位
     * @return Number 空手威力（包含攻击力+伤害加成+毒伤害）
     */
    public static function getUnarmedPower(unit:MovieClip):Number {
        // 空手威力 = 空手攻击力 + 伤害加成 + 毒伤害
        var unarmedAttack:Number = unit.空手攻击力 ? unit.空手攻击力 : 0;
        var damageBonus:Number = unit.伤害加成 ? unit.伤害加成 : 0;

        // 计算毒伤害：max(基础毒 + 空手毒, 淬毒)
        var equipPoison:Number = (unit.基础毒 ? unit.基础毒 : 0) + (unit.空手毒 ? unit.空手毒 : 0);
        var poisonDamage:Number = Math.max(equipPoison, unit.淬毒 ? unit.淬毒 : 0);

        return Math.floor(unarmedAttack + damageBonus + poisonDamage);
    }

    /**
     * 获得冷兵威力
     * @param unit 目标单位
     * @return Number 冷兵器威力（包含刀威力+伤害加成+毒伤害）
     */
    public static function getMeleePower(unit:MovieClip):Number {
        // 冷兵威力 = 刀属性.power + 伤害加成 + 毒伤害
        if (!unit.刀属性 || !unit.刀属性.power) return 0;
        var bladePower:Number = unit.刀属性.power;
        var damageBonus:Number = unit.伤害加成 ? unit.伤害加成 : 0;

        // 计算毒伤害：max(基础毒 + 兵器毒, 淬毒)
        var equipPoison:Number = (unit.基础毒 ? unit.基础毒 : 0) + (unit.兵器毒 ? unit.兵器毒 : 0);
        var poisonDamage:Number = Math.max(equipPoison, unit.淬毒 ? unit.淬毒 : 0);

        return Math.floor(bladePower + damageBonus + poisonDamage);
    }

    /**
     * 获得主手威力
     * @param unit 目标单位
     * @return Number 主手武器威力（包含计算威力+伤害加成+毒伤害）
     */
    public static function getMainHandPower(unit:MovieClip):Number {
        // 主手威力 = [ShootInitCore.calculateWeaponPower] + 伤害加成 + 毒伤害
        if (!unit.手枪属性 || !unit.手枪属性.power) return 0;

        // 使用ShootInitCore的统一计算函数，确保与实际战斗逻辑一致
        var isRay:Boolean = BulletTypeUtil.isRay(unit.手枪属性.bullet);
        var weaponPower:Number = ShootInitCore.calculateWeaponPower(unit, "手枪", unit.手枪属性.power, isRay);
        var damageBonus:Number = unit.伤害加成 ? unit.伤害加成 : 0;

        // 计算毒伤害：max(基础毒 + 手枪毒, 淬毒)
        var equipPoison:Number = (unit.基础毒 ? unit.基础毒 : 0) + (unit.手枪毒 ? unit.手枪毒 : 0);
        var poisonDamage:Number = Math.max(equipPoison, unit.淬毒 ? unit.淬毒 : 0);

        return Math.floor(weaponPower + damageBonus + poisonDamage);
    }

    /**
     * 获得副手威力
     * @param unit 目标单位
     * @return Number 副手武器威力（包含计算威力+伤害加成+毒伤害）
     */
    public static function getOffHandPower(unit:MovieClip):Number {
        // 副手威力 = [ShootInitCore.calculateWeaponPower] + 伤害加成 + 毒伤害
        if (!unit.手枪2属性 || !unit.手枪2属性.power) return 0;

        // 使用ShootInitCore的统一计算函数，确保与实际战斗逻辑一致
        var isRay:Boolean = BulletTypeUtil.isRay(unit.手枪2属性.bullet);
        var weaponPower:Number = ShootInitCore.calculateWeaponPower(unit, "手枪2", unit.手枪2属性.power, isRay);
        var damageBonus:Number = unit.伤害加成 ? unit.伤害加成 : 0;

        // 计算毒伤害：max(基础毒 + 手枪2毒, 淬毒)
        var equipPoison:Number = (unit.基础毒 ? unit.基础毒 : 0) + (unit.手枪2毒 ? unit.手枪2毒 : 0);
        var poisonDamage:Number = Math.max(equipPoison, unit.淬毒 ? unit.淬毒 : 0);

        return Math.floor(weaponPower + damageBonus + poisonDamage);
    }

    /**
     * 获得长枪威力
     * @param unit 目标单位
     * @return Number 长枪威力（包含计算威力+伤害加成+毒伤害）
     */
    public static function getRiflePower(unit:MovieClip):Number {
        // 长枪威力 = [ShootInitCore.calculateWeaponPower] + 伤害加成 + 毒伤害
        if (!unit.长枪属性 || !unit.长枪属性.power) return 0;

        // 使用ShootInitCore的统一计算函数，确保与实际战斗逻辑一致
        var isRay:Boolean = BulletTypeUtil.isRay(unit.长枪属性.bullet);
        var weaponPower:Number = ShootInitCore.calculateWeaponPower(unit, "长枪", unit.长枪属性.power, isRay);
        var damageBonus:Number = unit.伤害加成 ? unit.伤害加成 : 0;

        // 计算毒伤害：max(基础毒 + 长枪毒, 淬毒)
        var equipPoison:Number = (unit.基础毒 ? unit.基础毒 : 0) + (unit.长枪毒 ? unit.长枪毒 : 0);
        var poisonDamage:Number = Math.max(equipPoison, unit.淬毒 ? unit.淬毒 : 0);

        return Math.floor(weaponPower + damageBonus + poisonDamage);
    }

    /**
     * 获得手雷威力
     * @param unit 目标单位
     * @return Number 手雷威力（包含手雷威力+伤害加成+毒伤害）
     */
    public static function getGrenadePower(unit:MovieClip):Number {
        // 手雷威力 = 手雷属性.power + 伤害加成 + 毒伤害
        if (!unit.手雷属性 || !unit.手雷属性.power) return 0;
        var grenadePower:Number = unit.手雷属性.power;
        var damageBonus:Number = unit.伤害加成 ? unit.伤害加成 : 0;

        // 计算毒伤害：max(基础毒 + 手雷毒, 淬毒)
        var equipPoison:Number = (unit.基础毒 ? unit.基础毒 : 0) + (unit.手雷毒 ? unit.手雷毒 : 0);
        var poisonDamage:Number = Math.max(equipPoison, unit.淬毒 ? unit.淬毒 : 0);

        return Math.floor(grenadePower + damageBonus + poisonDamage);
    }

    /**
     * 获得空手加成
     * @param unit 目标单位
     * @return Number 空手攻击力加成
     */
    public static function getUnarmedBonus(unit:MovieClip):Number {
        // 空手加成 = (当前空手攻击力 - 基础空手攻击力)
        // 基础空手攻击力 = 根据等级计算的基准值
        var baseUnarmedAttack:Number = _root.根据等级计算值(unit.空手攻击力_min, unit.空手攻击力_max, unit.等级);
        var bonus:Number = unit.空手攻击力 - baseUnarmedAttack;
        // _root.发布消息("计算空手加成：当前 " + unit.空手攻击力 + " - 基础 " + baseUnarmedAttack + " = 加成 " + bonus);
        // _root.发布消息(unit.buffManager.toString());
        return Math.floor(bonus);
    }

    /**
     * 获得冷兵加成
     * @param unit 目标单位
     * @return Number 冷兵器锋利度加成
     */
    public static function getMeleeBonus(unit:MovieClip):Number {
        var value:Number = unit.装备刀锋利度加成 ? unit.装备刀锋利度加成 : 0;
        return value;
    }

    /**
     * 获得枪械加成
     * @param unit 目标单位
     * @return Number 枪械威力加成
     */
    public static function getFirearmBonus(unit:MovieClip):Number {
        var value:Number = unit.装备枪械威力加成 ? unit.装备枪械威力加成 : 0;
        return value;
    }

    // ========================================
    // 角色信息
    // ========================================

    /** 获得身高原始值。 */
    public static function getHeightValue(unit:MovieClip):Number {
        return Number(_root.身高);
    }

    /** 获得体重原始值。 */
    public static function getBodyWeightValue(unit:MovieClip):Number {
        return Number(unit.体重);
    }

    /** 获得 legacy 身高体重字符串（如 "175cm/70kg"）。 */
    public static function getHeightAndWeight(unit:MovieClip):String {
        return getHeightValue(unit) + "cm/" + getBodyWeightValue(unit) + "kg";
    }

    /**
     * 获得杀敌数
     * @param unit 目标单位（暂未使用，为未来扩展预留）
     * @return String 总杀敌数字符串
     */
    public static function getKillCountValue(unit:MovieClip) {
        // 从全局击杀统计获取总数
        if (_root.killStats && _root.killStats.total != undefined) {
            return _root.killStats.total;
        }
        return 0;
    }

    public static function getKillCount(unit:MovieClip):String {
        return String(getKillCountValue(unit));
    }

    /**
     * 获得称号
     * @param unit 目标单位
     * @return String 称号字符串
     */
    public static function getTitle(unit:MovieClip):String {
        return unit.称号;
    }

    /**
     * 将现役称号的受限 font 子集投成纯文本 + 净化 spans。
     * 不认识、嵌套或未闭合的标签整体降为纯文本，绝不透传原始 HTML。
     */
    public static function getTitleProjection(unit:MovieClip):Object {
        var title = getTitle(unit);
        return parseTitleProjection(
            title == null || title == undefined ? "" : String(title));
    }

    private static function parseTitleProjection(input:String):Object {
        var source:String = input == null ? "" : String(input);
        var spans:Array = [];
        var cursor:Number = 0;
        var style:Object = null;

        while (cursor < source.length) {
            var tagStart:Number = source.indexOf("<", cursor);
            if (tagStart < 0) {
                appendTitleSpan(spans, source.substring(cursor), style);
                cursor = source.length;
                break;
            }

            appendTitleSpan(
                spans, source.substring(cursor, tagStart), style);
            var tagEnd:Number = source.indexOf(">", tagStart + 1);
            if (tagEnd < 0) return plainTitleProjection(source);

            var tagBody:String =
                trimAsciiWhitespace(source.substring(tagStart + 1, tagEnd));
            var lowerTag:String = tagBody.toLowerCase();
            if (lowerTag == "/font") {
                if (style == null) return plainTitleProjection(source);
                style = null;
            } else if (lowerTag.substring(0, 4) == "font"
                       && lowerTag.length > 4
                       && isAsciiWhitespace(lowerTag.charCodeAt(4))) {
                if (style != null) return plainTitleProjection(source);
                style = parseFontAttributes(tagBody.substring(4));
                if (style == null) return plainTitleProjection(source);
            } else {
                return plainTitleProjection(source);
            }
            cursor = tagEnd + 1;
        }

        if (style != null) return plainTitleProjection(source);
        return {text:joinTitleSpanText(spans), spans:spans};
    }

    private static function parseFontAttributes(source:String):Object {
        var result:Object = {};
        var hasColor:Boolean = false;
        var hasSize:Boolean = false;
        var cursor:Number = 0;

        while (cursor < source.length) {
            while (cursor < source.length
                   && isAsciiWhitespace(source.charCodeAt(cursor))) {
                cursor++;
            }
            if (cursor >= source.length) break;

            var nameStart:Number = cursor;
            while (cursor < source.length) {
                var nameCode:Number = source.charCodeAt(cursor);
                if ((nameCode >= 65 && nameCode <= 90)
                    || (nameCode >= 97 && nameCode <= 122)) {
                    cursor++;
                } else {
                    break;
                }
            }
            if (cursor == nameStart) return null;
            var name:String =
                source.substring(nameStart, cursor).toLowerCase();

            while (cursor < source.length
                   && isAsciiWhitespace(source.charCodeAt(cursor))) {
                cursor++;
            }
            if (source.charAt(cursor) != "=") return null;
            cursor++;
            while (cursor < source.length
                   && isAsciiWhitespace(source.charCodeAt(cursor))) {
                cursor++;
            }

            var quote:String = source.charAt(cursor);
            if (quote != "'" && quote != "\"") return null;
            cursor++;
            var valueEnd:Number = source.indexOf(quote, cursor);
            if (valueEnd < 0) return null;
            var value:String = source.substring(cursor, valueEnd);
            cursor = valueEnd + 1;

            if (name == "color" && !hasColor && isSafeTitleColor(value)) {
                result.color = value.toUpperCase();
                hasColor = true;
            } else if (name == "size" && !hasSize
                       && isSafeTitleSize(value)) {
                result.size = Number(value);
                hasSize = true;
            } else {
                return null;
            }
        }

        return hasColor || hasSize ? result : null;
    }

    private static function isSafeTitleColor(value:String):Boolean {
        if (value.length != 7 || value.charAt(0) != "#") return false;
        for (var i:Number = 1; i < 7; i++) {
            var code:Number = value.charCodeAt(i);
            var isHex:Boolean = (code >= 48 && code <= 57)
                || (code >= 65 && code <= 70)
                || (code >= 97 && code <= 102);
            if (!isHex) return false;
        }
        return true;
    }

    private static function isSafeTitleSize(value:String):Boolean {
        if (value.length == 0) return false;
        for (var i:Number = 0; i < value.length; i++) {
            var code:Number = value.charCodeAt(i);
            if (code < 48 || code > 57) return false;
        }
        var size:Number = Number(value);
        return size >= 1 && size <= 72 && Math.floor(size) == size;
    }

    private static function appendTitleSpan(spans:Array, text:String,
                                            style:Object):Void {
        if (text.length == 0) return;
        var color:String = style && style.color ? String(style.color) : null;
        var size:Number = style && style.size ? Number(style.size) : 0;
        var previous:Object =
            spans.length > 0 ? spans[spans.length - 1] : null;
        if (previous && String(previous.color || "") == String(color || "")
            && Number(previous.size || 0) == size) {
            previous.text += text;
            return;
        }

        var span:Object = {text:text};
        if (color != null) span.color = color;
        if (size > 0) span.size = size;
        spans.push(span);
    }

    private static function joinTitleSpanText(spans:Array):String {
        var parts:Array = [];
        for (var i:Number = 0; i < spans.length; i++) {
            parts.push(spans[i].text);
        }
        return parts.join("");
    }

    private static function plainTitleProjection(source:String):Object {
        var parts:Array = [];
        var cursor:Number = 0;
        while (cursor < source.length) {
            var tagStart:Number = source.indexOf("<", cursor);
            if (tagStart < 0) {
                parts.push(source.substring(cursor).split(">").join(""));
                break;
            }
            parts.push(
                source.substring(cursor, tagStart).split(">").join(""));
            var tagEnd:Number = source.indexOf(">", tagStart + 1);
            if (tagEnd < 0) {
                parts.push(source.substring(tagStart + 1).split(">").join(""));
                break;
            }
            cursor = tagEnd + 1;
        }
        var text:String = parts.join("");
        var spans:Array = text.length > 0 ? [{text:text}] : [];
        return {text:text, spans:spans};
    }

    private static function trimAsciiWhitespace(value:String):String {
        var start:Number = 0;
        var end:Number = value.length;
        while (start < end && isAsciiWhitespace(value.charCodeAt(start))) {
            start++;
        }
        while (end > start && isAsciiWhitespace(value.charCodeAt(end - 1))) {
            end--;
        }
        return value.substring(start, end);
    }

    private static function isAsciiWhitespace(code:Number):Boolean {
        return code == 32 || code == 9 || code == 10 || code == 13;
    }

    /** 获得装备重量原始值。 */
    public static function getEquipmentWeightValue(unit:MovieClip):Number {
        return Number(unit.重量);
    }

    /** 获得 legacy 装备重量字符串（如 "50kg"）。 */
    public static function getEquipmentWeight(unit:MovieClip):String {
        return getEquipmentWeightValue(unit) + "kg";
    }

    /** 获得等级原始值。 */
    public static function getLevelValue():Number {
        return Number(_root.等级);
    }

    /** 获得经验值原始值。 */
    public static function getExperienceValue():Number {
        return Number(_root.经验值);
    }

    private static function formatExperience(level:Number, experience:Number):String {
        // 返回 "等级 + 经验值" 组合信息，节省UI空间
        // 等级显示为绿色，经验值显示为青色（与MP相同的颜色），方括号显示为浅灰色
        return "<font color='#8E9599'>[</font><font color='#00FF00'> Lv." + String(level) + "</font> <font color='#8E9599'>]</font>  ·  <font color='#8E9599'>[</font> <font color='#66FFFF'>" + String(experience) + "</font> <font color='#8E9599'>]</font>";
    }

    /** 获得 legacy 等级/经验值 HTML 字符串。 */
    public static function getExperience():String {
        return formatExperience(getLevelValue(), getExperienceValue());
    }

    public static function getBaseEncumbranceValue(unit:MovieClip):Number {
        return UnitUtil.getBaseEncumbrance(unit.等级);
    }

    public static function getMediumHeavyEncumbranceValue(unit:MovieClip):Number {
        return getBaseEncumbranceValue(unit) * 2;
    }

    public static function getHeavyEncumbranceValue(unit:MovieClip):Number {
        return getBaseEncumbranceValue(unit) * 4;
    }

    public static function getEncumbranceRatio(unit:MovieClip):Number {
        var baseEncumbrance:Number = getBaseEncumbranceValue(unit);
        var weightRatio:Number =
            getEquipmentWeightValue(unit) / baseEncumbrance / 4;
        if (weightRatio < 0) weightRatio = 0;
        if (weightRatio > 1) weightRatio = 1;
        return weightRatio;
    }

    /**
     * 显示负重情况（在UI目标对象上设置负重显示）
     * @param target UI目标MovieClip
     * @param unit 目标单位
     */
    public static function displayEncumbranceStatus(target:MovieClip, unit:MovieClip):Void {
        var baseEncumbrance:Number = getBaseEncumbranceValue(unit);
        target.轻甲_中甲重量 = baseEncumbrance + "kg";
        target.中甲_重甲重量 = getMediumHeavyEncumbranceValue(unit) + "kg";
        target.重甲重量 = getHeavyEncumbranceValue(unit) + "kg";
        target.负重滑块._x = 20 + getEncumbranceRatio(unit) * 240;
    }

    // ========================================
    // 主入口函数
    // ========================================

    /**
     * 返回不含 MovieClip 字段名、HTML 或布局坐标的只读人物信息投影。
     * 每次调用都返回新对象；缺少 hero 或存在不可序列化数值时 fail-closed。
     */
    public static function getPlayerInfoSnapshot():Object {
        return org.flashNight.arki.unit.PlayerInfoSnapshotBuilder.build(
            TargetCacheManager.findHero());
    }

    private static function indexSnapshotValues(snapshot:Object):Object {
        var values:Object = {};
        var groups:Array = snapshot.groups;
        for (var i:Number = 0; i < groups.length; i++) {
            var rows:Array = groups[i].rows;
            for (var j:Number = 0; j < rows.length; j++) {
                var row:Object = rows[j];
                values[row.key] = row.value;
            }
        }
        return values;
    }

    private static function findSnapshotRow(snapshot:Object, key:String):Object {
        var groups:Array = snapshot.groups;
        for (var i:Number = 0; i < groups.length; i++) {
            var rows:Array = groups[i].rows;
            for (var j:Number = 0; j < rows.length; j++) {
                if (rows[j].key == key) return rows[j];
            }
        }
        return null;
    }

    private static function formatEquipmentDefenseValues(baseDefense:Number, bonus:Number) {
        if (bonus > 0) return baseDefense + " + " + bonus;
        if (bonus < 0) return baseDefense + " " + bonus;
        return baseDefense;
    }

    private static function formatMovementSpeedValues(speedValue:Number,
                                                       encumbranceState:String):String {
        var speedText:String = speedValue + "m/s";
        if (encumbranceState == "light") {
            return "<font color='#00FF00'>" + speedText + "</font>";
        }
        if (encumbranceState == "heavy") {
            return "<font color='#FF0000'>" + speedText + "</font>";
        }
        return speedText;
    }

    private static function formatTitleRow(row:Object):String {
        var plainText:String = row ? String(row.value) : "";
        if (!row || !(row.spans instanceof Array)) {
            return escapeLegacyHtmlText(plainText);
        }

        var output:Array = [];
        var joined:Array = [];
        for (var i:Number = 0; i < row.spans.length; i++) {
            var span:Object = row.spans[i];
            if (!span || typeof(span.text) != "string") {
                return escapeLegacyHtmlText(plainText);
            }
            var text:String = String(span.text);
            joined.push(text);
            var color:String =
                span.color == undefined ? null : String(span.color);
            var size:Number =
                span.size == undefined ? 0 : Number(span.size);
            if ((color != null && !isSafeTitleColor(color))
                || (span.size != undefined
                    && (!isSafeTitleSize(String(span.size))
                        || Math.floor(size) != size))) {
                return escapeLegacyHtmlText(plainText);
            }

            var escaped:String = escapeLegacyHtmlText(text);
            if (color == null && size == 0) {
                output.push(escaped);
            } else {
                var openTag:String = "<font";
                if (color != null) {
                    openTag += " color='" + color.toUpperCase() + "'";
                }
                if (size > 0) openTag += " size='" + size + "'";
                output.push(openTag + ">" + escaped + "</font>");
            }
        }
        if (joined.join("") != plainText) {
            return escapeLegacyHtmlText(plainText);
        }
        return output.join("");
    }

    private static function escapeLegacyHtmlText(value:String):String {
        var output:Array = [];
        for (var i:Number = 0; i < value.length; i++) {
            var ch:String = value.charAt(i);
            if (ch == "&") output.push("&amp;");
            else if (ch == "<") output.push("&lt;");
            else if (ch == ">") output.push("&gt;");
            else output.push(ch);
        }
        return output.join("");
    }

    /**
     * Legacy MovieClip renderer。赋值顺序与旧 populatePlayerInfo 保持一致；
     * 富文本与滑块坐标只在此适配层生成，不进入 snapshot。
     */
    private static function renderPlayerInfoSnapshot(target:MovieClip, snapshot:Object):Void {
        if (!target || !snapshot || snapshot.stateHealth != "ok") return;
        var values:Object = indexSnapshotValues(snapshot);

        // ========== 基础信息 ==========
        target.身高体重 = values.height + "cm/" + values.bodyWeight + "kg";
        target.杀敌数 = String(values.killCount);
        target.称号 = formatTitleRow(findSnapshotRow(snapshot, "title"));
        target.经验值 = formatExperience(values.level, values.experience);

        // ========== 负重系统 ==========
        target.装备重量 = values.equipmentWeight + "kg";
        target.轻甲_中甲重量 = values.lightMediumThreshold + "kg";
        target.中甲_重甲重量 = values.mediumHeavyThreshold + "kg";
        target.重甲重量 = values.heavyThreshold + "kg";
        target.负重滑块._x = 20 + values.weightRatio * 240;

        // ========== 生命与能量 ==========
        target.最大HP = values.maxHp;
        target.最大MP = values.maxMp;
        target.内力 = values.innerPower;

        // ========== 魔法抗性 ==========
        target.能量抗性 = values.energyResistance;
        target.热抗性 = values.heatResistance;
        target.蚀抗性 = values.corrosionResistance;
        target.毒抗性 = values.poisonResistance;
        target.冷抗性 = values.coldResistance;
        target.电抗性 = values.lightningResistance;
        target.波抗性 = values.waveResistance;
        target.冲抗性 = values.impactResistance;

        // ========== 防御系统 ==========
        target.综合防御力 = values.totalDefense;
        target.基本防御 = values.baseDefense;
        target.装备防御 = formatEquipmentDefenseValues(
            values.equipmentDefense, values.equipmentDefenseBonus);
        target.减伤率 = values.damageReduction + "%";

        // ========== 韧性系统 ==========
        target.韧性上限 = formatLargeNumber(values.tenacityLimit);
        target.踉跄韧性 = formatLargeNumber(values.staggerTenacity);
        target.拆挡能力 = values.guardBreakAbility;
        target.坚稳能力 = values.stabilityAbility;

        // ========== 闪避与命中 ==========
        target.命中力 = values.accuracy;
        target.闪避负荷 = values.evasionCost;
        target.懒闪避 = values.lazyDodge;

        // ========== 硬直与移动 ==========
        target.速度 = formatMovementSpeedValues(
            values.movementSpeed, values.encumbranceState);

        // ========== 伤害加成 ==========
        target.伤害加成 = values.damageBonus;
        target.空手加成 = values.unarmedBonus;
        target.空手攻击力 = values.unarmedAttack;
        target.冷兵加成 = values.meleeBonus;
        target.枪械加成 = values.firearmBonus;

        // ========== 武器威力 ==========
        target.空手威力 = values.unarmedPower;
        target.冷兵威力 = values.meleePower;
        target.主手威力 = values.mainHandPower;
        target.副手威力 = values.offHandPower;
        target.长枪威力 = values.riflePower;
        target.手雷威力 = values.grenadePower;
    }

    /**
     * 结构化 Web snapshot 对任一非法 row 继续 fail-closed；旧 MovieClip 则保持
     * 历史逐字段刷新语义，避免一个坏字段把整张现役个人信息页冻结。这里仍只调用
     * 既有 getter，不建立第二套人物属性公式；称号继续走受限 spans 净化。
     */
    private static function renderDegradedLegacyPlayerInfo(
        target:MovieClip, heroUnit:MovieClip):Void {
        if (!target || !heroUnit) return;
        var titleProjection:Object = getTitleProjection(heroUnit);

        target.身高体重 = getHeightAndWeight(heroUnit);
        target.杀敌数 = getKillCount(heroUnit);
        target.称号 = formatTitleRow({
            value:titleProjection.text,
            spans:titleProjection.spans
        });
        target.经验值 = getExperience();

        target.装备重量 = getEquipmentWeight(heroUnit);
        displayEncumbranceStatus(target, heroUnit);

        target.最大HP = getMaxHP(heroUnit);
        target.最大MP = getMaxMP(heroUnit);
        target.内力 = getInnerPower(heroUnit);

        target.能量抗性 = getEnergyResistance(heroUnit);
        target.热抗性 = getHeatResistance(heroUnit);
        target.蚀抗性 = getCorrosionResistance(heroUnit);
        target.毒抗性 = getPoisonResistance(heroUnit);
        target.冷抗性 = getColdResistance(heroUnit);
        target.电抗性 = getLightningResistance(heroUnit);
        target.波抗性 = getWaveResistance(heroUnit);
        target.冲抗性 = getImpactResistance(heroUnit);

        target.综合防御力 = getTotalDefense(heroUnit);
        target.基本防御 = getBaseDefense(heroUnit);
        target.装备防御 = getEquipmentDefense(heroUnit);
        target.减伤率 = getDamageReductionRate(heroUnit);

        target.韧性上限 = getTenacityLimit(heroUnit);
        target.踉跄韧性 = getStaggerTenacity(heroUnit);
        target.拆挡能力 = getGuardBreakAbility(heroUnit);
        target.坚稳能力 = getStabilityAbility(heroUnit);

        target.命中力 = getAccuracy(heroUnit);
        target.闪避负荷 = getEvasionCost(heroUnit);
        target.懒闪避 = getLazyDodge(heroUnit);
        target.速度 = getMovementSpeed(heroUnit);

        target.伤害加成 = getDamageBonus(heroUnit);
        target.空手加成 = getUnarmedBonus(heroUnit);
        target.空手攻击力 = getUnarmedAttack(heroUnit);
        target.冷兵加成 = getMeleeBonus(heroUnit);
        target.枪械加成 = getFirearmBonus(heroUnit);

        target.空手威力 = getUnarmedPower(heroUnit);
        target.冷兵威力 = getMeleePower(heroUnit);
        target.主手威力 = getMainHandPower(heroUnit);
        target.副手威力 = getOffHandPower(heroUnit);
        target.长枪威力 = getRiflePower(heroUnit);
        target.手雷威力 = getGrenadePower(heroUnit);
    }

    /**
     * 获取人物信息（主入口函数）
     * 将结构化 snapshot 适配到旧 UI MovieClip。
     *
     * @param target UI目标MovieClip，信息将被设置到该对象的属性上
     */
    public static function populatePlayerInfo(target:MovieClip):Void {
        var heroUnit:MovieClip = TargetCacheManager.findHero();
        var snapshot:Object =
            org.flashNight.arki.unit.PlayerInfoSnapshotBuilder.build(heroUnit);
        if (snapshot.stateHealth == "ok") {
            renderPlayerInfoSnapshot(target, snapshot);
            return;
        }
        var reason:String = snapshot.diagnostics instanceof Array
            && snapshot.diagnostics.length > 0
            ? String(snapshot.diagnostics[0]) : "";
        if (heroUnit && reason.indexOf("invalid_row:") == 0) {
            renderDegradedLegacyPlayerInfo(target, heroUnit);
        }
    }

    // ========================================
    // AI DPS 估算缓存（粗排名，目标无关，30 帧 TTL）
    // ========================================
    // 缓存挂在 unit.估算 上；装备变化 / 攻击模式切换 显式 invalidate
    // readOrComputeDps 用闭包 fn 延迟计算，避免重复调用 estimator

    public static function getUnarmedDPS(unit:MovieClip):Number {
        return readOrComputeDps(unit, "unarmed", function() {
            return WeaponDpsEstimator.unarmedComboDPS(unit);
        });
    }

    public static function getMeleeDPS(unit:MovieClip):Number {
        return readOrComputeDps(unit, "melee", function() {
            return WeaponDpsEstimator.meleeComboDPS(unit);
        });
    }

    public static function getGunDPS(unit:MovieClip, mode:String):Number {
        return readOrComputeDps(unit, "gun_" + mode, function() {
            return WeaponDpsEstimator.gunSustainedDPS(unit, mode);
        });
    }

    // 候选模式集的 DPS 中位数，用于 log-ratio 归一化基线。
    // 键带 modes 签名，避免不同候选集读到同一条陈旧中位数
    public static function getReferenceDPS(unit:MovieClip, modes:Array):Number {
        var sig:String = modes.join(",");
        return readOrComputeDps(unit, "ref_" + sig, function() {
            var arr:Array = [];
            for (var i:Number = 0; i < modes.length; i++) {
                var m:String = modes[i];
                var v:Number;
                if (m == "空手") v = WeaponDpsEstimator.unarmedComboDPS(unit);
                else if (m == "兵器") v = WeaponDpsEstimator.meleeComboDPS(unit);
                else v = WeaponDpsEstimator.gunSustainedDPS(unit, m);
                arr.push(v);
            }
            arr.sort(Array.NUMERIC);
            var mid:Number = arr[arr.length >> 1];
            return (mid > 0) ? mid : 1;
        });
    }

    public static function invalidateDpsCache(unit:MovieClip):Void {
        unit.估算 = null;
    }

    private static function readOrComputeDps(unit:MovieClip, key:String, fn:Function):Number {
        var bag:Object = unit.估算;
        if (bag == null) { bag = {}; unit.估算 = bag; }
        var now:Number = AIEnvironment.getFrame();
        var stampKey:String = "_stamp_" + key;
        var stamp:Number = bag[stampKey];
        if (bag[key] != null && stamp != null && (now - stamp) < 30) return bag[key];
        bag[key] = fn();
        bag[stampKey] = now;
        return bag[key];
    }
}
