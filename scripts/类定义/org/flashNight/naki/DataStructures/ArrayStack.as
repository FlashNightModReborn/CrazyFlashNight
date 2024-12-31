class org.flashNight.naki.DataStructures.ArrayStack {
    private var items:Array; // 用于存储栈元素的数组
    private var top:Number;  // 栈顶索引，初始值为-1表示栈为空

    /**
     * 构造函数，初始化栈
     * @param capacity 栈的预期大小（可选）
     */
    public function ArrayStack(capacity:Number) {
        this.items = capacity ? new Array(capacity) : [];
        this.top = -1;
    }

    /**
     * 将元素压入栈中
     * @param value 要压入栈的元素
     */
    public function push(value:Object):Void {
        this.items[++this.top] = value; // 先将top自增1，然后将value存入items[top]
    }

    /**
     * 从栈中弹出顶部元素
     * @return 栈顶元素，如果栈为空则返回null
     */
    public function pop():Object {
        if (this.top == -1) return null; // 栈为空，返回null
        return this.items[this.top--]; // 返回items[top]，然后将top自减1
    }

    /**
     * 查看栈顶元素但不移除
     * @return 栈顶元素，如果栈为空则返回null
     */
    public function peek():Object {
        if (this.top == -1) return null; // 栈为空，返回null
        return this.items[this.top]; // 返回栈顶元素
    }

    /**
     * 检查栈是否为空
     * @return 如果栈为空，返回true；否则返回false
     */
    public function isEmpty():Boolean {
        return this.top == -1; // top为-1表示栈为空
    }

    /**
     * 获取栈的大小
     * @return 栈中的元素数量
     */
    public function getSize():Number {
        return this.top + 1; // 栈的大小为top加1
    }

    /**
     * 清空栈
     */
    public function clear():Void {
        this.top = -1;       // 重置栈顶索引为-1
        this.items.length = 0; // 清空存储元素的数组
    }

    /**
     * 调整栈的大小
     * @param newSize 新的大小
     */
    public function resize(newSize:Number):Void {
        if (newSize < 0) return; // 无效大小，不进行操作
        if (newSize < this.top + 1) {
            // 截断数组并调整top
            this.items.length = newSize;
            this.top = newSize - 1;
        }
    }
}