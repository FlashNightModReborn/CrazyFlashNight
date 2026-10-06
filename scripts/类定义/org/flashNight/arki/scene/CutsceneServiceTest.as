import org.flashNight.arki.scene.CutsceneService;
import org.flashNight.arki.pause.PauseManager;
import org.flashNight.arki.interaction.NativeInteractionContext;

/**
 * 暂停真值流程 + 现有二进制 SWF 的真实 MovieClipLoader/时间轴收尾。
 * 使用隔离 TestLoader，不进入主游戏、不加载/写入玩家存档。
 * 动画长片除首个摇滚公园自然播放外，跳到真实尾帧执行原结束脚本。
 */
class org.flashNight.arki.scene.CutsceneServiceTest {
    private static var _passed:Number = 0;
    private static var _failed:Number = 0;
    private static var _watch:MovieClip;
    private static var _oldContext:Object;
    private static var _saved:Object;
    private static var _teardowns:Array;
    public static var sceneId:String = "cutscene.test.1";
    private static var _cases:Array;
    private static var _index:Number = -1;
    private static var _case:Object;
    private static var _ticks:Number = 0;
    private static var _phase:Number = 0;
    private static var _session:Object;
    private static var _stale:Object;
    private static var _dialogue:String;
    private static var _finished:Boolean = false;
    private static var _testedMovies:Object = {};
    private static var _testedCount:Number = 0;
    private static var _unloadCalls:Number = 0;
    private static var _expectedDepth:Number;
    private static var _rootKeys:Array = ["暂停", "外部动画加载壳mc", "最上层发布文字提示", "获得翻译"];

    private static function check(value:Boolean, message:String):Void {
        if (value) { _passed++; trace("[PASS] " + message); }
        else { _failed++; trace("[FAIL] " + message); }
    }

    private static function active():Object {
        var cls:Object = CutsceneService;
        return cls["_active"];
    }

    private static function pending():Number {
        var cls:Object = CutsceneService;
        return cls["_retired"].length;
    }

    private static function setBase(value:Boolean):Void {
        PauseManager.set(value, "manual");
    }

    private static function testPauseFlows():Void {
        var a:String;
        var d:String;
        var w:String;
        setBase(false);
        a = PauseManager.leaseLegacyAnimation("animation");
        _root.暂停 = true;
        _root.暂停 = false;
        check(PauseManager.isPaused(), "legacy writes cannot lower a live movie claim");
        PauseManager.releaseLease(a);
        check(!PauseManager.isPaused(), "legacy true cannot persist after movie completion");
        PauseManager.releaseLease(a);
        check(!PauseManager.isPaused(), "repeated movie release is idempotent");

        setBase(true);
        a = PauseManager.leaseLegacyAnimation("animation");
        _root.暂停 = false;
        PauseManager.releaseLease(a);
        check(PauseManager.isPaused(), "entry manual pause survives legacy false");
        setBase(false);

        for (var first:Number = 0; first < 2; first++) {
            a = PauseManager.leaseLegacyAnimation("animation");
            d = PauseManager.lease(true, "dialogue");
            _root.暂停 = true;
            _root.暂停 = false;
            PauseManager.releaseLease(first == 0 ? d : a);
            check(PauseManager.isPaused(), "movie/dialogue OR first=" + first);
            PauseManager.releaseLease(first == 0 ? a : d);
            check(!PauseManager.isPaused(), "movie/dialogue restore first=" + first);
        }

        a = PauseManager.leaseLegacyAnimation("animation");
        setBase(true);
        _root.暂停 = false;
        PauseManager.releaseLease(a);
        check(PauseManager.isPaused(), "named manual true is authoritative during movie");
        a = PauseManager.leaseLegacyAnimation("animation");
        setBase(false);
        _root.暂停 = true;
        PauseManager.releaseLease(a);
        check(!PauseManager.isPaused(), "named manual false is authoritative during movie");

        for (var base:Number = 0; base < 2; base++) {
            for (var rewardFirst:Number = 0; rewardFirst < 2; rewardFirst++) {
                setBase(base == 1);
                a = PauseManager.leaseLegacyAnimation("animation");
                d = PauseManager.lease(true, "dialogue");
                w = PauseManager.lease(true, "webpanel");
                PauseManager.setRewardCommitPending(true);
                _root.暂停 = (base == 0);
                if (rewardFirst == 1) PauseManager.setRewardCommitPending(false);
                PauseManager.releaseLease(a);
                PauseManager.releaseLease(d);
                check(PauseManager.isPaused(), "web claim survives movie/dialogue base=" + base + " rewardFirst=" + rewardFirst);
                PauseManager.releaseLease(w);
                if (rewardFirst == 0) {
                    check(PauseManager.isPaused(), "reward pending survives all UI closes base=" + base);
                    PauseManager.setRewardCommitPending(false);
                }
                check(PauseManager.isPaused() == (base == 1), "reward final base=" + base + " rewardFirst=" + rewardFirst);
            }
        }

        setBase(false);
        a = PauseManager.leaseLegacyAnimation("animation");
        w = PauseManager.leaseLegacyAnimation("replacement");
        PauseManager.releaseLease(a);
        _root.暂停 = true;
        PauseManager.releaseLease(w);
        check(!PauseManager.isPaused(), "overlapping retired/new movies retain independent guards");
        d = PauseManager.lease(true, "dialogue");
        _root.暂停 = true;
        PauseManager.releaseLease(d);
        check(PauseManager.isPaused(), "ordinary bare pause keeps its existing contract outside movies");
        setBase(false);
    }

    public static function runAllTests():Void {
        PauseManager.install();
        _saved = {};
        for (var i:Number = 0; i < _rootKeys.length; i++) _saved[_rootKeys[i]] = _root[_rootKeys[i]];
        _oldContext = NativeInteractionContext;
        _teardowns = [];
        _global.org.flashNight.arki.interaction.NativeInteractionContext = {
            getSceneId: function():String { return CutsceneServiceTest.sceneId; },
            onSceneTeardown: function(fn:Function):Void { CutsceneServiceTest._teardowns.push(fn); }
        };
        _root.最上层发布文字提示 = function():Void {};
        _root.获得翻译 = function(text:String):String { return text; };
        _root.createEmptyMovieClip("外部动画加载壳mc", _root.getNextHighestDepth());
        _root.外部动画加载壳mc.swapDepths(-100);
        testPauseFlows();
        _cases = [
            {asset:"movie_gk_15_5", mode:"dialogue_first", natural:true},
            {asset:"movie_gk_15_5", mode:"movie_first"},
            {asset:"movie_gk_15_5", mode:"base_true"},
            {asset:"movie_avp_1_3"}, {asset:"movie_avp_1_5"},
            {asset:"movie_avp_1_7"}, {asset:"movie_avp_1_14"},
            {asset:"movie_gk_1_1"}, {asset:"movie_gk_8_2"}, {asset:"movie_gk_9_4"},
            {asset:"movie_gk_11_4"}, {asset:"movie_gk_17_1"},
            {asset:"movie_gk_21_4"}, {asset:"movie_gk_21_5"},
            {asset:"movie_gk_22_5", implicit:true}, {asset:"movie_gk_24_1", implicit:true},
            {asset:"故障转场"}, {asset:"电子战过场"},
            {asset:"movie_gk_15_5", mode:"native_unload"},
            {asset:"movie_gk_15_5", mode:"onUnload_write"},
            {asset:"movie_gk_15_5", mode:"native_remove"},
            {asset:"movie_gk_15_5", mode:"replace_pending"},
            {asset:"movie_gk_15_5", mode:"cancel_pending"},
            {asset:"movie_gk_15_5", mode:"replace_loaded"},
            {asset:"movie_gk_15_5", mode:"alias_missing"},
            {asset:"movie_gk_15_5", mode:"scene"},
            {asset:"movie_gk_15_5", mode:"parent_rebuild"},
            {asset:"__cutscene_missing_fixture__", mode:"load_error"},
            {asset:"故障转场", mode:"unmanaged"}
        ];
        _watch = _root.createEmptyMovieClip("__cutsceneTest", _root.getNextHighestDepth());
        _watch.onEnterFrame = tick;
        nextCase();
    }

    private static function nextCase():Void {
        _index++;
        if (_index >= _cases.length) { finishTests(); return; }
        _case = _cases[_index];
        _ticks = 0;
        _phase = 0;
        _dialogue = null;
        setBase(_case.mode == "base_true");
        _expectedDepth = _root.外部动画加载壳mc.getDepth();
        CutsceneService.play("../flashswf/movies/" + _case.asset + ".swf", _case.mode != "unmanaged" && !_case.implicit);
        _session = active();
        if (_case.mode == "unmanaged") {
            check(_session == null && !PauseManager.isPaused(), "unregistered neutral movie preserves direct load path");
        } else {
            check(_session != null && PauseManager.isPaused(), _case.asset + " acquired pause before first frame");
        }
        if (_case.mode == "cancel_pending") {
            CutsceneService.cancelActive();
            check(active() == null && _root.外部动画加载壳mc.getDepth() == _expectedDepth, "cancel before load keeps authored layer unchanged");
            _phase = 1;
        }
        if (_case.mode == "replace_pending") {
            _stale = _session;
            CutsceneService.play("../flashswf/movies/movie_gk_11_4.swf", true);
            _session = active();
            check(_stale !== _session && _stale.name != _session.name, "pending replacement gets unique display path and object session");
            _stale.listener.onLoadError(_stale.target, "test_late", 0);
            _stale.listener.onLoadInit(_session.target);
            check(active() === _session && PauseManager.isPaused(), "stale error/init cannot end replacement");
        }
    }

    private static function tick():Void {
        if (_finished) return;
        if (++_ticks > 450) {
            check(false, "case timeout " + _index + " " + _case.asset + " mode=" + _case.mode);
            CutsceneService.cancelActive();
            if (_dialogue != null) { PauseManager.releaseLease(_dialogue); _dialogue = null; }
            _phase = 2;
            _case.mode = "timed_out";
            _index = _cases.length;
        }
        if (_case.mode == "unmanaged") {
            var holder:MovieClip = _root.外部动画加载壳mc;
            if (_phase == 0 && holder._totalframes > 1) {
                check(!PauseManager.isPaused(), "neutral first frame does not introduce a pause");
                holder.gotoAndPlay(holder._totalframes);
                _phase = 1;
                _ticks = 0;
            } else if (_phase == 1 && _ticks >= 4) {
                check(!PauseManager.isPaused(), "neutral last frame preserves pause state");
                nextCase();
            }
            return;
        }
        if (_case.mode == "load_error") {
            if (active() == null && pending() == 0) {
                check(!PauseManager.isPaused(), "missing SWF releases pause and terminates its session");
                nextCase();
            }
            return;
        }
        if (_ticks == 20 && _phase == 0) {
            trace("[LOAD_DIAG] url=" + _session.target._url + " frames=" + _session.target._totalframes + " bytes=" + _session.target.getBytesLoaded() + " initialized=" + _session.initialized + " terminal=" + _session.terminal + " name=" + _session.name + " preparing=" + _session.preparing);
        }
        if (_phase == 0 && _session.terminal && pending() == 0) {
            check(false, "movie ended before initialization " + _case.asset + " holder=" + _session.holder._name + " target=" + _session.target._name + " reason=" + _session.endReason + " accepted=" + _session.loadAccepted);
            _index = _cases.length;
            finishTests();
            return;
        }
        if (_phase == 3 && _ticks >= 3) {
            check(active() === _session && _root.外部动画加载壳mc._name == _session.holderName && PauseManager.isPaused(), "lost public alias repairs without cancelling live movie");
            _session.target.gotoAndPlay(_session.target._totalframes);
            _phase = 1;
        }
        if (_phase == 0 && _session.initialized) loadedCase();
        if (_phase == 1 && active() == null && pending() == 0) endedCase();
        if (_phase == 2 && pending() == 0) nextCase();
    }

    private static function loadedCase():Void {
        var target:MovieClip = _session.target;
        if (!_testedMovies[_case.asset]) { _testedMovies[_case.asset] = true; _testedCount++; }
        check(target._totalframes > 1 && target._parent === _root && target.getDepth() == _session.layerDepth && _session.layerDepth == _expectedDepth, _case.asset + " loaded existing timeline at original layer and parent");
        check(PauseManager.isPaused(), _case.asset + " first-frame legacy pause is held");
        _phase = 1;
        if (_case.mode == "dialogue_first" || _case.mode == "movie_first" || _case.mode == undefined) {
            _dialogue = PauseManager.lease(true, "dialogue");
        }
        if (_case.mode == "dialogue_first") {
            PauseManager.releaseLease(_dialogue);
            _dialogue = null;
            check(PauseManager.isPaused(), "fast E completion leaves natural Rock Park movie paused until actual end");
        }
        if (_case.mode == "replace_loaded") {
            _stale = _session;
            CutsceneService.play("../flashswf/movies/movie_gk_11_4.swf", true);
            _session = active();
            _stale.listener.onLoadInit(_session.target);
            _stale.listener.onLoadError(_stale.target, "test_late", 0);
            check(_session !== _stale && active() === _session && PauseManager.isPaused(), "loaded movie replacement isolates late callbacks and keeps pause");
            _case.mode = "replacement_final";
            _phase = 0;
            _ticks = 0;
            return;
        }
        if (_case.mode == "alias_missing") {
            delete _root.外部动画加载壳mc;
            _phase = 3;
            _ticks = 0;
            return;
        }
        if (_case.mode == "onUnload_write") {
            target.onUnload = function():Void {
                CutsceneServiceTest._unloadCalls++;
                _root.暂停 = true;
            };
            _session.listener.onLoadInit(target);
        }
        if (_case.mode == "scene") {
            for (var i:Number = 0; i < _teardowns.length; i++) _teardowns[i].call(null);
            sceneId = "cutscene.test.2";
            check(active() == null, "scene teardown marks old movie terminal before scene rotation");
        } else if (_case.mode == "parent_rebuild") {
            _root.外部动画加载壳mc.removeMovieClip();
            _root.外部动画加载壳mc = _root.createEmptyMovieClip("外部动画加载壳mc", _root.getNextHighestDepth());
        } else if (_case.mode == "native_unload") {
            // 绕过实例方法，实际调用 native 原型，验证 root ticker / onUnload 兜底。
            MovieClip.prototype.unloadMovie.call(target);
        } else if (_case.mode == "native_remove") {
            delete target.onUnload;
            target.swapDepths(_root.getNextHighestDepth());
            MovieClip.prototype.removeMovieClip.call(target);
        } else if (!_case.natural) {
            target.gotoAndPlay(target._totalframes);
        }
    }

    private static function endedCase():Void {
        if (_case.mode == "onUnload_write") check(_unloadCalls == 1, "existing onUnload handler runs exactly once under legacy guard");
        if (_dialogue != null) {
            check(PauseManager.isPaused(), _case.asset + " actual tail cannot release remaining dialogue claim");
            PauseManager.releaseLease(_dialogue);
            _dialogue = null;
        }
        check(PauseManager.isPaused() == (_case.mode == "base_true"), _case.asset + " terminal state restores original pause mode=" + _case.mode);
        check(_root[_session.name] == undefined, _case.asset + " retired unique clip is removed");
        if (_case.mode != "parent_rebuild") check(_root.外部动画加载壳mc.getDepth() == _expectedDepth, _case.asset + " blank shell returns to original layer");
        if (_case.mode == "replacement_final") check(_root[_stale.name] == undefined && _stale.terminal, "loaded replacement removes only its retired predecessor");
        if (_case.mode == "parent_rebuild") {
            _stale = _session;
            CutsceneService.play("../flashswf/movies/movie_gk_11_4.swf", true);
            var replacement:Object = active();
            _stale.listener.onLoadError(_stale.target, "test_late", 0);
            check(active() === replacement && PauseManager.isPaused(), "same parent path reconstruction cannot rebind old session to new movie");
            CutsceneService.cancelActive();
            _phase = 2;
            return;
        }
        nextCase();
    }

    private static function finishTests():Void {
        _finished = true;
        delete _watch.onEnterFrame;
        _watch.removeMovieClip();
        _root.外部动画加载壳mc.removeMovieClip();
        _global.org.flashNight.arki.interaction.NativeInteractionContext = _oldContext;
        for (var i:Number = 0; i < _rootKeys.length; i++) _root[_rootKeys[i]] = _saved[_rootKeys[i]];
        trace("CutsceneServiceTest Existing Movies Tested: " + _testedCount);
        trace("CutsceneServiceTest Tests Passed: " + _passed);
        trace("CutsceneServiceTest Tests Failed: " + _failed);
        _root.cutsceneFocusedComplete();
    }
}
