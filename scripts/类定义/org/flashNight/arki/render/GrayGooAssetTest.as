import org.flashNight.arki.component.Effect.EffectSystem;
import org.flashNight.arki.component.Buff.BuffManager;
import org.flashNight.arki.bullet.BulletComponent.Queue.BulletHitEffectRegistry;
import org.flashNight.arki.component.Damage.DamageResult;
import org.flashNight.arki.item.equipment.ModRegistry;
import org.flashNight.gesh.xml.XMLParser;
import org.flashNight.neur.Event.EventDispatcher;

/** 真实灰蛊 XML/发布素材经生产 EffectSystem 验证三档与回池；零存档写。 */
class org.flashNight.arki.render.GrayGooAssetTest {
    private static var world:MovieClip, host:MovieClip, target:MovieClip, watcher:MovieClip;
    private static var oldWorld:Object, oldVisual:Object;
    private static var oldPoolMode:Boolean, oldLimit:Number;
    private static var oldMods:Array, behavior:Object, shooter:Object;
    private static var loader:MovieClipLoader, listener:Object;
    private static var passed:Number, failed:Number, frame:Number, phase:Number, waitAt:Number;
    private static var finished:Boolean, thirdName:String;

    private static function check(ok:Boolean, label:String):Void {
        if (ok) passed++;
        else { failed++; trace("[FAIL] GrayGooAssetTest " + label); }
    }

    public static function runAllTests():Void {
        passed=0; failed=0; frame=0; phase=0; finished=false;
        oldWorld=_root.gameworld; oldVisual=_root.是否视觉元素;
        oldPoolMode=EffectSystem.isDeathEffect; oldLimit=EffectSystem.maxEffectCount;
        oldMods=ModRegistry.getModList();
        world=_root.createEmptyMovieClip("grayGooAssetWorld",_root.getNextHighestDepth());
        _root.gameworld=world; _root.是否视觉元素=true;
        world._xscale=world._yscale=100;
        EffectSystem.isDeathEffect=true; EffectSystem.maxEffectCount=20;
        EffectSystem.initializeEffectPool();
        watcher=_root.createEmptyMovieClip("grayGooAssetWatch",_root.getNextHighestDepth());
        watcher.onEnterFrame=function():Void { GrayGooAssetTest.tick(); };
        var document:XML=new XML(); document.ignoreWhite=true;
        document.onLoad=function(ok:Boolean):Void {
            if (!ok) { GrayGooAssetTest.check(false,"actual XML loaded"); GrayGooAssetTest.finish(); return; }
            var parsed:Object=XMLParser.parseXMLNode(this.firstChild);
            ModRegistry.loadModData(XMLParser.configureDataAsArray(parsed.mod));
            var mod:Object=ModRegistry.getModData("灰蛊裂隙弹");
            var cases:Array=ModRegistry.matchUseSwitchAll(mod,ModRegistry.buildItemUseLookup("手枪","手枪"));
            GrayGooAssetTest.behavior=cases[0].override.hitBehavior;
            GrayGooAssetTest.check(GrayGooAssetTest.behavior.hitStacks==3 && GrayGooAssetTest.behavior.crumblePerMilestone==0.3,
                "actual handgun profile selected");
            GrayGooAssetTest.loadAsset();
        };
        document.load("../data/items/equipment_mods/高等材料_枪械专用.xml");
    }

    private static function loadAsset():Void {
        host=world.createEmptyMovieClip("library",world.getNextHighestDepth());
        listener={};
        listener.onLoadInit=function(loaded:MovieClip):Void {
            loaded.stop();
            for (var key:String in loaded) {
                if (typeof loaded[key]=="movieclip") loaded[key]._visible=false;
            }
            GrayGooAssetTest.world.效果=loaded.createEmptyMovieClip("effects",loaded.getNextHighestDepth());
            GrayGooAssetTest.target=GrayGooAssetTest.world.createEmptyMovieClip("target",GrayGooAssetTest.world.getNextHighestDepth());
            var t:MovieClip=GrayGooAssetTest.target;
            t._x=160; t._y=190;
            t.beginFill(0x202020); t.moveTo(-8,0); t.lineTo(8,0); t.lineTo(8,-40); t.lineTo(-8,-40); t.lineTo(-8,0); t.endFill();
            t.damageTakenMultiplier=1; t.dispatcher=new EventDispatcher(); t.buffManager=new BuffManager(t,null);
            GrayGooAssetTest.shooter={name:"grayGooAssetShooter"};
            GrayGooAssetTest.phase=1;
            GrayGooAssetTest.fireTwice();
            GrayGooAssetTest.waitAt=GrayGooAssetTest.frame+2;
        };
        listener.onLoadError=function(loaded:MovieClip,error:String):Void {
            GrayGooAssetTest.check(false,"actual SWF " + error); GrayGooAssetTest.finish();
        };
        loader=new MovieClipLoader(); loader.addListener(listener);
        check(loader.loadClip("../flashswf/arts/new/Codex专用素材.swf",host),"actual published SWF submitted");
    }

    private static function fireTwice():Void {
        for (var i:Number=0;i<2;i++) {
            var bullet:Object={hitBehavior:behavior,击溃:0,斩杀:0};
            BulletHitEffectRegistry.prepare(bullet,shooter,target);
            var result:DamageResult=new DamageResult(); result.dodgeStatus="";
            BulletHitEffectRegistry.apply(bullet,shooter,target,result);
        }
    }

    private static function active(stage:Number):MovieClip {
        var layer:MovieClip=world.效果;
        for (var key:String in layer) {
            var clip:MovieClip=layer[key];
            if (typeof clip=="movieclip" && clip._visible && clip.targetFrame==stage) return clip;
        }
        return null;
    }

    private static function verifyStage(stage:Number):Void {
        var effect:MovieClip=active(stage);
        check(effect!=null && effect.effectType=="灰蛊裂隙特效","real EffectSystem attaches stage " + stage);
        check(effect.标志._parent===effect && effect.标志._currentframe==stage,"authored marker stops at stage " + stage);
        var bounds:Object=effect.标志.getBounds(effect.标志);
        check(bounds.xMax>bounds.xMin && bounds.yMax>bounds.yMin,"stage has nonempty authored geometry " + stage);
        if (stage==3) thirdName=effect._name;
    }

    private static function tick():Void {
        if (finished) return;
        frame++;
        if (frame>900) { check(false,"asset/frame watchdog"); finish(); return; }
        if (phase==0 || frame<waitAt) return;
        if (phase<4) {
            verifyStage(phase);
            phase++;
            if (phase<4) { fireTwice(); waitAt=frame+2; }
            else {
                fireTwice();
                check(target.grayGooMilestoneTriggerCount==3,"18/18 sustained fire adds no marker");
                waitAt=frame+40;
            }
        } else if (phase==4) {
            var pool:Array=world.effectPools["灰蛊裂隙特效"];
            check(pool.length==3,"all three real timelines return to production pool");
            check(!active(1) && !active(2) && !active(3),"returned timelines are hidden");
            target.buffManager.update(420);
            fireTwice();
            check(pool.length==2,"next cycle reuses a pooled clip");
            phase=5; waitAt=frame+2;
        } else {
            var reused:MovieClip=active(1);
            check(reused._name==thirdName,"highest stage clip is reused for a lower stage");
            check(reused.标志._currentframe==1,"pooled stage III resets to stage I");
            trace("GrayGooAssetTest phases: XML,I,II,III,max,pooled,reuse");
            finish();
        }
    }

    private static function finish():Void {
        if (finished) return; finished=true;
        delete watcher.onEnterFrame;
        if (target) { target.buffManager.clearAllBuffs(); target.buffManager.destroy(); target.dispatcher.destroy(); }
        if (loader) loader.removeListener(listener);
        world.removeMovieClip(); watcher.removeMovieClip();
        _root.gameworld=oldWorld; _root.是否视觉元素=oldVisual;
        EffectSystem.isDeathEffect=oldPoolMode; EffectSystem.maxEffectCount=oldLimit;
        if (oldMods.length>0) ModRegistry.loadModData(oldMods);
        trace("GrayGooAssetTest result: passed="+passed+" failed="+failed);
        _root.grayGooAssetComplete();
    }
}
