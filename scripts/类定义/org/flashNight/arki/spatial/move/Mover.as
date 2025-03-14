import org.flashNight.sara.util.*;
import org.flashNight.arki.spatial.transform.SceneCoordinateManager;

/**
 * org.flashNight.arki.spatial.move.Mover
 * 
 * 提供统一的移动工具方法：
 * - move2D：处理纯 2D 移动
 * - move25D：处理带高度变化的 2.5D 移动（例如跳跃、浮空等）
 *
 * 优化说明：
 * 1. 将方向向量提前定义为静态属性，避免每次调用时重复创建。
 * 2. 利用 SceneCoordinateManager.getOffset() 获取全局偏移量，减少局部与全局坐标转换的开销。
 * 3. 内部采用静态临时变量复用 Vector 和 Vertex3D 对象，减少垃圾对象产生。
 */
class org.flashNight.arki.spatial.move.Mover {
    
    // --------------------
    // 静态方向向量（2D）—仅包含 dx, dy
    private static var directions2D:Object = {
        "上":  { dx: 0, dy: -1 },
        "下":  { dx: 0, dy:  1 },
        "左":  { dx: -1, dy: 0 },
        "右":  { dx: 1, dy: 0 }
    };

    // 静态方向向量（2.5D）—包含 dx, dy, dz（跳跃时 dz 有效）
    // 注意：这里保存的是基础值，调用时根据 isJump 参数决定是否采用 dz
    private static var directions25D:Object = {
        "上":  { dx: 0, dy: -1, dz: -1 },
        "下":  { dx: 0, dy:  1, dz:  1 },
        "左":  { dx: -1, dy: 0, dz: 0 },
        "右":  { dx: 1, dy: 0, dz: 0 }
    };

    // --------------------
    // 静态临时变量，复用以减少对象创建（2D部分）
    private static var tmpCurrent2D:Vector = new Vector(0, 0);
    private static var tmpDelta2D:Vector = new Vector(0, 0);
    private static var tmpTarget2D:Vector = new Vector(0, 0);
    // 用于存放全局坐标（对象字面量形式）
    private static var tmpGlobal:Object = { x: 0, y: 0 };

    // 静态临时变量（2.5D部分）
    private static var tmpCurrent3D:Vertex3D = new Vertex3D(0, 0, 0);
    private static var tmpDelta3D:Vertex3D = new Vertex3D(0, 0, 0);
    private static var tmpTarget3D:Vertex3D = new Vertex3D(0, 0, 0);

    /**
     * 纯 2D 移动（无高度变化），内部使用 Vector 计算
     * @param entity    要移动的 MovieClip 对象
     * @param direction 移动方向，字符串（如 "上", "下", "左", "右"）
     * @param speed     移动速度
     */
    public static function move2D(entity:MovieClip, direction:String, speed:Number):Void {
        // 读取当前2D坐标到复用的临时变量
        tmpCurrent2D.setTo(entity._x, entity._y);

        // 根据方向字符串获取对应的基础方向向量
        var dir:Object = directions2D[direction];
        if (!dir) { return; }  // 无效方向则直接返回

        // 计算增量：dx * speed, dy * speed
        tmpDelta2D.setTo(dir.dx * speed, dir.dy * speed);
        // 计算目标坐标 = 当前坐标 + 增量
        tmpTarget2D.setTo(tmpCurrent2D.x + tmpDelta2D.x, tmpCurrent2D.y + tmpDelta2D.y);

        // 利用 SceneCoordinateManager 获得偏移量（全局校正）
        var offset:Vector = SceneCoordinateManager.getOffset();
        tmpGlobal.x = tmpTarget2D.x + offset.x;
        tmpGlobal.y = tmpTarget2D.y + offset.y;
        
        // 如果目标位置未发生碰撞，则更新 entity 坐标
        if (!_root.gameworld.地图.hitTest(tmpGlobal.x, tmpGlobal.y, true)) {
            entity._x = tmpTarget2D.x;
            entity._y = tmpTarget2D.y;
        }
    }

    /**
     * 2.5D 移动（带高度变化），内部使用 Vertex3D 进行计算
     * @param entity    要移动的 MovieClip 对象，需有代表高度的属性（例如 Z轴坐标）
     * @param direction 移动方向，字符串（如 "上", "下", "左", "右"）
     * @param speed     移动速度
     * @param isJump    是否处于跳跃/高度变化状态，true 表示需要更新高度
     */
    public static function move25D(entity:MovieClip, direction:String, speed:Number, isJump:Boolean):Void {
        // 读取当前3D坐标到临时变量（假设 entity.Z轴坐标 为高度属性）
        tmpCurrent3D.setTo(entity._x, entity._y, entity.Z轴坐标);

        // 获取基础方向向量（2.5D）
        var baseDir:Object = directions25D[direction];
        if (!baseDir) { return; }
        // 根据 isJump 判断是否应用 dz（非跳跃时 dz = 0）
        var dz:Number = (isJump ? baseDir.dz : 0);

        // 计算增量向量（3D）
        tmpDelta3D.setTo(baseDir.dx * speed, baseDir.dy * speed, dz * speed);
        // 计算目标3D坐标 = 当前坐标 + 增量
        tmpTarget3D.setTo(tmpCurrent3D.x + tmpDelta3D.x, tmpCurrent3D.y + tmpDelta3D.y, tmpCurrent3D.z + tmpDelta3D.z);

        // 利用 SceneCoordinateManager 获得偏移量，只对 x,y 进行全局校正
        var offset:Vector = SceneCoordinateManager.getOffset();
        tmpGlobal.x = tmpTarget3D.x + offset.x;
        tmpGlobal.y = tmpTarget3D.y + offset.y;

        // 如果目标位置未发生碰撞，则更新 entity 坐标和高度，并同步显示层级
        if (!_root.gameworld.地图.hitTest(tmpGlobal.x, tmpGlobal.y, true)) {
            entity._x = tmpTarget3D.x;
            entity._y = tmpTarget3D.y;
            entity.Z轴坐标 = tmpTarget3D.z;
            entity.swapDepths(entity._y);
        }
    }
}
