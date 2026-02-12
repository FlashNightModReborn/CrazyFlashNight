/**
 * ARCCache v3.2 — Adaptive Replacement Cache (AS2 raw-key + pooling + robust)
 *
 * 基于 Megiddo & Modha (2003) ARC 论文的完整实现。
 *
 * v3.0 重写变更摘要：
 * ─────────────────
 * [P0] ARCH-1      : 移除内部 UID 生成（typeof + "_" 前缀 + Dictionary.getStaticUID），
 *                     key 直接用作 nodeMap 属性名。消除热路径字符串拼接与类型分支。
 * [P0] ARCH-2      : nodeMap.__proto__ = null，断开原型链避免 Object.prototype 冲突。
 * [P1] OPT-6       : 节点池化（free list）— ghost 清理 / remove 时节点进池，新建时出池，
 *                     减少 GC 压力。
 * [P1] OPT-7       : == undefined → === undefined，消除 ActionEquals2 类型协商。
 * [P2] ROBUST-1    : _doReplace 空队列回退 — 若首选队列为空则回退到另一队列，
 *                     防止 remove() 打乱 ARC 状态后 REPLACE 空转。
 * [P2] ROBUST-2    : ghost hit 路径增加 |T1|+|T2| >= c 前置守卫，
 *                     cache 未满时（remove 导致）跳过 REPLACE。
 * [P2] OPT-8       : _clear() 重用哨兵节点，避免 8 次对象分配。
 * [P3] VALID-1     : 构造函数校验 capacity >= 1。
 * [P4] API-1       : 新增 has(key) — 不变更状态的存在性检查（仅 T1/T2）。
 *
 * v3.1 增量优化（交叉评审）：
 * ──────────────────────────
 * [P0] OPT-9       : 新增 _putNew(key, value) — 纯新 key 快速插入，跳过存在性检查。
 *                     供 LazyCache MISS 路径使用，省一次 nodeMap hash 查找。
 * [P1] OPT-10      : 入池仅清 value（唯一可能持有外部大对象引用的字段）。
 *                     uid/prev/list 在复用时覆盖，无需预清。省 3 次赋值/次入池。
 *
 * v3.2 优化（代码审阅）：
 * ──────────────────────
 * [P0] OPT-C       : get() 变量整合（20 var → 13 var），B1/B2 幽灵路径合并，
 *                     localT1 延迟初始化。省 7 次 DefineLocal2 + T2 HIT 省 1 属性读取。
 * [P0] OPT-D       : get() MISS 检查后置至 T1/T2 之后。
 *                     AS2 AVM1 对 undefined.prop 返回 undefined 而非抛出异常，
 *                     T2/T1 HIT 各省 1 次 StrictEquals 比较。
 * [P1] OPT-B       : 提取 _evictForInsert() 消除 put()/_putNew() Case IV ~80 行代码克隆。
 * [P1] ROBUST-3    : Case IV 淘汰条件 L1 == c → L1 >= c，防御性兜底。
 * [P2] OPT-A       : _clear() 回收节点入池（_drainToPool），避免 reset 后 GC 重建。
 * [P2] ROBUST-4    : putNoEvict() ghost 路径增加 |T1|+|T2| >= c 容量守卫（触发 _doReplace）。
 *                     注意：MISS 路径仍不检查容量，调用者负责避免无界增长。
 * [P3] OPT-E       : put() B1/B2 幽灵路径合并（~14 行）+ 变量整合（~35 var → 16 var）。
 *
 * 保留自 v2.0 的优化：
 *   OPT-1 值直存节点 / OPT-2 内联 promote / OPT-3 T2 head 快路径
 *   OPT-4 链表局部变量缓存 / OPT-5 _lastNode ghost 直赋 / sentinel 哨兵
 *
 * ─── 原始键语义（ARCH-1）───
 * ARCCache 不对 key 做任何转换，直接将 key 用作 nodeMap 属性名。
 * AS2 自动将非字符串键转换为字符串（Number 123 → "123"，null → "null"）。
 *
 * 调用者责任：
 *   - 不同类型但字符串表示相同的键会碰撞（Number 123 与 String "123"）
 *   - 对象键默认走 toString()（返回 "[object Object]"），不推荐直接使用
 *   - 需要对象键时，应先用 Dictionary.getStaticUID() 转为唯一字符串再传入
 *   - "__proto__" 为 AS2 保留属性，不可用作缓存键
 *
 * 队列不变式（所有操作维护）：
 *   0 <= |T1| + |T2| <= c
 *   0 <= |T1| + |B1| <= c          (L1)
 *   0 <= |T1|+|T2|+|B1|+|B2| <= 2c (总量)
 *   0 <= p <= c
 *
 * 四个队列：
 *   T1 — "冷"队列（最近一次访问）  T2 — "热"队列（频繁访问）
 *   B1 — T1 幽灵（不存值）          B2 — T2 幽灵（不存值）
 *
 * 节点结构：{ uid:*, prev:Object, next:Object, list:Object, value:* }
 *   uid 为调用者传入的原始 key（用于 delete nodeMap[uid]）
 *   幽灵节点 value 为 undefined
 *
 * 队列结构：{ sentinel:Object, size:Number }
 *   sentinel 是循环哨兵：空队列时 sentinel.prev = sentinel.next = sentinel
 *   head = sentinel.next, tail = sentinel.prev
 */
class org.flashNight.naki.Cache.ARCCache {

    // ==================== 字段 ====================

    private var maxCapacity:Number;
    private var p:Number;

    private var T1:Object;
    private var T2:Object;
    private var B1:Object;
    private var B2:Object;

    private var nodeMap:Object;

    /** 节点池头（OPT-6）：空闲节点通过 .next 单链串联，null 表示池空 */
    private var _pool:Object;

    /**
     * 上次 get() 的命中类型（供子类读取）：
     *   0 = 完全未命中 (MISS)
     *   1 = 缓存命中   (HIT, T1/T2)
     *   2 = 幽灵命中 B1 (GHOST_B1)
     *   3 = 幽灵命中 B2 (GHOST_B2)
     *
     * public：AS2 没有 protected，子类需要直接读取此字段。
     */
    public var _hitType:Number;

    /**
     * 上次 get() 命中的节点引用（供子类在 ghost hit 后直接赋值，跳过 putNoEvict）。
     *
     * 使用场景（OPT-5）：
     *   var node:Object = this._lastNode;   // get() 后立即读取
     *   var computed = evaluator(key);       // 调用 evaluator（可能可重入）
     *   node.value = computed;               // 直接赋值
     *
     * 必须在调用 evaluator 之前存入局部变量，防止 evaluator 内部覆盖 _lastNode。
     * 生命周期：HIT 时未更新（保留上次值），MISS 时为 null，GHOST 时为对应节点。
     *
     * public：AS2 没有 protected。
     */
    public var _lastNode:Object;

    // ==================== 构造 ====================

    /**
     * @param capacity 缓存容量（至少 1，VALID-1）
     */
    public function ARCCache(capacity:Number) {
        // P3 VALID-1
        if (!(capacity >= 1)) capacity = 1;
        this.maxCapacity = capacity;
        this.p = 0;
        this._hitType = 0;
        this._lastNode = null;
        this._pool = null;
        this.T1 = this._createQueue();
        this.T2 = this._createQueue();
        this.B1 = this._createQueue();
        this.B2 = this._createQueue();
        // P0 ARCH-2：断开原型链
        var nm:Object = {};
        nm.__proto__ = null;
        this.nodeMap = nm;
    }

    // ==================== 内部工具 ====================

    /** 创建带哨兵的空队列 */
    private function _createQueue():Object {
        var s:Object = {};
        s.prev = s;
        s.next = s;
        return { sentinel: s, size: 0 };
    }

    /**
     * 将队列中所有节点回收入池，并重置队列为空（OPT-A）。
     * 回收节点通过 _pool 链供后续 _putNew/put 复用，减少 GC 压力。
     */
    private function _drainToPool(list:Object):Void {
        var s:Object = list.sentinel;
        var curr:Object = s.next;
        while (curr !== s) {
            var nxt:Object = curr.next;
            curr.value = undefined; // OPT-10: 仅清 value
            curr.next = this._pool;
            this._pool = curr;
            curr = nxt;
        }
        s.prev = s;
        s.next = s;
        list.size = 0;
    }

    /**
     * 重置所有队列和映射（供子类 reset/clear 使用）。
     * OPT-8：重用哨兵节点，避免 8 次对象分配。
     * OPT-A：回收现有节点入池，避免 reset 后重新分配。
     *
     * public：AS2 没有 protected，子类（ARCEnhancedLazyCache.reset）需要调用。
     */
    public function _clear():Void {
        this.p = 0;
        this._hitType = 0;
        this._lastNode = null;
        // OPT-A: 回收所有队列节点入池（而非丢弃）
        this._drainToPool(this.T1);
        this._drainToPool(this.T2);
        this._drainToPool(this.B1);
        this._drainToPool(this.B2);
        var nm:Object = {};
        nm.__proto__ = null;
        this.nodeMap = nm;
    }

    /**
     * REPLACE — 标准 ARC 淘汰 + P2 ROBUST-1 空队列回退。
     *
     * 从 T1 或 T2 中淘汰一个条目到对应的幽灵队列。
     * 选择逻辑：标准 ARC 优先 T1（当 |T1|>p 或 isB2Hit 且 |T1|==p）；
     * 若目标队列为空则回退到另一队列（ROBUST-1）。
     */
    private function _doReplace(isB2Hit:Boolean):Void {
        var t1:Object = this.T1;
        var t2:Object = this.T2;
        var t1Size:Number = t1.size;

        // 选择淘汰源(src) 和目标幽灵队列(dst)
        var src:Object;
        var dst:Object;

        if ((t1Size > 0) && ((t1Size > this.p) || (isB2Hit && t1Size == this.p))) {
            // 标准 ARC：从 T1 淘汰 → B1
            src = t1;
            dst = this.B1;
        } else if (t2.size > 0) {
            // 从 T2 淘汰 → B2
            src = t2;
            dst = this.B2;
        } else if (t1Size > 0) {
            // ROBUST-1 回退：T2 空，回退到 T1 → B1
            src = t1;
            dst = this.B1;
        } else {
            return; // 两队列均空（不应到达，由调用方守卫）
        }

        // 统一淘汰：src tail → dst head
        var ss:Object = src.sentinel;
        var victim:Object = ss.prev;
        var vp:Object = victim.prev;
        vp.next = ss;
        ss.prev = vp;
        src.size--;
        victim.value = undefined; // 幽灵不存值

        var sd:Object = dst.sentinel;
        var oh:Object = sd.next;
        victim.next = oh;
        victim.prev = sd;
        oh.prev = victim;
        sd.next = victim;
        dst.size++;
        victim.list = dst;
    }

    /**
     * Case IV 淘汰 — 为新 key 腾出空间（OPT-B）。
     *
     * 从 put()/_putNew() 提取的共用淘汰逻辑，消除 ~80 行代码克隆。
     * 调用后调用者可安全插入一个新节点到 T1。
     *
     * ROBUST-3: L1 >= c（防御性，原 L1 == c）。
     */
    private function _evictForInsert():Void {
        var localT1:Object = this.T1;
        var localT2:Object = this.T2;
        var mc:Number = this.maxCapacity;
        var lB1:Object = this.B1;
        var lB2:Object = this.B2;
        var L1:Number = localT1.size + lB1.size;

        if (L1 >= mc) {
            // Case A：|L1| >= c（ROBUST-3: >= 替代 ==）
            if (localT1.size < mc) {
                // removeTail B1（最老幽灵）+ pool
                var sb:Object = lB1.sentinel;
                var ghost:Object = sb.prev;
                if (ghost !== sb) {
                    var gp:Object = ghost.prev;
                    gp.next = sb;
                    sb.prev = gp;
                    lB1.size--;
                    delete this.nodeMap[ghost.uid];
                    // OPT-6 + OPT-10: pool（仅清 value）
                    ghost.value = undefined;
                    ghost.next = this._pool;
                    this._pool = ghost;
                }
                this._doReplace(false);
            } else {
                // |T1| >= c: 直接从 T1 删除（不进 B1）+ pool
                var st:Object = localT1.sentinel;
                var direct:Object = st.prev;
                if (direct !== st) {
                    var dp:Object = direct.prev;
                    dp.next = st;
                    st.prev = dp;
                    localT1.size--;
                    delete this.nodeMap[direct.uid];
                    // OPT-6 + OPT-10: pool（仅清 value）
                    direct.value = undefined;
                    direct.next = this._pool;
                    this._pool = direct;
                }
            }
        } else {
            // Case B：|L1| < c
            var L2:Number = localT2.size + lB2.size;
            if (L1 + L2 >= 2 * mc) {
                // removeTail B2 + pool
                var sb2:Object = lB2.sentinel;
                var ghost2:Object = sb2.prev;
                if (ghost2 !== sb2) {
                    var g2p:Object = ghost2.prev;
                    g2p.next = sb2;
                    sb2.prev = g2p;
                    lB2.size--;
                    delete this.nodeMap[ghost2.uid];
                    // OPT-6 + OPT-10: pool（仅清 value）
                    ghost2.value = undefined;
                    ghost2.next = this._pool;
                    this._pool = ghost2;
                }
            }
            if (localT1.size + localT2.size >= mc) {
                this._doReplace(false);
            }
        }
    }

    // ==================== get ====================

    /**
     * 从缓存获取项目。
     * 根据命中类型设置 _hitType，供子类判断后续操作。
     *
     * v3.2 OPT-C: 变量整合（20→13 var），B1/B2 路径合并，localT1 延迟。
     * v3.2 OPT-D: MISS 检查后置至 T1/T2 之后。
     *   AS2 AVM1 对 undefined.prop 返回 undefined（不抛异常），
     *   nodeMap[key] 为 undefined 时 node.list → undefined，
     *   不会匹配 T2/T1 的对象引用，安全落入延迟 MISS 检查。
     *
     * @param  key  要获取的键（原始键，直接用作属性名）
     * @return 缓存命中时返回值；未命中或幽灵命中返回 null
     */
    public function get(key:Object):Object {
        var node:Object = this.nodeMap[key];
        // OPT-D: node 可能为 undefined，node.list → undefined（AS2 安全）
        var nodeList:Object = node.list;
        var localT2:Object = this.T2;

        // ---- 链表操作复用变量（OPT-C: 13 var 替代原 20 var） ----
        var np:Object;
        var nn:Object;
        var oh:Object;
        var s:Object;

        // ---- T2 命中（最热路径优先，localT1 延迟） ----
        if (nodeList === localT2) {
            this._hitType = 1;
            s = localT2.sentinel;
            if (node !== s.next) {
                // unlink + addToHead（同队列，size 不变）
                np = node.prev;
                nn = node.next;
                np.next = nn;
                nn.prev = np;
                oh = s.next;
                node.next = oh;
                node.prev = s;
                oh.prev = node;
                s.next = node;
            }
            return node.value;
        }

        var localT1:Object = this.T1; // OPT-C: T2 HIT 不需要，延迟初始化

        // ---- T1 命中 ----
        if (nodeList === localT1) {
            this._hitType = 1;
            // unlink from T1
            np = node.prev;
            nn = node.next;
            np.next = nn;
            nn.prev = np;
            localT1.size--;
            // addToHead T2
            s = localT2.sentinel;
            oh = s.next;
            node.next = oh;
            node.prev = s;
            oh.prev = node;
            s.next = node;
            localT2.size++;
            node.list = localT2;
            return node.value;
        }

        // ---- OPT-D: MISS 延迟检查 ----
        if (node === undefined) {
            this._hitType = 0;
            this._lastNode = null;
            return null;
        }

        // ---- B1/B2 幽灵命中（OPT-C 合并 + 共用变量） ----
        var localB1:Object = this.B1;
        var localB2:Object = this.B2;
        var mc:Number = this.maxCapacity;
        var delta:Number;
        var newP:Number;

        if (nodeList === localB1) {
            // B1 幽灵命中：p 自适应（增大，偏向 T1 扩张）
            this._hitType = 2;
            delta = localB2.size / localB1.size;
            if (delta < 1) delta = 1;
            newP = this.p + delta;
            if (newP > mc) newP = mc;
            this.p = newP;
            // ROBUST-2：仅在 cache 满时 REPLACE
            if (localT1.size + localT2.size >= mc) {
                this._doReplace(false);
            }
        } else if (nodeList === localB2) {
            // B2 幽灵命中：p 自适应（减小，偏向 T2 扩张）
            this._hitType = 3;
            delta = localB1.size / localB2.size;
            if (delta < 1) delta = 1;
            newP = this.p - delta;
            if (newP < 0) newP = 0;
            this.p = newP;
            // ROBUST-2
            if (localT1.size + localT2.size >= mc) {
                this._doReplace(true);
            }
        } else {
            // 不应到达
            this._hitType = 0;
            this._lastNode = null;
            return null;
        }

        // B1/B2 共用：从幽灵队列断链
        np = node.prev;
        nn = node.next;
        np.next = nn;
        nn.prev = np;
        nodeList.size--; // nodeList 即 B1 或 B2

        // B1/B2 共用：加入 T2 头部
        s = localT2.sentinel;
        oh = s.next;
        node.next = oh;
        node.prev = s;
        oh.prev = node;
        s.next = node;
        localT2.size++;
        node.list = localT2;

        this._lastNode = node; // OPT-5
        return null;
    }

    // ==================== put ====================

    /**
     * 向缓存放入项目。
     * 正确处理：T1/T2 更新、B1/B2 幽灵命中、完全新 key。
     *
     * v3.2 OPT-E: B1/B2 幽灵路径合并 + 变量整合（~35 var → 16 var）。
     * v3.2 OPT-B: Case IV 使用 _evictForInsert()。
     *
     * @param key   键（原始键）
     * @param value 值
     */
    public function put(key:Object, value:Object):Void {
        var node:Object = this.nodeMap[key];
        var localT1:Object = this.T1;
        var localT2:Object = this.T2;

        var np:Object;
        var nn:Object;
        var oh:Object;
        var s:Object;

        if (node !== undefined) {
            var nodeList:Object = node.list;

            // ---- T2 中：更新值 + 移到头部 ----
            if (nodeList === localT2) {
                node.value = value;
                s = localT2.sentinel;
                if (node !== s.next) {
                    np = node.prev;
                    nn = node.next;
                    np.next = nn;
                    nn.prev = np;
                    oh = s.next;
                    node.next = oh;
                    node.prev = s;
                    oh.prev = node;
                    s.next = node;
                }
                return;
            }

            // ---- T1 中：更新值 + 移到 T2 头部 ----
            if (nodeList === localT1) {
                node.value = value;
                np = node.prev;
                nn = node.next;
                np.next = nn;
                nn.prev = np;
                localT1.size--;
                s = localT2.sentinel;
                oh = s.next;
                node.next = oh;
                node.prev = s;
                oh.prev = node;
                s.next = node;
                localT2.size++;
                node.list = localT2;
                return;
            }

            // ---- B1/B2 幽灵命中（OPT-E 合并） ----
            var localB1:Object = this.B1;
            var localB2:Object = this.B2;
            var mc:Number = this.maxCapacity;
            var delta:Number;
            var newP:Number;

            if (nodeList === localB1) {
                // p 自适应：增大
                delta = localB2.size / localB1.size;
                if (delta < 1) delta = 1;
                newP = this.p + delta;
                if (newP > mc) newP = mc;
                this.p = newP;
                // ROBUST-2
                if (localT1.size + localT2.size >= mc) {
                    this._doReplace(false);
                }
            } else if (nodeList === localB2) {
                // p 自适应：减小
                delta = localB1.size / localB2.size;
                if (delta < 1) delta = 1;
                newP = this.p - delta;
                if (newP < 0) newP = 0;
                this.p = newP;
                if (localT1.size + localT2.size >= mc) {
                    this._doReplace(true);
                }
            } else {
                return; // 不应到达
            }

            // B1/B2 共用：断链 + 赋值 + 加入 T2 头部
            np = node.prev;
            nn = node.next;
            np.next = nn;
            nn.prev = np;
            nodeList.size--;
            node.value = value;
            s = localT2.sentinel;
            oh = s.next;
            node.next = oh;
            node.prev = s;
            oh.prev = node;
            s.next = node;
            localT2.size++;
            node.list = localT2;
            return;
        }

        // ======== Case IV：完全新 key（OPT-B） ========
        this._evictForInsert();

        // OPT-6: 从池分配或新建节点
        var newNode:Object;
        var poolNode:Object = this._pool;
        if (poolNode !== null) {
            newNode = poolNode;
            this._pool = poolNode.next;
            newNode.uid = key;
            newNode.value = value;
        } else {
            newNode = { uid: key, prev: undefined, next: undefined,
                        list: undefined, value: value };
        }
        this.nodeMap[key] = newNode;
        var st1h:Object = localT1.sentinel;
        oh = st1h.next;
        newNode.next = oh;
        newNode.prev = st1h;
        oh.prev = newNode;
        st1h.next = newNode;
        localT1.size++;
        newNode.list = localT1;
    }

    // ==================== putNoEvict ====================

    /**
     * 轻量 put — MISS 路径跳过 Case IV 淘汰与 p 自适应，
     * 但 ghost 路径在缓存满时仍会触发 _doReplace（ROBUST-4）。
     *
     * 行为矩阵：
     *   T1/T2 HIT  → 更新值 + promote，不淘汰（|T1|+|T2| 不变）
     *   B1/B2 GHOST→ 断链 + 容量守卫（满时 _doReplace）→ 插入 T1
     *                 不执行 p 自适应，不享受 T2 热端优先级
     *   MISS       → 从池/新建 → 直插 T1，不检查容量
     *                 调用者负责确保不会无界增长（或接受临时 |T1|+|T2| > c）
     *
     * 注：v3.1 后 LazyCache 的 ghost hit 走 OPT-5 直赋，MISS 走 _putNew()，
     * 此方法当前无外部调用者。保留为公共 API 供未来扩展使用；
     * 若确认无需求可在后续版本移除。
     *
     * @param key   键（原始键）
     * @param value 值
     */
    public function putNoEvict(key:Object, value:Object):Void {
        var node:Object = this.nodeMap[key];
        var localT1:Object = this.T1;
        var localT2:Object = this.T2;

        var np:Object;
        var nn:Object;
        var oh:Object;

        if (node !== undefined) {
            var nodeList:Object = node.list;

            if (nodeList === localT2) {
                // T2 中：更新值 + 移到头部
                node.value = value;
                var s:Object = localT2.sentinel;
                if (node !== s.next) {
                    np = node.prev;
                    nn = node.next;
                    np.next = nn;
                    nn.prev = np;
                    oh = s.next;
                    node.next = oh;
                    node.prev = s;
                    oh.prev = node;
                    s.next = node;
                }
                return;
            }

            if (nodeList === localT1) {
                // T1 中：更新值 + 移到 T2 头部
                node.value = value;
                np = node.prev;
                nn = node.next;
                np.next = nn;
                nn.prev = np;
                localT1.size--;
                var s2:Object = localT2.sentinel;
                oh = s2.next;
                node.next = oh;
                node.prev = s2;
                oh.prev = node;
                s2.next = node;
                localT2.size++;
                node.list = localT2;
                return;
            }

            // B1/B2 中：先断链再插入 T1
            // 未经 p 自适应的回填不应享受 T2 热端优先级
            np = node.prev;
            nn = node.next;
            np.next = nn;
            nn.prev = np;
            nodeList.size--;
            node.value = value;
            // ROBUST-4: 容量守卫（防止外部调用时 |T1|+|T2| 超过 c）
            if (localT1.size + localT2.size >= this.maxCapacity) {
                this._doReplace(false);
            }
            var s3:Object = localT1.sentinel;
            oh = s3.next;
            node.next = oh;
            node.prev = s3;
            oh.prev = node;
            s3.next = node;
            localT1.size++;
            node.list = localT1;
            return;
        }

        // OPT-6: 从池分配或新建（不淘汰）→ T1
        var newNode:Object;
        var poolNode:Object = this._pool;
        if (poolNode !== null) {
            newNode = poolNode;
            this._pool = poolNode.next;
            newNode.uid = key;
            newNode.value = value;
        } else {
            newNode = { uid: key, prev: undefined, next: undefined,
                        list: undefined, value: value };
        }
        this.nodeMap[key] = newNode;
        var s4:Object = localT1.sentinel;
        oh = s4.next;
        newNode.next = oh;
        newNode.prev = s4;
        oh.prev = newNode;
        s4.next = newNode;
        localT1.size++;
        newNode.list = localT1;
    }

    // ==================== _putNew ====================

    /**
     * v3.1 OPT-9: 仅新 key 插入路径 — 调用者保证 key 不在 nodeMap 中。
     * 跳过 nodeMap[key] 存在性检查和 T1/T2/B1/B2 分支，直接执行 Case IV。
     * 供 ARCEnhancedLazyCache MISS 路径使用，省一次 hash 查找。
     *
     * v3.2 OPT-B: 淘汰逻辑委托 _evictForInsert()，消除代码克隆。
     *
     * 契约：
     *   - 调用者 MUST 保证 nodeMap[key] === undefined
     *   - 违反契约将导致 nodeMap 中出现重复节点（数据损坏）
     *
     * @param key   键
     * @param value 值
     */
    public function _putNew(key:Object, value:Object):Void {
        this._evictForInsert();

        // OPT-6: 从池分配或新建节点
        var newNode:Object;
        var poolNode:Object = this._pool;
        if (poolNode !== null) {
            newNode = poolNode;
            this._pool = poolNode.next;
            newNode.uid = key;
            newNode.value = value;
        } else {
            newNode = { uid: key, prev: undefined, next: undefined,
                        list: undefined, value: value };
        }
        this.nodeMap[key] = newNode;
        var localT1:Object = this.T1;
        var st1h:Object = localT1.sentinel;
        var oh:Object = st1h.next;
        newNode.next = oh;
        newNode.prev = st1h;
        oh.prev = newNode;
        st1h.next = newNode;
        localT1.size++;
        newNode.list = localT1;
    }

    // ==================== remove ====================

    /**
     * 从缓存中移除一个项目（包括幽灵队列中的记录）。
     * 移除的节点进入对象池（OPT-6）。
     *
     * @param  key 要移除的键
     * @return 成功移除返回 true，否则 false
     */
    public function remove(key:Object):Boolean {
        var node:Object = this.nodeMap[key];
        if (node === undefined) return false;

        // unlink（哨兵使断链无需分支）
        var np:Object = node.prev;
        var nn:Object = node.next;
        np.next = nn;
        nn.prev = np;
        node.list.size--;
        delete this.nodeMap[key];

        // OPT-6 + OPT-10: pool（仅清 value）
        node.value = undefined;
        node.next = this._pool;
        this._pool = node;
        return true;
    }

    // ==================== has ====================

    /**
     * P4 API-1：检查 key 是否在缓存中持有值（T1 或 T2）。
     * 不触发任何状态变更（不影响 LRU 排序、不修改 _hitType/_lastNode）。
     *
     * @param  key 要检查的键
     * @return key 在 T1 或 T2 中返回 true，否则 false
     */
    public function has(key:Object):Boolean {
        var node:Object = this.nodeMap[key];
        if (node === undefined) return false;
        var list:Object = node.list;
        return (list === this.T1 || list === this.T2);
    }

    // ==================== 调试方法 ====================

    /**
     * 获取指定队列中所有节点 uid（从头到尾）。
     * 仅用于调试，不建议在生产环境频繁调用。
     */
    private function _getListContents(list:Object):Array {
        var arr:Array = [];
        var s:Object = list.sentinel;
        var curr:Object = s.next;
        while (curr !== s) {
            arr.push(curr.uid);
            curr = curr.next;
        }
        return arr;
    }

    public function getT1():Array { return this._getListContents(this.T1); }
    public function getT2():Array { return this._getListContents(this.T2); }
    public function getB1():Array { return this._getListContents(this.B1); }
    public function getB2():Array { return this._getListContents(this.B2); }
    public function getCapacity():Number { return this.maxCapacity; }
}
