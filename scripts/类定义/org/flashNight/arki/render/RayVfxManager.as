import org.flashNight.arki.bullet.BulletComponent.Config.TeslaRayConfig;
import org.flashNight.arki.spatial.transform.SceneCoordinateManager;
import org.flashNight.arki.render.renderer.TeslaRenderer;
import org.flashNight.arki.render.renderer.PrismRenderer;
import org.flashNight.arki.render.renderer.SpectrumRenderer;
import org.flashNight.arki.render.renderer.WaveRenderer;

/**
 * RayVfxManager - 射线视觉效果管理器 (路由器)
 *
 * 统一管理所有射线渲染风格，提供：
 * • 风格路由：根据 vfxStyle 分发到对应渲染器
 * • 延迟队列：支持 chainDelay 分帧播放
 * • LOD 管理：根据加权渲染成本自动降级
 * • 对象池：减少 GC 压力
 *
 * 架构图：
 *   spawn() → 延迟队列判断 → createArc() → 活跃列表
 *   update() → 处理延迟队列 → 更新活跃电弧 → LOD 检查
 *
 * 支持的视觉风格：
 * • tesla    - 磁暴风格（高频抖动电弧 + 随机分叉）
 * • prism    - 光棱风格（稳定直束 + 呼吸动画）
 * • spectrum - 光谱风格（彩虹渐变 + 颜色滚动）
 * • wave     - 波能风格（正弦波路径 + 脉冲膨胀）
 *
 * SegmentMeta 结构：
 * {
 *     segmentKind: "main" | "chain" | "fork" | "pierce",
 *     hitIndex: 0,           // 当前是第几个命中 (0-based)
 *     intensity: 1.0,        // 强度因子 (可来自 damageMult)
 *     isHit: true,           // 是否命中目标
 *     parentEndX: 100,       // chain/fork: 上一段终点
 *     parentEndY: 200,
 *     hitPoints: []          // pierce 专用：所有命中点坐标
 * }
 *
 * @author FlashNight
 * @version 1.0
 * @see TeslaRayConfig
 * @see TeslaRenderer
 * @see PrismRenderer
 * @see SpectrumRenderer
 * @see WaveRenderer
 */
class org.flashNight.arki.render.RayVfxManager {

    // ════════════════════════════════════════════════════════════════════════
    // 活跃列表与延迟队列
    // ════════════════════════════════════════════════════════════════════════

    /** 活跃电弧列表 */
    private static var _activeArcs:Array = [];

    /** 延迟队列（chainDelay 分帧播放） */
    private static var _delayedSegments:Array = [];

    /** 电弧绘制容器 */
    private static var _container:MovieClip = null;

    /** 电弧 ID 自增计数器 */
    private static var _arcIdCounter:Number = 0;

    /** 初始化标志 */
    private static var _initialized:Boolean = false;

    // ════════════════════════════════════════════════════════════════════════
    // LOD 状态
    // ════════════════════════════════════════════════════════════════════════

    /** 当前 LOD 等级 (0=高, 1=中, 2=低) */
    private static var _currentLOD:Number = 0;

    /** 当前加权渲染成本 */
    private static var _renderCost:Number = 0;

    /** 风格渲染成本权重 */
    private static var STYLE_COST:Object = {
        tesla: 1.5,     // 分支 + 多路径
        prism: 1.0,     // 基础成本
        spectrum: 2.5,  // 多条纹 N 倍 drawcall
        wave: 2.0       // 正弦波分段 + 波纹
    };

    /** LOD 阈值 */
    private static var LOD_THRESHOLD_MEDIUM:Number = 8;   // cost >= 8 → LOD 1
    private static var LOD_THRESHOLD_LOW:Number = 25;     // cost >= 25 → LOD 2

    // ════════════════════════════════════════════════════════════════════════
    // 对象池
    // ════════════════════════════════════════════════════════════════════════

    /** 路径点对象池 {x, y, t} */
    private static var _ptPool:Array = [];
    private static var _ptIdx:Number = 0;

    /** 路径数组池 */
    private static var _arrPool:Array = [];
    private static var _arrIdx:Number = 0;

    /** 路径描述对象池 {path, isMain, isFork} */
    private static var _pdPool:Array = [];
    private static var _pdIdx:Number = 0;

    // ════════════════════════════════════════════════════════════════════════
    // 初始化
    // ════════════════════════════════════════════════════════════════════════

    /**
     * 确保渲染器已初始化
     */
    private static function ensureInitialized():Void {
        if (_initialized) return;

        var parent:MovieClip = _root.gameworld.效果;
        if (parent == null) parent = _root.gameworld.deadbody;
        if (parent == null) parent = _root.gameworld;

        _container = parent.createEmptyMovieClip("rayVfxContainer", parent.getNextHighestDepth());
        _activeArcs = [];
        _delayedSegments = [];
        _initialized = true;
    }

    // ════════════════════════════════════════════════════════════════════════
    // 公共 API
    // ════════════════════════════════════════════════════════════════════════

    /**
     * 生成射线视觉效果
     *
     * 【关键】config 应已在 fromXML() 阶段完成预设解析，
     * spawn 时仅读取，不做 for-in 合并（避免高频 spawn 的 GC 开销）。
     *
     * @param startX 起点 X 坐标（游戏世界坐标）
     * @param startY 起点 Y 坐标
     * @param endX   终点 X 坐标
     * @param endY   终点 Y 坐标
     * @param config 射线配置对象 (TeslaRayConfig)
     * @param meta   段上下文 (SegmentMeta)，可为 null 使用默认值
     */
    public static function spawn(startX:Number, startY:Number,
                                  endX:Number, endY:Number,
                                  config:TeslaRayConfig, meta:Object):Void {
        ensureInitialized();

        // 构建默认 meta
        if (meta == null) {
            meta = {
                segmentKind: "main",
                hitIndex: 0,
                intensity: 1.0,
                isHit: true,
                parentEndX: startX,
                parentEndY: startY,
                hitPoints: null
            };
        }

        // 延迟策略：按 segmentKind 区分
        var delay:Number = 0;
        var chainDelay:Number = (config != null) ? config.chainDelay : 0;

        if (meta.segmentKind == "chain" && meta.hitIndex > 0 && chainDelay > 0) {
            // chain: 逐段推进 (hitIndex × chainDelay)
            delay = chainDelay * meta.hitIndex;
        } else if (meta.segmentKind == "fork" && meta.hitIndex > 0 && chainDelay > 0) {
            // fork: 统一延迟 1 帧（主命中先，折射后）
            delay = 1;
        }
        // pierce: 不延迟 (delay = 0)

        if (delay > 0) {
            _delayedSegments.push({
                startX: startX,
                startY: startY,
                endX: endX,
                endY: endY,
                config: config,
                meta: meta,
                delayRemaining: delay
            });
            return;
        }

        createArc(startX, startY, endX, endY, config, meta);
    }

    /**
     * 每帧更新
     *
     * 处理顺序：
     * 1. 处理延迟队列 (chainDelay 逐段推进)
     * 2. 更新活跃电弧 (age++, 重绘/淡出)
     * 3. LOD 检查 (基于加权成本)
     */
    public static function update():Void {
        if (!_initialized) return;

        // 1. 处理延迟队列
        processDelayedSegments();

        // 2. 更新活跃电弧
        updateActiveArcs();

        // 3. LOD 检查
        updateLOD();
    }

    /**
     * 重置渲染器，清理所有活跃电弧
     */
    public static function reset():Void {
        if (!_initialized) return;

        // 清理活跃电弧
        for (var i:Number = _activeArcs.length - 1; i >= 0; --i) {
            if (_activeArcs[i].mc != null) {
                _activeArcs[i].mc.removeMovieClip();
            }
        }
        _activeArcs = [];
        _delayedSegments = [];

        // 清理容器
        if (_container != null) {
            _container.removeMovieClip();
            _container = null;
        }

        _initialized = false;
        _currentLOD = 0;
        _renderCost = 0;
    }

    /**
     * 获取当前活跃电弧数量
     */
    public static function getActiveCount():Number {
        return _activeArcs.length;
    }

    /**
     * 获取当前 LOD 等级
     */
    public static function getCurrentLOD():Number {
        return _currentLOD;
    }

    /**
     * 获取当前渲染成本
     */
    public static function getRenderCost():Number {
        return _renderCost;
    }

    // ════════════════════════════════════════════════════════════════════════
    // 内部方法：电弧创建与更新
    // ════════════════════════════════════════════════════════════════════════

    /**
     * 创建电弧对象并立即渲染
     */
    private static function createArc(startX:Number, startY:Number,
                                       endX:Number, endY:Number,
                                       config:TeslaRayConfig, meta:Object):Void {
        // 应用场景坐标偏移
        var offset:Object = SceneCoordinateManager.effectOffset;
        var offsetX:Number = (offset != null && offset.x != undefined) ? offset.x : 0;
        var offsetY:Number = (offset != null && offset.y != undefined) ? offset.y : 0;

        var arcId:Number = _arcIdCounter++;
        var arcMc:MovieClip = _container.createEmptyMovieClip("arc_" + arcId, _container.getNextHighestDepth());

        // 开启加色混合模式
        if (arcMc.blendMode !== undefined) {
            arcMc.blendMode = "add";
        }

        // 获取 vfxStyle
        var vfxStyle:String = (config != null && config.vfxStyle != null) ? config.vfxStyle : "tesla";

        // 构建电弧数据对象
        var arc:Object = {
            id: arcId,
            mc: arcMc,
            startX: startX + offsetX,
            startY: startY + offsetY,
            endX: endX + offsetX,
            endY: endY + offsetY,
            config: config,
            meta: meta,
            vfxStyle: vfxStyle,
            age: 0
        };

        // 从 config 读取时间参数
        arc.visualDuration = (config != null && !isNaN(config.visualDuration)) ? config.visualDuration : 5;
        arc.fadeDuration = (config != null && !isNaN(config.fadeOutDuration)) ? config.fadeOutDuration : 3;
        arc.totalDuration = arc.visualDuration + arc.fadeDuration;

        // 首帧立即渲染
        renderArc(arc);
        _activeArcs.push(arc);
    }

    /**
     * 处理延迟队列 (swap-delete 避免 O(n) splice)
     */
    private static function processDelayedSegments():Void {
        var len:Number = _delayedSegments.length;
        for (var i:Number = len - 1; i >= 0; i--) {
            var seg:Object = _delayedSegments[i];
            seg.delayRemaining--;

            if (seg.delayRemaining <= 0) {
                createArc(seg.startX, seg.startY, seg.endX, seg.endY, seg.config, seg.meta);
                // swap-delete: O(1) 删除
                var last:Number = _delayedSegments.length - 1;
                if (i < last) {
                    _delayedSegments[i] = _delayedSegments[last];
                }
                _delayedSegments.length = last;
            }
        }
    }

    /**
     * 更新活跃电弧
     */
    private static function updateActiveArcs():Void {
        for (var i:Number = _activeArcs.length - 1; i >= 0; --i) {
            var arc:Object = _activeArcs[i];
            arc.age++;

            if (arc.age <= arc.visualDuration) {
                // 活跃期：每帧重绘 + 随机爆闪
                renderArc(arc);
                arc.mc._alpha = 70 + Math.random() * 30;
            } else if (arc.age <= arc.totalDuration) {
                // 淡出期：线性递减透明度
                var fadeProgress:Number = (arc.age - arc.visualDuration) / arc.fadeDuration;
                arc.mc._alpha = 100 * (1 - fadeProgress);
            } else {
                // 过期销毁：swap-delete O(1)
                arc.mc.removeMovieClip();
                var last:Number = _activeArcs.length - 1;
                if (i < last) {
                    _activeArcs[i] = _activeArcs[last];
                }
                _activeArcs.length = last;
            }
        }
    }

    /**
     * 更新 LOD (基于加权成本)
     */
    private static function updateLOD():Void {
        // 计算加权成本 (包含活跃 + 延迟队列)
        _renderCost = 0;

        var i:Number;
        for (i = 0; i < _activeArcs.length; i++) {
            var style:String = _activeArcs[i].vfxStyle || "tesla";
            _renderCost += STYLE_COST[style] || 1.0;
        }
        for (i = 0; i < _delayedSegments.length; i++) {
            var dConfig:TeslaRayConfig = _delayedSegments[i].config;
            var dStyle:String = (dConfig != null && dConfig.vfxStyle != null) ? dConfig.vfxStyle : "tesla";
            _renderCost += STYLE_COST[dStyle] || 1.0;
        }

        // 基于加权成本判定 LOD
        if (_renderCost >= LOD_THRESHOLD_LOW) {
            _currentLOD = 2;
        } else if (_renderCost >= LOD_THRESHOLD_MEDIUM) {
            _currentLOD = 1;
        } else {
            _currentLOD = 0;
        }
    }

    // ════════════════════════════════════════════════════════════════════════
    // 渲染核心：风格路由
    // ════════════════════════════════════════════════════════════════════════

    /**
     * 渲染电弧（根据 vfxStyle 路由到对应渲染器）
     */
    private static function renderArc(arc:Object):Void {
        var mc:MovieClip = arc.mc;
        mc.clear();

        // 重置对象池
        resetPools();

        // 根据 vfxStyle 路由
        var style:String = arc.vfxStyle || "tesla";

        switch (style) {
            case "prism":
                PrismRenderer.render(arc, _currentLOD, mc);
                break;
            case "spectrum":
                SpectrumRenderer.render(arc, _currentLOD, mc);
                break;
            case "wave":
                WaveRenderer.render(arc, _currentLOD, mc);
                break;
            case "tesla":
            default:
                TeslaRenderer.render(arc, _currentLOD, mc);
                break;
        }
    }

    // ════════════════════════════════════════════════════════════════════════
    // 对象池操作（供渲染器使用）
    // ════════════════════════════════════════════════════════════════════════

    /** 重置所有池的使用计数 */
    public static function resetPools():Void {
        _ptIdx = 0;
        _arrIdx = 0;
        _pdIdx = 0;
    }

    /** 从池中获取或创建路径点对象 */
    public static function pt(x:Number, y:Number, t:Number):Object {
        var p:Object;
        if (_ptIdx < _ptPool.length) {
            p = _ptPool[_ptIdx];
            p.x = x; p.y = y; p.t = t;
        } else {
            p = {x: x, y: y, t: t};
            _ptPool[_ptIdx] = p;
        }
        _ptIdx++;
        return p;
    }

    /** 从池中获取或创建干净数组 */
    public static function poolArr():Array {
        var a:Array;
        if (_arrIdx < _arrPool.length) {
            a = _arrPool[_arrIdx];
            a.length = 0;
        } else {
            a = [];
            _arrPool[_arrIdx] = a;
        }
        _arrIdx++;
        return a;
    }

    /** 从池中获取或创建路径描述对象 */
    public static function pd(path:Array, isMain:Boolean, isFork:Boolean):Object {
        var d:Object;
        if (_pdIdx < _pdPool.length) {
            d = _pdPool[_pdIdx];
            d.path = path; d.isMain = isMain; d.isFork = isFork;
        } else {
            d = {path: path, isMain: isMain, isFork: isFork};
            _pdPool[_pdIdx] = d;
        }
        _pdIdx++;
        return d;
    }

    /**
     * 绘制折线路径（公共方法，供各渲染器使用）
     */
    public static function drawPath(mc:MovieClip, path:Array,
                                     color:Number, thickness:Number, alpha:Number):Void {
        if (path.length < 2) return;

        mc.lineStyle(thickness, color, alpha, true, "normal", "none", "miter", 3);
        mc.moveTo(path[0].x, path[0].y);

        for (var i:Number = 1; i < path.length; i++) {
            mc.lineTo(path[i].x, path[i].y);
        }
    }

    /**
     * 绘制圆形（用于 Wave 的命中点波纹）
     */
    public static function drawCircle(mc:MovieClip, cx:Number, cy:Number,
                                       radius:Number, color:Number, alpha:Number):Void {
        mc.lineStyle(2, color, alpha, true, "normal", "none", "round");
        mc.moveTo(cx + radius, cy);

        // 使用 8 段近似圆
        var segments:Number = 8;
        var angleStep:Number = (2 * Math.PI) / segments;
        for (var i:Number = 1; i <= segments; i++) {
            var angle:Number = i * angleStep;
            mc.lineTo(cx + Math.cos(angle) * radius, cy + Math.sin(angle) * radius);
        }
    }
}
