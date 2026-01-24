import org.flashNight.neur.Event.*;

_root.装备引用配置 = {};

// 定义巨拳模式下需要排除的引用名集合
// _root.装备引用配置.巨拳排除引用 = {
//     右下臂_引用: true,
//     左下臂_引用: true
// };
_root.装备引用配置.巨拳排除引用 = {
    单臂巨拳: {
        右下臂_引用: true
    },
    巨拳: {
        右下臂_引用: true,
        左下臂_引用: true
    }
};

// 定义各引用名对应的固定深度，未在此处定义的引用名将使用默认深度0
_root.装备引用配置.引用深度配置 = {
    发型_引用: 1,
    面具_引用: 2
}

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
    if (unit.空手动作类型 == "巨拳" || unit.空手动作类型 == "单臂巨拳" ) {
        if (_root.装备引用配置.巨拳排除引用[unit.空手动作类型][referenceName]) {
            return null;
        }
    }

    unit[referenceName] = movieClip.attachMovie(skinConfig,
                                                instanceName,
                                                _root.装备引用配置.引用深度配置[referenceName]) || null;

    // 仅在有订阅者注册了该引用的同步标签时才发布事件
    if (unit.syncRefs[referenceName]) {
        unit.dispatcher.publish(referenceName, unit);
    }

    return unit[referenceName];
}
