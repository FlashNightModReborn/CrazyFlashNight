/**
 * ARCCache 类 (AS2内联极致优化版)
 * 
 * 使用链表在 AS2 中实现自适应替换缓存（Adaptive Replacement Cache, ARC）算法。
 * 
 * ARC 算法通过结合最近最少使用（LRU）和最不常使用（LFU）的优点，动态调整缓存策略以适应不同的访问模式。
 * 
 * 本实现进行了以下优化：
 * 1. 将 _addToHead、_removeNode、_replace、_shrinkGhosts 等私有函数逻辑内联展开，
 *    减少在 AS2 中的函数调用层次，从而提升性能。
 * 2. 依旧维持单次淘汰、B1/B2 幽灵队列机制，以及 p 的自适应调节。
 * 
 * 四个队列说明：
 * - T1 (最近访问的“冷”队列): 存储最近被访问但不频繁使用的缓存项。
 * - T2 (最近访问的“热”队列): 存储频繁使用的缓存项。
 * - B1 (T1 的幽灵队列): 记录被 T1 淘汰的缓存项的键，用于调整 p 参数。
 * - B2 (T2 的幽灵队列): 记录被 T2 淘汰的缓存项的键，用于调整 p 参数。
 * 
 */
import org.flashNight.naki.DataStructures.*;

class org.flashNight.naki.Cache.ARCCache {
    private var maxCapacity:Number; // 缓存的最大容量
    private var p:Number;           // 自适应参数，用于平衡 T1 和 T2 的大小

    // 四个队列：T1(冷), T2(热), B1(冷的幽灵), B2(热的幽灵)
    private var T1:Object;
    private var T2:Object;
    private var B1:Object;
    private var B2:Object;

    // 缓存的实际存储和节点映射
    private var cacheStore:Object;
    private var nodeMap:Object;

    /**
     * 构造函数
     * 初始化四个队列和映射结构。
     * 
     * @param capacity 缓存的最大容量
     */
    public function ARCCache(capacity:Number) {
        this.maxCapacity = capacity;
        this.p = 0;

        // 初始化 T1, T2, B1, B2 队列
        this.T1 = { head: null, tail: null, size: 0 };
        this.T2 = { head: null, tail: null, size: 0 };
        this.B1 = { head: null, tail: null, size: 0 };
        this.B2 = { head: null, tail: null, size: 0 };

        // 初始化缓存存储和节点映射
        this.cacheStore = {};
        this.nodeMap = {};
    }

    /**
     * 从缓存获取项目
     * 
     * 根据 ARC 算法，处理 T1、T2 命中和 B1、B2 命中情况，进行相应的队列调整和淘汰。
     * 
     * @param key 要获取的键
     * @return 若缓存命中则返回对应的值，否则返回 null
     */
    public function get(key:Object):Object {
        // 生成键的唯一标识符 (UID)
        var uid:String;
        if (typeof(key) == "object" || typeof(key) == "function") {
            uid = "_" + Dictionary.getStaticUID(key);
        } else {
            uid = "_" + key;
        }

        // 查找节点是否存在于缓存映射中
        var node:Object = this.nodeMap[uid];

        // 局部化引用以提升性能
        var localT1:Object = this.T1;
        var localT2:Object = this.T2;
        var localB1:Object = this.B1;
        var localB2:Object = this.B2;
        var localCacheStore:Object = this.cacheStore;
        var localP:Number = this.p; // 临时保存 p 的值

        if (node != null) {
            var nodeList:Object = node.list;

            if (nodeList === localT1) {
                /**
                 * 命中 T1:
                 * - 从 T1 移除节点
                 * - 将节点添加到 T2 的头部，提升其优先级
                 * - 返回缓存值
                 */
                
                // === 从 T1 移除节点 ===
                var pN:Object = node.prev;
                var nN:Object = node.next;
                if (pN != null) {
                    pN.next = nN;
                } else {
                    localT1.head = nN;
                }
                if (nN != null) {
                    nN.prev = pN;
                } else {
                    localT1.tail = pN;
                }
                localT1.size--;
                node.prev = null;
                node.next = null;
                // === end of 移除节点 ===

                // === 将节点添加到 T2 的头部 ===
                node.prev = null;
                node.next = localT2.head;
                if (localT2.head != null) {
                    localT2.head.prev = node;
                } else {
                    localT2.tail = node;
                }
                localT2.head = node;
                localT2.size++;
                // === end of 添加节点 ===

                node.list = localT2; // 更新节点所在队列
                return localCacheStore[uid];

            } else if (nodeList === localT2) {
                /**
                 * 命中 T2:
                 * - 从 T2 移除节点
                 * - 再次添加到 T2 的头部，保持其高优先级
                 * - 返回缓存值
                 */

                // === 从 T2 移除节点 ===
                var pN2:Object = node.prev;
                var nN2:Object = node.next;
                if (pN2 != null) {
                    pN2.next = nN2;
                } else {
                    localT2.head = nN2;
                }
                if (nN2 != null) {
                    nN2.prev = pN2;
                } else {
                    localT2.tail = pN2;
                }
                localT2.size--;
                node.prev = null;
                node.next = null;
                // === end of 移除节点 ===

                // === 将节点重新添加到 T2 的头部 ===
                node.prev = null;
                node.next = localT2.head;
                if (localT2.head != null) {
                    localT2.head.prev = node;
                } else {
                    localT2.tail = node;
                }
                localT2.head = node;
                localT2.size++;
                // === end of 添加节点 ===

                return localCacheStore[uid];

            } else if (nodeList === localB1) {
                /**
                 * 命中 B1 (冷的幽灵队列):
                 * - 自适应增加 p，以偏向 T1
                 * - 进行单次淘汰 (从 T1 或 T2)
                 * - 将命中的节点从 B1 移动到 T2
                 * - 返回 null，表示未实际命中缓存
                 */

                // 自适应增加 p，但不超过 maxCapacity
                if (localP < this.maxCapacity) localP++;

                // === 单次淘汰逻辑 (_replace(false, localP)) ===
                var cond:Boolean = (localT1.size > localP);
                if (cond) {
                    // 从 T1 尾部移除一个节点作为受害者
                    var victim:Object = localT1.tail;
                    if (victim != null) {
                        // === 从 T1 移除 victim ===
                        var vp:Object = victim.prev;
                        var vn:Object = victim.next;
                        if (vp != null) {
                            vp.next = vn;
                        } else {
                            localT1.head = vn;
                        }
                        if (vn != null) {
                            vn.prev = vp;
                        } else {
                            localT1.tail = vp;
                        }
                        localT1.size--;
                        victim.prev = null;
                        victim.next = null;
                        // === end of 移除 victim ===

                        // 从 cacheStore 中删除受害者
                        delete localCacheStore[victim.uid];

                        // 将受害者添加到 B1 的头部
                        victim.prev = null;
                        victim.next = localB1.head;
                        if (localB1.head != null) {
                            localB1.head.prev = victim;
                        } else {
                            localB1.tail = victim;
                        }
                        localB1.head = victim;
                        localB1.size++;
                        victim.list = localB1;
                    }
                } else {
                    // 从 T2 尾部移除一个节点作为受害者
                    var victim2:Object = localT2.tail;
                    if (victim2 != null) {
                        // === 从 T2 移除 victim2 ===
                        var v2p:Object = victim2.prev;
                        var v2n:Object = victim2.next;
                        if (v2p != null) {
                            v2p.next = v2n;
                        } else {
                            localT2.head = v2n;
                        }
                        if (v2n != null) {
                            v2n.prev = v2p;
                        } else {
                            localT2.tail = v2p;
                        }
                        localT2.size--;
                        victim2.prev = null;
                        victim2.next = null;
                        // === end of 移除 victim2 ===

                        // 从 cacheStore 中删除受害者
                        delete localCacheStore[victim2.uid];

                        // 将受害者添加到 B2 的头部
                        victim2.prev = null;
                        victim2.next = localB2.head;
                        if (localB2.head != null) {
                            localB2.head.prev = victim2;
                        } else {
                            localB2.tail = victim2;
                        }
                        localB2.head = victim2;
                        localB2.size++;
                        victim2.list = localB2;
                    }
                }
                // === end of 单次淘汰 ===

                // 将命中的 node 从 B1 移动到 T2
                var pNB1:Object = node.prev;
                var nNB1:Object = node.next;
                if (pNB1 != null) {
                    pNB1.next = nNB1;
                } else {
                    localB1.head = nNB1;
                }
                if (nNB1 != null) {
                    nNB1.prev = pNB1;
                } else {
                    localB1.tail = pNB1;
                }
                localB1.size--;
                node.prev = null;
                node.next = null;

                // === 将 node 添加到 T2 的头部 ===
                node.prev = null;
                node.next = localT2.head;
                if (localT2.head != null) {
                    localT2.head.prev = node;
                } else {
                    localT2.tail = node;
                }
                localT2.head = node;
                localT2.size++;
                // === end of 添加节点 ===

                node.list = localT2; // 更新节点所在队列

                this.p = localP; // 更新 p 的值
                return null; // B1/B2 不存实际值，因此返回 null

            } else if (nodeList === localB2) {
                /**
                 * 命中 B2 (热的幽灵队列):
                 * - 自适应减少 p，以偏向 T2
                 * - 进行单次淘汰 (从 T1 或 T2)
                 * - 将命中的节点从 B2 移动到 T2
                 * - 返回 null，表示未实际命中缓存
                 */

                // 自适应减少 p，但不小于 0
                if (localP > 0) localP--;

                // === 单次淘汰逻辑 (_replace(true, localP)) ===
                var cond2:Boolean = (localT1.size > localP) || (true && localT1.size == localP);
                if (cond2) {
                    // 从 T1 尾部移除一个节点作为受害者
                    var victim3:Object = localT1.tail;
                    if (victim3 != null) {
                        // === 从 T1 移除 victim3 ===
                        var vp3:Object = victim3.prev;
                        var vn3:Object = victim3.next;
                        if (vp3 != null) {
                            vp3.next = vn3;
                        } else {
                            localT1.head = vn3;
                        }
                        if (vn3 != null) {
                            vn3.prev = vp3;
                        } else {
                            localT1.tail = vp3;
                        }
                        localT1.size--;
                        victim3.prev = null;
                        victim3.next = null;
                        // === end of 移除 victim3 ===

                        // 从 cacheStore 中删除受害者
                        delete localCacheStore[victim3.uid];

                        // 将受害者添加到 B1 的头部
                        victim3.prev = null;
                        victim3.next = localB1.head;
                        if (localB1.head != null) {
                            localB1.head.prev = victim3;
                        } else {
                            localB1.tail = victim3;
                        }
                        localB1.head = victim3;
                        localB1.size++;
                        victim3.list = localB1;
                    }
                } else {
                    // 从 T2 尾部移除一个节点作为受害者
                    var victim4:Object = localT2.tail;
                    if (victim4 != null) {
                        // === 从 T2 移除 victim4 ===
                        var v4p:Object = victim4.prev;
                        var v4n:Object = victim4.next;
                        if (v4p != null) {
                            v4p.next = v4n;
                        } else {
                            localT2.head = v4n;
                        }
                        if (v4n != null) {
                            v4n.prev = v4p;
                        } else {
                            localT2.tail = v4p;
                        }
                        localT2.size--;
                        victim4.prev = null;
                        victim4.next = null;
                        // === end of 移除 victim4 ===

                        // 从 cacheStore 中删除受害者
                        delete localCacheStore[victim4.uid];

                        // 将受害者添加到 B2 的头部
                        victim4.prev = null;
                        victim4.next = localB2.head;
                        if (localB2.head != null) {
                            localB2.head.prev = victim4;
                        } else {
                            localB2.tail = victim4;
                        }
                        localB2.head = victim4;
                        localB2.size++;
                        victim4.list = localB2;
                    }
                }
                // === end of 单次淘汰 ===

                // 将命中的 node 从 B2 移动到 T2
                var pNB2:Object = node.prev;
                var nNB2:Object = node.next;
                if (pNB2 != null) {
                    pNB2.next = nNB2;
                } else {
                    localB2.head = nNB2;
                }
                if (nNB2 != null) {
                    nNB2.prev = pNB2;
                } else {
                    localB2.tail = pNB2;
                }
                localB2.size--;
                node.prev = null;
                node.next = null;

                // === 将 node 添加到 T2 的头部 ===
                node.prev = null;
                node.next = localT2.head;
                if (localT2.head != null) {
                    localT2.head.prev = node;
                } else {
                    localT2.tail = node;
                }
                localT2.head = node;
                localT2.size++;
                // === end of 添加节点 ===

                node.list = localT2; // 更新节点所在队列

                this.p = localP; // 更新 p 的值
                return null; // B1/B2 不存实际值，因此返回 null
            }
        }
    }
    /**
     * 向缓存放入项目
     * 
     * 根据 ARC 算法，处理新项目的插入和现有项目的更新。
     * 
     * @param key 要插入的键
     * @param value 要插入的值
     */
    public function put(key:Object, value:Object):Void {
        // 生成键的唯一标识符 (UID)
        var uid:String;
        if (typeof(key) == "object" || typeof(key) == "function") {
            uid = "_" + Dictionary.getStaticUID(key);
        } else {
            uid = "_" + key;
        }

        // 查找节点是否存在于缓存映射中
        var node:Object = this.nodeMap[uid];

        // 局部化引用以提升性能
        var localT1:Object = this.T1;
        var localT2:Object = this.T2;
        var localB1:Object = this.B1;
        var localB2:Object = this.B2;
        var localCacheStore:Object = this.cacheStore;
        var localNodeMap:Object = this.nodeMap;
        var localP:Number = this.p;

        var inT1:Boolean = (node != null) && (node.list === localT1);
        var inT2:Boolean = (node != null) && (node.list === localT2);

        if (inT1 || inT2) {
            /**
             * 更新现有缓存项：
             * - 更新缓存值
             * - 调用 get(key) 以提升其优先级
             */
            localCacheStore[uid] = value;
            this.get(key);
            return;
        } else {
            /**
             * 插入新缓存项：
             * - 检查是否需要淘汰
             * - 进行单次淘汰 (从 T1 或 T2)
             * - 清理幽灵队列 (B1 和 B2)
             * - 将新节点添加到 T1 的头部
             */
            
            // 计算当前缓存的大小 (T1 + T2)
            var totalSize:Number = localT1.size + localT2.size;
            if (totalSize >= this.maxCapacity) {
                // 需要淘汰一个受害者
                var cond:Boolean = (localT1.size > localP); // 仅考虑 T1 大于 p
                if (cond) {
                    // 从 T1 尾部移除一个节点作为受害者
                    var victim:Object = localT1.tail;
                    if (victim != null) {
                        // === 从 T1 移除 victim ===
                        var vp:Object = victim.prev;
                        var vn:Object = victim.next;
                        if (vp != null) {
                            vp.next = vn;
                        } else {
                            localT1.head = vn;
                        }
                        if (vn != null) {
                            vn.prev = vp;
                        } else {
                            localT1.tail = vp;
                        }
                        localT1.size--;
                        victim.prev = null;
                        victim.next = null;
                        // === end of 移除 victim ===

                        // 从 cacheStore 中删除受害者
                        delete localCacheStore[victim.uid];

                        // 将受害者添加到 B1 的头部
                        victim.prev = null;
                        victim.next = localB1.head;
                        if (localB1.head != null) {
                            localB1.head.prev = victim;
                        } else {
                            localB1.tail = victim;
                        }
                        localB1.head = victim;
                        localB1.size++;
                        victim.list = localB1;
                    }
                } else {
                    // 从 T2 尾部移除一个节点作为受害者
                    var victim2:Object = localT2.tail;
                    if (victim2 != null) {
                        // === 从 T2 移除 victim2 ===
                        var v2p:Object = victim2.prev;
                        var v2n:Object = victim2.next;
                        if (v2p != null) {
                            v2p.next = v2n;
                        } else {
                            localT2.head = v2n;
                        }
                        if (v2n != null) {
                            v2n.prev = v2p;
                        } else {
                            localT2.tail = v2p;
                        }
                        localT2.size--;
                        victim2.prev = null;
                        victim2.next = null;
                        // === end of 移除 victim2 ===

                        // 从 cacheStore 中删除受害者
                        delete localCacheStore[victim2.uid];

                        // 将受害者添加到 B2 的头部
                        victim2.prev = null;
                        victim2.next = localB2.head;
                        if (localB2.head != null) {
                            localB2.head.prev = victim2;
                        } else {
                            localB2.tail = victim2;
                        }
                        localB2.head = victim2;
                        localB2.size++;
                        victim2.list = localB2;
                    }
                }
            }

            /**
             * 清理幽灵队列 (B1 和 B2)：
             * 确保 B1 + B2 的总大小不超过 2 * maxCapacity
             * 优先清理 B2，因为它对应的是热的幽灵队列
             */
            var localB1Size:Number = this.B1.size;
            var localB2Size:Number = this.B2.size;
            while ((localB1Size + localB2Size) > (2 * this.maxCapacity)) {
                // 优先清理 B2 队列
                if (localB2Size > this.maxCapacity) {
                    var removed:Object = this.B2.tail;
                    if (removed != null) {
                        // === 从 B2 移除 removed ===
                        var rp:Object = removed.prev;
                        var rn:Object = removed.next;
                        if (rp != null) {
                            rp.next = rn;
                        } else {
                            this.B2.head = rn;
                        }
                        if (rn != null) {
                            rn.prev = rp;
                        } else {
                            this.B2.tail = rp;
                        }
                        this.B2.size--;
                        removed.prev = null;
                        removed.next = null;
                        // === end of 移除 removed ===

                        // 从节点映射中删除 removed
                        delete this.nodeMap[removed.uid];
                        localB2Size--;
                    }
                } else if (localB1Size > this.maxCapacity) {
                    // 清理 B1 队列
                    var removed2:Object = this.B1.tail;
                    if (removed2 != null) {
                        // === 从 B1 移除 removed2 ===
                        var r2p:Object = removed2.prev;
                        var r2n:Object = removed2.next;
                        if (r2p != null) {
                            r2p.next = r2n;
                        } else {
                            this.B1.head = r2n;
                        }
                        if (r2n != null) {
                            r2n.prev = r2p;
                        } else {
                            this.B1.tail = r2p;
                        }
                        this.B1.size--;
                        removed2.prev = null;
                        removed2.next = null;
                        // === end of 移除 removed2 ===

                        // 从节点映射中删除 removed2
                        delete this.nodeMap[removed2.uid];
                        localB1Size--;
                    }
                } else {
                    // 如果 B1 和 B2 的大小均未超过，则停止清理
                    break;
                }
            }
            // === end of 清理幽灵队列 ===

            /**
             * 将新节点添加到 T1 的头部：
             * - 创建新的节点对象
             * - 将其添加到 T1 的头部
             * - 更新缓存存储
             */
            var newNode:Object = { uid: uid, prev: null, next: null, list: null };
            localNodeMap[uid] = newNode;

            // === 添加到 T1 的头部 ===
            newNode.prev = null;
            newNode.next = localT1.head;
            if (localT1.head != null) {
                localT1.head.prev = newNode;
            } else {
                localT1.tail = newNode;
            }
            localT1.head = newNode;
            localT1.size++;
            // === end of 添加到 T1 ===

            newNode.list = localT1; // 更新节点所在队列
            localCacheStore[uid] = value; // 更新缓存存储
        }
    }

    /**
     * 新增方法：不进行“容量检查”的 put
     * 
     * 在子类处理幽灵队列命中时调用，避免再次触发淘汰逻辑。
     * 
     * @param key 要插入的键
     * @param value 要插入的值
     */
    public function putNoEvict(key:Object, value:Object):Void {
        // 生成键的唯一标识符 (UID)
        var uid:String;
        if (typeof(key) == "object" || typeof(key) == "function") {
            uid = "_" + Dictionary.getStaticUID(key);
        } else {
            uid = "_" + key;
        }

        // 查找节点是否存在于缓存映射中
        var node:Object = this.nodeMap[uid];

        // 局部化引用以提升性能
        var localT1:Object = this.T1;
        var localT2:Object = this.T2;
        var localCacheStore:Object = this.cacheStore;
        var localNodeMap:Object = this.nodeMap;

        var inT1:Boolean = (node != null) && (node.list === localT1);
        var inT2:Boolean = (node != null) && (node.list === localT2);

        if (inT1 || inT2) {
            /**
             * 更新现有缓存项：
             * - 更新缓存值
             * - 调用 get(key) 以提升其优先级
             */
            localCacheStore[uid] = value;
            this.get(key);
        } else {
            /**
             * 插入新缓存项，不进行容量检查：
             * - 创建新的节点对象（如果不存在）
             * - 将其添加到 T1 的头部
             * - 更新缓存存储
             */
            var newNode:Object = node;
            if (newNode == null) {
                newNode = { uid: uid, prev: null, next: null, list: null };
                localNodeMap[uid] = newNode;
            }

            // === 添加到 T1 的头部 ===
            var headNode:Object = localT1.head;
            newNode.prev = null;
            newNode.next = headNode;
            if (headNode != null) {
                headNode.prev = newNode;
            } else {
                localT1.tail = newNode;
            }
            localT1.head = newNode;
            localT1.size++;
            // === end of 添加到 T1 ===

            newNode.list = localT1; // 更新节点所在队列
            localCacheStore[uid] = value; // 更新缓存存储
        }
    }

    /**
     * 从缓存中移除一个项目（包括其在幽灵队列中的记录）
     * 
     * @param key 要移除的键
     * @return {Boolean} 如果成功移除了一个项目，返回 true；否则返回 false
     */
    public function remove(key:Object):Boolean {
        // 1. 生成键的唯一标识符 (UID)
        var uid:String;
        if (typeof(key) == "object" || typeof(key) == "function") {
            // 注意：如果key是临时对象，可能无法获取到正确的UID。
            // 这里假设key是稳定的，与put时传入的key一致。
            uid = "_" + Dictionary.getStaticUID(key);
        } else {
            uid = "_" + key;
        }

        // 2. 查找节点是否存在于缓存映射中
        var node:Object = this.nodeMap[uid];

        // 3. 节点不存在，直接返回
        if (node == null) {
            return false;
        }

        // 4. 节点存在，开始移除流程
        var list:Object = node.list;
        
        // a. 从链中断开
        var prevNode:Object = node.prev;
        var nextNode:Object = node.next;

        if (prevNode != null) {
            prevNode.next = nextNode;
        } else {
            // 节点是头节点
            list.head = nextNode;
        }

        if (nextNode != null) {
            nextNode.prev = prevNode;
        } else {
            // 节点是尾节点
            list.tail = prevNode;
        }
        
        // b. 更新队列大小
        list.size--;

        // c. 清理存储
        // 如果节点在 T1 或 T2，从 cacheStore 删除
        if (list === this.T1 || list === this.T2) {
            delete this.cacheStore[uid];
        }
        
        // 从 nodeMap 中删除
        delete this.nodeMap[uid];

        return true;
    }

    /**
     * 获取指定队列中的所有节点 UID
     * 
     * 仅用于调试和测试目的，不影响缓存逻辑。
     * 
     * @param list 要获取内容的队列对象 (T1, T2, B1, B2)
     * @return 包含所有节点 UID 的数组
     */
    private function _getListContents(list:Object):Array {
        var arr:Array = [];
        var curr:Object = list.head;
        while (curr != null) {
            arr.push(curr.uid);
            curr = curr.next;
        }
        return arr;
    }

    /**
     * 调试用：获取 T1 队列的节点 UID 列表
     * 
     * @return 包含 T1 队列中所有节点 UID 的数组
     */
    public function getT1():Array {
        return this._getListContents(this.T1);
    }

    /**
     * 调试用：获取 T2 队列的节点 UID 列表
     * 
     * @return 包含 T2 队列中所有节点 UID 的数组
     */
    public function getT2():Array {
        return this._getListContents(this.T2);
    }

    /**
     * 调试用：获取 B1 队列的节点 UID 列表
     * 
     * @return 包含 B1 队列中所有节点 UID 的数组
     */
    public function getB1():Array {
        return this._getListContents(this.B1);
    }

    /**
     * 调试用：获取 B2 队列的节点 UID 列表
     * 
     * @return 包含 B2 队列中所有节点 UID 的数组
     */
    public function getB2():Array {
        return this._getListContents(this.B2);
    }

    /**
     * 调试用：获取 最大容量上限
     * 
     * @return maxCapacity 最大容量上限
     */
    public function getCapacity():Number {
        return this.maxCapacity;
    }
}
