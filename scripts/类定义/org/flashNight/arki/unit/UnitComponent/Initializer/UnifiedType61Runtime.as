import org.flashNight.arki.component.Shield.*;
import org.flashNight.arki.component.Buff.*;
import org.flashNight.arki.component.StatHandler.DodgeHandler;
import org.flashNight.arki.unit.UnitUtil;
import org.flashNight.arki.unit.UnitComponent.Initializer.SetEffectController;
import org.flashNight.arki.unit.Action.Shoot.ReloadManager;
import org.flashNight.arki.unit.Action.Shoot.WeaponAmmoRuntime;
import org.flashNight.arki.unit.Action.Shoot.LongGunSubWeaponCore;
import org.flashNight.arki.weather.WeatherSystem;
import org.flashNight.arki.unit.UnitComponent.Dressup.DressupSubscriber;
import org.flashNight.gesh.object.ObjectUtil;

/** 统合61式五甲共享运行态；只复用成功战技事件与现役付费装填，不拥有新技能槽。 */
class org.flashNight.arki.unit.UnitComponent.Initializer.UnifiedType61Runtime {
    public static var SET_ID:String = "unified_type_61_armor";
    public static var SHIELD_NAME:String = "unified_type_61_buffer";
    private static var SLOTS:Array = ["头部装备", "上装装备", "下装装备", "脚部装备", "手部装备"];
    private static var COMPONENTS:Array = ["helmet_sensor", "chest_buffer", "leg_loader", "boot_servo", "glove_control"];
    private static var GUNS:Array = ["长枪", "手枪", "手枪2"];
    private static var RESISTS:Array = ["基础", "热", "冷", "电", "波", "蚀", "毒"];
    private var target:MovieClip;
    private var effect:Object;
    private var ownerRef:Object;
    private var equipment:Array;
    private var version;
    private var config:Object;
    private var manager:BuffManager;
    private var container:AdaptiveShield;
    private var layer:Shield;
    private var shieldId:Number;
    private var buffs:Object;
    private var buffGroups:Array;
    private var dispatcher:Object;
    private var skillHandler:Function;
    private var modeHandler:Function;
    private var placementHandler:Function;
    private var weather:Object;
    private var nightOwner:Object;
    private var previousNight:Object;
    private var memory:Object;
    private var status:Object;
    private var registered:Boolean;
    private var initialized:Boolean;
    private var disposed:Boolean;
    private var started:Boolean;
    private var authorized:Boolean;
    private var dead:Boolean;
    private var lastFrame:Number;
    private var lastSkillFrame:Number;
    private var maximum:Number;
    private var strength:Number;
    private var brokenAt:Number;
    private var fireAt:Number;
    private var closeAt:Number;
    private var firePower:Number;
    private var fireAuthorized:Boolean;
    private var bulletTemplate:Object;
    private var cannonCount:Number;
    private var reloadCount:Number;
    private var unweightedWalk:Number;
    private var unweightedJump:Number;
    private var writtenWalk:Number;
    private var writtenJump:Number;
    private var appliedAuthorized:Number;
    private var appliedOnline:Number;

    public static function finite(value):Boolean {
        return typeof value == "number" && !isNaN(value) && (value - value) == 0;
    }
    private static function frameNow():Number { return Number(_root.帧计时器.当前帧数); }

    /** 白名单由套装表维护；血色天秤不因名称或技术谱系自动取得授权。 */
    public static function hasAuthorization(unit:Object, record:Object):Boolean {
        var raw = record.config.authorizedWeapons.weapon;
        var names:Array = raw instanceof Array ? raw : [raw];
        for (var i:Number = 0; i < names.length; i++) {
            if (typeof names[i] == "string" && names[i] != "" && unit.刀.name === names[i]) return true;
        }
        return false;
    }
    public static function prepare(record:Object, unit:MovieClip):Object {
        if (!unit || !unit.shield || !unit.buffManager || unit.__unifiedType61) return null;
        var runtime:UnifiedType61Runtime = new UnifiedType61Runtime();
        runtime.target = unit;
        runtime.effect = record;
        runtime.version = unit.version;
        runtime.equipment = [];
        for (var i:Number = 0; i < SLOTS.length; i++) {
            if (!unit[SLOTS[i]] || unit[SLOTS[i] + "数据"].setId !== SET_ID) return null;
            runtime.equipment.push(unit[SLOTS[i]]);
        }
        runtime.manager = unit.buffManager;
        runtime.container = unit.shield;
        runtime.buffs = {};
        runtime.buffGroups = [];
        runtime.status = {};
        runtime.registered = runtime.initialized = runtime.disposed = runtime.started = false;
        runtime.authorized = runtime.dead = false;
        runtime.lastFrame = runtime.lastSkillFrame = -1;
        runtime.maximum = runtime.strength = 0;
        runtime.brokenAt = runtime.fireAt = runtime.closeAt = -1;
        runtime.cannonCount = runtime.reloadCount = 0;
        runtime.appliedAuthorized = runtime.appliedOnline = -1;
        return runtime;
    }
    public function initializeComponent(ref:Object, params:Object):String {
        if (disposed || ref.自机 !== target || ref.套装效果记录 !== effect) return SetEffectController.FAILURE;
        var index:Number = -1;
        for (var i:Number = 0; i < SLOTS.length; i++) {
            if (ref.装备类型 == SLOTS[i] && ref.套装组件ID == COMPONENTS[i]) index = i;
        }
        if (index < 0 || target[SLOTS[index]] !== equipment[index]) return SetEffectController.FAILURE;
        if (!registered) {
            var self:UnifiedType61Runtime = this;
            if (!SetEffectController.registerResource(ref, function():Void { self.dispose(); })) return SetEffectController.FAILURE;
            ownerRef = ref;
            registered = true;
        }
        if (index == 0 && !initializeNight(ref)) return SetEffectController.FAILURE;
        if (index == 1) {
            if (!initializeCore(ref, params)) return SetEffectController.FAILURE;
            return SetEffectController.READY_CYCLE;
        }
        return SetEffectController.READY_STATIC;
    }
    private function initializeNight(ref:Object):Boolean {
        if (target._name !== _root.控制目标) return true;
        weather = WeatherSystem.getInstance();
        if (!weather || typeof weather.registerNightVision != "function") return false;
        nightOwner = {视觉情况:"浅绿夜视仪", 最小启动亮度:0, 最大启动亮度:4,
            启用装备:ref.装备名称, 装备类型:ref.装备类型};
        previousNight = target.红外夜视仪;
        target.红外夜视仪 = nightOwner;
        weather.registerNightVision(nightOwner);
        return true;
    }
    private function readConfig(params:Object):Boolean {
        config = {};
        var keys:Array = ["shieldHpRatio", "rechargeDelaySeconds", "rechargeSeconds", "normalRebuildSeconds",
            "authorizedRebuildSeconds", "ammoSeconds", "weightKg", "toughness", "dodgeNormal", "dodgeAuthorized",
            "resistNormal", "resistAuthorized", "damageTaken", "cannonOpenFrames", "cannonDurationFrames"];
        for (var i:Number = 0; i < keys.length; i++) {
            var value:Number = Number(params[keys[i]]);
            if (!finite(value) || !(value > 0)) return false;
            config[keys[i]] = value;
        }
        config.fps = Number(_root.帧计时器.帧率);
        return finite(config.fps) && config.fps > 0 && config.shieldHpRatio < 1 && config.damageTaken < 1;
    }
    /** 数值仍由真实注入 Pod 结算，Meta 统一拥有生命周期和冷/热 HUD 登记。 */
    private function addBuffGroup(group:String, keys:Array, properties:Array, calculations:Array, values:Array,
            name:String, description:String, activation:Object):Boolean {
        var children:Array = [];
        for (var i:Number = 0; i < keys.length; i++) {
            children.push(new PodBuff(properties[i], calculations[i], values[i]));
        }
        var meta:MetaBuff = new MetaBuff(children, [], 0);
        meta.hudInfo = {name:name, description:description, polarity:"benefit", stacks:0};
        meta.hudPresentation = {mods:true, activation:activation, activeLabel:"护盾在线", inactiveLabel:"护盾离线"};
        var id:String = manager.addBuff(meta, "unified61:" + group);
        if (!id) return false;
        buffGroups.push(id);
        var injected:Array = manager.getInjectedPodIds(meta.getId());
        if (injected.length != keys.length) return false;
        for (i = 0; i < keys.length; i++) {
            var pod:Object = manager.getBuffById(String(injected[i]));
            if (pod.getTargetProperty() !== properties[i]) return false;
            buffs[keys[i]] = String(injected[i]);
        }
        return true;
    }
    private function initializeCore(ref:Object, params:Object):Boolean {
        if (initialized || !readConfig(params)) return false;
        if (container.isSingleMode() && container.getName() == SHIELD_NAME) return false;
        var shields:Array = container.getShields();
        for (var i:Number = 0; i < shields.length; i++) {
            if (shields[i].getName() == SHIELD_NAME) return false;
        }
        var weight:Number = manager.getBaseValue("重量");
        var ratio:Number = UnitUtil.getWeightSpeedRatio(weight, target.等级);
        writtenWalk = manager.getBaseValue("行走X速度");
        writtenJump = manager.getBaseValue("起跳速度");
        if (!finite(weight) || !finite(ratio) || !(ratio > 0) || !finite(writtenWalk) || !finite(writtenJump)) return false;
        unweightedWalk = writtenWalk / ratio;
        unweightedJump = writtenJump / ratio;
        layer = Shield.createRechargeable(1, 0, 0, config.rechargeDelaySeconds * config.fps, SHIELD_NAME);
        layer.setCapacity(0);
        shieldId = layer.getId();
        var self:UnifiedType61Runtime = this;
        layer.setCallbacks({onHit:function(s:Object, amount:Number):Void { self.onShieldHit(amount); },
            onBreak:function(s:Object):Void { self.onShieldBreak(); }});
        if (!container.addShield(layer, true) || container.getShieldById(shieldId) !== layer) return false;
        if (!addBuffGroup("core", ["weight", "damage", "toughness", "toughnessDisplay", "dodge", "dodgeDisplay"],
                ["重量", "damageTakenMultiplier", "韧性系数", "韧性加成", "躲闪率", "闪避加成"],
                [BuffCalculationType.ADD, BuffCalculationType.MULT_NEGATIVE, BuffCalculationType.ADD,
                    BuffCalculationType.ADD, BuffCalculationType.ADD, BuffCalculationType.ADD],
                [-config.weightKg, config.damageTaken, 0, config.toughness, 0, 0],
                "全装助力", "统合61五件系统：韧性+250、挡拆+35（星座授权+175）、同类取强减伤12%、抵消12kg负重并启用浅绿夜视。", null)) return false;
        var resistKeys:Array = [], resistProperties:Array = [], resistCalculations:Array = [], resistValues:Array = [];
        for (i = 0; i < RESISTS.length; i++) {
            resistKeys.push("resist" + i);
            resistProperties.push("魔法抗性." + RESISTS[i]);
            resistCalculations.push(BuffCalculationType.ADD);
            resistValues.push(0);
        }
        // 这些回调只读已有运行态，HUD 重采样不能推进计时、补盾或补弹。
        var shieldPresentation:Object = {isActive:function():Boolean { return self.isBufferOnline(); },
            getRemaining:function():Number { return 0; }, getDuration:function():Number { return 0; }};
        if (!addBuffGroup("buffer", resistKeys, resistProperties, resistCalculations, resistValues,
                "缓冲护盾", "统合61轻盾：容量为正常最大HP的5%，盾强取稳定防御；有盾时补足抗性，星座授权可抗真伤。破盾后普通5秒、星座3秒重建，战技可立即回满。", shieldPresentation)) return false;
        dispatcher = target.dispatcher;
        if (!dispatcher || typeof dispatcher.subscribe != "function") return false;
        skillHandler = function(mode:String):Void { self.onWeaponSkill(); };
        modeHandler = function(unit:Object, oldMode:String, newMode:String):Void { self.onModeChanged(unit, oldMode, newMode); };
        placementHandler = function():Void { self.updateCannonVisual(); };
        if (!dispatcher.subscribe("WeaponSkill", skillHandler, this)
                || !dispatcher.subscribe("attackModeChanged", modeHandler, this)) return false;
        if (!target.syncRefs) target.syncRefs = {};
        DressupSubscriber.onPlacement(target, "身体_引用", placementHandler, this);
        bulletTemplate = ref.子弹配置.bullet_0;
        if (!bulletTemplate || !bulletTemplate.子弹种类) return false;
        initialized = true;
        target.__unifiedType61 = this;
        target.__unified61Status = status;
        manager.update(0);
        return true;
    }
    private function bindingValid():Boolean {
        if (disposed || !initialized || !target._parent || target.version !== version || target.__unifiedType61 !== this
                || target.buffManager !== manager || target.shield !== container || target.dispatcher !== dispatcher) return false;
        for (var i:Number = 0; i < SLOTS.length; i++) {
            if (target[SLOTS[i]] !== equipment[i] || target[SLOTS[i] + "数据"].setId !== SET_ID) return false;
        }
        return true;
    }
    private function fail(reason:String):Void {
        status.failure = reason;
        if (effect.group.status == "committed") SetEffectController.teardownGroup(target, effect.group.id);
        else SetEffectController.failRef(ownerRef, reason);
        trace("[Unified61] " + reason);
    }
    /** 等最终资源生成完成再读取容量；同单位换装保留比例与逐枪时钟，不能免费刷新。 */
    private function start():Boolean {
        var hp:Number = manager.getBaseValue("hp满血值");
        var defense:Number = manager.getBaseValue("防御力");
        if (!finite(hp) || !(hp > 0) || !finite(defense) || !(defense > 0)) return false;
        maximum = hp * config.shieldHpRatio;
        strength = defense;
        layer.setMaxCapacity(maximum);
        layer.setTargetCapacity(maximum);
        memory = target.__unified61Memory;
        if (!_root.gameworld.__unified61World) _root.gameworld.__unified61World = {};
        if (!memory || memory.schema !== 1 || memory.world !== _root.gameworld.__unified61World) {
            memory = {schema:1, world:_root.gameworld.__unified61World, ratio:1, brokenAt:-1, lastHit:-99999, readyAt:{长枪:0, 手枪:0, 手枪2:0}};
            target.__unified61Memory = memory;
        }
        brokenAt = Number(memory.brokenAt);
        if (!finite(brokenAt)) brokenAt = -1;
        var saved:Number = Number(memory.ratio);
        if (!finite(saved) || saved < 0 || saved > 1) saved = 0;
        layer.setCapacity(maximum * saved);
        if (!(layer.getCapacity() > 0) && brokenAt < 0) brokenAt = frameNow();
        started = true;
        var remainingDelay:Number = config.rechargeDelaySeconds * config.fps - (frameNow() - Number(memory.lastHit));
        if (layer.getCapacity() > 0 && finite(remainingDelay) && remainingDelay > 0) {
            layer.setRechargeDelay(remainingDelay);
            layer.setRechargeRate(maximum / (config.rechargeSeconds * config.fps));
            layer.onHit(0);
            layer.setRechargeDelay(config.rechargeDelaySeconds * config.fps);
        }
        authorized = hasAuthorization(target, effect);
        synchronizeLayer();
        return true;
    }
    public function tick(ref:Object):Void {
        if (disposed) return;
        if (!bindingValid()) { fail("binding_changed"); return; }
        if (effect.group.status != "committed" || target.__playerStatInitializing === true
                || (target.__resourceSpawn != undefined && target.__resourceSpawn.resourcesReady !== true)) return;
        var frame:Number = frameNow();
        if (!finite(frame) || frame == lastFrame) return;
        lastFrame = frame;
        if (!started && !start()) { fail("invalid_stable_stats"); return; }
        if (container.getShieldById(shieldId) !== layer) { fail("shield_missing"); return; }
        if (!(target.hp > 0)) {
            if (!dead) { dead = true; layer.setCapacity(0); brokenAt = frame; fireAt = closeAt = -1; synchronizeLayer(); }
            remember();
            return;
        }
        if (dead) { dead = false; brokenAt = frame; }
        authorized = hasAuthorization(target, effect);
        refreshStableStats();
        var waitFrames:Number = (authorized ? config.authorizedRebuildSeconds : config.normalRebuildSeconds) * config.fps;
        if (!(layer.getCapacity() > 0) && brokenAt > -1 && !(frame - brokenAt < waitFrames)) fillShield();
        synchronizeLayer();
        updateServo();
        if (fireAt > -1 && !(frame < fireAt)) { fireAt = -1; fireCannon(); }
        if (closeAt > -1 && !(frame < closeAt)) closeAt = -1;
        updateCannonVisual();
        remember();
    }
    private function refreshStableStats():Void {
        var hp:Number = manager.getBaseValue("hp满血值");
        var defense:Number = manager.getBaseValue("防御力");
        if (!finite(hp) || !(hp > 0) || !finite(defense) || !(defense > 0)) return;
        var newMaximum:Number = hp * config.shieldHpRatio;
        if (newMaximum != maximum) {
            var ratio:Number = maximum > 0 ? layer.getCapacity() / maximum : 0;
            maximum = newMaximum;
            layer.setMaxCapacity(maximum);
            layer.setTargetCapacity(maximum);
            layer.setCapacity(maximum * ratio);
            container.invalidateCache();
        }
        if (strength != defense) { strength = defense; synchronizeLayer(); }
    }
    private function synchronizeLayer():Void {
        var online:Boolean = started && !dead && target.hp > 0 && layer.getCapacity() > 0;
        var newStrength:Number = online ? strength : 0;
        var bypass:Boolean = online && authorized;
        if (layer.getStrength() != newStrength || layer.getResistBypass() != bypass) {
            layer.setStrength(newStrength);
            layer.setResistBypass(bypass);
            container.invalidateCache();
        }
        layer.setRechargeRate(online ? maximum / (config.rechargeSeconds * config.fps) : 0);
        var auth:Number = authorized ? 1 : 0;
        var onlineFlag:Number = online ? 1 : 0;
        if (auth != appliedAuthorized || onlineFlag != appliedOnline) {
            appliedAuthorized = auth;
            appliedOnline = onlineFlag;
            var bonus:Number = authorized ? config.dodgeAuthorized : config.dodgeNormal;
            var baseBonus:Number = manager.getBaseValue("闪避加成");
            if (!finite(baseBonus)) baseBonus = 0;
            var baseDodge:Number = Number(target.基础躲闪率);
            if (!finite(baseDodge) || !(baseDodge > 0)) baseDodge = manager.getBaseValue("躲闪率") * (1 + baseBonus / 100);
            manager.setPodBuffValue(buffs.dodge, DodgeHandler.applyDodgeBonus(baseDodge, baseBonus + bonus)
                - DodgeHandler.applyDodgeBonus(baseDodge, baseBonus));
            manager.setPodBuffValue(buffs.dodgeDisplay, bonus);
            var baseToughness:Number = Number(target.基础韧性系数);
            if (!finite(baseToughness) || !(baseToughness > 0)) baseToughness = 1;
            manager.setPodBuffValue(buffs.toughness, baseToughness * config.toughness / 100);
            // 补足固有抗性至25/45，与能量盾的+50相加得到75/95；不降低更高的固有抗性。
            var floor:Number = authorized ? config.resistAuthorized : config.resistNormal;
            for (var i:Number = 0; i < RESISTS.length; i++) {
                var base:Number = manager.getBaseValue("魔法抗性." + RESISTS[i]);
                if (!finite(base)) base = 0;
                manager.setPodBuffValue(buffs["resist" + i], online ? Math.max(0, floor - base) : 0);
            }
            manager.update(0);
        }
    }
    private function isBufferOnline():Boolean {
        return started && !disposed && !dead && target.hp > 0 && layer.getCapacity() > 0;
    }
    private function updateServo():Void {
        var rawRatio:Number = UnitUtil.getWeightSpeedRatio(manager.getBaseValue("重量"), target.等级);
        var walk:Number = manager.getBaseValue("行走X速度");
        var jump:Number = manager.getBaseValue("起跳速度");
        if (walk != writtenWalk) unweightedWalk = walk / rawRatio;
        if (jump != writtenJump) unweightedJump = jump / rawRatio;
        var ratio:Number = UnitUtil.getWeightSpeedRatio(target.重量, target.等级);
        writtenWalk = unweightedWalk * ratio;
        writtenJump = unweightedJump * ratio;
        if (walk != writtenWalk) manager.setBaseValue("行走X速度", writtenWalk);
        if (jump != writtenJump) manager.setBaseValue("起跳速度", writtenJump);
    }
    private function onShieldHit(amount:Number):Void {
        if (disposed || !started) return;
        if (amount > 0) memory.lastHit = frameNow();
        if (!(layer.getCapacity() > 0)) onShieldBreak();
        else remember();
    }
    private function onShieldBreak():Void {
        if (disposed || !started) return;
        if (brokenAt < 0) brokenAt = frameNow();
        synchronizeLayer();
        remember();
    }
    private function fillShield():Void {
        layer.reset();
        layer.setCapacity(maximum);
        brokenAt = -1;
        if (memory) memory.lastHit = -99999;
        container.invalidateCache();
        synchronizeLayer();
    }
    private function onWeaponSkill():Void {
        if (!bindingValid() || effect.group.status != "committed" || !started || dead || !(target.hp > 0)) return;
        var frame:Number = frameNow();
        if (!finite(frame) || frame == lastSkillFrame) return;
        lastSkillFrame = frame;
        authorized = hasAuthorization(target, effect);
        fillShield();
        firePower = Number(target.伤害加成);
        if (!finite(firePower) || firePower < 0) firePower = 0;
        firePower /= 12;
        fireAuthorized = authorized;
        fireAt = frame + config.cannonOpenFrames;
        closeAt = frame + config.cannonDurationFrames;
        updateCannonVisual();
        remember();
    }
    /** 装填动作由切换事件触发；满弹/失败保留就绪，不覆盖普通或翻滚换弹的计时。 */
    private function onModeChanged(unit:Object, oldMode:String, mode:String):Void {
        if (unit !== target || oldMode == mode || mode !== target.攻击模式 || !bindingValid() || effect.group.status != "committed"
                || !started || dead || !(target.hp > 0)) return;
        if (mode == "长枪") reloadSlot("长枪");
        else if (mode == "双枪") { reloadSlot("手枪"); reloadSlot("手枪2"); }
        else if (mode == "手枪" || mode == "手枪2") reloadSlot(mode);
        remember();
    }
    private function reloadSlot(slot:String):Void {
        var frame:Number = frameNow();
        var ready:Number = Number(memory.readyAt[slot]);
        if (!finite(frame) || !finite(ready) || frame < ready) return;
        var item:Object = target[slot];
        var attr:Object = target[slot + "属性"];
        if (!item || !item.value || !attr.clipname || !(target[slot + "弹匣容量"] > 0)) return;
        var ammo:Object = WeaponAmmoRuntime.ensure(target, slot);
        var capacity:Number = Number(target[slot + "弹匣容量"]);
        if (!(WeaponAmmoRuntime.normal(item.value, capacity) < capacity)) return;
        if (!ReloadManager.commitMagazine(target, slot, attr.clipname)) return;
        memory.readyAt[slot] = frame + config.ammoSeconds * config.fps;
        reloadCount++;
        if (slot == "长枪") LongGunSubWeaponCore.reloadLinked(target);
        dispatcher.publish("updateBullet", target, slot == "手枪2" ? "副手射击中" : "主手射击中",
            Math.max(0, capacity - item.value.shot), slot, target.攻击模式);
    }
    private function bodySkin():MovieClip {
        var holder:MovieClip = target.身体_引用;
        if (holder.装扮.炮口位置 && holder.装扮._totalframes == 3) return holder.装扮;
        if (holder.炮口位置 && holder._totalframes == 3) return holder;
        return null;
    }
    private function updateCannonVisual():Void {
        if (disposed || !initialized) return;
        var skin:MovieClip = bodySkin();
        if (!skin) return;
        var frame:Number = frameNow();
        var pose:Number = closeAt < 0 || dead ? 1 : (fireAt > frame ? 2 : 3);
        if (skin._currentframe != pose) skin.gotoAndStop(pose);
    }
    private function fireCannon():Void {
        if (!bindingValid() || dead || !(target.hp > 0) || typeof _root.子弹区域shoot传递 != "function") return;
        var props:Object = ObjectUtil.clone(bulletTemplate);
        var skin:MovieClip = bodySkin();
        var point:Object = {x:0, y:0};
        if (skin && skin.炮口位置) {
            skin.炮口位置.localToGlobal(point);
        } else {
            point.x = target.方向 == "左" ? -14 : 14;
            point.y = -56;
            target.localToGlobal(point);
        }
        props.转换中间y = point.y;
        _root.gameworld.globalToLocal(point);
        props.shootX = point.x;
        props.shootY = point.y;
        props.shootZ = target.Z轴坐标;
        props.子弹威力 = firePower;
        props.伤害类型 = fireAuthorized ? "真伤" : "魔法";
        props.魔法伤害属性 = fireAuthorized ? undefined : "热";
        props.发射者 = target._name;
        props.是否为敌人 = target.是否为敌人;
        _root.子弹区域shoot传递(props);
        cannonCount++;
    }
    private function remember():Void {
        if (!started || !memory) return;
        memory.ratio = maximum > 0 ? layer.getCapacity() / maximum : 0;
        memory.brokenAt = brokenAt;
        status.authorized = authorized;
        status.online = !dead && layer.getCapacity() > 0;
        status.capacity = layer.getCapacity();
        status.maximum = maximum;
        status.strength = layer.getStrength();
        status.brokenAt = brokenAt;
        status.cannonCount = cannonCount;
        status.reloadCount = reloadCount;
        status.readyAt = memory.readyAt;
    }
    public function getDiagnostics():Object { remember(); return ObjectUtil.clone(status); }
    public function getShieldId():Number { return shieldId; }
    public function dispose():Void {
        if (disposed) return;
        remember();
        var skin:MovieClip = bodySkin();
        if (skin) skin.gotoAndStop(1);
        disposed = true;
        if (dispatcher) {
            if (skillHandler) dispatcher.unsubscribe("WeaponSkill", skillHandler, this);
            if (modeHandler) dispatcher.unsubscribe("attackModeChanged", modeHandler, this);
            if (placementHandler) dispatcher.unsubscribe("身体_引用", placementHandler, this);
        }
        if (nightOwner) {
            weather.unregisterNightVision(nightOwner);
            if (target.红外夜视仪 === nightOwner) target.红外夜视仪 = previousNight;
        }
        if (layer) {
            layer.onHitCallback = layer.onBreakCallback = null;
            layer.setResistBypass(false);
            container.removeShieldById(shieldId);
        }
        if (manager) {
            for (var i:Number = 0; i < buffGroups.length; i++) manager.removeBuff(buffGroups[i]);
            manager.update(0);
            if (initialized && target.buffManager === manager) {
                var ratio:Number = UnitUtil.getWeightSpeedRatio(target.重量, target.等级);
                if (manager.getBaseValue("行走X速度") == writtenWalk) manager.setBaseValue("行走X速度", unweightedWalk * ratio);
                if (manager.getBaseValue("起跳速度") == writtenJump) manager.setBaseValue("起跳速度", unweightedJump * ratio);
            }
        }
        if (target.__unifiedType61 === this) {
            delete target.__unifiedType61;
            status.online = false;
            status.state = "OFFLINE";
        }
    }
}
