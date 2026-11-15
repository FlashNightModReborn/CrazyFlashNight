
// UI系统 是跨帧共享命名空间；禁止在后置 UI 初始化阶段整对象重置，
// 否则会抹掉早期注册的 NPC 商店等 WebView 服务。
_root.UI系统 = _root.UI系统 || {};
/**
 * 防御性刷新：确保等级经验值阈值已设置并刷新UI
 * 用于防止加载顺序问题导致UI显示默认值（如999）
 *
 * @return Boolean 如果成功刷新返回true，否则返回false
 */
_root.UI系统.防御性刷新等级经验 = function():Boolean {
    // 验证等级数据有效性
    if(isNaN(_root.等级) || _root.等级 <= 0) {
        return false;
    }

    // 检查并设置缺失的阈值
    if(isNaN(_root.升级需要经验值) || isNaN(_root.上次升级需要经验值)) {
        _root.升级需要经验值 = _root.根据等级得升级所需经验(_root.等级);
        _root.上次升级需要经验值 = _root.等级 > 1 ? _root.根据等级得升级所需经验(_root.等级 - 1) : 0;
    }

    // 触发UI刷新
    if(_root.玩家信息界面 && _root.玩家信息界面.刷新经验值显示) {
        _root.玩家信息界面.刷新经验值显示();
        return true;
    }

    return false;
}
