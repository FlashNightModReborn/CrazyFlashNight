import org.flashNight.arki.scene.Cf6ActorMaskState;

/** Actor-local CAS control ownership. HP and the normal death pipeline stay on hero. */
class org.flashNight.arki.scene.Cf6VehicleActorAdapter {
    private static function idle():Void {}
    private static function deny():Boolean {return false;}
    public static function acquire(world:MovieClip,owner:Object):Object {
        var hero:MovieClip=world[_root.控制目标];
        if(world!==_root.gameworld || world.__stageReturnWorldIdentity!==owner
                || typeof hero!="movieclip" || hero._parent!==world || !(hero.hp>0)
                || hero.__cf6VehicleOwner!==undefined || hero.__cf6TraversalOwner!==undefined
                || hero.__cf6VehicleDeadOwner!==undefined
                || !Cf6ActorMaskState.isKnownNone(hero)) return null;
        var a:Object={world:world,owner:owner,hero:hero,name:hero._name,controlName:_root.控制目标,token:{},
            visible:hero._visible,lock:hero.锁定方向,maskBirth:Cf6ActorMaskState.identity(hero),
            walk:hero.行走,switchMode:hero.按键控制攻击模式,keyCheck:hero.按键检测,closed:false};
        hero.__cf6VehicleOwner=a.token;hero.行走=idle;hero.按键控制攻击模式=idle;hero.按键检测=deny;
        hero._visible=false;hero.锁定方向=true;
        hero.左行=hero.右行=hero.上行=hero.下行=false;
        hero.动作A=hero.动作B=hero.动作C=false;hero.按住奔跑键=hero.强制奔跑=false;
        if(!control(a)) {release(a);return null;}
        return a;
    }
    public static function owned(a:Object):Boolean {
        return a!=null && !a.closed && a.hero.__cf6VehicleOwner===a.token
            && a.hero._parent===a.world && a.world[a.name]===a.hero
            && a.world.__stageReturnWorldIdentity===a.owner;
    }
    public static function current(a:Object):Boolean {
        return owned(a) && a.world===_root.gameworld && a.controlName===_root.控制目标
            && a.hero.行走===idle && a.hero.按键控制攻击模式===idle && a.hero.按键检测===deny
            && a.hero._visible===false && a.hero.锁定方向===true
            && Cf6ActorMaskState.identity(a.hero)===a.maskBirth && control(a);
    }
    private static function restoreBlock(a:Object):Void {
        if(a.block.__cf6VehicleOwner===a.token && a.token!==undefined) {
            if(a.block.onEnterFrame===idle) a.block.onEnterFrame=a.callback;
            delete a.block.__cf6VehicleOwner;
        }
        a.block=undefined;
    }
    private static function control(a:Object):Boolean {
        var block:MovieClip=a.hero.控制块;
        if(typeof block!="movieclip" || typeof block.onEnterFrame!="function") {restoreBlock(a);return true;}
        if(block.__cf6VehicleOwner===a.token) return block.onEnterFrame===idle;
        if(block.__cf6VehicleOwner!==undefined || block.__cf6TraversalOwner!==undefined) return false;
        restoreBlock(a);a.block=block;a.callback=block.onEnterFrame;
        block.__cf6VehicleOwner=a.token;block.onEnterFrame=idle;return true;
    }
    public static function move(a:Object,dx:Number,dy:Number,scale:Number,rect:Array,walls:Array):Void {
        if(!current(a) || !(a.hero.hp>0)) return;
        var x:Number=a.hero._x/scale+dx,y:Number=a.hero.Z轴坐标/scale+dy;
        // Resolve against the four source collision faces using the car footprint.
        // The chapter's broad camera limits are not substituted for these walls.
        x=Math.max(walls[2][2]-rect[0],Math.min(walls[3][0]-rect[2],x));
        y=Math.max(walls[0][3]-rect[1],Math.min(walls[1][1]-rect[3],y));
        a.hero._x=x*scale;a.hero._y=y*scale;a.hero.Z轴坐标=y*scale;
        if(typeof a.hero.aabbCollider.updateFromUnitArea=="function") a.hero.aabbCollider.updateFromUnitArea(a.hero);
        a.hero.swapDepths(a.hero.Z轴坐标);
    }
    /** Return input slots during the ordinary death UI, retaining only car presentation. */
    public static function park(a:Object):Object {
        if(!owned(a) || Cf6ActorMaskState.identity(a.hero)!==a.maskBirth
                || a.hero.__cf6VehicleDeadOwner!==undefined) return null;
        var hold:Object={world:a.world,owner:a.owner,hero:a.hero,name:a.name,controlName:a.controlName,
            visible:a.visible,maskBirth:a.maskBirth,token:{},closed:false};
        release(a,true);hold.hero.__cf6VehicleDeadOwner=hold.token;hold.hero._visible=false;
        return hold;
    }
    public static function parked(hold:Object):Boolean {
        return hold!=null && !hold.closed && hold.hero.__cf6VehicleDeadOwner===hold.token
            && hold.hero._parent===hold.world && hold.world[hold.name]===hold.hero
            && hold.world.__stageReturnWorldIdentity===hold.owner
            && Cf6ActorMaskState.identity(hold.hero)===hold.maskBirth;
    }
    public static function resume(hold:Object):Object {
        if(!parked(hold) || hold.world!==_root.gameworld || hold.controlName!==_root.控制目标 || !(hold.hero.hp>0)) return null;
        delete hold.hero.__cf6VehicleDeadOwner;
        var a:Object=acquire(hold.world,hold.owner);
        if(a==null) {
            if(hold.hero.__cf6VehicleDeadOwner===undefined && hold.world[hold.name]===hold.hero
                    && hold.world.__stageReturnWorldIdentity===hold.owner) hold.hero.__cf6VehicleDeadOwner=hold.token;
            else hold.closed=true;
            return null;
        }
        a.visible=hold.visible;hold.closed=true;return a;
    }
    public static function releaseParked(hold:Object):Void {
        if(hold==null || hold.closed) return;
        if(parked(hold)) {
            if(hold.hero._visible===false) hold.hero._visible=hold.visible;
            delete hold.hero.__cf6VehicleDeadOwner;
        }
        hold.closed=true;
    }
    public static function release(a:Object,preserveVisibility:Boolean):Void {
        if(a==null || a.closed) return;
        restoreBlock(a);
        if(owned(a)) {
            var hero:MovieClip=a.hero;
            if(hero.行走===idle) hero.行走=a.walk;
            if(hero.按键控制攻击模式===idle) hero.按键控制攻击模式=a.switchMode;
            if(hero.按键检测===deny) hero.按键检测=a.keyCheck;
            if(hero.锁定方向===true) hero.锁定方向=a.lock;
            if(!preserveVisibility && hero._visible===false && Cf6ActorMaskState.identity(hero)===a.maskBirth) hero._visible=a.visible;
            delete hero.__cf6VehicleOwner;
        }
        a.closed=true;
    }
}
