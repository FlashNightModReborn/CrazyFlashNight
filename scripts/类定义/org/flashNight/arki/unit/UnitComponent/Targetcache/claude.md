目标：为SortedUnitCache添加带过滤器的最近单位查询功能
1. 核心目标
在 org.flashNight.arki.unit.UnitComponent.Targetcache.SortedUnitCache 类中，实现一个新的方法系列 findNearestWithFilter。此方法应能高效地查找满足自定义过滤规则的、距离目标单位最近的单位。
该实现必须遵循以下设计原则：
性能优先：尽可能复用现有 findNearest 的 O(1) 性能优势。
延迟计算：仅在必要时才启动成本更高的邻域扩张搜索。
健壮性：必须包含性能安全阀（searchLimit）以防止在极端情况下造成性能问题。
2. SortedUnitCache.as 实现指南
2.1. 新增公共方法：findNearestWithFilter
在 最近单位查询方法 (// ===== 最近单位查询方法 =====) 区域后，添加以下新的公共方法。
code
Actionscript
// ========================================================================
    // 【新增】带过滤器的最近单位查询方法
    // ========================================================================

    /**
     * 查找满足过滤条件的最近单位（邻域扩张算法）
     * 
     * 该方法首先使用高效的 findNearest() 查找候选者。如果候选者满足过滤条件，则立即返回。
     * 否则，它会从目标单位在有序数组中的位置开始，向两侧交替搜索，直到找到满足条件的单位
     * 或达到搜索限制。
     *
     * @param {Object} target - 目标单位，查询的中心点。
     * @param {Function} filter - 过滤函数。接收一个单位对象作为参数，必须返回 {Boolean}。
     *                          - `true` 表示单位满足条件。
     *                          - `false` 表示单位不满足条件。
     * @param {Number} searchLimit - (可选) 最大邻域搜索数量。为了保证性能，从起点向外查找的
     *                             单位总数上限。推荐值为 30-50。默认为 30。
     * @return {Object} 满足条件的最近单位对象；如果找不到或达到搜索限制，则返回 null。
     */
    public function findNearestWithFilter(target:Object, filter:Function, searchLimit:Number):Object {
        // --- 参数验证 ---
        if (searchLimit == undefined) searchLimit = 30;
        if (this.data.length == 0 || filter == null || searchLimit <= 0) {
            return null;
        }

        // --- 阶段1: 快速路径检查 ---
        // 首先，使用最高效的 findNearest() 找到第一个候选者。
        var nearestCandidate:Object = findNearest(target);
        
        // 如果候选者存在且满足过滤条件，立即返回。这是最高性能的场景。
        if (nearestCandidate && filter(nearestCandidate) == true) {
            return nearestCandidate;
        }

        // --- 阶段2: 邻域扩张搜索 ---
        // 快速路径失败，启动邻域扩张。

        // 1. 找到搜索起点
        var targetX:Number = target.aabbCollider.left;
        var startIndex:Number = this.nameIndex[target._name];
        
        // 如果目标单位本身不在缓存列表中，通过二分查找找到其理论上的插入位置。
        if (startIndex == undefined) {
            startIndex = _findInsertIndex(targetX);
            // 对于不在列表中的目标，它自身不能是结果，所以 searchLimit 可以减1。
            if (searchLimit > 0) searchLimit--; 
        }

        // 2. 初始化左右指针
        var leftPtr:Number = startIndex - 1;
        var rightPtr:Number = startIndex + 1;
        var checkedCount:Number = 0; // 已检查的单位数量

        // 3. 开始循环扩张，直到超出数组边界或达到搜索限制
        while (checkedCount < searchLimit && (leftPtr >= 0 || rightPtr < this.data.length)) {
            
            var leftUnit:Object = (leftPtr >= 0) ? this.data[leftPtr] : null;
            var rightUnit:Object = (rightPtr < this.data.length) ? this.data[rightPtr] : null;

            // 确定左右单位与目标的距离
            var distLeft:Number = leftUnit ? (targetX - this.leftValues[leftPtr]) : Number.MAX_VALUE;
            var distRight:Number = rightUnit ? (this.leftValues[rightPtr] - targetX) : Number.MAX_VALUE;

            var unitToCheck:Object;

            // 4. 优先检查距离更近的单位
            if (distLeft <= distRight) {
                unitToCheck = leftUnit;
                leftPtr--;
            } else {
                unitToCheck = rightUnit;
                rightPtr++;
            }
            
            checkedCount++;

            // 5. 对选中的单位应用过滤器
            if (unitToCheck && filter(unitToCheck) == true) {
                return unitToCheck; // 找到满足条件的最近单位，立即返回
            }
        }

        // 6. 搜索结束，未找到满足条件的单位
        return null;
    }
2.2. 新增私有辅助方法：_findInsertIndex
这是一个用于支持 findNearestWithFilter 的辅助方法。当目标单位不在缓存列表中时，它能快速定位其应该插入的位置。
code
Actionscript
/**
     * 【私有】使用二分查找确定一个值在 leftValues 数组中的理论插入点。
     * @param {Number} value - 要查找位置的值。
     * @return {Number} 该值应插入的索引位置。
     * @private
     */
    private function _findInsertIndex(value:Number):Number {
        var len:Number = this.data.length;
        if (len == 0) return 0;

        var l:Number = 0;
        var r:Number = len - 1;

        if (value <= this.leftValues[l]) return l;
        if (value > this.leftValues[r]) return len;

        while (l <= r) {
            var m:Number = (l + r) >> 1;
            var midVal:Number = this.leftValues[m];

            if (midVal < value) {
                l = m + 1;
            } else if (midVal > value) {
                r = m - 1;
            } else {
                return m; // 找到完全相等的值
            }
        }
        return l; // 返回应该插入的位置
    }
3. SortedUnitCacheTest.as 测试策略指南
为了达到100%的测试覆盖率，你需要创建一个新的测试部分，并设计一系列针对性的测试用例。
3.1. 在测试套件中添加新的测试部分
在 runAll 方法中，添加对新测试函数的调用：
code
Actionscript
// 在 org.flashNight.arki.unit.UnitComponent.Targetcache.SortedUnitCacheTest.runAll() 中

// ...
runBoundaryConditionTests();

// 【新增】执行带过滤器的查询测试
runFilteredQueryTests(); // <--- 添加此行

runPerformanceBenchmarks();
// ...
创建新的测试函数 runFilteredQueryTests：
code
Actionscript
// ========================================================================
    // 【新增】带过滤器的查询测试
    // ========================================================================
    
    private static function runFilteredQueryTests():Void {
        trace("\n🧪 执行带过滤器的查询测试...");
        
        // 定义可复用的过滤器
        var hpFilter_under50 = function(u:Object):Boolean { return (u.hp / u.maxhp) < 0.5; };
        var nameFilter_contains1 = function(u:Object):Boolean { return u._name.indexOf("1") != -1; };
        var alwaysFalseFilter = function(u:Object):Boolean { return false; };

        testFindNearestWithFilter_fastPath(hpFilter_under50);
        testFindNearestWithFilter_expansionRight(hpFilter_under50);
        testFindNearestWithFilter_expansionLeft(hpFilter_under50);
        testFindNearestWithFilter_notFound(alwaysFalseFilter);
        testFindNearestWithFilter_searchLimit(nameFilter_contains1);
        testFindNearestWithFilter_targetNotInCache(hpFilter_under50);
        testFindNearestWithFilter_edgeCases();
    }
3.2. 详细测试用例设计
以下是每个测试用例的具体设计，请将它们作为 runFilteredQueryTests 的一部分来实现。
测试用例 1: testFindNearestWithFilter_fastPath
目的: 验证“快速路径”——即 findNearest 的第一个结果就满足过滤条件。
设置:
选择一个目标单位，如 testUnits[25]。
找到它的最近单位（testUnits[24] 或 testUnits[26]）。
修改这个最近单位的血量，使其满足过滤器条件（例如 hp = 40)。
执行: testCache.findNearestWithFilter(target, hpFilter_under50, 50)
断言:
assertNotNull() 确保返回了对象。
assertEquals() 确保返回的是被修改过血量的那个单位。
测试用例 2: testFindNearestWithFilter_expansionRight
目的: 验证当最近单位不满足条件时，向右（索引增大）扩张搜索能找到正确目标。
设置:
选择目标 testUnits[25]。
确保其最近单位 testUnits[24] 和 testUnits[26] 不满足过滤器（例如，hp = 90）。
修改右侧的下一个单位 testUnits[27]，使其满足过滤器（hp = 40）。
执行: testCache.findNearestWithFilter(target, hpFilter_under50, 50)
断言:
assertNotNull() 确保返回了对象。
assertEquals() 确保返回的是 testUnits[27]。
测试用例 3: testFindNearestWithFilter_expansionLeft
目的: 验证向左（索引减小）扩张搜索能找到正确目标。
设置:
选择目标 testUnits[25]。
确保其最近单位 testUnits[24] 和 testUnits[26] 不满足过滤器。
修改左侧的下一个单位 testUnits[23]，使其满足过滤器（hp = 40）。
执行: testCache.findNearestWithFilter(target, hpFilter_under50, 50)
断言:
assertNotNull() 确保返回了对象。
assertEquals() 确保返回的是 testUnits[23]。
测试用例 4: testFindNearestWithFilter_notFound
目的: 验证当没有单位满足过滤条件时，方法返回 null。
设置: 使用一个永远返回 false 的过滤器。
执行: testCache.findNearestWithFilter(target, alwaysFalseFilter, 50)
断言: assertNull() 确保结果为 null。
测试用例 5: testFindNearestWithFilter_searchLimit
目的: 验证 searchLimit 参数能有效中止搜索。
设置:
选择目标 testUnits[25]。
确保在 searchLimit 范围内的单位都不满足过滤器 nameFilter_contains1。
在 searchLimit 范围外的某个单位（如 testUnits[1]）满足该过滤器。
执行: testCache.findNearestWithFilter(target, nameFilter_contains1, 5) (使用一个小的 searchLimit)。
断言: assertNull() 确保结果为 null，因为满足条件的单位在搜索范围之外。
再次执行: testCache.findNearestWithFilter(target, nameFilter_contains1, 40) (使用一个大的 searchLimit)。
断言: assertNotNull() 确保这次能找到单位。
测试用例 6: testFindNearestWithFilter_targetNotInCache
目的: 验证当目标单位本身不在缓存中时，算法依然能正常工作（测试 _findInsertIndex 的逻辑）。
设置:
创建一个不在缓存中的外部单位 externalUnit，其 left 值位于 testUnits[10] 和 testUnits[11] 之间。
修改 testUnits[12] 使其满足过滤器（hp = 40）。
执行: testCache.findNearestWithFilter(externalUnit, hpFilter_under50, 50)。
断言:
assertNotNull() 确保返回了对象。
assertEquals() 确保返回的是 testUnits[12]。
测试用例 7: testFindNearestWithFilter_edgeCases
目的: 测试各种边界情况。
设置与执行:
空缓存: 创建一个空 SortedUnitCache，调用方法。断言返回 null。
单元素缓存: 创建只有一个单位的缓存，调用方法。断言返回 null（因为没有其他单位）。
目标是首元素: target = testUnits[0]。修改 testUnits[1] 满足条件。断言能找到 testUnits[1]。
目标是末尾元素: target = testUnits[49]。修改 testUnits[48] 满足条件。断言能找到 testUnits[48]。
filter 为 null: 调用 testCache.findNearestWithFilter(target, null, 10)。断言返回 null。
searchLimit 为 0: 调用 testCache.findNearestWithFilter(target, filter, 0)。断言返回 null（或者 findNearest 的结果，取决于实现，但我们的实现会返回 null）。