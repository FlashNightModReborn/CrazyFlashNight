import org.flashNight.arki.unit.UnitComponent.Targetcache.*;
import org.flashNight.arki.camera.ZoomController;
import org.flashNight.arki.camera.ParallaxBackground;
import org.flashNight.gesh.object.*;
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
        this.offsetTolerance = 0.5;
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

    /** 当前帧缩放倍率与缩放补偿 */
    private var currentScale:Number;
    private var zoomOffsetX:Number;
    private var zoomOffsetY:Number;
    private var hasZoomOffset:Boolean;

    /** 滚屏边界缓存，避免每帧分配 bounds 对象 */
    private var boundsEffBgW:Number;
    private var boundsEffBgH:Number;
    private var boundsMinX:Number;
    private var boundsMaxX:Number;
    private var boundsMinY:Number;
    private var boundsMaxY:Number;
    private var cachedBoundsScale:Number;
    private var cachedBoundsStageWidth:Number;
    private var cachedBoundsStageHeight:Number;

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

    /**
     * 全屏切换回调 - 刷新相机位置（幂等操作）
     * 仅刷新舞台尺寸并重新应用相机位置，不做增量补偿
     */
    public static function onFullScreenChanged():Void {
        if (instance) {
            instance.refreshCameraOnFullScreen();
        }
        // _root.服务器.发布服务器消息("Flash 全屏状态变更，执行刷新");
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
     * @param minZoom 最小绝对缩放倍率（特写用），当系统动态缩放小于此值时强制使用此倍率，默认0不限制
     *                示例：minZoom=2.0 表示"确保至少2倍缩放"，而非"在当前基础上再乘以2"
     */
    public static function pushFocus(target:MovieClip, frames:Number, snap:Boolean, 
                                   overrideEase:Number, tol:Number, biasX:Number, biasY:Number,
                                   minZoom:Number):Void {
        if (!instance) {
            getInstance(); // 确保实例存在
        }
        instance.pushFocusInternal(target, frames || 0, snap || false, 
                                 overrideEase || 0, tol || -1, biasX || 0, biasY || 0,
                                 minZoom || 0);
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
        // 检查目标对象有效性和焦点栈防护
        if (!scrollObj || scrollObj._x == undefined) {
            // 如果当前目标无效且不是默认目标，弹出当前焦点并重试
            if (this.focusStack && this.focusStack.length > 0 && scrollObj !== this.defaultFollowTarget) {
                this.popFocusInternal();
                // 重新检查更新后的目标
                if (scrollObj && scrollObj._x != undefined) {
                    updateFunction.call(this);
                }
            }
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
        if (!this.processZooming()) return;

        // 处理缩放偏移
        if (this.hasZoomOffset) {
            this.handleZoomOffset();
        }

        // 检查是否需要滚动
        if (!(this.stageWidth < this.boundsEffBgW || this.stageHeight < this.boundsEffBgH)) {
            return;
        }

        // 执行滚动逻辑
        if (this.processScrolling()) {
            // 更新视差背景
            ParallaxBackground.updateParallax(this.bgLayer, this.frameTimer.当前帧数, this.gameWorld._x);
        }
    }
    
    /**
     * 不带视差效果的更新函数（性能优化版本）
     */
    private function updateWithoutParallax():Void {
        // 执行缩放处理
        if (!this.processZooming()) return;
        
        // 处理缩放偏移
        if (this.hasZoomOffset) {
            this.handleZoomOffset();
        }
        
        // 检查是否需要滚动
        if (!(this.stageWidth < this.boundsEffBgW || this.stageHeight < this.boundsEffBgH)) {
            return;
        }
        
        // 执行滚动逻辑（无视差更新）
        this.processScrolling();
    }

    //================================================================================
    // 拆分的功能模块
    //================================================================================
    
    /**
     * 处理缩放逻辑
     * @return 是否继续执行滚屏
     */
    private function processZooming():Boolean {
        var newScale:Number;
        this.zoomOffsetX = 0;
        this.zoomOffsetY = 0;
        this.hasZoomOffset = false;
        
        if (this.enableCameraZoom) {
            // 从当前焦点读取"最小缩放阈值"，无则为 0（不限制）
            var __minClamp:Number = 0;
            if (this.currentFocus && this.currentFocus.minZoom > 0) {
                __minClamp = this.currentFocus.minZoom;
            }
            var zoomResult:Object = ZoomController.updateScale(
                this.scrollObj, this.gameWorld, this.bgLayer, 
                this.easeFactor, _root.basicZoomScale,
                __minClamp
            );
            newScale = zoomResult.newScale;
            this.zoomOffsetX = zoomResult.offsetX;
            this.zoomOffsetY = zoomResult.offsetY;
            this.hasZoomOffset = (this.zoomOffsetX !== 0 || this.zoomOffsetY !== 0);
        } else {
            newScale = _root.basicZoomScale;
            if (this.currentScale !== newScale) {
                var offset:Object = ZoomController.applyFixedScale(
                    this.scrollObj, this.gameWorld, this.bgLayer, newScale
                );
                this.zoomOffsetX = offset.offsetX;
                this.zoomOffsetY = offset.offsetY;
                this.hasZoomOffset = (this.zoomOffsetX !== 0 || this.zoomOffsetY !== 0);
            }
        }
        
        this.currentScale = newScale;
        this.updateBoundsForScale(newScale);
        return true;
    }
    
    /**
     * 处理缩放产生的偏移
     */
    private function handleZoomOffset():Void {
        var gw:MovieClip = this.gameWorld;
        
        // 计算临时坐标
        var clampedX:Number = gw._x + this.zoomOffsetX;
        var clampedY:Number = gw._y + this.zoomOffsetY;

        // 应用边界约束与像素取整
        if (this.stageWidth < this.boundsEffBgW) {
            if (clampedX < this.boundsMinX) {
                clampedX = this.boundsMinX;
            } else if (clampedX > this.boundsMaxX) {
                clampedX = this.boundsMaxX;
            }
        } else {
            clampedX = 0;
        }
        if (this.stageHeight < this.boundsEffBgH) {
            if (clampedY < this.boundsMinY) {
                clampedY = this.boundsMinY;
            } else if (clampedY > this.boundsMaxY) {
                clampedY = this.boundsMaxY;
            }
        } else {
            clampedY = 0;
        }
        clampedX = (clampedX < 0) ? ((clampedX - 0.5) | 0) : ((clampedX + 0.5) | 0);
        clampedY = (clampedY < 0) ? ((clampedY - 0.5) | 0) : ((clampedY + 0.5) | 0);
        
        // 更新世界坐标
        if (clampedX !== gw._x) {
            gw._x = clampedX;
        }
        if (clampedY !== gw._y) {
            gw._y = clampedY;
        }
        
        // 更新背景图层位置（考虑缩放后的地平线高度）
        var scaledHorizonHeight:Number = this.horizonHeight * this.currentScale;
        this.bgLayer._y = clampedY + scaledHorizonHeight;
        
        // 刷新视差背景（如果启用）
        if (this.enableParallax) {
            ParallaxBackground.refreshOnZoom(this.bgLayer, gw._x);
        }
    }
    
    /**
     * 处理滚动逻辑
     * @return 是否发生滚动
     */
    private function processScrolling():Boolean {
        // 检查并更新焦点栈状态（自动过期检查和容错）
        this.updateCurrentFocus();
        
        var gw:MovieClip = this.gameWorld;
        var target:MovieClip = this.scrollObj;
        var scale:Number = this.currentScale;

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
        
        // 标量计算热路径，避免每帧创建 center/screen/scroll 对象
        var halfScale:Number = scale * 0.5;
        var scaledOffset:Number = 100 / ((halfScale > 1) ? halfScale : 1);
        var stageCenterX:Number = this.stageWidth * 0.5;
        var targetX:Number = (target._xscale > 0) ? (stageCenterX - scaledOffset) : (stageCenterX + scaledOffset);
        var targetY:Number = this.stageHeight - 100;
        targetX += biasX;
        targetY += biasY;
        
        var screenX:Number = (target._x * scale) + gw._x;
        var screenY:Number = (target._y * scale) + gw._y;
        var deltaX:Number = targetX - screenX;
        var deltaY:Number = targetY - screenY;
        var adx:Number = (deltaX < 0) ? -deltaX : deltaX;
        var ady:Number = (deltaY < 0) ? -deltaY : deltaY;
        var needMoveX:Boolean = (adx > effectiveTolerance);
        var needMoveY:Boolean = (ady > effectiveTolerance);
        
        // 检查是否需要滚动
        if (!needMoveX && !needMoveY) {
            return false;
        }
        
        // 应用滚动偏移
        var dx:Number = needMoveX ? ((adx > 1) ? (deltaX / effectiveEase) : deltaX) : 0;
        var dy:Number = needMoveY ? ((ady > 1) ? (deltaY / effectiveEase) : deltaY) : 0;
        return this.applyScrollOffset(dx, dy);
    }
    
    /**
     * 应用滚动偏移量
     * @return 是否发生滚动
     */
    private function applyScrollOffset(dx:Number, dy:Number):Boolean {
        var gw:MovieClip = this.gameWorld;
        var oldX:Number = gw._x;
        var oldY:Number = gw._y;
        var clampedX:Number = oldX + dx;
        var clampedY:Number = oldY + dy;
        
        // 应用边界约束
        if (this.stageWidth < this.boundsEffBgW) {
            if (clampedX < this.boundsMinX) {
                clampedX = this.boundsMinX;
            } else if (clampedX > this.boundsMaxX) {
                clampedX = this.boundsMaxX;
            }
        } else {
            clampedX = 0;
        }
        if (this.stageHeight < this.boundsEffBgH) {
            if (clampedY < this.boundsMinY) {
                clampedY = this.boundsMinY;
            } else if (clampedY > this.boundsMaxY) {
                clampedY = this.boundsMaxY;
            }
        } else {
            clampedY = 0;
        }

        // 内联位运算取整，避免热路径 Math.round 与 helper 调用成本
        clampedX = (clampedX < 0) ? ((clampedX - 0.5) | 0) : ((clampedX + 0.5) | 0);
        clampedY = (clampedY < 0) ? ((clampedY - 0.5) | 0) : ((clampedY + 0.5) | 0);
        
        // 更新世界坐标
        var movedX:Boolean = false;
        var movedY:Boolean = false;
        if (clampedX !== oldX) {
            gw._x = clampedX;
            movedX = true;
        }
        if (clampedY !== oldY) {
            gw._y = clampedY;
            movedY = true;
        }
        
        // 只有 Y 或缩放变化才需要同步天空盒 Y；纯横向滚屏不重写
        if (movedY) {
            var scaledHorizonHeight:Number = this.horizonHeight * this.currentScale;
            this.bgLayer._y = clampedY + scaledHorizonHeight;
        }
        
        return movedX || movedY;
    }

    /**
     * 根据缩放倍率刷新滚屏边界缓存
     */
    private function updateBoundsForScale(scale:Number):Void {
        if (this.cachedBoundsScale === scale &&
            this.cachedBoundsStageWidth === this.stageWidth &&
            this.cachedBoundsStageHeight === this.stageHeight) {
            return;
        }

        var effBgW:Number = this.bgWidth * scale;
        var effBgH:Number = this.bgHeight * scale;

        this.boundsEffBgW = effBgW;
        this.boundsEffBgH = effBgH;
        this.boundsMinX = this.stageWidth - effBgW;
        this.boundsMaxX = 0;
        this.boundsMinY = this.stageHeight - effBgH;
        this.boundsMaxY = 0;
        this.cachedBoundsScale = scale;
        this.cachedBoundsStageWidth = this.stageWidth;
        this.cachedBoundsStageHeight = this.stageHeight;
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
        this.currentScale = _root.basicZoomScale;
        this.zoomOffsetX = 0;
        this.zoomOffsetY = 0;
        this.hasZoomOffset = false;
        this.cachedBoundsScale = -1;
        this.updateBoundsForScale(this.currentScale);

        // 统一像素化世界坐标，避免旧路径残留小数
        var worldX:Number = this.gameWorld._x;
        var worldY:Number = this.gameWorld._y;
        this.gameWorld._x = (worldX < 0) ? ((worldX - 0.5) | 0) : ((worldX + 0.5) | 0);
        this.gameWorld._y = (worldY < 0) ? ((worldY - 0.5) | 0) : ((worldY + 0.5) | 0);

        // 缩放后必须同步天空盒 Y 位置（地平线高度需按缩放比例调整）
        // 否则天空盒位置会残留 _root.加载后景 中设置的未缩放值
        this.bgLayer._y = this.gameWorld._y + this.horizonHeight * _root.basicZoomScale;

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
    
    /**
     * 全屏切换时刷新相机位置（绝对赋值，幂等操作）
     * 不做增量补偿，只更新必要的尺寸参数并重新应用当前位置
     */
    private function refreshCameraOnFullScreen():Void {
        // 1. 更新舞台尺寸缓存
        this.stageWidth = Stage.width;
        this.stageHeight = Stage.height - 64; // 底部UI占64px
        
        // 2. 如果场景未初始化，直接返回
        if (!this.gameWorld || !this.scrollObj) {
            return;
        }
        
        // 3. 获取当前缩放值（不改变）
        var currentScale:Number = this.gameWorld._xscale / 100;
        this.currentScale = currentScale;
        
        // 4. 重新计算滚动边界
        this.cachedBoundsScale = -1;
        this.updateBoundsForScale(currentScale);
        
        // 5. 获取当前目标的世界坐标
        var targetWorldX:Number = this.scrollObj._x;
        var targetWorldY:Number = this.scrollObj._y;
        
        // 6. 计算理想的相机位置（绝对值）
        var idealX:Number = this.stageWidth * 0.5 - (targetWorldX * currentScale);
        var idealY:Number = (this.stageHeight - 100) - (targetWorldY * currentScale);
        
        // 7. 应用边界约束
        var clampedX:Number = idealX;
        var clampedY:Number = idealY;
        if (this.stageWidth < this.boundsEffBgW) {
            if (clampedX < this.boundsMinX) {
                clampedX = this.boundsMinX;
            } else if (clampedX > this.boundsMaxX) {
                clampedX = this.boundsMaxX;
            }
        } else {
            clampedX = 0;
        }
        if (this.stageHeight < this.boundsEffBgH) {
            if (clampedY < this.boundsMinY) {
                clampedY = this.boundsMinY;
            } else if (clampedY > this.boundsMaxY) {
                clampedY = this.boundsMaxY;
            }
        } else {
            clampedY = 0;
        }
        clampedX = (clampedX < 0) ? ((clampedX - 0.5) | 0) : ((clampedX + 0.5) | 0);
        clampedY = (clampedY < 0) ? ((clampedY - 0.5) | 0) : ((clampedY + 0.5) | 0);
        
        // 8. 绝对赋值（不使用 +=）
        this.gameWorld._x = clampedX;
        this.gameWorld._y = clampedY;
        
        // 9. 更新背景层位置（绝对赋值）
        var scaledHorizonHeight:Number = this.horizonHeight * currentScale;
        this.bgLayer._y = clampedY + scaledHorizonHeight;
        
        // 10. 如果启用了视差，刷新视差背景
        if (this.enableParallax) {
            ParallaxBackground.refreshOnZoom(this.bgLayer, this.gameWorld._x);
        }
        
        // 调试日志
        // _root.发布消息("全屏刷新完成 - 舞台:" + this.stageWidth + "x" + this.stageHeight + 
        //               " 世界位置:" + this.gameWorld._x + "," + this.gameWorld._y);
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
     * @param minZoom 最小绝对缩放倍率（特写用），当系统动态缩放小于此值时强制使用此倍率（默认0）
     *                示例：minZoom=2.0 表示"确保至少2倍缩放"，而非"在当前基础上再乘以2"
     */
    private function pushFocusInternal(target:MovieClip, frames:Number, snap:Boolean, 
                                     overrideEase:Number, tol:Number, biasX:Number, biasY:Number,
                                     minZoom:Number):Void {
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
            biasY: (biasY != undefined) ? biasY : 0,
            // 新增：特写最小缩放阈值（仅当 >0 时生效）
            minZoom: (minZoom != undefined && minZoom > 0) ? minZoom : 0
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
