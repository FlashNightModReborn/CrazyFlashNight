import org.flashNight.arki.unit.Action.Skill.*;
/** 无存档夹具：真实AVM1输入分支、细墙hitTest与地图边界。 */
class org.flashNight.arki.unit.Action.Skill.IchimonjiMovementTest {
    private static var passed:Number,failed:Number;
    private static function check(ok:Boolean,label:String):Void {if(ok) passed++;else {failed++;trace("[FAIL] IchimonjiMovement: "+label);}}
    private static function position(hero:MovieClip,x:Number,z:Number):Void {
        hero._x=x;hero.Z轴坐标=z;hero._y=z;
        hero.上行=hero.下行=hero.左行=hero.右行=false;hero.方向="右";
    }
    public static function runAllTests():Void {
        passed=failed=0;
        var oldWorld=_root.gameworld,oldCollision=_root.collisionLayer,oldControl=_root.控制目标;
        var minX=_root.Xmin,maxX=_root.Xmax,minZ=_root.Ymin,maxZ=_root.Ymax;
        var depthApi:Object=org.flashNight.gesh.depth.DepthManager,oldDepth=depthApi.instance;
        var world:MovieClip=_root.createEmptyMovieClip("__ichimonjiFixture",_root.getNextHighestDepth());
        _root.gameworld=world;_root.Xmin=0;_root.Xmax=500;_root.Ymin=0;_root.Ymax=300;_root.控制目标="hero";
        var wall:MovieClip=world.createEmptyMovieClip("wall",1);_root.collisionLayer=wall;
        var hero:MovieClip=world.createEmptyMovieClip("hero",2);hero.aabbCollider={updateFromUnitArea:function():Void {}};
        depthApi.instance={updateDepth:function():Void {}};
        position(hero,100,100);hero.右行=true;IchimonjiMovement.moveFree(hero);check(hero._x==175,"right key is75 rather than750");
        position(hero,100,100);hero.左行=true;IchimonjiMovement.moveFree(hero);check(hero._x==25,"left key is bounded75");
        position(hero,100,100);hero.上行=true;IchimonjiMovement.moveFree(hero);check(Math.abs(hero.Z轴坐标-62.5)<0.1,"up key is37.5 rather than375");
        position(hero,100,100);hero.下行=true;IchimonjiMovement.moveFree(hero);check(Math.abs(hero.Z轴坐标-137.5)<0.1,"down key preserves half-speed");
        position(hero,100,100);IchimonjiMovement.moveFree(hero);check(hero._x==125,"no key preserves25 forward drift");
        position(hero,100,100);hero.方向="左";IchimonjiMovement.moveFree(hero);check(hero._x==75,"no key respects facing");
        position(hero,100,100);hero.右行=true;hero.下行=true;IchimonjiMovement.moveFree(hero);check(hero._x==175 && Math.abs(hero.Z轴坐标-137.5)<0.1,"diagonal uses both bounded axes");
        position(hero,490,100);hero.右行=true;IchimonjiMovement.moveFree(hero);check(hero._x==500,"right boundary cannot be crossed");
        position(hero,10,100);hero.左行=true;IchimonjiMovement.moveFree(hero);check(hero._x==0,"left boundary cannot be crossed");
        position(hero,100,10);hero.上行=true;IchimonjiMovement.moveFree(hero);check(hero.Z轴坐标>=0 && hero.Z轴坐标<1,"upper boundary cannot be crossed");
        position(hero,100,290);hero.下行=true;IchimonjiMovement.moveFree(hero);check(hero.Z轴坐标<=300 && hero.Z轴坐标>299,"lower boundary cannot be crossed");
        wall.beginFill(0);wall.moveTo(80,0);wall.lineTo(83,0);wall.lineTo(83,300);wall.lineTo(80,300);wall.endFill();
        position(hero,20,100);hero.右行=true;IchimonjiMovement.moveFree(hero);trace("IchimonjiMovement WallReadback: x="+hero._x+" hit80="+wall.hitTest(80,100,true)+" hit81="+wall.hitTest(81,100,true)+" hit84="+wall.hitTest(84,100,true));check(hero._x>=78 && hero._x<=80,"three-pixel wall blocks crossing even when endpoint is clear");
        wall.clear();wall.beginFill(0);wall.moveTo(0,80);wall.lineTo(500,80);wall.lineTo(500,83);wall.lineTo(0,83);wall.endFill();
        position(hero,100,60);hero.下行=true;IchimonjiMovement.moveFree(hero);check(hero.Z轴坐标>=78 && hero.Z轴坐标<80,"thin horizontal wall blocks vertical dash");
        wall.clear();position(hero,100,100);hero._y=80;hero.下行=true;IchimonjiMovement.moveFree(hero);check(Math.abs(hero.Z轴坐标-hero._y-20)<0.1,"movement preserves existing airborne height");
        position(hero,100,100);_root.控制目标="other";hero.右行=true;IchimonjiMovement.moveFree(hero);check(hero._x==125,"NPC ignores player direction flags and retains25 drift");
        _root.控制目标="hero";position(hero,100,100);hero.右行=true;_root.Xmax=NaN;IchimonjiMovement.moveFree(hero);check(hero._x==100,"unknown map bounds do not permit an unchecked move");
        world.removeMovieClip();_root.gameworld=oldWorld;_root.collisionLayer=oldCollision;_root.控制目标=oldControl;
        _root.Xmin=minX;_root.Xmax=maxX;_root.Ymin=minZ;_root.Ymax=maxZ;depthApi.instance=oldDepth;
        trace("IchimonjiMovementTest Tests Passed: "+passed);trace("IchimonjiMovementTest Tests Failed: "+failed);
    }
}
