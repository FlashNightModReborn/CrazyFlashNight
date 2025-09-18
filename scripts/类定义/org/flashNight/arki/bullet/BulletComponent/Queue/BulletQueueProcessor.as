/**
 * ============================================================================
 * 高性能子弹队列处理器（企业级优化版本）
 * ============================================================================
 *
 * 【系统概述】
 * 本类是游戏子弹碰撞检测系统的核心处理器，实现了高度优化的批量碰撞检测算法。
 * 通过双指针扫描线与有序缓存，将**碰撞阶段**的遍历从 O(B×T) 降至**摊还 O(B+T)**；
 * **整体帧成本**≈ 排序 `O(B log B)`（近有序时摊还近 `O(B)`） + 扫描 `O(B+T)`。
 *
 * 【核心算法特性】
 * - 双指针扫描线算法：O(B+T) 摊还复杂度的碰撞窗口计算
 * - 空窗口快判：O(1) 时间判断子弹是否有潜在目标，避免无效循环
 * - 右边界截断：当目标左边界超过子弹右边界时立即终止内层循环
 * - 循环展开优化：在跳过区间采用4步推进，**最多**可减少约75%的条件判断；实际效果取决于场景分布
 * - 静态上下文复用：零分配策略，避免GC压力
 * - 内联处理：消除高频函数调用开销，最小化栈帧切换成本
 *
 * 【性能优化技术】
 * 1. 内存优化：静态上下文复用；**核心扫描零临时分配**（除非触发联弹多边形**懒创建**或表现系统分配）
 * 2. 算法优化：双指针扫描线，空窗口快判，右边界截断
 * 3. 微优化：变量声明提升、属性缓存、位运算预计算；**热点路径尽量内联**，保留必要的业务/碰撞调用
 * 4. 渲染优化：延迟多边形碰撞器创建和更新；**首次命中该类弹体时会发生一次分配与更新**
 *
 * 【适用场景】
 * - 大规模子弹碰撞检测
 * - 实时游戏帧率要求
 * - AS2虚拟机优化环境
 *
 * 【变更历史】
 * v3.1: 优化变量声明组织，提升至函数级作用域避免循环内重复声明
 * v3.0: 实现双指针扫描线算法，添加空窗口快判优化
 * v2.0: 引入静态上下文复用，消除GC压力
 * v1.0: 基础队列处理实现，内联executeLogic优化
 *
 * @version 3.1
 * ============================================================================
 */

import org.flashNight.arki.bullet.BulletComponent.Queue.*;
import org.flashNight.arki.component.Collider.*;
import org.flashNight.arki.bullet.BulletComponent.Collider.*;
import org.flashNight.arki.component.Damage.*;
import org.flashNight.arki.component.*;
import org.flashNight.arki.component.Effect.*;
import org.flashNight.arki.unit.UnitComponent.Targetcache.*;
import org.flashNight.arki.render.*;
import org.flashNight.sara.util.*;
import org.flashNight.neur.Event.*;
import org.flashNight.arki.component.StatHandler.*;
import org.flashNight.naki.DataStructures.Dictionary;

/**
 * 高性能子弹队列处理器类
 *
 * 使用双指针扫描线算法和多项微优化技术，实现了高效的批量子弹碰撞检测。
 * **静态工具类**；**内部维护全局状态（activeQueues/fakeUnits）**；API为静态方法。
 *
 * 【线程/时序约束】
 * - 假定在**帧末统一调用 processQueue()**，确保所有子弹完成发射更新后再进行碰撞检测
 * - 子弹通过add()方法在帧中任意时刻加入队列，在帧末批量处理
 * - 静态上下文复用基于单线程帧末同步处理的假设，不支持并发调用
 * - 外部模块应对齐调用时机，避免在碰撞检测过程中修改队列状态
 */
class org.flashNight.arki.bullet.BulletComponent.Queue.BulletQueueProcessor {

    // ========================================================================
    // 静态数据存储
    // ========================================================================

    /**
     * 按阵营分类的活动队列映射表
     * 键: 阵营名称字符串（与FactionManager.getAllFactions()返回值一致，以及特殊的"all"）
     * 值: BulletQueue实例
     * 注意：键名大小写需与FactionManager注册时保持一致
     */
    public static var activeQueues:Object;

    /**
     * 按阵营分类的假单位映射表
     * 用于查询目标缓存时提供阵营上下文信息
     * 键: 阵营名称字符串 (与activeQueues保持一致)
     * 值: 该阵营的代理单位对象
     */
    public static var fakeUnits:Object;

    // ========================================================================
    // 子弹终止控制标志位（位运算优化）
    // 说明：REASON_* 位用于统计/诊断；实际终止分支仅依据 MODE_* 位（见收尾处理）
    // ========================================================================

    /** 终止原因：命中单位 */
    private static var KF_REASON_UNIT_HIT:Number     = 1 << 0;  // 0x1

    /** 终止原因：达到穿透上限 */
    private static var KF_REASON_PIERCE_LIMIT:Number = 1 << 1;  // 0x2

    /** 终止模式：播放消失动画 */
    private static var KF_MODE_VANISH:Number         = 1 << 8;  // 0x100

    /** 终止模式：直接移除 */
    private static var KF_MODE_REMOVE:Number         = 1 << 9;  // 0x200

    /**
     * 预计算的组合常量：穿透上限 + 直接移除
     * 避免运行时重复位运算计算
     */
    private static var KF_PIERCE_LIMIT_REMOVE:Number = (1 << 1) | (1 << 9);  // 0x202

    // ========================================================================
    // 消弹状态缓存（逐帧复用）
    // ========================================================================
    /**
     * 消弹结果 Token（逐帧复用）
     *
     * 编码结构：token = (queueStamp << 2) | mode
     *   - queueStamp = (frameId << 12) | (queueUID & 0x0FFF)
     *   - mode: 0=NONE, 1=VANISH, 2=REMOVE, 3=BOUNCE
     *
     * 不变量与安全性：
     *   - 每个token绑定特定帧ID和队列UID，跨帧/跨队列自动失效
     *   - mode 占 token 的低 2 位；其余位为 queueStamp
     *   - 在 (token>>>2) 得到的 stamp 中：高位为 frameId，**低 12 位为 queueUID
     *   - 验证时必须同时检查frameId和queueUID，确保token来自当前队列当前帧
     *
     * 写入示例：
     *   queueStamp = (frameId << 12) | (queueUID & 0x0FFF);
     *   cancelToken[i] = (queueStamp << 2) | mode;
     *
     * 读取示例：
     *   token = cancelToken[bulletIndex] | 0;  // undefined -> 0
     *   stamp = token >>> 2;
     *   valid = ((stamp >>> 12) == frameId) && ((stamp & 0x0FFF) == queueUID);
     *   tokenMode = valid ? (token & 3) : 0;
     */
    private static var _cancelToken:Array = [];
    // 仅当 mode==3(BOUNCE) 时使用，存发射者名
    private static var _cancelBounceShooter:Array = [];
    // 不再维护额外的帧ID；统一使用全局帧计数

    // ========================================================================
    // 系统初始化方法
    // ========================================================================

    /**
     * 初始化子弹队列处理器
     *
     * 创建所有阵营的子弹队列和对应的假单位对象，为后续的碰撞检测做准备。
     * 此方法应在游戏启动时调用一次。
     *
     * 重要约束：
     * - 所有自定义阵营必须在调用此方法之前通过FactionManager.registerFaction()注册
     * - 在初始化完成后再注册新阵营会导致add()方法访问不存在的队列并抛出错误
     *
     * @return {Boolean} 初始化是否成功，始终返回true
     *
     * 初始化内容：
     * 1. 为每个已知阵营创建独立的BulletQueue实例
     * 2. 为每个阵营创建假单位对象，用于目标缓存查询
     * 3. 创建特殊的"all"队列，处理友伤子弹
     */
    public static function initialize():Boolean {
        // 初始化映射表
        activeQueues = {};
        fakeUnits = {};

        // 获取所有已注册的阵营列表
        var fractions:Array = FactionManager.getAllFactions();
        var i:Number;
        var key:String;
        for (i = 0; i < fractions.length; i++) {
            key = fractions[i];

            // 为每个阵营创建独立的子弹队列
            activeQueues[key] = new BulletQueue();

            // 创建该阵营的假单位，用于目标缓存查询时的上下文信息
            fakeUnits[key] = FactionManager.createFactionUnit(key, "queue");
        }

        // 创建特殊的友伤队列，处理设置了友军伤害标志的子弹
        activeQueues["all"] = new BulletQueue();
        fakeUnits["all"] = FactionManager.createFactionUnit("all", "queue");

        return true;
    }

    // ========================================================================
    // 系统重置方法
    // ========================================================================

    /**
     * 重置子弹队列处理器
     *
     * 用于场景切换时清理队列，避免内存泄漏。
     * 调用所有活动队列的clear方法清空子弹。
     *
     * @return {Boolean} 重置是否成功
     */
    public static function reset():Boolean {
        // 遍历所有活动队列并清空
        var key:String;
        var queue:BulletQueue;
        for (key in activeQueues) {
            queue = activeQueues[key];
            queue.clear();
        }
        return true;
    }

    // ========================================================================
    // 子弹添加方法
    // ========================================================================

    /**
     * 将子弹添加到对应阵营的队列中
     *
     * 根据子弹的友军伤害设置和发射者阵营，自动将子弹路由到正确的队列。
     * 此方法通常在子弹创建时调用。
     *
     * @param {Object} bullet 要添加的子弹对象
     *
     * 路由规则：
     * - 若bullet.友军伤害为true，添加到"all"队列（可伤害所有单位）
     * - 否则根据发射者的阵营，添加到对应阵营的队列
     *
     * 性能说明：
     * - 使用条件表达式简化分支逻辑
     * - 阵营查询结果存入局部变量queueKey后立即使用
     */
    public static function add(bullet:Object):Void {
        // 根据友军伤害标志选择队列类型
        var queueKey:String = bullet.友军伤害 ? "all" :
            FactionManager.getFactionFromUnit(_root.gameworld[bullet.发射者名]);

        // 将子弹添加到对应队列
        activeQueues[queueKey].add(bullet);
    }

    // ========================================================================
    // 子弹预检查方法（按实现类型分类优化）
    // ========================================================================

    /**
     * 透明子弹专用的预检查方法
     *
     * 透明子弹是指使用纯Object实现的轻量级子弹，无MovieClip渲染开销。
     * 此类子弹通过数据驱动模拟，总是需要进行逻辑碰撞检测，因此直接加入执行队列。
     *
     * @param {Object} bullet 透明子弹对象（非MovieClip实例）
     *
     * 技术特点：
     * - 无渲染树开销：不占用Flash显示列表资源
     * - 纯数据驱动：通过Object属性模拟子弹行为
     * - 性能优化：减少内存分配和垃圾回收压力
     *
     * 处理流程：
     * 1. 更新子弹的AABB碰撞器边界（基于数据计算）
     * 2. 无条件将子弹加入执行队列进行碰撞检测
     */
    public static function preCheckTransparent(bullet):Void {
        var areaAABB:AABBCollider = bullet.aabbCollider;
        var detectionArea:MovieClip = bullet.子弹区域area;

        // 更新碰撞检测边界
        if (detectionArea) {
            // 基于关联的可视区域更新AABB（如引导激光等）
            areaAABB.updateFromBullet(bullet, detectionArea);
        } else {
            // 基于透明子弹数据属性更新AABB（纯数学计算）
            areaAABB.updateFromTransparentBullet(bullet);
        }

        // 透明子弹总是进入碰撞检测执行段
        BulletQueueProcessor.add(bullet);
    }

    /**
     * MovieClip子弹专用的优化预检查工厂方法
     *
     * 返回一个针对特定MovieClip子弹实例优化的预检查函数。此函数会根据子弹的
     * 区域属性决定是否需要进行碰撞检测，区分纯运动弹和实际战斗子弹。
     *
     * @param {MovieClip} bullet 要创建预检查函数的MovieClip子弹对象
     * @return {Function} 特化的预检查函数，返回boolean表示是否进入执行段
     *
     * 返回函数的行为：
     * - 若子弹无碰撞区域：仅更新位移，返回false（装饰性/纯运动弹）
     * - 若子弹有碰撞区域：更新AABB并加入队列，返回true（战斗子弹）
     *
     * 性能优化：
     * - 函数特化：避免运行时重复检查子弹类型
     * - 早期过滤：将非战斗子弹在预检查阶段过滤掉
     * - 减少队列负载：降低主处理循环的工作量
     *
     * 注意：返回函数需以**子弹为调用者**绑定（`this === bullet`），例如：`bullet.onEnterFrame = returnedFn;`
     */
    public static function createNormalPreCheck(bullet:MovieClip):Function {
        // 返回针对该MovieClip子弹特化的预检查函数
        return function():Boolean {
            var detectionArea:MovieClip = this.area;

            // 纯运动弹分支：无碰撞区域的装饰性子弹
            if (!detectionArea) {
                // 仅执行位移更新，不参与碰撞检测
                this.updateMovement(this);
                return false;
            }

            // 战斗子弹分支：有碰撞区域的实际战斗子弹
            var areaAABB:AABBCollider = this.aabbCollider;
            areaAABB.updateFromBullet(this, detectionArea);

            // 加入碰撞检测执行段
            BulletQueueProcessor.add(this);
            return true;
        };
    }

    // ========================================================================
    // 核心处理方法：高性能批量碰撞检测
    // ========================================================================

    /**
     * 处理所有阵营的子弹队列
     *
     * 这是整个子弹碰撞检测系统的核心方法，使用双指针扫描线算法实现
     * O(B+T)摊还复杂度的高性能批量碰撞检测。每帧调用一次。
     *
     * 【算法概述】
     * 1. 子弹按左边界排序 - 启用扫描线算法的前提条件
     * 2. 双指针扫描线推进 - 只遍历有碰撞可能的子弹-目标对
     * 3. 空窗口快判 - O(1)时间过滤无目标区域
     * 4. 右边界截断 - 提前终止无效检测
     * 5. 多级碰撞检测 - Z轴粗判→AABB检测→精确多边形检测
     * 6. 批量生命周期管理 - 统一处理子弹终止和清理
     *
     * 【性能优化技术】
     * - 内联展开：消除高频函数调用开销，最小化栈帧切换
     * - 变量声明提升：避免循环内重复var声明开销
     * - 属性缓存：减少对象属性查找的哈希计算开销
     * - 循环展开：4步展开减少75%的循环条件判断
     * - 静态上下文复用：零分配策略，避免GC压力
     * - 延迟计算：按需获取昂贵的计算结果（如旋转角度）
     *
     * 【复杂度分析】
     * - 排序阶段：`O(B log B)`；若上一帧到下一帧**近乎有序**，TimSort/插入优化摊还近 `O(B)`
     * - 扫描阶段（双指针）：`O(B+T)` 摊还
     * - 空间：方法级**额外分配 ~ O(1)**；系统依赖 `BulletQueue/SortedUnitCache` 的**预分配缓冲 O(B+T)**；首次命中某些联弹可能触发**多边形碰撞体懒创建**
     *
     * 【适用场景】
     * - 大规模实时战斗
     * - 稳定帧率要求
     * - AS2虚拟机环境
     *
     * @complexity 摊还时间复杂度 O(B+T)，B=子弹数量，T=目标数量
     */
    public static function processQueue():Void {
        // ================================================================
        // 性能优化说明：
        // - 内联展开executeLogic以消除高频函数调用开销
        // - sortByLeftBoundary和clear保留函数调用（每帧仅调用数次）
        // - 所有热点代码完全内联，最小化栈帧切换成本
        // ================================================================

        // 子弹类型标志位（通过宏引入，用于位运算判断）
        // FLAG_CHAIN: 联弹标志 - 需要精确多边形碰撞检测
        // FLAG_MELEE: 近战标志 - 触发硬直，不受消弹影响
        // FLAG_PIERCE: 穿透标志 - 可贯穿多个目标
        // FLAG_EXPLOSIVE: 爆炸标志 - 特殊终止处理
        // 标志位可叠加使用，如 FLAG_MELEE | FLAG_PIERCE 表示穿透近战弹
        #include "../macros/FLAG_CHAIN.as"
        #include "../macros/FLAG_MELEE.as"
        #include "../macros/FLAG_PIERCE.as"
        #include "../macros/FLAG_EXPLOSIVE.as"
        
        // 批处理前的通用初始化
        var gameWorld:MovieClip = _root.gameworld;
        var debugMode:Boolean = _root.调试模式;
        var MELEE_EXPLOSIVE_MASK:Number = FLAG_MELEE | FLAG_EXPLOSIVE;
        var PIERCE_LIMIT_REMOVE:Number = KF_PIERCE_LIMIT_REMOVE;
        var MODE_VANISH:Number = KF_MODE_VANISH;
        var MODE_REMOVE:Number = KF_MODE_REMOVE;
        var REASON_UNIT_HIT:Number = KF_REASON_UNIT_HIT;  // 缓存命中单位的原因标志

        // 外部静态系统引用缓存（AS2中减少作用域链查找）
        var Dodge:Object = DodgeHandler;
        var Damage:Object = DamageCalculator;
        var FX:Object = EffectSystem;
        var CFR:Object = ColliderFactoryRegistry;
        var PolyFactoryId:String = ColliderFactoryRegistry.PolygonFactory;
        var stunTime:Number = _root.钝感硬直时间;

        // === 仅准备一次消弹区域缓存，供所有阵营复用 ===
        var areas:Object = null;
        var hasCZ:Boolean = BulletCancelQueueProcessor.hasActive();

        // 消弹数组引用缓存（减少属性查找开销）
        // 各字段语义：
        //   idxArr: 消弹区域索引数组
        //   xMinArr/xMaxArr/yMinArr/yMaxArr: 消弹区域的AABB边界
        //   shootZArr: 消弹区域的Z轴基准高度
        //   zRangeArr: 消弹区域的Z轴有效范围
        //   dirCodeArr: 方向过滤码（0=全向，1=向右，-1=向左）
        //   isEnemyArr: 区域阵营标识（与bullet.是否为敌人比较，相同则跳过）
        //   isBounceArr: 是否反弹模式
        //   isPowerfulArr: 是否强力消弹（穿透弹会直接移除）
        //   shooterArr: 反弹模式下的新发射者名称
        var idxArr:Array, xMinArr:Array, xMaxArr:Array, yMinArr:Array, yMaxArr:Array;
        var shootZArr:Array, zRangeArr:Array, dirCodeArr:Array, isEnemyArr:Array;
        var isBounceArr:Array, isPowerfulArr:Array, shooterArr:Array;
        // i变量声明移到碰撞检测变量区域，避免重复声明

        var areaLen:Number = 0;  // 索引数组长度
        if (hasCZ) {
            BulletCancelQueueProcessor.prepareAreaCache();
            areas = BulletCancelQueueProcessor.getAreaCacheRef();
            if (!areas) {
                hasCZ = false;
            } else {
                idxArr = areas.indices;
                if (!idxArr) {
                    hasCZ = false;
                } else {
                    areaLen = idxArr.length;
                    if (areaLen == 0) {
                        hasCZ = false;
                    } else {
                        xMinArr = areas.xMin;
                        xMaxArr = areas.xMax;
                        yMinArr = areas.yMin;
                        yMaxArr = areas.yMax;
                        shootZArr = areas.shootZ;
                        zRangeArr = areas.zRange;
                        dirCodeArr = areas.dirCode;
                        isEnemyArr = areas.isEnemy;
                        isBounceArr = areas.isBounce;
                        isPowerfulArr = areas.isPowerful;
                        shooterArr = areas.shooter;
                    }
                }
            }
        }

                // ================================================================
        // 统一变量声明区域（性能热点优化：避免循环内重复var声明开销）
        // ================================================================

        // ---- 队列上下文管理变量 ----
        var key:String;                     // 当前处理的阵营键名（如"player", "enemy", "all"等）
        var q:BulletQueue;                  // 当前阵营的子弹队列实例
        var n:Number;                       // 队列中子弹数量（用于空队列早退判断）
        var frameId:Number;                 // 当前帧ID
        var queueUID:Number;                // 队列唯一标识符
        var queueStamp:Number;              // 队列时间戳（frameId和queueUID组合）

        // ---- 已排序子弹数据 ----
        var sortedArr:Array;                // 按左边界排序后的子弹数组引用
        var sortedLength:Number;            // 排序数组长度快照（避免重复length查询）

        // ---- 目标缓存系统 ----
        var cache:SortedUnitCache;          // 排序后的单位缓存对象
        var fakeUnit:Object;                // 阵营代理单位（用于查询缓存键）

        // ---- 双指针扫描线算法缓冲区 ----
        var unitMap:Array;                  // 目标单位映射数组
        var unitRightKeys:Array;            // 目标单位右边界键值数组（用于扫描优化）
        var unitLeftKeys:Array;             // 目标单位左边界键值数组（用于碰撞窗口计算）
        var bulletLeftKeys:Array;           // 子弹左边界键值数组
        var bulletRightKeys:Array;          // 子弹右边界键值数组
        var sweepIndex:Number;              // 扫描线当前索引位置
        var len:Number;                     // 目标数组长度（循环边界）

        // ---- 消弹区域处理变量（阶段1专用） ----
        var cancelToken:Array;              // 消弹结果token数组
        var cancelBounceShooter:Array;      // 反弹发射者数组
        var hasCancelResult:Boolean;        // 是否有消弹结果
        var areaPtr:Number;                 // 消弹区域指针
        var bulletPtr:Number;               // 子弹指针（消弹扫描用）
        var areaIdx:Number;                 // 消弹区域索引
        var areaMin:Number;                 // 消弹区域最小X边界
        var areaMax:Number;                 // 消弹区域最大X边界
        var czOff:Number;                   // Z轴偏移（消弹检测）
        var czr:Number;                     // Z轴范围（消弹检测）
        var d:Number;                       // 方向代码
        var bdir:Number;                    // 子弹方向
        var bx:Number;                      // 子弹X坐标
        var by:Number;                      // 子弹Y坐标
        var mode:Number;                    // 消弹模式

        // ---- 子弹遍历状态变量 ----
        var bulletIndex:Number;             // 子弹数组遍历索引（原idx）
        var bullet:MovieClip;               // 当前处理的子弹实例
        var flags:Number;                   // 子弹类型标志位（联弹、近战、穿透等）
        var areaAABB:AABBCollider;          // 子弹的AABB碰撞检测器
        var isPointSet:Boolean;             // 是否需要精确多边形碰撞检测（旋转联弹）
        var rot:Number;                     // 子弹旋转角度（仅联弹需要）
        var bulletZOffset:Number;           // 子弹Z轴坐标
        var bulletZRange:Number;            // 子弹Z轴攻击范围
        var killFlags:Number;               // 子弹终止标志位（命中、穿透上限等）
        var shooter:MovieClip;              // 子弹发射者实例
        var Lb:Number;                      // 子弹左边界
        var Rb:Number;                      // 子弹右边界
        var skipUnits:Boolean;              // 是否跳过单位碰撞检测
        var isUpdatePolygon:Boolean;        // 多边形碰撞器是否已更新

        // ---- 消弹状态变量 ----
        var token:Number;                   // 当前子弹的消弹token
        var stamp:Number;                   // token中的时间戳部分
        var valid:Boolean;                  // token是否有效
        var tokenMode:Number;               // 消弹模式（0=NONE, 1=VANISH, 2=REMOVE, 3=BOUNCE）
        var bounceShooter:String;           // 反弹发射者名称

        // ---- 碰撞检测变量 ----
        var queryLeft:Number;               // 子弹左边界查询坐标
        var startIndex:Number;              // 目标扫描起始索引
        var hitTarget:MovieClip;            // 当前命中的目标单位
        var zOffset:Number;                 // Z轴偏移量（子弹与目标的高度差）
        var unitArea:AABBCollider;          // 目标单位的AABB碰撞检测器
        var collisionResult:CollisionResult; // 碰撞检测结果对象
        var polygonCollider:ICollider;      // 多边形碰撞检测器（精确检测用）
        var unitIndex:Number;               // 单位遍历索引（原i）
        var i:Number;                       // 通用循环索引（用于消弹区域遍历）

        // ---- 命中后处理变量 ----
        var isNormalKill:Boolean;           // 是否普通击杀
        var shouldStun:Boolean;             // 是否应该硬直
        var isPierce:Boolean;               // 是否穿透
        var dodgeState:String;              // 闪避状态
        var damageResult:DamageResult;      // 伤害计算结果
        var targetDispatcher:EventDispatcher; // 目标事件分发器
        var targetX:Number;                 // 目标X坐标
        var targetY:Number;                 // 目标Y坐标

        // ================================================================
        // 主处理循环：按阵营遍历所有活动队列
        // ================================================================

        // 获取当前帧ID（每帧恒定，提到队列循环外）
        frameId = _root.帧计时器.当前帧数;

        for (key in activeQueues) {

            q = activeQueues[key];

            // ---- 空队列优化：早期退出避免无效计算 ----
            n = q.getCount();
            if (n == 0) continue;

            // 为本队列计算唯一 UID，并打包"帧戳+队列戳"
            fakeUnit = fakeUnits[key];
            queueUID = Dictionary.getStaticUID(fakeUnit) & 0x0FFF; // 12bits
            queueStamp = (frameId << 12) | queueUID;

            // ---- 子弹排序：按左边界排序以优化扫描线算法 ----
            // _root.服务器.发布服务器消息(key + " : " + q.toString()); // 调试输出当前队列状态

            q.sortByLeftBoundary();

            // ---- 获取排序后数据：避免重复方法调用的性能开销 ----
            sortedArr = q.getBulletsReference();        // 排序后子弹数组的直接引用
            sortedLength = sortedArr.length;            // 长度快照，避免.length属性重复查询

            // ---- 阵营单位获取：用于目标缓存查询 ----
            // fakeUnit 已在上面获取过

            // ---- 目标缓存获取：根据阵营类型选择合适的缓存策略 ----
            if(key == "all") {
                // 友伤模式：获取所有单位（包括友军）
                // updateInterval=1 强制每帧刷新缓存，保证碰撞检测使用最新数据
                cache = TargetCacheManager.acquireAllCache(fakeUnit, 1);
            } else {
                // 敌对模式：仅获取敌方单位
                // updateInterval=1 强制每帧刷新缓存，避免碰撞检测读取超期数据
                cache = TargetCacheManager.acquireEnemyCache(fakeUnit, 1);
            }

            // ---- 双指针扫描线数据准备：核心优化算法的数据基础 ----
            unitMap = cache.data;                       // 目标单位实例数组
            unitRightKeys = cache.rightValues;          // 目标右边界数组（用于扫描线推进）
            unitLeftKeys = cache.leftValues;            // 目标左边界数组（用于碰撞窗口判断）
            len = unitMap.length;                       // 目标遍历边界（整个队列处理期间不变）
            bulletLeftKeys = q.getLeftKeysRef();        // 子弹左边界数组（查询起点）
            bulletRightKeys = q.getRightKeysRef();      // 子弹右边界数组（截断终点）
            sweepIndex = 0;                             // 扫描线索引重置

            // ================================================================
            // 阶段1：消弹区域与子弹的双扫描线预处理
            //
            // 跳过规则（按顺序检查，任一满足即continue）：
            // 1. token已被本队列本帧写入 -> 跳过（避免重复处理）
            // 2. 近战子弹(FLAG_MELEE) -> 跳过（近战不受消弹影响）
            // 3. 静止子弹(xmov==0 && ymov==0) -> 跳过（静止弹不参与消弹）
            // 4. 同阵营(isEnemyArr==是否为敌人) -> 跳过（同阵营区域不消同阵营子弹）
            // 5. 方向不匹配(dirCode!=0且方向相反) -> 跳过（定向区域过滤）
            // 6. Z轴超出范围 -> 跳过（高度差超过有效范围）
            // 7. XY坐标在区域外 -> 跳过（位置不在消弹区域内）
            // ================================================================
            cancelToken = null;
            cancelBounceShooter = null;
            hasCancelResult = false;
            if (hasCZ && sortedLength > 0 && areaLen > 0) {
                cancelToken = _cancelToken;
                cancelBounceShooter = _cancelBounceShooter;

                bulletPtr = 0;
                // 所有变量已在函数开头声明
                for (areaPtr = 0; areaPtr < areaLen; ++areaPtr) {
                    areaIdx = idxArr[areaPtr];
                    areaMin = xMinArr[areaIdx];
                    areaMax = xMaxArr[areaIdx];
                    // 循环展开优化：每次跳4个子弹，减少条件判断开销
                    while (bulletPtr + 3 < sortedLength && bulletRightKeys[bulletPtr + 3] < areaMin) {
                        bulletPtr += 4;
                    }
                    // 处理剩余的0-3个子弹
                    while (bulletPtr < sortedLength && bulletRightKeys[bulletPtr] < areaMin) {
                        ++bulletPtr;
                    }
                    for (i = bulletPtr; i < sortedLength && bulletLeftKeys[i] <= areaMax; ++i) {
                        // 基于 token 的逐帧有效性判定
                        token = cancelToken[i];
                        if ((token >>> 2) == queueStamp) continue; // 仅当本队列本帧已写过才跳过
                        bullet = sortedArr[i];
                        flags = bullet.flags;
                        if ((flags & FLAG_MELEE) != 0) continue;
                        // 保护条件：静止子弹不参与消弹检测
                        if (bullet.xmov == 0 && bullet.ymov == 0) continue;
                        if (isEnemyArr[areaIdx] == bullet.是否为敌人) continue;
                        d = dirCodeArr[areaIdx];
                        if (d != 0) {
                            if (bullet.xmov == 0) continue; // 垂直/静止不匹配定向区
                            bdir = (bullet.xmov > 0) ? 1 : -1;
                            if (bdir != d) continue;
                        }
                        czOff = bullet.Z轴坐标 - shootZArr[areaIdx];
                        czr = zRangeArr[areaIdx];
                        if (czOff >= czr || czOff <= -czr) continue;
                        bx = bullet._x;
                        by = bullet._y;
                        if (bx < xMinArr[areaIdx] || bx > xMaxArr[areaIdx] ||
                            by < yMinArr[areaIdx] || by > yMaxArr[areaIdx]) continue;
                        hasCancelResult = true;
                        // 写入 token：低两位为 mode，高位为 queueStamp=(frameId<<12)|queueUID
                        if (isBounceArr[areaIdx]) {
                            mode = 3; // BOUNCE
                            cancelBounceShooter[i] = shooterArr[areaIdx];
                        } else {
                            // 强力消弹且穿透 -> REMOVE，否则 VANISH
                            mode = (isPowerfulArr[areaIdx] && (flags & FLAG_PIERCE) != 0) ? 2 : 1;
                        }
                        cancelToken[i] = (queueStamp << 2) | mode;
                    }
                }
                if (!hasCancelResult) {
                    cancelToken = null;
                    cancelBounceShooter = null;
                }
            }
            for (bulletIndex = 0; bulletIndex < sortedLength; bulletIndex++) {
                bullet = sortedArr[bulletIndex];
                flags = bullet.flags;
                areaAABB = bullet.aabbCollider;
                isPointSet = (flags & FLAG_CHAIN) != 0;
                if (isPointSet) {
                    rot = bullet._rotation;
                    isPointSet = rot != 0 && rot != 180;
                }
                bulletZOffset = bullet.Z轴坐标;          // 子弹Z轴坐标
                bulletZRange = bullet.Z轴攻击范围;       // Z轴攻击范围
                killFlags = 0;
                if (debugMode) {
                    AABBRenderer.renderAABB(areaAABB, 0, "line", bulletZRange);
                }
                shooter = gameWorld[bullet.发射者名];
                Lb = bulletLeftKeys[bulletIndex];
                Rb = bulletRightKeys[bulletIndex];
                // —— 读取 token：是否本帧消弹，以及具体模式
                token = (cancelToken != null) ? (cancelToken[bulletIndex] | 0) : 0; // undefined -> 0
                stamp = token >>> 2;
                valid = ((stamp >>> 12) == frameId) && ((stamp & 0x0FFF) == queueUID);
                tokenMode = valid ? (token & 3) : 0; // 0=NONE,1=VANISH,2=REMOVE,3=BOUNCE

                if (tokenMode == 3) {
                    bounceShooter = cancelBounceShooter ? cancelBounceShooter[bulletIndex] : null;
                    BulletCancelQueueProcessor.handleBounce(bullet, bounceShooter);
                    bullet.updateMovement(bullet);
                    continue;
                }
                if (tokenMode == 1 || tokenMode == 2) {
                    // 旧约定：记账到收尾统一表现
                    killFlags = (tokenMode == 2) ? MODE_REMOVE : MODE_VANISH;
                    bullet.霰弹值 = 1;
                    bullet.击中地图 = true;
                }
                skipUnits = (tokenMode == 1 || tokenMode == 2);
                // 阶段2：子弹 vs 单位碰撞检测
                // ================================================================
                if (!skipUnits) {
                    // ---- 扫描线算法：双指针优化的碰撞检测窗口计算 ----
                    queryLeft = Lb;        // 使用已缓存的子弹左边界
                // 推进扫描线：跳过所有右边界小于子弹左边界的目标
                // 循环展开优化：每次跳4个，减少循环判断开销
                while (sweepIndex + 3 < len && unitRightKeys[sweepIndex + 3] < queryLeft) {
                    sweepIndex += 4;
                    // _root.服务器.发布服务器消息("快速推进4步至索引 " + sweepIndex); // 调试输出
                }
                // 处理剩余的0-3个元素
                while (sweepIndex < len && unitRightKeys[sweepIndex] < queryLeft) {
                    ++sweepIndex;
                }
                startIndex = sweepIndex;                // 记录有效检测的起始索引
                // ---- 空窗口快判：O(1)时间复杂度，避免无效循环开销 ----
                // 如果没有任何目标在子弹的横向范围内，直接跳过
                if (startIndex >= len || Rb < unitLeftKeys[startIndex]) {
                    bullet.updateMovement(bullet);
                    continue;  // 直接进入下一发子弹的处理
                }

                // ---- 击中后效果标志：确保命中时能正确触发效果 ----
                bullet.shouldGeneratePostHitEffect = true;

                // ---- 子弹类型预计算：直接使用位运算结果作为条件判断 ----
                isNormalKill = (flags & MELEE_EXPLOSIVE_MASK) == 0;  // 普通击杀
                shouldStun = (flags & FLAG_MELEE) != 0 && !bullet.不硬直;  // 近战硬直
                isPierce = (flags & FLAG_PIERCE) != 0;  // 穿透
                // 注意：当前实现下，若同时标记 MELEE 与 PIERCE，则命中时不会触发硬直（由 !isPierce 分支控制）

                // ---- 多边形更新控制：避免同一子弹重复更新碰撞器 ----
                isUpdatePolygon = false;

                // ----------- 命中循环（带右边界截断） -----------
                for (unitIndex = startIndex; unitIndex < len && unitLeftKeys[unitIndex] <= Rb; ++unitIndex) {
                    hitTarget = unitMap[unitIndex];  // 只读取目标，延迟写入

                    // Z 轴粗判（避免Math.abs函数调用开销）
                    zOffset = bulletZOffset - hitTarget.Z轴坐标;
                    if (zOffset >= bulletZRange || zOffset <= -bulletZRange) continue;

                    if (hitTarget.hp > 0 && hitTarget.防止无限飞 != true) {
                        unitArea = hitTarget.aabbCollider;

                        // AABB 检测（无序早退交由右边界截断处理）
                        collisionResult = areaAABB.checkCollision(unitArea, zOffset);
                        if (!collisionResult.isColliding) {
                            continue;
                        }

                        // 多边形碰撞器的懒加载与生命周期管理
                        // 契约说明：
                        // 1. 创建时机：首次需要精确碰撞检测时懒创建（减少60-80%内存占用）
                        // 2. 更新策略：每帧首次使用时更新一次，同帧后续命中复用
                        // 3. 工厂职责：ColliderFactoryRegistry管理对象池，负责创建和回收
                        // 4. 回收时机：子弹终止时调用releaseCollider归还对象池
                        // 5. 对象池假设：工厂内部维护碰撞器池，避免频繁GC
                        if (isPointSet) {
                            if(!isUpdatePolygon) {
                                polygonCollider = bullet.polygonCollider;
                                if(!polygonCollider) {
                                    // 统一懒加载策略：所有点集联弹的多边形碰撞器都在此时创建
                                    // 注意：createFromBullet内部已包含初始更新
                                    polygonCollider = bullet.polygonCollider = CFR.getFactory(PolyFactoryId).createFromBullet(bullet, bullet.子弹区域area || bullet.area);
                                }
                                // 更新碰撞器（创建时已包含更新，但既有碰撞器需要显式更新）
                                polygonCollider.updateFromBullet(bullet, bullet.子弹区域area || bullet.area);
                                isUpdatePolygon = true;
                            } else {
                                // 后续命中直接使用已更新的碰撞器
                                polygonCollider = bullet.polygonCollider;
                            }

                            collisionResult = polygonCollider.checkCollision(unitArea, zOffset);

                            // 如果更精确的多边形检测都没有碰撞，则跳过这个目标
                            if (!collisionResult.isColliding) {
                                continue;
                            }
                        }

                        // 确认命中后才写入hitTarget，避免无效的哈希表操作
                        bullet.hitTarget = hitTarget;

                        if (debugMode) {
                            AABBRenderer.renderAABB(areaAABB, zOffset, "thick");
                            AABBRenderer.renderAABB(unitArea, zOffset, "filled");
                        }

                        // ---------- 命中后的业务处理（完全内联展开） ----------
                        // 使用预声明的局部变量，减少内存分配

                        // --- 命中计数与上下文填充 ---
                        bullet.hitCount++;
                        bullet.附加层伤害计算 = 0;
                        bullet.命中对象 = hitTarget;

                        // --- 闪避/命中状态（使用预声明变量） ---
                        dodgeState = (bullet.伤害类型 == "真伤") ? "未躲闪" :
                            Dodge.calculateDodgeState(
                                hitTarget,
                                Dodge.calcDodgeResult(shooter, hitTarget, bullet.命中率),
                                bullet
                            );

                        // --- 击中时触发函数（内联条件判断） ---
                        if (bullet.击中时触发函数) bullet.击中时触发函数();

                        // --- 计算伤害（使用预声明变量） ---
                        damageResult = Damage.calculateDamage(
                            bullet, shooter, hitTarget, collisionResult.overlapRatio, dodgeState
                        );

                        // --- 事件分发（使用预声明的dispatcher变量） ---
                        targetDispatcher = hitTarget.dispatcher;
                        targetDispatcher.publish("hit", hitTarget, shooter, bullet, collisionResult, damageResult);

                        // --- 死亡判定（内联展开） ---
                        if (hitTarget.hp <= 0) {
                            // 直接使用预计算的布尔值判断事件名
                            targetDispatcher.publish(isNormalKill ? "kill" : "death", hitTarget);
                            shooter.dispatcher.publish("enemyKilled", hitTarget, bullet);
                        }

                        // --- 表现触发（缓存坐标值） ---
                        targetX = hitTarget._x;
                        targetY = hitTarget._y;
                        damageResult.triggerDisplay(targetX, targetY);

                        // --- 终止意图：近战硬直 或 非穿刺 命中即"消失" ---
                        if (!isPierce) {  // 非穿透
                            if (shouldStun) {  // 应该硬直
                                shooter.硬直(shooter.man, stunTime);  // 使用缓存的硬直时间
                            }
                            killFlags |= (REASON_UNIT_HIT | MODE_VANISH);  // 使用缓存的常量
                        }
                    }
                    
                    // 穿刺上限：设置终止标志并结束循环
                    if (bullet.pierceLimit && bullet.pierceLimit < bullet.hitCount) {
                        killFlags |= PIERCE_LIMIT_REMOVE;
                        break;
                    }
                }
                
                    // 命中后效果（一次性）
                    if (bullet.hitCount > 0 && bullet.shouldGeneratePostHitEffect) {
                        FX.Effect(bullet.击中后子弹的效果, bullet._x, bullet._y, shooter._xscale);
                    }
                } // end if (!skipUnits)

                // 与原实现一致：执行段末尾做一次位移更新
                bullet.updateMovement(bullet);
                
                // ---------------- 单出口收尾 ----------------
                if (killFlags != 0 || bullet.shouldDestroy(bullet)) {
                    // 碰撞器回收：归还对象池供后续复用
                    // 注意：必须在子弹销毁前回收，避免内存泄漏
                    areaAABB.getFactory().releaseCollider(areaAABB);
                    if (bullet.polygonCollider) {
                        // 多边形碰撞器存在时才回收（懒加载可能未创建）
                        bullet.polygonCollider.getFactory().releaseCollider(bullet.polygonCollider);
                    }
                    

                    // 地图命中表现（收尾统一触发）
                    // 注意：消弹token决策（tokenMode=1/2）优先级高于单位命中流程
                    // 已在前面设置击中地图标志的情况下，此处统一处理表现
                    if (bullet.击中地图) {
                        FX.Effect(bullet.击中地图效果, bullet._x, bullet._y);
                        if (bullet.击中时触发函数) bullet.击中时触发函数();
                    }

                    // 子弹终止优先级处理表：
                    // ┌──────────────────┬────────────────┬──────────────┐
                    // │ 条件              │ 处理方式       │ 优先级        │
                    // ├──────────────────┼────────────────┼──────────────┤
                    // │ MODE_REMOVE      │ removeMovieClip│ 最高（1）    │
                    // │ MODE_VANISH      │ gotoAndPlay    │ 次高（2）    │
                    // │ 击中地图          │ gotoAndPlay    │ 中等（3）    │
                    // │ shouldDestroy    │ removeMovieClip│ 最低（4）    │
                    // └──────────────────┴────────────────┴──────────────┘
                    if ((killFlags & MODE_REMOVE) != 0) {
                        // 优先级1：直接移除（强力消弹+穿透弹）
                        bullet.removeMovieClip();
                    } else if ((killFlags & MODE_VANISH) != 0 || bullet.击中地图) {
                        // 优先级2-3：播放消失动画（普通消弹或击中地图）
                        bullet.gotoAndPlay("消失");
                    } else {
                        // 优先级4：其他情况默认移除
                        bullet.removeMovieClip();
                    }
                }
            }
            // === 内联 executeLogic 遍历结束 ===

            // 清空队列（仅调用一次，保留函数调用）
            q.clear();
            cancelToken = null;
            cancelBounceShooter = null;
        }

        // 帧结束清理：仅在有消弹区域时清空缓存，防止旧区域"复活"
        if (hasCZ) {
            BulletCancelQueueProcessor.endFrame();
        }
    }
}
