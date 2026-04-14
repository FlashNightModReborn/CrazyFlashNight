import org.flashNight.arki.bullet.BulletComponent.Type.BulletTypeUtil;
import org.flashNight.arki.unit.UnitAI.combat.data.AttackAssetMeta;
import org.flashNight.arki.unit.Action.Shoot.ShootInitCore;

/**
 * WeaponDpsEstimator — 武器模式 sustained DPS 估算器
 *
 * 用途：为 AI 武器选择提供装备感知的 DPS 粗排名。
 *      替代原 WeaponEvaluator.WEAPON_POWER 静态表。
 *
 * 设计原则（plan v4）：
 *   - 目标无关：不感知 target.HP / actualScatter 精算
 *   - 满匣口径：sustained DPS = 打空弹匣 + normal 换弹
 *   - 主伤/毒分离：主伤走 damageTypeWeight，毒走 NANO_SCALE 独立通道
 *   - 跨模式毒：评估时合成 (基础毒 + 候选模式毒)，不读 self.毒
 *   - 兵器 subset 拆分：blade/direct × weaponOnly/wholeBullet/none 三种被动作用域
 *
 * 输出用途：Math.log(dps / refDps) / 2，压榨到 ±1 后乘 POWER_WEIGHT 作为模式评分偏置
 */
class org.flashNight.arki.unit.UnitAI.combat.WeaponDpsEstimator {

    // ═══════ 共用助手 ═══════

    private static function bonusPerBullet(self:MovieClip):Number {
        return self.伤害加成 | 0;
    }

    // 跨模式毒合成：基础毒 + 模式毒，再被 淬毒 夺权（若更大）
    // 依据：BulletInitializer.as:313-317,374 / 单位函数_fs:1162-1166
    private static function poisonFor(self:MovieClip, modePoisonField:String):Number {
        var base:Number = self.基础毒 | 0;
        var mode:Number = self[modePoisonField] | 0;
        var 淬毒:Number = self.淬毒 | 0;
        var weaponSum:Number = base + mode;
        return (淬毒 > weaponSum) ? 淬毒 : weaponSum;
    }

    // L2 统一 nano 缩放；不分 isNormal/isVertical 子分支
    private static function poisonEffective(self:MovieClip, modePoisonField:String):Number {
        return poisonFor(self, modePoisonField) * AttackAssetMeta.NANO_SCALE;
    }

    // actualScatter 封顶（plan v4 L2 近似）
    private static function scatterCap(split:Number):Number {
        return (split > 6) ? 6 : split;
    }

    // 主伤伤害类型权重（UniversalDamageHandle 链）；毒走 NanoToxicDamageHandle 链不乘此系数
    // 三级回退：空手/兵器 先读 {模式}伤害类型 → 再 基础伤害类型 → 最后 "物理"
    private static function dmgTypeMult(self:MovieClip, modePrefix:String):Number {
        var t:String = self[modePrefix + "伤害类型"];
        if (t == null || t == "") t = self.基础伤害类型;
        if (t == null || t == "") t = "物理";
        var w:Number = AttackAssetMeta.DAMAGE_TYPE_WEIGHT[t];
        return w ? w : 1.0;
    }

    private static function framesToSec(n:Number):Number {
        return n / 30;
    }

    // ═══════ 空手 DPS ═══════

    public static function unarmedComboDPS(self:MovieClip):Number {
        var meta:Object = AttackAssetMeta.getUnarmed(self.空手动作类型);

        // 拳脚攻击被动（整体乘法；巨拳系不吃）
        var kickLvl:Number = 0;
        var kick:Object = self.被动技能.拳脚攻击;
        if (kick && kick.启用) kickLvl = kick.等级 | 0;
        var kickMult:Number = meta.applyKickPassive ? (1 + kickLvl * 0.1) : 1;

        var mpBonus:Number = self.mp攻击加成 | 0;

        // 主伤 = 空手攻击力 × effHits × kickMult + (mp+伤害加成) × judgmentHitCount
        var weaponPart:Number = self.空手攻击力 * meta.effHits * kickMult;
        var mainFlatPerBullet:Number = mpBonus + bonusPerBullet(self);
        var mainFlatPart:Number = mainFlatPerBullet * meta.judgmentHitCount;

        // 毒独立通道：近战每个 bullet spawn 触发一次（MELEE/CHAIN 非 VERTICAL）
        var poisonPart:Number = poisonEffective(self, "空手毒") * meta.bulletSpawnCount;

        // 巨拳 outlier 只乘主伤，不放大毒
        var outlierMult:Number = 1;
        if (meta.outlierTag) {
            var om:Number = AttackAssetMeta.OUTLIER_MULT[meta.outlierTag];
            if (om) outlierMult = om;
        }

        var tSec:Number = framesToSec(meta.totalFrames);
        return (weaponPart + mainFlatPart) * outlierMult * dmgTypeMult(self, "空手") / tSec
             + poisonPart / tSec;
    }

    // ═══════ 兵器 DPS ═══════

    public static function meleeComboDPS(self:MovieClip):Number {
        var meta:Object = AttackAssetMeta.getMelee(self.兵器动作类型);

        var bladeLvl:Number = 0;
        var sk:Object = self.被动技能.刀剑攻击;
        if (sk && sk.启用) bladeLvl = sk.等级 | 0;
        var bladeCount:Number = self.刀_刀口数 || 1;
        var weaponPow:Number = (self.刀属性 && self.刀属性.power) ? self.刀属性.power : 0;
        var mpBonus:Number = self.mp攻击加成 | 0;

        var flatPerBullet:Number = mpBonus + bonusPerBullet(self);
        var poisonUnit:Number = poisonEffective(self, "兵器毒");
        var mainTotal:Number = 0;
        var poisonTotal:Number = 0;

        var subsets:Array = meta.subsets;
        for (var i:Number = 0; i < subsets.length; i++) {
            var s:Object = subsets[i];
            var weaponContrib:Number = weaponPow * s.effHitsWeapon;
            var unarmedContrib:Number = self.空手攻击力 * s.effHitsUnarmed;
            var perSubsetMain:Number;

            // 被动作用域分路：
            //   weaponOnly：子弹威力 += 刀.power × lvl × 0.075（每次判定加一次）
            //   wholeBullet：子弹威力 *= 1 + lvl × 0.075（整段乘法，含 unarmed 部分）
            //   none：无被动
            if (s.passiveScope == "wholeBullet") {
                perSubsetMain = (weaponContrib + unarmedContrib) * (1 + bladeLvl * 0.075);
            } else if (s.passiveScope == "weaponOnly") {
                perSubsetMain = weaponContrib + unarmedContrib
                              + weaponPow * bladeLvl * 0.075 * s.judgmentHitCount;
            } else {
                perSubsetMain = weaponContrib + unarmedContrib;
            }
            perSubsetMain += flatPerBullet * s.judgmentHitCount;

            // spawn 倍数：blade subset × bladeCount；direct subset 保持 1
            var spawnMult:Number = (s.kind == "blade") ? bladeCount : 1;
            mainTotal += perSubsetMain * spawnMult;
            poisonTotal += poisonUnit * s.bulletSpawnCount * spawnMult;
        }

        var tSec:Number = framesToSec(meta.totalFrames);
        return mainTotal * dmgTypeMult(self, "兵器") / tSec + poisonTotal / tSec;
    }

    // ═══════ 枪械 DPS ═══════

    public static function gunSustainedDPS(self:MovieClip, mode:String):Number {
        if (mode == "双枪") return dualGunDPS(self);

        var attrSrc:String = resolveAttrSrc(self, mode);
        if (attrSrc == null) return 0;
        var wd:Object = self[attrSrc + "属性"];
        if (wd == null || wd.power == null) return 0;

        var capacity:Number = self[attrSrc + "弹匣容量"] || wd.capacity || 30;
        var main:Number = gunMainPerShot(self, attrSrc);
        var poison:Number = gunPoisonPerShot(self, attrSrc);
        var interval_s:Number = wd.interval / 1000;
        var reload_s:Number = reloadSecondsFor(self, attrSrc);

        var denom:Number = capacity * interval_s + reload_s;
        if (denom <= 0) return 0;

        var mainDPS:Number = capacity * main * dmgTypeMult(self, attrSrc) / denom;
        var poisonDPS:Number = capacity * poison / denom;
        return mainDPS + poisonDPS;
    }

    public static function gunReloadSeconds(self:MovieClip, mode:String):Number {
        if (mode == "双枪") return dualReloadSeconds(self);

        var attrSrc:String = resolveAttrSrc(self, mode);
        if (attrSrc == null) return 0;
        var wd:Object = self[attrSrc + "属性"];
        if (wd == null) return 0;
        return reloadSecondsFor(self, attrSrc);
    }

    public static function gunBurstSeconds(self:MovieClip, mode:String):Number {
        if (mode == "双枪") {
            if (self.手枪 == null || self.手枪2 == null) return 0;
            var mInt_s:Number = (self.手枪属性.interval | 0) / 1000;
            var oInt_s:Number = (self.手枪2属性.interval | 0) / 1000;
            var mCap:Number = self.手枪弹匣容量 || self.手枪属性.capacity || 30;
            var oCap:Number = self.手枪2弹匣容量 || self.手枪2属性.capacity || 30;
            var mBurst_s:Number = mCap * mInt_s;
            var oBurst_s:Number = oCap * oInt_s;
            return (mBurst_s > oBurst_s) ? mBurst_s : oBurst_s;
        }

        var attrSrc:String = resolveAttrSrc(self, mode);
        if (attrSrc == null) return 0;
        var wd:Object = self[attrSrc + "属性"];
        if (wd == null) return 0;

        var capacity:Number = self[attrSrc + "弹匣容量"] || wd.capacity || 30;
        return capacity * ((wd.interval | 0) / 1000);
    }

    // 主伤每发（含 basePow + 伤害加成；不含毒）
    private static function gunMainPerShot(self:MovieClip, attrSrc:String):Number {
        var wd:Object = self[attrSrc + "属性"];
        var isRay:Boolean = BulletTypeUtil.isRay(wd.bullet);
        var basePow:Number = ShootInitCore.calculateWeaponPower(self, attrSrc, wd.power, isRay);
        var split:Number = wd.split || 1;
        var scatter:Number = scatterCap(split);
        return (basePow + bonusPerBullet(self)) * scatter;
    }

    // 毒每发（独立通道）
    // NanoToxicDamageHandle.as:103 —— 仅 VERTICAL 子弹按 actualScatter 放大；普通子弹一发只 1 次毒
    private static function gunPoisonPerShot(self:MovieClip, attrSrc:String):Number {
        var wd:Object = self[attrSrc + "属性"];
        var isVertical:Boolean = BulletTypeUtil.isVertical(wd.bullet);
        var scatter:Number = isVertical ? scatterCap(wd.split || 1) : 1;
        return poisonEffective(self, attrSrc + "毒") * scatter;
    }

    // "手枪" 候选：若只装 手枪2 则映射到 手枪2 属性（单位函数_fs:1128-1143）
    private static function resolveAttrSrc(self:MovieClip, mode:String):String {
        if (mode == "长枪") return self.长枪 ? "长枪" : null;
        if (mode == "手枪") {
            if (self.手枪) return "手枪";
            if (self.手枪2) return "手枪2";
            return null;
        }
        return null;
    }

    private static function dualGunDPS(self:MovieClip):Number {
        if (self.手枪 == null || self.手枪2 == null) return 0;
        var mMain:Number = gunMainPerShot(self, "手枪");
        var mPoi:Number  = gunPoisonPerShot(self, "手枪");
        var oMain:Number = gunMainPerShot(self, "手枪2");
        var oPoi:Number  = gunPoisonPerShot(self, "手枪2");
        var mInt_s:Number = (self.手枪属性.interval | 0) / 1000;
        var oInt_s:Number = (self.手枪2属性.interval | 0) / 1000;
        var mCap:Number = self.手枪弹匣容量 || self.手枪属性.capacity || 30;
        var oCap:Number = self.手枪2弹匣容量 || self.手枪2属性.capacity || 30;
        var mBurst_s:Number = mCap * mInt_s;
        var oBurst_s:Number = oCap * oInt_s;
        var burst_s:Number = (mBurst_s > oBurst_s) ? mBurst_s : oBurst_s;
        var denom:Number = burst_s + dualReloadSeconds(self);
        if (denom <= 0) return 0;

        // 主/副手各自乘伤害类型权重（避免混搭误权重）
        var mMainDPS:Number = mCap * mMain * dmgTypeMult(self, "手枪") / denom;
        var oMainDPS:Number = oCap * oMain * dmgTypeMult(self, "手枪2") / denom;
        var poiDPS:Number   = (mCap * mPoi + oCap * oPoi) / denom;
        return mMainDPS + oMainDPS + poiDPS;
    }

    // ═══════ 换弹时长（Σ ceil(seg × burden/100) + fixedTail）═══════

    private static function reloadSecondsFor(self:MovieClip, attrSrc:String):Number {
        var meta:Object = AttackAssetMeta.getReload(attrSrc);
        var burden:Number = 100 + ((self[attrSrc + "属性"].reloadPenalty) | 0);
        return computeReloadFrames(meta, burden) / 30;
    }

    private static function dualReloadSeconds(self:MovieClip):Number {
        var mMeta:Object = AttackAssetMeta.getReload("双枪主手");
        var oMeta:Object = AttackAssetMeta.getReload("双枪副手");
        var eMeta:Object = AttackAssetMeta.getReload("双枪结束");
        var mBurden:Number = 100 + ((self.手枪属性.reloadPenalty) | 0);
        var oBurden:Number = 100 + ((self.手枪2属性.reloadPenalty) | 0);
        var f:Number = computeReloadFrames(mMeta, mBurden)
                     + computeReloadFrames(oMeta, oBurden)
                     + eMeta.fixedTail;
        return f / 30;
    }

    private static function computeReloadFrames(meta:Object, burden:Number):Number {
        var f:Number = meta.fixedTail;
        var segs:Array = meta.controlledSegments;
        if (segs != null) {
            for (var i:Number = 0; i < segs.length; i++) {
                f += Math.ceil(segs[i] * burden / 100);
            }
        }
        return f;
    }
}
