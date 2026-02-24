import org.flashNight.arki.bullet.BulletComponent.Config.TeslaRayConfig;
import org.flashNight.arki.spatial.transform.SceneCoordinateManager;

/**
 * LightningRenderer - 闪电/电弧渲染器
 *
 * 专门用于渲染磁暴射线（Tesla Ray）的电弧视觉效果，复刻红警2磁暴线圈的高压放电美学。
 *
 * ═══════════════════════════════════════════════════════════════════════════════
 * 【v5.0 核心算法：纺锤约束 (Spindle Containment)】
 * ═══════════════════════════════════════════════════════════════════════════════
 *
 * 1. 全局正弦包络 (Global Sinusoidal Envelope)
 *    ─────────────────────────────────────────
 *    所有电弧路径点的横向抖动受 Math.sin(t * PI) 约束：
 *
 *         抖动幅度
 *            ▲
 *            │      ╭───────╮
 *            │    ╱           ╲
 *            │  ╱               ╲
 *            │╱                   ╲
 *        ────┼─────────────────────────► 进度 t
 *           0.0      0.5         1.0
 *          枪口      中点        目标
 *
 *    - t=0 (枪口): sin(0) = 0，抖动归零，电弧精准从发射点出发
 *    - t=0.5 (中点): sin(π/2) = 1，抖动最大，电弧最狂野
 *    - t=1 (目标): sin(π) = 0，抖动归零，电弧精准命中目标
 *
 *    视觉效果：电弧形成一个纺锤形的约束场，两端收敛、中间膨胀。
 *
 * 2. 内收型游离分叉 (Inward-Converging Forks)
 *    ─────────────────────────────────────────
 *    分支不再向外放射发散，而是：
 *    - 从主干中间节点分裂
 *    - 顺着主轴方向向目标延伸 15%~30% 射程
 *    - 在到达目标前强制中断，模拟能量耗散
 *    - 同样受纺锤包络约束，不会飞出主光束范围
 *
 * 3. 三层渲染架构 (Triple-Layer Rendering)
 *    ─────────────────────────────────────────
 *    Layer 1: 底层宽域泛光 - 粗线条、低透明度、营造光晕
 *    Layer 2: 中层电离辉光 - 中等粗细、主色调、核心视觉
 *    Layer 3: 顶层白热内核 - 细线条、纯白色、高亮焦点
 *
 *    统一按图层顺序绘制，避免路径交叉导致的视觉发虚。
 *
 * ═══════════════════════════════════════════════════════════════════════════════
 * 【生命周期管理】
 * ═══════════════════════════════════════════════════════════════════════════════
 *
 * 自管理活跃列表（非 EnhancedCooldownWheel），支持任意帧数持续时间：
 *
 *   spawn() ──► 活跃期 (每帧重绘+爆闪) ──► 淡出期 (alpha递减) ──► 销毁
 *              │← visualDuration →│← fadeDuration →│
 *
 * 集成点：
 *   - 帧计时器 frameEnd 事件调用 update()
 *   - 场景切换 SceneChanged 事件调用 reset()
 *
 * ═══════════════════════════════════════════════════════════════════════════════
 * 【使用方法】
 * ═══════════════════════════════════════════════════════════════════════════════
 *
 *   // 生成电弧（由 BulletQueueProcessor 在射线命中时调用）
 *   LightningRenderer.spawn(startX, startY, endX, endY, rayConfig);
 *
 *   // 每帧更新（已集成到帧计时器 frameEnd 事件）
 *   LightningRenderer.update();
 *
 *   // 场景切换时清理（已集成到 SceneChanged 事件）
 *   LightningRenderer.reset();
 *
 * @author FlashNight
 * @version 5.0
 * @see TeslaRayConfig
 * @see TeslaRayLifecycle
 * @see BulletQueueProcessor (FLAG_RAY 分支)
 */
class org.flashNight.arki.render.LightningRenderer {

    // ════════════════════════════════════════════════════════════════════════
    // 默认配置常量
    // ════════════════════════════════════════════════════════════════════════

    /** 默认射线长度（像素） */
    private static var DEFAULT_RAY_LENGTH:Number = 900;

    /** 默认主电弧颜色（青色，模拟高压电离空气） */
    private static var DEFAULT_PRIMARY_COLOR:Number = 0x00FFFF;

    /** 默认辉光/内核颜色（纯白，模拟超高温等离子体） */
    private static var DEFAULT_SECONDARY_COLOR:Number = 0xFFFFFF;

    /** 默认电弧基础粗细（像素，实际渲染会按图层倍增） */
    private static var DEFAULT_THICKNESS:Number = 3;

    /** 默认分支总数（含主干，主干固定2条，剩余为游离分叉） */
    private static var DEFAULT_BRANCH_COUNT:Number = 4;

    /** 默认游离分叉生成概率 (0.0~1.0) */
    private static var DEFAULT_BRANCH_PROB:Number = 0.5;

    /** 默认分段长度（像素，控制电弧折点密度） */
    private static var DEFAULT_SEGMENT_LENGTH:Number = 35;

    /** 默认横向抖动幅度（像素，受纺锤包络调制） */
    private static var DEFAULT_JITTER:Number = 40;

    /** 默认活跃期帧数（每帧重绘+爆闪效果） */
    private static var DEFAULT_VISUAL_DURATION:Number = 5;

    /** 默认淡出期帧数（alpha 线性递减至 0） */
    private static var DEFAULT_FADE_DURATION:Number = 3;

    // ════════════════════════════════════════════════════════════════════════
    // 运行时状态
    // ════════════════════════════════════════════════════════════════════════

    /** 活跃电弧列表（自管理，不依赖 EnhancedCooldownWheel） */
    private static var _activeArcs:Array = [];

    /** 电弧绘制容器（挂载于 gameworld.效果 层） */
    private static var _container:MovieClip = null;

    /** 电弧 ID 自增计数器（用于 MovieClip 命名） */
    private static var _arcIdCounter:Number = 0;

    /** 初始化标志（延迟初始化，首次 spawn 时触发） */
    private static var _initialized:Boolean = false;

    // ════════════════════════════════════════════════════════════════════════
    // 对象池（减少 renderArc 每帧临时对象分配的 GC 压力）
    // ════════════════════════════════════════════════════════════════════════

    /** 路径点对象池 {x, y, t} */
    private static var _ptPool:Array = [];
    /** 路径点池当前使用量 */
    private static var _ptIdx:Number = 0;

    /** 路径数组池 (Array[]) */
    private static var _arrPool:Array = [];
    /** 路径数组池当前使用量 */
    private static var _arrIdx:Number = 0;

    /** 路径描述对象池 {path, isMain, isFork} */
    private static var _pdPool:Array = [];
    /** 路径描述池当前使用量 */
    private static var _pdIdx:Number = 0;

    // ════════════════════════════════════════════════════════════════════════
    // 初始化
    // ════════════════════════════════════════════════════════════════════════

    /**
     * 确保渲染器已初始化（延迟初始化模式）
     *
     * 容器层级优先级：gameworld.效果 > gameworld.deadbody > gameworld
     * 这确保电弧绑定在正确的渲染层，不被其他元素遮挡。
     */
    private static function ensureInitialized():Void {
        if (_initialized) return;
        var parent:MovieClip = _root.gameworld.效果;
        if (parent == null) parent = _root.gameworld.deadbody;
        if (parent == null) parent = _root.gameworld;

        _container = parent.createEmptyMovieClip("lightningContainer", parent.getNextHighestDepth());
        _activeArcs = [];
        _initialized = true;
    }

    // ════════════════════════════════════════════════════════════════════════
    // 公共 API
    // ════════════════════════════════════════════════════════════════════════

    /**
     * 生成一条电弧
     *
     * 由 BulletQueueProcessor 的 FLAG_RAY 分支在射线命中时调用。
     * 电弧从起点延伸到终点，使用纺锤约束算法确保两端收敛。
     *
     * @param startX 起点 X 坐标（游戏世界坐标，通常为枪口位置）
     * @param startY 起点 Y 坐标（游戏世界坐标）
     * @param endX   终点 X 坐标（游戏世界坐标，通常为命中点）
     * @param endY   终点 Y 坐标（游戏世界坐标）
     * @param config 射线配置对象（TeslaRayConfig），可为 null 使用默认值
     */
    public static function spawn(startX:Number, startY:Number,
                                  endX:Number, endY:Number,
                                  config:TeslaRayConfig):Void {
        ensureInitialized();

        // 应用场景坐标偏移（处理地图滚动等情况）
        var offset:Object = SceneCoordinateManager.effectOffset;
        var offsetX:Number = (offset != null && offset.x != undefined) ? offset.x : 0;
        var offsetY:Number = (offset != null && offset.y != undefined) ? offset.y : 0;

        var arcId:Number = _arcIdCounter++;
        var arcMc:MovieClip = _container.createEmptyMovieClip("arc_" + arcId, _container.getNextHighestDepth());

        // 开启加色混合模式 (Additive Blending)
        // 使电弧叠加时产生过曝的等离子体高光效果
        if (arcMc.blendMode !== undefined) {
            arcMc.blendMode = "add";
        }

        // 构建电弧数据对象，合并配置与默认值
        var arc:Object = {
            id: arcId,
            mc: arcMc,
            startX: startX + offsetX,
            startY: startY + offsetY,
            endX: endX + offsetX,
            endY: endY + offsetY,
            primaryColor: (config != null && !isNaN(config.primaryColor)) ? config.primaryColor : DEFAULT_PRIMARY_COLOR,
            secondaryColor: (config != null && !isNaN(config.secondaryColor)) ? config.secondaryColor : DEFAULT_SECONDARY_COLOR,
            thickness: (config != null && !isNaN(config.thickness)) ? config.thickness : DEFAULT_THICKNESS,
            branchCount: (config != null && !isNaN(config.branchCount)) ? config.branchCount : DEFAULT_BRANCH_COUNT,
            branchProbability: (config != null && !isNaN(config.branchProbability)) ? config.branchProbability : DEFAULT_BRANCH_PROB,
            segmentLength: (config != null && !isNaN(config.segmentLength)) ? config.segmentLength : DEFAULT_SEGMENT_LENGTH,
            jitter: (config != null && !isNaN(config.jitter)) ? config.jitter : DEFAULT_JITTER,
            visualDuration: (config != null && !isNaN(config.visualDuration)) ? config.visualDuration : DEFAULT_VISUAL_DURATION,
            fadeDuration: (config != null && !isNaN(config.fadeOutDuration)) ? config.fadeOutDuration : DEFAULT_FADE_DURATION,
            age: 0
        };
        arc.totalDuration = arc.visualDuration + arc.fadeDuration;

        // 首帧立即渲染
        renderArc(arc);
        _activeArcs.push(arc);
    }

    /**
     * 每帧更新所有活跃电弧
     *
     * 此方法由帧计时器的 frameEnd 事件调用。
     *
     * 生命周期状态机：
     *   age <= visualDuration  → 活跃期：每帧重绘 + 随机爆闪 (alpha 70~100)
     *   age <= totalDuration   → 淡出期：停止重绘 + alpha 线性递减
     *   age > totalDuration    → 销毁：移除 MovieClip，从列表中剔除
     */
    public static function update():Void {
        if (!_initialized || _activeArcs.length == 0) return;

        // 反向遍历以便安全删除
        for (var i:Number = _activeArcs.length - 1; i >= 0; --i) {
            var arc:Object = _activeArcs[i];
            arc.age++;

            if (arc.age <= arc.visualDuration) {
                // 活跃期：每帧重绘产生路径抖动 + 随机爆闪模拟电弧不稳定性
                // 注意：使用 <= 使 visualDuration=N 实际产生 N+1 帧活跃渲染
                // （spawn 首帧 age=0 + update 中 age 1..N 共 N 帧），这是有意为之
                renderArc(arc);
                arc.mc._alpha = 70 + Math.random() * 30;
            } else if (arc.age <= arc.totalDuration) {
                // 淡出期：线性递减透明度，保持最后一帧的路径形态
                // 【注意】若 fadeDuration=0 会产生除零（Infinity），AS2 不崩溃，
                // _alpha 被 Flash Player 自动 clamp 到 0~100，表现为立即消失，可接受。
                var fadeProgress:Number = (arc.age - arc.visualDuration) / arc.fadeDuration;
                arc.mc._alpha = 100 * (1 - fadeProgress);
            } else {
                // 过期销毁：swap-delete O(1)，避免 splice O(n) 的元素移动开销
                // 反向遍历保证被换入位置 i 的元素（来自更高索引）已处理过
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
     * 重置渲染器，清理所有活跃电弧
     *
     * 此方法由帧计时器的 SceneChanged 事件调用，
     * 确保场景切换时不会残留跨场景的电弧。
     */
    public static function reset():Void {
        if (!_initialized) return;
        for (var i:Number = _activeArcs.length - 1; i >= 0; --i) {
            if (_activeArcs[i].mc != null) _activeArcs[i].mc.removeMovieClip();
        }
        _activeArcs = [];
        if (_container != null) {
            _container.removeMovieClip();
            _container = null;
        }
        _initialized = false;
    }

    /**
     * 获取当前活跃电弧数量（调试/性能监控用）
     * @return 活跃电弧数量
     */
    public static function getActiveCount():Number {
        return _activeArcs.length;
    }

    // ════════════════════════════════════════════════════════════════════════
    // 对象池操作（内联级轻量方法）
    // ════════════════════════════════════════════════════════════════════════

    /** 重置所有池的使用计数（每次 renderArc 调用前执行） */
    private static function resetPools():Void {
        _ptIdx = 0;
        _arrIdx = 0;
        _pdIdx = 0;
    }

    /** 从池中获取或创建路径点对象 */
    private static function pt(x:Number, y:Number, t:Number):Object {
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
    private static function poolArr():Array {
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
    private static function pd(path:Array, isMain:Boolean, isFork:Boolean):Object {
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

    // ════════════════════════════════════════════════════════════════════════
    // 渲染核心：纺锤约束算法 (Spindle Containment Algorithm)
    // ════════════════════════════════════════════════════════════════════════

    /**
     * 渲染单条电弧的完整视觉效果
     *
     * 渲染流程：
     *   1. 生成主干路径（1~2条贯穿全程的核心电弧）
     *   2. 生成游离分叉（从主干节点分裂，向前延伸后中断）
     *   3. 按图层顺序统一绘制（避免路径交叉导致的视觉发虚）
     *
     * 三层渲染架构：
     *   ┌─────────────────────────────────────────────────────────────┐
     *   │ Layer 3: 白热内核   thickness×0.8  secondaryColor  α=100   │ ← 最上层
     *   │ Layer 2: 电离辉光   thickness×2.0  primaryColor    α=80    │
     *   │ Layer 1: 宽域泛光   thickness×4.5  primaryColor    α=30    │ ← 最下层
     *   └─────────────────────────────────────────────────────────────┘
     *
     * @param arc 电弧数据对象
     */
    private static function renderArc(arc:Object):Void {
        var mc:MovieClip = arc.mc;
        mc.clear();

        // 重置对象池（本次 renderArc 的所有临时对象从池中分配）
        resetPools();

        // 解析分支配置
        var strands:Number = isNaN(arc.branchCount) ? 4 : Math.max(1, arc.branchCount);
        var prob:Number = isNaN(arc.branchProbability) ? 0.5 : arc.branchProbability;

        // 计算电弧方向向量
        var dx:Number = arc.endX - arc.startX;
        var dy:Number = arc.endY - arc.startY;
        var dist:Number = Math.sqrt(dx * dx + dy * dy);
        if (dist == 0) return;

        // 路径收集器：从池中获取，避免每帧 new Array
        var pathsToDraw:Array = poolArr();
        var mainPaths:Array = poolArr();

        // ─────────────────────────────────────────────────────────────
        // 阶段 1：生成主干电弧（贯穿 t=0.0 → t=1.0 的全长路径）
        // ─────────────────────────────────────────────────────────────
        // 主干数量：最多 2 条，作为磁暴核心视觉
        var mainHitCount:Number = Math.min(strands, 2);
        for (var i:Number = 0; i < mainHitCount; i++) {
            var isMain:Boolean = (i == 0);
            // 第一条主干使用标准抖动，第二条增加 30% 抖动以产生层次感
            var mainPath:Array = generateSpindlePath(arc, 0.0, 1.0, isMain ? 1.0 : 1.3, null);
            pathsToDraw.push(pd(mainPath, isMain, false));
            mainPaths.push(mainPath);
        }

        // ─────────────────────────────────────────────────────────────
        // 阶段 2：生成游离分叉（从主干中间节点分裂，向前延伸后中断）
        // ─────────────────────────────────────────────────────────────
        var forkCount:Number = strands - mainHitCount;
        for (var f:Number = 0; f < forkCount; f++) {
            if (Math.random() <= prob) {
                // 随机选择一条主干作为父路径
                var parentPath:Array = mainPaths[Math.floor(Math.random() * mainPaths.length)];
                var maxIdx:Number = parentPath.length - 2;
                if (maxIdx < 1) continue;

                // 从父路径的中间节点分裂（排除首尾端点）
                var nodeIdx:Number = 1 + Math.floor(Math.random() * maxIdx);
                var startNode:Object = parentPath[nodeIdx];

                // 分叉只延伸 15%~30% 射程，在到达目标前强制中断
                // 模拟电弧分支在空气中能量耗散的物理现象
                var endT:Number = startNode.t + 0.15 + Math.random() * 0.15;
                if (endT > 0.95) endT = 0.95;

                // 生成分叉路径（抖动倍率 1.5，更狂野的视觉）
                var forkPath:Array = generateSpindlePath(arc, startNode.t, endT, 1.5, startNode);
                if (forkPath.length > 1) {
                    pathsToDraw.push(pd(forkPath, false, true));
                }
            }
        }

        // ─────────────────────────────────────────────────────────────
        // 阶段 3：按图层顺序统一绘制（底层先画，顶层后画）
        // ─────────────────────────────────────────────────────────────

        // Layer 1: 底层宽域泛光（营造电弧周围的辐射光晕）
        for (var p1:Number = 0; p1 < pathsToDraw.length; p1++) {
            var pathData1:Object = pathsToDraw[p1];
            var thick1:Number = arc.thickness * (pathData1.isMain ? 4.5 : 3.0);
            var alpha1:Number = pathData1.isFork ? 20 : 30;
            drawPath(mc, pathData1.path, arc.primaryColor, thick1, alpha1);
        }

        // Layer 2: 中层电离辉光（主色调，核心视觉表现）
        for (var p2:Number = 0; p2 < pathsToDraw.length; p2++) {
            var pathData2:Object = pathsToDraw[p2];
            var thick2:Number = arc.thickness * (pathData2.isMain ? 2.0 : 1.2);
            var alpha2:Number = pathData2.isFork ? 60 : 80;
            drawPath(mc, pathData2.path, arc.primaryColor, thick2, alpha2);
        }

        // Layer 3: 顶层白热内核（纯白高亮，模拟超高温等离子体）
        for (var p3:Number = 0; p3 < pathsToDraw.length; p3++) {
            var pathData3:Object = pathsToDraw[p3];
            if (pathData3.isMain || (!pathData3.isFork && Math.random() > 0.3)) {
                // 主干和部分副干：标准白芯
                drawPath(mc, pathData3.path, arc.secondaryColor, arc.thickness * 0.8, 100);
            } else if (pathData3.isFork) {
                // 游离分叉：极细白芯，强调其能量衰减
                drawPath(mc, pathData3.path, arc.secondaryColor, arc.thickness * 0.3, 70);
            }
        }
    }

    /**
     * 生成纺锤约束路径（核心算法）
     *
     * 纺锤约束原理：
     *   所有路径点的横向抖动幅度受全局进度 t 的正弦函数约束：
     *   offset_max = jitter × sin(t × π)
     *
     *   这确保：
     *   - t=0 (枪口): 抖动为 0，电弧精准从发射点出发
     *   - t=0.5 (中点): 抖动最大，电弧最狂野
     *   - t=1 (目标): 抖动为 0，电弧精准命中目标
     *
     * 轴向抖动 (Axial Jitter)：
     *   除横向偏移外，节点在轴向上也有微小随机偏移，
     *   打破等距分布的机械感，产生更自然的锯齿折角。
     *
     * @param arc        电弧数据对象
     * @param startT     路径起始全局进度 (0.0~1.0)
     * @param endT       路径结束全局进度 (0.0~1.0)
     * @param jitterMult 抖动倍率（1.0=标准，>1.0=更狂野）
     * @param startNode  分叉起始节点（null 表示从电弧起点开始）
     * @return           路径点数组 [{x, y, t}, ...]
     */
    private static function generateSpindlePath(arc:Object, startT:Number, endT:Number,
                                                 jitterMult:Number, startNode:Object):Array {
        // 计算方向向量和垂直向量
        var dx:Number = arc.endX - arc.startX;
        var dy:Number = arc.endY - arc.startY;
        var totalDist:Number = Math.sqrt(dx * dx + dy * dy);
        var perpX:Number = -dy / totalDist;  // 垂直方向 X 分量
        var perpY:Number = dx / totalDist;   // 垂直方向 Y 分量

        var points:Array = poolArr();

        // 起始点：分叉从父节点无缝连接，主干从电弧起点开始
        if (startNode != null) {
            points.push(pt(startNode.x, startNode.y, startNode.t));
        } else {
            points.push(pt(arc.startX, arc.startY, 0.0));
        }

        // 计算分段参数
        var pathDist:Number = totalDist * (endT - startT);
        var segLen:Number = Math.max(arc.segmentLength, 20);
        // 分叉使用更短的分段，产生尖端毛刺感
        if (startNode != null) segLen *= 0.8;

        var segments:Number = Math.max(2, Math.ceil(pathDist / segLen));

        // 生成中间节点
        for (var i:Number = 1; i <= segments; i++) {
            var localT:Number = i / segments;

            // 轴向抖动：非末端节点在轴向上微小偏移
            if (i < segments) {
                localT += (Math.random() - 0.5) * (0.8 / segments);
            }

            // 映射到全局进度
            var globalT:Number = startT + (endT - startT) * localT;

            // ═══════════════════════════════════════════════════════════
            // 【灵魂机制】全局正弦波纺锤包络
            // env = sin(globalT × π)
            // 在 t=0 和 t=1 处强制归零，约束所有横向抖动
            // ═══════════════════════════════════════════════════════════
            var env:Number = Math.sin(globalT * Math.PI);

            // 计算基础坐标（沿电弧主轴的位置）
            var baseX:Number = arc.startX + dx * globalT;
            var baseY:Number = arc.startY + dy * globalT;
            var offset:Number = 0;

            // 端点精度保护：强制锁死首尾坐标，避免浮点误差导致脱节
            if (globalT <= 0.001) {
                baseX = arc.startX;
                baseY = arc.startY;
                globalT = 0.0;
            } else if (globalT >= 0.999) {
                baseX = arc.endX;
                baseY = arc.endY;
                globalT = 1.0;
            } else {
                // 横向抖动 = 随机值 × 基础抖动 × 抖动倍率 × 纺锤包络
                offset = (Math.random() - 0.5) * 2 * arc.jitter * jitterMult * env;
            }

            points.push(pt(baseX + perpX * offset, baseY + perpY * offset, globalT));
        }
        return points;
    }

    /**
     * 绘制折线路径
     *
     * 使用 miter 连接模式 + miterLimit=3，产生锐利的低多边形折线美感，
     * 而非圆润的曲线，更符合高压电弧的视觉特征。
     *
     * @param mc        目标 MovieClip
     * @param path      路径点数组 [{x, y}, ...]
     * @param color     线条颜色 (0xRRGGBB)
     * @param thickness 线条粗细（像素）
     * @param alpha     透明度 (0~100)
     */
    private static function drawPath(mc:MovieClip, path:Array,
                                      color:Number, thickness:Number, alpha:Number):Void {
        if (path.length < 2) return;

        // lineStyle 参数：
        //   thickness: 线宽
        //   color: 颜色
        //   alpha: 透明度
        //   pixelHinting: true（像素对齐，更锐利）
        //   scaleMode: "normal"（随缩放变化）
        //   caps: "none"（无端点圆角）
        //   joints: "miter"（尖角连接，非圆角）
        //   miterLimit: 3（尖角限制，超过则截断）
        mc.lineStyle(thickness, color, alpha, true, "normal", "none", "miter", 3);
        mc.moveTo(path[0].x, path[0].y);

        for (var i:Number = 1; i < path.length; i++) {
            mc.lineTo(path[i].x, path[i].y);
        }
    }
}