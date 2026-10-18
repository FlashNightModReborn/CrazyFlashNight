/** Execute the exact production enemy knockback function in native AS2. */
class org.flashNight.arki.unit.Action.Melee.Cf6KnockbackScopeTest {
    private static var passed:Number,failed:Number,world:MovieClip;
    private static function check(ok:Boolean,label:String):Void {
        if(ok)passed++;else{failed++;trace("[TEST_FAIL] Cf6KnockbackScopeTest: "+label);}
    }
    private static function actor(name:String):MovieClip {
        var u:MovieClip=world.createEmptyMovieClip(name,world.getNextHighestDepth());
        u._x=0;u.免疫击退=false;u.硬直中=false;u.freezeCalls=0;
        u.移动=function(direction:String,speed:Number):Void {this._x+=direction=="右"?speed:-speed;};
        u.移动钝感硬直=function():Void {this.freezeCalls++;};
        u.被击移动=_root.敌人函数.被击移动;
        return u;
    }
    public static function runAllTests():Void {
        passed=failed=0;world=_root.createEmptyMovieClip("knockbackScopeFixture",_root.getNextHighestDepth());
        var a:MovieClip=actor("right"),b:MovieClip=actor("left");
        _root.减速度=undefined;a.被击移动("右",24,3);
        check(a.speed==24 && a.减速度==3 && typeof a.onEnterFrame=="function","target owns initial velocity and friction");
        a.onEnterFrame();trace("[KNOCKBACK_SCOPE] rootFriction=undefined ownFriction="+a.减速度+" speed="+a.speed+" x="+a._x);
        check(a.speed==21 && a._x==21,"rightward decay uses this target friction");
        _root.减速度=99;b.被击移动("左",24,2);b.onEnterFrame();
        trace("[KNOCKBACK_SCOPE] rootFriction=99 ownFriction="+b.减速度+" speed="+b.speed+" x="+b._x);
        check(b.speed==22 && b._x==-22,"unrelated root property cannot change leftward decay");
        b.硬直中=true;b.onEnterFrame();check(b.speed==22 && b._x==-22,"hitstop freezes velocity and position");b.硬直中=false;
        for(var i:Number=0;i<15;i++)if(typeof b.onEnterFrame=="function")b.onEnterFrame();
        check(b._x==-132 && b.onEnterFrame==undefined,"friction reaches exact finite stop without reversal");
        var immune:MovieClip=actor("immune");immune.免疫击退=true;immune.被击移动("右",24,3);
        check(immune._x==0 && immune.onEnterFrame==undefined && immune.freezeCalls==0,"immunity preserves no movement side effects");
        a._x=b._x=0;_root.减速度=undefined;a.被击移动("右",14,4);b.被击移动("右",10,2);
        a.onEnterFrame();b.onEnterFrame();a.onEnterFrame();b.onEnterFrame();
        check(a.speed==6 && b.speed==6 && a._x==16 && b._x==14,"two targets keep independent friction histories");
        delete _root.减速度;world.removeMovieClip();
        trace("Cf6KnockbackScopeTest: "+passed+" passed, "+failed+" failed");_root.cf6KnockbackScopeComplete();
    }
}
