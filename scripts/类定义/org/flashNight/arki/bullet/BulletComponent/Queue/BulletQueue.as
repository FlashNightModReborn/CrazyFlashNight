// ============================================================================
// 子弹队列管理器（混合排序优化版）
// ----------------------------------------------------------------------------
// 功能：管理子弹队列并提供有序访问，优化碰撞检测缓存命中率
// 排序策略：
// - < 64个元素：内联插入排序（低开销，缓存友好）
// - ≥ 64个元素：TimSort（稳定排序，适应部分有序）
// ============================================================================

import org.flashNight.naki.Sort.*;
import org.flashNight.arki.bullet.BulletComponent.Collider.*;
import org.flashNight.arki.component.Collider.*;    

class org.flashNight.arki.bullet.BulletComponent.Queue.BulletQueue {
    
    private var bullets:Array;
    
    // 排序阈值常量
    private static var INSERTION_SORT_THRESHOLD:Number = 64;
    
    // ========== 静态比较器支持 ==========
    // 避免每帧创建闭包
    private static var _cmpKeys:Array;
    
    /**
     * 索引比较函数，用于 TimSort 排序
     * 
     * 设计说明：
     * - 通过索引访问 _cmpKeys 数组中的实际排序值
     * - 简化版：(va > vb) - (va < vb) 利用布尔值隐式转换为 0/1
     * - 返回值：-1（a<b）、0（a==b）、1（a>b）
     * 
     * 前置条件：
     * - 所有键值已在 add() 中验证，保证为有效 Number
     * - 不存在 NaN、undefined 等异常值
     * 
     * 性能考虑：
     * - 静态函数避免闭包开销
     * - 通过共享 _cmpKeys 数组避免参数传递
     * - 简化的比较逻辑减少分支预测失败
     * 
     * @param a 第一个元素的索引
     * @param b 第二个元素的索引
     * @return 比较结果：-1/0/1
     */
    private static function cmpIndex(a:Number, b:Number):Number {
        var va:Number = _cmpKeys[a];
        var vb:Number = _cmpKeys[b];
        // AS2 中布尔值转数字是可靠的：true→1, false→0
        return (va > vb) - (va < vb);
    }

    
    // ========== 缓冲区复用 ==========
    // 减少每帧GC压力
    private var _leftKeysBuffer:Array;
    private var _rightKeysBuffer:Array;  // 新增：缓存右边界
    private var _indicesBuffer:Array;
    private var _sortedBuffer:Array;
    private var _sortedLeftBuffer:Array;  // 新增：排序后的左边界缓冲
    private var _sortedRightBuffer:Array; // 新增：排序后的右边界缓冲
    
    // ========== 双缓冲支持 ==========
    // 两套完整的数组缓冲，用于避免TimSort后的O(n)回写
    private var _arrA:Array;              // bullets双缓冲A
    private var _arrB:Array;              // bullets双缓冲B
    private var _leftA:Array;             // leftKeys双缓冲A
    private var _leftB:Array;             // leftKeys双缓冲B
    private var _rightA:Array;            // rightKeys双缓冲A
    private var _rightB:Array;            // rightKeys双缓冲B
    private var _useA:Boolean;            // 当前使用A侧缓冲
    private var _version:Number;          // 版本戳，防止跨帧误用
    
    /**
     * 构造函数
     */
    public function BulletQueue() {
        // 初始化双缓冲数组
        this._arrA = [];
        this._arrB = [];
        this._leftA = [];
        this._leftB = [];
        this._rightA = [];
        this._rightB = [];
        this._useA = true;
        this._version = 0;
        
        // 设置初始公开引用指向A侧
        this.bullets = this._arrA;
        this._leftKeysBuffer = this._leftA;
        this._rightKeysBuffer = this._rightA;
        
        // 初始化其他缓冲区
        this._indicesBuffer = [];
        this._sortedBuffer = [];
        this._sortedLeftBuffer = [];
        this._sortedRightBuffer = [];
    }
    
    /**
     * 添加子弹到队列
     * 执行严格的合法性检查，确保只有有效子弹进入队列
     * @param bullet 待添加的子弹对象
     */
    public function add(bullet:Object):Void {
        if (!bullet) return;
        var box:AABBCollider = bullet.aabbCollider;
        if (!box) return;

        var left:Number  = box.left;
        var right:Number = box.right;

        // 一次性数值健检：挡 NaN 与 ±Infinity
        if (((left - left) + (right - right)) != 0) return;

        // 比 push 更快的追加方式
        var arr:Array = this.bullets;
        arr[arr.length] = bullet;
    }

    
    /**
     * 按左边界排序子弹（混合排序策略）
     * 使用并行数组缓存key，避免动态属性污染
     * 注意：此方法假设所有子弹已在 add() 中通过合法性验证
     */
    public function sortByLeftBoundary():Void {
        var length:Number = this.bullets.length;
        
        // 即使只有0或1个元素，也要填充keys缓冲区
        if (length == 0) {
            return;
        }
        
        // ========== 预取左右边界值到缓冲区 ==========
        // 目的：
        // 1. 避免排序时重复访问属性链
        // 2. 检测是否已有序，跳过不必要的排序
        // 3. 缓存right值供碰撞检测复用
        
        // 复用缓冲区，必要时扩容（内联以减少函数调用开销）
        var leftKeys:Array = this._leftKeysBuffer;
        var rightKeys:Array = this._rightKeysBuffer;
        if (leftKeys.length < length) leftKeys.length = length;
        if (rightKeys.length < length) rightKeys.length = length;
        
        var i:Number = 0;
        var bullet:MovieClip;
        var leftValue:Number;
        var rightValue:Number;
        var prevValue:Number = -Infinity;
        var isSorted:Boolean = true;
        
        // 预取所有边界值，同时检测是否已有序
        // 所有子弹已在 add() 中验证，直接读取值
        while (i < length) {
            bullet = this.bullets[i];
            leftValue = bullet.aabbCollider.left;
            rightValue = bullet.aabbCollider.right;
            
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
        
        // ========== 单元素特殊处理 ==========
        // 单元素不需要排序，但keys已经填充
        if (length == 1) {
            return;
        }
        
        // ========== 已有序快速退出 ==========
        if (isSorted) {
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
            // 复用索引缓冲区（内联扩容检查）
            var indices:Array = this._indicesBuffer;
            if (indices.length < length) indices.length = length;
            
            // 初始化索引（4路展开）
            var end4:Number = length - (length & 3);  // 4的倍数部分
            i = 0;
            while (i < end4) {
                indices[i] = i;
                indices[i + 1] = i + 1;
                indices[i + 2] = i + 2;
                indices[i + 3] = i + 3;
                i += 4;
            }
            // 处理剩余元素
            while (i < length) {
                indices[i] = i;
                i++;
            }
            
            // 使用静态比较器（避免闭包开销）
            _cmpKeys = leftKeys;
            TimSort.sort(indices, cmpIndex);
            
            // 选择源和目标缓冲区
            var srcBullets:Array = this.bullets;
            var srcLeft:Array = this._leftKeysBuffer;
            var srcRight:Array = this._rightKeysBuffer;
            
            var dstBullets:Array = this._useA ? this._arrB : this._arrA;
            var dstLeft:Array = this._useA ? this._leftB : this._leftA;
            var dstRight:Array = this._useA ? this._rightB : this._rightA;
            
            // 确保目标缓冲区容量
            if (dstBullets.length < length) dstBullets.length = length;
            if (dstLeft.length < length) dstLeft.length = length;
            if (dstRight.length < length) dstRight.length = length;
            
            // 直接投影到目标缓冲区（4路展开）
            i = 0;
            var k0:Number, k1:Number, k2:Number, k3:Number;
            while (i < end4) {
                k0 = indices[i];
                k1 = indices[i + 1];
                k2 = indices[i + 2];
                k3 = indices[i + 3];
                
                dstBullets[i] = srcBullets[k0];
                dstBullets[i + 1] = srcBullets[k1];
                dstBullets[i + 2] = srcBullets[k2];
                dstBullets[i + 3] = srcBullets[k3];
                
                dstLeft[i] = srcLeft[k0];
                dstLeft[i + 1] = srcLeft[k1];
                dstLeft[i + 2] = srcLeft[k2];
                dstLeft[i + 3] = srcLeft[k3];
                
                dstRight[i] = srcRight[k0];
                dstRight[i + 1] = srcRight[k1];
                dstRight[i + 2] = srcRight[k2];
                dstRight[i + 3] = srcRight[k3];
                
                i += 4;
            }
            // 处理剩余元素
            while (i < length) {
                var k:Number = indices[i];
                dstBullets[i] = srcBullets[k];
                dstLeft[i] = srcLeft[k];
                dstRight[i] = srcRight[k];
                i++;
            }
            
            // 交换公开指针，避免O(n)回写
            this.bullets = dstBullets;
            this._leftKeysBuffer = dstLeft;
            this._rightKeysBuffer = dstRight;
            
            // 切换缓冲区标志
            this._useA = !this._useA;
            this._version++;
            
            // 确保长度正确
            this.bullets.length = length;
            this._leftKeysBuffer.length = length;
            this._rightKeysBuffer.length = length;
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
        // 清空所有双缓冲区
        this._arrA.length = 0;
        this._arrB.length = 0;
        this._leftA.length = 0;
        this._leftB.length = 0;
        this._rightA.length = 0;
        this._rightB.length = 0;
        
        // 重置到A侧作为公开数组
        this.bullets = this._arrA;
        this._leftKeysBuffer = this._leftA;
        this._rightKeysBuffer = this._rightA;
        this._useA = true;
        this._version++;
        
        // 清空其他缓冲区
        this._indicesBuffer.length = 0;
        this._sortedBuffer.length = 0;
        this._sortedLeftBuffer.length = 0;
        this._sortedRightBuffer.length = 0;
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
        return {
            bullets: this.bullets,
            indices: null,  // 就地重排后不需要索引
            leftKeys: this._leftKeysBuffer,
            rightKeys: this._rightKeysBuffer,
            length: length,
            isIndexed: false,  // 明确标记为非索引模式
            version: this._version  // 版本戳，防止跨帧误用
        };
    }
}