class org.flashNight.naki.DataStructures.SLNode {
    private var value:Object;
    private var next:SLNode = null;

    // 构造函数，初始化节点的值
    public function SLNode(value:Object) {
        this.value = value;
    }

    // 获取节点存储的值
    public function getValue():Object {
        return value;
    }

    // 设置节点存储的值
    public function setValue(value:Object):Void {
        this.value = value;
    }

    // 获取下一个节点的引用
    public function getNext():SLNode {
        return next;
    }

    // 设置下一个节点的引用
    public function setNext(next:SLNode):Void {
        this.next = next;
    }
}
