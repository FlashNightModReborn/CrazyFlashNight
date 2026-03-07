import org.flashNight.neur.StateMachine.FSM_Status;

/**
 * 状态转换管理器 - 高性能状态机过渡条件管理（v4.0 并行数组版）
 *
 * 核心设计：
 * ========
 * - Gate 和 Normal 转换规则分表存储，避免热路径上的 isGate 分支判断
 * - v4.0: 每条规则列表由三个并行数组（targets/funcs/actives）存储，
 *   消除 Object 节点的 GetMember 开销（~150ns/次），热路径改为数组索引（~35ns）
 * - 使用优先级队列管理转换规则（索引0 = 最高优先级）
 * - 支持条件函数的动态求值与去重机制
 *
 * 存储结构：
 * ========
 * gateLists / normalLists 格式：
 *   { 状态名: { t: [target...], f: [func...], a: [active...] } }
 *   三个数组等长，按索引对齐。
 *
 * @author flashNight
 * @version 4.0 (并行数组优化版)
 * @since AS2
 */
class org.flashNight.neur.StateMachine.Transitions {

    /** 状态机引用，用于条件函数的上下文调用 */
    public var status:FSM_Status;

    /**
     * Gate转换规则存储（动作前评估，用于暂停/死亡等即时阻断）
     * 格式：{ 状态名: { t:Array, f:Array, a:Array } }
     */
    public var gateLists:Object;

    /**
     * Normal转换规则存储（动作后评估，基于动作结果的状态切换）
     * 格式同 gateLists
     */
    public var normalLists:Object;

    public function Transitions(_status:FSM_Status) {
        this.status = _status;
        this.gateLists = {};
        this.normalLists = {};
    }

    /**
     * 添加转换规则（低优先级，尾插）
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
     * 添加转换规则（高优先级，头插）
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
     */
    public function remove(current:String, target:String, func:Function, isGate:Boolean):Boolean {
        if (isGate == null) isGate = false;
        var store:Object = isGate ? this.gateLists : this.normalLists;
        var rec:Object = store[current];
        if (rec == null) return false;

        var ts:Array = rec.t;
        var fs:Array = rec.f;
        var as_:Array = rec.a;
        var len:Number = ts.length;
        for (var i:Number = 0; i < len; i++) {
            if (ts[i] == target && fs[i] == func) {
                ts.splice(i, 1);
                fs.splice(i, 1);
                as_.splice(i, 1);
                return true;
            }
        }
        return false;
    }

    /**
     * 设置指定转换规则的激活状态
     */
    public function setActive(current:String, target:String, func:Function, isGate:Boolean, active:Boolean):Boolean {
        if (isGate == null) isGate = false;
        var store:Object = isGate ? this.gateLists : this.normalLists;
        var rec:Object = store[current];
        if (rec == null) return false;

        var ts:Array = rec.t;
        var fs:Array = rec.f;
        var len:Number = ts.length;
        for (var i:Number = 0; i < len; i++) {
            if (ts[i] == target && fs[i] == func) {
                rec.a[i] = active;
                return true;
            }
        }
        return false;
    }

    /**
     * 清除指定状态的所有转换规则（Gate 和 Normal 均清除）
     */
    public function clear(current:String):Void {
        delete this.gateLists[current];
        delete this.normalLists[current];
    }

    /**
     * 重置所有转换规则
     */
    public function reset():Void {
        this.gateLists = {};
        this.normalLists = {};
    }

    /**
     * 销毁转换管理器，释放所有引用。
     */
    public function destroy():Void {
        this.gateLists = null;
        this.normalLists = null;
        this.status = null;
    }

    /**
     * 执行Gate转换检查
     */
    public function TransitGate(current:String):String {
        var rec:Object = this.gateLists[current];
        if (rec == null) return null;

        var ts:Array = rec.t;
        var fs:Array = rec.f;
        var as_:Array = rec.a;
        var statusRef:FSM_Status = this.status;
        var len:Number = ts.length;

        for (var i:Number = 0; i < len; i++) {
            if (!as_[i]) continue;
            if (fs[i].call(statusRef, current, ts[i])) {
                return ts[i];
            }
        }
        return null;
    }

    /**
     * 执行普通转换检查
     */
    public function TransitNormal(current:String):String {
        var rec:Object = this.normalLists[current];
        if (rec == null) return null;

        var ts:Array = rec.t;
        var fs:Array = rec.f;
        var as_:Array = rec.a;
        var statusRef:FSM_Status = this.status;
        var len:Number = ts.length;

        for (var i:Number = 0; i < len; i++) {
            if (!as_[i]) continue;
            if (fs[i].call(statusRef, current, ts[i])) {
                return ts[i];
            }
        }
        return null;
    }

    /**
     * 内部方法 - 添加转换规则的通用实现（并行数组版）
     *
     * 去重机制：基于(target, func)组合判断规则唯一性。
     * 存在重复时重新激活规则，不创建新条目。
     * atHead=true 时提升到首位（手动移位，避免 splice+unshift 双桥接）。
     */
    private function _add(store:Object, current:String, target:String, func:Function, atHead:Boolean):Void {
        var rec:Object = store[current];
        if (rec == null) {
            rec = { t: [], f: [], a: [] };
            store[current] = rec;
        }

        var ts:Array = rec.t;
        var fs:Array = rec.f;
        var as_:Array = rec.a;
        var len:Number = ts.length;

        // 去重检查
        for (var i:Number = 0; i < len; i++) {
            if (ts[i] == target && fs[i] == func) {
                as_[i] = true;
                if (atHead && i != 0) {
                    // 手动移位到首位
                    var tmpT:String = ts[i];
                    var tmpF:Function = fs[i];
                    for (var j:Number = i; j > 0; --j) {
                        ts[j] = ts[j - 1];
                        fs[j] = fs[j - 1];
                        as_[j] = as_[j - 1];
                    }
                    ts[0] = tmpT;
                    fs[0] = tmpF;
                    as_[0] = true;
                }
                return;
            }
        }

        // 新增规则
        if (atHead) {
            ts.unshift(target);
            fs.unshift(func);
            as_.unshift(true);
        } else {
            ts.push(target);
            fs.push(func);
            as_.push(true);
        }
    }
}
