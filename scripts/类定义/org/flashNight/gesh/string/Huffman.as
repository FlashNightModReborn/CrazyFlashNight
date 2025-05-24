import org.flashNight.naki.DataStructures.*;
class org.flashNight.gesh.string.Huffman {
    /**
     * 根据输入字符串构建 Huffman 树
     * @param input 输入的字符串
     * @return Huffman 树的根节点
     */
    public static function buildHuffmanTree(input:String):HuffmanNode {
        // trace("构建 Huffman 树...");
        // 1. 计算字符的频率
        var frequencyMap:Object = {};
        for (var i:Number = 0; i < input.length; i++) {
            var char:String = input.charAt(i);
            if (frequencyMap[char] == undefined) {
                frequencyMap[char] = 0;
            }
            frequencyMap[char]++;
        }

        // 输出频率表
        // trace("字符频率表:");
        for (var charKey:String in frequencyMap) {
            // trace("字符: '" + charKey + "', 频率: " + frequencyMap[charKey]);
        }

        // 2. 将所有字符和其频率加入到优先队列中
        var priorityQueue:PriorityQueue = new PriorityQueue();
        for (var c:String in frequencyMap) {
            var node:HuffmanNode = new HuffmanNode(c, frequencyMap[c]);
            priorityQueue.enqueue(node);
            // trace("插入优先队列: '" + c + "' (频率: " + frequencyMap[c] + ")");
        }

        // 3. 合并节点，构建 Huffman 树
        while (priorityQueue.size() > 1) {
            var node1:HuffmanNode = priorityQueue.dequeue();
            // trace("取出最小频率节点: '" + node1.value + "' (频率: " + node1.frequency + ")");
            var node2:HuffmanNode = priorityQueue.dequeue();
            // trace("取出下一个最小频率节点: '" + node2.value + "' (频率: " + node2.frequency + ")");

            // 创建一个新的父节点，频率为两个子节点的频率之和
            var mergedNode:HuffmanNode = new HuffmanNode(null, node1.frequency + node2.frequency);
            mergedNode.left = node1;
            mergedNode.right = node2;
            // trace("合并节点: 新节点 (频率: " + mergedNode.frequency + ")");

            // 将新的父节点加入队列
            priorityQueue.enqueue(mergedNode);
            // trace("插入合并后的父节点到优先队列 (频率: " + mergedNode.frequency + ")");
        }

        // 剩下的节点就是 Huffman 树的根节点
        var root:HuffmanNode = priorityQueue.dequeue();
        if (root != null) {
            // trace("Huffman 树构建完成。根节点频率: " + root.frequency);
        } else {
            // trace("Huffman 树构建失败，根节点为 null");
        }
        return root;
    }

    /**
     * 生成 Huffman 编码表
     * @param root Huffman 树的根节点
     * @return 编码表，键为字符，值为其二进制编码
     */
    public static function generateCodes(root:HuffmanNode):Object {
        // trace("生成编码表...");
        var codes:Object = {};
        traverseTree(root, "", codes);
        // trace("编码表生成完成:");
        for (var char:String in codes) {
            // trace("字符: '" + char + "', 编码: " + codes[char]);
        }
        return codes;
    }

    /**
     * 遍历 Huffman 树，生成编码
     * @param node 当前节点
     * @param code 当前路径的编码
     * @param codes 编码表
     */
    private static function traverseTree(node:HuffmanNode, code:String, codes:Object):Void {
        if (node.isLeaf()) {
            codes[node.value] = code.length > 0 ? code : "0"; // 处理只有一个唯一字符的情况
            // trace("叶子节点: '" + node.value + "', 编码: " + codes[node.value]);
        } else {
            traverseTree(node.left, code + "0", codes);
            traverseTree(node.right, code + "1", codes);
        }
    }

    /**
     * 将输入字符串编码为 Huffman 二进制编码
     * @param input 输入的字符串
     * @return 编码后的二进制字符串
     */
    public static function encode(input:String):String {
        // trace("开始编码...");
        if (input == null || input.length == 0) {
            // trace("输入为空，返回空字符串");
            return "";
        }

        var root:HuffmanNode = buildHuffmanTree(input);
        var codes:Object = generateCodes(root);
        var encodedStr:String = "";

        for (var i:Number = 0; i < input.length; i++) {
            var char:String = input.charAt(i);
            if (codes[char] == undefined) {
                // trace("错误: 字符 '" + char + "' 没有编码");
                return undefined;
            }
            encodedStr += codes[char];
            // trace("编码字符: '" + char + "' -> " + codes[char]);
        }

        // trace("编码完成。编码长度: " + encodedStr.length);
        return encodedStr;
    }

    /**
     * 解码 Huffman 二进制字符串
     * @param encodedStr 编码后的二进制字符串
     * @param root Huffman 树的根节点
     * @return 解码后的原始字符串
     */
    public static function decode(encodedStr:String, root:HuffmanNode):String {
        // trace("开始解码...");
        if (encodedStr == null || encodedStr.length == 0) {
            // trace("编码字符串为空，返回空字符串");
            return "";
        }

        if (root == null) {
            // trace("Huffman 树根节点为空，无法解码");
            return undefined;
        }

        var decodedStr:String = "";
        var currentNode:HuffmanNode = root;

        for (var i:Number = 0; i < encodedStr.length; i++) {
            var bit:String = encodedStr.charAt(i);
            if (bit == "0") {
                currentNode = currentNode.left;
            } else if (bit == "1") {
                currentNode = currentNode.right;
            } else {
                // trace("错误: 无效的比特 '" + bit + "'");
                return undefined;
            }

            if (currentNode == null) {
                // trace("错误: 到达空节点，无法解码");
                return undefined;
            }

            if (currentNode.isLeaf()) {
                decodedStr += String(currentNode.value); // 修正此处为 currentNode.value
                // trace("解码字符: '" + currentNode.value + "'");
                currentNode = root;
            }
        }

        // trace("解码完成。解码字符串: " + decodedStr);
        return decodedStr;
    }
}


/*

import org.flashNight.naki.DataStructures.*;
import org.flashNight.gesh.string.*;
// 测试 Huffman 编码和解码

trace("===== 开始测试 Huffman 编码和解码 =====");

var testStr:String = "hello huffman";
trace("测试字符串: " + testStr);

// 编码
var encoded:String = Huffman.encode(testStr);
trace("编码后的二进制字符串: " + encoded);

// 检查是否编码成功
if (encoded == undefined) {
    trace("编码过程中发生错误。");
} else {
    // 构建 Huffman 树，用于解码
    var root:HuffmanNode = Huffman.buildHuffmanTree(testStr);
    if (root != null) {
        trace("成功构建 Huffman 树，用于解码");
    } else {
        trace("构建 Huffman 树失败");
    }

    // 解码
    var decoded:String = Huffman.decode(encoded, root);
    trace("解码后的字符串: " + decoded);

    // 验证结果
    var isEqual:Boolean = (testStr == decoded);
    trace("编码后解码是否匹配: " + isEqual);
}

trace("===== 测试完成 =====");

*/