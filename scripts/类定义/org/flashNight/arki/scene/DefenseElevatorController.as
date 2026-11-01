import org.flashNight.arki.scene.StageManager;
import org.flashNight.arki.scene.StageReturnFlow;

class org.flashNight.arki.scene.DefenseElevatorController {
    private static var active:Object;
    private static var LOOP_HEIGHT:Number = 924.928;
    private static var TRAVEL_SPEED:Number = LOOP_HEIGHT / 36;
    private static var SCROLL_URL:String = "flashswf/backgrounds/cf6/CF6_A10_elevator-scroll.swf";
    private static var FOREGROUND_URL:String = "flashswf/backgrounds/cf6/CF6_A10_foreground.swf";
    private static var ASSET_SCALE:Number = 1.7066666666666668;
    private static var SCROLL_X:Number = -85.3333;
    private static var SCROLL_Y:Number = -102.4;
    private static var FOREGROUND_X:Number = 103.168;
    private static var FOREGROUND_Y:Number = 11.008;
    private static var BACKGROUND_URL:String = "flashswf/backgrounds/cf6/CF6_A10_BG.swf";
    private static var STOP_FRAMES:Number = 60;
    private static var HOLD_FRAMES:Number = 30;
    private static var START_FRAMES:Number = 60;

    public static function begin():Void {
        dispose();
        var world:MovieClip = _root.gameworld;
        var manager:StageManager = StageManager.instance;
        if (world == null || manager == null) return;
        var background:MovieClip = world.背景;
        if (background == undefined) return;
        background._x = SCROLL_X;
        background._y = SCROLL_Y;
        background._xscale = background._yscale = ASSET_SCALE * 100;
        var s:Object = {
            world:world,
            owner:StageReturnFlow.worldIdentity(world),
            stageIndex:manager.currentStage,
            phase:"loading",
            speed:0,
            offset:0,
            frame:0,
            resume:true,
            assetsStarted:false,
            artReady:false,
            art2Ready:false,
            foregroundReady:false,
            backgroundSeen:false,
            backgroundRequested:false,
            backgroundReady:false,
            backgroundWait:0,
            backgroundFrame:0
        };
        active = s;
        s.watchClip = _root.createEmptyMovieClip("__defenseElevatorWatch", _root.getNextHighestDepth());
        s.watchClip.onEnterFrame = function():Void {
            org.flashNight.arki.scene.DefenseElevatorController.tick();
        };
    }

    public static function stop(waveIndex:Number, totalWaves:Number):Void {
        var s:Object = active;
        if (s == null) return;
        var resume:Boolean = waveIndex + 1 < totalWaves;
        if (!s.ready) {
            s.pendingResume = resume;
            return;
        }
        startStopping(s, resume);
    }

    public static function closeForStage(world:MovieClip, stageIndex:Number):Void {
        var s:Object = active;
        if (s == null || s.world !== world || s.stageIndex !== stageIndex) return;
        dispose();
    }

    private static function startStopping(s:Object, resume:Boolean):Void {
        if (s.phase == "stopping" || s.phase == "hold" || s.phase == "stopped") return;
        s.phase = "stopping";
        s.frame = 0;
        s.resume = resume;
    }

    private static function tick():Void {
        var s:Object = active;
        if (s == null) return;
        if (!current(s)) {
            dispose();
            return;
        }
        if (!s.ready) {
            if (!s.backgroundReady) {
                prepareBackground(s);
                return;
            }
            prepareAssets(s);
            return;
        }
        if (_root.暂停 === true) return;
        advanceTravel(s);
        s.holder.art._y = -s.offset;
        s.holder.art2._y = LOOP_HEIGHT - s.offset;
    }

    private static function current(s:Object):Boolean {
        var manager:StageManager = StageManager.instance;
        return s.world === _root.gameworld
            && StageReturnFlow.worldIdentity(s.world) === s.owner
            && manager != null && manager.currentStage === s.stageIndex
            && manager.isActive === true && manager.isFinished !== true && manager.isFailed !== true;
    }

    private static function prepareAssets(s:Object):Void {
        if (s.assetsStarted) return;
        var parent:MovieClip = s.world.deadbody;
        var effects:MovieClip = s.world.效果;
        if (parent == undefined || effects == undefined) return;
        s.assetsStarted = true;
        s.holder = parent.createEmptyMovieClip("__defenseElevatorScroll", -100);
        s.holder._x = SCROLL_X - parent._x;
        s.holder._y = SCROLL_Y - parent._y;
        s.holder._visible = false;
        s.holder.art = s.holder.createEmptyMovieClip("art", 0);
        s.holder.art2 = s.holder.createEmptyMovieClip("art2", 1);
        createWindowMask(s.holder, "windowMask", 2);
        createWindowMask(s.holder, "windowMask2", 3);

        s.foreground = effects.createEmptyMovieClip("__defenseElevatorForeground", effects.getNextHighestDepth());
        s.foreground._x = FOREGROUND_X;
        s.foreground._y = FOREGROUND_Y;
        s.foreground._visible = false;
        s.foregroundArt = s.foreground.createEmptyMovieClip("art", 0);

        s.loader = new MovieClipLoader();
        s.listener = {
            onLoadInit:function(mc:MovieClip):Void {
                org.flashNight.arki.scene.DefenseElevatorController.partReady(s, mc);
            },
            onLoadError:function(mc:MovieClip, error:String):Void {
                org.flashNight.arki.scene.DefenseElevatorController.fail(s, error);
            }
        };
        s.loader.addListener(s.listener);
        s.loader.loadClip(SCROLL_URL, s.holder.art);
        s.loader.loadClip(SCROLL_URL, s.holder.art2);
        s.loader.loadClip(FOREGROUND_URL, s.foregroundArt);
    }

    private static function prepareBackground(s:Object):Void {
        var background:MovieClip = s.world.背景;
        if (background == undefined) {
            fail(s, "电梯静态背景缺失");
            return;
        }
        if (!s.backgroundSeen) {
            if (++s.backgroundWait > 300) {
                fail(s, "电梯静态背景加载超时");
                return;
            }
            if (String(s.world.场景背景url) === BACKGROUND_URL
                    && background._width > 0 && background._height > 0) {
                s.backgroundSeen = true;
            }
            return;
        }
        if (!s.backgroundRequested) {
            s.backgroundRequested = true;
            s.backgroundFrame = 0;
            _root.贴背景图(true);
            return;
        }
        if (background._width === 0 && background._height === 0) {
            s.backgroundReady = true;
            return;
        }
        if (++s.backgroundFrame > 60) {
            fail(s, "电梯静态背景烘焙超时");
        }
    }

    private static function createWindowMask(holder:MovieClip, name:String, depth:Number):Void {
        var mask:MovieClip = holder.createEmptyMovieClip(name, depth);
        mask.beginFill(0);
        mask.moveTo(85.3333, 102.4);
        mask.lineTo(85.3333 + 1024, 102.4);
        mask.lineTo(85.3333 + 1024, 102.4 + 597.3333);
        mask.lineTo(85.3333, 102.4 + 597.3333);
        mask.endFill();
    }

    private static function partReady(s:Object, mc:MovieClip):Void {
        if (active !== s) return;
        if (mc === s.holder.art) {
            scaleAsset(mc);
            mc.setMask(s.holder.windowMask);
            s.artReady = true;
        } else if (mc === s.holder.art2) {
            scaleAsset(mc);
            mc.setMask(s.holder.windowMask2);
            s.art2Ready = true;
        } else if (mc === s.foregroundArt) {
            scaleAsset(mc);
            s.foregroundReady = true;
        } else {
            return;
        }
        if (!s.artReady || !s.art2Ready || !s.foregroundReady) return;
        s.holder._visible = true;
        s.foreground._visible = true;
        s.ready = true;
        s.phase = "moving";
        if (s.pendingResume !== undefined) {
            var resume:Boolean = s.pendingResume;
            delete s.pendingResume;
            startStopping(s, resume);
        }
    }

    private static function scaleAsset(mc:MovieClip):Void {
        mc._xscale = mc._yscale = ASSET_SCALE * 100;
    }

    private static function advanceTravel(s:Object):Void {
        if (s.phase == "moving") {
            s.speed = TRAVEL_SPEED;
        } else if (s.phase == "stopping") {
            s.frame++;
            s.speed = TRAVEL_SPEED * Math.max(0, 1 - s.frame / STOP_FRAMES);
            if (s.frame >= STOP_FRAMES) {
                s.frame = 0;
                s.phase = s.resume ? "hold" : "stopped";
            }
        } else if (s.phase == "hold") {
            s.speed = 0;
            s.frame++;
            if (s.frame >= HOLD_FRAMES) {
                s.frame = 0;
                s.phase = "starting";
            }
        } else if (s.phase == "starting") {
            s.frame++;
            s.speed = TRAVEL_SPEED * Math.min(1, s.frame / START_FRAMES);
            if (s.frame >= START_FRAMES) {
                s.frame = 0;
                s.phase = "moving";
            }
        } else if (s.phase == "stopped") {
            s.speed = 0;
        }
        s.offset = (s.offset + s.speed) % LOOP_HEIGHT;
    }

    private static function fail(s:Object, message:String):Void {
        if (active !== s) return;
        _root.发布消息("防御地带电梯动态背景加载失败，保留静态背景：" + message);
        dispose();
    }

    private static function dispose():Void {
        var s:Object = active;
        active = null;
        if (s == null) return;
        if (s.loader != null && s.listener != null) s.loader.removeListener(s.listener);
        if (s.holder != undefined) s.holder.removeMovieClip();
        if (s.foreground != undefined) s.foreground.removeMovieClip();
        if (s.watchClip != undefined) s.watchClip.removeMovieClip();
    }
}
