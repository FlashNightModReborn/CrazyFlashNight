/**
 * 文件：org/flashNight/arki/achievement/ObjectiveEvaluator.as
 * 说明：objective 指标的【共享原始读数器】——成就 curOf 与任务 conditions 的同一套
 * curOf/check 基础设施（设计：docs/任务成就-判定层共享-设计-2026-06-11.md §2）。
 *
 * rawOf(type, params) 返回指标【原始读数】，不带任何基线扣减——基线策略归各消费者：
 *   - 成就：killTotal 由 AchievementService.curOf 扣成就基线 a.base.kt（D1 终身语义）；
 *   - 任务：sinceAccept 条件由 TaskUtil 扣接取时基线 requirements.condBase[i]（窗口语义）。
 *
 * 硬约束：
 *   - 类型枚举 = tools/lib/objective-types.js OBJECTIVE_TYPES 同集（derive build gate 单源），
 *     新增类型三处联动：本类分发 + objective-types.js + （若成就启用）derive-achievement-catalog
 *     的 params switch case。未知类型返 0（永不达成，派生器已在 build 拦截）。
 *   - 全分支防御 undefined：任务侧可能在成就容器/各系统未就绪时调用（AVM1 属性读
 *     undefined 不抛、调用 undefined 函数静默返 undefined，仅 typeof 守卫显式函数调用）。
 *   - 禁在本类做 toast/锁存/写存档——纯读数，零副作用。
 */
import org.flashNight.arki.task.TaskUtil;
import org.flashNight.arki.item.ItemUtil;

class org.flashNight.arki.achievement.ObjectiveEvaluator {

    /**
     * 指标原始读数（无基线扣减，永不返 NaN/负数，未知类型返 0）。
     * @param type   objective 类型（OBJECTIVE_TYPES 枚举）
     * @param params 类型参数（缺省视为 {}）
     */
    public static function rawOf(type:String, params:Object):Number {
        var p:Object = (params != undefined) ? params : {};

        if (type == "killTotal") {
            var kt:Number = (_root.killStats != undefined) ? Number(_root.killStats.total) : NaN;
            return isNaN(kt) ? 0 : kt;
        }
        if (type == "economyCount") {
            // 经济计数器权威在 _saveExt.成就.cnt（AchievementMetrics.record 唯一写点）；
            // 任务消费同一份计数器属设计内共享，容器未建 → 0
            var ext:Object = _root._saveExt;
            if (ext == undefined || ext.成就 == undefined || ext.成就.cnt == undefined) return 0;
            var c:Number = Number(ext.成就.cnt[p.counter]);
            return isNaN(c) ? 0 : c;
        }
        if (type == "infraLevel") {
            if (_root.基建系统 == undefined || _root.基建系统.infrastructure == undefined) return 0;
            var lv:Number = Number(_root.基建系统.infrastructure[p.name]);
            return isNaN(lv) ? 0 : lv;
        }
        if (type == "infraBuiltCount") {
            if (_root.基建系统 == undefined || _root.基建系统.infrastructure == undefined) return 0;
            var n:Number = 0;
            var infra:Object = _root.基建系统.infrastructure;
            for (var k:String in infra) {
                if (Number(infra[k]) > 0) n++;
            }
            return n;
        }
        if (type == "taskFinished") {
            // ⚠ tasks_finished 值=完成次数非布尔（可重复任务自增），显式 >=1，禁 ==true
            if (_root.tasks_finished == undefined) return 0;
            return (Number(_root.tasks_finished[String(p.taskId)]) >= 1) ? 1 : 0;
        }
        if (type == "chainProgress") {
            if (_root.task_chains_progress == undefined) return 0;
            var prog:Number = Number(_root.task_chains_progress[p.chain]);
            return isNaN(prog) ? 0 : prog;
        }
        if (type == "skillLevel") {
            if (typeof _root.根据技能名查找主角技能等级 != "function") return 0;
            var sl:Number = Number(_root.根据技能名查找主角技能等级(p.skill));
            return isNaN(sl) ? 0 : sl;
        }
        if (type == "itemOwned") {
            // 0/1 布尔型（containTaskItems 语义）；要进度条用 itemCount
            var cnt:Number = (p.count != undefined && !isNaN(Number(p.count))) ? Number(p.count) : 1;
            return TaskUtil.containTaskItems([p.item + "#" + cnt]) ? 1 : 0;
        }
        if (type == "itemCount") {
            // 实数计数（背包+材料+情报，ItemUtil.getTotal）；非单调（可消耗），禁 sinceAccept（derive 已拦）
            var total:Number = Number(ItemUtil.getTotal(p.item));
            return isNaN(total) ? 0 : total;
        }
        return 0; // 未知类型：永不达成，不抛错（AS2 无 try/finally，回调禁 throw）
    }
}
