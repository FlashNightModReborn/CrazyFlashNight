/**
 * ARCCache Class
 * Implements the Adaptive Replacement Cache algorithm in AS2 using linked lists.
 */
import org.flashNight.naki.DataStructures.*;

class org.flashNight.naki.Cache.ARCCache {
    // Maximum capacity of the cache
    private var maxCapacity:Number;

    // Balancing parameter between T1 and T2
    private var p:Number;

    // Cache queues represented as linked lists
    private var T1:Object; // Recently used items (cold)
    private var T2:Object; // Frequently used items (hot)
    private var B1:Object; // Ghost entries evicted from T1
    private var B2:Object; // Ghost entries evicted from T2

    // Storage for cached items
    private var cacheStore:Object; // Maps UID to value

    // Node mapping for quick access
    private var nodeMap:Object; // Maps UID to node in the queue

    // Constructor
    /**
     * Initializes the ARCCache with a specified capacity.
     * @param capacity Maximum number of items the cache can hold.
     */
    public function ARCCache(capacity:Number) {
        this.maxCapacity = capacity;
        this.p = 0; // Initial balancing parameter

        // Initialize queues as linked lists
        this.T1 = this._createLinkedList();
        this.T2 = this._createLinkedList();
        this.B1 = this._createLinkedList();
        this.B2 = this._createLinkedList();

        // Initialize cache storage and node mapping
        this.cacheStore = {}; // Object to store cached values by UID
        this.nodeMap = {}; // Object to store nodes by UID
    }

    // Public Methods
    /**
     * Retrieves an item from the cache.
     * @param key The key (object or primitive) of the item to retrieve.
     * @return The cached value, or null if not found.
     */
    public function get(key:Object):Object {
        var uid:String = this._getUID(key);

        if (this._isInQueue(this.T1, uid)) {
            //trace("Cache Hit: T1 - " + key);
            return this._handleT1Hit(uid);
        } else if (this._isInQueue(this.T2, uid)) {
            //trace("Cache Hit: T2 - " + key);
            return this._handleT2Hit(uid);
        } else if (this._isInQueue(this.B1, uid)) {
            //trace("Cache Ghost Hit: B1 - " + key);
            this._handleB1Hit(uid);
            return null;
        } else if (this._isInQueue(this.B2, uid)) {
            //trace("Cache Ghost Hit: B2 - " + key);
            this._handleB2Hit(uid);
            return null;
        } else {
            // Cache miss
            //trace("Cache Miss: " + key);
            return null;
        }
    }

    /**
     * Inserts an item into the cache.
     * @param key The key (object or primitive) of the item to cache.
     * @param value The value to associate with the key.
     */
    public function put(key:Object, value:Object):Void {
        var uid:String = this._getUID(key);

        if (this._isInCache(uid)) {
            // Update existing item
            //trace("Updating existing key: " + key);
            this.cacheStore[uid] = value;
            // Promote item if necessary
            this.get(key);
        } else {
            // Insert new item
            //trace("Inserting new key: " + key);
            this._insertItem(uid, value);
        }
    }

    // Private Helper Methods

    /**
     * Generates or retrieves the UID for a key.
     * @param key The key to get UID for.
     * @return The UID associated with the key.
     */
    private function _getUID(key:Object):String {
        if (typeof key == "object" || typeof key == "function") {
            return "_" + Dictionary.getStaticUID(key); // Prefix to avoid conflicts
        } else {
            // For primitive types, use a unique string representation
            return "_" + key;
        }
    }

    /**
     * Checks if a UID is in any of the cache queues.
     * @param uid The UID to check.
     * @return True if the UID is in T1 or T2, false otherwise.
     */
    private function _isInCache(uid:String):Boolean {
        return this._isInQueue(this.T1, uid) || this._isInQueue(this.T2, uid);
    }

    /**
     * Checks if a UID is in a specific queue.
     * @param list The linked list to check.
     * @param uid The UID to look for.
     * @return True if the UID is in the list, false otherwise.
     */
    private function _isInQueue(list:Object, uid:String):Boolean {
        return this.nodeMap[uid] != null && this.nodeMap[uid].list === list;
    }

    /**
     * Handles a cache hit in T1.
     * @param uid The UID of the item.
     * @return The cached value.
     */
    private function _handleT1Hit(uid:String):Object {
        // Move item from T1 to T2
        var node:Object = this.nodeMap[uid];
        this._removeNode(this.T1, node);
        this._addNodeToFront(this.T2, node);
        node.list = this.T2;
        //trace("Moved UID " + uid + " from T1 to T2");
        return this.cacheStore[uid];
    }

    /**
     * Handles a cache hit in T2.
     * @param uid The UID of the item.
     * @return The cached value.
     */
    private function _handleT2Hit(uid:String):Object {
        // Move item to the front of T2
        var node:Object = this.nodeMap[uid];
        this._moveNodeToFront(this.T2, node);
        //trace("Promoted UID " + uid + " to front of T2");
        return this.cacheStore[uid];
    }

    /**
     * Handles a hit in the ghost queue B1.
     * @param uid The UID of the item.
     */
    private function _handleB1Hit(uid:String):Void {
        // Adaptively increase p
        var delta:Number = this.B2.size > 0 ? this.B2.size / this.B1.size : 1;
        this.p = Math.min(this.p + delta, this.maxCapacity);
        //trace("Handled B1 hit: Increased p to " + this.p);

        // Replace items
        this._replace(uid);

        // Move uid from B1 to T2
        var node:Object = this.nodeMap[uid];
        this._removeNode(this.B1, node);
        this._addNodeToFront(this.T2, node);
        node.list = this.T2;
        //trace("Moved UID " + uid + " from B1 to T2");
    }

    /**
     * Handles a hit in the ghost queue B2.
     * @param uid The UID of the item.
     */
    private function _handleB2Hit(uid:String):Void {
        // Adaptively decrease p
        var delta:Number = this.B1.size > 0 ? this.B1.size / this.B2.size : 1;
        this.p = Math.max(this.p - delta, 0);
        //trace("Handled B2 hit: Decreased p to " + this.p);

        // Replace items
        this._replace(uid);

        // Move uid from B2 to T2
        var node:Object = this.nodeMap[uid];
        this._removeNode(this.B2, node);
        this._addNodeToFront(this.T2, node);
        node.list = this.T2;
        //trace("Moved UID " + uid + " from B2 to T2");
    }

    /**
     * Inserts a new item into the cache.
     * @param uid The UID of the item.
     * @param value The value to cache.
     */
    private function _insertItem(uid:String, value:Object):Void {
        // Check if cache is full
        var totalSize:Number = this.T1.size + this.T2.size;
        if (totalSize >= this.maxCapacity) {
            //trace("Cache is full. Replacing an item...");
            this._replace(uid);
        }

        // Add item to T1
        var node:Object = this._createNode(uid);
        this._addNodeToFront(this.T1, node);
        node.list = this.T1;
        this.cacheStore[uid] = value;
        //trace("Added UID " + uid + " to T1");
    }

    /**
     * Replaces items in the cache based on ARC policy.
     * @param uid The UID of the item causing the replacement.
     */
    private function _replace(uid:String):Void {
        var t1Size:Number = this.T1.size;
        var b2ContainsUid:Boolean = this._isInQueue(this.B2, uid);

        if (t1Size > 0 && (t1Size > this.p || (b2ContainsUid && t1Size == this.p))) {
            // Evict from T1
            var victimNode:Object = this._removeLastNode(this.T1);
            delete this.cacheStore[victimNode.uid];
            victimNode.list = this.B1;
            this._addNodeToFront(this.B1, victimNode);
            //trace("Evicted UID " + victimNode.uid + " from T1 to B1");
        } else {
            // Evict from T2
            var victimNode:Object = this._removeLastNode(this.T2);
            delete this.cacheStore[victimNode.uid];
            victimNode.list = this.B2;
            this._addNodeToFront(this.B2, victimNode);
            //trace("Evicted UID " + victimNode.uid + " from T2 to B2");
        }

        // Ensure ghost queues do not exceed cache capacity
        this._trimGhostQueues();
    }

    /**
     * Ensures the ghost queues (B1 and B2) do not exceed the cache capacity.
     */
    private function _trimGhostQueues():Void {
        while (this.B1.size > this.maxCapacity) {
            var removedNode:Object = this._removeLastNode(this.B1);
            delete this.nodeMap[removedNode.uid];
            //trace("Trimmed B1: Removed UID " + removedNode.uid);
        }
        while (this.B2.size > this.maxCapacity) {
            var removedNode:Object = this._removeLastNode(this.B2);
            delete this.nodeMap[removedNode.uid];
            //trace("Trimmed B2: Removed UID " + removedNode.uid);
        }
    }

    // Linked List Operations

    /**
     * Creates a new linked list.
     * @return A new linked list object.
     */
    private function _createLinkedList():Object {
        var list:Object = {
            head: null,
            tail: null,
            size: 0
        };
        return list;
    }

    /**
     * Creates a new node for the linked list.
     * @param uid The UID of the item.
     * @return A new node object.
     */
    private function _createNode(uid:String):Object {
        var node:Object = {
            uid: uid,
            prev: null,
            next: null,
            list: null
        };
        this.nodeMap[uid] = node;
        return node;
    }

    /**
     * Adds a node to the front of the linked list.
     * @param list The linked list to add to.
     * @param node The node to add.
     */
    private function _addNodeToFront(list:Object, node:Object):Void {
        node.prev = null;
        node.next = list.head;
        if (list.head != null) {
            list.head.prev = node;
        } else {
            list.tail = node;
        }
        list.head = node;
        list.size++;
    }

    /**
     * Removes a node from its linked list.
     * @param list The linked list to remove from.
     * @param node The node to remove.
     */
    private function _removeNode(list:Object, node:Object):Void {
        if (node.prev != null) {
            node.prev.next = node.next;
        } else {
            list.head = node.next;
        }
        if (node.next != null) {
            node.next.prev = node.prev;
        } else {
            list.tail = node.prev;
        }
        node.prev = null;
        node.next = null;
        list.size--;
    }

    /**
     * Moves a node to the front of its linked list.
     * @param list The linked list to operate on.
     * @param node The node to move.
     */
    private function _moveNodeToFront(list:Object, node:Object):Void {
        this._removeNode(list, node);
        this._addNodeToFront(list, node);
    }

    /**
     * Removes and returns the last node from a linked list.
     * @param list The linked list to remove from.
     * @return The node that was removed.
     */
    private function _removeLastNode(list:Object):Object {
        var node:Object = list.tail;
        if (node != null) {
            this._removeNode(list, node);
        }
        return node;
    }

    // **Testing Helper Methods (Optional)**
        /**
     * 获取 T1 队列的当前状态（调试用）。
     * @return 一个数组，包含 T1 队列中的所有 UID。
     */
    public function getT1():Array {
        return this._getListContents(this.T1);
    }

    /**
     * 获取 T2 队列的当前状态（调试用）。
     * @return 一个数组，包含 T2 队列中的所有 UID。
     */
    public function getT2():Array {
        return this._getListContents(this.T2);
    }

    /**
     * 获取 B1 队列的当前状态（调试用）。
     * @return 一个数组，包含 B1 队列中的所有 UID。
     */
    public function getB1():Array {
        return this._getListContents(this.B1);
    }

    /**
     * 获取 B2 队列的当前状态（调试用）。
     * @return 一个数组，包含 B2 队列中的所有 UID。
     */
    public function getB2():Array {
        return this._getListContents(this.B2);
    }

    /**
     * 遍历链表并获取所有节点的 UID。
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

}
