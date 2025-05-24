import org.flashNight.naki.DataStructures.*;
class org.flashNight.naki.DataStructures.PriorityQueue {
    private var nodes:Array;

    public function PriorityQueue() {
        nodes = [];
    }

    // 插入一个 HuffmanNode，按照频率排序
    public function enqueue(node:HuffmanNode):Void {
        nodes.push(node);
        nodes.sort(compareNodes);
    }

    // 移除频率最低的节点
    public function dequeue():HuffmanNode {
        return HuffmanNode(nodes.shift());
    }

    // 获取队列大小
    public function size():Number {
        return nodes.length;
    }

    // 比较节点的频率（用于排序）
    private function compareNodes(a:HuffmanNode, b:HuffmanNode):Number {
        return a.frequency - b.frequency;
    }
}
