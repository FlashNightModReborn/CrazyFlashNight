class org.flashNight.naki.DataStructures.HuffmanNode {
    public var value:Object;    // 存储的字符或子树
    public var frequency:Number; // 出现频率
    public var left:HuffmanNode; // 左子节点
    public var right:HuffmanNode; // 右子节点

    // 构造函数
    public function HuffmanNode(value:Object, frequency:Number) {
        this.value = value;
        this.frequency = frequency;
        this.left = null;
        this.right = null;
    }
    
    // 判断是否为叶子节点
    public function isLeaf():Boolean {
        return left == null && right == null;
    }
}
