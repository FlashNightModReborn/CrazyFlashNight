import org.flashNight.arki.item.*;

/**
 * 套装效果装载控制器。
 *
 * 一期只开放 member_components routine 与 resistance_entry 模板。控制器负责：
 *  - 按唯一装备槽统计套装件数；
 *  - 在通用 lifecycle loader 前建立 gate；
 *  - 收集 gated init 三态，成功后统一注册 context/子周期；
 *  - 显式失败时按 stop/resource 两阶段回滚；
 *  - 在 routine 全部 ready 后提交声明式抗性表项。
 */
class org.flashNight.arki.unit.UnitComponent.Initializer.SetEffectController {

    public static var READY_CYCLE:String = "ready_cycle";
    public static var READY_STATIC:String = "ready_static";
    public static var FAILURE:String = "failure";

    private static var EQUIPMENT_SLOTS:Array = [
        "头部装备", "上装装备", "下装装备", "脚部装备", "颈部装备", "手部装备",
        "刀", "长枪", "手枪", "手枪2", "手雷"
    ];

    private static function newPlan():Object {
        return {stopStack:[], resourceStack:[]};
    }

    private static function newGroup(id:String, setId:String):Object {
        return {
            id:id,
            setId:setId,
            status:"candidate",
            effects:{},
            routines:[],
            templates:[],
            rollbackPlan:newPlan(),
            teardownPlan:newPlan(),
            failed:false
        };
    }

    private static function collectIndexed(container:Object, prefix:String):Array {
        var result:Array = [];
        if (!container) return result;
        var index:Number = 0;
        var entry:Object = container[prefix + index];
        while (entry != undefined) {
            result.push(entry);
            index++;
            entry = container[prefix + index];
        }
        return result;
    }

    private static function countEquippedSets(target:MovieClip):Object {
        var counts:Object = {};
        for (var i:Number = 0; i < EQUIPMENT_SLOTS.length; i++) {
            var slot:String = EQUIPMENT_SLOTS[i];
            var data:Object = target[slot + "数据"];
            var setId:String = data && data.setId != undefined ? String(data.setId) : "";
            if (setId != "") counts[setId] = Number(counts[setId] || 0) + 1;
        }
        return counts;
    }

    /** 纯计数入口，供测试锁定“同槽只计一件”。 */
    public static function countSetSlots(slotData:Object, setId:String):Number {
        var count:Number = 0;
        for (var i:Number = 0; i < EQUIPMENT_SLOTS.length; i++) {
            var data:Object = slotData[EQUIPMENT_SLOTS[i]];
            if (data && String(data.setId) == setId) count++;
        }
        return count;
    }

    /**
     * 在任何单件 lifecycle 装载前建立 effect/group record 与 gate。
     */
    public static function prepare(target:MovieClip):Void {
        var controller:Object = {target:target, groups:{}, effects:{}, activeGates:{}};
        target.__setEffectController = controller;

        var counts:Object = countEquippedSets(target);
        var configs:Object = ItemUtil.itemSetConfigDict;
        for (var setId:String in configs) {
            var setConfig:Object = configs[setId];
            var effects:Array = collectIndexed(setConfig.effects, "effect_");
            var equippedCount:Number = Number(counts[setId] || 0);

            for (var i:Number = 0; i < effects.length; i++) {
                var config:Object = effects[i];
                var threshold:Number = Number(config.threshold);
                if (!(threshold > 0) || equippedCount < threshold) continue;

                var effectId:String = String(config.id);
                var groupId:String = config.activationGroup != undefined && String(config.activationGroup) != ""
                    ? String(config.activationGroup) : effectId;
                var groupKey:String = setId + ":" + groupId;
                var group:Object = controller.groups[groupKey];
                if (!group) {
                    group = newGroup(groupKey, setId);
                    controller.groups[groupKey] = group;
                }

                var effect:Object = {
                    id:effectId,
                    key:setId + ":" + effectId,
                    setId:setId,
                    group:group,
                    config:config,
                    status:"preflighted",
                    context:null,
                    componentRefs:{},
                    pendingCycles:[],
                    expectedComponents:0
                };
                group.effects[effectId] = effect;
                controller.effects[effect.key] = effect;

                if (String(config.kind) == "routine") {
                    group.routines.push(effect);
                    var components:Array = collectIndexed(config.components, "component_");
                    effect.expectedComponents = components.length;
                    for (var c:Number = 0; c < components.length; c++) {
                        var component:Object = components[c];
                        var componentId:String = String(component.id);
                        var slot:String = String(component.slot);
                        controller.activeGates[effect.key + ":" + slot + ":" + componentId] = effect;
                    }

                    var prepareName:String = String(config.prepareRoutine || "");
                    var prepareFunc:Function = _root.装备生命周期函数[prepareName];
                    if (prepareName == "" || !prepareFunc) {
                        markFailure(group, "missing prepare routine: " + prepareName);
                    } else {
                        effect.context = prepareFunc(effect, target);
                        if (!effect.context) markFailure(group, "prepare routine failed: " + prepareName);
                    }
                } else if (String(config.kind) == "template") {
                    group.templates.push(effect);
                } else {
                    markFailure(group, "unsupported effect kind: " + config.kind);
                }
            }
        }
    }

    public static function isGateActive(target:MovieClip, setId:String, effectId:String,
                                        slot:String, componentId:String):Boolean {
        var controller:Object = target.__setEffectController;
        if (!controller) return false;
        var effect:Object = controller.activeGates[setId + ":" + effectId + ":" + slot + ":" + componentId];
        return effect != undefined && effect.group.failed !== true;
    }

    public static function bindRef(target:MovieClip, ref:Object, setId:String, effectId:String,
                                   slot:String, componentId:String):Object {
        var controller:Object = target.__setEffectController;
        if (!controller) return null;
        var effect:Object = controller.activeGates[setId + ":" + effectId + ":" + slot + ":" + componentId];
        if (!effect || effect.group.failed === true) return null;
        ref.套装事务 = effect.group;
        ref.套装上下文 = effect.context;
        ref.套装效果记录 = effect;
        ref.套装组件ID = componentId;
        return effect;
    }

    /** gated init 创建外部资源后立即登记幂等清理。 */
    public static function registerResource(ref:Object, cleanup:Function):Boolean {
        var group:Object = ref ? ref.套装事务 : null;
        if (!group || group.failed === true || !cleanup) return false;
        group.rollbackPlan.resourceStack.push(cleanup);
        group.teardownPlan.resourceStack.push(cleanup);
        return true;
    }

    public static function registerSkillRestore(ref:Object, target:MovieClip,
                                                slot:String, oldSkill:Object):Boolean {
        return registerResource(ref, function():Void {
            target.主动战技[slot] = oldSkill;
        });
    }

    public static function registerComponent(ref:Object, status:String, cycleFunc:Function):Boolean {
        var effect:Object = ref ? ref.套装效果记录 : null;
        if (!effect || effect.group.failed === true) return false;
        if (status != READY_CYCLE && status != READY_STATIC) {
            markFailure(effect.group, "component init failed: " + ref.套装组件ID);
            return false;
        }
        if (status == READY_CYCLE && !cycleFunc) {
            markFailure(effect.group, "component cycle missing: " + ref.套装组件ID);
            return false;
        }
        if (effect.componentRefs[ref.套装组件ID] != undefined) {
            markFailure(effect.group, "duplicate component: " + ref.套装组件ID);
            return false;
        }

        effect.componentRefs[ref.套装组件ID] = ref;
        ref.套装初始化状态 = status;
        if (status == READY_CYCLE) {
            effect.pendingCycles.push({ref:ref, cycleFunc:cycleFunc});
        }
        return true;
    }

    public static function failRef(ref:Object, reason:String):Void {
        if (ref && ref.套装事务) markFailure(ref.套装事务, reason);
    }

    private static function markFailure(group:Object, reason:String):Void {
        if (!group || group.failed === true) return;
        group.failed = true;
        group.failureReason = reason;
        group.status = "rollingBack";
        runPlan(group.rollbackPlan);
        clearFailedGroup(group);
    }

    private static function runStack(stack:Array):Void {
        for (var i:Number = stack.length - 1; i >= 0; i--) {
            var cleanup:Function = stack[i];
            if (cleanup) cleanup();
        }
        stack.length = 0;
    }

    private static function runPlan(plan:Object):Void {
        if (!plan) return;
        runStack(plan.stopStack);
        runStack(plan.resourceStack);
    }

    private static function clearFailedGroup(group:Object):Void {
        group.rollbackPlan.stopStack.length = 0;
        group.rollbackPlan.resourceStack.length = 0;
        group.teardownPlan.stopStack.length = 0;
        group.teardownPlan.resourceStack.length = 0;
        for (var effectId:String in group.effects) {
            var effect:Object = group.effects[effectId];
            effect.context = null;
            effect.componentRefs = {};
            effect.pendingCycles.length = 0;
            effect.status = "rolledBack";
        }
        group.status = "rolledBack";
    }

    private static function registerLifecycleTask(target:MovieClip, group:Object, effect:Object,
                                                  label:String, action:Function, parameters:Array):String {
        var taskId:String = _root.帧计时器.taskManager.addLifecycleTask(target, label, action, 0, parameters);
        var cleanup:Function = function():Void {
            _root.帧计时器.移除生命周期任务(target, label);
        };
        group.rollbackPlan.stopStack.push(cleanup);
        group.teardownPlan.stopStack.push(cleanup);
        return taskId;
    }

    private static function componentCount(effect:Object):Number {
        var count:Number = 0;
        for (var componentId:String in effect.componentRefs) count++;
        return count;
    }

    private static function scheduleRoutine(target:MovieClip, group:Object, effect:Object):Boolean {
        if (componentCount(effect) != effect.expectedComponents) return false;
        var pending:Array = effect.pendingCycles;
        var cycleName:String = String(effect.config.cycleRoutine || "");
        var contextFunc:Function = cycleName == "" ? null : _root.装备生命周期函数[cycleName];

        if (pending.length > 0 && cycleName != "" && !contextFunc) return false;
        if (pending.length > 0 && contextFunc) {
            registerLifecycleTask(target, group, effect,
                "set:" + effect.setId + ":" + effect.id + ":context",
                contextFunc, [effect, effect.context]);
        }

        for (var i:Number = 0; i < pending.length; i++) {
            var pendingCycle:Object = pending[i];
            var ref:Object = pendingCycle.ref;
            var label:String = "set:" + effect.setId + ":" + effect.id + ":" +
                               ref.装备类型 + ":" + ref.套装组件ID;
            var cycleParam:Object = contextFunc ? effect.context : ref.生命周期参数;
            ref.生命周期参数 = cycleParam;
            ref.标签名 = label;
            ref.生命周期任务ID = registerLifecycleTask(target, group, effect, label,
                pendingCycle.cycleFunc, [ref, cycleParam || {}]);
        }
        effect.status = "routinesReady";
        return true;
    }

    private static function isFiniteNumber(value):Boolean {
        var numberValue:Number = Number(value);
        return !isNaN(numberValue) && (numberValue - numberValue) == 0;
    }

    /** 抗性 add 模板的纯数值语义；非法输入返回 undefined。 */
    public static function calculateAdditiveResistance(existing, baseIfMissing, value) {
        if (!isFiniteNumber(baseIfMissing) || !isFiniteNumber(value)) return undefined;
        var baseValue:Number;
        if (existing == undefined) {
            baseValue = Number(baseIfMissing);
        } else {
            if (!isFiniteNumber(existing)) return undefined;
            baseValue = Number(existing);
        }
        var result:Number = baseValue + Number(value);
        return isFiniteNumber(result) ? result : undefined;
    }

    private static function applyResistanceTemplate(target:MovieClip, group:Object, effect:Object):Boolean {
        var config:Object = effect.config;
        if (String(config.template) != "resistance_entry") return false;
        var params:Object = config.params;
        if (!params || String(params.attribute) != "原体" || String(params.calculation) != "add") return false;
        if (!isFiniteNumber(params.baseIfMissing) || !isFiniteNumber(params.value)) return false;

        var attribute:String = String(params.attribute);
        var oldValue = target.魔法抗性[attribute];
        var hadValue:Boolean = oldValue != undefined;
        var finalValue = calculateAdditiveResistance(oldValue, params.baseIfMissing, params.value);
        if (finalValue == undefined) return false;

        target.魔法抗性[attribute] = finalValue;
        group.rollbackPlan.resourceStack.push(function():Void {
            if (hadValue) target.魔法抗性[attribute] = oldValue;
            else delete target.魔法抗性[attribute];
        });
        effect.status = "templateEligible";
        return true;
    }

    /** 单件 loader 全部返回后统一调度并提交模板。 */
    public static function finalize(target:MovieClip):Void {
        var controller:Object = target.__setEffectController;
        if (!controller) return;

        for (var groupKey:String in controller.groups) {
            var group:Object = controller.groups[groupKey];
            if (group.failed === true) continue;
            group.status = "preflighted";

            var ready:Boolean = true;
            for (var r:Number = 0; r < group.routines.length; r++) {
                if (!scheduleRoutine(target, group, group.routines[r])) {
                    ready = false;
                    break;
                }
            }
            if (!ready) {
                markFailure(group, "routine component preflight failed");
                continue;
            }
            group.status = "routinesReady";

            for (var t:Number = 0; t < group.templates.length; t++) {
                if (!applyResistanceTemplate(target, group, group.templates[t])) {
                    ready = false;
                    break;
                }
            }
            if (!ready) {
                markFailure(group, "template finalize failed");
                continue;
            }

            group.status = "committed";
            group.rollbackPlan.stopStack.length = 0;
            group.rollbackPlan.resourceStack.length = 0;

            var teardown:Object = {
                动作:function(args:Object):Void {
                    SetEffectController.teardownGroup(args.target, args.groupKey);
                },
                额外参数:{target:target, groupKey:groupKey}
            };
            target.生命周期函数列表.push(teardown);
        }

        if (target.shield && target.shield.refreshStanceResistance) {
            target.shield.refreshStanceResistance();
        }
    }

    public static function teardownGroup(target:MovieClip, groupKey:String):Void {
        var controller:Object = target ? target.__setEffectController : null;
        var group:Object = controller ? controller.groups[groupKey] : null;
        if (!group || group.status == "tornDown") return;
        runPlan(group.teardownPlan);
        group.status = "tornDown";
        for (var effectId:String in group.effects) {
            var effect:Object = group.effects[effectId];
            effect.context = null;
            effect.componentRefs = {};
            effect.pendingCycles.length = 0;
        }
    }

    public static function clearController(target:MovieClip):Void {
        if (target) target.__setEffectController = null;
    }
}
