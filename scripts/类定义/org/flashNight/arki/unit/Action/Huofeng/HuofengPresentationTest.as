import org.flashNight.arki.unit.Action.Huofeng.*;
import flash.geom.Matrix;

/** Native carry/scope regressions split out to stay below AVM1 branch limits. */
class org.flashNight.arki.unit.Action.Huofeng.HuofengPresentationTest {
    public static function carry(u:MovieClip,index:Number,check:Function):Void {
        var specs:Array=[
            ["hfCarryRifle","hfTorso","枪","长枪",[-.006435414,-1.164490115,-1.164490115,.006435414,-77.221293155,53.344075980]],
            ["hfCarryBlade","hfTorso","刀","刀",[.949379696,.680603875,-.680603875,.949379696,117.163238915,-246.878320360]],
            ["hfCarryPistol2","hfHip","枪","手枪2",[.070180778,1.167283040,-1.167283040,.070180778,28.778696316,-36.922942073]],
            ["hfCarryPistol","hfHip","枪","手枪",[-.006104267,1.169147841,-1.169147841,-.006104267,-55.922773390,-63.000020823]]];
        for(var i:Number=0;i<specs.length;i++) {
            var s:Array=specs[i];var carried:MovieClip=u.man[s[0]];var anchor:MovieClip=u.man[s[1]];
            check(carried._parent===u.man && anchor._parent===u.man,"authored action contains native carry/pose anchors "+s[0]);
            var inverse:Matrix=anchor.transform.matrix;inverse.invert();
            var actual:Matrix=carried.transform.matrix;actual.concat(inverse);
            var e:Array=s[4];
            check(Math.abs(actual.a-e[0])<.005 && Math.abs(actual.b-e[1])<.005 && Math.abs(actual.c-e[2])<.005
                && Math.abs(actual.d-e[3])<.005 && Math.abs(actual.tx-e[4])<.25 && Math.abs(actual.ty-e[5])<.25,
                "carry pose follows native torso/hip relationship through rotation/ascent "+s[0]);
            var holder:MovieClip=carried[s[2]];var skin:MovieClip=holder.装扮;
            if(index==16) check(skin==undefined && holder.基本款==undefined,"empty weapon slot has no fallback weapon "+s[3]);
            else {
                check(skin._parent===holder && skin._width>0 && skin._height>0,"actual equipped weapon skin loaded "+s[3]);
                check(u[s[3]+"_引用"]===skin,"carry uses the standard live equipment reference "+s[3]);
            }
        }
    }
    public static function scopeSwitch(u:MovieClip,runtime:HuofengSetRuntime,chest:Object,check:Function):Void {
        var emitter:Function=_root.子弹区域shoot传递;_root.子弹区域shoot传递=function():Void{};
        runtime.getState().tier=2;runtime.startAttack(false);
        for(var step:Number=1;step<=8;step++) {_root.帧计时器.当前帧数++;HuofengAction.tick(u.man);runtime.tick(chest);}
        check(flameCount(u)>0,"scope fixture begins with a real mace fire burst");
        u.攻击模式="兵器";_root.帧计时器.当前帧数++;HuofengAction.tick(u.man);runtime.tick(chest);
        check(flameCount(u)==0 && runtime.getAction()==null,"mode switch clears previous bursts and releases the mace action");
        check(runtime.isActive() && runtime.getTier()==2,"changing weapon preserves the set's Nirvana contract");
        _root.子弹区域shoot传递=emitter;
    }
    public static function mapReset(u:MovieClip,runtime:HuofengSetRuntime,chest:Object,reviveRun:Object,world:MovieClip,check:Function):Void {
        var state:Object=runtime.getState();
        var paidWorld:Object=org.flashNight.arki.scene.StageReturnFlow.worldIdentity(world);
        HuofengRunState.notifyPaidRevive(reviveRun,u,true,5,paidWorld);
        check(state.pendingNirvanaTier==2,"old map has a queued unshown paid revival");
        world.__stageReturnWorldIdentity={};
        var hpBefore:Number=u.hp;_root.帧计时器.当前帧数++;runtime.tick(chest);
        var fresh:Object=runtime.getState();
        check(fresh!==state && fresh.tier==0 && fresh.pendingNirvanaTier==0 && runtime.getAction()==null,
            "new map clears tiers and the old map pending animation");
        check(u.hp满血值==1000 && u.hp==hpBefore && u.__huofengHpContract==undefined,
            "map transition restores normal max HP without granting free healing");
        check(flameCount(u)==0 && !u.__huofengVisual._visible,"new map has no old attack fire or tier aura");
        HuofengRunState.notifyPaidRevive(reviveRun,u,true,6,paidWorld);runtime.tick(chest);
        check(fresh.tier==0 && runtime.getAction()==null,"late old-map payment cannot enhance the new map");
        HuofengRunState.notifyPaidRevive(reviveRun,u,true,5);runtime.tick(chest);
        check(fresh.tier==0,"map reset does not replay an already consumed coin receipt");
        HuofengRunState.notifyPaidRevive(reviveRun,u,true,7,world.__stageReturnWorldIdentity);runtime.tick(chest);
        check(fresh.tier==1 && runtime.getAction().tier==1 && u.hp满血值==700,
            "a new-map payment starts again at ordinary first-tier Nirvana");
        runtime.cancelAction(true);
    }
    private static function flameCount(u:MovieClip):Number {
        var count:Number=0;
        for(var i:Number=0;i<16;i++) if(u.__huofengVisual["burst"+i]._visible===true) count++;
        return count;
    }
}
