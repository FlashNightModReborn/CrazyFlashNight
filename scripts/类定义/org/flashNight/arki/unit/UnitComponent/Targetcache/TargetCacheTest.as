// 文件路径: org/flashNight/arki/unit/UnitComponent/targetcache/TargetCacheTest.as
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
    
    // 构造函数，传入正式测试和预热的迭代次数
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
    
    // 初始化游戏世界，构造初始假数据单位
    private function initializeGameWorld():Void {
        var initialCount:Number = 20;
        for (var i:Number = 0; i < initialCount; i++) {
            addUnit();
        }
    }
    
    // 创建一个假单位，包括基本属性和碰撞箱
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
    
    // 向游戏世界中添加一个单位（当单位数未达到最大值时）
    private function addUnit():Void {
        if (getUnitCount() >= maxUnits) return;
        var unit:Object = createFakeUnit();
        this.gameWorld[unit._name] = unit;
    }
    
    // 从游戏世界中随机移除一个单位（当单位数大于最小值时）
    private function removeUnit():Void {
        if (getUnitCount() <= minUnits) return;
        var keys:Array = [];
        for (var key:String in this.gameWorld) {
            keys.push(key);
        }
        var randomIndex:Number = Math.floor(Math.random() * keys.length);
        var unitKey:String = keys[randomIndex];
        delete this.gameWorld[unitKey];
    }
    
    // 获取当前游戏世界中单位的数量
    private function getUnitCount():Number {
        var count:Number = 0;
        for (var key:String in this.gameWorld) {
            count++;
        }
        return count;
    }
    
    // 模拟更新单位状态，包括随机移动和随机增删单位
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
    
    // 运行一次更新循环，模拟一帧游戏更新
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
        
        // 模拟调用缓存更新接口（更新敌人、友军、全体缓存）
        TargetCacheManager.updateTargetCache(sampleUnit, 5, "敌人", sampleUnit.是否为敌人.toString());
        TargetCacheManager.updateTargetCache(sampleUnit, 5, "友军", sampleUnit.是否为敌人.toString());
        TargetCacheManager.updateTargetCache(sampleUnit, 5, "全体", "all");
        
        // 模拟读取缓存数据（测试读取性能）
        var enemyTargets:Array = TargetCacheManager.getCachedEnemy(sampleUnit, 5);
        var allyTargets:Array = TargetCacheManager.getCachedAlly(sampleUnit, 5);
        var allTargets:Array = TargetCacheManager.getCachedAll(sampleUnit, 5);
        // 可选：调试时可以输出各类型目标数量
        // trace("敌人: " + enemyTargets.length + ", 友军: " + allyTargets.length + ", 全体: " + allTargets.length);
    }
    
    // 预热阶段：执行一段时间的更新循环并记录耗时（以稳定运行状态）
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
    
    // 测试阶段：执行指定次数的更新循环，记录总耗时（包含更新和缓存获取）
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
    
    // 主测试入口，先进行预热，再正式测试
    public function runTest():Void {
        trace("=== TargetCache 测试开始 ===");
        var warmupTime:Number = performWarmup();
        var testTime:Number = performTest();
        trace("预热阶段耗时：" + warmupTime + " 毫秒");
        trace("测试阶段耗时：" + testTime + " 毫秒");
        trace("当前单位数量：" + getUnitCount());
        trace("=== TargetCache 测试结束 ===");
    }
}


