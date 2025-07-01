/**
 * BitArray - 高性能位数组实现
 * 适用于 ActionScript 2.0
 * 
 */
class org.flashNight.naki.DataStructures.BitArray {
    
    // 常量定义
    private static var BITS_PER_CHUNK:Number = 32;
    private static var CHUNK_MASK:Number = 0x1F; // 31, 用于获取块内位置 (index & 31)
    private static var CHUNK_SHIFT:Number = 5;   // 用于快速除法 (index >> 5)
    
    // 私有成员变量
    private var chunks:Array;        // Number数组，存储位数据
    private var totalBits:Number;    // 总位数
    private var chunkCount:Number;   // 块数量
    
    /**
     * 构造函数
     * @param size 初始位数，如果不指定则为0
     */
    public function BitArray(size:Number) {
        if (size == undefined || size < 0) {
            size = 0;
        }
        
        this.totalBits = size;
        this.chunkCount = Math.ceil(size / BITS_PER_CHUNK);
        this.chunks = new Array(this.chunkCount);
        
        // 初始化所有块为0
        for (var i:Number = 0; i < this.chunkCount; i++) {
            this.chunks[i] = 0;
        }
    }
    
    /**
     * 获取指定位置的位值
     * @param index 位索引 (0-based)
     * @return 位值 (0 或 1)，超出范围返回0
     */
    public function getBit(index:Number):Number {
        if (!this.isValidIndex(index)) {
            return 0;
        }
        
        var chunkIndex:Number = index >> CHUNK_SHIFT;     // 等价于 Math.floor(index / 32)
        var bitPosition:Number = index & CHUNK_MASK;      // 等价于 index % 32
        
        return (this.chunks[chunkIndex] >> bitPosition) & 1;
    }
    
    /**
     * 设置指定位置的位值
     * @param index 位索引
     * @param value 位值 (0 或 1，其他值会被转换为0或1)
     */
    public function setBit(index:Number, value:Number):Void {
        if (!this.isValidIndex(index)) {
            this.expandToInclude(index);
        }
        
        var chunkIndex:Number = index >> CHUNK_SHIFT;
        var bitPosition:Number = index & CHUNK_MASK;
        
        if (value) {
            // 设置位为1：使用OR操作
            this.chunks[chunkIndex] |= (1 << bitPosition);
        } else {
            // 设置位为0：使用AND操作配合取反
            this.chunks[chunkIndex] &= ~(1 << bitPosition);
        }
    }
    
    /**
     * 翻转指定位置的位值
     * @param index 位索引
     */
    public function flipBit(index:Number):Void {
        if (!this.isValidIndex(index)) {
            this.expandToInclude(index);
        }
        
        var chunkIndex:Number = index >> CHUNK_SHIFT;
        var bitPosition:Number = index & CHUNK_MASK;
        
        // 使用XOR操作翻转位
        this.chunks[chunkIndex] ^= (1 << bitPosition);
    }
    
    /**
     * 清空所有位（设置为0）
     */
    public function clear():Void {
        for (var i:Number = 0; i < this.chunkCount; i++) {
            this.chunks[i] = 0;
        }
    }
    
    /**
     * 设置所有位为1
     */
    public function setAll():Void {
        for (var i:Number = 0; i < this.chunkCount; i++) {
            this.chunks[i] = 0xFFFFFFFF; // 32位全1
        }
        
        // 处理最后一个块的多余位
        this.clearExtraBits();
    }
    
    /**
     * 位与操作
     * @param other 另一个BitArray
     * @return 新的BitArray，包含与操作结果
     */
    public function bitwiseAnd(other:BitArray):BitArray {
        var maxLength:Number = Math.max(this.totalBits, other.getLength());
        var result:BitArray = new BitArray(maxLength);
        
        var minChunks:Number = Math.min(this.chunkCount, other.chunkCount);
        
        for (var i:Number = 0; i < minChunks; i++) {
            result.chunks[i] = this.chunks[i] & other.chunks[i];
        }
        
        return result;
    }
    
    /**
     * 位或操作
     * @param other 另一个BitArray
     * @return 新的BitArray，包含或操作结果
     */
    public function bitwiseOr(other:BitArray):BitArray {
        var maxLength:Number = Math.max(this.totalBits, other.getLength());
        var result:BitArray = new BitArray(maxLength);
        
        var maxChunks:Number = Math.max(this.chunkCount, other.chunkCount);
        
        for (var i:Number = 0; i < maxChunks; i++) {
            var thisChunk:Number = (i < this.chunkCount) ? this.chunks[i] : 0;
            var otherChunk:Number = (i < other.chunkCount) ? other.chunks[i] : 0;
            result.chunks[i] = thisChunk | otherChunk;
        }
        
        return result;
    }
    
    /**
     * 位异或操作
     * @param other 另一个BitArray
     * @return 新的BitArray，包含异或操作结果
     */
    public function bitwiseXor(other:BitArray):BitArray {
        var maxLength:Number = Math.max(this.totalBits, other.getLength());
        var result:BitArray = new BitArray(maxLength);
        
        var maxChunks:Number = Math.max(this.chunkCount, other.chunkCount);
        
        for (var i:Number = 0; i < maxChunks; i++) {
            var thisChunk:Number = (i < this.chunkCount) ? this.chunks[i] : 0;
            var otherChunk:Number = (i < other.chunkCount) ? other.chunks[i] : 0;
            result.chunks[i] = thisChunk ^ otherChunk;
        }
        
        return result;
    }
    
    /**
     * 位取反操作
     * @return 新的BitArray，包含取反结果
     */
    public function bitwiseNot():BitArray {
        var result:BitArray = new BitArray(this.totalBits);
        
        for (var i:Number = 0; i < this.chunkCount; i++) {
            result.chunks[i] = ~this.chunks[i];
        }
        
        // 清理最后一个块的多余位
        result.clearExtraBits();
        
        return result;
    }
    
    /**
     * 克隆当前BitArray
     * @return 新的BitArray实例
     */
    public function clone():BitArray {
        var result:BitArray = new BitArray(this.totalBits);
        
        for (var i:Number = 0; i < this.chunkCount; i++) {
            result.chunks[i] = this.chunks[i];
        }
        
        return result;
    }
    
    /**
     * 获取位数组长度
     * @return 总位数
     */
    public function getLength():Number {
        return this.totalBits;
    }
    
    /**
     * 统计设置为1的位数
     * @return 1的位数
     */
    public function countOnes():Number {
        var count:Number = 0;
        
        for (var i:Number = 0; i < this.chunkCount; i++) {
            count += this.popcount(this.chunks[i]);
        }
        
        return count;
    }
    
    /**
     * 检查是否为空（所有位都为0）
     * @return true如果所有位都为0
     */
    public function isEmpty():Boolean {
        for (var i:Number = 0; i < this.chunkCount; i++) {
            if (this.chunks[i] != 0) {
                return false;
            }
        }
        return true;
    }
    
    /**
     * 转换为字符串表示（调试用）
     * @return 二进制字符串
     */
    public function toString():String {
        var result:String = "";
        
        for (var i:Number = this.totalBits - 1; i >= 0; i--) {
            result += this.getBit(i).toString();
            
            // 每8位添加空格，便于阅读
            if (i > 0 && i % 8 == 0) {
                result += " ";
            }
        }
        
        return result || "0";
    }
    
    /**
     * 获取原始块数据（调试用）
     * @return 块数组的副本
     */
    public function getChunks():Array {
        var result:Array = new Array(this.chunkCount);
        for (var i:Number = 0; i < this.chunkCount; i++) {
            result[i] = this.chunks[i];
        }
        return result;
    }
    
    // ==================== 私有方法 ====================
    
    /**
     * 检查索引是否有效
     * @param index 位索引
     * @return true如果索引有效
     */
    private function isValidIndex(index:Number):Boolean {
        return index >= 0 && index < this.totalBits;
    }
    
    /**
     * 扩展数组以包含指定索引
     * @param index 目标索引
     */
    private function expandToInclude(index:Number):Void {
        if (index < 0) {
            return; // 不支持负索引
        }
        
        var newSize:Number = index + 1;
        var newChunkCount:Number = Math.ceil(newSize / BITS_PER_CHUNK);
        
        // 扩展块数组
        while (this.chunks.length < newChunkCount) {
            this.chunks.push(0);
        }
        
        this.totalBits = newSize;
        this.chunkCount = newChunkCount;
    }
    
    /**
     * 清理最后一个块中的多余位
     */
    private function clearExtraBits():Void {
        if (this.chunkCount == 0) return;
        
        var lastChunkBits:Number = this.totalBits % BITS_PER_CHUNK;
        if (lastChunkBits != 0) {
            var mask:Number = (1 << lastChunkBits) - 1;
            this.chunks[this.chunkCount - 1] &= mask;
        }
    }
    
    /**
     * 计算32位整数中1的个数（汉明重量）
     * @param n 32位整数
     * @return 1的个数
     */
    private function popcount(n:Number):Number {
        // Brian Kernighan算法的AS2实现
        var count:Number = 0;
        while (n) {
            count++;
            n &= n - 1; // 清除最低位的1
        }
        return count;
    }
}