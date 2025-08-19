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

        HorizontalScroller.getInstance = function():HorizontalScroller {
            return instance;
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
    // 栈式焦点系统
    //================================================================================
    
    /** 焦点栈：每个元素包含 {target, expireFrame, snap, easeFactor, offsetTolerance, biasX, biasY} */
    private var focusStack:Array;
    
    /** 默认跟随对象（通常是主角） */
    private var defaultFollowTarget:MovieClip;
    
    /** 当前有效的焦点配置缓存 */
    private var currentFocus:Object;

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
    // 栈式焦点系统 - 静态外观接口
    //================================================================================
    
    /**
     * 推入临时焦点目标（演出特写、开镜等场景）
     * @param target 跟随目标对象
     * @param frames 持续帧数，默认0表示永久直到手动pop
     * @param snap 是否瞬移到位，默认false
     * @param overrideEase 临时平滑系数，默认使用当前配置
     * @param tol 临时死区容差，默认使用当前配置
     * @param biasX 构图偏置X，默认0
     * @param biasY 构图偏置Y，默认0
     */
    public static function pushFocus(target:MovieClip, frames:Number, snap:Boolean, 
                                   overrideEase:Number, tol:Number, biasX:Number, biasY:Number):Void {
        if (!instance) {
            getInstance(); // 确保实例存在
        }
        instance.pushFocusInternal(target, frames || 0, snap || false, 
                                 overrideEase || 0, tol || -1, biasX || 0, biasY || 0);
    }
    
    /**
     * 弹出栈顶的焦点配置，回退到上一个目标
     */
    public static function popFocus():Void {
        if (!instance) {
            return; // 实例不存在，无需操作
        }
        instance.popFocusInternal();
    }
    
    /**
     * 直接切换跟随对象，不使用栈（适合永久切换或关卡阶段切换）
     * @param target 新的跟随目标，如果为null则回到默认主角
     */
    public static function switchFollowTo(target:MovieClip):Void {
        if (!instance) {
            getInstance(); // 确保实例存在
        }
        instance.switchFollowToInternal(target);
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
        // 检查并更新焦点栈状态（自动过期检查和容错）
        this.updateCurrentFocus();
        
        // 获取有效的滚动参数（支持临时参数覆盖）
        var effectiveEase:Number = this.easeFactor;
        var effectiveTolerance:Number = this.offsetTolerance;
        var biasX:Number = 0;
        var biasY:Number = 0;
        
        if (this.currentFocus) {
            effectiveEase = this.currentFocus.easeFactor;
            effectiveTolerance = this.currentFocus.offsetTolerance;
            biasX = this.currentFocus.biasX;
            biasY = this.currentFocus.biasY;
        }
        
        // 计算动态滚动中心点（根据缩放比例调整）
        var centerPoints:Object = this.calculateScrollCenters(zoomResult.newScale);
        
        // 获取角色在屏幕上的精确坐标
        var screenCoords:Object = this.calculateScreenCoordinates(zoomResult.newScale);
        
        // 根据朝向决定目标中心点，并应用构图偏置
        var isRightDirection:Boolean = (this.scrollObj._xscale > 0);
        var targetX:Number = isRightDirection ? centerPoints.rightCenter : centerPoints.leftCenter;
        var targetY:Number = centerPoints.verticalCenter;
        
        // 应用构图偏置
        targetX += biasX;
        targetY += biasY;
        
        // 计算滚动偏移量（使用有效的参数）
        var scrollParams:Object = ScrollLogic.computeScrollOffsets(
            screenCoords.screenX, screenCoords.screenY,
            targetX, targetY,
            effectiveTolerance, effectiveEase
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
        this.defaultFollowTarget = this.scrollObj; // 设置默认跟随目标（通常是主角）
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

        // 同步基础缩放倍率，避免场景切换后残留旧倍率
        var pct:Number = _root.basicZoomScale * 100;
        this.gameWorld._xscale = this.gameWorld._yscale = pct;
        this.bgLayer._xscale = this.bgLayer._yscale = pct;
        ZoomController.setCurrentScale(_root.basicZoomScale);


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
    // 栈式焦点系统实现
    //================================================================================
    
    /**
     * 推入一个临时焦点目标到栈顶（支持演出特写、开镜等场景）
     * @param target 跟随目标对象
     * @param frames 持续帧数，0表示永久直到手动pop
     * @param snap 是否瞬移到位（默认false）
     * @param overrideEase 临时平滑系数（默认使用当前配置）
     * @param tol 临时死区容差（默认使用当前配置）
     * @param biasX 构图偏置X（默认0）
     * @param biasY 构图偏置Y（默认0）
     */
    private function pushFocusInternal(target:MovieClip, frames:Number, snap:Boolean, 
                                     overrideEase:Number, tol:Number, biasX:Number, biasY:Number):Void {
        if (!target || target._x == undefined) {
            return; // 无效目标，忽略
        }
        
        // 初始化焦点栈（延迟初始化）
        if (!this.focusStack) {
            this.focusStack = [];
        }
        
        // 计算过期帧数
        var expireFrame:Number = 0;
        if (frames > 0) {
            expireFrame = this.frameTimer.当前帧数 + frames;
        }
        
        // 创建焦点配置对象
        var focusConfig:Object = {
            target: target,
            expireFrame: expireFrame,
            snap: (snap === true),
            easeFactor: (overrideEase > 0) ? overrideEase : this.easeFactor,
            offsetTolerance: (tol >= 0) ? tol : this.offsetTolerance,
            biasX: (biasX != undefined) ? biasX : 0,
            biasY: (biasY != undefined) ? biasY : 0
        };
        
        // 推入栈顶
        this.focusStack.push(focusConfig);
        
        // 更新当前焦点缓存
        this.updateCurrentFocus();
        
        // 如果是瞬移模式，临时设置高平滑系数实现一帧到位
        if (snap) {
            focusConfig.easeFactor = 1;
        }
    }
    
    /**
     * 弹出栈顶的焦点配置，回退到上一个目标
     */
    private function popFocusInternal():Void {
        if (!this.focusStack || this.focusStack.length == 0) {
            return; // 栈为空，无需操作
        }
        
        // 弹出栈顶元素
        this.focusStack.pop();
        
        // 更新当前焦点缓存
        this.updateCurrentFocus();
    }
    
    /**
     * 直接切换跟随对象，不使用栈（适合永久切换或关卡阶段切换）
     * @param target 新的跟随目标
     */
    private function switchFollowToInternal(target:MovieClip):Void {
        if (!target || target._x == undefined) {
            // 目标无效，切换到默认主角
            target = this.defaultFollowTarget;
        }
        
        // 更新当前滚动对象
        this.scrollObj = target;
        
        // 清空焦点栈，因为是永久切换
        if (this.focusStack) {
            this.focusStack = [];
        }
        this.currentFocus = null;
    }
    
    /**
     * 更新当前有效的焦点配置缓存（性能优化版本）
     * 只检查栈顶元素，懒惰清理无效元素
     */
    private function updateCurrentFocus():Void {
        if (!this.focusStack || this.focusStack.length == 0) {
            this.currentFocus = null;
            this.scrollObj = this.defaultFollowTarget;
            return;
        }
        
        // 懒惰验证：只检查栈顶元素
        var topFocus:Object = this.focusStack[this.focusStack.length - 1];
        
        // 检查栈顶元素是否有效
        var isTopValid:Boolean = this.isFocusValid(topFocus);
        
        if (isTopValid) {
            // 栈顶有效，直接使用
            this.currentFocus = topFocus;
            this.scrollObj = topFocus.target;
        } else {
            // 栈顶无效，移除并递归检查下一个
            this.focusStack.pop(); // 只移除栈顶，O(1)操作
            this.updateCurrentFocus(); // 尾递归，检查新的栈顶
        }
    }
    
    /**
     * 检查单个焦点配置是否有效
     * @param focus 焦点配置对象
     * @return 是否有效
     */
    private function isFocusValid(focus:Object):Boolean {
        if (!focus) return false;
        
        // 检查目标是否仍然有效
        if (!focus.target || focus.target._x == undefined) {
            return false;
        }
        
        // 检查是否已过期
        if (focus.expireFrame > 0 && this.frameTimer.当前帧数 >= focus.expireFrame) {
            return false;
        }
        
        return true;
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
