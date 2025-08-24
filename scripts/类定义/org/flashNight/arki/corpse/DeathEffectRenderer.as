import org.flashNight.arki.spatial.transform.*;
import org.flashNight.arki.component.Effect.*;
import org.flashNight.sara.util.*;
import flash.geom.*;

/**
 * @class org.flashNight.arki.corpse.DeathEffectRenderer
 * @classdesc 处理尸体效果的渲染，包括标准尸体效果与带旋转的尸体效果。
 * 
 * 此类采用对象复用和缓存机制，减少了重复创建矩阵和 ColorTransform 对象的开销。
 * 注意：此类依赖全局对象 _root.gameworld 以及 SceneCoordinateManager.effectOffset，
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
        if (!EffectSystem.isDeathEffect) return;

        // 离屏剔除（gameworld 平移+缩放闭式映射）

        var gameWorld:MovieClip = _root.gameworld;
        var sx:Number = gameWorld._xscale * 0.01;
        var off:Vector = SceneCoordinateManager.effectOffset;

        // 局部(世界)中心 → 屏幕坐标
        var gx:Number = gameWorld._x + (target._x + off.x) * sx;
        var gy:Number = gameWorld._y + (target._y + off.y) * sx;

        if (gx < -CORPSE_CULL_PAD || gx > Stage.width + CORPSE_CULL_PAD ||
            gy < -CORPSE_CULL_PAD || gy > Stage.height + CORPSE_CULL_PAD) {
            return; // 离屏：直接拒绝绘制
        }

        var effectOffset:Vector = SceneCoordinateManager.effectOffset;

        reusableMatrix.a  = target._xscale / 100;
        reusableMatrix.d  = target._yscale / 100;
        reusableMatrix.tx = target._x + effectOffset.x;
        reusableMatrix.ty = target._y + effectOffset.y;

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
        if (!EffectSystem.isDeathEffect) return;

        // 离屏剔除（gameworld 平移+缩放闭式映射）
        var gameWorld:MovieClip = _root.gameworld;
        var sx:Number = gameWorld._xscale * 0.01;
        var off:Vector = SceneCoordinateManager.effectOffset;

        // 局部(世界)中心 → 屏幕坐标
        var gx:Number = gameWorld._x + (target._x + off.x) * sx;
        var gy:Number = gameWorld._y + (target._y + off.y) * sx;

        if (gx < -CORPSE_CULL_PAD || gx > Stage.width + CORPSE_CULL_PAD ||
            gy < -CORPSE_CULL_PAD || gy > Stage.height + CORPSE_CULL_PAD) {
            return; // 离屏：直接拒绝绘制
        }

        // 将目标的角度（度）转换为弧度，以便 Math.cos/sin 计算
        var rotationRadians:Number = target._rotation * DEG_TO_RAD;
        // 全局效果偏移量，用于解决效果与尸体层的偏移问题
        var offset:Vector = SceneCoordinateManager.effectOffset;

        // 构造旋转 + 翻转矩阵元素
        // 根据目标的 _xscale 和 _yscale 符号，计算水平/垂直翻转因子 (±1)
        // 1 - 2*(expr) 利用布尔到数值隐式转换：expr 为 true → 1，false → 0
        // signX = +1 表示正常朝向，-1 表示水平翻转
        // signY = +1 表示正常朝向，-1 表示垂直翻转
        // a = cosθ * signX —— X 轴单位向量在变换后的 X 分量
        // b = sinθ * signY —— X 轴单位向量在变换后的 Y 分量
        // c = -sinθ * signY —— Y 轴单位向量在变换后的 X 分量（与 b 对称取负）
        // d = cosθ * signX —— Y 轴单位向量在变换后的 Y 分量（与 a 对称）
        var r_cos:Number = Math.cos(rotationRadians) * (1 - 2 * (target._xscale < 0));
        var r_sin:Number = Math.sin(rotationRadians) * (1 - 2 * (target._yscale < 0));

        reusableTransformMatrix.a  = r_cos;
        reusableTransformMatrix.b  = r_sin;
        reusableTransformMatrix.c  = -r_sin;
        reusableTransformMatrix.d  = r_cos;
        // 平移分量：目标坐标 + 全局偏移
        reusableTransformMatrix.tx = target._x + offset.x;
        reusableTransformMatrix.ty = target._y + offset.y;

        // 将目标 MovieClip 按照计算好的矩阵绘制到指定尸体层
        _root.gameworld.deadbody.layers[layerIndex].draw(
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
