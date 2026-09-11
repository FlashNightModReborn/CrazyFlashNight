import org.flashNight.arki.scene.StageRunSession;
import org.flashNight.arki.scene.StageReturnFlow;
import org.flashNight.arki.scene.SceneTransitionGuard;
import org.flashNight.arki.scene.StageReturnSelection;
import org.flashNight.arki.scene.StageReturnOptions;
import org.flashNight.arki.map.MapDomainBridge;
import org.flashNight.arki.task.TaskUtil;
import org.flashNight.arki.task.TaskDestinationOptions;
import org.flashNight.arki.task.TaskDeliverySelection;

class org.flashNight.arki.scene.StageReturnFlowTest {
    private static var passed:Number = 0;
    private static var failed:Number = 0;
    private static function check(value:Boolean, label:String):Void {
        if (value) passed++; else { failed++; trace("[TEST_FAIL] StageReturnFlow " + label); }
    }
    private static function reset():Void {
        StageRunSession.resetForRestart();
        _root._saveExt = {};
        _root.当前为战斗地图 = false;
        _root._webPanelPauseLease = undefined;
        _root.场景转换中 = false;
        _root.gameworld = {场景名:"地图-联合大学"};
        var startToken:String = StageRunSession.reserveStageStart("return_test", "大学城周边", "简单");
        StageRunSession.begin("大学城周边", "简单", startToken);
        StageRunSession.finish("victory");
        _root.当前为战斗地图 = true;
    }
    private static function arrived(world:Object, token:String):Boolean {
        return StageReturnFlow.confirmArrival(world, token, StageReturnFlow.worldIdentity(world));
    }
    private static function arrival():Void {
        reset();
        _root.当前为战斗地图 = false;
        var origin:Object = StageReturnFlow.captureOrigin();
        check(origin.frame === "地图-联合大学", "origin is the real scene, independent of stage StartFrame");
        StageReturnFlow.begin(origin);
        _root.关卡地图帧值 = "基地1层";
        check(StageReturnFlow.destination("基地1层") === "地图-联合大学", "normal return keeps university origin");
        StageReturnFlow.select({frame:"地图-彩蛋地图"});
        check(StageReturnFlow.destination("基地1层") === "地图-彩蛋地图", "explicit selection overrides origin");
        StageReturnFlow.setStoryReturn(37);
        check(StageReturnFlow.destination("基地1层") === 37, "effective story wins and preserves numeric frame type");
        StageReturnFlow.begin(origin);
        var oldWorld:Object = _root.gameworld;
        var token:String = StageReturnFlow.prepareTransition("地图-联合大学");
        check(!StageReturnFlow.beginSceneLoad(token, "地图-联合大学"), "unaccepted fade cannot start a load");
        check(!arrived(oldWorld, token), "old world never confirms arrival");
        StageReturnFlow.acceptTransition(token);
        check(!StageReturnFlow.beginSceneLoad("old.token", "地图-联合大学"), "late fade token is refused");
        check(!StageReturnFlow.beginSceneLoad(token, "基地1层"), "wrong target is refused");
        check(StageReturnFlow.beginSceneLoad(token, "地图-联合大学"), "accepted exact target starts loading");
        var wrong:Object = StageReturnFlow.sceneInit("基地场景-基地1层");
        check(wrong.__stageReturnToken == undefined, "a different scene does not inherit the arrival token");
        var next:Object = StageReturnFlow.sceneInit("地图-联合大学");
        _root.gameworld = next;
        check(!arrived(next, "old.token"), "stale SceneReady cannot open rewards");
        _root.当前为战斗地图 = true;
        check(!arrived(next, token), "battle scene cannot acknowledge ordinary return");
        _root.当前为战斗地图 = false;
        check(arrived(next, token), "new exact world acknowledges arrival");
        check(arrived(undefined, undefined), "explicit reward resume reuses the confirmed world");
        check(!arrived(oldWorld, token), "late old world is still rejected after arrival");
        check(StageReturnFlow.destination("fallback") === "地图-联合大学", "arrival consumes selected plan without discarding origin");

        StageReturnFlow.restorePending();
        check(!arrived(next, token), "restart does not adopt the old world as new arrival");
        var restoredWorld:Object = {场景名:"基地场景-基地1层"}; _root.gameworld = restoredWorld;
        check(arrived(restoredWorld, undefined), "restored rewards may appear at the normal save entry");
        check(StageReturnFlow.destination("基地1层") === "基地1层", "restart never restores an automatic navigation destination");
        _root.gameworld = {场景名:"基地场景-基地房顶"};
        check(StageReturnFlow.captureOrigin().frame === "基地房顶", "base wrapper normalizes to the real rooftop frame");
    }
    /** 真实 AVM1 MovieClip 重建；普通 Object fixture 不具备影片剪辑路径引用语义。 */
    private static function movieClipArrival():Void {
        reset();
        var fixture:MovieClip = _root.createEmptyMovieClip("__stageReturnFixture", _root.getNextHighestDepth());
        var oldWorld:MovieClip = fixture.createEmptyMovieClip("world", 1);
        oldWorld.场景名 = "战斗场景";
        _root.gameworld = oldWorld;
        var token:String = StageReturnFlow.prepareTransition("地图-联合大学");
        StageReturnFlow.acceptTransition(token);
        StageReturnFlow.beginSceneLoad(token, "地图-联合大学");
        oldWorld.removeMovieClip();
        var next:MovieClip = fixture.createEmptyMovieClip("world", 1);
        var init:Object = StageReturnFlow.sceneInit("地图-联合大学");
        for (var key:String in init) next[key] = init[key];
        _root.gameworld = next;
        _root.当前为战斗地图 = false;
        trace("[StageReturnMovieClipProbe] oldEqualsNew=" + (oldWorld === next)
            + " oldUndefined=" + (oldWorld == undefined) + " token=" + next.__stageReturnToken);
        var readyIdentity:Object = StageReturnFlow.worldIdentity(next);
        check(!StageReturnFlow.confirmArrival(next, token, undefined), "real arrival requires captured identity");
        check(StageReturnFlow.confirmArrival(next, token, readyIdentity), "real MovieClip replacement confirms arrival");
        check(StageReturnFlow.confirmArrival(undefined, undefined, undefined), "confirmed real world permits explicit resume");
        StageReturnFlow.restorePending();
        next.removeMovieClip();
        var restored:MovieClip = fixture.createEmptyMovieClip("world", 1);
        restored.场景名 = "地图-联合大学";
        _root.gameworld = restored;
        var restoredIdentity:Object = StageReturnFlow.worldIdentity(restored);
        check(!StageReturnFlow.confirmArrival(next, token, readyIdentity), "same-path stale event cannot restore new scene");
        check(StageReturnFlow.confirmArrival(restored, undefined, restoredIdentity), "real MovieClip replacement restores pending rewards");
        restored.removeMovieClip();
        var later:MovieClip = fixture.createEmptyMovieClip("world", 1);
        later.场景名 = "地图-联合大学";
        _root.gameworld = later;
        check(!StageReturnFlow.confirmArrival(restored, undefined, restoredIdentity), "same-path stale event cannot reuse arrival");
        check(!StageReturnFlow.confirmArrival(undefined, undefined, undefined), "unconfirmed replacement cannot inherit explicit resume");
        check(StageReturnFlow.confirmArrival(later, undefined, StageReturnFlow.worldIdentity(later)), "fresh ready event confirms an ordinary later scene");
        fixture.removeMovieClip();
    }
    private static function loadFailure():Void {
        reset();
        StageReturnFlow.begin({frame:"地图-联合大学"});
        StageReturnFlow.select({frame:"地图-彩蛋地图"});
        var oldToken:String = StageReturnFlow.prepareTransition("地图-彩蛋地图");
        StageReturnFlow.acceptTransition(oldToken);
        var oldFade:Object = _root.淡出动画;
        _root.淡出动画 = {淡出跳转帧:function():Boolean { return false; }};
        check(!StageReturnFlow.returnFromLoadFailure("基地1层"), "busy loading-failure return leaves the old plan intact");
        check(StageReturnFlow.beginSceneLoad(oldToken, "地图-彩蛋地图"), "rejected fallback retains retry of the original target");
        _root.淡出动画 = {淡出跳转帧:function(frame, token:String):Boolean {
            _root.__failureFrame = frame; _root.__failureToken = token; return true;
        }};
        check(StageReturnFlow.returnFromLoadFailure("基地1层") && _root.__failureFrame == "地图-联合大学"
            && _root.__failureToken != oldToken, "explicit loading-failure return targets captured origin with a new token");
        check(!StageReturnFlow.beginSceneLoad(oldToken, "地图-彩蛋地图"), "abandoned loading attempt cannot jump later");
        check(StageReturnFlow.beginSceneLoad(_root.__failureToken, "地图-联合大学"), "new fallback loading is accepted");
        _root.gameworld = StageReturnFlow.sceneInit("地图-联合大学");
        _root.当前为战斗地图 = false;
        check(arrived(_root.gameworld, _root.__failureToken), "fallback still requires exact scene arrival");
        _root.淡出动画 = oldFade;
    }
    private static function animatedDoors():Void {
        reset();
        var oldFade:Object = _root.淡出动画;
        var fade:Object = {_currentframe:6, gotoAndStop:function(frame):Void { this.stoppedAt = frame; }};
        _root.淡出动画 = fade;
        var token:String = StageReturnFlow.prepareTransition("基地1层");
        fade.__stageReturnToken = token; fade.跳转帧 = "基地1层";
        var pending:Object = SceneTransitionGuard.captureCleanup();
        check(!StageReturnFlow.canBeginSceneLoad(token, "基地1层"), "unaccepted return fails before teardown");
        StageReturnFlow.acceptTransition(token);
        check(SceneTransitionGuard.allowCleanup(pending), "accepted return admits cleanup of the old world");
        check(StageReturnFlow.sceneInit("基地场景-基地1层").__stageReturnToken == undefined,
            "cleanup admission alone does not mark arrival loading");
        check(!SceneTransitionGuard.prepareDoor("佣兵酒吧"), "ordinary door cannot replace a pending task return");
        check(fade.__stageReturnToken === token && fade.跳转帧 == "基地1层", "refused door preserves pending return");
        StageReturnFlow.beginSceneLoad(token, "基地1层");
        _root.gameworld = StageReturnFlow.sceneInit("基地场景-基地1层");
        _root.当前为战斗地图 = false;
        check(arrived(_root.gameworld, token), "battle return reaches the base before opening a door");
        check(fade.__stageReturnToken == undefined, "arrival consumes the shared fade token");
        check(!StageReturnFlow.beginSceneLoad(token, "基地1层"), "consumed token still cannot start another load");
        // 复现旧存量 token；双开门只会直接播放淡出时间线，不调用淡出跳转帧。
        fade.__stageReturnToken = token;
        check(SceneTransitionGuard.prepareDoor("佣兵酒吧"), "animated tavern door accepts an ordinary transition");
        check(fade.__stageReturnToken == undefined && fade.跳转帧 == "佣兵酒吧" && fade.__returnFadeActive === true,
            "door replaces stale token and reserves the fade before its animation");
        check(!SceneTransitionGuard.prepareDoor("医务室") && fade.跳转帧 == "佣兵酒吧", "second door cannot overwrite the first opening animation");
        var door:Object = SceneTransitionGuard.captureCleanup();
        check(SceneTransitionGuard.allowCleanup(door), "tavern cleanup is admitted without a return token");
        check(StageReturnFlow.beginSceneLoad(fade.__stageReturnToken, fade.跳转帧), "animated door reaches the tavern in one load");
        _root.gameworld = StageReturnFlow.sceneInit("基地场景-佣兵酒吧");
        check(arrived(_root.gameworld, undefined), "ordinary tavern arrival remains compatible with reward resume");
        fade.__returnFadeActive = false;
        check(SceneTransitionGuard.prepareDoor("基地1层"), "walking back from the tavern is still available");
        check(StageReturnFlow.beginSceneLoad(fade.__stageReturnToken, fade.跳转帧), "tavern exit remains an ordinary load");
        fade.__returnFadeActive = false;
        fade.跳转中标签 = {};
        check(!SceneTransitionGuard.prepareDoor("医务室"), "authored busy marker also blocks an overlapping door");
        _root.淡出动画 = oldFade;
    }
    private static function cleanupIdentity():Void {
        reset();
        StageReturnFlow.reset();
        var oldFade:Object = _root.淡出动画;
        var oldMessage:Function = _root.发布消息;
        _root.发布消息 = function(text:String):Void { trace(text); };
        var fade:Object = {_currentframe:6, 跳转帧:"佣兵酒吧", __stageReturnToken:"expired.return",
            __returnFadeActive:true, gotoAndStop:function(frame):Void { this.stoppedAt = frame; }};
        _root.淡出动画 = fade;
        var fixture:MovieClip = _root.createEmptyMovieClip("__cleanupFixture", _root.getNextHighestDepth());
        var first:MovieClip = fixture.createEmptyMovieClip("world", 1);
        first.场景名 = "基地场景-基地1层";
        _root.gameworld = first;
        var firstIdentity:Object = StageReturnFlow.worldIdentity(first);
        var stale:Object = SceneTransitionGuard.captureCleanup();
        check(!SceneTransitionGuard.allowCleanup(stale), "invalid return token is rejected before teardown");
        check(_root.gameworld === first && StageReturnFlow.worldIdentity(_root.gameworld) === firstIdentity,
            "rejected fade retains the actual live MovieClip");
        check(fade.stoppedAt == "空" && fade.__returnFadeActive === false, "rejected fade removes the black cover and releases busy state");
        check(SceneTransitionGuard.prepareDoor("佣兵酒吧"), "ordinary door can be retried after an invalid stale fade");
        var waiting:Object = SceneTransitionGuard.captureCleanup();
        check(SceneTransitionGuard.isCurrent(waiting), "blocked cleanup can retry its current scene and fade");
        first.removeMovieClip();
        var second:MovieClip = fixture.createEmptyMovieClip("world", 1);
        second.场景名 = "基地场景-基地1层";
        _root.gameworld = second;
        check(!SceneTransitionGuard.isCurrent(waiting), "same-path replacement invalidates a queued teardown");
        fade.stoppedAt = undefined;
        check(!SceneTransitionGuard.allowCleanup(waiting) && fade.stoppedAt == undefined && _root.gameworld === second,
            "late cleanup neither destroys the replacement world nor stops its fade");
        var newer:Object = SceneTransitionGuard.captureCleanup();
        check(SceneTransitionGuard.allowCleanup(newer), "fresh request can clean the replacement scene");
        check(!SceneTransitionGuard.ownsFade(waiting), "old callback cannot resume a newly registered fade");
        fade.跳转帧 = "医务室";
        check(!SceneTransitionGuard.isCurrent(newer), "changed destination invalidates cleanup retry");
        fade.跳转帧 = "佣兵酒吧"; fade.__stageReturnToken = "new.return";
        check(!SceneTransitionGuard.isCurrent(newer), "changed token invalidates cleanup retry");
        fade.__stageReturnToken = undefined; fade._currentframe = 13;
        check(!SceneTransitionGuard.isCurrent(newer), "advanced timeline cannot be restarted by an old cleanup retry");
        fixture.removeMovieClip();
        _root.淡出动画 = oldFade; _root.发布消息 = oldMessage;
    }
    private static function lastMessage():Object {
        return _root.__returnTestMessages[_root.__returnTestMessages.length - 1];
    }
    private static function choose():Object {
        StageReturnSelection.open();
        var token:String = String(lastMessage().initData.token);
        StageReturnSelection.snapshot({task:"cmd", action:"stageReturnSnapshot", callId:1, token:token});
        return {task:"cmd", action:"stageReturnConfirm", callId:2, token:token,
            taskId:"2", npcId:"university_npc", placementId:"university_place", locationId:"university"};
    }
    private static function selection():Void {
        var bridge:Object = MapDomainBridge;
        var original:Object = {snapshot:bridge.snapshot,getProjection:bridge.getProjection,
            getBootstrap:bridge.getBootstrap,resolveReturnPlan:bridge.resolveReturnPlan};
        var oldTasks:Object = TaskUtil.tasks;
        bridge.snapshot = function(done:Function, ids:Array):Void { done(true, ""); };
        bridge.getProjection = function():Object { return _root.__returnTestProjection; };
        bridge.getBootstrap = function():Object { return {frames:{base:"基地1层",university:"地图-联合大学"}}; };
        bridge.resolveReturnPlan = function(intent:Object, done:Function, guard:Function):Void {
            _root.__returnTestQueries++;
            _root.__returnTestQuery = {intent:intent,done:done,guard:guard};
        };
        reset();
        _root.__returnTestQueries = 0;
        _root.__returnTestReturns = 0;
        _root.__returnTestMessages = [];
        _root.server = {sendSocketMessage:function(wire:String):Void {
            _root.__returnTestMessages.push(new LiteJSON().parse(wire));
        }};
        _root.返回基地 = function():Boolean { _root.__returnTestReturns++; return true; };
        _root.taskCompleteCheck = function(index:Number):Boolean { return _root.tasks_to_do[index].done === true; };
        _root.tasks_to_do = [{id:"1",done:true},{id:"2",done:true},{id:"3",done:false}];
        TaskUtil.tasks = {};
        TaskUtil.tasks["1"] = {title:"基地任务"}; TaskUtil.tasks["2"] = {title:"大学任务"}; TaskUtil.tasks["3"] = {title:"未完成任务"};
        _root.__returnTestProjection = {taskEndpoints:{}};
        _root.__returnTestProjection.taskEndpoints["1"] = {finish:{npcId:"base_npc",npcName:"基地交付人",placementId:"base_place",locationId:"base",returnNavigable:true}};
        _root.__returnTestProjection.taskEndpoints["2"] = {finish:{npcId:"university_npc",npcName:"大学交付人",placementId:"university_place",locationId:"university",returnNavigable:true}};
        var params:Object = choose();
        check(lastMessage().choices.length == 2, "picker lists actually complete tasks only");
        check(lastMessage().choices[1].taskId == "2", "task identity is retained even behind an earlier base task");
        params.placementId = "base_place";
        StageReturnSelection.confirm(params);
        check(_root.__returnTestQueries == 0 && lastMessage().success === false, "forged placement cannot request a plan");
        params.placementId = "university_place";
        StageReturnSelection.confirm(params);
        var query:Object = _root.__returnTestQuery;
        check(query.intent.taskId == "2" && query.guard(), "confirm asks for the exact chosen task");
        query.done(true, "", {frame:"地图-联合大学"});
        check(lastMessage().closePanel === true && _root.__returnTestReturns == 0, "confirm waits for visible picker close");
        _root._webPanelPauseLease = "picker";
        StageRunSession.onWebPanelClosed();
        check(_root.__returnTestQueries == 1, "held pause blocks return");
        _root._webPanelPauseLease = undefined;
        StageRunSession.onWebPanelClosed();
        check(_root.__returnTestQueries == 2 && _root.__returnTestReturns == 0, "exact close revalidates the same selected endpoint");
        _root.__returnTestQuery.done(true, "", {frame:"地图-联合大学"});
        check(_root.__returnTestReturns == 1 && StageReturnFlow.destination("基地1层") == "地图-联合大学", "one confirmed return uses selected university");
        StageRunSession.onWebPanelClosed();
        check(_root.__returnTestReturns == 1, "duplicate close never returns twice");

        params = choose(); StageReturnSelection.confirm(params); query = _root.__returnTestQuery;
        var oldRunId:String = StageRunSession.getCurrentRunId();
        reset(); StageRunSession.getRunAuthority().runId = oldRunId;
        check(!query.guard(), "same textual run id after activation cannot revive an old callback");
        query.done(true, "", {frame:"基地1层"});
        check(_root.__returnTestReturns == 1 && !StageReturnSelection.isOpen(), "old confirmation neither navigates nor installs a choice");
        params = choose(); StageReturnSelection.confirm(params);
        _root.__returnTestQuery.done(true, "", {frame:"地图-联合大学"});
        _root.tasks_to_do[1].done = false;
        StageRunSession.onWebPanelClosed();
        _root.__returnTestQuery.done(true, "", {frame:"地图-联合大学"});
        check(_root.__returnTestReturns == 1 && !StageReturnSelection.isOpen(), "changed task condition at close cancels the return");
        _root.tasks_to_do[1].done = true;
        params = choose();
        org.flashNight.arki.achievement.AchievementService.testOnlySetCatalog([]);
        org.flashNight.arki.achievement.AchievementService.handleClaim({callId:10, achievementId:"1"});
        check(lastMessage().error == "return_selection_read_only", "picker cannot mutate achievement rewards");
        var beforeQueries:Number = _root.__returnTestQueries;
        StageRunSession.onWebPanelClosed();
        check(_root.__returnTestQueries == beforeQueries && _root.__returnTestReturns == 1,
            "cancelling picker before confirmation performs no plan or return");
        check(_root.tasks_to_do.length == 3 && _root.tasks_to_do[1].done === true,
            "selection never completes or removes a task");
        reset();
        var fixture:MovieClip = _root.createEmptyMovieClip("__returnChoiceFixture", _root.getNextHighestDepth());
        var oldWorld:MovieClip = fixture.createEmptyMovieClip("world", 1);
        _root.gameworld = oldWorld;
        params = choose(); StageReturnSelection.confirm(params); query = _root.__returnTestQuery;
        oldWorld.removeMovieClip();
        _root.gameworld = fixture.createEmptyMovieClip("world", 1);
        check(!query.guard(), "same-path replacement invalidates a pending choice callback");
        query.done(true, "", {frame:"地图-联合大学"});
        check(_root.__returnTestReturns == 1 && !StageReturnSelection.isOpen(), "stale MovieClip choice never starts a return");
        fixture.removeMovieClip();
        for (var key:String in original) bridge[key] = original[key];
        TaskUtil.tasks = oldTasks;
    }
    private static function inlineChoices():Void {
        var bridge:Object = MapDomainBridge;
        var original:Object = {snapshot:bridge.snapshot,getProjection:bridge.getProjection,
            getBootstrap:bridge.getBootstrap,resolveReturnPlan:bridge.resolveReturnPlan};
        var oldTasks:Object = TaskUtil.tasks;
        reset();
        _root.__returnTestReturns = 0; _root.__returnTestQueries = 0; _root.__returnTestMessages = [];
        bridge.snapshot = function(done:Function, ids:Array):Void { _root.__inlineSnapshot = done; };
        bridge.getProjection = function():Object { return _root.__returnTestProjection; };
        bridge.getBootstrap = function():Object {
            var bootstrap:Object = {frames:{base:"基地1层",university:"地图-联合大学"},
                locationByFrame:{}, locationLabels:{base:"基地1层",university:"联合大学"}};
            bootstrap.locationByFrame["地图-联合大学"] = "university"; return bootstrap;
        };
        bridge.resolveReturnPlan = function(intent:Object, done:Function, guard:Function):Void {
            _root.__returnTestQueries++; _root.__returnTestQuery = {intent:intent,done:done,guard:guard};
        };
        _root.返回基地 = function():Boolean { _root.__returnTestReturns++; return true; };
        _root.taskCompleteCheck = function(index:Number):Boolean { return _root.tasks_to_do[index].done === true; };
        _root.tasks_to_do = [{id:"1",done:true},{id:"2",done:true},{id:"3",done:true},{id:"4",done:false}];
        TaskUtil.tasks = {};
        TaskUtil.tasks["1"] = {title:"基地任务"}; TaskUtil.tasks["2"] = {title:"大学任务"};
        TaskUtil.tasks["3"] = {title:"大学任务二"}; TaskUtil.tasks["4"] = {title:"未完成任务"};
        _root.__returnTestProjection = {taskEndpoints:{}};
        _root.__returnTestProjection.taskEndpoints["1"] = {finish:{npcId:"base_npc",npcName:"基地交付人",placementId:"base_place",locationId:"base",returnNavigable:true}};
        _root.__returnTestProjection.taskEndpoints["2"] = {finish:{npcId:"npc",npcName:"Bat",placementId:"place",locationId:"university",returnNavigable:true}};
        _root.__returnTestProjection.taskEndpoints["3"] = {finish:{npcId:"npc",npcName:"Bat",placementId:"place",locationId:"university",returnNavigable:true}};
        _root.__returnTestProjection.taskEndpoints["4"] = {finish:{returnNavigable:true}};
        StageReturnOptions.refresh();
        check(StageReturnOptions.projection().status == "loading", "inline choices wait for fresh task facts");
        _root.__inlineSnapshot(true, "");
        var view:Object = StageReturnOptions.projection();
        check(view.choices.length == 3 && view.choices[0].id == "task.2"
            && view.choices[1].id == "task.3" && view.choices[2].id == "task.1"
            && view.choices[0].taskName == "大学任务" && view.choices[0].npcName == "Bat"
            && view.choices[0].locationName == "联合大学", "actual origin tasks first with stable queue order and full display facts");
        check(_root.__returnTestReturns == 0 && _root.__returnTestMessages.length == 0,
            "default projection neither returns nor opens a Web panel");
        check(!StageReturnOptions.confirm("old.token", "task.2").success && _root.__returnTestQueries == 0,
            "stale dropdown token cannot request navigation");
        check(StageReturnOptions.confirm(view.token, "task.2").success && StageReturnOptions.isBusy(),
            "settlement button starts exact endpoint validation");
        check(!StageReturnOptions.confirm(view.token, "task.1").success && !StageRunSession.beginReturnAttempt(),
            "inflight confirmation blocks double clicks and alternate return");
        var query:Object = _root.__returnTestQuery;
        check(query.guard() && query.intent.taskId == "2" && query.intent.placementId == "place", "selected row retains endpoint authority");
        query.done(true, "", {frame:"地图-联合大学"});
        check(_root.__returnTestReturns == 1 && StageReturnFlow.destination("基地1层") == "地图-联合大学",
            "one fresh response directly starts one formal return");
        query.done(true, "", {frame:"基地1层"});
        check(_root.__returnTestReturns == 1, "duplicate callback never navigates again");
        StageReturnOptions.reset(); StageReturnOptions.refresh(); _root.__inlineSnapshot(true, "");
        view = StageReturnOptions.projection(); StageReturnOptions.confirm(view.token, "task.2");
        query = _root.__returnTestQuery;
        _root.tasks_to_do[1].done = false;
        query.done(true, "", {frame:"地图-联合大学"});
        check(_root.__returnTestReturns == 1 && StageReturnOptions.projection().status == "error", "completion lost while resolving cancels delivery");
        _root.tasks_to_do[1].done = true;
        StageReturnOptions.reset(); StageReturnOptions.refresh(); _root.__inlineSnapshot(true, "");
        view = StageReturnOptions.projection(); StageReturnOptions.confirm(view.token, "task.1");
        query = _root.__returnTestQuery;
        var oldId:String = StageRunSession.getCurrentRunId();
        reset(); StageRunSession.getRunAuthority().runId = oldId;
        check(!query.guard(), "same textual run id cannot reuse a previous dropdown confirmation");
        query.done(true, "", {frame:"基地1层"});
        check(_root.__returnTestReturns == 1, "old run callback does not navigate");
        StageReturnOptions.refresh(); var oldSnapshot:Function = _root.__inlineSnapshot;
        StageReturnOptions.reset(); StageReturnOptions.refresh();
        oldSnapshot(true, "");
        check(StageReturnOptions.projection().status == "loading", "old snapshot cannot overwrite new options");
        _root.__inlineSnapshot(true, "");
        for (var i:Number = 0; i < _root.tasks_to_do.length; i++) _root.tasks_to_do[i].done = false;
        StageReturnOptions.reset(); StageReturnOptions.refresh(); _root.__inlineSnapshot(true, "");
        check(StageReturnOptions.projection().status == "ready" && StageReturnOptions.projection().choices.length == 0,
            "no deliverable task projects no dropdown choices");
        _root.tasks_to_do[1].done = true;
        StageReturnOptions.onMapProjection();
        check(StageReturnOptions.projection().choices.length == 1, "post-victory task progress updates choices from accepted map facts");
        var stableToken:String = StageReturnOptions.projection().token;
        StageReturnOptions.onMapProjection();
        check(StageReturnOptions.projection().token == stableToken, "unchanged map facts do not replace user options");
        StageReturnOptions.reset(); StageReturnOptions.refresh(); _root.__inlineSnapshot(false, "map_facts_stale");
        check(StageReturnOptions.projection().status == "error" && !StageReturnOptions.isBusy(), "snapshot failure stays recoverable without navigation");
        StageReturnFlow.setStoryReturn(37);
        check(StageReturnOptions.projection().status == "none", "story return suppresses task dropdown");
        StageReturnOptions.reset();
        for (var key:String in original) bridge[key] = original[key];
        TaskUtil.tasks = oldTasks;
    }
    private static function dailyAction(token:String, choice:String):Object {
        return {task:"cmd",action:"taskDeliveryAction",v:1,intent:"navigate",choicesToken:token,choiceId:choice};
    }
    private static function dailyChoices():Void {
        var bridge:Object = MapDomainBridge;
        var original:Object = {snapshot:bridge.snapshot,getProjection:bridge.getProjection,getBootstrap:bridge.getBootstrap,
            getProjectionToken:bridge.getProjectionToken,getSceneEpoch:bridge.getSceneEpoch,navigate:bridge.navigate};
        var oldTasks:Object = TaskUtil.tasks, oldServer:Object = _root.server;
        StageRunSession.resetForRestart(); _root._saveExt = {};
        _root.当前为战斗地图 = false; _root.场景转换中 = false; _root._webPanelPauseLease = undefined;
        _root.gameworld = {场景名:"地图-联合大学"};
        _root.__dailyEpoch = 1; _root.__dailySession = "session.1"; _root.__dailyNavigation = 0; _root.__dailyPushes = 0;
        _root.server = {isSocketConnected:true,sendTaskToNode:function(task:String,payload:Object):Void {
            if (task == "task_delivery") { _root.__dailyPayload = payload; _root.__dailyPushes++; }
        }};
        bridge.getProjection = function():Object { return _root.__dailyProjection; };
        bridge.getBootstrap = function():Object { return {locationLabels:{base:"基地1层",university:"联合大学"}}; };
        bridge.getProjectionToken = function():String { return _root.__dailySession; };
        bridge.getSceneEpoch = function():Number { return _root.__dailyEpoch; };
        bridge.snapshot = function(done:Function):Void { done(true, ""); };
        bridge.navigate = function(intent:Object,done:Function,guard:Function):Void {
            _root.__dailyNavigation++; _root.__dailyQuery = {intent:intent,done:done,guard:guard};
        };
        _root.taskCompleteCheck = function(index:Number):Boolean { return _root.tasks_to_do[index].done === true; };
        _root.tasks_to_do = [{id:"1",done:true},{id:"2",done:true},{id:"3",done:true},{id:"4",done:false}];
        TaskUtil.tasks = {};
        var endpoints:Object = {};
        for (var i:Number = 1; i <= 4; i++) {
            TaskUtil.tasks[String(i)] = {title:"交付任务" + i};
            endpoints[String(i)] = {finish:{npcId:"npc" + i,npcName:"交付人" + i,placementId:"place" + i,
                locationId:i == 1 ? "base" : "university",navigable:i != 3,returnNavigable:true}};
        }
        _root.__dailyProjection = {currentLocationId:"university",taskEndpoints:endpoints};
        var rows:Object = TaskDestinationOptions.build("university", false);
        check(rows.rows.length == 2 && rows.rows[0].id == "task.2" && rows.rows[1].id == "task.1",
            "daily choices use actual region then queue order and exclude unavailable or incomplete tasks");
        check(TaskDestinationOptions.build("university", true).rows.length == 3,
            "shared builder keeps ordinary navigation and victory return permissions distinct");
        TaskDeliverySelection.install(); TaskDeliverySelection.onMapProjection();
        var view:Object = _root.__dailyPayload; var token:String = view.options.token;
        check(view.options.choices[0].taskName == "交付任务2" && view.options.choices[0].locationName == "联合大学"
            && _root.__dailyNavigation == 0, "ordinary projection has display facts without navigation or reward");
        var pushes:Number = _root.__dailyPushes;
        TaskDeliverySelection.onMapProjection();
        check(_root.__dailyPushes == pushes, "unchanged daily projection does not churn dropdown state");
        _root.gameCommands.taskDeliverySync({v:1});
        check(_root.__dailyPushes == pushes + 1 && _root.__dailyPayload.options.token == token,
            "reconnecting HUD receives unchanged current choices again");
        var bad:Object = dailyAction(token, "task.2"); bad.extra = true;
        TaskDeliverySelection.handleAction(bad);
        TaskDeliverySelection.handleAction(dailyAction("stale", "task.2"));
        check(_root.__dailyNavigation == 0, "extra fields and old tokens cannot navigate");
        TaskDeliverySelection.handleAction(dailyAction(token, "task.1"));
        var query:Object = _root.__dailyQuery;
        check(_root.__dailyNavigation == 1 && query.guard() && query.intent.kind == "task_delivery"
            && query.intent.taskId == "1" && query.intent.placementId == "place1",
            "explicit ordinary choice keeps its exact task and placement instead of local default");
        TaskDeliverySelection.handleAction(dailyAction(token, "task.2"));
        check(_root.__dailyNavigation == 1 && _root.__dailyPayload.options.status == "confirming", "daily double click is blocked");
        _root.tasks_to_do.reverse();
        check(query.guard(), "queue reorder does not reinterpret selected task ID as an index");
        _root.tasks_to_do[3].done = false;
        check(!query.guard(), "lost completion rejects a delayed navigation response");
        query.done(false, "task_not_deliverable");
        view = _root.__dailyPayload;
        check(view.options.status == "ready" && view.options.token != token && view.options.choices.length == 1,
            "denied choice recovers with fresh remaining tasks and no reward mutation");
        TaskDeliverySelection.handleAction(dailyAction(view.options.token, "task.2")); query = _root.__dailyQuery;
        _root._webPanelPauseLease = {};
        check(!query.guard(), "Web pause invalidates inflight ordinary navigation");
        _root._webPanelPauseLease = undefined;
        query.done(true, ""); token = _root.__dailyPayload.options.token;
        var navigation:Number = _root.__dailyNavigation;
        TaskDeliverySelection.handleAction(dailyAction(view.options.token, "task.2"));
        check(_root.__dailyNavigation == navigation && token != view.options.token,
            "same-location completion consumes the old confirmation token");
        TaskDeliverySelection.handleAction(dailyAction(token, "task.2")); query = _root.__dailyQuery;
        var fixture:MovieClip = _root.createEmptyMovieClip("__dailyWorldFixture", _root.getNextHighestDepth());
        _root.gameworld = fixture.createEmptyMovieClip("world", 1);
        TaskDeliverySelection.onMapProjection(); view = _root.__dailyPayload;
        query.done(true, "");
        check(_root.__dailyPayload === view, "old world callback cannot replace a new daily view");
        TaskDeliverySelection.handleAction(dailyAction(view.options.token, "task.2")); query = _root.__dailyQuery;
        _root.gameworld.removeMovieClip(); _root.gameworld = fixture.createEmptyMovieClip("world", 1);
        check(!query.guard(), "same-path MovieClip replacement invalidates ordinary delivery selection");
        fixture.removeMovieClip(); _root.gameworld = {场景名:"地图-联合大学"};
        TaskDeliverySelection.onMapProjection(); view = _root.__dailyPayload;
        TaskDeliverySelection.handleAction(dailyAction(view.options.token, "task.2")); query = _root.__dailyQuery;
        _root.tasks_to_do = _root.tasks_to_do.concat([]);
        check(!query.guard(), "save reload invalidates selection even with identical textual task IDs");
        TaskDeliverySelection.onMapProjection();
        var fresh:Object = _root.__dailyPayload;
        query.done(true, "");
        check(_root.__dailyPayload === fresh, "old save callback cannot overwrite current choices");
        TaskDeliverySelection.handleAction(dailyAction(fresh.options.token, "task.2")); query = _root.__dailyQuery;
        _root.__dailySession = "new-session.1";
        check(!query.guard(), "map session change invalidates inflight selection");
        TaskDeliverySelection.onMapProjection(); view = _root.__dailyPayload;
        TaskDeliverySelection.handleAction(dailyAction(view.options.token, "task.2")); query = _root.__dailyQuery;
        _root.__dailyEpoch++;
        check(!query.guard(), "new scene epoch invalidates an old navigation result");
        _root.当前为战斗地图 = true;
        TaskDeliverySelection.onMapProjection();
        check(_root.__dailyPayload.options.status == "none", "combat suppresses ordinary delivery controls");
        _root.当前为战斗地图 = false;
        for (i = 0; i < _root.tasks_to_do.length; i++) _root.tasks_to_do[i].done = false;
        TaskDeliverySelection.onMapProjection();
        check(_root.__dailyPayload.options.status == "ready" && _root.__dailyPayload.options.choices.length == 0,
            "no completed task produces no daily selector");
        _root.server = oldServer; TaskUtil.tasks = oldTasks;
        for (var key:String in original) bridge[key] = original[key];
    }
    public static function runAllTests():Void {
        passed = failed = 0;
        arrival(); movieClipArrival(); loadFailure(); animatedDoors(); cleanupIdentity(); selection(); inlineChoices(); dailyChoices();
        StageRunSession.resetForRestart();
        trace("StageReturnFlowTest Tests Passed: " + passed);
        trace("StageReturnFlowTest Tests Failed: " + failed);
    }
}
