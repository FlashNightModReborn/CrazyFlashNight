import org.flashNight.arki.unit.UnitComponent.Targetcache.*;

// 文件路径：org/flashNight/arki/camera/HorizontalScroller.as
class org.flashNight.arki.camera.HorizontalScroller {
    /**
     * 等价于原来 _root.横版卷屏 的实现逻辑。
     * @param scrollTarget  要跟踪的目标在 gameworld 中的名称
     * @param bgWidth       背景宽度（像素）
     * @param bgHeight      背景高度（像素）
     * @param easeFactor    缓动系数
     * @param zoomScale     （暂时保留，按需传入一个默认值即可，其实内部并未直接用到此参数）
     */
    public static function update(
        scrollTarget:String,
        bgWidth:Number,
        bgHeight:Number,
        easeFactor:Number,
        zoomScale:Number
    ):Void {
        // 1) 先拿到 gameWorld 和 bgLayer
        var gameWorld:MovieClip = _root.gameworld;
        var bgLayer:MovieClip   = _root.天空盒;
        
        // 2) 如果目标不存在或未初始化，则不处理
        var scrollObj:MovieClip = gameWorld[scrollTarget];
        if (!scrollObj || scrollObj._x == undefined) {
            return;
        }
        
        // 3) 先计算距离、归一化与 logScale
        var farthestEnemy:Object = TargetCacheManager.findFarthestEnemy(scrollObj, 5);
        var distance:Number = (Math.abs(scrollObj._x - farthestEnemy._x) 
                              + Math.abs(scrollObj._y - farthestEnemy._y)) || 99999;
        var normalizedDistance:Number = Math.max(1, distance / 100);
        var logScale:Number = Math.log(normalizedDistance) / Math.log(10);
        
        // 4) 计算目标缩放比例，保证当 distance = 800 时，logScale≈1，对应缩放为 1
        //    这里用 1.11 的系数略微调了一下：2 - 1 * 1.11 = 0.89，最后又取最大值为 1
        var targetZoomScale:Number = Math.min(1.5, Math.max(1, 2 - logScale * 1.11));
        
        // 5) 初始化 lastScale
        if (!gameWorld.lastScale) {
            gameWorld.lastScale = targetZoomScale;
        }
        var oldScale:Number = gameWorld.lastScale;
        
        // 6) 计算当前实际 newScale（缓动）
        var newScale:Number = gameWorld.lastScale + (targetZoomScale - gameWorld.lastScale) / easeFactor;
        
        // 7) 计算放大后的有效背景尺寸，以及滚动边界
        var effBgW:Number = bgWidth  * newScale;
        var effBgH:Number = bgHeight * newScale;
        var stageWidth:Number  = Stage.width;
        var stageHeight:Number = Stage.height - 64; // 假定顶部 UI 占 64 像素
        
        var minScrollX:Number = stageWidth  - effBgW;
        var minScrollY:Number = stageHeight - effBgH;
        var maxScrollX:Number = 0;
        var maxScrollY:Number = 0;
        
        // 8) 先处理缩放补偿逻辑
        var scaleChanged:Boolean = Math.abs(newScale - oldScale) > 0.005;
        if (scaleChanged) {
            // 8.1) 记录缩放前目标在屏幕上的坐标
            var preScalePt:Object = { x:0, y:0 };
            scrollObj.localToGlobal(preScalePt);
            
            // 8.2) 应用新的缩放到 gameWorld 与 bgLayer
            var newScalePercent:Number = newScale * 100;
            gameWorld._xscale = gameWorld._yscale = newScalePercent;
            bgLayer._xscale   = bgLayer._yscale   = newScalePercent;
            
            // 8.3) 记录缩放后目标在屏幕上的坐标
            var postScalePt:Object = { x:0, y:0 };
            scrollObj.localToGlobal(postScalePt);
            
            // 8.4) 计算补偿向量
            var worldOffsetX:Number = preScalePt.x - postScalePt.x;
            var worldOffsetY:Number = preScalePt.y - postScalePt.y;
            
            // 8.5) 计算补偿后的世界坐标，并做边界检查
            var compensatedX:Number = gameWorld._x + worldOffsetX;
            var compensatedY:Number = gameWorld._y + worldOffsetY;
            
            // X 方向边界
            if (stageWidth < effBgW) {
                if (compensatedX < minScrollX) {
                    compensatedX = minScrollX;
                } else if (compensatedX > maxScrollX) {
                    compensatedX = maxScrollX;
                }
            }
            // Y 方向边界
            if (stageHeight < effBgH) {
                if (compensatedY < minScrollY) {
                    compensatedY = minScrollY;
                } else if (compensatedY > maxScrollY) {
                    compensatedY = maxScrollY;
                }
            }
            
            // 8.6) 将补偿后的坐标应用到 gameWorld
            gameWorld._x = compensatedX;
            gameWorld._y = compensatedY;
            
            // 8.7) 同步到天空盒根节点
            bgLayer._x = compensatedX;
            // “地平线高度”字段需要在 _root.天空盒 中提前定义
            bgLayer._y = compensatedY + bgLayer.地平线高度;
            
            // 8.8) 如果启用了后景视差，也立即刷新一次
            var bgList:Array = bgLayer.后景移动速度列表;
            var len:Number = bgList.length;
            for (var i:Number = 0; i < len; i++) {
                var info:Object = bgList[i];
                info.mc._x = compensatedX / info.speedrate;
            }
            
            // 8.9) 更新 lastScale
            gameWorld.lastScale = newScale;
        }
        
        // 9) 如果当前背景本身小于等于舞台可视区域，则不需要滚动
        if (stageWidth >= effBgW && stageHeight >= effBgH) {
            return;
        }
        
        // 10) 设定滚动容差，从帧计时器中读取
        var frameTimer:Object = _root.帧计时器;
        var offsetTolerance:Number = frameTimer.offsetTolerance;
        
        // 11) 设定滚动中心点（左右各偏 100px，上下偏 100px）
        var LEFT_SCROLL_CENTER:Number     = stageWidth  * 0.5 + 100;
        var RIGHT_SCROLL_CENTER:Number    = stageWidth  * 0.5 - 100;
        var VERTICAL_SCROLL_CENTER:Number = stageHeight - 100;
        
        // 12) 拿到目标在屏幕坐标下的位置
        var pt2:Object = { x:0, y:0 };
        scrollObj.localToGlobal(pt2);
        
        // 13) 根据朝向决定“水平目标中心”在哪一侧
        var isRightDirection:Boolean = (scrollObj._xscale > 0);
        var targetX:Number = isRightDirection ? RIGHT_SCROLL_CENTER : LEFT_SCROLL_CENTER;
        
        // 14) 计算水平/垂直方向与目标中心的偏移值
        var deltaX:Number = targetX - pt2.x;
        var deltaY:Number = VERTICAL_SCROLL_CENTER - pt2.y;
        var adx:Number = Math.abs(deltaX);
        var ady:Number = Math.abs(deltaY);
        
        // 15) 判断 X/Y 是否需要滚动
        var needMoveX:Boolean = (adx > offsetTolerance);
        var needMoveY:Boolean = (ady > offsetTolerance);
        if (!needMoveX && !needMoveY) {
            return;
        }
        
        // 16) 取当前世界坐标，准备计算新坐标
        var oldX:Number = gameWorld._x;
        var oldY:Number = gameWorld._y;
        var dx:Number = 0;
        var dy:Number = 0;
        
        // ---- X 方向滚动计算 ----
        if (needMoveX) {
            if (adx > 1) {
                dx = deltaX / easeFactor;
            } else {
                dx = deltaX;
            }
        }
        // ---- Y 方向滚动计算 ----
        if (needMoveY) {
            if (ady > 1) {
                dy = deltaY / easeFactor;
            } else {
                dy = deltaY;
            }
        }
        
        // 17) 如果最终 dx/dy 都是 0，则不移动
        if (dx == 0 && dy == 0) {
            return;
        }
        
        // 18) 计算未经边界约束的新世界坐标
        var newX:Number = oldX + dx;
        var newY:Number = oldY + dy;
        
        // ---- X 方向边界约束 ----
        if (stageWidth < effBgW) {
            if (newX < minScrollX) {
                newX = minScrollX;
            } else if (newX > maxScrollX) {
                newX = maxScrollX;
            }
        } else {
            newX = oldX;
        }
        // ---- Y 方向边界约束 ----
        if (stageHeight < effBgH) {
            if (newY < minScrollY) {
                newY = minScrollY;
            } else if (newY > maxScrollY) {
                newY = maxScrollY;
            }
        } else {
            newY = oldY;
        }
        
        // 19) 检查是否真的发生了坐标变化
        var onScrollX:Boolean = (newX != oldX);
        var onScrollY:Boolean = (newY != oldY);
        if (!onScrollX && !onScrollY) {
            return;
        }
        
        // 20) 最后把新坐标写回到 gameWorld 和 bgLayer
        if (bgLayer._xscale != newScale * 100) {
            bgLayer._xscale = bgLayer._yscale = newScale * 100;
        }
        
        if (onScrollX) {
            gameWorld._x = newX;
            if (onScrollY) {
                gameWorld._y = newY;
                bgLayer._y = gameWorld._y + bgLayer.地平线高度;
            }
        } else {
            if (onScrollY) {
                gameWorld._y = newY;
                bgLayer._y = gameWorld._y + bgLayer.地平线高度;
            } else {
                return;
            }
        }
        
        // 21) 如果启用了后景视差，则在滚动时更新一次后景
        if (_root.启用后景) {
            var bgSpeedList:Array = bgLayer.后景移动速度列表;
            var currentFrame:Number = _root.帧计时器.当前帧数;
            var worldXPos:Number = gameWorld._x;
            for (var j:Number = 0; j < bgSpeedList.length; j++) {
                var info2:Object = bgSpeedList[j];
                if (currentFrame % info2.delay === 0) {
                    info2.mc._x = worldXPos / info2.speedrate;
                }
            }
        }
    }
}
