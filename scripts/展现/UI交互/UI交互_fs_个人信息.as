import org.flashNight.arki.unit.UnitComponent.Targetcache.*;
import org.flashNight.arki.component.StatHandler.*;
import org.flashNight.arki.unit.Action.Shoot.*;
import org.flashNight.arki.unit.*;

// ========================================
// 重构说明：
// 核心逻辑已迁移至 PlayerInfoProvider 类
// 本脚本仅保留 _root.人物信息函数.获取人物信息 作为入口点
// 所有计算逻辑通过 PlayerInfoProvider 静态方法实现
// ========================================

_root.人物信息函数 = new Object();

/**
 * 获取人物信息 - 主入口函数
 * 将玩家的所有属性信息填充到目标UI对象上
 *
 * 注：此函数直接转发到 PlayerInfoProvider.populatePlayerInfo
 * 保持此接口是为了向后兼容现有的UI调用
 *
 * @param 目标 UI目标MovieClip
 */
_root.人物信息函数.获取人物信息 = function(目标:MovieClip):Void {
	PlayerInfoProvider.populatePlayerInfo(目标);
};
