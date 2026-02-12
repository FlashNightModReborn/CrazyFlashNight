/**
 * ARCCache v3.0 — Adaptive Replacement Cache (AS2 raw-key + pooling + robust)
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
     * 重置所有队列和映射（供子类 reset/clear 使用）。
     * P2 OPT-8：重用哨兵节点，避免 8 次对象分配。
     *
     * public：AS2 没有 protected，子类（ARCEnhancedLazyCache.reset）需要调用。
     */
    public function _clear():Void {
        this.p = 0;
        this._hitType = 0;
        this._lastNode = null;
        this._pool = null;
        // 重用哨兵
        var s:Object;
        s = this.T1.sentinel; s.prev = s; s.next = s; this.T1.size = 0;
        s = this.T2.sentinel; s.prev = s; s.next = s; this.T2.size = 0;
        s = this.B1.sentinel; s.prev = s; s.next = s; this.B1.size = 0;
        s = this.B2.sentinel; s.prev = s; s.next = s; this.B2.size = 0;
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

    // ==================== get ====================

    /**
     * 从缓存获取项目。
     * 根据命中类型设置 _hitType，供子类判断后续操作。
     *
     * @param  key  要获取的键（原始键，直接用作属性名）
     * @return 缓存命中时返回值；未命中或幽灵命中返回 null
     */
    public function get(key:Object):Object {
        var node:Object = this.nodeMap[key];
        if (node === undefined) {
            this._hitType = 0; // MISS
            this._lastNode = null;
            return null;
        }

        var nodeList:Object = node.list;
        var localT1:Object = this.T1;
        var localT2:Object = this.T2;

        // ---- 链表操作复用变量（AS2 函数作用域，各分支互斥） ----
        var np:Object;
        var nn:Object;
        var oh:Object;

        // ---- T2 命中（最热路径优先） ----
        if (nodeList === localT2) {
            this._hitType = 1;
            var s:Object = localT2.sentinel;
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
            var s2:Object = localT2.sentinel;
            oh = s2.next;
            node.next = oh;
            node.prev = s2;
            oh.prev = node;
            s2.next = node;
            localT2.size++;
            node.list = localT2;
            return node.value;
        }

        // ---- B1 幽灵命中 ----
        var localB1:Object = this.B1;
        if (nodeList === localB1) {
            this._hitType = 2;
            var localB2:Object = this.B2;

            // p 自适应：增大（偏向 T1 扩张）
            var d1:Number = localB2.size / localB1.size;
            if (d1 < 1) d1 = 1;
            var newP:Number = this.p + d1;
            var mc:Number = this.maxCapacity;
            if (newP > mc) newP = mc;
            this.p = newP;

            // ROBUST-2：仅在 cache 满时 REPLACE
            if (localT1.size + localT2.size >= mc) {
                this._doReplace(false);
            }

            // unlink from B1
            np = node.prev;
            nn = node.next;
            np.next = nn;
            nn.prev = np;
            localB1.size--;
            // addToHead T2
            var s3:Object = localT2.sentinel;
            oh = s3.next;
            node.next = oh;
            node.prev = s3;
            oh.prev = node;
            s3.next = node;
            localT2.size++;
            node.list = localT2;

            this._lastNode = node; // OPT-5
            return null;
        }

        // ---- B2 幽灵命中 ----
        var localB2b:Object = this.B2;
        if (nodeList === localB2b) {
            this._hitType = 3;

            // p 自适应：减小（偏向 T2 扩张）
            var d2:Number = localB1.size / localB2b.size;
            if (d2 < 1) d2 = 1;
            var newP2:Number = this.p - d2;
            if (newP2 < 0) newP2 = 0;
            this.p = newP2;

            // ROBUST-2
            var mc2:Number = this.maxCapacity;
            if (localT1.size + localT2.size >= mc2) {
                this._doReplace(true);
            }

            // unlink from B2
            np = node.prev;
            nn = node.next;
            np.next = nn;
            nn.prev = np;
            localB2b.size--;
            // addToHead T2
            var s4:Object = localT2.sentinel;
            oh = s4.next;
            node.next = oh;
            node.prev = s4;
            oh.prev = node;
            s4.next = node;
            localT2.size++;
            node.list = localT2;

            this._lastNode = node; // OPT-5
            return null;
        }

        // 不应到达此处
        this._hitType = 0;
        this._lastNode = null;
        return null;
    }

    // ==================== put ====================

    /**
     * 向缓存放入项目。
     * 正确处理：T1/T2 更新、B1/B2 幽灵命中、完全新 key。
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

        if (node !== undefined) {
            var nodeList:Object = node.list;

            // ---- T2 中：更新值 + 移到头部 ----
            if (nodeList === localT2) {
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

            // ---- T1 中：更新值 + 移到 T2 头部 ----
            if (nodeList === localT1) {
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

            // ---- B1 幽灵命中 ----
            var localB1:Object = this.B1;
            if (nodeList === localB1) {
                var localB2:Object = this.B2;
                // p 自适应
                var d1:Number = localB2.size / localB1.size;
                if (d1 < 1) d1 = 1;
                var np1:Number = this.p + d1;
                var mc0:Number = this.maxCapacity;
                if (np1 > mc0) np1 = mc0;
                this.p = np1;
                // ROBUST-2
                if (localT1.size + localT2.size >= mc0) {
                    this._doReplace(false);
                }
                // unlink from B1
                np = node.prev;
                nn = node.next;
                np.next = nn;
                nn.prev = np;
                localB1.size--;
                node.value = value;
                // addToHead T2
                var s3:Object = localT2.sentinel;
                oh = s3.next;
                node.next = oh;
                node.prev = s3;
                oh.prev = node;
                s3.next = node;
                localT2.size++;
                node.list = localT2;
                return;
            }

            // ---- B2 幽灵命中 ----
            var localB2b:Object = this.B2;
            if (nodeList === localB2b) {
                var d2:Number = localB1.size / localB2b.size;
                if (d2 < 1) d2 = 1;
                var np2:Number = this.p - d2;
                if (np2 < 0) np2 = 0;
                this.p = np2;
                var mc1:Number = this.maxCapacity;
                if (localT1.size + localT2.size >= mc1) {
                    this._doReplace(true);
                }
                // unlink from B2
                np = node.prev;
                nn = node.next;
                np.next = nn;
                nn.prev = np;
                localB2b.size--;
                node.value = value;
                // addToHead T2
                var s4:Object = localT2.sentinel;
                oh = s4.next;
                node.next = oh;
                node.prev = s4;
                oh.prev = node;
                s4.next = node;
                localT2.size++;
                node.list = localT2;
                return;
            }
        }

        // ======== Case IV：完全新 key ========
        var mc:Number = this.maxCapacity;
        var lB1:Object = this.B1;
        var lB2:Object = this.B2;
        var L1:Number = localT1.size + lB1.size;

        if (L1 == mc) {
            // Case A：|L1| == c
            if (localT1.size < mc) {
                // removeTail B1（最老幽灵）+ pool
                var sb1a:Object = lB1.sentinel;
                var ghost:Object = sb1a.prev;
                if (ghost !== sb1a) {
                    var gp:Object = ghost.prev;
                    gp.next = sb1a;
                    sb1a.prev = gp;
                    lB1.size--;
                    delete this.nodeMap[ghost.uid];
                    // OPT-6 + OPT-10: pool（仅清 value）
                    ghost.value = undefined;
                    ghost.next = this._pool;
                    this._pool = ghost;
                }
                this._doReplace(false);
            } else {
                // |T1| == c: 直接从 T1 删除（不进 B1）+ pool
                var st1a:Object = localT1.sentinel;
                var direct:Object = st1a.prev;
                if (direct !== st1a) {
                    var dp:Object = direct.prev;
                    dp.next = st1a;
                    st1a.prev = dp;
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
                var sb2a:Object = lB2.sentinel;
                var ghost2:Object = sb2a.prev;
                if (ghost2 !== sb2a) {
                    var g2p:Object = ghost2.prev;
                    g2p.next = sb2a;
                    sb2a.prev = g2p;
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
     * 不触发淘汰的 put — 用于子类在幽灵命中后存储计算值。
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
            // 注：此路径在当前 LazyCache 中为死代码（ghost hit 走 OPT-5 _lastNode 直赋）
            // 保留供外部直接调用 putNoEvict(ghost_key) 的场景使用
            np = node.prev;
            nn = node.next;
            np.next = nn;
            nn.prev = np;
            nodeList.size--;
            node.value = value;
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
     * 契约：
     *   - 调用者 MUST 保证 nodeMap[key] === undefined
     *   - 违反契约将导致 nodeMap 中出现重复节点（数据损坏）
     *
     * @param key   键
     * @param value 值
     */
    public function _putNew(key:Object, value:Object):Void {
        var localT1:Object = this.T1;
        var localT2:Object = this.T2;
        var mc:Number = this.maxCapacity;
        var lB1:Object = this.B1;
        var lB2:Object = this.B2;
        var L1:Number = localT1.size + lB1.size;
        var oh:Object;

        if (L1 == mc) {
            if (localT1.size < mc) {
                // removeTail B1 + pool
                var sb1a:Object = lB1.sentinel;
                var ghost:Object = sb1a.prev;
                if (ghost !== sb1a) {
                    var gp:Object = ghost.prev;
                    gp.next = sb1a;
                    sb1a.prev = gp;
                    lB1.size--;
                    delete this.nodeMap[ghost.uid];
                    ghost.value = undefined;
                    ghost.next = this._pool;
                    this._pool = ghost;
                }
                this._doReplace(false);
            } else {
                // |T1| == c: 直接从 T1 删除 + pool
                var st1a:Object = localT1.sentinel;
                var direct:Object = st1a.prev;
                if (direct !== st1a) {
                    var dp:Object = direct.prev;
                    dp.next = st1a;
                    st1a.prev = dp;
                    localT1.size--;
                    delete this.nodeMap[direct.uid];
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
                var sb2a:Object = lB2.sentinel;
                var ghost2:Object = sb2a.prev;
                if (ghost2 !== sb2a) {
                    var g2p:Object = ghost2.prev;
                    g2p.next = sb2a;
                    sb2a.prev = g2p;
                    lB2.size--;
                    delete this.nodeMap[ghost2.uid];
                    ghost2.value = undefined;
                    ghost2.next = this._pool;
                    this._pool = ghost2;
                }
            }
            if (localT1.size + localT2.size >= mc) {
                this._doReplace(false);
            }
        }

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
