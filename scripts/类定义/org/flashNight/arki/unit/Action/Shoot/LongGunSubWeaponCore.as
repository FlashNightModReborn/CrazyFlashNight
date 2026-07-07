import org.flashNight.arki.item.ItemUtil;
import org.flashNight.arki.item.equipment.SubweaponDataUtil;
import org.flashNight.neur.ScheduleTimer.EnhancedCooldownWheel;

/**
 * LongGunSubWeaponCore
 *
 * 长枪副武器运行时核心。负责副武器状态装载、K 发射、F 快装、R 联动补装与 UI 弹药同步。
 */
class org.flashNight.arki.unit.Action.Shoot.LongGunSubWeaponCore {

    private static var DEFERRED_RETRY_MS:Number = 34;
    private static var MAX_DEFERRED_RETRIES:Number = 4;

    public static function configureUnit(unit:Object, itemData:Object):Boolean {
        var sub:Object = SubweaponDataUtil.getSubweaponData(itemData);
        if (!sub) {
            clearUnit(unit);
            return false;
        }

        var config:Object = buildRuntimeConfig(sub, itemData);
        var firedCount:Number = readStoredFiredCount(unit, config);
        var state:Object = {
            loaded: config.capacity - firedCount,
            capacity: config.capacity,
            reserveName: config.reserveName,
            groupPaid: config.consumeMode != "onLoadGroup" || config.initialLoaded > 0,
            nextFireTime: 0
        };

        unit.长枪副武器配置 = config;
        unit.长枪副武器状态 = state;
        unit.subWeapon = state;
        syncFiredCount(unit);
        writeRuntimeBridgeFields(unit, config);
        updateAmmoDisplay(unit);
        return true;
    }

    public static function clearUnit(unit:Object):Void {
        if (!unit) return;
        cancelPendingFire(unit);
        clearDeferredManualReload(unit);
        unit.长枪副武器配置 = null;
        unit.长枪副武器状态 = null;
        unit.subWeapon = null;
        unit.当前弹夹副武器已发射数 = 0;
        delete unit.__subweaponManualReloadLock;
        if (unit.man) {
            delete unit.man.subweaponManualReload;
        }
        if (isHero(unit) && unit.攻击模式 == "长枪") {
            var ui:Object = _root.玩家信息界面.玩家必要信息界面;
            if (ui) {
                ui.子弹数_2 = 0;
                ui.弹夹数_2 = 0;
            }
        }
    }

    public static function hasSubweapon(unit:Object):Boolean {
        return unit && unit.长枪副武器配置 && unit.长枪副武器状态;
    }

    public static function buildControlSlot(config:Object):Object {
        if (!config) return null;
        var slot:Object = {};
        slot.名字 = config.controlName ? config.controlName : "副武器快装";
        slot.冷却时间 = config.manualReloadCd > 100 ? config.manualReloadCd : 100;
        slot.消耗hp = 0;
        slot.消耗mp = 0;
        slot.技能等级 = 1;
        slot.isSubweaponControl = true;
        return slot;
    }

    public static function fire(unit:Object):Boolean {
        return fireInternal(unit, unit ? unit.man : null, true);
    }

    public static function fireFromMan(unit:Object, man:Object):Boolean {
        return fireInternal(unit, man, false);
    }

    private static function fireInternal(unit:Object, man:Object, allowPoseChange:Boolean):Boolean {
        if (!hasSubweapon(unit)) {
            return false;
        }
        if (unit.攻击模式 != "长枪") {
            return false;
        }
        if (unit.浮空 || unit.倒地) {
            return false;
        }
        if (!isLongGunActionState(unit)) {
            return false;
        }
        if (unit.换弹中) {
            return false;
        }
        if (!man) {
            return false;
        }
        if (man.换弹标签) {
            return false;
        }

        var config:Object = unit.长枪副武器配置;
        var state:Object = unit.长枪副武器状态;
        if (state.loaded <= 0) {
            updateAmmoDisplay(unit);
            return false;
        }
        if (unit.__subweaponPendingFireCdUntil != undefined) {
            return false;
        }

        var now:Number = getTimer();
        if (state.nextFireTime > now) {
            return false;
        }
        if (!canPayFireCosts(unit, config, state)) {
            return false;
        }

        if (unit.浮空) unit.temp_y = unit._y;
        else unit.temp_y = 0;

        var cooldownUntil:Number = now + config.cd;
        state.nextFireTime = cooldownUntil;
        unit.__subweaponPendingFireCdUntil = cooldownUntil;
        var targetState:String = getNormalizedLongGunActionState(unit);
        if (allowPoseChange && targetState != unit.状态) {
            unit.行走冷却帧 = 2;
            submitFireAfterPoseChange(unit, targetState);
        } else {
            finishFireOnMan(unit, man);
        }
        return true;
    }

    public static function canReloadManual(unit:Object):Boolean {
        if (!hasSubweapon(unit)) return false;
        if (unit.攻击模式 != "长枪") return false;
        if (!isLongGunActionState(unit)) return false;
        if (isManualReloadMovementLocked(unit)) return false;
        if (!unit.man || unit.man.换弹标签 || unit.man.subweaponManualReload) return false;

        var config:Object = unit.长枪副武器配置;
        var state:Object = unit.长枪副武器状态;
        if (state.loaded >= state.capacity) {
            updateAmmoDisplay(unit);
            return false;
        }

        if (!hasReloadReserve(config)) {
            updateAmmoDisplay(unit);
            return false;
        }
        return true;
    }

    public static function canReloadLinked(unit:Object):Boolean {
        if (!hasSubweapon(unit)) return false;
        var config:Object = unit.长枪副武器配置;
        var state:Object = unit.长枪副武器状态;
        if (state.loaded >= state.capacity) {
            updateAmmoDisplay(unit);
            return false;
        }
        if (!hasReloadReserve(config)) {
            updateAmmoDisplay(unit);
            return false;
        }
        return true;
    }

    public static function startManualReloadAnimation(unit:Object):Boolean {
        if (!canReloadManual(unit)) return false;

        unit.__subweaponManualReloadLock = true;
        org.flashNight.arki.unit.Action.Shoot.ShootCore.cleanup(unit);
        var targetState:String = getNormalizedLongGunActionState(unit);
        if (targetState != unit.状态) {
            unit.行走冷却帧 = 2;
            submitManualReloadAfterPoseChange(unit, targetState);
        } else {
            startManualReloadOnCurrentMan(unit);
        }
        return true;
    }

    public static function isManualReloadMovementLocked(unit:Object):Boolean {
        if (!unit) return false;
        if (unit.__subweaponManualReloadLock === true) return true;
        return unit.man != null && unit.man.subweaponManualReload === true;
    }

    public static function clearManualReloadMovementLock(unit:Object):Void {
        if (!unit) return;
        delete unit.__subweaponManualReloadLock;
        clearDeferredManualReload(unit);
    }

    public static function reloadManual(unit:Object):Boolean {
        return reloadInternal(unit, true);
    }

    public static function reloadLinked(unit:Object):Boolean {
        return reloadInternal(unit, false);
    }

    public static function reloadLinkedFree(unit:Object):Boolean {
        return reloadInternalFree(unit);
    }

    public static function updateAmmoDisplay(unit:Object):Void {
        if (!isHero(unit)) return;
        var ui:Object = _root.玩家信息界面.玩家必要信息界面;
        if (!ui) return;

        if (!hasSubweapon(unit)) {
            if (unit.攻击模式 == "长枪") {
                ui.子弹数_2 = 0;
                ui.弹夹数_2 = 0;
            }
            return;
        }

        var config:Object = unit.长枪副武器配置;
        var state:Object = unit.长枪副武器状态;
        ui.子弹数_2 = state.loaded;
        ui.弹夹数_2 = ItemUtil.getTotal(config.reserveName);
    }

    public static function calculatePower(unit:Object, config:Object):Number {
        var power:Number = config.basePower * config.powerMultiplier * config.hostPowerMultiplier;
        var passiveSkills:Object = unit.被动技能;
        if (passiveSkills && passiveSkills.冲击连携 && passiveSkills.冲击连携.启用 && config.hostWeaponType == "霰弹枪") {
            var lv:Number = passiveSkills.冲击连携.等级 || 1;
            if (lv < 1) lv = 1;
            if (lv > 10) lv = 10;
            var damageBonus:Number = 0.15 + (lv - 1) * (0.25 - 0.15) / 9;
            power *= (1 + damageBonus);
        }
        return power;
    }

    public static function getManualReloadBurden(unit:Object):Number {
        if (!hasSubweapon(unit)) return 25;
        var burden:Number = Number(unit.长枪副武器配置.manualReloadBurden);
        if (isNaN(burden) || burden <= 0) burden = 25;
        if (burden < 20) burden = 20;
        return burden;
    }

    private static function buildRuntimeConfig(sub:Object, itemData:Object):Object {
        var config:Object = {};
        config.name = sub.name;
        config.controlName = sub.controlName;
        config.description = sub.description;
        config.cd = positiveNumber(sub.cd, 500);
        config.manualReloadCd = positiveNumber(sub.manualReloadCd, config.cd);
        config.manualReloadAnimation = sub.manualReloadAnimation ? sub.manualReloadAnimation : "longGun";
        config.manualReloadBurden = positiveNumber(sub.manualReloadBurden, 25);
        if (config.manualReloadBurden < 20) config.manualReloadBurden = 20;
        config.hp = nonNegativeNumber(sub.hp, 0);
        config.mp = nonNegativeNumber(sub.mp, 0);
        config.basePower = positiveNumber(sub.power, 2500);
        config.powerMultiplier = positiveNumber(sub.powerMultiplier, 1);
        config.capacity = positiveNumber(sub.capacity, 1);
        config.reserveName = sub.reserveName ? sub.reserveName : "榴弹弹药";
        config.bullet = sub.bullet ? sub.bullet : "榴弹";
        config.sound = sub.sound ? sub.sound : "re_GL_under.wav";
        config.split = positiveNumber(sub.split, 1);
        config.diffusion = nonNegativeNumber(sub.diffusion, 0);
        config.velocity = positiveNumber(sub.velocity, 25);
        config.range = positiveNumber(sub.range, 50);
        config.impact = nonNegativeNumber(sub.impact, 0.01);
        config.consumeMode = sub.consumeMode ? sub.consumeMode : "onLoadGroup";
        config.consumeTiming = sub.consumeTiming ? sub.consumeTiming : "onReloadCommit";
        config.clipCostPerLoad = nonNegativeNumber(sub.clipCostPerLoad, 1);
        config.fireCost = nonNegativeNumber(sub.fireCost, 1);
        if (sub.initialLoaded != undefined) {
            config.initialLoaded = nonNegativeNumber(sub.initialLoaded, config.capacity);
            if (config.initialLoaded > config.capacity) config.initialLoaded = config.capacity;
        } else {
            config.initialLoaded = (config.consumeMode == "onLoadGroup" && config.consumeTiming == "onReloadCommit") ? 0 : config.capacity;
        }
        config.damageType = sub.damageType ? sub.damageType : "物理";
        config.magicType = sub.magicType;
        config.hostWeaponType = itemData ? itemData.weapontype : null;
        config.hostPowerMultiplier = readHostPowerMultiplier(itemData);
        return config;
    }

    private static function canPayFireCosts(unit:Object, config:Object, state:Object):Boolean {
        if (config.hp > 0 && unit.hp <= config.hp) return false;
        if (config.mp > 0 && unit.mp < config.mp) return false;

        if (config.consumeMode == "onFire") {
            return config.fireCost <= 0 || ItemUtil.singleContain(config.reserveName, config.fireCost) != null;
        } else if (config.consumeTiming == "linkedFirstFire" && !state.groupPaid) {
            return config.clipCostPerLoad <= 0 || ItemUtil.singleContain(config.reserveName, config.clipCostPerLoad) != null;
        }
        return true;
    }

    private static function payFireCosts(unit:Object, config:Object, state:Object):Boolean {
        if (!canPayFireCosts(unit, config, state)) return false;

        if (config.consumeMode == "onFire") {
            if (config.fireCost > 0 && !ItemUtil.singleSubmit(config.reserveName, config.fireCost)) return false;
        } else if (config.consumeTiming == "linkedFirstFire" && !state.groupPaid) {
            if (config.clipCostPerLoad > 0 && !ItemUtil.singleSubmit(config.reserveName, config.clipCostPerLoad)) return false;
            state.groupPaid = true;
        }

        if (config.hp > 0) unit.hp -= config.hp;
        if (config.mp > 0) unit.mp -= config.mp;
        return true;
    }

    private static function hasReloadReserve(config:Object):Boolean {
        if (config.consumeMode == "onLoadGroup") {
            return config.clipCostPerLoad <= 0 || ItemUtil.singleContain(config.reserveName, config.clipCostPerLoad) != null;
        }
        if (config.consumeMode == "onFire") {
            return config.fireCost <= 0 || ItemUtil.singleContain(config.reserveName, config.fireCost) != null;
        }
        return true;
    }

    private static function reloadInternal(unit:Object, manual:Boolean):Boolean {
        if (!hasSubweapon(unit)) return false;
        var config:Object = unit.长枪副武器配置;
        var state:Object = unit.长枪副武器状态;
        if (state.loaded >= state.capacity) {
            updateAmmoDisplay(unit);
            return false;
        }

        if (!hasReloadReserve(config)) {
            updateAmmoDisplay(unit);
            return false;
        }

        if (config.consumeMode == "onLoadGroup" && (config.consumeTiming == "onReloadCommit" || manual)) {
            if (config.clipCostPerLoad > 0 && !ItemUtil.singleSubmit(config.reserveName, config.clipCostPerLoad)) {
                updateAmmoDisplay(unit);
                return false;
            }
            state.groupPaid = true;
        } else if (config.consumeMode == "onLoadGroup") {
            state.groupPaid = false;
        } else {
            state.groupPaid = true;
        }

        state.loaded = state.capacity;
        syncFiredCount(unit);
        writeRuntimeBridgeFields(unit, config);
        updateAmmoDisplay(unit);
        return true;
    }

    private static function reloadInternalFree(unit:Object):Boolean {
        if (!hasSubweapon(unit)) return false;
        var config:Object = unit.长枪副武器配置;
        var state:Object = unit.长枪副武器状态;
        if (state.loaded >= state.capacity) {
            updateAmmoDisplay(unit);
            return false;
        }

        state.groupPaid = true;
        state.loaded = state.capacity;
        syncFiredCount(unit);
        writeRuntimeBridgeFields(unit, config);
        updateAmmoDisplay(unit);
        return true;
    }

    private static function shoot(unit:Object, config:Object, man:Object):Void {
        var muzzle:Object = getMuzzlePosition(man);
        var myPoint:Object = getMuzzlePoint(unit, man, muzzle);
        var angleOffset:Number = getAngleOffset(unit);
        var bulletProps:Object = {
            声音: config.sound,
            霰弹值: config.split,
            子弹散射度: config.diffusion,
            发射效果: "",
            子弹种类: config.bullet,
            子弹威力: calculatePower(unit, config),
            子弹速度: config.velocity,
            击中地图效果: "",
            Z轴攻击范围: config.range,
            击倒率: config.impact,
            击中后子弹的效果: "",
            发射者: unit._name,
            角度偏移: angleOffset,
            shootX: myPoint.x,
            shootY: myPoint.y,
            shootZ: unit.Z轴坐标,
            伤害类型: config.damageType,
            魔法伤害属性: config.magicType
        };
        if (muzzle) bulletProps.区域定位area = muzzle;
        _root.子弹区域shoot传递(bulletProps);
    }

    private static function isLongGunActionState(unit:Object):Boolean {
        if (!unit) return false;
        var prefix:String = unit.攻击模式;
        return unit.状态 === prefix + "站立" || unit.状态 === prefix + "行走" || unit.状态 === prefix + "跑";
    }

    private static function getNormalizedLongGunActionState(unit:Object):String {
        if (unit.移动射击 && unit.状态 === unit.攻击模式 + "跑") {
            return unit.攻击模式 + "行走";
        }
        if (!unit.移动射击 && unit.状态 !== unit.攻击模式 + "站立") {
            return unit.攻击模式 + "站立";
        }
        return unit.状态;
    }

    private static function submitFireAfterPoseChange(unit:Object, targetState:String):Void {
        var job:Object = unit.__stateTransitionJob;
        if (job == undefined) {
            job = {};
            unit.__stateTransitionJob = job;
        }
        job.gotoLabel = undefined;
        job.callback = LongGunSubWeaponCore.finishFireOnCurrentMan;
        job.arg_containerName = undefined;
        job.arg_targetLabel = undefined;

        changeUnitState(unit, targetState);

        // 非 StateTransition 夹具或异常兜底：生产路径应由状态切换作业在新 man 上消费。
        if (job.callback != undefined) {
            job.callback = undefined;
            job.gotoLabel = undefined;
            finishFireOnCurrentMan(unit);
        }
    }

    private static function submitManualReloadAfterPoseChange(unit:Object, targetState:String):Void {
        var job:Object = unit.__stateTransitionJob;
        if (job == undefined) {
            job = {};
            unit.__stateTransitionJob = job;
        }
        job.gotoLabel = undefined;
        job.callback = LongGunSubWeaponCore.startManualReloadOnCurrentMan;
        job.arg_containerName = undefined;
        job.arg_targetLabel = undefined;

        changeUnitState(unit, targetState);

        // 非 StateTransition 夹具或异常兜底：生产路径应由状态切换作业在新 man 上消费。
        if (job.callback != undefined) {
            job.callback = undefined;
            job.gotoLabel = undefined;
            startManualReloadOnCurrentMan(unit);
        }
    }

    private static function finishFireOnCurrentMan(unit:Object):Void {
        var man:Object = unit ? unit.man : null;
        if (!isShootManReady(man)) {
            deferFinishFireOnCurrentMan(unit);
            return;
        }
        clearDeferredFire(unit);
        finishFireOnMan(unit, man);
    }

    private static function finishFireOnMan(unit:Object, man:Object):Void {
        if (!canCommitFire(unit, man)) {
            cancelPendingFire(unit);
            return;
        }
        var config:Object = unit.长枪副武器配置;
        var state:Object = unit.长枪副武器状态;
        if (state.loaded <= 0) {
            updateAmmoDisplay(unit);
            cancelPendingFire(unit);
            return;
        }
        if (!payFireCosts(unit, config, state)) {
            updateAmmoDisplay(unit);
            cancelPendingFire(unit);
            return;
        }

        clearPendingFire(unit);
        playShootAnimation(unit, man);
        shoot(unit, config, man);
        state.loaded--;
        if (state.loaded < 0) state.loaded = 0;
        syncFiredCount(unit);
        writeRuntimeBridgeFields(unit, config);
        updateAmmoDisplay(unit);
        if (isHero(unit)) _root.玩家信息界面.刷新mp显示();
    }

    private static function readStoredFiredCount(unit:Object, config:Object):Number {
        var fallback:Number = config.capacity - config.initialLoaded;
        if (fallback < 0) fallback = 0;
        if (fallback > config.capacity) fallback = config.capacity;

        if (!unit || !unit.长枪 || !unit.长枪.value || unit.长枪.value.subweaponShot == undefined) {
            return fallback;
        }

        var fired:Number = Number(unit.长枪.value.subweaponShot);
        if (isNaN(fired) || fired < 0) fired = 0;
        if (fired > config.capacity) fired = config.capacity;
        return fired;
    }

    private static function syncFiredCount(unit:Object):Void {
        if (!unit || !unit.长枪副武器状态) return;

        var state:Object = unit.长枪副武器状态;
        var fired:Number = state.capacity - state.loaded;
        if (isNaN(fired) || fired < 0) fired = 0;
        if (fired > state.capacity) fired = state.capacity;

        unit.当前弹夹副武器已发射数 = fired;
        if (unit.长枪 && unit.长枪.value) {
            unit.长枪.value.subweaponShot = fired;
        }
    }

    private static function startManualReloadOnCurrentMan(unit:Object):Void {
        var man:MovieClip = unit.man;
        if (!canCommitManualReload(unit, man)) {
            clearManualReloadMovementLock(unit);
            return;
        }
        if (!isManualReloadManReady(man)) {
            deferStartManualReloadOnCurrentMan(unit);
            return;
        }
        clearDeferredManualReload(unit);
        man.subweaponManualReload = true;
        man.换弹标签 = true;
        man.gotoAndPlay("换弹匣");
    }

    private static function changeUnitState(unit:Object, state:String):Void {
        if (unit.状态改变) {
            unit.状态改变(state);
        } else {
            unit.状态 = state;
        }
    }

    private static function playShootAnimation(unit:Object, man:Object):Void {
        if (!man || !man.gotoAndPlay) return;
        var frameName:String = getShootFrameName(unit);
        man.gotoAndPlay(frameName);
    }

    private static function getShootFrameName(unit:Object):String {
        if (_root.控制目标 === unit._name && !unit.上下移动射击) {
            if (unit.下行) return "下射击";
            if (unit.上行) return "上射击";
        }
        return "射击";
    }

    private static function getAngleOffset(unit:Object):Number {
        if (_root.控制目标 === unit._name && !unit.上下移动射击) {
            if (unit.下行) return 30;
            if (unit.上行) return -30;
        }
        return 0;
    }

    private static function canCommitFire(unit:Object, man:Object):Boolean {
        if (!hasSubweapon(unit)) return false;
        if (unit.攻击模式 != "长枪") return false;
        if (unit.浮空 || unit.倒地) return false;
        if (!isLongGunActionState(unit)) return false;
        if (unit.换弹中) return false;
        if (!man || man.换弹标签) return false;
        return true;
    }

    private static function canCommitManualReload(unit:Object, man:Object):Boolean {
        if (!hasSubweapon(unit)) return false;
        if (unit.攻击模式 != "长枪") return false;
        if (!isLongGunActionState(unit)) return false;
        if (unit.换弹中) return false;
        if (!man || man.换弹标签) return false;
        return true;
    }

    private static function getMuzzlePosition(man:Object):Object {
        return man.枪.枪.装扮.枪口位置;
    }

    private static function isShootManReady(man:Object):Boolean {
        return man != null && getMuzzlePosition(man) != null;
    }

    private static function isManualReloadManReady(man:Object):Boolean {
        return man != null && man.gotoAndPlay != null && man.开始换弹 != null && man.换弹匣 != null && man.结束换弹 != null;
    }

    private static function deferFinishFireOnCurrentMan(unit:Object):Void {
        if (!hasSubweapon(unit)) return;
        var tries:Number = unit.__subweaponDeferredFireRetries || 0;
        if (tries >= MAX_DEFERRED_RETRIES) {
            cancelPendingFire(unit);
            return;
        }
        unit.__subweaponDeferredFireRetries = tries + 1;
        EnhancedCooldownWheel.I().addTask(LongGunSubWeaponCore.finishFireOnCurrentMan, DEFERRED_RETRY_MS, 1, unit);
    }

    private static function clearDeferredFire(unit:Object):Void {
        if (!unit) return;
        delete unit.__subweaponDeferredFireRetries;
    }

    private static function clearPendingFire(unit:Object):Void {
        if (!unit) return;
        delete unit.__subweaponPendingFireCdUntil;
        clearDeferredFire(unit);
    }

    private static function cancelPendingFire(unit:Object):Void {
        if (!unit) return;
        var state:Object = unit.长枪副武器状态;
        var hasPending:Boolean = unit.__subweaponPendingFireCdUntil != undefined;
        var pendingUntil:Number = Number(unit.__subweaponPendingFireCdUntil);
        if (hasPending && state && state.nextFireTime == pendingUntil) {
            state.nextFireTime = 0;
        }
        clearPendingFire(unit);
    }

    private static function deferStartManualReloadOnCurrentMan(unit:Object):Void {
        if (!hasSubweapon(unit)) return;
        var tries:Number = unit.__subweaponDeferredReloadRetries || 0;
        if (tries >= MAX_DEFERRED_RETRIES) {
            clearManualReloadMovementLock(unit);
            clearDeferredManualReload(unit);
            return;
        }
        unit.__subweaponDeferredReloadRetries = tries + 1;
        EnhancedCooldownWheel.I().addTask(LongGunSubWeaponCore.startManualReloadOnCurrentMan, DEFERRED_RETRY_MS, 1, unit);
    }

    private static function clearDeferredManualReload(unit:Object):Void {
        if (!unit) return;
        delete unit.__subweaponDeferredReloadRetries;
    }

    private static function getMuzzlePoint(unit:Object, man:Object, muzzle:Object):Object {
        var holder:Object = muzzle ? muzzle._parent : null;
        if (!holder && man) holder = man.枪.枪.装扮;
        if (muzzle && holder) {
            var point:Object = {x: muzzle._x, y: muzzle._y};
            holder.localToGlobal(point);
            _root.gameworld.globalToLocal(point);
            return point;
        }

        muzzle = unit.长枪_引用.枪口位置;
        holder = unit.长枪_引用;
        if (muzzle && holder) {
            var fallbackPoint:Object = {x: muzzle._x, y: muzzle._y + 20};
            holder.localToGlobal(fallbackPoint);
            _root.gameworld.globalToLocal(fallbackPoint);
            return fallbackPoint;
        }

        return {x: unit._x, y: unit._y};
    }

    private static function writeRuntimeBridgeFields(unit:Object, config:Object):Void {
        unit.副武器子弹威力 = calculatePower(unit, config);
        unit.副武器可发射数 = config.capacity;
        unit.副武器弹药类型 = config.reserveName;
        unit.副武器子弹种类 = config.bullet;
        unit.副武器子弹声音 = config.sound;
        unit.副武器子弹霰弹值 = config.split;
        unit.副武器子弹散射度 = config.diffusion;
        unit.副武器子弹速度 = config.velocity;
        unit.副武器子弹Z轴攻击范围 = config.range;
        unit.副武器子弹击倒率 = config.impact;
        unit.副武器即时消耗弹药 = config.consumeMode == "onFire";
        unit.副武器伤害类型 = config.damageType;
        unit.副武器魔法伤害属性 = config.magicType;
    }

    private static function readHostPowerMultiplier(itemData:Object):Number {
        if (!itemData) return 1;
        var rootValue:Number = Number(itemData.subweaponPowerMultiplier);
        if (!isNaN(rootValue) && rootValue > 0) return rootValue;
        var dataValue:Number = Number(itemData.data.subweaponPowerMultiplier);
        if (!isNaN(dataValue) && dataValue > 0) return dataValue;
        return 1;
    }

    private static function isHero(unit:Object):Boolean {
        return unit && _root.gameworld && _root.控制目标 && _root.gameworld[_root.控制目标] === unit;
    }

    private static function positiveNumber(value:Object, fallback:Number):Number {
        var n:Number = Number(value);
        if (isNaN(n) || n <= 0) return fallback;
        return n;
    }

    private static function nonNegativeNumber(value:Object, fallback:Number):Number {
        var n:Number = Number(value);
        if (isNaN(n) || n < 0) return fallback;
        return n;
    }
}
