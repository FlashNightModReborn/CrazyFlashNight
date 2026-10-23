import flash.display.BitmapData;
import flash.geom.Matrix;
import org.flashNight.arki.scene.*;
import org.flashNight.gesh.depth.DepthManager;

/** Born-known-none geometry and ownership contract. Unknown actor-level masks are explicitly rejected. */
class org.flashNight.arki.scene.Cf6ActorMaskKnownNoneTest {
    private static var passed:Number;
    private static var failed:Number;
    private static var fixtureSerial:Number=0;
    private static var pending:Object;
    private static var geometryRows:Array;
    private static var geometryIndex:Number;
    private static var waitFrames:Number;
    private static var watch:MovieClip;
    private static var saved:Object;
    private static function check(ok:Boolean,label:String):Void {
        if(ok) passed++;else {failed++;trace("[FAIL] Cf6ActorMaskPresentation: "+label);}
    }
    private static function rect(mc:MovieClip,x:Number,y:Number,w:Number,h:Number,color:Number):Void {
        mc.beginFill(color,100);mc.moveTo(x,y);mc.lineTo(x+w,y);mc.lineTo(x+w,y+h);
        mc.lineTo(x,y+h);mc.lineTo(x,y);mc.endFill();
    }
    private static function setup(nested:Boolean,sx:Number,sy:Number,unique:Boolean):Object {
        // Reusing a removed path in the same AVM1 frame contaminates native bounds.
        // Geometry fixtures use fresh paths; explicit actor-replacement tests remain below.
        var name:String="__cf6MaskPresentationUnique"+(++fixtureSerial);
        var fixture:MovieClip=_root.createEmptyMovieClip(name,_root.getNextHighestDepth());
        var world:MovieClip=fixture.createEmptyMovieClip("world",0);
        world._x=37;world._y=23;world.__stageReturnWorldIdentity={};_root.gameworld=world;
        world.getNextHighestDepth=function():Number {return 900000+(this.__counter=this.__counter==undefined ? 1 : this.__counter+1);};
        DepthManager.instance=new DepthManager(world,0,870655,16);DepthManager.instance.calibrate(0,200);
        var room:Object={world:world,owner:world.__stageReturnWorldIdentity};world.__cf6Mechanism=room;
        var session:Object=Cf6PropDepthService.begin(world,room.owner,room);
        var init:Object=Cf6ActorMaskState.prepare(world,room.owner,"hero",{});
        var actor:MovieClip=world.createEmptyMovieClip("hero",world.getNextHighestDepth());
        for(var initKey:String in init) actor[initKey]=init[initKey];
        Cf6ActorMaskState.bind(actor,init);
        actor._x=80;actor._y=60;actor.Z轴坐标=60;actor._xscale=sx;actor._yscale=sy;actor.hp=100;
        DepthManager.instance.updateDepth(actor,60);_root.控制目标="hero";
        var man:MovieClip=actor.createEmptyMovieClip("man",0);
        rect(man,-16,-24,16,24,0xFF0000);rect(man,0,-24,16,24,0x00FF00);
        var foreign:MovieClip=world.createEmptyMovieClip("foreignMask",world.getNextHighestDepth());
        rect(foreign,70,0,40,100,0xFFFFFF);foreign._visible=false;
        if(nested) {
            var inner:MovieClip=actor.createEmptyMovieClip("innerMask",1);
            rect(inner,-8,-24,24,24,0xFFFFFF);man.setMask(inner);
        }
        var mask:Object=Cf6PropDepthService.create(session,"doorMask",0,0,80);
        var art:MovieClip=mask.holder.createEmptyMovieClip("art",0);
        rect(art,0,0,200,120,0xFFFFFF);mask.holder._visible=false;
        var token:Object={};actor.__cf6TraversalOwner=token;
        var t:Object={room:room,actor:actor,token:token,closed:false,acquired:true,lastVisible:true};
        return {fixture:fixture,world:world,actor:actor,foreign:foreign,room:room,session:session,mask:mask,t:t};
    }
    private static function snapshot(e:Object):Array {
        var bitmap:BitmapData=new BitmapData(200,150,true,0);bitmap.draw(e.fixture);
        // Interior and exterior samples avoid demanding bitmap/vector antialias identity at edges.
        var points:Array=[[64,36],[76,36],[88,36],[100,36],[76,52],[88,52],[112,36],[88,65],
            [68,44],[72,44],[96,44],[108,44]];
        var values:Array=[];
        for(var i:Number=0;i<points.length;i++) values.push(bitmap.getPixel32(points[i][0]+37,points[i][1]+23));
        bitmap.dispose();return values;
    }
    private static function same(a:Array,b:Array):Boolean {
        for(var i:Number=0;i<a.length;i++) if(a[i]!==b[i]) return false;
        return true;
    }
    private static function nonempty(a:Array):Boolean {
        for(var i:Number=0;i<a.length;i++) if(a[i]!==0) return true;
        return false;
    }
    private static function close(e:Object):Void {
        Cf6ActorMaskPresentation.release(e.p);Cf6PropDepthService.end(e.session);
        DepthManager.instance.dispose();e.fixture.removeMovieClip();
    }
    private static function diagnose(e:Object,label:String):Void {
        var local:Object=e.actor.getBounds(e.actor),parent:Object=e.actor.getBounds(e.world);
        var m:Matrix=e.actor.transform.matrix,globalMatrix:Matrix=e.actor.transform.concatenatedMatrix;
        trace("Cf6KnownNoneDiagnostic "+label+" actor="+e.actor+" world="+e.world
            +" local="+local.xMin+","+local.yMin+","+local.xMax+","+local.yMax
            +" parent="+parent.xMin+","+parent.yMin+","+parent.xMax+","+parent.yMax
            +" matrix="+m.a+","+m.b+","+m.c+","+m.d+","+m.tx+","+m.ty);
        var diagnostic:BitmapData=new BitmapData(320,240,true,0);
        var matrices:Array=[new Matrix(1,0,0,1,100,100),m,globalMatrix];
        for(var i:Number=0;i<matrices.length;i++) {
            diagnostic.fillRect(diagnostic.rectangle,0);diagnostic.draw(e.actor,matrices[i]);
            var bounds:Object=diagnostic.getColorBoundsRect(0xFF000000,0,false);
            trace("Cf6KnownNoneDiagnostic "+label+" mode="+i+" pixels="+bounds.x+","+bounds.y+","+bounds.width+","+bounds.height);
        }
        diagnostic.dispose();
    }
    private static function geometry(e:Object,nested:Boolean,sx:Number,sy:Number):Void {
        var original:Array=snapshot(e);
        check(nonempty(original),"nonzero transformed reference has visible actor");
        diagnose(e,"before-create "+sx+" nested="+nested);
        e.p=Cf6ActorMaskPresentation.create(e.t,e.session,e.mask);
        diagnose(e,"after-create "+sx+" nested="+nested);
        var rendered:Boolean=e.p!=null && Cf6ActorMaskPresentation.render(e.p,60,true);
        check(rendered,"transformed actor captures successfully; reason="+e.p.failure);
        check(e.actor._visible===true,"proxy never hides actor itself");
        e.actor._visible=false;e.t.lastVisible=false;
        check(same(original,snapshot(e)),"proxy matches world-position/mirror/scale and internal child-mask pixels");
        check(Cf6ActorMaskPresentation.render(e.p,60,false) && same(original,snapshot(e)),"hidden actor remains capturable under nested masks");
        check(e.p.ticket.holder.getDepth()===DepthManager.instance.getDepth(e.p.ticket.holder)
            && e.p.ticket.sortY===60,"proxy uses owned world footpoint depth");
        Cf6ActorMaskPresentation.release(e.p);e.actor._visible=true;e.t.lastVisible=true;
        check(same(original,snapshot(e)) && e.actor.man._parent===e.actor,"release leaves internal masks and parent chain intact");
        close(e);
    }
    private static function lifecycle(e:Object):Void {
        e.p=Cf6ActorMaskPresentation.create(e.t,e.session,e.mask);
        check(Cf6ActorMaskPresentation.create(e.t,e.session,e.mask)==null,"duplicate proxy cannot steal ownership");
        var rendered:Boolean=Cf6ActorMaskPresentation.render(e.p,60,true);
        check(rendered,"lifecycle fixture starts; reason="+e.p.failure);
        e.actor._visible=false;e.t.lastVisible=false;
        var fullMask:Array=snapshot(e);
        e.mask.holder.art.clear();rect(e.mask.holder.art,78,0,16,120,0xFFFFFF);
        var narrowMask:Array=[];
        for(var sampleIndex:Number=0;sampleIndex<fullMask.length;sampleIndex++)
            narrowMask.push(sampleIndex==2 || sampleIndex==5 || sampleIndex==7 ? fullMask[sampleIndex] : 0);
        check(Cf6ActorMaskPresentation.render(e.p,60,false) && nonempty(narrowMask)
            && same(narrowMask,snapshot(e)) && e.actor._visible===false,
            "owned door mask narrows only the proxy under mirror, scale and child mask");
        e.mask.holder.art.clear();rect(e.mask.holder.art,0,0,200,120,0xFFFFFF);
        check(Cf6ActorMaskPresentation.render(e.p,60,false) && same(fullMask,snapshot(e))
            && Cf6ActorMaskState.isKnownNone(e.actor),"restoring owned mask restores proxy without changing actor mask history");
        e.actor._visible=true;
        check(!Cf6ActorMaskPresentation.render(e.p,60,false) && e.actor._visible===true && e.p.closed,
            "external visibility change retires proxy without overriding actor");
        e.t.lastVisible=true;e.p=Cf6ActorMaskPresentation.create(e.t,e.session,e.mask);
        e.actor.hp=0;
        check(!Cf6ActorMaskPresentation.render(e.p,60,true) && e.p.bitmap==null,"death frees bitmap and proxy");
        e.actor.hp=100;e.p=Cf6ActorMaskPresentation.create(e.t,e.session,e.mask);
        _root.控制目标="other";
        check(!Cf6ActorMaskPresentation.render(e.p,60,true),"control target change rejects old proxy");
        _root.控制目标="hero";e.p=Cf6ActorMaskPresentation.create(e.t,e.session,e.mask);
        e.t.token={};e.actor.__cf6TraversalOwner=e.t.token;
        check(!Cf6ActorMaskPresentation.render(e.p,60,true),"new traversal token cannot revive old proxy");
        e.p=Cf6ActorMaskPresentation.create(e.t,e.session,e.mask);
        e.actor.setMask(e.foreign);
        check(!Cf6ActorMaskState.isKnownNone(e.actor) && !Cf6ActorMaskPresentation.render(e.p,60,true)
            && e.actor._visible===true,"new actor-level mask cancels proxy without hiding source");
        var nativeClear=e.actor.setMask(null);
        check(nativeClear===true && Cf6ActorMaskState.isKnownNone(e.actor),"native successful clear re-establishes known-none");
        var wrapper:Function=e.actor.setMask;e.actor.setMask=function():Boolean {return false;};
        check(Cf6ActorMaskPresentation.create(e.t,e.session,e.mask)==null,"overridden instance wrapper is rejected");
        e.actor.setMask=wrapper;
        check(!Cf6ActorMaskState.isKnownNone(e.actor),"restoring wrapper alone does not erase unknown history");
        e.actor.setMask(null);
        check(Cf6ActorMaskState.isKnownNone(e.actor),"explicit successful clear after wrapper restoration is known-none");
        e.p=Cf6ActorMaskPresentation.create(e.t,e.session,e.mask);
        e.mask.holder.art.removeMovieClip();
        var replacement:MovieClip=e.mask.holder.createEmptyMovieClip("art",0);rect(replacement,0,0,200,120,0xFFFFFF);
        check(!Cf6ActorMaskPresentation.render(e.p,60,true) && replacement._name=="art","same-path late mask replacement is preserved and rejected");
        e.p=Cf6ActorMaskPresentation.create(e.t,e.session,e.mask);e.actor.man._visible=false;
        check(!Cf6ActorMaskPresentation.render(e.p,60,true) && e.p.bitmap==null,"blank capture is not success");
        e.actor.man._visible=true;e.p=Cf6ActorMaskPresentation.create(e.t,e.session,e.mask);
        rect(e.actor.man,0,0,3000,10,0x0000FF);
        check(!Cf6ActorMaskPresentation.render(e.p,60,true) && e.p.closed,"bounds budget rejects oversized capture");
        e.t.closed=true;
        check(Cf6ActorMaskPresentation.create(e.t,e.session,e.mask)==null,"late mask readiness cannot acquire a closed traversal");
        close(e);
        e=setup(false,150,200);e.p=Cf6ActorMaskPresentation.create(e.t,e.session,e.mask);
        var nextInit:Object=Cf6ActorMaskState.prepare(e.world,e.room.owner,"hero",{});
        e.actor.removeMovieClip();var foreign:MovieClip=e.world.createEmptyMovieClip("hero",e.world.getNextHighestDepth());
        for(var nextKey:String in nextInit) foreign[nextKey]=nextInit[nextKey];
        Cf6ActorMaskState.bind(foreign,nextInit);foreign.__cf6TraversalOwner=e.t.token;foreign.hp=100;
        foreign.keep={};var keep:Object=foreign.keep;
        check(!Cf6ActorMaskPresentation.render(e.p,60,true) && foreign.keep===keep && foreign._visible,
            "same-path actor replacement cannot be captured or hidden");
        close(e);
        e=setup(false,150,200);e.p=Cf6ActorMaskPresentation.create(e.t,e.session,e.mask);
        var identity:Object={};e.world.__stageReturnWorldIdentity=identity;
        check(!Cf6ActorMaskPresentation.render(e.p,60,true) && e.world.__stageReturnWorldIdentity===identity,
            "replacement world identity remains untouched");
        close(e);
    }
    public static function runAllTests():Void {
        passed=0;failed=0;
        saved={world:_root.gameworld,manager:DepthManager.instance,control:_root.控制目标};
        geometryRows=[[false,150,200],[false,-150,200],[true,150,200],[true,-150,200]];
        geometryIndex=0;
        watch=_root.createEmptyMovieClip("__cf6MaskPresentationWatch",_root.getNextHighestDepth());
        watch.onEnterFrame=function():Void {org.flashNight.arki.scene.Cf6ActorMaskKnownNoneTest.tick();};
        prepare();
    }
    private static function prepare():Void {
        var row:Array=geometryIndex<4 ? geometryRows[geometryIndex] : [true,-150,200];
        pending=setup(row[0],row[1],row[2],true);waitFrames=0;
    }
    public static function tick():Void {
        if(++waitFrames<3) return;
        if(geometryIndex<4) {
            var row:Array=geometryRows[geometryIndex];
            geometry(pending,row[0],row[1],row[2]);geometryIndex++;prepare();return;
        }
        lifecycle(pending);
        delete watch.onEnterFrame;watch.removeMovieClip();pending=null;
        _root.gameworld=saved.world;DepthManager.instance=saved.manager;_root.控制目标=saved.control;
        trace("Cf6ActorMaskKnownNoneTest Tests Passed: "+passed);
        trace("Cf6ActorMaskKnownNoneTest Tests Failed: "+failed);
        _root.cf6ActorMaskKnownNoneComplete();
    }
}
