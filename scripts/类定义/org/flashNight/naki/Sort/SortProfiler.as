class org.flashNight.naki.Sort.SortProfiler {
    
    // 性能计数器
    public var comparisons:Number = 0;      // 比较次数
    public var swaps:Number = 0;            // 交换次数
    public var partitions:Number = 0;       // 分区次数
    public var badSplits:Number = 0;        // 坏分割次数
    public var heapsortCalls:Number = 0;    // 堆排序触发次数
    public var maxStackDepth:Number = 0;    // 最大栈深度
    public var currentStackDepth:Number = 0;// 当前栈深度
    
    // 启用标志
    private var enabled:Boolean = false;
    
    /**
     * 构造函数
     */
    public function SortProfiler() {
        reset();
    }
    
    /**
     * 启用/禁用性能分析
     */
    public function setEnabled(value:Boolean):Void {
        enabled = value;
        if (enabled) {
            reset();
        }
    }
    
    /**
     * 检查是否启用
     */
    public function isEnabled():Boolean {
        return enabled;
    }
    
    /**
     * 重置所有计数器
     */
    public function reset():Void {
        comparisons = 0;
        swaps = 0;
        partitions = 0;
        badSplits = 0;
        heapsortCalls = 0;
        maxStackDepth = 0;
        currentStackDepth = 0;
    }
    
    /**
     * 记录一次比较
     */
    public function recordComparison():Void {
        if (enabled) comparisons++;
    }
    
    /**
     * 记录一次交换
     */
    public function recordSwap():Void {
        if (enabled) swaps++;
    }
    
    /**
     * 记录一次分区操作
     */
    public function recordPartition():Void {
        if (enabled) partitions++;
    }
    
    /**
     * 记录一次坏分割
     */
    public function recordBadSplit():Void {
        if (enabled) badSplits++;
    }
    
    /**
     * 记录一次堆排序调用
     */
    public function recordHeapsortCall():Void {
        if (enabled) heapsortCalls++;
    }
    
    /**
     * 更新栈深度
     */
    public function updateStackDepth(depth:Number):Void {
        if (enabled) {
            currentStackDepth = depth;
            if (depth > maxStackDepth) {
                maxStackDepth = depth;
            }
        }
    }
    
    /**
     * 获取性能报告
     */
    public function getReport():String {
        var report:String = "\n=== Sort Performance Report ===\n";
        report += "Comparisons: " + comparisons + "\n";
        report += "Swaps: " + swaps + "\n";
        report += "Partitions: " + partitions + "\n";
        report += "Bad Splits: " + badSplits + "\n";
        report += "Heapsort Calls: " + heapsortCalls + "\n";
        report += "Max Stack Depth: " + maxStackDepth + "\n";
        report += "==============================\n";
        return report;
    }
    
    /**
     * 获取简短报告
     */
    public function getShortReport():String {
        return "Cmp:" + comparisons + " Swp:" + swaps + " Part:" + partitions + 
               " Bad:" + badSplits + " Heap:" + heapsortCalls + " Stack:" + maxStackDepth;
    }
    
    /**
     * 导出为对象
     */
    public function toObject():Object {
        return {
            comparisons: comparisons,
            swaps: swaps,
            partitions: partitions,
            badSplits: badSplits,
            heapsortCalls: heapsortCalls,
            maxStackDepth: maxStackDepth
        };
    }
}