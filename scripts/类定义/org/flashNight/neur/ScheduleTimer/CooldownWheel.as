/**
 * CooldownWheel.as  （无 ID / 无链表 / 无重复任务）
 * ——————————————————————————————————————————
 * 固定  WHEEL = 120  槽，对应 120 帧 = 1 冷却周期步长。
 * 每帧轮盘拨一格，执行该槽里所有回调，然后清空槽。
 */
class org.flashNight.neur.ScheduleTimer.CooldownWheel
{
    private static var WHEEL_SIZE:Number = 120;   // 固定步长 120 帧
    private var slots:Array;                     // 每槽是 Array<Function>
    private var pos:Number = 0;                  // 指针
    private static var inst:CooldownWheel;       // 单例

    /** 单例入口 */
    public static function I():CooldownWheel {
        return inst || (inst = new CooldownWheel());
    }

    /*=======  私有实现  =======*/
    private function CooldownWheel() {
        slots = new Array(WHEEL_SIZE);
        for (var i:Number = 0; i < WHEEL_SIZE; ++i) slots[i] = [];
        // 驱动
        var clip:MovieClip = _root.createEmptyMovieClip("_cdWheel", _root.getNextHighestDepth());
        var self:CooldownWheel = this;
        clip.onEnterFrame = function() { self.tick(); };
    }

    /** 添加一次性任务：delay = 步长(帧)，callback = 下一格 */
    public function add(delay:Number, callback:Function):Void {
        var slot:Number = (pos + (delay % WHEEL_SIZE) + WHEEL_SIZE) % WHEEL_SIZE;
        slots[slot].push(callback);
    }

    /** 每帧调用 */
    public function tick():Void {
        // 执行当前槽
        var list:Array = slots[pos];
        while (list.length) (list.pop())();      // LIFO 执行，次序无关紧要
        // 清槽并拨轮
        pos = (pos + 1) % WHEEL_SIZE;
    }
}
