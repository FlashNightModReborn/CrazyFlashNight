import org.flashNight.neur.Server.AgentHarnessService;

class org.flashNight.neur.Server.test.AgentHarnessServiceTest {
    private static var _passed:Number = 0;
    private static var _failed:Number = 0;

    private static function check(cond:Boolean, label:String):Void {
        if (cond) {
            _passed++;
        } else {
            _failed++;
            trace("FAIL AgentHarnessServiceTest: " + label);
        }
    }

    public static function runAllTests():Void {
        _passed = 0;
        _failed = 0;

        var savedSlot = _root.savePath;
        var savedExt = _root._saveExt;
        var savedServer = _root.server;
        var savedCommands = _root.gameCommands;
        var savedTimer = _root.帧计时器;
        var savedWorld = _root.gameworld;
        var savedPlayers = _root.当前玩家总数;
        var savedModeKeys:Array = [_root.键1,_root.键2,_root.键3,_root.键4,_root.键5];
        var modeHero:MovieClip;
        var savedHeroKeys = {
            left: _root.左键, right: _root.右键, interact: _root.互动键, wskill: _root.武器技能键
        };

        try {
            var sent:Array = [];
            _root.server = {
                sendSocketMessage: function(msg:String):Boolean {
                    sent.push(msg);
                    return true;
                }
            };
            _root.gameCommands = {};
            _root.帧计时器 = { 当前帧数: 100 };
            _root.左键 = 65;
            _root.右键 = 68;
            _root.互动键 = 69;
            _root.武器技能键 = 70;

            AgentHarnessService.install();
            check(!AgentHarnessService.isActive(), "inert before bind");
            check(typeof _root.gameCommands["agentHarnessCmd"] == "function", "agentHarnessCmd installed");

            // Refuse real player save slots
            _root.savePath = "crazyflasher7_saves";
            _root.gameCommands["agentHarnessCmd"]({
                sub: "bind", requestId: "r1", slot: "crazyflasher7_saves", sessionEpoch: "e1"
            });
            check(!AgentHarnessService.isActive(), "rejects player save slot");
            check(sent.length == 1 && sent[0].indexOf('"ok":false') >= 0, "player save bind emits failure");

            // Allow cf7_agent_* slot
            sent = [];
            _root.savePath = "cf7_agent_unit_test";
            _root.gameCommands["agentHarnessCmd"]({
                sub: "bind", requestId: "r2", slot: "cf7_agent_unit_test", sessionEpoch: "e2"
            });
            check(AgentHarnessService.isActive(), "binds cf7_agent_* slot");
            check(_root._agentHarnessActive === true, "sets _root._agentHarnessActive");
            check(sent.length == 1 && sent[0].indexOf('"ok":true') >= 0, "bind emits ok=true");

            // hold_mask expires after TTL
            _root.gameCommands["agentHarnessCmd"]({
                sub: "world_act", requestId: "r3", act: "hold_mask", mask: 2, durationFrames: 5
            });
            check(AgentHarnessService.sampleMask(null, 100) == 2, "mask active at frame 100");
            check(AgentHarnessService.sampleMask(null, 105) == 2, "mask active at frame 105");
            check(AgentHarnessService.sampleMask(null, 106) == 0, "mask auto-expires at frame 106");

            // virtual key works with bridge & expires
            _root.gameCommands["agentHarnessCmd"]({
                sub: "world_act", requestId: "r4", act: "tap_key", key: "互动键", durationFrames: 4
            });
            check(AgentHarnessService.isVirtualKeyDown(69) === true, "virtual interact key down at 100");
            check(_root._agentHarnessBridge.isKeyDown(69) === true, "bridge interact key down at 100");
            _root.帧计时器.当前帧数 = 104;
            check(AgentHarnessService.isVirtualKeyDown(69) === true, "virtual interact key down at 104");
            _root.帧计时器.当前帧数 = 105;
            check(AgentHarnessService.isVirtualKeyDown(69) === false, "virtual interact key auto-expires at 105");

            // Execute the authored player key consumer, using unused physical key codes.
            _root.gameworld = {__combatAdmitted:true}; _root.当前玩家总数=1;
            var modes:Array=["空手","兵器","手枪","长枪","手雷"];
            var selected:Array=[];
            modeHero=_root.createEmptyMovieClip("__harnessModeTest",_root.getNextHighestDepth());
            modeHero.__modeSelections=selected;
            modeHero.攻击模式切换=function(mode:String):Void { this.__modeSelections.push(mode); };
            modeHero.攻击模式切换("receiver_probe");
            check(selected.length==1 && selected[0]=="receiver_probe","mode receiver callback is bound to current actor");
            selected.length=0;
            modeHero.按键控制攻击模式=_root.主角函数.按键控制攻击模式;
            for(var modeIndex:Number=0;modeIndex<5;modeIndex++) _root["键"+(modeIndex+1)]=241+modeIndex;
            for(modeIndex=0;modeIndex<5;modeIndex++) {
                AgentHarnessService.resetVirtualInput();
                _root.gameCommands["agentHarnessCmd"]({sub:"world_act",requestId:"mode"+modeIndex,
                    act:"tap_key",key:String(241+modeIndex),durationFrames:5});
                modeHero.按键控制攻击模式();
                check(selected.length==modeIndex+1 && selected[modeIndex]==modes[modeIndex],"virtual weapon key uses authored mode consumer "+modeIndex);
            }
            AgentHarnessService.resetVirtualInput();
            _root.gameCommands["agentHarnessCmd"]({sub:"world_act",requestId:"modeGuard",act:"tap_key",key:"241",durationFrames:5});
            _root._agentHarnessActive=false; modeHero.按键控制攻击模式();
            check(selected.length==5,"normal unbound input ignores virtual weapon keys");
            _root._agentHarnessActive=true; _root.gameworld.__combatAdmitted=false; modeHero.按键控制攻击模式();
            check(selected.length==5,"virtual mode selection preserves combat admission guard");
            _root.gameworld.__combatAdmitted=true; _root.当前玩家总数=2; modeHero.按键控制攻击模式();
            check(selected.length==5,"virtual mode selection preserves player-count guard");
            _root.当前玩家总数=1; modeHero.__cf6TraversalOwner={}; modeHero.按键控制攻击模式();
            check(selected.length==5,"virtual mode selection preserves traversal ownership guard");
            modeHero.removeMovieClip(); modeHero=null;
            AgentHarnessService.resetVirtualInput();

            // bookrun_ owned by cf7_agent_ remains active, while bookrun_ owned by real player disarms
            _root.savePath = "bookrun_test_session";
            _root._saveExt = { bookRun: { originSlot: "cf7_agent_unit_test" } };
            check(AgentHarnessService.isActive() === true, "allows bookrun owned by cf7_agent_*");
            _root._saveExt = { bookRun: { originSlot: "crazyflasher7_saves" } };
            check(AgentHarnessService.isActive() === false, "disarms on bookrun owned by player save");

            // Re-bind for disconnect test; disarms immediately if _root.savePath switches to player slot
            _root._saveExt = undefined;
            _root.savePath = "cf7_agent_unit_test";
            _root.gameCommands["agentHarnessCmd"]({
                sub: "bind", requestId: "r5", slot: "cf7_agent_unit_test", sessionEpoch: "e2"
            });
            _root.savePath = "crazyflasher7_saves";
            check(AgentHarnessService.isActive() === false, "disarms on non-agent slot");
            check(AgentHarnessService.sampleMask(null, 105) === 0, "mask zero after disarm");

            AgentHarnessService.onTransportDisconnected();
            check(!AgentHarnessService.isActive(), "clean on disconnect");
            var fixture:Object = {手枪:{name:"战术版MGL",value:{shot:2}}, 手枪弹匣容量:5,
                手枪2:{name:"钛合金P90",value:{shot:-1,ammoState:{chamber:1,ghost:0,reward:0}}}, 手枪2弹匣容量:50,
                __titaniumType61Status:{state:"ONLINE_FULL",capacity:1250,maximum:1250,
                    ammoSynthesized:2,ammoMpSpent:750,baseMpEarned:6,mpSpent:750,healed:0,charged:0}};
            var projection:Object=AgentHarnessService.projectCombatResources(fixture);
            check(projection.weapons.length==2 && projection.weapons[0].shot==2 && projection.weapons[0].capacity==5,"combat snapshot preserves ordinary ammo fields");
            check(projection.weapons[1].shot==-1 && projection.weapons[1].chamber==1,"combat snapshot preserves legal negative shot and chamber");
            check(projection.titanium.ammoSynthesized==2 && projection.titanium.ammoMpSpent==750,"combat snapshot exposes existing authoritative synthesis counters");
            check(fixture.手枪.value.ammoState==undefined && fixture.手枪.value.shot==2,"combat observation never migrates or normalizes ammo state");
            projection.weapons[0].shot=99; projection.titanium.ammoMpSpent=0;
            check(fixture.手枪.value.shot==2 && fixture.__titaniumType61Status.ammoMpSpent==750,"combat snapshot is detached from mutable gameplay objects");
            check(AgentHarnessService.projectCombatResources({}).titanium==null,"missing hero resources project without enabling a set");
            fixture.__unified61Status={state:"BROKEN",capacity:0,maximum:250};
            fixture.__emergencyInjectionMemory={used:true,attempts:2,doses:1,observedDrops:5};
            projection=AgentHarnessService.projectCombatResources(fixture);
            check(projection.unified.capacity==0 && projection.emergencyInjection.doses==1
                && projection.emergencyInjection.crisisUsed && !projection.emergencyInjection.installed,
                "emergency observation reads existing crisis memory without installing an accessor");
            projection.unified.capacity=99; projection.emergencyInjection.doses=99;
            check(fixture.__unified61Status.capacity==0 && fixture.__emergencyInjectionMemory.doses==1,
                "unified and emergency observations are detached and never tick or repair");
        } finally {
            AgentHarnessService.onTransportDisconnected();
            _root.savePath = savedSlot;
            _root._saveExt = savedExt;
            _root.server = savedServer;
            _root.gameCommands = savedCommands;
            _root.帧计时器 = savedTimer;
            if(modeHero) modeHero.removeMovieClip();
            _root.gameworld = savedWorld;
            _root.当前玩家总数 = savedPlayers;
            for(var restoredKey:Number=0;restoredKey<5;restoredKey++) _root["键"+(restoredKey+1)]=savedModeKeys[restoredKey];
            _root.左键 = savedHeroKeys.left;
            _root.右键 = savedHeroKeys.right;
            _root.互动键 = savedHeroKeys.interact;
            _root.武器技能键 = savedHeroKeys.wskill;
        }

        trace("AgentHarnessServiceTest Tests Passed: " + _passed);
        trace("AgentHarnessServiceTest Tests Failed: " + _failed);
        trace("--- AgentHarnessServiceTest: " + _passed + "/" + (_passed + _failed) + " passed, " + _failed + " failed ---");
    }
}
