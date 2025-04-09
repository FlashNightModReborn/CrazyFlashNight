import org.flashNight.arki.render.*;
import org.flashNight.arki.spatial.transform.*;
import org.flashNight.sara.util.*;

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
_root.刀光系统.刀引用绘制刀光 = function(自机:MovieClip, 影片剪辑:MovieClip, 刀光样式名:String) {
    var 刀口集合 = [];
    var map:MovieClip = _root.gameworld.deadbody;
    var rawData = [];
    
    // 收集所有合法的碰撞箱数据（假设影片剪辑上有“刀口位置1” ~ “刀口位置5”）
    for (var i = 1; i <= 5; i++) {
        var 当前刀口 = 影片剪辑["刀口位置" + i];
        if (当前刀口 && 当前刀口._x != undefined) {
            // 取得碰撞箱的边界框
            var rect:Object = 当前刀口.getRect(当前刀口);
            
            // 取碰撞箱左下角点（xMin, yMax），并进行坐标转换
            var pt1:Object = { x: rect.xMin, y: rect.yMax };
            当前刀口.localToGlobal(pt1);
            map.globalToLocal(pt1);
            var p1 = { x: pt1.x, y: pt1.y };
            
            // 取碰撞箱右上角点（xMax, yMin），进行转换后构造一个“顶点”
            var pt3:Object = { x: rect.xMax, y: rect.yMin };
            当前刀口.localToGlobal(pt3);
            map.globalToLocal(pt3);
            var p3 = { x: pt3.x, y: pt3.y };
            
            // 构造0号点：使用 p3.x 与 p1.y 保持水平（原始逻辑）
            var p0 = { x: p3.x, y: p1.y };
            
            // 以 p0 与 p1 求得碰撞箱“顶边”中点及半宽作为数值参考
            var mid = { x: (p0.x + p1.x) / 2, y: (p0.y + p1.y) / 2 };
            var dx = p1.x - p0.x;
            var dy = p1.y - p0.y;
            var halfWidth = Math.sqrt(dx * dx + dy * dy) / 2;
            
            rawData.push({ p0: p0, p1: p1, mid: mid, halfWidth: halfWidth });
        }
    }
    
    // 只有至少有一个碰撞箱时才继续处理
    if (rawData.length > 0) {
        // 利用所有合法碰撞箱的中点，取第一个与最后一个构造理想刀身中轴
        var start = rawData[0].mid;
        var end = rawData[rawData.length - 1].mid;
        var d = { x: end.x - start.x, y: end.y - start.y };
        var dLen = Math.sqrt(d.x * d.x + d.y * d.y);
        if (dLen == 0) {
            d = { x: 1, y: 0 };
            dLen = 1;
        }
        // 得到理想中轴方向的单位切向量
        var u = { x: d.x / dLen, y: d.y / dLen };
        
        // 收缩系数，用以将碰撞箱边界点“内收”，使刀光更贴合刀身视觉（根据需要微调）
        var contractionFactor = 0.3;
        
        // 对每个碰撞箱数据进行处理：投影中点到理想中轴，并根据 collision box 的半宽用切向量偏移
        for (var j = 0; j < rawData.length; j++) {
            var data = rawData[j];
            // 计算从中轴起点 start 到碰撞箱中点的向量 v
            var v = { x: data.mid.x - start.x, y: data.mid.y - start.y };
            // 计算 v 在 u 方向上的投影长度（点积）
            var projectionLength = v.x * u.x + v.y * u.y;
            // 得到中点在理想中轴上的投影 m_ideal
            var m_ideal = { x: start.x + u.x * projectionLength, y: start.y + u.y * projectionLength };
            
            // 修改后的边缘点采用 u（切向量）方向偏移，
            // 使得最终刀光的两个边缘与刀身理想路径平行
            var offset = Math.max(data.halfWidth * contractionFactor, 5);
            var new_p0 = { x: m_ideal.x - u.x * offset, y: m_ideal.y - u.y * offset };
            var new_p1 = { x: m_ideal.x + u.x * offset, y: m_ideal.y + u.y * offset };
            
            刀口集合.push({ edge1: new_p0, edge2: new_p1 });
        }
        
        // 最后使用自机的 _name 作为发射者ID，将优化后的刀口集合提交给 TrailRenderer 绘制刀光
        TrailRenderer.getInstance().addTrailData(自机._name, 刀口集合, 刀光样式名);
    }
};




//-----------------------------------------------------------------------
// 清理内存，转调 TrailRenderer
//-----------------------------------------------------------------------
_root.刀光系统.清理内存 = function(forceCleanAll:Boolean, maxInactiveFrames:Number) {
    return TrailRenderer.getInstance().cleanMemory(forceCleanAll, maxInactiveFrames);
};

TrailRenderer.getInstance().initStyles();