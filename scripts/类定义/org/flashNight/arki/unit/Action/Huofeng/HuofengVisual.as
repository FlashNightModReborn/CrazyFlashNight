import org.flashNight.arki.unit.Action.Huofeng.*;
import org.flashNight.arki.component.Effect.EffectSystem;
import flash.geom.Matrix;

/** Equipment-owned presentation; Boss flame copies contain no combat scripts. */
class org.flashNight.arki.unit.Action.Huofeng.HuofengVisual {
    private var unit:MovieClip;
    private var owner:HuofengSetRuntime;
    private var layer:MovieClip;
    private var skirt:MovieClip;
    private var token:Object;
    private var events:Array;
    private var lastPose:Matrix;
    private var lastFrame:Number;
    private var age:Number;
    private var disposed:Boolean;
    // Bounded, reusable one-shot Boss art. No projectile or damage scripts.
    private var flames:Array;
    private var fireCursor:Number;
    private var ringCursor:Number;
    private var flameToken:Object;
    private var flameFrame:Number;
    private var fxPoint:Object;
    public function HuofengVisual(target:MovieClip,runtime:HuofengSetRuntime) {
        unit=target;owner=runtime;token={};events=[];age=0;lastFrame=-1;disposed=false;
        flames=[];fireCursor=ringCursor=0;flameFrame=-1;fxPoint={x:0,y:0};
        ensureLayer();
        attachSkirt();
        listen("屁股_引用");listen("dressup:refreshed");
    }
    private function ensureLayer():Void {
        if (layer.__huofengVisualToken===token && layer._parent===unit) return;
        // Native man uses depth 0; container and timeline adjuncts use low
        // depths. A fresh actor has no historical dynamic-depth high water.
        layer=unit.createEmptyMovieClip("__huofengVisual",Math.max(16,unit.getNextHighestDepth()));
        layer.__huofengVisualToken=token;layer._visible=false;lastFrame=-1;flames=[];flameToken=null;flameFrame=-1;
    }
    public function actionChanged():Void {
        clearFlames();
        hideSkirt();
        if (layer.__huofengVisualToken===token) layer._visible=false;
        lastFrame=-1;
    }
    private function listen(name:String):Void {
        if (!unit.dispatcher) return;
        if (!unit.syncRefs) unit.syncRefs={};
        unit.syncRefs[name]=true;
        var self:HuofengVisual=this;
        var callback:Function=function():Void { self.syncSkirt(self.owner.getAction()); };
        if (unit.dispatcher.subscribe(name,callback,this)) events.push({name:name,callback:callback});
    }
    private function attachSkirt():Void {
        var background:MovieClip=unit.底层背景;
        if (background._parent!==unit) return;
        if (skirt.__huofengVisualToken===token && skirt._parent===background) return;
        if (skirt.__huofengVisualToken===token) skirt.removeMovieClip();
        skirt=background.attachMovie("火凤套装_后披摆","__huofengSkirt",background.getNextHighestDepth(),{_visible:false});
        if (skirt) skirt.__huofengVisualToken=token;
        lastPose=null;
    }
    private function hideSkirt():Void {
        if (skirt.__huofengVisualToken===token) skirt._visible=false;
    }
    /** Local ancestry excludes camera/root transforms and their roundoff.
     * Shooting may use separate upper/lower body branches under the unit.
     */
    private function toUnit(clip:MovieClip):Matrix {
        if (!clip._parent) return null;
        var result:Matrix=clip.transform.matrix;
        var node:MovieClip=clip._parent;
        var depth:Number=0;
        while (node!==unit) {
            if (!node._parent || ++depth>16) return null;
            result.concat(node.transform.matrix);
            node=node._parent;
        }
        return result;
    }
    private function syncSkirt(action:Object):Void {
        if (disposed) return;
        var anchor:MovieClip=unit.屁股_引用;
        var background:MovieClip=unit.底层背景;
        if (action!=null || unit.dressupRefreshing || !(unit.hp>0) || background._parent!==unit) {hideSkirt();return;}
        var pose:Matrix=toUnit(anchor);
        var back:Matrix=background.transform.matrix;
        if (!pose || !(Math.abs(pose.a*pose.d-pose.b*pose.c)>0.00000001)
            || !(Math.abs(back.a*back.d-back.b*back.c)>0.00000001)) {hideSkirt();return;}
        back.invert();pose.concat(back);
        if (!isFinite(pose.a) || !isFinite(pose.b) || !isFinite(pose.c) || !isFinite(pose.d)
            || !isFinite(pose.tx) || !isFinite(pose.ty)) {hideSkirt();return;}
        attachSkirt();
        if (skirt.__huofengVisualToken!==token) return;
        if (!lastPose || lastPose.a!==pose.a || lastPose.b!==pose.b || lastPose.c!==pose.c
            || lastPose.d!==pose.d || lastPose.tx!==pose.tx || lastPose.ty!==pose.ty) {
            skirt.transform.matrix=pose;lastPose=pose;
        }
        skirt._visible=true;
    }
    private function flame(name:String,linkage:String):MovieClip {
        var clip:MovieClip=layer[name];
        if (!clip) clip=layer.attachMovie(linkage,name,layer.getNextHighestDepth(),{_visible:false});
        return clip;
    }
    private function clearFlames():Void {
        for(var i:Number=0;i<flames.length;i++) if(flames[i]) {
            flames[i]._visible=false;flames[i].__hfLife=0;
        }
        flameToken=null;flameFrame=-1;
    }
    private function emitFlame(marker:MovieClip,ring:Boolean,rotation:Number,tier:Number):Void {
        if (!marker._parent) return;
        var slot:Number=ring ? 12+(ringCursor++%4) : fireCursor++%12;
        var clip:MovieClip=flames[slot];
        if (!clip) {
            clip=flame("burst"+slot,ring?"火凤套装_原版回旋":"火凤套装_原版火攻");
            if (!clip) return;flames[slot]=clip;
        }
        // Original Boss spawns world-space bursts at 100%, with a fresh
        // timeline and rotated fire tongues. Do not glue the fading tail to
        // a moving mace or seek by the equipment's unrelated global age.
        fxPoint.x=fxPoint.y=0;marker.localToGlobal(fxPoint);
        _root.gameworld.globalToLocal(fxPoint);
        clip.__hfX=fxPoint.x;clip.__hfY=fxPoint.y;
        clip.__hfLife=1;clip.__hfBorn=lastFrame;
        clip.__hfFacing=unit.方向=="左"?-1:1;
        clip.__hfRotation=rotation*clip.__hfFacing;
        clip._alpha=tier==2?100:85;
        clip.gotoAndStop(1);clip._visible=true;
    }
    private function updateFlames(action:Object,tier:Number):Void {
        // Retire attack bursts immediately on a weapon-mode switch. The
        // set's passive ember, healing and HP contract remain independently owned.
        if (!HuofengRules.profileActive(unit)) {clearFlames();return;}
        var body:MovieClip=unit.man;
        var current:Object;
        var f:Number;
        var burst:Boolean=false;
        var cold:Boolean=false;
        if (action!=null && action.kind!=="nirvana" && HuofengAction.ownsMan(unit,action)) {
            current=action;f=action.frame;
            if(action.recovery==0) {
                if(action.kind==="normal") burst=f==8 || f==17 || f==31 || f==45 || f==55 || f==66;
                else if(action.kind==="run") burst=f>=8 && f<=30 && (f-8)%6==0;
                else if(action.kind==="spin") burst=(f>=14 && f<=60 && (f-14)%8==0) || (f>=68 && f<=114 && (f-68)%8==0);
            }
        } else if (body.__huofengColdSnapshot.owner===owner && !body.__huofengColdSnapshot.token.cancelled) {
            current=body.__huofengColdSnapshot;
            f=body._currentframe;cold=true;
            // Native blade emitters own their contact timing. Sample the
            // current blade pose at bounded intervals, including frame jumps.
            burst=f>=2 && (current!==flameToken || f<flameFrame || f-flameFrame>=6);
        }
        if (burst && (current!==flameToken || f!==flameFrame)) {
            flameToken=current;flameFrame=f;
            var first:MovieClip=cold?body.刀.刀.装扮.刀口位置1:body.hfHit1;
            var middle:MovieClip=cold?body.刀.刀.装扮.刀口位置2:body.hfHit2;
            var tip:MovieClip=cold?body.刀.刀.装扮.刀口位置3:body.hfTip;
            emitFlame(first,false,-65,tier);
            emitFlame(middle,false,35,tier);
            emitFlame(tip,false,125,tier);
            emitFlame(middle,true,0,tier);
        }
        var facing:Number=unit.方向=="左"?-1:1;
        for(var i:Number=0;i<flames.length;i++) {
            var clip:MovieClip=flames[i];
            if (!(clip.__hfLife>0)) continue;
            if(clip.__hfBorn!==lastFrame) clip.__hfLife++;
            if(clip.__hfLife>clip._totalframes) {clip.__hfLife=0;clip._visible=false;continue;}
            fxPoint.x=clip.__hfX;fxPoint.y=clip.__hfY;
            _root.gameworld.localToGlobal(fxPoint);layer.globalToLocal(fxPoint);
            clip._x=fxPoint.x;clip._y=fxPoint.y;
            clip._xscale=100*clip.__hfFacing*facing;clip._yscale=100;
            clip._rotation=clip.__hfRotation*facing;
            clip.gotoAndStop(clip.__hfLife);clip._visible=true;
        }
    }
    public function tick():Void {
        if (disposed) return;
        if (!owner.isActive() || !(unit.hp>0)) {
            if (layer.__huofengVisualToken===token) layer._visible=false;
            hideSkirt();clearFlames();return;
        }
        ensureLayer();
        var action:Object=owner.getAction();
        syncSkirt(action);
        var tier:Number=owner.getTier();
        var active:Boolean=tier>0 && !owner.controlLocked() && !unit.dressupRefreshing;
        layer._visible=active;
        // Tier zero has no ember timeline, flame clips or per-frame FX writes.
        if (!active) {clearFlames();return;}
        var frame:Number=Number(_root.帧计时器.当前帧数);
        if (_root.暂停 || frame===lastFrame) return;
        lastFrame=frame;age++;
        var ember:MovieClip=flame("ember","火凤套装_余烬");
        ember._alpha=tier==2?60:35;
        ember._xscale=ember._yscale=tier==2?100:80;
        ember.gotoAndStop(age%24+1);ember._visible=true;
        updateFlames(action,tier);
    }
    public function heal(tier:Number):Void {
        EffectSystem.Effect("火凤套装_回血提示",unit._x,unit._y,tier==2?90:65,undefined,true);
    }
    public function dispose():Void {
        if (disposed) return;disposed=true;
        for (var i:Number=0;i<events.length;i++) unit.dispatcher.unsubscribe(events[i].name,events[i].callback,this);
        events.length=0;
        if (layer.__huofengVisualToken===token) layer.removeMovieClip();
        if (skirt.__huofengVisualToken===token) skirt.removeMovieClip();
        layer=skirt=null;lastPose=null;flames=[];flameToken=null;
    }
}
