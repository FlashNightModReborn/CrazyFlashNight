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
     * - 供 hasActive() 零开销查询使用
     */
    private static var _frameEnqueueCount:Number = 0;

    /**
     * 是否已初始化
     */
    private static var initialized:Boolean = false;

    // ========================================================================
    // 并行数组（SoA）区域缓存 - 预留给一体化主循环查询
    // ========================================================================
    private static var _soaPrepared:Boolean = false;   // 是否已基于当前队列构建缓存
    private static var _soaLen:Number = 0;             // 缓存长度

    // 轴对齐矩形（gameworld坐标系）
    private static var _xMin:Array = [];
    private static var _xMax:Array = [];
    private static var _yMin:Array = [];
    private static var _yMax:Array = [];

    // 业务属性（按索引与矩形一一对应）
    private static var _shootZ:Array = [];
    private static var _zRange:Array = [];
    private static var _dirCode:Array = [];      // -1:左, 0:不限, 1:右
    private static var _isEnemy:Array = [];
    private static var _isBounce:Array = [];
    private static var _isPowerful:Array = [];
    private static var _shooter:Array = [];
    private static var _reqRef:Array = [];       // 原始请求引用，便于未来回调处理

    // 索引数组（用于排序，避免移动大量数据）
    private static var _sortIdx:Array = [];

    /**
     * 确保数组容量不小于 need；仅扩容，不缩容
     * @param {Array} a 目标数组
     * @param {Number} need 需要的最小长度
     */
    private static function ensureCapacity(a:Array, need:Number):Void {
        if (a.length < need) a.length = need;
    }

    /**
     * 对索引数组进行排序（数据本身保持无序）
     * 使用插入排序保证稳定性，适合近有序数据
     */
    private static function sortIndices():Void {
        if (_soaLen <= 1) return;

        // 确保索引数组容量
        ensureCapacity(_sortIdx, _soaLen);
        var idx:Array = _sortIdx;
        var i:Number, j:Number;

        // 填充索引（0, 1, 2, ...）
        for (i = 0; i < _soaLen; i++) {
            idx[i] = i;
        }

        // 稳定插入排序（仅操作索引，按 xMin 升序）
        var key:Number, keyX:Number;
        for (i = 1; i < _soaLen; i++) {
            key = idx[i];
            keyX = _xMin[key];  // 通过索引访问实际数据
            j = i - 1;
            while (j >= 0 && _xMin[idx[j]] > keyX) {
                idx[j + 1] = idx[j];
                j--;
            }
            idx[j + 1] = key;
        }

        // 索引数组长度设为有效长度
        idx.length = _soaLen;
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
        _soaLen = 0;
        _soaPrepared = false;

        // 清空并行数组，释放所有引用避免悬挂
        _xMin.length = _xMax.length = _yMin.length = _yMax.length = 0;
        _shootZ.length = _zRange.length = _dirCode.length = 0;
        _isEnemy.length = _isBounce.length = _isPowerful.length = 0;
        _shooter.length = _reqRef.length = 0;

        // 清空排序索引
        _sortIdx.length = 0;

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
        var idx:Number = _soaLen;

        // 确保容量
        ensureCapacity(_xMin, idx + 1);
        ensureCapacity(_xMax, idx + 1);
        ensureCapacity(_yMin, idx + 1);
        ensureCapacity(_yMax, idx + 1);
        ensureCapacity(_shootZ, idx + 1);
        ensureCapacity(_zRange, idx + 1);
        ensureCapacity(_dirCode, idx + 1);
        ensureCapacity(_isEnemy, idx + 1);
        ensureCapacity(_isBounce, idx + 1);
        ensureCapacity(_isPowerful, idx + 1);
        ensureCapacity(_shooter, idx + 1);
        ensureCapacity(_reqRef, idx + 1);

        // 填充数据
        _xMin[idx] = R.xMin;
        _xMax[idx] = R.xMax;
        _yMin[idx] = R.yMin;
        _yMax[idx] = R.yMax;

        _shootZ[idx] = request.shootZ;
        _zRange[idx] = request.Z轴攻击范围;

        // 方向编码：左=-1, 右=1, 其他=0
        var d:String = request.消弹方向;
        _dirCode[idx] = (d == "左") ? -1 : ((d == "右") ? 1 : 0);

        _isEnemy[idx] = request.消弹敌我属性;
        _isBounce[idx] = (request.反弹 == true);
        _isPowerful[idx] = (request.强力 == true);
        _shooter[idx] = request.shooter;
        _reqRef[idx] = request;

        // 更新计数器
        _soaLen++;
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
    // 新增：帧级活跃度与 SoA 缓存接口（不改变旧路径行为）
    // ========================================================================

    /**
     * 是否存在本帧入队的消弹请求（零开销短路查询）
     * - 仅检查 _frameEnqueueCount 计数，不触发任何分配或计算
     */
    public static function hasActive():Boolean {
        return _frameEnqueueCount > 0;
    }

    /**
     * 帧结束清理（必须在每帧末调用）
     * 清空所有缓存数据，为下一帧做准备
     * 防止旧消弹区域"复活"的关键方法
     */
    public static function endFrame():Void {
        // 下帧从空开始
        _soaLen = 0;
        _soaPrepared = false;
        _frameEnqueueCount = 0;

        // 可选：清空数组长度，避免高水位占内存
        // 注释掉以复用容量，减少下帧扩容开销
        // _xMin.length = _xMax.length = _yMin.length = _yMax.length = 0;
        // _shootZ.length = _zRange.length = _dirCode.length = 0;
        // _isEnemy.length = _isBounce.length = _isPowerful.length = 0;
        // _shooter.length = _reqRef.length = 0;
        // _sortIdx.length = 0;
    }

    /**
     * 构建并行数组（SoA）区域缓存，按 xMin 有序
     * - 输入：gameWorld（坐标换算基准）
     * - 输出：内部并行数组 _xMin/_xMax/_yMin/_yMax 等及 _soaLen
     * - 构建后立即消费队列，避免累积和重复处理
     *
     * 返回：是否成功生成有效缓存（当队列为空时返回 false）
     */
    public static function prepareAreaCache(gameWorld:MovieClip):Boolean {
        // 数据已在enqueue时直接填充到SoA，这里只需排序
        if (_soaLen == 0) {
            _frameEnqueueCount = 0;
            return false;
        }

        // 单元素：必须构建索引
        if (_soaLen == 1) {
            // 构建索引数组 [0]
            ensureCapacity(_sortIdx, 1);
            _sortIdx.length = 1;
            _sortIdx[0] = 0;

            _soaPrepared = true;
            _frameEnqueueCount = 0;
            return true;
        }

        // 仅对索引进行排序，数据数组保持无序
        sortIndices();

        // 不裁剪SoA数组长度，保留容量供下帧复用
        // 使用 _soaLen 作为有效长度标识即可

        _soaPrepared = true;
        _frameEnqueueCount = 0;
        return true;
    }

    /**
     * 获取已准备好的 SoA 区域缓存的只读视图（引用）
     * - 返回排序索引和原始无序数组，实现零拷贝间接访问
     * - 消费端通过 array[indices[i]] 方式访问有序数据
     * - 若尚未准备或为空，返回 null
     */
    public static function getAreaCacheRef():Object {
        if (!_soaPrepared || _soaLen == 0) return null;
        return {
            prepared: _soaPrepared,
            length: _soaLen,
            indices: _sortIdx,      // 排序后的索引数组
            xMin: _xMin,           // 原始无序数组
            xMax: _xMax,
            yMin: _yMin,
            yMax: _yMax,
            shootZ: _shootZ,
            zRange: _zRange,
            dirCode: _dirCode,
            isEnemy: _isEnemy,
            isBounce: _isBounce,
            isPowerful: _isPowerful,
            shooter: _shooter,
            reqRef: _reqRef
        };
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

        bullet.击中地图 = true;
        EffectSystem.Effect(bullet.击中地图效果, bullet._x, bullet._y);
        bullet.gotoAndPlay("消失");

        if (isPowerful && (bullet.flags & FLAG_PIERCE)) {
            bullet.removeMovieClip();
        }
    }
}
