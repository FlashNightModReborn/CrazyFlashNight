import org.flashNight.sara.util.*;
import org.flashNight.arki.spatial.move.*;
_root.单元体计数 = 0;

_root.创建单元体 = function(子弹:MovieClip, 子弹种类:String) {
    _root.单元体计数++;
    return 子弹.attachMovie("单元体-" + 子弹种类, "单元体-" + _root.单元体计数++, 子弹.getNextHighestDepth());
}

_root.回收单元体 = function(单元体:MovieClip) {
    单元体.removeMovieClip();
}

_root.子弹衰竭计数 = function(子弹:MovieClip) {
    return (子弹.霰弹值 + 子弹.子弹散射度) / 25;// 让衰减在前期更为剧烈  
}

// 定义在 _root.联弹系统 对象中
_root.联弹系统.爆炸联弹预处理 = function(clip:MovieClip):Void {
    // 初始化子弹属性，传入当前 clip 及 "近战联弹" 类型
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

_root.联弹系统 = {};

// 定义在 _root.联弹系统 内部
_root.联弹系统.联弹消失 = function(clip:MovieClip):Void {
    // 停止当前播放，防止继续播放后续帧动画
    clip.stop();
    // 设置标记为 true，表示联弹处于消失状态
    clip.flag = true;
    
    // 判断条件：如果霰弹值小于等于1，或者已经击中地图，则直接移除该 MovieClip
    if (clip.霰弹值 <= 1 || clip.击中地图) {
        clip.removeMovieClip();
    } else {
        // 否则，重置到第一帧（可用于循环播放消失动画或重置状态）
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
        
        // 信息传递完毕后，移除原始的 area 影片剪辑
        clip.area.removeMovieClip();
        
        // 将子弹属性传递给子弹区域处理函数
        _root.子弹区域shoot传递(clip.子弹属性);
        
        // 遍历 area 内的所有单元体，生成爆炸效果
        for (var i:Number = 0; i < clip.area.单元体列表.length; i++) {
            var 单元体:MovieClip = clip.area.单元体列表[i];
            // 记录单元体当前位置
            var point:Object = { x: 单元体._x, y: 单元体._y };
            // 坐标转换到 gameworld 坐标系
            _root.pointToGameworld(point, 单元体);
            
            // 在 gameworld 中添加联弹爆炸效果
            var 爆炸:MovieClip = _root.gameworld.attachMovie("联弹爆炸", "explosion" + i, _root.gameworld.getNextHighestDepth());
            爆炸._x = point.x;
            爆炸._y = point.y;
            
            // 回收该单元体
            _root.回收单元体(单元体);
        }
        // 标记处理完毕
        clip.flag = true;
    } else {
        // 如果已处理过，直接移除影片剪辑
        clip.removeMovieClip();
    }
};



// 定义在 _root.联弹系统 对象内部
_root.联弹系统.横向联弹初始化 = function(clip:MovieClip):Void {
    // 初始化衰竭计数器（衰竭值由霰弹值与子弹衰竭计数综合决定）
    clip.衰竭计数器 = clip._parent.霰弹值 * -1 - _root.子弹衰竭计数(clip._parent) * 3;
    
    // 初始化子弹单元体列表
    clip.单元体列表 = [];
    
    // 根据父对象 xmov 的方向确定运动系数
    clip.运动方向系数 = clip._parent.xmov < 0 ? -1 : 1;
    
    // 保存初始 y 坐标，作为后续碰撞箱大小的基准
    clip.y_基准 = clip._y;
    
    // 根据父对象的旋转角度计算余弦值（用于后续位置判断）
    clip.余弦值 = Math.cos(clip._parent._rotation * Math.PI / 180);
    
    // 提取子弹种类（注意：这里假设子弹种类的格式为 “XXX-子弹种类”）
    var 子弹种类:String = clip._parent.子弹种类.split("-")[1];
    
    // 根据霰弹值生成对应的子弹单元体，同时判断 flag 未定义时才生成
    for (var i:Number = 0; (i < clip._parent.霰弹值) && (clip._parent.flag == undefined); i++) {
        var 单元体:MovieClip = _root.创建单元体(clip._parent, 子弹种类);
        // 设置单元体的初始偏转（用于散射效果）
        单元体._rotation = _root.随机偏移(clip._parent.子弹散射度);
        clip.单元体列表.push(单元体);
    }
    
    // 设置 onEnterFrame 每帧更新子弹单元体的运动逻辑
    clip.onEnterFrame = function():Void {
        if(_root.暂停) return;

        // 累加衰竭计数
        clip.衰竭计数器 += _root.子弹衰竭计数(clip._parent);
        var y_min:Number = Infinity;
        var y_max:Number = -Infinity;
        
        // 倒序遍历单元体列表，便于安全地删除不再需要的单元体
        for (var j:Number = clip.单元体列表.length - 1; j >= 0; j--) {
            var 单元体:MovieClip = clip.单元体列表[j];
            // 根据父对象 xmov、单元体的旋转及运动方向系数更新单元体的 y 坐标
            单元体._y += clip._parent.xmov * Math.sin(单元体._rotation * Math.PI / 180) * clip.运动方向系数;
            
            // 判断是否达到回收条件：
            //   1. 衰竭计数器达到一定值
            //   2. 单元体超出父对象的 Z 轴坐标限制
            // 并且确保列表中至少保留一个单元体
            if (((clip.衰竭计数器 >= clip._parent.霰弹值 * -1) || 
                 (单元体._y * clip.余弦值 + clip._parent._y > clip._parent.Z轴坐标)) &&
                (clip.单元体列表.length > 1)) {
                
                // 回收单元体（例如放回对象池）
                _root.回收单元体(单元体);
                // 从列表中删除该单元体，同时调整索引
                clip.单元体列表.splice(j--, 1);
                // 同步减少父对象中的霰弹值
                clip._parent.霰弹值--;
                continue;
            }
            
            // 计算所有单元体的最小和最大 y 值，用于更新碰撞箱
            y_max = Math.max(单元体._y, y_max);
            y_min = Math.min(单元体._y, y_min);
        }
        // 更新当前 clip 的 y 坐标和高度，使碰撞箱与视觉效果相符
        clip._y = y_min;
        clip._height = Math.max(clip.y_基准 * -2, y_max - y_min);
    };
};


/*====================================================================
 * 横向拖尾联弹初始化 (轴向螺旋版：绕飞行轴的衰减螺旋 + 柔化收束 + 伪Z透视)
 * 说明：
 *   ① 轴心：每颗子弹维护 centerX/centerY 作为“飞行轴”，沿原弹道推进；
 *      实际绘制位置 = 轴心位置 + (随相位旋转的法向偏移)。
 *   ② 螺旋：半径随生命周期衰减；相位按总圈数推进；附带伪Z（用于前后景明暗/粗细）。
 *   ③ 拖尾：trail[] 存全局 {x,y,zn}（zn 为当帧 z 归一化），绘制时回到本地并据 zn 调整线条。
 *   ④ 收束：采用“尾段延展 + smoothstep + 残留角”，避免猛收口。
 *===================================================================*/
_root.联弹系统.横向拖尾联弹初始化 = function (clip:MovieClip):Void
{
    /* ---------- ① 基础字段 ---------- */

    clip.单元体列表       = [];
    clip.运动方向系数     = (clip._parent.xmov < 0) ? -1 : 1;
    clip.y_基准           = clip._y;
    clip.余弦值           = Math.cos(clip._parent._rotation * Math.PI / 180);
    var 子弹种类:String    = String(clip._parent.子弹种类).split("-")[1];

    // —— 角度收束参数（可被 clip._parent 覆盖）——
    clip.聚拢延迟         = (clip._parent.聚拢延迟 != undefined) ? clip._parent.聚拢延迟 : 3;     // 帧
    clip.聚拢时长         = (clip._parent.聚拢时长 != undefined) ? clip._parent.聚拢时长 : 18;    // 帧（偏慢更柔）
    clip.目标角           = (clip._parent.聚拢目标角 != undefined) ? clip._parent.聚拢目标角 : 0;  // °
    clip.速度自适应系数   = (clip._parent.聚拢速度自适应系数 != undefined) ? clip._parent.聚拢速度自适应系数 : 0.010;

    // —— 尾段柔化参数 ——（让末段别“猛地一合”）
    clip.尾段延展指数     = (clip._parent.尾段延展指数 != undefined) ? clip._parent.尾段延展指数 : 2.5; // >1 尾段更慢
    clip.收束残留角       = (clip._parent.收束残留角 != undefined) ? clip._parent.收束残留角 : 1.2;  // ° 收束到目标角附近留少许残角

    // —— 螺旋（绕轴）参数 ——（半径衰减 + 固定圈数 + 相位扰动）
    clip.螺旋初半径       = (clip._parent.螺旋初半径 != undefined) ? clip._parent.螺旋初半径 : 10;    // px，出生时绕轴半径
    clip.螺旋残留半径     = (clip._parent.螺旋残留半径 != undefined) ? clip._parent.螺旋残留半径 : 0;     // px，末段保留
    clip.螺旋阻尼指数     = (clip._parent.螺旋阻尼指数 != undefined) ? clip._parent.螺旋阻尼指数 : 1.6;   // γ，越大衰得越慢
    clip.螺旋圈数         = (clip._parent.螺旋圈数 != undefined) ? clip._parent.螺旋圈数 : 2.0;       // 生命周期内总圈数
    clip.螺旋相位扰动     = (clip._parent.螺旋相位扰动 != undefined) ? clip._parent.螺旋相位扰动 : 0.5;   // 0~1，相位分散
    // 伪Z对外观的影响（前近/后远）
    clip.螺旋背面暗化     = (clip._parent.螺旋背面暗化 != undefined) ? clip._parent.螺旋背面暗化 : 0.30; // 0~1，背面透明提升
    clip.螺旋近景增粗     = (clip._parent.螺旋近景增粗 != undefined) ? clip._parent.螺旋近景增粗 : 0.25; // 线宽在近景的加成比例

    // —— 拖尾宽度增益（扩散期更粗→收束后更细）——
    clip.拖尾扩散增益     = (clip._parent.拖尾扩散增益 != undefined) ? clip._parent.拖尾扩散增益 : 0.35;

    /* ---------- ② 生成子弹 ---------- */
    for (var i:Number = 0;
         (i < clip._parent.霰弹值) && (clip._parent.flag == undefined);
         i++)
    {
        var b:MovieClip = _root.创建单元体(clip._parent, 子弹种类);

        // 初始随机散射角（先“扩散”）
        b._rotation = _root.随机偏移(clip._parent.子弹散射度);

        // —— 生命周期/收束状态 —— 
        b.initRot   = b._rotation;
        b.age       = 0;
        b.phaseJit  = (Math.random() - 0.5) * 4;

        // —— 轴心（飞行轨迹轴体）：沿原弹道推进；实际 _x/_y = 轴心 + 法向偏移 —— 
        b.centerX = b._x;
        b.centerY = b._y;

        // —— 螺旋相位 —— 
        var jitter:Number = (Math.random()*2 - 1) * Math.PI * clip.螺旋相位扰动; // [-πr, πr]
        b.oscPhase0 = jitter;

        // 拖尾（存全局 {x,y,zn}）
        b.trail = [];

        clip.单元体列表.push(b);
    }


    /* ---------- ③ 帧循环 ---------- */
    clip.onEnterFrame = function ():Void
    {
        if (_root.暂停) return;
        var y_min:Number = Infinity;
        var y_max:Number = -Infinity;

        // 清理超额
        while (this.单元体列表.length > this._parent.霰弹值 && this.单元体列表.length > 1) {
            var excessBullet:MovieClip = this.单元体列表.pop();
            _root.回收单元体(excessBullet);
        }

        for (var j:Number = this.单元体列表.length - 1; j >= 0; j--)
        {
            var b:MovieClip = this.单元体列表[j];

            // —— 生命周期进度（0~1） —— 
            b.age++;
            var delay:Number = this.聚拢延迟;
            var span:Number  = this.聚拢时长;

            var spd:Number = Math.abs(this._parent.xmov);
            var spanScaled:Number = Math.round(span * (1 + this.速度自适应系数 * spd));

            var p:Number = (b.age - delay - b.phaseJit) / spanScaled;
            if (p < 0) p = 0; else if (p > 1) p = 1;

            // —— 柔化收束（角度）：尾段延展 + smoothstep + 残留角 —— 
            var gamma:Number = this.尾段延展指数;
            var p1:Number = 1 - Math.pow(1 - p, gamma);
            if (p1 < 0) p1 = 0; else if (p1 > 1) p1 = 1;

            var s:Number = p1 * p1 * (3 - 2 * p1);   // smoothstep
            var wRaw:Number = 1 - s;                 // 1→0
            var target:Number = this.目标角;
            var delta:Number  = Math.abs(b.initRot - target) + 1e-6;
            var wMin:Number   = this.收束残留角 / delta; if (wMin > 0.5) wMin = 0.5; if (wMin < 0) wMin = 0;
            var w:Number = wMin + (1 - wMin) * wRaw;

            b._rotation = target + (b.initRot - target) * w;
            b.convergeT = 1 - w;

            // —— 轴心推进（沿原“纵向”速度模型） —— 
            b.centerY += this._parent.xmov * Math.sin(b._rotation * Math.PI / 180) * this.运动方向系数;
            // （保持 centerX 不变，若你想轴心随角度略前进，可加：b.centerX += this._parent.xmov * Math.cos(...)*k）

            // —— 计算绕轴螺旋偏移 —— 
            // 局部切线 U=(cosθ, sinθ)；法线 N=(-sinθ, cosθ)
            var rad:Number = b._rotation * Math.PI / 180;
            var Ux:Number = Math.cos(rad), Uy:Number = Math.sin(rad);
            var Nx:Number = -Uy,          Ny:Number = Ux;

            // 半径衰减：R = R_min + (R0 - R_min) * (1 - p)^γ
            var env:Number = Math.pow(1 - p, this.螺旋阻尼指数);
            var R:Number   = this.螺旋残留半径 + (this.螺旋初半径 - this.螺旋残留半径) * env;

            // 相位：整段共转 螺旋圈数 圈；带初相偏移
            var phase:Number = 2 * Math.PI * (this.螺旋圈数 * p) + b.oscPhase0;

            // 在屏幕平面“绕轴”的法向位移（cos分量进屏内/外由伪Z承担）
            var offsetN:Number = R * Math.cos(phase); // 平面内的法向投影
            var zDepth:Number  = R * Math.sin(phase); // 伪Z：>0 近景，<0 远景

            // 应用到实际位置：轴心 + 法向偏移
            b._x = b.centerX + Nx * offsetN;
            b._y = b.centerY + Ny * offsetN;

            // —— 回收判断：按“轴心位置”判断，避免法向偏移误触阈值 —— 
            if ( b.centerY * this.余弦值 + this._parent._y > this._parent.Z轴坐标 && this.单元体列表.length > 1 )
            {
                _root.回收单元体(b);
                this.单元体列表.splice(j, 1);
                this._parent.霰弹值--;
                continue;
            }

            // 统计包围盒（以实际显示位置计算）
            if (b._y < y_min) y_min = b._y;
            if (b._y > y_max) y_max = b._y;

            // —— 采样拖尾（全局坐标 + 归一化伪Z）——
            var global_p:Object = {x: b._x, y: b._y};
            this._parent.localToGlobal(global_p);
            // 把 zDepth 归一化到 [-1,1]（用 R 做归一化，避免半径变化导致尺度漂移）
            var zn:Number = (R > 0) ? (zDepth / R) : 0;
            global_p.zn = zn;
            b.trail.unshift(global_p);
            if (b.trail.length > 8) b.trail.pop();
        }

        /* 3-2 绘制拖尾（trail 全局→本地 + 基于伪Z调节线宽与透明） ----------*/
        this.clear();
        this.moveTo(0, 0);

        for (var m:Number = 0; m < this.单元体列表.length; m++)
        {
            var bullet:MovieClip = this.单元体列表[m];
            if (bullet.trail.length > 1)
            {
                for (var t:Number = 0; t < bullet.trail.length - 1; t++)
                {
                    var gp1:Object = bullet.trail[t];
                    var gp2:Object = bullet.trail[t+1];

                    var lp1:Object = {x: gp1.x, y: gp1.y};
                    var lp2:Object = {x: gp2.x, y: gp2.y};
                    this.globalToLocal(lp1);
                    this.globalToLocal(lp2);

                    // 渐隐
                    var alphaBase:Number = 100 - t * 15;

                    // 近/远景调制（zn ∈ [-1,1]）：近景更粗更亮，远景更细更淡
                    var znAvg:Number = (((gp1.zn != undefined) ? gp1.zn : 0) + ((gp2.zn != undefined) ? gp2.zn : 0)) * 0.5;
                    if (znAvg > 1) znAvg = 1; else if (znAvg < -1) znAvg = -1;

                    // 线宽：基础 ×（扩散增益）×（近景增粗）
                    var baseW:Number = 2.5 - t * 0.3; if (baseW < 0.5) baseW = 0.5;
                    var widen:Number = (bullet.convergeT != undefined) ? (1.0 + (1.0 - bullet.convergeT) * this.拖尾扩散增益) : 1.0;
                    var nearGain:Number = 1 + this.螺旋近景增粗 * ((znAvg > 0) ? znAvg : 0); // 仅近景增粗
                    var width:Number = baseW * widen * nearGain;

                    // 透明：远景暗化
                    var farFade:Number = 1 - this.螺旋背面暗化 * ((znAvg < 0) ? -znAvg : 0);
                    var alphaDraw:Number = alphaBase * farFade;

                    this.lineStyle(width, 0xFFFFFF, alphaDraw);
                    this.moveTo(lp1.x, lp1.y);
                    this.lineTo(lp2.x, lp2.y);
                }
            }
        }

        /* 3-3 更新碰撞箱 -------------------------------------------------*/
        this._y      = y_min;
        this._height = Math.max(this.y_基准 * -2, y_max - y_min);
    };
};


_root.联弹系统.纵向联弹初始化 = function(clip:MovieClip):Void {
    // 保存初始坐标与单元体列表初始化
    clip.y_基准 = clip._y;
    clip.x_基准 = clip._x;
    clip.单元体列表 = [];
    
    // 保存父对象初始坐标与旋转信息
    clip.原始坐标x = clip._parent._x;
    clip.原始坐标y = clip._parent._y;
    
    // 根据父对象 xmov 判断运动方向
    clip.运动方向系数 = clip._parent.xmov < 0 ? -1 : 1;
    
    // 提取子弹种类
    clip.子弹种类 = clip._parent.子弹种类.split("-")[1];
    clip.count = 1;
    
    // 创建第一个单元体
    var firstUnit:MovieClip = _root.创建单元体(clip._parent, clip.子弹种类);
    firstUnit._rotation = _root.随机偏移(clip._parent.子弹散射度);
    clip.单元体列表.push(firstUnit);
    
    clip.onEnterFrame = function():Void {
        if(_root.暂停) return;
        var parentMC:MovieClip = this._parent;
        var bulletSpeedX:Number = parentMC.xmov;
        var countTotal:Number = parentMC.霰弹值;
        var directionalCoefficient:Number = this.运动方向系数;
        var radFactor:Number = Math.PI / 180;
        var parentRotRad:Number = parentMC._rotation * radFactor;
        var parentCos:Number = Math.cos(parentRotRad);
        var hitZ:Number = parentMC.Z轴坐标;
        var currentParentY:Number = parentMC._y;
        var unit:MovieClip;
        
        // 检查地图碰撞状态
        // var isHitMap:Boolean = Mover.isMovieClipValid(this);
        var y_min:Number = Infinity, y_max:Number = -Infinity;
        var x_min:Number, x_max:Number;
        var sinVal:Number;
        var unitRad:Number;
        var isHitGround:Boolean;
        var isHIt:Boolean;

        // 判断是否需要进行X轴更新（即是否还需创建新子弹）
        if(this.count < countTotal) {
            // X轴需要更新时，预先计算增量并重置极值
            var deltaXUpdate:Number = bulletSpeedX * directionalCoefficient;
            var originalX:Number = this.原始坐标x;
            var originalY:Number = this.原始坐标y;
            var cosVal:Number;

            x_min = Infinity;
            x_max = -Infinity;

            var currentParentX:Number = parentMC._x;
            
            // 遍历所有单元体，更新Y、X坐标和范围（无需内部判断x_update）
            for (var j:Number = this.单元体列表.length - 1; j >= 0; j--) {
                unit = this.单元体列表[j];
                unitRad = unit._rotation * radFactor;
                sinVal = Math.sin(unitRad);
                cosVal = Math.cos(unitRad);
                
                // 更新Y和X
                unit._y += bulletSpeedX * sinVal * directionalCoefficient;
                unit._x += deltaXUpdate * cosVal;

                /*
                
                isHitGround = (unit._y * parentCos + currentParentY > hitZ);
                isHIt = isHitMap && !Mover.isMovieClipPositionValid(unit);
                if ((isHIt || isHitGround) && (this.单元体列表.length > 1)) {
                    _root.回收单元体(unit);
                    this.单元体列表.splice(j, 1);
                    continue;
                }

                */
                
                if (unit._y > y_max) y_max = unit._y;
                if (unit._y < y_min) y_min = unit._y;
                if (unit._x > x_max) x_max = unit._x;
                if (unit._x < x_min) x_min = unit._x;
            }

            // 当X轴更新时，更新X碰撞箱并创建新的单元体
            this._x = x_min;
            this._width = Math.max(this.x_基准 * -2, x_max - x_min);
            
            // 计算新的单元体坐标（转换全局到父MC局部坐标系）
            var globalDeltaX:Number = currentParentX - originalX;
            var globalDeltaY:Number = currentParentY - originalY;
            var rad:Number = parentMC._rotation * Math.PI / 180;
            cosVal = Math.cos(rad);
            sinVal = Math.sin(rad);
            var localDeltaX:Number = globalDeltaX * cosVal + globalDeltaY * sinVal;
            var localDeltaY:Number = -globalDeltaX * sinVal + globalDeltaY * cosVal;
            
            var newUnit:MovieClip = _root.创建单元体(parentMC, this.子弹种类);
            newUnit._rotation = _root.随机偏移(parentMC.子弹散射度);
            newUnit._x += directionalCoefficient * localDeltaX + _root.随机偏移(parentMC.子弹散射度 + countTotal + this.count);
            newUnit._y += localDeltaY;
            
            this.单元体列表.push(newUnit);
            // 重置父对象坐标为原始值
            parentMC._x = originalX;
            parentMC._y = originalY;
            this.count++;
        } else {
            // 当X轴不更新时，沿用当前碰撞箱数据，且只更新Y轴
            x_min = this._x;
            x_max = this._x + this._width;
            for (var j:Number = this.单元体列表.length - 1; j >= 0; j--) {
                unit = this.单元体列表[j];
                sinVal = Math.sin(unit._rotation * radFactor);
                
                // 仅更新Y
                unit._y += bulletSpeedX * sinVal * directionalCoefficient;

                /*
                
                isHitGround = (unit._y * parentCos + currentParentY > hitZ);
                isHIt = isHitMap && !Mover.isMovieClipPositionValid(unit);
                if ((isHIt || isHitGround) && (this.单元体列表.length > 1)) {
                    _root.回收单元体(unit);
                    this.单元体列表.splice(j, 1);
                    continue;
                }

                */
                
                if (unit._y > y_max) y_max = unit._y;
                if (unit._y < y_min) y_min = unit._y;
            }
        }

        // 检查父对象是否超出边界,当前纵向联弹在中秋地图上存在隧穿问题
        // 只要有一发纵向联弹隧穿，就会出现如下的情况
        // 对于非旋转的纵向联弹，视觉正常但只有第一帧有判定，碰撞箱在后续帧无判定，命中敌人无效果
        // 对于旋转的纵向联弹，效果正常
        // 隧穿成为僵尸子弹后会极其卡顿，日志调试未发现异常值也未发现死循环
        // 未定位到原因，暂时额外加上边界检测
        
        if(parentMC._x < _root.Xmin || parentMC._x > _root.Xmax ||
           parentMC._y < _root.Ymin || parentMC._y > _root.Ymax) {
            // 超出边界时，回收所有单元体并移除自身
            for (var j:Number = this.单元体列表.length - 1; j >= 0; j--) {
                unit = this.单元体列表[j];
                _root.回收单元体(unit);
                this.单元体列表.splice(j, 1);
            }
            parentMC.霰弹值 = 0;
            this.removeMovieClip();
            return;
        }
        
        // 始终更新Y轴碰撞箱
        this._y = y_min;
        this._height = Math.max(this.y_基准 * -2, y_max - y_min);
        // _root.服务器.发布服务器消息(this._width + " " + this._height + ":" + _parent + " " + x_max + " " + x_min + " " + y_max + " " + y_min);
    };
};



// 定义在 _root.联弹系统 对象中
_root.联弹系统.滑翔联弹初始化 = function(clip:MovieClip):Void {
    // 保存初始坐标、角度和尺寸信息
    clip.y_基准 = clip._y;               // 用于后续更新碰撞箱的基准
    clip.单元体列表 = [];               // 初始化单元体列表
    clip.原始坐标x = clip._parent._x;    // 保存父对象原始 x 坐标
    clip.原始坐标y = clip._parent._y;    // 保存父对象原始 y 坐标
    clip.原始方向 = clip._parent._rotation; // 保存父对象原始旋转角度
    
    // 根据父对象 xmov 的正负确定运动方向
    clip.运动方向系数 = clip._parent.xmov < 0 ? -1 : 1;
    // 计算下滑速度，根据子弹散射度与 xmov 绝对值决定
    clip.下滑速度 = clip._parent.子弹散射度 * Math.abs(clip._parent.xmov) / 100;
    
    // 提取子弹种类（格式为 "xxx-子弹种类"）
    var 子弹种类:String = clip._parent.子弹种类.split("-")[1];
    
    // 循环创建单元体，只有在父对象 flag 未定义时才生成
    for (var i:Number = 0; (i < clip._parent.霰弹值) && (clip._parent.flag == undefined); ++i) {
        var 单元体:MovieClip = _root.创建单元体(clip._parent, 子弹种类);
        // 为单元体设置一个随机偏移的旋转角度，实现散射效果
        单元体._rotation = _root.随机偏移(clip._parent.子弹散射度);
        clip.单元体列表.push(单元体);
    }
    
    // 每帧更新处理逻辑
    clip.onEnterFrame = function():Void {
        if(_root.暂停) return;
        var y_min:Number = Infinity;
        var y_max:Number = -Infinity;
        
        // 更新父对象的 ymov，使下坠速度渐进（模拟滑翔角时下坠的迟缓）
        this._parent.ymov += Math.max(0.1, (this.下滑速度 - this._parent.ymov) * this.下滑速度 * 0.05);
        // 根据当前的 xmov 与 ymov 更新父对象的旋转角度
        this._parent._rotation = Math.atan2(this._parent.ymov, this._parent.xmov) * 180 / Math.PI;
        
        // 遍历所有单元体，更新它们的 y 坐标
        for (var j:Number = this.单元体列表.length - 1; j >= 0; --j) {
            var 单元体:MovieClip = this.单元体列表[j];
            单元体._y += this._parent.xmov * Math.sin(单元体._rotation * Math.PI / 180) * this.运动方向系数;
            
            // 判断条件：当单元体的 y 坐标经过旋转变换后超出父对象 Z 轴坐标，并且列表中至少保留一个单元体时
            if ((单元体._y * Math.cos(this._parent._rotation * Math.PI / 180) + this._parent._y > this._parent.Z轴坐标) && this.单元体列表.length > 1) {
                // 回收该单元体（例如放入对象池中以便复用）
                _root.回收单元体(单元体);
                // 从列表中移除该单元体，并调整索引
                this.单元体列表.splice(j--, 1);
                // 同步减少父对象中的霰弹值
                this._parent.霰弹值--;
                continue;
            }
            
            // 更新所有单元体的最小和最大 y 值
            y_max = Math.max(单元体._y, y_max);
            y_min = Math.min(单元体._y, y_min);
        }
        // 根据单元体的 y 值范围更新当前 clip 的位置与高度，确保碰撞箱与视觉效果相符
        this._y = y_min;
        this._height = Math.max(this.y_基准 * -2, y_max - y_min);
    };
};


// 定义在 _root.联弹系统 对象内
_root.联弹系统.爆炸联弹初始化 = function(clip:MovieClip):Void {
    // 保存 area 的初始 y 坐标，作为后续碰撞箱尺寸更新的基准
    clip.y_基准 = clip._y;
    // 初始化单元体列表
    clip.单元体列表 = [];
    // 保存父对象的原始坐标和旋转角度
    clip.原始坐标x = clip._parent._x;
    clip.原始坐标y = clip._parent._y;
    clip.原始方向 = clip._parent._rotation;
    // 根据父对象 xmov 的正负确定运动方向
    clip.运动方向系数 = clip._parent.xmov < 0 ? -1 : 1;
    
    // 调整父对象的垂直移动速度：根据子弹散射度和 xmov 的绝对值
    clip._parent.ymov += clip._parent.子弹散射度 * Math.abs(clip._parent.xmov) / 100;
    
    // 提取子弹种类（格式如 "xxx-子弹种类"）
    var 子弹种类:String = clip._parent.子弹种类.split("-")[1];
    // 根据父对象的霰弹值生成单元体
    for (var i:Number = 0; i < clip._parent.霰弹值; i++) {
        var 单元体:MovieClip = _root.创建单元体(clip._parent, 子弹种类);
        // 为单元体设置一个随机偏移角度，实现散射效果
        单元体._rotation = _root.随机偏移(clip._parent.子弹散射度);
        clip.单元体列表.push(单元体);
    }
    
    // 设置每帧执行的更新逻辑
    clip.onEnterFrame = function():Void {
        if(_root.暂停) return;
        var y_min:Number = Infinity;
        var y_max:Number = -Infinity;
        
        // 每帧增加父对象的垂直速度，模拟下坠加速效果
        this._parent.ymov += 1.2;
        // 根据当前 xmov 和 ymov 计算父对象的旋转角度（角度指向速度方向）
        this._parent._rotation = Math.atan2(this._parent.ymov, this._parent.xmov) * 180 / Math.PI;
        
        // 遍历所有单元体，更新它们的 y 坐标
        for (var j:Number = this.单元体列表.length - 1; j >= 0; j--) {
            var 单元体:MovieClip = this.单元体列表[j];
            单元体._y += this._parent.xmov * Math.sin(单元体._rotation * Math.PI / 180) * this.运动方向系数;
            
            // 判断单元体是否超出父对象定义的 Z 轴坐标（并且确保列表中至少保留一个单元体）
            if ((单元体._y * Math.cos(this._parent._rotation * Math.PI / 180) + this._parent._y > this._parent.Z轴坐标) && this.单元体列表.length > 1) {
                // 如果超出，则通知父对象进入“消失”状态
                this._parent.gotoAndStop("消失");
            }
            // 同时记录所有单元体的最大与最小 y 值
            y_max = Math.max(单元体._y, y_max);
            y_min = Math.min(单元体._y, y_min);
        }
        // 根据单元体的 y 范围更新当前 clip 的位置和高度，使碰撞箱与视觉效果匹配
        this._y = y_min;
        this._height = Math.max(this.y_基准 * -2, y_max - y_min);
    };
};
