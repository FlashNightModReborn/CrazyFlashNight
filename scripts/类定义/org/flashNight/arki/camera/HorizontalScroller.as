import org.flashNight.arki.unit.UnitComponent.Targetcache.*;
import org.flashNight.arki.camera.ZoomController;
import org.flashNight.arki.camera.ScrollBounds;
import org.flashNight.arki.camera.ScrollLogic;
import org.flashNight.arki.camera.ParallaxBackground;

/**
 * HorizontalScroller.as - 重构后的横版滚屏控制器（单例模式 + 函数组装优化）
 *
 * 主要改进：
 *  1. 从静态工具类改为有状态的单例控制器对象
 *  2. 在场景切换时根据配置预组装最优的更新函数，避免运行时条件判断
 *  3. 缓存常用引用和参数，减少解引用开销
 *  4. 将复杂的 update 方法拆分为职责明确的小方法
 *  5. 修正高缩放倍率下的居中问题和地平线高度计算错误
 *
 * 使用方式：
 *  - HorizontalScroller.update()  // 保持原有接口兼容性
 *  - HorizontalScroller.onSceneChanged()  // 场景切换时调用
 */
class org.flashNight.arki.camera.HorizontalScroller {

    //================================================================================
    // 单例管理
    //================================================================================
    
    /** 单例实例 */
    private static var instance:HorizontalScroller;
    
    /** 获取单例实例 */
    public static function getInstance():HorizontalScroller {
        if (!instance) {
            instance = new HorizontalScroller();
        }
        return instance;
    }
    
    /** 私有构造函数，确保单例模式 */
    private function HorizontalScroller() {
        // 初始化默认配置
        this.easeFactor = 10;
        this.offsetTolerance = 0;
    }

    //================================================================================
    // 缓存的引用和配置
    //================================================================================
    
    /** 滚动跟踪目标对象 */
    private var scrollObj:MovieClip;
    
    /** 游戏世界容器 */
    private var gameWorld:MovieClip;
    
    /** 背景图层容器 */
    private var bgLayer:MovieClip;
    
    /** 帧计时器引用 */
    private var frameTimer:Object;
    
    /** 背景原始宽度 */
    private var bgWidth:Number;
    
    /** 背景原始高度 */
    private var bgHeight:Number;
    
    /** 滚动缓动系数 */
    private var easeFactor:Number;
    
    /** 偏移容差 */
    private var offsetTolerance:Number;
    
    /** 是否启用后景视差效果 */
    private var enableParallax:Boolean;
    
    /** 是否启用摄像机缩放 */
    private var enableCameraZoom:Boolean;
    
    /** 舞台可用宽度（减去UI后） */
    private var stageWidth:Number;
    
    /** 舞台可用高度（减去UI后） */
    private var stageHeight:Number;
    
    /** 地平线高度缓存 */
    private var horizonHeight:Number;

    //================================================================================
    // 动态组装的更新函数
    //================================================================================
    
    /** 根据配置组装的最优更新函数 */
    private var updateFunction:Function;

    //================================================================================
    // 公共接口（保持向后兼容）
    //================================================================================
    
    /**
     * 主更新接口 - 保持与原 _root.横版卷屏 的兼容性
     */
    public static function update():Void {
        instance.performUpdate();
    }
    
    /**
     * 场景切换回调 - 重新初始化并组装最优的更新函数
     */
    public static function onSceneChanged():Void {
        instance.initializeForNewScene();
    }

    //================================================================================
    // 核心更新逻辑
    //================================================================================
    
    /**
     * 执行实际的更新逻辑
     */
    private function performUpdate():Void {
        // 检查目标对象有效性
        if (!scrollObj || scrollObj._x == undefined) {
            return;
        }

        
        // 调用预组装的更新函数
        updateFunction.call(this);
    }
    
    /**
     * 带视差效果的更新函数
     */
    private function updateWithParallax():Void {
        // 执行缩放处理
        var zoomResult:Object = this.processZooming();
        if (!zoomResult.shouldContinue) return;
        
        // 处理缩放偏移
        if (zoomResult.hasZoomOffset) {
            this.handleZoomOffset(zoomResult);
        }
        
        // 检查是否需要滚动
        if (!ScrollBounds.needsScroll(zoomResult.bounds.effBgW, zoomResult.bounds.effBgH, 
                                      this.stageWidth, this.stageHeight)) {
            return;
        }
        
        // 执行滚动逻辑
        var scrollResult:Object = this.processScrolling(zoomResult);
        if (scrollResult.hasScrolled) {
            // 更新视差背景
            ParallaxBackground.updateParallax(this.bgLayer, this.frameTimer.当前帧数, this.gameWorld._x);
        }
    }
    
    /**
     * 不带视差效果的更新函数（性能优化版本）
     */
    private function updateWithoutParallax():Void {
        // 执行缩放处理
        var zoomResult:Object = this.processZooming();
        if (!zoomResult.shouldContinue) return;
        
        // 处理缩放偏移
        if (zoomResult.hasZoomOffset) {
            this.handleZoomOffset(zoomResult);
        }
        
        // 检查是否需要滚动
        if (!ScrollBounds.needsScroll(zoomResult.bounds.effBgW, zoomResult.bounds.effBgH, 
                                      this.stageWidth, this.stageHeight)) {
            return;
        }
        
        // 执行滚动逻辑（无视差更新）
        this.processScrolling(zoomResult);
    }

    //================================================================================
    // 拆分的功能模块
    //================================================================================
    
    /**
     * 处理缩放逻辑
     * @return 包含缩放结果和边界信息的对象
     */
    private function processZooming():Object {
        var newScale:Number;
        var offsetX:Number = 0;
        var offsetY:Number = 0;
        var hasZoomOffset:Boolean = false;
        
        if (this.enableCameraZoom) {
            var zoomResult:Object = ZoomController.updateScale(
                this.scrollObj, this.gameWorld, this.bgLayer, 
                this.easeFactor, _root.basicZoomScale
            );
            newScale = zoomResult.newScale;
            offsetX = zoomResult.offsetX;
            offsetY = zoomResult.offsetY;
            hasZoomOffset = (offsetX !== 0 || offsetY !== 0);
        } else {
            newScale = _root.basicZoomScale;
            var offset:Object = ZoomController.applyFixedScale(
                this.scrollObj, this.gameWorld, this.bgLayer, newScale
            );
            offsetX = offset.offsetX;
            offsetY = offset.offsetY;
            hasZoomOffset = (offsetX !== 0 || offsetY !== 0);
        }
        
        // 计算滚动边界
        var bounds:Object = ScrollBounds.calculateBounds(
            this.bgWidth, this.bgHeight, newScale, 
            this.stageWidth, this.stageHeight
        );
        
        return {
            newScale: newScale,
            offsetX: offsetX,
            offsetY: offsetY,
            hasZoomOffset: hasZoomOffset,
            bounds: bounds,
            shouldContinue: true
        };
    }
    
    /**
     * 处理缩放产生的偏移
     * @param zoomResult 缩放结果对象
     */
    private function handleZoomOffset(zoomResult:Object):Void {
        // 计算临时坐标
        var tentativeX:Number = this.gameWorld._x + zoomResult.offsetX;
        var tentativeY:Number = this.gameWorld._y + zoomResult.offsetY;
        
        // 应用边界约束
        var clamped:Object = ScrollBounds.clampPosition(
            tentativeX, tentativeY, zoomResult.bounds,
            this.stageWidth, this.stageHeight
        );
        
        // 更新世界坐标
        this.gameWorld._x = clamped.clampedX;
        this.gameWorld._y = clamped.clampedY;
        
        // 更新背景图层位置（考虑缩放后的地平线高度）
        var scaledHorizonHeight:Number = this.horizonHeight * zoomResult.newScale;
        this.bgLayer._y = clamped.clampedY + scaledHorizonHeight;
        
        // 刷新视差背景（如果启用）
        if (this.enableParallax) {
            ParallaxBackground.refreshOnZoom(this.bgLayer, this.gameWorld._x);
        }
    }
    
    /**
     * 处理滚动逻辑
     * @param zoomResult 缩放结果对象
     * @return 包含滚动结果的对象
     */
    private function processScrolling(zoomResult:Object):Object {
        // 计算动态滚动中心点（根据缩放比例调整）
        var centerPoints:Object = this.calculateScrollCenters(zoomResult.newScale);
        
        // 获取角色在屏幕上的精确坐标
        var screenCoords:Object = this.calculateScreenCoordinates(zoomResult.newScale);
        
        // 根据朝向决定目标中心点
        var isRightDirection:Boolean = (this.scrollObj._xscale > 0);
        var targetX:Number = isRightDirection ? centerPoints.rightCenter : centerPoints.leftCenter;
        
        // 计算滚动偏移量
        var scrollParams:Object = ScrollLogic.computeScrollOffsets(
            screenCoords.screenX, screenCoords.screenY,
            targetX, centerPoints.verticalCenter,
            this.offsetTolerance, this.easeFactor
        );
        
        // 检查是否需要滚动
        if (!scrollParams.needMoveX && !scrollParams.needMoveY) {
            return { hasScrolled: false };
        }
        
        // 应用滚动偏移
        return this.applyScrollOffset(scrollParams, zoomResult);
    }
    
    /**
     * 根据缩放倍率计算动态滚动中心点
     * @param scale 当前缩放倍率
     * @return 包含各中心点坐标的对象
     */
    private function calculateScrollCenters(scale:Number):Object {
        // 根据缩放倍率动态调整偏移量，高缩放时减小偏移保持居中
        var baseOffset:Number = 100;
        var scaledOffset:Number = baseOffset / Math.max(1, scale * 0.5);
        
        return {
            leftCenter: this.stageWidth * 0.5 + scaledOffset,
            rightCenter: this.stageWidth * 0.5 - scaledOffset,
            verticalCenter: this.stageHeight - 100
        };
    }
    
    /**
     * 计算角色在屏幕上的精确坐标
     * @param scale 当前缩放倍率
     * @return 包含屏幕坐标的对象
     */
    private function calculateScreenCoordinates(scale:Number):Object {
        var worldX:Number = this.scrollObj._x;
        var worldY:Number = this.scrollObj._y;
        
        return {
            screenX: (worldX * scale) + this.gameWorld._x,
            screenY: (worldY * scale) + this.gameWorld._y
        };
    }
    
    /**
     * 应用滚动偏移量
     * @param scrollParams 滚动参数对象
     * @param zoomResult 缩放结果对象
     * @return 包含滚动结果的对象
     */
    private function applyScrollOffset(scrollParams:Object, zoomResult:Object):Object {
        var oldX:Number = this.gameWorld._x;
        var oldY:Number = this.gameWorld._y;
        var newX:Number = oldX + scrollParams.dx;
        var newY:Number = oldY + scrollParams.dy;
        
        // 应用边界约束
        var clampedFinal:Object = ScrollBounds.clampPosition(
            newX, newY, zoomResult.bounds, 
            this.stageWidth, this.stageHeight
        );
        
        // 更新世界坐标
        var hasScrolled:Boolean = false;
        if (clampedFinal.clampedX !== oldX) {
            this.gameWorld._x = clampedFinal.clampedX;
            hasScrolled = true;
        }
        if (clampedFinal.clampedY !== oldY) {
            this.gameWorld._y = clampedFinal.clampedY;
            hasScrolled = true;
        }
        
        // 同步背景图层位置
        if (hasScrolled) {
            var scaledHorizonHeight:Number = this.horizonHeight * zoomResult.newScale;
            this.bgLayer._y = this.gameWorld._y + scaledHorizonHeight;
        }
        
        return { hasScrolled: hasScrolled };
    }

    //================================================================================
    // 初始化和配置
    //================================================================================
    
    /**
     * 为新场景初始化控制器并组装最优的更新函数
     */
    private function initializeForNewScene():Void {
        // 缓存常用引用，减少运行时解引用开销
        this.scrollObj = _root.gameworld[_root.控制目标];
        this.gameWorld = _root.gameworld;
        this.bgLayer = _root.天空盒;
        this.frameTimer = _root.帧计时器;
        
        // 重置背景图层位置
        this.bgLayer._x = 0;
        
        // 缓存配置参数
        this.bgWidth = _root.gameworld.背景长;
        this.bgHeight = _root.gameworld.背景高;
        this.enableParallax = _root.启用后景;
        this.enableCameraZoom = _root.cameraZoomToggle;
        this.horizonHeight = this.bgLayer.地平线高度;
        
        // 缓存舞台尺寸
        this.stageWidth = Stage.width;
        this.stageHeight = Stage.height - 64; // 底部UI占64px
        
        // 缓存帧计时器参数
        if (this.frameTimer && this.frameTimer.offsetTolerance !== undefined) {
            this.offsetTolerance = this.frameTimer.offsetTolerance;
        }

        // _root.发布消息(bgWidth,bgHeight,enableParallax,enableCameraZoom,horizonHeight);
        
        // 根据配置组装最优的更新函数
        this.assembleUpdateFunction();
    }
    
    /**
     * 根据当前配置组装最优的更新函数
     * 避免运行时的条件判断，提升性能
     */
    private function assembleUpdateFunction():Void {
        if (this.enableParallax) {
            this.updateFunction = this.updateWithParallax;
        } else {
            this.updateFunction = this.updateWithoutParallax;
        }
    }
    
    //================================================================================
    // 调试和工具方法
    //================================================================================
    
    /**
     * 获取当前控制器状态信息（用于调试）
     * @return 包含状态信息的对象
     */
    public function getDebugInfo():Object {
        return {
            hasScrollObj: (this.scrollObj != null),
            enableParallax: this.enableParallax,
            enableCameraZoom: this.enableCameraZoom,
            bgDimensions: { width: this.bgWidth, height: this.bgHeight },
            stageDimensions: { width: this.stageWidth, height: this.stageHeight },
            updateFunctionType: this.enableParallax ? "WithParallax" : "WithoutParallax"
        };
    }
}