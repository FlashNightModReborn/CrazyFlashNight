import org.flashNight.arki.item.ItemUtil;
import org.flashNight.arki.item.equipment.SubweaponDataUtil;
import org.flashNight.arki.unit.Action.Input.UnitActionIntentService;
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
        var reloadCount:Number = readStoredReloadCount(unit);
        var state:Object = {
            loaded: getLoadedCountFromFired(config.capacity, firedCount),
            capacity: config.capacity,
            reserveName: config.reserveName,
            reloadCount: reloadCount,
            groupPaid: config.consumeMode != "onLoadGroup" || config.initialLoaded > 0,
            nextFireTime: 0
        };

        unit.长枪副武器配置 = config;
        unit.长枪副武器状态 = state;
        unit.subWeapon = state;
        installVirtualWeapon(unit, config, state, firedCount);
        syncSnapshots(unit);
        refreshRuntimeStats(unit);
        updateAmmoDisplay(unit);
        return true;
    }

    public static function clearUnit(unit:Object, persistStoredMirror:Boolean):Void {
        if (!unit) return;
        cancelPendingFire(unit);
        UnitActionIntentService.cancelKind(
            unit,
            UnitActionIntentService.CHANNEL_COMBAT,
            UnitActionIntentService.KIND_SUBWEAPON_RELOAD
        );
        if (persistStoredMirror !== false) {
            syncSnapshots(unit);
        }
        org.flashNight.arki.unit.Action.Shoot.ShootCore.cleanupLane(
            unit,
            org.flashNight.arki.unit.Action.Shoot.ShootCore.subweaponParams
        );
        unit.长枪副武器配置 = null;
        unit.长枪副武器状态 = null;
        unit.长枪副武器 = null;
        unit.长枪副武器弹匣容量 = 0;
        unit.长枪副武器属性 = null;
        delete unit.长枪副武器射击;
        unit.subWeapon = null;
        unit.当前弹夹副武器已发射数 = 0;
        delete unit.__subweaponShootingMan;
        if (unit.man) {
            clearReloadRequest(unit.man);
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

    public static function prepareManBulletProps(unit:Object, man:Object):Object {
        if (!hasSubweapon(unit) || !man) return null;
        ensureRuntimeStatsFresh(unit);
        var config:Object = unit.长枪副武器配置;
        var props:Object = man.副武器子弹属性;
        if (!props) props = {};

        var angleOffset:Number = Number(props.角度偏移);
        if (isNaN(angleOffset)) angleOffset = getAngleOffset(unit);

        props.声音 = config.sound;
        props.霰弹值 = config.split;
        props.子弹散射度 = config.diffusion;
        props.站立子弹散射度 = config.diffusion;
        props.移动子弹散射度 = config.diffusion;
        props.发射效果 = "";
        props.子弹种类 = config.bullet;
        props.子弹威力 = config.resolvedPower;
        props.子弹速度 = config.velocity;
        props.击中地图效果 = "";
        props.Z轴攻击范围 = config.range;
        props.击倒率 = config.resolvedImpact;
        props.击中后子弹的效果 = "";
        props.发射者 = unit._name;
        props.角度偏移 = angleOffset;
        props.伤害类型 = config.damageType;
        props.魔法伤害属性 = config.magicType;
        props.ammoCost = 1;

        man.副武器子弹属性 = props;
        return props;
    }

    public static function getBulletPropsForShoot(core:Object, man:Object, laneConfig:Object, context:Object):Object {
        return prepareManBulletProps(core, man);
    }

    public static function getMagazineRemaining(core:Object, weaponType:String, bulletAttr:Object, context:Object):Number {
        if (!hasSubweapon(core)) return 0;
        return getLoadedCount(core);
    }

    public static function buildShootContext(unit:Object):Object {
        if (!hasSubweapon(unit)) return null;
        var config:Object = unit.长枪副武器配置;
        return {
            params: org.flashNight.arki.unit.Action.Shoot.ShootCore.subweaponParams,
            weaponType: "长枪副武器",
            fireMethodName: "长枪副武器射击",
            preFireEventName: null,
            postShotEventName: "长枪副武器射击",
            interval: config.cd,
            emptyPolicy: "denyNoReload",
            useSemiAuto: false,
            useGunslinger: false,
            useGlobalRecoilTask: false,
            recoilPolicy: "aggregate",
            // 射速门禁仍使用完整 config.cd；动作/转向后摇最多 300ms。
            shootingStateCapMs: 300,
            blockOnReload: true,
            refreshManEachTick: true,
            shootingManFieldName: "__subweaponShootingMan",
            shotOwner: unit.长枪副武器,
            magazineCapacity: unit.长枪副武器状态.capacity,
            bulletPropsProvider: LongGunSubWeaponCore.getBulletPropsForShoot,
            magazineRemainingProvider: LongGunSubWeaponCore.getMagazineRemaining
        };
    }

    public static function fire(unit:Object):Boolean {
        return requestShoot(unit);
    }

    // 兼容 / 测试入口。运行时输入入口必须使用 requestShoot(unit)，避免跨状态持有旧 man。
    public static function fireFromMan(unit:Object, man:Object):Boolean {
        return fireInternal(unit, man, false);
    }

    public static function requestShoot(unit:Object):Boolean {
        return fireInternal(unit, unit ? unit.man : null, true);
    }

    public static function executeShot(unit:Object, muzzlePosition:MovieClip, bulletProps:Object):Boolean {
        if (!hasSubweapon(unit)) return false;
        var man:Object = unit.__subweaponShootingMan ? unit.__subweaponShootingMan : unit.man;
        if (!canCommitFire(unit, man)) {
            updateAmmoDisplay(unit);
            return false;
        }

        var config:Object = unit.长枪副武器配置;
        var state:Object = unit.长枪副武器状态;
        if (getLoadedCount(unit) <= 0) {
            updateAmmoDisplay(unit);
            return false;
        }
        if (!canPayFireCosts(unit, config, state)) {
            updateAmmoDisplay(unit);
            return false;
        }

        if (!bulletProps) bulletProps = prepareManBulletProps(unit, man);
        if (!bulletProps) return false;
        if (muzzlePosition) bulletProps.区域定位area = muzzlePosition;

        var ok:Boolean = org.flashNight.arki.unit.Action.Shoot.WeaponFireCore.executeShot(
            unit,
            "长枪副武器",
            muzzlePosition,
            bulletProps,
            LongGunSubWeaponCore.commitFireCosts
        );
        if (!ok) {
            updateAmmoDisplay(unit);
            return false;
        }

        state.nextFireTime = getTimer() + config.cd;
        syncSnapshots(unit);
        ensureRuntimeStatsFresh(unit);
        updateAmmoDisplay(unit);
        if (isHero(unit)) _root.玩家信息界面.刷新mp显示();
        return true;
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
        if (getLoadedCount(unit) <= 0) {
            updateAmmoDisplay(unit);
            return false;
        }
        if (unit.__subweaponPoseChangePending == true) {
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

        var targetState:String = getNormalizedLongGunActionState(unit);
        if (!unit.移动射击 && targetState != unit.状态) {
            if (allowPoseChange) {
                unit.行走冷却帧 = 2;
                changeUnitState(unit, targetState);
            }
            return false;
        }
        if (allowPoseChange && targetState != unit.状态) {
            unit.行走冷却帧 = 2;
            submitFireAfterPoseChange(unit, targetState);
        } else {
            return startShootingOnMan(unit, man);
        }
        return true;
    }

    public static function canReloadManual(unit:Object):Boolean {
        if (!hasSubweapon(unit)) return false;
        if (unit.攻击模式 != "长枪") return false;
        if (!isLongGunActionState(unit)) return false;
        if (!unit.man || unit.man.换弹标签 || isManualReloadRequest(unit.man)) return false;

        var config:Object = unit.长枪副武器配置;
        var state:Object = unit.长枪副武器状态;
        if (getLoadedCount(unit) >= state.capacity) {
            updateAmmoDisplay(unit);
            return false;
        }

        if (!hasReloadReserve(config) && !canTacticalFreeReload(unit, config, state)) {
            updateAmmoDisplay(unit);
            return false;
        }
        return true;
    }

    public static function canReloadLinked(unit:Object):Boolean {
        if (!hasSubweapon(unit)) return false;
        var config:Object = unit.长枪副武器配置;
        var state:Object = unit.长枪副武器状态;
        if (getLoadedCount(unit) >= state.capacity) {
            updateAmmoDisplay(unit);
            return false;
        }
        if (!hasReloadReserve(config) && !canTacticalFreeReload(unit, config, state)) {
            updateAmmoDisplay(unit);
            return false;
        }
        return true;
    }

    public static function setManualReloadRequest(target:Object, unit:Object):Object {
        return setReloadRequest(target, unit, "manual");
    }

    public static function setLinkedReloadRequest(target:Object, unit:Object):Object {
        return setReloadRequest(target, unit, "linked");
    }

    public static function setFreeReloadRequest(target:Object, unit:Object):Object {
        return setReloadRequest(target, unit, "free");
    }

    public static function getReloadRequest(target:Object):Object {
        if (!target) return null;
        return target.subweaponReloadRequest;
    }

    public static function isManualReloadRequest(target:Object):Boolean {
        var request:Object = getReloadRequest(target);
        return request != null && request.kind == "manual";
    }

    public static function isLinkedReloadRequest(target:Object):Boolean {
        var request:Object = getReloadRequest(target);
        return request != null && request.kind == "linked";
    }

    public static function isSubweaponReloadRequest(target:Object):Boolean {
        var request:Object = getReloadRequest(target);
        return request != null && request.weaponType == "长枪副武器";
    }

    public static function clearReloadRequest(target:Object):Void {
        if (!target) return;
        delete target.subweaponReloadRequest;
        delete target.subweaponManualReload;
        delete target.subweaponLinkedReload;
    }

    public static function commitReloadRequest(target:Object, unit:Object):Boolean {
        var request:Object = getReloadRequest(target);
        if (request == null) return false;
        if (request.kind == "manual") return reloadManual(unit);
        if (request.kind == "linked") return reloadLinked(unit);
        if (request.kind == "free") return reloadLinkedFree(unit);
        return false;
    }

    public static function commitLinkedReloadRequest(target:Object, unit:Object):Boolean {
        if (!isLinkedReloadRequest(target)) return false;
        return reloadLinked(unit);
    }

    public static function startManualReloadAnimation(unit:Object):Boolean {
        if (!canReloadManual(unit)) return false;

        org.flashNight.arki.unit.Action.Shoot.ShootCore.cleanup(unit);
        var targetState:String = getNormalizedLongGunActionState(unit);
        if (targetState != unit.状态) {
            unit.行走冷却帧 = 2;
            changeUnitState(unit, targetState);
        }
        return startManualReloadOnCurrentMan(unit);
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
        ui.子弹数_2 = getLoadedCount(unit);
        ui.弹夹数_2 = ItemUtil.getTotal(config.reserveName);
    }

    public static function getFiredCount(unit:Object):Number {
        if (!unit || !unit.长枪副武器状态) return 0;

        var state:Object = unit.长枪副武器状态;
        var capacity:Number = getStateCapacity(state);
        var fired:Number;

        if (unit.长枪副武器 && unit.长枪副武器.value && unit.长枪副武器.value.shot != undefined) {
            fired = Number(unit.长枪副武器.value.shot);
        } else if (unit.长枪 && unit.长枪.value && unit.长枪.value.subweaponShot != undefined) {
            fired = Number(unit.长枪.value.subweaponShot);
        } else {
            fired = capacity - Number(state.loaded);
        }
        return clampFiredCount(fired, capacity);
    }

    public static function getLoadedCount(unit:Object):Number {
        if (!unit || !unit.长枪副武器状态) return 0;
        var state:Object = unit.长枪副武器状态;
        return getLoadedCountFromFired(getStateCapacity(state), getFiredCount(unit));
    }

    public static function setFiredCount(unit:Object, fired:Number):Void {
        if (!unit || !unit.长枪副武器状态) return;

        var state:Object = unit.长枪副武器状态;
        var count:Number = clampFiredCount(fired, getStateCapacity(state));
        if (unit.长枪副武器 && unit.长枪副武器.value) {
            unit.长枪副武器.value.shot = count;
        }
        if (unit.长枪 && unit.长枪.value) {
            unit.长枪.value.subweaponShot = count;
        }
        syncSnapshots(unit);
    }

    public static function syncSnapshots(unit:Object):Void {
        if (!unit || !unit.长枪副武器状态) return;

        var state:Object = unit.长枪副武器状态;
        var capacity:Number = getStateCapacity(state);
        var fired:Number = getFiredCount(unit);
        var loaded:Number = getLoadedCountFromFired(capacity, fired);
        var reloadCount:Number = getReloadCount(unit);

        state.loaded = loaded;
        state.reloadCount = reloadCount;
        unit.subWeapon = state;
        unit.当前弹夹副武器已发射数 = fired;
        if (unit.长枪副武器 && unit.长枪副武器.value) {
            unit.长枪副武器.value.shot = fired;
            unit.长枪副武器.value.reloadCount = reloadCount;
        }
        unit.长枪副武器弹匣容量 = capacity;
        if (unit.长枪副武器属性 && unit.长枪副武器配置) {
            unit.长枪副武器属性.interval = unit.长枪副武器配置.cd;
        }
        if (unit.长枪 && unit.长枪.value) {
            unit.长枪.value.subweaponShot = fired;
            unit.长枪.value.subweaponReloadCount = reloadCount;
        }
    }

    public static function markRuntimeStatsDirty(unit:Object):Void {
        if (!hasSubweapon(unit)) return;
        unit.长枪副武器配置.runtimeStatsDirty = true;
    }

    public static function refreshRuntimeStats(unit:Object):Void {
        if (!hasSubweapon(unit)) return;
        var config:Object = unit.长枪副武器配置;
        var signature:String = buildRuntimeStatsSignature(unit, config);
        var stats:Object = resolveRuntimeStats(unit, config);

        config.resolvedPower = stats.power;
        config.resolvedImpact = stats.impact;
        config.runtimeStatsSignature = signature;
        config.runtimeStatsDirty = false;
        writeRuntimeBridgeFields(unit, config);
    }

    private static function ensureRuntimeStatsFresh(unit:Object):Void {
        if (!hasSubweapon(unit)) return;
        var config:Object = unit.长枪副武器配置;
        var signature:String = buildRuntimeStatsSignature(unit, config);
        if (config.runtimeStatsDirty
            || config.runtimeStatsSignature != signature
            || config.resolvedPower == undefined
            || config.resolvedImpact == undefined) {
            refreshRuntimeStats(unit);
        }
    }

    private static function resolveRuntimeStats(unit:Object, config:Object):Object {
        return {
            power: calculatePower(unit, config),
            impact: calculateImpact(unit, config)
        };
    }

    private static function buildRuntimeStatsSignature(unit:Object, config:Object):String {
        var passiveSkills:Object = unit.被动技能;
        var chain:Object = passiveSkills ? passiveSkills.冲击连携 : null;
        var chainEnabled:Number = (chain && chain.启用) ? 1 : 0;
        var chainLevel:Number = chain ? Number(chain.等级 || 1) : 0;
        if (isNaN(chainLevel)) chainLevel = 0;
        var gunpower:Number = Number(unit.装备枪械威力加成);
        if (isNaN(gunpower)) gunpower = 0;

        return [
            config.basePower,
            config.powerMultiplier,
            config.hostPowerMultiplier,
            config.hostWeaponType,
            config.impact,
            chainEnabled,
            chainLevel,
            gunpower
        ].join("|");
    }

    public static function calculatePower(unit:Object, config:Object):Number {
        var power:Number = config.basePower * config.powerMultiplier * config.hostPowerMultiplier;
        var passiveSkills:Object = unit.被动技能;
        if (passiveSkills && passiveSkills.冲击连携 && passiveSkills.冲击连携.启用 && config.hostWeaponType == "霰弹枪") {
            var lv:Number = passiveSkills.冲击连携.等级 || 1;
            if (lv < 1) lv = 1;
            if (lv > 10) lv = 10;
            var damageMultiplier:Number = 1.5 + (lv - 1) * (2.0 - 1.5) / 9;
            power *= damageMultiplier;
        }
        if (passiveSkills && passiveSkills.冲击连携 && passiveSkills.冲击连携.启用) {
            var impactLv:Number = passiveSkills.冲击连携.等级 || 1;
            if (impactLv < 1) impactLv = 1;
            if (impactLv > 10) impactLv = 10;
            var gunpower:Number = Number(unit.装备枪械威力加成);
            if (!isNaN(gunpower) && gunpower > 0) {
                power += gunpower * ((impactLv - 1) * 0.50 / 9);
            }
        }
        return power;
    }

    public static function calculateImpact(unit:Object, config:Object):Number {
        var baseImpact:Number = Number(config.impact);
        if (isNaN(baseImpact)) baseImpact = 0.01;
        if (baseImpact == 0) return 0;
        if (baseImpact < 0) baseImpact = 0.01;

        var passiveSkills:Object = unit.被动技能;
        if (passiveSkills && passiveSkills.冲击连携 && passiveSkills.冲击连携.启用) {
            var lv:Number = passiveSkills.冲击连携.等级 || 1;
            if (lv < 1) lv = 1;
            if (lv > 10) lv = 10;
            var impactBonus:Number = 0.50 + (lv - 1) * (1.00 - 0.50) / 9;
            return baseImpact / (1 + impactBonus);
        }
        return baseImpact;
    }

    public static function getManualReloadBurden(unit:Object):Number {
        if (!hasSubweapon(unit)) return 25;
        var burden:Number = Number(unit.长枪副武器配置.manualReloadBurden);
        if (isNaN(burden) || burden <= 0) burden = 25;
        if (burden < 20) burden = 20;
        return burden;
    }

    private static function setReloadRequest(target:Object, unit:Object, kind:String):Object {
        if (!target) return null;
        var request:Object = {
            weaponType: "长枪副武器",
            kind: kind,
            unitName: unit ? unit._name : null
        };
        target.subweaponReloadRequest = request;
        delete target.subweaponManualReload;
        delete target.subweaponLinkedReload;
        return request;
    }

    private static function getStateCapacity(state:Object):Number {
        if (!state) return 0;
        var capacity:Number = Number(state.capacity);
        if (isNaN(capacity) || capacity < 0) capacity = 0;
        return capacity;
    }

    private static function clampFiredCount(fired:Number, capacity:Number):Number {
        var count:Number = Number(fired);
        if (isNaN(count) || count < 0) count = 0;
        if (count > capacity) count = capacity;
        return count;
    }

    private static function getLoadedCountFromFired(capacity:Number, fired:Number):Number {
        var loaded:Number = capacity - clampFiredCount(fired, capacity);
        if (isNaN(loaded) || loaded < 0) loaded = 0;
        if (loaded > capacity) loaded = capacity;
        return loaded;
    }

    private static function sanitizeReloadCount(value:Object):Number {
        var count:Number = Number(value);
        if (isNaN(count) || count < 0) count = 0;
        return Math.floor(count);
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

    private static function installVirtualWeapon(unit:Object, config:Object, state:Object, firedCount:Number):Void {
        var fired:Number = clampFiredCount(firedCount, getStateCapacity(state));
        var reloadCount:Number = Number(state.reloadCount);
        if (isNaN(reloadCount) || reloadCount < 0) reloadCount = 0;

        unit.长枪副武器 = {
            name: config.name,
            value: {shot: fired, reloadCount: reloadCount}
        };
        unit.长枪副武器弹匣容量 = state.capacity;
        unit.长枪副武器属性 = {
            interval: config.cd,
            reloadType: "subweapon"
        };
        unit.长枪副武器射击 = function(muzzlePosition:MovieClip, bulletProps:Object):Boolean {
            return LongGunSubWeaponCore.executeShot(unit, muzzlePosition, bulletProps);
        };
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
            if (config.fireCost > 0 && !ItemUtil.singleSubmit(config.reserveName,
                    config.fireCost, {source:"weapon_cost", reason:"subweapon_fire"})) return false;
        } else if (config.consumeTiming == "linkedFirstFire" && !state.groupPaid) {
            if (config.clipCostPerLoad > 0 && !ItemUtil.singleSubmit(config.reserveName,
                    config.clipCostPerLoad,
                    {source:"weapon_cost", reason:"subweapon_linked_first_fire"})) return false;
            state.groupPaid = true;
        }

        if (config.hp > 0) unit.hp -= config.hp;
        if (config.mp > 0) unit.mp -= config.mp;
        return true;
    }

    private static function commitFireCosts(unit:Object, weaponType:String, bulletProps:Object):Boolean {
        if (!hasSubweapon(unit)) return false;
        return payFireCosts(unit, unit.长枪副武器配置, unit.长枪副武器状态);
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
        if (getLoadedCount(unit) >= state.capacity) {
            updateAmmoDisplay(unit);
            return false;
        }

        var hasReserve:Boolean = hasReloadReserve(config);
        var hasTacticalFreeReload:Boolean = canTacticalFreeReload(unit, config, state);
        if (!hasReserve && !hasTacticalFreeReload) {
            updateAmmoDisplay(unit);
            return false;
        }

        var weaponValue:Object = unit.长枪副武器.value;
        var weaponHadReloadCount:Boolean = weaponValue.reloadCount != undefined;
        var weaponReloadCountBefore = weaponValue.reloadCount;
        var stateHadReloadCount:Boolean = state.reloadCount != undefined;
        var stateReloadCountBefore = state.reloadCount;
        var tacticalFreeReload:Boolean = applyTacticalRecovery(unit, config, state);
        if (tacticalFreeReload) {
            state.groupPaid = true;
        } else if (config.consumeMode == "onLoadGroup" && (config.consumeTiming == "onReloadCommit" || manual)) {
            if (config.clipCostPerLoad > 0 && !ItemUtil.singleSubmit(config.reserveName,
                    config.clipCostPerLoad,
                    {source:"reload", reason:"subweapon_reload", mergeScope:"operation"})) {
                // 付费提交失败时撤销本次战术回收尝试；否则重复按换弹会累计同一
                // 未卸弹匣并最终免费补满，造成无真实损失的弹药注入。
                if (weaponHadReloadCount) weaponValue.reloadCount = weaponReloadCountBefore;
                else delete weaponValue.reloadCount;
                if (stateHadReloadCount) state.reloadCount = stateReloadCountBefore;
                else delete state.reloadCount;
                updateAmmoDisplay(unit);
                return false;
            }
            state.groupPaid = true;
        } else if (config.consumeMode == "onLoadGroup") {
            state.groupPaid = false;
        } else {
            state.groupPaid = true;
        }

        setFiredCount(unit, 0);
        ensureRuntimeStatsFresh(unit);
        updateAmmoDisplay(unit);
        return true;
    }

    private static function canTacticalFreeReload(unit:Object, config:Object, state:Object):Boolean {
        if (!canUseTacticalRecovery(unit, config)) return false;
        return org.flashNight.arki.unit.Action.Shoot.ReloadManager.canTacticalFreeReloadValue(
            unit.长枪副武器.value,
            state.capacity,
            getGunslingerLevel(unit)
        );
    }

    private static function applyTacticalRecovery(unit:Object, config:Object, state:Object):Boolean {
        if (!canUseTacticalRecovery(unit, config)) return false;
        var freeReload:Boolean = org.flashNight.arki.unit.Action.Shoot.ReloadManager.applyTacticalRecovery(
            unit.长枪副武器.value,
            state.capacity,
            getGunslingerLevel(unit)
        );
        state.reloadCount = unit.长枪副武器.value.reloadCount;
        return freeReload;
    }

    private static function canUseTacticalRecovery(unit:Object, config:Object):Boolean {
        if (!isHero(unit)) return false;
        if (config.consumeMode != "onLoadGroup") return false;
        if (!unit.被动技能 || !unit.被动技能.枪械师 || !unit.被动技能.枪械师.启用) return false;
        return true;
    }

    private static function getGunslingerLevel(unit:Object):Number {
        var lv:Number = Number(unit.被动技能.枪械师.等级 || 1);
        if (isNaN(lv) || lv < 1) lv = 1;
        if (lv > 10) lv = 10;
        return lv;
    }

    private static function reloadInternalFree(unit:Object):Boolean {
        if (!hasSubweapon(unit)) return false;
        var config:Object = unit.长枪副武器配置;
        var state:Object = unit.长枪副武器状态;
        if (getLoadedCount(unit) >= state.capacity) {
            updateAmmoDisplay(unit);
            return false;
        }

        state.groupPaid = true;
        setFiredCount(unit, 0);
        ensureRuntimeStatsFresh(unit);
        updateAmmoDisplay(unit);
        return true;
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

    private static function isSubweaponShootPoseReady(unit:Object):Boolean {
        if (!isLongGunActionState(unit)) return false;
        var prefix:String = unit.攻击模式;
        if (!unit.移动射击) {
            return unit.状态 === prefix + "站立";
        }
        return unit.状态 !== prefix + "跑";
    }

    private static function submitFireAfterPoseChange(unit:Object, targetState:String):Void {
        unit.__subweaponPoseChangePending = true;
        var job:Object = unit.__stateTransitionJob;
        if (job == undefined) {
            job = {};
            unit.__stateTransitionJob = job;
        }
        job.gotoLabel = undefined;
        job.callback = LongGunSubWeaponCore.startShootingOnCurrentMan;
        job.arg_containerName = undefined;
        job.arg_targetLabel = undefined;

        changeUnitState(unit, targetState);

        // 非 StateTransition 夹具或异常兜底：生产路径应由状态切换作业在新 man 上消费。
        if (job.callback != undefined) {
            job.callback = undefined;
            job.gotoLabel = undefined;
            startShootingOnCurrentMan(unit);
        }
    }

    private static function startShootingOnCurrentMan(unit:Object):Void {
        if (!unit) return;
        delete unit.__subweaponPoseChangePending;
        var man:Object = unit ? unit.man : null;
        if (!isShootManReady(man)) {
            deferFinishFireOnCurrentMan(unit);
            return;
        }
        clearDeferredFire(unit);
        startShootingOnMan(unit, man);
    }

    private static function finishFireOnCurrentMan(unit:Object):Void {
        startShootingOnCurrentMan(unit);
    }

    private static function startShootingOnMan(unit:Object, man:Object):Boolean {
        if (!canCommitFire(unit, man)) {
            cancelPendingFire(unit);
            return false;
        }
        var config:Object = unit.长枪副武器配置;
        var state:Object = unit.长枪副武器状态;
        if (getLoadedCount(unit) <= 0) {
            updateAmmoDisplay(unit);
            cancelPendingFire(unit);
            return false;
        }
        if (!canPayFireCosts(unit, config, state)) {
            updateAmmoDisplay(unit);
            cancelPendingFire(unit);
            return false;
        }

        installVirtualWeapon(unit, config, state, getFiredCount(unit));
        unit.__subweaponShootingMan = man;
        prepareManBulletProps(unit, man);
        var context:Object = buildShootContext(unit);
        return org.flashNight.arki.unit.Action.Shoot.ShootCore.startShootingAs(
            unit,
            man,
            org.flashNight.arki.unit.Action.Shoot.ShootCore.subweaponParams,
            context
        );
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

    private static function readStoredReloadCount(unit:Object):Number {
        if (!unit) return 0;
        if (unit.长枪副武器 && unit.长枪副武器.value && unit.长枪副武器.value.reloadCount != undefined) {
            return sanitizeReloadCount(unit.长枪副武器.value.reloadCount);
        }
        if (unit.长枪 && unit.长枪.value && unit.长枪.value.subweaponReloadCount != undefined) {
            return sanitizeReloadCount(unit.长枪.value.subweaponReloadCount);
        }
        return 0;
    }

    private static function getReloadCount(unit:Object):Number {
        if (!unit || !unit.长枪副武器状态) return 0;
        if (unit.长枪副武器 && unit.长枪副武器.value && unit.长枪副武器.value.reloadCount != undefined) {
            return sanitizeReloadCount(unit.长枪副武器.value.reloadCount);
        }
        return sanitizeReloadCount(unit.长枪副武器状态.reloadCount);
    }

    private static function startManualReloadOnCurrentMan(unit:Object):Boolean {
        var man:MovieClip = unit ? unit.man : null;
        if (!canCommitManualReload(unit, man)) return false;
        // 与普通换弹一致：状态改变返回后直接由当前 man 持有 request 与换弹标签。
        // unit 不保存跨动画移动锁；技能/受伤等替换 man 时，换弹所有权随旧 man 自然退场。
        if (!man.gotoAndPlay) return false;
        setManualReloadRequest(man, unit);
        man.换弹标签 = true;
        man.gotoAndPlay("换弹匣");
        return true;
    }

    private static function changeUnitState(unit:Object, state:String):Void {
        if (unit.状态改变) {
            unit.状态改变(state);
        } else {
            unit.状态 = state;
        }
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
        if (!isSubweaponShootPoseReady(unit)) return false;
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
        delete unit.__subweaponPoseChangePending;
        delete unit.__subweaponShootingMan;
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

    private static function writeRuntimeBridgeFields(unit:Object, config:Object):Void {
        var power:Number = Number(config.resolvedPower);
        if (isNaN(power)) power = calculatePower(unit, config);
        var impact:Number = Number(config.resolvedImpact);
        if (isNaN(impact)) impact = calculateImpact(unit, config);

        unit.副武器子弹威力 = power;
        unit.副武器可发射数 = config.capacity;
        unit.副武器弹药类型 = config.reserveName;
        unit.副武器子弹种类 = config.bullet;
        unit.副武器子弹声音 = config.sound;
        unit.副武器子弹霰弹值 = config.split;
        unit.副武器子弹散射度 = config.diffusion;
        unit.副武器子弹速度 = config.velocity;
        unit.副武器子弹Z轴攻击范围 = config.range;
        unit.副武器子弹击倒率 = impact;
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
