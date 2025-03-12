import org.flashNight.arki.unit.UnitComponent.Targetcache.*;

// TargetCacheTest.as
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
  
    /**
     * 构造函数，传入正式测试和预热的迭代次数
     */
    public function TargetCacheTest(updateIterations:Number, warmupIterations:Number) {
        this.updateIterations = updateIterations;
        this.warmupIterations = warmupIterations;
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
        return unit;
    }
  
    /**
     * 向游戏世界中添加一个单位（当单位数未达到最大值时）
     */
    private function addUnit():Void {
        if (getUnitCount() >= maxUnits) return;
        var unit:Object = createFakeUnit();
        this.gameWorld[unit._name] = unit;
        TargetCacheUpdater.addUnit(unit); // ✅ 新增版本更新
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
        TargetCacheUpdater.removeUnit(this.gameWorld[unitKey]); // ✅ 新增版本更新
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
        // 遍历所有单位，随机移动单位并更新碰撞箱
        for (var key:String in this.gameWorld) {
            var unit:Object = this.gameWorld[key];
            // 随机移动：x 和 y 方向各随机 -2 到 +2
            var dx:Number = (Math.random() * 4) - 2;
            var dy:Number = (Math.random() * 4) - 2;
            unit.x += dx;
            unit.y += dy;
            // 更新碰撞箱右边界
            unit.aabbCollider.updateFromUnitArea(unit);
        }
    }
  
    /**
     * 运行一次更新循环，模拟一帧游戏更新
     */
    public function runUpdateCycle():Void {
        // 增加全局帧计时器
        _root.帧计时器.当前帧数++;
      
        // 随机决定是否添加或移除单位（各 10% 概率）
        if (Math.random() < 0.1) {
            if (Math.random() < 0.5) {
                addUnit();
            } else {
                removeUnit();
            }
        }
      
        // 更新所有单位的位置和碰撞箱
        updateUnits();
      
        // 选择一个示例单位（任一单位）用于调用 TargetCacheManager 的接口
        var sampleUnit:Object;
        for (var key:String in this.gameWorld) {
            sampleUnit = this.gameWorld[key];
            break;
        }
        if (!sampleUnit) return;
      
        // 模拟调用缓存更新接口（更新敌人、友军、全体缓存），这里的更新间隔写死为 5 帧
        TargetCacheManager.updateTargetCache(sampleUnit, 5, "敌人", sampleUnit.是否为敌人.toString());
        TargetCacheManager.updateTargetCache(sampleUnit, 5, "友军", sampleUnit.是否为敌人.toString());
        TargetCacheManager.updateTargetCache(sampleUnit, 5, "全体", "all");
      
        // 如果需要，也可在此读取缓存（例如测试读取性能）
        // var enemyTargets:Array = TargetCacheManager.getCachedEnemy(sampleUnit, 5);
        // var allyTargets:Array = TargetCacheManager.getCachedAlly(sampleUnit, 5);
        // var allTargets:Array = TargetCacheManager.getCachedAll(sampleUnit, 5);
    }
  
    /**
     * 预热阶段：执行一段时间的更新循环并记录耗时（以便让系统进入稳定状态）
     */
    public function performWarmup():Number {
        var startTime:Number = getTimer();
        for (var i:Number = 0; i < this.warmupIterations; i++) {
            runUpdateCycle();
        }
        var endTime:Number = getTimer();
        var elapsed:Number = endTime - startTime;
        trace("预热阶段：" + this.warmupIterations + " 次更新耗时 " + elapsed + " 毫秒");
        return elapsed;
    }
  
    /**
     * 测试阶段：执行指定次数的更新循环，记录总耗时（包含更新和缓存获取）
     */
    public function performTest():Number {
        var startTime:Number = getTimer();
        for (var i:Number = 0; i < this.updateIterations; i++) {
            runUpdateCycle();
        }
        var endTime:Number = getTimer();
        var elapsed:Number = endTime - startTime;
        trace("测试阶段：" + this.updateIterations + " 次更新耗时 " + elapsed + " 毫秒");
        return elapsed;
    }

    /**
     * 在预热结束后，进行一次缓存准确性检验：
     * 对当前游戏世界中每个单位，分别获取敌人、友军和全体缓存，
     * 与手动筛选 + 排序的结果对比，检查是否满足预期。
     */
    private function checkCacheAccuracy():Void {
        trace("=== 开始缓存准确性检验 ===");
        var mismatchCount:Number = 0;

        var traceEnemies:Boolean = false;
        var traceAllies:Boolean = false;
        var traceALL:Boolean = false;
        
        for (var key:String in this.gameWorld) {
            var unit:Object = this.gameWorld[key];
            
            // 从 TargetCacheManager 获取缓存数据（设定 updateInterval=0，强制立即更新）
            var enemiesCached:Array = TargetCacheManager.getCachedEnemy(unit, 0);
            var alliesCached:Array  = TargetCacheManager.getCachedAlly(unit, 0);
            var allCached:Array     = TargetCacheManager.getCachedAll(unit, 0);

            // 手动筛选并排序
            var enemiesManual:Array = collectManualEnemies(unit);
            var alliesManual:Array  = collectManualAllies(unit);
            var allManual:Array     = collectManualAll();

            // 逐项比较
            if (!compareArrays(enemiesCached, enemiesManual)) {
                mismatchCount++;
                trace(" [不匹配] 单位 " + unit._name + " 的敌人列表与手动结果不同");
                traceEnemies = true;

            }
            
            if (!compareArrays(alliesCached, alliesManual)) {
                mismatchCount++;
                trace(" [不匹配] 单位 " + unit._name + " 的友军列表与手动结果不同");
                traceAllies = true;

            }
            
            if (!compareArrays(allCached, allManual)) {
                mismatchCount++;
                trace(" [不匹配] 单位 " + unit._name + " 的全体列表与手动结果不同");
                traceALL = true;
            }
        }

        if(traceEnemies) {
            trace("   缓存返回: " + arrayToString(enemiesCached));
            trace("   手动结果: " + arrayToString(enemiesManual));
        }

        if(traceAllies) {
            trace("   缓存返回: " + arrayToString(alliesCached));
            trace("   手动结果: " + arrayToString(alliesManual));
        }

        if(traceALL) {
            trace("   缓存返回: " + arrayToString(allCached));
            trace("   手动结果: " + arrayToString(allManual));
        }
        if (mismatchCount == 0) {
            trace("=== 缓存准确性检验通过，未发现差异 ===");
        } else {
            trace("=== 缓存准确性检验结束，共发现 " + mismatchCount + " 处不匹配 ===");
        }
    }
    
    /**
     * 将数组信息转为便于阅读的字符串，可根据需要增改打印的属性
     */
    private function arrayToString(arr:Array):String {
        var s:String = "[";
        for (var i:Number = 0; i < arr.length; i++) {
            var u:Object = arr[i];
            // 打印名称和 right 值，以直观查看排序结果
            s += u._name + "(right=" + u.aabbCollider.right + ")";
            if (i < arr.length - 1) {
                s += ", ";
            }
        }
        s += "]";
        return s;
    }
  
    /**
     * 运行完整测试：先预热，再进行准确性校验，然后再正式测试
     */
    public function runTest():Void {
        trace("=== TargetCache 测试开始 ===");
        var warmupTime:Number = performWarmup();
        
        // 预热结束后，进行缓存准确性检验
        checkCacheAccuracy();
        
        // 然后进入正式性能测试
        var testTime:Number = performTest();
        
        trace("预热阶段耗时：" + warmupTime + " 毫秒");
        trace("测试阶段耗时：" + testTime + " 毫秒");
        trace("当前单位数量：" + getUnitCount());
        trace("=== TargetCache 测试结束 ===");
    }
  
    // -----------------------------------------------------------------
    // 以下是校验准确性时用到的辅助方法：手动筛选 + 排序 + 数组比对
    // -----------------------------------------------------------------

    /**
     * 手动筛选：收集指定参考单位(RefUnit)的敌人集合并按 right 值排序
     */
    private function collectManualEnemies(refUnit:Object):Array {
        var result:Array = [];
        for (var key:String in this.gameWorld) {
            var u:Object = this.gameWorld[key];
            if (u.hp > 0 && u.是否为敌人 != refUnit.是否为敌人) {
                result.push(u);
            }
        }
        insertionSortByRight(result);
        return result;
    }

    /**
     * 手动筛选：收集指定参考单位(RefUnit)的友军集合并按 right 值排序
     */
    private function collectManualAllies(refUnit:Object):Array {
        var result:Array = [];
        for (var key:String in this.gameWorld) {
            var u:Object = this.gameWorld[key];
            if (u.hp > 0 && u.是否为敌人 == refUnit.是否为敌人) {
                result.push(u);
            }
        }
        insertionSortByRight(result);
        return result;
    }

    /**
     * 手动筛选：收集所有存活单位并按 right 值排序
     */
    private function collectManualAll():Array {
        var result:Array = [];
        for (var key:String in this.gameWorld) {
            var u:Object = this.gameWorld[key];
            if (u.hp > 0) {
                result.push(u);
            }
        }
        insertionSortByRight(result);
        return result;
    }
  
    /**
     * 简单的插入排序，根据 aabbCollider.right 进行排序
     */
    private function insertionSortByRight(list:Array):Void {
        var len:Number = list.length;
        for (var i:Number = 1; i < len; i++) {
            var key:Object = list[i];
            var keyVal:Number = key.aabbCollider.right;
            var j:Number = i - 1;
            while (j >= 0 && list[j].aabbCollider.right > keyVal) {
                list[j + 1] = list[j];
                j--;
            }
            list[j + 1] = key;
        }
    }

    /**
     * 比较两个数组元素是否相同（包含顺序比较），如果长度或任一位置的元素不一致则返回 false
     */
    private function compareArrays(arr1:Array, arr2:Array):Boolean {
        if (arr1.length != arr2.length) {
            return false;
        }
        for (var i:Number = 0; i < arr1.length; i++) {
            if (arr1[i] != arr2[i]) {
                return false;
            }
        }
        return true;
    }
}
