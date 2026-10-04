import org.flashNight.arki.scene.CutsceneService;
import org.flashNight.arki.pause.PauseManager;
import org.flashNight.arki.interaction.NativeInteractionContext;
import org.flashNight.arki.dialogue.NativeDialogueService;
import org.flashNight.arki.key.KeyManager;
import org.flashNight.arki.input.IsolatedInputPolicy;

/**
 * 真实 SWF 尾帧 + 可控物理键采样，验证对白优先、松开再按、改键和收尾。
 * 不进入完整游戏，不访问存档；按键采样与对白状态为装夹，不能替代真人按键验收。
 */
class org.flashNight.arki.scene.CutsceneSkipTest {
    private static var _passed:Number = 0;
    private static var _failed:Number = 0;
    private static var _saved:Object;
    private static var _watch:MovieClip;
    private static var _cases:Array;
    private static var _index:Number = -1;
    private static var _case:Object;
    private static var _session:Object;
    private static var _stale:Object;
    private static var _phase:Number = 0;
    private static var _ticks:Number = 0;
    private static var _down:Object = {};
    private static var _tips:Number = 0;
    private static var _lease:String;
    private static var _tested:Object = {};
    private static var _testedCount:Number = 0;
    private static var _finished:Boolean = false;
    private static var _rootKeys:Array = ["暂停", "外部动画加载壳mc", "最上层发布文字提示", "获得翻译"];

    private static function check(value:Boolean, message:String):Void {
        if (value) { _passed++; trace("[PASS] skip " + message); }
        else { _failed++; trace("[FAIL] skip " + message); }
    }

    private static function active():Object {
        var cls:Object = CutsceneService;
        return cls["_active"];
    }

    private static function pending():Number {
        var cls:Object = CutsceneService;
        return cls["_retired"].length;
    }

    private static function readKey(code:Number):Boolean { return _down[code] === true; }

    private static function sample():Void {
        var cls:Object = CutsceneService;
        cls["tickSkip"](_session, _session.target);
    }

    private static function setDialogue(value:Object):Void {
        var cls:Object = NativeDialogueService;
        cls["_session"] = value;
    }

    private static function setKey(code:Number):Void {
        var cls:Object = KeyManager;
        cls["keySettingsCache"]["互动键"] = code;
    }

    private static function pressToSkip(code:Number):Void {
        _down[code] = false;
        sample();
        _down[code] = true;
        sample();
        check(_session.skipRequested === true, _case.asset + " fresh interaction press requests audited tail");
        sample();
        check(_session.skipHint == null, _case.asset + " accepted skip clears only its own hint");
    }

    public static function runAllTests():Void {
        _saved = {context:NativeInteractionContext};
        var cls:Object = CutsceneService;
        _saved.readKey = cls["_readKey"];
        _saved.consumedKey = cls["_consumedSkipKey"];
        cls["_readKey"] = readKey;
        cls = NativeDialogueService;
        _saved.dialogue = cls["_session"];
        setDialogue(null);
        cls = KeyManager;
        _saved.keySettings = cls["keySettingsCache"];
        cls["keySettingsCache"] = {};
        cls = IsolatedInputPolicy;
        _saved.inputPresent = cls["_present"];
        cls["_present"] = false;
        for (var i:Number = 0; i < _rootKeys.length; i++) _saved[_rootKeys[i]] = _root[_rootKeys[i]];
        _global.org.flashNight.arki.interaction.NativeInteractionContext = {
            getSceneId: function():String { return "cutscene.skip.test"; },
            onSceneTeardown: function(fn:Function):Void {}
        };
        _root.最上层发布文字提示 = function(text:String):Void { CutsceneSkipTest._tips++; };
        _root.获得翻译 = function(text:String):String { return text; };
        _root.createEmptyMovieClip("__skipTestShell", _root.getNextHighestDepth());
        _root.外部动画加载壳mc = _root.__skipTestShell;
        _root.外部动画加载壳mc.swapDepths(-100);
        _cases = [
            {asset:"movie_gk_15_5"}, {asset:"movie_avp_1_3"}, {asset:"movie_avp_1_5"},
            {asset:"movie_avp_1_7"}, {asset:"movie_avp_1_14"}, {asset:"movie_gk_1_1"},
            {asset:"movie_gk_8_2"}, {asset:"movie_gk_9_4"}, {asset:"movie_gk_11_4"},
            {asset:"movie_gk_17_1"}, {asset:"movie_gk_21_4"}, {asset:"movie_gk_21_5"},
            {asset:"movie_gk_22_5", implicit:true}, {asset:"movie_gk_24_1", implicit:true},
            {asset:"故障转场"}, {asset:"电子战过场"},
            {asset:"movie_gk_15_5", mode:"held_entry"},
            {asset:"movie_gk_15_5", mode:"dialogue"},
            {asset:"movie_gk_15_5", mode:"pending_dialogue"},
            {asset:"movie_gk_15_5", mode:"remap"},
            {asset:"movie_gk_15_5", mode:"manual"},
            {asset:"movie_gk_15_5", mode:"web"},
            {asset:"movie_gk_15_5", mode:"replacement"},
            {asset:"movie_gk_15_5", mode:"frames_changed"},
            {asset:"__unreviewed_cutscene_fixture__", mode:"unreviewed"},
            {asset:"movie_gk_15_5", mode:"isolated_input"},
            {asset:"movie_gk_15_5", mode:"invalid_key"}
        ];
        _watch = _root.createEmptyMovieClip("__cutsceneSkipTest", _root.getNextHighestDepth());
        _watch.onEnterFrame = tick;
        nextCase();
    }

    private static function nextCase():Void {
        _index++;
        if (_index >= _cases.length) { finishTests(); return; }
        _case = _cases[_index];
        _ticks = 0;
        _phase = 0;
        _tips = 0;
        _lease = null;
        _down = {};
        setKey(69);
        setDialogue(null);
        PauseManager.set(_case.mode == "manual", "manual");
        if (_case.mode == "web") _lease = PauseManager.lease(true, "web");
        if (_case.mode == "held_entry") _down[69] = true;
        if (_case.mode == "frames_changed") {
            var cls:Object = CutsceneService;
            cls["_skipTails"].movie_gk_15_5 = 170;
        }
        CutsceneService.play("../flashswf/movies/" + _case.asset + ".swf", !_case.implicit);
        _session = active();
        check(_session != null && PauseManager.isPaused(), _case.asset + " prepares a paused session before loading");
        check(CutsceneService.blocksWorldInteraction(), _case.asset + " preparing movie blocks world E broadcasts");
        if (_case.mode == "unreviewed") {
            // 未登记名字用现有短片装夹实际内容，仅替换下载地址，不修改跳过登记表。
            _session.path = "../flashswf/movies/故障转场.swf";
        }
        _down[69] = true;
        sample();
        check(!_session.skipRequested, _case.asset + " loading-time E is not buffered into skip");
        if (_case.mode != "held_entry") _down[69] = false;
    }

    private static function tick():Void {
        if (_finished) return;
        if (++_ticks > 180) {
            check(false, "timeout " + _case.asset + " mode=" + _case.mode);
            _index = _cases.length;
            setDialogue(null);
            if (_lease != null) { PauseManager.releaseLease(_lease); _lease = null; }
            CutsceneService.cancelActive();
            _phase = 1;
        }
        if (_phase == 0 && _session.initialized && !_session.terminal) loadedCase();
        if (_phase == 0 && _session.terminal && pending() == 0) {
            check(false, "ended before input checks " + _case.asset + " " + _session.endReason);
            _index = _cases.length;
            finishTests();
            return;
        }
        if (_phase == 1 && active() == null && pending() == 0) endedCase();
    }

    private static function loadedCase():Void {
        _phase = 1;
        var target:MovieClip = _session.target;
        var cls:Object = CutsceneService;
        if (_case.mode == "frames_changed" || _case.mode == "unreviewed") {
            sample();
            _down[69] = true;
            sample();
            check(!_session.skipRequested && _session.skipHint == null && active() === _session,
                _case.mode + " remains unskippable and keeps its pause");
            cls["_skipTails"].movie_gk_15_5 = 169;
            CutsceneService.cancelActive();
            return;
        }
        if (!_tested[_case.asset]) { _tested[_case.asset] = true; _testedCount++; }
        check(_session.skipAllowed && target._currentframe < target._totalframes,
            _case.asset + " allows skip before natural ending");
        if (_case.mode == "dialogue" || _case.mode == "pending_dialogue") {
            _lease = PauseManager.lease(true, "dialogue");
            setDialogue({terminal:false, awaitingCommit:_case.mode == "pending_dialogue" ? {} : null});
            sample();
            _down[69] = true;
            sample();
            check(!_session.skipRequested && _session.skipHint == null && active() === _session,
                _case.mode + " owns E and hides the skip hint");
            setDialogue(null);
            PauseManager.releaseLease(_lease);
            _lease = null;
            sample();
            check(!_session.skipRequested && PauseManager.isPaused(), "last dialogue press cannot also skip remaining movie");
        } else if (_case.mode == "held_entry" || _case.mode == "replacement_final") {
            sample();
            check(!_session.skipRequested, "held key must release after movie entry/replacement");
        } else if (_case.mode == "replacement") {
            _down[69] = true;
            // 旧片尚未采样这次按下，就被另一片替换；不能传递到新会话。
            _stale = _session;
            CutsceneService.play("../flashswf/movies/movie_gk_11_4.swf", true);
            _session = active();
            _stale.listener.onLoadInit(_session.target);
            _stale.listener.onLoadError(_stale.target, "stale_skip", 0);
            check(active() === _session && !_session.skipRequested, "replacement rejects stale loader callbacks and pending E");
            _case.mode = "replacement_final";
            _ticks = 0;
            _phase = 0;
            return;
        } else if (_case.mode == "remap") {
            sample();
            check(_session.skipHint.label.text == "E 跳过动画", "default interaction prompt uses E");
            setKey(88);
            _down[88] = true;
            sample();
            check(!_session.skipRequested && _session.skipHint.label.text == "X 跳过动画", "remapped held X changes prompt without skipping");
            _down[88] = false;
            _down[69] = true;
            sample();
            check(!_session.skipRequested, "old E binding no longer skips after remap");
            pressToSkip(88);
            return;
        } else if (_case.mode == "isolated_input") {
            cls = IsolatedInputPolicy;
            cls["_present"] = true;
            sample();
            _down[69] = true;
            sample();
            check(!_session.skipRequested && _session.skipHint == null, "input isolation denies legacy movie keyboard polling");
            cls["_present"] = false;
            sample();
            check(!_session.skipRequested, "held key cannot cross input isolation boundary");
        } else if (_case.mode == "invalid_key") {
            setKey(NaN);
            sample();
            _down[69] = true;
            sample();
            check(!_session.skipRequested && _session.skipHint == null, "invalid interaction key disables skip safely");
            setKey(69);
            sample();
            check(!_session.skipRequested, "restoring binding still requires release");
        }
        pressToSkip(69);
    }

    private static function endedCase():Void {
        check(_root[_session.name] == undefined && _session.skipHint == null, _case.asset + " removes clip and prompt after actual tail");
        check(_root.外部动画加载壳mc.getDepth() == -100, _case.asset + " restores original movie layer");
        check(PauseManager.isPaused() == (_case.mode == "manual" || _case.mode == "web"),
            _case.asset + " skip releases only movie pause mode=" + _case.mode);
        if (_case.asset == "movie_gk_1_1") check(_tips == 1, "teaching movie retains its original final hint exactly once");
        if (_case.mode == "replacement_final") check(_stale.terminal && _root[_stale.name] == undefined, "replacement clears only retired predecessor");
        if (_lease != null) {
            PauseManager.releaseLease(_lease);
            _lease = null;
            check(!PauseManager.isPaused(), "closing other UI releases its retained pause");
        }
        if (_session.skipRequested) {
            check(CutsceneService.blocksWorldInteraction(), "accepted skip consumes held E/repeat after animation ended");
        }
        _down = {};
        var cls:Object = CutsceneService;
        cls["tick"]();
        check(!CutsceneService.blocksWorldInteraction(), "released interaction key restores ordinary world input");
        PauseManager.set(false, "manual");
        nextCase();
    }

    private static function finishTests():Void {
        _finished = true;
        delete _watch.onEnterFrame;
        _watch.removeMovieClip();
        _root.外部动画加载壳mc.removeMovieClip();
        var cls:Object = CutsceneService;
        cls["_readKey"] = _saved.readKey;
        cls["_consumedSkipKey"] = _saved.consumedKey;
        cls["_skipTails"].movie_gk_15_5 = 169;
        cls = NativeDialogueService;
        cls["_session"] = _saved.dialogue;
        cls = KeyManager;
        cls["keySettingsCache"] = _saved.keySettings;
        cls = IsolatedInputPolicy;
        cls["_present"] = _saved.inputPresent;
        _global.org.flashNight.arki.interaction.NativeInteractionContext = _saved.context;
        for (var i:Number = 0; i < _rootKeys.length; i++) _root[_rootKeys[i]] = _saved[_rootKeys[i]];
        trace("CutsceneSkipTest Existing Movies Tested: " + _testedCount);
        trace("CutsceneSkipTest Tests Passed: " + _passed);
        trace("CutsceneSkipTest Tests Failed: " + _failed);
        _root.cutsceneSkipFocusedComplete();
    }
}
