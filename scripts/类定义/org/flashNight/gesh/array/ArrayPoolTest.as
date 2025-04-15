import org.flashNight.gesh.array.*;

class org.flashNight.gesh.array.ArrayPoolTest {
    private var testCount:Number = 0;
    private var passCount:Number = 0;
    
    public function runAllTests():Void {
        trace("开始 ArrayPool 测试套件");
        
        testBasicFunctionality();
        testArrayReset();
        testEdgeCases();
        testPerformance();
        
        trace("测试完成: " + passCount + "/" + testCount + " 通过");
    }

    // 测试基本功能：获取、释放和清空对象池
    private function testBasicFunctionality():Void {
        var pool:ArrayPool = new ArrayPool(0);
        
        // 初始状态验证
        assert(pool.getPoolSize() == 0, "初始池大小应为0");
        
        // 第一次获取时应创建新数组
        var arr1:Array = pool.getObject();
        assert(arr1 != null, "应成功获取数组实例");
        assert(pool.getPoolSize() == 0, "获取后池应仍为空");
        
        // 释放对象后池大小增加
        pool.releaseObject(arr1);
        assert(pool.getPoolSize() == 1, "释放后池大小应为1");
        
        // 再次获取应复用同一个实例
        var arr2:Array = pool.getObject();
        assert(arr2 === arr1, "应获取到同一个实例");
        assert(pool.getPoolSize() == 0, "复用后池应为空");
        
        pool.clearPool();
        assert(pool.getPoolSize() == 0, "清空后池应为空");
    }
    
    // 测试数组重置：释放数组后应重置为初始容量且内容清空
    private function testArrayReset():Void {
        var pool:ArrayPool = new ArrayPool(5);
        
        // 获取新数组并验证初始容量
        var arr:Array = pool.getObject();
        assert(arr.length == 5, "新数组应初始化容量5");
        
        // 修改数组内容与长度
        arr[0] = "test";
        arr.length = 10;
        
        // 释放后应重置为初始容量，并清除数据
        pool.releaseObject(arr);
        var newArr:Array = pool.getObject();
        assert(newArr.length == 5, "重置后容量应恢复为5");
        assert(newArr[0] === undefined, "数组内容应被清除");
    }
    
    // 测试边界情况：非法对象与空值均不应影响池状态
    private function testEdgeCases():Void {
        var pool:ArrayPool = new ArrayPool(3);
        
        // 非法对象不应加入池
        pool.releaseObject(new Object());
        assert(pool.getPoolSize() == 0, "非法对象不应加入池");
        
        // null/undefined 不应影响池状态
        pool.releaseObject(null);
        pool.releaseObject(undefined);
        assert(pool.getPoolSize() == 0, "空值不应影响池");
        
        // 压力测试：重复获取并释放，期望池中只保留最后一个对象
        for(var i:Number = 0; i < 1000; i++) {
            pool.releaseObject(pool.getObject());
        }
        assert(pool.getPoolSize() == 1, "批量操作后池大小错误");
    }
    
    // 性能测试：通过预热确保测量更加公平
    private function testPerformance():Void {
        var iterations:Number = 100000;
        var warmUpIterations:Number = 10000;
        var arr:Array;
        var i:Number;
        
        // --- 原生创建测试 ---
        // 预热阶段：模拟完整的生命周期
        for(i = 0; i < warmUpIterations; i++) {
            arr = new Array(100);
            arr[0] = i;
            arr.length = 0;  // 模拟释放
        }
        
        // 测试原生创建与销毁
        var nativeStart:Number = getTimer();
        for(i = 0; i < iterations; i++) {
            arr = new Array(100);
            arr[0] = i;
            arr.length = 0;  // 模拟释放
        }
        var nativeTime:Number = getTimer() - nativeStart;
        
        // --- 对象池测试 ---
        var pool:ArrayPool = new ArrayPool(100);
        // 预热阶段：确保池中的对象均经过初始化与重置
        for(i = 0; i < warmUpIterations; i++) {
            var pArr:Array = pool.getObject();
            pArr[0] = i;
            pool.releaseObject(pArr);
        }
        
        // 测试对象池的获取与释放性能
        var poolStart:Number = getTimer();
        for(i = 0; i < iterations; i++) {
            pArr = pool.getObject();
            pArr[0] = i;
            pool.releaseObject(pArr);
        }
        var poolTime:Number = getTimer() - poolStart;
        
        trace("性能测试结果:");
        trace("原生创建: " + nativeTime + "ms");
        trace("对象池:   " + poolTime + "ms");
        trace("性能提升: " + Math.round((nativeTime / poolTime) * 100) / 100 + "倍");
    }
    
    // 断言方法
    private function assert(condition:Boolean, message:String):Void {
        testCount++;
        if (condition) {
            passCount++;
        } else {
            trace("测试失败: " + message);
        }
    }
}
