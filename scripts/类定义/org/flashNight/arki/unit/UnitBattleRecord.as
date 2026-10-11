import org.flashNight.arki.scene.StageRunSession;
import org.flashNight.arki.unit.UnitUtil;
import org.flashNight.arki.unit.UnitComponent.Targetcache.FactionManager;

/** 单位实例身份与每条生命的战报事实。MovieClip 路径和头像键均不作为实例身份。 */
class org.flashNight.arki.unit.UnitBattleRecord {
    private static var _sequence:Number = 0;

    public static function initialize(target:MovieClip):Void {
        if (target.element) return;
        var state:Object = stateFor(target);
        if (state.subscribed === true) return;
        state.subscribed = true;
        // 不用 subscribeSingle，保留 DeathEventComponent 的原有死亡清理订阅。
        if (target.dispatcher != undefined) {
            target.dispatcher.subscribe("death", UnitBattleRecord.onDown, target);
        }
    }

    private static function stateFor(target:MovieClip):Object {
        var state:Object = target.__battleRecord;
        if (state == undefined) {
            _sequence++;
            state = {unitId:"unit." + getTimer() + "." + _sequence,
                life:0, down:false, killReported:false, snapshot:null, allyToken:null};
            target.__battleRecord = state;
        }
        return state;
    }

    private static function text(value, maximum:Number):String {
        var result:String = value == null ? "" : String(value);
        // 战报及持久化边界不接受控制字符；外观/物品键本身不作目录重写。
        var clean:String = "";
        for (var i:Number = 0; i < result.length && clean.length < maximum; i++) {
            var code:Number = result.charCodeAt(i);
            if (code >= 32 && code != 127) clean += result.charAt(i);
        }
        return clean;
    }

    private static function itemText(value):String {
        if (value instanceof Array) value = value[0];
        else if (value != null && typeof value == "object") value = value.name;
        var name:String = text(value, 128);
        var info:Object = _root.物品属性列表[name];
        return info != undefined && info.displayname != undefined
            ? text(info.displayname, 128) : name;
    }

    public static function snapshot(target:MovieClip):Object {
        var state:Object = stateFor(target);
        var key:String = text(UnitUtil.getUnitTypeKey(target), 128);
        var individual:Boolean = target.hasDressup === true
            || key.indexOf("主角-") == 0;
        var info:Object = _root.敌人属性表[key];
        var name:String = text(target.名字, 96);
        var icon:String = "";
        if (!individual && info != undefined && info.displayname != undefined) {
            if (FactionManager.getFactionFromUnit(target) != FactionManager.FACTION_PLAYER || name == "") {
                name = text(info.displayname, 96);
            }
            icon = key;
        } else if (key.indexOf("敌人-") == 0) icon = key;
        if (name == "") name = key;
        var doll:Object = null;
        var loadout:Object = null;
        if (individual) {
            doll = {face:text(target.脸型,128), hair:text(target.发型,128),
                mask:text(target.面具,128), head:text(target.头部装备,128),
                body:text(target.上装装备,128), leg:text(target.下装装备,128),
                hand:text(target.手部装备,128), foot:text(target.脚部装备,128),
                neck:text(target.颈部装备,128), gender:text(target.性别,128)};
            loadout = {head:itemText(target.头部装备), body:itemText(target.上装装备),
                leg:itemText(target.下装装备), hand:itemText(target.手部装备),
                foot:itemText(target.脚部装备), neck:itemText(target.颈部装备),
                primary:itemText(target.长枪), secondary1:itemText(target.手枪),
                secondary2:itemText(target.手枪2), melee:itemText(target.刀),
                grenade:itemText(target.手雷)};
        }
        var level:Number = Number(target.等级);
        if (isNaN(level) || level < 0) level = 0;
        level = Math.min(9999, Math.floor(level));
        return {key:key, displayName:name, iconName:icon, doll:doll,
            eliteLevel:UnitUtil.getEliteLevel(target), individual:individual,
            unitId:state.unitId, level:level, loadout:loadout};
    }

    public static function snapshotAtDeath(target:MovieClip):Object {
        var state:Object = stateFor(target);
        return state.snapshot == null ? snapshot(target) : state.snapshot;
    }

    public static function onDown(target:MovieClip):Void {
        if (target == undefined || target.element || target.斗兽标定隔离 === true
                || isNaN(Number(target.hp)) || Number(target.hp) > 0) return;
        var state:Object = stateFor(target);
        if (state.down) return;
        state.down = true;
        state.snapshot = snapshot(target);
        if (FactionManager.getFactionFromUnit(target) != FactionManager.FACTION_PLAYER) return;
        var hero:Boolean = target._name === _root.控制目标;
        var token:Object = StageRunSession.recordAllyDown(state.snapshot, hero, state.allyToken);
        state.allyToken = token;
        // 每条生命独立 operationId 和 itemKey；离线也先写战报事实。
        if (typeof _root.发布物资变更消息 == "function") {
            var eventId:String = state.unitId + ".down." + state.life;
            _root.发布物资变更消息("loss", "casualty", eventId, 1,
                "ally_casualty", "", state.snapshot.iconName, eventId, "unit_life",
                hero ? "hero_down" : "ally_down", state.snapshot.doll, 0, 1,
                String(state.snapshot.displayName).substr(0, 61) + " 倒地");
        }
    }

    public static function onRevive(target:MovieClip):Void {
        if (target == undefined || !(target.hp > 0)) return;
        var state:Object = target.__battleRecord;
        if (state == undefined || !state.down) return;
        StageRunSession.recordAllyRevive(state.allyToken);
        state.down = false;
        state.killReported = false;
        state.snapshot = null;
        state.life++;
        // 装备直接恢复主角 HP 时也要同步原生关卡结果卡的 life 轴。
        if (target._name === _root.控制目标) StageRunSession.onHeroRespawn(target);
    }

    public static function onRetire(target:MovieClip):Void {
        onDown(target);
        var state:Object = target.__battleRecord;
        if (state != undefined && state.down && target.死亡撤退 === true) {
            StageRunSession.recordAllyRetreat(state.allyToken);
        }
    }

    public static function claimPlayerKill(target:MovieClip):Boolean {
        if (target == undefined || target.element || target.斗兽标定隔离 === true
                || !(target.hp <= 0)) return false;
        onDown(target);
        var state:Object = stateFor(target);
        if (state.killReported) return false;
        state.killReported = true;
        return true;
    }
}
