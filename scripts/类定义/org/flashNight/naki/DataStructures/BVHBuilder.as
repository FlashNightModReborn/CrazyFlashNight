import org.flashNight.sara.util.AABB;
import org.flashNight.naki.DataStructures.BVH;
import org.flashNight.naki.DataStructures.BVHNode;
import org.flashNight.naki.DataStructures.IBVHObject;

// ============================================================================
// BVHBuilder - 高性能边界体积层次结构(BVH)树构建器
// ----------------------------------------------------------------------------
// 
// 边界体积层次结构(Bounding Volume Hierarchy)是一种用于加速空间查询的数据结构，
// 广泛应用于碰撞检测、射线追踪、视锥剔除等计算机图形学和游戏开发领域。
//
// 本实现的核心优化特性：
// 1. 避免递归中重复创建匿名函数 - 使用静态比较函数，减少对象创建开销
// 2. 就地分区算法 - 使用索引范围操作，避免数组切片与不必要的内存复制
// 3. 内联AABB合并逻辑 - 直接操作边界值，减少方法调用开销
// 4. O(N)快速选择算法 - 使用Quickselect替代O(N log N)的完整排序，显著提升性能
//
// 时间复杂度：O(N log N) 平均情况，O(N²) 最坏情况（极少发生）
// 空间复杂度：O(log N) 递归栈空间 + O(N) 存储空间
//
// 作者：FlashNight Team
// 版本：3.0 (Quickselect优化版)
// ============================================================================

/**
 * BVHBuilder - 边界体积层次结构树构建器
 * 
 * 这个类提供了高效构建BVH树的静态方法。BVH树是一种二叉树结构，
 * 其中每个节点都包含一个轴对齐包围盒(AABB)，叶子节点存储实际的几何对象。
 * 
 * 使用场景：
 * - 3D场景中的碰撞检测优化
 * - 射线追踪加速结构
 * - 视锥剔除和空间查询
 * - 大量物体的空间分割管理
 * 
 * 性能特点：
 * - 构建时间：平均 O(N log N)，最坏 O(N²)
 * - 查询时间：平均 O(log N)
 * - 内存使用：约 2N 个节点（N为输入对象数量）
 */
class org.flashNight.naki.DataStructures.BVHBuilder {
    
    /** 
     * 叶子节点允许存储的最大对象数量
     * 
     * 这个值影响树的深度和查询性能：
     * - 较小的值：树更深，构建时间稍长，但查询可能更快
     * - 较大的值：树更浅，构建更快，但叶子节点查询成本可能更高
     * 
     * 推荐值：4-16，根据具体应用场景调整
     * 当前默认值8是经过测试的平衡选择
     */
    public static var MAX_OBJECTS_IN_LEAF:Number = 8;

    /**
     * 静态比较函数：按X轴中心坐标排序
     * 
     * 用于在构建BVH树时对对象进行空间排序。通过比较对象包围盒的X轴中心点，
     * 确定对象在X轴上的相对位置，从而实现有效的空间分割。
     * 
     * 算法细节：
     * - 计算公式：centerX = (left + right) / 2，此处为了避免浮点除法，直接比较 (left + right)
     * - 返回值：负数表示a在b左侧，正数表示a在b右侧，0表示中心点相同
     * 
     * @param a 第一个要比较的IBVHObject对象
     * @param b 第二个要比较的IBVHObject对象
     * @return 比较结果：a.centerX - b.centerX，用于排序算法
     */
    private static function compareByXAxis(a:IBVHObject, b:IBVHObject):Number {
        var aBox:AABB = a.getAABB();
        var bBox:AABB = b.getAABB();
        var aCenter:Number = aBox.left + aBox.right;
        var bCenter:Number = bBox.left + bBox.right;
        return aCenter - bCenter;
    }

    /**
     * 静态比较函数：按Y轴中心坐标排序
     * 
     * 用于在构建BVH树时对对象进行Y轴方向的空间排序。与X轴比较函数类似，
     * 但比较的是Y轴中心点，用于实现不同深度层级的轴向分割。
     * 
     * 算法细节：
     * - 计算公式：centerY = (top + bottom) / 2，此处直接比较 (top + bottom)
     * - 分割策略：通常与X轴分割交替使用，实现更均匀的空间划分
     * 
     * @param a 第一个要比较的IBVHObject对象
     * @param b 第二个要比较的IBVHObject对象
     * @return 比较结果：a.centerY - b.centerY，用于排序算法
     */
    private static function compareByYAxis(a:IBVHObject, b:IBVHObject):Number {
        var aBox:AABB = a.getAABB();
        var bBox:AABB = b.getAABB();
        var aCenter:Number = aBox.top + aBox.bottom;
        var bCenter:Number = bBox.top + bBox.bottom;
        return aCenter - bCenter;
    }

    /**
     * 通用BVH树构建方法
     * 
     * 这是最常用的构建方法，适用于任意顺序的对象数组。方法会自动处理对象的
     * 空间排序和树结构构建，无需预处理输入数据。
     * 
     * 使用场景：
     * - 动态场景中的实时BVH构建
     * - 对象顺序未知或随机分布的情况
     * - 需要频繁重建BVH的应用
     * 
     * 性能特点：
     * - 时间复杂度：O(N log N) 平均，O(N²) 最坏情况
     * - 空间复杂度：O(N) + O(log N) 递归栈
     * - 内存安全：会创建输入数组的副本，不修改原始数据
     * 
     * @param objects 实现了IBVHObject接口的对象数组，可以是任意顺序
     *                每个对象必须能够通过getAABB()方法返回有效的轴对齐包围盒
     * @return 构建完成的BVH实例，如果输入为空则返回包含null根节点的BVH
     * 
     * 注意事项：
     * - 输入对象的AABB必须是有效的（left <= right, top <= bottom）
     * - 建议在构建前确保对象的AABB是紧密包围的，以获得最佳性能
     * - 对于大量对象（>10000），建议考虑分批构建或使用专门的大数据优化版本
     */
    public static function build(objects:Array):BVH {
        // 输入验证：检查空输入情况
        if (objects == null || objects.length == 0) {
            return new BVH(null);
        }
        
        // 创建工作数组副本，避免修改原始输入数据
        // 这是一个防御性编程实践，确保方法调用不会产生副作用
        var workingArray:Array = objects.concat();
        
        // 开始递归构建过程，从根节点开始，深度为0
        var rootNode:BVHNode = buildRecursiveOptimized(workingArray, 0, workingArray.length, 0);
        
        return new BVH(rootNode);
    }

    /**
     * 高性能预排序BVH树构建方法
     * 
     * 这是一个专门的优化方法，适用于已经按X轴中心坐标排序的对象数组。
     * 通过跳过初始排序步骤，可以显著提升构建性能，特别适合于需要频繁
     * 重建BVH或处理大量对象的高性能应用场景。
     * 
     * 适用场景：
     * - 对象已经按空间位置预排序的情况
     * - 需要最大化构建性能的实时应用
     * - 批量处理大量几何对象
     * - 从外部数据源导入已排序的几何数据
     * 
     * 性能优势：
     * - 跳过O(N log N)的初始排序，直接进入O(N)的分割阶段
     * - 减少不必要的比较操作
     * - 更好的缓存局部性，因为相邻对象在空间上也相邻
     * 
     * 重要前提条件：
     * 输入数组必须严格按照对象AABB的X轴中心坐标升序排列，即：
     * 对于任意 i < j，都有 objects[i].getAABB().centerX <= objects[j].getAABB().centerX
     * 
     * @param sortedObjects 已按X轴中心坐标严格升序排列的对象数组
     *                      违反排序约定可能导致构建的BVH树质量下降或查询错误
     * @return 构建完成的BVH实例，利用预排序特性获得最佳性能
     * 
     * 使用示例：
     * ```actionscript
     * // 错误用法 - 未排序的数组
     * var randomObjects:Array = [obj3, obj1, obj4, obj2];
     * var bvh1:BVH = BVHBuilder.buildFromSortedX(randomObjects); // 可能产生质量差的BVH
     * 
     * // 正确用法 - 预排序的数组
     * var sortedObjects:Array = [obj1, obj2, obj3, obj4]; // 按X轴中心排序
     * var bvh2:BVH = BVHBuilder.buildFromSortedX(sortedObjects); // 高质量高性能
     * ```
     */
    public static function buildFromSortedX(sortedObjects:Array):BVH {
        // 输入验证
        if (sortedObjects == null || sortedObjects.length == 0) {
            return new BVH(null);
        }
        
        var numObjects:Number = sortedObjects.length;
        
        // 计算根节点的包围盒 - 包含所有输入对象
        var rootAABB:AABB = calculateAABBForRange(sortedObjects, 0, numObjects);
        var rootNode:BVHNode = new BVHNode(rootAABB);

        // 叶子节点优化：如果对象数量足够少，直接创建叶子节点
        // 这避免了不必要的进一步分割，提升了构建效率和查询性能
        if (numObjects <= MAX_OBJECTS_IN_LEAF) {
            rootNode.objects = sortedObjects;
            return new BVH(rootNode);
        }
        
        // 对于大量对象，计算中点进行二分分割
        // 由于数组已排序，简单的中点分割就能获得良好的空间平衡
        var mid:Number = Math.floor(numObjects / 2);

        // 递归构建左右子树，深度从1开始（根节点深度为0）
        // 左子树包含前半部分对象（空间上偏左的对象）
        // 右子树包含后半部分对象（空间上偏右的对象）
        rootNode.left  = buildRecursiveOptimized(sortedObjects, 0, mid, 1);
        rootNode.right = buildRecursiveOptimized(sortedObjects, mid, numObjects, 1);

        return new BVH(rootNode);
    }

    /**
     * 核心递归构建函数 - 高性能优化版本
     * 
     * 这是BVH构建的核心算法实现，采用自顶向下的递归分治策略。
     * 通过交替使用X轴和Y轴分割，实现均匀的空间划分，构建平衡的二叉树结构。
     * 
     * 算法流程：
     * 1. 计算当前范围内所有对象的总包围盒
     * 2. 创建当前层级的BVH节点
     * 3. 检查终止条件（对象数量是否足够少）
     * 4. 选择分割轴（基于当前深度，X轴和Y轴交替）
     * 5. 使用Quickselect算法找到中位数并分区
     * 6. 递归构建左右子树
     * 
     * 核心优化特性：
     * - 使用O(N)的Quickselect替代O(N log N)的完整排序
     * - 就地分区操作，避免数组复制开销
     * - 轴向交替分割，确保空间划分的均匀性
     * - 智能终止条件，平衡树深度和叶子节点大小
     * 
     * 时间复杂度分析：
     * - 平均情况：O(N log N) - Quickselect平均O(N)，递归log N层
     * - 最坏情况：O(N²) - 当pivot总是选择极值时，但概率极低
     * - 实际表现：通常接近平均情况，远优于完整排序方案
     * 
     * @param objects 当前正在处理的对象数组（整个构建过程中保持不变）
     * @param start   当前处理范围的起始索引（包含），用于限定处理区间
     * @param end     当前处理范围的结束索引（不包含），形成[start, end)区间
     * @param depth   当前递归深度，用于决定分割轴向（偶数深度用X轴，奇数用Y轴）
     * @return 构建完成的BVHNode，可能是内部节点（有子节点）或叶子节点（有对象列表）
     * 
     * 递归终止条件：
     * - 当前区间对象数量 <= MAX_OBJECTS_IN_LEAF
     * - 此时创建叶子节点，直接存储对象列表
     * 
     * 分割策略：
     * - 偶数深度（0, 2, 4...）：使用X轴分割，适合水平方向的空间划分
     * - 奇数深度（1, 3, 5...）：使用Y轴分割，适合垂直方向的空间划分
     * - 交替策略确保了空间划分的均匀性和树结构的平衡性
     */
    private static function buildRecursiveOptimized(objects:Array, start:Number, end:Number, depth:Number):BVHNode {
        var numObjects:Number = end - start;
        
        // 第一步：计算当前范围内所有对象的联合包围盒
        // 这个包围盒将成为当前BVH节点的空间边界
        var nodeAABB:AABB = calculateAABBForRange(objects, start, end);
        
        // 第二步：创建当前层级的BVH节点
        var node:BVHNode = new BVHNode(nodeAABB);

        // 第三步：检查递归终止条件
        // 如果当前区间的对象数量足够少，创建叶子节点
        if (numObjects <= MAX_OBJECTS_IN_LEAF) {
            // 创建对象子数组并赋值给叶子节点
            // slice方法创建[start, end)范围的浅拷贝
            node.objects = objects.slice(start, end);
            return node;
        }

        // 第四步：选择分割轴和对应的比较函数
        // 使用深度的奇偶性来交替选择分割轴向
        // 这种策略有助于创建更均匀的空间划分
        var axis:Number = depth % 2; // 0表示X轴，1表示Y轴
        var compareFunc:Function = (axis == 0) ? compareByXAxis : compareByYAxis;
        
        // 第五步：计算中位数位置并进行快速选择分区
        // 中位数分割策略确保左右子树的对象数量基本相等
        var mid:Number = start + Math.floor(numObjects / 2);
        
        // 使用Quickselect算法进行O(N)时间的分区操作
        // 分区后，所有小于等于中位数的元素都在mid左侧
        // 所有大于中位数的元素都在mid右侧
        select(objects, start, end, mid, compareFunc);

        // 第六步：递归构建左右子树
        // 左子树处理[start, mid)范围的对象
        // 右子树处理[mid, end)范围的对象
        // 深度递增1，确保下一层使用不同的分割轴向
        node.left  = buildRecursiveOptimized(objects, start, mid, depth + 1);
        node.right = buildRecursiveOptimized(objects, mid, end, depth + 1);

        return node;
    }

    /**
     * 计算指定范围内对象的联合包围盒 - 内联优化版本
     * 
     * 这个函数计算数组指定范围内所有对象的最小外接轴对齐包围盒(AABB)。
     * 结果包围盒是能够完全包含所有输入对象的最小矩形区域。
     * 
     * 算法实现：
     * 1. 初始化：使用第一个对象的AABB作为起始边界
     * 2. 迭代合并：遍历剩余对象，逐个扩展边界
     * 3. 边界更新：对每个维度（left/right/top/bottom）取最值
     * 
     * 内联优化特性：
     * - 避免了传统mergeWith()方法的函数调用开销
     * - 直接操作边界值，减少临时对象创建
     * - 本地变量缓存AABB属性，提升访问效率
     * 
     * 时间复杂度：O(N)，其中N是范围内的对象数量
     * 空间复杂度：O(1)，只使用常量额外空间
     * 
     * @param objects 包含IBVHObject对象的数组
     * @param start   计算范围的起始索引（包含）
     * @param end     计算范围的结束索引（不包含）
     * @return 新创建的AABB对象，表示所有输入对象的联合包围盒
     * 
     * 前提条件：
     * - start < end（确保范围有效）
     * - objects[start] 到 objects[end-1] 都是有效的IBVHObject实例
     * - 每个对象的getAABB()方法返回有效的AABB
     * 
     * 使用注意：
     * - 返回的AABB是新创建的对象，不会影响输入对象的AABB
     * - 如果范围内只有一个对象，返回该对象AABB的副本
     * - 边界计算采用包含式策略，确保所有对象完全在包围盒内
     */
    private static function calculateAABBForRange(objects:Array, start:Number, end:Number):AABB {
        // 使用第一个对象的AABB作为初始边界
        var firstAABB:AABB = objects[start].getAABB();
        var left:Number = firstAABB.left;
        var right:Number = firstAABB.right;
        var top:Number = firstAABB.top;
        var bottom:Number = firstAABB.bottom;
        
        // 遍历剩余对象，逐个扩展包围盒边界
        // 内联的边界合并操作，避免方法调用开销
        for (var i:Number = start + 1; i < end; i++) {
            var currentAABB:AABB = objects[i].getAABB();
            
            // 对每个维度进行边界扩展
            // left取最小值（最左边界）
            if (currentAABB.left < left) left = currentAABB.left;
            // right取最大值（最右边界）
            if (currentAABB.right > right) right = currentAABB.right;
            // top取最小值（最上边界，假设Y轴向下为正）
            if (currentAABB.top < top) top = currentAABB.top;
            // bottom取最大值（最下边界）
            if (currentAABB.bottom > bottom) bottom = currentAABB.bottom;
        }
        
        // 创建并返回合并后的包围盒
        return new AABB(left, right, top, bottom);
    }

    // ========================================================================
    // O(N) 快速选择算法实现
    // ========================================================================

    /**
     * Quickselect快速选择算法 - O(N)平均时间复杂度的第k小元素查找
     * 
     * 快速选择算法是快速排序的变种，专门用于寻找数组中第k小的元素。
     * 与完整排序不同，它只需要保证第k个位置的元素正确，并将数组分区为
     * 小于、等于、大于第k个元素的三个部分。
     * 
     * 算法优势：
     * - 时间复杂度：平均O(N)，最坏O(N²)，远优于完整排序的O(N log N)
     * - 空间复杂度：O(1)，原地操作不需要额外数组空间
     * - 分区特性：算法完成后，k位置左侧都是较小元素，右侧都是较大元素
     * 
     * 在BVH构建中的作用：
     * - 寻找中位数元素，实现均匀的空间分割
     * - 将对象分区为左右两部分，分别用于构建左右子树
     * - 避免完整排序的开销，因为我们只需要分区，不需要完全有序
     * 
     * 算法流程：
     * 1. 选择分区边界（low = start, high = end-1）
     * 2. 循环执行分区操作，直到找到第k个元素
     * 3. 根据分区结果调整搜索范围
     * 4. 当pivotIndex == k时，分区完成
     * 
     * 性能优化：
     * - 三数取中法选择pivot，避免最坏情况
     * - Lomuto分区方案，实现简单且高效
     * - 尾递归优化为迭代，避免栈溢出
     * 
     * @param objects     要进行分区的数组，会被原地修改
     * @param start       分区范围的起始索引（包含）
     * @param end         分区范围的结束索引（不包含）
     * @param k           目标第k小元素的索引位置（通常是中位数位置）
     * @param compareFunc 比较函数，用于确定元素大小关系
     * 
     * 分区后效果：
     * - objects[0...k-1]: 所有元素都 <= objects[k]
     * - objects[k]: 第k小的元素（中位数）
     * - objects[k+1...end-1]: 所有元素都 >= objects[k]
     * 
     * 注意事项：
     * - 算法会原地修改输入数组的元素顺序
     * - k必须在[start, end)范围内，否则行为未定义
     * - compareFunc必须提供一致的比较结果
     */
    private static function select(objects:Array, start:Number, end:Number, k:Number, compareFunc:Function):Void {
        // 转换为包含式边界，便于分区算法处理
        var low:Number = start;
        var high:Number = end - 1; // Quickselect在包含式边界上操作
        
        // 迭代式快速选择主循环
        // 每次迭代都会缩小搜索范围，直到找到目标位置
        while (high > low) {
            // 执行分区操作，返回pivot元素的最终位置
            var pivotIndex:Number = partition(objects, low, high, compareFunc);
            
            if (pivotIndex == k) {
                // 找到目标位置，分区完成
                return;
            } else if (pivotIndex > k) {
                // 目标在左半部分，缩小搜索范围到左边
                high = pivotIndex - 1;
            } else {
                // 目标在右半部分，缩小搜索范围到右边
                low = pivotIndex + 1;
            }
        }
    }

    /**
     * 快速排序/快速选择的分区函数 - Lomuto分区方案实现
     * 
     * 分区是快速排序族算法的核心操作，它选择一个pivot元素，
     * 将数组重新排列为：[小于pivot的元素][pivot][大于等于pivot的元素]
     * 
     * Lomuto分区方案特点：
     * - 实现简单，易于理解和维护
     * - 稳定性好，对重复元素处理得当
     * - 与三数取中pivot选择策略配合良好
     * 
     * 三数取中优化：
     * 为了避免在已排序或逆序数据上的最坏O(N²)性能，我们使用三数取中法
     * 选择pivot。这种方法从low、mid、high三个位置选择中位数作为pivot，
     * 大大提高了在实际数据上的性能表现。
     * 
     * 算法步骤：
     * 1. 三数取中选择最优pivot
     * 2. 将pivot移到数组末尾
     * 3. 从左到右扫描，将小于等于pivot的元素移到左侧
     * 4. 将pivot放到正确位置
     * 5. 返回pivot的最终位置
     * 
     * 时间复杂度：O(N)，需要遍历整个区间一次
     * 空间复杂度：O(1)，只使用常量额外空间
     * 
     * @param arr         要分区的数组
     * @param low         分区范围起始索引（包含）
     * @param high        分区范围结束索引（包含）
     * @param compareFunc 比较函数，定义元素大小关系
     * @return pivot元素分区后的最终位置索引
     * 
     * 分区后保证：
     * - arr[low...返回值-1]: 所有元素 <= pivot
     * - arr[返回值]: pivot元素
     * - arr[返回值+1...high]: 所有元素 > pivot
     */
    private static function partition(arr:Array, low:Number, high:Number, compareFunc:Function):Number {
        // 三数取中法选择pivot，提升在现实数据上的性能
        // 这个优化对于避免最坏情况O(N²)性能至关重要
        var mid:Number = low + Math.floor((high - low) / 2);
        
        // 对low、mid、high三个位置的元素进行排序
        // 确保arr[low] <= arr[mid] <= arr[high]
        if (compareFunc(arr[mid], arr[low]) < 0) swap(arr, mid, low);
        if (compareFunc(arr[high], arr[low]) < 0) swap(arr, high, low);
        if (compareFunc(arr[mid], arr[high]) < 0) swap(arr, mid, high);
        
        // 选择high位置的元素作为pivot（经过三数取中，这是一个好的选择）
        var pivot:IBVHObject = arr[high];
        
        // i指向小于等于pivot元素区域的末尾
        var i:Number = low - 1;

        // Lomuto分区的核心循环
        // 扫描[low, high-1]范围，将小于等于pivot的元素移到左侧
        for (var j:Number = low; j < high; j++) {
            if (compareFunc(arr[j], pivot) <= 0) {
                i++;
                swap(arr, i, j);
            }
        }
        
        // 将pivot元素放到正确位置（小于等于区域的右边）
        swap(arr, i + 1, high);
        
        // 返回pivot的最终位置
        return i + 1;
    }

    /**
     * 数组元素交换工具函数
     * 
     * 高效地交换数组中两个位置的元素。这是分区算法的基础操作，
     * 通过元素交换来重新排列数组，实现分区的目标。
     * 
     * 实现采用经典的三变量交换法：
     * 1. 保存第一个元素到临时变量
     * 2. 将第二个元素移到第一个位置
     * 3. 将临时变量的值放到第二个位置
     * 
     * 时间复杂度：O(1)
     * 空间复杂度：O(1)
     * 
     * @param arr 要操作的数组
     * @param i   第一个元素的索引位置
     * @param j   第二个元素的索引位置
     * 
     * 注意事项：
     * - 如果i == j，操作仍然安全，但会有不必要的开销
     * - 调用者需要确保i和j都是有效的数组索引
     * - 这个函数会直接修改原数组，不会创建副本
     */
    private static function swap(arr:Array, i:Number, j:Number):Void {
        var temp:IBVHObject = arr[i];
        arr[i] = arr[j];
        arr[j] = temp;
    }
}