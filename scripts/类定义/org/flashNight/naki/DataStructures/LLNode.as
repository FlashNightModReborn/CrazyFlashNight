class org.flashNight.naki.DataStructures.LLNode {
    private var value:Object;
    private var prev:LLNode = null;
    private var next:LLNode = null;

    // 构造函数
    public function LLNode(value:Object) {
        this.value = value;
    }

    // 获取节点存储的值
    public function getValue():Object {
        return value;
    }

    public function getString():String
    {
        return ""; // TODO: 实现 toString 方法
    }

    // 设置节点存储的值
    public function setValue(value:Object):Void {
        this.value = value;
    }

    // 获取前一个节点
    public function getPrev():LLNode {
        return prev;
    }

    // 设置前一个节点
    public function setPrev(prev:LLNode):Void {
        this.prev = prev;
    }

    // 获取下一个节点
    public function getNext():LLNode {
        return next;
    }

    // 设置下一个节点
    public function setNext(next:LLNode):Void {
        this.next = next;
    }
}
