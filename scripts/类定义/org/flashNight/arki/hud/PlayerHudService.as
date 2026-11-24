import org.flashNight.arki.hud.PlayerHudUnitHotWire;
import org.flashNight.arki.hud.PlayerHudAllyRoster;
import org.flashNight.arki.hud.WeaponAmmoHudProjection;
import org.flashNight.arki.hud.PlayerHudBuffProjection;
import org.flashNight.arki.hud.FocusTargetHudService;
import org.flashNight.arki.hud.PlayerHudShieldProjection;
import org.flashNight.arki.unit.UnitComponent.Targetcache.TargetCacheManager;
import org.flashNight.arki.unit.Action.Input.EnemyActionRuntime;
import org.flashNight.arki.unit.Action.Skill.ManualCooldownService;
import org.flashNight.arki.unit.Action.Skill.DrugInputService;
import org.flashNight.arki.unit.Action.Shoot.LongGunSubWeaponCore;
import org.flashNight.arki.skill.SkillLoadoutService;
import org.flashNight.arki.skill.SkillResourceService;
import org.flashNight.arki.item.ItemUtil;
import org.flashNight.arki.item.DrugHudMutationService;
import org.flashNight.arki.render.FrameBroadcaster;
import org.flashNight.arki.scene.StageReturnFlow;
import org.flashNight.arki.interaction.NativeInteractionContext;
import org.flashNight.gesh.tooltip.NativeTooltipBridge;
import org.flashNight.gesh.tooltip.TooltipInputProjection;
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
    private static var shieldDetailsEnabled:Boolean = false;
    private static var poiseVisualsEnabled:Boolean = false;
    private static var resourceHintsEnabled:Boolean = false;
    private static var weaponVisualsEnabled:Boolean = false;
    private static var deckDetailsEnabled:Boolean = false;
    private static var ammoDetailsEnabled:Boolean = false;
    private static var coldSkillsEnabled:Boolean = false;
    private static var allyRosterEnabled:Boolean = false;
    private static var unitHotEnabled:Boolean = false;
    private static var focusTargetEnabled:Boolean = false;
    private static var focusTargetsEnabled:Boolean = false;
    private static var focusUnitInfoEnabled:Boolean = false;
    private static var focusTargetCapacity:Number = 4;
    private static var buffDetailsEnabled:Boolean = false;
    private static var lastFull:Number = 0;
    private static var lastProjectionError:Number = -10000;
    private static var profileEnabled:Boolean = false;
    private static var profileId:String = "";
    private static var profileSamples:Array = [];
    // Only allocated while profiling. Phases: context, loadout, vitals, combat,
    // cooldowns, buffs, coldSkills, focus, resources, JSON, Base64, handoff.
    private static var profileKind:Number;
    private static var profileMarks:Array;
    private static var profileDurations:Array;
    private static var profileTotals:Array;
    private static var profileSlow:Array;
    private static var profileTickStart:Number;
    private static var profileStart:Number = 0;
    private static var profilePackets:Number = 0;
    private static var profileBytes:Number = 0;
    private static var rosterTrace:Boolean = false;
    private static var rosterBatch:Object;
    private static var traceVitals:Object;
    private static var traceAllies:Object;
    private static var profileHotPackets:Number = 0;
    private static var profileHotBytes:Number = 0;
    private static var profileJsonUnitPackets:Number = 0;
    private static var profileWireReasons:Object = {};
    private static var tickCount:Number = 0;
    private static var rawGroups:Object = {};
    private static var cooldownKeys:Array;
    private static var cooldownValues:Array = [];
    private static var lastManualCooldownRevision:Number = -1;
    private static var manualCooldownSnapshot:Array;
    private static var wireGroups:Object = {};
    private static var wireComma:Object;

    private static var loadout:Object;
    private static var lastFrameSkills:Object;
    private static var lastDrugSource:Object;
    private static var lastDrugVersion:Number;
    private static var drugNames:Array = [];
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
        FocusTargetHudService.install();
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
        if (profileEnabled) { profileKind = 0; profileTickStart = started; profileMarks = []; }
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
        flushRosterTrace();
        profileEnabled = p.enabled; profileId = p.profileId;
        rosterTrace = p.enabled && p.rosterReplay === true;
        resetDetailProfile();
        profileSamples = []; profileStart = getTimer(); profilePackets = profileBytes = 0;
    }
    private static function flushRosterTrace():Void {
        if (rosterBatch != null && rosterBatch.samples.length > 0)
            _root.server.sendServerMessage("[RosterReplay] " + json().stringifySafe(rosterBatch));
        rosterBatch = null; traceVitals = null; traceAllies = null;
    }
    // Opt-in diagnostic only. Reuse the immutable projection already produced by tick().
    private static function recordRosterTrace():Void {
        var stage:String = text(_root.当前关卡名);
        if (rosterBatch != null && (rosterBatch.epoch != epoch || rosterBatch.stage != stage)) flushRosterTrace();
        if (stage.length == 0 || rawGroups.vitals == null) return;
        if (rosterBatch == null) rosterBatch = {stage:stage,epoch:epoch,vitals:[],allies:[],samples:[],sourceHp:[],mode:PlayerHudAllyRoster.currentMode()};
        if (rawGroups.vitals !== traceVitals) {traceVitals=rawGroups.vitals; rosterBatch.vitals.push(traceVitals);}
        if (rawGroups.allies != null && rawGroups.allies !== traceAllies) {
            traceAllies=rawGroups.allies;
            var slim:Array=[], r:Object, a:Array;
            for(var group:Number=0;group<2;group++) {
                a=group==0?traceAllies.rows:traceAllies.overflow;
                for(var i:Number=0;i<a.length;i++) {
                    r=a[i];slim.push([r.slot,r.id,r.generation,r.role,r.name,r.hp[0],r.hp[1],r.shield[0],r.shield[1],r.down,r["protected"]]);
                }
            }
            rosterBatch.allies.push(slim);
        }
        var frame:Number=Number(_root.帧计时器.当前帧数);
        var sourceUtc:Number = (new Date()).getTime();
        var live:Array = PlayerHudAllyRoster.observeHp();
        var source:Array = rosterBatch.sourceHp;
        var prior:Array = source.length ? source[source.length-1] : null;
        var changed:Boolean = prior == null || live.length != prior.length;
        for (var j:Number=0; !changed && j<live.length; j++)
            for (var c:Number=0; c<5; c++) if (live[j][c] !== prior[j][c]) {changed=true;break;}
        if (changed) source.push(live);
        rosterBatch.samples.push([tickCount,isFinite(frame)?frame:-1,getTimer(),rosterBatch.vitals.length-1,rosterBatch.allies.length-1,source.length-1,PlayerHudAllyRoster.sampled,sourceUtc]);
        if (rosterBatch.samples.length >= 30 || rosterBatch.allies.length>=5 || source.length>=5) flushRosterTrace();
    }
    private static function resetDetailProfile():Void {
        profileHotPackets = profileHotBytes = profileJsonUnitPackets = 0;
        profileWireReasons = {};
        profileDurations = [[], [], []]; profileTotals = [[], [], []]; profileSlow = [];
    }
    private static function recordProfile(elapsed:Number):Void {
        var times:Array = profileMarks;
        var sums:Array = profileTotals[profileKind];
        var previous:Number = profileTickStart;
        for (var phase:Number = 0; phase < times.length; phase++) {
            var end:Number = times[phase];
            times[phase] = end - previous;
            sums[phase] = (sums[phase] || 0) + times[phase];
            previous = end;
        }
        profileDurations[profileKind].push(elapsed);
        if (elapsed >= 50 && profileSlow.length < 24)
            profileSlow.push([profileSamples.length, profileKind, elapsed, times]);

        profileSamples.push(Math.max(0, elapsed));
        if (profileSamples.length < 300) return;
        profileSamples.sort(Array.NUMERIC);
        var total:Number = 0;
        for (var i:Number = 0; i < profileSamples.length; i++) total += profileSamples[i];
        _root.server.sendServerMessage("[PlayerHudPerf] " + json().stringifySafe({id:profileId, source:"as2",
            samples:300, windowMs:getTimer()-profileStart, meanMs:total/300, p50Ms:profileSamples[149],
            p95Ms:profileSamples[284], maxMs:profileSamples[299], packets:profilePackets, encodedBytes:profileBytes,
            unitHotV1:unitHotEnabled, hotPackets:profileHotPackets, hotBytes:profileHotBytes, jsonUnitPackets:profileJsonUnitPackets, wireReasons:profileWireReasons}));
        var summary:Array = [];
        for (var kind:Number = 0; kind < 3; kind++) {
            var data:Array = profileDurations[kind];
            data.sort(Array.NUMERIC);
            var n:Number = data.length;
            var sum:Number = 0;
            for (var j:Number = 0; j < n; j++) sum += data[j];
            summary.push(n ? [n,sum,data[Math.ceil(n*.5)-1],data[Math.ceil(n*.95)-1],data[Math.ceil(n*.99)-1],data[n-1]] : [0]);
        }
        _root.server.sendServerMessage("[PlayerHudCaptureDetail] " + json().stringifySafe({
            id:profileId, lastTick:tickCount, byKind:summary, phaseTotals:profileTotals, slow:profileSlow}));
        resetDetailProfile();
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
        wireGroups = {};
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
        if (rosterTrace) flushRosterTrace();
        hideTooltip();
        if (buffProjection != null) buffProjection.deinitialize();
        worldToken = undefined;
        actorId = 0;
        loadout = null;
        rawGroups = {};
        wireGroups = {};
        ammo = ["", "", "", ""]; ammoMode = "";
        primaryOwner = secondaryOwner = null; lastCombat = null;
        forceFull = true;
        epoch++;
        FrameBroadcaster.setPlayerHudPayload(null);
        if (_root.server.isSocketConnected === true && !org.flashNight.arki.render.WorkerProjectionPolicy.isNone("playerHud"))
            sendImmediate({v:1, epoch:epoch, seq:++sequence, full:true, visible:false});
        wasVisible = false;
    }
    private static function configureProjection(p:Object):Void {
        // Older isolated candidates keep their exact v1 field set until they opt in.
        if (p.poiseDetails === true) poiseDetailsEnabled = true;
        if (p.shieldDetails === true) shieldDetailsEnabled = true;
        if (p.poiseVisuals === true) poiseVisualsEnabled = true;
        if (p.resourceHints === true) resourceHintsEnabled = true;
        if (p.weaponVisuals === true) weaponVisualsEnabled = true;
        if (p.deckDetails === true) { deckDetailsEnabled = true; buffProjection.setDeckDetails(true); }
        if (p.ammoDetails === true) ammoDetailsEnabled = true;
        // 冷兵器主动技能冷却面板（原生 C# 绘制）。只有认识这个组的 Launcher
        // 才会在 playerHudSync 里索取；老 Launcher 不索取、本端也不发，
        // 避免旧解析器的白名单 Keys() 因未知组名整包拒收。
        if (p.coldSkills === true) coldSkillsEnabled = true;
        if (p.allyRoster === true) { allyRosterEnabled = true; PlayerHudAllyRoster.configure(p.allySampling); }
        if (p.unitHotV1 === true) unitHotEnabled = true;
        if (p.focusTarget === true) focusTargetEnabled = true;
        if (p.focusTargets === true) {
            focusTargetsEnabled = true;
            focusTargetCapacity = p.focusTargetCapacity === 8 ? 8 : 4;
        }
        if (p.focusUnitInfo === true) focusUnitInfoEnabled = true;
        if (p.buffDetails === true) { buffDetailsEnabled = true; buffProjection.setDetailsEnabled(true); }
        forceFull = true;
    }
    public static function tick():Void {
        if (org.flashNight.arki.render.WorkerProjectionPolicy.isNone("playerHud")) return;
        var online:Boolean = _root.server.isSocketConnected === true;
        if (!online) { connected = false; deckDetailsEnabled = false; buffProjection.setDeckDetails(false); allyRosterEnabled = false; unitHotEnabled = false; weaponVisualsEnabled = false; ammoDetailsEnabled = false; resourceHintsEnabled = false; poiseDetailsEnabled = false; shieldDetailsEnabled = false; poiseVisualsEnabled = false; coldSkillsEnabled = false; focusTargetEnabled = false; focusTargetsEnabled = false; focusUnitInfoEnabled = false; focusTargetCapacity = 4; buffDetailsEnabled = false; buffProjection.setDetailsEnabled(false); forceFull = true; FrameBroadcaster.setPlayerHudPayload(null); return; }
        if (!connected) { connected = true; forceFull = true; }
        var unit:Object = hero();
        // 热路径只观察外层屏障；重算仍由领域冷路及显式读取负责。
        if(unit.__playerStatInitializing===true || unit.__playerStatProjectionBlocked===true) {
            if(wasVisible || forceFull) {clear();forceFull=false;}return;
        }
        if (!ensureContext(unit) || typeof _root.gameworld != "movieclip") {
            if (wasVisible || forceFull) { clear(); forceFull = false; }
            return;
        }
        buffProjection.initialize(unit.buffManager);
        _root.UI系统.iconBar = buffProjection;
        tickCount++;
        var full:Boolean = forceFull || FrameBroadcaster.hasPlayerHudPending() || getTimer() - lastFull > 2000;
        if (profileEnabled) profileMarks[0] = getTimer();
        refreshFrameLoadout(unit, full, tickCount % 3);
        if (profileEnabled) profileMarks[1] = getTimer();
        var groups:Object = {};
        var count:Number = 0;
        if (addGroup(groups, "vitals", readVitals(unit), full)) count++;
        if (profileEnabled) profileMarks[2] = getTimer();
        if (addGroup(groups, "combat", readCombat(unit), full)) count++;
        if (addGroup(groups, "loadout", loadout, full)) count++;
        if (profileEnabled) profileMarks[3] = getTimer();
        if (addGroup(groups, "cooldowns", readCooldowns(), full)) count++;
        if (profileEnabled) profileMarks[4] = getTimer();
        if (addGroup(groups, "buffs", buffProjection.snapshotFor(unit), full)) count++;
        if (profileEnabled) profileMarks[5] = getTimer();
        if (coldSkillsEnabled && addGroup(groups, "coldSkills", readColdSkills(unit), full)) count++;
        if (profileEnabled) profileMarks[6] = getTimer();
        var oldFocus = rawGroups.focusTarget;
        var oldAllies = rawGroups.allies;
        var focusRows = focusTargetsEnabled ? FocusTargetHudService.snapshotList(unit, focusTargetCapacity, focusUnitInfoEnabled)
            : (focusTargetEnabled ? FocusTargetHudService.snapshot() : null);
        if ((focusTargetsEnabled || focusTargetEnabled) && addGroup(groups, "focusTarget", focusRows, full)) count++;
        if (allyRosterEnabled && addGroup(groups, "allies", PlayerHudAllyRoster.snapshotAt(unit,focusRows,Number(_root.帧计时器.当前帧数),getTimer(),_root.暂停===true,forceFull), full)) count++;
        if (profileEnabled) profileMarks[7] = getTimer();
        if (resourceHintsEnabled && addGroup(groups, "resources", SkillResourceService.snapshot(unit, loadout, rawGroups.resources), full)) count++;
        if (profileEnabled) profileMarks[8] = getTimer();
        compat._pendingHpDisplayRefresh = false;
        if (profileEnabled && rosterTrace) recordRosterTrace();
        if (count == 0) return;
        var packet:Object = {v:1, epoch:epoch, seq:++sequence, full:full, visible:true, groups:groups};
        if (profileEnabled) profileKind = full ? 2 : 1;
        var wire:String = encodeFrame(packet, count, oldFocus, oldAllies);
        if (wire == null) { clear(); return; }
        if (_root.暂停 === true) {
            FrameBroadcaster.setPlayerHudPayload(null);
            _root.server.sendSocketMessage("U" + wire);
        } else FrameBroadcaster.setPlayerHudPayload(wire);
        if (full) lastFull = getTimer();
        forceFull = false;
        wasVisible = true;
        if (profileEnabled) profileMarks[11] = getTimer();
    }
    private static function encodeFrame(packet:Object, count:Number, oldFocus, oldAllies):String {
        var groups:Object = packet.groups;
        var hasFocus:Boolean = groups.hasOwnProperty("focusTarget");
        var hasAllies:Boolean = groups.hasOwnProperty("allies");
        var units:Number = Number(hasFocus) + Number(hasAllies);
        var head:String = null, tail:String = null;
        if (!packet.full && unitHotEnabled && units > 0) {
            if (count == units) {
                head = PlayerHudUnitHotWire.encode(epoch, sequence, groups, oldFocus, oldAllies);
            } else {
                tail = PlayerHudUnitHotWire.encodeUnitsOnly(epoch, sequence + 1, groups.focusTarget,
                    hasFocus, groups.allies, hasAllies, oldFocus, oldAllies);
                if (tail != null) {
                    // Only the transient outgoing map changes. rawGroups owns the complete snapshots.
                    delete groups.focusTarget;
                    delete groups.allies;
                }
            }
        }
        if (head == null) head = encodeHudPacket(packet);
        else if (profileEnabled) profileMarks[9] = profileMarks[10] = getTimer();
        var wire:String = "pi:" + head;
        if (tail != null) wire += "|pi:" + tail;
        if (tail != null ? length(wire) > 131072 : length(head) > 131072) return null;
        if (tail != null) sequence++;
        if (profileEnabled) {
            profilePackets++; profileBytes += length(head);
            var why:String;
            if (tail != null) {
                profilePackets++; profileBytes += length(tail);
                profileHotPackets++; profileHotBytes += length(tail);
                why = "mixedHot";
            } else if (head.charAt(0) == "~") {
                profileHotPackets++; profileHotBytes += length(head);
                why = "hot";
            } else {
                if (!packet.full && units > 0) profileJsonUnitPackets++;
                why = packet.full ? "full" : PlayerHudUnitHotWire.fallbackReason(groups, oldFocus, oldAllies);
            }
            profileWireReasons[why] = (profileWireReasons[why] || 0) + 1;
        }
        return wire;
    }
    private static function encodeHudPacket(packet:Object):String {
        var groups:Object = packet.groups;
        // Let the existing codec emit the envelope in its normal member order.
        // Only its groups:null placeholder is expanded with cached UTF-8 fragments.
        packet.groups = null;
        var header:String = json().stringifySafe(packet);
        packet.groups = groups;
        var marker:String = '"groups":null';
        var at:Number = header.indexOf(marker) + marker.length - 4;
        var prefix:String = header.substr(0,at) + "{";
        var suffix:String = "}" + header.substr(at+4);
        var parts:Array = [];
        var row:Object;
        for (var key:String in groups) {
            if (!groups.hasOwnProperty(key)) continue;
            row = wireGroups[key];
            // A different but deeply equal object can have a different AVM1
            // enumeration order. Re-encode it to preserve exact legacy wire bytes.
            if (row == null || row.value !== groups[key]) {
                // Only HUD-owned literal group names are inserted in the envelope.
                row = {value:groups[key], text:'"' + key + '":' + json().stringifySafe(groups[key])};
                wireGroups[key] = row;
            }
            parts.push(row);
        }
        if (profileEnabled) profileMarks[9] = getTimer();
        if (wireComma == null) wireComma = Base64.displayPart(",");
        var output:Array = [], carry:Array = [];
        Base64.appendDisplayPart(output,carry,Base64.displayPart(prefix));
        for (var i:Number = 0; i < parts.length; i++) {
            row = parts[i];
            if (i > 0) Base64.appendDisplayPart(output,carry,wireComma);
            if (row.part == null) { row.part = Base64.displayPart(row.text); delete row.text; }
            Base64.appendDisplayPart(output,carry,row.part);
        }
        Base64.appendDisplayPart(output,carry,Base64.displayPart(suffix));
        if (carry.length) output.push(Base64.encodeBytes(carry));
        var encoded:String = output.join("");
        if (profileEnabled) profileMarks[10] = getTimer();
        return encoded;
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
    private static function text(value):String { return value == null ? "" : String(value); }
    /** 资源展示的纯读入口；不安装 HUD 动作、帧监听或持久写服务。 */
    public static function readVitalsSnapshot(unit:Object):Object { return readVitals(unit); }
    private static function readVitals(unit:Object):Object {
        var previous:Object = rawGroups.vitals;
        var shield:Object = unit.shield;
        var shieldReady:Boolean = typeof shield.getMaxCapacity == "function";
        var shieldCapacity:Number = shieldReady ? Number(shield.getCapacity()) : 0;
        var shieldMaximum:Number = shieldReady ? Number(shield.getMaxCapacity()) : 0;
        if (!isFinite(shieldCapacity) || !isFinite(shieldMaximum)) shieldReady = false;
        var shieldPresent:Boolean = shieldReady && shieldMaximum > 0;
        // Preserve the old AVM1 read order, including right-to-left array values.
        // Property accessors may refresh derived state: the second shield sample
        // must stay after HP/MP reads, even when the first readiness read was valid.
        var hpMax:Number = finiteValue(unit.hp满血值), hp:Number = finiteValue(unit.hp);
        var mpMax:Number = finiteValue(unit.mp满血值), mp:Number = finiteValue(unit.mp);
        shieldMaximum = shieldPresent ? finiteValue(shield.getMaxCapacity()) : 0;
        shieldCapacity = shieldPresent ? finiteValue(shield.getCapacity()) : 0;
        var poise:Number = finiteValue(unit.nonlinearMappingResilience);
        var experienceEnd:Number = finiteValue(_root.升级需要经验值);
        var experienceStart:Number = finiteValue(_root.上次升级需要经验值);
        var experience:Number = finiteValue(_root.经验值);
        var level:Number = finiteValue(_root.等级), name:String = text(_root.角色名), sp:Number = finiteValue(_root.技能点数);
        var paused:Boolean = !!_root.暂停, decorations:Boolean = _root.__nativeHudDecorations !== false;
        var poiseDetail:Object;
        var poiseVisual:Object;
        var shieldDetail:Object;
        if (poiseDetailsEnabled) poiseDetail = readPoiseDetail(unit, previous.poiseDetail);
        if (poiseVisualsEnabled) {
            var airborne:Boolean = !!unit.浮空, rigid:Boolean = !!(unit.刚体 || unit.man.刚体标签), down:Boolean = !!unit.倒地;
            var oldVisual:Object = previous.poiseVisual;
            poiseVisual = oldVisual != null && oldVisual.airborne === airborne && oldVisual.rigid === rigid && oldVisual.down === down
                ? oldVisual : {airborne:airborne, rigid:rigid, down:down};
        }
        if (shieldDetailsEnabled) {
            shieldDetail = PlayerHudShieldProjection.read(unit);
            if (sameProjection(previous.shieldDetail, shieldDetail)) shieldDetail = previous.shieldDetail;
        }
        // Compare normalized live facts before allocating arrays. Every returned DTO
        // remains detached; no scratch array ever aliases an already-sent snapshot.
        if (previous != null && previous.hp[0] === hp && previous.hp[1] === hpMax
                && previous.mp[0] === mp && previous.mp[1] === mpMax
                && previous.shield[0] === shieldCapacity && previous.shield[1] === shieldMaximum
                && previous.shieldPresent === shieldPresent && previous.shieldReady === shieldReady && previous.poise === poise
                && previous.experience[0] === experience && previous.experience[1] === experienceStart && previous.experience[2] === experienceEnd
                && previous.level === level && previous.name === name && previous.sp === sp
                && previous.paused === paused && previous.decorations === decorations
                && previous.poiseDetail === poiseDetail && previous.poiseVisual === poiseVisual && previous.shieldDetail === shieldDetail) return previous;
        var result:Object = {hp:[hp, hpMax], mp:[mp, mpMax], shield:[shieldCapacity, shieldMaximum],
            shieldPresent:shieldPresent, shieldReady:shieldReady, poise:poise,
            experience:[experience, experienceStart, experienceEnd], level:level, name:name, sp:sp, paused:paused, decorations:decorations};
        if (poiseDetailsEnabled) result.poiseDetail = poiseDetail;
        if (poiseVisualsEnabled) result.poiseVisual = poiseVisual;
        if (shieldDetailsEnabled) result.shieldDetail = shieldDetail;
        return result;
    }
    private static function readPoiseDetail(unit:Object, previous:Object):Object {
        // Consume ImpactHandler's authoritative derived values. Never refresh gameplay
        // attributes, advance decay, or infer a threshold from the rounded HUD percent.
        var cap:Number = Number(unit.韧性上限);
        var boundary:Number = Number(unit.impactStaggerBoundary);
        var impact:Number = Number(unit.remainingImpactForce);
        var threshold:Number = 0, hasStaggerBand:Boolean = false, phase:String = "unavailable";
        if (cap > 0 && isFinite(cap) && isFinite(boundary) && !(boundary < 0) && isFinite(impact) && !(impact < 0)) {
            threshold = Math.max(0, Math.min(1, 1 - Math.sqrt(boundary / cap)));
            hasStaggerBand = boundary < cap;
            phase = unit.浮空 ? "air" : unit.倒地 ? "down" :
                (unit.刚体 || unit.man.刚体标签) ? "rigid" : impact > cap ? "break" : impact > boundary ? "stagger" : "buffer";
        }
        if (previous != null && previous.threshold === threshold && previous.hasStaggerBand === hasStaggerBand && previous.phase === phase) return previous;
        return {threshold:threshold, hasStaggerBand:hasStaggerBand, phase:phase};
    }
    private static function readCombat(unit:Object):Object {
        var mode:String = text(unit.攻击模式);
        var skill:Object = unit.主动战技[unit.攻击模式];
        // 同一特殊槽按装备阶段切换时，就绪的普通战技仍需显示 F 与冷却。
        if (mode == "长枪" && LongGunSubWeaponCore.hasSubweapon(unit)
                && (skill == null || skill.isSubweaponControl === true)) mode = "长枪副武器";
        var valid:Boolean = false;
        for (var i:Number = 0; i < modes.length; i++) if (modes[i] == mode) valid = true;
        if (!valid) return lastCombat != null ? lastCombat : {mode:"", ammo:["", "", "", ""],
            weapon:{visible:false, name:"", mp:0, cooldownMs:0, key:keyLabel("武器技能键")}};
        compat.玩家必要信息界面.mode = mode;
        synchronizeAmmoOwners(unit);
        var secondMagazine:String = text(ammo[3]), secondAmmo:String = text(ammo[2]);
        var firstMagazine:String = text(ammo[1]), firstAmmo:String = text(ammo[0]);
        var oldDetails:Array = lastCombat.ammoDetails;
        var primaryDetail:Object = null;
        var secondaryDetail:Object = null;
        if (ammoDetailsEnabled) {
            var primarySlot:String = mode == "双枪" ? "手枪" : (mode == "长枪副武器" ? "长枪" : mode);
            var secondarySlot:String = mode == "双枪" ? "手枪2" : (mode == "长枪副武器" ? "长枪副武器" : "");
            primaryDetail = WeaponAmmoHudProjection.read(unit, primarySlot, oldDetails[0]);
            if (secondarySlot != "") secondaryDetail = WeaponAmmoHudProjection.read(unit, secondarySlot, oldDetails[1]);
            if (primaryDetail != null && unit[primarySlot].value.ammoState.v == 1) {
                var primaryData:Object = unit[primarySlot + "属性"];
                firstAmmo = text(primaryDetail.loaded * (org.flashNight.arki.bullet.BulletComponent.Type.BulletTypeUtil.isVertical(primaryData.bullet) ? primaryData.split : 1));
            }
            if (secondaryDetail != null && secondarySlot == "手枪2" && unit.手枪2.value.ammoState.v == 1) {
                var secondaryData:Object = unit.手枪2属性;
                secondAmmo = text(secondaryDetail.loaded * (org.flashNight.arki.bullet.BulletComponent.Type.BulletTypeUtil.isVertical(secondaryData.bullet) ? secondaryData.split : 1));
            }
        }
        var visible:Boolean = skill != null && skill.isSubweaponControl !== true;
        var name:String = weaponName(skill), mp:Number = finiteValue(skill.消耗mp);
        var cooldownMs:Number = finiteValue(skill.冷却时间), key:String = keyLabel("武器技能键");
        var iconKey:String = "", itemIconKey:String = "", sourceItem:String = "";
        if (weaponVisualsEnabled && visible) {
            iconKey = text(skill.iconKey);
            sourceItem = text(skill.装备来源);
            if (sourceItem == "") {
                var sourceSlot:String = mode == "兵器" ? "刀" : (mode == "空手" ? "手部装备" : mode);
                var equipment = unit[sourceSlot];
                sourceItem = typeof equipment == "string" ? text(equipment) : text(equipment.name);
            }
            var sourceData:Object = sourceItem == "" ? null : ItemUtil.getRawItemData(sourceItem);
            itemIconKey = text(sourceData.icon);
        }
        var deck:Object = deckDetailsEnabled ? readDeck(unit, mode, lastCombat.deck) : null;
        var oldWeapon:Object = lastCombat.weapon;
        if (lastCombat != null && (deckDetailsEnabled ? deck === lastCombat.deck : lastCombat.deck == undefined) && lastCombat.mode === mode && lastCombat.ammo[0] === firstAmmo
                && lastCombat.ammo[1] === firstMagazine && lastCombat.ammo[2] === secondAmmo && lastCombat.ammo[3] === secondMagazine
                && (ammoDetailsEnabled ? (oldDetails != null && oldDetails[0] === primaryDetail && oldDetails[1] === secondaryDetail)
                    : oldDetails == undefined)
                && oldWeapon.visible === visible && oldWeapon.name === name && oldWeapon.mp === mp
                && oldWeapon.cooldownMs === cooldownMs && oldWeapon.key === key
                && (weaponVisualsEnabled ? (oldWeapon.iconKey === iconKey && oldWeapon.itemIconKey === itemIconKey
                    && oldWeapon.sourceItem === sourceItem) : oldWeapon.iconKey == undefined)) return lastCombat;
        lastCombat = {mode:mode, ammo:[firstAmmo, firstMagazine, secondAmmo, secondMagazine],
            weapon:{visible:visible, name:name, mp:mp, cooldownMs:cooldownMs, key:key}};
        if (deck != null) lastCombat.deck = deck;
        if (ammoDetailsEnabled) lastCombat.ammoDetails = [primaryDetail, secondaryDetail];
        if (weaponVisualsEnabled) {
            lastCombat.weapon.iconKey = iconKey;
            lastCombat.weapon.itemIconKey = itemIconKey;
            lastCombat.weapon.sourceItem = sourceItem;
        }
        return lastCombat;
    }
    private static function readDeck(unit:Object, mode:String, previous:Object):Object {
        var current:Number = Number(unit.淬毒);
        if (!isFinite(current) || current < 0) current = 0;
        var application:Object = unit.__hudCoatingInitial;
        var initial:Number = 0;
        if (application != null) {
            if (current <= 0 || current > application.last) delete unit.__hudCoatingInitial;
            else { initial = application.value; application.last = current; }
        }
        var slot:String = mode == "空手" ? "手部装备" : (mode == "兵器" ? "刀" : (mode == "手雷" ? "手雷" : ""));
        var equipped = unit[slot];
        var name:String = slot == "" ? "" : (typeof equipped == "string" ? text(equipped) : text(equipped.name));
        var power:Number = -1;
        if (mode == "空手") power = org.flashNight.arki.unit.PlayerInfoProvider.getUnarmedPower(MovieClip(unit));
        if (mode == "兵器") power = org.flashNight.arki.unit.PlayerInfoProvider.getMeleePower(MovieClip(unit));
        if (mode == "手雷") power = org.flashNight.arki.unit.PlayerInfoProvider.getGrenadePower(MovieClip(unit));
        if (!isFinite(power) || power < 0) power = -1;
        if (previous != null && previous.points === current && previous.initial === initial
            && previous.equipment === name && previous.power === power) return previous;
        return {points:current, initial:initial, equipment:name, power:power};
    }
    private static function synchronizeAmmoOwners(unit:Object):Void {
        var mode:String = text(unit.攻击模式);
        var primary:Object = mode == "双枪" ? unit.手枪 : unit[mode];
        var secondary:Object = mode == "双枪" ? unit.手枪2 : (mode == "长枪" ? unit.长枪副武器状态 : null);
        if (mode != ammoMode || primary !== primaryOwner) {
            ammo[0] = ammo[1] = ammo[2] = ammo[3] = "";
            if (mode == "手雷" && primary != null && _root.物品栏 != null && _root.物品栏.装备栏 != null) {
                var grenadeCount = _root.物品栏.装备栏.getValue("手雷");
                if (grenadeCount != undefined) ammo[1] = grenadeCount;
            }
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
    private static function refreshFrameLoadout(unit:Object, full:Boolean, phase:Number):Void {
        var skills:Object;
        var nativeSkills:Boolean = unit.__enemyActionRuntime.enabled === true;
        if (!nativeSkills) skills = full ? SkillLoadoutService.getHudDescriptors() :
            SkillLoadoutService.getHudDescriptorsForFrame(phase);
        var source:Object = _root.物品栏.药剂栏;
        var version:Number = source.getMutationRevision == undefined ? -1 : source.getMutationRevision();
        var bank:Number = DrugInputService.getActiveBank();
        if (full || loadout == null || lastFrameSkills !== skills || lastDrugSource !== source ||
                lastDrugVersion !== version || loadout.drugRevision !== drugRevision || loadout.bank !== bank ||
                (nativeSkills && phase == 0) || !drugSliceMatches(source, bank, phase)) {
            loadout = readLoadout(unit, skills);
            lastFrameSkills = skills;
            lastDrugSource = source;
            lastDrugVersion = version;
        }
    }

    // Some legacy scripts edit item objects, display metadata or bindings in place.
    // Check the eight physical slots within the original three capture interval.
    private static function drugSliceMatches(source:Object, bank:Number, phase:Number):Boolean {
        var end:Number = phase == 2 ? 8 : phase * 3 + 3;
        for (var i:Number = phase * 3; i < end; i++) {
            var item:Object = source.getItem(String(i));
            if (item !== drugItems[i] || text(item.name) !== drugNames[i] ||
                    (item == null ? 0 : finiteValue(item.value)) !== drugCounts[i]) return false;
            var lane:Number = i - bank * 4;
            if (lane < 0 || lane > 3) continue;
            var row:Object = loadout.drugs[lane];
            var icon:String = item == null ? "" : text(ItemUtil.getRawItemData(item.name).icon);
            if (row.icon !== icon || row.key !== keyLabel(DrugInputService.getKeyName(lane))) return false;
        }
        return phase != 0 || loadout.switchKey === keyLabel(DrugInputService.getSwitchKeyName());
    }

    private static function readLoadout(nativeUnit:Object, skills:Object):Object {
        if (nativeUnit == null) nativeUnit = hero();
        if (skills == null) skills = nativeUnit.__enemyActionRuntime.enabled === true
            ? EnemyActionRuntime.hudDescriptors(nativeUnit) : SkillLoadoutService.getHudDescriptors();
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
            drugNames[i] = text(item.name);
            signature += ";" + drugNames[i] + ":" + count;
        }
        if (changed || signature !== drugSignature) { drugSignature = signature; drugRevision++; }
        var previous:Object = rawGroups.loadout;
        var oldDrugs:Array = previous.drugs;
        var drugs:Array = oldDrugs.length == 4 ? null : [];
        for (i = 0; i < 4; i++) {
            var slot:Number = bank * 4 + i;
            var current:Object = drugItems[slot];
            // Only the icon scalar is projected. Reading the raw catalog avoids a
            // deep clone while the returned row still owns strings/numbers only.
            var data:Object = current == null ? null : ItemUtil.getRawItemData(current.name);
            var name:String = text(current.name), icon:String = text(data.icon);
            var key:String = keyLabel(DrugInputService.getKeyName(i));
            var row:Object = oldDrugs[i];
            if (row == null || row.slot !== slot || row.name !== name || row.icon !== icon
                    || row.count !== drugCounts[slot] || row.key !== key) {
                if (drugs == null) drugs = oldDrugs.slice(0, i);
                row = {slot:slot, name:name, icon:icon, count:drugCounts[slot], key:key};
            }
            if (drugs != null) drugs.push(row);
        }
        if (drugs == null) drugs = oldDrugs;
        var revision:Number = finiteValue(skills.revision);
        var switchKey:String = keyLabel(DrugInputService.getSwitchKeyName());
        if (previous != null && previous.revision === revision && previous.skills === skills.slots
                && previous.drugRevision === drugRevision && previous.bank === bank
                && previous.drugs === drugs && previous.switchKey === switchKey) return previous;
        return {revision:revision, skills:skills.slots, drugRevision:drugRevision,
            bank:bank, drugs:drugs, switchKey:switchKey};
    }
    private static function readCooldowns():Array {
        var nativeUnit:Object = hero();
        if (nativeUnit.__enemyActionRuntime.enabled === true) return EnemyActionRuntime.hudCooldowns(nativeUnit);
        var i:Number;
        // 首次实际读取时再引用其他类，避免类注册期跨类初始化。
        if (cooldownKeys == null) {
            cooldownKeys = [ManualCooldownService.WEAPON_SKILL_KEY];
            for (i = 1; i < 13; i++) cooldownKeys.push(ManualCooldownService.quickSkillKey(i));
            for (i = 0; i < 4; i++) cooldownKeys.push(ManualCooldownService.drugKey(i));
            cooldownKeys.push(ManualCooldownService.drugSwitchKey());
        }
        var revision:Number = ManualCooldownService.getHudRevision();
        if (manualCooldownSnapshot != null && revision === lastManualCooldownRevision) return manualCooldownSnapshot;
        var values:Array = cooldownValues;
        ManualCooldownService.writeHudSnapshot(cooldownKeys, values);
        var previous:Array = rawGroups.cooldowns;
        var count:Number = cooldownKeys.length;
        var unchanged:Boolean = previous != null && previous.length == count;
        var offset:Number = 0;
        if (unchanged) {
            for (i = 0; i < count; i++) {
                var old:Array = previous[i];
                if (old[0] !== values[offset] || old[1] !== values[offset + 1] || old[2] !== values[offset + 2]) {
                    unchanged = false;
                    break;
                }
                offset += 3;
            }
        }
        // previous 是上次独立 DTO；scratch 永远不写入它。full 仍由 addGroup 强制发送。
        lastManualCooldownRevision = revision;
        if (unchanged) { manualCooldownSnapshot = previous; return previous; }
        var result:Array = [];
        offset = 0;
        for (i = 0; i < count; i++) {
            result.push([values[offset], values[offset + 1], values[offset + 2]]);
            offset += 3;
        }
        manualCooldownSnapshot = result;
        return result;
    }
    /**
     * 冷兵器主动技能面板（原生 C# 侧 PlayerHudColdSkillWidget）。
     * 具体口径全部落在 单位函数_黑猫_技能搓招指令.as 的 冷技能HUD快照：
     * 只返回「已学会」的技能，未学会的不入表，所以原生侧不会画出空格子。
     * 未安装该投影（或它不可用）时返回空表，原生面板随之隐藏。
     */
    private static function readColdSkills(unit:Object):Array {
        var fn:Object = _root.技能函数;
        if (fn == null || typeof fn.冷技能HUD快照 != "function") return [];
        var rows:Array = fn.冷技能HUD快照(unit);
        return rows instanceof Array ? rows : [];
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
            var current:Object = readLoadout(null, null);
            var slot:Number = Number(p.slot);
            if (p.kind == "skill" && slot > 0 && slot < 13 && Math.floor(slot) == slot
                    && Number(p.revision) == current.revision && text(p.key) == text(current.skills[slot - 1].skillKey)) {
                result = hero().__enemyActionRuntime.enabled === true
                    ? {success:false, error:"fixed_loadout", changed:false}
                    : SkillLoadoutService.unequip(slot, current.revision);
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
        var current:Object = readLoadout(null, null);
        var slot:Number = Number(p.slot);
        hideTooltip();
        hoverId = id;
        if (p.kind == "skill" && slot > 0 && slot < 13 && Math.floor(slot) == slot
                && Number(p.revision) == current.revision && text(p.key) == text(current.skills[slot-1].skillKey)) {
            var nativeUnit:Object = hero();
            if (nativeUnit.__enemyActionRuntime.enabled === true) {
                var action:Object = EnemyActionRuntime.hudAction(nativeUnit, slot);
                if (action != null) NativeTooltipBridge.show({version:1, kind:"hud", mode:"action",
                    data:{name:action.name, keyLabel:current.skills[slot-1].keyLabel,
                        description:action.description}}, null, "top", anchor);
                hoverRequest = NativeTooltipBridge.activeRequestId();
                return;
            }
            var rows:Array = _root.主角技能表;
            for (var i:Number = 0; i < rows.length; i++) {
                if (rows[i][0] === p.key) {
                    var parts:Object = TooltipInputProjection.loadoutSkill(i);
                    if (parts != null) {
                        parts.resourceHint = SkillResourceService.quick(hero(), parts.skillName,
                            Number(current.skills[slot-1].mp));
                        NativeTooltipBridge.show(parts, null, "top", anchor);
                    }
                    break;
                }
            }
        } else if (p.kind == "coldSkill" && slot > 0 && slot < 13 && Math.floor(slot) == slot) {
            var coldRows:Array = _root.主角技能表;
            for (var c:Number = 0; c < coldRows.length; c++) {
                if (coldRows[c][0] === p.key) {
                    var coldParts:Object = TooltipInputProjection.loadoutSkill(c);
                    var coldData:Object = (_root.技能表对象 == undefined) ? null : _root.技能表对象[p.key];
                    var coldMp:Number = coldData == null ? 0 : finiteValue(coldData.MP);
                    if (coldParts != null) {
                        coldParts.resourceHint = SkillResourceService.quick(hero(), coldParts.skillName, coldMp);
                        NativeTooltipBridge.show(coldParts, null, "top", anchor);
                    }
                    break;
                }
            }
        } else if (p.kind == "drug" && slot > -1 && slot < 8 && Math.floor(slot) == slot
                && Number(p.revision) == drugRevision && text(p.key) == text(drugItems[slot].name)) {
            var item:Object = drugItems[slot];
            if (item != null) {
                var projection:Object = org.flashNight.arki.item.InventoryPanelService.buildTooltipProjection(item);
                if (projection.success) {
                    var lane:Number = slot % 4;
                    var drugKey:String = text(current.drugs[lane].key);
                    if (drugKey == "") drugKey = keyLabel(DrugInputService.getKeyName(lane));
                    var drugInput:Object = projection.tooltipInput;
                    drugInput.hud = {kind:"drug", count:Math.floor(finiteValue(drugCounts[slot])),
                        slot:slot, key:drugKey};
                    NativeTooltipBridge.show(drugInput, null, "top", anchor);
                }
            }
        } else if (p.kind == "weapon") {
            var unit:Object = hero();
            var skill:Object = unit.主动战技[unit.攻击模式];
            if (skill != null && skill.isSubweaponControl !== true && weaponName(skill) == text(p.key)) {
                NativeTooltipBridge.show({version:1, kind:"hud", mode:"weapon", data:{
                    name:weaponName(skill), cooldown:finiteValue(skill.冷却时间),
                    mp:finiteValue(skill.消耗mp), hp:finiteValue(skill.消耗hp), sp:finiteValue(skill.消耗sp),
                    description:text(skill.描述), information:text(skill.信息),
                    resourceHint:SkillResourceService.weapon(unit, skill)}}, null, "top", anchor);
            }
        } else if (p.kind == "switch") {
            NativeTooltipBridge.show({version:1, kind:"hud", mode:"switch", data:{
                bank:current.bank, switchKey:current.switchKey,
                otherBankHasStock:DrugInputService.hasBankStock(_root, 1-current.bank)}}, null, "top", anchor);
        } else if (p.kind == "resources") {
            var v:Object = readVitals(hero());
            NativeTooltipBridge.show({version:1, kind:"hud", mode:"resources", data:{
                hp:v.hp, mp:v.mp, shield:v.shield, shieldReady:v.shieldReady, shieldPresent:v.shieldPresent,
                poise:v.poise, experience:v.experience, sp:v.sp}}, null, "top", anchor);
        }
        hoverRequest = NativeTooltipBridge.activeRequestId();
    }
    private static function hideTooltip():Void {
        if (hoverRequest != null) NativeTooltipBridge.hide(hoverRequest);
        hoverRequest = null;
        hoverId = "";
    }
    /** Focused TestLoader probes; never called from production. */
    public static function testOnlyUnitPacket(groups:Object, seq:Number, full:Boolean):String {
        return encodeHudPacket({v:1,epoch:1,seq:seq,full:full,visible:true,groups:groups});
    }
    public static function testOnlyReadVitals(unit:Object):Object { return readVitals(unit); }
    public static function testOnlyPoise(unit:Object):Object { return readPoiseDetail(unit); }
    public static function testOnlyConfigure(p:Object):Void { configureProjection(p); }
    public static function testOnlyCooldownGroup(full:Boolean):Object {
        var groups:Object = {};
        addGroup(groups, "cooldowns", readCooldowns(), full);
        return groups;
    }
    public static function testOnlySameProjection(previous, current):Boolean { return sameProjection(previous, current); }
    public static function testOnlyContext(unit:Object):Number {
        if (compat == null) compat = createCompatibility();
        if (buffProjection == null) buffProjection = new PlayerHudBuffProjection();
        ensureContext(unit); return epoch;
    }
    public static function testOnlyWire(unit:Object):String {
        if (compat == null) compat = createCompatibility();
        var currentLoadout:Object = readLoadout(null, null);
        var groups:Object = {vitals:readVitals(unit), combat:readCombat(unit), loadout:currentLoadout,
            cooldowns:readCooldowns(), buffs:[]};
        if (resourceHintsEnabled) groups.resources = SkillResourceService.snapshot(unit, currentLoadout);
        return Base64.encodeDisplay(json().stringifySafe({v:1, epoch:1, seq:1, full:true, visible:true, groups:groups}));
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
        value.刷新攻击模式 = function(mode:String):Void {
            this.玩家必要信息界面.mode = mode;
            if (mode == "手雷" && _root.物品栏 != null && _root.物品栏.装备栏 != null) {
                var grenadeCount = _root.物品栏.装备栏.getValue("手雷");
                this.玩家必要信息界面.弹夹数 = grenadeCount != undefined ? grenadeCount : "";
            }
        };
        return value;
    }
}
