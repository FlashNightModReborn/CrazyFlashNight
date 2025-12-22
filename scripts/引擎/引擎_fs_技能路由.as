/**
 * 技能路由器 - Step 1: 转发型API
 *
 * 目的：将所有"技能启动的跳帧入口"收口到统一路由，
 *       为后续容器化改造提供切入点。
 *
 * 当前版本：仅执行旧逻辑（gotoAndPlay到原技能帧），确保玩法零变化。
 *
 * API说明：
 *   - 技能标签跳转_旧(unit, skillName): 从外部触发技能跳帧
 *   - 技能man载入后跳转_旧(man, unit): man加载完成后跳转到技能帧
 *
 * @author fs
 * @version 1.0 - Step 1 旧逻辑转发
 */

_root.技能路由 = {};

/** 
 * 技能标签跳转（旧实现）
 * 用于外部代码触发技能时调用，如释放行为、AI释放等场景
 *
 * @param unit:MovieClip 执行技能的单位（需要有man子剪辑）
 * @param skillName:String 技能名称（对应man时间轴上的帧标签）
 */
_root.技能路由.技能标签跳转_旧 = function(unit:MovieClip, skillName:String):Void {
    _root.发布消息("路由技能标签跳转", skillName);
    unit.man.gotoAndPlay(skillName);
};

/**
 * 技能man载入后跳转（旧实现）
 * 用于man剪辑加载完成后，根据unit.技能名跳转到对应帧
 * 典型场景：主角进入"技能"状态时，man加载后的第一帧调用
 *
 * @param man:MovieClip man剪辑自身
 * @param unit:MovieClip man的父级单位（通过unit.技能名获取目标帧）
 */
_root.技能路由.技能man载入后跳转_旧 = function(man:MovieClip, unit:MovieClip):Void {
    _root.发布消息("路由技能man载入后跳转", unit.技能名);
    man.gotoAndPlay(unit.技能名);
};
