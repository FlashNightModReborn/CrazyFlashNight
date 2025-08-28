import org.flashNight.neur.Event.*;

_root.装备引用配置 = {};

// 定义巨拳模式下需要排除的引用名集合
_root.装备引用配置.巨拳排除引用 = {
    右下臂_引用: true,
    左下臂_引用: true
};

// 需要等待加载完成才发布事件的装备
_root.装备引用配置.需要同步的装备 = {
    长枪_引用: true,
    刀_引用: true,
    手枪_引用: true
};

_root.装备引用配置.配置装扮 = function(movieClip:MovieClip, 
                                     skinConfig:String, 
                                     instanceName:String, 
                                     referenceName:String):MovieClip {
    var unit:MovieClip = movieClip._parent._parent._parent;
    if (!skinConfig) {
        unit[referenceName] = null;
        return null;
    }

    // 检查巨拳模式下是否需要排除
    if (unit.空手动作类型 == "巨拳") {
        if (_root.装备引用配置.巨拳排除引用[referenceName]) {
            return null;
        }
    }

    var skin:MovieClip = movieClip.attachMovie(skinConfig, instanceName, movieClip.getNextHighestDepth());

    unit[referenceName] = skin || null;
    
    // 检查是否是需要同步的装备
    if (_root.装备引用配置.需要同步的装备[referenceName]) {
        var currentFrame = _root.帧计时器.当前帧数;
        
        // 初始化装备加载状态
        if (!unit.装备加载状态) {
            unit.装备加载状态 = {};
        }
        
        // 记录该装备已加载
        unit.装备加载状态[referenceName] = currentFrame;
        
        // 检查所有需要同步的装备是否都已加载
        var allLoaded = true;
        for (var key in _root.装备引用配置.需要同步的装备) {
            if (unit[key] !== undefined && unit.装备加载状态[key] !== currentFrame) {
                allLoaded = false;
                break;
            }
        }
        
        // 如果所有需要同步的装备都在当前帧加载完成，发布事件
        if (allLoaded && unit.lastStatusChangeFrame < currentFrame) {
            unit.lastStatusChangeFrame = currentFrame;
            var dispatcher:EventDispatcher = unit.dispatcher;
            dispatcher.publish("StatusChange", unit);
        }
    }
    
    return unit[referenceName];
}
