import org.flashNight.naki.DataStructures.SLNode;

class org.flashNight.naki.DataStructures.LinkedStack {
    
    // 栈顶指针
    private var top:SLNode;
    
    // 栈中元素的数量
    private var count:Number;
    
    /**
     * 构造函数，初始化链表栈
     */
    public function LinkedStack() {
        this.top = null;
        this.count = 0;
    }
    
    /**
     * 入栈操作，将元素压入栈顶
     * @param value 要压入栈的元素
     */
    public function push(value:Object):Void {
        var newNode:SLNode = new SLNode(value);
        newNode.setNext(this.top); // 新节点指向当前的栈顶
        this.top = newNode; // 更新栈顶指针
        this.count++;
    }
    
    /**
     * 出栈操作，移除并返回栈顶元素
     * @return 栈顶元素，如果栈为空则返回 null
     */
    public function pop():Object {
        if (this.isEmpty()) {
            return null; // 栈为空
        }
        var value:Object = this.top.getValue();
        this.top = this.top.getNext(); // 更新栈顶指针
        this.count--;
        return value;
    }
    
    /**
     * 查看栈顶的元素但不移除
     * @return 栈顶的元素，如果栈为空则返回 null
     */
    public function peek():Object {
        if (this.isEmpty()) {
            return null; // 栈为空
        }
        return this.top.getValue(); // 返回栈顶元素
    }
    
    /**
     * 检查栈是否为空
     * @return 如果栈为空，返回 true；否则返回 false
     */
    public function isEmpty():Boolean {
        return this.count == 0;
    }
    
    /**
     * 获取栈的大小
     * @return 栈中的元素数量
     */
    public function getSize():Number {
        return this.count;
    }
    
    /**
     * 清空栈
     */
    public function clear():Void {
        this.top = null;
        this.count = 0;
    }
}
