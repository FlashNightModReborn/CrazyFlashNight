/** Actual damage object ownership. Recovery, death and timeouts never retire a group. */
class org.flashNight.arki.scene.Cf6DamageGroups {
    private static var serial:Number=0;
    private static var groups:Array=[];
    private static var members:Array=[];
    private static var world:MovieClip;
    private static var epoch:Object;

    public static function bindWorld(w:MovieClip,identity:Object):Void {
        if(world===w && epoch===identity)return;
        // This is a new verified map lifetime, not a shooter/target timeout.
        for(var i:Number=0;i<groups.length;i++){
            groups[i].ended=true;groups[i].worldCleaned=true;
        }
        world=w;epoch=identity;groups=[];members=[];
    }
    public static function begin(record:Object,cycle:Number):Object {
        if(record==null || world!==_root.gameworld || record.worldEpoch!==epoch)return null;
        var group:Object={id:++serial,world:world,epoch:epoch,record:record,cycle:cycle,
            live:0,born:0,open:true,unknown:false,ended:false,worldCleaned:false};
        groups.push(group);
        return group;
    }
    public static function seal(group:Object):Void {
        if(group==null || group.ended)return;
        group.open=false;
        // No created object is not proof of safe termination. Keep the lease
        // and report the missing lifecycle rather than silently replaying.
        if(group.born==0)group.unknown=true;
        settle(group);
    }
    public static function noEmission(group:Object):Void {
        if(group!=null && group.open && group.born==0){group.open=false;group.ended=true;}
    }
    private static function settle(group:Object):Void {
        if(!group.open && !group.unknown && group.live==0)group.ended=true;
    }
    public static function inherit(source:Object,props:Object):Void {
        var member:Object=source.__cf6DamageMember;
        if(member==null || member.retired || member.object!==source || source.cf6DamageGroup!==member.group)return;
        props.cf6DamageGroup=member.group;
        props.cf6BoundTarget=source.cf6BoundTarget;
        props.cf6BoundTargetVersion=source.cf6BoundTargetVersion;
        props.cf6BoundTargetKey=source.cf6BoundTargetKey;
        props.cf6FixedFlight=source.cf6FixedFlight;
    }
    public static function enforceTarget(projectile:Object):Boolean {
        if(projectile.cf6FixedFlight!==true)return true;
        var target:Object=projectile.cf6BoundTarget,group:Object=projectile.cf6DamageGroup;
        if(group!=null && group.epoch===epoch && group.world===_root.gameworld
            && target._parent===world && target.hp>0 && target.version===projectile.cf6BoundTargetVersion
            && target.__cf6SignalIdentity.key===projectile.cf6BoundTargetKey)return true;
        // Target loss terminates this actual carrier. Never enter generic search.
        projectile.removeMovieClip();return false;
    }
    public static function born(projectile:Object,props:Object,oneFrameDrain:Object):Void {
        var group:Object=props.cf6DamageGroup;
        if(group==null || group.ended || group.epoch!==epoch || group.world!==world)return;
        if(projectile==null || typeof projectile.removeMovieClip!="function"){
            group.unknown=true;return;
        }
        var previous:Object=projectile.__cf6DamageMember;
        if(previous!=null && !previous.retired){group.unknown=true;return;}
        var remove:Function=projectile.removeMovieClip;
        if(previous!=null && remove===previous.wrapper)remove=previous.remove;
        var member:Object={object:projectile,group:group,retired:false,
            clip:typeof projectile=="movieclip",name:projectile._name,parent:projectile._parent,
            remove:remove,oneFrameDrain:oneFrameDrain};
        projectile.cf6DamageGroup=group;projectile.__cf6DamageMember=member;
        group.live++;group.born++;members.push(member);
        member.wrapper=removeCallback(member);projectile.removeMovieClip=member.wrapper;
    }
    private static function removeCallback(member:Object):Function {
        return function():Void {
            // A delayed callback owns its captured birth. Reading the current
            // marker here would let an old MovieClip path retire its successor.
            if(member.retired || member.object!==this || this.__cf6DamageMember!==member)return;
            member.remove.call(this);
            if(member.clip && this._parent===member.parent && this._name===member.name
                && this.__cf6DamageMember===member)return;
            org.flashNight.arki.scene.Cf6DamageGroups.retired(member);
        };
    }
    public static function retired(member:Object):Void {
        if(member==null || member.retired)return;
        member.retired=true;
        var group:Object=member.group;
        if(group.ended)return;
        group.live--;settle(group);
    }
    public static function observe():Void {
        if(world!==_root.gameworld)return;
        for(var i:Number=members.length-1;i>=0;i--){
            var member:Object=members[i],projectile:Object=member.object;
            // Timeline removal can bypass a method wrapper. Verify the plain
            // birth record; a recycled MovieClip path is never the old member.
            // A discarded single-frame collision object has no MovieClip or
            // next-frame pump. Release its real colliders when its queue has
            // actually dropped it (including pause/reset), never on elapsed time.
            if(!member.retired && member.oneFrameDrain.drained===true && !member.clip
                && projectile.__cf6DamageMember===member)member.wrapper.call(projectile);
            if(!member.retired && member.clip && (projectile._parent!==member.parent
                || projectile._name!==member.name || projectile.__cf6DamageMember!==member))retired(member);
            if(member.retired)members.splice(i,1);
        }
        for(i=groups.length-1;i>=0;i--)if(groups[i].ended)groups.splice(i,1);
    }
    public static function live(record:Object,cycle:Number):Boolean {
        for(var i:Number=0;i<groups.length;i++){
            var group:Object=groups[i];
            if(!group.ended && group.record===record && (cycle<0 || cycle===group.cycle))return true;
        }
        return false;
    }
    public static function unresolved():Boolean {
        for(var i:Number=0;i<groups.length;i++)if(groups[i].unknown)return true;
        return false;
    }
    public static function counts():Object {
        var live:Number=0,unknown:Number=0;
        for(var i:Number=0;i<groups.length;i++){
            live+=groups[i].live;if(groups[i].unknown)unknown++;
        }
        return {groups:groups.length,objects:live,unknown:unknown};
    }
}
