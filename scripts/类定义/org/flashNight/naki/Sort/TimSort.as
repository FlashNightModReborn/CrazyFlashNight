/**
 * ActionScript 2.0 标准 TimSort 实现（s算法特性集成，后续需要进行常数细节优化）
 *
 * TimSort 是一个高度优化的混合稳定排序算法，由 Tim Peters 于 2002 年为 Python 语言设计。
 * 它结合了合并排序和插入排序的优点，特别擅长处理真实世界中的部分有序数据。
 * 
 * 核心特性：
 * 1. 稳定排序：相等元素的相对位置保持不变
 * 2. 自适应性：对已排序或部分排序的数据有近似 O(n) 的性能
 * 3. 疾速模式（Galloping Mode）：通过指数搜索+二分搜索优化结构化数据的合并
 * 4. 智能合并策略：通过堆栈管理和边界修剪减少不必要的比较
 * 5. 自然运行（Natural Runs）检测：识别并利用输入数据中的现有有序片段
 *
 * 时间复杂度：
 * - 最佳情况：O(n) - 数据已完全排序
 * - 平均情况：O(n log n) - 随机数据
 * - 最坏情况：O(n log n) - 完全逆序数据
 * 
 * 空间复杂度：O(n) - 需要额外的临时数组空间
 *
 * @since ActionScript 2.0
 */
class org.flashNight.naki.Sort.TimSort {
    
    // --- 私有常量定义 ---
    
    /**
     * 最小合并阈值
     * 当数组长度小于此值时，使用简单的插入排序而不是复杂的合并排序
     * 这个值是基于大量实验得出的最优值，平衡了算法复杂性和性能
     */
    private static var MIN_MERGE:Number = 32;
    
    /**
     * 疾速模式触发阈值
     * 当某个 run 连续获胜这么多次时，算法会切换到疾速模式（Galloping Mode）
     * 疾速模式使用指数搜索+二分搜索来快速定位大块数据的插入位置
     * 值 7 是 Tim Peters 通过理论分析和实验确定的最优值
     */
    private static var MIN_GALLOP:Number = 7;

    // --- 公共接口 ---

    /**
     * TimSort 主排序函数
     * 
     * 这是 TimSort 算法的入口点，负责：
     * 1. 参数验证和预处理
     * 2. 初始化算法状态
     * 3. 识别和处理自然运行（Natural Runs）
     * 4. 管理合并堆栈和合并策略
     * 5. 执行最终的强制合并
     * 
     * @param arr 待排序的数组，会被原地修改
     * @param compareFunction 比较函数，接受两个参数 (a, b)：
     *                       - 返回负数：a < b
     *                       - 返回 0：a == b  
     *                       - 返回正数：a > b
     *                       如果为 null，则使用默认的数值比较
     * @return 排序后的原数组（原地排序）
     */
    public static function sort(arr:Array, compareFunction:Function):Array {
        var n:Number = arr.length;
        
        // 边界情况：空数组或单元素数组无需排序
        if (n < 2) return arr;

        // 设置比较函数：如果未提供，使用默认的数值比较
        var compare:Function = (compareFunction == null)
            ? function(a, b):Number { return a - b; }
            : compareFunction;

        // 预分配临时数组：最大需要 n/2 的空间用于合并操作
        // 这是 TimSort 空间复杂度的主要来源
        var tempArray:Array = new Array(Math.ceil(n / 2));
        
        // 初始化算法状态对象，包含所有必要的工作数据
        var state:Object = {
            arr:        arr,              // 原始数组引用
            compare:    compare,          // 比较函数
            runStack:   new Array(),      // 运行堆栈，用于管理待合并的 runs
            minRun:     _calculateMinRun(n),  // 动态计算的最小运行长度
            tempArray:  tempArray,        // 临时工作数组
            minGallop:  MIN_GALLOP        // 疾速模式的动态阈值
        };

        // 主循环：逐步识别运行并合并，直到处理完整个数组
        var remaining:Number = n;
        var lo:Number = 0;
        while (remaining > 0) {
            // 步骤1：识别从当前位置开始的自然运行
            var runLen:Number = _countRunAndReverse(state, lo);
            
            // 步骤2：如果运行太短，使用插入排序扩展到最小长度
            if (runLen < state.minRun) {
                // 计算需要强制排序的长度：取剩余长度和最小运行长度的较小值
                var force:Number = (remaining < state.minRun) ? remaining : state.minRun;
                _insertionSort(state, lo, lo + force - 1);
                runLen = force;
            }
            
            // 步骤3：将新运行推入堆栈
            state.runStack.push({base: lo, len: runLen});
            
            // 步骤4：检查并执行必要的合并以维护堆栈不变量
            _mergeCollapse(state);
            
            // 步骤5：移动到下一个未处理的位置
            lo += runLen;
            remaining -= runLen;
        }

        // 最终步骤：强制合并剩余的所有运行
        _mergeForceCollapse(state);
        return arr;
    }

    // --- 私有核心辅助函数 ---

    /**
     * 计算最小运行长度（MinRun）
     * 
     * 这是 TimSort 的一个重要优化：动态计算最小运行长度，使得：
     * 1. 最终的合并树接近平衡
     * 2. 避免产生过多的小运行
     * 3. 确保 32 ≤ minRun ≤ 64（当 n ≥ 64 时）
     * 
     * 算法原理：
     * - 如果 n < 64，返回 n（使用插入排序处理整个数组）
     * - 否则，取 n 的高位几个比特，如果低位有任何 1 比特则加 1
     * - 这确保 n/minRun 接近但略小于 2 的幂，产生平衡的合并树
     * 
     * @param n 数组长度
     * @return 计算得出的最小运行长度
     */
    private static function _calculateMinRun(n:Number):Number {
        var r:Number = 0;
        
        // 持续右移 n 直到小于 MIN_MERGE（32）
        // 同时记录是否有低位比特被丢弃（r |= n & 1）
        while (n >= MIN_MERGE) {
            r |= (n & 1);  // 如果最低位是 1，记录下来
            n >>= 1;       // 右移一位
        }
        
        // 返回高位部分加上低位标志
        // 这确保如果原始 n 不是 2 的幂的倍数，结果会适当调整
        return n + r;
    }

    /**
     * 识别并处理自然运行（Natural Runs）
     * 
     * 自然运行是输入数据中已经有序（升序或严格降序）的连续片段。
     * TimSort 的关键优化之一就是识别这些片段并直接利用它们。
     * 
     * 处理规则：
     * 1. 升序运行：直接使用，允许相等元素
     * 2. 严格降序运行：识别后反转为升序
     * 
     * 注意：只有严格降序（不包含相等元素）才会被反转，这确保了算法的稳定性
     * 
     * @param state 算法状态对象
     * @param lo 运行的起始位置
     * @return 识别到的运行长度
     */
    private static function _countRunAndReverse(state:Object, lo:Number):Number {
        var arr:Array = state.arr;
        var compare:Function = state.compare;
        var hi:Number = lo + 1;
        
        // 边界情况：如果已到数组末尾，返回长度 1
        if (hi >= arr.length) return 1;

        // 检查第一对元素的关系来确定运行类型
        if (compare(arr[lo], arr[hi++]) > 0) { 
            // 降序运行：继续扫描严格降序的元素
            while (hi < arr.length && compare(arr[hi - 1], arr[hi]) > 0) {
                hi++;
            }
            // 将降序运行反转为升序，保证稳定性
            _reverseRange(arr, lo, hi - 1);
        } else { 
            // 升序运行：继续扫描非降序的元素（允许相等）
            while (hi < arr.length && compare(arr[hi - 1], arr[hi]) <= 0) {
                hi++;
            }
        }
        
        return hi - lo;
    }

    /**
     * 反转数组中指定范围的元素
     * 
     * 这个函数用于将严格降序的自然运行转换为升序。
     * 使用双指针技术，从两端向中间交换元素。
     * 
     * @param arr 目标数组
     * @param lo 反转范围的起始索引（包含）
     * @param hi 反转范围的结束索引（包含）
     */
    private static function _reverseRange(arr:Array, lo:Number, hi:Number):Void {
        while (lo < hi) {
            var t:Object = arr[lo];
            arr[lo++] = arr[hi];
            arr[hi--] = t;
        }
    }
    
    /**
     * 稳定插入排序
     * 
     * 对指定范围内的元素执行插入排序。插入排序在小数组上非常高效，
     * 并且是稳定的，这对 TimSort 的稳定性保证很重要。
     * 
     * 该实现使用了标准的插入排序算法：
     * 1. 从第二个元素开始，逐个处理每个元素
     * 2. 将当前元素与前面的已排序部分比较
     * 3. 找到合适位置并插入
     * 
     * 时间复杂度：
     * - 最佳情况：O(n) - 数据已排序
     * - 最坏情况：O(n²) - 数据完全逆序
     * 
     * @param state 算法状态对象
     * @param left 排序范围的起始索引（包含）
     * @param right 排序范围的结束索引（包含）
     */
    private static function _insertionSort(state:Object, left:Number, right:Number):Void {
        var arr:Array = state.arr;
        var compare:Function = state.compare;
        
        // 从第二个元素开始，逐个插入到正确位置
        for (var i:Number = left + 1; i <= right; i++) {
            var key:Object = arr[i];  // 当前要插入的元素
            var j:Number = i - 1;     // 已排序部分的最后一个元素
            
            // 向左搜索插入位置，同时移动较大的元素
            while (j >= left && compare(arr[j], key) > 0) {
                arr[j + 1] = arr[j];  // 移动元素为新元素腾出空间
                j--;
            }
            
            // 在找到的位置插入元素
            arr[j + 1] = key;
        }
    }

    /**
     * 合并堆栈折叠
     * 
     * 这是 TimSort 的核心部分之一，负责维护运行堆栈的不变量。
     * 不变量确保：
     * 1. stack[i].len > stack[i+1].len + stack[i+2].len（对于所有有效的 i）
     * 2. stack[i].len > stack[i+1].len（对于所有有效的 i）
     * 
     * 这些不变量保证：
     * - 合并操作的总时间复杂度为 O(n log n)
     * - 避免退化到 O(n²) 的最坏情况
     * - 产生平衡的合并树结构
     * 
     * @param state 算法状态对象
     */
    private static function _mergeCollapse(state:Object):Void {
        var stack:Array = state.runStack;
        
        // 持续检查和修复堆栈不变量，直到不需要更多合并
        while (stack.length > 1) {
            var n:Number = stack.length - 2;  // 倒数第二个运行的索引
            
            // 检查第一个不变量：stack[n-1].len <= stack[n].len + stack[n+1].len
            if (n > 0 && stack[n - 1].len <= stack[n].len + stack[n + 1].len) {
                // 不变量被违反，选择较小的一对进行合并
                if (stack[n - 1].len < stack[n + 1].len) {
                    _mergeAt(state, n - 1);  // 合并 stack[n-1] 和 stack[n]
                } else {
                    _mergeAt(state, n);      // 合并 stack[n] 和 stack[n+1]
                }
            } 
            // 检查第二个不变量：stack[n].len <= stack[n+1].len
            else if (stack[n].len <= stack[n + 1].len) {
                _mergeAt(state, n);          // 合并 stack[n] 和 stack[n+1]
            } 
            else {
                break;  // 不变量已满足，退出循环
            }
        }
    }

    /**
     * 强制合并堆栈中的所有运行
     * 
     * 在主排序循环结束后调用，将堆栈中剩余的所有运行合并成一个。
     * 这个过程类似于 _mergeCollapse，但不维护严格的不变量，
     * 只是简单地从右到左合并所有运行。
     * 
     * 合并策略：始终选择较平衡的合并（合并较小的相邻对）
     * 
     * @param state 算法状态对象
     */
    private static function _mergeForceCollapse(state:Object):Void {
        var stack:Array = state.runStack;
        
        // 继续合并直到只剩一个运行
        while (stack.length > 1) {
            var n:Number = stack.length - 2;
            
            // 如果有三个或更多运行，选择更平衡的合并
            if (n > 0 && stack[n - 1].len < stack[n + 1].len) {
                _mergeAt(state, n - 1);  // 合并较小的一对
            } else {
                _mergeAt(state, n);      // 合并最后两个
            }
        }
    }

    /**
     * 合并堆栈中指定位置的两个相邻运行
     * 
     * 这是 TimSort 合并策略的核心，负责：
     * 1. 边界修剪：通过二分搜索找到真正需要合并的部分
     * 2. 合并方向选择：选择更节省内存的合并方向
     * 3. 调用相应的合并函数
     * 
     * 边界修剪优化：
     * - 如果 runA 的所有元素都小于 runB 的第一个元素，无需合并
     * - 如果 runB 的所有元素都大于 runA 的最后一个元素，无需合并
     * - 否则，只合并真正重叠的部分
     * 
     * @param state 算法状态对象
     * @param i 第一个运行在堆栈中的索引（将与 i+1 合并）
     */
    private static function _mergeAt(state:Object, i:Number):Void {
        var stack:Array = state.runStack;
        var runA:Object = stack[i];      // 第一个运行
        var runB:Object = stack[i + 1];  // 第二个运行

        // 更新堆栈：合并两个运行的记录
        stack[i] = {base: runA.base, len: runA.len + runB.len};
        stack.splice(i + 1, 1);  // 移除第二个运行的记录
        
        var arr:Array = state.arr;
        
        // 边界修剪步骤1：找到 runB 的第一个元素在 runA 中的插入位置
        // 这确定了 runA 中有多少元素不需要参与合并
        var k:Number = _gallopRight(state, arr[runB.base], arr, runA.base, runA.len);
        var loA:Number = runA.base + k;  // runA 的有效起始位置
        var lenA:Number = runA.len - k;  // runA 的有效长度
        
        // 如果 runA 完全小于 runB，无需合并
        if (lenA == 0) return;

        // 边界修剪步骤2：找到 runA 的最后一个元素在 runB 中的插入位置
        // 这确定了 runB 中有多少元素需要参与合并
        k = _gallopLeft(state, arr[loA + lenA - 1], arr, runB.base, runB.len);
        var lenB:Number = k;  // runB 的有效长度
        
        // 如果 runB 完全大于 runA，无需合并
        if (lenB == 0) return;

        // 选择合并方向：将较小的运行复制到临时空间
        // 这最小化了临时空间的使用和复制操作的数量
        if (lenA <= lenB) {
            // runA 较小，使用 mergeLo（从左到右合并）
            _mergeLo(state, {base: loA, len: lenA}, {base: runB.base, len: lenB});
        } else {
            // runB 较小，使用 mergeHi（从右到左合并）
            _mergeHi(state, {base: loA, len: lenA}, {base: runB.base, len: lenB});
        }
    }
    
    /**
     * 从左到右合并两个运行（mergeLo）
     * 
     * 将较小的运行（runA）复制到临时空间，然后与较大的运行（runB）合并。
     * 结果写回到原始位置。这个方向适用于 runA 较小的情况。
     * 
     * 合并过程：
     * 1. 将 runA 复制到临时数组
     * 2. 使用双指针技术合并 temp[runA] 和 arr[runB]
     * 3. 检测并进入疾速模式以优化结构化数据
     * 4. 处理剩余元素
     * 
     * 疾速模式触发条件：
     * - 当某个运行连续获胜 minGallop 次时触发
     * - 使用指数搜索+二分搜索快速找到大块数据的插入位置
     * 
     * @param state 算法状态对象
     * @param runA 第一个运行的信息（将被复制到临时空间）
     * @param runB 第二个运行的信息（保持在原数组中）
     */
    private static function _mergeLo(state:Object, runA:Object, runB:Object):Void {
        var arr:Array = state.arr;
        var compare:Function = state.compare;
        var temp:Array = state.tempArray;

        // 步骤1：将 runA 复制到临时数组
        for (var i:Number = 0; i < runA.len; i++) {
            temp[i] = arr[runA.base + i];
        }

        // 初始化合并指针和计数器
        var ptrA:Number = 0;                    // 临时数组（runA）的当前位置
        var ptrB:Number = runB.base;            // 原数组（runB）的当前位置  
        var dest:Number = runA.base;            // 目标位置（结果写入位置）
        var endA:Number = runA.len;             // 临时数组的结束位置
        var endB:Number = runB.base + runB.len; // runB 的结束位置
        var countA:Number = 0;                  // runA 连续获胜次数
        var countB:Number = 0;                  // runB 连续获胜次数

        // 主合并循环：逐个比较元素，统计连续获胜次数
        while (ptrA < endA && ptrB < endB) {
            // 稳定性保证：相等时优先选择 runA（左侧运行）
            if (compare(temp[ptrA], arr[ptrB]) <= 0) {
                // runA 获胜
                arr[dest++] = temp[ptrA++];
                countA++; 
                countB = 0;
                
                // 检查疾速模式触发条件
                if (countA >= state.minGallop) {
                    // 进入疾速模式：批量移动 runB 中小于当前 runA 元素的所有元素
                    var k:Number = _gallopRight(state, temp[ptrA], arr, ptrB, endB - ptrB);
                    
                    // 批量复制找到的元素
                    for (var j:Number = 0; j < k; j++) {
                        arr[dest + j] = arr[ptrB + j];
                    }
                    dest += k; 
                    ptrB += k;
                    
                    // 调整疾速阈值：成功则降低阈值，否则提高阈值
                    if (k < MIN_GALLOP) state.minGallop++;
                    state.minGallop = Math.max(1, state.minGallop - 1);
                    countA = 0;
                }
            } else {
                // runB 获胜
                arr[dest++] = arr[ptrB++];
                countB++; 
                countA = 0;
                
                // 检查疾速模式触发条件
                if (countB >= state.minGallop) {
                    // 进入疾速模式：批量移动 runA 中小于等于当前 runB 元素的所有元素
                    var k:Number = _gallopLeft(state, arr[ptrB], temp, ptrA, endA - ptrA);
                    
                    // 批量复制找到的元素
                    for (var j:Number = 0; j < k; j++) {
                        arr[dest + j] = temp[ptrA + j];
                    }
                    dest += k; 
                    ptrA += k;
                    
                    // 调整疾速阈值
                    if (k < MIN_GALLOP) state.minGallop++;
                    state.minGallop = Math.max(1, state.minGallop - 1);
                    countB = 0;
                }
            }
        }
        
        // 复制 runA 的剩余元素（runB 的剩余元素已在正确位置）
        while (ptrA < endA) {
            arr[dest++] = temp[ptrA++];
        }
    }
    
    /**
     * 从右到左合并两个运行（mergeHi）
     * 
     * 将较小的运行（runB）复制到临时空间，然后从右到左与较大的运行（runA）合并。
     * 这个方向适用于 runB 较小的情况，避免了覆盖尚未处理的数据。
     * 
     * 算法特点：
     * 1. 从两个运行的末尾开始，向前合并
     * 2. 较大的元素先被放置到最终位置
     * 3. 支持疾速模式优化
     * 4. 保证算法的稳定性
     * 
     * @param state 算法状态对象
     * @param runA 第一个运行的信息（保持在原数组中）
     * @param runB 第二个运行的信息（将被复制到临时空间）
     */
    private static function _mergeHi(state:Object, runA:Object, runB:Object):Void {
        var arr:Array = state.arr;
        var compare:Function = state.compare;
        var temp:Array = state.tempArray;
        
        // 步骤1：将 runB 复制到临时数组
        for (var i:Number = 0; i < runB.len; i++) {
            temp[i] = arr[runB.base + i];
        }

        // 初始化合并指针和计数器（从末尾开始）
        var ptrA:Number = runA.base + runA.len - 1;  // runA 的最后一个元素
        var ptrB:Number = runB.len - 1;              // 临时数组的最后一个元素
        var dest:Number = runB.base + runB.len - 1;  // 目标位置（从右到左填充）
        var baseA:Number = runA.base;                // runA 的起始位置
        var baseB:Number = 0;                        // 临时数组的起始位置
        var countA:Number = 0;                       // runA 连续获胜次数
        var countB:Number = 0;                       // runB 连续获胜次数

        // 主合并循环：从右到左比较元素
        while (ptrA >= baseA && ptrB >= baseB) {
            // 稳定性保证：相等时优先选择 runB（右侧运行）
            if (compare(arr[ptrA], temp[ptrB]) > 0) {
                // runA 获胜（元素更大）
                arr[dest--] = arr[ptrA--];
                countA++; 
                countB = 0;
                
                // 检查疾速模式触发条件
                if (countA >= state.minGallop) {
                    var lenToSearch:Number = ptrA - baseA + 1;
                    
                    // 查找 runA 中有多少元素大于当前 runB 元素
                    // 使用 _gallopLeft 找到小于等于的元素数量，然后用总数减去它
                    var k:Number = lenToSearch - _gallopLeft(state, temp[ptrB], arr, baseA, lenToSearch);
                    
                    // 批量移动找到的元素（从右到左）
                    for(var j:Number = 0; j < k; j++) {
                        arr[dest - j] = arr[ptrA - j];
                    }
                    dest -= k; 
                    ptrA -= k;
                    
                    // 调整疾速阈值
                    if (k < MIN_GALLOP) state.minGallop++;
                    state.minGallop = Math.max(1, state.minGallop - 1);
                    countA = 0;
                }
            } else {
                // runB 获胜（元素更大或相等）
                arr[dest--] = temp[ptrB--];
                countB++; 
                countA = 0;
                
                // 检查疾速模式触发条件
                if (countB >= state.minGallop) {
                    var lenToSearch:Number = ptrB - baseB + 1;
                    
                    // 查找 runB 中有多少元素大于当前 runA 元素
                    var k:Number = lenToSearch - _gallopLeft(state, arr[ptrA], temp, baseB, lenToSearch);
                    
                    // 批量移动找到的元素（从右到左）
                    for(var j:Number = 0; j < k; j++) {
                        arr[dest - j] = temp[ptrB - j];
                    }
                    dest -= k; 
                    ptrB -= k;
                    
                    // 调整疾速阈值
                    if (k < MIN_GALLOP) state.minGallop++;
                    state.minGallop = Math.max(1, state.minGallop - 1);
                    countB = 0;
                }
            }
        }
        
        // 复制 runB 的剩余元素（runA 的剩余元素已在正确位置）
        while (ptrB >= baseB) {
            arr[dest--] = temp[ptrB--];
        }
    }
    
    /**
     * 疾速搜索：查找严格小于指定值的元素数量（等价于 Python 的 gallop_left）
     * 
     * 这个函数实现了 TimSort 疾速模式的核心算法：指数搜索 + 二分搜索。
     * 它用于快速找到一个值在有序数组中的插入位置（lower bound）。
     * 
     * 算法步骤：
     * 1. 指数搜索阶段：使用 1, 3, 7, 15, 31... 的步长快速定位范围
     * 2. 二分搜索阶段：在找到的范围内精确定位
     * 
     * 时间复杂度：O(log k)，其中 k 是目标位置的距离
     * 这比普通二分搜索的 O(log n) 更优，特别是当目标很近时
     * 
     * @param state 算法状态对象
     * @param key 要搜索的关键值
     * @param a 有序数组
     * @param base 搜索范围的起始位置
     * @param len 搜索范围的长度
     * @return 数组中严格小于 key 的元素数量
     */
    private static function _gallopRight(state:Object, key:Object, a:Array, base:Number, len:Number):Number {
        var compare:Function = state.compare;
        var ofs:Number = 1;      // 当前偏移量
        var lastOfs:Number = 0;  // 上一个偏移量
        
        // 边界检查：空数组或第一个元素就不小于 key
        if (len == 0 || compare(a[base], key) >= 0) return 0;
        
        // 指数搜索阶段：找到包含目标位置的范围 [lastOfs, ofs]
        while (ofs < len && compare(a[base + ofs], key) < 0) {
            lastOfs = ofs;
            ofs = (ofs << 1) + 1;  // 指数增长：1, 3, 7, 15, 31...
            if (ofs <= 0) ofs = len;  // 溢出保护
        }
        if (ofs > len) ofs = len;

        // 二分搜索阶段：在 [lastOfs, ofs] 范围内精确定位
        return lastOfs + _binarySearchLeft(a, compare, key, base + lastOfs, ofs - lastOfs);
    }
    
    /**
     * 疾速搜索：查找小于或等于指定值的元素数量（等价于 Python 的 gallop_right）
     * 
     * 这个函数与 _gallopRight 类似，但查找的是 upper bound 而不是 lower bound。
     * 它返回数组中小于或等于指定值的元素数量。
     * 
     * 主要区别：
     * - 比较条件使用 <= 而不是 <
     * - 调用 _binarySearchRight 而不是 _binarySearchLeft
     * - 用于找到 upper bound（第一个大于 key 的位置）
     * 
     * @param state 算法状态对象
     * @param key 要搜索的关键值
     * @param a 有序数组
     * @param base 搜索范围的起始位置
     * @param len 搜索范围的长度
     * @return 数组中小于或等于 key 的元素数量
     */
    private static function _gallopLeft(state:Object, key:Object, a:Array, base:Number, len:Number):Number {
        var compare:Function = state.compare;
        var ofs:Number = 1;      // 当前偏移量
        var lastOfs:Number = 0;  // 上一个偏移量
        
        // 边界检查：空数组或第一个元素就大于 key
        if (len == 0 || compare(a[base], key) > 0) return 0;
        
        // 指数搜索阶段：找到包含目标位置的范围 [lastOfs, ofs]
        while (ofs < len && compare(a[base + ofs], key) <= 0) {
            lastOfs = ofs;
            ofs = (ofs << 1) + 1;  // 指数增长：1, 3, 7, 15, 31...
            if (ofs <= 0) ofs = len;  // 溢出保护
        }
        if (ofs > len) ofs = len;

        // 二分搜索阶段：在 [lastOfs, ofs] 范围内精确定位
        return lastOfs + _binarySearchRight(a, compare, key, base + lastOfs, ofs - lastOfs);
    }
    
    /**
     * 二分搜索：查找第一个大于或等于指定值的位置（lower bound）
     * 
     * 这是标准的 lower bound 二分搜索实现，用于找到：
     * - 第一个 >= value 的元素位置
     * - 等价地，< value 的元素数量
     * 
     * 算法保证：
     * - 返回的位置 pos 满足：arr[base + pos - 1] < value <= arr[base + pos]
     * - 如果所有元素都 < value，返回 len
     * - 如果所有元素都 >= value，返回 0
     * 
     * @param arr 有序数组
     * @param compare 比较函数
     * @param value 要搜索的值
     * @param base 搜索范围的起始位置
     * @param len 搜索范围的长度
     * @return 第一个 >= value 的元素相对于 base 的偏移量
     */
    private static function _binarySearchLeft(arr:Array, compare:Function, value:Object, base:Number, len:Number):Number {
        var lo:Number = 0;     // 搜索范围的左边界
        var hi:Number = len;   // 搜索范围的右边界
        
        // 标准二分搜索循环
        while (lo < hi) {
            var mid:Number = lo + ((hi - lo) >> 1);  // 计算中点，避免溢出
            
            if (compare(arr[base + mid], value) < 0) {
                lo = mid + 1;  // 中点元素太小，搜索右半部分
            } else {
                hi = mid;      // 中点元素足够大，搜索左半部分（包含中点）
            }
        }
        
        return lo;
    }

    /**
     * 二分搜索：查找第一个大于指定值的位置（upper bound）
     * 
     * 这是标准的 upper bound 二分搜索实现，用于找到：
     * - 第一个 > value 的元素位置
     * - 等价地，<= value 的元素数量
     * 
     * 算法保证：
     * - 返回的位置 pos 满足：arr[base + pos - 1] <= value < arr[base + pos]
     * - 如果所有元素都 <= value，返回 len
     * - 如果所有元素都 > value，返回 0
     * 
     * @param arr 有序数组
     * @param compare 比较函数
     * @param value 要搜索的值
     * @param base 搜索范围的起始位置
     * @param len 搜索范围的长度
     * @return 第一个 > value 的元素相对于 base 的偏移量
     */
    private static function _binarySearchRight(arr:Array, compare:Function, value:Object, base:Number, len:Number):Number {
        var lo:Number = 0;     // 搜索范围的左边界
        var hi:Number = len;   // 搜索范围的右边界
        
        // 标准二分搜索循环
        while (lo < hi) {
            var mid:Number = lo + ((hi - lo) >> 1);  // 计算中点，避免溢出
            
            if (compare(arr[base + mid], value) <= 0) {
                lo = mid + 1;  // 中点元素不够大，搜索右半部分
            } else {
                hi = mid;      // 中点元素太大，搜索左半部分（包含中点）
            }
        }
        
        return lo;
    }
}