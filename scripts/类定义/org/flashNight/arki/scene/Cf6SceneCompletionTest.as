import org.flashNight.arki.scene.*;

/** Prepared native suite. It has NOT run until fresh CS6 trace binds these bytes. */
class org.flashNight.arki.scene.Cf6SceneCompletionTest {
    private static var passed:Number;
    private static var failed:Number;
    private static function check(value:Boolean, message:String):Void {
        if (value) passed++; else {failed++;trace("[FAIL] Cf6SceneCompletion: "+message);}
    }
    private static function traversal():Object {
        return {mode:"depart",fps:30,durationFrames:3,samples:[
            {frame:1,x:0,z:0,visible:true,action:"stand"},
            {frame:2,x:5,z:-2,visible:true,action:"walk"},
            {frame:3,x:10,z:-4,visible:false,action:"stand"}]};
    }
    private static function vehicle():Object {
        return {fps:30,roadKillThreshold:30,roadToBossFrames:59,fireIntervalMs:150,barrels:2,
            bossLoopFrames:120,bossThrowFrame:19,bossDeathFirstFrame:121,bossExitFrame:208,originalBossHp:5000};
    }
    public static function runAllTests():Void {
        passed=0;failed=0;
        var owner:Object={};var other:Object={};var spec:Object=traversal();
        check(Cf6TraversalRules.valid(spec),"finite traversal accepted");
        var s:Object=Cf6TraversalRules.create(spec,owner);
        spec.samples[1].x=999;
        check(Cf6TraversalRules.advance(s,owner,false,false,true)=="" && s.frame==0,"uncleared gate cannot depart");
        check(Cf6TraversalRules.advance(s,owner,false,true,false)=="" && s.frame==0,"cleared room still needs gate");
        check(Cf6TraversalRules.advance(s,owner,false,true,true)=="begin","actual gate starts sequence");
        Cf6TraversalRules.advance(s,owner,true,true,true);
        check(s.frame==1,"external pause freezes sequence");
        Cf6TraversalRules.advance(s,owner,false,true,true);
        var row:Object=Cf6TraversalRules.sample(s,owner);
        check(row.x==5,"source mutation cannot change captured path");row.x=777;
        check(Cf6TraversalRules.sample(s,owner).x==5 && Cf6TraversalRules.sample(s,other)==null,"sample copy preserves path and foreign owner cannot render it");
        check(Cf6TraversalRules.advance(s,owner,false,true,true)=="complete","last frame completes");
        check(!Cf6TraversalRules.takeCompletion(s,other),"foreign owner cannot consume completion");
        check(Cf6TraversalRules.takeCompletion(s,owner),"completion delivered once");
        check(!Cf6TraversalRules.takeCompletion(s,owner),"completion cannot replay");
        s=Cf6TraversalRules.create(traversal(),owner);
        check(Cf6TraversalRules.advance(s,other,false,true,true)=="cancel","owner replacement cancels");
        check(!Cf6TraversalRules.takeCompletion(s,owner),"cancelled sequence cannot complete");
        spec=traversal();spec.samples[1].x=NaN;check(!Cf6TraversalRules.valid(spec),"NaN path rejected");
        spec=traversal();spec.samples[1].z=Infinity;check(!Cf6TraversalRules.valid(spec),"infinite path rejected");
        spec=traversal();spec.mode="arrive";spec.actorReleaseFrame=2;s=Cf6TraversalRules.create(spec,owner);
        Cf6TraversalRules.advance(s,owner,false,false,false);
        check(Cf6TraversalRules.advance(s,owner,false,false,false)=="release-actor" && s.actorReleased,"arrival restores actor before trailing door closes");
        check(s.phase=="playing" && Cf6TraversalRules.sample(s,owner)==null,"door continues after actor release without hiding the restored hero");
        var v:Object=Cf6VehicleRules.create(vehicle(),owner,100,6,3);
        check(v!=null,"finite vehicle config accepted");
        check(Cf6VehicleRules.create(vehicle(),owner,NaN,6,3)==null,"NaN health rejected");
        var input:Object={x:1,z:-1,fire:true};var shots:Number=0;
        for(var i:Number=0;i<30;i++) shots+=Cf6VehicleRules.tick(v,owner,false,input).shots;
        check(shots==14,"dual 150ms guns produce seven volleys in first 30 ticks");
        var frame:Number=v.frame;
        check(Cf6VehicleRules.tick(v,owner,true,input).shots==0 && v.frame==frame,"vehicle pause freezes clock and guns");
        check(v.phase=="road","time alone never clears road");
        check(Cf6VehicleRules.roadDeath(v,owner,"unit0"),"first verified road death accepted");
        check(!Cf6VehicleRules.roadDeath(v,owner,"unit0"),"duplicate road death rejected");
        for(i=1;i<30;i++) Cf6VehicleRules.roadDeath(v,owner,"unit"+i);
        check(v.phase=="boss-intro" && v.roadKills==30,"30 unique deaths enter boss handoff");
        check(!Cf6VehicleRules.roadDeath(v,owner,"late"),"late road death cannot alter boss phase");
        for(i=0;i<58;i++) Cf6VehicleRules.tick(v,owner,false,input);
        check(v.phase=="boss-intro","intro keeps original frame budget");
        check(Cf6VehicleRules.tick(v,owner,false,input).cue=="spawn-boss","boss spawned once after intro");
        var grenades:Number=0;
        for(i=0;i<120;i++) if(Cf6VehicleRules.tick(v,owner,false,{x:0,z:0,fire:false}).bossThrow) grenades++;
        check(grenades==1,"one grenade cue per original boss loop");
        check(Cf6VehicleRules.hitBoss(v,owner,"bullet1",1000),"verified boss hit accepted");
        check(!Cf6VehicleRules.hitBoss(v,owner,"bullet1",1000) && v.bossHp==4000,"same bullet cannot damage twice");
        check(!Cf6VehicleRules.hitBoss(v,owner,"nan",NaN),"NaN damage rejected");
        Cf6VehicleRules.hitBoss(v,owner,"bullet2",4000);
        check(v.phase=="boss-death","lethal boss hit starts authored death");
        var tails:Number=0;
        for(i=0;i<100;i++) if(Cf6VehicleRules.tick(v,owner,false,{x:0,z:0,fire:false}).cue=="spawn-tail") tails++;
        check(tails==1 && v.phase=="tail","tail spawned once after frame 208");
        check(!Cf6VehicleRules.reachTail(v,owner,false),"tail completion requires collision trigger");
        check(Cf6VehicleRules.reachTail(v,owner,true),"actual tail gate completes encounter");
        check(Cf6VehicleRules.takeCompletion(v,owner) && !Cf6VehicleRules.takeCompletion(v,owner),"one completion for normal stage adapter");
        v=Cf6VehicleRules.create(vehicle(),owner,100,6,3);
        check(Cf6VehicleRules.hitPlayer(v,owner,"impact1",100) && v.phase=="defeat","lethal player impact ends the run branch");
        check(Cf6VehicleRules.tick(v,owner,false,input).shots==0,"defeat cannot keep firing");
        v=Cf6VehicleRules.create(vehicle(),owner,100,6,3);
        check(Cf6VehicleRules.tick(v,other,false,input).cue=="cancel","changed scene owner cancels vehicle");
        check(!Cf6VehicleRules.takeCompletion(v,owner),"cancelled vehicle cannot award completion");
        var lift:Object=Cf6ElevatorRules.create({mapId:"A10",closeFrames:24,stopFrames:30,openFrames:24,scrollFrames:37},owner);
        check(lift!=null,"lift uses existing bounded timing");
        for(i=0;i<300;i++) Cf6ElevatorRules.advance(lift,owner,false,false,false,false);
        check(lift.phase=="boarding","time cannot fake boarding");
        check(Cf6ElevatorRules.advance(lift,owner,false,true,false,false)=="close-gate","confirmed boarding closes gate");
        for(i=0;i<24;i++) Cf6ElevatorRules.advance(lift,owner,false,true,false,false);
        check(lift.phase=="moving","gate closure releases combat travel");
        for(i=0;i<300;i++) Cf6ElevatorRules.advance(lift,owner,false,true,false,false);
        check(lift.phase=="moving","travel clock cannot clear combat");
        frame=lift.travelFrame;Cf6ElevatorRules.advance(lift,owner,true,true,false,false);
        check(lift.travelFrame==frame,"external pause freezes elevator travel");
        check(Cf6ElevatorRules.advance(lift,owner,false,true,true,false)=="stop-at-floor","authoritative clear stops elevator");
        for(i=0;i<30;i++) Cf6ElevatorRules.advance(lift,owner,false,true,false,false);
        check(lift.phase=="opening","arrival stop precedes gate opening");
        for(i=0;i<24;i++) Cf6ElevatorRules.advance(lift,owner,false,true,false,false);
        for(i=0;i<300;i++) Cf6ElevatorRules.advance(lift,owner,false,true,false,false);
        check(lift.phase=="offboarding" && !Cf6ElevatorRules.takeCompletion(lift,owner),"time cannot fake walking off elevator");
        Cf6ElevatorRules.advance(lift,owner,false,true,false,true);
        check(Cf6ElevatorRules.takeCompletion(lift,owner) && !Cf6ElevatorRules.takeCompletion(lift,owner),"lift restores actor and completes once");
        trace("Cf6SceneCompletionTest Tests Passed: "+passed);
        trace("Cf6SceneCompletionTest Tests Failed: "+failed);
    }
}
