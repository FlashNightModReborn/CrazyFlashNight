import org.flashNight.arki.pause.PauseManager;
import org.flashNight.arki.interaction.NativeInteractionContext;
import org.flashNight.arki.dialogue.NativeDialogueService;
import org.flashNight.arki.key.KeyManager;
import org.flashNight.arki.input.IsolatedInputPolicy;

/**
 * 旧过场的统一暂停责任与生命周期。素材仍可裸写暂停/自行卸载。
 * 每次装载使用不复用的根实例名；会话身份只用普通对象，避免 AVM1 同路径重绑。
 * 回调由类方法创建，不能捕获会被卸载的 asLoader 帧脚本局部变量。
 */
class org.flashNight.arki.scene.CutsceneService {
    private static var _installed:Boolean = false;
    private static var _sequence:Number = 0;
    private static var _shellSequence:Number = 0;
    private static var _shellDepth:Number;
    private static var _holder:MovieClip = null;
    private static var _active:Object = null;
    private static var _retired:Array = null;
    private static var _watch:MovieClip = null;
    private static var _readKey:Function = Key.isDown;
    private static var _consumedSkipKey:Number = NaN;

    // 逐个核对过根时间轴与嵌套脚本：没有必须顺序执行的中途业务事件。
    // 只开放这些素材的原尾帧；帧数变化须重新审查，不猜测新素材的结束位置。
    private static var _skipTails:Object = {
        movie_avp_1_3: 171, movie_avp_1_5: 239,
        movie_avp_1_7: 344, movie_avp_1_14: 210,
        movie_gk_1_1: 214, movie_gk_8_2: 147,
        movie_gk_9_4: 109, movie_gk_11_4: 191,
        movie_gk_15_5: 169, movie_gk_17_1: 156,
        movie_gk_21_4: 163, movie_gk_21_5: 96,
        movie_gk_22_5: 143, movie_gk_24_1: 170,
        故障转场: 19, 电子战过场: 102
    };

    // 已核对的旧素材会在首帧裸写 true，部分 XML 没有 Pause 字段。
    // 未登记且未显式请求暂停的素材，继续使用原壳的 loadMovie 路径。
    private static var _legacyPause:Object = {
        movie_avp_1_3: true, movie_avp_1_5: true,
        movie_avp_1_7: true, movie_avp_1_14: true,
        movie_gk_1_1: true, movie_gk_8_2: true,
        movie_gk_9_4: true, movie_gk_11_4: true,
        movie_gk_15_5: true, movie_gk_17_1: true,
        movie_gk_21_4: true, movie_gk_21_5: true,
        movie_gk_22_5: true, movie_gk_24_1: true
    };

    private static function install():Void {
        if (_installed) return;
        _installed = true;
        _retired = [];
        NativeInteractionContext.onSceneTeardown(onSceneTeardown);
    }

    private static function assetName(path:String):String {
        var clean:String = path.split("?")[0].split("#")[0];
        clean = clean.split("\\").join("/");
        var parts:Array = clean.split("/");
        var name:String = String(parts[parts.length - 1]);
        if (name.substr(-4).toLowerCase() == ".swf") name = name.substr(0, name.length - 4);
        return name;
    }

    public static function play(path:String, requestPause:Boolean):Void {
        install();
        cancelActive();
        var holder:MovieClip = getHolder();
        if (holder == undefined || holder._name == undefined || path == undefined || path == "") return;
        var name:String = assetName(path);
        // Chapters share the managed lifetime/input gate, while retaining their own page controls.
        var bookChapter:Boolean = name == "修理大学章节";
        if (!bookChapter && !requestPause && _legacyPause[name] !== true) {
            holder._visible = true;
            holder.loadMovie(path);
            return;
        }

        // 保留原素材的 root / parent 拓扑。被 unload 的壳不能再作 MCL 目标的父层。
        // 独占根实例与壳交换深度，播放结束时还原，壳的占位图形保持隐藏。
        holder = replaceHolder(holder);
        if (holder == null) return;
        var clipName:String = "__cutscene_" + (++_sequence);
        var session:Object = {
            name: clipName, holder: holder, holderName: holder._name, layerDepth: holder.getDepth(),
            target: null, path: path, preparing: true, bookChapter: bookChapter,
            tailFrame: bookChapter ? 1 : _skipTails[name], skipAllowed: false, skipRequested: false,
            skipKey: NaN, skipWasDown: true,
            sceneId: NativeInteractionContext.getSceneId(), terminal: false,
            initialized: false, leaseId: PauseManager.leaseLegacyAnimation("animation"),
            loader: new MovieClipLoader(), cleanupPhase: 0
        };
        _active = session;
        session.listener = makeListener(session);
        session.loader.addListener(session.listener);
        ensureWatch();
    }

    private static function getHolder():MovieClip {
        var holder:MovieClip = _root.外部动画加载壳mc;
        if (holder == undefined || holder._name == undefined) {
            // 根时间轴重新布置 authored 实例时，先撤去已失效的显式别名再解析。
            delete _root.外部动画加载壳mc;
            holder = _root.外部动画加载壳mc;
        }
        if ((holder == undefined || holder._name == undefined) && _holder != null && _holder._name != undefined) {
            holder = _holder;
            _root.外部动画加载壳mc = holder;
        }
        if ((holder == undefined || holder._name == undefined) && !isNaN(_shellDepth)) {
            holder = _root.createEmptyMovieClip("__cutsceneShell_" + (++_shellSequence), _root.getNextHighestDepth());
            holder.swapDepths(_shellDepth);
            _root.外部动画加载壳mc = holder;
        }
        _holder = holder;
        return holder;
    }

    private static function replaceHolder(old:MovieClip):MovieClip {
        _shellDepth = old.getDepth();
        var x:Number = old._x;
        var y:Number = old._y;
        var xs:Number = old._xscale;
        var ys:Number = old._yscale;
        // 卸载后的 MC 会保留 native 名称，却丢掉 script object。新壳必须换实际实例名，
        // 同名重建仍会重绑到旧状态；外部继续通过原中文成员别名访问。
        old.swapDepths(_root.getNextHighestDepth());
        old.unloadMovie();
        old.removeMovieClip();
        var holder:MovieClip = _root.createEmptyMovieClip("__cutsceneShell_" + (++_shellSequence), _root.getNextHighestDepth());
        if (holder == undefined) return null;
        holder.swapDepths(_shellDepth);
        holder._x = x;
        holder._y = y;
        holder._xscale = xs;
        holder._yscale = ys;
        holder._visible = false;
        _root.外部动画加载壳mc = holder;
        _holder = holder;
        return holder;
    }

    public static function cancelActive():Void {
        if (_active != null) finish(_active);
    }

    /** UI 互动下发前查询：受管动画和本次跳过的长按不传给门/拾取等场景互动。 */
    public static function blocksWorldInteraction():Boolean {
        return _active != null || (_retired != null && _retired.length > 0) || !isNaN(_consumedSkipKey);
    }

    private static function onSceneTeardown():Void {
        cancelActive();
    }

    private static function isActive(session:Object):Boolean {
        return session != null && !session.terminal && session === _active;
    }

    private static function makeListener(session:Object):Object {
        return {
            session: session,
            onLoadComplete: function(target:MovieClip):Void {
                if (CutsceneService.isActive(this.session)) CutsceneService.bindEndHooks(this.session, target);
            },
            onLoadInit: function(target:MovieClip):Void {
                var current:Object = this.session;
                if (!CutsceneService.isActive(current)) return;
                current.initialized = true;
                current.loadedUrl = target._url;
                current.loadedFrames = target._totalframes;
                current.skipAllowed = current.tailFrame === current.loadedFrames;
                CutsceneService.bindEndHooks(current, target);
            },
            onLoadError: function(target:MovieClip, code:String, status:Number):Void {
                if (CutsceneService.isActive(this.session)) {
                    this.session.endReason = "load_error:" + code;
                    CutsceneService.finish(this.session);
                }
            }
        };
    }

    private static function bindEndHooks(session:Object, target:MovieClip):Void {
        bindMethod(session, target, "unloadMovie");
        bindMethod(session, target, "removeMovieClip");
        // 首帧可自定义 onUnload；onLoadInit 再绑定一次，保留它最新的处理器。
        if (session.unloadHook == undefined || target.onUnload !== session.unloadHook) {
            session.oldOnUnload = target.onUnload;
            session.ownOnUnload = target.hasOwnProperty("onUnload");
            session.unloadHook = makeOnUnload(session, session.oldOnUnload);
            target.onUnload = session.unloadHook;
        }
    }

    private static function bindMethod(session:Object, target:MovieClip, key:String):Void {
        if (target[key] === session[key + "Hook"]) return;
        session[key + "Original"] = target[key];
        session[key + "Own"] = target.hasOwnProperty(key);
        session[key + "Hook"] = makeEndMethod(session, target[key]);
        target[key] = session[key + "Hook"];
    }

    private static function makeEndMethod(session:Object, original:Function):Function {
        var hook:Function = function():Void {
            var callback:Object = arguments.callee;
            // 必须先记终态；native 卸载可能立即销毁本函数的 MovieClip 执行上下文。
            CutsceneService.finish(callback.session);
            callback.original.apply(this, arguments);
        };
        hook.session = session;
        hook.original = original;
        return hook;
    }

    private static function makeOnUnload(session:Object, previous:Function):Function {
        var hook:Function = function():Void {
            var callback:Object = arguments.callee;
            CutsceneService.finish(callback.session);
            if (callback.previous != undefined) callback.previous.call(this);
        };
        hook.session = session;
        hook.previous = previous;
        return hook;
    }

    private static function finish(session:Object):Void {
        if (session == null || session.terminal) return;
        session.terminal = true;
        clearSkipHint(session);
        if (_active === session) _active = null;
        restoreLayer(session);
        _retired.push(session);
        ensureWatch();
    }

    private static function ensureWatch():Void {
        if (_watch == null || _watch._name == undefined) {
            _watch = _root.createEmptyMovieClip("__cutsceneLifecycle", _root.getNextHighestDepth());
        }
        _watch.onEnterFrame = tick;
    }

    private static function targetFor(session:Object):MovieClip {
        // 名字永不复用，不会把新片当成旧片清理；不依赖旧 MC 引用相等。
        var target:MovieClip = _root[session.name];
        return target._name == session.name ? target : null;
    }

    private static function startLoad(session:Object):Void {
        // 根帧观察者到下一帧才创建；暂停 claim 已在 play 中预先取得。
        session.preparing = false;
        var holder:MovieClip = session.holder;
        var target:MovieClip = _root.createEmptyMovieClip(session.name, _root.getNextHighestDepth());
        if (target == undefined) { session.endReason = "create_failed"; finish(session); return; }
        target._lockroot = false;
        target._x = holder._x;
        target._y = holder._y;
        target._xscale = holder._xscale;
        target._yscale = holder._yscale;
        session.layerDepth = holder.getDepth();
        target.swapDepths(holder);
        session.target = target;
        session.loadAccepted = session.loader.loadClip(session.path, target);
        if (!session.loadAccepted) { session.endReason = "load_rejected"; finish(session); }
    }

    private static function tick():Void {
        // 结束后仍观察本次跳过键直到松开，屏蔽 repeat，也覆盖跳过期间改键。
        if (!isNaN(_consumedSkipKey) && !_readKey(_consumedSkipKey)) _consumedSkipKey = NaN;
        var session:Object = _active;
        if (session != null) {
            // 旧 authored 壳的迟到删除会删除原中文成员；实际实例名独占，缺别名可恢复。
            var holder:MovieClip = getHolder();
            if (session.sceneId != NativeInteractionContext.getSceneId() || session.holder._name != session.holderName
                    || holder._name != session.holderName) {
                session.endReason = "context_changed";
                finish(session);
            } else if (session.preparing) {
                startLoad(session);
            } else {
                var target:MovieClip = targetFor(session);
                if (target == null || (session.initialized && (target._url != session.loadedUrl
                        || target._totalframes < session.loadedFrames))) {
                    // 原型直接卸载、丢失 onUnload、父层卸载均由根上的观察者兜底。
                    session.endReason = "target_or_contents_missing";
                    finish(session);
                } else if (session.initialized) {
                    tickSkip(session, target);
                }
            }
        }
        var remaining:Array = [];
        var retired:Array = _retired;
        _retired = [];
        for (var i:Number = 0; i < retired.length; i++) {
            session = retired[i];
            if (session.cleanupPhase == 0) {
                session.cleanupPhase = 1;
                cleanupTarget(session);
                remaining.push(session);
            } else {
                PauseManager.releaseLease(session.leaseId);
                session.leaseId = null;
            }
        }
        _retired = remaining.concat(_retired);
        if (_active == null && _retired.length == 0 && isNaN(_consumedSkipKey)) delete _watch.onEnterFrame;
    }

    private static function tickSkip(session:Object, target:MovieClip):Void {
        if (!isActive(session)) return;
        if (session.skipRequested) {
            // gotoAndPlay 的帧脚本可能晚于当前 enterFrame 分发，留足原尾帧执行时间。
            // 常规尾帧经结束钩子收口；停止但未卸载的尾帧由既有清理流程兜底。
            if (++session.skipWaitFrames > 2 && target._currentframe == session.tailFrame) finish(session);
            return;
        }
        var code:Number = KeyManager.getKeySetting("互动键");
        if (!session.skipAllowed || IsolatedInputPolicy.forbidsLegacyDrivers()
                || NativeDialogueService.hasActiveSession() || !(code > 0 && code < 256)) {
            session.skipWasDown = true;
            clearSkipHint(session);
            return;
        }
        if (session.skipKey !== code) {
            session.skipKey = code;
            session.skipWasDown = true;
        }
        showSkipHint(session, code);
        var down:Boolean = _readKey(code);
        var wasDown:Boolean = session.skipWasDown;
        session.skipWasDown = down;
        if (down && !wasDown) {
            if (session.bookChapter && typeof target.advanceChapter == "function") {
                _consumedSkipKey = code;
                target.advanceChapter();
                return;
            }
            session.skipRequested = true;
            _consumedSkipKey = code;
            session.skipWaitFrames = 0;
            clearSkipHint(session);
            // 执行原结束脚本（包括教学提示），不能仅卸载素材或结束对白。
            target.gotoAndPlay(session.tailFrame);
        }
    }

    private static function showSkipHint(session:Object, code:Number):Void {
        var hint:MovieClip = session.skipHint;
        if (hint == null || hint._name == undefined) {
            hint = _watch.createEmptyMovieClip(session.name + "_skipHint", _watch.getNextHighestDepth());
            session.skipHint = hint;
            hint._x = 352;
            hint._y = 506;
            hint.beginFill(0x000000, 65);
            hint.moveTo(0, 0);
            hint.lineTo(320, 0);
            hint.lineTo(320, 34);
            hint.lineTo(0, 34);
            hint.lineTo(0, 0);
            hint.endFill();
            hint.createTextField("label", 1, 4, 5, 312, 26);
            hint.label.selectable = false;
            var format:TextFormat = new TextFormat("_sans", 16, 0xFFFFFF, true);
            format.align = "center";
            hint.label.setNewTextFormat(format);
        }
        if (session.hintKey === code) return;
        session.hintKey = code;
        var keyName:String = KeyManager.getKeyName(code);
        if (keyName == "") keyName = String(code);
        var label:String = session.bookChapter ? "继续" : "跳过动画";
        if (_root.获得翻译 != undefined) label = _root.获得翻译(label);
        hint.label.text = keyName + " " + label;
    }

    private static function clearSkipHint(session:Object):Void {
        if (session.skipHint != null) session.skipHint.removeMovieClip();
        session.skipHint = null;
        session.hintKey = null;
    }

    private static function restoreMethod(session:Object, target:MovieClip, key:String):Void {
        if (target[key] !== session[key + "Hook"]) return;
        if (session[key + "Own"]) target[key] = session[key + "Original"];
        else delete target[key];
    }

    private static function restoreLayer(session:Object):Void {
        var holder:MovieClip = session.holder;
        var target:MovieClip = targetFor(session);
        if (holder._name == session.holderName && _root.外部动画加载壳mc._name == session.holderName) {
            if (target != null && target.getDepth() == session.layerDepth) target.swapDepths(holder);
            else holder.swapDepths(session.layerDepth);
        }
        if (target != null) {
            target._visible = false;
            // removeMovieClip 对 authored 负深度无效；父壳重建后也要能真正清掉旧片。
            if (target.getDepth() < 0) target.swapDepths(_root.getNextHighestDepth());
        }
    }

    private static function cleanupTarget(session:Object):Void {
        session.loader.removeListener(session.listener);
        var target:MovieClip = targetFor(session);
        if (target == null) return;
        restoreMethod(session, target, "unloadMovie");
        restoreMethod(session, target, "removeMovieClip");
        if (target.onUnload === session.unloadHook) {
            if (session.ownOnUnload) target.onUnload = session.oldOnUnload;
            else delete target.onUnload;
        }
        // 暂停 claim 延后到下一根帧释放，让本帧 onUnload 的旧裸写仍在保护内。
        // 取消下载也使用对应 loader，迟到 init/error 回调仅能命中 terminal 会话。
        session.loader.unloadClip(target);
        target.removeMovieClip();
    }
}
