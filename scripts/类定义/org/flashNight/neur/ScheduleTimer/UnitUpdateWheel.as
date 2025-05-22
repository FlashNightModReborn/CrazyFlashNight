/**
 * UnitUpdateWheel.as (优化版本)
 * ——————————————————————————————————————————
 * 优化点：
 * 1. 修复数据一致性问题
 * 2. 改进删除算法，通过标记懒操作以提高性能
 * 3. 增强错误处理
 * 4. 优化内存使用
 * 5. 添加调试和统计功能
 */
class org.flashNight.neur.ScheduleTimer.UnitUpdateWheel {
    // ————————————————————————
    // 配置常量 & 私有字段
    // ————————————————————————
    private static var WHEEL_SIZE:Number = 4;           // 时间轮槽数
    private var slots:Array;                            // Array<Number>[], 存储unit ID列表
    private var unitDict:Object;                        // ID -> MovieClip 映射
    private var slotDict:Object;                        // ID -> slot索引 映射
    private var counter:Number = 0;                     // 全局ID计数器
    private var currentPos:Number = WHEEL_SIZE - 1;     // 当前处理位置
    private static var inst:UnitUpdateWheel;            // 单例引用
    
    // 统计信息（可选）
    private var totalUnits:Number = 0;                  // 当前总单位数
    private var processedCount:Number = 0;              // 已处理计数
    
    // ————————————————————————
    // 单例获取
    // ————————————————————————
    public static function I():UnitUpdateWheel {
        return inst || (inst = new UnitUpdateWheel());
    }
    
    // ————————————————————————
    // 构造函数（私有）
    // ————————————————————————
    private function UnitUpdateWheel() {
        slots = new Array(WHEEL_SIZE);
        for (var i:Number = 0; i < WHEEL_SIZE; i++) {
            slots[i] = [];
        }
        unitDict = {};
        slotDict = {};
    }
    
    // ————————————————————————
    // 公开方法
    // ————————————————————————
    
    /**
     * 添加 update 任务
     * @param unit 目标单位
     * @return 分配的ID，如果已存在则返回现有ID
     */
    public function add(unit:MovieClip):Number {
        // 防重复添加
        if (unit.updateEventComponentID != null) {
            return unit.updateEventComponentID;
        }
        
        var id:Number = ++counter;
        var targetSlot:Number = currentPos;
        
        // 添加到数据结构
        slots[targetSlot].push(id);
        unitDict[id] = unit;
        slotDict[id] = targetSlot;
        unit.updateEventComponentID = id;
        
        totalUnits++;
        return id;
    }
    
    /**
     * 移除 update 任务（优化版本）
     * @param unit 目标单位
     */
    public function remove(unit:MovieClip):Void {
        var id:Number = unit.updateEventComponentID;
        
        // 参数验证
        if (id == null || unitDict[id] !== unit) {
            return;
        }
        
        // 快速删除：不需要遍历数组，只需标记删除
        // 在tick时会自动清理无效引用
        delete unitDict[id];
        delete slotDict[id];
        unit.updateEventComponentID = null;
        totalUnits--;
    }
    
    /**
     * 强制立即移除（遍历查找版本，适用于紧急情况）
     * @param unit 目标单位
     */
    public function forceRemove(unit:MovieClip):Void {
        var id:Number = unit.updateEventComponentID;
        if (id == null) return;
        
        var slotIndex:Number = slotDict[id];
        if (slotIndex != null) {
            var list:Array = slots[slotIndex];
            for (var i:Number = list.length - 1; i >= 0; i--) {
                if (list[i] == id) {
                    list.splice(i, 1);
                    break;
                }
            }
        }
        
        delete unitDict[id];
        delete slotDict[id];
        unit.updateEventComponentID = null;
        totalUnits--;
    }
    
    /**
     * 时间轮前进一帧
     */
    public function tick():Void {
        // 移动到下一个槽位
        currentPos = (currentPos + 1) % WHEEL_SIZE;
        
        var list:Array = slots[currentPos];
        var cleanupNeeded:Boolean = false;
        
        // 处理当前槽位的所有单位
        for (var i:Number = list.length - 1; i >= 0; i--) {
            var id:Number = list[i];
            var unit:MovieClip = unitDict[id];
            
            // 检查单位是否仍然有效
            if (unit == null || unit.dispatcher == null) {
                // 标记需要清理
                list.splice(i, 1);
                if (unit != null) {
                    unit.updateEventComponentID = null;
                }
                delete unitDict[id];
                delete slotDict[id];
                cleanupNeeded = true;
                continue;
            }
            
            // 发布更新事件
            try {
                unit.dispatcher.publish("UpdateEventComponent", unit);
                processedCount++;
            } catch (e:Error) {
                // 发布事件失败，移除该单位
                list.splice(i, 1);
                unit.updateEventComponentID = null;
                delete unitDict[id];
                delete slotDict[id];
                cleanupNeeded = true;
            }
        }
        
        // 更新统计信息
        if (cleanupNeeded) {
            totalUnits = getTotalUnitsCount();
        }
    }
    
    /**
     * 获取统计信息
     */
    public function getStats():Object {
        return {
            totalUnits: totalUnits,
            processedCount: processedCount,
            currentPos: currentPos,
            slotsDistribution: getSlotDistribution()
        };
    }
    
    /**
     * 重置时间轮
     */
    public function reset():Void {
        // 清理所有单位的ID标记
        for (var id:String in unitDict) {
            var unit:MovieClip = unitDict[id];
            if (unit != null) {
                unit.updateEventComponentID = null;
            }
        }
        
        // 重置数据结构
        for (var i:Number = 0; i < WHEEL_SIZE; i++) {
            slots[i] = [];
        }
        currentPos = WHEEL_SIZE - 1;
        unitDict = {};
        slotDict = {};
        counter = 0;
        totalUnits = 0;
        processedCount = 0;
    }
    
    // ————————————————————————
    // 私有辅助方法
    // ————————————————————————
    
    /**
     * 计算实际的单位总数（用于验证统计信息）
     */
    private function getTotalUnitsCount():Number {
        var count:Number = 0;
        for (var id:String in unitDict) {
            if (unitDict[id] != null) {
                count++;
            }
        }
        return count;
    }
    
    /**
     * 获取各槽位的单位分布情况
     */
    private function getSlotDistribution():Array {
        var distribution:Array = [];
        for (var i:Number = 0; i < WHEEL_SIZE; i++) {
            distribution[i] = slots[i].length;
        }
        return distribution;
    }
    
    /**
     * 清理无效引用（可定期调用）
     */
    public function cleanup():Number {
        var cleaned:Number = 0;
        
        for (var i:Number = 0; i < WHEEL_SIZE; i++) {
            var list:Array = slots[i];
            for (var j:Number = list.length - 1; j >= 0; j--) {
                var id:Number = list[j];
                var unit:MovieClip = unitDict[id];
                
                if (unit == null || unit.dispatcher == null) {
                    list.splice(j, 1);
                    if (unit != null) {
                        unit.updateEventComponentID = null;
                    }
                    delete unitDict[id];
                    delete slotDict[id];
                    cleaned++;
                }
            }
        }
        
        totalUnits = getTotalUnitsCount();
        return cleaned;
    }
}