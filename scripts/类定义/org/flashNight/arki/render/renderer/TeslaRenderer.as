import org.flashNight.arki.render.RayVfxManager;

/**
 * TeslaRenderer - 磁暴电弧渲染器
 *
 * 复刻红警2磁暴线圈的高压放电美学，核心特征：
 * • 纺锤约束算法：两端收敛、中间膨胀的电弧形态
 * • 三层渲染架构：泛光层 → 辉光层 → 内核层
 * • 随机分叉：从主干节点分裂的游离电弧
 * • 高频抖动：每帧重绘产生的电弧不稳定感
 *
 * 纺锤约束原理：
 *   所有电弧路径点的横向抖动受 Math.sin(t * PI) 约束：
 *   - t=0 (枪口): sin(0) = 0，抖动归零，精准从发射点出发
 *   - t=0.5 (中点): sin(π/2) = 1，抖动最大，电弧最狂野
 *   - t=1 (目标): sin(π) = 0，抖动归零，精准命中目标
 *
 * LOD 降级效果：
 *   LOD 0: 全特效（全量分支 + 每帧重绘）
 *   LOD 1: branchCount × 0.5
 *   LOD 2: 单路径，无分支
 *
 * @author FlashNight
 * @version 1.0
 */
class org.flashNight.arki.render.renderer.TeslaRenderer {

    // ════════════════════════════════════════════════════════════════════════
    // 默认配置常量
    // ════════════════════════════════════════════════════════════════════════

    private static var DEFAULT_PRIMARY_COLOR:Number = 0x00FFFF;
    private static var DEFAULT_SECONDARY_COLOR:Number = 0xFFFFFF;
    private static var DEFAULT_THICKNESS:Number = 3;
    private static var DEFAULT_BRANCH_COUNT:Number = 4;
    private static var DEFAULT_BRANCH_PROB:Number = 0.5;
    private static var DEFAULT_SEGMENT_LENGTH:Number = 35;
    private static var DEFAULT_JITTER:Number = 40;

    // ════════════════════════════════════════════════════════════════════════
    // 渲染入口
    // ════════════════════════════════════════════════════════════════════════

    /**
     * 渲染磁暴电弧
     *
     * @param arc 电弧数据对象
     * @param lod 当前 LOD 等级 (0=高, 1=中, 2=低)
     * @param mc  目标 MovieClip
     */
    public static function render(arc:Object, lod:Number, mc:MovieClip):Void {
        var config:Object = arc.config;
        var meta:Object = arc.meta;

        // 解析配置参数
        var primaryColor:Number = (config != null && !isNaN(config.primaryColor)) ? config.primaryColor : DEFAULT_PRIMARY_COLOR;
        var secondaryColor:Number = (config != null && !isNaN(config.secondaryColor)) ? config.secondaryColor : DEFAULT_SECONDARY_COLOR;
        var thickness:Number = (config != null && !isNaN(config.thickness)) ? config.thickness : DEFAULT_THICKNESS;
        var branchCount:Number = (config != null && !isNaN(config.branchCount)) ? config.branchCount : DEFAULT_BRANCH_COUNT;
        var branchProb:Number = (config != null && !isNaN(config.branchProbability)) ? config.branchProbability : DEFAULT_BRANCH_PROB;
        var segmentLength:Number = (config != null && !isNaN(config.segmentLength)) ? config.segmentLength : DEFAULT_SEGMENT_LENGTH;
        var jitter:Number = (config != null && !isNaN(config.jitter)) ? config.jitter : DEFAULT_JITTER;

        // 应用 intensity 强度因子
        var intensity:Number = (meta != null && !isNaN(meta.intensity)) ? meta.intensity : 1.0;
        thickness *= intensity;
        jitter *= intensity;

        // LOD 降级调整
        if (lod >= 2) {
            // LOD 2: 单路径，无分支
            branchCount = 1;
        } else if (lod >= 1) {
            // LOD 1: 分支数减半
            branchCount = Math.max(1, Math.floor(branchCount * 0.5));
        }

        // 计算电弧方向向量
        var dx:Number = arc.endX - arc.startX;
        var dy:Number = arc.endY - arc.startY;
        var dist:Number = Math.sqrt(dx * dx + dy * dy);
        if (dist == 0) return;

        // 路径收集器
        var pathsToDraw:Array = RayVfxManager.poolArr();
        var mainPaths:Array = RayVfxManager.poolArr();

        // ─────────────────────────────────────────────────────────────
        // 阶段 1：生成主干电弧
        // ─────────────────────────────────────────────────────────────
        var mainHitCount:Number = Math.min(branchCount, 2);
        for (var i:Number = 0; i < mainHitCount; i++) {
            var isMain:Boolean = (i == 0);
            var mainPath:Array = generateSpindlePath(arc, 0.0, 1.0, isMain ? 1.0 : 1.3, null, segmentLength, jitter);
            pathsToDraw.push(RayVfxManager.pd(mainPath, isMain, false));
            mainPaths.push(mainPath);
        }

        // ─────────────────────────────────────────────────────────────
        // 阶段 2：生成游离分叉
        // ─────────────────────────────────────────────────────────────
        var forkCount:Number = branchCount - mainHitCount;
        for (var f:Number = 0; f < forkCount; f++) {
            if (Math.random() <= branchProb) {
                var parentPath:Array = mainPaths[Math.floor(Math.random() * mainPaths.length)];
                var maxIdx:Number = parentPath.length - 2;
                if (maxIdx < 1) continue;

                var nodeIdx:Number = 1 + Math.floor(Math.random() * maxIdx);
                var startNode:Object = parentPath[nodeIdx];

                var endT:Number = startNode.t + 0.15 + Math.random() * 0.15;
                if (endT > 0.95) endT = 0.95;

                var forkPath:Array = generateSpindlePath(arc, startNode.t, endT, 1.5, startNode, segmentLength * 0.8, jitter);
                if (forkPath.length > 1) {
                    pathsToDraw.push(RayVfxManager.pd(forkPath, false, true));
                }
            }
        }

        // ─────────────────────────────────────────────────────────────
        // 阶段 3：按图层顺序统一绘制
        // ─────────────────────────────────────────────────────────────

        // Layer 1: 底层宽域泛光
        for (var p1:Number = 0; p1 < pathsToDraw.length; p1++) {
            var pathData1:Object = pathsToDraw[p1];
            var thick1:Number = thickness * (pathData1.isMain ? 4.5 : 3.0);
            var alpha1:Number = pathData1.isFork ? 20 : 30;
            RayVfxManager.drawPath(mc, pathData1.path, primaryColor, thick1, alpha1);
        }

        // Layer 2: 中层电离辉光
        for (var p2:Number = 0; p2 < pathsToDraw.length; p2++) {
            var pathData2:Object = pathsToDraw[p2];
            var thick2:Number = thickness * (pathData2.isMain ? 2.0 : 1.2);
            var alpha2:Number = pathData2.isFork ? 60 : 80;
            RayVfxManager.drawPath(mc, pathData2.path, primaryColor, thick2, alpha2);
        }

        // Layer 3: 顶层白热内核
        for (var p3:Number = 0; p3 < pathsToDraw.length; p3++) {
            var pathData3:Object = pathsToDraw[p3];
            if (pathData3.isMain || (!pathData3.isFork && Math.random() > 0.3)) {
                RayVfxManager.drawPath(mc, pathData3.path, secondaryColor, thickness * 0.8, 100);
            } else if (pathData3.isFork) {
                RayVfxManager.drawPath(mc, pathData3.path, secondaryColor, thickness * 0.3, 70);
            }
        }
    }

    // ════════════════════════════════════════════════════════════════════════
    // 纺锤约束路径生成
    // ════════════════════════════════════════════════════════════════════════

    /**
     * 生成纺锤约束路径
     *
     * @param arc         电弧数据对象
     * @param startT      路径起始全局进度 (0.0~1.0)
     * @param endT        路径结束全局进度 (0.0~1.0)
     * @param jitterMult  抖动倍率
     * @param startNode   分叉起始节点（null 表示从电弧起点开始）
     * @param segLen      分段长度
     * @param jitter      抖动幅度
     * @return            路径点数组 [{x, y, t}, ...]
     */
    private static function generateSpindlePath(arc:Object, startT:Number, endT:Number,
                                                  jitterMult:Number, startNode:Object,
                                                  segLen:Number, jitter:Number):Array {
        var dx:Number = arc.endX - arc.startX;
        var dy:Number = arc.endY - arc.startY;
        var totalDist:Number = Math.sqrt(dx * dx + dy * dy);
        var perpX:Number = -dy / totalDist;
        var perpY:Number = dx / totalDist;

        var points:Array = RayVfxManager.poolArr();

        // 起始点
        if (startNode != null) {
            points.push(RayVfxManager.pt(startNode.x, startNode.y, startNode.t));
        } else {
            points.push(RayVfxManager.pt(arc.startX, arc.startY, 0.0));
        }

        // 计算分段参数
        var pathDist:Number = totalDist * (endT - startT);
        segLen = Math.max(segLen, 20);
        if (startNode != null) segLen *= 0.8;

        var segments:Number = Math.max(2, Math.ceil(pathDist / segLen));

        // 生成中间节点
        for (var i:Number = 1; i <= segments; i++) {
            var localT:Number = i / segments;

            // 轴向抖动
            if (i < segments) {
                localT += (Math.random() - 0.5) * (0.8 / segments);
            }

            // 映射到全局进度
            var globalT:Number = startT + (endT - startT) * localT;

            // 纺锤包络
            var env:Number = Math.sin(globalT * Math.PI);

            // 计算基础坐标
            var baseX:Number = arc.startX + dx * globalT;
            var baseY:Number = arc.startY + dy * globalT;
            var offset:Number = 0;

            // 端点精度保护
            if (globalT <= 0.001) {
                baseX = arc.startX;
                baseY = arc.startY;
                globalT = 0.0;
            } else if (globalT >= 0.999) {
                baseX = arc.endX;
                baseY = arc.endY;
                globalT = 1.0;
            } else {
                offset = (Math.random() - 0.5) * 2 * jitter * jitterMult * env;
            }

            points.push(RayVfxManager.pt(baseX + perpX * offset, baseY + perpY * offset, globalT));
        }

        return points;
    }
}
