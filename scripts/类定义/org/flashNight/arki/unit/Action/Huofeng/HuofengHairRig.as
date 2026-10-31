import flash.geom.Matrix;

/** Helmet-owned rear hair. Only this controller's clips are transformed or removed. */
class org.flashNight.arki.unit.Action.Huofeng.HuofengHairRig {
    private static var nextSerial:Number = 0;
    private var unit:MovieClip;
    private var config:Object;
    private var ownerKey:String;
    private var token:Object;
    private var serial:Number;
    private var parts:Array;
    private var events:Array;
    private var disposed:Boolean;
    private var backHost:MovieClip;
    private var headIdentity:Object;
    private var motion:Object;
    public var bindCount:Number;

    public function HuofengHairRig(actor:MovieClip, configuration:Object, expectedHelmet:String) {
        this.unit=actor;this.config=configuration;this.ownerKey=expectedHelmet;
        this.token={};this.serial=++org.flashNight.arki.unit.Action.Huofeng.HuofengHairRig.nextSerial;
        this.parts=[];this.events=[];this.disposed=false;this.bindCount=0;
        var previous:Object=actor.__hf8HairOwner;
        if (previous && previous.controller) previous.controller.dispose();
        actor.__hf8HairOwner={token:this.token,controller:this};
        this.listen("面具_引用",false);this.listen("dressup:refreshed",false);
        this.listen("UnitReInitialized",true);
        this.update();
    }
    private function listen(name:String, remove:Boolean):Void {
        var dispatcher:Object=this.unit.dispatcher;
        if (!dispatcher) return;
        if (!this.unit.syncRefs) this.unit.syncRefs={};
        if (name=="面具_引用") this.unit.syncRefs[name]=true;
        var controller:org.flashNight.arki.unit.Action.Huofeng.HuofengHairRig=this;var callback:Function;
        if (remove) callback=function():Void { controller.dispose(); };
        else callback=function():Void { controller.update(); };
        if (dispatcher.subscribe(name,callback,this)) this.events.push({dispatcher:dispatcher,name:name,callback:callback});
    }
    public static function multiply(l:Array, r:Array):Array {
        return [l[0]*r[0]+l[2]*r[1],l[1]*r[0]+l[3]*r[1],
                l[0]*r[2]+l[2]*r[3],l[1]*r[2]+l[3]*r[3],
                l[0]*r[4]+l[2]*r[5]+l[4],l[1]*r[4]+l[3]*r[5]+l[5]];
    }
    public static function determinant(m:Array):Number { return m[0]*m[3]-m[1]*m[2]; }
    public static function inverse(m:Array):Array {
        var d:Number = org.flashNight.arki.unit.Action.Huofeng.HuofengHairRig.determinant(m);
        if (!(Math.abs(d) > 0.0000000001)) return null;
        return [m[3]/d,-m[1]/d,-m[2]/d,m[0]/d,(m[2]*m[5]-m[3]*m[4])/d,(m[1]*m[4]-m[0]*m[5])/d];
    }
    public static function point(m:Array,p:Array):Array { return [m[0]*p[0]+m[2]*p[1]+m[4],m[1]*p[0]+m[3]*p[1]+m[5]]; }
    public static function angle(m:Array):Number {
        var sign:Number = org.flashNight.arki.unit.Action.Huofeng.HuofengHairRig.determinant(m) < 0 ? -1 : 1;
        return Math.atan2(m[1]-sign*m[2],m[0]+sign*m[3]);
    }

    public static function rotate(angle:Number, pivot:Array):Array {
        var c:Number=Math.cos(angle);var s:Number=Math.sin(angle);
        return [c,s,-s,c,pivot[0]-c*pivot[0]+s*pivot[1],pivot[1]-s*pivot[0]-c*pivot[1]];
    }
    /** Bounded angular lag, elapsed-time based. Discontinuities reset without overshoot. */
    public static function step(previous:Object,head:Array,stamp:Number,p:Object):Object {
        var a:Number=org.flashNight.arki.unit.Action.Huofeng.HuofengHairRig.angle(head);
        var sign:Number=org.flashNight.arki.unit.Action.Huofeng.HuofengHairRig.determinant(head)<0 ? -1 : 1;
        if (!previous) return {angle:a,stamp:stamp,sign:sign,tail:0};
        var dt:Number=(stamp-previous.stamp)/1000;
        if (dt<=0) return previous;
        var delta:Number=Math.atan2(Math.sin(a-previous.angle),Math.cos(a-previous.angle));
        if (dt>0.25 || Math.abs(delta)>1.1 || previous.sign!=sign) return {angle:a,stamp:stamp,sign:sign,tail:0};
        var limit:Number=p.maxTailRadians;
        var handed:Number=sign*(org.flashNight.arki.unit.Action.Huofeng.HuofengHairRig.determinant(p.backToHead)<0 ? -1 : 1);
        var target:Number=Math.max(-limit,Math.min(limit,-delta/dt*p.lagSeconds*handed));
        var factor:Number=1-Math.exp(-dt/0.08);
        var tail:Number=previous.tail+(target-previous.tail)*factor;
        return {angle:a,stamp:stamp,sign:sign,tail:Math.max(-limit,Math.min(limit,tail))};
    }
    public static function placement(head:Array,p:Object,tail:Number):Array {
        var root:Array=org.flashNight.arki.unit.Action.Huofeng.HuofengHairRig.multiply(head,p.backToHead);
        return org.flashNight.arki.unit.Action.Huofeng.HuofengHairRig.multiply(root,org.flashNight.arki.unit.Action.Huofeng.HuofengHairRig.rotate(tail,p.tailPivot));
    }
    private function matrixToUnit(clip:MovieClip):Array {
        if (!clip._parent) return null;
        var m:Matrix=new Matrix();var node:MovieClip=clip;var depth:Number=0;
        while (node!==this.unit) {
            if (!node._parent || ++depth>16 || node.__huofengAction.cancelled===true
                || node._name.indexOf("__retiredMan")==0 || node._name.indexOf("__huofengRetired")==0) return null;
            m.concat(node.transform.matrix);node=node._parent;
        }
        if (!isFinite(m.a) || !isFinite(m.b) || !isFinite(m.c) || !isFinite(m.d)
            || !isFinite(m.tx) || !isFinite(m.ty)) return null;
        return [m.a,m.b,m.c,m.d,m.tx,m.ty];
    }
    private function clearParts():Void {
        for (var i:Number=0;i<this.parts.length;i++) {
            var clip:MovieClip=this.parts[i].clip;
            if (clip && clip.__hf8Token===this.token) clip.removeMovieClip();
        }
        this.parts=[];this.motion=null;this.headIdentity=null;
    }
    private function bind(head:MovieClip):Boolean {
        var background:MovieClip=this.unit.底层背景;
        if (background._parent!==this.unit) {this.clearParts();return false;}
        var valid:Boolean=this.parts.length==2 && this.backHost===background;
        for (var i:Number=0;i<this.parts.length && valid;i++) {
            var clip:MovieClip=this.parts[i].clip;
            valid=clip && clip._parent && clip.__hf8Token===this.token;
        }
        if (!valid) {
            this.clearParts();this.backHost=background;
            // Tail first, root second: their overlap stays covered at both extremes.
            var links:Array=[this.config.tail,this.config.upper];
            for (i=0;i<2;i++) {
                clip=background.attachMovie(links[i],"__hf8_"+this.serial+"_"+i,background.getNextHighestDepth());
                if (!clip) {this.clearParts();return false;}
                clip.__hf8Token=this.token;clip._visible=false;this.parts.push({clip:clip,tail:i==0});
            }
            this.bindCount++;
        }
        if (this.headIdentity!==head.__hf8HairIdentity) {this.motion=null;this.headIdentity=head.__hf8HairIdentity;}
        return true;
    }
    public function update(stamp:Number):Void {
        if (this.disposed) return;
        var owner:Object=this.unit.__hf8HairOwner;
        if (!this.unit._parent || !owner || owner.token!==this.token || this.unit.面具!==this.ownerKey) {this.dispose();return;}
        if (this.unit.dressupRefreshing) return;
        var head:MovieClip=this.unit.面具_引用;
        // A missing reference may temporarily fall back to the naked face holder.
        if (!head || !head._parent || !head.__hf8HairIdentity) {this.clearParts();return;}
        var hm:Array=this.matrixToUnit(head);
        if (!hm || !org.flashNight.arki.unit.Action.Huofeng.HuofengHairRig.inverse(hm)) {this.clearParts();return;}
        if (!this.bind(head)) return;
        if (stamp==undefined) stamp=getTimer();
        this.motion=org.flashNight.arki.unit.Action.Huofeng.HuofengHairRig.step(this.motion,hm,stamp,this.config);
        for (var i:Number=0;i<this.parts.length;i++) {
            var part:Object=this.parts[i];var pi:Array=org.flashNight.arki.unit.Action.Huofeng.HuofengHairRig.inverse(this.matrixToUnit(part.clip._parent));
            if (!pi) {part.clip._visible=false;continue;}
            var m:Array=org.flashNight.arki.unit.Action.Huofeng.HuofengHairRig.multiply(pi,org.flashNight.arki.unit.Action.Huofeng.HuofengHairRig.placement(hm,this.config,part.tail ? this.motion.tail : 0));
            part.clip.transform.matrix=new Matrix(m[0],m[1],m[2],m[3],m[4],m[5]);part.clip._visible=true;
        }
    }
    public function dispose():Void {
        if (this.disposed) return;this.disposed=true;this.clearParts();
        for (var i:Number=0;i<this.events.length;i++) {
            var e:Object=this.events[i];e.dispatcher.unsubscribe(e.name,e.callback,this);
        }
        this.events=[];
        var owner:Object=this.unit.__hf8HairOwner;
        if (owner && owner.token===this.token) delete this.unit.__hf8HairOwner;
        this.backHost=null;
    }
    public function isDisposed():Boolean {return this.disposed;}
}
