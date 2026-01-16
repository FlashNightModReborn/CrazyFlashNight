/**
 * RegenEffect - 缓释恢复效果词条
 *
 * 在指定时间内持续恢复HP/MP，通过BuffManager的TickComponent实现。
 * 与heal词条的"即时恢复"语义分离，regen显式表达"持续恢复"。
 *
 * XML配置示例:
 * <!-- 总量模式：600帧内平均恢复150HP -->
 * <effect type="regen" hp="150" duration="600" interval="30" mode="total"
 *         id="药剂_缓释HP" stack="refresh" scaleWithAlchemy="true"/>
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
 *   - "total":       总量模式，hp/mp为总恢复量，自动分摊到每个tick
 *   - "perTick":     每tick模式，hp/mp为每次恢复量
 * - target:          目标（默认"self"，暂不支持"group"）
 * - scaleWithAlchemy: 是否应用炼金加成（默认true）
 * - id:              buff标识（用于叠加控制，默认根据物品名生成）
 * - stack:           叠加模式（默认"refresh"）
 *   - "refresh":     刷新，移除旧的添加新的
 *   - "stack":       叠加，允许多个实例同时存在
 *   - "extend":      延长，延长现有buff的持续时间（TODO）
 *
 * @author FlashNight
 * @version 1.0
 */
import org.flashNight.arki.item.drug.IDrugEffect;
import org.flashNight.arki.item.drug.DrugContext;
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

        // 解析HP/MP值
        var hpRaw:Number = parseValue(effectData.hp, target.hp满血值);
        var mpRaw:Number = parseValue(effectData.mp, target.mp满血值);

        if (hpRaw == 0 && mpRaw == 0) {
            trace("[RegenEffect] hp和mp均为0，无效果");
            return false;
        }

        // 计算tick次数和每tick恢复量
        var tickCount:Number = Math.ceil(duration / interval);
        var hpPerTick:Number, mpPerTick:Number;

        if (mode == "total") {
            // 总量模式：分摊到每个tick
            hpPerTick = (hpRaw > 0) ? Math.ceil(hpRaw / tickCount) : 0;
            mpPerTick = (mpRaw > 0) ? Math.ceil(mpRaw / tickCount) : 0;
        } else {
            // perTick模式：每次恢复固定量
            hpPerTick = hpRaw;
            mpPerTick = mpRaw;
        }

        // 应用炼金加成
        if (scaleWithAlchemy) {
            hpPerTick = ctx.calcHPWithAlchemy(hpPerTick);
            mpPerTick = ctx.calcMPWithAlchemy(mpPerTick);
        }

        // 解析叠加参数
        var stack:String = effectData.stack || "refresh";
        var buffIdHP:String = effectData.id ? (effectData.id + "_HP") : "药剂_缓释_HP";
        var buffIdMP:String = effectData.id ? (effectData.id + "_MP") : "药剂_缓释_MP";

        var buffManager:BuffManager = target.buffManager;

        // HP和MP分开创建独立的buff，各自竞争各自的槽位
        // 这样HP缓释和HP缓释竞争，MP缓释和MP缓释竞争，互不干扰

        if (hpPerTick > 0) {
            // 处理HP缓释叠加逻辑
            var finalHPId:String = buffIdHP;
            if (stack == "stack" && buffManager.getBuffById(buffIdHP)) {
                finalHPId = buffIdHP + "_" + getTimer() + "_" + Math.floor(Math.random() * 1000);
            }
            createRegenBuff(buffManager, finalHPId, hpPerTick, 0, interval, duration, target);
        }

        if (mpPerTick > 0) {
            // 处理MP缓释叠加逻辑
            var finalMPId:String = buffIdMP;
            if (stack == "stack" && buffManager.getBuffById(buffIdMP)) {
                finalMPId = buffIdMP + "_" + getTimer() + "_" + Math.floor(Math.random() * 1000);
            }
            createRegenBuff(buffManager, finalMPId, 0, mpPerTick, interval, duration, target);
        }

        return true;
    }

    /**
     * 创建缓释恢复Buff
     */
    private function createRegenBuff(
        buffManager:BuffManager,
        buffId:String,
        hpPerTick:Number,
        mpPerTick:Number,
        interval:Number,
        duration:Number,
        target:Object
    ):Void {
        // 创建tick回调
        // 注意：AS2闭包捕获的是引用，需要通过context传递值
        var tickCallback:Function = function(host:IBuff, tickNum:Number, ctx:Object):Void {
            var t:Object = ctx.target;
            if (!t || t.hp <= 0) return; // 目标无效或已死亡

            // _root.发布消息("RegenEffect Tick: " + tickNum + ", HP恢复 " + ctx.hpPerTick + ", MP恢复 " + ctx.mpPerTick);

            // HP恢复
            if (ctx.hpPerTick > 0) {
                var newHP:Number = t.hp + ctx.hpPerTick;
                var maxHP:Number = t.hp满血值;
                if (newHP > maxHP) newHP = maxHP;
                if (newHP > t.hp) {
                    t.hp = newHP;
                    _root.玩家信息界面.刷新hp显示();
                }
            }

            // MP恢复
            if (ctx.mpPerTick > 0) {
                var newMP:Number = t.mp + ctx.mpPerTick;
                var maxMP:Number = t.mp满血值;
                if (newMP > maxMP) newMP = maxMP;
                if (newMP > t.mp) {
                    t.mp = newMP;
                    _root.玩家信息界面.刷新mp显示();
                }
            }
        };

        // 构建上下文对象
        var tickContext:Object = {
            target: target,
            hpPerTick: hpPerTick,
            mpPerTick: mpPerTick
        };

        // 计算tick次数
        var maxTicks:Number = Math.ceil(duration / interval);

        // 创建组件
        // 只使用 TickComponent 控制生命周期，不需要 TimeLimitComponent
        // 因为 MetaBuff._updateComponents 的逻辑是"任意组件存活则继续"
        var tickComp:TickComponent = new TickComponent(interval, tickCallback, maxTicks, tickContext, false);

        // 创建MetaBuff（无childBuffs，纯组件驱动）
        var regenMeta:MetaBuff = new MetaBuff([], [tickComp], 0);

        // 添加到BuffManager
        buffManager.addBuff(regenMeta, buffId);
        buffManager.update(0); // 立即生效
    }

    /**
     * 解析恢复值（支持百分比）
     */
    private function parseValue(raw, maxValue:Number):Number {
        if (raw == null || raw == undefined) return 0;

        var strValue:String = String(raw);
        if (strValue.indexOf("%") >= 0) {
            // 百分比恢复
            var percent:Number = parseFloat(strValue.replace("%", ""));
            if (isNaN(percent)) return 0;
            return Math.floor(maxValue * percent / 100);
        } else {
            var num:Number = Number(raw);
            return isNaN(num) ? 0 : num;
        }
    }
}
