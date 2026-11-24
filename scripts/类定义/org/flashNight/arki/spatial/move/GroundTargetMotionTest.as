import org.flashNight.arki.scene.SceneCollisionManager;
import org.flashNight.arki.collision.CollisionLayerRenderer;
import org.flashNight.naki.DataStructures.Dictionary;
import org.flashNight.gesh.depth.DepthManager;

/** 原生 MovieClip 同路径重建、生产碰撞层和位移入口；此夹具不进入 loader。 */
class org.flashNight.arki.spatial.move.GroundTargetMotionTest {
    private static var api:Object;
    private static var hero:MovieClip, enemy:MovieClip, action:MovieClip, wall:MovieClip;
    private static var passed:Number, failed:Number;

    private static function check(ok:Boolean, label:String):Void {
        if (ok) passed++;
        else { failed++; trace("[FAIL] GroundTargetMotion " + label); }
    }

    private static function place(mc:MovieClip, x:Number, z:Number):Void {
        mc._x = x;
        mc._y = mc.Z轴坐标 = z;
    }

    private static function reset():Void {
        wall.clear();
        place(hero, 250, 200);
        place(enemy, 400, 240);
        hero.攻击目标 = enemy._name;
        hero.飞行浮空 = hero.浮空 = false;
        hero.方向 = "右";
        hero.刷新 = hero.转向 = hero.排序 = 0;
        hero.hp = enemy.hp = 100;
        delete hero.起始Y;
        action.速度上限 = 35;
        action.速度下限 = 15;
        action.追踪持续帧 = 8;
        api.captureTarget(action);
    }

    private static function draw(x:Number, z:Number, width:Number, height:Number):Void {
        wall.beginFill(0);
        wall.moveTo(x,z); wall.lineTo(x+width,z); wall.lineTo(x+width,z+height);
        wall.lineTo(x,z+height); wall.lineTo(x,z); wall.endFill();
    }

    private static function boundaries():Void {
        reset();
        for (var x:Number=0; x<=1000; x+=1000) {
            for (var z:Number=0; z<=700; z+=700) {
                place(hero,x,z);
                var sx:Number = x == 0 ? -1 : 1;
                var sz:Number = z == 0 ? -1 : 1;
                check(!api.checkedFourWay(action,0,sz*301,0,sx*301,action.motionAction)
                      && hero._x==x && hero.Z轴坐标==z && hero.刷新==0, "corner "+x+","+z);
            }
        }
        reset();place(hero,110,100);place(enemy,120,100);
        check(!api.followAxes(action,130) && hero._x==110, "offset outside map");
        reset();draw(295,210,12,60);
        check(api.checkedFourWay(action,0,40,0,50,action.motionAction)==false
              && hero._x==250 && hero._y==200 && hero.转向==0 && hero.刷新==0, "Z then blocked X");
        reset();draw(395,220,12,5);
        check(!api.followAxes(action,0) && hero._x==250 && hero._y==200 && hero.刷新==0, "X then blocked Z");
        for (var phase:Number=0; phase<2; phase+=0.25) {
            reset();draw(280+phase,190,2.5,20);
            check(!api.followAxes(action,0), "thin wall phase "+phase);
        }
        reset();place(hero,100,200);place(enemy,900,200);
        check(!api.followAxes(action,0) && hero._x==100, "over sample budget");
        place(enemy,868,200);
        check(api.followAxes(action,0) && hero._x==868, "768px exact budget");
        reset();hero.area.removeMovieClip();
        check(!api.followAxes(action,0) && hero._x==250 && hero.刷新==0,"missing area");
        hero.createEmptyMovieClip("area",5);
        reset();draw(245,197,10,10);
        check(!api.followAxes(action,10) && hero._x==250 && hero.刷新==0 && action.motionReject=="invalid-origin", "invalid source");
    }

    private static function heights():Void {
        reset();hero.方向="左";place(enemy,245,199.5);
        hero.浮空=true; hero._y=-10; hero.起始Y=230;
        check(api.followAxes(action,20) && hero._x==265 && hero._y==-10.5
             && hero.Z轴坐标==199.5 && hero.起始Y==229.5 && hero.上次排序==-10.5, "negative distance and airborne -.5");
        reset();hero.浮空=true;hero._y=0;hero.起始Y=195;enemy.Z轴坐标=200.5;
        check(api.followAxes(action,0) && hero._y==0.5 && hero.起始Y==195.5
              && hero.Z轴坐标==200.5 && hero.刷新==1, "airborne +.5 refresh once");
        reset();hero.浮空=true;
        check(!api.followAxes(action,10) && hero._x==250 && hero.排序==0 && hero.刷新==0,
              "missing airborne origin refuses whole move");
        enemy.Z轴坐标=200;
        check(api.followAxes(action,10) && hero.起始Y===undefined, "pure X needs no airborne origin");
        reset();hero.飞行浮空=true;check(!api.followAxes(action,0) && hero.刷新==0, "flight");
        hero.飞行浮空=false;hero.方向="";check(!api.followAxes(action,0), "invalid facing");
        reset();check(!api.followAxes(action,NaN) && !api.followAxes(action,10,0,Infinity)
              && !api.checkedFourWay(action,0,NaN,0,10,action.motionAction), "non-finite requests");
        check(api.followAxes(action,100,0,75,30) && hero._x==300 && hero.Z轴坐标==230, "Ichimonji caps");
    }

    private static function rushes():Void {
        var ws:Array=[5.6,5.8,8.3], mins:Array=[3,2,3], times:Array=[8,5,8];
        var first:Array=[433.2,438.4,425.1], inputs:Array=[0,.05,-.05,.5,-.5,140,-140,300,-300];
        for(var n:Number=0;n<3;n++){
            for(var i:Number=0;i<inputs.length;i++){
                for(var j:Number=-2;j<=2;j++){
                    reset();var dx:Number=inputs[i],dz:Number=j==0?0:(Math.abs(j)==1?8*j:15*j);
                    place(hero,500,450);place(enemy,500-dx,450-dz);
                    action.速度上限=7*ws[n];action.速度下限=mins[n]*ws[n];action.追踪持续帧=times[n];
                    api.lockRush(action);
                    var ok:Boolean=api.advanceRush(action,n==2?-1:1,1,true,action.motionAction);
                    check(ok && isFinite(hero.Z轴坐标) && Math.abs(450-hero.Z轴坐标)<=Math.abs(dz)+0.001
                        && Math.abs(action.速度Z)<=Math.abs(action.速度X)+0.001, "rush "+n+"/"+i+"/"+j);
                    if(dx==.5 && dz==30)check(Math.abs(hero.Z轴坐标-first[n])<.001, "historical first Z "+n);
                }
            }
        }
        reset();api.lockRush(action);var z:Number=hero.Z轴坐标;
        check(api.advanceRush(action,-1,-1,false,action.motionAction) && hero._x<250 && hero.Z轴坐标<z && hero.方向=="右", "both axes retreat");
        reset();api.lockRush(action);check(api.advanceRush(action) && hero._x>250, "original one argument rush");
        reset();api.lockRush(action);check(api.advanceRush(action,1,1,true), "explicit synchronous rush");
        reset();check(api.checkedFourWay(action,0,4,0,10), "synchronous four way");
        reset();action.速度下限=36;api.lockRush(action);
        check(isNaN(action.追踪编号) && action.左速度==0 && !api.advanceRush(action), "invalid cap clears lock");
        reset();place(enemy,250,240);api.lockChase(action,.8,1.1);
        check(action.速度X==0 && Math.abs(action.速度Z+4.4)<.0001, "continuous same-column limit");
        action.速度上限=0;api.lockChase(action,1,1);
        check(action.速度X==0 && action.速度Z==0, "zero cap at zero dx");
        for(var k:Number=1;k<=600;k++){
            var gap:Number=(k%2?1:-1)*(k/3),cap:Number=k%23+1,frames:Number=k%25+1;
            var rx:Number=(7+k%5)/10,rz:Number=(7+k%4)/10;
            var oldX:Number=Math.max(-cap,Math.min(cap,gap/frames))*rx;
            var ratio:Number=api.chaseScale(gap,cap,frames);
            check(Math.abs(gap*ratio*rx-oldX)<.000001 && Math.abs(30*ratio*rx*rz-oldX*30/gap*rz)<.000001,"slope "+k);
        }
    }

    private static function identities(world:MovieClip):Void {
        reset();var old:MovieClip=action, token:Number=action.motionAction;
        var late:Function=function():Boolean { return api.checkedFourWay(old,0,4,0,10,token); };
        action.removeMovieClip();action=hero.createEmptyMovieClip("man",3);
        api.captureTarget(action);
        check(old === action && token !== action.motionAction && !late() && hero.刷新==0
              && hero._x==250 && hero._y==200 && hero.转向==0 && hero.排序==0, "rebound old callback after fresh lock");
        check(api.checkedFourWay(action,0,4,0,10,action.motionAction) && hero._x==260, "fresh callback works");
        reset();hero.索敌目标列表=[{敌人:enemy}];api.captureCandidates(action);
        check(api.isCandidateCurrent(action,0),"original candidate");
        enemy.removeMovieClip();enemy=world.createEmptyMovieClip("target",2);
        place(enemy,400,240);enemy.hp=100;var prior=enemy.__dictUID;
        check(!api.isCandidateCurrent(action,0) && !api.followAxes(action,10) && prior===enemy.__dictUID,
              "rebound target and candidate not signed by consumer");
        api.captureTarget(action);api.captureCandidates(action);
        hero.索敌目标列表=hero.索敌目标列表.concat();
        check(!api.isCandidateCurrent(action,0),"new list");
        enemy.hp=0;check(!api.followAxes(action,10),"dead target");
        hero.攻击目标="无";api.captureTarget(action);enemy.hp=100;hero.攻击目标=enemy._name;
        check(!api.followAxes(action,10) && isNaN(action.追踪编号),"failed recapture clears credentials");
        reset();var newWorld:MovieClip=_root.createEmptyMovieClip("__gmtOther",_root.getNextHighestDepth());
        _root.gameworld=newWorld;check(!api.followAxes(action,10) && hero.刷新==0,"scene replaced");
        _root.gameworld=world;newWorld.removeMovieClip();
    }

    public static function runAllTests():Void {
        passed=failed=0;
        api=org.flashNight.arki.spatial.move.GroundTargetMotion;
        var oldWorld=_root.gameworld,oldWall=_root.collisionLayer;
        var xmin=_root.Xmin,xmax=_root.Xmax,zmin=_root.Ymin,zmax=_root.Ymax;
        var depth:Object=org.flashNight.gesh.depth.DepthManager, oldDepth=depth.instance;
        var world:MovieClip=_root.createEmptyMovieClip("__gmtWorld",_root.getNextHighestDepth());
        // Include the production UID provider in the independent TestLoader.
        Dictionary.getStaticUID(world);
        _root.gameworld=world;_root.Xmin=0;_root.Xmax=1000;_root.Ymin=0;_root.Ymax=700;
        wall=world.createEmptyMovieClip("wall",4);_root.collisionLayer=wall;
        hero=world.createEmptyMovieClip("hero",1);enemy=world.createEmptyMovieClip("target",2);
        action=hero.createEmptyMovieClip("man",3);
        hero.createEmptyMovieClip("area",5);
        hero.aabbCollider={updateFromUnitArea:function(u:MovieClip):Void {u.刷新++;}};
        hero.方向改变=function(d:String):Void {this.方向=d;this.转向++;};
        depth.instance={updateDepth:function(u:MovieClip,y:Number):Void {u.排序++;u.上次排序=y;}};
        boundaries();heights();rushes();identities(world);
        reset();world.createEmptyMovieClip("地图",6);
        var manager:SceneCollisionManager=SceneCollisionManager.getInstance();
        manager.init();
        var door:MovieClip=world.createEmptyMovieClip("door",5);
        manager.addMovieClipCollision(door,{xMin:275,xMax:279,yMin:190,yMax:210},true);
        check(!api.followAxes(action,0),"dynamic add published");
        manager.addMovieClipCollision(door,{xMin:650,xMax:655,yMin:190,yMax:210},true);
        check(api.followAxes(action,0),"dynamic change published");
        place(hero,250,200);
        manager.addMovieClipCollision(door,{xMin:275,xMax:279,yMin:190,yMax:210},false);
        check(api.followAxes(action,0),"deferred dirty geometry still old");
        place(hero,250,200);manager.redraw();
        manager.removeMovieClipCollision(door,false);
        check(!api.followAxes(action,0),"deferred removal still blocks");
        manager.redraw();check(api.followAxes(action,0),"published removal permits");
        place(hero,250,200);var rev:Number=CollisionLayerRenderer.revision;
        CollisionLayerRenderer.drawObstacle(wall,{xMin:275,xMax:279,yMin:190,yMax:210},false);
        check(rev===CollisionLayerRenderer.revision && !api.followAxes(action,0),"same revision, new drawn geometry");
        manager.dispose();world.removeMovieClip();
        _root.gameworld=oldWorld;_root.collisionLayer=oldWall;
        _root.Xmin=xmin;_root.Xmax=xmax;_root.Ymin=zmin;_root.Ymax=zmax;depth.instance=oldDepth;
        trace("GroundTargetMotionTest Tests Passed: "+passed);
        trace("GroundTargetMotionTest Tests Failed: "+failed);
    }
}
