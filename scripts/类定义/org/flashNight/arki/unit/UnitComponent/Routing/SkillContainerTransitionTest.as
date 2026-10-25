import org.flashNight.arki.unit.UnitComponent.Routing.*;
/** 真实things0时间轴与生产路由；单位状态夹具不代表完整游戏命中链。 */
class org.flashNight.arki.unit.UnitComponent.Routing.SkillContainerTransitionTest {
    private static var world:MovieClip,unit:MovieClip,driver:MovieClip;
    private static var rows:Array,current:Object,index:Number,age:Number,phase:String,passed:Number,failed:Number;
    private static function check(ok:Boolean,label:String):Void {if(ok) passed++;else {failed++;trace("[FAIL] SkillContainerTransition: "+label);}}
    public static function noop():Void {}
    public static function capture(props:Object):Void {
        if(current==null || phase!="target") return;
        var rect:Object=props.区域定位area.getRect(world);
        if(props.子弹种类=="近战联弹") trace("Audit Geometry: case="+current.name+" age="+age+" frame="+unit.man._currentframe+" area="+props.区域定位area+" x="+props.shootX+" z="+props.shootZ+" rect="+rect.xMin+","+rect.xMax+","+rect.yMin+","+rect.yMax);
        trace("Audit Raw: case="+current.name+" type="+props.子弹种类+" mode="+unit.攻击模式+" state="+unit.状态+" rawVamp="+props.吸血+" rawElement="+props.魔法伤害属性+" modeVamp="+unit.吸血+" modeElement="+unit.魔法伤害属性);
        org.flashNight.arki.bullet.BulletComponent.Init.BulletInitializer.inheritShooterAttributes(props,unit);
        var batch:Boolean=props.子弹种类=="近战联弹" && props.霰弹值==15;
        if(current.kind=="strike" && batch) {
            props._x=props.shootX;props._y=props.shootY;
            var collider:org.flashNight.arki.bullet.BulletComponent.Collider.AABBCollider =
                new org.flashNight.arki.bullet.BulletComponent.Collider.AABBCollider(0,0,0,0);
            var nativeBullet = props;
            collider.updateFromBullet(nativeBullet,props.区域定位area);
            props.aabbCollider=collider;
            var queue:org.flashNight.arki.bullet.BulletComponent.Queue.BulletQueue =
                new org.flashNight.arki.bullet.BulletComponent.Queue.BulletQueue();
            queue.add(props);
            current.admitted+=queue.getCount()*props.霰弹值;
            trace("Audit Queue: case="+current.name+" accepted="+queue.getCount()+" left="+collider.left+" right="+collider.right);
        }
        if(current.kind=="strike" && !batch) return;
        current.shots.push({age:age,count:props.霰弹值,power:props.子弹威力,type:props.子弹种类,
            vamp:props.吸血,element:props.魔法伤害属性,modeVamp:unit.吸血,modeElement:unit.魔法伤害属性,crush:props.击溃});
    }
    public static function runAllTests():Void {
        passed=failed=0;index=-1;
        check(org.flashNight.arki.unit.UnitComponent.Routing.StateTransitionTest.runAll(),"existing state transition regression");
        rows=[{name:"idle-to-strike",kind:"strike"},
            {name:"spin-to-strike",kind:"strike",before:"旋风腿",cut:2},
            {name:"slash-to-strike",kind:"strike",before:"凶斩",cut:2},
            {name:"step-to-strike",kind:"strike",before:"瞬步斩",cut:2},
            {name:"flash-to-strike",kind:"strike",before:"闪现",cut:2},
            {name:"beam-to-strike",kind:"strike",before:"龟派气功",cut:2},
            {name:"weapon-default-step",kind:"attributes",war:true},
            {name:"weapon-tracking-five",kind:"attributes",war:true,skill:"追踪五连"},
            {name:"weapon-wolf-leap",kind:"attributes",war:true,skill:"狼跳"},
            {name:"weapon-spin-ground",kind:"attributes",war:true,skill:"回旋裂地"},
            {name:"weapon-destruction",kind:"attributes",war:true,skill:"破坏殆尽"},
            {name:"learned-step",kind:"attributes",war:false},
            {name:"ichimonji-no-target-right",kind:"ichimonji",war:true}];
        _root.暂停=false;_root.是否阴影=false;_root.控制目标="probeHero";_root.Xmin=0;_root.Xmax=2000;_root.Ymin=0;_root.Ymax=800;
        _root.帧计时器={当前帧数:1};_root.播放音效=noop;_root.敌人二级函数={};
        var depthApi:Object=org.flashNight.gesh.depth.DepthManager;depthApi.instance={updateDepth:noop};
        org.flashNight.arki.spatial.move.Mover.init();
        world=_root.createEmptyMovieClip("__skillTransitionWorld",_root.getNextHighestDepth());_root.gameworld=world;
        _root.collisionLayer=world.createEmptyMovieClip("collision",1);
        unit=world.createEmptyMovieClip("probeHero",2);
        driver=_root.createEmptyMovieClip("__skillTransitionDriver",_root.getNextHighestDepth());
        driver.onEnterFrame=function():Void {org.flashNight.arki.unit.UnitComponent.Routing.SkillContainerTransitionTest.tick();};
        phase="next";age=0;
        check(_root.__cadenceRsl!=undefined,"production things0 RSL anchor is instantiated");
        trace("SkillContainerTransition Root: "+_root._target+" unit="+unit._target);
    }
    private static function initUnit():Void {
        unit.hp=1000;unit.hp满血=1000;unit.等级=40;unit.技能等级=10;unit.内力=100;unit.空手攻击力=100;unit.mp攻击加成=0;
        unit.兵种="主角-男";unit.攻击模式="兵器";unit.状态="兵器站立";unit.__stateGotoLabel="兵器站立";
        unit._x=400;unit._y=unit.Z轴坐标=400;unit.方向="右";unit.身高=175;unit.myxscale=100;unit.浮空=false;unit.飞行浮空=false;unit.temp_y=0;
        unit.左行=unit.右行=unit.上行=unit.下行=false;unit.刀="probe-blade";unit.刀属性={power:100,skillmultipliers:{瞬步斩:3,凶斩:3}};
        unit.基础伤害类型="物理";unit.基础魔法伤害属性=null;unit.基础吸血=unit.基础毒=unit.基础击溃=unit.基础命中加成=unit.基础斩杀=0;unit.基础命中率=100;
        unit.兵器伤害类型="魔法";unit.兵器魔法伤害属性="冲";unit.兵器吸血=20;unit.兵器击溃=7;unit.被动技能={};
        unit.根据模式重新读取武器加成=_root.主角函数.根据模式重新读取武器加成;unit.根据模式重新读取武器加成("兵器");
        unit.状态改变=function(value:String):Void {org.flashNight.arki.unit.UnitComponent.Routing.StateTransition.apply(this,value);};
        unit.读取当前飞行状态=noop;unit.存储当前飞行状态=noop;unit.攻击呐喊=noop;
        // 坐标端口使用固定三个真实MovieClip刀口；伤害和属性仍走生产BladeShootCore。
        unit.刀_刀口数=3;
        unit.刀口位置生成子弹=function(u:MovieClip,p:Object):Void {trace("Audit Blade: unit="+u+" count="+u.刀_刀口数);org.flashNight.arki.unit.Action.Melee.BladeShootCore.shoot(u,p,"__attributeProbeBlade");};
        unit.UpdateBigSmallState=function(big:String,small:String):Void {this.probeBig=big;this.probeSmall=small;};
        unit.动画完毕=function():Void {this.状态改变("兵器站立");};unit.aabbCollider={updateFromUnitArea:noop};
        if(unit.container==undefined) unit.createEmptyMovieClip("container",1000);
        unit.container._x=3.4;unit.container._y=-62.35;unit.container._xscale=27.708435;unit.container._yscale=27.690124;
        unit.dispatcher={publish:noop};
    }
    private static function cast(name:String,war:Boolean):Void {
        unit.技能等级=10;
        if(war) _root.战技路由.战技标签跳转_旧(unit,name);
        else _root.技能路由.技能标签跳转_旧(unit,name);
        check(unit.man!=undefined,"native attach "+name+" case="+current.name);trace("SkillContainerTransition Attach: case="+current.name+" frames="+unit.man._totalframes+" frame="+unit.man._currentframe+" target="+unit.man._target);
        if(current.kind=="attributes" && !war) {
            var blade:MovieClip=unit.man.createEmptyMovieClip("__attributeProbeBlade",unit.man.getNextHighestDepth());
            var dressup:MovieClip=blade.createEmptyMovieClip("刀",1).createEmptyMovieClip("装扮",1);
            for(var i:Number=1;i<=3;i++){var point:MovieClip=dressup.createEmptyMovieClip("刀口位置"+i,i);point._x=i*10;point._y=0;}
        }
    }
    public static function tick():Void {
        _root.帧计时器.当前帧数++;
        if(phase=="done") return;
        if(phase=="next") {
            if(unit.man!=undefined) unit.man.removeMovieClip();
            index++;if(index==rows.length){finish();return;}
            current=rows[index];current.shots=[];current.maxX=0;current.admitted=0;phase="reset";age=0;return;
        }
        if(phase=="reset") {
            if(++age<2)return;unit.removeMovieClip();unit=world.createEmptyMovieClip("probeHero"+index,2);_root.控制目标=unit._name;initUnit();age=0;
            if(current.kind=="ichimonji") {
                _root.Xmax=500;unit.右行=true;
                var wall:MovieClip=_root.collisionLayer;wall.clear();wall.beginFill(0);wall.moveTo(450,0);wall.lineTo(453,0);wall.lineTo(453,800);wall.lineTo(450,800);wall.endFill();
            }
            if(current.before!=undefined) {phase="previous";cast(current.before,false);}
            else {phase="target";cast(current.skill!=undefined?current.skill:current.kind=="strike"?"一瞬千击":current.kind=="ichimonji"?"一文字落雷":"瞬步斩",current.war===true);}
            return;
        }
        if(phase=="previous") {if(++age<current.cut)return;age=0;phase="target";cast("一瞬千击",false);return;}
        if(phase=="target")current.maxX=Math.max(current.maxX,unit._x);
        if(phase=="target" && age<3)trace("SkillContainerTransition Frame: case="+current.name+" age="+age+" frame="+unit.man._currentframe+" state="+unit.状态+" fn="+typeof unit.man.瞬步斩攻击);
        if(phase=="target" && ++age>100) {
            var count:Number=0;for(var i:Number=0;i<current.shots.length;i++)count+=current.shots[i].count;
            trace("SkillContainerTransition Case: "+current.name+" groups="+current.shots.length+" count="+count);
            for(i=0;i<current.shots.length;i++) {var row:Object=current.shots[i];trace("SkillContainerTransition Shot: case="+current.name+" age="+row.age+" count="+row.count+" vamp="+row.vamp+" element="+row.element+" modeVamp="+row.modeVamp+" modeElement="+row.modeElement+" crush="+row.crush+" power="+row.power);}
            if(current.kind=="strike"){check(count==30,"two15 batches across "+current.name);check(current.admitted==30,"both native collision areas admitted across "+current.name);}
            else if(current.kind=="ichimonji") {
                trace("SkillContainerTransition Ichimonji: maxX="+current.maxX+" finalX="+unit._x+" mapXmax="+_root.Xmax);
                check(current.maxX>400 && current.maxX<=450,"actual no-target direction-key timeline stops at thin wall");
                check(current.maxX<=_root.Xmax,"actual resource callback cannot escape map");
            }
            else {check(current.shots.length>0,"actual default skill emits damage "+current.name);var valid:Boolean=true;for(i=0;i<current.shots.length;i++)if(!(current.shots[i].vamp>=20)||current.shots[i].element!="冲" || current.shots[i].crush!=7)valid=false;check(valid,"weapon elemental and vampirism inheritance "+current.name);}
            phase="next";
        }
    }
    private static function finish():Void {
        if(phase=="done")return;phase="done";delete driver.onEnterFrame;driver.removeMovieClip();world.removeMovieClip();
        trace("SkillContainerTransitionTest Tests Passed: "+passed);trace("SkillContainerTransitionTest Tests Failed: "+failed);_root.skillContainerTransitionComplete();
    }
}
