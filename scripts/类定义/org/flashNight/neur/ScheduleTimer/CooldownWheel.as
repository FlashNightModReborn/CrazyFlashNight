/**
CooldownWheel.as  （无 ID / 无链表 / 无重复任务）
——————————————————————————————————————————
固定 WHEEL_SIZE = 120 槽，对应 120 帧的步长（如 120ms）。
每帧拨轮一次，执行该槽里所有回调，然后清空槽。
*/
class org.flashNight.neur.ScheduleTimer.CooldownWheel {
    // ————————————————————————
    // 配置常量 & 私有字段
    // ————————————————————————
    private static var WHEEL_SIZE:Number = 120;         // 时间轮槽数
    private var slots:Array;                            // Array<Function>[]，每槽保存回调列表
    private var pos:Number = WHEEL_SIZE - 1;            // 当前读写指针，初始化到"上一次帧"
    private static var inst:CooldownWheel;              // 单例引用
    
    // ————————————————————————
    // 单例获取
    // ————————————————————————
    /**
     * 返回全局唯一实例
     */
    public static function I():CooldownWheel {
        return inst || (inst = new CooldownWheel());
    }
    
    // ————————————————————————
    // 构造函数（私有）
    // ————————————————————————
    private function CooldownWheel() {
        // 初始化各槽为一个空数组
        slots = new Array(WHEEL_SIZE);
        for (var i:Number = 0; i < WHEEL_SIZE; ++i) {
            slots[i] = [];
        }
        
        // 创建驱动 MovieClip，每帧调用 tick()
        var depth:Number = _root.getNextHighestDepth();
        var clip:MovieClip = _root.createEmptyMovieClip("_cdWheel", depth);
        var self:CooldownWheel = this;
        clip.onEnterFrame = function():Void {
            self.tick();
        };
    }
    
    // ————————————————————————
    // 公开方法
    // ————————————————————————
    /**
     * 添加一次性延迟任务
     * @param delay    延迟帧数
     *                 >0 → 在经过 delay 次 tick 后执行
     *                 ≤0 → 在下一次 tick 时立即执行
     * @param callback 回调函数（无参数）
     */
    public function add(delay:Number, callback:Function):Void {
        var slotIndex:Number;
        if (delay > 0) {
            slotIndex = (pos + delay) % WHEEL_SIZE;
        } else {
            // 延迟 <= 0 时，在下一帧执行
            slotIndex = (pos + 1) % WHEEL_SIZE;
        }
        slots[slotIndex].push(callback);
    }
    
    /**
     * 每帧由 onEnterFrame 调用：
     * 执行并清空当前槽所有回调
     * 指针前移一格
     */
    public function tick():Void {
        // 先移动指针到下一槽
        pos = (pos + 1) % WHEEL_SIZE;
        
        // 再执行当前槽回调
        var list:Array = slots[pos];
        while (list.length) {
            (list.pop())();
        }
    }
    
    /**
     * 重置时间轮状态（用于测试）
     */
    public function reset():Void {
        for (var i:Number = 0; i < WHEEL_SIZE; ++i) {
            slots[i] = [];
        }
        pos = WHEEL_SIZE - 1;
    }
}