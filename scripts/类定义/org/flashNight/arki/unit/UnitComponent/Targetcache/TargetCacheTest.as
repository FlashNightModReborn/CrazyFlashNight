/* 文件路径: org/flashNight/arki/unit/UnitComponent/targetcache/TargetCacheTest.as */
import org.flashNight.arki.unit.UnitComponent.Targetcache.*;

class org.flashNight.arki.unit.UnitComponent.Targetcache.TargetCacheTest {
  
    // 模拟游戏世界对象，存储所有单位
    private var gameWorld:Object;
  
    // 单位计数器，用于生成唯一的单位名称
    private var unitCounter:Number;
  
    // 控制单位数量的范围
    private var minUnits:Number;
    private var maxUnits:Number;
  
    // 测试参数：更新迭代次数与预热迭代次数
    private var updateIterations:Number;
    private var warmupIterations:Number;
  
    // 新增：预热循环次数，用于重复预热和准确率校验
    private var warmupCycles:Number;

    // 新增边界测试结果跟踪
    private var boundaryTestPassed:Boolean = true;
    private var boundaryTestCases:Number = 0;
    private var boundaryTestFailures:Number = 0;
    private var sampleUnit:Object;
    private var expectedOrder:Array;
    private var sampleU2:Object;  // 用于存储相同right值排序测试中创建的第二个单位


  
    /**
     * 构造函数，传入正式测试和预热的迭代次数，以及预热循环次数
     */
    public function TargetCacheTest(updateIterations:Number, warmupIterations:Number, warmupCycles:Number) {
        this.updateIterations = updateIterations;
        this.warmupIterations = warmupIterations;
        this.warmupCycles = warmupCycles;
        this.gameWorld = {};
        this.unitCounter = 0;
        this.minUnits = 10;
        this.maxUnits = 30;
      
        // 初始化全局对象 _root 模拟（如果尚未存在）
        if (!_root) {
            _global = {};
        }
        if (!_root.帧计时器) {
            _root.帧计时器 = { 当前帧数: 0 };
        }
        if (!_root.gameworld) {
            _root.gameworld = this.gameWorld;
        }
      
        // 初始化初始单位（例如 20 个）
        initializeGameWorld();
    }
  
    /**
     * 初始化游戏世界，构造初始假数据单位
     */
    private function initializeGameWorld():Void {

        _resetCacheSystem();
        var initialCount:Number = 20;
        for (var i:Number = 0; i < initialCount; i++) {
            addUnit();
        }
    }
  
    /**
     * 创建一个假单位，包括基本属性和碰撞箱
     */
    private function createFakeUnit():Object {
        var id:Number = this.unitCounter++;
        var unit:Object = {};
        unit._name = "unit" + id;
        unit.hp = 100; // 初始生命值
        unit.是否为敌人 = (Math.random() > 0.5); // 随机敌我状态
        // 随机初始位置
        unit.x = Math.random() * 500;
        unit.y = Math.random() * 500;
        unit.width = 50; // 假定单位宽度
      
        // 模拟碰撞箱对象，包含右边界属性和更新方法
        unit.aabbCollider = {
            right: unit.x + unit.width,
            updateFromUnitArea: function(u:Object):Void {
                // 根据单位当前 x 位置更新右边界
                this.right = u.x + u.width;
            }
        };

        unit.toString = function():String {
            return unit._name + " " + unit.是否为敌人 + " " + unit.aabbCollider.right;
        };
        return unit;
    }
  
    /**
     * 向游戏世界中添加一个单位（当单位数未达到最大值时）
     */
    private function addUnit():Void {
        if (getUnitCount() >= maxUnits) return;
        var unit:Object = createFakeUnit();
        this.gameWorld[unit._name] = unit;
        TargetCacheUpdater.addUnit(unit); // 新增行
    }
  
    /**
     * 从游戏世界中随机移除一个单位（当单位数大于最小值时）
     */
    private function removeUnit():Void {
        if (getUnitCount() <= minUnits) return;
        var keys:Array = [];
        for (var key:String in this.gameWorld) {
            keys.push(key);
        }
        var randomIndex:Number = Math.floor(Math.random() * keys.length);
        var unitKey:String = keys[randomIndex];
        TargetCacheUpdater.removeUnit(this.gameWorld[unitKey]); // 新增行
        delete this.gameWorld[unitKey];
    }
  
    /**
     * 获取当前游戏世界中单位的数量
     */
    private function getUnitCount():Number {
        var count:Number = 0;
        for (var key:String in this.gameWorld) {
            count++;
        }
        return count;
    }
  
    /**
     * 模拟更新单位状态，包括随机移动和随机增删单位
     */
    private function updateUnits():Void {
        for (var key:String in this.gameWorld) {
            var unit:Object = this.gameWorld[key];
            // 随机移动：x 和 y 方向各随机 -2 到 +2
            var dx:Number = (Math.random() * 4) - 2;
            var dy:Number = (Math.random() * 4) - 2;
            unit.x += dx;
            unit.y += dy;
            unit.aabbCollider.updateFromUnitArea(unit);
        }
    }
  
    /**
     * 运行一次更新循环，模拟一帧游戏更新
     */
    public function runUpdateCycle():Void {
        _root.帧计时器.当前帧数++;
      
        // 随机决定是否添加或移除单位（各 10% 概率）
        if (Math.random() < 0.1) {
            if (Math.random() < 0.5) {
                addUnit();
            } else {
                removeUnit();
            }
        }
      
        updateUnits();
      
        var sampleUnit:Object;
        for (var key:String in this.gameWorld) {
            sampleUnit = this.gameWorld[key];
            break;
        }
        if (!sampleUnit) return;
      
        // 更新敌人、友军、全体缓存（更新间隔写死为 1 帧）
        TargetCacheManager.getCachedEnemy(sampleUnit, 1);
        TargetCacheManager.getCachedAlly(sampleUnit, 1);
        TargetCacheManager.getCachedAll(sampleUnit, 1);
    }

    /**
     * 新增：边界条件测试核心方法
     * 执行所有预定义的边界场景测试用例
     */
    public function runBoundaryTests():Void {
        trace("\n=== 开始边界条件测试 ===");
        
        // 测试用例1：空游戏世界
        _testBoundaryCase(
            "空游戏世界测试", 
            function(test:TargetCacheTest):Void {
                test.gameWorld = {};
                test.unitCounter = 0;
                var dummy:Object = { 是否为敌人: true, aabbCollider: { right: 0, updateFromUnitArea: function(u:Object):Void {} } };
                test.sampleUnit = dummy;

            },
            function(test:TargetCacheTest, u:Object):Void {
                // 无需测试单位，直接验证缓存
                test.assertArrayLength("敌人缓存", TargetCacheManager.getCachedEnemy(null, 0), 0);
                test.assertArrayLength("友军缓存", TargetCacheManager.getCachedAlly(null, 0), 0);
                test.assertArrayLength("全体缓存", TargetCacheManager.getCachedAll(null, 0), 0);
            }
        );


        // 测试用例 2：仅存在一个敌人单位
        _testBoundaryCase(
            "单一敌人单位测试", 
            function(test:TargetCacheTest):Void {
                test._resetWorld();
                var unit:Object = test._addUnitDirectly(true);
                test.sampleUnit = unit;
            },
            function(test:TargetCacheTest, u:Object):Void {
                test.assertArrayProp("敌人缓存应为空（只有自己，无相反阵营）", TargetCacheManager.getCachedEnemy(u, 0), "length", 0);
                test.assertArrayLength("友军缓存(包含自己)", TargetCacheManager.getCachedAlly(u, 0), 1);
                test.assertArrayLength("全体缓存", TargetCacheManager.getCachedAll(u, 0), 1);
            }
        );

        // 测试用例 3：仅存在一个友军单位
        _testBoundaryCase(
            "单一友军单位测试", 
            function(test:TargetCacheTest):Void {
                test._resetWorld();
                var unit:Object = test._addUnitDirectly(false);
                test.sampleUnit = unit;
            },
            function(test:TargetCacheTest, u:Object):Void {
                test.assertArrayLength("敌人缓存(空)", TargetCacheManager.getCachedEnemy(u, 0), 0);
                test.assertArrayLength("友军缓存(包含自己)", TargetCacheManager.getCachedAlly(u, 0), 1);
                test.assertArrayLength("全体缓存", TargetCacheManager.getCachedAll(u, 0), 1);
            }
        );

        // 测试用例 4：全部单位均为敌人
        _testBoundaryCase(
            "全敌人场景测试", 
            function(test:TargetCacheTest):Void {
                test._resetWorld();
                for(var i:Number=0; i<5; i++) test._addUnitDirectly(true);
                test.sampleUnit = test._getFirstUnit();
            },
            function(test:TargetCacheTest, u:Object):Void {
                test.assertArrayLength("敌人缓存（请求者为敌人）", TargetCacheManager.getCachedEnemy(u, 0), 0);
                test.assertArrayLength("全体缓存", TargetCacheManager.getCachedAll(u, 0), 5);
            }
        );

        // 测试用例5：相同right值排序测试
        _testBoundaryCase(
            "相同right值排序测试", 
            function(test:TargetCacheTest):Void {
                test._resetWorld();
                var u1:Object = test._addUnitDirectly(true); // 敌人
                u1.x = 100;
                u1.aabbCollider.updateFromUnitArea(u1);
                var u2:Object = test._addUnitDirectly(false); // 友军
                u2.x = 100;
                u2.aabbCollider.updateFromUnitArea(u2);
                test.sampleUnit = u2; // 请求者改为友军
                test.sampleU2 = u1;
            },
            function(test:TargetCacheTest, u:Object):Void {
                var cached:Array = TargetCacheManager.getCachedEnemy(u, 0);
                test.assertArrayLength("应包含1个敌人", cached, 1);
                test.assertSameObject("应返回敌人单位", cached[0], test.sampleU2);
            }
        );



        // 测试用例 6：精确排序验证
        _testBoundaryCase(
            "精确排序验证", 
            function(test:TargetCacheTest):Void {
                test._resetWorld();
                var units:Array = [];
                for(var i:Number=0; i<5; i++){
                    var u:Object = test._addUnitDirectly(i%2==0);
                    u.x = 100 - i*10;
                    // 新增：更新碰撞箱右边界
                    u.aabbCollider.updateFromUnitArea(u);
                    units.push(u);
                }
                test.sampleUnit = units[4];
                var sorted:Array = units.slice();
                sorted.sort(function(a:Object, b:Object):Number {
                    return a.aabbCollider.right - b.aabbCollider.right;
                });
                test.expectedOrder = sorted;
            },
            function(test:TargetCacheTest, u:Object):Void {
                var cachedAll:Array = TargetCacheManager.getCachedAll(u, 0);
                test.assertArrayOrder("全体缓存排序验证", cachedAll, test.expectedOrder);
            }
        );



        // 输出边界测试结果
        trace("\n=== 边界条件测试完成 ===");
        trace("测试用例总数: " + boundaryTestCases);
        trace("通过用例: " + (boundaryTestCases - boundaryTestFailures));
        trace("失败用例: " + boundaryTestFailures);
        boundaryTestPassed = (boundaryTestFailures == 0);
    }

    /**
     * 新增：边界测试用例执行器
     */
    private function _testBoundaryCase(
        caseName:String,
        setup:Function,
        verify:Function
    ):Void {
        boundaryTestCases++;
        trace("\n运行边界测试用例: " + caseName);
        
        // 重置测试环境
        _resetCacheSystem();
        
        try {
            // 执行测试设置
            setup(this);
            
            // 获取参考单位（优先使用预设单位）
            var testUnit:Object = this.sampleUnit || _getFirstUnit();
            if(!testUnit) {
                trace("测试用例错误：未设置有效测试单位");
                boundaryTestFailures++;
                return;
            }
            
            // 强制刷新缓存（updateInterval=0）
            TargetCacheManager.getCachedEnemy(testUnit, 0);
            TargetCacheManager.getCachedAlly(testUnit, 0);
            TargetCacheManager.getCachedAll(testUnit, 0);
            
            // 执行验证
            verify(this, testUnit);
        } catch(e:Error) {
            trace("测试用例执行异常: " + e.message);
            boundaryTestFailures++;
        }
    }

    /**
     * 新增：断言辅助方法
     */
    public function assertArrayLength(context:String, arr:Array, expected:Number):Void {
        var actual:Number = arr ? arr.length : 0;
        if(actual !== expected) {
            trace("[断言失败] " + context + " 预期长度:" + expected + " 实际长度:" + actual);
            boundaryTestFailures++;
        }
    }
    
    public function assertArrayProp(context:String, arr:Array, prop:String, expected:Number):Void {
        var actual:Number = arr[prop];
        if(actual !== expected) {
            trace("[断言失败] " + context + " 属性" + prop + " 预期值:" + expected + " 实际值:" + actual);
            boundaryTestFailures++;
        }
    }
    
    public function assertSameObject(context:String, actual:Object, expected:Object):Void {
        if(actual !== expected) {
            trace("[断言失败] " + context);
            trace("预期对象: " + expected._name);
            trace("实际对象: " + (actual ? actual._name : "null"));
            boundaryTestFailures++;
        }
    }
    
    public function assertArrayOrder(context:String, actual:Array, expected:Array):Void {
        if(actual.length != expected.length) {
            trace("[断言失败] " + context + " 数组长度不一致");
            boundaryTestFailures++;
            return;
        }
        for(var i:Number=0; i<expected.length; i++) {
            if(actual[i] !== expected[i]) {
                trace("[断言失败] " + context + " 位置" + i + "不匹配");
                trace("预期对象: " + expected[i]._name);
                trace("实际对象: " + actual[i]._name);
                boundaryTestFailures++;
                return;
            }
        }
    }

    /**
     * 新增：重置缓存系统状态
     */
    private function _resetCacheSystem():Void {
        // 重置缓存管理器
        TargetCacheManager.initialize();
        
        // 重置帧计时器
        _root.帧计时器.当前帧数 = 0;
        
        // 重置游戏世界
        _resetWorld();
    }

    /**
     * 新增：直接添加单位（不触发版本更新）
     */
    private function _addUnitDirectly(isEnemy:Boolean):Object {
        var unit:Object = createFakeUnit();
        unit.是否为敌人 = isEnemy;
        gameWorld[unit._name] = unit;
        TargetCacheUpdater.addUnit(unit);
        return unit;
    }

    /**
     * 新增：获取第一个单位
     */
    private function _getFirstUnit():Object {
        for(var key:String in gameWorld) return gameWorld[key];
        return null;
    }

    /**
     * 新增：重置游戏世界
     */
    private function _resetWorld():Void {
        gameWorld = {};
        unitCounter = 0;
        _root.gameworld = gameWorld; // 确保全局引用指向新对象
    }

  
    /**
     * 预热阶段：执行一段时间的更新循环并记录耗时
     */
    public function performWarmup():Number {
        var startTime:Number = getTimer();
        for (var i:Number = 0; i < this.warmupIterations; i++) {
            runUpdateCycle();
        }
        var elapsed:Number = getTimer() - startTime;
        trace("预热阶段：" + this.warmupIterations + " 次更新耗时 " + elapsed + " 毫秒");
        return elapsed;
    }
  
    /**
     * 测试阶段：执行指定次数的更新循环并记录总耗时
     */
    public function performTest():Number {
        var startTime:Number = getTimer();
        for (var i:Number = 0; i < this.updateIterations; i++) {
            runUpdateCycle();
        }
        var elapsed:Number = getTimer() - startTime;
        trace("测试阶段：" + this.updateIterations + " 次更新耗时 " + elapsed + " 毫秒");
        return elapsed;
    }

    /**
     * 辅助方法：将数组转为便于阅读的字符串
     */
    private function arrayToString(arr:Array):String {
        var s:String = "[";
        for (var i:Number = 0; i < arr.length; i++) {
            var u:Object = arr[i];
            s += u._name + "(right=" + u.aabbCollider.right + ")";
            if (i < arr.length - 1) {
                s += ", ";
            }
        }
        s += "]";
        return s;
    }
  
    private function insertionSortByRight(list:Array):Void {
        var len:Number = list.length;
        for (var i:Number = 1; i < len; i++) {
            var currentUnit:Object = list[i];
            var currentVal:Number = currentUnit.aabbCollider.right;
            var j:Number = i - 1;
            while (j >= 0 && list[j].aabbCollider.right > currentVal) {
                list[j + 1] = list[j];
                j--;
            }
            list[j + 1] = currentUnit;
        }
    }
  
    private function compareArrays(arr1:Array, arr2:Array):Boolean {
        if (arr1.length != arr2.length) {
            trace("数组长度不匹配: ");
            trace("arr1 长度: " + arr1.length + " | 内容: " + arrayToString(arr1));
            trace("arr2 长度: " + arr2.length + " | 内容: " + arrayToString(arr2));
            return false;
        }
        for (var i:Number = 0; i < arr1.length; i++) {
            if (arr1[i] != arr2[i]) {
                trace("数组元素不匹配（索引 " + i + "）: ");
                trace("arr1 元素: " + arr1[i]._name + " (right=" + arr1[i].aabbCollider.right + ")");
                trace("arr2 元素: " + arr2[i]._name + " (right=" + arr2[i].aabbCollider.right + ")");
                trace("完整数组对比:");
                trace("arr1: " + arrayToString(arr1));
                trace("arr2: " + arrayToString(arr2));
                return false;
            }
        }
        return true;
    }
  
    // 以下方法用于手动筛选，用以验证缓存准确性
    private function collectManualEnemies(requestor:Object):Array {
        var result:Array = [];
        for (var key:String in this.gameWorld) {
            var u:Object = this.gameWorld[key];
            if (u.hp > 0 && u.是否为敌人 != requestor.是否为敌人) { 
                u.aabbCollider.updateFromUnitArea(u);
                result.push(u);
            }
        }
        insertionSortByRight(result);
        return result;
    }

    private function collectManualAllies(requestor:Object):Array {
        var result:Array = [];
        for (var key:String in this.gameWorld) {
            var u:Object = this.gameWorld[key];
            if (u.hp > 0 && u.是否为敌人 == requestor.是否为敌人) { 
                u.aabbCollider.updateFromUnitArea(u);
                result.push(u);
            }
        }
        insertionSortByRight(result);
        return result;
    }

  
    private function collectManualAll():Array {
        var result:Array = [];
        for (var key:String in this.gameWorld) {
            var u:Object = this.gameWorld[key];
            if (u.hp > 0) {
                u.aabbCollider.updateFromUnitArea(u);
                result.push(u);
            }
        }
        insertionSortByRight(result);
        return result;
    }
  
    /**
     * 校验缓存准确性，将缓存结果与手动筛选+排序结果对比
     */
    private function checkCacheAccuracy():Void {
        trace("=== 开始缓存准确性检验 ===");
        var mismatchCount:Number = 0;
        for (var key:String in this.gameWorld) {
            var unit:Object = this.gameWorld[key];
            var enemiesCached:Array = TargetCacheManager.getCachedEnemy(unit, 0);
            var alliesCached:Array  = TargetCacheManager.getCachedAlly(unit, 0);
            var allCached:Array     = TargetCacheManager.getCachedAll(unit, 0);
  
            var enemiesManual:Array = collectManualEnemies(unit);
            var alliesManual:Array  = collectManualAllies(unit);
            var allManual:Array     = collectManualAll();
  
            if (!compareArrays(enemiesCached, enemiesManual)) {
                mismatchCount++;
                trace("Enemies [不匹配] 单位 " + unit + " 的敌人列表与手动结果不同");
            }
            if (!compareArrays(alliesCached, alliesManual)) {
                mismatchCount++;
                trace("Allies [不匹配] 单位 " + unit + " 的友军列表与手动结果不同");
            }
            if (!compareArrays(allCached, allManual)) {
                mismatchCount++;
                trace("All [不匹配] 单位 " + unit + " 的全体列表与手动结果不同");
            }
        }
  
        if (mismatchCount == 0) {
            trace("=== 缓存准确性检验通过，未发现差异 ===");
        } else {
            trace("=== 缓存准确性检验结束，共发现 " + mismatchCount + " 处不匹配 ===");
        }
    }
  
    /**
     * 执行测试：重复多次预热+准确性校验，再执行正式测试，并输出性能指标
     */
    public function runTest():Void {
        trace("=== TargetCache 测试开始 ===");

        // 阶段1：执行边界条件测试
        runBoundaryTests();
        if(!boundaryTestPassed) {
            trace("\n!!! 边界条件测试未通过，终止测试流程 !!!");
            return;
        }
        
        // 阶段2：恢复随机测试环境
        initializeGameWorld();

        var totalWarmupTime:Number = 0;
        for (var cycle:Number = 0; cycle < this.warmupCycles; cycle++) {
            trace("=== 预热阶段循环 " + (cycle + 1) + " 开始 ===");
            var warmupTime:Number = performWarmup();
            totalWarmupTime += warmupTime;
            checkCacheAccuracy();
            trace("=== 预热阶段循环 " + (cycle + 1) + " 结束 ===");
        }
        var totalWarmupIterations:Number = this.warmupCycles * this.warmupIterations;
        var avgWarmupTime:Number = totalWarmupTime / totalWarmupIterations;
      
        var testTime:Number = performTest();
        var totalIterations:Number = totalWarmupIterations + this.updateIterations;
        var totalTime:Number = totalWarmupTime + testTime;
        var testAvg:Number = testTime / this.updateIterations;
        var totalAvg:Number = totalTime / totalIterations;
      
        trace("\n性能指标分析：");
        trace("预热阶段：");
        trace("  ▸ 循环次数：" + this.warmupCycles);
        trace("  ▸ 每循环更新次数：" + this.warmupIterations);
        trace("  ▸ 平均耗时：" + avgWarmupTime + " 毫秒/次");
        trace("测试阶段：");
        trace("  ▸ 总次数：" + this.updateIterations + " 次");
        trace("  ▸ 单次耗时：" + testAvg + " 毫秒/次");
        trace("综合统计：");
        trace("  ▸ 总耗时：" + totalTime + " 毫秒");
        trace("  ▸ 平均耗时：" + totalAvg + " 毫秒/次");
        trace("  ▸ 帧率估算：" + (1000 / totalAvg) + " FPS");
        trace("\n当前单位数量：" + getUnitCount());
        trace("=== TargetCache 测试结束 ===");
    }
}
