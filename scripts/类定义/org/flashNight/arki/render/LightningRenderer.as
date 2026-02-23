import org.flashNight.arki.bullet.BulletComponent.Config.TeslaRayConfig;
import org.flashNight.arki.spatial.transform.SceneCoordinateManager;

/**
 * LightningRenderer - 闪电/电弧渲染器
 *
 * 专门用于渲染磁暴射线（Tesla Ray）的电弧视觉效果。
 *
 * 核心特性：
 * 1. 分形细分算法 - 生成自然的锯齿状电弧路径
 * 2. 随机分支生成 - 模拟真实闪电的分叉效果
 * 3. 自管理活跃列表 - 不使用 EnhancedCooldownWheel（因其 127 帧限制）
 * 4. 每帧重绘抖动 - 电弧位置每帧随机偏移，产生动态效果
 * 5. 平滑淡出 - 电弧在消失前逐渐变透明
 *
 * 使用方法：
 *   // 生成电弧（通常由 BulletQueueProcessor 在射线命中时调用）
 *   LightningRenderer.spawn(startX, startY, endX, endY, rayConfig);
 *
 *   // 每帧更新（需要在游戏主循环中调用）
 *   LightningRenderer.update();
 *
 *   // 场景切换时清理
 *   LightningRenderer.reset();
 *
 * @version 1.0
 */
class org.flashNight.arki.render.LightningRenderer {

    // ========================================================================
    // 静态常量
    // ========================================================================

    /** 默认射线长度 */
    private static var DEFAULT_RAY_LENGTH:Number = 900;

    /** 默认主电弧颜色（青色） */
    private static var DEFAULT_PRIMARY_COLOR:Number = 0x00FFFF;

    /** 默认辉光颜色（白色） */
    private static var DEFAULT_SECONDARY_COLOR:Number = 0xFFFFFF;

    /** 默认电弧粗细 */
    private static var DEFAULT_THICKNESS:Number = 3;

    /** 默认分支数量 */
    private static var DEFAULT_BRANCH_COUNT:Number = 4;

    /** 默认分支概率 */
    private static var DEFAULT_BRANCH_PROBABILITY:Number = 0.5;

    /** 默认分段长度 */
    private static var DEFAULT_SEGMENT_LENGTH:Number = 25;

    /** 默认抖动幅度 */
    private static var DEFAULT_JITTER:Number = 18;

    /** 默认视觉持续帧数 */
    private static var DEFAULT_VISUAL_DURATION:Number = 30;

    /** 默认淡出帧数 */
    private static var DEFAULT_FADE_DURATION:Number = 15;

    // ========================================================================
    // 静态变量
    // ========================================================================

    /** 活跃电弧列表 */
    private static var _activeArcs:Array = [];

    /** 电弧绘制容器（MovieClip） */
    private static var _container:MovieClip = null;

    /** 电弧 ID 计数器 */
    private static var _arcIdCounter:Number = 0;

    /** 是否已初始化 */
    private static var _initialized:Boolean = false;

    // ========================================================================
    // 初始化方法
    // ========================================================================

    /**
     * 确保渲染器已初始化
     */
    private static function ensureInitialized():Void {
        if (_initialized) return;

        // 创建绘制容器（在 gameworld 的 effect 层或 deadbody 层）
        var parent:MovieClip = _root.gameworld.效果;
        if (parent == null) {
            parent = _root.gameworld.deadbody;
        }
        if (parent == null) {
            parent = _root.gameworld;
        }

        _container = parent.createEmptyMovieClip("lightningContainer", parent.getNextHighestDepth());
        _activeArcs = [];
        _initialized = true;
    }

    // ========================================================================
    // 公共 API
    // ========================================================================

    /**
     * 生成一条电弧
     *
     * @param startX 起点 X 坐标（游戏世界坐标）
     * @param startY 起点 Y 坐标（游戏世界坐标）
     * @param endX 终点 X 坐标（游戏世界坐标）
     * @param endY 终点 Y 坐标（游戏世界坐标）
     * @param config 射线配置对象（TeslaRayConfig），可选
     */
    public static function spawn(startX:Number, startY:Number,
                                  endX:Number, endY:Number,
                                  config:TeslaRayConfig):Void {
        ensureInitialized();

        // 应用场景坐标偏移
        var offset:Object = SceneCoordinateManager.effectOffset;
        var offsetX:Number = (offset != null && offset.x != undefined) ? offset.x : 0;
        var offsetY:Number = (offset != null && offset.y != undefined) ? offset.y : 0;

        // 使用配置或默认值
        var primaryColor:Number = (config != null && !isNaN(config.primaryColor)) ? config.primaryColor : DEFAULT_PRIMARY_COLOR;
        var secondaryColor:Number = (config != null && !isNaN(config.secondaryColor)) ? config.secondaryColor : DEFAULT_SECONDARY_COLOR;
        var thickness:Number = (config != null && !isNaN(config.thickness)) ? config.thickness : DEFAULT_THICKNESS;
        var branchCount:Number = (config != null && !isNaN(config.branchCount)) ? config.branchCount : DEFAULT_BRANCH_COUNT;
        var branchProbability:Number = (config != null && !isNaN(config.branchProbability)) ? config.branchProbability : DEFAULT_BRANCH_PROBABILITY;
        var segmentLength:Number = (config != null && !isNaN(config.segmentLength)) ? config.segmentLength : DEFAULT_SEGMENT_LENGTH;
        var jitter:Number = (config != null && !isNaN(config.jitter)) ? config.jitter : DEFAULT_JITTER;
        var visualDuration:Number = (config != null && !isNaN(config.visualDuration)) ? config.visualDuration : DEFAULT_VISUAL_DURATION;
        var fadeDuration:Number = (config != null && !isNaN(config.fadeOutDuration)) ? config.fadeOutDuration : DEFAULT_FADE_DURATION;

        // 创建电弧 MovieClip
        var arcId:Number = _arcIdCounter++;
        var arcMc:MovieClip = _container.createEmptyMovieClip("arc_" + arcId, _container.getNextHighestDepth());

        // 创建电弧数据对象
        var arc:Object = {
            id: arcId,
            mc: arcMc,
            startX: startX + offsetX,
            startY: startY + offsetY,
            endX: endX + offsetX,
            endY: endY + offsetY,
            primaryColor: primaryColor,
            secondaryColor: secondaryColor,
            thickness: thickness,
            branchCount: branchCount,
            branchProbability: branchProbability,
            segmentLength: segmentLength,
            jitter: jitter,
            visualDuration: visualDuration,
            fadeDuration: fadeDuration,
            age: 0,
            totalDuration: visualDuration + fadeDuration
        };

        // 首次绘制
        renderArc(arc);

        // 添加到活跃列表
        _activeArcs.push(arc);
    }

    /**
     * 每帧更新所有活跃电弧
     *
     * 此方法应在游戏主循环中调用（如 onEnterFrame）。
     * 负责：
     * 1. 推进电弧年龄
     * 2. 活跃期重绘（产生抖动效果）
     * 3. 淡出期调整透明度
     * 4. 过期电弧清理
     */
    public static function update():Void {
        if (!_initialized || _activeArcs.length == 0) return;

        // 反向遍历以便安全删除
        for (var i:Number = _activeArcs.length - 1; i >= 0; --i) {
            var arc:Object = _activeArcs[i];
            arc.age++;

            if (arc.age < arc.visualDuration) {
                // 活跃期：每帧重绘产生抖动效果
                renderArc(arc);
            } else if (arc.age < arc.totalDuration) {
                // 淡出期：降低透明度并重绘
                var fadeProgress:Number = (arc.age - arc.visualDuration) / arc.fadeDuration;
                arc.mc._alpha = 100 * (1 - fadeProgress);
                renderArc(arc);
            } else {
                // 过期：移除
                arc.mc.removeMovieClip();
                _activeArcs.splice(i, 1);
            }
        }
    }

    /**
     * 重置渲染器
     *
     * 清理所有活跃电弧，用于场景切换时调用。
     */
    public static function reset():Void {
        if (!_initialized) return;

        // 清理所有电弧
        for (var i:Number = _activeArcs.length - 1; i >= 0; --i) {
            var arc:Object = _activeArcs[i];
            if (arc.mc != null) {
                arc.mc.removeMovieClip();
            }
        }
        _activeArcs = [];

        // 移除容器
        if (_container != null) {
            _container.removeMovieClip();
            _container = null;
        }

        _initialized = false;
    }

    /**
     * 获取当前活跃电弧数量
     */
    public static function getActiveCount():Number {
        return _activeArcs.length;
    }

    // ========================================================================
    // 私有渲染方法
    // ========================================================================

    /**
     * 渲染单条电弧
     *
     * @param arc 电弧数据对象
     */
    private static function renderArc(arc:Object):Void {
        var mc:MovieClip = arc.mc;

        // 清除之前的绘制
        mc.clear();

        // 生成主电弧路径
        var mainPath:Array = generateArcPath(
            arc.startX, arc.startY,
            arc.endX, arc.endY,
            arc.segmentLength, arc.jitter
        );

        // 绘制辉光层（较粗、较淡、使用次要颜色）
        drawPath(mc, mainPath, arc.secondaryColor, arc.thickness * 3, 30);

        // 绘制主电弧层
        drawPath(mc, mainPath, arc.primaryColor, arc.thickness, 100);

        // 绘制核心层（更细、更亮）
        drawPath(mc, mainPath, 0xFFFFFF, arc.thickness * 0.5, 80);

        // 生成并绘制分支
        if (arc.branchCount > 0) {
            var branchesDrawn:Number = 0;
            var pathLen:Number = mainPath.length;

            for (var i:Number = 1; i < pathLen - 1 && branchesDrawn < arc.branchCount; i++) {
                if (Math.random() < arc.branchProbability) {
                    var branchStart:Object = mainPath[i];

                    // 分支方向：在垂直于主电弧的方向上偏移
                    var dx:Number = arc.endX - arc.startX;
                    var dy:Number = arc.endY - arc.startY;
                    var len:Number = Math.sqrt(dx * dx + dy * dy);
                    if (len == 0) len = 1;

                    // 垂直方向
                    var perpX:Number = -dy / len;
                    var perpY:Number = dx / len;

                    // 随机分支方向（左或右）
                    var sign:Number = (Math.random() > 0.5) ? 1 : -1;

                    // 分支长度（主电弧的 20-40%）
                    var branchLen:Number = len * (0.2 + Math.random() * 0.2);

                    // 分支终点
                    var branchEndX:Number = branchStart.x + (perpX * sign + dx / len * 0.5) * branchLen;
                    var branchEndY:Number = branchStart.y + (perpY * sign + dy / len * 0.5) * branchLen;

                    // 生成分支路径
                    var branchPath:Array = generateArcPath(
                        branchStart.x, branchStart.y,
                        branchEndX, branchEndY,
                        arc.segmentLength * 0.7,
                        arc.jitter * 0.6
                    );

                    // 绘制分支（较细、较淡）
                    drawPath(mc, branchPath, arc.secondaryColor, arc.thickness * 0.6, 50);
                    drawPath(mc, branchPath, arc.primaryColor, arc.thickness * 0.4, 70);

                    branchesDrawn++;
                }
            }
        }
    }

    /**
     * 生成电弧路径（分形细分算法）
     *
     * @param x1 起点 X
     * @param y1 起点 Y
     * @param x2 终点 X
     * @param y2 终点 Y
     * @param segmentLen 分段长度
     * @param jitter 抖动幅度
     * @return Array 路径点数组 [{x, y}, ...]
     */
    private static function generateArcPath(x1:Number, y1:Number,
                                             x2:Number, y2:Number,
                                             segmentLen:Number, jitter:Number):Array {
        var points:Array = [];
        points.push({x: x1, y: y1});

        var dx:Number = x2 - x1;
        var dy:Number = y2 - y1;
        var dist:Number = Math.sqrt(dx * dx + dy * dy);

        if (dist == 0) {
            points.push({x: x2, y: y2});
            return points;
        }

        var segments:Number = Math.ceil(dist / segmentLen);
        if (segments < 2) segments = 2;

        // 归一化方向
        var dirX:Number = dx / dist;
        var dirY:Number = dy / dist;

        // 垂直方向（用于随机偏移）
        var perpX:Number = -dirY;
        var perpY:Number = dirX;

        for (var i:Number = 1; i < segments; i++) {
            var t:Number = i / segments;

            // 沿主方向的基础位置
            var baseX:Number = x1 + dx * t;
            var baseY:Number = y1 + dy * t;

            // 随机垂直偏移
            var offset:Number = (Math.random() - 0.5) * 2 * jitter;

            points.push({
                x: baseX + perpX * offset,
                y: baseY + perpY * offset
            });
        }

        points.push({x: x2, y: y2});
        return points;
    }

    /**
     * 绘制路径
     *
     * @param mc 目标 MovieClip
     * @param path 路径点数组
     * @param color 线条颜色
     * @param thickness 线条粗细
     * @param alpha 透明度（0-100）
     */
    private static function drawPath(mc:MovieClip, path:Array,
                                      color:Number, thickness:Number, alpha:Number):Void {
        if (path.length < 2) return;

        mc.lineStyle(thickness, color, alpha, true, "none", "round", "round");

        var start:Object = path[0];
        mc.moveTo(start.x, start.y);

        for (var i:Number = 1; i < path.length; i++) {
            var pt:Object = path[i];
            mc.lineTo(pt.x, pt.y);
        }
    }
}
