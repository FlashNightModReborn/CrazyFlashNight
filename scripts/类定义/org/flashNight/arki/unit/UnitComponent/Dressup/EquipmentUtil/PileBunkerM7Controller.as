import org.flashNight.arki.unit.UnitComponent.Dressup.EquipmentUtil.*;
import org.flashNight.arki.unit.UnitComponent.Initializer.RuntimeEquipmentProjection;
import org.flashNight.arki.unit.UnitComponent.Dressup.DressupSubscriber;
import org.flashNight.arki.unit.Action.Shoot.LongGunSubWeaponCore;
import org.flashNight.arki.unit.Action.Shoot.ShootCore;
import org.flashNight.arki.unit.Action.Shoot.WeaponFireCore;
import org.flashNight.arki.item.equipment.EquipmentConfigManager;

/** 原打桩机的重锤进阶控制器；弹药和威力继续由既有射击/兵器系统维护。 */
class org.flashNight.arki.unit.UnitComponent.Dressup.EquipmentUtil.PileBunkerM7Controller {
    private var ref:Object;
    private var unit:MovieClip;
    private var equipment:Object;
    private var version:Number;
    private var data:Object;
    private var dataLease:Object;
    private var dataError:String;
    private var gunPlayer:NamedPosePlayer;
    private var bladePlayer:NamedPosePlayer;
    private var active:Boolean;
    private var aliasActive:Boolean;
    private var phase:String;
    private var poseId:Number;
    private var clipId:String;
    private var sourceFrame:Number;
    private var path:Object;
    private var pathStart:Number;
    private var destination:String;
    private var desiredForm:String;
    private var lastTick:Number;
    private var pendingBranch:String;
    private var pendingRounds:Number;
    private var pendingMultiplier:Number;
    private var pendingCommitted:Boolean;
    private var chargeNotBeforeFrame:Number;
    private var skillIntent:Boolean;
    private var skillCommitted:Boolean;
    private var lastBranch:String;
    private var shotCount:Number;
    private var lastAmmoCost:Number;
    private var lastMultiplier:Number;
    private var oldFire:Function;
    private var wrappedFire:Function;
    private var oldAttack:Function;
    private var wrappedAttack:Function;
    private var oldBladeShoot:Function;
    private var wrappedBladeShoot:Function;
    private var shotHandler:Function;
    private var placementHandler:Function;
    private var previousStyle:String;
    private var markerPoint:Object;
    private var combat:Object;
    private var tuning:Object;
    private var fuelState:Object;
    private var overloadSlot:Object;
    private var controlSlot:Object;
    private var hammerSlot:Object;
    private var originalHammerSlot:Object;
    private var ownedGunSlot:Object;
    private var hammerBuffUntil:Number;
    private var hammerEffectStage:Number;
    private var lastHammerEffectFrame:Number;
    private var lastFuelCost:Number;
    private var flameCount:Number;
    private var rockCount:Number;
    private var pendingMuzzle:MovieClip;
    private var skillHandler:Function;
    private var strikeMatrices:Object;
    private var strikeArea:MovieClip;
    private var strikeAreaOwner:Object;
    private var strikeRigIdentity:Object;
    private var meleeProjection:PileBunkerMeleeProjection;

    public function PileBunkerM7Controller(ownerRef:Object, param:Object) {
        ref = ownerRef; unit = ref.自机; equipment = unit.长枪; version = unit.version;
        data = null; dataLease = null; dataError = null;
        active = true; aliasActive = false; phase = "loading"; desiredForm = "gun";
        path = null; lastTick = -1; skillIntent = false; skillCommitted = false;
        pendingBranch = null; lastBranch = null; shotCount = 0;
        pendingRounds = 0; pendingCommitted = false; chargeNotBeforeFrame = -1;
        lastAmmoCost = 0; lastMultiplier = 1;
        tuning = param; fuelState = null; controlSlot = null; hammerSlot = null;
        overloadSlot = unit.主动战技.长枪; ownedGunSlot = overloadSlot;
        originalHammerSlot = unit.主动战技.兵器;
        hammerBuffUntil = -1; hammerEffectStage = 0; lastHammerEffectFrame = -99999;
        lastFuelCost = 0; flameCount = 0; rockCount = 0;
        strikeMatrices = null; strikeArea = null; strikeAreaOwner = null; strikeRigIdentity = null;
        meleeProjection = null;
        ref.wasTransformKeyDown = false;
        markerPoint = {x:0,y:0};
        combat = {
            N0:param.normalPowerMultiplier == undefined ? 1 : param.normalPowerMultiplier,
            N1:param.chargedPowerMultiplier == undefined ? 1 : param.chargedPowerMultiplier,
            S1:param.skillPowerMultiplier == undefined ? 1 : param.skillPowerMultiplier,
            S1Middle:param.skillMiddlePowerMultiplier,
            bladePower:Number(param.bladePower)
        };
        ref.chargeCount = 0;
        ref.chargeStep = 1;
        unit.chargeComplete = false;
        unit.__pileBunkerM7 = this;
        if (validCombat()) { configureAlias(); configureFuel(); }
        installHooks();
        if (!ref.生命周期函数列表) ref.生命周期函数列表 = [];
        ref.生命周期函数列表.push({动作:PileBunkerM7Controller.cleanup,额外参数:ref});
        var self:PileBunkerM7Controller = this;
        dataLease = NamedPoseDataStore.acquire(String(param.poseData),function(source:Object):Void {
            self.onDataReady(source);
        },function(error:String):Void { self.onDataFailed(error); });
    }

    private function onDataReady(source:Object):Void {
        if (!isCurrent()) return;
        if (!validCombat()) { onDataFailed("invalid M7 combat tuning"); return; }
        var names:Array = ["idle","ready","charge","cancel_ready","idle_used","idle_empty","N0","N1","S1","hammer_enter","hammer_hold","hammer_exit"];
        for (var i:Number = 0; i < names.length; i++) {
            if (!(source.clips[names[i]].frames instanceof Array)) { onDataFailed("missing M7 clip"); return; }
        }
        var config:Object = source.config;
        if (!(typeof source.fps == "number" && isFinite(source.fps) && source.fps > 0)
                || !(config.chargeCountMax > 0 && config.chargeCountMax < 65534 && config.chargeCountMax == (config.chargeCountMax | 0))
                || !(config.prepareTicks >= 2 && config.prepareTicks < 65534 && config.prepareTicks == (config.prepareTicks | 0))
                || !(config.transformTicks >= 2 && config.transformTicks < 65534 && config.transformTicks == (config.transformTicks | 0))
                || !(config.normalFireEntry0 >= 0 && config.normalFireEntry0 < source.clips.N0.frames.length - 1
                    && config.normalFireEntry0 == (config.normalFireEntry0 | 0))) {
            onDataFailed("invalid M7 timing"); return;
        }
        var geometry:Array = [config.bladeRotation,config.bladeX,config.bladeY,config.bladeFaceHalfHeight];
        for (i = 0; i < geometry.length; i++) {
            if (typeof geometry[i] != "number" || !isFinite(geometry[i])) { onDataFailed("invalid M7 geometry"); return; }
        }
        if (!(config.bladeFaceHalfHeight > 0)) { onDataFailed("invalid M7 hit area"); return; }
        dataError = null;
        data = source;
        releaseStrikeArea();
        gunPlayer = new NamedPosePlayer(data); bladePlayer = new NamedPosePlayer(data);
        strikeMatrices = {};
        var branches:Array = ["N0","N1","S1"];
        for (i = 0; i < branches.length; i++) {
            var branch:String = branches[i];
            var strikeFrame = config.strikeFrames0[branch];
            if (typeof strikeFrame != "number" || !isFinite(strikeFrame) || !(strikeFrame > -1)
                    || !(strikeFrame < source.clips[branch].frames.length) || strikeFrame != Math.floor(strikeFrame)) {
                onDataFailed("invalid M7 strike frame"); return;
            }
            strikeMatrices[branch] = gunPlayer.getTargetMatrix("part_main_shaft",source.clips[branch].frames[strikeFrame]);
            if (strikeMatrices[branch] == null) { onDataFailed("missing M7 strike part"); return; }
        }
        ref.chargeCountMax = config.chargeCountMax;
        holdIdle(); syncVisual();
    }

    private function validCombat():Boolean {
        var keys:Array = ["N0","N1","S1","S1Middle"];
        for (var i:Number = 0; i < keys.length; i++) {
            var value = combat[keys[i]];
            if (typeof value != "number" || !isFinite(value) || !(value > 0 && value <= 10)) return false;
        }
        if (!(combat.bladePower > 0 && combat.bladePower < 100000) || combat.S1Middle < combat.N1 || combat.S1 < combat.S1Middle) return false;
        var values:Array = [tuning.chargedCrumble,tuning.skillExecute,tuning.hammerCrumble,tuning.hammerExecute,
            tuning.rockPowerMultiplier,tuning.hammerBuffFrames,tuning.effectIntervalFrames];
        for (i = 0; i < values.length; i++) if (typeof values[i] != "number" || !isFinite(values[i]) || !(values[i] > 0)) return false;
        for (i = 0; i < 3; i++) {
            var effect:Object = tuning["flame_" + i];
            if (typeof effect.bullet != "string" || effect.bullet.length == 0
                    || !(effect.powerMultiplier > 0 && effect.powerMultiplier <= 10)) return false;
        }
        if (!(tuning.chargedCrumble <= 100 && tuning.skillExecute <= 100
                && tuning.hammerCrumble <= 100 && tuning.hammerExecute <= 100)) return false;
        return tuning.hammerBuffFrames == Math.floor(tuning.hammerBuffFrames)
            && tuning.effectIntervalFrames == Math.floor(tuning.effectIntervalFrames);
    }

    private function onDataFailed(error:String):Void {
        if (!isCurrent()) return;
        dataError = error; phase = "failed"; path = null; data = null; clearCharge();
        releaseStrikeArea(); strikeMatrices = null;
        syncControlSlot();
        if (gunPlayer) gunPlayer.reset();
        if (bladePlayer) bladePlayer.reset();
        unit.长枪_引用.动画._visible = true;
        if (ownsBlade()) unit.刀_引用.动画._visible = false;
        trace("[打桩机M7] 姿态读取失败，保留普通射击：" + error);
    }

    private function configureAlias():Void {
        var supported:Boolean = ref.是否为主角 || unit.装备能力.复合枪械 === true;
        if (!supported || typeof _root.刀配置 != "function") return;
        var intent:Object = RuntimeEquipmentProjection.reserveEmptySlotAlias(ref, "刀");
        if (intent == null) return;
        previousStyle = unit.兵器动作类型;
        _root.刀配置(unit._name, "桔色电子吉他", 1);
        if (!RuntimeEquipmentProjection.commitSlotAlias(intent)) {
            RuntimeEquipmentProjection.cancelSlotAlias(intent); return;
        }
        unit.刀_装扮 = unit.长枪_装扮;
        // 刀配置引用物品字典；只改本角色的投影，不污染供体的公共属性。
        var bladeProps:Object = {};
        for (var property:String in unit.刀属性) bladeProps[property] = unit.刀属性[property];
        unit.刀属性 = bladeProps;
        var bladeBonus:Number = Number(unit.装备刀锋利度加成);
        if (!isFinite(bladeBonus)) bladeBonus = 0;
        unit.刀属性.power = Math.floor(combat.bladePower * EquipmentConfigManager.getLevelMultiplier(equipment.value.level)) + bladeBonus;
        unit.刀属性.actiontype = "狂野";
        unit.刀_刀口数 = 3;
        unit.兵器动作类型 = "狂野";
        aliasActive = true;
        meleeProjection = new PileBunkerMeleeProjection(unit,equipment,"破击","装甲");
        refreshHammerFields();
        unit.装载主动战技(tuning.skill_1, "兵器");
        hammerSlot = unit.主动战技.兵器;
    }

    private function refreshHammerFields():Void {
        if (meleeProjection) meleeProjection.refresh();
    }
    private function projectHammerBullet(props:Object):Void {
        if (meleeProjection) meleeProjection.projectBullet(props);
    }
    private function restoreHammerFields():Void {
        if (meleeProjection) meleeProjection.restore();
    }

    private function configureFuel():Void {
        // 内置联动模块归本装备生命周期；根层仍只声明一个专属战技，避免两个特殊槽常驻双占。
        if (LongGunSubWeaponCore.hasSubweapon(unit)) return;
        if (!LongGunSubWeaponCore.configureUnit(unit, {subweapon:tuning.flamethrower,weapontype:unit.长枪数据.weapontype})) return;
        fuelState = unit.长枪副武器状态;
        controlSlot = LongGunSubWeaponCore.buildControlSlot(unit.长枪副武器配置);
        var self:PileBunkerM7Controller = this;
        fuelState.fireGuard = function():Boolean { return self.canSpray(); };
        syncControlSlot();
    }

    public function canSpray():Boolean {
        return isCurrent() && unit.长枪副武器状态 === fuelState && canFire()
            && (phase == "idle" || phase == "failed") && pendingBranch == null;
    }

    private function syncControlSlot():Void {
        if (controlSlot == null || !isCurrent()) return;
        if (unit.主动战技.长枪 !== ownedGunSlot) return;
        var slot:Object = phase == "ready" ? overloadSlot :
            ((phase == "idle" || phase == "failed") ? controlSlot : null);
        unit.主动战技.长枪 = slot;
        ownedGunSlot = slot;
    }

    private function installHooks():Void {
        var self:PileBunkerM7Controller = this;
        oldFire = unit.长枪射击;
        wrappedFire = function(muzzle:MovieClip, props:Object):Boolean {
            if (!self.isCurrent()) return false;
            if (self.pendingBranch != null) return false;
            if (!self.canFire()) { self.unit.__pendingFireInterval = 0; return false; }
            var rounds:Number = self.skillIntent ? self.remainingRounds() : 1;
            if (!(rounds > 0)) { self.unit.__pendingFireInterval = 0; return false; }
            var branch:String = self.skillIntent ? "S1" : (self.phase == "ready" ? "N1" : "N0");
            var area:MovieClip = null;
            if (self.phase != "failed") {
                self.syncVisual();
                area = self.prepareStrikeArea(branch);
                if (!area) { self.unit.__pendingFireInterval = 0; return false; }
            }
            self.pendingBranch = branch;
            var multiplier:Number = self.phase == "failed" ? 1 : self.combat[self.pendingBranch];
            if (self.pendingBranch == "S1") {
                var capacity:Number = self.unit.长枪弹匣容量;
                // 与三个机械弹仓指示窗同档；扩容只移动各档余弹区间。
                var ammoTier:Number = Math.ceil(rounds * 3 / capacity);
                multiplier = ammoTier == 1 ? self.combat.N1 : (ammoTier == 2 ? self.combat.S1Middle : self.combat.S1);
            }
            self.pendingRounds = rounds; self.pendingMultiplier = multiplier; self.pendingCommitted = false;
            self.pendingMuzzle = muzzle;
            var shotProps:Object = props;
            if (self.phase != "failed") {
                shotProps = {};
                for (var key:String in props) shotProps[key] = props[key];
                shotProps.子弹威力 *= multiplier;
                // 取该动作完整出桩轮廓的一次区域快照；不延迟扣费，也不补发第二次伤害。
                shotProps.区域定位area = area;
                if (self.pendingBranch != "N0") shotProps.血量上限击溃 = Math.max(Number(props.血量上限击溃) > 0 ? Number(props.血量上限击溃) : 0, self.tuning.chargedCrumble);
                if (self.pendingBranch == "S1") shotProps.斩杀 = Math.max(Number(props.斩杀) > 0 ? Number(props.斩杀) : 0, self.tuning.skillExecute);
            }
            // 仅投影本次发射。核心结算首发；S1在本次确切回执中补扣其余待发弹药。
            var result:Boolean = self.oldFire.call(this, muzzle, shotProps);
            self.pendingBranch = null; self.pendingRounds = 0; self.pendingMuzzle = null;
            self.syncVisual();
            return result;
        };
        if (typeof oldFire == "function") unit.长枪射击 = wrappedFire;
        oldAttack = unit.攻击;
        wrappedAttack = function() {
            if (self.isCurrent()) {
                if (self.unit.攻击模式 == "长枪" && !self.canFire()) return false;
                if (self.ownsBlade() && self.unit.攻击模式 == "兵器" && !self.canMelee()) return false;
            }
            return self.oldAttack.apply(this, arguments);
        };
        if (typeof oldAttack == "function") unit.攻击 = wrappedAttack;
        oldBladeShoot = unit.刀口位置生成子弹;
        wrappedBladeShoot = function() {
            if (self.isCurrent() && self.ownsBlade() && !self.canMelee()) return;
            // 刀技首个伤害点可以早于装备周期；先把借用锤态与刀口写回当前显示。
            if (!self.isCurrent() || !self.ownsBlade()) return self.oldBladeShoot.apply(this, arguments);
            self.syncVisual();
            self.refreshHammerFields();
            var projected:Object = {};
            var source:Object = arguments[1];
            for (var key:String in source) projected[key] = source[key];
            projected.伤害类型 = "破击"; projected.魔法伤害属性 = "装甲";
            self.projectHammerBullet(projected);
            if (self.isHammerBoosted()) {
                projected.血量上限击溃 = Math.max(Number(projected.血量上限击溃) > 0 ? Number(projected.血量上限击溃) : 0, self.tuning.hammerCrumble);
                projected.斩杀 = Math.max(Number(projected.斩杀) > 0 ? Number(projected.斩杀) : 0, self.tuning.hammerExecute);
            }
            self.oldBladeShoot.call(this, arguments[0], projected, arguments[2]);
            self.onHammerAttack();
        };
        if (typeof oldBladeShoot == "function") unit.刀口位置生成子弹 = wrappedBladeShoot;
        shotHandler = function(owner:MovieClip, weaponType:String, muzzle:MovieClip, props:Object, firedWeapon:Object):Void {
            self.onShot(owner, weaponType, firedWeapon, props);
        };
        unit.dispatcher.subscribe("processShot", shotHandler, ref);
        skillHandler = function(mode:String):Void {
            if (mode == "兵器" && self.isCurrent() && self.ownsBlade() && self.unit.主动战技.兵器 === self.hammerSlot) {
                self.hammerBuffUntil = self.now() + self.tuning.hammerBuffFrames;
                self.hammerEffectStage = 0;
            }
        };
        unit.dispatcher.subscribe("WeaponSkill", skillHandler, ref);
        placementHandler = function():Void { self.syncVisual(); };
        DressupSubscriber.onPlacement(unit, "长枪_引用", placementHandler, ref);
        if (aliasActive) DressupSubscriber.onPlacement(unit, "刀_引用", placementHandler, ref);
    }

    public function isCurrent():Boolean {
        return active && unit.__pileBunkerM7 === this && unit.version === version && unit.长枪 === equipment;
    }
    private function ownsBlade():Boolean {
        return aliasActive && unit.刀 === equipment && RuntimeEquipmentProjection.hasActiveAlias(unit,"刀","长枪");
    }
    private function isBladeSkill():Boolean {
        return ownsBlade() && (unit.状态 == "技能" || unit.状态 == "战技") && !!unit.man.兵器使用标签;
    }
    private function usesBladeVisual():Boolean {
        return ownsBlade() && (unit.攻击模式 == "兵器" || !!unit.man.兵器使用标签);
    }
    public function canFire():Boolean {
        return isCurrent() && unit.hp > 0 && unit.攻击模式 == "长枪"
            && (phase == "idle" || phase == "ready" || phase == "failed") && !unit.man.换弹标签;
    }
    public function canMelee():Boolean {
        return isCurrent() && data != null && ownsBlade() && unit.hp > 0
            && (isBladeSkill() || (usesBladeVisual() && phase == "hammer"));
    }
    public function canSkill():Boolean {
        return canFire() && phase == "ready" && unit.chargeComplete === true
            && !unit.主手射击中 && !unit.浮空 && !unit.倒地
            && remainingRounds() > 0;
    }
    public function canHammerSkill():Boolean {
        return canMelee() && phase == "hammer" && unit.攻击模式 == "兵器"
            && !unit.浮空 && !unit.倒地 && unit.状态 != "战技" && unit.状态 != "技能";
    }
    private function isHammerBoosted():Boolean {
        return ownsBlade() && unit.攻击模式 == "兵器" && now() < hammerBuffUntil;
    }
    private function remainingRounds():Number {
        var capacity:Number = Number(unit.长枪弹匣容量);
        var spent:Number = Number(equipment.value.shot);
        if (!isFinite(capacity) || !isFinite(spent) || capacity < 1 || capacity != Math.floor(capacity)
                || spent < 0 || spent != Math.floor(spent) || spent >= capacity) return 0;
        return capacity - spent;
    }

    public function releaseSkill():Boolean {
        if (skillIntent || !canSkill()) return false;
        var skill:Object = overloadSlot;
        var mpCost:Number = skill.消耗mp > 0 ? Number(skill.消耗mp) : 0;
        var hpCost:Number = skill.消耗hp > 0 ? Number(skill.消耗hp) : 0;
        if (skill.消耗sp > 0 || unit.mp < mpCost || !(unit.hp > hpCost)) return false;
        var previousA:Boolean = unit.动作A;
        skillIntent = true; skillCommitted = false;
        unit.动作A = true;
        unit.攻击();
        unit.动作A = previousA;
        skillIntent = false;
        if (!skillCommitted) return false;
        unit.mp -= mpCost; unit.hp -= hpCost;
        return true;
    }

    private function onShot(owner:MovieClip, weaponType:String, firedWeapon:Object, shotProps:Object):Void {
        if (!isCurrent() || owner !== unit || weaponType != "长枪" || firedWeapon !== equipment
                || pendingBranch == null || pendingCommitted) return;
        pendingCommitted = true;
        lastBranch = pendingBranch; shotCount++;
        lastFuelCost = 0;
        lastAmmoCost = pendingRounds; lastMultiplier = pendingMultiplier;
        if (pendingBranch == "S1") {
            // 基础监听器还会shot++，加余数与它的执行先后无关；不能直接写成弹容。
            firedWeapon.value.shot = Number(firedWeapon.value.shot) + pendingRounds - 1;
            skillCommitted = true;
        }
        unit.chargeComplete = false; ref.chargeCount = 0;
        if (data == null) return;
        var interval:Number = Number(unit.__pendingFireInterval);
        if (!(isFinite(interval) && interval > 0)) interval = Number(unit.长枪属性.interval);
        if (!(isFinite(interval) && interval > 0)) interval = 0;
        chargeNotBeforeFrame = now() + Math.ceil(interval * data.fps / 1000);
        var entry:Number = pendingBranch == "N0" ? data.config.normalFireEntry0 : 0;
        var clip:Object = data.clips[pendingBranch];
        begin("recovery", [{clip:pendingBranch,from:entry}], clip.frames.length - entry, "idle", now());
        // 先把本次出桩姿态写入真实区域，再交给原有联弹发射链读取。
        syncVisual();
        WeaponFireCore.updateMuzzlePosition(unit, pendingMuzzle, shotProps);
        if (pendingBranch == "S1") lastFuelCost = emitFuelFlames(pendingRounds, pendingMuzzle);
    }

    private function emitFuelFlames(maximum:Number, anchor:MovieClip):Number {
        if (!isCurrent() || unit.长枪副武器状态 !== fuelState || !anchor) return 0;
        var count:Number = Math.min(maximum, LongGunSubWeaponCore.getLoadedCount(unit), 3);
        if (!(count > 0) || !LongGunSubWeaponCore.consumeLoadedAmmo(unit, equipment, fuelState, count)) return 0;
        LongGunSubWeaponCore.refreshRuntimeStats(unit);
        for (var i:Number = 0; i < count; i++) emitEffect(tuning["flame_" + i], anchor, true);
        return count;
    }

    private function emitEffect(effect:Object, anchor:MovieClip, fueled:Boolean):Void {
        markerPoint.x = 0; markerPoint.y = 0;
        anchor.localToGlobal(markerPoint); _root.gameworld.globalToLocal(markerPoint);
        var props:Object = {发射者:unit._name,子弹种类:String(effect.bullet),霰弹值:1,
            声音:"",发射效果:"",击中地图效果:"",击中后子弹的效果:"",
            shootX:markerPoint.x,shootY:markerPoint.y,shootZ:unit.Z轴坐标};
        props.子弹散射度 = 0; props.子弹速度 = 0; props.Z轴攻击范围 = 50; props.击倒率 = 1;
        props.子弹威力 = fueled ? unit.长枪副武器配置.resolvedPower * effect.powerMultiplier : unit.刀属性.power * tuning.rockPowerMultiplier;
        props.伤害类型 = "破击"; props.魔法伤害属性 = fueled ? "立场" : "装甲";
        if (fueled) { props.hitBehavior = {type:"pileBunkerFuel",fuelUnits:1}; flameCount++; }
        else rockCount++;
        _root.子弹区域shoot传递(props);
    }

    private function readHammerStage():Number {
        if (unit.状态 == "战技" && unit.技能名 == "破坏殆尽") return 5;
        var state:String = typeof unit.getSmallState == "function" ? unit.getSmallState() : unit.状态;
        if (state == "兵器一段中" || state == "兵器冲击") return 1;
        if (state == "兵器四段中") return 4;
        if (state == "兵器五段中") return 5;
        return 0;
    }

    private function onHammerAttack():Void {
        if (unit.攻击模式 != "兵器" || !ownsBlade()) return;
        var stage:Number = readHammerStage();
        if (stage == 0 || stage == hammerEffectStage || now() - lastHammerEffectFrame < tuning.effectIntervalFrames) return;
        hammerEffectStage = stage; lastHammerEffectFrame = now();
        var anchor:MovieClip = unit.刀_引用.刀口位置3;
        if (isHammerBoosted() && unit.长枪副武器状态 === fuelState
                && LongGunSubWeaponCore.consumeLoadedAmmo(unit, equipment, fuelState, 1)) {
            LongGunSubWeaponCore.refreshRuntimeStats(unit);
            emitEffect(tuning["flame_" + (stage == 1 ? 0 : (stage == 4 ? 1 : 2))], anchor, true);
        } else if (stage != 4 || isHammerBoosted()) emitEffect({bullet:"碎石飞扬"}, anchor, false);
    }

    private function now():Number { return _root.帧计时器.当前帧数; }

    public function tick():Void {
        if (!isCurrent()) { dispose(); return; }
        var current:Number = now();
        if (current === lastTick) return;
        var elapsed:Number = lastTick >= 0 && current > lastTick ? current - lastTick : 1;
        var cancelRise:Boolean = KeyEdgeTrigger.onRise(ref,unit,_root.武器变形键,"wasTransformKeyDown");
        if (data == null) { lastTick = current; clearCharge(); return; }
        if (current < lastTick) { path = null; hold("idle"); clearCharge(); chargeNotBeforeFrame = current; hammerBuffUntil = -1; }
        lastTick = current;
        if (!(unit.hp > 0)) { path = null; hold("idle"); clearCharge(); syncVisual(); return; }
        // 普通刀技沿用既有即时借刀语义。仅投影完整锤态，不改枪的准备/回收状态。
        if (isBladeSkill()) {
            if (path != null) {
                if (phase == "recovery") advance(current);
                else pathStart += elapsed;
            }
            syncVisual(); return;
        }
        var mode:String = unit.攻击模式;
        if (readHammerStage() != hammerEffectStage) hammerEffectStage = 0;
        if (phase == "ready" && mode == "长枪" && cancelRise && !unit.man.换弹标签) {
            clearCharge();
            begin("unloading",[{clip:"cancel_ready",from:0}],data.config.prepareTicks,"idle",current);
        }
        desiredForm = usesBladeVisual() ? "hammer" : "gun";
        if (mode != "长枪") clearCharge();
        // 先处理形态意图。准备中转锤从当前源帧继续，不跳回目录起点。
        if (desiredForm == "hammer" && (phase == "idle" || phase == "ready" || phase == "preparing")) {
            var segments:Array = [];
            if (phase == "idle") segments.push({clip:"charge",from:0});
            if (phase == "preparing") segments.push({clip:"charge",from:sourceFrame});
            segments.push({clip:"hammer_enter",from:0});
            clearCharge();
            begin("toHammer",segments,data.config.transformTicks,"hammer",current);
        } else if (desiredForm == "gun" && phase == "hammer") {
            clearCharge();
            begin("toGun",[{clip:"hammer_exit",from:0},{clip:"cancel_ready",from:0}],data.config.transformTicks,"idle",current);
        }
        // 切到空手/其他武器也先收锤；不能在选择目标模式时直接抹掉出锤路径。
        if (mode != "长枪" && desiredForm != "hammer" && phase != "toGun" && phase != "toHammer" && phase != "recovery") {
            path = null; clearCharge(); holdIdle(); syncVisual(); return;
        }
        if (path != null) {
            // 变形沿用生命周期状态 + placement 回写；显示尚未就位时保留当前样本。
            if ((phase == "toHammer" || phase == "toGun") && !hasTransformVisual()) pathStart += elapsed;
            advance(current);
        }
        // 阈值前只有计数；阈值后准备播完，松键不主动撤销。
        if (phase == "idle" && current > chargeNotBeforeFrame && mode == "长枪" && desiredForm == "gun"
                && !unit.man.换弹标签 && equipment.value.shot < unit.长枪弹匣容量) {
            ChargeKeyAccumulator.tick(ref,unit,_root.武器变形键,true);
            if (unit.chargeComplete) begin("preparing",[{clip:"charge",from:0}],data.config.prepareTicks,"ready",current);
        }
        if (phase == "idle") holdIdle();
        syncControlSlot();
        syncVisual();
    }

    private function clearCharge():Void { ref.chargeCount = 0; unit.chargeComplete = false; }

    private function begin(state:String, segments:Array, ticks:Number, endState:String, startTick:Number):Void {
        path = NamedPosePlayer.composePath(data,segments,ticks);
        if (path == null) { onDataFailed("invalid playback path"); return; }
        phase = state; destination = endState; pathStart = startTick;
        poseId = path.poses[0]; clipId = path.clips[0]; sourceFrame = path.frames[0];
        if (phase != "idle" && fuelState != null) ShootCore.cleanupLane(unit,ShootCore.subweaponParams);
        syncControlSlot();
    }
    private function advance(current:Number):Void {
        var age:Number = current - pathStart;
        if (age < 0) age = 0;
        var last:Number = path.poses.length - 1;
        var index:Number = age > last ? last : age;
        poseId = path.poses[index]; clipId = path.clips[index]; sourceFrame = path.frames[index];
        if (age >= last) {
            var end:String = destination;
            // 回收长于射击间隔时，蓄力只能从回收结束的下一帧开始计数。
            if (phase == "recovery") chargeNotBeforeFrame = Math.max(chargeNotBeforeFrame, current);
            path = null;
            if (end == "ready") hold("ready");
            else if (end == "hammer") hold("hammer_hold");
            else holdIdle();
        }
    }
    private function hold(name:String):Void {
        clipId = name; sourceFrame = 0; poseId = data.clips[name].frames[0];
        phase = name == "ready" ? "ready" : (name == "hammer_hold" ? "hammer" : "idle");
        syncControlSlot();
    }
    private function holdIdle():Void {
        var spent:Number = equipment.value.shot;
        hold(spent >= unit.长枪弹匣容量 ? "idle_empty" : (spent > 0 ? "idle_used" : "idle"));
    }

    private function hasTransformVisual():Boolean {
        var skin:MovieClip = usesBladeVisual() ? unit.刀_引用 : unit.长枪_引用;
        // 与 DressupReferenceManager 的活动 man 分支合同一致；旧分支仍有 parent 不代表可见。
        return skin._parent._parent._parent === unit.man && skin.动画._parent != undefined;
    }

    public function syncVisual():Void {
        if (!isCurrent() || data == null) return;
        var gun:MovieClip = unit.长枪_引用;
        var blade:MovieClip = unit.刀_引用;
        var bladeMode:Boolean = usesBladeVisual();
        var displayPose:Number = isBladeSkill() ? data.clips.hammer_hold.frames[0] : poseId;
        var capacity:Number = unit.长枪弹匣容量;
        var remaining:Number = capacity - equipment.value.shot;
        var liveSlots:Number = capacity > 0 && remaining > 0 ? Math.ceil(remaining * 3 / capacity) : 0;
        if (gunPlayer.bind(gun.动画)) {
            gun.动画._visible = !bladeMode;
            gunPlayer.applyPose(displayPose); gunPlayer.setAmmo(liveSlots);
            updateGunMuzzle(gun);
        }
        if (ownsBlade() && bladePlayer.bind(blade.动画)) {
            blade.动画._visible = bladeMode;
            blade.动画._rotation = data.config.bladeRotation;
            blade.动画._x = data.config.bladeX; blade.动画._y = data.config.bladeY;
            bladePlayer.applyPose(displayPose); bladePlayer.setAmmo(liveSlots);
            updateBladeMarkers(blade);
            if (bladeMode) unit.兵器动作类型 = "狂野";
        }
    }
    private function prepareStrikeArea(branch:String):MovieClip {
        var rig:MovieClip = unit.长枪_引用.动画;
        var shaft:MovieClip = gunPlayer.getAnchor("part_main_shaft");
        if (!shaft || !rig.__namedPoseIdentity || strikeMatrices[branch] == null) return null;
        if (strikeRigIdentity !== rig.__namedPoseIdentity || strikeArea.__pileBunkerOwner !== strikeAreaOwner || strikeAreaOwner == null) {
            releaseStrikeArea();
            var bounds:Object = shaft.getRect(shaft);
            if (!(bounds.xMax > bounds.xMin && bounds.yMax > bounds.yMin)) return null;
            strikeArea = rig.createEmptyMovieClip("__pileBunkerStrikeArea",rig.getNextHighestDepth());
            strikeAreaOwner = {}; strikeArea.__pileBunkerOwner = strikeAreaOwner;
            strikeRigIdentity = rig.__namedPoseIdentity;
            strikeArea.beginFill(0xFF0000,100);
            strikeArea.moveTo(bounds.xMin,bounds.yMin); strikeArea.lineTo(bounds.xMax,bounds.yMin);
            strikeArea.lineTo(bounds.xMax,bounds.yMax); strikeArea.lineTo(bounds.xMin,bounds.yMax);
            strikeArea.lineTo(bounds.xMin,bounds.yMin); strikeArea.endFill();
            strikeArea._alpha = 0;
        }
        strikeArea.transform.matrix = strikeMatrices[branch];
        return strikeArea;
    }

    private function releaseStrikeArea():Void {
        if (strikeAreaOwner != null && strikeArea.__pileBunkerOwner === strikeAreaOwner) strikeArea.removeMovieClip();
        strikeArea = null; strikeAreaOwner = null; strikeRigIdentity = null;
    }

    private function updateGunMuzzle(gun:MovieClip):Void {
        var anchor:MovieClip = gunPlayer.getAnchor("anchor_tip");
        if (!anchor || !gun.枪口位置) return;
        markerPoint.x = 0; markerPoint.y = 0;
        anchor.localToGlobal(markerPoint); gun.globalToLocal(markerPoint);
        gun.枪口位置._x = markerPoint.x; gun.枪口位置._y = markerPoint.y;
    }
    private function updateBladeMarkers(blade:MovieClip):Void {
        var anchor:MovieClip = bladePlayer.getAnchor("anchor_face");
        if (!anchor) return;
        for (var i:Number = 1; i <= 3; i++) {
            markerPoint.x = anchor._x;
            markerPoint.y = anchor._y + (i - 2) * data.config.bladeFaceHalfHeight;
            blade.动画.localToGlobal(markerPoint);
            blade.globalToLocal(markerPoint);
            var node:MovieClip = blade["刀口位置" + i];
            node._x = markerPoint.x; node._y = markerPoint.y;
            node._rotation = data.config.bladeRotation;
        }
    }

    public function getSnapshot():Object {
        return {phase:phase,clip:clipId,frame0:sourceFrame,poseId:poseId,chargeCount:ref.chargeCount,
            charged:unit.chargeComplete,lastBranch:lastBranch,shots:shotCount,alias:ownsBlade(),
            lastAmmoCost:lastAmmoCost,lastMultiplier:lastMultiplier,chargeNotBeforeFrame:chargeNotBeforeFrame,
            fuel:unit.长枪副武器状态 === fuelState ? LongGunSubWeaponCore.getLoadedCount(unit) : 0,
            lastFuelCost:lastFuelCost,flames:flameCount,rocks:rockCount,hammerBuffUntil:hammerBuffUntil,
            canFire:canFire(),canSkill:canSkill(),canMelee:canMelee(),active:active,dataReady:data != null,dataError:dataError};
    }
    public function dispose():Void {
        if (!active) return;
        if (unit.__pileBunkerM7 === this) {
            clearCharge();
            if (unit.长枪副武器状态 === fuelState && fuelState != null) LongGunSubWeaponCore.clearUnit(unit, unit.长枪 === equipment);
            if (unit.长枪 === equipment && unit.主动战技.长枪 === ownedGunSlot) unit.主动战技.长枪 = overloadSlot;
            if (hammerSlot != null && unit.主动战技.兵器 === hammerSlot) unit.主动战技.兵器 = originalHammerSlot;
            if (unit.长枪射击 === wrappedFire) unit.长枪射击 = oldFire;
            if (unit.攻击 === wrappedAttack) unit.攻击 = oldAttack;
            if (unit.刀口位置生成子弹 === wrappedBladeShoot) unit.刀口位置生成子弹 = oldBladeShoot;
            restoreHammerFields();
            if (ownsBlade() && unit.兵器动作类型 == "狂野") unit.兵器动作类型 = previousStyle;
            delete unit.__pileBunkerM7;
        }
        unit.dispatcher.unsubscribe("processShot",shotHandler,ref);
        unit.dispatcher.unsubscribe("WeaponSkill",skillHandler,ref);
        unit.dispatcher.unsubscribe("长枪_引用",placementHandler,ref);
        unit.dispatcher.unsubscribe("刀_引用",placementHandler,ref);
        releaseStrikeArea(); strikeMatrices = null;
        if (gunPlayer) gunPlayer.reset();
        if (bladePlayer) bladePlayer.reset();
        NamedPoseDataStore.release(dataLease);
        dataLease = null; data = null; gunPlayer = null; bladePlayer = null;
        active = false; path = null;
    }
    public static function cleanup(value:Object):Void { value.pileBunkerController.dispose(); }
}
