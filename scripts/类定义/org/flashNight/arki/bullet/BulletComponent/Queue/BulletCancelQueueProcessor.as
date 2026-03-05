/**
 * ============================================================================
 * 子弹消除队列处理器
 * ============================================================================
 * 
 * 【系统概述】
 * 本类负责处理游戏中的消弹判定系统，通过队列缓存和批处理机制实现高效的子弹消除。
 * 支持反弹、消除等多种处理模式，使用事件驱动的帧更新机制。
 *
 * 【核心特性】
 * - 队列缓存：帧内入队，帧末批处理
 * - 区域碰撞：基于矩形区域的快速碰撞检测
 * - 方向过滤：支持按子弹飞行方向过滤
 * - Z轴判定：支持3D空间的高度差判定
 * - 敌我识别：根据阵营属性过滤子弹
 *
 * 【设计原则】
 * - 静态工具类模式，全局单例管理
 * - 零分配策略，复用数组对象
 * - 事件驱动，与帧更新系统集成
 *
 * @version 1.0
 * ============================================================================
 */

import org.flashNight.arki.component.Effect.*;
import org.flashNight.neur.Event.*;

class org.flashNight.arki.bullet.BulletComponent.Queue.BulletCancelQueueProcessor {

    // ========================================================================
    // 静态数据存储
    // ========================================================================

    /**
     * 本帧入队计数（帧级活跃度计数）
     * - 仅在 enqueue 时递增
     * - 在帧末处理后归零
     * - 供 prepareIfActive() 零开销短路查询使用
     */
    private static var _frameEnqueueCount:Number = 0;

    /**
     * 是否已初始化
     */
    private static var initialized:Boolean = false;

    // ========================================================================
    // 并行数组（SoA）区域缓存 - 由 BulletQueueProcessor 直接引用，零拷贝访问
    // ========================================================================
    private static var _soaPrepared:Boolean = false;   // 是否已基于当前队列构建缓存
    public  static var soaLen:Number = 0;              // 缓存有效长度（消费端读此字段）

    // 轴对齐矩形（gameworld坐标系）— public 供 BulletQueueProcessor 直接引用
    public  static var xMin:Array = [];
    public  static var xMax:Array = [];
    public  static var yMin:Array = [];
    public  static var yMax:Array = [];

    // 业务属性（按索引与矩形一一对应）
    public  static var shootZ:Array = [];
    public  static var zRange:Array = [];
    public  static var dirCode:Array = [];      // -1:左, 0:不限, 1:右
    public  static var isEnemy:Array = [];
    public  static var isBounce:Array = [];
    public  static var isPowerful:Array = [];
    public  static var shooter:Array = [];
    private static var _reqRef:Array = [];      // 原始请求引用，便于未来回调处理

    // 索引数组（用于排序，避免移动大量数据）— public 供消费端按序访问
    public  static var sortIdx:Array = [];
    
    /**
     * 对消弹区域的索引数组 sortIdx 进行**稳定升序排序**（按 xMin 的值排序）
     * ----------------------------------------------------------------------------
     * 【函数目的】
     *  - 仅对”索引数组”排序，所有 SoA 数据（xMin/xMax/yMin/yMax/...）保持原地不动；
     *  - 这样能避免大量数据搬移，提高缓存命中率与整体吞吐。
     *
     * 【算法说明】
     *  - 小规模场景（本项目实际峰值 3~5）：采用**插入排序**的单趟实现，常数最小；
     *  - “边填充索引、边插入”的单趟策略：不再先做 0..n-1 的全量写入，进一步减少一次 O(n) 写；
     *  - **近有序快路**：若当前键值 ≥ 上一个键值，直接追加，完全有序时退化为 O(n)；
     *  - **带守卫的 do…while 左移**：仅在确实需要左移时进入，一次循环可连续搬移，减少分支；
     *  - **稳定排序**：比较使用 `>` 而非 `>=`，确保相等键保持相对顺序不变。
     *
     * 【输入/输出（隐式）】
     *  - 输入：soaLen（有效元素数）；xMin（按索引访问的排序键）；sortIdx（将被填充/排序的索引数组）
     *  - 输出：sortIdx[0..soaLen-1] 按 xMin 升序排列；sortIdx.length 设为 soaLen
     *  - 其余并行数组不做任何写入或搬移
     *
     * 【复杂度】
     *  - 最好：O(n)（完全非降序，近有序快路生效）
     *  - 平均/最坏：O(n^2)（插入排序特性；但对 n≲5 的典型负载，常数最小、效果最佳）
     *  - 额外空间：O(1)
     *
     * 【边界与健壮性】
     *  - 当 soaLen ≤ 1：直接调整 length 并返回；
     *  - 函数会**预扩容** sortIdx 到至少 soaLen，避免动态扩容分配；
     *  - 函数结束时仅将 length 截断到 soaLen，容量保留以便下帧复用（零分配策略）。
     */
    private static function sortIndices():Void {
        var len:Number = soaLen;
        var idx:Array  = sortIdx;
        var xMinL:Array = xMin;  // 局部别名，避免与 public static xMin 字段歧义

        // 空/单元素：设定有效长度后返回
        if (len <= 0) {
            idx.length = 0;
            return;
        }
        if (len == 1) {
            idx[0] = 0;
            idx.length = 1;
            return;
        }
        // 确保索引数组有足够容量，避免访问越界
        if (idx.length < len) idx.length = len;

        // 种子：首元素恒为自身索引 0
        idx[0] = 0;

        // prev 用于”近有序快路”的非降序检测（记录当前已排序部分的最大值）
        var prev:Number = xMinL[0];

        // 循环变量（函数级声明，减少重复 var 成本）
        var i:Number = 1;
        var j:Number;
        var key:Number;
        var keyX:Number;

        // 单趟：边填充索引，边执行插入
        for (; i < len; i++) {
            key  = i;             // 目标索引
            keyX = xMinL[key];    // 其排序键（xMin）

            // 近有序快路：直接追加（当前键值大于等于前一个最大值）
            if (keyX >= prev) {
                idx[i] = key;
                prev   = keyX;   // 更新有序基线
                continue;
            }

            // 需要插入：从 i-1 起向左寻找插入点，并依次左移元素空出位置
            j = i - 1;

            // 守卫：仅当首比较确实需要左移时才进入 do…while 连续搬移
            if (xMinL[idx[j]] > keyX) {
                do {
                    idx[j + 1] = idx[j]; // 右移元素
                    j--;
                } while (j >= 0 && xMinL[idx[j]] > keyX);
            }

            // 统一落点：
            // - 若发生左移：j 已退到插入点左侧，写入 j+1；
            // - 若未发生左移：j 仍为 i-1，此处等价于写回 idx[i]。
            idx[j + 1] = key;

            // 注意：此分支下 keyX < prev，prev 保持不变（因为插入的元素小于当前最大值）
        }

        // 截断到有效长度（容量保留以复用，避免反复分配）
        idx.length = len;
    }



    // ========================================================================
    // 系统初始化方法
    // ========================================================================

    /**
     * 初始化消弹队列处理器
     *
     * 创建队列和缓存，订阅事件监听器。
     * 此方法应在游戏启动时调用一次。
     *
     * @return {Boolean} 初始化是否成功
     */
    public static function initialize():Boolean {
        if (initialized) {
            return true;
        }

        // 使用 EventBus 单例订阅事件
        var eventBus:EventBus = EventBus.getInstance();

        // 不再订阅 frameUpdate；消弹由 BulletQueueProcessor 一体化阶段处理

        // 订阅场景切换事件
        eventBus.subscribe("SceneChanged", function() {
            BulletCancelQueueProcessor.reset();
        }, BulletCancelQueueProcessor);

        initialized = true;
        return true;
    }

    // ========================================================================
    // 系统重置方法
    // ========================================================================

    /**
     * 重置消弹队列处理器
     *
     * 清空队列和缓存，用于场景切换时防止引用旧对象。
     *
     * @return {Boolean} 重置是否成功
     */
    public static function reset():Boolean {
        // 清空缓存
        _frameEnqueueCount = 0;

        // 清空 SoA 缓存元信息
        soaLen = 0;
        _soaPrepared = false;

        // 清空并行数组，释放所有引用避免悬挂
        xMin.length = xMax.length = yMin.length = yMax.length = 0;
        shootZ.length = zRange.length = dirCode.length = 0;
        isEnemy.length = isBounce.length = isPowerful.length = 0;
        shooter.length = _reqRef.length = 0;

        // 清空排序索引
        sortIdx.length = 0;

        return true;
    }

    // ========================================================================
    // 消弹请求入队方法
    // ========================================================================

    /**
     * 将消弹请求加入队列（直接SoA入队优化版）
     *
     * @param {Object} request 消弹请求对象，包含以下属性：
     *   - 区域定位area {MovieClip} 消弹区域
     *   - shooter {String} 发射者名称（反弹模式用）
     *   - shootZ {Number} 发射者Z轴坐标
     *   - 消弹敌我属性 {Boolean} 是否为敌人
     *   - 消弹方向 {String} "左"/"右"/null
     *   - Z轴攻击范围 {Number} Z轴判定范围
     *   - 反弹 {Boolean} 是否反弹模式
     *   - 强力 {Boolean} 是否强力消除
     */
    public static function enqueue(request:Object):Void {
        if (_root.暂停) return;

        // 最小校验：需要区域定位area
        if (!request || !request.区域定位area) return;

        var area:MovieClip = request.区域定位area;
        if (!area.getRect) return;

        // 立即计算几何边界（避免帧末重复计算）
        var gameWorld:MovieClip = _root.gameworld;
        if (!gameWorld) return;

        var R:Object = area.getRect(gameWorld);

        // 直接填充到并行数组（SoA）
        var idx:Number = soaLen;

        // 填充数据（AS2数组会自动扩容）
        xMin[idx] = R.xMin;
        xMax[idx] = R.xMax;
        yMin[idx] = R.yMin;
        yMax[idx] = R.yMax;

        shootZ[idx] = request.shootZ;
        zRange[idx] = request.Z轴攻击范围;

        // 方向编码：左=-1, 右=1, 其他=0
        var d:String = request.消弹方向;
        dirCode[idx] = (d == "左") ? -1 : ((d == "右") ? 1 : 0);

        isEnemy[idx] = request.消弹敌我属性;
        isBounce[idx] = (request.反弹 == true);
        isPowerful[idx] = (request.强力 == true);
        shooter[idx] = request.shooter;
        _reqRef[idx] = request;

        // 更新计数器
        soaLen++;
        _frameEnqueueCount++;
        _soaPrepared = false;  // 需要排序
    }

    /**
     * 添加消弹请求（enqueue的别名，与BulletQueueProcessor保持一致）
     */
    public static function add(request:Object):Void {
        enqueue(request);
    }

    // ========================================================================
    // 属性初始化辅助方法
    // ========================================================================

    /**
     * 初始化消弹属性对象
     *
     * 便捷方法，用于构造标准的消弹请求对象。
     *
     * @param {MovieClip} area 消弹区域MovieClip
     * @return {Object} 初始化好的消弹属性对象
     */
    public static function initArea(area:MovieClip):Object {
        var props:Object = {
            shooter: area._parent._parent._name,
            shootZ: area._parent._parent.Z轴坐标,
            消弹敌我属性: area._parent._parent.是否为敌人,
            消弹方向: null,          // 无方向限制；可传 "左" 或 "右"
            Z轴攻击范围: 10,
            区域定位area: area
        };
        return props;
    }

    // ========================================================================
    // 帧级活跃度与 SoA 缓存接口
    // ========================================================================

    /**
     * 准备消弹区域缓存（合并 hasActive + prepareAreaCache 为单次调用）
     *
     * - 无消弹请求时：O(1) 返回 false，零额外开销
     * - 有请求时：对索引排序，随后消费端可直接读取 public 静态数组
     * - 消费端通过 sortIdx[i] 间接访问有序数据（零拷贝）
     *
     * @return Boolean 是否存在有效消弹区域（true = 本帧需要做消弹扫描）
     */
    public static function prepareIfActive():Boolean {
        if (_frameEnqueueCount == 0) return false;
        _frameEnqueueCount = 0;  // 清零，防止重复调用

        // 单元素：直接写索引，不排序
        if (soaLen == 1) {
            sortIdx.length = 1;
            sortIdx[0] = 0;
            _soaPrepared = true;
            return true;
        }

        // 多元素：插入排序（峰值 3~5 个区域，常数最小）
        sortIndices();
        _soaPrepared = true;
        return true;
    }

    /**
     * 帧结束清理（在每帧末消弹处理完后调用）
     * 仅重置长度计数，数组容量保留供下帧复用（零分配策略）
     */
    public static function endFrame():Void {
        soaLen = 0;
        _soaPrepared = false;
        _frameEnqueueCount = 0;
    }

    /**
     * @deprecated 改用 prepareIfActive()（消除中间 Object 分配）
     * 保留空实现避免外部残留调用报错
     */
    public static function hasActive():Boolean {
        return _frameEnqueueCount > 0;
    }

    /**
     * @deprecated 改用 prepareIfActive() + 直接访问 public 静态数组
     * 保留空实现避免外部残留调用报错
     */
    public static function prepareAreaCache():Boolean {
        return prepareIfActive();
    }

    /**
     * @deprecated 改用直接访问 public 静态数组（消除每帧 Object 分配）
     * 保留空实现避免外部残留调用报错
     */
    public static function getAreaCacheRef():Object {
        return null;
    }

    // ========================================================================
    // 核心处理方法：批量消弹判定（已废弃）
    // ========================================================================

    /**
     * @deprecated 集成模式下无需调用，空实现避免历史代码报错
     *
     * 消弹处理已集成到 BulletQueueProcessor.processQueue() 的阶段1中。
     * 保留此方法仅为向后兼容。
     */
    public static function processQueue():Void {
        /* no-op - 消弹由 BulletQueueProcessor 一体化阶段处理 */
    }

    // ========================================================================
    // 子弹处理方法
    // ========================================================================

    /**
     * 处理子弹反弹
     *
     * @param {MovieClip} bullet 要反弹的子弹
     * @param {String} newShooter 新的发射者名称
     */
    public static function handleBounce(bullet:MovieClip, newShooter:String):Void {
        // 当前方向（弧度）与速度
        var rad:Number = Math.atan2(bullet.ymov, bullet.xmov);
        var speed:Number = Math.sqrt(bullet.xmov * bullet.xmov + bullet.ymov * bullet.ymov);

        // 随机偏移（±30°）
        var offsetRad:Number = (Math.random() - 0.5) * (Math.PI / 3);
        // 反弹 = 方向 + π，再加一点随机扰动
        var newRad:Number = rad + Math.PI + offsetRad;

        // 更新速度向量与朝向
        bullet.xmov = Math.cos(newRad) * speed;
        bullet.ymov = Math.sin(newRad) * speed;
        bullet._rotation = newRad * 180 / Math.PI;

        // 安全获取阵营，防止newShooter临时失效
        var sh:MovieClip = _root.gameworld[newShooter];
        if (sh) {
            bullet.是否为敌人 = sh.是否为敌人;
            bullet.发射者名 = newShooter;
        }
    }

    /**
     * 处理子弹消除
     *
     * @param {MovieClip} bullet 要消除的子弹
     * @param {Boolean} isPowerful 是否强力消除
     */
    public static function handleCancel(bullet:MovieClip, isPowerful:Boolean):Void {
        #include "../macros/FLAG_PIERCE.as"
        #include "../macros/STATE_HIT_MAP.as"

        // 使用位运算直接写入 stateFlags
        bullet.stateFlags |= STATE_HIT_MAP;
        EffectSystem.Effect(bullet.击中地图效果, bullet._x, bullet._y);
        bullet.gotoAndPlay("消失");

        if (isPowerful && (bullet.flags & FLAG_PIERCE)) {
            bullet.removeMovieClip();
        }
    }
}