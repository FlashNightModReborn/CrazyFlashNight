class org.flashNight.arki.corpse.DeathEffectRenderer {
    // 常量定义
    private static var DARKEN_FACTOR:Number = 0.3;
    private static var MIN_SCALE:Number = 0.5;
    
    /**
     * 渲染尸体效果（标准）
     * @param root 游戏根对象（_root）
     * @param target 目标影片剪辑
     * @param layerIndex 层索引
     */
    public static function renderCorpse(root:MovieClip, target:MovieClip, layerIndex:Number):Void {
        // 清除旧的标志与文字
        DeathEffectRenderer.clearLegacyClips(target);
        if (!root.帧计时器.是否死亡特效) return;
        
        var renderPos:Object = DeathEffectRenderer.calculateGlobalPosition(target);
        
        if (root.血腥开关) {
            DeathEffectRenderer.drawDarkenedBody(root, target, layerIndex, renderPos);
        } else {
            DeathEffectRenderer.playDisappearEffect(root, renderPos);
        }
    }
    
    /**
     * 渲染带旋转的尸体效果
     * @param root 游戏根对象（_root）
     * @param target 目标影片剪辑
     * @param layerIndex 层索引
     */
    public static function renderRotatedCorpse(root:MovieClip, target:MovieClip, layerIndex:Number):Void {
        if (!root.帧计时器.是否死亡特效) return;
        
        var offset:Vector = SceneCoordinateManager.effectOffset;
        var transform:Object = DeathEffectRenderer.calculateTransform(target, offset);
        var gameWorld:MovieClip = root.gameworld;
        
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
    private static function drawDarkenedBody(root:MovieClip, target:MovieClip, layerIndex:Number, pos:Object):Void {
        var gameWorld:MovieClip = root.gameworld;
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
    private static function playDisappearEffect(root:MovieClip, pos:Object):Void {
        var gameWorld:MovieClip = root.gameworld;
        gameWorld.效果.globalToLocal(pos);
        root.效果("尸体消失", pos.x, pos.y, 100);
    }
    
    /**
     * 创建暗化用的 ColorTransform
     */
    private static function createDarkenCT(originalCT:ColorTransform):ColorTransform {
        return new ColorTransform(
            originalCT.redMultiplier - DARKEN_FACTOR,
            originalCT.greenMultiplier - DARKEN_FACTOR,
            originalCT.blueMultiplier - DARKEN_FACTOR,
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
