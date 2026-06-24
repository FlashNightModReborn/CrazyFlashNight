import org.flashNight.arki.bullet.BulletComponent.Queue.BulletQueueProcessor;

/**
 * RayComboCursor —— combo（含 pierce 的组合，如铁枪 chain,fork,pierce）射线的【增量 per-node 迭代游标】组件。
 *
 * 从 BulletQueueProcessor 抽出（2026-06-24，"先粗糙能跑、再组件化"的组件化步）：原 ~14 个散落 bullet 的
 * combo 状态字段 + 4 个 static 函数收敛为本类（state + next() + 三个 advance）。每次 next() 返回 batch
 * per-node 管线序列的下一个命中：节点 → 其 chain 走链 → 其 fork → 下一节点；N=1 下每帧 resume 一次。
 *
 * 死目标由各 find* 的 visited/hp 过滤自动跳过续走。dmgMult 按 phase 算好放 hit.dmgMult
 * （node=pnDmgMult；chain 起于 pnDmgMult×falloff 逐跳衰减；fork 全用 pnDmgMult×falloff），逐字对齐 batch per-node。
 *
 * 几何扫描原语（findAlongRay/findNearestAt/collectForkList）仍是 BulletQueueProcessor 的 public static
 * （射线扫描层 = 未来 findNextHit 策略 line→band→cone 的复用面）；本游标只编排命中序列、不做几何。
 *
 * 实例挂在 bullet._rayCombo（processPersistentRay 首帧 new；跨帧 resume）。
 */
class org.flashNight.arki.bullet.BulletComponent.Queue.RayComboCursor {

    // ── node 阶段 ──
    public var phase:String;          // "node" / "chain" / "fork"
    public var pnDmgMult:Number;      // per-node 衰减基（每过一个 node ×= falloff）
    public var nodeTEntry:Number;     // 已推进到的 pierce 节点 tEntry（沿束严格递增）

    // ── chain 子阶段（当前节点）──
    public var chainCX:Number;
    public var chainCY:Number;
    public var chainCZ:Number;
    public var chainDmgMult:Number;

    // ── fork 子阶段（当前节点）──
    public var forkBaseX:Number;
    public var forkBaseY:Number;
    public var forkBaseZ:Number;
    public var forkDmgMult:Number;
    public var forkList:Array;        // 本节点 fork 候选缓存（首次进 fork 阶段惰性收集）
    public var forkIdx:Number;        // fork 吐出游标

    public function RayComboCursor() {
        this.phase = "node";
        this.pnDmgMult = 1;
        this.nodeTEntry = -1;
        this.chainCX = 0; this.chainCY = 0; this.chainCZ = 0; this.chainDmgMult = 1;
        this.forkBaseX = 0; this.forkBaseY = 0; this.forkBaseZ = 0; this.forkDmgMult = 1;
        this.forkList = null; this.forkIdx = 0;
    }

    /**
     * 返回 batch per-node 序列的下一个命中（node→chain→fork→下一node），或 null（节点耗尽=combo 结束）。
     * @param ctx       processPersistentRay 打包的每帧上下文（窗口/几何/config）
     * @param visited   已命中 _name 去重表（跨帧，bullet._rayVisited）
     * @param falloff   config.damageFalloff
     * @param hasChain  config.hasChain()
     * @param hasFork   config.hasFork()
     * @param budget    剩余命中名额（bullet._rayBudget；fork maxCount 用，与 batch cfMaxCount 同源）
     * @return {target, hitX, hitY, dmgMult} 或 null
     */
    public function next(ctx:Object, visited:Object, falloff:Number,
                         hasChain:Boolean, hasFork:Boolean, budget:Number):Object {
        while (true) {
            if (this.phase == "node") {
                // node 耗尽 → advanceNode 返回 null = combo 结束（直接透传）
                return this.advanceNode(ctx, visited, falloff);
            } else if (this.phase == "chain") {
                var chainHit:Object = this.advanceChain(ctx, visited, falloff, hasChain);
                if (chainHit != null) return chainHit;
            } else if (this.phase == "fork") {
                var forkHit:Object = this.advanceFork(ctx, visited, hasFork, budget);
                if (forkHit != null) return forkHit;
            } else {
                return null;
            }
        }
    }

    /** node 阶段：沿主束取下一个 pierce 节点，初始化该节点的 chain/fork 子游标。 */
    private function advanceNode(ctx:Object, visited:Object, falloff:Number):Object {
        var node:Object = BulletQueueProcessor.findAlongRay(ctx, visited, this.nodeTEntry);
        if (node == null) return null;

        this.nodeTEntry = node.tEntry;
        var p0:Number = this.pnDmgMult;
        this.pnDmgMult = p0 * falloff;   // P1：node 之后衰减一档

        // 该节点的 chain/fork 均以 P1 为基（对齐 batch：chain 起于 pnDmgMult、fork 用 pnDmgMult）
        this.chainCX = node.hitX;
        this.chainCY = node.hitY;
        this.chainCZ = node.target.Z轴坐标;
        this.chainDmgMult = this.pnDmgMult;
        this.forkBaseX = node.hitX;
        this.forkBaseY = node.hitY;
        this.forkBaseZ = node.target.Z轴坐标;
        this.forkDmgMult = this.pnDmgMult;
        this.forkList = null;
        this.forkIdx = 0;
        this.phase = "chain";
        node.dmgMult = p0;
        return node;
    }

    /** chain 阶段：从当前链游标取最近目标；断链或无 chain 时切到 fork。 */
    private function advanceChain(ctx:Object, visited:Object, falloff:Number, hasChain:Boolean):Object {
        if (hasChain) {
            var hit:Object = BulletQueueProcessor.findNearestAt(ctx, visited, this.chainCX, this.chainCY, this.chainCZ);
            if (hit != null) {
                hit.dmgMult = this.chainDmgMult;
                this.chainDmgMult *= falloff;
                this.chainCX = hit.hitX;
                this.chainCY = hit.hitY;
                this.chainCZ = hit.target.Z轴坐标;
                return hit;
            }
        }
        this.phase = "fork";
        return null;
    }

    /** fork 阶段：惰性收集本节点 fork 候选（top-budget 近）并按近到远吐出；耗尽后切回 node。 */
    private function advanceFork(ctx:Object, visited:Object, hasFork:Boolean, budget:Number):Object {
        if (hasFork) {
            if (this.forkList == null) {
                this.forkList = BulletQueueProcessor.collectForkList(
                    ctx, visited, this.forkBaseX, this.forkBaseY, this.forkBaseZ, budget);
            }
            var fl:Array = this.forkList;
            while (this.forkIdx < fl.length) {
                var hit:Object = fl[this.forkIdx];
                this.forkIdx++;
                if (visited[hit.target._name] == true) continue;   // chain 可能已吃掉
                hit.dmgMult = this.forkDmgMult;
                return hit;
            }
        }
        this.phase = "node";
        return null;
    }
}
