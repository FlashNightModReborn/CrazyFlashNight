import org.flashNight.neur.StateMachine.FSM_Status;

class org.flashNight.neur.StateMachine.Transitions {
    private var status:FSM_Status;      // 目标状态机引用
    private var lists:Object;           // 过渡线表：current -> Array

    public function Transitions(_status:FSM_Status) {
        this.status = _status;
        this.lists  = {};               // 等价 new Object()
    }

    // 对外方法 ------------------------------------------------------------
    public function push(current:String, target:String, func:Function):Void {
        _add(current, target, func, false);
    }
    public function unshift(current:String, target:String, func:Function):Void {
        _add(current, target, func, true);
    }

    /** 删除某状态全部过渡线，供测试或阶段性清理。*/
    public function clear(current:String):Void {
        delete this.lists[current];
    }

    /** 清空全部过渡线。*/
    public function reset():Void {
        this.lists = {};
    }

    /**
     * 根据当前子状态尝试执行过渡。
     * @return  命中时返回目标状态名；否则返回 null
     * 
     * Hot path 优化：
     *  - 缓存列表引用和长度
     *  - 在循环内将 node.func / node.target 缓存到局部变量
     *  - 直接 if (func.call(...)) 代替 Boolean(...) 包装
     */
    public function Transit(current:String):String {
        var list:Array = lists[current];
        if (list == null) return null;

        var statusRef:FSM_Status = status;
        var len:Number = list.length;
        // 缓存到局部，减少作用域链查找
        for (var i:Number = 0; i < len; i++) {
            var node:Object = list[i];
            if (!node.active) continue;

            // 本地缓存，避免多次属性访问
            var fn:Function = node.func;
            var tgt:String   = node.target;
            // 直接调用、判断
            if (fn.call(statusRef, current, tgt, this)) {
                return tgt;
            }
        }
        return null;
    }

    // 内部工具 ------------------------------------------------------------
    /**
     * 添加或重新激活一个过渡线。
     * atHead=true 时将优先级提升到首位：用 O(1) 交换替代 splice+unshift。
     */
    private function _add(current:String, target:String, func:Function, atHead:Boolean):Void {
        var list:Array = lists[current];
        if (list == null) {
            list = [];
            lists[current] = list;
        }

        // 去重：相同 (target, func) 只保留一份
        var len:Number = list.length;
        for (var i:Number = 0; i < len; i++) {
            var n:Object = list[i];
            if (n.target == target && n.func == func) {
                n.active = true;
                // 提升优先级：O(1) 交换到头部
                if (atHead && i != 0) {
                    var tmp:Object = list[0];
                    list[0] = n;
                    list[i] = tmp;
                }
                return;
            }
        }

        // 新建节点并插入
        var node:Object = { target: target, func: func, active: true };
        if (atHead) {
            // 头插简单 unshift，避免与提升冲突
            list.unshift(node);
        } else {
            list.push(node);
        }
    }
}
