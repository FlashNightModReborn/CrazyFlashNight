import org.flashNight.arki.scene.BookComicService;
import org.flashNight.arki.audio.AudioBridge;

/** CF6 只负责路线映射与段落串联；呈现协议和生命周期由 BookComicService 独占。 */
class org.flashNight.arki.scene.Cf6StoryService {
    public static function install():Void {
        BookComicService.install();
    }
    public static function knownPage(page:String):Boolean {
        return BookComicService.isCf6Page(page);
    }
    public static function pagesBeforeChapter(index:Number):Array {
        if (index == 1) return ["cf6-s1"];
        if (index == 2) return ["cf6-s2"];
        if (index == 3) return ["cf6-s3"];
        // S4 enters A07. Only the vehicle authority's completed tail can reach the next A08 chapter.
        if (index == 7) return ["cf6-s4"];
        if (index == 8) return ["cf6-s5"];
        if (index == 18) return ["cf6-s6"];
        return [];
    }
    public static function hasChapterStory(index:Number):Boolean {
        return pagesBeforeChapter(index).length > 0;
    }
    public static function beginChapter(index:Number, continuation:Function, interruption:Function):Boolean {
        return beginSequence(pagesBeforeChapter(index), continuation, interruption);
    }
    public static function beginFinal(continuation:Function, interruption:Function):Boolean {
        return beginSequence(["cf6-s7", "cf6-end"], continuation, interruption);
    }
    public static function begin(pageId:String, continuation:Function, interruption:Function):Boolean {
        return beginSequence([pageId], continuation, interruption);
    }
    public static function beginSequence(pageIds:Array, continuation:Function, interruption:Function):Boolean {
        if (pageIds == null || pageIds.length == 0) return false;
        var pages:Array = pageIds.slice(0);
        for (var i:Number = 0; i < pages.length; i++) if (!knownPage(pages[i])) return false;
        var state:Object = {done:false, continuation:continuation, interruption:interruption,
            leaseRequestId:null, leaseStatus:"pending", prepared:[]};
        var requestId:String = AudioBridge.acquireBgmLease(leaseCallback(state));
        if (state.leaseRequestId == null) state.leaseRequestId = requestId;
        if (requestId == null && state.leaseStatus == "pending") settleLease(state, false);
        var opened:Boolean = BookComicService.begin(pages[0],
            sequenceContinuation(pages, 1, state), sequenceInterruption(state), preparation(state));
        if (!opened) finishSequence(state, "open_failed", "sequence", true);
        return opened;
    }
    private static function leaseCallback(state:Object):Function {
        return function(result:Object, isLatest:Boolean):Void {
            if (state.done || result == null) return;
            state.leaseRequestId = result.requestId;
            if (result.completionState == "accepted_deferred") return;
            org.flashNight.arki.scene.Cf6StoryService.settleLease(state, result.category == "ok");
        };
    }
    private static function settleLease(state:Object, acquired:Boolean):Void {
        if (state.done || state.leaseStatus != "pending") return;
        state.leaseStatus = acquired ? "acquired" : "unavailable";
        resolvePrepared(state);
    }
    private static function preparation(state:Object):Object {
        return {
            prepare:function(s:Object, p:Object):Boolean {
                if (state.done) return true;
                state.prepared.push({session:s, packet:p});
                org.flashNight.arki.scene.Cf6StoryService.resolvePrepared(state);
                return true;
            },
            tick:function(s:Object):Void {
                if (!state.done && state.leaseStatus == "pending"
                        && getTimer() - s.began >= 2000) {
                    org.flashNight.arki.scene.Cf6StoryService.settleLease(state, false);
                }
            }
        };
    }
    private static function resolvePrepared(state:Object):Void {
        if (state.done || state.leaseStatus == "pending" || state.prepared == null
                || state.prepared.length == 0) return;
        var pending:Array = state.prepared;
        state.prepared = [];
        var error:String = state.leaseStatus == "acquired" ? "" : "bgm_lease_unavailable";
        BookComicService.completePrepared(pending[0].session, pending[0].packet, error);
        for (var i:Number = 1; i < pending.length; i++) {
            BookComicService.handle("prepared", pending[i].packet);
        }
    }
    private static function sequenceContinuation(pages:Array, position:Number, state:Object):Function {
        return function(reason:String, phase:String):Void {
            if (state.done || (reason != "continue" && reason != "skip")) return;
            if (position >= pages.length) {
                org.flashNight.arki.scene.Cf6StoryService.finishSequence(state, reason, phase, false);
                return;
            }
            if (!BookComicService.begin(pages[position],
                    org.flashNight.arki.scene.Cf6StoryService.sequenceContinuation(pages, position + 1, state),
                    org.flashNight.arki.scene.Cf6StoryService.sequenceInterruption(state),
                    org.flashNight.arki.scene.Cf6StoryService.preparation(state))) {
                org.flashNight.arki.scene.Cf6StoryService.finishSequence(state, "open_failed", "sequence", true);
            }
        };
    }
    private static function sequenceInterruption(state:Object):Function {
        return function(reason:String, phase:String):Void {
            org.flashNight.arki.scene.Cf6StoryService.finishSequence(state, reason, phase, true);
        };
    }
    private static function finishSequence(
            state:Object, reason:String, phase:String, interrupted:Boolean):Void {
        if (state.done) return;
        state.done = true;
        state.prepared = null;
        if (state.leaseRequestId != null) {
            AudioBridge.releaseBgmLease(state.leaseRequestId, null);
            state.leaseRequestId = null;
        }
        var follow:Function = interrupted ? state.interruption : state.continuation;
        state.continuation = null;
        state.interruption = null;
        if (follow != null) follow(reason, phase);
    }
}
