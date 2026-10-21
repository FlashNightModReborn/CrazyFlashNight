import org.flashNight.arki.component.Shield.Shield;
import org.flashNight.arki.component.Buff.PodBuff;
import org.flashNight.arki.component.Buff.BuffCalculationType;
import org.flashNight.arki.unit.UnitComponent.Targetcache.TargetCacheManager;
import org.flashNight.arki.unit.UnitComponent.Targetcache.FactionManager;
import org.flashNight.arki.unit.UnitComponent.Initializer.EventComponent.AggroEventComponent;

/** One dog owns one energy layer. No shared shield, AI or damage rules change. */
class org.flashNight.arki.unit.UnitAI.Custom.WarlordDogController {
    public static var KIND:String = "敌人-军阀铁卫犬";
    public static var SHIELD_NAME:String = "铁卫犬能源护盾";
    public static var BUFF_ID:String = "iron-guard:shield-toughness";

    public static function install(root:Object):Void {
        root.铁卫犬 = {
            属性初始化:function():Void { _root.敌人函数.根据等级初始数值.call(this,this.等级); },
            初始化:function(unit:MovieClip):Boolean { return WarlordDogController.initialize(unit); },
            撕咬:function(unit:MovieClip):Void { WarlordDogController.bite(unit); }
        };
    }

    private static function clock():Number {
        return Number(_root.帧计时器.当前帧数);
    }

    public static function initialize(unit:MovieClip):Boolean {
        if (unit.__ironGuard) return !unit.__ironGuard.disposed;
        if (unit.NPC || unit._parent !== _root.gameworld || !(unit.hp > 0)) return false;
        var cfg:Object = unit.铁卫犬配置 || _root.敌人属性表[KIND].铁卫犬;
        var required:Array = ["shieldHpRatio","strengthAtkRatio","rechargeFrames",
            "rechargeFullFrames","rechargeDelay","toughnessBonus","teslaMultiplier","focusInterval"];
        for (var i:Number=0;i<required.length;i++) {
            if (!isFinite(Number(cfg[required[i]])) || !(Number(cfg[required[i]]) > 0)) {
                trace("[IronGuard] invalid config: " + required[i]); return false;
            }
        }
        if (!unit.shield || !unit.buffManager || !unit.dispatcher || !isFinite(clock())) return false;
        var c:Object = {unit:unit,world:unit._parent,version:unit.version,config:cfg,
            container:unit.shield,manager:unit.buffManager,dispatcher:unit.dispatcher,
            ready:false,disposed:false,busy:false,lastFrame:clock(),readyAt:0,
            focusAt:clock(),focusTarget:null,discharges:0,commands:0,bites:0};
        unit.__ironGuard = c;
        // Keep the legacy direction facade local to this actor, like other custom enemies.
        unit.myxscale = Math.abs(unit._yscale);
        unit.方向改变 = function(direction:String):Void {
            if (this.锁定方向 || (direction != "左" && direction != "右")) return;
            this.方向 = direction;
            this._xscale = direction == "右" ? this.myxscale : -this.myxscale;
            this.新版人物文字信息._xscale = direction == "右" ? 100 : -100;
        };
        unit.方向改变(unit.方向);
        var thinker:MovieClip = unit.createEmptyMovieClip("__ironGuardThink",unit.getNextHighestDepth());
        thinker.context = c;
        thinker.onEnterFrame = function():Void { WarlordDogController.tick(this.context); };
        thinker.onUnload = function():Void { WarlordDogController.dispose(this.context); };
        c.thinker = thinker;
        c.killHandler = function():Void { WarlordDogController.dispose(c); };
        c.dispatcher.subscribe("kill",c.killHandler,c);
        if (unit.铁卫犬关闭能力 !== true) activate(c);
        unit.gotoAndStop(unit.状态);
        return true;
    }

    private static function valid(c:Object):Boolean {
        return !c.disposed && c.unit.__ironGuard === c && c.unit.version === c.version &&
            c.unit._parent === c.world && c.world === _root.gameworld &&
            c.unit.shield === c.container && c.unit.buffManager === c.manager;
    }

    private static function ownsLayer(c:Object):Boolean {
        return c.layer && c.container.getShieldById(c.layer.getId()) === c.layer;
    }

    private static function activate(c:Object):Void {
        if (!valid(c) || !(c.unit.hp > 0) || c.ready) return;
        var capacity:Number = Math.max(1,Math.floor(c.unit.hp满血值*Number(c.config.shieldHpRatio)));
        var strength:Number = Math.max(1,c.unit.空手攻击力*Number(c.config.strengthAtkRatio));
        var layer:Shield = Shield.createRechargeable(capacity,strength,
            capacity/Number(c.config.rechargeFullFrames),Number(c.config.rechargeDelay),SHIELD_NAME);
        layer.setCallbacks({onBreak:function():Void { WarlordDogController.deplete(c,"broken"); }});
        c.layer = layer;
        if (!c.container.addShield(layer,true) || !ownsLayer(c)) {
            dispose(c); trace("[IronGuard] owned shield registration failed"); return;
        }
        var delta:Number = c.unit.基础韧性系数*Number(c.config.toughnessBonus);
        c.buffId = c.manager.addBuff(new PodBuff("韧性系数",BuffCalculationType.ADD_POSITIVE,delta),BUFF_ID);
        c.manager.update(0);
        c.ready = true;
        c.readyAt = 0;
        c.state = "charged";
        syncLamp(c);
    }

    private static function syncLamp(c:Object):Void {
        if (c.unit.__ironGuard !== c) return;
        var collar:MovieClip = c.unit.man.part200;
        if (collar) collar.gotoAndStop(c.ready && c.unit.hp > 0 ? 1 : 2);
    }

    public static function deplete(c:Object,reason:String):Void {
        if (c.disposed || !c.ready) return;
        c.ready = false;
        c.state = reason;
        c.readyAt = clock()+Number(c.config.rechargeFrames);
        if (c.buffId) { c.manager.removeBuff(c.buffId); c.buffId = null; c.manager.update(0); }
        var oldLayer:Shield = c.layer;
        c.layer = null;
        if (oldLayer && c.container.getShieldById(oldLayer.getId()) === oldLayer)
            c.container.removeShieldById(oldLayer.getId());
        syncLamp(c);
    }

    public static function tick(c:Object):Void {
        if (c.disposed) return;
        if (!valid(c) || !(c.unit.hp > 0)) { dispose(c); return; }
        syncLamp(c);
        if (_root.暂停) {
            var pausedFrames:Number = Math.max(0,clock()-c.lastFrame);
            if (c.readyAt > 0) c.readyAt += pausedFrames;
            c.focusAt += pausedFrames;
            c.lastFrame = clock();
            return;
        }
        if (clock() === c.lastFrame) return;
        c.lastFrame = clock();
        if (c.unit.铁卫犬关闭能力 === true) return;
        if (c.ready && (!ownsLayer(c) || !(c.layer.getCapacity() > 0))) deplete(c,"broken");
        if (!c.ready && c.readyAt > 0 && clock() >= c.readyAt) activate(c);
        var victim:MovieClip = c.world[c.unit.攻击目标];
        if (victim.hp > 0 && FactionManager.areUnitsEnemies(c.unit,victim) &&
            (victim !== c.focusTarget || victim.version !== c.focusTargetVersion) && clock() >= c.focusAt) command(c,victim);
    }

    public static function command(c:Object,victim:MovieClip):Void {
        if (!valid(c) || !(c.unit.hp > 0) || !(victim.hp > 0) || victim._parent !== c.world ||
            !FactionManager.areUnitsEnemies(c.unit,victim)) return;
        var allies:Array = TargetCacheManager.getCachedAlly(c.unit,0);
        var recipients:Number = 0;
        for (var i:Number=0;i<allies.length;i++) {
            var ally:MovieClip = allies[i];
            if (ally !== c.unit && ally._name != _root.控制目标 && ally.hp > 0 && !ally.NPC && !ally.element &&
                ally.unitAIType != "None" && ally.dispatcher && FactionManager.areUnitsEnemies(ally,victim)) {
                AggroEventComponent.onAggroSet(ally,victim); recipients++;
            }
        }
        c.focusTarget = victim;
        c.focusTargetVersion = victim.version;
        c.focusAt = clock()+Number(c.config.focusInterval);
        c.commands++;
        if (recipients > 0) _root.播放音效("狗叫-1.wav");
    }

    /** Called only by the preserved bite emitters in the native attack timeline. */
    public static function bite(unit:MovieClip):Void {
        var c:Object = unit.__ironGuard;
        if (!valid(c) || !(unit.hp > 0) || _root.暂停) return;
        var point:Object = {x:320,y:107};
        if (unit.man.part230) unit.man.part230.localToGlobal(point);
        else { point.x=unit._x; point.y=unit._y-unit.中心高度; c.world.localToGlobal(point); }
        c.world.globalToLocal(point);
        var props:Object = {声音:"",霰弹值:1,子弹散射度:0,发射效果:"",子弹种类:"近战子弹",
            子弹威力:unit.空手攻击力,子弹速度:0,Z轴攻击范围:30,击中地图效果:"",
            发射者:unit._name,shootX:point.x,shootY:point.y,shootZ:unit.Z轴坐标,
            击倒率:10,击中后子弹的效果:"空手攻击火花"};
        props.击中时触发函数 = function():Void { WarlordDogController.onBiteHit(c,this); };
        _root.子弹区域shoot传递(props);
        c.bites++;
    }

    public static function onBiteHit(c:Object,bullet:Object):Void {
        var victim:MovieClip = bullet.hitTarget;
        if (!valid(c) || !c.ready || c.busy || !(c.unit.hp > 0) || !ownsLayer(c) ||
            !(c.layer.getCapacity() > 0) || !(victim.hp > 0) || victim._parent !== c.world ||
            !FactionManager.areUnitsEnemies(c.unit,victim) || victim.魔法抗性.机械 === undefined) return;
        var unit:MovieClip = c.unit;
        // A fresh object deliberately does not inherit the bite callback.
        var props:Object = {声音:"",霰弹值:1,子弹散射度:0,发射效果:"",子弹种类:"磁暴射线",
            子弹威力:unit.空手攻击力*Number(c.config.teslaMultiplier),子弹速度:0,
            Z轴攻击范围:30,击中地图效果:"",发射者:unit._name,
            shootX:unit._x,shootY:unit._y-unit.中心高度*Math.abs(unit._yscale)/100,
            shootZ:unit.Z轴坐标,击倒率:10,击中后子弹的效果:"",
            伤害类型:"魔法",魔法伤害属性:"电",lockonTarget:victim};
        c.busy = true;
        var ray:Object = _root.子弹区域shoot传递(props);
        if (ray) { c.discharges++; deplete(c,"discharged"); }
        c.busy = false;
    }

    public static function dispose(c:Object):Void {
        if (!c || c.disposed) return;
        if (c.unit.__ironGuard !== c) { c.disposed = true; return; }
        if (c.ready) deplete(c,"disposed");
        c.disposed = true;
        c.ready = false;
        c.readyAt = 0;
        c.dispatcher.unsubscribe("kill",c.killHandler,c);
        if (c.thinker) { delete c.thinker.onEnterFrame; delete c.thinker.onUnload; }
        syncLamp(c);
    }
}
