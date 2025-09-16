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
     * 子弹键缓存
     * 用于避免每帧重复枚举子弹容器
     */
    private static var bulletKeyCache:Array = [];

    /**
     * 是否已初始化
     */
    private static var initialized:Boolean = false;

    /**
     * 未来“多消费者单排序”一体化路径总开关（预留，不改变现状）
     * - 默认 false：沿用旧的事件型处理（本类仍由 EventBus 驱动）
     * - 设为 true：旧路径在 processQueue() 入口短路，避免双重处理
     */
    public static var integratedMode:Boolean = false;

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

        // 订阅帧更新事件
        eventBus.subscribe("frameUpdate", function() {
            BulletCancelQueueProcessor.processQueue();
        }, BulletCancelQueueProcessor);

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
        bulletKeyCache.length = 0;

        // 清空 SoA 缓存元信息（数组保留以复用内存）
        _soaLen = 0;
        _soaPrepared = false;
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
     * - 不清空原队列，不改变旧路径；仅提供未来一体化主循环查询用的数据视图
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
        // 预分配索引数组
        var idx:Array = new Array(n);

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
            return false;
        }

        // 使用索引数组按 xMin 升序排序（自定义比较函数）
        idx.length = _soaLen;
        idx.sort(function(a:Number, b:Number):Number {
            var xa:Number = _xMin[a];
            var xb:Number = _xMin[b];
            if (xa < xb) return -1;
            if (xa > xb) return 1;
            return 0;
        });

        // 重排到新的数组（避免原地交换的复杂度和额外比较）
        var t:Array;
        var j:Number;

        t = new Array(_soaLen); for (j = 0; j < _soaLen; j++) t[j] = _xMin[idx[j]]; _xMin = t;
        t = new Array(_soaLen); for (j = 0; j < _soaLen; j++) t[j] = _xMax[idx[j]]; _xMax = t;
        t = new Array(_soaLen); for (j = 0; j < _soaLen; j++) t[j] = _yMin[idx[j]]; _yMin = t;
        t = new Array(_soaLen); for (j = 0; j < _soaLen; j++) t[j] = _yMax[idx[j]]; _yMax = t;

        t = new Array(_soaLen); for (j = 0; j < _soaLen; j++) t[j] = _shootZ[idx[j]]; _shootZ = t;
        t = new Array(_soaLen); for (j = 0; j < _soaLen; j++) t[j] = _zRange[idx[j]]; _zRange = t;
        t = new Array(_soaLen); for (j = 0; j < _soaLen; j++) t[j] = _dirCode[idx[j]]; _dirCode = t;
        t = new Array(_soaLen); for (j = 0; j < _soaLen; j++) t[j] = _isEnemy[idx[j]]; _isEnemy = t;
        t = new Array(_soaLen); for (j = 0; j < _soaLen; j++) t[j] = _isBounce[idx[j]]; _isBounce = t;
        t = new Array(_soaLen); for (j = 0; j < _soaLen; j++) t[j] = _isPowerful[idx[j]]; _isPowerful = t;
        t = new Array(_soaLen); for (j = 0; j < _soaLen; j++) t[j] = _shooter[idx[j]]; _shooter = t;
        t = new Array(_soaLen); for (j = 0; j < _soaLen; j++) t[j] = _reqRef[idx[j]]; _reqRef = t;

        _soaPrepared = true;
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
    // 核心处理方法：批量消弹判定
    // ========================================================================

    /**
     * 处理消弹队列
     *
     * 这是消弹系统的核心方法，每帧调用一次。
     * 遍历队列中的所有请求，对每个请求进行区域碰撞检测和处理。
     *
     * 【处理流程】
     * 1. 构建子弹键缓存（避免重复枚举）
     * 2. 遍历队列中的每个消弹请求
     * 3. 对每个请求，扫描所有子弹进行碰撞检测
     * 4. 根据模式（反弹/消除）处理命中的子弹
     * 5. 清空队列，准备下一帧
     *
     * 【性能优化】
     * - 使用缓存避免重复枚举
     * - 早期退出减少无效检测
     * - 复用数组对象，零分配策略
     */
    public static function processQueue():Void {
        // 一体化模式启用时：旧事件型路径短路退出（避免双重处理）
        if (integratedMode) {
            return;
        }
        if (_root.暂停) return;

        var gw:MovieClip = _root.gameworld;
        if (!gw) return;

        var 子弹容器:Object = gw.子弹区域;
        if (!子弹容器 || queue.length == 0) return;

        // 每帧仅构建一次子弹 key 列表
        var keys:Array = bulletKeyCache;
        var ki:Number = 0;
        for (var k:String in 子弹容器) {
            keys[ki++] = k;
        }
        keys.length = ki; // 截断到本帧长度

        // ========================================================================
        // 宏定义导入（编译时展开）
        // ========================================================================
        #include "../macros/FLAG_MELEE.as"

        // 逐请求处理（合批）
        var qlen:Number = queue.length;

        for (var qi:Number = 0; qi < qlen; qi++) {
            var req:Object = queue[qi];

            // 局部缓存参数
            var 消弹敌我属性:Boolean = req.消弹敌我属性;
            var 消弹方向:String = req.消弹方向;          // "左"/"右"/null
            var shootZ:Number = req.shootZ;
            var Z轴攻击范围:Number = req.Z轴攻击范围;
            var 区域定位area:MovieClip = req.区域定位area;

            // 若区域已被移除或无 getRect，则跳过该请求
            if (!区域定位area || !区域定位area.getRect) continue;

            // 使用"最终位置"求矩形（gameworld 坐标系）
            var R:Object = 区域定位area.getRect(gw);

            // 扫描子弹（用缓存 keys）
            for (var i:Number = 0; i < ki; i++) {
                var b:MovieClip = 子弹容器[keys[i]];
                if (!b) continue;

                // 早退：Z轴范围 / 近战 / 静止
                var zOff:Number = b.Z轴坐标 - shootZ;
                if ((zOff > Z轴攻击范围 || zOff < -Z轴攻击范围) ||
                    (b.flags & FLAG_MELEE) ||
                    b.xmov == 0) continue;

                // 方向过滤（可选）
                var bdir:String = (b.xmov > 0) ? "右" : "左";
                if (消弹方向 && 消弹方向 != bdir) continue;

                // 只处理"敌对子弹"（同侧跳过）
                if (消弹敌我属性 == b.是否为敌人) continue;

                // 注册点 -> gameworld 坐标
                var pt:Object = {x:0, y:0};
                b.localToGlobal(pt);
                gw.globalToLocal(pt);

                // 点 ∈ 矩形（轴对齐）
                if (pt.x < R.xMin || pt.x > R.xMax ||
                    pt.y < R.yMin || pt.y > R.yMax) continue;

                // 命中处理
                if (req.反弹) {
                    handleBounce(b, req.shooter);
                } else {
                    handleCancel(b, req.强力);
                }
            }
        }

        // 清空队列（复用数组对象，零分配）
        queue.length = 0;
        _frameEnqueueCount = 0;
        _soaLen = 0;
        _soaPrepared = false;
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
    private static function handleBounce(bullet:MovieClip, newShooter:String):Void {
        bullet.发射者名 = newShooter;

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
    }

    /**
     * 处理子弹消除
     *
     * @param {MovieClip} bullet 要消除的子弹
     * @param {Boolean} isPowerful 是否强力消除
     */
    private static function handleCancel(bullet:MovieClip, isPowerful:Boolean):Void {
        #include "../macros/FLAG_PIERCE.as"

        bullet.击中地图 = true;
        EffectSystem.Effect(bullet.击中地图效果, bullet._x, bullet._y);
        bullet.gotoAndPlay("消失");

        if (isPowerful && (bullet.flags & FLAG_PIERCE)) {
            bullet.removeMovieClip();
        }
    }
}
