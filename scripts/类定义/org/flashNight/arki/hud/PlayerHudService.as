import org.flashNight.arki.hud.PlayerHudBuffProjection;
import org.flashNight.arki.unit.UnitComponent.Targetcache.TargetCacheManager;
import org.flashNight.arki.unit.Action.Skill.ManualCooldownService;
import org.flashNight.arki.unit.Action.Skill.DrugInputService;
import org.flashNight.arki.unit.Action.Shoot.LongGunSubWeaponCore;
import org.flashNight.arki.skill.SkillLoadoutService;
import org.flashNight.arki.item.ItemUtil;
import org.flashNight.arki.item.DrugHudMutationService;
import org.flashNight.arki.render.FrameBroadcaster;
import org.flashNight.arki.scene.StageReturnFlow;
import org.flashNight.arki.interaction.NativeInteractionContext;
import org.flashNight.gesh.tooltip.NativeTooltipBridge;
import org.flashNight.gesh.tooltip.NativeTooltipDocument;
/**
 * Live HUD projection. No MovieClip renderer, gameplay clock or inventory authority.
 * pi:<base64(UTF8 safe JSON)> uses bounded replacement in FrameBroadcaster.
 * Groups replace atomically; explicit full/clear packets establish each actor epoch.
 * Writes are once-only intents; unknown completion is queried, never replayed.
 */
class org.flashNight.arki.hud.PlayerHudService {
    private static var jsonCodec:LiteJSON;
    private static function json():LiteJSON { if (jsonCodec == null) jsonCodec = new LiteJSON(); return jsonCodec; }
    private static var installed:Boolean = false;
    private static var epoch:Number = 0;
    private static var sequence:Number = 0;
    private static var actorCounter:Number = 0;
    private static var actorId:Number = 0;
    private static var worldToken:Object;
    private static var connected:Boolean = false;
    private static var forceFull:Boolean = true;
    private static var wasVisible:Boolean = false;
    private static var poiseDetailsEnabled:Boolean = false;
    private static var lastFull:Number = 0;
    private static var lastProjectionError:Number = -10000;
    private static var profileEnabled:Boolean = false;
    private static var profileId:String = "";
    private static var profileSamples:Array = [];
    private static var profileStart:Number = 0;
    private static var profilePackets:Number = 0;
    private static var profileBytes:Number = 0;
    private static var tickCount:Number = 0;
    private static var rawGroups:Object = {};
    private static var loadout:Object;
    private static var drugRevision:Number = 0;
    private static var drugSignature:String = "";
    private static var drugItems:Array = [];
    private static var drugCounts:Array = [];
    private static var ammo:Array = ["", "", "", ""];
    private static var ammoMode:String = "";
    private static var primaryOwner:Object;
    private static var secondaryOwner:Object;
    private static var lastCombat:Object;
    private static var compat:Object;
    private static var buffProjection:PlayerHudBuffProjection;
    private static var outcomes:Object = {};
    private static var outcomeOrder:Array = [];
    private static var hoverId:String = "";
    private static var hoverRequest:String;
    private static var modes:Array = ["手枪", "手枪2", "长枪", "兵器", "手雷", "空手", "双枪", "长枪副武器"];

    public static function install():Void {
        if (installed) return;
        installed = true;
        buffProjection = new PlayerHudBuffProjection();
        _root.UI系统 = _root.UI系统 || {};
        _root.UI系统.iconBar = buffProjection;
        compat = createCompatibility();
        _root.玩家信息界面 = compat;
        _root.玩家必要信息界面 = compat.玩家必要信息界面;
        _root.gameCommands["playerHudAction"] = function(p:Object):Void { PlayerHudService.handleAction(p); };
        _root.gameCommands["playerHudQuery"] = function(p:Object):Void { PlayerHudService.handleQuery(p); };
        _root.gameCommands["playerHudTooltip"] = function(p:Object):Void { PlayerHudService.handleTooltip(p); };
        _root.gameCommands["playerHudSync"] = configureProjection;
        _root.gameCommands["playerHudProfile"] = function(p:Object):Void { PlayerHudService.setProfile(p); };
        NativeInteractionContext.onSceneTeardown(PlayerHudService.clear);
        FrameBroadcaster.setPlayerHudCapture(function():Void { PlayerHudService.captureFrameEnd(); });
        var driver:MovieClip = _root.createEmptyMovieClip("__playerHudProjection", _root.getNextHighestDepth());
        driver.onEnterFrame = function():Void { PlayerHudService.lifecycleTick(); };
    }
    public static function lifecycleTick():Void {
        // The simulation's frameEnd is suspended when paused; clear/paused projection still lives.
        if (_root.server.isSocketConnected !== true || typeof _root.gameworld != "movieclip" || _root.暂停 === true) captureSafely();
    }
    public static function captureFrameEnd():Void {
        if (_root.暂停 !== true) captureSafely();
    }
    private static function captureSafely():Void {
        var started:Number = profileEnabled ? getTimer() : 0;
        try { tick(); }
        catch (error) {
            // Projection failures must not cancel this frame's audio, camera or input packet.
            FrameBroadcaster.setPlayerHudPayload(null);
            forceFull = true;
            if (getTimer() - lastProjectionError > 5000) {
                lastProjectionError = getTimer();
                trace("[PlayerHud] projection unavailable: " + error);
            }
            try { clear(); } catch (clearError) { }
        }
        if (profileEnabled) {
            try { recordProfile(getTimer() - started); }
            catch (profileError) { profileEnabled = false; }
        }
    }
    public static function setProfile(p:Object):Void {
        if (typeof p.enabled != "boolean" || text(p.profileId).substr(0, 4) != "php:" || length(text(p.profileId)) > 48) return;
        profileEnabled = p.enabled; profileId = p.profileId;
        profileSamples = []; profileStart = getTimer(); profilePackets = profileBytes = 0;
    }
    private static function recordProfile(elapsed:Number):Void {
        profileSamples.push(Math.max(0, elapsed));
        if (profileSamples.length < 300) return;
        profileSamples.sort(Array.NUMERIC);
        var total:Number = 0;
        for (var i:Number = 0; i < profileSamples.length; i++) total += profileSamples[i];
        _root.server.sendServerMessage("[PlayerHudPerf] " + json().stringifySafe({id:profileId, source:"as2",
            samples:300, windowMs:getTimer()-profileStart, meanMs:total/300, p50Ms:profileSamples[149],
            p95Ms:profileSamples[284], maxMs:profileSamples[299], packets:profilePackets, encodedBytes:profileBytes}));
        profileSamples.length = 0; profileStart = getTimer(); profilePackets = profileBytes = 0;
    }
    private static function hero():Object { return TargetCacheManager.findHero(); }
    private static function ensureContext(unit:Object):Boolean {
        var world:Object = StageReturnFlow.worldIdentity(_root.gameworld);
        if (!unit || world === undefined) return false;
        if (unit.__nativePlayerHudActorId == undefined) unit.__nativePlayerHudActorId = ++actorCounter;
        if (worldToken !== world || actorId != unit.__nativePlayerHudActorId) {
            worldToken = world;
            actorId = unit.__nativePlayerHudActorId;
            epoch++;
            rawGroups = {};
            loadout = null;
            drugSignature = "";
            ammo = ["", "", "", ""];
            ammoMode = ""; primaryOwner = secondaryOwner = null; lastCombat = null;
            compat.玩家必要信息界面.mode = "";
            forceFull = true;
            buffProjection.initialize(unit.buffManager);
        }
        return true;
    }
    public static function clear():Void {
        hideTooltip();
        if (buffProjection != null) buffProjection.deinitialize();
        worldToken = undefined;
        actorId = 0;
        loadout = null;
        rawGroups = {};
        ammo = ["", "", "", ""]; ammoMode = "";
        primaryOwner = secondaryOwner = null; lastCombat = null;
        forceFull = true;
        epoch++;
        FrameBroadcaster.setPlayerHudPayload(null);
        if (_root.server.isSocketConnected === true) sendImmediate({v:1, epoch:epoch, seq:++sequence, full:true, visible:false});
        wasVisible = false;
    }
    private static function configureProjection(p:Object):Void {
        // Older isolated candidates keep their exact v1 field set until they opt in.
        if (p.poiseDetails === true) poiseDetailsEnabled = true;
        forceFull = true;
    }
    public static function tick():Void {
        var online:Boolean = _root.server.isSocketConnected === true;
        if (!online) { connected = false; poiseDetailsEnabled = false; forceFull = true; FrameBroadcaster.setPlayerHudPayload(null); return; }
        if (!connected) { connected = true; forceFull = true; }
        var unit:Object = hero();
        if (!ensureContext(unit) || typeof _root.gameworld != "movieclip") {
            if (wasVisible || forceFull) { clear(); forceFull = false; }
            return;
        }
        buffProjection.initialize(unit.buffManager);
        _root.UI系统.iconBar = buffProjection;
        tickCount++;
        var full:Boolean = forceFull || FrameBroadcaster.hasPlayerHudPending() || getTimer() - lastFull > 2000;
        if (loadout == null || full || tickCount % 3 == 0) loadout = readLoadout();
        var groups:Object = {};
        var count:Number = 0;
        if (addGroup(groups, "vitals", readVitals(unit), full)) count++;
        if (addGroup(groups, "combat", readCombat(unit), full)) count++;
        if (addGroup(groups, "loadout", loadout, full)) count++;
        if (addGroup(groups, "cooldowns", readCooldowns(), full)) count++;
        if (addGroup(groups, "buffs", buffProjection.snapshot(), full)) count++;
        compat._pendingHpDisplayRefresh = false;
        if (count == 0) return;
        var packet:Object = {v:1, epoch:epoch, seq:++sequence, full:full, visible:true, groups:groups};
        var encoded:String = Base64.encodeDisplay(json().stringifySafe(packet));
        if (length(encoded) > 131072) { clear(); return; }
        if (profileEnabled) { profilePackets++; profileBytes += length(encoded); }
        if (_root.暂停 === true) {
            FrameBroadcaster.setPlayerHudPayload(null);
            _root.server.sendSocketMessage("Upi:" + encoded);
        } else FrameBroadcaster.setPlayerHudPayload("pi:" + encoded);
        if (full) lastFull = getTimer();
        forceFull = false;
        wasVisible = true;
    }
    private static function addGroup(groups:Object, key:String, value:Object, full:Boolean):Boolean {
        // These are detached display DTOs. Compare values before serializing so an
        // unchanged frame never walks thousands of JSON characters (or Base64).
        if (!full && sameProjection(rawGroups[key], value)) return false;
        rawGroups[key] = value;
        groups[key] = value;
        return true;
    }
    private static function sameProjection(previous, current):Boolean {
        if (previous === current) return true;
        if (typeof previous != "object" || typeof current != "object" || previous == null || current == null) return false;
        if (previous instanceof Array || current instanceof Array) {
            if (!(previous instanceof Array) || !(current instanceof Array) || previous.length != current.length) return false;
            for (var i:Number = 0; i < current.length; i++) if (!sameProjection(previous[i], current[i])) return false;
            return true;
        }
        var count:Number = 0;
        var name:String;
        for (name in current) {
            if (!current.hasOwnProperty(name)) continue;
            if (!previous.hasOwnProperty(name) || !sameProjection(previous[name], current[name])) return false;
            count++;
        }
        for (name in previous) if (previous.hasOwnProperty(name)) count--;
        return count == 0;
    }
    private static function finiteValue(value):Number { var n:Number = Number(value); return (n - n) == 0 ? n : 0; }
    private static function text(value):String { return value == undefined || value == null ? "" : String(value); }
    private static function readVitals(unit:Object):Object {
        var shield:Object = unit.shield;
        var shieldReady:Boolean = shield != null && typeof shield.getMaxCapacity == "function";
        var shieldCapacity:Number = shieldReady ? Number(shield.getCapacity()) : 0;
        var shieldMaximum:Number = shieldReady ? Number(shield.getMaxCapacity()) : 0;
        if (!isFinite(shieldCapacity) || !isFinite(shieldMaximum)) shieldReady = false;
        var shieldPresent:Boolean = shieldReady && shieldMaximum > 0;
        var result:Object = {hp:[finiteValue(unit.hp), finiteValue(unit.hp满血值)], mp:[finiteValue(unit.mp), finiteValue(unit.mp满血值)],
            shield:[shieldPresent ? finiteValue(shield.getCapacity()) : 0, shieldPresent ? finiteValue(shield.getMaxCapacity()) : 0],
            shieldPresent:shieldPresent, shieldReady:shieldReady, poise:finiteValue(unit.nonlinearMappingResilience),
            experience:[finiteValue(_root.经验值), finiteValue(_root.上次升级需要经验值), finiteValue(_root.升级需要经验值)],
            level:finiteValue(_root.等级), name:text(_root.角色名), sp:finiteValue(_root.技能点数),
            paused:!!_root.暂停, decorations:_root.__nativeHudDecorations !== false};
        if (poiseDetailsEnabled) result.poiseDetail = readPoiseDetail(unit);
        return result;
    }
    private static function readPoiseDetail(unit:Object):Object {
        // Consume ImpactHandler's authoritative derived values. Never refresh gameplay
        // attributes, advance decay, or infer a threshold from the rounded HUD percent.
        var cap:Number = Number(unit.韧性上限);
        var boundary:Number = Number(unit.impactStaggerBoundary);
        var impact:Number = Number(unit.remainingImpactForce);
        if (!(cap > 0) || !isFinite(cap) || !isFinite(boundary) || boundary < 0 || !isFinite(impact) || impact < 0)
            return {threshold:0, hasStaggerBand:false, phase:"unavailable"};
        var threshold:Number = Math.max(0, Math.min(1, 1 - Math.sqrt(boundary / cap)));
        var phase:String = unit.浮空 ? "air" : unit.倒地 ? "down" :
            (unit.刚体 || unit.man.刚体标签) ? "rigid" : impact > cap ? "break" :
            impact > boundary ? "stagger" : "buffer";
        return {threshold:threshold, hasStaggerBand:boundary < cap, phase:phase};
    }
    private static function readCombat(unit:Object):Object {
        var mode:String = text(unit.攻击模式);
        if (mode == "长枪" && LongGunSubWeaponCore.hasSubweapon(unit)) mode = "长枪副武器";
        var valid:Boolean = false;
        for (var i:Number = 0; i < modes.length; i++) if (modes[i] == mode) valid = true;
        if (!valid) return lastCombat != null ? lastCombat : {mode:"", ammo:["", "", "", ""],
            weapon:{visible:false, name:"", mp:0, cooldownMs:0, key:keyLabel("武器技能键")}};
        compat.玩家必要信息界面.mode = mode;
        synchronizeAmmoOwners(unit);
        var skill:Object = unit.主动战技[unit.攻击模式];
        lastCombat = {mode:mode, ammo:[text(ammo[0]), text(ammo[1]), text(ammo[2]), text(ammo[3])],
            weapon:{visible:skill != null && skill.isSubweaponControl !== true,
            name:weaponName(skill), mp:finiteValue(skill.消耗mp), cooldownMs:finiteValue(skill.冷却时间),
            key:keyLabel("武器技能键")}};
        return lastCombat;
    }
    private static function synchronizeAmmoOwners(unit:Object):Void {
        var mode:String = text(unit.攻击模式);
        var primary:Object = mode == "双枪" ? unit.手枪 : unit[mode];
        var secondary:Object = mode == "双枪" ? unit.手枪2 : (mode == "长枪" ? unit.长枪副武器状态 : null);
        if (mode != ammoMode || primary !== primaryOwner) {
            ammo[0] = ammo[1] = ammo[2] = ammo[3] = "";
        } else if (secondary !== secondaryOwner) {
            ammo[2] = ammo[3] = "";
        }
        ammoMode = mode; primaryOwner = primary; secondaryOwner = secondary;
    }
    private static function weaponName(skill:Object):String {
        return text(skill.名字 != undefined ? skill.名字 : skill.名称);
    }
    private static function percentage(current:Number, maximum:Number):String {
        return maximum > 0 ? Math.floor(current / maximum * 100) + "%" : "未就绪";
    }
    private static function keyLabel(name:String):String {
        var code:Number = Number(_root[name]);
        return isFinite(code) && _root.keyshow != undefined ? text(_root.keyshow(code)) : "";
    }
    private static function readLoadout():Object {
        var skills:Object = SkillLoadoutService.getHudDescriptors();
        var bank:Number = DrugInputService.getActiveBank();
        var source:Object = _root.物品栏.药剂栏;
        var signature:String = String(bank);
        var changed:Boolean = false;
        var i:Number;
        for (i = 0; i < 8; i++) {
            var item:Object = source.getItem(String(i));
            var count:Number = item == null ? 0 : finiteValue(item.value);
            if (drugItems[i] !== item || drugCounts[i] != count) changed = true;
            drugItems[i] = item;
            drugCounts[i] = count;
            signature += ";" + text(item.name) + ":" + count;
        }
        if (changed || signature !== drugSignature) { drugSignature = signature; drugRevision++; }
        var drugs:Array = [];
        for (i = 0; i < 4; i++) {
            var slot:Number = bank * 4 + i;
            var current:Object = drugItems[slot];
            var data:Object = current == null ? null : ItemUtil.getItemData(current.name);
            drugs.push({slot:slot, name:text(current.name), icon:text(data.icon), count:drugCounts[slot],
                key:keyLabel(DrugInputService.getKeyName(i))});
        }
        return {revision:finiteValue(skills.revision), skills:skills.slots, drugRevision:drugRevision,
            bank:bank, drugs:drugs, switchKey:keyLabel(DrugInputService.getSwitchKeyName())};
    }
    private static function readCooldowns():Array {
        var result:Array = [];
        var keys:Array = [ManualCooldownService.WEAPON_SKILL_KEY];
        var i:Number;
        for (i = 1; i < 13; i++) keys.push(ManualCooldownService.quickSkillKey(i));
        for (i = 0; i < 4; i++) keys.push(ManualCooldownService.drugKey(i));
        keys.push(ManualCooldownService.drugSwitchKey());
        for (i = 0; i < keys.length; i++) {
            var state:Object = ManualCooldownService.getSnapshot(keys[i]);
            result.push([state.ready === true ? 1 : 0, finiteValue(state.currentStep), finiteValue(state.totalSteps)]);
        }
        return result;
    }
    private static function validContext(p:Object):Boolean {
        var unit:Object = hero();
        return ensureContext(unit) && Number(p.epoch) == epoch && wasVisible;
    }
    public static function handleAction(p:Object):Void {
        var id:String = text(p.actionId);
        if (length(id) < 5 || length(id) > 96 || id.substr(0, 3) != "ph:") return;
        var prior:Object = outcomes[id];
        if (prior != undefined) { sendResult(id, prior); return; }
        var result:Object = {success:false, error:"stale_state"};
        // Store pending BEFORE the first domain call. A thrown listener leaves a queryable unknown write.
        outcomes[id] = {success:false, error:"pending"};
        outcomeOrder.push(id);
        if (outcomeOrder.length > 128) delete outcomes[outcomeOrder.shift()];
        if (validContext(p) && typeof p.paused == "boolean" && p.paused === !!_root.暂停) {
            var current:Object = readLoadout();
            var slot:Number = Number(p.slot);
            if (p.kind == "skill" && slot > 0 && slot < 13 && Math.floor(slot) == slot
                    && Number(p.revision) == current.revision && text(p.key) == text(current.skills[slot - 1].skillKey)) {
                result = SkillLoadoutService.unequip(slot, current.revision);
            } else if (p.kind == "drug" && slot > -1 && slot < 8 && Math.floor(slot) == slot
                    && Math.floor(slot / 4) == current.bank && Number(p.revision) == drugRevision
                    && text(p.key) == text(drugItems[slot].name)) {
                result = DrugHudMutationService.unequip(_root, slot, drugItems[slot], drugCounts[slot], false);
            } else if (p.kind == "switch" && Number(p.revision) == drugRevision) {
                result = DrugInputService.switchFromHud(hero(), Number(p.bank));
            }
        }
        if (result == null || typeof result.success != "boolean" ||
                (result.success === false && length(text(result.error)) == 0)) {
            outcomes[id] = {success:false, error:"unknown", changed:false};
        } else {
            outcomes[id] = {success:result.success === true, error:text(result.error), changed:result.changed === true};
        }
        if (p.kind == "skill" && outcomes[id].success && outcomes[id].changed) SkillLoadoutService.runOptionalRenderers();
        forceFull = true;
        captureSafely();
        sendResult(id, outcomes[id]);
    }
    public static function handleQuery(p:Object):Void {
        var id:String = text(p.actionId);
        if (length(id) > 96 || id.substr(0, 3) != "ph:") return;
        var result:Object = outcomes[id];
        sendResult(id, result == undefined ? {success:false, error:"unknown"} : result);
    }
    private static function sendResult(id:String, result:Object):Void {
        sendImmediate({v:1, result:{actionId:id, success:result.success === true, error:text(result.error), changed:result.changed === true}});
    }
    private static function sendImmediate(packet:Object):Void {
        if (_root.server.isSocketConnected === true) _root.server.sendSocketMessage("Upi:" + Base64.encodeDisplay(json().stringifySafe(packet)));
    }
    public static function handleTooltip(p:Object):Void {
        var id:String = text(p.hoverId);
        if (p.op == "hide") { if (id == hoverId) hideTooltip(); return; }
        if (!validContext(p)) return;
        var anchor:Object = p.anchor;
        if (anchor == null || !isFinite(Number(anchor.x)) || !isFinite(Number(anchor.y))
                || !isFinite(Number(anchor.width)) || !isFinite(Number(anchor.height))
                || anchor.width < 1 || anchor.height < 1 || anchor.x < 0 || anchor.y < 0
                || anchor.x + anchor.width > 1024 || anchor.y + anchor.height > 576) return;
        var current:Object = readLoadout();
        var slot:Number = Number(p.slot);
        hideTooltip();
        hoverId = id;
        if (p.kind == "skill" && slot > 0 && slot < 13 && Math.floor(slot) == slot
                && Number(p.revision) == current.revision && text(p.key) == text(current.skills[slot-1].skillKey)) {
            var rows:Array = _root.主角技能表;
            for (var i:Number = 0; i < rows.length; i++) {
                if (rows[i][0] === p.key) {
                    var parts:Object = org.flashNight.gesh.tooltip.SkillTooltipComposer.describeLoadout(i);
                    NativeTooltipBridge.show(parts.document, null, "top", anchor);
                    break;
                }
            }
        } else if (p.kind == "drug" && slot > -1 && slot < 8 && Math.floor(slot) == slot
                && Number(p.revision) == drugRevision && text(p.key) == text(drugItems[slot].name)) {
            var item:Object = drugItems[slot];
            if (item != null) {
                var projection:Object = org.flashNight.arki.item.InventoryPanelService.buildTooltipProjection(item);
                if (projection.success) NativeTooltipBridge.show(projection.document, null, "top", anchor);
            }
        } else if (p.kind == "weapon") {
            var unit:Object = hero();
            var skill:Object = unit.主动战技[unit.攻击模式];
            if (skill != null && skill.isSubweaponControl !== true && weaponName(skill) == text(p.key)) {
                var intro:String = "<B>" + weaponName(skill) + "</B><BR>冷却：" + finiteValue(skill.冷却时间) / 1000 + " 秒";
                intro += "<BR>MP消耗：" + finiteValue(skill.消耗mp);
                if (finiteValue(skill.消耗hp) > 0) intro += "<BR>生命消耗：" + finiteValue(skill.消耗hp);
                if (finiteValue(skill.消耗sp) > 0) intro += "<BR>技能点消耗：" + finiteValue(skill.消耗sp);
                if (text(skill.描述) != "") intro += "<BR>" + text(skill.描述);
                if (text(skill.信息) != "") intro += "<BR>" + text(skill.信息);
                NativeTooltipBridge.show(NativeTooltipDocument.buildBody(intro, "dense"), null, "top", anchor);
            }
        } else if (p.kind == "switch") {
            var hint:String = "<B>药剂组 " + (current.bank == 0 ? "I" : "II") + "</B><BR>点击或按 " + current.switchKey + " 切换另一组药剂。";
            hint += "<BR>同一列共用冷却，换组不会重置冷却。";
            NativeTooltipBridge.show(NativeTooltipDocument.buildBody(hint, "simple"), null, "top", anchor);
        } else if (p.kind == "resources") {
            var v:Object = readVitals(hero());
            var lines:String = "生命：" + Math.floor(v.hp[0]) + " / " + Math.floor(v.hp[1]) + "（" + percentage(v.hp[0], v.hp[1]) + "）";
            lines += "<BR>护盾：" + (!v.shieldReady ? "未就绪" : v.shieldPresent ? Math.floor(v.shield[0]) + " / " + Math.floor(v.shield[1]) : "无护盾");
            lines += "<BR>MP：" + Math.floor(v.mp[0]) + " / " + Math.floor(v.mp[1]) + "（" + percentage(v.mp[0], v.mp[1]) + "）";
            lines += "<BR>韧性：" + Math.floor(v.poise * 100) + "%<BR>经验：" + Math.floor(v.experience[0]) + " / " + Math.floor(v.experience[2]);
            lines += "<BR>技能点：" + Math.floor(v.sp);
            NativeTooltipBridge.show(NativeTooltipDocument.buildBody(lines, "dense"), null, "top", anchor);
        }
        hoverRequest = NativeTooltipBridge.activeRequestId();
    }
    private static function hideTooltip():Void {
        if (hoverRequest != null) NativeTooltipBridge.hide(hoverRequest);
        hoverRequest = null;
        hoverId = "";
    }
    /** Focused TestLoader probes; never called from production. */
    public static function testOnlyReadVitals(unit:Object):Object { return readVitals(unit); }
    public static function testOnlyPoise(unit:Object):Object { return readPoiseDetail(unit); }
    public static function testOnlyConfigure(p:Object):Void { configureProjection(p); }
    public static function testOnlySameProjection(previous, current):Boolean { return sameProjection(previous, current); }
    public static function testOnlyContext(unit:Object):Number {
        if (compat == null) compat = createCompatibility();
        if (buffProjection == null) buffProjection = new PlayerHudBuffProjection();
        ensureContext(unit); return epoch;
    }
    public static function testOnlyWire(unit:Object):String {
        if (compat == null) compat = createCompatibility();
        return Base64.encodeDisplay(json().stringifySafe({v:1, epoch:1, seq:1, full:true, visible:true,
            groups:{vitals:readVitals(unit), combat:readCombat(unit), loadout:readLoadout(),
                cooldowns:readCooldowns(), buffs:[]}}));
    }

    private static function setAmmo(index:Number, value):Void {
        storeAmmo(hero(), index, value);
    }
    private static function storeAmmo(unit:Object, index:Number, value):Void {
        if (ensureContext(unit)) { synchronizeAmmoOwners(unit); ammo[index] = value; }
    }
    public static function testOnlyCombat(unit:Object):Object { ensureContext(unit); return readCombat(unit); }
    public static function testOnlyAmmo(unit:Object, index:Number, value):Void { storeAmmo(unit, index, value); }
    public static function testOnlyRawAmmo(index:Number) { return ammo[index]; }
    private static function ammoGetter(index:Number):Function { return function() { return ammo[index]; }; }
    private static function ammoSetter(index:Number):Function { return function(value):Void { PlayerHudService.setAmmo(index, value); }; }
    private static function noRender():Void { }
    private static function createCompatibility():Object {
        var info:Object = {mode:"", 战技栏:{战技栏图标刷新:noRender}, 战技控制器:{}};
        var fields:Array = ["子弹数", "弹夹数", "子弹数_2", "弹夹数_2"];
        for (var i:Number = 0; i < fields.length; i++) info.addProperty(fields[i], ammoGetter(i), ammoSetter(i));
        info.gotoAndStop = function(mode:String):Void { this.mode = mode; };
        info.刷新 = info.gotoAndStop;
        var value:Object = {玩家必要信息界面:info, 刷新hp显示:noRender, 刷新mp显示:noRender,
            刷新经验值显示:noRender, 刷新技能等级显示:noRender, 刷新韧性显示:noRender};
        value.刷新攻击模式 = function(mode:String):Void { this.玩家必要信息界面.mode = mode; };
        return value;
    }
}
