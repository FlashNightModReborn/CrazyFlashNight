/**
 * ARCCache 类
 * 使用链表在 AS2 中实现自适应替换缓存（Adaptive Replacement Cache）算法。
 * 该类经过性能优化，牺牲了一定的代码可读性，因此注释将详细解释每个代码块的功能和背后的原理。
 */
import org.flashNight.naki.DataStructures.*;

class org.flashNight.naki.Cache.ARCCache {
    // 缓存的最大容量
    private var maxCapacity:Number;

    // T1 和 T2 队列之间的平衡参数
    private var p:Number;

    // 缓存队列，使用链表表示
    private var T1:Object; // 最近使用的项目（冷数据）
    private var T2:Object; // 频繁使用的项目（热数据）
    private var B1:Object; // 从 T1 中移除的幽灵条目
    private var B2:Object; // 从 T2 中移除的幽灵条目

    // 存储缓存的实际数据
    private var cacheStore:Object; // 将 UID 映射到具体的值

    // 节点映射，用于快速访问
    private var nodeMap:Object; // 将 UID 映射到队列中的节点

    // 构造函数
    /**
     * 使用指定的容量初始化 ARCCache。
     * @param capacity 缓存可以容纳的最大项目数。
     */
    public function ARCCache(capacity:Number) {
        this.maxCapacity = capacity; // 设置缓存的最大容量
        this.p = 0; // 初始化平衡参数 p

        // 初始化四个缓存队列，使用链表结构
        this.T1 = { head: null, tail: null, size: 0 }; // 冷数据队列
        this.T2 = { head: null, tail: null, size: 0 }; // 热数据队列
        this.B1 = { head: null, tail: null, size: 0 }; // 冷数据的幽灵队列
        this.B2 = { head: null, tail: null, size: 0 }; // 热数据的幽灵队列

        // 初始化缓存存储和节点映射
        this.cacheStore = {}; // 用于存储实际的缓存值，键为 UID
        this.nodeMap = {}; // 用于快速查找节点，键为 UID
    }

    // 公共方法
    /**
     * 从缓存中检索一个项目。
     * @param key 要检索的项目的键（对象或原始类型）。
     * @return 缓存的值，如果未找到则返回 null。
     */
    public function get(key:Object):Object {
        var uid:String;
        // 根据键的类型生成唯一标识符 UID
        if (typeof key == "object" || typeof key == "function") {
            uid = "_" + Dictionary.getStaticUID(key); // 对象类型，使用静态 UID
        } else {
            uid = "_" + key; // 原始类型，直接转换为字符串
        }

        // 从节点映射中获取对应的节点
        var node:Object = this.nodeMap[uid];

        // 为了提高性能，将频繁访问的属性局部化，减少解引用开销
        var localT1:Object = this.T1;
        var localT2:Object = this.T2;
        var localB1:Object = this.B1;
        var localB2:Object = this.B2;
        var localCacheStore:Object = this.cacheStore;

        // 检查节点是否存在于缓存或幽灵列表中
        if (node != null) {
            var nodeList:Object = node.list;
            if (nodeList === localT1) {
                // 命中 T1 队列（冷数据）

                // 从 T1 中移除节点
                var prevNode:Object = node.prev;
                var nextNode:Object = node.next;

                if (prevNode != null) {
                    prevNode.next = nextNode;
                } else {
                    localT1.head = nextNode;
                }

                if (nextNode != null) {
                    nextNode.prev = prevNode;
                } else {
                    localT1.tail = prevNode;
                }

                // 更新 T1 队列的大小
                localT1.size--;

                // 将节点添加到 T2 的头部
                node.prev = null;
                node.next = localT2.head;
                if (localT2.head != null) {
                    localT2.head.prev = node;
                } else {
                    localT2.tail = node;
                }
                localT2.head = node;
                localT2.size++;

                // 更新节点所在的列表引用
                node.list = localT2;

                // 返回缓存的值
                return localCacheStore[uid];

            } else if (nodeList === localT2) {
                // 命中 T2 队列（热数据）

                // 从 T2 中移除节点
                prevNode = node.prev;
                nextNode = node.next;

                if (prevNode != null) {
                    prevNode.next = nextNode;
                } else {
                    localT2.head = nextNode;
                }

                if (nextNode != null) {
                    nextNode.prev = prevNode;
                } else {
                    localT2.tail = prevNode;
                }

                // 更新 T2 队列的大小
                localT2.size--;

                // 将节点重新添加到 T2 的头部（提升优先级）
                node.prev = null;
                node.next = localT2.head;
                if (localT2.head != null) {
                    localT2.head.prev = node;
                } else {
                    localT2.tail = node;
                }
                localT2.head = node;
                localT2.size++;

                // 返回缓存的值
                return localCacheStore[uid];

            } else if (nodeList === localB1) {
                // 命中 B1 幽灵队列

                // 自适应地增加参数 p，倾向于增加 T1 的容量
                this.p = (this.p < this.maxCapacity) ? (this.p + 1) : this.maxCapacity;

                // 根据 ARC 策略进行替换
                if (localT1.size > this.p || (localT1.size == this.p && localB2.size > 0)) {
                    // 从 T1 中移除尾部节点
                    var victimNode:Object = localT1.tail;
                    if (victimNode != null) {
                        var victimPrev:Object = victimNode.prev;
                        var victimNext:Object = victimNode.next;

                        if (victimPrev != null) {
                            victimPrev.next = victimNext;
                        } else {
                            localT1.head = victimNext;
                        }

                        if (victimNext != null) {
                            victimNext.prev = victimPrev;
                        } else {
                            localT1.tail = victimPrev;
                        }

                        localT1.size--;

                        // 从缓存存储中移除
                        delete localCacheStore[victimNode.uid];

                        // 将受害者节点添加到 B1 幽灵队列的头部
                        victimNode.list = localB1;
                        victimNode.prev = null;
                        victimNode.next = localB1.head;
                        if (localB1.head != null) {
                            localB1.head.prev = victimNode;
                        } else {
                            localB1.tail = victimNode;
                        }
                        localB1.head = victimNode;
                        localB1.size++;
                    }
                } else {
                    // 从 T2 中移除尾部节点
                    var victimNode2:Object = localT2.tail;
                    if (victimNode2 != null) {
                        var victim2Prev:Object = victimNode2.prev;
                        var victim2Next:Object = victimNode2.next;

                        if (victim2Prev != null) {
                            victim2Prev.next = victim2Next;
                        } else {
                            localT2.head = victim2Next;
                        }

                        if (victim2Next != null) {
                            victim2Next.prev = victim2Prev;
                        } else {
                            localT2.tail = victim2Prev;
                        }

                        localT2.size--;

                        // 从缓存存储中移除
                        delete localCacheStore[victimNode2.uid];

                        // 将受害者节点添加到 B2 幽灵队列的头部
                        victimNode2.list = localB2;
                        victimNode2.prev = null;
                        victimNode2.next = localB2.head;
                        if (localB2.head != null) {
                            localB2.head.prev = victimNode2;
                        } else {
                            localB2.tail = victimNode2;
                        }
                        localB2.head = victimNode2;
                        localB2.size++;
                    }
                }

                // 将命中的节点从 B1 移动到 T2 的头部
                var b1Prev:Object = node.prev;
                var b1Next:Object = node.next;

                if (b1Prev != null) {
                    b1Prev.next = b1Next;
                } else {
                    localB1.head = b1Next;
                }

                if (b1Next != null) {
                    b1Next.prev = b1Prev;
                } else {
                    localB1.tail = b1Prev;
                }

                localB1.size--;

                node.prev = null;
                node.next = localT2.head;
                if (localT2.head != null) {
                    localT2.head.prev = node;
                } else {
                    localT2.tail = node;
                }
                localT2.head = node;
                localT2.size++;

                node.list = localT2;

                // 返回 null，因为幽灵队列中不存储实际的值
                return null;

            } else if (nodeList === localB2) {
                // 命中 B2 幽灵队列

                // 自适应地减少参数 p，倾向于增加 T2 的容量
                this.p = (this.p > 0) ? (this.p - 1) : 0;

                // 根据 ARC 策略进行替换
                if (localT1.size > this.p || (localT1.size == this.p && localB2.size > 0)) {
                    // 从 T1 中移除尾部节点
                    victimNode = localT1.tail;
                    if (victimNode != null) {
                        victimPrev = victimNode.prev;
                        victimNext = victimNode.next;

                        if (victimPrev != null) {
                            victimPrev.next = victimNext;
                        } else {
                            localT1.head = victimNext;
                        }

                        if (victimNext != null) {
                            victimNext.prev = victimPrev;
                        } else {
                            localT1.tail = victimPrev;
                        }

                        localT1.size--;

                        // 从缓存存储中移除
                        delete localCacheStore[victimNode.uid];

                        // 将受害者节点添加到 B1 幽灵队列的头部
                        victimNode.list = localB1;
                        victimNode.prev = null;
                        victimNode.next = localB1.head;
                        if (localB1.head != null) {
                            localB1.head.prev = victimNode;
                        } else {
                            localB1.tail = victimNode;
                        }
                        localB1.head = victimNode;
                        localB1.size++;
                    }
                } else {
                    // 从 T2 中移除尾部节点
                    victimNode2 = localT2.tail;
                    if (victimNode2 != null) {
                        victim2Prev = victimNode2.prev;
                        victim2Next = victimNode2.next;

                        if (victim2Prev != null) {
                            victim2Prev.next = victim2Next;
                        } else {
                            localT2.head = victim2Next;
                        }

                        if (victim2Next != null) {
                            victim2Next.prev = victim2Prev;
                        } else {
                            localT2.tail = victim2Prev;
                        }

                        localT2.size--;

                        // 从缓存存储中移除
                        delete localCacheStore[victimNode2.uid];

                        // 将受害者节点添加到 B2 幽灵队列的头部
                        victimNode2.list = localB2;
                        victimNode2.prev = null;
                        victimNode2.next = localB2.head;
                        if (localB2.head != null) {
                            localB2.head.prev = victimNode2;
                        } else {
                            localB2.tail = victimNode2;
                        }
                        localB2.head = victimNode2;
                        localB2.size++;
                    }
                }

                // 将命中的节点从 B2 移动到 T2 的头部
                var b2Prev:Object = node.prev;
                var b2Next:Object = node.next;

                if (b2Prev != null) {
                    b2Prev.next = b2Next;
                } else {
                    localB2.head = b2Next;
                }

                if (b2Next != null) {
                    b2Next.prev = b2Prev;
                } else {
                    localB2.tail = b2Prev;
                }

                localB2.size--;

                node.prev = null;
                node.next = localT2.head;
                if (localT2.head != null) {
                    localT2.head.prev = node;
                } else {
                    localT2.tail = node;
                }
                localT2.head = node;
                localT2.size++;

                node.list = localT2;

                // 返回 null，因为幽灵队列中不存储实际的值
                return null;
            } else {
                // 不在任何已知的队列中，缓存未命中
                return null;
            }
        } else {
            // 节点不存在，缓存未命中
            return null;
        }
    }

    /**
     * 将一个项目插入到缓存中。
     * @param key 要缓存的项目的键（对象或原始类型）。
     * @param value 与键关联的值。
     */
    public function put(key:Object, value:Object):Void {
        var uid:String;
        // 根据键的类型生成唯一标识符 UID
        if (typeof key == "object" || typeof key == "function") {
            uid = "_" + Dictionary.getStaticUID(key); // 对象类型，使用静态 UID
        } else {
            uid = "_" + key; // 原始类型，直接转换为字符串
        }

        var node:Object = this.nodeMap[uid];
        var inT1:Boolean = (node != null) && (node.list === this.T1);
        var inT2:Boolean = (node != null) && (node.list === this.T2);

        if (inT1 || inT2) {
            // 如果项目已存在于缓存中，更新其值

            this.cacheStore[uid] = value;

            // 通过调用 get 方法提升其优先级
            this.get(key);
        } else {
            // 项目不在缓存中，需要插入

            // 局部化引用，减少解引用开销
            var localT1:Object = this.T1;
            var localT2:Object = this.T2;
            var localB1:Object = this.B1;
            var localB2:Object = this.B2;
            var localCacheStore:Object = this.cacheStore;
            var localNodeMap:Object = this.nodeMap;

            var totalSize:Number = localT1.size + localT2.size;

            if (totalSize >= this.maxCapacity) {
                // 缓存已满，需要替换

                var inB2:Boolean = (node != null) && (node.list === localB2);

                if (localT1.size > this.p || (inB2 && localT1.size == this.p)) {
                    // 从 T1 中移除尾部节点
                    var victimNode:Object = localT1.tail;
                    if (victimNode != null) {
                        var victimPrev:Object = victimNode.prev;
                        var victimNext:Object = victimNode.next;

                        if (victimPrev != null) {
                            victimPrev.next = victimNext;
                        } else {
                            localT1.head = victimNext;
                        }

                        if (victimNext != null) {
                            victimNext.prev = victimPrev;
                        } else {
                            localT1.tail = victimPrev;
                        }

                        localT1.size--;

                        // 从缓存存储中移除
                        delete localCacheStore[victimNode.uid];

                        // 将受害者节点添加到 B1 幽灵队列的头部
                        victimNode.list = localB1;
                        victimNode.prev = null;
                        victimNode.next = localB1.head;
                        if (localB1.head != null) {
                            localB1.head.prev = victimNode;
                        } else {
                            localB1.tail = victimNode;
                        }
                        localB1.head = victimNode;
                        localB1.size++;
                    }
                } else {
                    // 从 T2 中移除尾部节点
                    var victimNode2:Object = localT2.tail;
                    if (victimNode2 != null) {
                        var victim2Prev:Object = victimNode2.prev;
                        var victim2Next:Object = victimNode2.next;

                        if (victim2Prev != null) {
                            victim2Prev.next = victim2Next;
                        } else {
                            localT2.head = victim2Next;
                        }

                        if (victim2Next != null) {
                            victim2Next.prev = victim2Prev;
                        } else {
                            localT2.tail = victim2Prev;
                        }

                        localT2.size--;

                        // 从缓存存储中移除
                        delete localCacheStore[victimNode2.uid];

                        // 将受害者节点添加到 B2 幽灵队列的头部
                        victimNode2.list = localB2;
                        victimNode2.prev = null;
                        victimNode2.next = localB2.head;
                        if (localB2.head != null) {
                            localB2.head.prev = victimNode2;
                        } else {
                            localB2.tail = victimNode2;
                        }
                        localB2.head = victimNode2;
                        localB2.size++;
                    }
                }

            } else if ((localT1.size + localT2.size + localB1.size + localB2.size) >= (2 * this.maxCapacity)) {
                // 确保幽灵队列的总大小不超过 2 倍的缓存容量

                while ((localB1.size + localB2.size) > (2 * this.maxCapacity)) {
                    if (localB2.size > this.maxCapacity) {
                        // 从 B2 中移除尾部节点
                        var removedNode:Object = localB2.tail;
                        if (removedNode != null) {
                            var b2Prev:Object = removedNode.prev;
                            var b2Next:Object = removedNode.next;

                            if (b2Prev != null) {
                                b2Prev.next = b2Next;
                            } else {
                                localB2.head = b2Next;
                            }

                            if (b2Next != null) {
                                b2Next.prev = b2Prev;
                            } else {
                                localB2.tail = b2Prev;
                            }

                            localB2.size--;

                            // 从节点映射中移除
                            delete localNodeMap[removedNode.uid];
                        }
                    } else if (localB1.size > this.maxCapacity) {
                        // 从 B1 中移除尾部节点
                        var removedNode2:Object = localB1.tail;
                        if (removedNode2 != null) {
                            var b1Prev:Object = removedNode2.prev;
                            var b1Next:Object = removedNode2.next;

                            if (b1Prev != null) {
                                b1Prev.next = b1Next;
                            } else {
                                localB1.head = b1Next;
                            }

                            if (b1Next != null) {
                                b1Next.prev = b1Prev;
                            } else {
                                localB1.tail = b1Prev;
                            }

                            localB1.size--;

                            // 从节点映射中移除
                            delete localNodeMap[removedNode2.uid];
                        }
                    } else {
                        break;
                    }
                }
            }

            // 创建一个新节点
            var newNode:Object = {
                uid: uid,
                prev: null,
                next: null,
                list: null
            };
            localNodeMap[uid] = newNode;

            // 将新节点添加到 T1 的头部
            newNode.prev = null;
            newNode.next = localT1.head;
            if (localT1.head != null) {
                localT1.head.prev = newNode;
            } else {
                localT1.tail = newNode;
            }
            localT1.head = newNode;
            localT1.size++;

            // 指定节点所属的列表为 T1
            newNode.list = localT1;

            // 在缓存存储中保存值
            localCacheStore[uid] = value;
        }
    }

    // **测试辅助方法（可选）**

    // 测试辅助方法保持不变，因为它们不是性能关键点
    // 并且不影响缓存操作的运行效率

    /**
     * 获取 T1 队列的当前状态（用于调试）。
     * @return 包含 T1 队列中所有 UID 的数组。
     */
    public function getT1():Array {
        return this._getListContents(this.T1);
    }

    /**
     * 获取 T2 队列的当前状态（用于调试）。
     * @return 包含 T2 队列中所有 UID 的数组。
     */
    public function getT2():Array {
        return this._getListContents(this.T2);
    }

    /**
     * 获取 B1 队列的当前状态（用于调试）。
     * @return 包含 B1 队列中所有 UID 的数组。
     */
    public function getB1():Array {
        return this._getListContents(this.B1);
    }

    /**
     * 获取 B2 队列的当前状态（用于调试）。
     * @return 包含 B2 队列中所有 UID 的数组。
     */
    public function getB2():Array {
        return this._getListContents(this.B2);
    }

    /**
     * 遍历链表并检索所有节点的 UID。
     * @param list 链表对象。
     * @return 包含链表中所有 UID 的数组。
     */
    private function _getListContents(list:Object):Array {
        var contents:Array = [];
        var currentNode:Object = list.head;
        while (currentNode != null) {
            contents.push(currentNode.uid);
            currentNode = currentNode.next;
        }
        return contents;
    }

    /**
     * 获取缓存存储的内容（用于调试）。
     * @return 表示缓存存储内容的字符串。
     */
    private function _getCacheContents():String {
        var contents:Array = [];
        for (var key:String in this.cacheStore) {
            contents.push(key + ": " + this.cacheStore[key]);
        }
        return "{" + contents.join(", ") + "}";
    }

    /**
     * 获取节点映射的内容（用于调试）。
     * @return 表示节点映射内容的字符串。
     */
    private function _getNodeMapContents():String {
        var contents:Array = [];
        for (var key:String in this.nodeMap) {
            contents.push(key + ": " + this.nodeMap[key].uid);
        }
        return "{" + contents.join(", ") + "}";
    }
}
