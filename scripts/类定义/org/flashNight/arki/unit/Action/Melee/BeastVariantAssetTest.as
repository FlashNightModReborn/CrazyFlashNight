import flash.display.BitmapData;
import flash.geom.Matrix;

class org.flashNight.arki.unit.Action.Melee.BeastVariantAssetTest {
    private static var library:MovieClip, driver:MovieClip, unit:MovieClip;
    private static var loader:MovieClipLoader, listener:Object;
    private static var passed:Number, failed:Number, ticks:Number, checkedFrames:Number;
    private static var ready:Boolean, finished:Boolean;

    private static function check(ok:Boolean, name:String):Void {
        if (ok) passed++;
        else { failed++; trace("[TEST_FAIL] BeastVariantAssetTest: " + name); }
    }

    public static function runAllTests():Void {
        passed = failed = ticks = checkedFrames = 0;
        ready = finished = false;
        library = _root.createEmptyMovieClip("__beastVariantLibrary", _root.getNextHighestDepth());
        driver = _root.createEmptyMovieClip("__beastVariantDriver", _root.getNextHighestDepth());
        library._visible = false;
        _root.gameworld = library;
        _root.暂停 = false;
        _root.控制目标 = "__no_player";
        _root.控制目标全自动 = false;
        _root.是否阴影 = true;
        _root.播放音效 = function():Void {};
        _root.发布消息 = function():Void {};
        _root.效果 = function():Void {};
        _root.add2map = function():Void {};
        _root.add2map2 = function():Void {};
        _root.子弹属性初始化 = function():Object { return {}; };
        _root.子弹区域shoot传递 = function():Void {};
        _root.子弹区域shoot = function():Void {};
        _root.初始化思考标签 = function(mc:MovieClip):Void {
            mc._name = "思考标签";
            mc.stop();
            mc._visible = false;
        };
        _root.敌人二级函数 = {
            攻击时移动: function():Void {},
            X轴追踪移动: function():Void {},
            Z轴追踪移动: function():Void {},
            计算攻击角度: function():Void {},
            固定角度移动: function():Void {}
        };
        _root.初始化敌人模板 = function():Void {
            this.hp = this.hp满血值 = 1000;
            this.空手攻击力 = 100;
            this.等级 = 30;
            this.状态 = "空手站立";
            this.攻击模式 = "空手";
            this.方向 = "右";
            this.攻击目标 = "无";
            this.fixtureDone = 0;
            this.swapDepths = function():Void {};
            this.行走 = function():Void {};
            this.移动 = function():Void {};
            this.方向改变 = function():Void {};
            this.配置音效 = function():Void {};
            this.动画完毕 = function():Void {
                this.fixtureDone++;
                this.man.stop();
            };
            this.stop();
        };
        listener = {
            onLoadInit: function(mc:MovieClip):Void {
                BeastVariantAssetTest.loaded(mc);
            },
            onLoadError: function(mc:MovieClip, error:String):Void {
                BeastVariantAssetTest.check(false, "load " + error);
                BeastVariantAssetTest.finish();
            }
        };
        loader = new MovieClipLoader();
        loader.addListener(listener);
        check(loader.loadClip("../flashswf/arts/new/3XD做的npc.swf", library), "load actual published 3XD做的npc.swf");
        driver.onEnterFrame = function():Void {
            BeastVariantAssetTest.tick();
        };
    }

    private static function loaded(mc:MovieClip):Void {
        mc.stop();
        unit = library.attachMovie("敌人-兽化变种", "beastVariant", library.getNextHighestDepth());
        check(unit != null, "attach 敌人-兽化变种");
        unit.近战招式 = "连击刺";
        unit.gotoAndStop("近战");
        check(unit.man != null, "attach native attack timeline");
        unit.man.stop();
        ready = true;
        ticks = 0;
    }

    private static function rasterizeFrame(frameNumber:Number):Number {
        var source:MovieClip = unit.man;
        source.gotoAndStop(frameNumber);
        var b:Object = source.getBounds(source);
        if (!(b.xMax > b.xMin && b.yMax > b.yMin)) return 0;
        var scale:Number = Math.min(96 / (b.xMax - b.xMin), 96 / (b.yMax - b.yMin));
        var matrix:Matrix = new Matrix(scale, 0, 0, scale, 6 - b.xMin * scale, 6 - b.yMin * scale);
        var bitmap:BitmapData = new BitmapData(108, 108, true, 0);
        bitmap.draw(source, matrix);
        var visible:Number = 0;
        for (var y:Number = 0; y < 108; y += 4) {
            for (var x:Number = 0; x < 108; x += 4) {
                if ((bitmap.getPixel32(x, y) >>> 24) > 64) visible++;
            }
        }
        bitmap.dispose();
        return visible;
    }

    private static function checkSequence(label:String, firstFrame:Number, lastFrame:Number, expectedFrame:Number):Void {
        unit.man.gotoAndStop(label);
        check(unit.man._currentframe == expectedFrame, label + " label enters frame " + expectedFrame);
        var emptyFrames:String = "";
        for (var frameNumber:Number = firstFrame; frameNumber <= lastFrame; frameNumber++) {
            var visible:Number = rasterizeFrame(frameNumber);
            checkedFrames++;
            if (visible < 20) emptyFrames += frameNumber + "(" + visible + ") ";
        }
        check(emptyFrames == "", label + " all native frames contain actual body pixels " + emptyFrames);
    }

    private static function tick():Void {
        if (finished) return;
        ticks++;
        if (!ready) {
            if (ticks > 300) {
                check(false, "load timeout");
                finish();
            }
            return;
        }
        if (ticks != 3) return;
        checkSequence("连击刺", 2, 88, 2);
        checkSequence("崩地", 90, 170, 90);
        var boundaryPixels:Number = rasterizeFrame(89);
        checkedFrames++;
        check(boundaryPixels >= 20, "former empty separator frame 89 retains body pixels (" + boundaryPixels + ")");
        check(checkedFrames == 169, "both attacks and separator cover 169 actual frames");
        finish();
    }

    private static function finish():Void {
        if (finished) return;
        finished = true;
        delete driver.onEnterFrame;
        if (loader != null) loader.removeListener(listener);
        trace("BeastVariantAssetTest: " + passed + " passed, " + failed + " failed; " + checkedFrames + " actual attack frames");
        library.removeMovieClip();
        driver.removeMovieClip();
        unit = null;
        _root.beastVariantAssetComplete();
    }
}
