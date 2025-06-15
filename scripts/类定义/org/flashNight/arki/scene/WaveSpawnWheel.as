import org.flashNight.arki.scene.WaveSpawner;

/**
 * WaveSpawnWheel 类：一个简化的单级时间轮，用于高效管理和调度定时任务。
 * 适用于高频、固定循环任务场景，且所有任务执行同一函数。
 */
class org.flashNight.arki.scene.WaveSpawnWheel {
    public static var instance:WaveSpawnWheel; // 单例引用
    private var waveSpawner:WaveSpawner; // WaveSpawner单例

    private var slots:Array; // 时间轮的槽位数组，每个槽位存储一个参数包装对象数组
    private var currentPointer:Number = 0; // 当前指针，指向当前处理的槽位
    private var wheelSize:Number = 60; // 时间轮的大小，固定为60

    private var longDelayTasks:Array;

    public static function getInstance():WaveSpawnWheel {
        return instance || (instance = new WaveSpawnWheel());
    }

    /**
     * 构造函数（私有）
     */
    private function WaveSpawnWheel() {
    }

    /**
     * 初始化时间轮。
     * wheelSize固定为60，不需要自定义。
     */
    public function init():Void{
        this.waveSpawner = WaveSpawner.instance;
        this.slots = new Array(this.wheelSize);
        this.longDelayTasks = [];
        this.currentPointer = 0;
    }
    
    public function clear():Void{
        this.slots = null;
        this.longDelayTasks = null;
        this.currentPointer = 0;
    }

    /**
     * 获取时间轮的当前状态，包括当前指针位置、轮大小和每个槽位的任务数量。
     * WaveSpawnWheel不使用节点池，因此不包含节点池信息。
     *
     * @return 一个包含时间轮状态信息的对象。
     */
    public function getTimeWheelStatus():Object {
        var paramCounts:Array = new Array(this.wheelSize); // 存储每个槽位的参数数量
        for (var i:Number = 0; i < this.wheelSize; i++) {
            if (this.slots[i] == null) {
                paramCounts[i] = 0; // 如果槽位为空，参数数量为 0
            } else {
                paramCounts[i] = this.slots[i].length; // 获取槽位中的参数数量 (数组长度)
            }
        }
        return {
            currentPointer: this.currentPointer, // 当前指针位置
            wheelSize: this.wheelSize, // 时间轮的大小
            paramCounts: paramCounts // 每个槽位的参数数量
        };
    }

    /**
     * 获取时间轮的当前数据，包括当前指针位置和轮大小。
     *
     * @return 一个包含当前指针和轮大小的对象。
     */
    public function getTimeWheelData():Object {
        return { 
            currentPointer: this.currentPointer, // 当前指针位置
            wheelSize: this.wheelSize // 时间轮的大小
        };
    }

    /**
     * 内部辅助方法，用于将包装后的参数（包含原始参数和延迟信息）添加到指定槽位。
     *
     * @param wrapper 包含 {param: Object, delay: Number, slotIndex: Number} 的包装对象。
     */
    private function _addToSlot(wrapper:Object):Void {
        // 规范化延迟，确保 slotIndex 非负且小于 wheelSize
        // (currentPointer + ((delay % wheelSize) + wheelSize) % wheelSize) % wheelSize
        // 这里的 ((delay % wheelSize) + wheelSize) % wheelSize 是为了确保结果为正数，即使 delay 是负数
        var slotIndex:Number = (this.currentPointer + ((wrapper.delay % this.wheelSize) + this.wheelSize) % this.wheelSize) % this.wheelSize;

        // 获取槽位，如果槽位未初始化则创建新的数组
        if (this.slots[slotIndex] == null) {
            this.slots[slotIndex] = new Array();
        }
        // 将包装后的参数添加到槽位的数组中
        this.slots[slotIndex].push(wrapper);
        // wrapper.slotIndex = slotIndex; // 记录包装对象所在的槽位索引
    }

    /**
     * 内部辅助方法，用于将包装后的参数（包含原始参数和延迟信息）添加到长时间任务列表。
     *
     * @param wrapper 包装对象。
     */
    private function _addToLongDelayTasks(wrapper:Object):Void {
        // 将包装后的参数添加长时间任务列表中
        wrapper.delayCount = wrapper.delay;
        this.longDelayTasks.push(wrapper);
    }

    /**
     * 添加定时器。
     *
     * @param delay 延迟的时间步数。
     */
    public function addTask(quantity:Number, delay:Number, attribute, index:Number, waveIndex:Number):Void{
        if (delay < 1) {
            delay = 1;
        }
        // 创建一个包装对象，包含原始参数和用于重新调度的延迟信息
        var wrapper:Object = {
            quantity:quantity,
            delay: delay, // 存储原始延迟，用于后续的自动重新调度（循环任务）
            attribute: attribute,
            index: index,
            waveIndex: waveIndex
        };

        if(delay >= this.wheelSize) this._addToLongDelayTasks(wrapper);
        else this._addToSlot(wrapper);
    }

    /**
     * 移除定时器。
     * 遍历所有槽位，找到与给定 `param` 对象严格相等的任务并移除。
     * 注意：`param` 必须是当初调用 `addTask` 时传入的同一个对象实例。
     *
     * @param param 要移除的任务参数对象。
     */
    public function removeTask(param:Object):Void {
        var wrapper:Object;
        for (var i:Number = 0; i < this.wheelSize; i++) { // 遍历所有槽位
            var slot:Array = this.slots[i];
            if (slot != null) { // 如果槽位中有参数
                for (var j:Number = 0; j < slot.length; j++) {
                    wrapper = slot[j];
                    if (wrapper.param === param) { // 找到匹配的参数 (使用严格相等检查对象引用)
                        slot.splice(j, 1); // 从数组中移除
                        // 如果槽位变空，可以将其设为 null 节省内存，避免空数组占用
                        if (slot.length == 0) {
                            this.slots[i] = null;
                        }
                        return; // 成功移除后退出函数
                    }
                }
            }
        }
    }


    /**
     * 执行 tick 操作，推进时间轮的当前指针，并执行当前槽位中的所有任务。
     * 同时，自动将任务重新调度，实现循环任务。
     */
    public function tick():Void {
        var i:Number;
        var wrapper:Object;
        var currentSlotTasks:Array = this.slots[this.currentPointer]; // 获取当前槽位中的任务参数数组
        this.slots[this.currentPointer] = null; // 清空当前槽位，准备下一次填充

        this.currentPointer = (this.currentPointer + 1) % this.wheelSize; // 推进指针，循环回绕

        if (currentSlotTasks.length > 0) {
            // 遍历并执行当前槽位中的所有任务
            for (i = 0; i < currentSlotTasks.length; i++) {
                wrapper = currentSlotTasks[i];
                
                // 执行 spawn 函数
                wrapper.quantity = this.waveSpawner.spawn(wrapper.attribute, wrapper.index, wrapper.waveIndex, wrapper.quantity);
                // 重新调度任务（实现循环任务）
                if(wrapper.quantity > 0) this._addToSlot(wrapper);
            }
        }

        for(i = this.longDelayTasks.length - 1; i > -1; i--){
            wrapper = longDelayTasks[i];
            wrapper.delayCount--;
            if(wrapper.delayCount <= 0){
                wrapper.quantity = this.waveSpawner.spawn(wrapper.attribute, wrapper.index, wrapper.waveIndex, wrapper.quantity);
                if(wrapper.quantity > 0){
                    wrapper.delayCount = wrapper.delay;
                }else{
                    longDelayTasks.splice(i,1);
                }
            }
        }
    }
}
