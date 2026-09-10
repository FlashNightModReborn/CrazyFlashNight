import org.flashNight.arki.component.Shield.*;
import org.flashNight.arki.component.Buff.*;
import org.flashNight.arki.unit.UnitUtil;
import org.flashNight.arki.unit.Action.Regeneration.HealApplier;
import org.flashNight.arki.unit.UnitComponent.Initializer.SetEffectController;
import org.flashNight.arki.weather.WeatherSystem;
import org.flashNight.arki.unit.Action.Shoot.ReloadManager;
import org.flashNight.arki.bullet.BulletComponent.Type.BulletTypeUtil;
import org.flashNight.arki.unit.UnitComponent.Dressup.EquipmentUtil.EquipmentFireIntent;
import org.flashNight.arki.item.ItemUtil;
import org.flashNight.arki.item.equipment.EquipmentConfigManager;

/** 五甲共享运行态。只有胸甲有周期，其余组件完成静态注册后参与同一事务。 */
class org.flashNight.arki.unit.UnitComponent.Initializer.TitaniumSetRuntime {
    public static var SET_ID:String = "titanium_type_61_armor";
    public static var SHIELD_NAME:String = "titanium_type_61_set_shield";
    private static var SLOTS:Array = ["头部装备", "上装装备", "下装装备", "脚部装备", "手部装备"];
    private static var COMPONENTS:Array = ["helmet_night_vision", "chest_life_support", "leg_ammo_supply", "boot_servo", "glove_energy_bus"];

    private var target:MovieClip;
    private var effect:Object;
    private var version;
    private var equipment:Array;
    private var ownerRef:Object;
    private var registered:Boolean;
    private var disposed:Boolean;
    private var initialized:Boolean;
    private var config:Object;
    private var manager:BuffManager;
    private var container:AdaptiveShield;
    private var layer:Shield;
    private var shieldId:Number;
    private var armorHp:Number;
    private var armorDamage:Number;
    private var fullStrength:Number;
    private var startupPaid:Boolean;
    private var phase:String;
    private var lastFrame:Number;
    private var pulseFrame:Number;
    private var weightId:String;
    private var speedId:String;
    private var overloadId:String;
    private var appliedWeight:Number;
    private var appliedSpeed:Number;
    private var appliedOverload:Number;
    private var unweightedWalk:Number;
    private var unweightedJump:Number;
    private var writtenWalk:Number;
    private var writtenJump:Number;
    private var nightOwner:Object;
    private var previousNight:Object;
    private var weather:Object;
    private var failureReason:String;
    private var mpSpent:Number;
    private var healed:Number;
    private var charged:Number;
    private var startups:Number;
    private var dispatcher:Object;
    private var shotHandler:Function;
    private var baseMpEarned:Number;
    private var ammoSynthesized:Number;
    private var ammoMpSpent:Number;
    private var initialShieldPending:Boolean;
    private var initialShieldAllowed:Boolean;
    private var initialShieldGranted:Number;
    private var bloodLoss:Number;
    private var bloodEquipment:Object;
    private var deathSuspended:Boolean;
    private var bloodBonusId:String;
    private var bloodPendingBonus:Number;
    private var bloodBonusUntil:Number;
    private var bloodCasting:Boolean;
    private var bloodMan:MovieClip;
    private var bloodBonusGranted:Boolean;
    private var bloodCastId:Number;

    public static function finite(value):Boolean {
        return typeof value == "number" && !isNaN(value) && (value - value) == 0;
    }

    /** 固有生命负担只读原始物品与强化；插件抵消、当前缺血和超血不改变锚点。 */
    public static function getBloodLoss(unit:Object):Number {
        var sword:Object = unit.刀;
        if (!sword || sword.name !== "血色光剑天秤") return 0;
        var source:Object = ItemUtil.getRawItemData(sword.name);
        var level:Number = Number(sword.value.level);
        if (!finite(level) || level < 1 || level > EquipmentConfigManager.getMaxLevel() || level != Math.floor(level)) return 0;
        var base:Number = Number(source.data.hp);
        if (!finite(base) || !(base < 0)) return 0;
        return Math.round(-base * EquipmentConfigManager.getLevelMultiplier(level));
    }

    public static function prepare(record:Object, unit:MovieClip):Object {
        if (!unit || !unit.shield || !unit.buffManager || unit.__titaniumType61) return null;
        var runtime:TitaniumSetRuntime = new TitaniumSetRuntime();
        runtime.target = unit;
        runtime.effect = record;
        runtime.version = unit.version;
        runtime.equipment = [];
        runtime.armorHp = 0;
        runtime.armorDamage = 0;
        for (var i:Number = 0; i < SLOTS.length; i++) {
            var slot:String = SLOTS[i];
            var item:Object = unit[slot];
            var source:Object = unit[slot + "数据"];
            if (!item || source.setId !== SET_ID) return null;
            var hp:Number = Number(source.data.hp);
            var damage:Number = source.data.damage == undefined ? 0 : Number(source.data.damage);
            if (!finite(hp) || !finite(damage) || hp < 0 || damage < 0) return null;
            runtime.armorHp += hp;
            runtime.armorDamage += damage;
            runtime.equipment.push(item);
        }
        if (!(runtime.armorHp > 0)) return null;
        runtime.manager = unit.buffManager;
        runtime.container = unit.shield;
        runtime.registered = false;
        runtime.disposed = false;
        runtime.initialized = false;
        runtime.startupPaid = false;
        runtime.phase = "BREACHED";
        runtime.failureReason = "";
        runtime.lastFrame = -1;
        runtime.pulseFrame = -1;
        runtime.appliedWeight = 0;
        runtime.appliedSpeed = 1;
        runtime.appliedOverload = 0;
        runtime.mpSpent = 0;
        runtime.healed = 0;
        runtime.charged = 0;
        runtime.startups = 0;
        runtime.baseMpEarned = 0;
        runtime.ammoSynthesized = 0;
        runtime.ammoMpSpent = 0;
        runtime.initialShieldPending = true;
        runtime.initialShieldAllowed = true;
        runtime.initialShieldGranted = 0;
        runtime.bloodLoss = getBloodLoss(unit);
        runtime.bloodEquipment = unit.刀;
        runtime.deathSuspended = false;
        runtime.bloodCasting = false;
        runtime.bloodMan = null;
        runtime.bloodBonusGranted = false;
        runtime.bloodCastId = 0;
        runtime.bloodPendingBonus = 0;
        runtime.bloodBonusUntil = 0;
        return runtime;
    }

    /** 只接受本次真实五槽的组件，副作用全部由一个事务逆操作接管。 */
    public function initializeComponent(ref:Object, params:Object):String {
        if (disposed || ref.自机 !== target || ref.套装效果记录 !== effect) return SetEffectController.FAILURE;
        var index:Number = -1;
        for (var i:Number = 0; i < SLOTS.length; i++) {
            if (ref.装备类型 == SLOTS[i] && ref.套装组件ID == COMPONENTS[i]) index = i;
        }
        if (index < 0 || target[SLOTS[index]] !== equipment[index]) return SetEffectController.FAILURE;
        if (!registered) {
            var self:TitaniumSetRuntime = this;
            if (!SetEffectController.registerResource(ref, function():Void { self.dispose(); })) return SetEffectController.FAILURE;
            registered = true;
            ownerRef = ref;
        }
        if (index == 0 && !initializeNightVision(ref)) return SetEffectController.FAILURE;
        if (index == 1) {
            if (!initializeCore(params)) return SetEffectController.FAILURE;
            return SetEffectController.READY_CYCLE;
        }
        return SetEffectController.READY_STATIC;
    }

    private function initializeNightVision(ref:Object):Boolean {
        if (target._name !== _root.控制目标) return true;
        weather = WeatherSystem.getInstance();
        if (!weather || typeof weather.registerNightVision != "function") return false;
        nightOwner = {视觉情况:"高级夜视仪", 最小启动亮度:0, 最大启动亮度:4,
                      启用装备:ref.装备名称, 装备类型:ref.装备类型};
        previousNight = target.红外夜视仪;
        target.红外夜视仪 = nightOwner;
        weather.registerNightVision(nightOwner);
        return true;
    }

    private function readConfig(params:Object):Boolean {
        config = {};
        var keys:Array = ["shieldArmorHpRatio", "fullRechargeSeconds", "shieldMpPerPoint", "bloodServoBonusKg",
                          "bloodShieldRatio", "shieldLazyDodge", "bloodSkillHpRatio", "bloodSkillBuffSeconds",
                          "bloodCrumblePercent", "bloodExecutePercent", "bloodPulsePowerRatio",
                          "healBaseHpRatioPerSecond", "healMissingRatioPerSecond", "healMpPerPoint", "startupMp",
                          "overloadCoefficient", "overloadExponent", "pulseFrames", "ammoMpPerRound", "ammoMaxPerSlotPulse"];
        for (var i:Number = 0; i < keys.length; i++) {
            var key:String = keys[i];
            var value:Number = Number(params[key]);
            if (!finite(value) || !(value > 0)) return false;
            config[key] = value;
        }
        if (config.pulseFrames != Math.floor(config.pulseFrames) ||
            config.ammoMaxPerSlotPulse != Math.floor(config.ammoMaxPerSlotPulse)) return false;
        config.ammoReserveRatio = Number(params.ammoReserveRatio);
        if (!finite(config.ammoReserveRatio) || config.ammoReserveRatio < 0 || config.ammoReserveRatio > 1) return false;
        var fps:Number = Number(_root.帧计时器.帧率);
        if (!finite(fps) || !(fps > 0)) return false;
        config.pulseSeconds = config.pulseFrames / fps;
        return true;
    }

    private function reservedLayerExists():Boolean {
        if (container.isSingleMode()) return container.getName() == SHIELD_NAME;
        var shields:Array = container.getShields();
        for (var i:Number = 0; i < shields.length; i++) {
            if (typeof shields[i].getName == "function" && shields[i].getName() == SHIELD_NAME) return true;
        }
        return false;
    }

    private function initializeCore(params:Object):Boolean {
        if (initialized || !readConfig(params) || reservedLayerExists()) return false;
        if (!finite(Number(target.hp满血值)) || !(target.hp满血值 > 0) ||
            !finite(Number(target.mp满血值)) || !(target.mp满血值 > 0)) return false;
        var weight:Number = manager.getBaseValue("重量");
        var ratio:Number = UnitUtil.getWeightSpeedRatio(weight, target.等级);
        var walk:Number = manager.getBaseValue("行走X速度");
        var jump:Number = manager.getBaseValue("起跳速度");
        if (!finite(weight) || !finite(ratio) || !(ratio > 0) || !finite(walk) || !(walk > 0) || !finite(jump)) return false;
        unweightedWalk = walk / ratio;
        unweightedJump = jump / ratio;
        writtenWalk = walk;
        writtenJump = jump;
        fullStrength = armorHp * config.shieldArmorHpRatio + bloodLoss * config.bloodShieldRatio;
        if (!finite(fullStrength) || !(fullStrength > 0)) return false;

        // BaseShield 构造默认满盾；注册前清零，零盾强防止未付费就获得抗击溃等能力。
        layer = Shield.createRechargeable(fullStrength, 0, 0, 0, SHIELD_NAME);
        layer.setCapacity(0);
        layer.setResistBypass(bloodLoss > 0);
        shieldId = layer.getId();
        var self:TitaniumSetRuntime = this;
        layer.setCallbacks({onHit:function(s:Object, amount:Number):Void { self.onShieldChanged(); },
                            onBreak:function(s:Object):Void { self.onShieldBroken(); }});
        if (!container.addShield(layer, true) || container.getShieldById(shieldId) !== layer) return false;

        weightId = manager.addBuff(new PodBuff("重量", BuffCalculationType.ADD, 0), "titanium61:weight");
        speedId = manager.addBuff(new PodBuff("行走X速度", BuffCalculationType.MULT_POSITIVE, 1), "titanium61:servo");
        overloadId = manager.addBuff(new PodBuff("伤害加成", BuffCalculationType.ADD, 0), "titanium61:overload");
        bloodBonusId = manager.addBuff(new PodBuff("伤害加成", BuffCalculationType.ADD, 0), "titanium61:bloodPact");
        if (!weightId || !speedId || !overloadId || !bloodBonusId) return false;
        manager.update(0);
        dispatcher = target.dispatcher;
        if (!dispatcher || typeof dispatcher.subscribe != "function") return false;
        shotHandler = function(owner:Object, slot:String, muzzle:Object, props:Object, firedWeapon:Object):Void {
            self.onProcessShot(owner, slot, firedWeapon);
        };
        if (!dispatcher.subscribe("processShot", shotHandler, this)) return false;
        initialized = true;
        target.__titaniumType61 = this;
        writeStatus();
        return true;
    }

    private function bindingValid():Boolean {
        if (disposed || !initialized || !target._parent || target.version !== version ||
            target.__titaniumType61 !== this || target.shield !== container || target.buffManager !== manager || target.dispatcher !== dispatcher || target.刀 !== bloodEquipment) return false;
        for (var i:Number = 0; i < SLOTS.length; i++) {
            if (target[SLOTS[i]] !== equipment[i] || target[SLOTS[i] + "数据"].setId !== SET_ID) return false;
        }
        return true;
    }

    private function structuralFailure(reason:String):Void {
        failureReason = reason;
        if (effect.group.status == "committed") SetEffectController.teardownGroup(target, effect.group.id);
        else SetEffectController.failRef(ownerRef, reason);
        target.__titaniumType61Status = {state:"OFFLINE", failure:reason};
        trace("[Titanium61] " + reason);
    }

    /** 由胸甲的唯一 lifecycle task 调用；世界时钟未推进时绝不扣资源。 */
    public function tick(ref:Object):Void {
        if (disposed) return;
        if (!bindingValid()) { structuralFailure("binding_changed"); return; }
        if (effect.group.status != "committed") return;
        if (!(target.hp > 0)) { suspendForDeath(); return; }
        if (deathSuspended) return;
        var frame:Number = Number(_root.帧计时器.当前帧数);
        if (!finite(frame) || frame == lastFrame) return;
        lastFrame = frame;
        if (bloodBonusUntil > 0 && frame >= bloodBonusUntil) {
            manager.setPodBuffValue(bloodBonusId, 0);
            bloodBonusUntil = 0;
        }
        if (bloodCasting && (target.状态 != "战技" || (bloodMan && target.man !== bloodMan))) cancelBloodCast();
        if (container.getShieldById(shieldId) !== layer) { structuralFailure("shield_missing"); return; }
        if (!finite(layer.getCapacity()) || !finite(layer.getMaxCapacity()) ||
            layer.getCapacity() < 0 || layer.getMaxCapacity() != fullStrength || layer.getCapacity() > fullStrength) {
            structuralFailure("shield_capacity_invalid"); return;
        }
        if (!finite(Number(target.hp)) || !finite(Number(target.hp满血值)) || !(target.hp满血值 > 0) ||
            !finite(Number(target.mp)) || target.mp < 0 || !finite(Number(target.mp满血值)) || !(target.mp满血值 > 0)) {
            structuralFailure("resources_invalid"); return;
        }
        // 最终HP/MP会在initializeUnit返回后结算；只在首个已提交维护帧兑现免费初始盾。
        grantInitialShield();
        synchronizeState();
        if (disposed) return;
        if (pulseFrame >= 0 && frame - pulseFrame < config.pulseFrames) return;
        pulseFrame = frame;
        healFromMp();
        chargeFromMp();
        synchronizeState();
        if (disposed) return;
        // 缺弹更多的一槽优先；相同时主手在前。每槽提交仍独立复核真实状态。
        var secondaryFirst:Boolean = target.手枪2.value.shot > target.手枪.value.shot;
        synthesizeAmmo(secondaryFirst ? "手枪2" : "手枪");
        synthesizeAmmo(secondaryFirst ? "手枪" : "手枪2");
        writeStatus();
    }

    /** 重初始化的旧资源来自StaticInitializer入口；降上限不能伪装成原本满血。 */
    public function constrainInitialShieldToPreviousHealth(hp:Number, maximum:Number):Void {
        if (!initialShieldPending) return;
        initialShieldAllowed = initialShieldAllowed && finite(hp) && finite(maximum) && maximum > 0 && hp >= maximum;
    }

    /** 同一MovieClip死亡只暂停；保留组件和周期所有权，卸装/离场仍由事务清理。 */
    private function suspendForDeath():Void {
        if (deathSuspended) return;
        deathSuspended = true;
        cancelBloodCast();
        manager.setPodBuffValue(bloodBonusId, 0);
        bloodBonusUntil = 0;
        layer.setCapacity(0);
        synchronizeState();
        manager.setPodBuffValue(overloadId, 0);
        appliedOverload = 0;
        container.invalidateCache();
        writeStatus();
    }

    public function resumeAfterRespawn():Void {
        if (!bindingValid() || effect.group.status != "committed" || !(target.hp > 0)) return;
        cancelBloodCast();
        manager.setPodBuffValue(bloodBonusId, 0);
        bloodBonusUntil = 0;
        deathSuspended = false;
        initialShieldPending = true;
        initialShieldAllowed = target.hp >= target.hp满血值;
        startupPaid = false;
        lastFrame = pulseFrame = -1;
        grantInitialShield();
        synchronizeState();
        writeStatus();
    }

    public function getLazyDodge():Number {
        return bindingValid() && effect.group.status == "committed" && target.hp > 0 && isOnline()
            && container.getShieldById(shieldId) === layer ? config.shieldLazyDodge : 0;
    }

    /** 战技直接伤害以强化后的固有负担为锚点；联弹段数由动作声明。 */
    public function getBloodPulsePower():Number {
        return isBloodPactAnimation(bloodMan) ? bloodLoss * config.bloodPulsePowerRatio : 0;
    }

    /** 只投射到新建的血剑攻击参数；常态要求破盾，战技由动作所有权提供资格。 */
    public function projectBloodAttack(owner:Object, sword:Object, props:Object):Void {
        if (owner !== target || sword !== bloodEquipment || !(bloodLoss > 0) ||
            sword.name !== "血色光剑天秤" || !bindingValid() || deathSuspended || !(target.hp > 0) ||
            effect.group.status != "committed" || container.getShieldById(shieldId) !== layer ||
            target.攻击模式 != "兵器" || initialShieldPending || !(layer.getCapacity() === 0)) return;
        applyBloodFinishers(props);
    }

    private function applyBloodFinishers(props:Object):Void {
        props.血量上限击溃 = Math.max(finite(props.血量上限击溃) ? props.血量上限击溃 : 0, config.bloodCrumblePercent);
        props.斩杀 = Math.max(finite(props.斩杀) ? props.斩杀 : 0, config.bloodExecutePercent);
    }

    /** 每一攻击关键帧携带本次man身份，取消/卸装后的旧回调不能再发射。 */
    public function prepareBloodPactAttack(man:MovieClip, props:Object):Boolean {
        if (!isBloodPactAnimation(man)) return false;
        // 砸地帧内先配给再发射，不依赖不同图层帧脚本的执行先后。
        if (man._currentframe >= 26) grantBloodPactBonus(man);
        props.子弹威力 = getBloodPulsePower();
        applyBloodFinishers(props);
        props.hitBehavior = {type:"titaniumBloodPact", directPower:props.子弹威力,
            crumble:config.bloodCrumblePercent, execute:config.bloodExecutePercent};
        return true;
    }

    public function canBloodPact():Boolean {
        return bindingValid() && effect.group.status == "committed" && !deathSuspended && !bloodCasting
            && bloodLoss > 0 && target.攻击模式 == "兵器" && !target.倒地 && !target.浮空
            && (target.状态 == "兵器站立" || target.状态 == "兵器行走" || target.状态 == "兵器跑")
            && finite(target.hp) && target.hp > 1 && finite(target.hp满血值) && target.hp满血值 > 0
            && finite(target.mp) && target.mp >= 0 && container.getShieldById(shieldId) === layer;
    }

    /** 无事件的资源临界段。满盾和零MP均允许；费用取实际缺口，增益资格在此快照。 */
    public function commitBloodPact():Boolean {
        if (!canBloodPact()) return false;
        var paidHp:Number = Math.min(target.hp - 1, target.hp * config.bloodSkillHpRatio);
        var missing:Number = fullStrength - layer.getCapacity();
        var paidMp:Number = Math.min(target.mp, Math.max(0, missing) * config.shieldMpPerPoint);
        target.hp -= paidHp;
        spend(paidMp);
        layer.setCapacity(fullStrength);
        charged += missing;
        initialShieldPending = false;
        startupPaid = false;
        bloodPendingBonus = target.mp > 0 ? bloodLoss * paidHp / target.hp满血值 : 0;
        bloodCasting = true;
        bloodMan = null;
        bloodBonusGranted = false;
        bloodCastId++;
        container.invalidateCache();
        synchronizeState();
        writeStatus();
        return true;
    }

    /** 首帧绑定本次动作；技能强制取消时立即清理，保留既有路由的卸载回调。 */
    public function bindBloodPactAnimation(man:MovieClip):Boolean {
        if (!man || bloodMan || !bloodCasting || !bindingValid() || !(target.hp > 0)
            || target.man !== man || target.状态 != "战技") return false;
        bloodMan = man;
        man.__ti61BloodRuntime = this;
        man.__ti61BloodCastId = bloodCastId;
        var runtime:TitaniumSetRuntime = this;
        var castMan:MovieClip = man;
        var castId:Number = bloodCastId;
        var previousUnload:Function = man.onUnload;
        man.onUnload = function():Void {
            runtime.finishBloodPact(castMan, castId);
            if (previousUnload) previousUnload.apply(this);
        };
        return true;
    }

    private function isBloodPactAnimation(man:MovieClip):Boolean {
        return man && bloodCasting && bloodMan === man && man.__ti61BloodRuntime === this && man.__ti61BloodCastId === bloodCastId
            && target.man === man && target.状态 == "战技"
            && bindingValid() && effect.group.status == "committed" && target.hp > 0;
    }

    /** 砸地只兑现一次支付快照；计时从此帧起，后续低伤多段仍属于本次动作。 */
    public function grantBloodPactBonus(man:MovieClip):Void {
        if (!isBloodPactAnimation(man) || bloodBonusGranted) return;
        bloodBonusGranted = true;
        manager.setPodBuffValue(bloodBonusId, bloodPendingBonus);
        bloodPendingBonus = 0;
        bloodBonusUntil = Number(_root.帧计时器.当前帧数) + config.bloodSkillBuffSeconds * Number(_root.帧计时器.帧率);
    }

    public function finishBloodPact(man:MovieClip, castId:Number):Void {
        if (man && bloodMan === man && castId === bloodCastId) cancelBloodCast();
    }

    private function cancelBloodCast():Void {
        // MovieClip路径可能被下一招复用，只清理仍属于本实例、本次施放的标签。
        if (bloodMan && bloodMan.__ti61BloodRuntime === this && bloodMan.__ti61BloodCastId === bloodCastId) bloodMan.无敌标签 = false;
        bloodMan = null;
        bloodCasting = false;
        bloodBonusGranted = false;
        bloodPendingBonus = 0;
    }

    private function grantInitialShield():Void {
        if (!initialShieldPending) return;
        initialShieldPending = false;
        if (!initialShieldAllowed || target.hp < target.hp满血值) return;
        var before:Number = layer.getCapacity();
        layer.setCapacity(fullStrength);
        initialShieldGranted = layer.getCapacity() - before;
        startupPaid = false;
        container.invalidateCache();
    }

    private function spend(amount:Number):Void {
        target.mp = Math.max(0, target.mp - amount);
        mpSpent += amount;
    }

    // AVM1中十进制配置与字面量相除可能落在整数下方；只修正相对1e-12内的舍入尾差。
    public static function affordableUnits(available:Number, cost:Number):Number {
        if (!finite(available) || available < 0 || !finite(cost) || !(cost > 0)) return 0;
        var units:Number = Math.floor(available / cost);
        var nextCost:Number = (units + 1) * cost;
        if (nextCost - available > 0 && nextCost - available <= Math.max(1, available) * 0.000000000001) units++;
        return units;
    }

    private function healFromMp():Void {
        var missing:Number = target.hp满血值 - target.hp;
        if (!(missing > 0)) return;
        var requested:Number = Math.max(1, Math.floor((target.hp满血值 * config.healBaseHpRatioPerSecond +
            missing * config.healMissingRatioPerSecond) * config.pulseSeconds));
        var affordable:Number = affordableUnits(target.mp, config.healMpPerPoint);
        var actual:Number = HealApplier.applyHpCapped(target, Math.min(requested, affordable), target.hp满血值);
        if (actual > 0) { spend(actual * config.healMpPerPoint); healed += actual; }
    }

    private function chargeFromMp():Void {
        var capacity:Number = layer.getCapacity();
        if (!(capacity < fullStrength)) return;
        if (!(capacity > 0)) {
            if (target.hp < target.hp满血值) return;
            if (!startupPaid) {
                if (target.mp < config.startupMp) return;
                spend(config.startupMp);
                startupPaid = true;
                startups++;
            }
        }
        var requested:Number = Math.min(Math.min(fullStrength - capacity,
            fullStrength / config.fullRechargeSeconds * config.pulseSeconds),
            target.mp / config.shieldMpPerPoint);
        if (!(requested > 0)) return;
        layer.setCapacity(capacity + requested);
        var actual:Number = layer.getCapacity() - capacity;
        if (actual > 0) {
            spend(actual * config.shieldMpPerPoint);
            charged += actual;
            startupPaid = false;
            container.invalidateCache();
        }
    }

    private function onShieldChanged():Void {
        if (!disposed) container.invalidateCache();
    }

    private function onShieldBroken():Void {
        if (disposed || !initialized) return;
        if (layer.getStrength() > 0) startupPaid = false;
        synchronizeState();
        writeStatus();
    }

    private function synchronizeState():Void {
        var capacity:Number = layer.getCapacity();
        var online:Boolean = capacity > 0;
        var strength:Number = online ? fullStrength : 0;
        if (layer.getStrength() != strength) {
            layer.setStrength(strength);
            container.invalidateSort();
            container.refreshStanceResistance();
        }
        var next:String = online ? (capacity == fullStrength ? "ONLINE_FULL" : "ONLINE_DAMAGED")
            : (startupPaid && !(target.hp < target.hp满血值) ? "REBOOTING" : "BREACHED");
        if (next != phase) {
            phase = next;
            if (target._name === _root.控制目标 && typeof _root.发布消息 == "function") {
                if (phase == "BREACHED") _root.发布消息("钛合金机甲：护盾破碎，生命维持运行");
                else if (phase == "ONLINE_FULL") _root.发布消息("钛合金机甲：护盾充满");
                else if (phase == "REBOOTING") _root.发布消息("钛合金机甲：发生器重启");
            }
        }
        updateWeightAndServo(online);
        if (disposed) return;
        var missingRatio:Number = Math.max(0, Math.min(1, 1 - target.hp / target.hp满血值));
        var damage:Number = online ? 0 : armorDamage * config.overloadCoefficient * Math.pow(missingRatio, config.overloadExponent);
        if (damage != appliedOverload) {
            if (!manager.setPodBuffValue(overloadId, damage)) { structuralFailure("overload_buff_missing"); return; }
            appliedOverload = damage;
        }
    }

    private function updateWeightAndServo(online:Boolean):Void {
        var delta:Number = online && target.刀.name === "血色光剑天秤" ? -config.bloodServoBonusKg : 0;
        var rawWeight:Number = manager.getBaseValue("重量");
        var rawRatio:Number = UnitUtil.getWeightSpeedRatio(rawWeight, target.等级);
        var walkBase:Number = manager.getBaseValue("行走X速度");
        var jumpBase:Number = manager.getBaseValue("起跳速度");
        // 外部正规基值重写后，以当前未补偿负重重新取基底，避免把已有Buff读回基值。
        if (walkBase != writtenWalk) unweightedWalk = walkBase / rawRatio;
        if (jumpBase != writtenJump) unweightedJump = jumpBase / rawRatio;
        if (delta != appliedWeight) {
            if (!manager.setPodBuffValue(weightId, delta)) { structuralFailure("weight_buff_missing"); return; }
            appliedWeight = delta;
        }
        var ratio:Number = UnitUtil.getWeightSpeedRatio(target.重量, target.等级);
        if (!finite(ratio) || !(ratio > 0)) { structuralFailure("weight_ratio_invalid"); return; }
        writtenWalk = unweightedWalk * ratio;
        writtenJump = unweightedJump * ratio;
        if (walkBase != writtenWalk) manager.setBaseValue("行走X速度", writtenWalk);
        if (jumpBase != writtenJump) manager.setBaseValue("起跳速度", writtenJump);
        var multiplier:Number = online && ratio < 1 ? 1 / ratio : 1;
        if (multiplier != appliedSpeed) {
            if (!manager.setPodBuffValue(speedId, multiplier)) { structuralFailure("servo_buff_missing"); return; }
            appliedSpeed = multiplier;
        }
    }

    private function onProcessShot(owner:Object, slot:String, firedWeapon:Object):Void {
        if (!bindingValid() || effect.group.status != "committed" || !(target.hp > 0) ||
            container.getShieldById(shieldId) !== layer) return;
        if (!EquipmentFireIntent.isPistolSlotProcessShot(target, owner, slot, slot, target[slot], firedWeapon)) return;
        if (!finite(target.mp) || target.mp < 0 || !finite(target.mp满血值) || !(target.mp满血值 > 0)) return;
        // 基础循环回收一发合成成本；武器的额外发电有独立生命周期，不能被套装回滚撤销。
        baseMpEarned += HealApplier.applyMpCapped(target, config.ammoMpPerRound, target.mp满血值);
    }

    public function getFireControlProgress():Number {
        if (!bindingValid() || effect.group.status != "committed" || !(target.hp > 0) ||
            !isOnline() || container.getShieldById(shieldId) !== layer ||
            target.攻击模式 != "长枪" || target.长枪.name !== "钛合金QJZ171") return 0;
        var weight:Number = target.重量;
        return finite(weight) && weight < 0 ? Math.min(-weight,17)/17 : 0;
    }

    /** 发射边界快照；其他来源的同类贡献取高值，不回写持久模板。 */
    public function projectShot(owner:Object, slot:String, firedWeapon:Object, props:Object):Object {
        if (owner !== target || slot != "长枪" || target.长枪 !== firedWeapon) return props;
        var progress:Number = getFireControlProgress();
        if (!(progress > 0)) return props;
        var projected:Object = {};
        for (var key:String in props) projected[key] = props[key];
        var rout:Number = finite(props.血量上限击溃) ? props.血量上限击溃 : 0;
        var slay:Number = finite(props.斩杀) ? props.斩杀 : 0;
        projected.血量上限击溃 = Math.max(rout, 0.15 * progress);
        projected.斩杀 = Math.max(slay, 10 * progress);
        return projected;
    }

    private function readAmmo(slot:String):Object {
        var item:Object = target[slot];
        var source:Object = target[slot + "数据"];
        var attrs:Object = target[slot + "属性"];
        var man:Object = target.man;
        if (!item || !item.value || !source || !attrs || !man || man._parent !== target || man.换弹标签) return null;
        if (source.use != "手枪" || source.name !== item.name || typeof attrs.clipname != "string" || attrs.clipname.length == 0) return null;
        var capacity:Number = target[slot + "弹匣容量"];
        var shot:Number = item.value.shot;
        if (!finite(capacity) || capacity <= 0 || capacity != Math.floor(capacity) ||
            !finite(shot) || shot < 0 || shot > capacity || shot != Math.floor(shot)) return null;
        return {item:item, value:item.value, source:source, attrs:attrs, name:item.name,
                clipname:attrs.clipname, capacity:capacity, shot:shot, man:man,
                generation:ReloadManager.getReloadGeneration(man)};
    }

    /** 只改真实 shot；二次复核后同步扣MP/造弹，再发布可失败的视觉刷新。 */
    public function synthesizeAmmo(slot:String):Number {
        if ((slot != "手枪" && slot != "手枪2") || !bindingValid() || effect.group.status != "committed" ||
            !(target.hp > 0) || container.getShieldById(shieldId) !== layer || layer.getCapacity() != fullStrength) return 0;
        var first:Object = readAmmo(slot);
        if (!first || first.shot == 0) return 0;
        var second:Object = readAmmo(slot);
        if (!second || !bindingValid() || effect.group.status != "committed" ||
            container.getShieldById(shieldId) !== layer || layer.getCapacity() != fullStrength ||
            first.item !== second.item || first.value !== second.value || first.source !== second.source ||
            first.attrs !== second.attrs || first.name !== second.name || first.clipname !== second.clipname ||
            first.capacity != second.capacity || first.shot != second.shot || first.man !== second.man ||
            first.generation != second.generation) return 0;
        var cost:Number = config.ammoMpPerRound;
        var reserve:Number = target.mp满血值 * config.ammoReserveRatio;
        if (!finite(cost) || !(cost > 0) || !finite(reserve) || reserve < 0 ||
            !finite(target.mp) || target.mp < 0 || !finite(config.ammoMaxPerSlotPulse) ||
            !(config.ammoMaxPerSlotPulse > 0) || config.ammoMaxPerSlotPulse != Math.floor(config.ammoMaxPerSlotPulse)) return 0;
        var count:Number = Math.min(Math.min(second.shot, config.ammoMaxPerSlotPulse),
            affordableUnits(Math.max(0, target.mp - reserve), cost));
        if (!(count > 0)) return 0;
        var price:Number = count * cost;
        // 临界段内无事件/库存调用；小数尾差最多钳到既定储备线。
        target.mp = Math.max(reserve, target.mp - price);
        second.value.shot = second.shot - count;
        mpSpent += price;
        ammoMpSpent += price;
        ammoSynthesized += count;
        try {
            ReloadManager.updateAmmoDisplay(second.man, target, _root);
            var isSecondary:Boolean = slot == "手枪2" && target.攻击模式 == "双枪";
            var scale:Number = BulletTypeUtil.isVertical(second.attrs.bullet) ? second.attrs.split : 1;
            dispatcher.publish("updateBullet", target, isSecondary ? "副手射击中" : "主手射击中",
                scale * (second.capacity - second.value.shot), isSecondary ? "子弹数_2" : "子弹数", slot);
        } catch (displayError) {
            trace("[Titanium61] ammo_display_failed: " + slot + " " + displayError);
        }
        return count;
    }

    public function getState():String { return disposed ? "OFFLINE" : phase; }
    public function getShieldId():Number { return shieldId; }
    public function isOnline():Boolean { return !disposed && initialized && !deathSuspended && target.hp > 0 && layer.getCapacity() > 0; }
    public function getDiagnostics():Object {
        var progress:Number = getFireControlProgress();
        return {state:getState(), shieldId:shieldId, capacity:disposed || !layer ? 0 : layer.getCapacity(),
                maximum:fullStrength, bloodLoss:bloodLoss, lazyDodge:getLazyDodge(), deathSuspended:deathSuspended,
                bloodCasting:bloodCasting, bloodBonusGranted:bloodBonusGranted, bloodBonusUntil:bloodBonusUntil,
                startupPaid:startupPaid, mpSpent:mpSpent, initialShieldGranted:initialShieldGranted,
                healed:healed, charged:charged, startups:startups, failure:failureReason,
                baseMpEarned:baseMpEarned, ammoSynthesized:ammoSynthesized, ammoMpSpent:ammoMpSpent,
                fireControlProgress:progress, fireControlRout:0.15*progress, fireControlSlay:10*progress};
    }
    private function writeStatus():Void { target.__titaniumType61Status = getDiagnostics(); }

    public function dispose():Void {
        if (disposed) return;
        cancelBloodCast();
        disposed = true;
        initialShieldPending = false;
        startupPaid = false;
        if (dispatcher && shotHandler) dispatcher.unsubscribe("processShot", shotHandler, this);
        shotHandler = null;
        if (nightOwner) {
            weather.unregisterNightVision(nightOwner);
            if (target.红外夜视仪 === nightOwner) target.红外夜视仪 = previousNight;
            nightOwner = null;
            previousNight = null;
            weather = null;
        }
        if (manager) {
            if (weightId) manager.removeBuff(weightId);
            if (speedId) manager.removeBuff(speedId);
            if (overloadId) manager.removeBuff(overloadId);
            if (bloodBonusId) manager.removeBuff(bloodBonusId);
            manager.update(0);
            if (initialized && target.buffManager === manager) {
                var ratio:Number = UnitUtil.getWeightSpeedRatio(target.重量, target.等级);
                if (manager.getBaseValue("行走X速度") == writtenWalk) manager.setBaseValue("行走X速度", unweightedWalk * ratio);
                if (manager.getBaseValue("起跳速度") == writtenJump) manager.setBaseValue("起跳速度", unweightedJump * ratio);
            }
        }
        if (layer) {
            layer.onHitCallback = null;
            layer.onBreakCallback = null;
            if (container.getShieldById(shieldId) === layer) container.removeShieldById(shieldId);
            container.refreshStanceResistance();
            layer = null;
        }
        if (target.__titaniumType61 === this) delete target.__titaniumType61;
        writeStatus();
        equipment = null;
        ownerRef = null;
    }
}
