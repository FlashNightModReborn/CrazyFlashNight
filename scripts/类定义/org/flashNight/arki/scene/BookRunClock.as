import org.flashNight.arki.pause.PauseManager;

/** 竞速只累计未暂停的游戏时间；漫画、对白、过场及商店共用暂停权威。 */
class org.flashNight.arki.scene.BookRunClock {
    private static var _installed:Boolean = false;
    private static var _session:Object;
    private static var _watch:MovieClip;

    public static function install():Void {
        if (_installed) return;
        _installed = true;
        PauseManager.install();
        PauseManager.subscribe(onPause, null);
    }
    public static function ensureStarted(run:Object):Void {
        if (!matches(run)) start(run);
    }
    public static function start(run:Object):Void {
        install();
        run.playTimeMs = 0;
        run.clockVersion = 1;
        _session = {slot:String(_root.savePath), seed:run.seed, startedAt:run.startedAt,
            bookId:run.bookId, last:getTimer(), elapsed:0, paused:_root.暂停 === true};
        if (_watch == null || _watch._name == undefined)
            _watch = _root.createEmptyMovieClip("__bookRunClock", _root.getNextHighestDepth());
        _watch.onEnterFrame = function():Void { org.flashNight.arki.scene.BookRunClock.tick(); };
    }
    private static function matches(run:Object):Boolean {
        var s:Object = _session;
        return s != null && run != null && s.slot === String(_root.savePath) && run.slot === s.slot
            && run.seed === s.seed && run.startedAt === s.startedAt && run.bookId === s.bookId;
    }
    /** 单独的积分函数让暂停边界可用确定性毫秒序列测试，无需真实等待。 */
    public static function accumulate(state:Object, now:Number, nextPaused:Boolean):Number {
        var delta:Number = now - state.last;
        if (!state.paused && delta > 0) state.elapsed += delta;
        state.last = now; state.paused = nextPaused;
        return state.elapsed;
    }
    private static function sample(nextPaused:Boolean):Void {
        var run:Object = _root._saveExt.bookRun;
        if (!matches(run) || run.outcome != "active") { _session = null; return; }
        run.playTimeMs = accumulate(_session, getTimer(), nextPaused);
    }
    private static function onPause(value:Boolean, previous:Boolean, owner:String):Void {
        // 此订阅只记时间；不可嵌套增减暂停租约。
        if (_session != null) sample(value === true);
    }
    public static function tick():Void {
        if (_session == null) { delete _watch.onEnterFrame; return; }
        sample(_root.暂停 === true);
    }
    public static function elapsed(run:Object):Number {
        if (matches(run)) sample(_root.暂停 === true);
        if (run.clockVersion === 1 && typeof run.playTimeMs == "number" && !isNaN(run.playTimeMs)
                && run.playTimeMs >= 0) return Math.max(1, run.playTimeMs);
        // 老版本的临时角色没有可恢复的暂停账；保留旧算法，不能伪造更快纪录。
        return Math.max(1, new Date().getTime() - Number(run.startedAt));
    }
}
