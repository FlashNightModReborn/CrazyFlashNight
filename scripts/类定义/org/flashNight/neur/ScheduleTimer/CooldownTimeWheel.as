/**
 * CooldownTimeWheel.as
 * 简化的技能冷却时间轮调度器
 * -----------------------------------------------------------------------------
 * 专为技能冷却设计的精简时间轮，只实现核心调度功能，确保可靠性。
 * 
 * 特点：
 *  1. 无动态内存分配，避免内存泄漏
 *  2. 固定时间轮结构，性能开销极小
 *  3. 专为技能冷却优化，去除不必要功能
 *  4. 提供与原有接口兼容的API
 *  5. 自动创建驱动影片剪辑，无需手动更新
 */
class org.flashNight.neur.ScheduleTimer.CooldownTimeWheel {
    // 时间轮大小，与步长对应（120毫秒为一步）
    private static var WHEEL_SIZE:Number = 120;
    
    // 时间轮槽位，每个槽位存放任务链表
    private var timeSlots:Array;
    
    // 当前时间轮指针位置
    private var currentPosition:Number;
    
    // 任务ID生成器
    private var taskIdCounter:Number;
    
    // 驱动更新的影片剪辑
    private var driverClip:MovieClip;
    
    // 单例实例引用
    private static var instance:CooldownTimeWheel;
    
    /**
     * 任务节点内部类
     * -----------------------------------------------------------------------------
     * 用于构造时间轮中的任务
     */
    private function TaskNode(id:String, action:Function, repeatCount:Number) {
        this.id = id;
        this.action = action;
        this.repeatCount = repeatCount;
        this.next = null;
    }
    
    /**
     * 构造函数
     * -----------------------------------------------------------------------------
     * 私有构造，确保单例模式
     */
    private function CooldownTimeWheel() {
        this.timeSlots = new Array(WHEEL_SIZE);
        this.currentPosition = 0;
        this.taskIdCounter = 0;
        
        // 初始化时间轮槽位
        for (var i:Number = 0; i < WHEEL_SIZE; i++) {
            this.timeSlots[i] = null;
        }
        
        // 创建驱动影片剪辑
        this.createDriverClip();
    }
    
    /**
     * 获取单例实例
     * -----------------------------------------------------------------------------
     * 确保整个应用只有一个时间轮实例
     */
    public static function getInstance():CooldownTimeWheel {
        if (instance == null) {
            instance = new CooldownTimeWheel();
        }
        return instance;
    }
    
    /**
     * 创建驱动影片剪辑
     * -----------------------------------------------------------------------------
     * 在_root层级创建一个空MovieClip，通过onEnterFrame驱动update
     */
    private function createDriverClip():Void {
        var depth:Number = _root.getNextHighestDepth();
        this.driverClip = _root.createEmptyMovieClip("_timeWheelDriver", depth);
        
        var self:CooldownTimeWheel = this;
        this.driverClip.onEnterFrame = function():Void {
            self.update();
        };
    }
    
    /**
     * 添加冷却任务
     * -----------------------------------------------------------------------------
     * 兼容原有接口的任务添加方法
     *
     * @param action 任务回调函数
     * @param interval 间隔时间（步长，默认为120）
     * @param repeatCount 重复次数
     * @return 任务ID字符串
     */
    public function addTask(action:Function, interval:Number, repeatCount:Number):String {
        var taskId:String = String(++this.taskIdCounter);
        
        // 计算任务应放入的槽位
        var slotIndex:Number = (this.currentPosition + interval) % WHEEL_SIZE;
        
        // 创建新任务节点
        var newTask:TaskNode = new TaskNode(taskId, action, repeatCount);
        
        // 将任务插入到对应槽位链表头部
        newTask.next = this.timeSlots[slotIndex];
        this.timeSlots[slotIndex] = newTask;
        
        return taskId;
    }
    
    /**
     * 时间轮更新方法
     * -----------------------------------------------------------------------------
     * 由驱动MovieClip的onEnterFrame自动调用
     */
    private function update():Void {
        // 获取当前槽位的任务链表
        var current:TaskNode = this.timeSlots[this.currentPosition];
        var prev:TaskNode = null;
        
        // 处理当前槽位的所有任务
        while (current != null) {
            var next:TaskNode = current.next;
            
            // 执行任务
            current.action();
            
            // 减少重复次数
            current.repeatCount--;
            
            // 判断任务是否完成
            if (current.repeatCount <= 0) {
                // 移除完成的任务
                if (prev == null) {
                    this.timeSlots[this.currentPosition] = next;
                } else {
                    prev.next = next;
                }
            } else {
                // 如果还需要重复，重新调度到未来的槽位
                var futureSlot:Number = (this.currentPosition + 120) % WHEEL_SIZE;
                
                // 从当前位置移除任务
                if (prev == null) {
                    this.timeSlots[this.currentPosition] = next;
                } else {
                    prev.next = next;
                }
                
                // 添加到未来槽位
                current.next = this.timeSlots[futureSlot];
                this.timeSlots[futureSlot] = current;
            }
            
            current = next;
        }
        
        // 移动时间轮指针
        this.currentPosition = (this.currentPosition + 1) % WHEEL_SIZE;
    }
    
    /**
     * 重置时间轮
     * -----------------------------------------------------------------------------
     * 清除所有任务
     */
    public function reset():Void {
        for (var i:Number = 0; i < WHEEL_SIZE; i++) {
            this.timeSlots[i] = null;
        }
        this.currentPosition = 0;
    }
    
    /**
     * 销毁时间轮
     * -----------------------------------------------------------------------------
     * 清理驱动MovieClip和所有任务
     */
    public function destroy():Void {
        // 移除驱动影片剪辑
        this.driverClip.removeMovieClip();
        
        // 清除时间轮
        this.reset();
        
        // 清除静态引用
        instance = null;
    }
}