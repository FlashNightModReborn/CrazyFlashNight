import org.flashNight.arki.unit.UnitComponent.Routing.*;
import org.flashNight.arki.spatial.move.Mover;
class org.flashNight.arki.unit.UnitComponent.Routing.MovementDirectionTimelineTest {
    private static var jobs:Array;
    private static var index:Number;
    private static var passed:Number;
    private static var failed:Number;
    private static var age:Number;
    private static var active:MovieClip;
    private static var host:MovieClip;
    private static var oldWorld:MovieClip;
    private static var oldControl:Object;
    private static var oldStrict:Function;
    private static var oldFast:Function;
    private static var oldRoute:Object;
    private static function record(target:Object,direction:String,amount:Number):Void {
        target.observedMoves.push({direction:direction,amount:amount});
    }
    public static function runAllTests():Void {
        jobs=[];index=0;passed=0;failed=0;
        var skills:Array=["小跳","闪现","战技小跳"];
        var inputs:Array=[{x:-1,y:0},{x:1,y:0},{x:0,y:-1},{x:-1,y:-1},{x:0,y:0}];
        for(var s:Number=0;s<skills.length;s++) for(var f:Number=0;f<2;f++)
            for(var i:Number=0;i<inputs.length;i++) jobs.push({skill:skills[s],face:f==0?"左":"右",input:inputs[i]});
        for(var cf:Number=0;cf<2;cf++) for(var locked:Number=0;locked<2;locked++)
            jobs.push({skill:"拔刀术",face:cf==0?"左":"右",input:{x:cf==0?1:-1,y:0},locked:locked==1,phase:0});
        oldWorld=_root.gameworld;oldControl=_root.控制目标;oldRoute=_root.技能路由;
        oldStrict=Mover.move2DStrict;oldFast=Mover.move2D;
        Mover.move2DStrict=record;Mover.move2D=record;
        _root.技能路由={动画完毕:function(man,unit){unit.timelineComplete=true;}};
        _root.gameworld=_root.createEmptyMovieClip("movementTimelineWorld",_root.getNextHighestDepth());
        host=_root.createEmptyMovieClip("movementTimelineDriver",_root.getNextHighestDepth());
        host.onEnterFrame=function():Void {MovementDirectionTimelineTest.tick();};
        next();
    }
    private static function next():Void {
        if(active) active.removeMovieClip();
        if(index==jobs.length) {finish();return;}
        var job:Object=jobs[index];age=0;
        active=_root.gameworld.createEmptyMovieClip("movementUnit"+index,index+1);
        active.技能名=job.skill;active.方向=job.face;active.技能等级=1;
        active.等级=1;active.重量=0;active.hp=100;active.hp满血值=100;active.mp=100;
        active.Z轴坐标=100;active._y=100;active.左行=job.input.x<0;active.右行=job.input.x>0;
        active.上行=job.input.y<0;active.下行=job.input.y>0;
        active.状态="技能";active.攻击模式="空手";active.跳跃中=false;
        active.observedMoves=[];active.移动=function(direction,amount){MovementDirectionTimelineTest.record(this,direction,amount);};
        active.锁定方向=job.locked===true;
        active.方向改变=function(direction){if(!this.锁定方向)this.方向=direction;};
        active.状态改变=function(value){this.状态=value;};
        active.动画完毕=function(){this.timelineComplete=true;};
        active.UpdateBigSmallState=function(){};
        _root.控制目标=active._name;
        RoutingLifecycle.applyMovementSkillFacing(active,job.skill);
        var placement:MovieClip=active.createEmptyMovieClip("placement",1);
        var init:Object=RoutingLifecycle.buildPublicContainerInit(placement);
        var linkage:String=(job.skill=="战技小跳"?"战技容器-":"技能容器-")+job.skill;
        var man:MovieClip=active.attachMovie(linkage,"man",2,init);
        RoutingLifecycle.bindMovement(man);
        if(!man){failed++;trace("[FAIL] Timeline linkage missing "+linkage);index++;next();return;}
        // 起手后立刻反转两轴输入，真实资源的后续帧必须仍消费本次快照。
        if(job.skill!="拔刀术") {
            active.左行=!active.左行;active.右行=!active.右行;
            active.上行=!active.上行;active.下行=!active.下行;
        }
    }
    private static function tick():Void {
        if(!active)return;
        age++;
        var job:Object=jobs[index];
        var required:Number=job.input.y!=0 && job.input.x!=0?2:1;
        var budget:Number=job.skill=="拔刀术" && job.phase==0?30:10;
        if(active.observedMoves.length<required && age<budget)return;
        var moves:Array=active.observedMoves;
        if(job.skill=="拔刀术") {
            if(job.phase==0) {
                var bladeDirection:String=job.locked?job.face:(job.input.x<0?"左":"右");
                job.bladeOk=moves.length>0 && moves[0].direction==bladeDirection && moves[0].amount==80;
                trace("BladeFlash segment blade face="+job.face+" locked="+job.locked+" direction="+moves[0].direction+" amount="+moves[0].amount);
                active.man.removeMovieClip();active.observedMoves=[];
                active.技能名="闪现";RoutingLifecycle.applyMovementSkillFacing(active,"闪现");
                var comboInit:Object=RoutingLifecycle.buildPublicContainerInit(active.placement);
                var comboMan:MovieClip=active.attachMovie("技能容器-闪现","man",2,comboInit);
                RoutingLifecycle.bindMovement(comboMan);
                job.phase=1;age=0;return;
            }
            var worldDelta:Number=moves.length>0?(moves[0].direction=="左"?-1:1)*moves[0].amount:0;
            var comboOk:Boolean=job.bladeOk && worldDelta==job.input.x*48;
            if(comboOk)passed++;else{failed++;trace("[FAIL] BladeFlash face="+job.face+" locked="+job.locked+" flashDelta="+worldDelta);}
            trace("BladeFlash segment flash face="+job.face+" locked="+job.locked+" worldDelta="+worldDelta);
            index++;next();return;
        }
        var side:Boolean=job.input.y!=0;
        var amount:Number=job.skill=="闪现"?(side?30:48):(side?11:22);
        var expectedDirection:String;
        var expectedAmount:Number;
        if(side){expectedDirection="上";expectedAmount=amount;}
        else {expectedDirection=job.face;expectedAmount=job.input.x==(job.face=="左"?-1:1)?amount:-amount;}
        var ok:Boolean=moves.length>0 && moves[0].direction==expectedDirection
            && Math.abs(moves[0].amount-expectedAmount)<0.001;
        if(side && job.input.x!=0) ok=ok && moves.length>1
            && moves[1].direction=="左" && Math.abs(moves[1].amount-amount)<0.001;
        if(ok)passed++;else{failed++;trace("[FAIL] Timeline "+job.skill+" face="+job.face+" x="+job.input.x+" y="+job.input.y+" count="+moves.length+" observed="+moves[0].direction+"/"+moves[0].amount);}
        index++;next();
    }
    private static function finish():Void {
        delete host.onEnterFrame;host.removeMovieClip();
        if(active)active.removeMovieClip();
        _root.gameworld.removeMovieClip();_root.gameworld=oldWorld;_root.控制目标=oldControl;
        _root.技能路由=oldRoute;Mover.move2DStrict=oldStrict;Mover.move2D=oldFast;
        trace("MovementDirectionTimelineTest: "+passed+" passed, "+failed+" failed; actual published timelines");
        _root.movementTimelineComplete();
    }
}
