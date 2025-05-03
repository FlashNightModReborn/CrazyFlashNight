import org.flashNight.sara.util.*;
import org.flashNight.arki.spatial.move.*;
import org.flashNight.arki.spatial.transform.*;

/**
 * Mover 测试套件（AS2 示例）
 * =============================
 *
 * 主要功能：
 *  1. 初始化假数据，模拟游戏世界与地图碰撞区域
 *  2. 测试 move2D 与 move25D 的各种移动场景（无碰撞、边界碰撞、挤出处理等）
 *  3. 测试 SceneCoordinateManager 计算中心点和安全半径是否正确
 *  4. 评估移动逻辑的性能（循环多次调用并记录耗时）
 *
 * 使用方法：
 *  1. 在需要的地方执行 MoverTestSuite.runAllTests()
 *  2. 查看输出日志，检查断言与性能数据
 */
class org.flashNight.arki.spatial.move.MoverTestSuite {

    // 模拟的游戏世界
    private static var gameworld:MovieClip;
    // 模拟的地图 MovieClip
    private static var map:MovieClip;
    // 测试用实体
    private static var entity:MovieClip;

    // 用于性能测试的计时
    private static var startTime:Number;
    private static var endTime:Number;

    /**
     * 断言函数
     * 当 condition 为 false 时，输出断言失败信息
     */
    private static function assert(condition:Boolean, message:String):Void {
        if (!condition) {
            trace("断言失败: " + message);
        } else {
            trace("断言通过: " + message);
        }
    }

    /**
     * 初始化测试环境：
     *  - 创建 gameworld 与 map
     *  - 绘制碰撞区域
     *  - 构造测试实体
     *  - 调用 SceneCoordinateManager.update 与 Mover.init
     */
    private static function initEnvironment():Void {
        // 创建 gameworld
        gameworld = _root.createEmptyMovieClip("gameworld", _root.getNextHighestDepth());
        gameworld._x = 0;
        gameworld._y = 0;

        // 创建地图
        map = gameworld.createEmptyMovieClip("地图", gameworld.getNextHighestDepth());
        map._x = 0;
        map._y = 0;

        // 绘制地图碰撞区域
        drawCollisionBoundary();

        // 创建用于测试的实体
        entity = gameworld.createEmptyMovieClip("testEntity", gameworld.getNextHighestDepth());
        entity._x = 200;
        entity._y = 200;
        entity.Z轴坐标 = 200;
        entity.起始Y = 200;

        // 更新场景坐标管理器
        SceneCoordinateManager.update();

        // 初始化 Mover (只需执行一次)
        if(!Mover.initTag) {
            Mover.init();
        }
    }

    /**
     * 绘制一个简单的碰撞区域，用于模拟地图边界 (Xmin=50, Xmax=550, Ymin=50, Ymax=350)
     * 并设置全局 _root 的 X/Y 边界值，以便 Mover 和 SceneCoordinateManager 正确工作
     */
    private static function drawCollisionBoundary():Void {
        var margin:Number = 300;
        var xmin:Number = 50;
        var xmax:Number = 550;
        var ymin:Number = 50;
        var ymax:Number = 350;

        // 设置全局边界参数
        _root.Xmin = xmin;
        _root.Xmax = xmax;
        _root.Ymin = ymin;
        _root.Ymax = ymax;

        // 在 map 上绘制一个中空矩形，用于碰撞检测
        map.lineStyle(2, 0xFF0000, 100); // 红色边线
        map.beginFill(0x66CC66, 100);    // 半透明绿色填充

        // 外框（顺时针）
        map.moveTo(xmin - margin, ymin - margin);
        map.lineTo(xmax + margin, ymin - margin);
        map.lineTo(xmax + margin, ymax + margin);
        map.lineTo(xmin - margin, ymax + margin);
        map.lineTo(xmin - margin, ymin - margin);

        // 内框（逆时针，形成中空区域）
        map.moveTo(xmin, ymin);
        map.lineTo(xmin, ymax);
        map.lineTo(xmax, ymax);
        map.lineTo(xmax, ymin);
        map.lineTo(xmin, ymin);

        map.endFill();
    }

    /**
     * 测试：校验 SceneCoordinateManager 计算中心点和安全半径是否正确
     */
    private static function testSceneCoordinateManager():Void {
        trace("== 测试 SceneCoordinateManager ==");

        // 由绘制区域可知：Xmin=50, Xmax=550, Ymin=50, Ymax=350
        // => centerX = (50+550)/2 = 300, centerY = (50+350)/2=200
        // => safeRadius = min(550-50, 350-50)/2 = min(500,300)/2=150
        SceneCoordinateManager.update();

        var center:Vector = SceneCoordinateManager.center;
        var radius:Number = SceneCoordinateManager.safeRadius;

        assert(Math.abs(center.x - 300) < 0.01, "场景中心 X 坐标应为 300");
        assert(Math.abs(center.y - 200) < 0.01, "场景中心 Y 坐标应为 200");
        assert(Math.abs(radius - 150) < 0.01, "安全半径应为 150");
    }

    /**
     * 测试：move2D - 无碰撞移动
     */
    private static function testMove2D_NoCollision():Void {
        trace("== 测试 move2D (无碰撞) ==");

        // 放在中间位置，确保不会撞到边界
        entity._x = 300;
        entity._y = 200;
        entity.Z轴坐标 = 200;

        var initX:Number = entity._x;
        var initY:Number = entity._y;

        // 向右移动 50，确认坐标变化正确
        Mover.move2D(entity, "右", 50);

        assert(Math.abs(entity._x - (initX + 50)) < 0.01, "move2D: X 坐标应增加 50");
        assert(Math.abs(entity._y - initY) < 0.01,        "move2D: Y 坐标应保持不变");
    }

    /**
     * 测试：move2D - 边界碰撞挤出
     */
    private static function testMove2D_Collision():Void {
        trace("== 测试 move2D (碰撞挤出) ==");

        // 放置在离左边界 X=50 很近的地方 (X=60)
        entity._x = 60;
        entity._y = 200;
        entity.Z轴坐标 = 200;

        // 向左移动 30，会超出边界到 X=30，应该被挤回 >= 50
        Mover.move2D(entity, "左", 30);

        assert(entity._x >= 50, "move2D: 碰撞后 X 坐标应被挤回到不小于 50");
    }

    /**
     * 测试：move25D - 无碰撞跳跃移动
     */
    private static function testMove25D_NoCollision():Void {
        trace("== 测试 move25D (无碰撞) ==");

        // 放在中间位置
        entity._x = 300;
        entity._y = 200;
        entity.Z轴坐标 = 200;

        var initX:Number = entity._x;
        var initY:Number = entity._y;
        var initZ:Number = entity.Z轴坐标;

        // 向上移动 2.5D 30，会改变 Y、Z 坐标
        Mover.move25D(entity, "上", 30);

        assert(Math.abs(entity._x - initX) < 0.01,             "move25D: X 坐标不变");
        assert(Math.abs(entity._y - (initY - 30)) < 0.01,      "move25D: Y 坐标应减少 30");
        assert(Math.abs(entity.Z轴坐标 - (initZ - 30)) < 0.01, "move25D: Z轴坐标应减少 30");
    }

    /**
     * 测试：move25D - 边界碰撞挤出
     */
    private static function testMove25D_Collision():Void {
        trace("== 测试 move25D (碰撞挤出) ==");

        // 放置在离上边界 Y=50 很近的地方 (Y=60)
        entity._x = 300;
        entity._y = 60;
        entity.Z轴坐标 = 60;

        // 继续向上移动 30，会超出 Y=30，应该被挤回 >= 50
        Mover.move25D(entity, "上", 30);

        assert(entity._y >= 50,           "move25D: 碰撞后 Y 坐标应被挤回到不小于 50");
        assert(entity.Z轴坐标 >= 50,     "move25D: 碰撞后 Z轴坐标应被挤回到不小于 50");
    }

    /**
     * 增强版性能测试：对move2D与move25D进行全面的性能评估
     * 
     * 本方法解决了原有测试中的几个问题：
     * 1. 消除了hitTest缓存初始化的影响（通过预热）
     * 2. 分别测试不同移动场景（无碰撞区域和碰撞区域）
     * 3. 交换测试顺序，避免固定顺序带来的偏差
     * 4. 重置实体位置，确保每次测试的起始条件一致
     * 5. 多次重复测试，计算平均值和标准差
     */
    private static function testPerformance():Void {
        trace("== 增强版性能测试 (move2D / move25D) ==");
        
        var iterations:Number = 10000;    // 每次测试的迭代次数
        var repeats:Number = 50;          // 重复测试次数，用于计算平均值
        var warmupIterations:Number = 200; // 预热迭代次数
        
        // 缓存外部引用，减少属性查找开销
        var gameMap:MovieClip = _root.gameworld.地图;
        var move2D:Function = Mover.move2D;
        var move25D:Function = Mover.move25D;
        
        // 记录测试结果
        var results:Object = {
            move2D_无碰撞: new Array(repeats),
            move25D_无碰撞: new Array(repeats),
            move2D_边界碰撞: new Array(repeats),
            move25D_边界碰撞: new Array(repeats),
            move2D_先测: new Array(repeats),
            move25D_先测: new Array(repeats)
        };
        
        // 测试场景1：无碰撞区域移动
        trace("-- 场景1: 无碰撞区域移动 --");
        for (var r:Number = 0; r < repeats; r++) {
            // 重置实体位置到安全区域中央
            resetEntityPosition(300, 200);
            
            // 预热 - 两种方法都预热，丢弃结果
            warmupBothMethods(warmupIterations);
            
            // 测试move2D - 无碰撞
            resetEntityPosition(300, 200);
            var startT:Number = getTimer();
            for (var i:Number = 0; i < iterations; i++) {
                move2D(entity, "右", 2);
                // 每100次迭代重置位置，避免碰到边界
                if (i % 100 == 0) resetEntityPosition(300, 200);
            }
            var endT:Number = getTimer();
            results["move2D_无碰撞"][r] = endT - startT;
            
            // 测试move25D - 无碰撞
            resetEntityPosition(300, 200);
            startT = getTimer();
            for (i = 0; i < iterations; i++) {
                move25D(entity, "右", 2);
                // 每100次迭代重置位置，避免碰到边界
                if (i % 100 == 0) resetEntityPosition(300, 200);
            }
            endT = getTimer();
            results["move25D_无碰撞"][r] = endT - startT;
        }
        
        // 测试场景2：边界碰撞移动
        trace("-- 场景2: 边界碰撞移动 --");
        for (r = 0; r < repeats; r++) {
            // 重置实体位置到边界附近
            resetEntityPosition(60, 60);
            
            // 预热 - 两种方法都预热，丢弃结果
            warmupBothMethods(warmupIterations);
            
            // 测试move2D - 边界碰撞
            resetEntityPosition(60, 60);
            startT = getTimer();
            for (i = 0; i < iterations; i++) {
                move2D(entity, "左", 2);
                // 每20次迭代重置位置，保持在边界附近
                if (i % 20 == 0) resetEntityPosition(60, 60);
            }
            endT = getTimer();
            results["move2D_边界碰撞"][r] = endT - startT;
            
            // 测试move25D - 边界碰撞
            resetEntityPosition(60, 60);
            startT = getTimer();
            for (i = 0; i < iterations; i++) {
                move25D(entity, "左", 2);
                // 每20次迭代重置位置，保持在边界附近
                if (i % 20 == 0) resetEntityPosition(60, 60);
            }
            endT = getTimer();
            results["move25D_边界碰撞"][r] = endT - startT;
        }
        
        // 测试场景3：交替测试顺序（先测试25D，后测试2D）
        trace("-- 场景3: 交替测试顺序 --");
        for (r = 0; r < repeats; r++) {
            // 重置环境，移除所有缓存
            resetTestEnvironment();
            
            // 预热 - 只预热move25D
            resetEntityPosition(300, 200);
            for (i = 0; i < warmupIterations; i++) {
                move25D(entity, "右", 2);
                if (i % 50 == 0) resetEntityPosition(300, 200);
            }
            
            // 先测试move25D
            resetEntityPosition(300, 200);
            startT = getTimer();
            for (i = 0; i < iterations; i++) {
                move25D(entity, "右", 2);
                if (i % 100 == 0) resetEntityPosition(300, 200);
            }
            endT = getTimer();
            results["move25D_先测"][r] = endT - startT;
            
            // 再测试move2D
            resetEntityPosition(300, 200);
            startT = getTimer();
            for (i = 0; i < iterations; i++) {
                move2D(entity, "右", 2);
                if (i % 100 == 0) resetEntityPosition(300, 200);
            }
            endT = getTimer();
            results["move2D_先测"][r] = endT - startT;
        }
        
        // 计算并输出结果
        outputResults(results, iterations, repeats);
    }

    /**
     * 重置实体位置
     */
    private static function resetEntityPosition(x:Number, y:Number):Void {
        entity._x = x;
        entity._y = y;
        entity.Z轴坐标 = y;
        entity.起始Y = y;
        
        // 更新碰撞器
        if (entity.aabbCollider) {
            entity.aabbCollider.updateFromUnitArea(entity);
        }
    }

    /**
     * 预热两种移动方法
     */
    private static function warmupBothMethods(iterations:Number):Void {
        // 预热move2D
        for (var i:Number = 0; i < iterations; i++) {
            Mover.move2D(entity, "右", 1);
            if (i % 50 == 0) resetEntityPosition(300, 200);
        }
        
        // 预热move25D
        resetEntityPosition(300, 200);
        for (i = 0; i < iterations; i++) {
            Mover.move25D(entity, "右", 1);
            if (i % 50 == 0) resetEntityPosition(300, 200);
        }
    }

    /**
     * 重置测试环境，清除缓存
     */
    private static function resetTestEnvironment():Void {
        // 重新初始化环境
        initEnvironment();
        
        // 强制重新渲染地图以清除hitTest缓存
        map.clear();
        drawCollisionBoundary();
    }

    /**
     * 计算并输出测试结果
     */
    private static function outputResults(results:Object, iterations:Number, repeats:Number):Void {
        var categories:Array = [
            "move2D_无碰撞", "move25D_无碰撞", 
            "move2D_边界碰撞", "move25D_边界碰撞",
            "move2D_先测", "move25D_先测"
        ];
        
        trace("\n== 性能测试结果汇总 ==");
        trace("每项测试包含 " + iterations + " 次迭代，重复 " + repeats + " 次");
        
        // 计算每个类别的平均值和标准差
        for (var c:Number = 0; c < categories.length; c++) {
            var category:String = categories[c];
            var data:Array = results[category];
            
            // 计算平均值
            var sum:Number = 0;
            for (var i:Number = 0; i < data.length; i++) {
                sum += data[i];
            }
            var avg:Number = sum / data.length;
            
            // 计算标准差
            var sumSq:Number = 0;
            for (i = 0; i < data.length; i++) {
                var diff:Number = data[i] - avg;
                sumSq += diff * diff;
            }
            var stdDev:Number = Math.sqrt(sumSq / data.length);
            
            // 输出结果
            trace(category + "：平均 " + Math.round(avg) + " ms，标准差 " + 
                Math.round(stdDev) + " ms，详细数据：" + data.join(", "));
        }
        
        // 计算并输出直接比较
        var move2D_avg:Number = average(results["move2D_无碰撞"]);
        var move25D_avg:Number = average(results["move25D_无碰撞"]);
        trace("\n无碰撞场景比较：move25D 是 move2D 的 " + 
            Math.round((move2D_avg / move25D_avg) * 100) / 100 + " 倍速度");
        
        var move2D_coll_avg:Number = average(results["move2D_边界碰撞"]);
        var move25D_coll_avg:Number = average(results["move25D_边界碰撞"]);
        trace("边界碰撞场景比较：move25D 是 move2D 的 " + 
            Math.round((move2D_coll_avg / move25D_coll_avg) * 100) / 100 + " 倍速度");
        
        var move2D_after_avg:Number = average(results["move2D_先测"]);
        var move25D_first_avg:Number = average(results["move25D_先测"]);
        trace("交替顺序比较（25D先测）：move25D 是 move2D 的 " + 
            Math.round((move2D_after_avg / move25D_first_avg) * 100) / 100 + " 倍速度");
    }

    /**
     * 计算数组平均值
     */
    private static function average(arr:Array):Number {
        var sum:Number = 0;
        for (var i:Number = 0; i < arr.length; i++) {
            sum += arr[i];
        }
        return sum / arr.length;
    }

    /**
     * 运行所有测试
     */
    public static function runAllTests():Void {
        trace("========== 开始运行 Mover 测试套件 ==========");
        initEnvironment();

        // 1. 测试场景坐标管理器
        testSceneCoordinateManager();

        // 2. 测试 move2D 无碰撞与碰撞挤出
        testMove2D_NoCollision();
        testMove2D_Collision();

        // 3. 测试 move25D 无碰撞与碰撞挤出
        testMove25D_NoCollision();
        testMove25D_Collision();

        // 4. 性能评估
        testPerformance();

        trace("========== 所有测试完成！ ==========");
    }
}
