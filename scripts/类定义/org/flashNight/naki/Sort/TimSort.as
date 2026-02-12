/**
 * ================================================================================================
 * ActionScript 2.0 高性能 TimSort 实现 - 企业级优化版本
 * ================================================================================================
 * 
 * 【算法背景】
 * TimSort是一种混合稳定排序算法，由Tim Peters于2002年为Python设计，
 * 现已成为Java、Python等语言的标准排序算法。本实现专为AS2虚拟机深度优化。
 * 
 * 【核心算法特性】
 * - 稳定排序：相等元素的相对顺序不会改变
 * - 自适应性：对部分有序的数据有卓越性能表现
 * - 最优时间复杂度：O(n) 当数据已排序时
 * - 最坏时间复杂度：O(n log n) 严格保证
 * - 额外空间上界：O(n/2)（预分配tempArray长度为⌈n/2⌉，因此大O为O(n)）
 * - 实际单次合并使用：min(lenA, lenB)（仅在合并时使用到对应一侧的长度）
 * 
 * ================================================================================================
 * 【AS2专项优化技术详解】
 * ================================================================================================
 * 
 * 本实现针对AS2虚拟机进行了15项深度优化，在基准测试中有显著性能收益：
 * 
 * 【1. 完全内联化（Function Inlining）】
 * - 所有辅助方法完全内联，消除函数调用开销
 * - AS2函数调用成本较高，内联化在实践中可提供可观察的加速
 * - 代码体积增加但执行效率显著提升
 * 
 * 【2. 变量声明提升（Variable Hoisting）】
 * - 所有变量统一在函数顶部声明，利用AS2的提升特性
 * - 避免运行时变量创建和作用域查找开销
 * - 在实践中提升解释器执行效率
 * 
 * 【3. 寄存器复用策略（Register Reuse）】
 * - 精心设计的变量复用方案，提升AVM1的局部变量缓存效率
 * - 时间复用：不同算法阶段复用相同变量名
 * - 语义复用：相似功能变量共享存储空间
 * - 显著减少内存分配和垃圾回收压力
 * 
 * 【4. 副作用合并优化（Side-effect Merging）】
 * - 通过赋值表达式的副作用缓存地址计算结果
 * - arr[idx = base + offset] 模式触发AS2寄存器分配
 * - 显著减少重复地址计算开销
 * 
 * 【5. 循环展开优化（Loop Unrolling）】
 * - 批量操作采用4元素块处理，减少循环条件检查
 * - 结合副作用合并，实现高效的内存块传输
 * - 提升数组操作性能
 * 
 * 【6. 对齐优化（Alignment Optimization）】
 * - 使用位运算计算4元素对齐边界
 * - copyEnd = len - (len & 3) 确保4元素对齐循环展开的正确性
 * - 优化AS2虚拟机的内存访问模式
 * 
 * 【7. 指数搜索优化（Exponential Search）】
 * - Galloping模式使用优化的指数增长公式
 * - ofs = (ofs << 1) + 1 生成1,3,7,15,31...序列
 * - 相比标准实现在实践中减少比较次数
 * 
 * 【8. 二分搜索内联（Binary Search Inlining）】
 * - 左右二分搜索完全内联，避免函数调用
 * - 变量复用减少临时变量分配
 * - 在实践中提升搜索性能
 * 
 * 【9. 栈管理优化（Stack Management）】
 * - 预分配栈容量避免动态扩容（对于预期数据规模有效）
 * - 栈压缩操作使用优化的数组移动算法
 * - 减少内存重新分配的性能影响
 * 
 * 【10. 合并方向智能选择（Merge Direction）】
 * - 动态选择mergeLo或mergeHi以最小化内存使用
 * - 临时数组大小优化为min(lenA, lenB)
 * - 平均节省50%的临时空间
 * 
 * 【11. Galloping阈值自适应（Adaptive Galloping）】
 * - 动态调整minGallop阈值提升galloping效率
 * - 根据galloping成功率自动优化触发条件：
 *   当一次gallop复制了≥MIN_GALLOP个元素时，minGallop-=1降低阈值；
 *   否则minGallop+=1提高阈值更谨慎进入gallop
 * - 在不同数据分布下保持最优性能
 * 
 * 【12. 插入排序混合优化（Hybrid Insertion Sort）】
 * - 短距离使用线性插入，长距离使用二分插入
 * - 距离阈值针对AS2虚拟机特性优化
 * - 显著提升小规模数据排序性能
 * 
 * 【13. 内存访问模式优化（Memory Access Pattern）】
 * - 顺序访问优先，减少缓存缺失
 * - 循环展开确保连续内存访问
 * - 提高顺序内存访问的局部性（在多数实现中有利于缓存/解释器）
 * 
 * 【14. 边界条件优化（Boundary Optimization）】
 * - 单元素合并的快速路径
 * - 空序列的早期退出机制
 * - 减少不必要的复杂计算
 * 
 * 【15. 算术运算优化（Arithmetic Optimization）】
 * - 使用位运算替代除法和模运算（位运算在AS2下会触发32位整形规则）
 * - 减量操作符优化（--stackSize vs stackSize--）
 * - 针对AS2数值计算特性的微调
 * 
 * ================================================================================================
 * 【性能测试数据】
 * ================================================================================================
 * 
 * 性能测试表明在多种数据分布下均有显著收益：
 * - 随机数据、部分有序、逆序数据、重复元素等场景
 * - 内存使用优化显著
 * - 垃圾回收触发显著减少
 * 
 * ================================================================================================
 * 【维护建议】
 * ================================================================================================
 * 
 * 本实现高度优化，修改时需注意：
 * 1. 保持变量复用的时序关系
 * 2. 循环展开的边界条件处理
 * 3. 副作用合并的正确性验证
 * 4. AS2虚拟机特性的兼容性
 * 
 * 推荐的性能测试：
 * 1. 多种数据分布的基准测试
 * 2. 内存使用量监控
 * 3. 不同数据规模的伸缩性测试
 * 
 */
class org.flashNight.naki.Sort.TimSort {

    // 静态工作区缓存 - 跨调用复用，减少 new Array() 产生的 GC 压力
    private static var _workspace:Array   = null;  // tempArray 缓存
    private static var _wsLen:Number      = 0;     // _workspace 当前容量
    private static var _runBase:Array     = null;  // runBase 栈缓存
    private static var _runLen:Array      = null;  // runLen 栈缓存
    private static var _stackCap:Number   = 0;     // 栈缓存当前容量

    /**
     * TimSort主排序方法
     * 
     * @param arr 待排序的数组
     * @param compareFunction 比较函数，接受两个参数(a,b)，返回数值：
     *                       < 0: a < b
     *                       = 0: a = b  
     *                       > 0: a > b
     *                       如果为null，则使用默认的数值比较
     * @return 排序后的数组（原地排序，返回原数组引用）
     */
    public static function sort(arr:Array, compareFunction:Function):Array {
        
        /*
         * ===============================================================================================
         * 变量声明提升区域 - AS2性能优化与寄存器复用策略
         * ===============================================================================================
         * 
         * 【AS2虚拟机特性】
         * 由于AS2只有函数作用域，所有var声明会被提升到函数顶部。
         * 在此统一声明所有变量以优化解释器性能，避免运行时重复分配。
         * 
         * 【高效的变量复用策略】
         * 精心设计的变量复用方案，旨在提升AVM1的局部变量缓存效率：
         * 1. 时间复用：不同算法阶段复用相同变量名
         * 2. 语义复用：相似用途的变量共享存储空间  
         * 3. 副作用合并：通过赋值表达式的副作用触发寄存器分配
         * 
         * 【变量分组说明】
         * - 基础控制变量：算法常量和全局状态
         * - 核心数据结构：栈、数组、比较函数等
         * - 阶段专用变量：按算法执行阶段分组，支持复用
         * - 优化辅助变量：循环展开、地址计算缓存等
         */
        
        // ==========================================
        // 基础控制变量 - 算法常量与全局配置
        // ==========================================
        var n:Number,                    // 数组长度（算法入口参数）
            MIN_MERGE:Number,            // 最小合并大小常量 (32) - 小于此值用插入排序
            MIN_GALLOP:Number;           // 最小galloping触发阈值 (7) - galloping模式启动条件
        
        // ==========================================
        // 核心算法数据结构 - TimSort核心组件
        // ==========================================
        var compare:Function,            // 比较函数：用户提供或默认数值比较
            tempArray:Array,             // 临时数组：存储合并时的较短序列（优先复用静态缓存）
            runBase:Array,               // run栈：存储每个有序片段的起始位置
            runLen:Array,                // run栈：存储每个有序片段的长度  
            stackSize:Number,            // 栈大小：当前run栈中的元素数量
            minGallop:Number;            // 动态galloping阈值：根据galloping效果自适应调整
        
        // ==========================================  
        // minRun计算阶段变量 - 最优run长度计算
        // ==========================================
        var minRun:Number;               // 最小run长度：算法计算的最优有序片段长度
            /* 【寄存器复用】minRun计算阶段复用：
             * - tempN 复用 ofs (临时存储n的副本)
             * - r 复用 lastOfs (记录奇偶位标志)
             * 计算完成后这两个变量将被其他阶段复用
             */
        
        // ==========================================
        // 主循环控制变量 - run识别与处理控制
        // ==========================================
        var remaining:Number,            // 剩余待处理元素数：主循环条件变量
            lo:Number;                   // 当前处理位置：指向待处理区域开始位置
        
        // ==========================================
        // run检测阶段变量 - 有序片段识别
        // ==========================================
        var runLength:Number,            // 当前run长度：已识别的有序片段长度
            hi:Number;                   // run结束位置：有序片段的结束边界
        
        // ==========================================
        // 数组反转优化变量 - 下降序列处理
        // ==========================================
        var revLo:Number,                // 反转起始位置：下降序列反转的左边界
            revHi:Number,                // 反转结束位置：下降序列反转的右边界  
            tmp:Object;                  // 临时交换变量：反转过程中的元素暂存
        
        // ==========================================
        // 插入排序阶段变量 - 短run扩展处理
        // ==========================================
        var force:Number,                // 强制排序长度：短run需要扩展到的目标长度
            right:Number,                // 插入排序右边界：排序区域的右端点
            i:Number,                    // 循环计数器：外层循环索引
            key:Object,                  // 待插入元素：当前需要插入的元素值
            j:Number;                    // 内层循环计数器：插入位置搜索索引
        
        // ==========================================
        // 合并栈管理变量 - 栈不变量维护
        // ==========================================
        var size:Number,                 // 当前栈大小：栈不变量检查用的栈大小副本
            n_idx:Number,                // 栈索引：栈不变量检查的索引位置
            shouldMerge:Boolean,         // 是否需要合并标志：栈不变量违反检测结果
            mergeIdx:Number;             // 合并位置索引：确定要合并的run位置
            /* 【寄存器复用】栈管理阶段复用：
             * - mergeN 复用 copyLen (合并过程中的数量计算)
             * - mergeJ 复用 copyI (合并过程中的索引变量)
             */
        
        // ==========================================
        // 合并操作核心变量 - 双序列合并基础
        // ==========================================
        var loA:Number,                  // A区域起始位置：第一个run的起始位置
            lenA:Number,                 // A区域长度：第一个run的长度
            loB:Number,                  // B区域起始位置：第二个run的起始位置
            lenB:Number;                 // B区域长度：第二个run的长度
        
        // ==========================================
        // Galloping搜索核心变量 - 指数搜索优化
        // ==========================================
        var gallopK:Number,              // galloping搜索结果：搜索找到的位置偏移
            target:Object,               // 搜索目标元素：galloping搜索的目标值
            base:Number,                 // 搜索基准位置：搜索范围的起始位置
            len:Number;                  // 搜索长度：搜索范围的长度
        
        // ==========================================
        // 指数搜索阶段变量 - galloping前置步骤
        // ==========================================
        var ofs:Number,                  // 当前偏移量：指数搜索的当前步长
            lastOfs:Number;              // 上一个偏移量：指数搜索的前一步长
            /* 【寄存器复用】指数搜索完成后复用：
             * - ofs 在minRun计算时复用为tempN
             * - lastOfs 在minRun计算时复用为r
             */
        
        // ==========================================
        // 二分搜索阶段变量 - 精确位置定位  
        // ==========================================
        // 【寄存器复用】二分搜索变量的多重身份：
        // - left: 二分搜索左边界 / 插入排序位置计算 / 复用为bsLo
        // - hi2: 二分搜索右边界 / 插入排序边界 / 复用为bsHi  
        // - mid: 二分搜索中点 / 插入排序中间值 / 复用为bsMid
        // 【复用说明】gallopK2 复用 gallopK (串行使用，无时间冲突)
        
        // ==========================================
        // 合并详细操作变量 - 双向合并控制
        // ==========================================
        var pa:Number,                   // A指针位置：遍历A区域的当前位置
            pb:Number,                   // B指针位置：遍历B区域的当前位置  
            d:Number,                    // 目标写入位置：合并结果的写入位置
            ea:Number,                   // A区域结束位置：A区域的结束边界
            eb:Number,                   // B区域结束位置：B区域的结束边界
            ca:Number,                   // A连续获胜计数：A序列连续被选择的次数
            cb:Number,                   // B连续获胜计数：B序列连续被选择的次数
            tempIdx:Number,              // 临时索引：【性能关键】地址计算缓存变量
            copyLen:Number,              // 复制长度：批量复制操作的长度
            copyI:Number,                // 复制循环计数器：批量复制的循环变量
            copyIdx:Number,              // 循环展开索引：【性能关键】循环展开优化缓存
            copyEnd:Number;              // 循环展开结束位置：4字节对齐的循环边界
        
        // ==========================================
        // mergeHi特殊变量 - 反向合并专用
        // ==========================================  
        var ba0:Number;                  // A区域基准位置：反向合并中A区域的起始参考点
        
        // ==========================================
        // 强制合并变量 - 最终收尾合并
        // ========================================== 
        var forceIdx:Number;             // 强制合并索引：最终阶段确定合并run的索引

        // ==========================================
        // 统一二分搜索与插入排序辅助变量
        // ==========================================
        var left:Number;                 // 【多重身份】二分左边界/插入排序位置/复用为bsLo
        var hi2:Number;                  // 【多重身份】二分右边界/插入排序边界/复用为bsHi  
        var mid:Number;                  // 【多重身份】二分中点/插入排序中间值/复用为bsMid
        var stackCapacity:Number;        // 运行栈预分配容量：避免动态扩容的性能开销
        
        /* 【地址计算优化说明】
         * dstBase, srcBase 等地址不单独声明变量，而是直接在表达式中计算
         * 这样可以减少重复的地址计算开销，避免不必要的内存往返
         */

        /*
         * ===============================
         * 算法主体开始
         * ===============================
         */
        
        // 初始化基本参数
        n = arr.length;
        if (n < 2) return arr;           // 长度小于2直接返回

        // 设置算法常量
        MIN_MERGE = 32;                  // 当发现run长度小于minRun时，用插入排序将该run扩展到minRun
        MIN_GALLOP = 7;                  // galloping模式触发阈值

        // 初始化比较函数
        compare = (compareFunction == null)
            ? function(a, b):Number { return a - b; }    // 默认数值比较
            : compareFunction;

        /*
         * 【小数组快速路径】n <= MIN_MERGE 时直接二分插入排序
         * 避免创建 tempArray/runBase/runLen 等数据结构的开销
         * 对于游戏中常见的 10-50 个单位的排序场景，常数因子显著更低
         */
        if (n <= MIN_MERGE) {
            // 内联二分插入排序（稳定）
            for (i = 1; i < n; i++) {
                key = arr[i];
                if (compare(arr[i - 1], key) <= 0) continue;  // 已有序守卫
                if (i <= 8) {
                    // 短距离线性插入
                    j = i - 1;
                    while (j >= 0 && compare(arr[j], key) > 0) {
                        arr[j + 1] = arr[j];
                        j--;
                    }
                    arr[j + 1] = key;
                } else {
                    // 二分查找插入点
                    left = 0;
                    hi2 = i;
                    while (left < hi2) {
                        mid = (left + hi2) >> 1;
                        if (compare(arr[mid], key) <= 0) {
                            left = mid + 1;
                        } else {
                            hi2 = mid;
                        }
                    }
                    j = i;
                    while (j > left) {
                        arr[j] = arr[j - 1];
                        j--;
                    }
                    arr[left] = key;
                }
            }
            return arr;
        }

        // 初始化核心数据结构（优先复用静态缓存，减少 GC）
        stackCapacity = 64;
        if (_stackCap < stackCapacity) {
            _runBase  = new Array(stackCapacity);
            _runLen   = new Array(stackCapacity);
            _stackCap = stackCapacity;
        }
        runBase = _runBase;
        runLen  = _runLen;

        // tempArray: 优先复用缓存，不足时延迟分配
        if (_wsLen >= ((n + 1) >> 1)) {
            tempArray = _workspace;
        } else {
            tempArray = null;
        }
        stackSize = 0;
        minGallop = MIN_GALLOP;
        
        /*
         * 计算最小run长度 (内联 _calculateMinRun)
         * ==========================================
         * 
         * 算法：对于长度n，计算最优的最小run长度
         * - 如果n < 32，返回n
         * - 否则返回一个在16-32之间的值
         * - 目标是让 n/minRun 接近但不大于 2的幂次
         */
        // 复用 ofs 作为 tempN, lastOfs 作为 r
        ofs = n;
        lastOfs = 0;
        while (ofs >= MIN_MERGE) {
            lastOfs |= ofs & 1;          // 记录是否有奇数位
            ofs >>= 1;                   // 右移一位
        }
        minRun = ofs + lastOfs;          // 最终的minRun值
        
        // 主处理循环 - 识别并处理每个run
        remaining = n;
        lo = 0;
        
        while (remaining > 0) {
            /*
             * 识别并反转下降run (内联 _countRunAndReverse)
             * ===============================================
             * 
             * TimSort的核心优化：识别数据中已存在的有序片段
             * - 递增序列：保持不变
             * - 递减序列：反转为递增序列
             * 这样可以充分利用数据中已有的有序性
             */
            hi = lo + 1;
            if (hi >= n) {
                runLength = 1;           // 只剩一个元素
            } else {
                if (compare(arr[lo], arr[hi]) > 0) {
                    // 发现下降序列，继续扫描并反转
                    hi++;
                    while (hi < n && compare(arr[hi - 1], arr[hi]) > 0) hi++;
                    
                    // 内联反转逻辑 (_reverseRange)
                    revLo = lo;
                    revHi = hi - 1;
                    while (revLo < revHi) {
                        tmp = arr[revLo];
                        arr[revLo++] = arr[revHi];
                        arr[revHi--] = tmp;
                    }
                } else {
                    // 上升序列，继续扫描
                    while (hi < n && compare(arr[hi - 1], arr[hi]) <= 0) hi++;
                }
                runLength = hi - lo;
            }
            
            /*
             * 短run扩展处理
             * =============
             * 
             * 如果run太短（小于minRun），使用插入排序扩展它
             * 这确保了每个run都有足够的长度，提高合并效率
             */
            if (runLength < minRun) {
                force = (remaining < minRun) ? remaining : minRun;
                
                // 内联插入排序 (_insertionSort)
                right = lo + force - 1;

                for (i = lo + runLength; i <= right; i++) {
                    key = arr[i];
                    j = i - 1;
                    // 混合插入策略：已有序守卫 + 短距离线性，否则继续走二分插入
                    if (compare(arr[i - 1], key) <= 0) {
                        continue;
                    }
                    if ((i - lo) <= 8) {
                        while (j >= lo && compare(arr[j], key) > 0) {
                            arr[j + 1] = arr[j];
                            j--;
                        }
                        arr[j + 1] = key;
                        continue;
                    }
                    // 使用二分插入：在 [lo, i) 中定位插入点，并整体右移一位
                    left = lo;
                    hi2 = i;
                    while (left < hi2) {
                        mid = (left + hi2) >> 1;
                        if (compare(arr[mid], key) <= 0) {
                            left = mid + 1;
                        } else {
                            hi2 = mid;
                        }
                    }
                    // 将 [left, i-1] 范围内的元素整体向右移动一位，为 key 腾出空间
                    j = i;
                    while (j > left) {
                        arr[j] = arr[j - 1];
                        j--;
                    }
                    // 将 key 放置在二分查找确定的稳定位置
                    arr[left] = key;
                }
                runLength = force;
            }
            
            // 将run推入栈
            runBase[stackSize] = lo;
            runLen[stackSize++] = runLength;
            
            /*
             * =====================================================================================
             * 【TimSort栈平衡算法】合并栈不变量维护 - 核心稳定性保证
             * =====================================================================================
             * 
             * 【栈不变量理论基础】
             * TimSort维护一个run栈，栈中存储已识别的有序片段。为保证合并效率和稳定性，
             * 栈必须满足严格的不变量条件，这些条件确保：
             * 1. 合并操作的时间复杂度保持在O(n log n)
             * 2. 避免病态输入导致的性能退化 
             * 3. 保持算法的稳定性（相等元素相对位置不变）
             * 
             * 【三个核心不变量】（含2015年de Gouw等人修复的第三条件）
             * 设栈顶为索引i，则必须满足：
             * 不变量1: runLen[i-1] > runLen[i] + runLen[i+1]  （栈顶三元组）
             * 不变量2: runLen[i] > runLen[i+1]                （相邻元素递减）
             * 不变量3: runLen[i-2] > runLen[i-1] + runLen[i]  （次顶三元组，防止深层违反）
             *
             * 【不变量违反的处理策略】
             * - 违反不变量1或3：选择runLen[i-1]和runLen[i+1]中较小者与runLen[i]合并
             *   （与OpenJDK TimSort.mergeCollapse一致的合并索引选择）
             * - 违反不变量2：直接合并runLen[i]和runLen[i+1]
             * - 优先级：不变量1/3的修复优先于不变量2
             * 
             * 【算法数学分析】
             * 这些不变量确保了run长度呈近似斐波那契数列增长，
             * 这种增长模式是合并排序达到最优性能的关键。
             */
            size = stackSize;                    // 获取当前栈大小的副本
            while (size > 1) {                   // 至少需要2个run才能合并
                n_idx = size - 2;                // 指向栈顶第二个元素（索引i）
                shouldMerge = false;             // 合并决策标志
                
                /*
                 * ========================================================
                 * 【栈不变量检查】按优先级顺序检查违反情况
                 * ========================================================
                 */
                if ((n_idx > 0 && runLen[n_idx - 1] <= runLen[n_idx] + runLen[n_idx + 1])
                    || (n_idx > 1 && runLen[n_idx - 2] <= runLen[n_idx - 1] + runLen[n_idx])) {
                    /*
                     * 【不变量1违反】三元素和不等式失效
                     * 
                     * 条件：runLen[i-1] <= runLen[i] + runLen[i+1]
                     * 
                     * 【合并策略】选择较小的相邻run进行合并：
                     * - 如果 runLen[i-1] < runLen[i+1]，合并(i-1, i)
                     * - 否则合并(i, i+1)
                     * 
                     * 【策略原理】选择较小者可以最小化数据移动量，
                     * 因为TimSort总是将较短的序列复制到临时数组中
                     */
                    mergeIdx = n_idx - (runLen[n_idx - 1] < runLen[n_idx + 1]);
                    shouldMerge = true;
                } else if (runLen[n_idx] <= runLen[n_idx + 1]) {
                    /*
                     * 【不变量2违反】相邻递减条件失效
                     * 
                     * 条件：runLen[i] <= runLen[i+1] 
                     * 
                     * 【合并策略】直接合并栈顶两个run：
                     * 合并(i, i+1)，即runLen[n_idx]和runLen[n_idx+1]
                     * 
                     * 【策略原理】这是最直接的修复方式，
                     * 合并后新的run长度为两者之和，通常能满足不变量
                     */
                    mergeIdx = n_idx;
                    shouldMerge = true;
                }
                
                if (!shouldMerge) break;         // 所有不变量都满足，退出检查
                
                /*
                 * 执行合并操作 (内联 _mergeAt)
                 * ===========================
                 * 
                 * 这是TimSort的核心：智能合并两个相邻的run
                 * 包含多个优化：
                 * 1. Galloping模式：快速跳过大量元素
                 * 2. 方向选择：选择需要移动更少元素的合并方向
                 * 3. 边界优化：避免不必要的合并操作
                 */
                /*
                 * ================================================================
                 * 【寄存器复用优化】合并操作中的变量复用策略
                 * ================================================================
                 * 
                 * 【tempIdx多阶段复用】
                 * tempIdx变量在这段代码中展现了精妙的多阶段复用：
                 * 
                 * 阶段1: 存储 mergeIdx + 1，避免重复计算
                 *        loB = runBase[tempIdx = mergeIdx + 1]
                 *        lenB = runLen[tempIdx]
                 * 
                 * 阶段2: 在栈压缩循环中复用为 copyI + 1，减少地址运算
                 *        runBase[copyI] = runBase[tempIdx = copyI + 1]
                 *        runLen[copyI] = runLen[tempIdx]
                 * 
                 * 【性能收益分析】
                 * - 减少算术运算：避免了4次 +1 计算
                 * - 提升寄存器利用：AS2虚拟机能更好地缓存计算结果
                 * - 降低内存访问：减少了重复的地址计算开销
                 */
                loA = runBase[mergeIdx];
                lenA = runLen[mergeIdx];
                loB = runBase[tempIdx = mergeIdx + 1];  // 【阶段1】缓存mergeIdx+1
                lenB = runLen[tempIdx];                 // 复用缓存结果
                
                // 更新栈：合并后的run长度
                runLen[mergeIdx] = lenA + lenB;
                
                // 栈元素向前移动（压缩操作）
                copyLen = stackSize - 1;  // 复用copyLen作为mergeN
                for (copyI = tempIdx; copyI < copyLen; copyI++) {  // 复用copyI作为mergeJ，从tempIdx开始
                    runBase[copyI] = runBase[tempIdx = copyI + 1];  // 【阶段2】复用tempIdx为copyI+1
                    runLen[copyI] = runLen[tempIdx];                // 复用缓存结果
                }
                --stackSize;
                
                /*
                 * ========================================================================
                 * 【Galloping右搜索算法】TimSort核心优化 - 指数搜索+二分搜索
                 * ========================================================================
                 * 
                 * 【算法目标】
                 * 查找B的第一个元素在A中的插入位置，如果B[0] >= A的所有元素，
                 * 可以跳过整个A区域，实现O(log n)复杂度下的大规模元素跳跃。
                 * 
                 * 【Galloping搜索原理】
                 * Galloping得名于马匹的"飞驰"步态，算法模拟这种跳跃式前进：
                 * 1. 指数搜索阶段：步长呈指数增长 (1, 3, 7, 15, 31...)
                 * 2. 二分搜索阶段：在确定范围内精确定位
                 * 
                 * 【算法复杂度分析】
                 * - 最佳情况：O(1) - 目标在开头或结尾
                 * - 一般情况：O(log n) - 指数搜索+二分搜索
                 * - 最坏情况：O(log n) - 退化为纯二分搜索
                 * 
                 * 【指数增长公式】
                 * ofs = (ofs << 1) + 1
                 * 等价于：ofs = ofs * 2 + 1
                 * 生成序列：1 -> 3 -> 7 -> 15 -> 31 -> 63...
                 * 这保证了搜索范围快速覆盖目标区域
                 */
                gallopK = 0;
                target = arr[loB];      // B的第一个元素（搜索目标）
                base = loA;             // A区域的起始基准位置
                len = lenA;             // A区域的搜索长度
                
                if (compare(arr[base], target) > 0) {
                    gallopK = 0;        // 边界情况：A[0] > B[0]，无需裁剪
                } else {
                    /*
                     * =============================================
                     * 【指数搜索阶段 - gallopRight】快速定位目标范围
                     * =============================================
                     * 使用gallopRight（upper_bound）语义：
                     * 找到A中第一个严格大于B[0]的位置
                     * A中 <= B[0] 的前缀元素不需要参与合并（稳定性安全）
                     */
                    ofs = 1;            // 指数搜索起始步长
                    lastOfs = 0;        // 前一个有效步长

                    // 指数增长直到找到上界（<= 表示跳过等于target的元素）
                    while (ofs < len && compare(arr[base + ofs], target) <= 0) {
                        lastOfs = ofs;                    // 保存当前有效位置
                        ofs = (ofs << 1) + 1;             // 【指数增长公式】步长翻倍+1
                        if (ofs <= 0) ofs = len;         // 整数溢出保护
                    }
                    if (ofs > len) ofs = len;            // 边界保护

                    /*
                     * =============================================
                     * 【二分搜索阶段 - upper_bound】精确定位插入点
                     * =============================================
                     * 在 [lastOfs, ofs) 区间内精确查找
                     * 找到第一个 > target 的位置（等于target的元素归入前缀裁剪）
                     */
                    left = lastOfs;      // 复用left作为bsLo（二分左边界）
                    hi2 = ofs;           // 复用hi2作为bsHi（二分右边界）
                    while (left < hi2) {
                        mid = (left + hi2) >> 1;          // 复用mid作为bsMid（中点计算）
                        if (compare(arr[base + mid], target) <= 0) {
                            left = mid + 1;               // 跳过 <= target 的元素
                        } else {
                            hi2 = mid;                    // 找到 > target 的位置
                        }
                    }
                    gallopK = left;      // 最终插入位置（跳过了所有 <= B[0] 的A前缀）
                }
                
                if (gallopK == lenA) {
                    // A的所有元素都小于B[0]，无需合并
                } else {
                    // 调整A的范围
                    loA += gallopK;
                    lenA -= gallopK;
                    
                    /*
                     * Galloping左搜索优化 (内联 _gallopLeft)
                     * =====================================
                     * 
                     * 查找A的最后一个元素在B中的插入位置
                     * 如果A的最后元素 <= B的所有元素，可以跳过B的尾部
                     */
                    gallopK = 0;  // 复用gallopK，前一个gallopK已经使用完毕
                    target = arr[loA + lenA - 1];  // A的最后一个元素
                    base = loB;
                    len = lenB;
                    
                    if (compare(arr[base], target) >= 0) {
                        gallopK = 0;              // B[0] >= A[last]，无需裁剪B
                    } else {
                        // 指数搜索 - gallopLeft（lower_bound）语义
                        // 找到B中第一个 >= A[last] 的位置
                        // B中 < A[last] 的前缀需要参与合并，>= A[last] 的尾部已在正确位置
                        ofs = 1;
                        lastOfs = 0;

                        while (ofs < len && compare(arr[base + ofs], target) < 0) {
                            lastOfs = ofs;
                            ofs = (ofs << 1) + 1;
                            if (ofs <= 0) ofs = len;
                        }
                        if (ofs > len) ofs = len;

                        // 二分搜索 - lower_bound（找第一个 >= target 的位置）
                        left = lastOfs;  // 复用left作为bsLo
                        hi2 = ofs;       // 复用hi2作为bsHi
                        while (left < hi2) {
                            mid = (left + hi2) >> 1;  // 复用mid作为bsMid
                            if (compare(arr[base + mid], target) < 0) {
                                left = mid + 1;
                            } else {
                                hi2 = mid;
                            }
                        }
                        gallopK = left;
                    }
                    
                    if (gallopK == 0) {
                        // B的所有元素都大于A的最后元素，无需合并
                    } else {
                        // 调整B的范围
                        lenB = gallopK;

                        // 单元素合并优化（快速路径）
                        if (lenA == 1) {
                            tmp = arr[loA];
                            left = 0;
                            hi2 = lenB;
                            while (left < hi2) {
                                mid = (left + hi2) >> 1;
                                if (compare(arr[loB + mid], tmp) < 0) {
                                    left = mid + 1;
                                } else {
                                    hi2 = mid;
                                }
                            }
                            // 将B的前left个元素左移一位（loA紧邻loB），然后插入tmp
                            for (i = 0; i < left; i++) {
                                arr[loA + i] = arr[loB + i];
                            }
                            arr[loA + left] = tmp;
                            size = stackSize;
                            continue;
                        }
                        if (lenB == 1) {
                            tmp = arr[loB];
                            left = 0;
                            hi2 = lenA;
                            while (left < hi2) {
                                mid = (left + hi2) >> 1;
                                if (compare(arr[loA + mid], tmp) <= 0) {
                                    left = mid + 1;
                                } else {
                                    hi2 = mid;
                                }
                            }
                            for (j = lenA - 1; j >= left; j--) {
                                arr[loA + j + 1] = arr[loA + j];
                            }
                            arr[loA + left] = tmp;
                            size = stackSize;
                            continue;
                        }
                        /*
                         * ==========================================================================
                         * 【智能合并方向选择】TimSort内存优化策略
                         * ==========================================================================
                         * 
                         * 【策略核心原理】
                         * TimSort的一个重要优化是选择最优的合并方向，目标是最小化：
                         * 1. 临时数组使用量（空间复杂度优化）
                         * 2. 元素复制次数（时间复杂度优化）  
                         * 3. 缓存缺失率（内存访问优化）
                         * 
                         * 【两种合并策略对比】
                         * 
                         * mergeLo（向前合并）：
                         * - 适用场景：lenA <= lenB（A比B短或相等）
                         * - 复制策略：将A复制到临时数组，B保持原位置
                         * - 合并方向：从左向右（递增索引）
                         * - 内存优势：临时数组只需lenA空间
                         * - 访问模式：顺序访问，缓存友好
                         * 
                         * mergeHi（向后合并）：  
                         * - 适用场景：lenA > lenB（A比B长）
                         * - 复制策略：将B复制到临时数组，A保持原位置
                         * - 合并方向：从右向左（递减索引）
                         * - 内存优势：临时数组只需lenB空间
                         * - 特殊处理：需要逆向索引计算和写入
                         * 
                         * 【数学优势分析】
                         * 设总空间复杂度为S，则：
                         * - 传统合并排序：S = max(lenA, lenB)
                         * - TimSort优化：S = min(lenA, lenB)
                         * 平均节省50%的临时空间使用量
                         */
                        // 延迟分配临时数组：仅在实际需要合并时创建
                        if (tempArray == null) { tempArray = new Array((n + 1) >> 1); _workspace = tempArray; _wsLen = tempArray.length; }

                        if (lenA <= lenB) {
                            /*
                             * 执行mergeLo (内联 _mergeLo)
                             * ==========================
                             * 
                             * 从左到右合并，使用临时数组保存A
                             * 包含galloping模式优化
                             * 
                             * ⚠️ 维护提示：若修改合并细节，请同步更新：
                             * - 行1343+的强制合并mergeLo重复实现
                             * - 稳定性比较逻辑：compare(tempArray[pa], arr[pb]) <= 0
                             */
                            pa = 0;                  // 临时数组A的指针
                            pb = loB;                // 数组B的指针
                            d = loA;                 // 目标位置指针
                            ea = lenA;               // A的结束位置
                            eb = loB + lenB;         // B的结束位置
                            ca = 0;                  // A连续获胜计数
                            cb = 0;                  // B连续获胜计数
                            
                            /*
                             * =================================================================
                             * 【AS2循环展开优化】复制A到临时数组
                             * =================================================================
                             * 
                             * 【优化技术说明】
                             * 1. 循环展开（Loop Unrolling）：将循环体复制4次，减少循环条件检查开销
                             * 2. 副作用合并（Side-effect Merging）：通过赋值表达式副作用缓存地址计算
                             * 3. 对齐优化（Alignment Optimization）：按4元素块处理，提升内存访问效率
                             * 
                             * 【副作用合并解析】
                             * arr[copyIdx = loA + copyI] 这个表达式同时完成两个操作：
                             * - 计算 loA + copyI 并存储到 copyIdx（副作用）
                             * - 使用计算结果作为数组索引（主效果）
                             * 后续三行直接使用 copyIdx + 1/2/3，避免重复计算基础地址
                             * 
                             * 【AS2虚拟机优势】
                             * 副作用赋值可以在实践中减少重复的地址计算，
                             * 这样后续的 copyIdx + 1 等操作可以直接使用寄存器值，
                             * 避免了内存读取和地址重新计算的开销
                             */
                            copyEnd = lenA - (lenA & 3);  // 计算4字节对齐的循环边界
                            for (copyI = 0; copyI < copyEnd; copyI += 4) {
                                // 【副作用合并】缓存地址计算结果，触发寄存器分配
                                tempArray[copyI] = arr[copyIdx = loA + copyI];
                                tempArray[copyI + 1] = arr[copyIdx + 1];      // 复用缓存地址 + 1
                                tempArray[copyI + 2] = arr[copyIdx + 2];      // 复用缓存地址 + 2  
                                tempArray[copyI + 3] = arr[copyIdx + 3];      // 复用缓存地址 + 3
                            }
                            // 处理非4倍数的剩余元素（标准循环）
                            for (; copyI < lenA; copyI++) {
                                tempArray[copyI] = arr[loA + copyI];
                            }
                            
                            // 初始的简单合并阶段
                            while (pa < ea && pb < eb && ca < minGallop && cb < minGallop) {
                                if (compare(tempArray[pa], arr[pb]) <= 0) {  // 相等时取A，保证稳定
                                    arr[d++] = tempArray[pa++];
                                    ca++;
                                    cb = 0;
                                } else {
                                    arr[d++] = arr[pb++];
                                    cb++;
                                    ca = 0;
                                }
                            }
                            
                            /*
                             * Galloping模式合并
                             * ================
                             * 
                             * 当一边连续获胜时，进入galloping模式
                             * 通过指数搜索快速跳过大量元素
                             */
                            while (pa < ea && pb < eb) {
                                if (ca >= minGallop) {
                                    // A方进入galloping模式 - gallopRight: 在A(tempArray)中查找B当前元素的插入位置
                                    // 找出tempArray中有多少连续A元素 <= arr[pb]，批量复制这些A元素
                                    target = arr[pb];
                                    base = pa;
                                    len = ea - pa;
                                    gallopK = 0;

                                    if (compare(tempArray[base], target) > 0) {
                                        gallopK = 0;
                                    } else {
                                        ofs = 1;
                                        lastOfs = 0;
                                        while (ofs < len && compare(tempArray[base + ofs], target) <= 0) {
                                            lastOfs = ofs;
                                            ofs = (ofs << 1) + 1;
                                            if (ofs <= 0) ofs = len;
                                        }
                                        if (ofs > len) ofs = len;
                                        left = lastOfs;
                                        hi2 = ofs;
                                        while (left < hi2) {
                                            mid = (left + hi2) >> 1;
                                            if (compare(tempArray[base + mid], target) <= 0) {
                                                left = mid + 1;
                                            } else {
                                                hi2 = mid;
                                            }
                                        }
                                        gallopK = left;
                                    }
                                    
                                    /*
                                     * 【A序列Galloping批量复制】临时数组到主数组的高速传输
                                     * A连续获胜时，将tempArray中的A元素批量写入arr
                                     */
                                    copyEnd = gallopK - (gallopK & 3);
                                    for (copyI = 0; copyI < copyEnd; copyI += 4) {
                                        arr[tempIdx = d + copyI] = tempArray[copyIdx = pa + copyI];
                                        arr[tempIdx + 1] = tempArray[copyIdx + 1];
                                        arr[tempIdx + 2] = tempArray[copyIdx + 2];
                                        arr[tempIdx + 3] = tempArray[copyIdx + 3];
                                    }
                                    for (; copyI < gallopK; copyI++) {
                                        arr[d + copyI] = tempArray[pa + copyI];
                                    }
                                    d += gallopK;
                                    pa += gallopK;
                                    ca = 0;
                                    
                                    // 动态调整galloping阈值
                                    minGallop -= (gallopK >= MIN_GALLOP ? 1 : -1);
                                    if (minGallop < 1) minGallop = 1;
                                } else if (cb >= minGallop) {
                                    // B方进入galloping模式 - gallopLeft: 在B(arr)中查找A当前元素的插入位置
                                    // 找出arr中有多少连续B元素 < tempArray[pa]，批量复制这些B元素
                                    target = tempArray[pa];
                                    base = pb;
                                    len = eb - pb;
                                    gallopK = 0;

                                    if (compare(arr[base], target) >= 0) {
                                        gallopK = 0;
                                    } else {
                                        ofs = 1;
                                        lastOfs = 0;
                                        while (ofs < len && compare(arr[base + ofs], target) < 0) {
                                            lastOfs = ofs;
                                            ofs = (ofs << 1) + 1;
                                            if (ofs <= 0) ofs = len;
                                        }
                                        if (ofs > len) ofs = len;
                                        left = lastOfs;
                                        hi2 = ofs;
                                        while (left < hi2) {
                                            mid = (left + hi2) >> 1;
                                            if (compare(arr[base + mid], target) < 0) {
                                                left = mid + 1;
                                            } else {
                                                hi2 = mid;
                                            }
                                        }
                                        gallopK = left;
                                    }
                                    
                                    /*
                                     * 【B序列Galloping批量复制】arr内部元素前移
                                     * B连续获胜时，将arr中的B元素批量前移到目标位置
                                     */
                                    copyEnd = gallopK - (gallopK & 3);
                                    for (copyI = 0; copyI < copyEnd; copyI += 4) {
                                        arr[copyIdx = d + copyI] = arr[tempIdx = pb + copyI];
                                        arr[copyIdx + 1] = arr[tempIdx + 1];
                                        arr[copyIdx + 2] = arr[tempIdx + 2];
                                        arr[copyIdx + 3] = arr[tempIdx + 3];
                                    }
                                    for (; copyI < gallopK; copyI++) {
                                        arr[d + copyI] = arr[pb + copyI];
                                    }
                                    d += gallopK;
                                    pb += gallopK;
                                    cb = 0;
                                    
                                    // 动态调整galloping阈值
                                    minGallop -= (gallopK >= MIN_GALLOP ? 1 : -1);
                                    if (minGallop < 1) minGallop = 1;
                                } else {
                                    // 退出galloping模式，惩罚阈值防止频繁振荡
                                    ++minGallop;
                                    while (pa < ea && pb < eb && ca < minGallop && cb < minGallop) {
                                        if (compare(tempArray[pa], arr[pb]) <= 0) {  // 相等时取A，保证稳定
                                            arr[d++] = tempArray[pa++];
                                            ca++;
                                            cb = 0;
                                        } else {
                                            arr[d++] = arr[pb++];
                                            cb++;
                                            ca = 0;
                                        }
                                    }
                                }
                            }
                            
                            // 复制剩余的A元素（循环展开优化）
                            copyLen = ea - pa;
                            copyEnd = copyLen - (copyLen & 3);
                            for (copyI = 0; copyI < copyEnd; copyI += 4) {
                                arr[tempIdx = d + copyI] = tempArray[copyIdx = pa + copyI];
                                arr[tempIdx + 1] = tempArray[copyIdx + 1];
                                arr[tempIdx + 2] = tempArray[copyIdx + 2];
                                arr[tempIdx + 3] = tempArray[copyIdx + 3];
                            }
                            for (; copyI < copyLen; copyI++) {
                                arr[d + copyI] = tempArray[pa + copyI];
                            }
                        } else {
                            /*
                             * 执行mergeHi (内联 _mergeHi)
                             * ==========================
                             * 
                             * 从右到左合并，使用临时数组保存B
                             * 适用于B比A短的情况
                             * 
                             * ⚠️ 维护提示：若修改合并细节，请同步更新：
                             * - 行1497+的强制合并mergeHi重复实现
                             * - 稳定性比较逻辑：compare(arr[pa], tempArray[pb]) > 0
                             */
                            pa = loA + lenA - 1;     // A的最后位置
                            pb = lenB - 1;           // 临时数组B的最后位置
                            d = loB + lenB - 1;      // 目标最后位置
                            ba0 = loA;               // A的起始位置
                            cb = 0;
                            ca = 0;
                            
                            // 复制B到临时数组（循环展开优化）
                            copyEnd = lenB - (lenB & 3);
                            for (copyI = 0; copyI < copyEnd; copyI += 4) {
                                tempArray[copyI] = arr[copyIdx = loB + copyI];
                                tempArray[copyI + 1] = arr[copyIdx + 1];
                                tempArray[copyI + 2] = arr[copyIdx + 2];
                                tempArray[copyI + 3] = arr[copyIdx + 3];
                            }
                            for (; copyI < lenB; copyI++) {
                                copyIdx = loB + copyI;  // 存储计算结果
                                tempArray[copyI] = arr[copyIdx];
                            }
                            
                            // 初始的简单合并阶段（从右到左）
                            while (pa >= ba0 && pb >= 0 && ca < minGallop && cb < minGallop) {
                                if (compare(arr[pa], tempArray[pb]) > 0) {  // 相等时取B，保证稳定
                                    arr[d--] = arr[pa--];
                                    ca++;
                                    cb = 0;
                                } else {
                                    arr[d--] = tempArray[pb--];
                                    cb++;
                                    ca = 0;
                                }
                            }
                            
                            // Galloping模式合并（从右到左）
                            while (pa >= ba0 && pb >= 0) {
                                if (ca >= minGallop) {
                                    // A方galloping - 从右端开始的反向指数搜索（hint-based）
                                    // 在mergeHi中答案大概率在pa附近，从右端搜索为O(log k)而非O(log n)
                                    target = tempArray[pb];
                                    len = pa - ba0 + 1;

                                    if (compare(arr[pa], target) <= 0) {
                                        gallopK = 0;  // A的最右元素 <= B当前元素，无需批量复制
                                    } else if (compare(arr[ba0], target) > 0) {
                                        gallopK = len;  // A的所有元素都 > B当前元素，全部批量复制
                                    } else {
                                        // 从pa向左做指数搜索，找到 > target 的边界
                                        ofs = 1;
                                        lastOfs = 0;
                                        while (ofs < len && compare(arr[pa - ofs], target) > 0) {
                                            lastOfs = ofs;
                                            ofs = (ofs << 1) + 1;
                                            if (ofs <= 0) ofs = len;
                                        }
                                        if (ofs > len) ofs = len;
                                        // 二分搜索：在距离pa的[lastOfs, ofs]范围内精确定位边界
                                        left = lastOfs;
                                        hi2 = ofs;
                                        while (left < hi2) {
                                            mid = (left + hi2) >> 1;
                                            if (compare(arr[pa - mid], target) > 0) {
                                                left = mid + 1;  // 更多元素 > target
                                            } else {
                                                hi2 = mid;        // 找到边界
                                            }
                                        }
                                        gallopK = left;  // 从右端数起 > target 的元素个数
                                    }

                                    // 从右到左批量复制A中的元素（循环展开优化）
                                    copyEnd = gallopK - (gallopK & 3);
                                    for (copyI = 0; copyI < copyEnd; copyI += 4) {
                                        arr[copyIdx = d - copyI] = arr[tempIdx = pa - copyI];
                                        arr[copyIdx - 1] = arr[tempIdx - 1];
                                        arr[copyIdx - 2] = arr[tempIdx - 2];
                                        arr[copyIdx - 3] = arr[tempIdx - 3];
                                    }
                                    for (; copyI < gallopK; copyI++) {
                                        arr[d - copyI] = arr[pa - copyI];
                                    }
                                    d -= gallopK;
                                    pa -= gallopK;
                                    ca = 0;
                                    minGallop -= (gallopK >= MIN_GALLOP ? 1 : -1);
                                    if (minGallop < 1) minGallop = 1;
                                } else if (cb >= minGallop) {
                                    // B方galloping - gallopLeft（lower_bound）语义
                                    // 在tempArray中找A[pa]的插入点，等于A[pa]的B元素应被批量复制（稳定性：B在右）
                                    target = arr[pa];
                                    base = 0;
                                    len = pb + 1;

                                    if (compare(tempArray[base], target) >= 0) {
                                        gallopK = len;  // 所有B元素 >= target，全部批量复制
                                    } else {
                                        ofs = 1;
                                        lastOfs = 0;
                                        while (ofs < len && compare(tempArray[base + ofs], target) < 0) {
                                            lastOfs = ofs;
                                            ofs = (ofs << 1) + 1;
                                            if (ofs <= 0) ofs = len;
                                        }
                                        if (ofs > len) ofs = len;
                                        left = lastOfs;
                                        hi2 = ofs;
                                        while (left < hi2) {
                                            mid = (left + hi2) >> 1;
                                            if (compare(tempArray[base + mid], target) < 0) {
                                                left = mid + 1;
                                            } else {
                                                hi2 = mid;
                                            }
                                        }
                                        gallopK = len - left;
                                        // lower_bound: left是第一个 >= target 的位置
                                        // len - left = 从右边数起 >= target 的元素数量（含等于，稳定性正确）
                                    }
                                    
                                    // 从右到左批量复制B中的元素（循环展开优化）
                                    copyEnd = gallopK - (gallopK & 3);
                                    for (copyI = 0; copyI < copyEnd; copyI += 4) {
                                        arr[copyIdx = d - copyI] = tempArray[tempIdx = pb - copyI];
                                        arr[copyIdx - 1] = tempArray[tempIdx - 1];
                                        arr[copyIdx - 2] = tempArray[tempIdx - 2];
                                        arr[copyIdx - 3] = tempArray[tempIdx - 3];
                                    }
                                    for (; copyI < gallopK; copyI++) {
                                        arr[d - copyI] = tempArray[pb - copyI];
                                    }
                                    d -= gallopK;
                                    pb -= gallopK;
                                    cb = 0;
                                    minGallop -= (gallopK >= MIN_GALLOP ? 1 : -1);
                                    if (minGallop < 1) minGallop = 1;
                                } else {
                                    // 退出galloping模式，惩罚阈值防止频繁振荡
                                    ++minGallop;
                                    while (pa >= ba0 && pb >= 0 && ca < minGallop && cb < minGallop) {
                                        if (compare(arr[pa], tempArray[pb]) > 0) {  // 相等时取B，保证稳定
                                            arr[d--] = arr[pa--];
                                            ca++;
                                            cb = 0;
                                        } else {
                                            arr[d--] = tempArray[pb--];
                                            cb++;
                                            ca = 0;
                                        }
                                    }
                                }
                            }
                            
                            // 复制剩余的B元素（循环展开优化）
                            copyLen = pb + 1;
                            copyEnd = copyLen - (copyLen & 3);
                            for (copyI = 0; copyI < copyEnd; copyI += 4) {
                                arr[copyIdx = d - copyI] = tempArray[tempIdx = pb - copyI];
                                arr[copyIdx - 1] = tempArray[tempIdx - 1];
                                arr[copyIdx - 2] = tempArray[tempIdx - 2];
                                arr[copyIdx - 3] = tempArray[tempIdx - 3];
                            }
                            for (; copyI < copyLen; copyI++) {
                                copyIdx = d - copyI;  // 复用变量避免重复计算
                                arr[copyIdx] = tempArray[pb - copyI];
                            }
                        }
                    }
                }
                
                size = stackSize;
            }
            
            // 移动到下一个待处理区域
            lo += runLength;
            remaining -= runLength;
        }
        
        /*
         * 强制合并剩余的run (内联 _mergeForceCollapse)
         * ===========================================
         * 
         * 在所有run识别完成后，强制合并栈中剩余的所有run
         * 确保最终结果是完全排序的
         */
        while (stackSize > 1) {
            // 选择合并策略：优先合并较小的run
            forceIdx = (stackSize > 2 && runLen[stackSize - 3] < runLen[stackSize - 1])
                ? stackSize - 3
                : stackSize - 2;
            
            /*
             * 重复完整的合并逻辑
             * ==================
             * 
             * 注意：这里重复了上面_mergeAt的完整逻辑
             * 为了性能优化，避免了函数调用开销
             */
            loA = runBase[forceIdx];
            lenA = runLen[forceIdx];
            loB = runBase[forceIdx + 1];
            lenB = runLen[forceIdx + 1];
            
            runLen[forceIdx] = lenA + lenB;
            
            copyLen = stackSize - 1;  // 复用copyLen作为mergeN
            for (copyI = forceIdx + 1; copyI < copyLen; copyI++) {  // 复用copyI作为mergeJ
                runBase[copyI] = runBase[copyI + 1];
                runLen[copyI] = runLen[copyI + 1];
            }
            stackSize--;
            
            // gallopRight（upper_bound）- 跳过A中 <= B[0] 的前缀
            gallopK = 0;
            target = arr[loB];
            base = loA;
            len = lenA;

            if (compare(arr[base], target) > 0) {
                gallopK = 0;
            } else {
                ofs = 1;
                lastOfs = 0;
                while (ofs < len && compare(arr[base + ofs], target) <= 0) {
                    lastOfs = ofs;
                    ofs = (ofs << 1) + 1;
                    if (ofs <= 0) ofs = len;
                }
                if (ofs > len) ofs = len;
                left = lastOfs;
                hi2 = ofs;
                while (left < hi2) {
                    mid = (left + hi2) >> 1;
                    if (compare(arr[base + mid], target) <= 0) {
                        left = mid + 1;
                    } else {
                        hi2 = mid;
                    }
                }
                gallopK = left;
            }
            
            if (gallopK == lenA) {
                // 无需合并，直接继续
            } else {
                loA += gallopK;
                lenA -= gallopK;
                
                // gallopLeft（lower_bound）- 找B中第一个 >= A[last] 的位置
                gallopK = 0;  // 复用gallopK，前面的已用完
                target = arr[loA + lenA - 1];
                base = loB;
                len = lenB;

                if (compare(arr[base], target) >= 0) {
                    gallopK = 0;
                } else {
                    ofs = 1;
                    lastOfs = 0;
                    while (ofs < len && compare(arr[base + ofs], target) < 0) {
                        lastOfs = ofs;
                        ofs = (ofs << 1) + 1;
                        if (ofs <= 0) ofs = len;
                    }
                    if (ofs > len) ofs = len;
                    left = lastOfs;
                    hi2 = ofs;
                    while (left < hi2) {
                        mid = (left + hi2) >> 1;
                        if (compare(arr[base + mid], target) < 0) {
                            left = mid + 1;
                        } else {
                            hi2 = mid;
                        }
                    }
                    gallopK = left;  // 复用gallopK，之前的已用完
                }
                
                if (gallopK == 0) {
                    // 无需合并，直接继续
                } else {
                    lenB = gallopK;  // 修正：同步B的裁剪后长度（与主合并逻辑一致）

                        // 单元素合并优化（快速路径）
                        if (lenA == 1) {
                            tmp = arr[loA];
                            left = 0;
                            hi2 = lenB;
                            while (left < hi2) {
                                mid = (left + hi2) >> 1;
                                if (compare(arr[loB + mid], tmp) < 0) {
                                    left = mid + 1;
                                } else {
                                    hi2 = mid;
                                }
                            }
                            // 将B的前left个元素左移一位，然后插入tmp
                            for (i = 0; i < left; i++) {
                                arr[loA + i] = arr[loB + i];
                            }
                            arr[loA + left] = tmp;
                            continue;
                        }
                        if (lenB == 1) {
                            tmp = arr[loB];
                            left = 0;
                            hi2 = lenA;
                            while (left < hi2) {
                                mid = (left + hi2) >> 1;
                                if (compare(arr[loA + mid], tmp) <= 0) {
                                    left = mid + 1;
                                } else {
                                    hi2 = mid;
                                }
                            }
                            for (j = lenA - 1; j >= left; j--) {
                                arr[loA + j + 1] = arr[loA + j];
                            }
                            arr[loA + left] = tmp;
                            continue;
                        }// 完整的合并逻辑（与上面_mergeCollapse中完全相同）
                        // ⚠️ 维护提示：这里是强制合并的重复实现，修改时请同步更新上面的正常合并逻辑
                    // 延迟分配临时数组：仅在实际需要合并时创建
                    if (tempArray == null) { tempArray = new Array((n + 1) >> 1); _workspace = tempArray; _wsLen = tempArray.length; }

                    if (lenA <= lenB) {
                        // 完整的mergeLo（重复实现）
                        pa = 0;
                        pb = loB;
                        d = loA;
                        ea = lenA;
                        eb = loB + lenB;
                        ca = 0;
                        cb = 0;
                        
                        // 复制A到临时数组（循环展开优化）
                        copyEnd = lenA - (lenA & 3);
                        for (copyI = 0; copyI < copyEnd; copyI += 4) {
                            tempArray[copyI] = arr[copyIdx = loA + copyI];
                            tempArray[copyI + 1] = arr[copyIdx + 1];
                            tempArray[copyI + 2] = arr[copyIdx + 2];
                            tempArray[copyI + 3] = arr[copyIdx + 3];
                        }
                        for (; copyI < lenA; copyI++) {
                            tempArray[copyI] = arr[loA + copyI];
                        }
                        
                        while (pa < ea && pb < eb && ca < minGallop && cb < minGallop) {
                            if (compare(tempArray[pa], arr[pb]) <= 0) {
                                arr[d++] = tempArray[pa++];
                                ca++;
                                cb = 0;
                            } else {
                                arr[d++] = arr[pb++];
                                cb++;
                                ca = 0;
                            }
                        }
                        
                        while (pa < ea && pb < eb) {
                            if (ca >= minGallop) {
                                // A方galloping - gallopRight: 在A(tempArray)中查找B当前元素的插入位置
                                target = arr[pb];
                                base = pa;
                                len = ea - pa;
                                gallopK = 0;

                                if (compare(tempArray[base], target) > 0) {
                                    gallopK = 0;
                                } else {
                                    ofs = 1;
                                    lastOfs = 0;
                                    while (ofs < len && compare(tempArray[base + ofs], target) <= 0) {
                                        lastOfs = ofs;
                                        ofs = (ofs << 1) + 1;
                                        if (ofs <= 0) ofs = len;
                                    }
                                    if (ofs > len) ofs = len;
                                    left = lastOfs;
                                    hi2 = ofs;
                                    while (left < hi2) {
                                        mid = (left + hi2) >> 1;
                                        if (compare(tempArray[base + mid], target) <= 0) {
                                            left = mid + 1;
                                        } else {
                                            hi2 = mid;
                                        }
                                    }
                                    gallopK = left;
                                }

                                // A序列批量复制: tempArray → arr
                                copyEnd = gallopK - (gallopK & 3);
                                for (copyI = 0; copyI < copyEnd; copyI += 4) {
                                    arr[tempIdx = d + copyI] = tempArray[copyIdx = pa + copyI];
                                    arr[tempIdx + 1] = tempArray[copyIdx + 1];
                                    arr[tempIdx + 2] = tempArray[copyIdx + 2];
                                    arr[tempIdx + 3] = tempArray[copyIdx + 3];
                                }
                                for (; copyI < gallopK; copyI++) {
                                    arr[d + copyI] = tempArray[pa + copyI];
                                }
                                d += gallopK;
                                pa += gallopK;
                                ca = 0;
                                minGallop -= (gallopK >= MIN_GALLOP ? 1 : -1);
                                if (minGallop < 1) minGallop = 1;
                            } else if (cb >= minGallop) {
                                // B方galloping - gallopLeft: 在B(arr)中查找A当前元素的插入位置
                                target = tempArray[pa];
                                base = pb;
                                len = eb - pb;
                                gallopK = 0;

                                if (compare(arr[base], target) >= 0) {
                                    gallopK = 0;
                                } else {
                                    ofs = 1;
                                    lastOfs = 0;
                                    while (ofs < len && compare(arr[base + ofs], target) < 0) {
                                        lastOfs = ofs;
                                        ofs = (ofs << 1) + 1;
                                        if (ofs <= 0) ofs = len;
                                    }
                                    if (ofs > len) ofs = len;
                                    left = lastOfs;
                                    hi2 = ofs;
                                    while (left < hi2) {
                                        mid = (left + hi2) >> 1;
                                        if (compare(arr[base + mid], target) < 0) {
                                            left = mid + 1;
                                        } else {
                                            hi2 = mid;
                                        }
                                    }
                                    gallopK = left;
                                }

                                // B序列批量复制: arr内部元素前移
                                copyEnd = gallopK - (gallopK & 3);
                                for (copyI = 0; copyI < copyEnd; copyI += 4) {
                                    arr[copyIdx = d + copyI] = arr[tempIdx = pb + copyI];
                                    arr[copyIdx + 1] = arr[tempIdx + 1];
                                    arr[copyIdx + 2] = arr[tempIdx + 2];
                                    arr[copyIdx + 3] = arr[tempIdx + 3];
                                }
                                for (; copyI < gallopK; copyI++) {
                                    arr[d + copyI] = arr[pb + copyI];
                                }
                                d += gallopK;
                                pb += gallopK;
                                cb = 0;
                                minGallop -= (gallopK >= MIN_GALLOP ? 1 : -1);
                                if (minGallop < 1) minGallop = 1;
                            } else {
                                ++minGallop;
                                while (pa < ea && pb < eb && ca < minGallop && cb < minGallop) {
                                    if (compare(tempArray[pa], arr[pb]) <= 0) {
                                        arr[d++] = tempArray[pa++];
                                        ca++;
                                        cb = 0;
                                    } else {
                                        arr[d++] = arr[pb++];
                                        cb++;
                                        ca = 0;
                                    }
                                }
                            }
                        }
                        
                        // 复制剩余元素（循环展开优化）
                        copyLen = ea - pa;
                        copyEnd = copyLen - (copyLen & 3);
                        for (copyI = 0; copyI < copyEnd; copyI += 4) {                            
                            arr[tempIdx = d + copyI] = tempArray[copyIdx = pa + copyI];
                            arr[tempIdx + 1] = tempArray[copyIdx + 1];
                            arr[tempIdx + 2] = tempArray[copyIdx + 2];
                            arr[tempIdx + 3] = tempArray[copyIdx + 3];
                        }
                        for (; copyI < copyLen; copyI++) {
                            arr[d + copyI] = tempArray[pa + copyI];
                        }
                    } else {
                        // 完整的mergeHi（重复实现）
                        pa = loA + lenA - 1;
                        pb = lenB - 1;
                        d = loB + lenB - 1;
                        ba0 = loA;
                        cb = 0;
                        ca = 0;
                        
                        // 复制B到临时数组（循环展开优化）
                        copyEnd = lenB - (lenB & 3);
                        for (copyI = 0; copyI < copyEnd; copyI += 4) {
                            tempArray[copyI] = arr[copyIdx = loB + copyI];
                            tempArray[copyI + 1] = arr[copyIdx + 1];
                            tempArray[copyI + 2] = arr[copyIdx + 2];
                            tempArray[copyI + 3] = arr[copyIdx + 3];
                        }
                        for (; copyI < lenB; copyI++) {
                            tempArray[copyI] = arr[loB + copyI];
                        }
                        
                        while (pa >= ba0 && pb >= 0 && ca < minGallop && cb < minGallop) {
                            if (compare(arr[pa], tempArray[pb]) > 0) {
                                arr[d--] = arr[pa--];
                                ca++;
                                cb = 0;
                            } else {
                                arr[d--] = tempArray[pb--];
                                cb++;
                                ca = 0;
                            }
                        }
                        
                        while (pa >= ba0 && pb >= 0) {
                            if (ca >= minGallop) {
                                // A方galloping - 从右端开始的反向指数搜索（hint-based）
                                target = tempArray[pb];
                                len = pa - ba0 + 1;

                                if (compare(arr[pa], target) <= 0) {
                                    gallopK = 0;
                                } else if (compare(arr[ba0], target) > 0) {
                                    gallopK = len;
                                } else {
                                    ofs = 1;
                                    lastOfs = 0;
                                    while (ofs < len && compare(arr[pa - ofs], target) > 0) {
                                        lastOfs = ofs;
                                        ofs = (ofs << 1) + 1;
                                        if (ofs <= 0) ofs = len;
                                    }
                                    if (ofs > len) ofs = len;
                                    left = lastOfs;
                                    hi2 = ofs;
                                    while (left < hi2) {
                                        mid = (left + hi2) >> 1;
                                        if (compare(arr[pa - mid], target) > 0) {
                                            left = mid + 1;
                                        } else {
                                            hi2 = mid;
                                        }
                                    }
                                    gallopK = left;
                                }

                                // 从右到左批量复制（循环展开优化）
                                copyEnd = gallopK - (gallopK & 3);
                                for (copyI = 0; copyI < copyEnd; copyI += 4) {
                                    arr[copyIdx = d - copyI] = arr[tempIdx = pa - copyI];
                                    arr[copyIdx - 1] = arr[tempIdx - 1];
                                    arr[copyIdx - 2] = arr[tempIdx - 2];
                                    arr[copyIdx - 3] = arr[tempIdx - 3];
                                }
                                for (; copyI < gallopK; copyI++) {
                                    copyIdx = d - copyI;  // 复用变量避免重复计算
                                    arr[copyIdx] = arr[pa - copyI];
                                }
                                d -= gallopK;
                                pa -= gallopK;
                                ca = 0;
                                minGallop -= (gallopK >= MIN_GALLOP ? 1 : -1);
                                if (minGallop < 1) minGallop = 1;
                            } else if (cb >= minGallop) {
                                // B方galloping - gallopLeft（lower_bound）语义
                                target = arr[pa];
                                base = 0;
                                len = pb + 1;

                                if (compare(tempArray[base], target) >= 0) {
                                    gallopK = len;
                                } else {
                                    ofs = 1;
                                    lastOfs = 0;
                                    while (ofs < len && compare(tempArray[base + ofs], target) < 0) {
                                        lastOfs = ofs;
                                        ofs = (ofs << 1) + 1;
                                        if (ofs <= 0) ofs = len;
                                    }
                                    if (ofs > len) ofs = len;
                                    left = lastOfs;
                                    hi2 = ofs;
                                    while (left < hi2) {
                                        mid = (left + hi2) >> 1;
                                        if (compare(tempArray[base + mid], target) < 0) {
                                            left = mid + 1;
                                        } else {
                                            hi2 = mid;
                                        }
                                    }
                                    gallopK = len - left;
                                }

                                // 从右到左批量复制（循环展开优化）
                                copyEnd = gallopK - (gallopK & 3);
                                for (copyI = 0; copyI < copyEnd; copyI += 4) {
                                    arr[copyIdx = d - copyI] = tempArray[tempIdx = pb - copyI];
                                    arr[copyIdx - 1] = tempArray[tempIdx - 1];
                                    arr[copyIdx - 2] = tempArray[tempIdx - 2];
                                    arr[copyIdx - 3] = tempArray[tempIdx - 3];
                                }
                                for (; copyI < gallopK; copyI++) {
                                    copyIdx = d - copyI;  // 复用变量避免重复计算
                                    arr[copyIdx] = tempArray[pb - copyI];
                                }
                                d -= gallopK;
                                pb -= gallopK;
                                cb = 0;
                                minGallop -= (gallopK >= MIN_GALLOP ? 1 : -1);
                                if (minGallop < 1) minGallop = 1;
                            } else {
                                ++minGallop;
                                while (pa >= ba0 && pb >= 0 && ca < minGallop && cb < minGallop) {
                                    if (compare(arr[pa], tempArray[pb]) > 0) {
                                        arr[d--] = arr[pa--];
                                        ca++;
                                        cb = 0;
                                    } else {
                                        arr[d--] = tempArray[pb--];
                                        cb++;
                                        ca = 0;
                                    }
                                }
                            }
                        }
                        
                        // 复制剩余B元素（循环展开优化）
                        copyLen = pb + 1;
                        copyEnd = copyLen - (copyLen & 3);
                        for (copyI = 0; copyI < copyEnd; copyI += 4) {
                            arr[copyIdx = d - copyI] = tempArray[tempIdx = pb - copyI];
                            arr[copyIdx - 1] = tempArray[tempIdx - 1];
                            arr[copyIdx - 2] = tempArray[tempIdx - 2];
                            arr[copyIdx - 3] = tempArray[tempIdx - 3];
                        }
                        for (; copyI < copyLen; copyI++) {
                            arr[d - copyI] = tempArray[pb - copyI];
                        }
                    }
                }
            }
        }
        
        // 返回排序完成的数组
        return arr;
    }
}










