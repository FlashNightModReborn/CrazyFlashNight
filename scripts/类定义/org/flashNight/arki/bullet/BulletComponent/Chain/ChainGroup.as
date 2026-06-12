// ChainGroup —— 联弹组状态对象（P5 class 化）
//
// 取代帧脚本中的 {} 字面量组对象：非 dynamic 类，全部字段静态声明，
// 经 ChainGroup 类型引用的字段名拼写错误在编译期即报错——这是 class 化的主要目的
// （AVM1 运行时类实例与普通对象同为哈希访问，性能中性；类型注解运行时擦除）。
// 新增字段必须在此声明（sealed 契约）。
//
// 生命周期：每次射击创建一发联弹时 new 一次（约 30 次/秒量级，非每帧路径，
// 按 S02 不池化）；构造函数引用全部参数（DF2 快速路径）。
class org.flashNight.arki.bullet.BulletComponent.Chain.ChainGroup {

    // ---------- 结构/标识 ----------
    // ⚠ tick 的分支判别依据（对象化联弹 = true）。勿改回判 area == null：
    // 悬挂 MC 引用与 null 的 loose equality 在 AVM1 中无可靠语义
    public var isObject:Boolean;
    // MC 壳模式的碰撞代理子剪辑；对象化联弹恒为 null
    public var area:MovieClip;
    // 宿主子弹：MC 壳模式为 MovieClip，对象化模式为纯对象——保持无类型
    public var bullet;
    // 单元体数据对象列表（元素为 ChainUnitData）
    public var 单元体列表:Array;
    // 每帧模拟函数（ChainUnitManager.tick 以 f(group) 形态调用，不依赖 this）
    public var update:Function;
    // 渲染函数引用（联弹系统.渲染组；落组避免每帧链式查找）
    public var render:Function;
    // removeGroup 幂等标记
    public var __removed:Boolean;

    // ---------- 渲染矩阵/显示状态缓存（渲染组维护，碰撞器数据路径复用） ----------
    // 显示状态版本（差量下发 scale/alpha/visible 用）；⚠ 必须初始化为数值 0：
    // undefined++ 得 NaN，而异变量 NaN != NaN 恒 true，差量机制会静默退化为每帧全写
    public var rVer:Number;
    public var rRot:Number;
    public var rXs:Number;
    public var rYs:Number;
    public var rA:Number;
    public var rV:Boolean;
    // 子弹旋转的未缩放三角函数（PolygonCollider OBB 轴展开复用）
    public var rcos:Number;
    public var rsin:Number;
    // 子弹仿射矩阵（含缩放；AABBCollider 复合 zone 仿射复用）
    public var ma:Number;
    public var mb:Number;
    public var mc2:Number;
    public var md:Number;
    // 镜像/负缩放标记（渲染走矩阵复合求显示角的兜底分支）
    public var rMir:Boolean;

    // ---------- 本地碰撞盒（area 矩形等价语义；对象化联弹由碰撞器直接读取） ----------
    public var 盒x:Number;
    public var 盒y:Number;
    public var 盒宽:Number;
    public var 盒高:Number;
    // 联弹area 固有 25×25 形状之半（多边形路径用，不随实例缩放）
    public var 盒固有半宽:Number;
    public var 盒固有半高:Number;
    // 盒尺寸下限（基准 * -2 预计算，更新热路径免每帧乘算）
    public var 最小盒高:Number;
    public var 最小盒宽:Number;

    // ---------- 通用运动 ----------
    public var 运动方向系数:Number;
    public var 余弦值:Number;
    public var 子弹种类:String;
    public var y_基准:Number;
    public var x_基准:Number;

    // ---------- 横向（霰弹齐射） ----------
    public var 衰竭计数器:Number;

    // ---------- 纵向（机枪扫射，逐帧补弹） ----------
    public var count:Number;
    public var 原始坐标x:Number;
    public var 原始坐标y:Number;
    // 补弹率（发/帧，可小数；率<1 经累加器隔帧补弹）
    public var 补弹率:Number;
    public var 补弹累计:Number;

    // ---------- 滑翔 ----------
    public var 下滑速度:Number;

    // ---------- 横向拖尾（轴向螺旋 + 收束 + 伪Z） ----------
    public var 聚拢延迟:Number;
    public var 聚拢时长:Number;
    public var 目标角:Number;
    public var 速度自适应系数:Number;
    public var 尾段延展指数:Number;
    public var 收束残留角:Number;
    public var 螺旋初半径:Number;
    public var 螺旋残留半径:Number;
    public var 螺旋阻尼指数:Number;
    public var 螺旋圈数:Number;
    public var 螺旋相位扰动:Number;
    public var 螺旋背面暗化:Number;
    public var 螺旋近景增粗:Number;
    public var 拖尾扩散增益:Number;

    // @param areaClip  MC 壳模式的 area 子剪辑；对象化联弹传 null
    // @param bulletRef 宿主子弹（MC 或纯对象）
    // @param updateFn  每帧模拟函数
    // @param renderFn  渲染函数（联弹系统.渲染组）
    public function ChainGroup(areaClip:MovieClip, bulletRef, updateFn:Function, renderFn:Function) {
        area = areaClip;
        bullet = bulletRef;
        update = updateFn;
        render = renderFn;
        单元体列表 = [];
        rVer = 0;
    }
}
