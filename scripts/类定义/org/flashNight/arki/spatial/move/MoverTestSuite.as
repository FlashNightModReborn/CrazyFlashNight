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
     * 性能测试：循环多次调用 move2D 与 move25D
     * 记录总耗时，用于后续做性能对比
     */
    private static function testPerformance():Void {
        trace("== 测试性能 (move2D / move25D) ==");

        var iterations:Number = 2000;
        var i:Number;

        // 先测试 move2D 性能
        var startT:Number = getTimer();
        for (i = 0; i < iterations; i++) {
            Mover.move2D(entity, "右", 2);
        }
        var endT:Number = getTimer();
        trace("move2D - " + iterations + " 次调用总耗时: " + (endT - startT) + " ms");

        // 再测试 move25D 性能
        startT = getTimer();
        for (i = 0; i < iterations; i++) {
            Mover.move25D(entity, "上", 2);
        }
        endT = getTimer();
        trace("move25D - " + iterations + " 次调用总耗时: " + (endT - startT) + " ms");
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
