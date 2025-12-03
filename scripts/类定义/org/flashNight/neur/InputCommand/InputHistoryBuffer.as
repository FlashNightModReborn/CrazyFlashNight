/**
 * InputHistoryBuffer - 输入事件历史环形缓冲区
 * 
 * 用于存储最近若干帧的输入事件序列，支持：
 * - 环形缓冲：自动丢弃超出容量的旧事件
 * - 帧边界标记：记录每帧事件的起止位置
 * - 窗口查询：获取最近 N 帧的事件序列
 * - 零 GC 设计：复用内部数组，避免频繁分配
 *
 * 与 TrieDFA 的 findAllFastInRange / matchAtRaw 配合使用，
 * 实现基于滑动窗口的搓招识别。
 *
 * 使用方式：
 *   var buffer:InputHistoryBuffer = new InputHistoryBuffer(64, 30);
 *
 *   // 每帧调用
 *   buffer.appendFrame(sampler.sample(unit));
 *
 *   // 获取用于匹配的序列
 *   var seq:Array = buffer.getSequence();
 *   var from:Number = buffer.getWindowStart(10); // 最近10帧
 *   dfa.findAllFastInRange(seq, from, seq.length);
 *
 * @author FlashNight
 * @version 1.0
 */
class org.flashNight.neur.InputCommand.InputHistoryBuffer {

    // ========== 配置常量 ==========

    /** 默认事件容量 */
    public static var DEFAULT_EVENT_CAPACITY:Number = 64;

    /** 默认帧容量 */
    public static var DEFAULT_FRAME_CAPACITY:Number = 30;

    // ========== 内部数据结构 ==========

    /**
     * 事件序列缓冲区（线性数组，逻辑上环形使用）
     * 存储所有输入事件的 ID
     */
    private var events:Array;

    /** 事件缓冲区容量 */
    private var eventCapacity:Number;

    /** 当前事件数量 */
    private var eventCount:Number;

    /**
     * 帧信息数组
     * frameInfo[i] = {start:Number, count:Number, timestamp:Number}
     * - start: 该帧第一个事件在 events 中的位置
     * - count: 该帧事件数量
     * - timestamp: 帧时间戳（可选，用于基于时间的超时）
     */
    private var frameInfo:Array;

    /** 帧信息容量 */
    private var frameCapacity:Number;

    /** 当前帧数量 */
    private var frameCount:Number;

    /** 帧序号（用于环形索引计算） */
    private var frameHead:Number;

    /** 全局帧计数器（用于时间戳） */
    private var globalFrameCounter:Number;

    // ========== 窗口匹配辅助 ==========

    /**
     * 导出序列缓冲区（复用，避免每次 getSequence 创建新数组）
     */
    private var exportBuffer:Array;

    /** 导出缓冲区是否需要重建 */
    private var exportDirty:Boolean;

    // ========== 构造函数 ==========

    /**
     * 创建 InputHistoryBuffer 实例
     *
     * @param eventCapacity 事件容量（默认64，建议 >= maxPatternLen * 2）
     * @param frameCapacity 帧容量（默认30，约1秒@30fps）
     */
    public function InputHistoryBuffer(eventCapacity:Number, frameCapacity:Number) {
        if (eventCapacity == undefined || eventCapacity < 16) {
            eventCapacity = DEFAULT_EVENT_CAPACITY;
        }
        if (frameCapacity == undefined || frameCapacity < 10) {
            frameCapacity = DEFAULT_FRAME_CAPACITY;
        }

        this.eventCapacity = eventCapacity;
        this.frameCapacity = frameCapacity;

        this.events = new Array(eventCapacity);
        this.eventCount = 0;

        this.frameInfo = new Array(frameCapacity);
        for (var i:Number = 0; i < frameCapacity; i++) {
            this.frameInfo[i] = {start: 0, count: 0, timestamp: 0};
        }
        this.frameCount = 0;
        this.frameHead = 0;

        this.globalFrameCounter = 0;

        this.exportBuffer = [];
        this.exportDirty = true;
    }

    // ========== 核心操作 ==========

    /**
     * 追加一帧的输入事件
     *
     * @param frameEvents 本帧事件数组（来自 InputSampler.sample()）
     * @param timestamp 可选时间戳（默认使用内部帧计数器）
     */
    public function appendFrame(frameEvents:Array, timestamp:Number):Void {
        if (timestamp == undefined) {
            timestamp = this.globalFrameCounter;
        }
        this.globalFrameCounter++;

        var evCount:Number = (frameEvents != undefined) ? frameEvents.length : 0;

        // 计算新帧在 frameInfo 中的位置（环形）
        var frameIdx:Number = (this.frameHead + this.frameCount) % this.frameCapacity;

        // 如果帧缓冲已满，需要丢弃最老的帧
        if (this.frameCount >= this.frameCapacity) {
            // 丢弃最老帧的事件
            var oldFrame:Object = this.frameInfo[this.frameHead];
            this.discardOldestEvents(oldFrame.count);

            // 移动帧头
            this.frameHead = (this.frameHead + 1) % this.frameCapacity;
            // frameCount 不变（替换而非增长）
            frameIdx = (this.frameHead + this.frameCount - 1) % this.frameCapacity;
        } else {
            this.frameCount++;
        }

        // 检查事件容量，必要时丢弃更多旧事件
        while (this.eventCount + evCount > this.eventCapacity && this.frameCount > 1) {
            var oldestFrame:Object = this.frameInfo[this.frameHead];
            this.discardOldestEvents(oldestFrame.count);
            this.frameHead = (this.frameHead + 1) % this.frameCapacity;
            this.frameCount--;
        }

        // 记录新帧信息
        var startPos:Number = this.eventCount;
        var info:Object = this.frameInfo[frameIdx];
        info.start = startPos;
        info.count = evCount;
        info.timestamp = timestamp;

        // 追加事件
        for (var i:Number = 0; i < evCount; i++) {
            this.events[this.eventCount] = frameEvents[i];
            this.eventCount++;
        }

        this.exportDirty = true;
    }

    /**
     * 丢弃最老的 N 个事件（内部方法）
     */
    private function discardOldestEvents(count:Number):Void {
        if (count <= 0 || this.eventCount == 0) return;

        // 将剩余事件前移
        var remaining:Number = this.eventCount - count;
        for (var i:Number = 0; i < remaining; i++) {
            this.events[i] = this.events[i + count];
        }
        this.eventCount = remaining;

        // 更新所有帧的 start 位置
        for (var f:Number = 0; f < this.frameCount; f++) {
            var idx:Number = (this.frameHead + f) % this.frameCapacity;
            this.frameInfo[idx].start -= count;
        }

        this.exportDirty = true;
    }

    /**
     * 清空缓冲区
     */
    public function clear():Void {
        this.eventCount = 0;
        this.frameCount = 0;
        this.frameHead = 0;
        this.exportDirty = true;
    }

    // ========== 查询接口 ==========

    /**
     * 获取事件序列（用于 TrieDFA 匹配）
     *
     * 返回的是内部数组的引用（或复制），长度为 eventCount。
     * 注意：为避免 GC，返回的是复用的 exportBuffer。
     *
     * @return 事件序列数组
     */
    public function getSequence():Array {
        if (this.exportDirty) {
            this.rebuildExportBuffer();
        }
        return this.exportBuffer;
    }

    /**
     * 重建导出缓冲区（内部方法）
     */
    private function rebuildExportBuffer():Void {
        // 调整长度
        this.exportBuffer.length = this.eventCount;

        // 复制事件
        for (var i:Number = 0; i < this.eventCount; i++) {
            this.exportBuffer[i] = this.events[i];
        }

        this.exportDirty = false;
    }

    /**
     * 获取当前事件数量
     */
    public function getEventCount():Number {
        return this.eventCount;
    }

    /**
     * 获取当前帧数量
     */
    public function getFrameCount():Number {
        return this.frameCount;
    }

    /**
     * 获取最近 N 帧的起始位置（用于 findAllFastInRange 的 from 参数）
     *
     * @param frameWindow 帧窗口大小
     * @return 起始事件位置
     */
    public function getWindowStart(frameWindow:Number):Number {
        if (frameWindow <= 0 || this.frameCount == 0) {
            return this.eventCount; // 返回末尾，表示空窗口
        }

        if (frameWindow >= this.frameCount) {
            return 0; // 返回开头，表示全部
        }

        // 计算目标帧的索引
        var targetFrameOffset:Number = this.frameCount - frameWindow;
        var targetFrameIdx:Number = (this.frameHead + targetFrameOffset) % this.frameCapacity;

        return this.frameInfo[targetFrameIdx].start;
    }

    /**
     * 获取指定时间戳之后的起始位置
     *
     * @param minTimestamp 最小时间戳（包含）
     * @return 起始事件位置
     */
    public function getWindowStartByTime(minTimestamp:Number):Number {
        // 从最老帧开始查找
        for (var f:Number = 0; f < this.frameCount; f++) {
            var idx:Number = (this.frameHead + f) % this.frameCapacity;
            if (this.frameInfo[idx].timestamp >= minTimestamp) {
                return this.frameInfo[idx].start;
            }
        }
        return this.eventCount; // 没有符合条件的帧
    }

    /**
     * 获取最后一帧的事件起始位置
     */
    public function getLastFrameStart():Number {
        if (this.frameCount == 0) return 0;

        var lastIdx:Number = (this.frameHead + this.frameCount - 1) % this.frameCapacity;
        return this.frameInfo[lastIdx].start;
    }

    /**
     * 获取最后一帧的事件数量
     */
    public function getLastFrameEventCount():Number {
        if (this.frameCount == 0) return 0;

        var lastIdx:Number = (this.frameHead + this.frameCount - 1) % this.frameCapacity;
        return this.frameInfo[lastIdx].count;
    }

    /**
     * 获取最后一帧的时间戳
     */
    public function getLastFrameTimestamp():Number {
        if (this.frameCount == 0) return 0;

        var lastIdx:Number = (this.frameHead + this.frameCount - 1) % this.frameCapacity;
        return this.frameInfo[lastIdx].timestamp;
    }

    /**
     * 获取全局帧计数器
     */
    public function getGlobalFrameCounter():Number {
        return this.globalFrameCounter;
    }

    // ========== 高级查询 ==========

    /**
     * 获取指定帧范围内的事件序列
     *
     * @param fromFrame 起始帧偏移（0 = 最老帧）
     * @param toFrame 结束帧偏移（不包含）
     * @return 事件序列范围 {start:Number, end:Number}
     */
    public function getFrameRange(fromFrame:Number, toFrame:Number):Object {
        if (fromFrame < 0) fromFrame = 0;
        if (toFrame > this.frameCount) toFrame = this.frameCount;
        if (fromFrame >= toFrame) {
            return {start: this.eventCount, end: this.eventCount};
        }

        var startIdx:Number = (this.frameHead + fromFrame) % this.frameCapacity;
        var endIdx:Number = (this.frameHead + toFrame - 1) % this.frameCapacity;

        var startPos:Number = this.frameInfo[startIdx].start;
        var endInfo:Object = this.frameInfo[endIdx];
        var endPos:Number = endInfo.start + endInfo.count;

        return {start: startPos, end: endPos};
    }

    /**
     * 检查缓冲区是否为空
     */
    public function isEmpty():Boolean {
        return this.eventCount == 0;
    }

    /**
     * 获取缓冲区容量信息
     */
    public function getCapacityInfo():Object {
        return {
            eventCapacity: this.eventCapacity,
            eventCount: this.eventCount,
            eventUsage: this.eventCount / this.eventCapacity,
            frameCapacity: this.frameCapacity,
            frameCount: this.frameCount,
            frameUsage: this.frameCount / this.frameCapacity
        };
    }

    // ========== 调试方法 ==========

    /**
     * 打印缓冲区状态（调试用）
     */
    public function dump():Void {
        trace("===== InputHistoryBuffer Dump =====");
        trace("Events: " + this.eventCount + "/" + this.eventCapacity);
        trace("Frames: " + this.frameCount + "/" + this.frameCapacity);
        trace("Global frame: " + this.globalFrameCounter);

        trace("\n--- Frames ---");
        for (var f:Number = 0; f < this.frameCount; f++) {
            var idx:Number = (this.frameHead + f) % this.frameCapacity;
            var info:Object = this.frameInfo[idx];
            var evStr:String = "";
            for (var e:Number = 0; e < info.count; e++) {
                if (e > 0) evStr += ",";
                evStr += this.events[info.start + e];
            }
            trace("  [" + f + "] ts=" + info.timestamp +
                  " start=" + info.start +
                  " count=" + info.count +
                  " events=[" + evStr + "]");
        }

        trace("\n--- Event Sequence ---");
        var seq:Array = this.getSequence();
        trace("  [" + seq.join(",") + "]");

        trace("===================================");
    }
}
