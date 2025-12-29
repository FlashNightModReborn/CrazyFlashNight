import org.flashNight.arki.unit.UnitComponent.Targetcache.*;
import org.flashNight.arki.component.StatHandler.*;
import org.flashNight.arki.unit.Action.Shoot.*;
import org.flashNight.arki.unit.UnitUtil;

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
     * 获得减伤率（格式化为百分比字符串）
     * 综合考虑防御减伤和系数减伤（damageTakenMultiplier）
     * @param unit 目标单位
     * @return String 减伤率（如 "45.3%"）
     */
    public static function getDamageReductionRate(unit:MovieClip):String {
        // 防御减伤系数
        var defenseDamageRatio:Number = DamageResistanceHandler.defenseDamageRatio(unit.防御力);

        // 承伤系数（霸体减伤等效果），默认为1
        var damageTakenMultiplier:Number = 1;
        if (unit.buffManager) {
            damageTakenMultiplier = unit.buffManager.getPropertyValue("damageTakenMultiplier");
            if (isNaN(damageTakenMultiplier) || damageTakenMultiplier <= 0) {
                damageTakenMultiplier = 1;
            }
        }

        // 综合伤害系数 = 防御减伤系数 × 承伤系数
        var totalDamageRatio:Number = defenseDamageRatio * damageTakenMultiplier;

        // 减伤率 = 1 - 综合伤害系数
        var reductionRate:Number = (1 - totalDamageRatio) * 100;
        return Math.floor(reductionRate * 10) / 10 + "%"; // 保留一位小数
    }

    /**
     * 获得基本防御
     * @param unit 目标单位
     * @return Number 基本防御力
     */
    public static function getBaseDefense(unit:MovieClip):Number {
        return Math.floor(unit.基本防御力);
    }

    /**
     * 获得装备防御（包含加成显示）
     * @param unit 目标单位
     * @return String/Number 装备防御（如 "100 + 20" 或 100）
     */
    public static function getEquipmentDefense(unit:MovieClip) {
        var baseDefense:Number = Math.floor(unit.装备防御力);
        var bonus:Number = unit.装备防御力加成 ? Math.floor(unit.装备防御力加成) : 0;

        if (bonus > 0) {
            return baseDefense + " + " + bonus;
        } else if (bonus < 0) {
            return baseDefense + " " + bonus;
        }
        return baseDefense;
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

    /**
     * 获得速度（带负重颜色标识）
     * @param unit 目标单位
     * @return String 速度字符串（可能包含HTML颜色标签）
     */
    public static function getMovementSpeed(unit:MovieClip):String {
        var speedValue:Number = Math.floor(unit.行走X速度 * 20) / 10;
        var speedText:String = speedValue + "m/s";

        // 根据负重情况添加颜色
        var baseEncumbrance:Number = UnitUtil.getBaseEncumbrance(unit.等级);
        var currentWeight:Number = unit.重量;
        var lightThreshold:Number = baseEncumbrance;
        var heavyThreshold:Number = baseEncumbrance * 2;

        // 判断负重状态并添加HTML颜色
        if (currentWeight < lightThreshold) {
            // 低负重增益 - 绿色
            return "<font color='#00FF00'>" + speedText + "</font>";
        } else if (currentWeight > heavyThreshold) {
            // 高负重拖累 - 红色
            return "<font color='#FF0000'>" + speedText + "</font>";
        } else {
            // 标准负重 - 白色（默认颜色）
            return speedText;
        }
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

    /**
     * 获得韧性上限
     * @param unit 目标单位
     * @return String 韧性上限（可能带k单位）
     */
    public static function getTenacityLimit(unit:MovieClip):String {
        var tenacityLimit:Number = unit.韧性系数 * unit.hp / DamageResistanceHandler.defenseDamageRatio(unit.防御力 / 1000);
        return formatLargeNumber(tenacityLimit);
    }

    /**
     * 获得踉跄韧性
     * @param unit 目标单位
     * @return String 踉跄韧性阈值（可能带k单位）
     */
    public static function getStaggerTenacity(unit:MovieClip):String {
        // 踉跄判定阈值 = 韧性上限 / 2 / 躲闪率
        var tenacityLimit:Number = unit.韧性系数 * unit.hp / DamageResistanceHandler.defenseDamageRatio(unit.防御力 / 1000);
        var staggerTenacity:Number = tenacityLimit / 2 / unit.躲闪率;
        return formatLargeNumber(staggerTenacity);
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
        var weaponPower:Number = ShootInitCore.calculateWeaponPower(unit, "手枪", unit.手枪属性.power);
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
        var weaponPower:Number = ShootInitCore.calculateWeaponPower(unit, "手枪2", unit.手枪2属性.power);
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
        var weaponPower:Number = ShootInitCore.calculateWeaponPower(unit, "长枪", unit.长枪属性.power);
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

    /**
     * 获得身高体重（合并显示）
     * @param unit 目标单位
     * @return String 身高体重字符串（如 "175cm/70kg"）
     */
    public static function getHeightAndWeight(unit:MovieClip):String {
        return _root.身高 + "cm/" + unit.体重 + "kg";
    }

    /**
     * 获得杀敌数
     * @param unit 目标单位（暂未使用，为未来扩展预留）
     * @return String 总杀敌数字符串
     */
    public static function getKillCount(unit:MovieClip):String {
        // 从全局击杀统计获取总数
        if (_root.killStats && _root.killStats.total != undefined) {
            return String(_root.killStats.total);
        }
        return "0";
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
     * 获得装备重量
     * @param unit 目标单位
     * @return String 装备重量字符串（如 "50kg"）
     */
    public static function getEquipmentWeight(unit:MovieClip):String {
        return unit.重量 + "kg";
    }

    /**
     * 获得经验值（格式化为带颜色的HTML字符串）
     * @return String 经验值和等级的HTML格式字符串
     */
    public static function getExperience():String {
        // 返回 "等级 + 经验值" 组合信息，节省UI空间
        // 等级显示为绿色，经验值显示为青色（与MP相同的颜色），方括号显示为浅灰色
        return "<font color='#8E9599'>[</font><font color='#00FF00'> Lv." + String(_root.等级) + "</font> <font color='#8E9599'>]</font>  ·  <font color='#8E9599'>[</font> <font color='#66FFFF'>" + String(_root.经验值) + "</font> <font color='#8E9599'>]</font>";
    }

    /**
     * 显示负重情况（在UI目标对象上设置负重显示）
     * @param target UI目标MovieClip
     * @param unit 目标单位
     */
    public static function displayEncumbranceStatus(target:MovieClip, unit:MovieClip):Void {
        var baseEncumbrance:Number = UnitUtil.getBaseEncumbrance(unit.等级);
        target.轻甲_中甲重量 = baseEncumbrance + "kg";
        target.中甲_重甲重量 = baseEncumbrance * 2 + "kg";
        target.重甲重量 = baseEncumbrance * 4 + "kg";
        var weightRatio:Number = unit.重量 / baseEncumbrance / 4;
        if (weightRatio < 0) weightRatio = 0;
        if (weightRatio > 1) weightRatio = 1;
        target.负重滑块._x = 20 + weightRatio * 240;
    }

    // ========================================
    // 主入口函数
    // ========================================

    /**
     * 获取人物信息（主入口函数）
     * 将所有计算好的信息填充到目标UI对象上
     *
     * @param target UI目标MovieClip，信息将被设置到该对象的属性上
     */
    public static function populatePlayerInfo(target:MovieClip):Void {
        var heroUnit:MovieClip = TargetCacheManager.findHero();

        // ========== 基础信息 ==========
        target.身高体重 = getHeightAndWeight(heroUnit);
        target.杀敌数 = getKillCount(heroUnit);
        target.称号 = getTitle(heroUnit);
        target.经验值 = getExperience();

        // ========== 负重系统 ==========
        target.装备重量 = getEquipmentWeight(heroUnit);
        displayEncumbranceStatus(target, heroUnit);

        // ========== 生命与能量 ==========
        target.最大HP = getMaxHP(heroUnit);
        target.最大MP = getMaxMP(heroUnit);
        target.内力 = getInnerPower(heroUnit);

        // ========== 魔法抗性 ==========
        target.能量抗性 = getEnergyResistance(heroUnit);
        target.热抗性 = getHeatResistance(heroUnit);
        target.蚀抗性 = getCorrosionResistance(heroUnit);
        target.毒抗性 = getPoisonResistance(heroUnit);
        target.冷抗性 = getColdResistance(heroUnit);
        target.电抗性 = getLightningResistance(heroUnit);
        target.波抗性 = getWaveResistance(heroUnit);
        target.冲抗性 = getImpactResistance(heroUnit);

        // ========== 防御系统 ==========
        target.综合防御力 = getTotalDefense(heroUnit);
        target.基本防御 = getBaseDefense(heroUnit);
        target.装备防御 = getEquipmentDefense(heroUnit);
        target.减伤率 = getDamageReductionRate(heroUnit);

        // ========== 韧性系统 ==========
        target.韧性上限 = getTenacityLimit(heroUnit);
        target.踉跄韧性 = getStaggerTenacity(heroUnit);
        target.拆挡能力 = getGuardBreakAbility(heroUnit);
        target.坚稳能力 = getStabilityAbility(heroUnit);

        // ========== 闪避与命中 ==========
        target.命中力 = getAccuracy(heroUnit);
        target.闪避负荷 = getEvasionCost(heroUnit);
        target.懒闪避 = getLazyDodge(heroUnit);

        // ========== 硬直与移动 ==========
        target.速度 = getMovementSpeed(heroUnit);

        // ========== 伤害加成 ==========
        target.伤害加成 = getDamageBonus(heroUnit);
        target.空手加成 = getUnarmedBonus(heroUnit);
        target.空手攻击力 = getUnarmedAttack(heroUnit); // 兼容旧UI
        target.冷兵加成 = getMeleeBonus(heroUnit);
        target.枪械加成 = getFirearmBonus(heroUnit);

        // ========== 武器威力 ==========
        target.空手威力 = getUnarmedPower(heroUnit);
        target.冷兵威力 = getMeleePower(heroUnit);
        target.主手威力 = getMainHandPower(heroUnit);
        target.副手威力 = getOffHandPower(heroUnit);
        target.长枪威力 = getRiflePower(heroUnit);
        target.手雷威力 = getGrenadePower(heroUnit);
    }
}
