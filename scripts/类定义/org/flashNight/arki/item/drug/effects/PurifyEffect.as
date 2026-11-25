import org.flashNight.arki.item.drug.IDrugEffect;
import org.flashNight.arki.item.drug.DrugContext;
import org.flashNight.arki.component.Buff.BuffManager;
import org.flashNight.arki.unit.UnitComponent.Targetcache.TargetCacheManager;

/**
 * PurifyEffect - 净化效果词条
 *
 * 清除/减轻负面状态：降低地形伤害系数（单调衰减）、设置麻痹抗性（带下限保护）、
 * 缩短或消除 debuff（按前缀与 harm 极性匹配），并支持 target="group" 群体净化。
 *
 * XML配置示例:
 * <effect type="purify" value="50" scaleWithAlchemy="true" clearDebuffs="debuff_" />
 * <effect type="purify" value="15" target="group" scaleWithAlchemy="true" />
 *
 * 参数说明:
 * - value: 净化强度值
 * - target: 作用范围（"self" 默认单体；"group" 自身及存活友军，可选 rangeX/rangeY）
 * - scaleWithAlchemy: 是否应用炼金加成（默认 true）
 * - clearDebuffs: 要净化的 debuff ID 前缀（逗号分隔；省略时默认 "debuff_"；"none"/false 关闭）
 * - matchHarmPolarity: 是否同时匹配 hudInfo.polarity == "harm" 的负面 Buff（默认 true）
 * - dispelThreshold: 无计时器常驻 debuff 的直接驱散门槛（默认 50，<= 0 不设门槛）
 * - applyTerrain: 是否衰减全局 _root.地形伤害系数（默认 true；群体施放仅生效一次）
 * - terrainDamageBase: 地形伤害系数渐近下限（默认 0.09）
 * - terrainDamageFactor: 地形伤害系数衰减半衰因子（默认 30）
 * - paralysisMultiplier: 麻痹值倍率（默认 -10）
 * - id: 可选效果标识；传入时同一帧同 id 仅衰减一次地形伤害系数（防止循环调用重复触发）
 *
 * 计算公式:
 * - 麻痹值 = min(原麻痹值, paralysisMultiplier * 净化量)
 * - 地形伤害系数 = base + (当前系数 - base) * factor / (factor + 净化量)  [当前系数 > base 时]
 *
 * @author FlashNight
 * @version 2.0
 */
class org.flashNight.arki.item.drug.effects.PurifyEffect implements IDrugEffect {

    /** 同一帧同 ID 地形系数去重缓存（保护女仆白等循环调用者） */
    private static var _lastTerrainEffectId:String = null;
    private static var _lastTerrainFrameStamp:Number = -1;

    /** 单元测试可注入的群体友军解析钩子；生产环境保持 null 并走 TargetCacheManager */
    public static var groupTargetResolver:Function = null;

    /**
     * 重置地形系数同帧去重状态（供单元测试使用）
     */
    public static function resetTerrainDedupForTest():Void {
        _lastTerrainEffectId = null;
        _lastTerrainFrameStamp = -1;
    }

    public function PurifyEffect() {
    }

    public function getType():String {
        return "purify";
    }

    public function execute(context:Object, effectData:Object):Boolean {
        var ctx:DrugContext = DrugContext(context);
        if (!ctx || !ctx.target) return false;

        var value:Number = Number(effectData.value);
        if (isNaN(value)) value = 0;

        // XMLParser 会把 "true"/"false" 转成 Boolean，需要同时兼容两种情况
        var scaleWithAlchemy:Boolean = (effectData.scaleWithAlchemy !== false && effectData.scaleWithAlchemy != "false");

        // 应用炼金加成
        if (scaleWithAlchemy) {
            value = ctx.calcPurifyWithAlchemy(value);
        }

        // 获取配置参数（使用默认值）
        var terrainDamageBase:Number = Number(effectData.terrainDamageBase);
        if (isNaN(terrainDamageBase)) terrainDamageBase = 0.09;

        var terrainDamageFactor:Number = Number(effectData.terrainDamageFactor);
        if (isNaN(terrainDamageFactor) || !(terrainDamageFactor > 0)) terrainDamageFactor = 30;

        var paralysisMultiplier:Number = Number(effectData.paralysisMultiplier);
        if (isNaN(paralysisMultiplier)) paralysisMultiplier = -10;

        var dispelThreshold:Number = Number(effectData.dispelThreshold);
        if (isNaN(dispelThreshold)) dispelThreshold = 50;

        var targetMode:String = (effectData.target != null && String(effectData.target).length > 0)
            ? String(effectData.target) : "self";

        // 1. 降低全局地形伤害系数（每次施放最多触发一次；有 id 时按帧去重）
        var applyTerrain:Boolean = (effectData.applyTerrain !== false && effectData.applyTerrain != "false");
        if (applyTerrain && value > 0) {
            var shouldApplyTerrain:Boolean = true;
            if (effectData.id != null) {
                var effectIdStr:String = String(effectData.id);
                if (effectIdStr.length > 0) {
                    var frameStamp:Number = (_root.帧计时器 != null && !isNaN(Number(_root.帧计时器.当前帧数)))
                        ? Number(_root.帧计时器.当前帧数)
                        : getTimer();
                    if (_lastTerrainEffectId == effectIdStr && _lastTerrainFrameStamp == frameStamp) {
                        shouldApplyTerrain = false;
                    } else {
                        _lastTerrainEffectId = effectIdStr;
                        _lastTerrainFrameStamp = frameStamp;
                    }
                }
            }

            if (shouldApplyTerrain) {
                var curTerrain:Number = Number(_root.地形伤害系数);
                if (isNaN(curTerrain) || !(curTerrain > 0)) {
                    curTerrain = 1;
                }
                if (curTerrain > terrainDamageBase) {
                    _root.地形伤害系数 = terrainDamageBase +
                        (curTerrain - terrainDamageBase) * terrainDamageFactor / (terrainDamageFactor + value);
                }
            }
        }

        // 2. 解析 debuff 净化配置（未显式禁用时默认匹配 "debuff_" 与 polarity == "harm"）
        var rawClear:Object = effectData.clearDebuffs;
        var enableDebuffPurify:Boolean = true;
        var prefixes:Array = [];
        if (rawClear === false || rawClear == "false" || rawClear == "none") {
            enableDebuffPurify = false;
        } else {
            var clearStr:String = (rawClear != null) ? String(rawClear) : "";
            if (clearStr.length > 0) {
                var parts:Array = clearStr.split(",");
                for (var p:Number = 0; p < parts.length; p++) {
                    var prefix:String = parts[p];
                    while (prefix.charAt(0) == " ") prefix = prefix.substring(1);
                    while (prefix.charAt(prefix.length - 1) == " ") prefix = prefix.substring(0, prefix.length - 1);
                    if (prefix.length > 0) {
                        prefixes.push(prefix);
                    }
                }
            }
            if (prefixes.length == 0) {
                prefixes.push("debuff_");
            }
        }
        var matchHarmPolarity:Boolean = (effectData.matchHarmPolarity !== false && effectData.matchHarmPolarity != "false");

        // 3. 解析作用目标列表（单体 / 群体）
        var targets:Array = (targetMode == "group")
            ? resolveGroupTargetsWithResolver(ctx.target, effectData, groupTargetResolver)
            : [ctx.target];

        // 4. 逐目标执行麻痹值保护赋值与 debuff 减时/消除
        for (var i:Number = 0; i < targets.length; i++) {
            var unit:Object = targets[i];
            if (!unit) continue;

            if (value > 0) {
                var paralysisFloor:Number = paralysisMultiplier * value;
                var curParalysis:Number = Number(unit.麻痹值);
                if (unit.麻痹值 == undefined || unit.麻痹值 == null || isNaN(curParalysis) || curParalysis > paralysisFloor) {
                    unit.麻痹值 = paralysisFloor;
                }
            }

            if (enableDebuffPurify && value > 0 && unit.buffManager) {
                var buffManager:BuffManager = unit.buffManager;
                var purifyResult:Object = buffManager.purifyDebuffs(value, prefixes, matchHarmPolarity, dispelThreshold);
                if (purifyResult && purifyResult.removed > 0) {
                    buffManager.update(0);
                }
            }
        }

        return true;
    }

    /**
     * 解析群体效果目标列表（包含施法者自身与存活友军，支持可选 rangeX/rangeY 过滤）
     * 供 PurifyEffect 与 PlayEffectEffect 共享。
     */
    public static function resolveGroupTargetsWithResolver(caster:Object, effectData:Object, resolver:Function):Array {
        var targets:Array = [];
        if (!caster) return targets;

        if (caster.hp > 0) {
            targets.push(caster);
        }

        var allies:Array = (resolver != null)
            ? resolver(caster)
            : TargetCacheManager.getCachedAlly(caster, 5);
        if (!allies || allies.length == 0) {
            return targets;
        }

        var rangeX:Number = Number(effectData.rangeX);
        var rangeY:Number = Number(effectData.rangeY);
        var useRange:Boolean = (!isNaN(rangeX) && rangeX > 0 && !isNaN(rangeY) && rangeY > 0);

        for (var i:Number = 0; i < allies.length; i++) {
            var u:Object = allies[i];
            if (!u || !(u.hp > 0)) continue;

            var duplicated:Boolean = false;
            for (var j:Number = 0; j < targets.length; j++) {
                if (targets[j] === u) {
                    duplicated = true;
                    break;
                }
            }
            if (duplicated) continue;

            if (useRange) {
                var dx:Number = Number(u._x) - Number(caster._x);
                var dy:Number = Number(u._y) - Number(caster._y);
                if (dx < 0) dx = -dx;
                if (dy < 0) dy = -dy;
                if (!(dx < rangeX && dy < rangeY)) continue;
            }
            targets.push(u);
        }

        return targets;
    }
}
