import org.flashNight.sara.util.*;
import org.flashNight.arki.spatial.move.*;

/**
 * 场景坐标管理系统
 * 
 * 职责：
 * 1. 管理游戏场景的坐标系转换参数
 * 2. 维护场景中心点坐标和安全区域半径
 * 3. 提供场景切换时的坐标参数更新功能
 * 
 * 功能特点：
 * - 所有属性和方法均为静态，全局唯一实例
 * - 自动计算场景偏移量/中心点/安全半径
 * - 需在场景切换后手动调用 update() 更新参数
 */
class org.flashNight.arki.spatial.transform.SceneCoordinateManager {
    /*---------------------------------------
    |   静 态 属 性 定 义
    ---------------------------------------*/
    
    /**
     * 场景偏移量（像素坐标系）
     * 表示场景坐标系到全局坐标系的偏移量
     * 格式：二维向量 (x, y)
     */
    public static var offset:Vector = new Vector(0, 0);
    public static var effectOffset:Vector = new Vector(0, 0);
    /**
     * 场景中心点坐标（游戏逻辑坐标系）
     * 格式：二维向量 (x, y)
     */
    public static var center:Vector = new Vector(0, 0);
    
    /**
     * 场景安全半径（游戏逻辑单位）
     * 表示以中心点为圆心，保证内容可见的圆形区域半径
     * 取场景短边长度的一半
     */
    public static var safeRadius:Number = 0;
    

    /*---------------------------------------
    |   核 心 功 能 方 法
    ---------------------------------------*/
    
    /**
     * 场景参数更新入口
     * 
     * 使用场景：
     * - 场景切换后
     * - 摄像机位置变化时
     * - 需要刷新坐标参数时
     * 
     * 执行顺序：
     * 1. 计算场景偏移量
     * 2. 计算场景中心点
     * 3. 计算安全半径
     */
    public static function update():Void {
        calculateOffset();
        calculateCenter();
        calculateEffectOffset();
        calculateSafeRadius();
        
        if(!Mover.initTag) Mover.init();
    }
    

    /*---------------------------------------
    |   偏 移 量 相 关 方 法
    ---------------------------------------*/
    
    /**
     * 计算场景偏移量
     * 
     * 实现逻辑：
     * 1. 获取地图容器引用
     * 2. 执行本地到全局再到父容器的坐标转换
     * 
     * 注意事项：
     * - 直接修改静态属性 offset
     * - 依赖 _root.gameworld 的舞台结构
     * 
     * @return Vector 计算后的偏移量（与静态属性 offset 指向同一对象）
     */
    public static function calculateOffset():Vector {
        offset.setTo(0, 0);
        
        // 获取场景容器引用
        var gw:MovieClip = _root.gameworld;
        var map:MovieClip = gw.地图;
        
        // 执行坐标系转换
        map.localToGlobal(offset);
        gw.globalToLocal(offset);
        
        return offset;
    }
    
    /**
     * 获取当前场景偏移量
     * 
     * @return Vector 当前偏移量（与静态属性 offset 指向同一对象）
     */
    public static function getOffset():Vector {
        return offset;
    }

    public static function calculateEffectOffset():Vector {
        effectOffset.setTo(0, 0);
        
        // 获取场景容器引用
        var gw:MovieClip = _root.gameworld;
        var db:MovieClip = gw.deadbody;
        var effect:MovieClip = gw.效果;
        
        // 执行坐标系转换
        effect.localToGlobal(effectOffset);
        db.globalToLocal(effectOffset);
        
        return effectOffset;
    }
    
    /**
     * 获取当前场景偏移量
     * 
     * @return Vector 当前偏移量（与静态属性 EffectOffset 指向同一对象）
     */
    public static function getEffectOffset():Vector {
        return effectOffset;
    }
    

    /*---------------------------------------
    |   中 心 点 相 关 方 法
    ---------------------------------------*/
    
    /**
     * 计算场景中心点
     * 
     * 实现逻辑：
     * - 取 X/Y 轴坐标范围的中间值
     * 
     * 数据来源：
     * - 依赖 _root 的 Xmin/Xmax/Ymin/Ymax 属性
     * 
     * 注意事项：
     * - 直接修改静态属性 center
     * 
     * @return Vector 计算后的中心点（与静态属性 center 指向同一对象）
     */
    public static function calculateCenter():Vector {
        center.setTo(
            (_root.Xmin + _root.Xmax) / 2,
            (_root.Ymin + _root.Ymax) / 2
        );
        return center;
    }
    
    /**
     * 获取当前场景中心点
     * 
     * @return Vector 当前中心点（与静态属性 center 指向同一对象）
     */
    public static function getCenter():Vector {
        return center;
    }
    

    /*---------------------------------------
    |   安 全 区 域 相 关 方 法
    ---------------------------------------*/
    
    /**
     * 计算场景安全半径
     * 
     * 实现逻辑：
     * - 取场景 X/Y 轴范围的较小值的一半
     * 
     * 数据来源：
     * - 依赖 _root 的 Xmin/Xmax/Ymin/Ymax 属性
     * 
     * 注意事项：
     * - 直接修改静态属性 safeRadius
     * 
     * @return Number 计算后的安全半径
     */
    public static function calculateSafeRadius():Number {
        var xRange:Number = _root.Xmax - _root.Xmin;
        var yRange:Number = _root.Ymax - _root.Ymin;
        safeRadius = Math.min(xRange, yRange) / 2;
        return safeRadius;
    }
    
    /**
     * 获取当前安全半径
     * 
     * @return Number 当前安全半径值
     */
    public static function getSafeRadius():Number {
        return safeRadius;
    }
}