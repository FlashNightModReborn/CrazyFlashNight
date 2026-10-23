import flash.display.BitmapData;
import flash.geom.Matrix;
import org.flashNight.arki.scene.Cf6PropDepthService;
import org.flashNight.arki.scene.Cf6ActorMaskState;

/** A masked display proxy only. TraversalService alone owns actor visibility/control. */
class org.flashNight.arki.scene.Cf6ActorMaskPresentation {
    private static var serial:Number=0;
    private static var MAX_EDGE:Number=1024;
    private static var MAX_PIXELS:Number=524288;

    private static function finite(value):Boolean {
        return typeof value=="number" && (value-value)==0 && Math.abs(value)<1000000;
    }
    private static function traversalCurrent(t:Object):Boolean {
        return t!=null && t.closed!==true && t.acquired===true && t.token!=undefined
            && t.room.world===_root.gameworld
            && t.room.owner===_root.gameworld.__stageReturnWorldIdentity
            && t.room.world.__cf6Mechanism===t.room
            && t.actor===t.room.world[_root.控制目标] && t.actor._parent===t.room.world
            && t.actor.__cf6TraversalOwner===t.token && t.actor.hp>0;
    }
    public static function create(t:Object,depthSession:Object,maskTicket:Object):Object {
        if(!traversalCurrent(t) || !Cf6ActorMaskState.isKnownNone(t.actor)
                || t.__cf6ActorMaskPresentation!=undefined
                || depthSession.owner!==t.room || depthSession.identity!==t.room.owner
                || maskTicket.session!==depthSession || !Cf6PropDepthService.valid(maskTicket)
                || maskTicket.holder.__cf6ActorMaskConsumer!=undefined) return null;
        var art:MovieClip=maskTicket.holder.art;
        if(art._parent!==maskTicket.holder || !(art._width>0) || !(art._height>0)) return null;
        var ticket:Object=Cf6PropDepthService.create(depthSession,"actor-mask-"+(++serial),
            t.actor._x,t.actor._y,t.actor.Z轴坐标);
        if(ticket==null) return null;
        ticket.holder._visible=false;
        var p:Object={traversal:t,actor:t.actor,actorToken:t.token,controlName:_root.控制目标,
            worldIdentity:t.room.owner,session:depthSession,ticket:ticket,maskTicket:maskTicket,
            maskArt:art,maskBirth:Cf6ActorMaskState.identity(t.actor),token:{},closed:false,bitmap:null};
        p.surface=ticket.holder.createEmptyMovieClip("pixels",0);
        p.surface.__cf6ActorMaskSurface=p.token;
        maskTicket.holder.__cf6ActorMaskConsumer=p.token;
        art.__cf6ActorMaskArtToken=p.token;
        t.__cf6ActorMaskPresentation=p;
        // Only this newly-created proxy gets a mask. Never actor/man.setMask.
        ticket.holder.setMask(maskTicket.holder);
        return p;
    }
    private static function current(p:Object,expectedVisible:Boolean):Boolean {
        return p!=null && p.closed===false && traversalCurrent(p.traversal)
            && Cf6ActorMaskState.identity(p.actor)===p.maskBirth
            && p.traversal.__cf6ActorMaskPresentation===p
            && p.actor===p.traversal.actor && p.actorToken===p.traversal.token
            && _root.控制目标===p.controlName && p.traversal.room.owner===p.worldIdentity
            && p.actor._visible===expectedVisible && p.traversal.lastVisible===expectedVisible
            && Cf6PropDepthService.valid(p.ticket) && Cf6PropDepthService.valid(p.maskTicket)
            && p.ticket.session===p.session && p.maskTicket.session===p.session
            && p.maskTicket.holder.__cf6ActorMaskConsumer===p.token
            && p.surface._parent===p.ticket.holder && p.surface.__cf6ActorMaskSurface===p.token
            && p.maskArt._parent===p.maskTicket.holder
            && p.maskArt.__cf6ActorMaskArtToken===p.token
            && p.maskTicket.holder.art===p.maskArt;
    }
    /** Allocation boundary only; the steady draw path has no exception wrapper. */
    private static function allocate(width:Number,height:Number):BitmapData {
        var bitmap:BitmapData;
        try {bitmap=new BitmapData(width,height,true,0);} catch(error) {return null;}
        if(bitmap==null || bitmap.width!==width || bitmap.height!==height) {
            if(bitmap!=null) bitmap.dispose();
            return null;
        }
        return bitmap;
    }
    private static function fail(p:Object,reason:String):Boolean {
        if(p!=null) p.failure=reason;
        release(p);return false;
    }
    /** Success means caller may hide its actor. This method never writes actor._visible. */
    public static function render(p:Object,sortY:Number,expectedActorVisible:Boolean):Boolean {
        if(!current(p,expectedActorVisible) || !finite(sortY)) return fail(p,"ownership-or-sortY");
        var art:MovieClip=p.maskArt;
        if(!(art._width>0) || !(art._height>0)) return fail(p,"empty-mask-frame");
        var actor:MovieClip=p.actor;
        // Preserve the source actor's parent-space matrix while capturing its sibling mask.
        // Zeroing the actor transform can put that existing mask outside a local bitmap.
        var bounds:Object=actor.getBounds(p.session.world);
        if(!finite(bounds.xMin) || !finite(bounds.xMax) || !finite(bounds.yMin) || !finite(bounds.yMax)) {
            return fail(p,"invalid-bounds");
        }
        var left:Number=Math.floor(bounds.xMin)-2, top:Number=Math.floor(bounds.yMin)-2;
        var width:Number=Math.ceil(bounds.xMax)-left+2, height:Number=Math.ceil(bounds.yMax)-top+2;
        if(!(width>0) || !(height>0) || width>MAX_EDGE || height>MAX_EDGE || width*height>MAX_PIXELS) {
            return fail(p,"capture-budget");
        }
        var matrix:Matrix=actor.transform.matrix;
        if(!finite(matrix.a) || !finite(matrix.b) || !finite(matrix.c) || !finite(matrix.d)
                || !finite(matrix.tx) || !finite(matrix.ty) || matrix.a*matrix.d-matrix.b*matrix.c==0) {
            return fail(p,"invalid-transform");
        }
        if(p.bitmap==null || p.bitmap.width!==width || p.bitmap.height!==height) {
            var replacement:BitmapData=allocate(width,height);
            if(replacement==null) return fail(p,"allocation-failed");
            var previous:BitmapData=p.bitmap;
            p.bitmap=replacement;
            p.surface.attachBitmap(replacement,0,"auto",true);
            if(previous!=null) previous.dispose();
        }
        p.bitmap.fillRect(p.bitmap.rectangle,0);
        matrix.tx-=left;matrix.ty-=top;
        p.bitmap.draw(actor,matrix,null,"normal",null,true);
        // An empty capture is not a successful appearance proxy. Caller must cancel/restore.
        var occupied:Object=p.bitmap.getColorBoundsRect(0xFF000000,0,false);
        if(!(occupied.width>0) || !(occupied.height>0)) return fail(p,"empty-actor-capture");
        if(!Cf6PropDepthService.update(p.ticket,sortY)) return fail(p,"depth-update");
        p.surface._x=left-actor._x;p.surface._y=top-actor._y;
        p.ticket.holder.transform.matrix=new Matrix(1,0,0,1,actor._x,actor._y);
        p.ticket.holder._visible=true;
        return true;
    }
    public static function release(p:Object):Void {
        if(p==null || p.closed===true) return;
        if(Cf6PropDepthService.valid(p.maskTicket)
                && p.maskTicket.holder.__cf6ActorMaskConsumer===p.token) {
            delete p.maskTicket.holder.__cf6ActorMaskConsumer;
            if(p.maskArt.__cf6ActorMaskArtToken===p.token) delete p.maskArt.__cf6ActorMaskArtToken;
        }
        Cf6PropDepthService.release(p.ticket);
        if(p.bitmap!=null) {p.bitmap.dispose();p.bitmap=null;}
        if(p.traversal.__cf6ActorMaskPresentation===p) delete p.traversal.__cf6ActorMaskPresentation;
        p.closed=true;
    }
}
