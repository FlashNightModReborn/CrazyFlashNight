import org.flashNight.neur.StateMachine.FSM_Status;

/**
 * 状态转换管理器 - 高性能状态机过渡条件管理
 *
 * 功能概述：
 * ========
 * 本类负责管理状态机中各状态之间的转换条件，支持优先级控制、条件判断、
 * 动态添加/移除过渡规则等功能。经过深度性能优化，适用于实时应用场景。
 *
 * 核心设计：
 * ========
 * - Gate 和 Normal 转换规则分表存储（gateLists / normalLists），
 *   避免热路径上的 isGate 分支判断
 * - 使用优先级队列管理转换规则（头部 = 高优先级）
 * - 支持条件函数的动态求值
 * - 提供去重机制避免重复规则
 * - 采用AS2优化友好的编程模式
 *
 * 使用场景：
 * ========
 * - 游戏AI状态机（NPC行为控制）
 * - UI交互状态管理
 * - 动画状态控制系统
 * - 业务流程状态转换
 * - 实时系统状态监控
 *
 * 示例用法：
 * ========
 * ```actionscript
 * var trans:Transitions = new Transitions(statusManager);
 *
 * // 添加普通转换规则：当血量 < 30% 时从战斗转为逃跑
 * trans.push("combat", "flee", function():Boolean {
 *     return this.data.health < 30;
 * });
 *
 * // 高优先级 Gate 规则：当血量 <= 0 时立即死亡（动作前生效）
 * trans.unshift("combat", "death", function():Boolean {
 *     return this.data.health <= 0;
 * }, true);
 *
 * // 执行 Gate 检查（动作前）
 * var gateTarget:String = trans.TransitGate("combat");
 * // 执行 Normal 检查（动作后）
 * var normalTarget:String = trans.TransitNormal("combat");
 * ```
 *
 * 注意事项：
 * ========
 * - 条件函数的this指向FSM_Status实例
 * - 避免在条件函数中执行耗时操作
 * - unshift添加的规则具有最高优先级
 *
 * @author flashNight神经网络团队
 * @version 3.0 (Gate/Normal分表优化版)
 * @since AS2
 */
class org.flashNight.neur.StateMachine.Transitions {

    /** 状态机引用，用于条件函数的上下文调用 */
    private var status:FSM_Status;

    /** 迭代守卫计数器：>0 时禁止对转换表进行结构性修改 */
    private var _iterating:Number = 0;

    /**
     * Gate转换规则存储结构（动作前评估，用于暂停/死亡等即时阻断）
     * 格式：{ 状态名: [规则数组] }
     * 规则对象格式：{ target: String, func: Function, active: Boolean }
     * 数组顺序表示优先级（索引0 = 最高优先级）
     */
    private var gateLists:Object;

    /**
     * Normal转换规则存储结构（动作后评估，基于动作结果的状态切换）
     * 格式同 gateLists
     */
    private var normalLists:Object;

    /**
     * 构造函数 - 初始化转换管理器
     *
     * @param _status 状态机实例，用于条件函数调用时的上下文
     */
    public function Transitions(_status:FSM_Status) {
        this.status = _status;
        this.gateLists = {};
        this.normalLists = {};
    }

    /**
     * 添加转换规则（低优先级）
     *
     * 将新规则添加到指定状态的转换列表末尾。如果相同的(target, func)组合
     * 已存在于同类型列表中，则重新激活该规则而不创建重复项。
     *
     * @param current 源状态名称
     * @param target  目标状态名称
     * @param func    条件判断函数，返回Boolean类型
     *                函数签名：function(current:String, target:String, transitions:Transitions):Boolean
     *                函数内this指向status实例
     * @param isGate  是否为Gate转换（默认false）。Gate转换在动作前评估，普通转换在动作后评估
     */
    public function push(current:String, target:String, func:Function, isGate:Boolean):Void {
        if (isGate == null) isGate = false;
        if (isGate) {
            _add(this.gateLists, current, target, func, false);
        } else {
            _add(this.normalLists, current, target, func, false);
        }
    }

    /**
     * 添加转换规则（高优先级）
     *
     * 将新规则添加到指定状态的转换列表首部，获得最高优先级。如果相同的
     * (target, func)组合已存在，则重新激活并提升其优先级到首位。
     *
     * @param current 源状态名称
     * @param target  目标状态名称
     * @param func    条件判断函数，返回Boolean类型
     * @param isGate  是否为Gate转换（默认false）
     */
    public function unshift(current:String, target:String, func:Function, isGate:Boolean):Void {
        if (isGate == null) isGate = false;
        if (isGate) {
            _add(this.gateLists, current, target, func, true);
        } else {
            _add(this.normalLists, current, target, func, true);
        }
    }

    /**
     * 移除指定的转换规则
     *
     * 通过 (target, func) 组合定位并物理移除规则节点。
     * 如果该规则不存在，则静默返回 false。
     *
     * @param current 源状态名称
     * @param target  目标状态名称
     * @param func    条件判断函数
     * @param isGate  是否为Gate转换（默认false）
     * @return Boolean 是否成功移除（true=找到并移除，false=未找到）
     */
    public function remove(current:String, target:String, func:Function, isGate:Boolean):Boolean {
        if (this._iterating > 0) {
            trace("[Transitions] 错误：迭代过程中禁止调用 remove(\"" + current + "\", \"" + target + "\")");
            return false;
        }
        if (isGate == null) isGate = false;
        var store:Object = isGate ? this.gateLists : this.normalLists;
        var list:Array = store[current];
        if (list == null) return false;

        var len:Number = list.length;
        for (var i:Number = 0; i < len; i++) {
            var n:Object = list[i];
            if (n.target == target && n.func == func) {
                list.splice(i, 1);
                return true;
            }
        }
        return false;
    }

    /**
     * 设置指定转换规则的激活状态
     *
     * 通过 (target, func) 组合定位规则节点并设置其 active 标志。
     * 非活跃规则在 TransitGate/TransitNormal 中被跳过，但仍保留在列表中，
     * 可随时通过再次调用本方法重新启用。
     *
     * @param current 源状态名称
     * @param target  目标状态名称
     * @param func    条件判断函数
     * @param isGate  是否为Gate转换（默认false）
     * @param active  是否激活（true=启用，false=禁用）
     * @return Boolean 是否成功设置（true=找到并设置，false=未找到）
     */
    public function setActive(current:String, target:String, func:Function, isGate:Boolean, active:Boolean):Boolean {
        if (this._iterating > 0) {
            trace("[Transitions] 错误：迭代过程中禁止调用 setActive(\"" + current + "\", \"" + target + "\")");
            return false;
        }
        if (isGate == null) isGate = false;
        var store:Object = isGate ? this.gateLists : this.normalLists;
        var list:Array = store[current];
        if (list == null) return false;

        var len:Number = list.length;
        for (var i:Number = 0; i < len; i++) {
            var n:Object = list[i];
            if (n.target == target && n.func == func) {
                n.active = active;
                return true;
            }
        }
        return false;
    }

    /**
     * 清除指定状态的所有转换规则（Gate 和 Normal 均清除）
     *
     * @param current 要清除转换规则的状态名称
     */
    public function clear(current:String):Void {
        if (this._iterating > 0) {
            trace("[Transitions] 错误：迭代过程中禁止调用 clear(\"" + current + "\")");
            return;
        }
        delete this.gateLists[current];
        delete this.normalLists[current];
    }

    /**
     * 重置所有转换规则
     *
     * 清空整个转换规则表，恢复到初始状态。
     */
    public function reset():Void {
        if (this._iterating > 0) {
            trace("[Transitions] 错误：迭代过程中禁止调用 reset()");
            return;
        }
        this.gateLists = {};
        this.normalLists = {};
    }

    /**
     * 执行Gate转换检查（仅检查Gate转换）
     *
     * 专门用于在动作执行前检查Gate转换条件。
     * Gate转换用于实现即时状态阻断，如暂停、紧急停止等。
     *
     * @param current 当前状态名称
     * @return String Gate目标状态名称，无Gate转换时返回null
     */
    public function TransitGate(current:String):String {
        // 缓存数组引用，避免重复属性查找
        var list:Array = this.gateLists[current];
        if (list == null) return null;

        // 缓存状态引用，减少this.status访问开销
        var statusRef:FSM_Status = this.status;
        // 缓存数组长度，避免重复计算
        var len:Number = list.length;

        ++this._iterating;
        // 按优先级顺序检查转换条件
        for (var i:Number = 0; i < len; i++) {
            var node:Object = list[i];
            // 跳过非活跃规则
            if (!node.active) continue;

            // 缓存函数和目标到局部变量，优化属性访问
            var fn:Function = node.func;
            var tgt:String = node.target;

            // 调用条件函数，this指向statusRef
            if (fn.call(statusRef, current, tgt, this)) {
                --this._iterating;
                return tgt;
            }
        }
        --this._iterating;
        return null;
    }

    /**
     * 执行普通转换检查（仅检查普通转换）
     *
     * 专门用于在动作执行后检查普通转换条件。
     *
     * @param current 当前状态名称
     * @return String 普通目标状态名称，无普通转换时返回null
     */
    public function TransitNormal(current:String):String {
        // 缓存数组引用，避免重复属性查找
        var list:Array = this.normalLists[current];
        if (list == null) return null;

        // 缓存状态引用，减少this.status访问开销
        var statusRef:FSM_Status = this.status;
        // 缓存数组长度，避免重复计算
        var len:Number = list.length;

        ++this._iterating;
        // 按优先级顺序检查转换条件
        for (var i:Number = 0; i < len; i++) {
            var node:Object = list[i];
            // 跳过非活跃规则
            if (!node.active) continue;

            // 缓存函数和目标到局部变量，优化属性访问
            var fn:Function = node.func;
            var tgt:String = node.target;

            // 调用条件函数，this指向statusRef
            if (fn.call(statusRef, current, tgt, this)) {
                --this._iterating;
                return tgt;
            }
        }
        --this._iterating;
        return null;
    }

    /**
     * 内部方法 - 添加转换规则的通用实现
     *
     * 实现push和unshift的核心逻辑，支持去重、优先级调整等功能。
     *
     * 去重机制：
     * - 基于(target, func)组合判断规则唯一性
     * - 存在重复时重新激活规则，不创建新实例
     * - 支持优先级调整（atHead=true时提升到首位）
     *
     * @param store   目标存储对象（gateLists 或 normalLists）
     * @param current 源状态名称
     * @param target  目标状态名称
     * @param func    条件函数
     * @param atHead  是否添加到头部（高优先级）
     */
    private function _add(store:Object, current:String, target:String, func:Function, atHead:Boolean):Void {
        if (this._iterating > 0) {
            trace("[Transitions] 错误：迭代过程中禁止调用 push/unshift(\"" + current + "\", \"" + target + "\")");
            return;
        }
        // 获取或创建状态的转换规则列表
        var list:Array = store[current];
        if (list == null) {
            list = [];
            store[current] = list;
        }

        // 去重检查：查找相同的(target, func)组合
        var len:Number = list.length;
        for (var i:Number = 0; i < len; i++) {
            var n:Object = list[i];
            if (n.target == target && n.func == func) {
                // 找到重复规则，重新激活
                n.active = true;
                // 如果需要提升优先级且不在首位，则交换到首位
                if (atHead && i != 0) {
                    var tmp:Object = list[0];
                    list[0] = n;
                    list[i] = tmp;
                }
                return;
            }
        }

        // 创建新的转换规则节点
        var node:Object = { target: target, func: func, active: true };

        // 根据优先级要求添加到相应位置
        if (atHead) {
            list.unshift(node);  // 添加到头部（高优先级）
        } else {
            list.push(node);     // 添加到尾部（低优先级）
        }
    }
}
