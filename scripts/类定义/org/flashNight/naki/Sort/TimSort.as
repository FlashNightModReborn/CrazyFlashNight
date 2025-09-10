/**
 * ActionScript 2.0 完全内联 TimSort 实现（变量声明提升优化版本）
 * 
 * TimSort是一种混合稳定排序算法，由Tim Peters于2002年为Python设计。
 * 它结合了归并排序和插入排序的优势，在现实世界的数据上表现优异。
 * 
 * 算法特点：
 * - 稳定排序：相等元素的相对顺序不会改变
 * - 自适应性：对部分有序的数据有很好的性能
 * - 最优时间复杂度：O(n) 当数据已排序时
 * - 最坏时间复杂度：O(n log n)
 * - 空间复杂度：O(n)
 * 
 * 此实现特点：
 * - 完全内联所有辅助方法，减少函数调用开销
 * - 变量声明提升，优化AS2解释器性能
 * - 保持完整的galloping模式优化
 * - 适用于Flash/ActionScript 2.0环境
 * 
 */
class org.flashNight.naki.Sort.TimSort {
    
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
         * ===============================
         * 变量声明提升区域 - 性能优化
         * ===============================
         * 
         * 由于AS2只有函数作用域，所有var声明会被提升到函数顶部。
         * 在此统一声明所有变量以优化解释器性能。
         */
        
        // 基础控制变量
        var n:Number,                    // 数组长度
            MIN_MERGE:Number,            // 最小合并大小常量 (32)
            MIN_GALLOP:Number;           // 最小galloping触发阈值 (7)
        
        // 核心算法变量
        var compare:Function,            // 比较函数
            tempArray:Array,             // 临时数组，用于合并操作
            runBase:Array,               // run起始位置栈
            runLen:Array,                // run长度栈
            stackSize:Number,            // 栈大小
            minGallop:Number;            // 动态galloping阈值
        
        // minRun计算相关
        var minRun:Number;               // 最小run长度
            // tempN, r 复用 ofs, lastOfs (在minRun计算阶段)
        
        // 主循环控制
        var remaining:Number,            // 剩余待处理元素数
            lo:Number;                   // 当前处理位置
        
        // run检测和处理
        var runLength:Number,            // 当前run长度
            hi:Number;                   // run结束位置
        
        // 数组反转相关
        var revLo:Number,                // 反转起始位置
            revHi:Number,                // 反转结束位置  
            tmp:Object;                  // 临时交换变量
        
        // 插入排序相关
        var force:Number,                // 强制排序长度
            right:Number,                // 插入排序右边界
            i:Number,                    // 循环计数器
            key:Object,                  // 待插入元素
            j:Number;                    // 内层循环计数器
        
        // 合并栈管理
        var size:Number,                 // 当前栈大小
            n_idx:Number,                // 栈索引
            shouldMerge:Boolean,         // 是否需要合并标志
            mergeIdx:Number;             // 合并位置索引
            // mergeN 复用 copyLen, mergeJ 复用 copyI
        
        // 合并操作核心变量
        var loA:Number,                  // A区域起始位置
            lenA:Number,                 // A区域长度
            loB:Number,                  // B区域起始位置
            lenB:Number;                 // B区域长度
        
        // Galloping搜索变量
        var gallopK:Number,              // galloping搜索结果
            target:Object,               // 搜索目标元素
            base:Number,                 // 搜索基准位置
            len:Number;                  // 搜索长度
        
        // 指数搜索变量
        var ofs:Number,                  // 当前偏移量
            lastOfs:Number;              // 上一个偏移量
        
        // 二分搜索复用 left, hi2, mid
        // gallopK2 复用 gallopK (串行使用)
        
        // 合并详细操作变量
        var pa:Number,                   // A指针位置
            pb:Number,                   // B指针位置
            d:Number,                    // 目标写入位置
            ea:Number,                   // A区域结束位置
            eb:Number,                   // B区域结束位置
            ca:Number,                   // A连续获胜计数
            cb:Number,                   // B连续获胜计数
            tempIdx:Number,              // 临时索引
            copyLen:Number,              // 复制长度
            copyI:Number,                // 复制循环计数器
            copyIdx:Number,              // 循环展开索引
            copyEnd:Number;              // 循环展开结束位置
        
        // mergeHi特殊变量
        var ba0:Number;                  // A区域基准位置
        
        // 强制合并变量
        var forceIdx:Number;             // 强制合并索引

        // 统一提前声明的二分/插入排序及循环展开辅助变量
        var left:Number;                 // 二分左边界/插入排序用/复用为bsLo
        var hi2:Number;                  // 二分右边界/复用为bsHi
        var mid:Number;                  // 二分中点/复用为bsMid
        // dstBase, srcBase 直接使用计算，不声明
        var stackCapacity:Number;        // 运行栈预分配容量

        /*
         * ===============================
         * 算法主体开始
         * ===============================
         */
        
        // 初始化基本参数
        n = arr.length;
        if (n < 2) return arr;           // 长度小于2直接返回
        
        // 设置算法常量
        MIN_MERGE = 32;                  // 小于此值使用插入排序
        MIN_GALLOP = 7;                  // galloping模式触发阈值
        
        // 初始化比较函数
        compare = (compareFunction == null)
            ? function(a, b):Number { return a - b; }    // 默认数值比较
            : compareFunction;
        
        // 初始化核心数据结构
        tempArray = new Array(Math.ceil(n / 2));         // 临时数组，最大需要n/2空间
        stackCapacity = 64;                                    // 栈容量预分配
        runBase = new Array(stackCapacity);                                    // run栈：存储run起始位置
        runLen = new Array(stackCapacity);                                     // run栈：存储run长度
        stackSize = 0;                                   // 栈大小初始化
        minGallop = MIN_GALLOP;                         // 动态galloping阈值
        
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

                for (i = lo + 1; i <= right; i++) {
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
                    // 将 [left, i) 整体右移一位
                    j = i;
                    while (j > left) {
                        arr[j] = arr[j - 1];
                        j--;
                    }
                    // 向前查找插入位置
                    /*
                    
                    // 旧的线性插入已由二分插入替代，保留为空循环以减少改动面

                    while (false && j >= lo && compare(arr[j], key) > 0) {
                        arr[j + 1] = arr[j--];
                    }
                    
                    */
                    // 将 key 放到计算出的稳定插入位置
                    arr[left] = key;
                }
                runLength = force;
            }
            
            // 将run推入栈
            runBase[stackSize] = lo;
            runLen[stackSize++] = runLength;
            
            /*
             * 合并栈平衡 (内联 _mergeCollapse)
             * ===============================
             * 
             * TimSort的关键优化：维护栈不变量
             * 栈顶的三个run必须满足：
             * 1. runLen[i-1] > runLen[i] + runLen[i+1]
             * 2. runLen[i] > runLen[i+1]
             * 
             * 这确保了合并的平衡性，避免最坏情况的O(n²)复杂度
             */
            size = stackSize;
            while (size > 1) {
                n_idx = size - 2;
                shouldMerge = false;
                
                // 检查栈不变量
                if (n_idx > 0 && runLen[n_idx - 1] <= runLen[n_idx] + runLen[n_idx + 1]) {
                    // 违反第一个不变量，选择较小的run合并
                    mergeIdx = n_idx - (runLen[n_idx - 1] < runLen[n_idx + 1]);
                    shouldMerge = true;
                } else if (runLen[n_idx] <= runLen[n_idx + 1]) {
                    // 违反第二个不变量
                    mergeIdx = n_idx;
                    shouldMerge = true;
                }
                
                if (!shouldMerge) break;
                
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
                loA = runBase[mergeIdx];
                lenA = runLen[mergeIdx];
                loB = runBase[mergeIdx + 1];
                lenB = runLen[mergeIdx + 1];
                
                // 更新栈：合并后的run长度
                runLen[mergeIdx] = lenA + lenB;
                
                // 栈元素向前移动
                copyLen = stackSize - 1;  // 复用copyLen作为mergeN
                for (copyI = mergeIdx + 1; copyI < copyLen; copyI++) {  // 复用copyI作为mergeJ
                    runBase[copyI] = runBase[copyI + 1];
                    runLen[copyI] = runLen[copyI + 1];
                }
                stackSize--;
                
                /*
                 * Galloping右搜索优化 (内联 _gallopRight)
                 * ======================================
                 * 
                 * 查找B的第一个元素在A中的插入位置
                 * 如果B[0] >= A的所有元素，可以跳过整个A
                 */
                gallopK = 0;
                target = arr[loB];      // B的第一个元素
                base = loA;
                len = lenA;
                
                if (len == 0 || compare(arr[base], target) >= 0) {
                    gallopK = 0;        // 插入到A的开头
                } else {
                    // 指数搜索：快速定位大致范围
                    ofs = 1;
                    lastOfs = 0;
                    
                    while (ofs < len && compare(arr[base + ofs], target) < 0) {
                        lastOfs = ofs;
                        ofs = (ofs << 1) + 1;    // 指数增长
                        if (ofs <= 0) ofs = len; // 溢出保护
                    }
                    if (ofs > len) ofs = len;
                    
                    // 二分搜索：精确定位 (内联 _binarySearchLeft)
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
                    
                    if (len == 0 || compare(arr[base], target) > 0) {
                        gallopK = 0;              // 插入到B的开头
                    } else {
                        // 指数搜索
                        ofs = 1;
                        lastOfs = 0;
                        
                        while (ofs < len && compare(arr[base + ofs], target) <= 0) {
                            lastOfs = ofs;
                            ofs = (ofs << 1) + 1;
                            if (ofs <= 0) ofs = len;
                        }
                        if (ofs > len) ofs = len;
                        
                        // 二分搜索 (内联 _binarySearchRight)
                        left = lastOfs;  // 复用left作为bsLo
                        hi2 = ofs;       // 复用hi2作为bsHi
                        while (left < hi2) {
                            mid = (left + hi2) >> 1;  // 复用mid作为bsMid
                            if (compare(arr[base + mid], target) <= 0) {
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
                            for (i = 0; i < left; i++) {
                                arr[loA + i] = arr[loB + i];
                            }
                            arr[loA + left] = tmp;
                            for (i = left; i < lenB; i++) {
                                arr[loA + i + 1] = arr[loB + i];
                            }
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
                        }/*
                         * 选择合并方向
                         * =============
                         * 
                         * 选择移动较少元素的方向：
                         * - mergeLo：从左到右合并，复制较短的A到临时数组
                         * - mergeHi：从右到左合并，复制较短的B到临时数组
                         */
                        if (lenA <= lenB) {
                            /*
                             * 执行mergeLo (内联 _mergeLo)
                             * ==========================
                             * 
                             * 从左到右合并，使用临时数组保存A
                             * 包含galloping模式优化
                             */
                            pa = 0;                  // 临时数组A的指针
                            pb = loB;                // 数组B的指针
                            d = loA;                 // 目标位置指针
                            ea = lenA;               // A的结束位置
                            eb = loB + lenB;         // B的结束位置
                            ca = 0;                  // A连续获胜计数
                            cb = 0;                  // B连续获胜计数
                            
                            // 复制A到临时数组（循环展开优化）
                            copyEnd = lenA - (lenA & 3);  // 4的倍数部分
                            for (copyI = 0; copyI < copyEnd; copyI += 4) {
                                copyIdx = loA + copyI;
                                tempArray[copyI] = arr[copyIdx];
                                tempArray[copyI + 1] = arr[copyIdx + 1];
                                tempArray[copyI + 2] = arr[copyIdx + 2];
                                tempArray[copyI + 3] = arr[copyIdx + 3];
                            }
                            // 处理剩余元素
                            for (; copyI < lenA; copyI++) {
                                tempArray[copyI] = arr[loA + copyI];
                            }
                            
                            // 初始的简单合并阶段
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
                            
                            /*
                             * Galloping模式合并
                             * ================
                             * 
                             * 当一边连续获胜时，进入galloping模式
                             * 通过指数搜索快速跳过大量元素
                             */
                            while (pa < ea && pb < eb) {
                                if (ca >= minGallop) {
                                    // A方进入galloping模式 (内联 gallopRight 逻辑)
                                    target = tempArray[pa];
                                    base = pb;
                                    len = eb - pb;
                                    gallopK = 0;
                                    
                                    if (len == 0 || compare(arr[base], target) >= 0) {
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
                                    
                                    // 批量复制B中的元素（循环展开优化）
                                    copyEnd = gallopK - (gallopK & 3);
                                    for (copyI = 0; copyI < copyEnd; copyI += 4) {
                                        arr[d + copyI] = arr[pb + copyI];
                                        arr[d + copyI + 1] = arr[pb + copyI + 1];
                                        arr[d + copyI + 2] = arr[pb + copyI + 2];
                                        arr[d + copyI + 3] = arr[pb + copyI + 3];
                                    }
                                    for (; copyI < gallopK; copyI++) {
                                        arr[d + copyI] = arr[pb + copyI];
                                    }
                                    d += gallopK;
                                    pb += gallopK;
                                    ca = 0;
                                    
                                    // 动态调整galloping阈值
                                    minGallop -= (gallopK >= MIN_GALLOP ? 1 : -1);
                                    if (minGallop < 1) minGallop = 1;
                                } else if (cb >= minGallop) {
                                    // B方进入galloping模式 (内联 gallopLeft 逻辑)
                                    target = arr[pb];
                                    base = pa;
                                    len = ea - pa;
                                    gallopK = 0;
                                    
                                    if (len == 0 || compare(tempArray[base], target) > 0) {
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
                                    
                                    // 批量复制A中的元素（循环展开优化）
                                    copyEnd = gallopK - (gallopK & 3);
                                    for (copyI = 0; copyI < copyEnd; copyI += 4) {
                                        copyIdx = pa + copyI;
                                        copyIdx = pa + copyI;
                                        arr[d + copyI] = tempArray[copyIdx];
                                        arr[d + copyI + 1] = tempArray[copyIdx + 1];
                                        arr[d + copyI + 2] = tempArray[copyIdx + 2];
                                        arr[d + copyI + 3] = tempArray[copyIdx + 3];
                                    }
                                    for (; copyI < gallopK; copyI++) {
                                        arr[d + copyI] = tempArray[pa + copyI];
                                    }
                                    d += gallopK;
                                    pa += gallopK;
                                    cb = 0;
                                    
                                    // 动态调整galloping阈值
                                    minGallop -= (gallopK >= MIN_GALLOP ? 1 : -1);
                                    if (minGallop < 1) minGallop = 1;
                                } else {
                                    // 退出galloping模式，回到简单合并
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
                            
                            // 复制剩余的A元素（循环展开优化）
                            copyLen = ea - pa;
                            copyEnd = copyLen - (copyLen & 3);
                            for (copyI = 0; copyI < copyEnd; copyI += 4) {
                                copyIdx = pa + copyI;
                                copyIdx = pa + copyI;
                                arr[d + copyI] = tempArray[copyIdx];
                                arr[d + copyI + 1] = tempArray[copyIdx + 1];
                                arr[d + copyI + 2] = tempArray[copyIdx + 2];
                                arr[d + copyI + 3] = tempArray[copyIdx + 3];
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
                                copyIdx = loB + copyI;
                                tempArray[copyI] = arr[copyIdx];
                                tempArray[copyI + 1] = arr[copyIdx + 1];
                                tempArray[copyI + 2] = arr[copyIdx + 2];
                                tempArray[copyI + 3] = arr[copyIdx + 3];
                            }
                            for (; copyI < lenB; copyI++) {
                                tempArray[copyI] = arr[loB + copyI];
                            }
                            
                            // 初始的简单合并阶段（从右到左）
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
                            
                            // Galloping模式合并（从右到左）
                            while (pa >= ba0 && pb >= 0) {
                                if (ca >= minGallop) {
                                    // A方galloping (内联 gallopLeft 逻辑用于mergeHi)
                                    target = tempArray[pb];
                                    base = ba0;
                                    len = pa - ba0 + 1;
                                    gallopK = len;
                                    
                                    if (len == 0 || compare(arr[base], target) > 0) {
                                        gallopK = len;
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
                                        gallopK = len - left;
                                    }
                                    
                                    // 从右到左批量复制A中的元素（循环展开优化）
                                    copyEnd = gallopK - (gallopK & 3);
                                    for (copyI = 0; copyI < copyEnd; copyI += 4) {
                                        arr[d - copyI] = arr[pa - copyI];
                                        arr[d - copyI - 1] = arr[pa - copyI - 1];
                                        arr[d - copyI - 2] = arr[pa - copyI - 2];
                                        arr[d - copyI - 3] = arr[pa - copyI - 3];
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
                                    // B方galloping (内联 gallopLeft 逻辑用于temp数组)
                                    target = arr[pa];
                                    base = 0;
                                    len = pb + 1;
                                    gallopK = len;
                                    
                                    if (len == 0 || compare(tempArray[base], target) > 0) {
                                        gallopK = len;
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
                                        gallopK = len - left;
                                    }
                                    
                                    // 从右到左批量复制B中的元素（循环展开优化）
                                    copyEnd = gallopK - (gallopK & 3);
                                    for (copyI = 0; copyI < copyEnd; copyI += 4) {
                                        arr[d - copyI] = tempArray[pb - copyI];
                                        arr[d - copyI - 1] = tempArray[pb - copyI - 1];
                                        arr[d - copyI - 2] = tempArray[pb - copyI - 2];
                                        arr[d - copyI - 3] = tempArray[pb - copyI - 3];
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
                                    // 回到简单合并
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
                            
                            // 复制剩余的B元素（循环展开优化）
                            copyLen = pb + 1;
                            copyEnd = copyLen - (copyLen & 3);
                            for (copyI = 0; copyI < copyEnd; copyI += 4) {
                                arr[d - copyI] = tempArray[pb - copyI];
                                arr[d - copyI - 1] = tempArray[pb - copyI - 1];
                                arr[d - copyI - 2] = tempArray[pb - copyI - 2];
                                arr[d - copyI - 3] = tempArray[pb - copyI - 3];
                            }
                            for (; copyI < copyLen; copyI++) {
                                arr[d - copyI] = tempArray[pb - copyI];
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
            
            // 完整的gallopRight逻辑（重复实现以避免函数调用）
            gallopK = 0;
            target = arr[loB];
            base = loA;
            len = lenA;
            
            if (len == 0 || compare(arr[base], target) >= 0) {
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
            
            if (gallopK == lenA) {
                // 无需合并，直接继续
            } else {
                loA += gallopK;
                lenA -= gallopK;
                
                // 完整的gallopLeft逻辑（重复实现）
                gallopK = 0;  // 复用gallopK，前面的已用完
                target = arr[loA + lenA - 1];
                base = loB;
                len = lenB;
                
                if (len == 0 || compare(arr[base], target) > 0) {
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
                    gallopK = left;  // 复用gallopK，之前的已用完
                }
                
                if (gallopK == 0) {
                    // 无需合并，直接继续
                } else {
                    
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
                            for (i = 0; i < left; i++) {
                                arr[loA + i] = arr[loB + i];
                            }
                            arr[loA + left] = tmp;
                            for (i = left; i < lenB; i++) {
                                arr[loA + i + 1] = arr[loB + i];
                            }
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
                        }// 完整的合并逻辑（与上面_mergeCollapse中完全相同）
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
                            copyIdx = loA + copyI;
                            tempArray[copyI] = arr[copyIdx];
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
                                target = tempArray[pa];
                                base = pb;
                                len = eb - pb;
                                gallopK = 0;
                                
                                if (len == 0 || compare(arr[base], target) >= 0) {
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
                                
                                // 批量复制（循环展开优化）
                                copyEnd = gallopK - (gallopK & 3);
                                for (copyI = 0; copyI < copyEnd; copyI += 4) {
                                    arr[d + copyI] = arr[pb + copyI];
                                    arr[d + copyI + 1] = arr[pb + copyI + 1];
                                    arr[d + copyI + 2] = arr[pb + copyI + 2];
                                    arr[d + copyI + 3] = arr[pb + copyI + 3];
                                }
                                for (; copyI < gallopK; copyI++) {
                                    arr[d + copyI] = arr[pb + copyI];
                                }
                                d += gallopK;
                                pb += gallopK;
                                ca = 0;
                                minGallop -= (gallopK >= MIN_GALLOP ? 1 : -1);
                                if (minGallop < 1) minGallop = 1;
                            } else if (cb >= minGallop) {
                                target = arr[pb];
                                base = pa;
                                len = ea - pa;
                                gallopK = 0;
                                
                                if (len == 0 || compare(tempArray[base], target) > 0) {
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
                                
                                // 批量复制（循环展开优化）
                                copyEnd = gallopK - (gallopK & 3);
                                for (copyI = 0; copyI < copyEnd; copyI += 4) {
                                    copyIdx = pa + copyI;
                                    copyIdx = pa + copyI;
                                arr[d + copyI] = tempArray[copyIdx];
                                arr[d + copyI + 1] = tempArray[copyIdx + 1];
                                arr[d + copyI + 2] = tempArray[copyIdx + 2];
                                arr[d + copyI + 3] = tempArray[copyIdx + 3];
                                }
                                for (; copyI < gallopK; copyI++) {
                                    arr[d + copyI] = tempArray[pa + copyI];
                                }
                                d += gallopK;
                                pa += gallopK;
                                cb = 0;
                                minGallop -= (gallopK >= MIN_GALLOP ? 1 : -1);
                                if (minGallop < 1) minGallop = 1;
                            } else {
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
                            copyIdx = pa + copyI;
                            copyIdx = pa + copyI;
                            arr[d + copyI] = tempArray[copyIdx];
                            arr[d + copyI + 1] = tempArray[copyIdx + 1];
                            arr[d + copyI + 2] = tempArray[copyIdx + 2];
                            arr[d + copyI + 3] = tempArray[copyIdx + 3];
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
                            copyIdx = loB + copyI;
                            tempArray[copyI] = arr[copyIdx];
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
                                target = tempArray[pb];
                                base = ba0;
                                len = pa - ba0 + 1;
                                gallopK = len;
                                
                                if (len == 0 || compare(arr[base], target) > 0) {
                                    gallopK = len;
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
                                    gallopK = len - left;
                                }
                                
                                // 从右到左批量复制（循环展开优化）
                                copyEnd = gallopK - (gallopK & 3);
                                for (copyI = 0; copyI < copyEnd; copyI += 4) {
                                    arr[d - copyI] = arr[pa - copyI];
                                    arr[d - copyI - 1] = arr[pa - copyI - 1];
                                    arr[d - copyI - 2] = arr[pa - copyI - 2];
                                    arr[d - copyI - 3] = arr[pa - copyI - 3];
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
                                target = arr[pa];
                                base = 0;
                                len = pb + 1;
                                gallopK = len;
                                
                                if (len == 0 || compare(tempArray[base], target) > 0) {
                                    gallopK = len;
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
                                    gallopK = len - left;
                                }
                                
                                // 从右到左批量复制（循环展开优化）
                                copyEnd = gallopK - (gallopK & 3);
                                for (copyI = 0; copyI < copyEnd; copyI += 4) {
                                    arr[d - copyI] = tempArray[pb - copyI];
                                arr[d - copyI - 1] = tempArray[pb - copyI - 1];
                                arr[d - copyI - 2] = tempArray[pb - copyI - 2];
                                arr[d - copyI - 3] = tempArray[pb - copyI - 3];
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
                            arr[d - copyI] = tempArray[pb - copyI];
                            arr[d - copyI - 1] = tempArray[pb - copyI - 1];
                            arr[d - copyI - 2] = tempArray[pb - copyI - 2];
                            arr[d - copyI - 3] = tempArray[pb - copyI - 3];
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










