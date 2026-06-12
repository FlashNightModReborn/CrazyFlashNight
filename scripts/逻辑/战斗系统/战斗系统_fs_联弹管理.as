import org.flashNight.sara.util.*;
import org.flashNight.arki.spatial.move.*;
import org.flashNight.gesh.depth.*;
import org.flashNight.neur.ScheduleTimer.*;
import org.flashNight.arki.bullet.BulletComponent.Chain.*;

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
 * ===================================================================== */

_root.单元体计数 = 0; // 兼容保留（实例命名计数已由 ChainUnitManager 接管）

_root.子弹衰竭计数 = function(子弹:MovieClip) {
    return (子弹.霰弹值 + 子弹.子弹散射度) / 25;// 让衰减在前期更为剧烈
};

if (_root.联弹系统 == undefined) _root.联弹系统 = {};

/* =====================================================================
 * 组构建 / 渲染公共设施
 * ===================================================================== */

// 创建组对象并注册到统一 tick；clip = area 子剪辑（FLA onClipEvent(load) 传入）
_root.联弹系统.创建组 = function(clip:MovieClip, updateFn:Function):Object {
    var group:Object = {
        area: clip,
        bullet: clip._parent,
        单元体列表: [],
        update: updateFn
    };
    ChainUnitManager.registerGroup(group);
    return group;
};

// 生成一个单元体数据对象（本地坐标原点 + 指定散射角），加入组并返回
_root.联弹系统.生成单元体 = function(group:Object, 旋转:Number):Object {
    var u:Object = {
        mc: ChainUnitManager.acquireUnit(group.子弹种类),
        x: 0,
        y: 0,
        rot: 旋转
    };
    group.单元体列表.push(u);
    return u;
};

// 回收组内 index 处单元体（swap-with-last + pop，O(1) 删除）
_root.联弹系统.回收单元体于 = function(group:Object, index:Number):Void {
    var list:Array = group.单元体列表;
    ChainUnitManager.releaseUnit(list[index].mc);
    var last:Number = list.length - 1;
    if (index < last) list[index] = list[last];
    list.pop();
};

// 渲染组：本地坐标经子弹仿射矩阵（旋转/缩放/镜像通用）映射到共享层坐标。
// 共享层与子弹同为 子弹区域 的直接子级且自身无变换，
// 故子弹的 _x/_y/_rotation/_xscale/_yscale 即完整映射矩阵，无需 localToGlobal。
_root.联弹系统.渲染组 = function(group:Object):Void {
    var b:MovieClip = group.bullet;
    var rad:Number = b._rotation * 0.017453292519943295;
    var sx:Number = b._xscale * 0.01;
    var sy:Number = b._yscale * 0.01;
    var cosR:Number = Math.cos(rad);
    var sinR:Number = Math.sin(rad);
    var ma:Number = sx * cosR;
    var mb:Number = sx * sinR;
    var mc2:Number = -sy * sinR;
    var md:Number = sy * cosR;
    var bx:Number = b._x;
    var by:Number = b._y;
    var bRot:Number = b._rotation;
    var 无镜像:Boolean = (sx > 0) && (sy > 0);
    var list:Array = group.单元体列表;
    for (var i:Number = 0; i < list.length; i++) {
        var u:Object = list[i];
        var m:MovieClip = u.mc;
        m._x = bx + ma * u.x + mc2 * u.y;
        m._y = by + mb * u.x + md * u.y;
        if (无镜像) {
            m._rotation = bRot + u.rot;
        } else {
            // 镜像/负缩放场合用矩阵复合求显示角（常规子弹不镜像，此分支为兜底）
            var ur:Number = u.rot * 0.017453292519943295;
            var cu:Number = Math.cos(ur);
            var su:Number = Math.sin(ur);
            m._rotation = Math.atan2(mb * cu + md * su, ma * cu + mc2 * su) * 57.29577951308232;
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

        // 将子弹属性传递给子弹区域处理函数
        _root.子弹区域shoot传递(clip.子弹属性);

        // 遍历组内所有单元体，在其真实位置生成爆炸效果后整组回收
        var group:Object = ChainUnitManager.findGroupByBullet(clip);
        if (group != null) {
            var list:Array = group.单元体列表;
            for (var i:Number = 0; i < list.length; i++) {
                var m:MovieClip = list[i].mc;
                // 共享层坐标 → 全局 → gameworld 坐标
                var point:Object = { x: m._x, y: m._y };
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

_root.联弹系统.横向联弹更新 = function(group:Object):Void {
    var area:MovieClip = group.area;
    var parentMC:MovieClip = group.bullet;

    // 累加衰竭计数
    group.衰竭计数器 += _root.子弹衰竭计数(parentMC);
    var y_min:Number = Infinity;
    var y_max:Number = -Infinity;
    var list:Array = group.单元体列表;
    var radFactor:Number = Math.PI / 180;

    // 倒序遍历，便于 O(1) 安全删除
    for (var j:Number = list.length - 1; j >= 0; j--) {
        var u:Object = list[j];
        // 根据子弹 xmov、单元体散射角及运动方向系数更新本地 y
        u.y += parentMC.xmov * Math.sin(u.rot * radFactor) * group.运动方向系数;

        // 回收条件：衰竭计数到点 或 超出 Z 轴坐标限制；列表至少保留一个单元体
        if (((group.衰竭计数器 >= parentMC.霰弹值 * -1) ||
             (u.y * group.余弦值 + parentMC._y > parentMC.Z轴坐标)) &&
            (list.length > 1)) {
            _root.联弹系统.回收单元体于(group, j);
            parentMC.霰弹值--;
            continue;
        }

        y_max = Math.max(u.y, y_max);
        y_min = Math.min(u.y, y_min);
    }
    // 更新碰撞箱（本地坐标，公式与旧实现一致）
    area._y = y_min;
    area._height = Math.max(group.y_基准 * -2, y_max - y_min);

    _root.联弹系统.渲染组(group);
};

_root.联弹系统.横向联弹初始化 = function(clip:MovieClip):Void {
    var group:Object = _root.联弹系统.创建组(clip, _root.联弹系统.横向联弹更新);

    // 初始化衰竭计数器（衰竭值由霰弹值与子弹衰竭计数综合决定）
    group.衰竭计数器 = clip._parent.霰弹值 * -1 - _root.子弹衰竭计数(clip._parent) * 3;
    group.运动方向系数 = clip._parent.xmov < 0 ? -1 : 1;
    group.y_基准 = clip._y;
    group.余弦值 = Math.cos(clip._parent._rotation * Math.PI / 180);
    group.子弹种类 = clip._parent.子弹种类.split("-")[1];

    // 根据霰弹值生成单元体（flag 已定义时跳过，与旧逻辑一致）
    for (var i:Number = 0; (i < clip._parent.霰弹值) && (clip._parent.flag == undefined); i++) {
        _root.联弹系统.生成单元体(group, _root.随机偏移(clip._parent.子弹散射度));
    }
    _root.联弹系统.渲染组(group);
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

_root.联弹系统.横向拖尾联弹更新 = function(group:Object):Void {
    var area:MovieClip = group.area;
    var parentMC:MovieClip = group.bullet;
    var list:Array = group.单元体列表;
    var y_min:Number = Infinity;
    var y_max:Number = -Infinity;

    // 清理超额（霰弹值被外部削减时）
    while (list.length > parentMC.霰弹值 && list.length > 1) {
        _root.联弹系统.回收单元体于(group, list.length - 1);
    }

    for (var j:Number = list.length - 1; j >= 0; j--) {
        var u:Object = list[j];

        // —— 生命周期进度（0~1） ——
        u.age++;
        var delay:Number = group.聚拢延迟;
        var span:Number  = group.聚拢时长;

        var spd:Number = Math.abs(parentMC.xmov);
        var spanScaled:Number = Math.round(span * (1 + group.速度自适应系数 * spd));

        var p:Number = (u.age - delay - u.phaseJit) / spanScaled;
        if (p < 0) p = 0; else if (p > 1) p = 1;

        // —— 柔化收束（角度）：尾段延展 + smoothstep + 残留角 ——
        var gamma:Number = group.尾段延展指数;
        var p1:Number = 1 - Math.pow(1 - p, gamma);
        if (p1 < 0) p1 = 0; else if (p1 > 1) p1 = 1;

        var s:Number = p1 * p1 * (3 - 2 * p1);   // smoothstep
        var wRaw:Number = 1 - s;                 // 1→0
        var target:Number = group.目标角;
        var delta:Number  = Math.abs(u.initRot - target) + 1e-6;
        var wMin:Number   = group.收束残留角 / delta; if (wMin > 0.5) wMin = 0.5; if (wMin < 0) wMin = 0;
        var w:Number = wMin + (1 - wMin) * wRaw;

        u.rot = target + (u.initRot - target) * w;
        u.convergeT = 1 - w;

        // —— 轴心推进（沿原"纵向"速度模型） ——
        u.centerY += parentMC.xmov * Math.sin(u.rot * Math.PI / 180) * group.运动方向系数;

        // —— 计算绕轴螺旋偏移 ——
        var rad:Number = u.rot * Math.PI / 180;
        var Ux:Number = Math.cos(rad), Uy:Number = Math.sin(rad);
        var Nx:Number = -Uy,          Ny:Number = Ux;

        // 半径衰减：R = R_min + (R0 - R_min) * (1 - p)^γ
        var env:Number = Math.pow(1 - p, group.螺旋阻尼指数);
        var R:Number   = group.螺旋残留半径 + (group.螺旋初半径 - group.螺旋残留半径) * env;

        // 相位：整段共转 螺旋圈数 圈；带初相偏移
        var phase:Number = 2 * Math.PI * (group.螺旋圈数 * p) + u.oscPhase0;

        var offsetN:Number = R * Math.cos(phase); // 平面内的法向投影
        var zDepth:Number  = R * Math.sin(phase); // 伪Z：>0 近景，<0 远景

        // 应用到本地位置：轴心 + 法向偏移
        u.x = u.centerX + Nx * offsetN;
        u.y = u.centerY + Ny * offsetN;

        // —— 回收判断：按"轴心位置"判断，避免法向偏移误触阈值 ——
        if ( u.centerY * group.余弦值 + parentMC._y > parentMC.Z轴坐标 && list.length > 1 )
        {
            _root.联弹系统.回收单元体于(group, j);
            parentMC.霰弹值--;
            continue;
        }

        // 统计包围盒（以实际显示位置计算）
        if (u.y < y_min) y_min = u.y;
        if (u.y > y_max) y_max = u.y;

        // —— 采样拖尾（全局坐标 + 归一化伪Z）——
        var global_p:Object = {x: u.x, y: u.y};
        parentMC.localToGlobal(global_p);
        var zn:Number = (R > 0) ? (zDepth / R) : 0;
        global_p.zn = zn;
        u.trail.unshift(global_p);
        if (u.trail.length > 8) u.trail.pop();
    }

    /* 绘制拖尾（trail 全局→area 本地 + 基于伪Z调节线宽与透明） */
    area.clear();
    area.moveTo(0, 0);

    for (var m:Number = 0; m < list.length; m++)
    {
        var bullet:Object = list[m];
        if (bullet.trail.length > 1)
        {
            for (var t:Number = 0; t < bullet.trail.length - 1; t++)
            {
                var gp1:Object = bullet.trail[t];
                var gp2:Object = bullet.trail[t+1];

                var lp1:Object = {x: gp1.x, y: gp1.y};
                var lp2:Object = {x: gp2.x, y: gp2.y};
                area.globalToLocal(lp1);
                area.globalToLocal(lp2);

                // 渐隐
                var alphaBase:Number = 100 - t * 15;

                // 近/远景调制（zn ∈ [-1,1]）
                var znAvg:Number = (((gp1.zn != undefined) ? gp1.zn : 0) + ((gp2.zn != undefined) ? gp2.zn : 0)) * 0.5;
                if (znAvg > 1) znAvg = 1; else if (znAvg < -1) znAvg = -1;

                // 线宽：基础 ×（扩散增益）×（近景增粗）
                var baseW:Number = 2.5 - t * 0.3; if (baseW < 0.5) baseW = 0.5;
                var widen:Number = (bullet.convergeT != undefined) ? (1.0 + (1.0 - bullet.convergeT) * group.拖尾扩散增益) : 1.0;
                var nearGain:Number = 1 + group.螺旋近景增粗 * ((znAvg > 0) ? znAvg : 0);
                var width:Number = baseW * widen * nearGain;

                // 透明：远景暗化
                var farFade:Number = 1 - group.螺旋背面暗化 * ((znAvg < 0) ? -znAvg : 0);
                var alphaDraw:Number = alphaBase * farFade;

                area.lineStyle(width, 0xFFFFFF, alphaDraw);
                area.moveTo(lp1.x, lp1.y);
                area.lineTo(lp2.x, lp2.y);
            }
        }
    }

    /* 更新碰撞箱 */
    area._y      = y_min;
    area._height = Math.max(group.y_基准 * -2, y_max - y_min);

    _root.联弹系统.渲染组(group);
};

_root.联弹系统.横向拖尾联弹初始化 = function (clip:MovieClip):Void
{
    var group:Object = _root.联弹系统.创建组(clip, _root.联弹系统.横向拖尾联弹更新);

    /* ---------- ① 基础字段 ---------- */
    group.运动方向系数     = (clip._parent.xmov < 0) ? -1 : 1;
    group.y_基准           = clip._y;
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
        var u:Object = _root.联弹系统.生成单元体(group, _root.随机偏移(clip._parent.子弹散射度));

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

        // 拖尾（存全局 {x,y,zn}）
        u.trail = [];
    }
    _root.联弹系统.渲染组(group);
};

/* =====================================================================
 * 纵向联弹（机枪式扫射，逐帧补弹）
 * ===================================================================== */

_root.联弹系统.纵向联弹更新 = function(group:Object):Void {
    var area:MovieClip = group.area;
    var parentMC:MovieClip = group.bullet;
    var bulletSpeedX:Number = parentMC.xmov;
    var countTotal:Number = parentMC.霰弹值;
    var directionalCoefficient:Number = group.运动方向系数;
    var radFactor:Number = Math.PI / 180;
    var currentParentY:Number = parentMC._y;
    var list:Array = group.单元体列表;
    var u:Object;

    var y_min:Number = Infinity, y_max:Number = -Infinity;
    var x_min:Number, x_max:Number;
    var sinVal:Number;
    var cosVal:Number;

    // 判断是否需要进行X轴更新（即是否还需创建新单元体）
    if (group.count < countTotal) {
        var deltaXUpdate:Number = bulletSpeedX * directionalCoefficient;
        var originalX:Number = group.原始坐标x;
        var originalY:Number = group.原始坐标y;

        x_min = Infinity;
        x_max = -Infinity;

        var currentParentX:Number = parentMC._x;

        // 遍历所有单元体，更新Y、X坐标与范围
        for (var j:Number = list.length - 1; j >= 0; j--) {
            u = list[j];
            var unitRad:Number = u.rot * radFactor;
            sinVal = Math.sin(unitRad);
            cosVal = Math.cos(unitRad);

            u.y += bulletSpeedX * sinVal * directionalCoefficient;
            u.x += deltaXUpdate * cosVal;

            if (u.y > y_max) y_max = u.y;
            if (u.y < y_min) y_min = u.y;
            if (u.x > x_max) x_max = u.x;
            if (u.x < x_min) x_min = u.x;
        }

        // 计算新单元体坐标（子弹全局位移转换回本地坐标系）
        var globalDeltaX:Number = currentParentX - originalX;
        var globalDeltaY:Number = currentParentY - originalY;
        var rad:Number = parentMC._rotation * Math.PI / 180;
        cosVal = Math.cos(rad);
        sinVal = Math.sin(rad);
        var localDeltaX:Number = globalDeltaX * cosVal + globalDeltaY * sinVal;
        var localDeltaY:Number = -globalDeltaX * sinVal + globalDeltaY * cosVal;

        // 每帧补充 N 发单元体，沿当帧位移做分数位置插值，避免同点叠弹
        // （每帧补弹数=1 时插值=1，与旧行为一致）
        var 补弹数:Number = group.每帧补弹数;
        for (var s:Number = 0; s < 补弹数 && group.count < countTotal; s++) {
            var 插值:Number = (s + 1) / 补弹数;
            u = _root.联弹系统.生成单元体(group, _root.随机偏移(parentMC.子弹散射度));
            u.x = directionalCoefficient * localDeltaX * 插值 + _root.随机偏移(parentMC.子弹散射度 + countTotal + group.count);
            u.y = localDeltaY * 插值;

            // 新单元体当帧即纳入包围盒极值，保证首帧可命中
            if (u.x > x_max) x_max = u.x;
            if (u.x < x_min) x_min = u.x;
            if (u.y > y_max) y_max = u.y;
            if (u.y < y_min) y_min = u.y;

            group.count++;
        }

        // 更新X碰撞箱（含本帧新增单元体）
        area._x = x_min;
        area._width = Math.max(group.x_基准 * -2, x_max - x_min);

        // 重置子弹坐标为原始值
        parentMC._x = originalX;
        parentMC._y = originalY;
    } else {
        // X轴不更新时，沿用当前碰撞箱数据，只更新Y轴
        for (var j2:Number = list.length - 1; j2 >= 0; j2--) {
            u = list[j2];
            sinVal = Math.sin(u.rot * radFactor);
            u.y += bulletSpeedX * sinVal * directionalCoefficient;

            if (u.y > y_max) y_max = u.y;
            if (u.y < y_min) y_min = u.y;
        }
    }

    // 始终更新Y轴碰撞箱
    area._y = y_min;
    area._height = Math.max(group.y_基准 * -2, y_max - y_min);

    _root.联弹系统.渲染组(group);
};

_root.联弹系统.纵向联弹初始化 = function(clip:MovieClip):Void {
    var group:Object = _root.联弹系统.创建组(clip, _root.联弹系统.纵向联弹更新);

    group.y_基准 = clip._y;
    group.x_基准 = clip._x;
    group.原始坐标x = clip._parent._x;
    group.原始坐标y = clip._parent._y;
    group.运动方向系数 = clip._parent.xmov < 0 ? -1 : 1;
    group.子弹种类 = clip._parent.子弹种类.split("-")[1];
    group.count = 1;

    // 每帧补弹数：显式推参（每帧补弹数）优先；其次由实际发射间隔（发射间隔毫秒，
    // 由 WeaponFireCore.executeShot 盖戳，仅 fillrate opt-in 武器写入）推导，
    // 保证全部霰弹值在两次射击间隔内发射完毕；两者皆无时保持旧行为（每帧1发）
    // ⚠ 守卫必须用 >0 而非 >=1：AVM1 中 undefined>=1 恒为 true（>= 实现为 !(<)，NaN 比较返回 undefined）
    // ⚠ 向上取整：补弹插值以 (s+1)/每帧补弹数 计算，小数推参会使插值>1、单元体超出当帧位移
    var 每帧补弹数:Number = Math.ceil(clip._parent.每帧补弹数);
    if (!(每帧补弹数 > 0)) {
        var 发射间隔毫秒:Number = clip._parent.发射间隔毫秒;
        if (发射间隔毫秒 > 0) {
            var 间隔帧数:Number = Math.floor(发射间隔毫秒 / EnhancedCooldownWheel.I().每帧毫秒);
            if (间隔帧数 < 1) 间隔帧数 = 1;
            每帧补弹数 = Math.ceil((clip._parent.霰弹值 - 1) / 间隔帧数);
        }
        if (!(每帧补弹数 > 0)) 每帧补弹数 = 1;
    }
    group.每帧补弹数 = 每帧补弹数;

    // 创建第一个单元体
    _root.联弹系统.生成单元体(group, _root.随机偏移(clip._parent.子弹散射度));
    _root.联弹系统.渲染组(group);
};

/* =====================================================================
 * 滑翔联弹（下滑弹道）
 * ===================================================================== */

_root.联弹系统.滑翔联弹更新 = function(group:Object):Void {
    var area:MovieClip = group.area;
    var parentMC:MovieClip = group.bullet;
    var list:Array = group.单元体列表;
    var y_min:Number = Infinity;
    var y_max:Number = -Infinity;

    // 更新子弹 ymov，使下坠速度渐进（模拟滑翔角时下坠的迟缓）
    parentMC.ymov += Math.max(0.1, (group.下滑速度 - parentMC.ymov) * group.下滑速度 * 0.05);
    // 根据当前的 xmov 与 ymov 更新子弹旋转角度
    parentMC._rotation = Math.atan2(parentMC.ymov, parentMC.xmov) * 180 / Math.PI;

    for (var j:Number = list.length - 1; j >= 0; j--) {
        var u:Object = list[j];
        u.y += parentMC.xmov * Math.sin(u.rot * Math.PI / 180) * group.运动方向系数;

        // 超出 Z 轴坐标限制时回收（列表至少保留一个单元体）
        if ((u.y * Math.cos(parentMC._rotation * Math.PI / 180) + parentMC._y > parentMC.Z轴坐标) && list.length > 1) {
            _root.联弹系统.回收单元体于(group, j);
            parentMC.霰弹值--;
            continue;
        }

        y_max = Math.max(u.y, y_max);
        y_min = Math.min(u.y, y_min);
    }
    area._y = y_min;
    area._height = Math.max(group.y_基准 * -2, y_max - y_min);

    _root.联弹系统.渲染组(group);
};

_root.联弹系统.滑翔联弹初始化 = function(clip:MovieClip):Void {
    var group:Object = _root.联弹系统.创建组(clip, _root.联弹系统.滑翔联弹更新);

    group.y_基准 = clip._y;
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

_root.联弹系统.爆炸联弹更新 = function(group:Object):Void {
    var area:MovieClip = group.area;
    var parentMC:MovieClip = group.bullet;
    var list:Array = group.单元体列表;
    var y_min:Number = Infinity;
    var y_max:Number = -Infinity;

    // 每帧增加子弹垂直速度，模拟下坠加速效果
    parentMC.ymov += 1.2;
    // 根据当前 xmov 和 ymov 计算子弹旋转角度（角度指向速度方向）
    parentMC._rotation = Math.atan2(parentMC.ymov, parentMC.xmov) * 180 / Math.PI;

    for (var j:Number = list.length - 1; j >= 0; j--) {
        var u:Object = list[j];
        u.y += parentMC.xmov * Math.sin(u.rot * Math.PI / 180) * group.运动方向系数;

        // 超出 Z 轴坐标限制时，通知子弹进入"消失"状态
        if ((u.y * Math.cos(parentMC._rotation * Math.PI / 180) + parentMC._y > parentMC.Z轴坐标) && list.length > 1) {
            parentMC.gotoAndStop("消失");
        }
        y_max = Math.max(u.y, y_max);
        y_min = Math.min(u.y, y_min);
    }
    area._y = y_min;
    area._height = Math.max(group.y_基准 * -2, y_max - y_min);

    _root.联弹系统.渲染组(group);
};

_root.联弹系统.爆炸联弹初始化 = function(clip:MovieClip):Void {
    var group:Object = _root.联弹系统.创建组(clip, _root.联弹系统.爆炸联弹更新);

    group.y_基准 = clip._y;
    group.运动方向系数 = clip._parent.xmov < 0 ? -1 : 1;
    group.子弹种类 = clip._parent.子弹种类.split("-")[1];

    // 调整子弹垂直移动速度：根据子弹散射度和 xmov 的绝对值
    clip._parent.ymov += clip._parent.子弹散射度 * Math.abs(clip._parent.xmov) / 100;

    for (var i:Number = 0; i < clip._parent.霰弹值; i++) {
        _root.联弹系统.生成单元体(group, _root.随机偏移(clip._parent.子弹散射度));
    }
    _root.联弹系统.渲染组(group);
};
