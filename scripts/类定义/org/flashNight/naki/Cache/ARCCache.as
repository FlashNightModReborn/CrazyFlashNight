/**
 * ARCCache v2.0 — Adaptive Replacement Cache (AS2 sentinel + inline optimized)
 *
 * 基于 Megiddo & Modha (2003) ARC 论文的完整实现。
 *
 * v2.0 重写变更摘要：
 * ─────────────────
 * [P0] CRITICAL-1 fix : putNoEvict 不再通过 this.get() 虚调用 → 消除子类无限递归
 * [P0] CRITICAL-2 fix : put() 正确处理 B1/B2 中的 key（p 自适应 + REPLACE + 移入 T2）
 * [P0] HIGH-1 fix     : _doReplace 增加 |T1|>0 前置守卫，修复 B2 hit + T1 空时的淘汰缺失
 * [P0] HIGH-2 fix     : 新增 _hitType 字段，子类可区分 MISS / GHOST / HIT，
 *                        完全未命中走 put() 触发淘汰而非 putNoEvict()
 * [P1] OPT-1          : 值直接存储在节点 node.value 上，消除独立 cacheStore 哈希表
 * [P1] OPT-2          : put/putNoEvict 更新路径全部内联，不再调用 get()
 * [P1] OPT-3          : T2 head 快速路径 — 已在头部时跳过 remove+addToHead
 * [P1] OPT-4          : 链表操作局部变量缓存 — unlink/addToHead/removeTail 模式中
 *                        缓存 node.prev/node.next/sentinel.next，消除冗余属性读取
 * [P2] sentinel        : 哨兵节点消除所有 head/tail null 分支检查
 * [P2] p adaptation    : 标准 ARC delta 公式 max(1, |B_other|/|B_self|)
 * [P2] Case IV         : 标准 ARC 幽灵清理（L1/L2 不变式）
 *
 * 队列不变式（所有操作维护）：
 *   0 <= |T1| + |T2| <= c
 *   0 <= |T1| + |B1| <= c          (L1)
 *   0 <= |T1|+|T2|+|B1|+|B2| <= 2c (总量)
 *   0 <= p <= c
 *
 * 四个队列说明：
 *   T1 — 最近访问的"冷"队列，存储最近被访问但不频繁使用的缓存项
 *   T2 — 最近访问的"热"队列，存储频繁使用的缓存项
 *   B1 — T1 的幽灵队列，记录被 T1 淘汰的键（不存值）
 *   B2 — T2 的幽灵队列，记录被 T2 淘汰的键（不存值）
 *
 * 节点结构：{ uid:String, prev:Object, next:Object, list:Object, value:* }
 *   幽灵节点的 value 为 undefined
 *
 * 队列结构：{ sentinel:Object, size:Number }
 *   sentinel 是循环哨兵：空队列时 sentinel.prev = sentinel.next = sentinel
 *   head = sentinel.next, tail = sentinel.prev
 *
 * 链表操作三模式（OPT-4，所有 var 缓存均为消除冗余属性读取）：
 *   unlink:      var np=node.prev, nn=node.next; np.next=nn; nn.prev=np;
 *   addToHead:   var oh=s.next; node.next=oh; node.prev=s; oh.prev=node; s.next=node;
 *   removeTail:  var victim=s.prev, vp=victim.prev; vp.next=s; s.prev=vp;
 */
import org.flashNight.naki.DataStructures.*;

class org.flashNight.naki.Cache.ARCCache {

    // ==================== 字段 ====================

    private var maxCapacity:Number;
    private var p:Number;

    private var T1:Object;
    private var T2:Object;
    private var B1:Object;
    private var B2:Object;

    private var nodeMap:Object;

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

    // ==================== 构造 ====================

    public function ARCCache(capacity:Number) {
        this.maxCapacity = capacity;
        this.p = 0;
        this._hitType = 0;
        this.T1 = this._createQueue();
        this.T2 = this._createQueue();
        this.B1 = this._createQueue();
        this.B2 = this._createQueue();
        this.nodeMap = {};
    }

    // ==================== 内部工具 ====================

    /**
     * 创建带哨兵的空队列
     */
    private function _createQueue():Object {
        var s:Object = {};
        s.prev = s;
        s.next = s;
        return { sentinel: s, size: 0 };
    }

    /**
     * 重置所有队列和映射（供子类 reset/clear 使用）。
     *
     * public：AS2 没有 protected，子类（ARCEnhancedLazyCache.reset）需要调用。
     */
    public function _clear():Void {
        this.p = 0;
        this._hitType = 0;
        this.T1 = this._createQueue();
        this.T2 = this._createQueue();
        this.B1 = this._createQueue();
        this.B2 = this._createQueue();
        this.nodeMap = {};
    }

    /**
     * REPLACE(p, isB2Hit) — 标准 ARC 淘汰
     * 从 T1 或 T2 中淘汰一个条目到对应的幽灵队列。
     * 包含 |T1|>0 前置守卫（HIGH-1 fix）。
     *
     * 隐式前置条件：|T1|+|T2| >= 1（由 put() Case IV 保证）。
     */
    private function _doReplace(isB2Hit:Boolean):Void {
        var t1:Object = this.T1;
        var t1Size:Number = t1.size;

        // 标准 ARC REPLACE 条件：|T1|>0 AND (|T1|>p OR (isB2Hit AND |T1|==p))
        if ((t1Size > 0) && ((t1Size > this.p) || (isB2Hit && t1Size == this.p))) {
            // 从 T1 尾部淘汰 → B1
            var s1:Object = t1.sentinel;
            var victim:Object = s1.prev;
            // removeTail: 从 T1 移除
            var vp:Object = victim.prev;
            vp.next = s1;
            s1.prev = vp;
            t1.size--;
            victim.value = undefined; // 幽灵节点不存值
            // addToHead: 添加到 B1 头部
            var b1:Object = this.B1;
            var sb1:Object = b1.sentinel;
            var oh:Object = sb1.next;
            victim.next = oh;
            victim.prev = sb1;
            oh.prev = victim;
            sb1.next = victim;
            b1.size++;
            victim.list = b1;
        } else {
            // 从 T2 尾部淘汰 → B2
            var t2:Object = this.T2;
            var s2:Object = t2.sentinel;
            var victim2:Object = s2.prev;
            if (victim2 !== s2) {
                // removeTail: 从 T2 移除
                var vp2:Object = victim2.prev;
                vp2.next = s2;
                s2.prev = vp2;
                t2.size--;
                victim2.value = undefined;
                // addToHead: 添加到 B2 头部
                var b2:Object = this.B2;
                var sb2:Object = b2.sentinel;
                var oh2:Object = sb2.next;
                victim2.next = oh2;
                victim2.prev = sb2;
                oh2.prev = victim2;
                sb2.next = victim2;
                b2.size++;
                victim2.list = b2;
            }
        }
    }

    // ==================== get ====================

    /**
     * 从缓存获取项目。
     * 根据命中类型设置 _hitType，供子类判断后续操作。
     *
     * @param  key  要获取的键
     * @return 缓存命中时返回值；未命中或幽灵命中返回 null
     */
    public function get(key:Object):Object {
        // ---- UID 生成（内联，热路径优化） ----
        var uid:String;
        if (typeof(key) == "object" || typeof(key) == "function") {
            uid = "_" + Dictionary.getStaticUID(key);
        } else {
            uid = "_" + key;
        }

        var node:Object = this.nodeMap[uid];
        if (node == undefined) {
            this._hitType = 0; // MISS
            return null;
        }

        var nodeList:Object = node.list;
        var localT1:Object = this.T1;
        var localT2:Object = this.T2;

        // ---- 链表操作复用变量（AS2 函数作用域，各分支互斥） ----
        var np:Object; // node.prev 缓存
        var nn:Object; // node.next 缓存
        var oh:Object; // sentinel.next 缓存 (old head)

        // ---- T2 命中（最热路径优先） ----
        if (nodeList === localT2) {
            this._hitType = 1;
            var s:Object = localT2.sentinel;
            if (node !== s.next) {
                // unlink + addToHead（同队列移动，size 不变）
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
            // unlink: 从 T1 移除
            np = node.prev;
            nn = node.next;
            np.next = nn;
            nn.prev = np;
            localT1.size--;
            // addToHead: 添加到 T2 头部
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
            if (newP > this.maxCapacity) newP = this.maxCapacity;
            this.p = newP;

            // REPLACE
            this._doReplace(false);

            // unlink: 从 B1 移除
            np = node.prev;
            nn = node.next;
            np.next = nn;
            nn.prev = np;
            localB1.size--;
            // addToHead: 添加到 T2 头部
            var s3:Object = localT2.sentinel;
            oh = s3.next;
            node.next = oh;
            node.prev = s3;
            oh.prev = node;
            s3.next = node;
            localT2.size++;
            node.list = localT2;

            return null; // 幽灵命中无实际值
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

            // REPLACE
            this._doReplace(true);

            // unlink: 从 B2 移除
            np = node.prev;
            nn = node.next;
            np.next = nn;
            nn.prev = np;
            localB2b.size--;
            // addToHead: 添加到 T2 头部
            var s4:Object = localT2.sentinel;
            oh = s4.next;
            node.next = oh;
            node.prev = s4;
            oh.prev = node;
            s4.next = node;
            localT2.size++;
            node.list = localT2;

            return null;
        }

        // 不应到达此处
        this._hitType = 0;
        return null;
    }

    // ==================== put ====================

    /**
     * 向缓存放入项目。
     * 正确处理所有情况：T1/T2 更新、B1/B2 幽灵命中、完全新 key。
     *
     * @param key   要插入的键
     * @param value 要插入的值
     */
    public function put(key:Object, value:Object):Void {
        // ---- UID 生成 ----
        var uid:String;
        if (typeof(key) == "object" || typeof(key) == "function") {
            uid = "_" + Dictionary.getStaticUID(key);
        } else {
            uid = "_" + key;
        }

        var node:Object = this.nodeMap[uid];
        var localT1:Object = this.T1;
        var localT2:Object = this.T2;

        // ---- 链表操作复用变量 ----
        var np:Object;
        var nn:Object;
        var oh:Object;

        if (node != undefined) {
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

            // ---- B1 幽灵命中 (CRITICAL-2 fix) ----
            var localB1:Object = this.B1;
            if (nodeList === localB1) {
                var localB2:Object = this.B2;
                // p 自适应
                var d1:Number = localB2.size / localB1.size;
                if (d1 < 1) d1 = 1;
                var np1:Number = this.p + d1;
                if (np1 > this.maxCapacity) np1 = this.maxCapacity;
                this.p = np1;
                // REPLACE
                this._doReplace(false);
                // unlink: 从 B1 移除
                np = node.prev;
                nn = node.next;
                np.next = nn;
                nn.prev = np;
                localB1.size--;
                node.value = value;
                // addToHead: 添加到 T2
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

            // ---- B2 幽灵命中 (CRITICAL-2 fix) ----
            var localB2b:Object = this.B2;
            if (nodeList === localB2b) {
                // localB1 已在 B1 路径声明并赋值，AS2 函数作用域下此处可直接复用
                // p 自适应
                var d2:Number = localB1.size / localB2b.size;
                if (d2 < 1) d2 = 1;
                var np2:Number = this.p - d2;
                if (np2 < 0) np2 = 0;
                this.p = np2;
                // REPLACE
                this._doReplace(true);
                // unlink: 从 B2 移除
                np = node.prev;
                nn = node.next;
                np.next = nn;
                nn.prev = np;
                localB2b.size--;
                node.value = value;
                // addToHead: 添加到 T2
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
        // 标准 ARC 幽灵清理 + 淘汰 + 插入
        var mc:Number = this.maxCapacity;
        var lB1:Object = this.B1;
        var lB2:Object = this.B2;
        var L1:Number = localT1.size + lB1.size;

        if (L1 == mc) {
            // Case A：|L1| == c
            if (localT1.size < mc) {
                // removeTail: 删除 B1 尾部（最老幽灵）
                var sb1a:Object = lB1.sentinel;
                var ghost:Object = sb1a.prev;
                if (ghost !== sb1a) {
                    var gp:Object = ghost.prev;
                    gp.next = sb1a;
                    sb1a.prev = gp;
                    lB1.size--;
                    delete this.nodeMap[ghost.uid];
                }
                // REPLACE
                this._doReplace(false);
            } else {
                // |T1| == c, |B1| == 0：直接从 T1 删除（不进入 B1）
                var st1a:Object = localT1.sentinel;
                var direct:Object = st1a.prev;
                if (direct !== st1a) {
                    var dp:Object = direct.prev;
                    dp.next = st1a;
                    st1a.prev = dp;
                    localT1.size--;
                    delete this.nodeMap[direct.uid];
                }
                // 不调用 REPLACE（直接删除已腾出空间）
            }
        } else {
            // Case B：|L1| < c
            var L2:Number = localT2.size + lB2.size;
            if (L1 + L2 >= 2 * mc) {
                // removeTail: 删除 B2 尾部
                var sb2a:Object = lB2.sentinel;
                var ghost2:Object = sb2a.prev;
                if (ghost2 !== sb2a) {
                    var g2p:Object = ghost2.prev;
                    g2p.next = sb2a;
                    sb2a.prev = g2p;
                    lB2.size--;
                    delete this.nodeMap[ghost2.uid];
                }
            }
            // 如果缓存已满，REPLACE
            if (localT1.size + localT2.size >= mc) {
                this._doReplace(false);
            }
        }

        // addToHead: 插入新节点到 T1 头部
        var newNode:Object = { uid: uid, prev: undefined, next: undefined,
                               list: undefined, value: value };
        this.nodeMap[uid] = newNode;
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
     * v2.0 修复：
     *   - 不再调用 this.get()（消除虚调用 → 无限递归风险）
     *   - 正确处理 B1/B2 中的节点（先断链再插入）
     *
     * @param key   键
     * @param value 值
     */
    public function putNoEvict(key:Object, value:Object):Void {
        var uid:String;
        if (typeof(key) == "object" || typeof(key) == "function") {
            uid = "_" + Dictionary.getStaticUID(key);
        } else {
            uid = "_" + key;
        }

        var node:Object = this.nodeMap[uid];
        var localT1:Object = this.T1;
        var localT2:Object = this.T2;

        // ---- 链表操作复用变量 ----
        var np:Object;
        var nn:Object;
        var oh:Object;

        if (node != undefined) {
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

            // B1/B2 中（BUG-3 fix）：先从幽灵队列断链，再插入 T1
            // 注意：这是防御性代码。当前唯一调用者 ARCEnhancedLazyCache 在 ghost hit 时，
            // super.get() 已将 node 从 B→T2，后续 putNoEvict 走 T2 更新分支。
            // 此分支仅在直接调 putNoEvict(ghostKey) 时触发。
            // 插入 T1（而非 T2）是有意为之：未经 p 自适应的回填不应享受 T2 热端优先级。
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

        // addToHead: 全新节点 → T1（不淘汰）
        var newNode:Object = { uid: uid, prev: undefined, next: undefined,
                               list: undefined, value: value };
        this.nodeMap[uid] = newNode;
        var s4:Object = localT1.sentinel;
        oh = s4.next;
        newNode.next = oh;
        newNode.prev = s4;
        oh.prev = newNode;
        s4.next = newNode;
        localT1.size++;
        newNode.list = localT1;
    }

    // ==================== remove ====================

    /**
     * 从缓存中移除一个项目（包括幽灵队列中的记录）。
     *
     * @param  key 要移除的键
     * @return 成功移除返回 true，否则 false
     */
    public function remove(key:Object):Boolean {
        var uid:String;
        if (typeof(key) == "object" || typeof(key) == "function") {
            uid = "_" + Dictionary.getStaticUID(key);
        } else {
            uid = "_" + key;
        }

        var node:Object = this.nodeMap[uid];
        if (node == undefined) return false;

        // unlink: 哨兵节点使断链无需分支
        var np:Object = node.prev;
        var nn:Object = node.next;
        np.next = nn;
        nn.prev = np;
        node.list.size--;
        delete this.nodeMap[uid];
        return true;
    }

    // ==================== 调试方法 ====================

    /**
     * 获取指定队列中所有节点 UID（从头到尾）
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
