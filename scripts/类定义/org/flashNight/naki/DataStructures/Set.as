class org.flashNight.naki.DataStructures.Set {
    
    // 用于存储集合元素的对象
    private var items:Object;
    
    /**
     * 构造函数，初始化 Set
     */
    public function Set() {
        this.items = {};
    }
    
    /**
     * 添加元素到集合中
     * @param value 要添加的元素
     * @return 如果元素成功添加（不存在重复），返回 true；否则返回 false
     */
    public function add(value:Object):Boolean {
        if (!this.has(value)) {
            this.items[value] = true;
            return true;
        }
        return false;
    }
    
    /**
     * 从集合中移除元素
     * @param value 要移除的元素
     * @return 如果元素成功移除，返回 true；否则返回 false
     */
    public function remove(value:Object):Boolean {
        if (this.has(value)) {
            delete this.items[value];
            return true;
        }
        return false;
    }
    
    /**
     * 检查元素是否存在于集合中
     * @param value 要检查的元素
     * @return 如果元素存在，返回 true；否则返回 false
     */
    public function has(value:Object):Boolean {
        var key:String = String(value); // 将 value 强制转换为字符串
        return this.items.hasOwnProperty(key);
    }

    /**
     * 获取集合中所有的元素
     * @return 包含所有元素的数组
     */
    public function values():Array {
        var result:Array = [];
        for (var key:String in this.items) {
            result.push(key);
        }
        return result;
    }
    
    /**
     * 清空集合
     */
    public function clear():Void {
        this.items = {};
    }
    
    /**
     * 获取集合的大小
     * @return 集合中的元素数量
     */
    public function size():Number {
        var count:Number = 0;
        for (var key:String in this.items) {
            count++;
        }
        return count;
    }
    
    /**
     * 检查集合是否为空
     * @return 如果集合为空，返回 true；否则返回 false
     */
    public function isEmpty():Boolean {
        return this.size() == 0;
    }
    
    /**
     * 集合的并集操作
     * @param otherSet 另一个 Set 实例
     * @return 一个新的 Set，包含当前集合和另一个集合的并集
     */
    public function union(otherSet:Set):Set {
        var unionSet:Set = new Set();
        var values:Array = this.values();
        
        // 添加当前集合的所有元素
        for (var i:Number = 0; i < values.length; i++) {
            unionSet.add(values[i]);
        }
        
        // 添加另一个集合的元素
        values = otherSet.values();
        for (var i:Number = 0; i < values.length; i++) {
            unionSet.add(values[i]);
        }
        
        return unionSet;
    }
    
    /**
     * 集合的交集操作
     * @param otherSet 另一个 Set 实例
     * @return 一个新的 Set，包含当前集合和另一个集合的交集
     */
    public function intersection(otherSet:Set):Set {
        var intersectionSet:Set = new Set();
        var values:Array = this.values();
        
        // 只有当元素在另一个集合中也存在时才添加到交集
        for (var i:Number = 0; i < values.length; i++) {
            if (otherSet.has(values[i])) {
                intersectionSet.add(values[i]);
            }
        }
        
        return intersectionSet;
    }
    
    /**
     * 集合的差集操作
     * @param otherSet 另一个 Set 实例
     * @return 一个新的 Set，包含当前集合中有但另一个集合中没有的元素
     */
    public function difference(otherSet:Set):Set {
        var differenceSet:Set = new Set();
        var values:Array = this.values();
        
        // 只添加当前集合中不在另一个集合中的元素
        for (var i:Number = 0; i < values.length; i++) {
            if (!otherSet.has(values[i])) {
                differenceSet.add(values[i]);
            }
        }
        
        return differenceSet;
    }
    
    /**
     * 检查集合是否是另一个集合的子集
     * @param otherSet 另一个 Set 实例
     * @return 如果当前集合是另一个集合的子集，返回 true；否则返回 false
     */
    public function isSubsetOf(otherSet:Set):Boolean {
        var values:Array = this.values();
        
        // 只要当前集合中有一个元素不在另一个集合中，返回 false
        for (var i:Number = 0; i < values.length; i++) {
            if (!otherSet.has(values[i])) {
                return false;
            }
        }
        
        return true;
    }
}
