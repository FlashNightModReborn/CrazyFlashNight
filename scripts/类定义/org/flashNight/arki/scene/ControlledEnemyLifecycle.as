import org.flashNight.arki.scene.StageReturnFlow;
import org.flashNight.arki.scene.StageRunSession;
import org.flashNight.arki.scene.LeeTrialDefinition;
import org.flashNight.arki.unit.UnitBattleRecord;

/** 当前临时角色的出生与死亡适配；动作和数值仍由原单位定义提供。 */
class org.flashNight.arki.scene.ControlledEnemyLifecycle {
    private static var _actionCooldowns:Object;
    public static function createSpawn(root:Object, x:Number, y:Number, includeAccount:Boolean):Object {
        var run:Object = root._saveExt.bookRun;
        var kind:String = root.特殊操作单位 != null && root.特殊操作单位 != ""
            ? String(root.特殊操作单位) : "主角-男";
        var parameters:Object = {_x:x, _y:y, 是否为敌人:false, respawn:true,
            身高:root.身高, 名字:root.角色名, 等级:root.等级, 性别:root.性别};
        if (includeAccount) parameters.用户ID = root.accId;
        if (run != null && run.bookId == "lee-trial") {
            var config:Object = LeeTrialDefinition.get();
            if (run.slot !== String(root.savePath) || run.outcome != "active" || config == null) return null;
            kind = config.actor.identifier;
            parameters.名字 = config.actor.name;
            parameters.等级 = config.actor.level;
            parameters.身高 = config.actor.height;
            parameters.性别 = config.actor.gender;
            // 不采用主角纸娃娃、装备或主角已学技能，玩家与AI共用原Lee数值/招式。
            parameters.__enemyActionPlayer = true;
            parameters.__enemyActionCooldownSession = actionCooldowns(run,
                StageRunSession.getRunAuthority(), String(root.savePath));
            parameters.宠物属性 = org.flashNight.gesh.object.PersistedSnapshot.clone(config.actor.宠物属性 || {});
            if (run.leeAssault.awakened === true) parameters.宠物属性.冲腿龙息 = true;
            parameters.mp = 0;
            parameters.mp满血值 = 0;
            parameters.允许拾取 = false;
            var context:Object = {slot:String(root.savePath), run:run,
                world:StageReturnFlow.worldIdentity(root.gameworld), handled:false};
            parameters.__controlledEnemyContext = context;
            parameters.__enemyActionOnDeath = deathCallback(context);
        }
        return {identifier:kind, parameters:parameters};
    }

    /** 仅内存中的本轮动作账；不写主角/临时角色存档，不跨新一局继承。 */
    public static function actionCooldowns(run:Object, stageRun:Object, slot:String):Object {
        if (run.bookId !== "lee-trial" || run.outcome !== "active" || run.slot !== slot
                || stageRun == null || stageRun.stageName !== LeeTrialDefinition.get().stageName
                || typeof stageRun.activeFrames != "number" || isNaN(stageRun.activeFrames)) return null;
        if (_actionCooldowns == null || _actionCooldowns.clock !== stageRun || _actionCooldowns.slot !== slot
                || _actionCooldowns.seed !== run.seed || _actionCooldowns.startedAt !== run.startedAt) {
            _actionCooldowns = {clock:stageRun, slot:slot, seed:run.seed,
                startedAt:run.startedAt, deadlines:{}};
        }
        return _actionCooldowns;
    }

    private static function deathCallback(context:Object):Function {
        return function(unit:Object):Boolean {
            return org.flashNight.arki.scene.ControlledEnemyLifecycle.onDeath(unit, context);
        };
    }

    /** 独立普通对象身份阻断同路径新世界/新单位收到旧死亡回调。 */
    public static function ownsContext(root:Object, unit:Object, context:Object):Boolean {
        return context != null && unit != null && unit.__controlledEnemyContext === context
            && context.slot === String(root.savePath) && context.run === root._saveExt.bookRun
            && context.run.slot === context.slot
            && context.run.bookId == "lee-trial" && unit._name === root.控制目标
            && unit._parent === root.gameworld
            && context.world === StageReturnFlow.worldIdentity(root.gameworld);
    }

    public static function onDeath(unit:Object, context:Object):Boolean {
        if (!ownsContext(_root, unit, context) || isNaN(Number(unit.hp)) || Number(unit.hp) > 0) return false;
        if (context.handled !== true) {
            context.handled = true;
            unit.已加经验值 = true;
            UnitBattleRecord.onDown(MovieClip(unit));
            StageRunSession.onHeroDeath();
        }
        // 保留主控实体给现役死亡结果/返回流程；不发经验、掉落或移除尸体。
        if (unit.状态 == "血腥死") unit.man.stop();
        return true;
    }
}
