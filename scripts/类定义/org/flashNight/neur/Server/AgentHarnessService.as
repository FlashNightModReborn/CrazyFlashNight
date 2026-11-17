import org.flashNight.arki.unit.UnitComponent.Targetcache.TargetCacheManager;
import org.flashNight.arki.unit.Action.Input.UnitActionIntentService;
import org.flashNight.arki.scene.SceneInteractionManager;
import org.flashNight.arki.dialogue.NativeDialogueService;
import org.flashNight.arki.unit.Action.Skill.EmergencyInjectionService;

/**
 * AgentHarnessService — 受 `--agent-harness` 独占激活的 AS2 测试线束服务。
 *
 * 安全不变量：
 * 1. 默认彻底惰性（_bound=false）；正常玩家对局、ArenaWorker 与普通 AgentRuntime v1 零行为变化。
 * 2. 强制校验 _root.savePath 必须以 "cf7_agent_" 开头；任一帧检测到非 cf7_agent_ 槽位立即自解绑。
 * 3. 提供锁定桌面/后台模式下仍确定性工作的 world_snapshot 与虚拟键位/导航输入（不修改原生 Key.isDown）。
 */
class org.flashNight.neur.Server.AgentHarnessService {

    private static var _installed:Boolean = false;
    private static var _bound:Boolean = false;
    private static var _sessionEpoch:String = "";
    private static var _boundSlot:String = "";
    private static var _json:LiteJSON = null;

    // 虚拟 8 位动作/移动掩码（对应 通信_fs_帧计时器.键盘输入控制目标）与帧有效期
    private static var _heldMask:Number = 0;
    private static var _heldMaskUntilFrame:Number = 0;
    // 虚拟键码 -> 过期帧号（>=0；0 表示常驻直到 release_all/解绑）
    private static var _virtualKeys:Object = {};

    // 目标点自动导航状态
    private static var _navActive:Boolean = false;
    private static var _navTargetX:Number = 0;
    private static var _navTargetZ:Number = 0;
    private static var _navTolerance:Number = 25;
    private static var _navRun:Boolean = false;
    private static var _navDeadlineFrame:Number = 0;
    private static var _navMask:Number = 0;
    private static var _navRequestId:String = "";

    public static function install():Void {
        if (_installed) return;
        _installed = true;
        if (_root.gameCommands == undefined) _root.gameCommands = {};
        _root.gameCommands["agentHarnessCmd"] = function(params:Object):Void {
            org.flashNight.neur.Server.AgentHarnessService.handleCommand(params);
        };
        if (_root._agentHarnessBridge == undefined) {
            _root._agentHarnessBridge = {
                sampleMask: function(hero:MovieClip, currentFrame:Number):Number {
                    return org.flashNight.neur.Server.AgentHarnessService.sampleMask(hero, currentFrame);
                },
                isKeyDown: function(keycode:Number):Boolean {
                    return org.flashNight.neur.Server.AgentHarnessService.isVirtualKeyDown(keycode);
                }
            };
        }
        syncRootFlag();
    }

    public static function onTransportDisconnected():Void {
        resetVirtualInput();
        _bound = false;
        _sessionEpoch = "";
        _boundSlot = "";
        syncRootFlag();
    }

    private static function isAllowedHarnessSlot(slot:String):Boolean {
        if (slot == undefined || slot == null) return false;
        var s:String = String(slot);
        if (s.length > 10 && s.indexOf("cf7_agent_") == 0) return true;
        if (s.indexOf("bookrun_") == 0
                && _root._saveExt != undefined && _root._saveExt.bookRun != undefined) {
            var origin:String = String(_root._saveExt.bookRun.originSlot || "");
            if (origin.length > 10 && origin.indexOf("cf7_agent_") == 0) return true;
        }
        return false;
    }

    public static function isActive():Boolean {
        if (!_bound) return false;
        var slot:String = (_root.savePath == undefined || _root.savePath == null) ? "" : String(_root.savePath);
        if (!isAllowedHarnessSlot(slot)) {
            // 非隔离测试槽位禁止保留虚拟输入/线束状态
            resetVirtualInput();
            if (slot != "") {
                _bound = false;
                _sessionEpoch = "";
                _boundSlot = "";
                syncRootFlag();
            }
            return false;
        }
        return true;
    }

    private static function syncRootFlag():Void {
        _root._agentHarnessActive = (_bound === true);
    }

    public static function resetVirtualInput():Void {
        _heldMask = 0;
        _heldMaskUntilFrame = 0;
        _virtualKeys = {};
        _navActive = false;
        _navMask = 0;
        _navDeadlineFrame = 0;
        _navRequestId = "";
    }

    private static function currentFrame():Number {
        var f:Number = (_root.帧计时器 != undefined) ? Number(_root.帧计时器.当前帧数) : 0;
        return isNaN(f) ? 0 : f;
    }

    public static function isVirtualKeyDown(keycode:Number):Boolean {
        if (!_bound) return false;
        if (keycode == undefined || isNaN(keycode)) return false;
        if (!isActive()) return false;
        var exp = _virtualKeys[String(keycode)];
        if (exp == undefined) return false;
        var expFrame:Number = Number(exp);
        if (expFrame > 0 && currentFrame() > expFrame) {
            delete _virtualKeys[String(keycode)];
            return false;
        }
        return true;
    }

    public static function sampleMask(hero:MovieClip, frameNo:Number):Number {
        if (!isActive()) return 0;
        var now:Number = (frameNo == undefined || isNaN(frameNo)) ? currentFrame() : frameNo;
        if (_heldMask != 0 && _heldMaskUntilFrame > 0 && now > _heldMaskUntilFrame) {
            _heldMask = 0;
            _heldMaskUntilFrame = 0;
        }
        if (_navActive) {
            updateNavigation(hero, now);
        } else {
            _navMask = 0;
        }
        return (_heldMask | _navMask);
    }

    private static function updateNavigation(hero:MovieClip, now:Number):Void {
        if (hero == undefined || hero == null) {
            _navActive = false;
            _navMask = 0;
            emitEvent("nav_failed", { reason: "hero_missing", requestId: _navRequestId });
            return;
        }
        if (_navDeadlineFrame > 0 && now > _navDeadlineFrame) {
            _navActive = false;
            _navMask = 0;
            emitEvent("nav_timeout", {
                requestId: _navRequestId,
                x: Math.round(Number(hero._x)),
                z: Math.round(isNaN(Number(hero.Z轴坐标)) ? Number(hero._y) : Number(hero.Z轴坐标))
            });
            return;
        }
        var hx:Number = Number(hero._x);
        var hz:Number = isNaN(Number(hero.Z轴坐标)) ? Number(hero._y) : Number(hero.Z轴坐标);
        var dx:Number = _navTargetX - hx;
        var dz:Number = _navTargetZ - hz;
        var tol:Number = _navTolerance > 2 ? _navTolerance : 2;
        if (Math.abs(dx) <= tol && Math.abs(dz) <= tol) {
            _navActive = false;
            _navMask = 0;
            emitEvent("nav_completed", {
                requestId: _navRequestId,
                x: Math.round(hx),
                z: Math.round(hz)
            });
            return;
        }
        var m:Number = 0;
        if (dx < -tol) m = m | 1;
        else if (dx > tol) m = m | 2;
        if (dz < -tol) m = m | 4;
        else if (dz > tol) m = m | 8;
        if (_navRun) m = m | 128;
        _navMask = m;
    }

    public static function handleCommand(params:Object):Void {
        var reqId:String = (params != undefined && params.requestId != undefined) ? String(params.requestId) : "";
        var sub:String = (params != undefined && params.sub != undefined) ? String(params.sub) : "";
        if (sub == "") {
            sendResponse(reqId, sub, false, "missing_subcommand", null);
            return;
        }
        if (sub == "bind") {
            handleBind(reqId, params);
            return;
        }
        if (sub == "unbind") {
            onTransportDisconnected();
            sendResponse(reqId, sub, true, "", { bound: false });
            return;
        }
        var slot:String = (_root.savePath == undefined || _root.savePath == null) ? "" : String(_root.savePath);
        if (!_bound || !isAllowedHarnessSlot(slot)) {
            sendResponse(reqId, sub, false, "harness_not_bound_or_unsafe_slot", { slot: slot, bound: _bound });
            return;
        }
        if (sub == "world_snapshot") {
            sendResponse(reqId, sub, true, "", buildWorldSnapshot(params));
            return;
        }
        if (sub == "world_act") {
            handleWorldAct(reqId, params);
            return;
        }
        if (sub == "flush_save") {
            var flushOk:Boolean = false;
            if (_root.存档系统 != undefined && typeof _root.存档系统.flushDurableNow == "function") {
                flushOk = (_root.存档系统.flushDurableNow("manual_save") === true);
            } else if (typeof _root.强制存盘 == "function") {
                flushOk = (_root.强制存盘() === true);
            }
            sendResponse(reqId, sub, flushOk, flushOk ? "" : "save_flush_failed", {
                slot: slot,
                dirty: (_root.存档系统 != undefined ? (_root.存档系统.dirtyMark === true) : false)
            });
            return;
        }
        sendResponse(reqId, sub, false, "unknown_subcommand", null);
    }

    private static function handleBind(reqId:String, params:Object):Void {
        var reqSlot:String = (params.slot != undefined) ? String(params.slot) : "";
        var epoch:String = (params.sessionEpoch != undefined) ? String(params.sessionEpoch) : "";
        var currentSlot:String = (_root.savePath == undefined || _root.savePath == null) ? "" : String(_root.savePath);
        if (reqSlot.indexOf("cf7_agent_") != 0 || epoch == "") {
            sendResponse(reqId, "bind", false, "invalid_harness_slot_or_epoch", null);
            return;
        }
        if (currentSlot != "" && currentSlot.indexOf("cf7_agent_") != 0) {
            sendResponse(reqId, "bind", false, "active_slot_is_not_agent_slot", { savePath: currentSlot });
            return;
        }
        install();
        resetVirtualInput();
        _bound = true;
        _boundSlot = reqSlot;
        _sessionEpoch = epoch;
        syncRootFlag();
        sendResponse(reqId, "bind", true, "", {
            bound: true,
            slot: (currentSlot != "" ? currentSlot : reqSlot),
            sessionEpoch: _sessionEpoch
        });
    }

    public static function buildWorldSnapshot(params:Object):Object {
        var gw:MovieClip = _root.gameworld;
        var hero:MovieClip = TargetCacheManager.findHero();
        var sceneObj:Object = (_root.agent != undefined && typeof _root.agent.投影场景段 == "function")
            ? _root.agent.投影场景段()
            : {
                stageFlag: (_root.关卡标志 == undefined) ? "" : String(_root.关卡标志),
                stageName: (_root.当前关卡名 == undefined) ? "" : String(_root.当前关卡名),
                entrance: (_root.场景进入位置名 == undefined) ? "" : String(_root.场景进入位置名),
                inCombat: (_root.当前为战斗地图 === true)
            };

        var heroObj:Object = { present: false };
        var hx:Number = 0;
        var hz:Number = 0;
        if (hero != undefined && hero != null) {
            hx = isNaN(Number(hero._x)) ? 0 : Number(hero._x);
            hz = isNaN(Number(hero.Z轴坐标)) ? (isNaN(Number(hero._y)) ? 0 : Number(hero._y)) : Number(hero.Z轴坐标);
            heroObj = {
                present: true,
                id: String(hero._name),
                displayName: (_root.角色名 == undefined) ? "" : String(_root.角色名),
                x: Math.round(hx),
                y: Math.round(Number(hero._y)),
                z: Math.round(hz),
                direction: (hero.方向 == undefined) ? "" : String(hero.方向),
                state: (hero.状态 == undefined) ? "" : String(hero.状态),
                attackMode: (hero.攻击模式 == undefined) ? "" : String(hero.攻击模式),
                hp: isNaN(Number(hero.hp)) ? 0 : Math.round(Number(hero.hp)),
                maxHp: isNaN(Number(hero.hp满血值)) ? 0 : Math.round(Number(hero.hp满血值)),
                mp: isNaN(Number(hero.mp)) ? 0 : Math.round(Number(hero.mp)),
                maxMp: isNaN(Number(hero.mp满血值)) ? 0 : Math.round(Number(hero.mp满血值)),
                reloading: (hero.man != undefined && hero.man.换弹标签 === true),
                virtualMask: _heldMask | _navMask,
                navActive: _navActive,
                combatResources: projectCombatResources(hero)
            };
        }

        var units:Array = [];
        var pickups:Array = [];
        var doors:Array = [];
        if (gw != undefined && gw != null) {
            for (var k:String in gw) {
                var child = gw[k];
                if (typeof child != "movieclip") continue;
                if (hero != null && child === hero) continue;
                var cx:Number = Number(child._x);
                var cy:Number = Number(child._y);
                if (isNaN(cx) || isNaN(cy)) continue;
                var cz:Number = isNaN(Number(child.Z轴坐标)) ? cy : Number(child.Z轴坐标);
                var dist:Number = Math.round(Math.abs(cx - hx) + Math.abs(cz - hz));

                if (child.hp != undefined && !isNaN(Number(child.hp)) && Number(child.hp满血值) > 0) {
                    var faction:String = (child.是否为敌人 === true) ? "enemy" : ((child.是否为敌人 === false) ? "ally" : "neutral");
                    var uName:String = (child.名字 != undefined) ? String(child.名字) : ((child.兵种 != undefined) ? String(child.兵种) : String(child._name));
                    units.push({
                        id: String(child._name),
                        name: uName,
                        faction: faction,
                        hp: Math.round(Number(child.hp)),
                        maxHp: Math.round(Number(child.hp满血值)),
                        x: Math.round(cx),
                        y: Math.round(cy),
                        z: Math.round(cz),
                        dist: dist,
                        state: (child.状态 == undefined) ? "" : String(child.状态),
                        interactive: (typeof child.互动 == "function" || child.NPC对话已绑定 === true || child.enableInteractionKey === true)
                    });
                } else if (child.物品名 != undefined || child.掉落物 == true) {
                    if (pickups.length < 25) {
                        pickups.push({
                            id: String(child._name),
                            itemName: (child.物品名 == undefined) ? String(child._name) : String(child.物品名),
                            x: Math.round(cx),
                            y: Math.round(cy),
                            dist: dist
                        });
                    }
                } else if (child.目标场景 != undefined || child.切换场景 != undefined || String(child._name).indexOf("门") >= 0) {
                    if (doors.length < 20) {
                        doors.push({
                            id: String(child._name),
                            target: (child.目标场景 != undefined) ? String(child.目标场景) : "",
                            x: Math.round(cx),
                            y: Math.round(cy),
                            dist: dist
                        });
                    }
                }
            }
        }
        units.sort(function(a:Object, b:Object):Number {
            return Number(a.dist) - Number(b.dist);
        });
        if (units.length > 40) units.length = 40;

        var interactions:Array = [];
        var sim:SceneInteractionManager = SceneInteractionManager.instance;
        if (sim != null && sim.interactionInfoList instanceof Array) {
            var ilist:Array = sim.interactionInfoList;
            for (var ii:Number = 0; ii < ilist.length && interactions.length < 25; ii++) {
                var info:Object = ilist[ii];
                if (info == null || info.mc == null) continue;
                if (info.mc.enableInteractionKey !== true) continue;
                interactions.push({
                    id: String(info.mc._name),
                    x: Math.round(Number(info.x)),
                    y: Math.round(Number(info.y)),
                    isCurrent: (sim.currentMC === info.mc)
                });
            }
        }

        var dlgActive:Boolean = false;
        var dlgSnap:Object = null;
        try {
            dlgActive = NativeDialogueService.hasActiveSession() === true;
            if (dlgActive) dlgSnap = NativeDialogueService.getSessionSnapshot();
        } catch (dlgErr) {}

        var snap:Object = {
            slot: (_root.savePath == undefined) ? "" : String(_root.savePath),
            frame: currentFrame(),
            paused: (_root.暂停 === true),
            scene: sceneObj,
            worldPresent: (gw != undefined && gw != null),
            bounds: {
                xmin: Number(_root.Xmin),
                xmax: Number(_root.Xmax),
                ymin: Number(_root.Ymin),
                ymax: Number(_root.Ymax)
            },
            money: isNaN(Number(_root.金钱)) ? 0 : Number(_root.金钱),
            kpoint: isNaN(Number(_root.虚拟币)) ? 0 : Number(_root.虚拟币),
            hero: heroObj,
            units: units,
            pickups: pickups,
            doors: doors,
            interactions: interactions,
            dialogue: { active: dlgActive, snapshot: dlgSnap }
        };

        if (params != undefined && params.includePlayer === true && _root.agent != undefined && typeof _root.agent.构建存档投影 == "function") {
            snap.player = _root.agent.构建存档投影(snap.slot);
        }
        return snap;
    }

    private static function handleWorldAct(reqId:String, params:Object):Void {
        var act:String = (params.act != undefined) ? String(params.act) : "";
        var hero:MovieClip = TargetCacheManager.findHero();
        var now:Number = currentFrame();

        if (act == "release_all") {
            resetVirtualInput();
            sendResponse(reqId, "world_act", true, "", { act: act, frame: now });
            return;
        }
        if (act == "hold_mask" || act == "tap_mask") {
            var m:Number = Number(params.mask);
            if (isNaN(m) || m < 0) {
                sendResponse(reqId, "world_act", false, "invalid_mask", null);
                return;
            }
            var frames:Number = normalizeDuration(params.durationFrames, act == "tap_mask" ? 3 : 30);
            _heldMask = m & 255;
            _heldMaskUntilFrame = (frames > 0) ? (now + frames) : 0;
            sendResponse(reqId, "world_act", true, "", { act: act, mask: _heldMask, untilFrame: _heldMaskUntilFrame });
            return;
        }
        if (act == "hold_keys" || act == "tap_key" || act == "tap_keys") {
            var keys:Array = [];
            if (params.keys instanceof Array) {
                keys = params.keys;
            } else if (params.key != undefined) {
                keys = [params.key];
            }
            var dur:Number = normalizeDuration(params.durationFrames, act == "hold_keys" ? 30 : 3);
            var exp:Number = (dur > 0) ? (now + dur) : 0;
            var maskAcc:Number = 0;
            var keyCodesApplied:Array = [];
            for (var i:Number = 0; i < keys.length; i++) {
                var kStr:String = String(keys[i]);
                if (kStr == "reload" || kStr == "换弹") {
                    if (hero != null) {
                        UnitActionIntentService.submit(
                            hero,
                            UnitActionIntentService.CHANNEL_COMBAT,
                            UnitActionIntentService.KIND_PRIMARY_RELOAD,
                            now,
                            2,
                            null,
                            1
                        );
                    }
                    continue;
                }
                var bit:Number = maskBitForKeyName(kStr);
                if (bit > 0) maskAcc = maskAcc | bit;
                var code:Number = keyCodeForName(kStr, hero);
                if (!isNaN(code) && code > 0) {
                    _virtualKeys[String(code)] = exp;
                    keyCodesApplied.push(code);
                }
            }
            if (maskAcc > 0) {
                _heldMask = (_heldMask | maskAcc) & 255;
                _heldMaskUntilFrame = exp;
            }
            sendResponse(reqId, "world_act", true, "", {
                act: act,
                mask: _heldMask,
                keyCodes: keyCodesApplied,
                untilFrame: exp
            });
            return;
        }
        if (act == "move_to") {
            var tx:Number = Number(params.x);
            var tz:Number = Number(params.z);
            if (isNaN(tx) || isNaN(tz)) {
                sendResponse(reqId, "world_act", false, "invalid_target_coords", null);
                return;
            }
            if (hero == undefined || hero == null) {
                sendResponse(reqId, "world_act", false, "hero_missing", null);
                return;
            }
            var maxFrames:Number = normalizeDuration(params.maxFrames, 180);
            var tol:Number = (params.tolerance != undefined && !isNaN(Number(params.tolerance))) ? Number(params.tolerance) : 25;
            _navTargetX = tx;
            _navTargetZ = tz;
            _navTolerance = tol;
            _navRun = (params.run === true);
            _navDeadlineFrame = now + maxFrames;
            _navRequestId = reqId;
            _navActive = true;
            sendResponse(reqId, "world_act", true, "", {
                act: act,
                navActive: true,
                targetX: tx,
                targetZ: tz,
                deadlineFrame: _navDeadlineFrame
            });
            return;
        }
        if (act == "pickup") {
            if (hero == undefined || hero == null || typeof hero.拾取 != "function") {
                sendResponse(reqId, "world_act", false, "pickup_unavailable", null);
                return;
            }
            hero.拾取();
            sendResponse(reqId, "world_act", true, "", { act: act, frame: now });
            return;
        }
        if (act == "interact") {
            var sim:SceneInteractionManager = SceneInteractionManager.instance;
            if (sim != null && sim.currentMC != null) {
                sim.interact();
                sendResponse(reqId, "world_act", true, "", { act: act, via: "scene_interaction" });
                return;
            }
            var ikCode:Number = keyCodeForName("互动键", hero);
            if (!isNaN(ikCode) && ikCode > 0) {
                _virtualKeys[String(ikCode)] = now + 3;
            }
            sendResponse(reqId, "world_act", true, "", { act: act, via: "virtual_key", keyCode: ikCode });
            return;
        }
        if (act == "open_panel") {
            openPanelFromHarness(reqId, params);
            return;
        }
        sendResponse(reqId, "world_act", false, "unknown_world_act", { act: act });
    }

    private static function openPanelFromHarness(reqId:String, params:Object):Void {
        var panel:String = (params.panel != undefined) ? String(params.panel) : "";
        var cmds:Object = _root.gameCommands;
        if (panel == "" || cmds == undefined) {
            sendResponse(reqId, "world_act", false, "panel_or_commands_unavailable", { panel: panel });
            return;
        }
        var ok:Boolean = false;
        if (panel == "workbench") {
            if (typeof cmds["openInventoryWorkbench"] == "function") {
                ok = cmds["openInventoryWorkbench"]({
                    profile: String(params.profile || "battlebox"),
                    view: String(params.view || "inventory"),
                    source: "agent_control"
                }) !== false;
            }
        } else if (panel == "arena") {
            if (typeof cmds["openArenaForAgent"] == "function") {
                ok = cmds["openArenaForAgent"]({}) === true;
            }
        } else if (panel == "gym") {
            if (typeof cmds["openGymForAgent"] == "function") {
                ok = cmds["openGymForAgent"]() === true;
            }
        } else if (panel == "bookshelf") {
            if (typeof cmds["openBookshelfForAgent"] == "function") {
                ok = cmds["openBookshelfForAgent"]() === true;
            }
        } else if (panel == "npcshop") {
            if (typeof cmds["openNpcShop"] == "function") {
                if (params.shopId != undefined && String(params.shopId) != "") {
                    ok = cmds["openNpcShop"]({ shopId: String(params.shopId), source: "world_npc" }) === true;
                } else if (_root.shops != undefined) {
                    for (var sid:String in _root.shops) {
                        if (cmds["openNpcShop"]({ shopId: sid, source: "world_npc" }) === true) {
                            ok = true;
                            break;
                        }
                    }
                }
            }
        } else if (panel == "crafting") {
            if (typeof cmds["openCraftingWorkbench"] == "function") {
                ok = cmds["openCraftingWorkbench"]({
                    category: String(params.category || "武器合成"),
                    source: "crafting_entry"
                }) === true;
            }
        } else if (panel == "stage-select") {
            if (typeof cmds["openWebStageSelect"] == "function") {
                ok = cmds["openWebStageSelect"]({
                    source: "agent_harness",
                    frameLabel: String(params.frameLabel || _root.关卡地图帧值 || "基地门口"),
                    returnFrameLabel: String(params.returnFrameLabel || _root.关卡地图帧值 || "基地门口")
                }) === true;
            }
        } else if (panel == "hairdresser") {
            if (typeof cmds["openHairdresser"] == "function") ok = cmds["openHairdresser"]() === true;
        } else if (panel == "modifier") {
            if (typeof cmds["openModifier"] == "function") ok = cmds["openModifier"]() === true;
        } else if (panel == "settings") {
            if (typeof cmds["openSettings"] == "function") ok = cmds["openSettings"]() === true;
        } else if (panel == "sleep") {
            if (typeof cmds["openSleepForAgent"] == "function") ok = cmds["openSleepForAgent"]() === true;
        } else if (panel == "subway") {
            if (typeof cmds["openSubwayForAgent"] == "function") ok = cmds["openSubwayForAgent"]() === true;
        } else if (panel == "egg-stage-select") {
            if (typeof cmds["openEggStageSelectForAgent"] == "function") ok = cmds["openEggStageSelectForAgent"]() === true;
        } else if (panel == "surgery") {
            if (typeof cmds["openSurgeryForAgent"] == "function") ok = cmds["openSurgeryForAgent"]() === true;
        } else if (panel == "garage") {
            if (typeof cmds["openGarageForAgent"] == "function") {
                ok = cmds["openGarageForAgent"]({ vehicleId: String(params.vehicleId || "bicycle") }) === true;
            }
        } else {
            sendResponse(reqId, "world_act", false, "unsupported_as2_panel", { panel: panel });
            return;
        }
        sendResponse(reqId, "world_act", ok, ok ? "" : "open_panel_rejected", { act: "open_panel", panel: panel });
    }

    private static function normalizeDuration(raw, fallback:Number):Number {
        if (raw == undefined || raw == null) return fallback;
        var n:Number = Number(raw);
        if (isNaN(n)) return fallback;
        if (n <= 0) return 0;
        if (n > 600) return 600;
        return Math.floor(n);
    }

    private static function maskBitForKeyName(name:String):Number {
        if (name == "left" || name == "左" || name == "左键") return 1;
        if (name == "right" || name == "右" || name == "右键") return 2;
        if (name == "up" || name == "上" || name == "上键") return 4;
        if (name == "down" || name == "下" || name == "下键") return 8;
        if (name == "A" || name == "a" || name == "attack" || name == "shoot" || name == "A键" || name == "攻击" || name == "射击") return 16;
        if (name == "B" || name == "b" || name == "B键" || name == "重击") return 32;
        if (name == "C" || name == "c" || name == "jump" || name == "dodge" || name == "C键" || name == "跳跃" || name == "闪避") return 64;
        if (name == "run" || name == "shift" || name == "奔跑" || name == "奔跑键") return 128;
        return 0;
    }

    /** 隔离线束只读投影：不调用弹药ensure/修复，不推进套装周期或触发持久写。 */
    public static function projectCombatResources(hero:Object):Object {
        var slots:Array = ["手枪", "手枪2"];
        var weapons:Array = [];
        for (var i:Number = 0; i < slots.length; i++) {
            var slot:String = slots[i];
            var item:Object = hero[slot];
            var value:Object = item.value;
            var ammo:Object = value.ammoState;
            weapons.push({slot:slot, name:item.name == undefined ? "" : String(item.name),
                capacity:hero[slot + "弹匣容量"], shot:value.shot, chamber:ammo.chamber,
                ghost:ammo.ghost, reward:ammo.reward});
        }
        var state:Object = hero.__titaniumType61Status;
        var titanium:Object = null;
        if (state) titanium = {state:state.state, capacity:state.capacity, maximum:state.maximum,
            ammoSynthesized:state.ammoSynthesized, ammoMpSpent:state.ammoMpSpent,
            baseMpEarned:state.baseMpEarned, mpSpent:state.mpSpent, healed:state.healed, charged:state.charged};
        var unifiedState:Object = hero.__unified61Status;
        var unified:Object = unifiedState == null ? null : {
            state:unifiedState.state, capacity:unifiedState.capacity, maximum:unifiedState.maximum};
        var memory:Object = hero.__emergencyInjectionMemory;
        var injector:Object = hero.__emergencyInjector;
        var emergency:Object = {authorization:EmergencyInjectionService.snapshot(_root),
            installed:injector != undefined, crisisUsed:memory.used === true,
            attempts:memory == null ? 0 : memory.attempts,
            doses:memory == null ? 0 : memory.doses,
            observedDrops:memory == null ? 0 : memory.observedDrops,
            lastBefore:injector.lastBefore, lastAfter:injector.lastAfter, lastError:injector.lastError};
        return {weapons:weapons, titanium:titanium, unified:unified, emergencyInjection:emergency};
    }

    private static function keyCodeForName(name:String, hero:MovieClip):Number {
        if (name == "left" || name == "左" || name == "左键") return Number(hero != null ? hero.左键 : _root.左键);
        if (name == "right" || name == "右" || name == "右键") return Number(hero != null ? hero.右键 : _root.右键);
        if (name == "up" || name == "上" || name == "上键") return Number(hero != null ? hero.上键 : _root.上键);
        if (name == "down" || name == "下" || name == "下键") return Number(hero != null ? hero.下键 : _root.下键);
        if (name == "A" || name == "a" || name == "attack" || name == "shoot" || name == "A键" || name == "攻击" || name == "射击") return Number(hero != null ? hero.A键 : _root.A键);
        if (name == "B" || name == "b" || name == "B键" || name == "重击") return Number(hero != null ? hero.B键 : _root.B键);
        if (name == "C" || name == "c" || name == "jump" || name == "dodge" || name == "C键" || name == "跳跃" || name == "闪避") return Number(hero != null ? hero.C键 : _root.C键);
        if (name == "run" || name == "shift" || name == "奔跑" || name == "奔跑键") return isNaN(Number(_root.奔跑键)) ? 16 : Number(_root.奔跑键);
        if (name == "interact" || name == "互动" || name == "互动键") return isNaN(Number(_root.互动键)) ? 69 : Number(_root.互动键);
        if (name == "weapon_skill" || name == "武器技能" || name == "武器技能键") return Number(_root.武器技能键);
        if (name == "switch_weapon" || name == "切换武器" || name == "切换武器键") return Number(_root.切换武器键 != undefined ? _root.切换武器键 : (hero != null ? hero.切换武器键 : NaN));
        if (name == "drug_switch" || name == "药剂切换" || name == "药剂组切换键") return Number(_root["药剂组切换键"]);
        if (name.indexOf("quick_skill_") == 0) return Number(_root["快捷技能栏键" + name.substr(12)]);
        if (name.indexOf("技能") == 0) return Number(_root["快捷技能栏键" + name.substr(2)]);
        if (name.indexOf("drug_") == 0) return Number(_root["快捷物品栏键" + name.substr(5)]);
        if (name.indexOf("药剂") == 0) return Number(_root["快捷物品栏键" + name.substr(2)]);
        if (name.indexOf("key:") == 0) return Number(name.substr(4));
        var direct:Number = Number(name);
        return (!isNaN(direct) && direct > 0) ? direct : NaN;
    }

    private static function emitEvent(kind:String, data:Object):Void {
        if (_root.server == undefined || typeof _root.server.sendSocketMessage != "function") return;
        if (_json == undefined) _json = new LiteJSON();
        var env:Object = {
            task: "agent_harness_event",
            payload: {
                sessionEpoch: _sessionEpoch,
                kind: kind,
                frame: currentFrame(),
                data: data
            }
        };
        _root.server.sendSocketMessage(_json.stringifySafe(env));
    }

    private static function sendResponse(reqId:String, sub:String, ok:Boolean, error:String, data:Object):Void {
        if (_root.server == undefined || typeof _root.server.sendSocketMessage != "function") return;
        if (_json == undefined) _json = new LiteJSON();
        var env:Object = {
            task: "agent_harness_response",
            payload: {
                requestId: reqId,
                sessionEpoch: _sessionEpoch,
                sub: sub,
                ok: ok,
                error: error,
                data: data
            }
        };
        _root.server.sendSocketMessage(_json.stringifySafe(env));
    }
}
