// ============================================================================
// 子弹队列管理器（混合排序优化版）
// ----------------------------------------------------------------------------
// 功能：管理子弹队列并提供有序访问，优化碰撞检测缓存命中率
// 排序策略：
// - < 64个元素：内联插入排序（低开销，缓存友好）
// - ≥ 64个元素：TimSort（稳定排序，适应部分有序）
// ============================================================================

import org.flashNight.naki.Sort.*;

class org.flashNight.arki.bullet.BulletComponent.Queue.BulletQueue {
    
    private var bullets:Array;
    
    // 排序阈值常量
    private static var INSERTION_SORT_THRESHOLD:Number = 64;
    
    // ========== 静态比较器支持 ==========
    // 避免每帧创建闭包
    private static var _cmpKeys:Array;
    
    private static function cmpIndex(a:Number, b:Number):Number {
        var d:Number = _cmpKeys[a] - _cmpKeys[b];
        return (d < 0) ? -1 : ((d > 0) ? 1 : 0);
    }
    
    // ========== 缓冲区复用 ==========
    // 减少每帧GC压力
    private var _leftKeysBuffer:Array;
    private var _rightKeysBuffer:Array;  // 新增：缓存右边界
    private var _indicesBuffer:Array;
    private var _sortedBuffer:Array;
    private var _sortedLeftBuffer:Array;  // 新增：排序后的左边界缓冲
    private var _sortedRightBuffer:Array; // 新增：排序后的右边界缓冲
    
    /**
     * 构造函数
     */
    public function BulletQueue() {
        this.bullets = [];
        // 初始化缓冲区
        this._leftKeysBuffer = [];
        this._rightKeysBuffer = [];  // 初始化右边界缓冲
        this._indicesBuffer = [];
        this._sortedBuffer = [];
        this._sortedLeftBuffer = [];   // 初始化排序左边界缓冲
        this._sortedRightBuffer = [];  // 初始化排序右边界缓冲
    }
    
    /**
     * 确保缓冲区容量
     * @private
     */
    private function ensureCapacity(buffer:Array, capacity:Number):Void {
        if (buffer.length < capacity) {
            buffer.length = capacity;
        }
    }
    
    /**
     * 添加子弹到队列
     * 放宽检查，因为预检测会处理异常情况
     */
    public function add(bullet:MovieClip):Void {
        if (bullet) {
            this.bullets.push(bullet);
        }
    }
    
    /**
     * 按左边界排序子弹（混合排序策略）
     * 使用并行数组缓存key，避免动态属性污染
     */
    public function sortByLeftBoundary():Void {
        var length:Number = this.bullets.length;
        if (length <= 1) {
            return;
        }
        
        // ========== 预取左右边界值到缓冲区 ==========
        // 目的：
        // 1. 避免排序时重复访问属性链
        // 2. 处理NaN/undefined，保证比较一致性
        // 3. 检测是否已有序，跳过不必要的排序
        // 4. 缓存right值供碰撞检测复用
        
        // 复用缓冲区，必要时扩容
        var leftKeys:Array = this._leftKeysBuffer;
        var rightKeys:Array = this._rightKeysBuffer;
        this.ensureCapacity(leftKeys, length);
        this.ensureCapacity(rightKeys, length);
        
        var i:Number = 0;
        var bullet:MovieClip;
        var leftValue:Number;
        var rightValue:Number;
        var prevValue:Number = Number.NEGATIVE_INFINITY;
        var isSorted:Boolean = true;
        
        var hasInvalid:Boolean = false;  // 记录是否有异常对象
        
        // 预取所有边界值，同时检测是否已有序
        while (i < length) {
            bullet = this.bullets[i];
            if (bullet && bullet.aabbCollider) {
                leftValue = bullet.aabbCollider.left;
                rightValue = bullet.aabbCollider.right;
                
                // NaN检查：left异常压到末尾，right异常设为负无穷避免误杀早退
                if (isNaN(leftValue)) {
                    leftValue = Number.POSITIVE_INFINITY;
                    hasInvalid = true;
                }
                if (isNaN(rightValue)) {
                    rightValue = Number.NEGATIVE_INFINITY;
                    hasInvalid = true;
                }
            } else {
                leftValue = Number.POSITIVE_INFINITY;
                rightValue = Number.NEGATIVE_INFINITY;
                hasInvalid = true;
            }
            
            leftKeys[i] = leftValue;
            rightKeys[i] = rightValue;
            
            // 检测是否有序（非降序）
            if (isSorted && leftValue < prevValue) {
                isSorted = false;
                // 不break，继续预取完所有key
            }
            prevValue = leftValue;
            i++;
        }
        
        // ========== 已有序快速退出 ==========
        // 如果有异常对象，强制排序以确保它们被推到队尾
        if (isSorted && !hasInvalid) {
            return;  // 跳过排序，节省大量开销
        }
        
        // ========== 小数组路径：插入排序（< 64个元素） ==========
        if (length < INSERTION_SORT_THRESHOLD) {
            // 带索引的插入排序，同步移动所有数组
            
            var arr:Array = this.bullets;    // 局部缓存
            var lkeys:Array = leftKeys;      // 左边界keys
            var rkeys:Array = rightKeys;     // 右边界keys（必须同步）
            var j:Number;
            var key:MovieClip;
            var keyLeft:Number;
            var keyRight:Number;
            
            i = 1;
            do {
                // 取出待插入元素及其所有key
                key = arr[i];
                keyLeft = lkeys[i];
                keyRight = rkeys[i];  // 同时取出右边界
                j = i - 1;
                
                // 向前查找插入位置
                // 关键：用 > 而非 >= 保证稳定性
                while (j >= 0 && lkeys[j] > keyLeft) {
                    // 同时移动子弹和所有keys
                    arr[j + 1] = arr[j];
                    lkeys[j + 1] = lkeys[j];
                    rkeys[j + 1] = rkeys[j];  // 同步移动rightKeys
                    j--;
                }
                
                // 插入到正确位置
                arr[j + 1] = key;
                lkeys[j + 1] = keyLeft;
                rkeys[j + 1] = keyRight;  // 同步插入rightKey
                
            } while (++i < length);
            
        // ========== 大数组路径：索引排序 + 重排 ==========
        } else {
            // 复用索引缓冲区
            var indices:Array = this._indicesBuffer;
            this.ensureCapacity(indices, length);
            for (i = 0; i < length; i++) {
                indices[i] = i;
            }
            
            // 使用静态比较器（避免闭包开销）
            _cmpKeys = leftKeys;
            TimSort.sort(indices, cmpIndex);
            
            // 复用所有排序缓冲区
            var sortedBullets:Array = this._sortedBuffer;
            var sortedLeft:Array = this._sortedLeftBuffer;
            var sortedRight:Array = this._sortedRightBuffer;
            this.ensureCapacity(sortedBullets, length);
            this.ensureCapacity(sortedLeft, length);
            this.ensureCapacity(sortedRight, length);
            
            // 根据排序后的索引重排所有数组
            for (i = 0; i < length; i++) {
                var k:Number = indices[i];
                sortedBullets[i] = this.bullets[k];
                sortedLeft[i] = leftKeys[k];
                sortedRight[i] = rightKeys[k];
            }
            
            // 重要：就地覆盖所有数组，保持一致性
            var arr:Array = this.bullets;
            for (i = 0; i < length; i++) {
                arr[i] = sortedBullets[i];
                leftKeys[i] = sortedLeft[i];
                rightKeys[i] = sortedRight[i];
            }
            // 确保长度一致
            arr.length = length;
        }
    }
    
    /**
     * 获取排序后的子弹数组
     * 注意：此方法有副作用，会对内部数组进行排序
     * @return 排序后的内部数组引用（不是副本）
     */
    public function getSortedBullets():Array {
        this.sortByLeftBoundary();
        return this.bullets;
    }
    
    /**
     * 清空队列（原地清空，保持引用有效）
     */
    public function clear():Void {
        this.bullets.length = 0;  // 原地清空，不替换数组引用
    }
    
    /**
     * 获取子弹数量
     */
    public function getCount():Number {
        return this.bullets.length;
    }
    
    /**
     * 直接获取内部数组引用（谨慎使用）
     */
    public function getBulletsReference():Array {
        return this.bullets;
    }
    
    /**
     * 获取左边界缓存（只读，供碰撞检测复用）
     */
    public function getLeftKeysRef():Array {
        return this._leftKeysBuffer;
    }
    
    /**
     * 获取右边界缓存（只读，供碰撞检测复用）
     */
    public function getRightKeysRef():Array {
        return this._rightKeysBuffer;
    }
    
    /**
     * 按排序顺序遍历子弹（高效版，避免重排拷贝）
     * @param visitor 访问函数，接收(bullet, index)参数
     */
    public function forEachSorted(visitor:Function):Void {
        this.sortByLeftBoundary();
        
        var length:Number = this.bullets.length;
        var arr:Array = this.bullets;
        
        // 由于采用就地重排模式，大小数组都直接顺序遍历
        for (var i:Number = 0; i < length; i++) {
            visitor(arr[i], i);
        }
    }
    
    /**
     * 按排序顺序遍历子弹，同时提供边界值
     * 提供统一的访问器，避免调用方误用索引
     * @param visitor 访问函数，接收(bullet, leftKey, rightKey, index)参数
     */
    public function forEachSortedWithKeys(visitor:Function):Void {
        this.sortByLeftBoundary();
        
        var arr:Array = this.bullets;
        var L:Array = this._leftKeysBuffer;
        var R:Array = this._rightKeysBuffer;
        var n:Number = arr.length;
        
        for (var i:Number = 0; i < n; i++) {
            visitor(arr[i], L[i], R[i], i);
        }
    }
    
    /**
     * 获取排序迭代器（供高级用途）
     * @return 包含所有缓存数据的迭代器对象
     */
    public function getSortedIterator():Object {
        this.sortByLeftBoundary();
        
        var length:Number = this.bullets.length;
        // 由于采用了就地重排模式，不再需要indices
        return {
            bullets: this.bullets,
            indices: null,  // 就地重排后不需要索引
            leftKeys: this._leftKeysBuffer,
            rightKeys: this._rightKeysBuffer,
            length: length,
            isIndexed: false  // 明确标记为非索引模式
        };
    }
}