import org.flashNight.arki.render.*;
import org.flashNight.arki.spatial.transform.*;
import org.flashNight.sara.util.*;
import org.flashNight.neur.Event.*;

//----------------------------------------------------
// 刀光系统：只做“刀口采集与提交”，并调用 TrailRenderer 进行拖影管理
//----------------------------------------------------
_root.刀光系统 = {};

//-----------------------------------------------------------------------
// 对外接口：绘制刀本体及其刀光
//-----------------------------------------------------------------------
_root.刀光系统.绘制刀及其刀光 = function(影片剪辑:MovieClip, 刀光样式名:String, 参数:Object) {
    // 1. 绘制刀本体
    _root.残影系统.绘制元件(影片剪辑.man.刀, 参数);
    // 2. 采集刀口位置并提交给 TrailRenderer
    this.绑定并绘制刀光(影片剪辑, 刀光样式名);
};

//-----------------------------------------------------------------------
// 对外接口：绘制人物及其刀光
//-----------------------------------------------------------------------
_root.刀光系统.绘制人物及其刀光 = function(影片剪辑:MovieClip, 刀光样式名:String, 参数:Object) {
    // 1. 绘制人物主体
    _root.残影系统.绘制元件(影片剪辑, 参数);
    // 2. 采集刀口位置并提交给 TrailRenderer
    this.绑定并绘制刀光(影片剪辑, 刀光样式名);
};

//-----------------------------------------------------------------------
// 收集刀口位置并调用 TrailRenderer
//-----------------------------------------------------------------------
_root.刀光系统.绑定并绘制刀光 = function(mc:MovieClip, style:String) {
    var 刀口集合 = [];
    var 装扮 = mc.man.刀.刀.装扮;
    var gameworld:MovieClip = _root.gameworld; // 缓存引用
    var tempPoint:Vector = new Vector(0, 0);

    for (var i = 1; i <= 5; i++) {
        var 当前刀口 = 装扮["刀口位置" + i];
        if (!当前刀口 || 当前刀口._x == undefined) continue;

        // 完全内联版本 ----------------------------------------------------
        var rect = 当前刀口.getRect(当前刀口);
        
        // 转换edge1
        tempPoint.x = rect.xMax;
        tempPoint.y = rect.yMax;
        当前刀口.localToGlobal(tempPoint);
        gameworld.globalToLocal(tempPoint);
        var edge1 = new Vector(tempPoint.x, tempPoint.y);
        
        // 转换edge3
        tempPoint.x = rect.xMin;
        tempPoint.y = rect.yMin;
        当前刀口.localToGlobal(tempPoint); // 复用对象避免内存分配
        gameworld.globalToLocal(tempPoint);
        var edge3 = new Vector(tempPoint.x, tempPoint.y);
        // ----------------------------------------------------------------
        
        刀口集合.push({ edge1: edge1, edge2: edge3 });
    }
    
    if (刀口集合.length > 0) {
        TrailRenderer.getInstance().addTrailData(mc._name, 刀口集合, style);
    }
};

//-----------------------------------------------------------------------
// 针对独立刀对象的绘制（与上面逻辑类似）
//-----------------------------------------------------------------------
_root.刀光系统.刀引用绘制刀光 = function(自机:MovieClip, 影片剪辑:MovieClip, 刀光样式名:String)
{
    // --- 以下是集中在函数顶部的变量声明与缓存 ---
    var map:MovieClip = _root.gameworld.deadbody;
    var rawData:Array = [];
    var 刀口集合:Array = [];

    // 循环相关
    var i:Number, j:Number;
    // 碰撞箱读取相关临时对象
    var 当前刀口:MovieClip;
    var rect:Object;
    var pt1:Object = { x:0, y:0 };
    var pt3:Object = { x:0, y:0 };
    // 存储计算过程中的 x, y, dx, dy 等
    var p0:Object;  // 此处依然会在循环里创建新对象保存
    var mid:Object = { x:0, y:0 };
    var dx:Number, dy:Number, halfWidth:Number;

    // ---------------------------------------------
    // 1) 收集碰撞箱数据
    // ---------------------------------------------
    for (i = 1; i <= 5; i++)
    {
        当前刀口 = 影片剪辑["刀口位置" + i];
        if (当前刀口 && 当前刀口._x != undefined)
        {
            // 获取碰撞箱边界
            rect = 当前刀口.getRect(当前刀口);

            // 利用复用对象 pt1 / pt3 做局部坐标转换
            pt1.x = rect.xMin;
            pt1.y = rect.yMax;
            当前刀口.localToGlobal(pt1);
            map.globalToLocal(pt1);

            pt3.x = rect.xMax;
            pt3.y = rect.yMin;
            当前刀口.localToGlobal(pt3);
            map.globalToLocal(pt3);

            // 生成 p1, p3, p0, mid 等
            // 这里 p1 与 p3 直接用拷贝形式，避免后面复用 pt1/pt3 时产生冲突
            var p1:Object = { x: pt1.x, y: pt1.y };
            var p3:Object = { x: pt3.x, y: pt3.y };
            p0 = { x: p3.x, y: p1.y }; // 每次都 new 一个新对象

            mid.x = (p0.x + p1.x) / 2;
            mid.y = (p0.y + p1.y) / 2;

            dx = p1.x - p0.x;
            dy = p1.y - p0.y;
            halfWidth = Math.sqrt(dx * dx + dy * dy) * 0.5;

            // 把结果存进 rawData：同样要 new 对象拷贝
            rawData.push({
                p0: { x:p0.x, y:p0.y },
                p1: { x:p1.x, y:p1.y },
                mid: { x:mid.x, y:mid.y },
                halfWidth: halfWidth
            });
        }
    }

    // ---------------------------------------------
    // 2) 后续处理与刀光绘制
    // ---------------------------------------------
    var len:Number = rawData.length;
    if (len > 0)
    {
        // 取第一个与最后一个的 mid 构造中轴
        var start:Object = rawData[0].mid;
        var end:Object   = rawData[len - 1].mid;

        var d:Object = { x:end.x - start.x, y:end.y - start.y };
        var dLen:Number = Math.sqrt(d.x*d.x + d.y*d.y);
        if (dLen == 0)
        {
            d.x = 1;
            d.y = 0;
            dLen = 1;
        }
        // 中轴方向单位向量
        var ux:Number = d.x / dLen;
        var uy:Number = d.y / dLen;

        // 收缩系数
        var contractionFactor:Number = 0.3;

        // 声明复用的临时对象
        var v:Object = { x:0, y:0 };
        var m_ideal:Object = { x:0, y:0 };
        var offset:Number, projectionLength:Number;
        var ox:Number, oy:Number;  // 用来缓存 offset * ux/uy

        // 这里依然保留顺序遍历
        for (j = 0; j < len; j++)
        {
            var data:Object = rawData[j];

            // v = data.mid - start
            v.x = data.mid.x - start.x;
            v.y = data.mid.y - start.y;
            // 投影长度
            projectionLength = v.x * ux + v.y * uy;

            // m_ideal = start + (u * projectionLength)
            m_ideal.x = start.x + ux * projectionLength;
            m_ideal.y = start.y + uy * projectionLength;

            // 偏移量，避免刀光“瘪”到看不见，所以取最大值 5
            offset = Math.max(data.halfWidth * contractionFactor, 5);

            // 预先计算 offset * ux / uy
            ox = offset * ux;
            oy = offset * uy;

            // 生成新的 p0 / p1 作为刀光边缘（同样要 new）
            var new_p0:Object = { x:m_ideal.x - ox, y:m_ideal.y - oy };
            var new_p1:Object = { x:m_ideal.x + ox, y:m_ideal.y + oy };

            刀口集合.push({
                edge1: new_p0,
                edge2: new_p1
            });
        }

        // 取一次 TrailRenderer 实例
        var tr:TrailRenderer = TrailRenderer.getInstance();
        // 用自机的 _name 作为发射者ID
        tr.addTrailData(自机._name, 刀口集合, 刀光样式名);
    }
};



//-----------------------------------------------------------------------
// 清理内存，转调 TrailRenderer
//-----------------------------------------------------------------------
_root.刀光系统.清理内存 = function(forceCleanAll:Boolean, maxInactiveFrames:Number) {
    return TrailRenderer.getInstance().cleanMemory(forceCleanAll, maxInactiveFrames);
};

var trailRenderer:TrailRenderer = TrailRenderer.getInstance();
trailRenderer.initStyles();
EventBus.getInstance().subscribe("SceneChanged", trailRenderer.cleanMemory, trailRenderer); 
EventBus.getInstance().subscribe("SceneChanged", VectorAfterimageRenderer.instance.onSceneChanged
, VectorAfterimageRenderer.instance); 
