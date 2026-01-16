/**
 * RegenEffect - 缓释恢复效果词条
 *
 * 在指定时间内持续恢复HP/MP，通过BuffManager的TickComponent实现。
 * 与heal词条的"即时恢复"语义分离，regen显式表达"持续恢复"。
 *
 * XML配置示例:
 * <!-- 总量模式：600帧内平均恢复150HP -->
 * <effect type="regen" hp="150" duration="600" interval="30" mode="total"
 *         id="特殊缓释" stack="refresh" scaleWithAlchemy="true"/>
 *
 * <!-- 每tick模式：每30帧恢复10HP，持续1800帧 -->
 * <effect type="regen" hp="10" duration="1800" interval="30" mode="perTick"/>
 *
 * <!-- 百分比恢复：每60帧恢复1%最大HP -->
 * <effect type="regen" hp="1%" duration="1800" interval="60" mode="perTick"/>
 *
 * <!-- 先快后缓组合 -->
 * <effects>
 *     <effect type="heal" hp="100" target="self" scaleWithAlchemy="true"/>
 *     <effect type="regen" hp="200" duration="900" interval="30" mode="total"/>
 *     <effect type="playEffect" name="药剂动画"/>
 * </effects>
 *
 * 参数说明:
 * - hp:              HP恢复值（数值或百分比如"50%"）
 * - mp:              MP恢复值（数值或百分比）
 * - duration:        总持续帧数（必需）
 * - interval:        tick间隔帧数（默认30帧≈1秒）
 * - mode:            计算模式（默认"perTick"）
 *   - "total":       总量模式，hp/mp为总恢复量，先炼金加成再分摊到每个tick
 *   - "perTick":     每tick模式，hp/mp为每次恢复量，每次做炼金加成
 * - target:          目标（默认"self"，暂不支持"group"）
 * - scaleWithAlchemy: 是否应用炼金加成（默认true）
 * - id:              buff标识（用于叠加控制，默认按属性类型生成）
 * - stack:           叠加模式（默认"refresh"）
 *   - "refresh":     刷新，移除旧的添加新的
 *   - "stack":       叠加，允许多个实例同时存在
 *
 * 槽位规则:
 * - HP缓释共享 "药剂_缓释_HP" 槽位，互相刷新
 * - MP缓释共享 "药剂_缓释_MP" 槽位，互相刷新
 * - HP和MP缓释互不干扰，可同时存在
 *
 * @author FlashNight
 * @version 1.1
 */
import org.flashNight.arki.item.drug.IDrugEffect;
import org.flashNight.arki.item.drug.DrugContext;
import org.flashNight.arki.item.drug.DrugValueParser;
import org.flashNight.arki.component.Buff.*;
import org.flashNight.arki.component.Buff.Component.*;

class org.flashNight.arki.item.drug.effects.RegenEffect implements IDrugEffect {

    public function RegenEffect() {
    }

    public function getType():String {
        return "regen";
    }

    public function execute(context:Object, effectData:Object):Boolean {
        var ctx:DrugContext = DrugContext(context);
        if (!ctx || !ctx.target) return false;

        var target:Object = ctx.target;

        // 检查buffManager是否存在
        if (!target.buffManager) {
            trace("[RegenEffect] 目标没有buffManager");
            return false;
        }

        // 解析必需参数
        var duration:Number = Number(effectData.duration);
        if (isNaN(duration) || duration <= 0) {
            trace("[RegenEffect] 缺少有效的 duration");
            return false;
        }

        // 解析可选参数
        var interval:Number = Number(effectData.interval);
        if (isNaN(interval) || interval <= 0) interval = 30; // 默认30帧

        var mode:String = effectData.mode || "perTick";
        // XMLParser 可能返回 Boolean
        var scaleWithAlchemy:Boolean = effectData.scaleWithAlchemy !== false;

        // 解析HP/MP原始值
        var hpRaw:Number = DrugValueParser.parse(effectData.hp, target.hp满血值);
        var mpRaw:Number = DrugValueParser.parse(effectData.mp, target.mp满血值);

        if (hpRaw == 0 && mpRaw == 0) {
            trace("[RegenEffect] hp和mp均为0，无效果");
            return false;
        }

        // 计算tick次数
        var tickCount:Number = Math.ceil(duration / interval);

        // 计算每tick恢复量和余数
        var hpPerTick:Number = 0;
        var mpPerTick:Number = 0;
        var hpRemainder:Number = 0;
        var mpRemainder:Number = 0;

        if (mode == "total") {
            // 总量模式：先对总量做炼金加成，再分摊
            var hpTotal:Number = hpRaw;
            var mpTotal:Number = mpRaw;

            if (scaleWithAlchemy) {
                hpTotal = ctx.calcHPWithAlchemy(hpRaw);
                mpTotal = ctx.calcMPWithAlchemy(mpRaw);
            }

            // 精确分配：floor分摊 + 余数分配给前N次tick
            if (hpTotal > 0) {
                hpPerTick = Math.floor(hpTotal / tickCount);
                hpRemainder = hpTotal - (hpPerTick * tickCount);
            }
            if (mpTotal > 0) {
                mpPerTick = Math.floor(mpTotal / tickCount);
                mpRemainder = mpTotal - (mpPerTick * tickCount);
            }
        } else {
            // perTick模式：每次恢复固定量
            if (scaleWithAlchemy) {
                hpPerTick = ctx.calcHPWithAlchemy(hpRaw);
                mpPerTick = ctx.calcMPWithAlchemy(mpRaw);
            } else {
                hpPerTick = hpRaw;
                mpPerTick = mpRaw;
            }
        }

        // 解析叠加参数
        var stack:String = effectData.stack || "refresh";
        var buffIdHP:String = effectData.id ? (effectData.id + "_HP") : "药剂_缓释_HP";
        var buffIdMP:String = effectData.id ? (effectData.id + "_MP") : "药剂_缓释_MP";

        var buffManager:BuffManager = target.buffManager;

        // 获取炼金HP上限（用于tick回调）
        var maxHPWithAlchemy:Number = ctx.getMaxHPWithAlchemy();

        // HP和MP分开创建独立的buff，各自竞争各自的槽位
        if (hpPerTick > 0 || hpRemainder > 0) {
            var finalHPId:String = buffIdHP;
            if (stack == "stack" && buffManager.getBuffById(buffIdHP)) {
                finalHPId = buffIdHP + "_" + getTimer() + "_" + Math.floor(Math.random() * 1000);
            }
            createRegenBuff(buffManager, finalHPId, hpPerTick, hpRemainder, 0, 0,
                           interval, tickCount, target, maxHPWithAlchemy);
        }

        if (mpPerTick > 0 || mpRemainder > 0) {
            var finalMPId:String = buffIdMP;
            if (stack == "stack" && buffManager.getBuffById(buffIdMP)) {
                finalMPId = buffIdMP + "_" + getTimer() + "_" + Math.floor(Math.random() * 1000);
            }
            createRegenBuff(buffManager, finalMPId, 0, 0, mpPerTick, mpRemainder,
                           interval, tickCount, target, maxHPWithAlchemy);
        }

        return true;
    }

    /**
     * 创建缓释恢复Buff
     *
     * @param buffManager      BuffManager实例
     * @param buffId           buff标识
     * @param hpPerTick        每tick HP恢复量
     * @param hpRemainder      HP余数（分配给前N次tick各+1）
     * @param mpPerTick        每tick MP恢复量
     * @param mpRemainder      MP余数（分配给前N次tick各+1）
     * @param interval         tick间隔
     * @param maxTicks         最大tick次数
     * @param target           目标单位
     * @param maxHPWithAlchemy 炼金加成后的HP上限
     */
    private function createRegenBuff(
        buffManager:BuffManager,
        buffId:String,
        hpPerTick:Number,
        hpRemainder:Number,
        mpPerTick:Number,
        mpRemainder:Number,
        interval:Number,
        maxTicks:Number,
        target:Object,
        maxHPWithAlchemy:Number
    ):Void {
        // 创建tick回调
        var tickCallback:Function = function(host:IBuff, tickNum:Number, ctx:Object):Void {
            var t:Object = ctx.target;
            if (!t || t.hp <= 0) return; // 目标无效或已死亡

            // HP恢复
            if (ctx.hpPerTick > 0 || ctx.hpRemainder > 0) {
                // 计算本次恢复量（前N次+1分配余数）
                var hpThisTick:Number = ctx.hpPerTick;
                if (tickNum <= ctx.hpRemainder) {
                    hpThisTick += 1;
                }

                if (hpThisTick > 0) {
                    // 使用炼金加成后的HP上限
                    var maxHP:Number = ctx.maxHPWithAlchemy;
                    var newHP:Number = t.hp + hpThisTick;
                    if (newHP > maxHP) newHP = maxHP;
                    if (newHP > t.hp) {
                        t.hp = newHP;
                        _root.玩家信息界面.刷新hp显示();
                    }
                }
            }

            // MP恢复
            if (ctx.mpPerTick > 0 || ctx.mpRemainder > 0) {
                // 计算本次恢复量（前N次+1分配余数）
                var mpThisTick:Number = ctx.mpPerTick;
                if (tickNum <= ctx.mpRemainder) {
                    mpThisTick += 1;
                }

                if (mpThisTick > 0) {
                    var maxMP:Number = t.mp满血值;
                    var newMP:Number = t.mp + mpThisTick;
                    if (newMP > maxMP) newMP = maxMP;
                    if (newMP > t.mp) {
                        t.mp = newMP;
                        _root.玩家信息界面.刷新mp显示();
                    }
                }
            }
        };

        // 构建上下文对象
        var tickContext:Object = {
            target: target,
            hpPerTick: hpPerTick,
            hpRemainder: hpRemainder,
            mpPerTick: mpPerTick,
            mpRemainder: mpRemainder,
            maxHPWithAlchemy: maxHPWithAlchemy
        };

        // 创建组件
        var tickComp:TickComponent = new TickComponent(interval, tickCallback, maxTicks, tickContext, false);

        // 创建MetaBuff（无childBuffs，纯组件驱动）
        var regenMeta:MetaBuff = new MetaBuff([], [tickComp], 0);

        // 添加到BuffManager
        buffManager.addBuff(regenMeta, buffId);
        buffManager.update(0); // 立即生效
    }
}
