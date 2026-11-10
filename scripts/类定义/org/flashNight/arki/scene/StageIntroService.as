import org.flashNight.arki.scene.StageReturnFlow;
import org.flashNight.neur.Event.EventBus;

/** World-bound execution permission. No pause lease, reward or window authority. */
class org.flashNight.arki.scene.StageIntroService {
    private static var _installed:Boolean = false;
    private static var _sequence:Number = 0;
    private static var _scope:Object;

    public static function declare(world:Object, descriptor:Object):Void {
        var run:Object = _root._saveExt.bookRun;
        var plan:Object=org.flashNight.arki.scene.BookRunRules.chapterIntro(
            org.flashNight.arki.scene.BookDefinition.get(), descriptor.chapter);
        if (descriptor.kind !== "book_chapter" || plan == null
                || descriptor.bookId !== plan.bookId || descriptor.pageId !== plan.pageId
                || descriptor.bgmLease !== plan.bgmLease || run.bookId !== plan.bookId
                || run.outcome !== "active" || run.slot !== String(_root.savePath)
                || !org.flashNight.arki.scene.BookRunService.isBookStageContext()
                || !org.flashNight.arki.ui.SceneTransitionService.supportsIntroHandoff()) return;
        if (!_installed) {
            _installed = true;
            EventBus.getInstance().subscribe("SceneTransitionReleased", onTimelineReleased, null);
            org.flashNight.arki.interaction.NativeInteractionContext.onSceneTeardown(onTeardown);
        }
        var identity:Object = StageReturnFlow.worldIdentity(world);
        if (current(_scope) && _scope.owner === identity) return;
        retire();
        var scope:Object = {id:"intro:" + (++_sequence), world:world, owner:identity,
            run:org.flashNight.gesh.object.PersistedSnapshot.clone(run), slot:String(_root.savePath),
            chapter:plan.chapter, pageId:plan.pageId,
            state:"loading", narrativeDone:false, surfaceReady:false, chapterStarted:false};
        if (!org.flashNight.arki.ui.SceneTransitionService.bindIntro(scope)) return;
        _scope = scope;
        world.__stageIntroExecutionHeld = true;
        _global.ASSetPropFlags(world,["__stageIntroExecutionHeld"],1,false);
        log(scope, "declared");
    }
    private static function current(scope:Object):Boolean {
        return scope != null && scope.owner != null && scope.world === _root.gameworld
            && scope.owner === _root.gameworld.__stageReturnWorldIdentity
            && scope.slot === String(_root.savePath)
            && org.flashNight.arki.scene.BookRunRules.sameActiveRun(scope.run, _root._saveExt.bookRun);
    }
    public static function active():Object { return current(_scope) ? _scope : null; }
    public static function deferStart(gate:Object):Boolean {
        var scope:Object = active();
        if (scope == null || scope.state == "complete") return false;
        scope.playerGate = gate;
        return true;
    }
    public static function chapterAlreadyStarted(index:Number):Boolean {
        var scope:Object = active();
        return scope != null && scope.chapter === index && scope.chapterStarted === true;
    }
    public static function chapterStarting(index:Number):Void {
        var scope:Object = active();
        if (scope != null && scope.chapter === index) scope.chapterStarted = true;
    }
    public static function canPresentChapter(index:Number):Boolean {
        var scope:Object = active();
        return scope == null || scope.chapter === index && scope.state == "opening";
    }
    public static function comicScope(pageId:String):Object {
        var scope:Object = active();
        return scope != null && scope.pageId === pageId && scope.state == "opening" ? scope : null;
    }
    private static function onTimelineReleased(world:Object, token:String, identity:Object):Void {
        var scope:Object = active();
        if (scope == null || scope.state != "loading" || scope.world !== world || scope.owner !== identity) return;
        scope.state = "opening";
        org.flashNight.arki.ui.SceneTransitionService.publishIntro(scope, "opening");
        org.flashNight.arki.scene.BookRunService.playChapter(scope.chapter);
    }
    public static function prepared(scope:Object):Void {
        if (!current(scope) || scope !== _scope || scope.state != "opening") return;
        scope.state = "narrative";
        org.flashNight.arki.ui.SceneTransitionService.publishIntro(scope, "narrative");
        log(scope, "comic_prepared");
    }
    public static function failed(scope:Object, reason:String):Void {
        if (!current(scope) || scope !== _scope || scope.state == "complete") return;
        scope.state = "failed";
        scope.surfaceReady = false;
        org.flashNight.arki.ui.SceneTransitionService.publishIntro(scope, "failed");
        log(scope, "failed:" + reason);
    }
    public static function interruption(scope:Object):Function {
        return function(reason:String, phase:String):Void {
            org.flashNight.arki.scene.StageIntroService.failed(scope, reason);
        };
    }
    public static function dialogueFollow(index:Number):Object {
        var scope:Object = active();
        if (scope == null || scope.chapter !== index) return null;
        var eventName:String = "__stageIntroNarrative:" + scope.id;
        if (scope.dialogueSubscribed !== true) {
            scope.dialogueSubscribed = true;
            scope.world.dispatcher.subscribeOnce(eventName, completeNarrative, null);
        }
        return {name:eventName, args:[scope]};
    }
    public static function completeNarrative(scope:Object):Void {
        if (!current(scope) || scope !== _scope || scope.state == "failed" || scope.narrativeDone) return;
        scope.narrativeDone = true;
        var manager:Object = org.flashNight.arki.scene.StageManager.instance;
        if (manager != null && typeof manager.noteNarrativeDone == "function") {
            manager.noteNarrativeDone(scope.world, scope.owner, scope.chapter);
        }
        org.flashNight.arki.scene.BookRunService.completeIntroChapter(scope.owner, scope.chapter);
        scope.state = "resume";
        org.flashNight.arki.ui.SceneTransitionService.publishIntro(scope, "resume");
        log(scope, "narrative_complete");
        tryGrant(scope);
    }
    public static function handleReceipt(p:Object):Boolean {
        if (p.kind != "intro_surface" && p.kind != "intro_retry" && p.kind != "intro_return") return false;
        var scope:Object = active();
        if (scope == null || p.introId !== scope.id || p.requestId !== scope.requestId
                || p.revision !== scope.wireRevision) return true;
        if (p.kind == "intro_surface" && (scope.state == "narrative" || scope.state == "resume")) {
            scope.surfaceReady = true;
            log(scope, "surface_ready");
            tryGrant(scope);
        } else if (p.kind == "intro_retry" && scope.state == "failed") {
            scope.state = "opening";
            org.flashNight.arki.ui.SceneTransitionService.publishIntro(scope, "opening");
            org.flashNight.arki.scene.BookRunService.retryIntroChapter(scope.owner, scope.chapter);
        } else if (p.kind == "intro_return" && scope.state == "failed"
                && typeof _root.返回基地 == "function") {
            // Existing return authority owns persistence and navigation, including rejection.
            _root.返回基地();
        }
        return true;
    }
    private static function tryGrant(scope:Object):Void {
        if (!current(scope) || scope !== _scope || scope.state != "resume"
                || scope.narrativeDone !== true || scope.surfaceReady !== true) return;
        scope.state = "complete";
        scope.world.__stageIntroExecutionHeld = false;
        Selection.setFocus(null);
        org.flashNight.arki.scene.BookRunClock.tick();
        org.flashNight.arki.ui.SceneTransitionService.publishIntro(scope, "complete");
        log(scope, "execution_granted");
        var gate:Object = scope.playerGate;
        scope.playerGate = null;
        if (gate != null) gate.manager.onPlayerReady(gate);
    }
    private static function onTeardown():Void { retire(); }
    public static function retire():Void {
        var scope:Object = _scope;
        _scope = null;
        if (scope == null) return;
        if (scope.owner === scope.world.__stageReturnWorldIdentity)
            scope.world.__stageIntroExecutionHeld = false;
        org.flashNight.arki.ui.SceneTransitionService.publishIntro(scope, "cancelled");
    }
    public static function noteStart(phase:String):Void {
        var scope:Object=active();
        if(scope!=null && scope.state=="complete")log(scope,phase);
    }
    private static function log(scope:Object, phase:String):Void {
        if (typeof _root.server.sendServerMessage == "function")
            _root.server.sendServerMessage("[StageIntro] id=" + scope.id + " phase=" + phase);
    }
}
