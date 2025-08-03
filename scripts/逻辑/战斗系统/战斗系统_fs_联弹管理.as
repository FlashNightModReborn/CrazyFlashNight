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
 * 横向拖尾联弹初始化 (修正版)
 * 说明：
 *   ① 坐标转换问题已修正。
 *   ② trail[] 数组现在正确地存储全局坐标，并在绘制时转换回局部坐标。
 *===================================================================*/
_root.联弹系统.横向拖尾联弹初始化 = function (clip:MovieClip):Void
{
    /* ---------- ① 基础字段 ---------- */

    clip.单元体列表     = [];
    clip.运动方向系数   = (clip._parent.xmov < 0) ? -1 : 1;
    clip.y_基准         = clip._y;
    clip.余弦值         = Math.cos(clip._parent._rotation * Math.PI / 180);

    var 子弹种类:String  = String(clip._parent.子弹种类).split("-")[1];

    /* ---------- ② 生成子弹 ---------- */
    for (var i:Number = 0;
         (i < clip._parent.霰弹值) && (clip._parent.flag == undefined);
         i++)
    {
        var b:MovieClip = _root.创建单元体(clip._parent, 子弹种类);

        b._rotation = _root.随机偏移(clip._parent.子弹散射度);
        b.trail     = []; // 拖尾轨迹将存储【全局坐标】
        clip.单元体列表.push(b);
    }


    /* ---------- ③ 帧循环 ---------- */
    clip.onEnterFrame = function ():Void
    {
        /* 3‑1 更新子弹 (此部分无需改变) --------------------------------*/
        var y_min:Number = Infinity;
        var y_max:Number = -Infinity;

        // 检查霰弹值变化，移除多余的单元体
        while (this.单元体列表.length > this._parent.霰弹值 && this.单元体列表.length > 1) {
            var excessBullet:MovieClip = this.单元体列表.pop();
            _root.回收单元体(excessBullet);
        }

        for (var j:Number = this.单元体列表.length - 1; j >= 0; j--)
        {
            var b:MovieClip = this.单元体列表[j];
            b._y += this._parent.xmov * Math.sin(b._rotation * Math.PI / 180) * this.运动方向系数;

            if ( b._y * this.余弦值 + this._parent._y > this._parent.Z轴坐标 && this.单元体列表.length > 1 )
            {
                _root.回收单元体(b);
                this.单元体列表.splice(j, 1);
                this._parent.霰弹值--;
                continue;
            }

            y_max = Math.max(b._y, y_max);
            y_min = Math.min(b._y, y_min);
        }

        /* 3‑2 绘制拖尾 (核心修正) --------------------------------------*/
        this.clear();
        this.moveTo(0, 0); 

        for (var k:Number = 0; k < this.单元体列表.length; k++)
        {
            var bullet:MovieClip = this.单元体列表[k];

            /* —— 【核心修正】采样当前位置时，使用正确的父级进行坐标转换 —— */
            // 1. 获取子弹相对于其父级(clip._parent)的坐标
            var global_p:Object = {x: bullet._x, y: bullet._y};
            
            // 2. 【重点】必须使用子弹的真正父级(this._parent)来调用localToGlobal
            this._parent.localToGlobal(global_p);

            /* —— trail[] 维护最近 8 帧的全局坐标 —— */
            bullet.trail.unshift(global_p);
            if (bullet.trail.length > 8) bullet.trail.pop();

            /* —— 绘制部分 (此部分逻辑不变，但优化了渐变算法) —— */
            if (bullet.trail.length > 1)
            {
                // 循环绘制后续线段
                for (var t:Number = 0; t < bullet.trail.length - 1; t++)
                {
                    // 将存储的全局坐标点，转换为当前clip的局部坐标用于绘制
                    var local_p1:Object = {x: bullet.trail[t].x, y: bullet.trail[t].y};
                    var local_p2:Object = {x: bullet.trail[t+1].x, y: bullet.trail[t+1].y};
                    this.globalToLocal(local_p1);
                    this.globalToLocal(local_p2);
                    
                    // 为8帧的拖尾（7个线段）优化渐变效果
                    var alpha:Number = 100 - t * 15;
                    var width:Number = 2.5 - t * 0.3;
                    if (width < 0.5) width = 0.5; // 确保线条不会完全消失

                    this.lineStyle(width, 0xFFFFFF, alpha);
                    this.moveTo(local_p1.x, local_p1.y);
                    this.lineTo(local_p2.x, local_p2.y);
                }
            }
        }

        /* 3‑3 更新碰撞箱 (此部分无需改变) -------------------------------*/
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
        var isHitMap:Boolean = Mover.isMovieClipValid(this);
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
                
                isHitGround = (unit._y * parentCos + currentParentY > hitZ);
                isHIt = isHitMap && !Mover.isMovieClipPositionValid(unit);
                if ((isHIt || isHitGround) && (this.单元体列表.length > 1)) {
                    _root.回收单元体(unit);
                    this.单元体列表.splice(j, 1);
                    continue;
                }
                
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
                
                isHitGround = (unit._y * parentCos + currentParentY > hitZ);
                isHIt = isHitMap && !Mover.isMovieClipPositionValid(unit);
                if ((isHIt || isHitGround) && (this.单元体列表.length > 1)) {
                    _root.回收单元体(unit);
                    this.单元体列表.splice(j, 1);
                    continue;
                }
                
                if (unit._y > y_max) y_max = unit._y;
                if (unit._y < y_min) y_min = unit._y;
            }
        }
        
        // 始终更新Y轴碰撞箱
        this._y = y_min;
        this._height = Math.max(this.y_基准 * -2, y_max - y_min);
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
