import org.flashNight.arki.ui.NativeGuidanceService;

/** Focused U8 trigger/lifetime tests; socket is replaced, no player save or task writes. */
class org.flashNight.arki.ui.NativeGuidanceServiceTest {
    private static var passed:Number = 0;
    private static var failed:Number = 0;
    private static var frames:Array;
    private static var helpAllowed:Boolean;
    private static function check(ok:Boolean, label:String):Void {
        if (ok) passed++; else { failed++; trace("[TEST_FAIL] " + label); }
    }
    public static function runAllTests():Void {
        passed = 0; failed = 0; frames = [];
        var originalPause = _root.暂停;
        var originalCommands = _root.gameCommands;
        var originalWorld = _root.gameworld;
        var originalInteract = _root.互动键;
        var originalKeyShow = _root.keyshow;
        var originalSend:Function = NativeGuidanceService.sendOverride;
        var originalHelpAdmission:Function = NativeGuidanceService.helpAdmissionOverride;
        helpAllowed = true;
        NativeGuidanceService.helpAdmissionOverride = function():Boolean {
            return org.flashNight.arki.ui.NativeGuidanceServiceTest.helpAllowed;
        };
        _root.gameCommands = {};
        NativeGuidanceService.sendOverride = function(payload:Object):Boolean {
            org.flashNight.arki.ui.NativeGuidanceServiceTest.frames.push(payload); return true;
        };
        var files:Array = ["引导-开始游戏","引导-地图传送","引导-战斗","引导-奔跑","引导-拾取","引导-打开箱子","引导-打开箱子2"];
        var ids:Array = ["start","map","combat","run","pickup","crate","crate-safe"];
        for (var i:Number = 0; i < files.length; i++) {
            check(NativeGuidanceService.guideId(files[i]) == ids[i], "legacy mapping " + i);
            check(NativeGuidanceService.show(files[i]), "show " + i);
            var last:Object = frames[frames.length - 1];
            check(last.op == "show" && last.guideId == ids[i] && last.version == 1, "native route " + i);
        }
        check(!NativeGuidanceService.show("unknown"), "unknown guide rejected");
        check(NativeGuidanceService.opacity("pickup", 1, 900) == 0.75, "pickup center");
        check(NativeGuidanceService.opacity("crate-safe", 1, 700) == 0.75, "safe crate center");
        check(NativeGuidanceService.opacity("crate", 1, 0) == 0, "far crate hidden");
        check(NativeGuidanceService.opacity("pickup", 1, Number.NaN) == 0, "missing player hidden");
        check(NativeGuidanceService.opacity("combat", 50, 0) == 0, "fifty-frame delay");
        check(NativeGuidanceService.opacity("run", 120, 0) == 0.7, "fade capped");
        var count:Number = frames.length;
        NativeGuidanceService.handleAction({requestId:"ng:0",sceneId:"foreign",revision:1,verb:"close"});
        check(frames.length == count, "foreign close rejected");
        NativeGuidanceService.clear();
        check(frames[frames.length - 1].op == "hide", "cleanup hides");
        count = frames.length; NativeGuidanceService.tick(); NativeGuidanceService.clear();
        check(frames.length == count, "cleanup stops frame sends");
        _root.gameworld = {};
        org.flashNight.neur.Event.EventBus.getInstance().publish("SceneChanged");
        _root.互动键 = 84;
        _root.keyshow = function(value):String { return "键" + value; };
        NativeGuidanceService.show("引导-打开箱子");
        _root.互动键 = 69; NativeGuidanceService.tick();
        check(frames[frames.length - 1].keys.interact == "键69", "changed binding is republished");
        var current:Object = frames[frames.length - 1];
        NativeGuidanceService.handleAction({requestId:current.requestId,sceneId:current.sceneId,revision:current.revision,verb:"close"});
        check(frames[frames.length - 1].op == "hide", "exact current-world close");
        NativeGuidanceService.show("引导-战斗");current = frames[frames.length - 1];count = frames.length;
        NativeGuidanceService.handleAction({requestId:current.requestId,sceneId:current.sceneId,revision:current.revision + 1,verb:"close"});
        check(frames.length == count, "future close revision rejected");
        NativeGuidanceService.handleAction({requestId:current.requestId,sceneId:current.sceneId,revision:0,verb:"close"});
        check(frames.length == count, "zero close revision rejected");
        _root.互动键 = 70;NativeGuidanceService.tick();
        NativeGuidanceService.handleAction({requestId:current.requestId,sceneId:current.sceneId,revision:current.revision,verb:"close"});
        check(frames[frames.length - 1].op == "hide", "same-request close survives a newer display snapshot");
        count = frames.length;NativeGuidanceService.tick();
        check(frames.length == count, "delayed close stops frame sends");
        NativeGuidanceService.sendOverride = function(payload:Object):Boolean {
            org.flashNight.arki.ui.NativeGuidanceServiceTest.frames.push(payload); return false;
        };
        NativeGuidanceService.show("引导-战斗");current = frames[frames.length - 1];
        NativeGuidanceService.tick();
        check(frames[frames.length - 1].revision == current.revision + 1, "failed snapshot retries with a fresh revision");
        org.flashNight.neur.Event.EventBus.getInstance().publish("SceneChanged");
        check(frames[frames.length - 1].op == "hide", "scene event tears down the guide");
        count = frames.length; NativeGuidanceService.tick();
        check(frames.length == count, "scene teardown stops the frame pump");
        check(!NativeGuidanceService.allowsAutomaticHelp("map", "stage_settlement", "idle", false), "settlement owns help admission before Host request");
        check(!NativeGuidanceService.allowsAutomaticHelp("map", "scene_transition", "idle", false), "scene transition defers help");
        check(!NativeGuidanceService.allowsAutomaticHelp("map", "base_scene", "stage_settlement_active", false), "live loot report defers help");
        check(NativeGuidanceService.allowsAutomaticHelp("start", "stage_run", "idle", false), "ordinary tutorial remains available");
        check(NativeGuidanceService.allowsAutomaticHelp("combat", "stage_settlement", "stage_settlement_active", false), "passive scene diagrams do not acquire help admission");
        check(!NativeGuidanceService.allowsAutomaticHelp("map", "base_scene", "idle", true), "durable rewards do not let help overtake an unpresented report");
        check(NativeGuidanceService.allowsAutomaticHelp("map", "base_scene", "idle", false), "settled report permits a deferred map tutorial");
        check(NativeGuidanceService.allowsAutomaticHelp("combat", "base_scene", "idle", true), "unpresented report does not suppress passive diagrams");
        NativeGuidanceService.sendOverride = function(payload:Object):Boolean {
            org.flashNight.arki.ui.NativeGuidanceServiceTest.frames.push(payload); return true;
        };
        helpAllowed = false;
        NativeGuidanceService.show("引导-地图传送");current = frames[frames.length - 1];
        check(current.opacity == 0, "map tutorial starts dormant during settlement");
        count = frames.length;NativeGuidanceService.tick();
        check(frames.length == count, "dormant tutorial does not flood frame sends");
        helpAllowed = true;NativeGuidanceService.tick();
        var resumed:Object = frames[frames.length - 1];
        check(resumed.opacity == 1 && resumed.requestId == current.requestId, "settled tutorial resumes the same request");
        count = frames.length;NativeGuidanceService.tick();
        check(frames.length == count, "resumed tutorial remains a single presentation");
        helpAllowed = false;org.flashNight.neur.Event.EventBus.getInstance().publish("SceneChanged");
        count = frames.length;helpAllowed = true;NativeGuidanceService.tick();
        check(frames.length == count, "scene teardown cannot resurrect a deferred tutorial");
        check(_root.暂停 === originalPause, "no pause change");
        NativeGuidanceService.sendOverride = originalSend;
        NativeGuidanceService.helpAdmissionOverride = originalHelpAdmission;
        _root.gameCommands = originalCommands;
        _root.gameworld = originalWorld;
        _root.互动键 = originalInteract;
        _root.keyshow = originalKeyShow;
        org.flashNight.neur.Event.EventBus.getInstance().publish("SceneChanged");
        trace("NativeGuidanceServiceTest Tests Passed: " + passed);
        trace("NativeGuidanceServiceTest Tests Failed: " + failed);
    }
}
