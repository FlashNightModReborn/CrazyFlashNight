import org.flashNight.arki.unit.UnitComponent.Targetcache.*;
import org.flashNight.arki.camera.ZoomController;
import org.flashNight.arki.camera.ScrollBounds;
import org.flashNight.arki.camera.ScrollLogic;
import org.flashNight.arki.camera.ParallaxBackground;

/**
 * HorizontalScroller.as - 升级版主控制器（修复版）
 *
 * 修复内容：
 *  1. 修复缩放时边界约束逻辑 - 只要发生缩放就执行边界检查，不依赖offset是否为0
 *  2. 修复天空盒错位问题 - 在滚动阶段恢复bgLayer._x的同步更新
 */
class org.flashNight.arki.camera.HorizontalScroller {

    // ==================== 核心参数 ====================
    public static var scrollTarget:String;
    public static var bgWidth:Number;
    public static var bgHeight:Number;
    public static var easeFactor:Number;
    public static var zoomScale:Number;
    public static var gameWorld:MovieClip;
    public static var bgLayer:MovieClip;

    // ==================== 新增：配置管理 ====================
    private static var _defaultConfig:Object;
    private static var _configChangeCallbacks:Array = [];
    private static var _isInitialized:Boolean = false;
    private static var _debugMode:Boolean = false;

    // 参数约束配置
    private static var _paramConstraints:Object;

    // ==================== 初始化方法 ====================
    
    /**
     * 初始化参数约束配置
     */
    private static function _initParamConstraints():Void {
        if (_paramConstraints) return; // 避免重复初始化
        
        _paramConstraints = {};
        
        // easeFactor 约束
        _paramConstraints.easeFactor = {};
        _paramConstraints.easeFactor.min = 1;
        _paramConstraints.easeFactor.max = 50;
        _paramConstraints.easeFactor.defaultValue = 10;
        
        // zoomScale 约束
        _paramConstraints.zoomScale = {};
        _paramConstraints.zoomScale.min = 0.1;
        _paramConstraints.zoomScale.max = 5.0;
        _paramConstraints.zoomScale.defaultValue = 1.0;
        
        // bgWidth 约束
        _paramConstraints.bgWidth = {};
        _paramConstraints.bgWidth.min = 100;
        _paramConstraints.bgWidth.max = 10000;
        _paramConstraints.bgWidth.defaultValue = 800;
        
        // bgHeight 约束
        _paramConstraints.bgHeight = {};
        _paramConstraints.bgHeight.min = 100;
        _paramConstraints.bgHeight.max = 10000;
        _paramConstraints.bgHeight.defaultValue = 600;
    }

    public static function reset(paramsObject:Object):Void {
        // 初始化参数约束（如果还未初始化）
        _initParamConstraints();
        
        // 保存默认配置
        _defaultConfig = _cloneConfig(paramsObject);
        
        // 验证并应用配置
        var validatedConfig:Object = _validateConfig(paramsObject);
        _applyConfig(validatedConfig);
        
        _isInitialized = true;
        _logDebug("HorizontalScroller initialized with config: " + _formatConfig(validatedConfig));
        
        // 触发初始化回调
        _triggerConfigChange("initialized", validatedConfig);
    }

    public static function onSceneChanged():Void {
        _logDebug("Scene change detected - performing complete reset");
        
        // ===== 1) 彻底清理上一个场景的状态缓存 =====
        _clearSceneCache();
        
        // ===== 2) 重新构建参数对象 =====
        var paramsObject = {
            scrollTarget: _root.控制目标,
            bgWidth: _root.gameworld.背景长,
            bgHeight: _root.gameworld.背景高,
            easeFactor: 10,
            zoomScale: 1,
            gameWorld: _root.gameworld,
            bgLayer: _root.天空盒
        };

        // ===== 3) 重新初始化 =====
        reset(paramsObject);
        
        // ===== 4) 强制重置世界和天空盒位置到初始状态 =====
        _resetWorldPositions();
        
        _logDebug("Scene change complete - all caches cleared");
        _triggerConfigChange("sceneChanged", { newScene: true });
    }

    /**
     * 清理场景缓存数据
     * 在场景切换时调用，确保上一个场景的状态不会影响新场景
     */
    private static function _clearSceneCache():Void {
        // 清理gameWorld的缓存状态
        if (gameWorld) {
            gameWorld.lastScale = undefined;
            // 如果有其他自定义缓存属性，在这里清理
            gameWorld._scrollerInitialized = undefined;
        }
        
        // 清理bgLayer的缓存状态
        if (bgLayer) {
            bgLayer._lastParallaxFrame = undefined;
            // 清理视差背景缓存
            if (bgLayer.bgParallaxList) {
                // 重置所有视差层的缓存位置
                var bgList:Array = bgLayer.bgParallaxList;
                for (var i:Number = 0; i < bgList.length; i++) {
                    var info:Object = bgList[i];
                    if (info.mc) {
                        info.mc._lastUpdateFrame = undefined;
                    }
                }
            }
        }
        
        _logDebug("Scene cache cleared");
    }

    /**
     * 重置世界和天空盒位置到初始状态
     * 确保新场景从干净的坐标状态开始
     */
    private static function _resetWorldPositions():Void {
        if (!gameWorld || !bgLayer) {
            _logError("Cannot reset positions: gameWorld or bgLayer is null");
            return;
        }
        
        // 重置世界容器位置到原点
        gameWorld._x = 0;
        gameWorld._y = 0;
        
        // 重置缩放到基准值
        var baseScalePercent:Number = zoomScale * 100;
        gameWorld._xscale = gameWorld._yscale = baseScalePercent;
        gameWorld.lastScale = zoomScale;
        
        // 同步重置天空盒
        bgLayer._x = 0;
        bgLayer._y = bgLayer.地平线高度 || 0;
        bgLayer._xscale = bgLayer._yscale = baseScalePercent;
        
        // 重置所有视差背景层位置
        if (bgLayer.bgParallaxList) {
            var bgList:Array = bgLayer.bgParallaxList;
            for (var i:Number = 0; i < bgList.length; i++) {
                var info:Object = bgList[i];
                if (info.mc) {
                    info.mc._x = 0;
                    // Y坐标保持原始设计位置，不重置
                }
            }
        }
        
        _logDebug("World positions reset - gameWorld: (" + gameWorld._x + "," + gameWorld._y + 
                 "), bgLayer: (" + bgLayer._x + "," + bgLayer._y + "), scale: " + zoomScale);
    }

    // ==================== 新增：运行时参数修改API ====================

    /**
     * 设置滚动目标
     * @param targetName 目标对象名称
     * @return Boolean 是否设置成功
     */
    public static function setScrollTarget(targetName:String):Boolean {
        if (!_isInitialized) {
            _logError("HorizontalScroller not initialized");
            return false;
        }

        var oldTarget:String = scrollTarget;
        scrollTarget = targetName;
        
        _logDebug("ScrollTarget changed: " + oldTarget + " -> " + targetName);
        _triggerConfigChange("scrollTarget", { from: oldTarget, to: targetName });
        return true;
    }

    /**
     * 设置背景尺寸
     * @param width 背景宽度
     * @param height 背景高度
     * @return Boolean 是否设置成功
     */
    public static function setBackgroundSize(width:Number, height:Number):Boolean {
        if (!_isInitialized) {
            _logError("HorizontalScroller not initialized");
            return false;
        }

        var widthValid:Boolean = _validateParam("bgWidth", width);
        var heightValid:Boolean = _validateParam("bgHeight", height);
        
        if (!widthValid || !heightValid) {
            _logError("Invalid background size: " + width + "x" + height);
            return false;
        }

        var oldSize:Object = { width: bgWidth, height: bgHeight };
        bgWidth = width;
        bgHeight = height;
        
        _logDebug("Background size changed: " + oldSize.width + "x" + oldSize.height + " -> " + width + "x" + height);
        _triggerConfigChange("backgroundSize", { from: oldSize, to: { width: width, height: height } });
        return true;
    }

    /**
     * 设置缓动系数
     * @param factor 缓动系数 (1-50)
     * @return Boolean 是否设置成功
     */
    public static function setEaseFactor(factor:Number):Boolean {
        if (!_isInitialized) {
            _logError("HorizontalScroller not initialized");
            return false;
        }

        if (!_validateParam("easeFactor", factor)) {
            _logError("Invalid ease factor: " + factor);
            return false;
        }

        var oldFactor:Number = easeFactor;
        easeFactor = factor;
        
        _logDebug("EaseFactor changed: " + oldFactor + " -> " + factor);
        _triggerConfigChange("easeFactor", { from: oldFactor, to: factor });
        return true;
    }

    /**
     * 设置缩放系数
     * @param scale 缩放系数 (0.1-5.0)
     * @return Boolean 是否设置成功
     */
    public static function setZoomScale(scale:Number):Boolean {
        if (!_isInitialized) {
            _logError("HorizontalScroller not initialized");
            return false;
        }

        if (!_validateParam("zoomScale", scale)) {
            _logError("Invalid zoom scale: " + scale);
            return false;
        }

        var oldScale:Number = zoomScale;
        zoomScale = scale;
        
        // 重置gameWorld的lastScale以应用新的缩放基准
        if (gameWorld && gameWorld.lastScale !== undefined) {
            gameWorld.lastScale = scale;
        }
        
        _logDebug("ZoomScale changed: " + oldScale + " -> " + scale);
        _triggerConfigChange("zoomScale", { from: oldScale, to: scale });
        return true;
    }

    /**
     * 批量更新配置
     * @param configObject 配置对象
     * @return Boolean 是否全部更新成功
     */
    public static function updateConfig(configObject:Object):Boolean {
        if (!_isInitialized) {
            _logError("HorizontalScroller not initialized");
            return false;
        }

        var validatedConfig:Object = _validateConfig(configObject);
        var oldConfig:Object = getCurrentConfig();
        
        _applyConfig(validatedConfig);
        
        _logDebug("Config batch updated");
        _triggerConfigChange("batchUpdate", { from: oldConfig, to: validatedConfig });
        return true;
    }

    /**
     * 获取当前配置
     * @return Object 当前配置对象
     */
    public static function getCurrentConfig():Object {
        return {
            scrollTarget: scrollTarget,
            bgWidth: bgWidth,
            bgHeight: bgHeight,
            easeFactor: easeFactor,
            zoomScale: zoomScale,
            isInitialized: _isInitialized
        };
    }

    /**
     * 重置为默认配置
     * @return Boolean 是否重置成功
     */
    public static function resetToDefaults():Boolean {
        if (!_defaultConfig) {
            _logError("No default config available");
            return false;
        }

        var oldConfig:Object = getCurrentConfig();
        _applyConfig(_defaultConfig);
        
        _logDebug("Config reset to defaults");
        _triggerConfigChange("resetToDefaults", { from: oldConfig, to: _defaultConfig });
        return true;
    }

    /**
     * 获取参数约束信息
     * @return Object 参数约束配置
     */
    public static function getParamConstraints():Object {
        _initParamConstraints();
        return _cloneConfig(_paramConstraints);
    }

    /**
     * 启用/禁用调试模式
     * @param enabled 是否启用
     */
    public static function setDebugMode(enabled:Boolean):Void {
        _debugMode = enabled;
        _logDebug("Debug mode " + (enabled ? "enabled" : "disabled"));
    }

    // ==================== 事件回调系统 ====================

    /**
     * 添加配置变化回调
     * @param callback 回调函数 function(changeType:String, changeData:Object):Void
     */
    public static function addConfigChangeCallback(callback:Function):Void {
        if (_configChangeCallbacks.indexOf(callback) === -1) {
            _configChangeCallbacks.push(callback);
        }
    }

    /**
     * 移除配置变化回调
     * @param callback 要移除的回调函数
     */
    public static function removeConfigChangeCallback(callback:Function):Void {
        var index:Number = _configChangeCallbacks.indexOf(callback);
        if (index !== -1) {
            _configChangeCallbacks.splice(index, 1);
        }
    }

    // ==================== 调试和工具方法 ====================

    /**
     * 获取系统状态信息
     * @return Object 状态信息
     */
    public static function getSystemStatus():Object {
        var scrollObj:MovieClip = gameWorld ? gameWorld[scrollTarget] : null;
        
        return {
            isInitialized: _isInitialized,
            hasValidScrollTarget: (scrollObj && scrollObj._x !== undefined),
            currentScale: gameWorld ? gameWorld.lastScale : null,
            gameWorldPosition: gameWorld ? { x: gameWorld._x, y: gameWorld._y } : null,
            bgLayerPosition: bgLayer ? { x: bgLayer._x, y: bgLayer._y } : null,
            stageSize: { width: Stage.width, height: Stage.height },
            debugMode: _debugMode
        };
    }

    /**
     * 强制立即更新一次（调试用）
     */
    public static function forceUpdate():Void {
        if (!_isInitialized) {
            _logError("Cannot force update: not initialized");
            return;
        }
        
        _logDebug("Force update triggered");
        update();
    }

    // ==================== 内部辅助方法 ====================

    private static function _validateConfig(cfg:Object):Object {
        var validatedConfig:Object = {};
        
        // 复制基本字符串和引用
        validatedConfig.scrollTarget = cfg.scrollTarget || scrollTarget;
        validatedConfig.gameWorld = cfg.gameWorld || gameWorld;
        validatedConfig.bgLayer = cfg.bgLayer || bgLayer;
        
        // 验证数值参数
        validatedConfig.bgWidth = _validateParam("bgWidth", cfg.bgWidth) ? cfg.bgWidth : 
                                 (bgWidth || _paramConstraints.bgWidth.defaultValue);
        validatedConfig.bgHeight = _validateParam("bgHeight", cfg.bgHeight) ? cfg.bgHeight : 
                                  (bgHeight || _paramConstraints.bgHeight.defaultValue);
        validatedConfig.easeFactor = _validateParam("easeFactor", cfg.easeFactor) ? cfg.easeFactor : 
                                    (easeFactor || _paramConstraints.easeFactor.defaultValue);
        validatedConfig.zoomScale = _validateParam("zoomScale", cfg.zoomScale) ? cfg.zoomScale : 
                                   (zoomScale || _paramConstraints.zoomScale.defaultValue);
        
        return validatedConfig;
    }

    private static function _validateParam(paramName:String, value:Number):Boolean {
        // 确保约束配置已初始化
        _initParamConstraints();
        
        var constraint:Object = _paramConstraints[paramName];
        if (!constraint) return true;
        
        return (value >= constraint.min && value <= constraint.max);
    }

    private static function _applyConfig(cfg:Object):Void {
        scrollTarget = cfg.scrollTarget;
        bgWidth = cfg.bgWidth;
        bgHeight = cfg.bgHeight;
        easeFactor = cfg.easeFactor;
        zoomScale = cfg.zoomScale;
        gameWorld = cfg.gameWorld;
        bgLayer = cfg.bgLayer;

        // 初始化缩放状态
        if (gameWorld && !gameWorld.lastScale) {
            gameWorld.lastScale = zoomScale;
        }
    }

    private static function _cloneConfig(cfg:Object):Object {
        var cloned:Object = {};
        for (var key:String in cfg) {
            cloned[key] = cfg[key];
        }
        return cloned;
    }

    private static function _triggerConfigChange(changeType:String, changeData:Object):Void {
        for (var i:Number = 0; i < _configChangeCallbacks.length; i++) {
            var callback:Function = _configChangeCallbacks[i];
            try {
                callback(changeType, changeData);
            } catch (error:Error) {
                _logError("Error in config change callback: " + error.message);
            }
        }
    }

    private static function _formatConfig(cfg:Object):String {
        var parts:Array = [];
        for (var key:String in cfg) {
            if (typeof cfg[key] !== "object" || cfg[key] === null) {
                parts.push(key + ":" + cfg[key]);
            }
        }
        return "{" + parts.join(", ") + "}";
    }

    private static function _logDebug(message:String):Void {
        if (_debugMode) {
            _root.服务器.发布服务器消息("[HorizontalScroller DEBUG] " + message);
        }
    }

    private static function _logError(message:String):Void {
        _root.发布消息("[HorizontalScroller ERROR] " + message);
    }

    // ==================== 修复后的更新逻辑 ====================

    /**
     * 主更新方法（修复版）
     * 
     * 修复内容：
     * 1. 缩放后始终执行边界约束，不依赖offset是否为0
     * 2. 滚动阶段恢复bgLayer._x的同步更新
     */
    public static function update():Void {
        if (!_isInitialized) {
            _logError("Update called before initialization");
            return;
        }

        // —— 1) 先拿到 gameWorld 和 bgLayer（天空盒） ——
        var gameWorld:MovieClip = HorizontalScroller.gameWorld;
        var bgLayer:MovieClip   = HorizontalScroller.bgLayer;
        var bgHeight:Number     = HorizontalScroller.bgHeight;
        var bgWidth:Number      = HorizontalScroller.bgWidth;
        var easeFactor:Number   = HorizontalScroller.easeFactor;
        var zoomScale:Number    = HorizontalScroller.zoomScale;
        var scrollObj:MovieClip = gameWorld[HorizontalScroller.scrollTarget];

        // —— 2) 如果目标不存在或未初始化，则直接 return ——
        if (!scrollObj || scrollObj._x == undefined) {
            _logDebug("ScrollObj not available: " + HorizontalScroller.scrollTarget);
            return;
        }

        // —— 3) 先执行缩放逻辑（ZoomController），得到 newScale 与 worldOffset ——
        var zoomResult:Object = ZoomController.updateScale(scrollObj, gameWorld, bgLayer, easeFactor, zoomScale);
        var newScale:Number   = zoomResult.newScale;
        var offsetX:Number    = zoomResult.offsetX;
        var offsetY:Number    = zoomResult.offsetY;
        var scaleChanged:Boolean = zoomResult.scaleChanged;

        // —— 4) 根据缩放后的背景尺寸与舞台尺寸，计算滚动边界（ScrollBounds） ——
        var stageWidth:Number  = Stage.width;
        var stageHeight:Number = Stage.height - 64; // 顶部 UI 占 64px
        var bounds:Object = ScrollBounds.calculateBounds(
            bgWidth, bgHeight, newScale, stageWidth, stageHeight
        );

        // —— 5) 【修复1】如果缩放发生了，无论offset是否为0都要执行边界约束 ——
        if (scaleChanged) {
            // 计算补偿后的坐标
            var tentativeX:Number = gameWorld._x + offsetX;
            var tentativeY:Number = gameWorld._y + offsetY;

            // 执行边界约束
            var clamped:Object = ScrollBounds.clampPosition(
                tentativeX, tentativeY, bounds, stageWidth, stageHeight
            );

            // 应用约束后的坐标
            gameWorld._x = clamped.clampedX;
            gameWorld._y = clamped.clampedY;
            bgLayer._x = clamped.clampedX;
            bgLayer._y = clamped.clampedY + bgLayer.地平线高度;

            // 立即刷新视差背景
            ParallaxBackground.refreshOnZoom(bgLayer, gameWorld._x);
            
            _logDebug("Scale compensation applied - newScale: " + newScale + 
                     ", offsetX: " + offsetX + ", offsetY: " + offsetY);
        }

        // —— 6) 如果当前背景本身大小（缩放后） 小于等于舞台可视区域，则无需做滚动，直接 return ——
        if (!ScrollBounds.needsScroll(bounds.effBgW, bounds.effBgH, stageWidth, stageHeight)) {
            return;
        }

        // —— 7) 读取滚动容差与中心点常量 ——
        var frameTimer:Object = _root.帧计时器;
        var offsetTolerance:Number = frameTimer.offsetTolerance;

        var LEFT_SCROLL_CENTER:Number     = stageWidth  * 0.5 + 100;
        var RIGHT_SCROLL_CENTER:Number    = stageWidth  * 0.5 - 100;
        var VERTICAL_SCROLL_CENTER:Number = stageHeight - 100;

        // —— 8) 获取 scrollObj 在屏幕上的坐标 —— 
        var pt2:Object = { x:0, y:0 };
        scrollObj.localToGlobal(pt2);

        // —— 9) 根据朝向决定水平目标中心点 —— 
        var isRightDirection:Boolean = (scrollObj._xscale > 0);
        var targetX:Number = isRightDirection ? RIGHT_SCROLL_CENTER : LEFT_SCROLL_CENTER;

        // —— 10) 用 ScrollLogic 来计算 dx/dy —— 
        var scrollParams:Object = ScrollLogic.computeScrollOffsets(
            pt2.x, pt2.y, targetX, VERTICAL_SCROLL_CENTER, offsetTolerance, easeFactor
        );
        var needMoveX:Boolean = scrollParams.needMoveX;
        var needMoveY:Boolean = scrollParams.needMoveY;
        var dx:Number = scrollParams.dx;
        var dy:Number = scrollParams.dy;

        if (!needMoveX && !needMoveY) {
            return;
        }

        // —— 11) 计算未约束的新世界坐标 —— 
        var oldX:Number = gameWorld._x;
        var oldY:Number = gameWorld._y;
        var newX:Number = oldX + dx;
        var newY:Number = oldY + dy;

        // —— 12) 用 ScrollBounds.clampPosition 对 newX/newY 进行约束 —— 
        var clampedFinal:Object = ScrollBounds.clampPosition(
            newX, newY, bounds, stageWidth, stageHeight
        );

        // —— 13) 最终写回 gameWorld 与 bgLayer —— 
        var onScrollX:Boolean = (clampedFinal.clampedX !== oldX);
        var onScrollY:Boolean = (clampedFinal.clampedY !== oldY);

        if (onScrollX) {
            gameWorld._x = clampedFinal.clampedX;
            // 【修复2】恢复bgLayer._x的同步更新，保持天空盒与世界容器一致
            bgLayer._x = clampedFinal.clampedX;
        }
        if (onScrollY) {
            gameWorld._y = clampedFinal.clampedY;
            bgLayer._y = clampedFinal.clampedY + bgLayer.地平线高度;
        }

        // —— 14) 如果启用了后景视差，则在滚动时更新一次后景 —— 
        if (_root.启用后景 && onScrollX) { // 优化：仅在X轴滚动时才更新视差背景
            var currentFrame:Number = frameTimer.当前帧数;
            ParallaxBackground.updateParallax(bgLayer, currentFrame, gameWorld._x);
        }
    }
}