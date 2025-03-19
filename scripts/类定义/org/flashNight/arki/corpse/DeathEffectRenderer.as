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
    /** @private {Number} 最小缩放比例 */
    private static var MIN_SCALE:Number = 0.5;
    /** @private {Number} 角度转弧度常量（角度 * DEG_TO_RAD = 弧度） */
    private static var DEG_TO_RAD:Number = Math.PI / 180;

    // ------------------ 对象复用及缓存 ------------------
    
    /** @private {Matrix} 可复用的矩阵对象，用于绘制标准尸体效果 */
    private static var reusableMatrix:Matrix = new Matrix();
    /** @private {Matrix} 可复用的矩阵对象，用于计算旋转后的矩阵 */
    private static var reusableTransformMatrix:Matrix = new Matrix();
    /** @private {Object} 缓存暗化 ColorTransform 对象，key 为位运算生成的唯一数字 */
    private static var darkenCTCache:Object = {};
    
    
    // ------------------ 公共方法 ------------------

    /**
     * 渲染标准尸体效果。
     * 先清除目标影片剪辑中的旧标志与文字，若效果系统处于尸体效果状态，
     * 则绘制暗化后的尸体图像。
     *
     * @param {MovieClip} target - 目标影片剪辑。
     * @param {Number} layerIndex - 层索引。
     * @return {Void}
     */
    public static function renderCorpse(target:MovieClip, layerIndex:Number):Void {
        // 清除旧的标志与文字
        DeathEffectRenderer.clearLegacyClips(target);
        if (!EffectSystem.isDeathEffect) return;
        DeathEffectRenderer.drawDarkenedBody(target, layerIndex);
    }
    
    /**
     * 渲染带旋转的尸体效果。
     * 当效果系统处于尸体效果状态时，根据目标影片剪辑的旋转与缩放状态，
     * 计算旋转矩阵，并绘制旋转后的尸体。
     *
     * @param {MovieClip} target - 目标影片剪辑。
     * @param {Number} layerIndex - 层索引。
     * @return {Void}
     */
    public static function renderRotatedCorpse(target:MovieClip, layerIndex:Number):Void {
        if (!EffectSystem.isDeathEffect) return;
        
        _root.gameworld.deadbody.layers[layerIndex].draw(
            target,
            DeathEffectRenderer.calculateTransform(target),
            DeathEffectRenderer.createDarkenCT(target.transform.colorTransform),
            "normal",
            undefined,
            true
        );
    }
    
    
    // ------------------ 私有工具方法 ------------------

    /**
     * 清除目标影片剪辑中的旧标志和文字。
     * 当前仅处理 ["人物文字信息", "新版人物文字信息"] 两种标识。
     *
     * @param {MovieClip} target - 目标影片剪辑。
     * @return {Void}
     * @private
     */
    private static function clearLegacyClips(target:MovieClip):Void {
        // 旧版代码示例（可能包含其他标志）： 
        // var clips:Array = ["暴走标志", "远古标志", "亚种标志", "人物文字信息", "新版人物文字信息"];
        var clips:Array = ["人物文字信息", "新版人物文字信息"];
        for (var i:Number = 0; i < clips.length; i++) {
            if (target[clips[i]]) {
                target[clips[i]].removeMovieClip();
            }
        }
    }
    
    /**
     * 根据目标影片剪辑及其位置，绘制暗化后的尸体。
     * 利用复用的 Matrix 对象减少内存分配，每次调用前更新矩阵属性。
     *
     * 优化说明：
     *  1. 预先创建 Matrix 对象 reusableMatrix，避免重复 new 操作。
     *  2. 更新 Matrix 对象的属性（a、b、c、d、tx、ty）以反映 target 当前状态。
     *  3. 此方法适用于单线程同步调用，如 draw() 内部异步存储传入矩阵引用则需谨慎。
     *
     * @param {MovieClip} target - 目标影片剪辑。
     * @param {Number} layerIndex - 层索引。
     * @return {Void}
     * @private
     */
    private static function drawDarkenedBody(target:MovieClip, layerIndex:Number):Void {
        var gameWorld:MovieClip = _root.gameworld;
        var effectOffset:Vector = SceneCoordinateManager.effectOffset;
        
        // 更新 reusableMatrix 的属性
        reusableMatrix.a  = target._xscale / 100;
        reusableMatrix.b  = 0;
        reusableMatrix.c  = 0;
        reusableMatrix.d  = target._yscale / 100;
        reusableMatrix.tx = target._x + effectOffset.x;
        reusableMatrix.ty = target._y + effectOffset.y;
        
        // 使用更新后的矩阵绘制暗化尸体
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
     * 播放尸体消失特效。
     * 将全局坐标转换为局部坐标后，触发效果系统的“尸体消失”特效。
     *
     * @param {Object} pos - 包含 x 和 y 属性的位置对象。
     * @return {Void}
     * @private
     */
    private static function playDisappearEffect(pos:Object):Void {
        var gameWorld:MovieClip = _root.gameworld;
        gameWorld.效果.globalToLocal(pos);
        EffectSystem.Effect("尸体消失", pos.x, pos.y, 100);
    }
    
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
    
    /**
     * 根据目标影片剪辑计算旋转后的矩阵。
     * 利用复用的 Matrix 对象 reusableTransformMatrix，计算旋转角度、正弦余弦及缩放比例，
     * 并确保缩放不低于最小值 MIN_SCALE。
     *
     * 计算过程：
     *   - theta = target._rotation * DEG_TO_RAD
     *   - cosTheta = Math.cos(theta)
     *   - sinTheta = Math.sin(theta)
     *   - scaleX = max(|target._xscale| / 100, MIN_SCALE)
     *   - scaleY = max(|target._yscale| / 100, MIN_SCALE)
     *   - 矩阵各元素：
     *         a = cosTheta * scaleX
     *         b = sinTheta * scaleY
     *         c = -sinTheta * scaleX
     *         d = cosTheta * scaleY
     *         tx = target._x + offset.x
     *         ty = target._y + offset.y
     *
     * @param {MovieClip} target - 目标影片剪辑。
     * @return {Matrix} 计算后的旋转矩阵。
     * @private
     */
    private static function calculateTransform(target:MovieClip):Matrix {
        var theta:Number = target._rotation * DEG_TO_RAD;
        var offset:Vector = SceneCoordinateManager.effectOffset;
        var cosTheta:Number = Math.cos(theta);
        var sinTheta:Number = Math.sin(theta);
        var scaleX:Number = Math.max(Math.abs(target._xscale) / 100, MIN_SCALE);
        var scaleY:Number = Math.max(Math.abs(target._yscale) / 100, MIN_SCALE);
        
        reusableTransformMatrix.a  = cosTheta * scaleX;
        reusableTransformMatrix.b  = sinTheta * scaleY;
        reusableTransformMatrix.c  = -sinTheta * scaleX;
        reusableTransformMatrix.d  = cosTheta * scaleY;
        reusableTransformMatrix.tx = target._x + offset.x;
        reusableTransformMatrix.ty = target._y + offset.y;

        return reusableTransformMatrix;
    }
}
