import org.flashNight.arki.spatial.transform.*;
import org.flashNight.arki.component.Effect.*;
import org.flashNight.sara.util.*;
import flash.geom.*;
import org.flashNight.gesh.object.*;

/**
 * @class org.flashNight.arki.corpse.DeathEffectRenderer
 * @classdesc 处理尸体效果的渲染，包括标准尸体效果与带旋转的尸体效果。
 * 
 * 此类采用对象复用和缓存机制，减少了重复创建矩阵和 ColorTransform 对象的开销。
 * 注意：此类依赖全局对象 _root.gameworld 以及 gameworld.deadbody，
 *       使用时需保证这些全局对象已正确初始化。
 */
class org.flashNight.arki.corpse.DeathEffectRenderer {
    // ------------------ 常量定义 ------------------
    
    /** @private {Number} 暗化因子 */
    private static var DARKEN_FACTOR:Number = 0.3;
    /** @private {Number} 角度转弧度常量（角度 * DEG_TO_RAD = 弧度） */
    private static var DEG_TO_RAD:Number = Math.PI / 180;

    // ------------------ 对象复用及缓存 ------------------
    
    /** @private {Matrix} 可复用的矩阵对象，用于绘制标准尸体效果 */
    private static var reusableMatrix:Matrix = new Matrix();    // 默认 b 和 c 为 0
    /** @private {Matrix} 可复用的矩阵对象，用于计算旋转后的矩阵 */
    private static var reusableTransformMatrix:Matrix = new Matrix();
    /** @private {Object} 缓存暗化 ColorTransform 对象，key 为位运算生成的唯一数字 */
    private static var darkenCTCache:Object = {};

    private static var CORPSE_CULL_PAD:Number = 60; // 适当缓冲，减少边缘误杀
    
    /** @private {Boolean} 是否启用尸体效果渲染 */
    public static var isEnabled:Boolean = true;
    
    /** @private {Boolean} 是否启用离屏剔除优化 */
    public static var enableCulling:Boolean = true;
    
    
    // ------------------ 公共方法 ------------------

    /**
     * 渲染标准尸体效果。
     * 则绘制暗化后的尸体图像。
     *
     * 优化说明：
     *  1. 预先创建 Matrix 对象 reusableMatrix，避免重复 new 操作。
     *  2. 更新 Matrix 对象的属性（a、b、c、d、tx、ty）以反映 target 当前状态。
     *  3. as2 为单线程，因此复用变量无需担忧异步污染
     *
     * @param {MovieClip} target - 目标影片剪辑。
     * @param {Number} layerIndex - 层索引。
     * @return {Void}
     */
    public static function renderCorpse(target:MovieClip, layerIndex:Number):Void {
        //_root.发布消息(DeathEffectRenderer.isEnabled, DeathEffectRenderer.enableCulling)

        if (!DeathEffectRenderer.isEnabled) return;

        var gameWorld:MovieClip = _root.gameworld;

        // 同一个全局点分别转换到 gameWorld(剔除用) 与 deadbody(写 BD 用) 坐标系
        var pt:Object = {x: 0, y: 0};
        target.localToGlobal(pt);
        var layerPt:Object = {x: pt.x, y: pt.y};
        gameWorld.globalToLocal(pt);
        gameWorld.deadbody.globalToLocal(layerPt);

        // 离屏剔除（gameworld 平移+缩放闭式映射）
        if (DeathEffectRenderer.enableCulling) {

            var sx:Number = gameWorld._xscale * 0.01;

            // 局部(世界)中心 → 屏幕坐标
            var gx:Number = gameWorld._x + pt.x * sx;
            var gy:Number = gameWorld._y + pt.y * sx;

            if (gx < -CORPSE_CULL_PAD || gx > Stage.width + CORPSE_CULL_PAD ||
                gy < -CORPSE_CULL_PAD || gy > Stage.height + CORPSE_CULL_PAD) {
                //_root.发布消息("离屏：直接拒绝绘制")
                return; // 离屏：直接拒绝绘制
            }
        }

        // 获取 target 相对于全局的累积缩放
        var accumulatedScaleX:Number = 1;
        var accumulatedScaleY:Number = 1;
        var mc:MovieClip = target;
        while (mc != gameWorld && mc != undefined) {
            accumulatedScaleX *= mc._xscale / 100;
            accumulatedScaleY *= mc._yscale / 100;
            mc = mc._parent;
        }

        reusableMatrix.a  = accumulatedScaleX;
        reusableMatrix.d  = accumulatedScaleY;
        reusableMatrix.tx = layerPt.x;
        reusableMatrix.ty = layerPt.y;

        gameWorld.deadbody.layers[layerIndex].draw(
            target,
            reusableMatrix,
            DeathEffectRenderer.createDarkenCT(target.transform.colorTransform),
            "normal",
            undefined,
            true
        );
    }

    
    /**
     * 渲染带旋转和翻转的尸体效果。
     * 当效果系统处于尸体效果状态时，根据目标影片剪辑的旋转角度、缩放符号（用于翻转）以及全局偏移，
     * 构造一个 2×3 仿射变换矩阵 (Matrix)，再将目标图像绘制到死尸图层上。
     *
     * 矩阵形式（Flash Matrix 内部顺序）：
     *     | a  c  tx |
     * M = | b  d  ty |
     * 
     * 其中 (a, b, c, d) 共同描述旋转 + 翻转（±1）变换，(tx, ty) 描述平移偏移。
     *
     * @param {MovieClip} target - 要渲染的影片剪辑
     * @param {Number} layerIndex - 渲染到的尸体图层索引
     */
    public static function renderRotatedCorpse(target:MovieClip, layerIndex:Number):Void {
        if (!DeathEffectRenderer.isEnabled) return;
        var gameWorld:MovieClip = _root.gameworld;
        var worldPt:Object = {x: 0, y: 0};
        target.localToGlobal(worldPt);
        var layerPt:Object = {x: worldPt.x, y: worldPt.y};
        gameWorld.globalToLocal(worldPt);
        gameWorld.deadbody.globalToLocal(layerPt);

        // 离屏剔除（gameworld 平移+缩放闭式映射）
        if (DeathEffectRenderer.enableCulling) {
            
            var sx:Number = gameWorld._xscale * 0.01;
            // 局部(世界)中心 → 屏幕坐标
            var gx:Number = gameWorld._x + worldPt.x * sx;
            var gy:Number = gameWorld._y + worldPt.y * sx;

            if (gx < -CORPSE_CULL_PAD || gx > Stage.width + CORPSE_CULL_PAD ||
                gy < -CORPSE_CULL_PAD || gy > Stage.height + CORPSE_CULL_PAD) {
                return; // 离屏：直接拒绝绘制
            }
        }

        // 将目标的角度（度）转换为弧度，以便 Math.cos/sin 计算
        var rotationRadians:Number = target._rotation * DEG_TO_RAD;
        // 构造旋转 + 翻转矩阵元素
        // 根据目标的 _xscale 和 _yscale 符号，计算水平/垂直翻转因子 (±1)
        // 1 - 2*(expr) 利用布尔到数值隐式转换：expr 为 true → 1，false → 0
        // signX = +1 表示正常朝向，-1 表示水平翻转
        // signY = +1 表示正常朝向，-1 表示垂直翻转
        // 翻转因子必须绑定到“矩阵列(基底轴)”，而非 cos/sin：
        //   a,b 同属 X 基底列 → 共用 signX；c,d 同属 Y 基底列 → 共用 signY
        // 标准 旋转+翻转 仿射：
        //   a = cosθ·signX —— X 基底变换后的 X 分量
        //   b = sinθ·signX —— X 基底变换后的 Y 分量（与 a 同列，共用 signX）
        //   c = -sinθ·signY —— Y 基底变换后的 X 分量（与 d 同列，共用 signY）
        //   d = cosθ·signY —— Y 基底变换后的 Y 分量（与 c 同列，共用 signY）
        // 旧实现把 signY 错绑到 sin、signX 错绑到 cos：θ≈0 时垂直翻转(signY)被 d=signX 吞掉而失效。
        var cosV:Number = Math.cos(rotationRadians);
        var sinV:Number = Math.sin(rotationRadians);
        var signX:Number = 1 - 2 * (target._xscale < 0); // X 基底列翻转因子
        var signY:Number = 1 - 2 * (target._yscale < 0); // Y 基底列翻转因子

        reusableTransformMatrix.a  =  cosV * signX;
        reusableTransformMatrix.b  =  sinV * signX;
        reusableTransformMatrix.c  = -sinV * signY;
        reusableTransformMatrix.d  =  cosV * signY;
        // 平移分量：目标原点在 deadbody 位图层坐标系中的位置
        reusableTransformMatrix.tx = layerPt.x;
        reusableTransformMatrix.ty = layerPt.y;

        // 将目标 MovieClip 按照计算好的矩阵绘制到指定尸体层
        gameWorld.deadbody.layers[layerIndex].draw(
            target,
            reusableTransformMatrix,
            DeathEffectRenderer.createDarkenCT(target.transform.colorTransform),
            "normal",
            undefined,
            true
        );
    }

    
    
    // ------------------ 私有工具方法 ------------------

    /**
     * 根据原始 ColorTransform 快速生成暗化版的 ColorTransform 并进行缓存。
     * 使用一次性位运算构造唯一数字 key，避免字符串拼接带来的开销。
     * 假设 multiplier*100 后值在 0..65535 范围内，offset 在 -32768..32767 范围内。
     *
     * @param {ColorTransform} originalCT - 原始 ColorTransform 对象。
     * @return {ColorTransform} 暗化版 ColorTransform 对象。
     * @private
     */
    private static function createDarkenCT(originalCT:ColorTransform):ColorTransform {
        var key:Number = (
            ((((originalCT.redMultiplier   * 100) & 0xFFFF) << 16) | ((originalCT.greenMultiplier * 100) & 0xFFFF))
            ^ ((((originalCT.blueMultiplier  * 100) & 0xFFFF) << 16) | ((originalCT.alphaMultiplier * 100) & 0xFFFF))
            ^ ((originalCT.redOffset   + 32768) & 0xFFFF)
            ^ (((originalCT.greenOffset + 32768) & 0xFFFF) << 16)
            ^ (((originalCT.blueOffset  + 32768) & 0xFFFF) << 8)
            ^ (((originalCT.alphaOffset + 32768) & 0xFFFF) << 24)
        );

        if (darkenCTCache[key] != undefined) {
            return darkenCTCache[key];
        }

        return darkenCTCache[key] = new ColorTransform(
            originalCT.redMultiplier   - DARKEN_FACTOR,
            originalCT.greenMultiplier - DARKEN_FACTOR,
            originalCT.blueMultiplier  - DARKEN_FACTOR,
            originalCT.alphaMultiplier,
            originalCT.redOffset,
            originalCT.greenOffset,
            originalCT.blueOffset,
            originalCT.alphaOffset
        );
    }
}
