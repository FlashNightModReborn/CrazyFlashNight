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
      
        // 模拟碰撞箱对象，包含左右边界属性和更新方法
        unit.aabbCollider = {
            left: unit.x,
            right: unit.x + unit.width,
            updateFromUnitArea: function(u:Object):Void {
                this.left = u.x;
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
                    return a.aabbCollider.left - b.aabbCollider.left;
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
    // 使用 FactionManager 进行阵营关系判断，正确处理三阵营（PLAYER/ENEMY/HOSTILE_NEUTRAL）
    private function collectManualEnemies(requestor:Object):Array {
        var result:Array = [];
        for (var key:String in this.gameWorld) {
            var u:Object = this.gameWorld[key];
            if (u.hp > 0 && FactionManager.areUnitsEnemies(requestor, u)) {
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
            if (u.hp > 0 && FactionManager.areUnitsAllies(requestor, u)) {
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
  
    // ========================================================================
    // 高级测试：过滤器查询 / 单调扫描 / 版本失效 / rightMaxValues
    // ========================================================================

    /** 高级测试失败计数 */
    private var advancedTestCases:Number = 0;
    private var advancedTestFailures:Number = 0;

    /** 高级测试断言：布尔条件 */
    public function advAssertTrue(context:String, condition:Boolean):Void {
        if (!condition) {
            trace("[高级断言失败] " + context);
            advancedTestFailures++;
        }
    }

    /** 高级测试断言：相等 */
    public function advAssertEqual(context:String, actual, expected):Void {
        if (actual !== expected) {
            trace("[高级断言失败] " + context + " 预期:" + expected + " 实际:" + actual);
            advancedTestFailures++;
        }
    }

    /**
     * 运行所有高级测试
     */
    public function runAdvancedTests():Boolean {
        trace("\n=== 开始高级测试 ===");
        advancedTestCases = 0;
        advancedTestFailures = 0;

        testFilterQuery();
        testFilterFallback();
        testMonotonicSweep();
        testVersionInvalidation();
        testRightMaxValues();

        trace("\n=== 高级测试完成 ===");
        trace("测试用例总数: " + advancedTestCases);
        trace("通过用例: " + (advancedTestCases - advancedTestFailures));
        trace("失败用例: " + advancedTestFailures);
        return (advancedTestFailures == 0);
    }

    // ------------------------------------------------------------------
    // 测试7：过滤器查询（findNearestWithFilter 系列）
    // ------------------------------------------------------------------
    private function testFilterQuery():Void {
        advancedTestCases++;
        trace("\n运行高级测试: 过滤器查询");
        _resetCacheSystem();

        // 创建场景：友军请求者 + 3 个敌人
        var requester:Object = _addUnitDirectly(false); // 友军
        requester.x = 200;
        requester.aabbCollider.updateFromUnitArea(requester);

        var e1:Object = _addUnitDirectly(true); // 敌人，近，高血量
        e1.x = 220; e1.hp = 100; e1.maxhp = 100; e1.threat = 5;
        e1.aabbCollider.updateFromUnitArea(e1);

        var e2:Object = _addUnitDirectly(true); // 敌人，中，低血量
        e2.x = 250; e2.hp = 30; e2.maxhp = 100; e2.threat = 1;
        e2.aabbCollider.updateFromUnitArea(e2);

        var e3:Object = _addUnitDirectly(true); // 敌人，远，高威胁
        e3.x = 300; e3.hp = 80; e3.maxhp = 100; e3.threat = 10;
        e3.aabbCollider.updateFromUnitArea(e3);

        // 测试 findNearestEnemy：应返回 e1（最近）
        var nearest:Object = TargetCacheManager.findNearestEnemy(requester, 0);
        advAssertTrue("findNearestEnemy 返回最近敌人", nearest == e1);

        // 测试 findNearestLowHPEnemy：应返回 e2（hp < 50%）
        var lowHP:Object = TargetCacheManager.findNearestLowHPEnemy(requester, 0, 30);
        advAssertTrue("findNearestLowHPEnemy 返回低血量敌人", lowHP == e2);

        // 测试 findNearestThreateningEnemy（阈值8）：e1(5) 和 e2(1) 不满足，应返回 e3(10)
        var threatening:Object = TargetCacheManager.findNearestThreateningEnemy(requester, 0, 8, 30);
        advAssertTrue("findNearestThreateningEnemy 返回高威胁敌人", threatening == e3);

        // 测试 findNearestEnemyWithFilter 自定义过滤器：查找 hp > 50 的敌人
        var customResult:Object = TargetCacheManager.findNearestEnemyWithFilter(
            requester, 0,
            function(u:Object, t:Object, dist:Number):Boolean { return u.hp > 50; },
            30, undefined
        );
        advAssertTrue("自定义过滤器返回 hp>50 的最近敌人", customResult == e1);
    }

    // ------------------------------------------------------------------
    // 测试8：过滤器回退（findNearestWithFallback 系列）
    // ------------------------------------------------------------------
    private function testFilterFallback():Void {
        advancedTestCases++;
        trace("\n运行高级测试: 过滤器回退");
        _resetCacheSystem();

        // 场景：友军请求者 + 1 个敌人，无高威胁
        var requester:Object = _addUnitDirectly(false);
        requester.x = 100;
        requester.aabbCollider.updateFromUnitArea(requester);

        var e1:Object = _addUnitDirectly(true);
        e1.x = 150; e1.hp = 80; e1.maxhp = 100; e1.threat = 2;
        e1.aabbCollider.updateFromUnitArea(e1);

        // 查找威胁>=10的敌人（不存在），应回退到最近敌人 e1
        var fallback:Object = TargetCacheManager.findNearestThreateningEnemyWithFallback(requester, 0, 10, 30);
        advAssertTrue("回退返回最近敌人", fallback == e1);

        // 查找低血量敌人（e1 hp=80%，不满足 <50%），应回退到最近敌人 e1
        var fallback2:Object = TargetCacheManager.findNearestLowHPEnemyWithFallback(requester, 0, 30);
        advAssertTrue("低血量回退返回最近敌人", fallback2 == e1);
    }

    // ------------------------------------------------------------------
    // 测试9：单调扫描正确性
    // ------------------------------------------------------------------
    private function testMonotonicSweep():Void {
        advancedTestCases++;
        trace("\n运行高级测试: 单调扫描");
        _resetCacheSystem();

        // 创建 5 个等距敌人：x = 50, 100, 150, 200, 250
        var requester:Object = _addUnitDirectly(false);
        requester.x = 0;
        requester.aabbCollider.updateFromUnitArea(requester);

        var enemies:Array = [];
        for (var i:Number = 0; i < 5; i++) {
            var e:Object = _addUnitDirectly(true);
            e.x = 50 + i * 50;
            e.width = 40;
            e.aabbCollider.updateFromUnitArea(e);
            enemies.push(e);
        }

        // 触发一次缓存构建
        TargetCacheManager.getCachedEnemy(requester, 0);

        // 获取缓存对象
        var cache:SortedUnitCache = TargetCacheManager.acquireEnemyCache(requester, 0);
        advAssertTrue("缓存非空", cache != null);

        if (cache != null) {
            // 模拟从左到右的单调扫描查询
            var currentFrame:Number = _root.帧计时器.当前帧数;
            cache.beginMonotonicSweep(currentFrame);

            var lastStartIndex:Number = -1;
            var sweepCorrect:Boolean = true;

            // 5 个查询点从左到右：queryLeft = 30, 80, 130, 180, 230
            for (var q:Number = 0; q < 5; q++) {
                var queryLeft:Number = 30 + q * 50;
                // 构造一个模拟的查询 AABB
                var mockQuery = { left: queryLeft, right: queryLeft + 20 };
                var result:Object = cache.getTargetsFromIndexMonotonic(mockQuery);

                // startIndex 必须单调非减
                if (result.startIndex < lastStartIndex) {
                    sweepCorrect = false;
                    trace("  单调性违反：查询" + q + " startIndex=" + result.startIndex
                        + " < 上次=" + lastStartIndex);
                }
                lastStartIndex = result.startIndex;
            }
            advAssertTrue("单调扫描 startIndex 单调非减", sweepCorrect);

            // 验证跨帧重置：新帧号应重置指针
            cache.beginMonotonicSweep(currentFrame + 1);
            var mockQuery2 = { left: 9999, right: 10000 };
            var resetResult:Object = cache.getTargetsFromIndexMonotonic(mockQuery2);
            // 查询一个超远位置，startIndex 应等于数据长度
            advAssertEqual("跨帧重置后超远查询", resetResult.startIndex, cache.data.length);
        }
    }

    // ------------------------------------------------------------------
    // 测试10：版本失效逻辑
    // ------------------------------------------------------------------
    private function testVersionInvalidation():Void {
        advancedTestCases++;
        trace("\n运行高级测试: 版本失效");
        _resetCacheSystem();

        // 初始场景：1 友军请求者 + 2 敌人
        var requester:Object = _addUnitDirectly(false);
        requester.x = 100;
        requester.aabbCollider.updateFromUnitArea(requester);

        var e1:Object = _addUnitDirectly(true);
        e1.x = 150;
        e1.aabbCollider.updateFromUnitArea(e1);

        var e2:Object = _addUnitDirectly(true);
        e2.x = 200;
        e2.aabbCollider.updateFromUnitArea(e2);

        // 首次获取：应有 2 个敌人，使用较大 interval 使缓存不会自动过期
        var enemies1:Array = TargetCacheManager.getCachedEnemy(requester, 9999);
        advAssertEqual("初始敌人数", enemies1.length, 2);

        // 添加新敌人 → 版本号变更 → 即使 interval 未到，缓存应失效并包含新单位
        var e3:Object = _addUnitDirectly(true);
        e3.x = 250;
        e3.aabbCollider.updateFromUnitArea(e3);

        var enemies2:Array = TargetCacheManager.getCachedEnemy(requester, 9999);
        advAssertEqual("添加后敌人数", enemies2.length, 3);

        // 移除一个敌人 → 版本号变更
        TargetCacheUpdater.removeUnit(e1);
        delete gameWorld[e1._name];

        var enemies3:Array = TargetCacheManager.getCachedEnemy(requester, 9999);
        advAssertEqual("移除后敌人数", enemies3.length, 2);

        // 验证友军缓存不受敌人变更影响（版本号隔离）
        // 先获取一次友军缓存建立基线
        var allies1:Array = TargetCacheManager.getCachedAlly(requester, 9999);
        var allyCount1:Number = allies1.length;

        // 添加一个敌人（不应影响友军缓存版本）
        var e4:Object = _addUnitDirectly(true);
        e4.x = 300;
        e4.aabbCollider.updateFromUnitArea(e4);

        // 由于友军阵营版本未变，且 interval=9999 足够大，应命中缓存（返回相同数据）
        var allies2:Array = TargetCacheManager.getCachedAlly(requester, 9999);
        advAssertEqual("友军缓存不受敌人变更影响", allies2.length, allyCount1);
    }

    // ------------------------------------------------------------------
    // 测试11：rightMaxValues 构建正确性
    // ------------------------------------------------------------------
    private function testRightMaxValues():Void {
        advancedTestCases++;
        trace("\n运行高级测试: rightMaxValues 构建");
        _resetCacheSystem();

        // 创建宽度各异的单位（left 递增但 right 不一定单调）
        var requester:Object = _addUnitDirectly(false);
        requester.x = 0;
        requester.aabbCollider.updateFromUnitArea(requester);

        // 敌人：不同宽度导致 right 非单调
        // e1: x=50, width=100 → left=50, right=150  (宽)
        // e2: x=80, width=20  → left=80, right=100  (窄，right < e1.right)
        // e3: x=120, width=30 → left=120, right=150 (right = e1.right)
        // e4: x=200, width=80 → left=200, right=280 (新最大)
        var widths:Array = [100, 20, 30, 80];
        var xPositions:Array = [50, 80, 120, 200];

        for (var i:Number = 0; i < 4; i++) {
            var e:Object = _addUnitDirectly(true);
            e.x = xPositions[i];
            e.width = widths[i];
            e.aabbCollider.updateFromUnitArea(e);
        }

        // 触发缓存构建
        TargetCacheManager.getCachedEnemy(requester, 0);
        var cache:SortedUnitCache = TargetCacheManager.acquireEnemyCache(requester, 0);
        advAssertTrue("rightMaxValues 缓存非空", cache != null);

        if (cache != null) {
            var data:Array = cache.data;
            var rv:Array = cache.rightValues;
            var rmv:Array = cache.rightMaxValues;
            var n:Number = data.length;

            advAssertEqual("rightMaxValues 长度一致", rmv.length, n);

            // 验证前缀最大值性质
            var runningMax:Number = -Infinity;
            var prefixCorrect:Boolean = true;
            var monotonicCorrect:Boolean = true;

            for (var k:Number = 0; k < n; k++) {
                if (rv[k] > runningMax) runningMax = rv[k];

                if (rmv[k] != runningMax) {
                    prefixCorrect = false;
                    trace("  rightMaxValues[" + k + "]=" + rmv[k] + " != 期望=" + runningMax);
                }
                if (k > 0 && rmv[k] < rmv[k - 1]) {
                    monotonicCorrect = false;
                    trace("  rightMaxValues 非单调：[" + (k-1) + "]=" + rmv[k-1] + " > [" + k + "]=" + rmv[k]);
                }
            }
            advAssertTrue("rightMaxValues 满足前缀最大值", prefixCorrect);
            advAssertTrue("rightMaxValues 单调非降", monotonicCorrect);

            // 验证 validateData 也能通过
            var validation:Object = cache.validateData();
            advAssertTrue("validateData 通过", validation.isValid);
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

        // 阶段1.5：执行高级测试
        var advancedPassed:Boolean = runAdvancedTests();
        if(!advancedPassed) {
            trace("\n!!! 高级测试未通过，终止测试流程 !!!");
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
