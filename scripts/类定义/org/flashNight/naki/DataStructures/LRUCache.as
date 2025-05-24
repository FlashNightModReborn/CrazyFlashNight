import org.flashNight.naki.DataStructures.LLNode;
import org.flashNight.naki.DataStructures.DoublyLinkedList;

class org.flashNight.naki.DataStructures.LRUCache {
    private var capacity:Number;              // 缓存的容量
    private var cache:Object;                 // 键到节点的映射
    private var list:DoublyLinkedList;        // 用于维护元素顺序的双向链表

    /**
     * 构造函数，初始化 LRU 缓存
     * @param capacity 缓存的最大容量
     */
    public function LRUCache(capacity:Number) {
        this.capacity = capacity;
        this.cache = {};
        this.list = new DoublyLinkedList();
    }

    /**
     * 获取缓存中的值
     * @param key 要获取的键
     * @return 如果键存在，返回对应的值；否则返回 null
     */
    public function get(key:String):Object {
        if (this.cache.hasOwnProperty(key)) {
            var node:LLNode = this.cache[key];
            // 将节点移动到链表头部，表示最近使用
            this.list.remove(node);
            this.list.addFirst({key: key, value: node.getValue().value});
            // 更新哈希表中的节点引用
            this.cache[key] = this.list.getFirst();
            return this.cache[key].getValue().value;
        } else {
            return null; // 未找到
        }
    }

    /**
     * 添加或更新缓存中的值
     * @param key 要添加或更新的键
     * @param value 要存储的值
     */
    public function put(key:String, value:Object):Void {
        if (this.cache.hasOwnProperty(key)) {
            // 更新已有节点的值，并移动到头部
            var existingNode:LLNode = this.cache[key];
            this.list.remove(existingNode);
        } else {
            // 检查缓存是否已满
            if (this.list.getSize() >= this.capacity) {
                // 移除链表尾部节点（最近最少使用的节点）
                var tailNode:LLNode = this.list.getLast();
                if (tailNode != null) {
                    var tailKey:String = tailNode.getValue().key;
                    this.list.removeLast();
                    delete this.cache[tailKey];
                }
            }
        }
        // 添加新节点到链表头部
        var newNode:Object = {key: key, value: value};
        this.list.addFirst(newNode);
        this.cache[key] = this.list.getFirst();
    }

    /**
     * 删除缓存中的指定键
     * @param key 要删除的键
     */
    public function remove(key:String):Void {
        if (this.cache.hasOwnProperty(key)) {
            var node:LLNode = this.cache[key];
            this.list.remove(node);
            delete this.cache[key];
        }
    }

    /**
     * 清空缓存
     */
    public function clear():Void {
        this.cache = {};
        this.list.clear();
    }

    /**
     * 获取缓存当前的大小
     * @return 当前缓存中的元素数量
     */
    public function size():Number {
        return this.list.getSize();
    }

    /**
     * 返回缓存的字符串表示
     * @return 缓存内容的字符串表示
     */
    public function toString():String {
        var elements:Array = [];
        this.list.traverseForward(function(node:LLNode):Void {
            elements.push(node.getValue().key + ":" + node.getValue().value);
        });
        return elements.join(", ");
    }
}
