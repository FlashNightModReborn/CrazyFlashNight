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
     * 消弹请求队列
     * 存储待处理的消弹请求对象
     */
    private static var queue:Array = [];

    /**
     * 本帧入队计数（帧级活跃度计数）
     * - 仅在 enqueue 时递增
     * - 在旧路径 processQueue 执行结束时归零
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

    // 双缓冲后备数组与索引复用（零分配策略）
    private static var _xMinB:Array = [];
    private static var _xMaxB:Array = [];
    private static var _yMinB:Array = [];
    private static var _yMaxB:Array = [];
    private static var _shootZB:Array = [];
    private static var _zRangeB:Array = [];
    private static var _dirCodeB:Array = [];
    private static var _isEnemyB:Array = [];
    private static var _isBounceB:Array = [];
    private static var _isPowerfulB:Array = [];
    private static var _shooterB:Array = [];
    private static var _reqRefB:Array = [];

    private static var _idx:Array = []; // 复用索引数组

    /**
     * 确保数组容量不小于 need；仅扩容，不缩容
     * @param {Array} a 目标数组
     * @param {Number} need 需要的最小长度
     */
    private static function ensureCapacity(a:Array, need:Number):Void {
        if (a.length < need) a.length = need;
    }

    /**
     * 索引排序比较函数：按 _xMin 升序
     */
    private static function cmpIdxByXMin(a:Number, b:Number):Number {
        var xa:Number = _xMin[a];
        var xb:Number = _xMin[b];
        if (xa < xb) return -1;
        if (xa > xb) return 1;
        return 0;
    }

    /**
     * 稳定插入排序：对 idx[0..len-1] 按 _xMin 升序进行稳定排序
     * 使用 '>' 比较确保相等键不交换，保证稳定性
     */
    private static function stableInsertionSortByXMin(idx:Array, len:Number):Void {
        var i:Number, j:Number, key:Number, keyX:Number;
        for (i = 1; i < len; i++) {
            key = idx[i];
            keyX = _xMin[key];
            j = i - 1;
            while (j >= 0 && _xMin[idx[j]] > keyX) {
                idx[j + 1] = idx[j];
                j--;
            }
            idx[j + 1] = key;
        }
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
        // 清空队列和缓存
        queue.length = 0;
        _frameEnqueueCount = 0;

        // 清空 SoA 缓存元信息
        _soaLen = 0;
        _soaPrepared = false;

        // 清空并行数组，释放所有引用避免悬挂
        _xMin.length = _xMax.length = _yMin.length = _yMax.length = 0;
        _shootZ.length = _zRange.length = _dirCode.length = 0;
        _isEnemy.length = _isBounce.length = _isPowerful.length = 0;
        _shooter.length = _reqRef.length = 0;

        // 同步清空后备缓冲与复用索引
        _xMinB.length = _xMaxB.length = _yMinB.length = _yMaxB.length = 0;
        _shootZB.length = _zRangeB.length = _dirCodeB.length = 0;
        _isEnemyB.length = _isBounceB.length = _isPowerfulB.length = 0;
        _shooterB.length = _reqRefB.length = 0;
        _idx.length = 0;

        return true;
    }

    // ========================================================================
    // 消弹请求入队方法
    // ========================================================================

    /**
     * 将消弹请求加入队列
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
        if (request && request.区域定位area) {
            queue.push(request);
            // 帧级活跃度计数：供 hasActive() 查询
            _frameEnqueueCount++;
            // 任意入队都会使 SoA 缓存失效（等待下次显式 prepare）
            _soaPrepared = false;
        }
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
     * 构建并行数组（SoA）区域缓存，按 xMin 有序
     * - 输入：gameWorld（坐标换算基准）
     * - 输出：内部并行数组 _xMin/_xMax/_yMin/_yMax 等及 _soaLen
     * - 构建后立即消费队列，避免累积和重复处理
     *
     * 返回：是否成功生成有效缓存（当队列为空时返回 false）
     */
    public static function prepareAreaCache(gameWorld:MovieClip):Boolean {
        var n:Number = queue.length;
        _soaLen = 0;
        _soaPrepared = false;

        if (!gameWorld || n == 0) {
            return false;
        }

        // 先将数据填充到并行数组中（未排序）
        // 为了保证后续重排高效，使用索引数组进行排序然后一次性重排
        var i:Number;
        // 复用索引数组，避免每帧分配
        _idx.length = n;
        var idx:Array = _idx;

        // 统一扩容：为“活动缓冲”（前台数组）和索引在进入填充前做容量保证
        // 只增不减，避免填充阶段的隐式扩容成本
        ensureCapacity(_xMin, n); ensureCapacity(_xMax, n);
        ensureCapacity(_yMin, n); ensureCapacity(_yMax, n);
        ensureCapacity(_shootZ, n); ensureCapacity(_zRange, n);
        ensureCapacity(_dirCode, n); ensureCapacity(_isEnemy, n);
        ensureCapacity(_isBounce, n); ensureCapacity(_isPowerful, n);
        ensureCapacity(_shooter, n); ensureCapacity(_reqRef, n);

        // 填充阶段
        for (i = 0; i < n; i++) {
            var req:Object = queue[i];
            var area:MovieClip = req.区域定位area;
            if (!area || !area.getRect) continue; // 跳过失效请求

            var R:Object = area.getRect(gameWorld);

            _xMin[_soaLen] = R.xMin;
            _xMax[_soaLen] = R.xMax;
            _yMin[_soaLen] = R.yMin;
            _yMax[_soaLen] = R.yMax;

            _shootZ[_soaLen] = req.shootZ;
            _zRange[_soaLen] = req.Z轴攻击范围;

            // 方向编码：左=-1, 右=1, 其他=0
            var d:String = req.消弹方向;
            _dirCode[_soaLen] = (d == "左") ? -1 : ((d == "右") ? 1 : 0);

            _isEnemy[_soaLen] = req.消弹敌我属性;
            _isBounce[_soaLen] = (req.反弹 == true);
            _isPowerful[_soaLen] = (req.强力 == true);
            _shooter[_soaLen] = req.shooter;
            _reqRef[_soaLen] = req;

            idx[_soaLen] = _soaLen;
            _soaLen++;
        }

        if (_soaLen == 0) {
            // 所有请求均无效：消费队列并快速返回，避免后续帧重复 getRect 开销
            queue.length = 0;
            _frameEnqueueCount = 0;
            return false;
        }

        // 极小输入快速路径：1 个元素无需排序与重排
        if (_soaLen == 1) {
            _xMin.length = _xMax.length = _yMin.length = _yMax.length = 1;
            _shootZ.length = _zRange.length = _dirCode.length = 1;
            _isEnemy.length = _isBounce.length = _isPowerful.length = 1;
            _shooter.length = _reqRef.length = 1;
            _soaPrepared = true;
            queue.length = 0; _frameEnqueueCount = 0;
            return true;
        }

        // 使用稳定插入排序，避免 AS2 Array.sort 不稳定带来的潜在顺序扰动
        idx.length = _soaLen;
        stableInsertionSortByXMin(idx, _soaLen);

        // 重排到后备数组并交换引用（双缓冲；单循环写入，提高局部性）
        var t:Array;
        var j:Number;

        // 准备本地别名，减少属性查找成本
        ensureCapacity(_xMinB, _soaLen); ensureCapacity(_xMaxB, _soaLen);
        ensureCapacity(_yMinB, _soaLen); ensureCapacity(_yMaxB, _soaLen);
        ensureCapacity(_shootZB, _soaLen); ensureCapacity(_zRangeB, _soaLen);
        ensureCapacity(_dirCodeB, _soaLen); ensureCapacity(_isEnemyB, _soaLen);
        ensureCapacity(_isBounceB, _soaLen); ensureCapacity(_isPowerfulB, _soaLen);
        ensureCapacity(_shooterB, _soaLen); ensureCapacity(_reqRefB, _soaLen);

        var sxMin:Array = _xMin, sxMax:Array = _xMax, syMin:Array = _yMin, syMax:Array = _yMax;
        var sShootZ:Array = _shootZ, sZRange:Array = _zRange, sDir:Array = _dirCode;
        var sEnemy:Array = _isEnemy, sBounce:Array = _isBounce, sPower:Array = _isPowerful;
        var sShooter:Array = _shooter, sReq:Array = _reqRef;

        var dxMin:Array = _xMinB, dxMax:Array = _xMaxB, dyMin:Array = _yMinB, dyMax:Array = _yMaxB;
        var dShootZ:Array = _shootZB, dZRange:Array = _zRangeB, dDir:Array = _dirCodeB;
        var dEnemy:Array = _isEnemyB, dBounce:Array = _isBounceB, dPower:Array = _isPowerfulB;
        var dShooter:Array = _shooterB, dReq:Array = _reqRefB;

        for (j = 0; j < _soaLen; j++) {
            var k:Number = idx[j];
            dxMin[j] = sxMin[k];
            dxMax[j] = sxMax[k];
            dyMin[j] = syMin[k];
            dyMax[j] = syMax[k];

            dShootZ[j] = sShootZ[k];
            dZRange[j] = sZRange[k];
            dDir[j] = sDir[k];
            dEnemy[j] = sEnemy[k];
            dBounce[j] = sBounce[k];
            dPower[j] = sPower[k];
            dShooter[j] = sShooter[k];
            dReq[j] = sReq[k];
        }

        // 交换前后缓冲并裁剪有效长度
        t = _xMin; _xMin = _xMinB; _xMinB = t; _xMin.length = _soaLen;
        t = _xMax; _xMax = _xMaxB; _xMaxB = t; _xMax.length = _soaLen;
        t = _yMin; _yMin = _yMinB; _yMinB = t; _yMin.length = _soaLen;
        t = _yMax; _yMax = _yMaxB; _yMaxB = t; _yMax.length = _soaLen;

        t = _shootZ; _shootZ = _shootZB; _shootZB = t; _shootZ.length = _soaLen;
        t = _zRange; _zRange = _zRangeB; _zRangeB = t; _zRange.length = _soaLen;
        t = _dirCode; _dirCode = _dirCodeB; _dirCodeB = t; _dirCode.length = _soaLen;
        t = _isEnemy; _isEnemy = _isEnemyB; _isEnemyB = t; _isEnemy.length = _soaLen;
        t = _isBounce; _isBounce = _isBounceB; _isBounceB = t; _isBounce.length = _soaLen;
        t = _isPowerful; _isPowerful = _isPowerfulB; _isPowerfulB = t; _isPowerful.length = _soaLen;
        t = _shooter; _shooter = _shooterB; _shooterB = t; _shooter.length = _soaLen;
        t = _reqRef; _reqRef = _reqRefB; _reqRefB = t; _reqRef.length = _soaLen;

        _soaPrepared = true;
        // 一体化路径：构建后即消费，避免队列累积&重复处理
        queue.length = 0;
        _frameEnqueueCount = 0;
        return true;
    }

    /**
     * 获取已准备好的 SoA 区域缓存的只读视图（引用）
     * - 不复制数组：返回内部数组引用用于零拷贝访问
     * - 若尚未准备或为空，返回 null
     */
    public static function getAreaCacheRef():Object {
        if (!_soaPrepared || _soaLen == 0) return null;
        return {
            prepared: _soaPrepared,
            length: _soaLen,
            xMin: _xMin,
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
