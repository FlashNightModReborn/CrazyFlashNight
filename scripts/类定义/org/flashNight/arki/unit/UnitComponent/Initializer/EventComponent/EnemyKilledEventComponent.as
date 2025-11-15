import org.flashNight.neur.Event.EventDispatcher;
import org.flashNight.arki.unit.UnitComponent.Targetcache.FactionManager;
import org.flashNight.arki.unit.UnitUtil;
import org.flashNight.gesh.object.ObjectUtil;

/**
 * 主角阵营击杀统计事件组件
 * 负责在主角阵营单位上订阅 enemyKilled 事件，并更新全局击杀统计。
 *
 * @class EnemyKilledEventComponent
 * @package org.flashNight.arki.unit.UnitComponent.Initializer.EventComponent
 */
class org.flashNight.arki.unit.UnitComponent.Initializer.EventComponent.EnemyKilledEventComponent {

    /**
     * 初始化当前单位的击杀统计事件监听
     * @param target {MovieClip} 单位 MovieClip（可能是玩家、佣兵或敌人）
     */
    public static function initialize(target:MovieClip):Void {
        var dispatcher:EventDispatcher = target.dispatcher;
        if (!dispatcher) return;

        // 只在主角阵营单位上订阅 enemyKilled
        var faction:String = FactionManager.getFactionFromUnit(target);
        if (faction != FactionManager.FACTION_PLAYER) {
            return;
        }

        // 订阅 enemyKilled 事件，回调 scope 绑定为 shooter（即 target 本身）
        dispatcher.subscribe("enemyKilled", EnemyKilledEventComponent.onEnemyKilled, target);
    }

    /**
     * enemyKilled 事件回调
     * @param hitTarget {MovieClip} 被击杀的单位
     * @param bullet {MovieClip} 造成击杀的子弹/攻击体
     */
    public static function onEnemyKilled(hitTarget:MovieClip, bullet:MovieClip):Void {

        // 判断被击杀目标的阵营，只统计敌对目标
        var targetFaction:String = FactionManager.getFactionFromUnit(hitTarget);
        if (targetFaction == FactionManager.FACTION_PLAYER) return;

        // 计算兵种标识（使用 UnitUtil 中的通用方法）
        var typeKey:String = UnitUtil.getUnitTypeKey(hitTarget);

        // 更新总击杀数
        _root.killStats.total = Number(_root.killStats.total) + 1;

        // 更新按兵种统计
        var map:Object = _root.killStats.byType;
        if (map[typeKey] == undefined) {
            map[typeKey] = 1;
        } else {
            map[typeKey] = Number(map[typeKey]) + 1;
        }

        // 标记存档数据已变更
        _root.存档系统.dirtyMark = true;

        // _root.服务器.发布服务器消息("[KillStats] ", typeKey ,ObjectUtil.toString(_root.killStats) );
    }
}