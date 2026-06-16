
/* =====================================================================
 * 联弹管理（P2 池化改造版，2026-06-12）
 *
 * 单元体不再作为子弹 MC 的子剪辑创建/销毁，而是统一放入
 * gameworld.子弹区域.联弹单元体层，按 linkage 池化复用（ChainUnitManager）。
 * 每组联弹保存纯数据状态（单元体坐标在【子弹本地坐标系】演算，数学公式与
 * 旧实现逐式等价），由 ChainUnitManager.tick 统一驱动（替代每组一个
 * onEnterFrame 闭包），渲染时经子弹仿射矩阵映射到共享层坐标。
 *
 * area 子剪辑仍是碰撞代理：包围盒（_x/_y/_width/_height）由本地极值按旧公式
 * 更新，碰撞管线（FLAG_CHAIN 多边形碰撞器）零改动。
 * FLA 帧脚本入口（X联弹初始化(this=area) / 联弹消失(this=子弹) /
 * 爆炸联弹消失(this=子弹)）签名保持不变，FLA 零改动。
 *
 * 行为差异备忘（验收口径）：
 * ① 衰竭回收由 splice(j--,1)（旧代码会多跳过一个单元体一帧更新）改为
 *    swap-with-last + pop，不再跳帧，视觉更平滑；
 * ② 消弹直删等未走消失帧的路径，单元体由 tick 兜底回收，存在至多 1 帧视觉残留；
 * ③ 单元体渲染层级在子弹区域顶层（旧实现跟随各自子弹深度）；
 * ④ 爆炸联弹预处理 现在被正确注册（旧文件在 联弹系统={} 重置前赋值，实际未注册）；
 * ⑤ 爆炸联弹消失 的单元体爆炸定位修正为真实单元体位置（旧代码对单元体自身调
 *    localToGlobal 传入其坐标，偏移被叠加两次）。
 *
 * P4 热路径改造（2026-06-12，纪律对齐 agentsDoc/as2-performance.md 与 BulletQueueProcessor）：
 * • 每帧稳态零分配：单元体数据对象池化（ChainUnitManager.acquireUnitData）、
 *   拖尾 trail 环形缓冲（8 槽复用）、坐标散点静态暂存（散点A/B）
 * • 单元体 sin/cos 生成时一次缓存（枪式/滑翔/爆炸 rot 终身不变，拖尾逐帧跟写），
 *   消除热循环每单元体每帧 Math.sin（255ns/次）
 * • 渲染矩阵组级缓存（rcos/rsin/ma..md，仅旋转/缩放变化时重算）+
 *   显示状态版本差量下发（rVer）+ 显示角影子跳写（u.wr）
 * • 每帧不变量循环外上提（H01/H02），Math.max/min/abs/floor 热点按 H13~H15 内联
 * • 纵向补弹率累加器：率可 <1（隔帧补弹），弹链节奏与调度器有效射击间隔对齐（fillrate 普及化）
 * ===================================================================== */

_root.单元体计数 = 0; // 兼容保留（实例命名计数已由 ChainUnitManager 接管）

_root.子弹衰竭计数 = function(子弹:MovieClip) {
    return (子弹.霰弹值 + 子弹.子弹散射度) / 25;// 让衰减在前期更为剧烈
};

if (_root.联弹系统 == undefined) _root.联弹系统 = {};

/* =====================================================================
 * 组构建 / 渲染公共设施
 * ===================================================================== */

// 坐标转换静态暂存对象（localToGlobal/globalToLocal 原地改写，帧内同步复用，零分配）
_root.联弹系统.散点A = {x: 0, y: 0};
_root.联弹系统.散点B = {x: 0, y: 0};

// 创建组对象并注册到统一 tick；clip = area 子剪辑（FLA onClipEvent(load) 传入）
// ChainGroup 为非 dynamic 类（P5 class 化）：字段拼写错误编译期即报错；
// 构造器内置 单元体列表=[] 与 rVer=0（⚠ rVer 必须为数值 0：undefined++ 得 NaN，
// 而异变量 NaN != NaN 恒 true 会使渲染差量下发静默失效）。
// render 落组引用：更新函数以 f(group) 形态调用（CallFunction ~485ns），
// 避免每帧 _root.联弹系统.渲染组(...) 的链式查找+方法调用（~1340ns）
_root.联弹系统.创建组 = function(clip:MovieClip, updateFn:Function):ChainGroup {
    var group:ChainGroup = new ChainGroup(clip, clip._parent, updateFn, _root.联弹系统.渲染组);
    ChainUnitManager.registerGroup(group);
    return group;
};

// 生成一个单元体数据对象（本地坐标原点 + 指定散射角），加入组并返回。
// 数据对象（ChainUnitData，非 dynamic）经 ChainUnitManager 池化复用
// （高射速武器每秒数百次生成，避免逐次分配 + GC）；
// sin/cos 生成时一次求值缓存——横向/纵向/滑翔/爆炸的 rot 终身不变，
// 消除热循环里每单元体每帧的 Math.sin 调用（拖尾会逐帧改 rot，更新时自行跟写缓存）
_root.联弹系统.生成单元体 = function(group:ChainGroup, 旋转:Number):ChainUnitData {
    var u:ChainUnitData = ChainUnitManager.acquireUnitData();
    u.mc = ChainUnitManager.acquireUnit(group.子弹种类);
    u.x = 0;
    u.y = 0;
    u.rot = 旋转;
    var rad:Number = 旋转 * 0.017453292519943295;
    u.sin = Math.sin(rad);
    u.cos = Math.cos(rad);
    // 渲染脏标记复位：池化复用的数据对象会携带前世状态，必须强制首帧全量写入
    u.v = -1;            // 显示状态版本（组版本恒 ≥1，-1 必不相等）
    u.wr = undefined;    // 已写显示角（有限数 != undefined 恒 true，必触发首帧写）
    var l:Array = group.单元体列表;
    l[l.length] = u;     // 索引直写（~135ns）替代 push()（~273ns）
    return u;
};

// 回收组内 index 处单元体（swap-with-last + length 截断，O(1) 删除；MC 与数据对象分别回池）
_root.联弹系统.回收单元体于 = function(group:ChainGroup, index:Number):Void {
    var list:Array = group.单元体列表;
    var u:ChainUnitData = list[index];
    ChainUnitManager.releaseUnit(u.mc);
    ChainUnitManager.releaseUnitData(u);
    var last:Number = list.length - 1;
    if (index < last) list[index] = list[last];
    list.length = last;   // 截断替代 pop()（~69ns vs ~185ns）
};

// 渲染组：本地坐标经子弹仿射矩阵（旋转/缩放/镜像通用）映射到共享层坐标。
// 共享层与子弹同为 子弹区域 的直接子级且自身无变换，
// 故子弹的 _x/_y/_rotation/_xscale/_yscale 即完整映射矩阵，无需 localToGlobal。
//
// 热路径纪律（agentsDoc/as2-performance.md）：
// • 矩阵缓存：cos/sin 仅在子弹 旋转/缩放/透明度/可见性 变化时重算（枪式联弹终身不变），
//   缓存于 group.ma/mb/mc2/md + rcos/rsin——碰撞器数据路径同帧复用（updateFromChainObject）
// • 显示状态版本(rVer)差量下发：缩放/透明度/可见性不变时，每单元体仅 1 次成员读 + 比较，
//   省 4 次 MC 显示属性写（~170ns/次且触发变换脏化）
// • 显示角影子(u.wr)：目标角不变则跳过 _rotation 写（拖尾逐帧改 rot 自然逐帧写，行为不变）
// • _x/_y 每帧必变，无条件写
_root.联弹系统.渲染组 = function(group:ChainGroup):Void {
    var b:MovieClip = group.bullet;
    var bRot:Number = b._rotation;
    var bXs:Number = b._xscale;
    var bYs:Number = b._yscale;
    var bAlpha:Number = b._alpha;
    var bVisible:Boolean = b._visible;

    if (bRot != group.rRot || bXs != group.rXs || bYs != group.rYs
        || bAlpha != group.rA || bVisible != group.rV) {
        group.rRot = bRot;
        group.rXs = bXs;
        group.rYs = bYs;
        group.rA = bAlpha;
        group.rV = bVisible;
        group.rVer++;
        var rad:Number = bRot * 0.017453292519943295;
        var sx:Number = bXs * 0.01;
        var sy:Number = bYs * 0.01;
        var cosR:Number = Math.cos(rad);
        var sinR:Number = Math.sin(rad);
        group.rcos = cosR;
        group.rsin = sinR;
        group.ma = sx * cosR;
        group.mb = sx * sinR;
        group.mc2 = -sy * sinR;
        group.md = sy * cosR;
        group.rMir = !((sx > 0) && (sy > 0));
    }

    var ma:Number = group.ma;
    var mb:Number = group.mb;
    var mc2:Number = group.mc2;
    var md:Number = group.md;
    var bx:Number = b._x;
    var by:Number = b._y;
    var gv:Number = group.rVer;
    var mir:Boolean = group.rMir;
    var list:Array = group.单元体列表;
    var n:Number = list.length;
    var u:ChainUnitData;
    var m:MovieClip;
    var tr:Number;
    for (var i:Number = 0; i < n; i++) {
        u = list[i];
        m = u.mc;
        m._x = bx + ma * u.x + mc2 * u.y;
        m._y = by + mb * u.x + md * u.y;
        if (u.v != gv) {
            // 继承父子弹的缩放/透明度/可见性，复刻旧子剪辑的视觉继承
            // （非等比缩放+子旋转的斜切无法用 _scale/_rotation 表达，取最近似分解；常规子弹为 100% 等比）
            u.v = gv;
            m._xscale = bXs;
            m._yscale = bYs;
            m._alpha = bAlpha;
            m._visible = bVisible;
        }
        if (mir) {
            // 镜像/负缩放兜底：矩阵复合求显示角（u.cos/u.sin 由生成时缓存、拖尾更新时跟写）
            tr = Math.atan2(mb * u.cos + md * u.sin, ma * u.cos + mc2 * u.sin) * 57.29577951308232;
        } else {
            tr = bRot + u.rot;
        }
        if (tr != u.wr) {
            u.wr = tr;
            m._rotation = tr;
        }
    }
};

/* =====================================================================
 * 嵌套子弹属性 / 爆炸联弹预处理
 * ===================================================================== */

_root.嵌套子弹属性初始化 = function(子弹元件:MovieClip,子弹种类:String){
	var 子弹属性 = {
		声音:"",
		霰弹值:子弹元件.霰弹值,
		子弹散射度:1,
		发射效果:"",
		子弹种类:子弹种类 == undefined ? "普通子弹" : 子弹种类,
		子弹威力:子弹元件.子弹威力,
		子弹速度:10,
		Z轴攻击范围:10,
		击中地图效果:"火花",
		发射者:子弹元件.发射者名,
		shootX:子弹元件._x,
		shootY:子弹元件._y,
		shootZ:子弹元件.Z轴坐标,
		击倒率:10,
		击中后子弹的效果:"",
		水平击退速度:NaN,
		垂直击退速度:NaN,
		命中率:NaN,
		固伤:NaN,
		百分比伤害:NaN,
		血量上限击溃:NaN,
		防御粉碎:NaN,
		区域定位area:子弹元件.子弹区域area
	}
	return 子弹属性;
}

// 初始化子弹属性，传入当前 clip 及 "近战联弹" 类型
_root.联弹系统.爆炸联弹预处理 = function(clip:MovieClip):Void {
    clip.子弹属性 = _root.嵌套子弹属性初始化(clip, "近战联弹");

    // 设置爆炸范围
    clip.爆炸范围 = 150;

    // 配置子弹属性：设置子弹速度为 0、击倒率为 1，
    // 同时将 Z 轴攻击范围设为爆炸范围，并取消击中地图效果
    clip.子弹属性.子弹速度 = 0;
    clip.子弹属性.击倒率 = 1;
    clip.子弹属性.Z轴攻击范围 = clip.爆炸范围;
    clip.子弹属性.击中地图效果 = "";

    // 停止当前影片剪辑的播放
    clip.stop();
};

/* =====================================================================
 * 消失路径（FLA 消失帧脚本入口，this=子弹 MC）
 * ===================================================================== */

_root.联弹系统.联弹消失 = function(clip:MovieClip):Void {
    // 停止当前播放，防止继续播放后续帧动画
    clip.stop();
    // 设置标记为 true，表示联弹处于消失状态
    clip.flag = true;

    // 判断条件：如果霰弹值小于等于1，或者已经击中地图，则直接移除该 MovieClip
    if (clip.霰弹值 <= 1 || clip.击中地图) {
        // 先显式回收单元体组，再移除子弹本体
        ChainUnitManager.removeGroupByBullet(clip);
        clip.removeMovieClip();
    } else {
        // 否则，重置到第一帧（组保持活动，单元体继续由统一 tick 驱动）
        clip.gotoAndStop(1);
    }
};

_root.联弹系统.爆炸联弹消失 = function(clip:MovieClip):Void {
    // 停止当前影片剪辑的播放
    clip.stop();

    // 如果未标记过，则执行信息传递和爆炸效果
    if (clip.flag == undefined) {
        // 调整子弹区域的尺寸，加上爆炸范围
        clip.子弹区域area._height = clip.area._height + clip.爆炸范围;
        clip.子弹区域area._width  = clip.area._width + clip.爆炸范围;

        // 移除原联弹碰撞区：area 跨越消失帧，若不移除会被 BulletQueueProcessor
        // 预检查（仅检测 area 属性）再次识别为战斗子弹入队，与新爆炸碰撞重叠重复结算
        clip.area.removeMovieClip();

        // 将子弹属性传递给子弹区域处理函数
        _root.子弹区域shoot传递(clip.子弹属性);

        // 遍历组内所有单元体，在其真实位置生成爆炸效果后整组回收
        var group:ChainGroup = ChainUnitManager.findGroupByBullet(clip);
        if (group != null) {
            var list:Array = group.单元体列表;
            var point:Object = _root.联弹系统.散点A;   // 散点复用（帧内同步），免逐单元体分配
            for (var i:Number = 0; i < list.length; i++) {
                var m:MovieClip = list[i].mc;
                // 共享层坐标 → 全局 → gameworld 坐标
                point.x = m._x;
                point.y = m._y;
                m._parent.localToGlobal(point);
                _root.gameworld.globalToLocal(point);

                var 爆炸:MovieClip = _root.gameworld.attachMovie("联弹爆炸", "explosion" + i, _root.gameworld.getNextHighestDepth());
                爆炸._x = point.x;
                爆炸._y = point.y;
                // 纳入深度管理器，正确参与 Y 排序
                DepthManager.instance.updateDepth(爆炸, point.y);
            }
            ChainUnitManager.removeGroup(group);
        }
        // 标记处理完毕
        clip.flag = true;
    } else {
        // 如果已处理过，回收残余组并移除影片剪辑
        ChainUnitManager.removeGroupByBullet(clip);
        clip.removeMovieClip();
    }
};

/* =====================================================================
 * 横向联弹（霰弹枪式齐射）
 * ===================================================================== */

_root.联弹系统.横向联弹更新 = function(group:ChainGroup):Void {
    var parentMC:MovieClip = group.bullet;
    var list:Array = group.单元体列表;

    // 每帧不变量上提（H01/H02）；衰竭计数内联（原 _root.子弹衰竭计数，省每帧一次函数调用）
    var sv:Number = parentMC.霰弹值;
    var sv0:Number = sv;
    var 衰竭:Number = group.衰竭计数器 + (sv + parentMC.子弹散射度) / 25;
    group.衰竭计数器 = 衰竭;
    var A:Number = parentMC.xmov * group.运动方向系数;   // 带方向轴速；u.sin 为生成时缓存
    var cosV:Number = group.余弦值;
    var py:Number = parentMC._y;
    var hitZ:Number = parentMC.Z轴坐标;
    var thr:Number = -sv;
    var y_min:Number = Infinity;
    var y_max:Number = -Infinity;
    var len:Number = list.length;
    var u:ChainUnitData;
    var uy:Number;

    // 倒序遍历，便于 O(1) swap + 截断安全删除（回收内联：MC 与数据对象分别回池）
    for (var j:Number = len - 1; j >= 0; j--) {
        u = list[j];
        uy = u.y + A * u.sin;
        u.y = uy;

        // 回收条件：衰竭计数到点 或 超出 Z 轴坐标限制；列表至少保留一个单元体
        // （thr 随 sv 递减实时抬升，保持旧实现"回收级联"语义，勿提为循环外常量）
        if ((衰竭 >= thr || uy * cosV + py > hitZ) && len > 1) {
            ChainUnitManager.releaseUnit(u.mc);
            ChainUnitManager.releaseUnitData(u);
            len--;
            if (j < len) list[j] = list[len];
            list.length = len;   // 截断替代 pop()
            sv--;
            thr = -sv;
            continue;
        }

        if (uy > y_max) y_max = uy;
        if (uy < y_min) y_min = uy;
    }
    if (sv != sv0) parentMC.霰弹值 = sv;

    // 更新碰撞盒（本地坐标，公式与旧实现一致）；对象化联弹由碰撞器直接读取组字段
    group.盒y = y_min;
    var h:Number = y_max - y_min;
    var minH:Number = group.最小盒高;
    group.盒高 = (h > minH) ? h : minH;
    var area:MovieClip = group.area;
    if (area != null) {
        area._y = y_min;
        area._height = group.盒高;
    }

    var render:Function = group.render;
    render(group);
};

// 横向联弹组装核心（MC / 对象双模共用；调用前组的 盒x/盒y/盒宽/盒高 须已初始化）
_root.联弹系统.横向联弹组装 = function(group:ChainGroup):Void {
    var b = group.bullet;

    // 初始化衰竭计数器（衰竭值由霰弹值与子弹衰竭计数综合决定）
    group.衰竭计数器 = b.霰弹值 * -1 - _root.子弹衰竭计数(b) * 3;
    // ⚠ 时序考古（勿再改成常量）：AVM1 中 attachMovie 的时间轴子剪辑在首次渲染才实例化，
    // area 的 onClipEvent(load) 实际晚于工厂的 xmov 赋值执行——生产行为就是条件值
    // （左射=-1）。对象路径的组装同样在 xmov 赋值之后调用，两模式一致
    group.运动方向系数 = b.xmov < 0 ? -1 : 1;
    group.y_基准 = group.盒y;
    group.最小盒高 = group.盒y * -2;   // 盒高下限（y_基准*-2），更新热路径免每帧乘算
    group.余弦值 = Math.cos(b._rotation * Math.PI / 180);
    group.子弹种类 = b.子弹种类.split("-")[1];

    // 根据霰弹值生成单元体（flag 已定义时跳过，与旧逻辑一致）
    for (var i:Number = 0; (i < b.霰弹值) && (b.flag == undefined); i++) {
        _root.联弹系统.生成单元体(group, _root.随机偏移(b.子弹散射度));
    }
    _root.联弹系统.渲染组(group);
};

// 从 area 子剪辑捕获碰撞盒初值（MC 模式；载入时即 FLA 授权矩形）
_root.联弹系统.初始化盒 = function(group:ChainGroup, clip:MovieClip):Void {
    group.盒x = clip._x;
    group.盒y = clip._y;
    group.盒宽 = clip._width;
    group.盒高 = clip._height;
    group.盒固有半宽 = 12.5; // 联弹area 固有 25×25 形状之半（多边形路径用）
    group.盒固有半高 = 12.5;
};

_root.联弹系统.横向联弹初始化 = function(clip:MovieClip):Void {
    var group:ChainGroup = _root.联弹系统.创建组(clip, _root.联弹系统.横向联弹更新);
    _root.联弹系统.初始化盒(group, clip);
    _root.联弹系统.横向联弹组装(group);
};

/* =====================================================================
 * 横向拖尾联弹（轴向螺旋 + 柔化收束 + 伪Z透视）
 * 说明：
 *   ① 轴心：每颗子弹维护 centerX/centerY 作为"飞行轴"，沿原弹道推进；
 *      实际绘制位置 = 轴心位置 + (随相位旋转的法向偏移)。
 *   ② 螺旋：半径随生命周期衰减；相位按总圈数推进；附带伪Z（前后景明暗/粗细）。
 *   ③ 拖尾：trail[] 存全局 {x,y,zn}，绘制在 area 上（全局点回 area 本地）。
 *   ④ 收束：尾段延展 + smoothstep + 残留角，避免猛收口。
 * ===================================================================== */

_root.联弹系统.横向拖尾联弹更新 = function(group:ChainGroup):Void {
    var area:MovieClip = group.area;
    var parentMC:MovieClip = group.bullet;
    var list:Array = group.单元体列表;
    var y_min:Number = Infinity;
    var y_max:Number = -Infinity;

    // 清理超额（霰弹值被外部削减时）
    var svCap:Number = parentMC.霰弹值;
    while (list.length > svCap && list.length > 1) {
        _root.联弹系统.回收单元体于(group, list.length - 1);
    }

    // —— 每帧不变量与 Math 引用上提（H01/H11；拖尾逐帧改 rot，trig 无法预缓存，缓存引用减查找税）——
    var msin:Function = Math.sin;
    var mcos:Function = Math.cos;
    var mpow:Function = Math.pow;
    var xm:Number = parentMC.xmov;
    var 系数:Number = group.运动方向系数;
    var spd:Number = (xm < 0) ? -xm : xm;                                            // H14
    var spanScaled:Number = (group.聚拢时长 * (1 + group.速度自适应系数 * spd) + 0.5) | 0;  // H13：非负小值，等价 Math.round
    var invSpan:Number = 1 / spanScaled;
    var delay:Number = group.聚拢延迟;
    var gamma:Number = group.尾段延展指数;
    var target:Number = group.目标角;
    var 残留角:Number = group.收束残留角;
    var 阻尼:Number = group.螺旋阻尼指数;
    var R0:Number = group.螺旋初半径;
    var Rmin:Number = group.螺旋残留半径;
    var 圈数:Number = group.螺旋圈数;
    var cosV:Number = group.余弦值;
    var py:Number = parentMC._y;
    var hitZ:Number = parentMC.Z轴坐标;
    var u:ChainUnitData;

    for (var j:Number = list.length - 1; j >= 0; j--) {
        u = list[j];

        // —— 生命周期进度（0~1） ——
        u.age++;
        var p:Number = (u.age - delay - u.phaseJit) * invSpan;
        if (p < 0) p = 0; else if (p > 1) p = 1;

        // —— 柔化收束（角度）：尾段延展 + smoothstep + 残留角 ——
        var p1:Number = 1 - mpow(1 - p, gamma);
        if (p1 < 0) p1 = 0; else if (p1 > 1) p1 = 1;

        var s:Number = p1 * p1 * (3 - 2 * p1);   // smoothstep
        var wRaw:Number = 1 - s;                 // 1→0
        var dRot:Number = u.initRot - target;
        var delta:Number = ((dRot < 0) ? -dRot : dRot) + 1e-6;                       // H14
        var wMin:Number = 残留角 / delta; if (wMin > 0.5) wMin = 0.5; if (wMin < 0) wMin = 0;
        var w:Number = wMin + (1 - wMin) * wRaw;

        var rot:Number = target + dRot * w;
        u.rot = rot;
        u.convergeT = 1 - w;

        // —— 轴心推进 + 绕轴螺旋偏移（U=(cosθ,sinθ)，N=(-sinθ,cosθ)） ——
        var rad:Number = rot * 0.017453292519943295;
        var Ux:Number = mcos(rad);
        var Uy:Number = msin(rad);
        // 同步跟写单元体角缓存（渲染组镜像兜底分支读 u.cos/u.sin；拖尾逐帧改角必须跟写）
        u.cos = Ux;
        u.sin = Uy;
        u.centerY += xm * Uy * 系数;

        // 半径衰减：R = R_min + (R0 - R_min) * (1 - p)^γ
        var env:Number = mpow(1 - p, 阻尼);
        var R:Number = Rmin + (R0 - Rmin) * env;

        // 相位：整段共转 螺旋圈数 圈；带初相偏移
        var phase:Number = 6.283185307179586 * (圈数 * p) + u.oscPhase0;

        var offsetN:Number = R * mcos(phase); // 平面内的法向投影
        var zDepth:Number  = R * msin(phase); // 伪Z：>0 近景，<0 远景

        // 应用到本地位置：轴心 + 法向偏移
        u.x = u.centerX - Uy * offsetN;
        u.y = u.centerY + Ux * offsetN;

        // —— 回收判断：按"轴心位置"判断，避免法向偏移误触阈值 ——
        if (u.centerY * cosV + py > hitZ && list.length > 1) {
            _root.联弹系统.回收单元体于(group, j);
            parentMC.霰弹值--;
            continue;
        }

        // 统计包围盒（以实际显示位置计算）
        if (u.y < y_min) y_min = u.y;
        if (u.y > y_max) y_max = u.y;

        // —— 采样拖尾（全局坐标 + 归一化伪Z；8 槽环形缓冲复用槽对象，稳态零分配）——
        var head:Number = (u.tHead + 1) & 7;
        u.tHead = head;
        var trail:Array = u.trail;
        var slot:Object = trail[head];
        if (slot == undefined) { slot = {x: 0, y: 0, zn: 0}; trail[head] = slot; }
        slot.x = u.x;
        slot.y = u.y;
        parentMC.localToGlobal(slot);
        slot.zn = (R > 0) ? (zDepth / R) : 0;
        if (u.tLen < 8) u.tLen++;
    }

    /* 绘制拖尾（trail 全局→area 本地 + 基于伪Z调节线宽与透明；散点对象复用，零分配） */
    area.clear();
    area.moveTo(0, 0);

    var lp1:Object = _root.联弹系统.散点A;
    var lp2:Object = _root.联弹系统.散点B;
    var 扩散增益:Number = group.拖尾扩散增益;
    var 近景增粗:Number = group.螺旋近景增粗;
    var 背面暗化:Number = group.螺旋背面暗化;
    var n:Number = list.length;
    for (var i:Number = 0; i < n; i++) {
        u = list[i];
        var tLen:Number = u.tLen;
        if (tLen > 1) {
            var trail2:Array = u.trail;
            var head2:Number = u.tHead;
            // 线宽扩散增益对整条拖尾相同，提到段循环外
            var widen:Number = (u.convergeT != undefined) ? (1.0 + (1.0 - u.convergeT) * 扩散增益) : 1.0;
            for (var t:Number = 0; t < tLen - 1; t++) {
                // 环形索引：t=0 为最新段；负数 & 7 依 Int32 补码正确回卷
                var gp1:Object = trail2[(head2 - t) & 7];
                var gp2:Object = trail2[(head2 - t - 1) & 7];

                lp1.x = gp1.x; lp1.y = gp1.y;
                lp2.x = gp2.x; lp2.y = gp2.y;
                area.globalToLocal(lp1);
                area.globalToLocal(lp2);

                // 渐隐
                var alphaBase:Number = 100 - t * 15;

                // 近/远景调制（zn ∈ [-1,1]；环形槽恒有 zn，无需 undefined 守卫）
                var znAvg:Number = (gp1.zn + gp2.zn) * 0.5;
                if (znAvg > 1) znAvg = 1; else if (znAvg < -1) znAvg = -1;

                // 线宽：基础 ×（扩散增益）×（近景增粗）
                var baseW:Number = 2.5 - t * 0.3; if (baseW < 0.5) baseW = 0.5;
                var nearGain:Number = 1 + 近景增粗 * ((znAvg > 0) ? znAvg : 0);
                var width:Number = baseW * widen * nearGain;

                // 透明：远景暗化
                var farFade:Number = 1 - 背面暗化 * ((znAvg < 0) ? -znAvg : 0);

                area.lineStyle(width, 0xFFFFFF, alphaBase * farFade);
                area.moveTo(lp1.x, lp1.y);
                area.lineTo(lp2.x, lp2.y);
            }
        }
    }

    /* 更新碰撞箱 */
    area._y = y_min;
    var h:Number = y_max - y_min;
    var minH:Number = group.最小盒高;
    area._height = (h > minH) ? h : minH;

    var render:Function = group.render;
    render(group);
};

_root.联弹系统.横向拖尾联弹初始化 = function (clip:MovieClip):Void
{
    var group:ChainGroup = _root.联弹系统.创建组(clip, _root.联弹系统.横向拖尾联弹更新);

    /* ---------- ① 基础字段 ---------- */
    group.运动方向系数     = (clip._parent.xmov < 0) ? -1 : 1;
    group.y_基准           = clip._y;
    group.最小盒高         = clip._y * -2;   // 盒高下限，更新热路径免每帧乘算
    group.余弦值           = Math.cos(clip._parent._rotation * Math.PI / 180);
    group.子弹种类         = String(clip._parent.子弹种类).split("-")[1];

    // —— 角度收束参数（可被 clip._parent 覆盖）——
    group.聚拢延迟         = (clip._parent.聚拢延迟 != undefined) ? clip._parent.聚拢延迟 : 3;     // 帧
    group.聚拢时长         = (clip._parent.聚拢时长 != undefined) ? clip._parent.聚拢时长 : 18;    // 帧（偏慢更柔）
    group.目标角           = (clip._parent.聚拢目标角 != undefined) ? clip._parent.聚拢目标角 : 0;  // °
    group.速度自适应系数   = (clip._parent.聚拢速度自适应系数 != undefined) ? clip._parent.聚拢速度自适应系数 : 0.010;

    // —— 尾段柔化参数 ——
    group.尾段延展指数     = (clip._parent.尾段延展指数 != undefined) ? clip._parent.尾段延展指数 : 2.5;
    group.收束残留角       = (clip._parent.收束残留角 != undefined) ? clip._parent.收束残留角 : 1.2;

    // —— 螺旋（绕轴）参数 ——
    group.螺旋初半径       = (clip._parent.螺旋初半径 != undefined) ? clip._parent.螺旋初半径 : 10;
    group.螺旋残留半径     = (clip._parent.螺旋残留半径 != undefined) ? clip._parent.螺旋残留半径 : 0;
    group.螺旋阻尼指数     = (clip._parent.螺旋阻尼指数 != undefined) ? clip._parent.螺旋阻尼指数 : 1.6;
    group.螺旋圈数         = (clip._parent.螺旋圈数 != undefined) ? clip._parent.螺旋圈数 : 2.0;
    group.螺旋相位扰动     = (clip._parent.螺旋相位扰动 != undefined) ? clip._parent.螺旋相位扰动 : 0.5;
    group.螺旋背面暗化     = (clip._parent.螺旋背面暗化 != undefined) ? clip._parent.螺旋背面暗化 : 0.30;
    group.螺旋近景增粗     = (clip._parent.螺旋近景增粗 != undefined) ? clip._parent.螺旋近景增粗 : 0.25;

    // —— 拖尾宽度增益 ——
    group.拖尾扩散增益     = (clip._parent.拖尾扩散增益 != undefined) ? clip._parent.拖尾扩散增益 : 0.35;

    /* ---------- ② 生成子弹 ---------- */
    for (var i:Number = 0;
         (i < clip._parent.霰弹值) && (clip._parent.flag == undefined);
         i++)
    {
        var u:ChainUnitData = _root.联弹系统.生成单元体(group, _root.随机偏移(clip._parent.子弹散射度));

        // —— 生命周期/收束状态 ——
        u.initRot   = u.rot;
        u.age       = 0;
        u.phaseJit  = (Math.random() - 0.5) * 4;

        // —— 轴心（飞行轨迹轴体）：沿原弹道推进；实际 x/y = 轴心 + 法向偏移 ——
        u.centerX = 0;
        u.centerY = 0;

        // —— 螺旋相位 ——
        var jitter:Number = (Math.random()*2 - 1) * Math.PI * group.螺旋相位扰动;
        u.oscPhase0 = jitter;

        // 拖尾环形缓冲（8 槽，存全局 {x,y,zn}）：池化复用的数据对象保留槽数组，
        // 仅复位读写指针——槽对象跨生命周期复用，稳态零分配
        if (u.trail == undefined) u.trail = [];
        u.tLen = 0;
        u.tHead = -1;
    }
    _root.联弹系统.渲染组(group);
};

/* =====================================================================
 * 纵向联弹（机枪式扫射，逐帧补弹）
 * ===================================================================== */

_root.联弹系统.纵向联弹更新 = function(group:ChainGroup):Void {
    var area:MovieClip = group.area;
    var parentMC:MovieClip = group.bullet;
    var countTotal:Number = parentMC.霰弹值;
    var A:Number = parentMC.xmov * group.运动方向系数;   // 带方向轴速（X/Y 推进共用；u.sin/u.cos 为生成时缓存）
    var list:Array = group.单元体列表;
    var u:ChainUnitData;
    var y_min:Number = Infinity, y_max:Number = -Infinity;
    var uy:Number, ux:Number;
    var j:Number;

    // 判断是否需要进行X轴更新（即是否还需创建新单元体）
    if (group.count < countTotal) {
        var originalX:Number = group.原始坐标x;
        var originalY:Number = group.原始坐标y;
        var x_min:Number = Infinity;
        var x_max:Number = -Infinity;
        var currentParentX:Number = parentMC._x;
        var currentParentY:Number = parentMC._y;

        // 遍历所有单元体，更新Y、X坐标与范围
        for (j = list.length - 1; j >= 0; j--) {
            u = list[j];
            uy = u.y + A * u.sin;
            ux = u.x + A * u.cos;
            u.y = uy;
            u.x = ux;

            if (uy > y_max) y_max = uy;
            if (uy < y_min) y_min = uy;
            if (ux > x_max) x_max = ux;
            if (ux < x_min) x_min = ux;
        }

        // 计算新单元体坐标（子弹全局位移转换回本地坐标系；
        // 子弹旋转在飞行中可能被运动模块改写，保持逐帧取真值，不读渲染矩阵缓存）
        var globalDeltaX:Number = currentParentX - originalX;
        var globalDeltaY:Number = currentParentY - originalY;
        var rad:Number = parentMC._rotation * 0.017453292519943295;
        var cosVal:Number = Math.cos(rad);
        var sinVal:Number = Math.sin(rad);
        var localDeltaX:Number = globalDeltaX * cosVal + globalDeltaY * sinVal;
        var localDeltaY:Number = -globalDeltaX * sinVal + globalDeltaY * cosVal;

        // —— 补弹累加器（整数 Bresenham：acc += 分子，每满一个分母出一发）——
        // 率<1 = 隔帧补弹（2,3,2,… 不均匀帧分布是预期行为，长期均值精确等于分子/分母）；
        // 率>1 = 帧内多发沿当帧位移分数插值（插值=(s+1)/n 恒 ≤1，不会超出当帧位移）。
        // 全程整数算术：分母个 tick 内恰好补完，无浮点漂移（勿改回浮点率累加，见组装处注释）
        // ⚠ 落点不乘 运动方向系数：localDelta 本身已是带方向的本地位移
        // （localDeltaX = 当帧位移在枪管轴上的投影，任意射角恒为 +|v|），
        // 再乘系数会使左射落点反向展开——新单元体出生在枪口后方（枪管内）。
        // 旧 MC 实现靠"原始坐标捕获于一帧位移后"的时序巧合补偿了该反向；
        // 对象路径在工厂内捕获（位移前），此处采用方向无关的物理正确插值
        var acc:Number = group.补弹累计 + group.补弹分子;
        var D:Number = group.补弹分母;
        var n:Number = (acc / D) | 0;        // 整数对整数，floor 精确（H13 前提满足）
        var remain:Number = countTotal - group.count;
        if (n > remain) n = remain;
        if (n > 0) {
            var 生成:Function = _root.联弹系统.生成单元体;   // 纯函数，不依赖 this
            var rnd:Function = _root.随机偏移;               // Delegate 闭包自携 this
            var 散射度:Number = parentMC.子弹散射度;
            var invN:Number = 1 / n;
            for (var s:Number = 0; s < n; s++) {
                u = 生成(group, rnd(散射度));
                ux = localDeltaX * ((s + 1) * invN) + rnd(散射度 + countTotal + group.count);
                uy = localDeltaY * ((s + 1) * invN);
                u.x = ux;
                u.y = uy;

                // 新单元体当帧即纳入包围盒极值，保证首帧可命中
                if (ux > x_max) x_max = ux;
                if (ux < x_min) x_min = ux;
                if (uy > y_max) y_max = uy;
                if (uy < y_min) y_min = uy;

                group.count++;
            }
        }
        group.补弹累计 = acc - n * D;

        // 更新X碰撞盒（含本帧新增单元体）；对象化联弹由碰撞器直接读取组字段
        group.盒x = x_min;
        var w:Number = x_max - x_min;
        var minW:Number = group.最小盒宽;
        group.盒宽 = (w > minW) ? w : minW;
        if (area != null) {
            area._x = x_min;
            area._width = group.盒宽;
        }

        // 重置子弹坐标为原始值（补弹期间子弹锚定枪口，弹链整体由单元体本地坐标推进）
        parentMC._x = originalX;
        parentMC._y = originalY;
    } else {
        // X轴不更新时，沿用当前碰撞盒数据，只更新Y轴
        for (j = list.length - 1; j >= 0; j--) {
            u = list[j];
            uy = u.y + A * u.sin;
            u.y = uy;

            if (uy > y_max) y_max = uy;
            if (uy < y_min) y_min = uy;
        }
    }

    // 始终更新Y轴碰撞盒
    group.盒y = y_min;
    var h:Number = y_max - y_min;
    var minH:Number = group.最小盒高;
    group.盒高 = (h > minH) ? h : minH;
    if (area != null) {
        area._y = y_min;
        area._height = group.盒高;
    }

    var render:Function = group.render;
    render(group);
};

// 纵向联弹组装核心（MC / 对象双模共用；调用前组的 盒x/盒y/盒宽/盒高 须已初始化）
_root.联弹系统.纵向联弹组装 = function(group:ChainGroup):Void {
    var b = group.bullet;

    group.y_基准 = group.盒y;
    group.x_基准 = group.盒x;
    group.最小盒高 = group.盒y * -2;   // 盒高/盒宽下限，更新热路径免每帧乘算
    group.最小盒宽 = group.盒x * -2;
    group.原始坐标x = b._x;
    group.原始坐标y = b._y;
    // ⚠ 时序考古同 横向联弹组装：area 载入晚于 xmov 赋值，生产行为就是条件值，勿改常量
    group.运动方向系数 = b.xmov < 0 ? -1 : 1;
    group.子弹种类 = b.子弹种类.split("-")[1];
    group.count = 1;

    // 补弹率（分数 分子/分母，整数 Bresenham 误差累加）：显式推参（每帧补弹数）优先；
    // 其次由实际发射间隔（发射间隔毫秒，WeaponFireCore.executeShot 对全武器盖戳，
    // 含枪械师点按/连按修正与配件改装后的运行时射速）推导 (霰弹值-1)/间隔帧数：
    // 高射速（间隔<1帧，如 XM214）一帧补完；低射速（如磁稳贯穿弹改装后 interval 300ms+）
    // 隔帧补弹，弹链节奏与调度器有效射击间隔对齐。技能等无间隔戳的直调路径 → 回退每帧 1 发旧行为。
    // ⚠ 必须整数化、禁用浮点率累加（复审发现）：如 4/6 在 double 下累加 6 次可停在
    //   3.999…，|0 截断使最后一发延至下一射击周期之后（split5/interval200ms 等
    //   209 组合扫描中 65 组复现）。整数分子/分母的误差累加精确无漂移；
    //   分母取 Math.ceil(间隔帧数)，与 EnhancedCooldownWheel 的 Never-Early 向上取整
    //   同源同式——在该有效调度间隔的第 D 个更新 tick 补完；同 tick 内事件先后不作保证。
    // ⚠ 守卫必须用 !(x>0) 而非 >=：AVM1 中 undefined>=1 恒为 true（>= 实现为 !(<)，NaN 比较返回 undefined）
    var fillN:Number = 0;
    var fillD:Number = 1;
    var rate:Number = b.每帧补弹数;
    if (rate > 0) {
        // 显式推参（可小数）：向上定点化 N/4096；最小有效正数 1/4096，低于该值仍按 1/4096 执行
        fillN = Math.ceil(rate * 4096);
        fillD = 4096;
    } else {
        var 发射间隔毫秒:Number = b.发射间隔毫秒;
        if (发射间隔毫秒 > 0) {
            fillD = Math.ceil(发射间隔毫秒 / EnhancedCooldownWheel.I().每帧毫秒);
            if (fillD < 1) fillD = 1;
            fillN = b.霰弹值 - 1;
        }
    }
    if (!(fillN > 0)) { fillN = 1; fillD = 1; }   // 无戳/异常值 → 每帧 1 发旧行为
    group.补弹分子 = fillN;
    group.补弹分母 = fillD;
    group.补弹累计 = 0;

    // 创建第一个单元体
    _root.联弹系统.生成单元体(group, _root.随机偏移(b.子弹散射度));
    _root.联弹系统.渲染组(group);
};

_root.联弹系统.纵向联弹初始化 = function(clip:MovieClip):Void {
    var group:ChainGroup = _root.联弹系统.创建组(clip, _root.联弹系统.纵向联弹更新);
    _root.联弹系统.初始化盒(group, clip);
    _root.联弹系统.纵向联弹组装(group);
};

/* =====================================================================
 * 滑翔联弹（下滑弹道）
 * ===================================================================== */

_root.联弹系统.滑翔联弹更新 = function(group:ChainGroup):Void {
    var area:MovieClip = group.area;
    var parentMC:MovieClip = group.bullet;
    var list:Array = group.单元体列表;
    var y_min:Number = Infinity;
    var y_max:Number = -Infinity;

    // 更新子弹 ymov，使下坠速度渐进（模拟滑翔角时下坠的迟缓）
    var 下滑速度:Number = group.下滑速度;
    var dym:Number = (下滑速度 - parentMC.ymov) * 下滑速度 * 0.05;
    parentMC.ymov += (dym > 0.1) ? dym : 0.1;                            // H15
    // 根据当前的 xmov 与 ymov 更新子弹旋转角度
    var rotDeg:Number = Math.atan2(parentMC.ymov, parentMC.xmov) * 57.29577951308232;
    parentMC._rotation = rotDeg;

    // 每帧不变量上提：旧实现的 Math.cos(子弹旋转) 在循环内逐单元体重算，本帧内恒定
    var A:Number = parentMC.xmov * group.运动方向系数;
    var cosTilt:Number = Math.cos(rotDeg * 0.017453292519943295);
    var py:Number = parentMC._y;
    var hitZ:Number = parentMC.Z轴坐标;
    var u:ChainUnitData;
    var uy:Number;

    for (var j:Number = list.length - 1; j >= 0; j--) {
        u = list[j];
        uy = u.y + A * u.sin;
        u.y = uy;

        // 超出 Z 轴坐标限制时回收（列表至少保留一个单元体）
        if (uy * cosTilt + py > hitZ && list.length > 1) {
            _root.联弹系统.回收单元体于(group, j);
            parentMC.霰弹值--;
            continue;
        }

        if (uy > y_max) y_max = uy;
        if (uy < y_min) y_min = uy;
    }
    area._y = y_min;
    var h:Number = y_max - y_min;
    var minH:Number = group.最小盒高;
    area._height = (h > minH) ? h : minH;

    var render:Function = group.render;
    render(group);
};

_root.联弹系统.滑翔联弹初始化 = function(clip:MovieClip):Void {
    var group:ChainGroup = _root.联弹系统.创建组(clip, _root.联弹系统.滑翔联弹更新);

    group.y_基准 = clip._y;
    group.最小盒高 = clip._y * -2;
    group.运动方向系数 = clip._parent.xmov < 0 ? -1 : 1;
    // 计算下滑速度，根据子弹散射度与 xmov 绝对值决定
    group.下滑速度 = clip._parent.子弹散射度 * Math.abs(clip._parent.xmov) / 100;
    group.子弹种类 = clip._parent.子弹种类.split("-")[1];

    for (var i:Number = 0; (i < clip._parent.霰弹值) && (clip._parent.flag == undefined); ++i) {
        _root.联弹系统.生成单元体(group, _root.随机偏移(clip._parent.子弹散射度));
    }
    _root.联弹系统.渲染组(group);
};

/* =====================================================================
 * 爆炸联弹（下坠 + 触地转入消失帧逐单元体爆炸）
 * ===================================================================== */

_root.联弹系统.爆炸联弹更新 = function(group:ChainGroup):Void {
    var area:MovieClip = group.area;
    var parentMC:MovieClip = group.bullet;
    var list:Array = group.单元体列表;
    var y_min:Number = Infinity;
    var y_max:Number = -Infinity;

    // 每帧增加子弹垂直速度，模拟下坠加速效果
    parentMC.ymov += 1.2;
    // 根据当前 xmov 和 ymov 计算子弹旋转角度（角度指向速度方向）
    var rotDeg:Number = Math.atan2(parentMC.ymov, parentMC.xmov) * 57.29577951308232;
    parentMC._rotation = rotDeg;

    // 每帧不变量上提：旧实现的 Math.cos(子弹旋转) 在循环内逐单元体重算，本帧内恒定
    var A:Number = parentMC.xmov * group.运动方向系数;
    var cosTilt:Number = Math.cos(rotDeg * 0.017453292519943295);
    var py:Number = parentMC._y;
    var hitZ:Number = parentMC.Z轴坐标;
    var u:ChainUnitData;
    var uy:Number;

    for (var j:Number = list.length - 1; j >= 0; j--) {
        u = list[j];
        uy = u.y + A * u.sin;
        u.y = uy;

        // 超出 Z 轴坐标限制时，通知子弹进入"消失"状态。
        // gotoAndStop 同步执行消失帧脚本（爆炸联弹消失）：area 被移除、单元体
        // 整组回收、本组注销。旧实现由 area.onEnterFrame 驱动，卸载自身即终止
        // 后续生命周期；共享 tick 驱动下无此语义，组失效后必须立即终止本帧更新，
        // 不再触碰已回池的 list 数据对象 / 已移除的 area / 空转渲染
        if (uy * cosTilt + py > hitZ && list.length > 1) {
            parentMC.gotoAndStop("消失");
            if (group.__removed) return;
        }
        if (uy > y_max) y_max = uy;
        if (uy < y_min) y_min = uy;
    }
    area._y = y_min;
    var h:Number = y_max - y_min;
    var minH:Number = group.最小盒高;
    area._height = (h > minH) ? h : minH;

    var render:Function = group.render;
    render(group);
};

_root.联弹系统.爆炸联弹初始化 = function(clip:MovieClip):Void {
    var group:ChainGroup = _root.联弹系统.创建组(clip, _root.联弹系统.爆炸联弹更新);

    group.y_基准 = clip._y;
    group.最小盒高 = clip._y * -2;
    group.运动方向系数 = clip._parent.xmov < 0 ? -1 : 1;
    group.子弹种类 = clip._parent.子弹种类.split("-")[1];

    // 调整子弹垂直移动速度：根据子弹散射度和 xmov 的绝对值
    clip._parent.ymov += clip._parent.子弹散射度 * Math.abs(clip._parent.xmov) / 100;

    for (var i:Number = 0; i < clip._parent.霰弹值; i++) {
        _root.联弹系统.生成单元体(group, _root.随机偏移(clip._parent.子弹散射度));
    }
    _root.联弹系统.渲染组(group);
};

/* =====================================================================
 * 对象化联弹（P3 去影片剪辑化）
 *
 * 注册表声明可对象化的联弹前缀及其 FLA 授权常量（即 area 子剪辑的本地矩形，
 * 源自壳元件中 联弹area 实例矩阵：固有 25×25 形状 × 0.4 缩放 = 10×10；
 * 横向系 tx=-5,ty=-5 → [-5,5]×[-5,5]；纵向系 tx=7,ty=-5 → [7,17]×[-5,5]）。
 *
 * BulletFactory 按本注册表门控：命中前缀 → 创建纯对象子弹（无 MC 壳），
 * 碰撞经 updateFromChainObject 数据路径，击杀经 gotoAndPlay 垫片分发到 对象联弹消失。
 * 删除注册条目即整型回退 MC 壳路径（FLA 元件仍在库中），逐模板可灰度。
 *
 * 暂保留 MC 壳的类型：横向拖尾联弹/横向拖尾追踪联弹（trail 矢量绘制依赖 area 画布）、
 * 滑翔联弹/爆炸联弹（帧标签 + 子弹区域area 联动的死亡行为）。
 * ===================================================================== */

_root.联弹系统.对象化模板 = {};
_root.联弹系统.注册对象化模板 = function(prefix:String, 盒x:Number, 盒y:Number, 盒宽:Number, 盒高:Number, updateFn:Function, assembleFn:Function):Void {
    var tpl:Object = {};
    tpl.盒x = 盒x;
    tpl.盒y = 盒y;
    tpl.盒宽 = 盒宽;
    tpl.盒高 = 盒高;
    tpl.盒固有半宽 = 12.5; // 联弹area 固有 25×25 形状之半（多边形路径用，不随实例缩放）
    tpl.盒固有半高 = 12.5;
    tpl.update = updateFn;
    tpl.assemble = assembleFn;
    _root.联弹系统.对象化模板[prefix] = tpl;
};

// 对象化联弹初始化（由 BulletFactory 在绑定生命周期之前调用——bindCollider 需读取组碰撞盒）
_root.联弹系统.对象联弹初始化 = function(bullet:Object):Void {
    var tpl:Object = _root.联弹系统.对象化模板[bullet.baseAsset];
    var group:ChainGroup = new ChainGroup(null, bullet, tpl.update, _root.联弹系统.渲染组);
    // ⚠ isObject 是 tick 的分支判别依据，勿改回判 area == null：
    // MC 壳组的 area 被直删（REMOVE 消弹/超射程 priority-4）后是悬挂 MC 引用，
    // 其与 null 的 loose equality 在 AVM1 中无可靠语义，误判会绕过 MC 分支的
    // _parent == undefined 兜底回收，产生每帧向碰撞队列泵入死子弹的僵尸组
    group.isObject = true;
    bullet.chainGroup = group;
    group.盒x = tpl.盒x;
    group.盒y = tpl.盒y;
    group.盒宽 = tpl.盒宽;
    group.盒高 = tpl.盒高;
    group.盒固有半宽 = tpl.盒固有半宽;
    group.盒固有半高 = tpl.盒固有半高;
    ChainUnitManager.registerGroup(group);
    tpl.assemble(group);
};

// 对象化联弹消失：复刻 MC 消失帧（联弹消失）语义——
// 霰弹值耗尽或击中地图 → 销毁（removeMovieClip 垫片回收碰撞器与单元体组）；
// 否则仅置 flag，剩余单元体继续由统一 tick 驱动飞行
_root.联弹系统.对象联弹消失 = function(bullet:Object):Void {
    bullet.flag = true;
    if (bullet.霰弹值 <= 1 || bullet.击中地图) {
        bullet.removeMovieClip();
    }
};

// 六个枪式联弹模板全部对象化（横向系=霰弹齐射，纵向系=机枪扫射）
_root.联弹系统.注册对象化模板("横向联弹",     -5, -5, 10, 10, _root.联弹系统.横向联弹更新, _root.联弹系统.横向联弹组装);
_root.联弹系统.注册对象化模板("横向机枪联弹", -5, -5, 10, 10, _root.联弹系统.横向联弹更新, _root.联弹系统.横向联弹组装);
_root.联弹系统.注册对象化模板("横向手枪联弹", -5, -5, 10, 10, _root.联弹系统.横向联弹更新, _root.联弹系统.横向联弹组装);
_root.联弹系统.注册对象化模板("纵向联弹",      7, -5, 10, 10, _root.联弹系统.纵向联弹更新, _root.联弹系统.纵向联弹组装);
_root.联弹系统.注册对象化模板("纵向机枪联弹",  7, -5, 10, 10, _root.联弹系统.纵向联弹更新, _root.联弹系统.纵向联弹组装);
_root.联弹系统.注册对象化模板("纵向手枪联弹",  7, -5, 10, 10, _root.联弹系统.纵向联弹更新, _root.联弹系统.纵向联弹组装);
