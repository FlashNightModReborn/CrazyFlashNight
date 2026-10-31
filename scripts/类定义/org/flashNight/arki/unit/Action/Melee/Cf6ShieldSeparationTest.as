import org.flashNight.arki.unit.UnitComponent.Status.ImpactStateHandler;
import org.flashNight.arki.component.Damage.DamageResult;
import org.flashNight.arki.component.StatHandler.ImpactHandler;
import org.flashNight.arki.spatial.move.Mover;
import org.flashNight.gesh.depth.DepthManager;
import org.flashNight.arki.bullet.BulletComponent.Collider.AABBCollider;

/** Controlled standard impact/movement on the canonical player hit area, not a human playtest. */
class org.flashNight.arki.unit.Action.Melee.Cf6ShieldSeparationTest {
    private static var passed:Number,failed:Number,world:MovieClip,walls:MovieClip;
    private static function check(ok:Boolean,label:String):Void {
        if(ok)passed++;else{failed++;trace("[TEST_FAIL] Cf6ShieldSeparationTest: "+label);}
    }
    public static function runAllTests():Void {
        passed=failed=0;_root.暂停=false;_root.帧计时器={当前帧数:0};_root.钝感硬直时间=0;
        world=_root.createEmptyMovieClip("__shieldSeparation",_root.getNextHighestDepth());_root.gameworld=world;
        world.createEmptyMovieClip("地图",world.getNextHighestDepth());world.Xmin=-3000;world.Xmax=3000;world.Ymin=-500;world.Ymax=1500;
        walls=_root.createEmptyMovieClip("__shieldWalls",_root.getNextHighestDepth());_root.collisionLayer=walls;
        DepthManager.instance=new DepthManager(world,100000,1000000,64);DepthManager.instance.calibrate(-500,1500);Mover.init();
        var speeds:Array=[7,18,24];
        for(var side:Number=0;side<2;side++)for(var s:Number=0;s<speeds.length;s++)for(var mode:Number=0;mode<4;mode++){
            walls.clear();var sign:Number=side==0?1:-1;
            var target:MovieClip=_root.cf6MakePlayerTarget(world,"target",175);target._x=sign*40;
            target.hp=target.hp满血值=10000;target.防御力=300;target.韧性系数=mode==3?1:10;target.躲闪率=50;
            target.remainingImpactForce=0;target.损伤值=60;target.刚体=true;target.浮空=target.倒地=target.硬直中=false;
            target.免疫击退=mode==2;target.状态="长枪站立";
            target.createEmptyMovieClip("man",2);target.状态改变=target.移动钝感硬直=function():Void {};
            target.被击移动=_root.cf6PressureKnockback;
            target.移动=function(direction:String,speed:Number):Void {Mover.move2D(this,direction,speed);};
            target.aabbCollider=new AABBCollider(0,0,0,0);target.aabbCollider.updateFromUnitArea(target);
            if(mode==1){
                var edge:Number=sign*90;walls.beginFill(0);walls.moveTo(edge,100);walls.lineTo(edge+sign*200,100);
                walls.lineTo(edge+sign*200,300);walls.lineTo(edge,300);walls.lineTo(edge,100);walls.endFill();
            }
            var bullet:MovieClip=world.createEmptyMovieClip("impact",world.getNextHighestDepth());
            bullet.水平击退速度=speeds[s];bullet.垂直击退速度=0;bullet.击倒率=10;
            ImpactStateHandler.handleImpactState(target,bullet,DamageResult.getIMPACT(),sign>0?"右":"左",true);
            var friction:Number=target.减速度,steps:Number=0;
            for(var f:Number=0;f<100;f++)if(typeof target.onEnterFrame=="function"){target.onEnterFrame();steps++;}
            var moved:Number=(target._x-sign*40)*sign,gap:Number=target._x*sign;
            check(isFinite(moved) && moved>=0 && target.onEnterFrame==undefined,"finite standard impact decay "+side+"/"+s+"/"+mode);
            if(mode==0){
                check(friction==3,"test covers normal non-stagger impact branch "+side+"/"+s);
                check(Math.abs(moved-(s==0?5:s==1?45:84))<0.15,"native displacement for configured push "+side+"/"+s);
                if(s==2)check(gap>=120 && gap<200,"shield bash restores space outside 95px knife range "+side);
            }else if(mode==1)check(gap<=90 && moved<=50,"map wall limits bash displacement "+side+"/"+s);
            else if(mode==2)check(moved==0,"existing knockback immunity remains authoritative "+side+"/"+s);
            else check(friction==2 && Math.abs(moved-(s==0?9:s==1?72:132))<0.15,"stagger branch preserves standard friction "+side+"/"+s);
            trace("[CF6_SHIELD_SEPARATION] side="+side+" push="+speeds[s]+" mode="+mode+" friction="+friction+" moved="+moved+" gap="+gap+" steps="+steps);
            bullet.removeMovieClip();target.removeMovieClip();
        }
        world.removeMovieClip();walls.removeMovieClip();
        trace("Cf6ShieldSeparationTest: "+passed+" passed, "+failed+" failed; 24 standard-impact cases");
        _root.cf6ShieldSeparationComplete();
    }
}
