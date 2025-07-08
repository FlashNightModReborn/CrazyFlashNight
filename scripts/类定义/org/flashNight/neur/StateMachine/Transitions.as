import org.flashNight.neur.StateMachine.FSM_Status;

class org.flashNight.neur.StateMachine.Transitions {
    private var status:FSM_Status;      // 目标状态机引用
    private var lists:Object;           // 过渡线表：current -> Array

    public function Transitions(_status:FSM_Status) {
        this.status = _status;
        this.lists  = {};               // 等价 new Object()
    }

    // 对外方法 ------------------------------------------------------------
    public function push   (current:String, target:String, func:Function):Void { _add(current, target, func, /*atHead=*/false); }
    public function unshift(current:String, target:String, func:Function):Void { _add(current, target, func, /*atHead=*/true ); }

    /** 删除某状态全部过渡线，供测试或阶段性清理。*/
    public function clear(current:String):Void { delete this.lists[current]; }

    /** 清空全部过渡线。*/
    public function reset():Void { this.lists = {}; }

    /**
     * 根据当前子状态尝试执行过渡。
     * @return  命中时返回目标状态名；否则返回 null
     */
    public function Transit(current:String):String {
        var list:Array = this.lists[current];
        if (!list) return null;

        var statusRef:FSM_Status = this.status;
        var len:Number = list.length;

        for (var i:Number = 0; i < len; i++) {
            var node:Object = list[i];
            if (!node.active) continue;

            /* 给条件函数加丰富上下文：
             *  this      ->  绑定为状态机（与旧版保持一致）
             *  参数[0]   ->  当前状态名
             *  参数[1]   ->  目标状态名
             *  参数[2]   ->  Transitions 实例（可选）
             */
            var ok:Boolean = Boolean(node.func.call(statusRef, current, node.target, this));
            if (ok) return node.target;
        }
        return null;
    }

    // 内部工具 ------------------------------------------------------------
    private function _add(current:String, target:String, func:Function, atHead:Boolean):Void {
        var list:Array = this.lists[current];
        if (!list) {
            list = [];
            this.lists[current] = list;
        }

        // —— 去重：相同 (target, func) 只保留一份 ——
        for (var i:Number = 0; i < list.length; i++) {
            var n:Object = list[i];
            if (n.target == target && n.func == func) {
                n.active = true;        // 若此前被禁用则重新激活
                if (atHead && i != 0) { // 提升优先级
                    list.splice(i, 1);
                    list.unshift(n);
                }
                return;                 // 已存在则不再新建
            }
        }

        // 新建节点
        var node:Object = {target:target, active:true, func:func};
        atHead ? list.unshift(node) : list.push(node);
    }
}
