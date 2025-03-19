import org.flashNight.arki.spatial.transform.*;
import org.flashNight.arki.component.Effect.*;
import org.flashNight.sara.util.*;
import flash.geom.*;

class org.flashNight.arki.corpse.DeathEffectRenderer {
    // 常量定义
    private static var DARKEN_FACTOR:Number = 0.3;
    private static var MIN_SCALE:Number = 0.5;
    
    /**
     * 渲染尸体效果（标准）
     * @param target 目标影片剪辑
     * @param layerIndex 层索引
     */
    public static function renderCorpse(target:MovieClip, layerIndex:Number):Void {
        // 清除旧的标志与文字
        DeathEffectRenderer.clearLegacyClips(target);
        if (!EffectSystem.isDeathEffect) return;
        
        var renderPos:Object = DeathEffectRenderer.calculateGlobalPosition(target);
        DeathEffectRenderer.drawDarkenedBody(target, layerIndex, renderPos);

        /*
        if (_root.血腥开关) {
            DeathEffectRenderer.drawDarkenedBody(target, layerIndex, renderPos);
        } else {
            DeathEffectRenderer.playDisappearEffect(renderPos);
        }
        */
    }
    
    /**
     * 渲染带旋转的尸体效果
     * @param target 目标影片剪辑
     * @param layerIndex 层索引
     */
    public static function renderRotatedCorpse(target:MovieClip, layerIndex:Number):Void {
        if (!EffectSystem.isDeathEffect) return;
        
        var offset:Vector = SceneCoordinateManager.effectOffset;
        var transform:Object = DeathEffectRenderer.calculateTransform(target, offset);
        var gameWorld:MovieClip = _root.gameworld;

        
        gameWorld.deadbody.layers[layerIndex].draw(
            target,
            transform.matrix,
            DeathEffectRenderer.createDarkenCT(target.transform.colorTransform),
            "normal",
            undefined,
            true
        );
    }
    
    // ------------------ 私有工具方法 ------------------
    
    /**
     * 清除目标影片剪辑中的旧标志和文字
     */
    private static function clearLegacyClips(target:MovieClip):Void {
        var clips:Array = ["暴走标志", "远古标志", "亚种标志", "人物文字信息", "新版人物文字信息"];
        for (var i:Number = 0; i < clips.length; i++) {
            if (target[clips[i]]) {
                target[clips[i]].removeMovieClip();
            }
        }
    }
    
    /**
     * 计算目标影片剪辑的全局坐标
     */
    private static function calculateGlobalPosition(target:MovieClip):Object {
        var pos:Object = {x:0, y:0};
        target.localToGlobal(pos);
        return pos;
    }
    
    /**
     * 根据目标影片剪辑与位置绘制暗化的尸体
     */
    private static function drawDarkenedBody(target:MovieClip, layerIndex:Number, pos:Object):Void {
        var gameWorld:MovieClip = _root.gameworld;
        gameWorld.deadbody.globalToLocal(pos);
        var matrix:Matrix = new Matrix(
            target._xscale / 100, 0,
            0, target._yscale / 100,
            pos.x, pos.y
        );

        gameWorld.deadbody.layers[layerIndex].draw(
            target,
            matrix,
            DeathEffectRenderer.createDarkenCT(target.transform.colorTransform),
            "normal",
            undefined,
            true
        );
    }
    
    /**
     * 播放尸体消失特效
     */
    private static function playDisappearEffect(pos:Object):Void {
        var gameWorld:MovieClip = _root.gameworld;
        gameWorld.效果.globalToLocal(pos);
        EffectSystem.Effect("尸体消失", pos.x, pos.y, 100);
    }

    // 添加缓存对象，用于保存已创建的 ColorTransform 对象
    private static var darkenCTCache:Object = {};
    
    /**
     * 根据原始 ColorTransform 快速生成暗化版的 ColorTransform 并缓存
     * — 使用一次性位运算构造唯一的数字 key（避免字符串拼接开销）
     * — 假设 multiplier*100 后值在 0..65535 范围内，offset 在 -32768..32767 范围内
     */
    private static function createDarkenCT(originalCT:ColorTransform):ColorTransform {
        // 一行生成唯一 key：通过位运算把 8 个属性打包成一个 32 位整数
        // ┌────────────────────────────────────────────────────────┐
        // │ multipliers: red→高16 位，green→低16 位                 │
        // │              blue→高16 位，alpha→低16 位                │
        // │ offsets: redOffset 放 bits0-15, greenOffset bits16-31  │
        // │          blueOffset 左移8 位，alphaOffset 左移24 位     │
        // └────────────────────────────────────────────────────────┘
        var key:Number = (
            ((((originalCT.redMultiplier   * 100) & 0xFFFF) << 16) | ((originalCT.greenMultiplier * 100) & 0xFFFF))
            ^ ((((originalCT.blueMultiplier  * 100) & 0xFFFF) << 16) | ((originalCT.alphaMultiplier * 100) & 0xFFFF))
            ^ ((originalCT.redOffset   + 32768) & 0xFFFF)
            ^ (((originalCT.greenOffset + 32768) & 0xFFFF) << 16)
            ^ (((originalCT.blueOffset  + 32768) & 0xFFFF) << 8)
            ^ (((originalCT.alphaOffset + 32768) & 0xFFFF) << 24)
        );

        // 如果缓存中已有相同 key，则直接返回已有 ColorTransform
        if (darkenCTCache[key] != undefined) {
            return darkenCTCache[key];
        }

        // 未命中缓存时新建暗化 ColorTransform 并存入缓存
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
     * 根据目标影片剪辑与偏移量计算旋转后的矩阵
     */
    private static function calculateTransform(target:MovieClip, offset:Vector):Object {
        var rotationRadians:Number = target._rotation * Math.PI / 180;
        var scaleX:Number = Math.max(Math.abs(target._xscale) / 100, MIN_SCALE);
        var scaleY:Number = Math.max(Math.abs(target._yscale) / 100, MIN_SCALE);
        
        var matrix:Matrix = new Matrix(
            Math.cos(rotationRadians) * scaleX,
            Math.sin(rotationRadians) * scaleY,
            -Math.sin(rotationRadians) * scaleX,
            Math.cos(rotationRadians) * scaleY,
            target._x + offset.x,
            target._y + offset.y
        );
        
        return { matrix: matrix };
    }
}
