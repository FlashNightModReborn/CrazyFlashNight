import org.flashNight.arki.bullet.BulletComponent.Config.TeslaRayConfig;
import org.flashNight.arki.spatial.transform.SceneCoordinateManager;
import org.flashNight.arki.render.RayStyleRegistry;

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

    // 风格渲染成本权重已迁入 RayStyleRegistry（单一事实来源）

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
        var delay:Number = computeSegmentDelay(config, meta);

        if (delay > 0) {
            var delayedStyle:String = (config != null && config.vfxStyle != null) ? config.vfxStyle : "tesla";
            _delayedSegments.push({
                startX: startX,
                startY: startY,
                endX: endX,
                endY: endY,
                config: config,
                meta: meta,
                styleCost: getStyleCost(delayedStyle),
                delayRemaining: delay
            });
            return;
        }

        createArc(startX, startY, endX, endY, config, meta);
    }

    /**
     * 计算段的延迟帧数（供 spawn 与测试复用）
     *
     * 规则：
     * - chain: hitIndex * chainDelay（主命中 hitIndex=0 不延迟）
     * - fork:  统一延迟 1 帧（主命中先，折射后）
     * - 其他模式不延迟
     */
    public static function computeSegmentDelay(config:TeslaRayConfig, meta:Object):Number {
        if (meta == null) return 0;

        var chainDelay:Number = cfgNum(config, "chainDelay", 0);
        if (chainDelay <= 0) return 0;

        if (meta.segmentKind == "chain") {
            var hitIndex:Number = (meta.hitIndex != undefined && !isNaN(meta.hitIndex))
                ? Number(meta.hitIndex) : 0;
            if (hitIndex <= 0) return 0;
            return chainDelay * hitIndex;
        }

        if (meta.segmentKind == "fork") {
            // fork 统一延迟 1 帧：所有折射段都在主命中后显示
            return 1;
        }

        return 0;
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
            styleCost: getStyleCost(vfxStyle),
            age: 0
        };

        // 对 pierce 命中点应用相同坐标偏移（与 start/end 保持一致）
        if (meta != null && meta.hitPoints != null && (offsetX != 0 || offsetY != 0)) {
            var hps:Array = meta.hitPoints;
            for (var h:Number = hps.length - 1; h >= 0; --h) {
                hps[h].x += offsetX;
                hps[h].y += offsetY;
            }
        }

        // 从 config 读取时间参数
        arc.visualDuration = cfgNum(config, "visualDuration", 5);
        arc.fadeDuration = cfgNum(config, "fadeOutDuration", 3);
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
                // 活跃期重绘策略：
                //   LOD < 2: 每帧重绘（支持抖动/动画/随机路径等动态效果）
                //   LOD >= 2: 冻结重绘，首帧已在 createArc 渲染完成，仅做 alpha 控制
                if (_currentLOD < 2) {
                    renderArc(arc);
                }
                // 随机爆闪（由 config.flickerEnabled 控制，默认仅 Tesla 开启）
                var cfg:Object = arc.config;
                if (cfg != null && cfg.flickerEnabled == true) {
                    var fMin:Number = cfgNum(cfg, "flickerMin", 70);
                    var fMax:Number = cfgNum(cfg, "flickerMax", 100);
                    arc.mc._alpha = fMin + Math.random() * (fMax - fMin);
                } else {
                    arc.mc._alpha = 100;
                }
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
            _renderCost += (_activeArcs[i].styleCost != undefined) ? _activeArcs[i].styleCost : 1.0;
        }
        for (i = 0; i < _delayedSegments.length; i++) {
            _renderCost += (_delayedSegments[i].styleCost != undefined) ? _delayedSegments[i].styleCost : 1.0;
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
     * 渲染电弧（通过 RayStyleRegistry 查表路由到对应渲染器）
     */
    private static function renderArc(arc:Object):Void {
        var mc:MovieClip = arc.mc;
        mc.clear();

        // 重置对象池
        resetPools();

        // 通过注册表查表路由（消除 switch/case，新增风格只改 Registry）
        RayStyleRegistry.renderArc(arc.vfxStyle || "tesla", arc, _currentLOD, mc);
    }

    // ════════════════════════════════════════════════════════════════════════
    // 配置读取工具（供渲染器使用，消除样板代码）
    // ════════════════════════════════════════════════════════════════════════

    /**
     * 从 config 读取 Number 字段，null/NaN/undefined 返回默认值
     *
     * 利用 NaN != NaN 特性：AS2 中 Number(undefined) → NaN，
     * 因此 (v == v) 同时排除 NaN 和 undefined。
     * config == null 时短路返回，避免 null[field] 异常。
     *
     * @param config 配置对象（可为 null）
     * @param field  字段名
     * @param def    默认值
     * @return 有效值或默认值
     */
    public static function cfgNum(config:Object, field:String, def:Number):Number {
        if (config == null) return def;
        var v:Number = config[field];
        return (v == v) ? v : def;
    }

    /**
     * 从 config 读取 Array 字段，null 返回默认值
     *
     * @param config 配置对象（可为 null）
     * @param field  字段名
     * @param def    默认数组
     * @return 有效数组或默认值
     */
    public static function cfgArr(config:Object, field:String, def:Array):Array {
        if (config == null) return def;
        var v:Array = config[field];
        return (v != null) ? v : def;
    }

    /**
     * 从 SegmentMeta 读取 intensity，null/NaN 返回 1.0
     *
     * @param meta SegmentMeta 对象（可为 null）
     * @return intensity 值或 1.0
     */
    public static function cfgIntensity(meta:Object):Number {
        if (meta == null) return 1.0;
        var v:Number = meta.intensity;
        return (v == v) ? v : 1.0;
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
     * 构建起点到终点的直线路径（供各渲染器复用）
     */
    public static function straightPath(startX:Number, startY:Number, endX:Number, endY:Number):Array {
        var path:Array = poolArr();
        path.push(pt(startX, startY, 0.0));
        path.push(pt(endX, endY, 1.0));
        return path;
    }

    /**
     * 获取风格渲染成本权重（委托给 RayStyleRegistry）
     */
    private static function getStyleCost(style:String):Number {
        return RayStyleRegistry.getStyleCost(style);
    }

    /**
     * 生成正弦波路径（通用方法，供 Wave/Vortex/Plasma 等渲染器复用）
     *
     * 算法：沿射线方向均匀采样，每个采样点叠加正弦波偏移。
     * 两端使用 smoothstep 包络衰减，避免端点突变。
     *
     * @param arc           电弧数据对象 {startX, startY, endX, endY}
     * @param perpX         垂直方向 X 分量（单位向量）
     * @param perpY         垂直方向 Y 分量（单位向量）
     * @param dist          射线总长度
     * @param waveAmp       波形幅度（像素）
     * @param waveLen       波长（像素）
     * @param waveSpeed     波传播速度（波长/帧）
     * @param age           当前帧龄
     * @param phaseOffset   相位偏移（弧度）
     * @param ptsPerWave    每波长采样点数（Wave/Vortex=24, Plasma=12）
     * @param maxSegments   最大分段数上限（Wave/Vortex=250, Plasma=200）
     * @param noiseRatio    高频噪声比率（0=无噪声, >0=叠加 sin 噪声）
     *                      噪声波长 = waveLen * noiseRatio，噪声幅度 = 0.25
     * @return              路径点数组（池化）
     */
    public static function generateSinePath(
        arc:Object, perpX:Number, perpY:Number, dist:Number,
        waveAmp:Number, waveLen:Number, waveSpeed:Number,
        age:Number, phaseOffset:Number,
        ptsPerWave:Number, maxSegments:Number, noiseRatio:Number
    ):Array {
        var dx:Number = arc.endX - arc.startX;
        var dy:Number = arc.endY - arc.startY;

        var points:Array = poolArr();

        if (waveLen < 5) waveLen = 5;
        var segmentCount:Number = Math.ceil(dist / (waveLen / ptsPerWave));
        if (segmentCount < 10) segmentCount = 10;
        if (segmentCount > maxSegments) segmentCount = maxSegments;

        var step:Number = 1.0 / segmentCount;
        var margin:Number = 0.08;
        var hasNoise:Boolean = (noiseRatio > 0);
        var TWO_PI:Number = 2 * Math.PI;

        for (var i:Number = 0; i <= segmentCount; i++) {
            var t:Number = i * step;

            var baseX:Number = arc.startX + dx * t;
            var baseY:Number = arc.startY + dy * t;

            var offset:Number = 0;

            if (t > 0.001 && t < 0.999) {
                // smoothstep 包络
                var envelope:Number = 1.0;
                if (t < margin) {
                    envelope = t / margin;
                } else if (t > 1.0 - margin) {
                    envelope = (1.0 - t) / margin;
                }
                envelope = envelope * envelope * (3 - 2 * envelope);

                var phase:Number = (t * dist / waveLen - age * waveSpeed) * TWO_PI
                    + phaseOffset;
                var wave:Number = Math.sin(phase);

                // 可选高频噪声叠加（Plasma 专用）
                if (hasNoise) {
                    var noisePhase:Number = (t * dist / (waveLen * noiseRatio) - age * waveSpeed * 1.5)
                        * TWO_PI;
                    wave += Math.sin(noisePhase) * 0.25;
                }

                offset = waveAmp * envelope * wave;
            }

            if (t <= 0.001) {
                points.push(pt(arc.startX, arc.startY, 0.0));
            } else if (t >= 0.999) {
                points.push(pt(arc.endX, arc.endY, 1.0));
            } else {
                points.push(pt(
                    baseX + perpX * offset,
                    baseY + perpY * offset, t));
            }
        }

        return points;
    }

    /**
     * 绘制平滑填充圆盘
     *
     * v6 重写：用 8 段二次贝塞尔曲线 + beginFill 替代旧的
     * 8 段 lineTo 八边形描边。旧实现在 additive blend 下
     * 会暴露明显的八边形硬边轮廓（"六边形能量盾"伪影）。
     *
     * 新实现：无描边、纯填充、curveTo 曲线 → 视觉上完美平滑的圆。
     * 8 段二次贝塞尔近似圆的最大误差 < 0.06% 半径，肉眼不可见。
     */
    public static function drawCircle(mc:MovieClip, cx:Number, cy:Number,
                                       radius:Number, color:Number, alpha:Number):Void {
        if (radius <= 0 || alpha <= 0) return;

        // 关闭描边（alpha=0 使 hairline 不可见）
        mc.lineStyle(0, 0, 0);
        mc.beginFill(color, alpha);

        // 8 段 curveTo：每段 45°，控制点距圆心 r/cos(π/8)
        var segAngle:Number = 0.7853981633974483; // π/4
        var k:Number = radius * 1.0823922002923940; // 1/cos(π/8)

        mc.moveTo(cx + radius, cy);
        for (var i:Number = 0; i < 8; i++) {
            var midA:Number = (i + 0.5) * segAngle;
            var endA:Number = (i + 1) * segAngle;
            mc.curveTo(
                cx + k * Math.cos(midA), cy + k * Math.sin(midA),
                cx + radius * Math.cos(endA), cy + radius * Math.sin(endA)
            );
        }
        mc.endFill();
    }
}
