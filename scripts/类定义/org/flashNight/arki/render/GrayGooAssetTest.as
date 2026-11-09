import org.flashNight.arki.component.Effect.EffectSystem;
import org.flashNight.arki.component.Buff.BuffManager;
import org.flashNight.arki.bullet.BulletComponent.Queue.BulletHitEffectRegistry;
import org.flashNight.arki.component.Damage.DamageResult;
import org.flashNight.arki.item.equipment.ModRegistry;
import org.flashNight.gesh.xml.XMLParser;
import org.flashNight.neur.Event.EventDispatcher;
import org.flashNight.arki.component.Damage.CrumbleDamageHandle;
import flash.display.BitmapData;

/** 真实灰蛊 XML/发布素材经生产 EffectSystem 验证三档与回池；零存档写。 */
class org.flashNight.arki.render.GrayGooAssetTest {
    private static var world:MovieClip, host:MovieClip, target:MovieClip, watcher:MovieClip;
    private static var oldWorld:Object, oldVisual:Object;
    private static var oldPoolMode:Boolean, oldLimit:Number;
    private static var oldMods:Array, behavior:Object, shooter:Object;
    private static var loader:MovieClipLoader, listener:Object;
    private static var passed:Number, failed:Number, frame:Number, phase:Number, waitAt:Number;
    private static var finished:Boolean, thirdName:String;
    private static var lastCrumble:Number, preview:BitmapData;
    private static var foreignMark:MovieClip;

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
        world._x=20; world._y=18; world._xscale=world._yscale=75;
        EffectSystem.isDeathEffect=true; EffectSystem.maxEffectCount=0;
        preview=null; lastCrumble=0;
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
            t._x=260; t._y=370; t._xscale=-150; t._yscale=120;
            t.beginFill(0x202020); t.moveTo(-8,0); t.lineTo(8,0); t.lineTo(8,-40); t.lineTo(-8,-40); t.lineTo(-8,0); t.endFill();
            t.icX=0; t.icY=-65;
            var info:MovieClip=t.createEmptyMovieClip("新版人物文字信息",t.getNextHighestDepth());
            info._y=-65; info.beginFill(0xAACC88); info.moveTo(-12,0); info.lineTo(12,0);
            info.lineTo(12,4); info.lineTo(-12,4); info.lineTo(-12,0); info.endFill();
            var decoy:MovieClip=t.createEmptyMovieClip("inflatedAttachment",t.getNextHighestDepth());
            decoy._y=-1400; decoy.beginFill(0xFF0000); decoy.moveTo(0,0); decoy.lineTo(10,0);
            decoy.lineTo(10,10); decoy.lineTo(0,10); decoy.lineTo(0,0); decoy.endFill(); decoy._visible=false;
            GrayGooAssetTest.check(t._height>900,"fixture reproduces oversized root bounds");
            t.hp满血值=72968; t.hp=72968; t.损伤值=0;
            t.damageTakenMultiplier=1; t.dispatcher=new EventDispatcher(); t.buffManager=new BuffManager(t,null);
            var foreign:MovieClip=GrayGooAssetTest.world.效果.createEmptyMovieClip("foreignMark",GrayGooAssetTest.world.效果.getNextHighestDepth());
            foreign.grayGooTargetKey="another-unit"; foreign.createEmptyMovieClip("标志",1);
            GrayGooAssetTest.foreignMark=foreign; t.grayGooLastMarkEffect=foreign;
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
            var bullet:Object={hitBehavior:behavior,击溃:0,斩杀:0,子弹威力:100,additionalEffectDamage:0};
            BulletHitEffectRegistry.prepare(bullet,shooter,target);
            var result:DamageResult=new DamageResult(); result.dodgeStatus="";
            var before:Number=Number(target.hp满血值);
            if (bullet.击溃>0) CrumbleDamageHandle.getInstance().handleBulletDamage(bullet,shooter,target,null,result);
            lastCrumble=before-Number(target.hp满血值);
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
        var position:Object={x:0,y:0}; effect.localToGlobal(position);
        var infoBounds:Object=target.新版人物文字信息.getBounds(_root);
        check(position.y>=48 && position.y<infoBounds.yMin && infoBounds.yMin-position.y<100,
            "nameplate anchor stays visible with inflated bounds, camera scale and flipped actor " + stage);
        check(effect.grayGooCrumbleAmount==lastCrumble && lastCrumble>0
            && effect.击溃爆发._visible && effect.击溃爆发._currentframe==stage
            && effect.击溃爆发.动画._currentframe>=1 && effect.击溃爆发.动画._currentframe<=5,
            "authored crumble burst follows real ceiling loss and stage " + stage);
        var burstBounds:Object=effect.击溃爆发.动画.getBounds(effect.击溃爆发);
        check(burstBounds.xMax-burstBounds.xMin>20 && burstBounds.yMax-burstBounds.yMin>20,
            "real authored burst has visible vector geometry " + stage);
        check(Math.abs(effect._xscale*world._xscale/100-100)<0.01
            && Math.abs(effect._yscale*world._yscale/100-100)<0.01,"both display axes keep readable size " + stage);
        if (stage>1) check(!active(stage-1).标志._visible && effect.标志._visible,
            "only the latest progress mark remains visible " + stage);
        else {
            check(foreignMark.标志._visible,"a cached effect now owned by another unit is not hidden");
            foreignMark.removeMovieClip();
        }
        if (stage==3) thirdName=effect._name;
    }

    private static function tick():Void {
        if (finished) return;
        frame++;
        if (frame>900) { check(false,"asset/frame watchdog"); finish(); return; }
        if (phase==0 || frame<waitAt) return;
        if (phase<4) {
            verifyStage(phase);
            if (phase==3) {
                try {
                    preview=new BitmapData(Stage.width,Stage.height,false,0x17222B);
                    preview.draw(world,world.transform.matrix);
                } catch (captureError) {
                    if (preview) preview.dispose(); preview=null;
                    trace("GrayGooAssetTest visual snapshot unavailable: "+captureError);
                }
            }
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
        } else if (phase==5) {
            var reused:MovieClip=active(1);
            check(reused._name==thirdName,"highest stage clip is reused for a lower stage");
            check(reused.标志._currentframe==1,"pooled stage III resets to stage I");
            check(reused.标志._visible && reused.击溃爆发._visible && reused.击溃爆发._currentframe==1
                && reused.击溃爆发.动画._currentframe>=1 && reused.击溃爆发.动画._currentframe<=5
                && reused.grayGooCrumbleAmount==lastCrumble,"pooled burst restarts for the current resolved loss");
            phase=6; waitAt=frame+40;
        } else if (phase==6) {
            target.hp满血值=1;
            check(target.hp满血值==1,"minimum ceiling fixture has no remaining crumble room");
            target.buffManager.update(420); fireTwice(); phase=7; waitAt=frame+2;
        } else {
            var zero:MovieClip=active(1);
            check(!zero.击溃爆发._visible && zero.grayGooFeedback==undefined,
                "zero resolved loss hides the burst and no floating amount text is created");
            check(zero.grayGooCrumbleAmount==0,"zero resolved loss does not copy a prior target amount");
            trace("GrayGooAssetTest phases: XML,I,II,III,max,pooled,reuse,zero-loss");
            finish();
        }
    }

    private static function finish():Void {
        if (finished) return; finished=true;
        delete watcher.onEnterFrame;
        if (target) { target.buffManager.clearAllBuffs(); target.buffManager.destroy(); target.dispatcher.destroy(); }
        if (loader) loader.removeListener(listener);
        world.removeMovieClip(); watcher.removeMovieClip();
        if (preview && failed==0) {
            var evidence:MovieClip=_root.createEmptyMovieClip("grayGooVisualEvidence",_root.getNextHighestDepth());
            evidence.attachBitmap(preview,1);
        } else if (preview) preview.dispose();
        _root.gameworld=oldWorld; _root.是否视觉元素=oldVisual;
        EffectSystem.isDeathEffect=oldPoolMode; EffectSystem.maxEffectCount=oldLimit;
        if (oldMods.length>0) ModRegistry.loadModData(oldMods);
        trace("GrayGooAssetTest result: passed="+passed+" failed="+failed);
        _root.grayGooAssetComplete();
    }
}
