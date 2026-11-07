import org.flashNight.arki.bullet.BulletComponent.Lifecycle.*;
import org.flashNight.arki.bullet.BulletComponent.Loader.AttributeLoader;
import org.flashNight.gesh.xml.XMLParser;

/** AVM1 下的确定性计时/参数/幂等回归；原生素材与生产管线另见 AssetTest。 */
class org.flashNight.arki.bullet.BulletComponent.Lifecycle.TimedDetonationTest {
    private static var passed:Number, failed:Number, records:Array;

    private static function check(ok:Boolean, name:String):Void {
        if (ok) passed++; else { failed++; trace("[TEST_FAIL] TimedDetonationTest: " + name); }
    }
    private static function close(a:Number, b:Number):Boolean { return Math.abs(a-b)<0.001; }
    private static function profileNode():Object {
        return {timeoutMs:1000, explosion:{type:"高压爆炸",powerScale:0.7,fallbackPower:800,zRange:80},
            timeoutScatter:{type:"普通手雷",count:4,powerScale:0.25,fallSpeed:10,spreadDegrees:8,
                explosion:{type:"火焰集束手雷爆炸",powerScale:0.7,fallbackPower:500,zRange:60}}};
    }
    private static function fixture():Object {
        return {_x:20,_y:-120,Z轴坐标:0,子弹威力:100,发射者名:"fixture",是否为敌人:false,
            伤害类型:"魔法",魔法伤害属性:"热",毒:7,nanoToxic:13,nanoToxicDecay:1,
            吸血:3,暴击:2,固伤:11,命中率:90,stateFlags:0,area:{},
            onEnterFrame:function():Boolean{return false;},
            shouldDestroy:function(target:Object):Boolean{return !!target.mapHit;},
            gotoAndPlay:function(frame):Void{this.originalFrame=frame;},
            removeMovieClip:function():Void{this.removed=true;}};
    }
    private static function record(props:Object):Object {
        records.push(props);
        var result:Object=fixture();
        for(var key:String in props) result[key]=props[key];
        result.发射者名=props.发射者;
        return result;
    }
    private static function arm():Object {
        var target:Object=fixture();
        check(TimedDetonation.bind(target,TimedDetonationProfile.fromXML(profileNode()),null),"bind fresh instance");
        target.__timedDetonation.lastMs=0;
        return target;
    }
    public static function runAllTests():Void {
        passed=failed=0;records=[];
        var savedShoot:Function=_root.子弹区域shoot传递;
        var savedGravity:Object=_root.重力加速度;
        var savedPause:Object=_root.暂停;
        _root.子弹区域shoot传递=record;_root.重力加速度=0.5;_root.暂停=false;
        var profile:TimedDetonationProfile=TimedDetonationProfile.fromXML(profileNode());
        check(profile.timeoutMs==1000 && profile.scatter.count==4,"profile parses timeout and count");
        var xml:XML=new XML('<bullet><name>sample</name><attribute><timedDetonation><timeoutMs>125</timeoutMs><explosion><type>其他爆炸</type><powerScale>1</powerScale><fallbackPower>5</fallbackPower><zRange>12</zRange></explosion></timedDetonation></attribute></bullet>');
        xml.ignoreWhite=true;
        var loaded:Object=new AttributeLoader().load(XMLParser.parseXMLNode(xml.firstChild));
        check(loaded.timedDetonation.timeoutMs==125 && loaded.timedDetonation.scatter==null,"real XMLParser and AttributeLoader accept reusable timer-only template");
        var invalid:Array=[0,-1,NaN,Infinity];
        for(var i:Number=0;i<invalid.length;i++) {
            var node:Object=profileNode();node.timeoutMs=invalid[i];
            check(TimedDetonationProfile.fromXML(node)==null,"invalid timeout rejected "+i);
        }
        invalid=[0,1.5,33,Infinity];
        for(i=0;i<invalid.length;i++) {
            node=profileNode();node.timeoutScatter.count=invalid[i];
            check(TimedDetonationProfile.fromXML(node)==null,"invalid child count rejected "+i);
        }
        node=profileNode();node.timeoutScatter.spreadDegrees=46;
        check(TimedDetonationProfile.fromXML(node)==null,"non-downward cone rejected");
        node=profileNode();node.timeoutScatter.fallSpeed=-1;
        check(TimedDetonationProfile.fromXML(node)==null,"upward launch rejected");
        node=profileNode();node.explosion.type="";
        check(TimedDetonationProfile.fromXML(node)==null,"missing explosion type rejected");

        node=profileNode();node.timeoutScatter.fallSpeed=20;node.timeoutScatter.spreadDegrees=45;
        node.timeoutScatter.landingSpread={radiusX:240,radiusZ:40};
        var footprint:TimedDetonationProfile=TimedDetonationProfile.fromXML(node);
        check(footprint.scatter.landingSpread.radiusX==240 && footprint.scatter.landingSpread.radiusZ==40,"optional ground footprint parses");
        var badFootprints:Array=[{radiusX:-1,radiusZ:40},{radiusX:240,radiusZ:NaN},
            {radiusX:0,radiusZ:0},{radiusX:Infinity,radiusZ:40},{radiusX:240}];
        for(i=0;i<badFootprints.length;i++) {
            node=profileNode();node.timeoutScatter.landingSpread=badFootprints[i];
            check(TimedDetonationProfile.fromXML(node)==null,"invalid landing footprint rejected "+i);
        }
        node=profileNode();node.timeoutScatter.landingSpread={radiusX:240,radiusZ:40};node.timeoutScatter.spreadDegrees=0;
        check(TimedDetonationProfile.fromXML(node)==null,"zero cone cannot silently erase requested footprint");
        xml=new XML('<bullet><name>footprint</name><attribute><timedDetonation><timeoutMs>1000</timeoutMs><explosion><type>高压爆炸</type><powerScale>0.7</powerScale><fallbackPower>800</fallbackPower><zRange>80</zRange></explosion><timeoutScatter><type>普通手雷</type><count>4</count><powerScale>0.25</powerScale><fallSpeed>20</fallSpeed><spreadDegrees>45</spreadDegrees><landingSpread><radiusX>240</radiusX><radiusZ>40</radiusZ></landingSpread><explosion><type>火焰集束手雷爆炸</type><powerScale>0.7</powerScale><fallbackPower>500</fallbackPower><zRange>60</zRange></explosion></timeoutScatter></timedDetonation></attribute></bullet>');
        loaded=new AttributeLoader().load(XMLParser.parseXMLNode(xml.firstChild));
        check(loaded.timedDetonation.scatter.landingSpread.radiusX==240,"real XML loader carries landing footprint");
        check(TimedDetonation.landingFrames(600,20,1)==21,"600px drop uses discrete 21-frame landing");
        check(TimedDetonation.landingFrames(1200,20,1)==34,"1200px drop uses discrete 34-frame landing");
        check(TimedDetonation.landingFrames(600,20,0)==30,"zero gravity retains finite downward flight");
        check(TimedDetonation.landingFrames(0,20,1)==1,"ground-level fallback has one bounded frame");
        var heights:Array=[600,1200];
        for(var h:Number=0;h<heights.length;h++) {
            var sumX:Number=0,sumZ:Number=0;
            var flight:Number=TimedDetonation.landingFrames(heights[h],20,1);
            for(i=0;i<4;i++) {
                var planned:Object=TimedDetonation.launchVelocity(i,4,footprint.scatter,heights[h],1,Math.random());
                check(close(planned.x*flight,-240+160*i) && close(planned.z*flight,i%2==0?-40:40),"height-independent staggered landing point "+h+"/"+i);
                check(planned.down==20 && planned.x*planned.x+planned.z*planned.z<=400.0001,"footprint preserves downward cone "+h+"/"+i);
                sumX+=planned.x;sumZ+=planned.z;
            }
            check(close(sumX,0) && close(sumZ,0),"footprint is centered at airburst "+h);
        }
        planned=TimedDetonation.launchVelocity(0,1,footprint.scatter,600,1,0);
        check(planned.x==0 && planned.z==0 && planned.down==20,"single child uses centered downward path");
        sumX=sumZ=0;
        for(i=0;i<3;i++){planned=TimedDetonation.launchVelocity(i,3,footprint.scatter,600,1,0);sumX+=planned.x;sumZ+=planned.z;}
        check(close(sumX,0) && close(sumZ,0),"odd child count retains centered footprint");
        planned=TimedDetonation.launchVelocity(0,4,footprint.scatter,20,1,0);
        check(planned.x*planned.x+planned.z*planned.z<=400.0001 && Math.abs(planned.x)<240,"low airburst contracts footprint inside downward cone");
        planned=TimedDetonation.launchVelocity(0,4,profile.scatter,600,1,0.5);
        var legacy:Object=TimedDetonation.scatterVelocity(0,4,10,8,0.5);
        check(close(planned.x,legacy.x) && close(planned.z,legacy.z) && planned.down==legacy.down,"omitted footprint keeps legacy random cone");
        records=[];_root.重力加速度=1;
        for(i=0;i<4;i++) {
            var falling:Object=fixture();falling._x=0;falling._y=-600;
            TimedDetonation.bind(falling,new TimedDetonationProfile(0,footprint.scatter.explosion,null),
                TimedDetonation.launchVelocity(i,4,footprint.scatter,600,1,0));
            for(var f:Number=0;f<21;f++)TimedDetonation.advanceScatter(falling);
            check(close(records[i].shootX,-240+160*i) && close(records[i].shootZ,i%2==0?-40:40)
                && close(records[i].shootY,records[i].shootZ),"actual grenade movement lands at planned point "+i);
        }
        check(records.length==4 && records[0].子弹种类=="火焰集束手雷爆炸","ground footprint emits four ordinary blasts without recursion");
        records=[];_root.重力加速度=0.5;

        var target:Object=arm(),state:Object=target.__timedDetonation;
        TimedDetonation.advanceClock(target,999,false);
        check(!target.shouldDestroy(target) && records.length==0,"999ms neither explodes nor scatters");
        TimedDetonation.advanceClock(target,1000,false);
        check(target.shouldDestroy(target),"exact 1000ms requests detonation");
        target.子弹威力=999;target.魔法伤害属性="冰";target.毒=999;
        target.gotoAndPlay("消失");
        check(records.length==5 && records[0].子弹种类=="高压爆炸","timeout emits one blast and four grenades");
        check(close(records[0].子弹威力,70),"parent keeps original 0.7 multiplier");
        check(records[0].魔法伤害属性=="热" && records[0].毒==7 && records[0].nanoToxic==13,"birth damage snapshot survives later mutation");
        check(records[0].lockShooterAttributes && records[0].发射者=="fixture","derived blast locks original shooter attributes");
        for(i=1;i<5;i++) check(records[i].子弹种类=="普通手雷" && close(records[i].子弹威力,25),"ordinary grenade shares quarter power "+i);
        check(state.emitted && state.reason=="timeout" && target.removed,"timeout removes source once");
        target.gotoAndPlay("消失");TimedDetonation.detonate(target);
        check(records.length==5,"repeat disappearance cannot duplicate blast or children");
        check(!TimedDetonation.bind(target,profile,null),"rebinding never replaces instance ledger");

        records=[];target=arm();state=target.__timedDetonation;
        TimedDetonation.advanceClock(target,1000,false);target.mapHit=true;
        check(target.shouldDestroy(target) && !state.timeoutRequested,"collision takes priority at deadline");
        target.gotoAndPlay("消失");
        check(records.length==1 && state.reason=="impact","collision emits only parent blast");
        records=[];target=arm();state=target.__timedDetonation;
        TimedDetonation.advanceClock(target,1000,false);target.shouldDestroy(target);
        target._y=target.Z轴坐标;
        target.gotoAndPlay("消失");
        check(records.length==1 && state.reason=="impact","landing after deadline check overrides pending timeout");

        records=[];target=arm();state=target.__timedDetonation;
        TimedDetonation.advanceClock(target,500,false);
        TimedDetonation.advanceClock(target,5500,true);
        check(state.elapsedMs==500 && !target.shouldDestroy(target),"five paused seconds consume no fuse");
        TimedDetonation.advanceClock(target,5999,false);
        check(!target.shouldDestroy(target),"resume preserves remaining 1ms");
        TimedDetonation.advanceClock(target,6000,false);
        check(target.shouldDestroy(target),"resume expires at remaining active-time boundary");
        target.removeMovieClip();
        check(state.cancelled && !TimedDetonation.detonate(target) && records.length==0,"direct removal cancels without late emissions");

        var one:Object=fixture(),two:Object=fixture();
        TimedDetonation.bind(one,profile,null);TimedDetonation.bind(two,profile,null);
        one.__timedDetonation.elapsedMs=1000;
        check(one.shouldDestroy(one) && !two.shouldDestroy(two),"simultaneous shots have independent clocks");
        check(profile.scatter.count==4 && profile.timeoutMs==1000,"shared read-only profile remains unchanged");
        two.gotoAndPlay("其他标签");
        check(two.originalFrame=="其他标签","non-disappearance timeline calls retain native method");
        for(i=0;i<4;i++) {
            var v:Object=TimedDetonation.scatterVelocity(i,4,10,8,0.5);
            check(v.down>0 && Math.abs(v.x)<v.down && Math.abs(v.z)<v.down,"downward direction dominates "+i);
            check((i==0||i==3?v.x>0:v.x<0) && (i<2?v.z>0:v.z<0),"four quadrants spread in ground x/depth "+i);
        }
        records=[];target=fixture();
        TimedDetonation.bind(target,new TimedDetonationProfile(0,profile.scatter.explosion,null),{x:1,z:2,down:10});
        target.area.onEnterFrame=function():Void{this.unwanted=true;};
        check(target.area.onEnterFrame==undefined,"late legacy gravity assignment is blocked");
        TimedDetonation.advanceScatter(target);
        check(close(target._x,21) && close(target.Z轴坐标,2) && close(target._y,-108),"downward movement separates ground depth and height");
        check(close(target.__timedDetonation.velocity.down,10.5),"gravity accelerates downwards");
        target._y=target.Z轴坐标-1;TimedDetonation.advanceScatter(target);
        check(records.length==1 && records[0].子弹种类=="火焰集束手雷爆炸","child landing emits ordinary grenade blast without recursive scatter");
        records=[];target=arm();
        var group:Object={};
        target.cf6DamageGroup=group;target.cf6FixedFlight=true;target.cf6BoundTargetKey="fixed-target";
        target.__cf6DamageMember={object:target,group:group,retired:false};
        target.gotoAndPlay("消失");
        check(records[0].cf6DamageGroup===group && records[0].cf6BoundTargetKey=="fixed-target","existing shot-group and bound-target metadata survive derivation");
        check(records[0].cf6FixedFlight===true && records[0].timedDetonation==undefined,"derived shot retains targeting contract without recursive timer configuration");
        records=[];target=fixture();target.子弹威力=0;
        TimedDetonation.bind(target,profile,null);target.gotoAndPlay("消失");
        check(records[0].子弹威力==800,"zero source power keeps legacy parent fallback");
        records=[];target=arm();target.stateFlags|=32;
        check(target.shouldDestroy(target),"explicit map-boundary flag terminates even without an area");
        target.gotoAndPlay("消失");
        check(records.length==1 && target.__timedDetonation.reason=="impact","map-boundary flag never produces timeout scatter");
        _root.子弹区域shoot传递=savedShoot;_root.重力加速度=savedGravity;_root.暂停=savedPause;
        trace("TimedDetonationTest Tests Passed: "+passed);
        trace("TimedDetonationTest Tests Failed: "+failed);
    }
}
