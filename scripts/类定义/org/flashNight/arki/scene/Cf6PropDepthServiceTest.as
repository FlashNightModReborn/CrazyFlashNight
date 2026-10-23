import org.flashNight.arki.scene.*;
import org.flashNight.gesh.depth.DepthManager;
import flash.display.BitmapData;

/** Real MovieClip identity and display-list pixels, not an offline AS2 substitute. */
class org.flashNight.arki.scene.Cf6PropDepthServiceTest {
    private static var passed:Number;
    private static var failed:Number;
    private static function check(ok:Boolean, message:String):Void {
        if(ok) passed++; else {failed++;trace("[FAIL] Cf6PropDepthService: "+message);}
    }
    private static function world():MovieClip {
        var mc:MovieClip=_root.createEmptyMovieClip("__cf6PropDepthFixture",_root.getNextHighestDepth());
        _root.gameworld=mc;mc.__stageReturnWorldIdentity={};
        // Match SceneManager's creation staging contract without consuming real scene objects.
        var counter:Number=900000;
        mc.getNextHighestDepth=function():Number {return counter++;};
        DepthManager.instance=new DepthManager(mc,0,870655,8);
        DepthManager.instance.calibrate(0,100);
        return mc;
    }
    private static function square(mc:MovieClip, color:Number):Void {
        mc.beginFill(color,100);mc.moveTo(10,10);mc.lineTo(30,10);
        mc.lineTo(30,30);mc.lineTo(10,30);mc.lineTo(10,10);mc.endFill();
    }
    private static function pixel(mc:MovieClip):Number {
        var bitmap:BitmapData=new BitmapData(40,40,true,0);
        bitmap.draw(mc);var result:Number=bitmap.getPixel(20,20);bitmap.dispose();return result;
    }
    public static function runAllTests():Void {
        passed=0;failed=0;
        var savedWorld:MovieClip=_root.gameworld;
        var savedManager:DepthManager=DepthManager.instance;
        var w:MovieClip=world();var identity:Object=w.__stageReturnWorldIdentity;
        var owner:Object={};var api:Object=org.flashNight.arki.scene.Cf6PropDepthService;
        check(api.begin(w,{},owner)==null,"reject foreign world identity");
        check(api.begin(w,identity,null)==null,"reject absent owner");
        var session:Object=api.begin(w,identity,owner);
        check(session!=null,"bind current world and manager");
        check(api.begin(w,identity,owner)===session,"same owner begin is idempotent");
        check(api.begin(w,identity,{})==null,"cannot steal another owner session");
        check(api.create(session,"bad",0,0,Number("bad"))==null,"reject nonfinite sortY");
        var door:Object=api.create(session,"door",0,0,50);
        check(door!=null && door.holder._parent===w,"door is a direct world child");
        check(door.holder.getDepth()===DepthManager.instance.getDepth(door.holder),"uses actual unit depth manager");
        check(api.create(session,"door",0,0,50)===door,"duplicate layer returns same ticket");
        check(api.create(session,"door",0,0,60)==null,"duplicate conflicting specification rejected");
        var art:MovieClip=door.holder.createEmptyMovieClip("art",0);square(art,0xFF0000);
        var actor:MovieClip=w.createEmptyMovieClip("actor",w.getNextHighestDepth());square(actor,0x00FF00);
        DepthManager.instance.updateDepth(actor,40);
        check(pixel(w)==0xFF0000,"real pixels: character behind door");
        DepthManager.instance.updateDepth(actor,60);
        check(pixel(w)==0x00FF00,"real pixels: character in front of door");
        check(api.update(door,70) && pixel(w)==0xFF0000,"moving prop reorders with actual character");
        var before:Number=door.holder.getDepth();art._xscale=50;art._x=-7;
        check(api.update(door,70) && door.holder.getDepth()===before,"visual pivot and scale never rescale sortY");
        check(door.holder.getDepth()===before,"no independent animation or pause clock");
        check(!api.update(door,1/0) && door.sortY==70,"invalid update leaves previous depth");
        var savedToken:Object=door.holder.__cf6PropDepthToken;
        door.holder.__cf6PropDepthToken={};
        check(!api.valid(door),"holder ownership is exact");
        door.holder.__cf6PropDepthToken=savedToken;
        check(api.valid(door),"owned holder remains usable");
        var other:Object=api.create(session,"other",0,0,30);
        var replacedName:String=other.name;other.holder.removeMovieClip();
        var foreign:MovieClip=w.createEmptyMovieClip(replacedName,w.getNextHighestDepth());foreign.keep={};
        var keep:Object=foreign.keep;
        check(!api.valid(other),"same-path MovieClip replacement is not the old ticket");
        api.release(other);
        check(w[replacedName].keep===keep,"stale release preserves same-path foreign clip");
        api.end(session);api.end(session);
        check(door.closed===true && !api.valid(door),"death/retreat end closes all owned tickets idempotently");
        check(w[replacedName].keep===keep,"end preserves foreign replacement");
        check(!api.update(door,20) && api.create(session,"late",0,0,20)==null,"late callbacks cannot resurrect closed session");
        var next:Object=api.begin(w,identity,{});
        check(next!=null && next!==session,"fresh owner can begin after end");
        var late:Object=api.create(next,"lateWorld",0,0,50);
        DepthManager.instance.dispose();w.removeMovieClip();
        w=world();var newIdentity:Object=w.__stageReturnWorldIdentity;
        var fresh:Object=api.begin(w,newIdentity,{});
        var freshProp:Object=api.create(fresh,"fresh",0,0,50);
        check(!api.valid(late),"same-path world replacement rejects old callback");
        api.end(next);
        check(api.valid(freshProp),"old end cannot erase replacement world session");
        api.end(fresh);DepthManager.instance.dispose();
        DepthManager.instance=new DepthManager(w,0,870655,1);DepthManager.instance.calibrate(0,100);
        var limited:Object=api.begin(w,newIdentity,{});
        var first:Object=api.create(limited,"first",0,0,50);
        check(first!=null,"one available depth id accepts first prop");
        check(api.create(limited,"full",0,0,50)==null && DepthManager.instance.size()==1,"capacity failure leaves no unsorted live prop");
        api.release(first);
        check(DepthManager.instance.size()==0,"release returns depth id");
        var reused:Object=api.create(limited,"first",0,0,50);
        check(reused!=null && reused!==first,"released id gets fresh independent ticket");
        api.end(limited);DepthManager.instance.dispose();w.removeMovieClip();
        _root.gameworld=savedWorld;DepthManager.instance=savedManager;
        trace("Cf6PropDepthServiceTest Tests Passed: "+passed);
        trace("Cf6PropDepthServiceTest Tests Failed: "+failed);
    }
}
