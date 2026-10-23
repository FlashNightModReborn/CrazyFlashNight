import flash.display.BitmapData;

/** In-memory diagnostic only. Passing fixture checks does NOT approve a visual proxy. */
class org.flashNight.arki.scene.Cf6ActorMaskProbeTest {
    private static var passed:Number;
    private static var failed:Number;
    private static function check(ok:Boolean,message:String):Void {
        if(ok) passed++;else {failed++;trace("[FAIL] Cf6ActorMaskProbe: "+message);}
    }
    private static function rectangle(mc:MovieClip,x:Number,width:Number):Void {
        mc.beginFill(0x00FF00,100);mc.moveTo(x,0);mc.lineTo(x+width,0);
        mc.lineTo(x+width,16);mc.lineTo(x,16);mc.lineTo(x,0);mc.endFill();
    }
    private static function sample(mc:MovieClip):Array {
        var pixels:BitmapData=new BitmapData(16,16,true,0);
        pixels.draw(mc);
        var values:Array=[pixels.getPixel32(4,8),pixels.getPixel32(12,8)];
        pixels.dispose();return values;
    }
    private static function same(a:Array,b:Array):Boolean {return a[0]===b[0] && a[1]===b[1];}
    private static function describe(label:String,values:Array):Void {
        trace("Cf6ActorMaskProbe "+label+": "+values[0]+","+values[1]);
    }
    public static function runAllTests():Void {
        passed=0;failed=0;
        var world:MovieClip=_root.createEmptyMovieClip("__cf6ActorMaskProbe",_root.getNextHighestDepth());
        var actor:MovieClip=world.createEmptyMovieClip("actor",1);
        var man:MovieClip=actor.createEmptyMovieClip("man",0);rectangle(man,0,16);
        var foreignMask:MovieClip=world.createEmptyMovieClip("foreignMask",2);rectangle(foreignMask,8,8);
        var actorIdentity:Object={};actor.__probeIdentity=actorIdentity;
        // This is the fixture's pre-existing mask, not a production mask mutation.
        actor.setMask(foreignMask);
        var reference:Array=sample(world);describe("WorldReference",reference);
        check(reference[0]===0 && reference[1]!==0,"reference really clips the left half");
        var direct:Array=sample(actor);describe("DirectActor",direct);
        var body:Array=sample(man);describe("DirectMan",body);
        check(actor._parent===world && man._parent===actor,"sampling preserves original parent chain");
        actor._visible=false;
        var hidden:Array=sample(actor);describe("HiddenActor",hidden);
        var hiddenWorld:Array=sample(world);
        check(hiddenWorld[0]===0 && hiddenWorld[1]===0,"hidden live actor is absent from world rendering");
        actor._visible=true;
        var restored:Array=sample(world);describe("RestoredWorld",restored);
        check(same(restored,reference),"sampling and visibility restoration leave original mask intact");
        check(actor.__probeIdentity===actorIdentity,"sampling preserves logical actor identity");
        var safe:Boolean=same(direct,reference) && same(hidden,reference);
        trace("Cf6ActorMaskProbe UnknownActorMaskSafe: "+safe);
        trace("Cf6ActorMaskProbe DirectManPreservesActorMask: "+same(body,reference));
        // Contrast a child-local authored mask: the actor is now the capture root,
        // so this tests a different boundary and cannot substitute for UnknownActorMaskSafe.
        actor.setMask(null);
        var childMask:MovieClip=actor.createEmptyMovieClip("childMask",1);rectangle(childMask,8,8);
        man.setMask(childMask);
        var childReference:Array=sample(world);var childCapture:Array=sample(actor);
        describe("ChildMaskedActor",childCapture);
        check(childReference[0]===0 && childReference[1]!==0,"child-mask contrast fixture is clipped");
        trace("Cf6ActorMaskProbe ChildMaskPreserved: "+same(childReference,childCapture));
        world.removeMovieClip();
        trace("Cf6ActorMaskProbeTest Tests Passed: "+passed);
        trace("Cf6ActorMaskProbeTest Tests Failed: "+failed);
    }
}
