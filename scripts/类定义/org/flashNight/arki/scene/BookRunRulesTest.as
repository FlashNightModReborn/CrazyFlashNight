import org.flashNight.arki.scene.BookRunRules;
import org.flashNight.arki.scene.BookDefinition;
class org.flashNight.arki.scene.BookRunRulesTest {
    private static var passed:Number;
    private static var failed:Number;
    private static function check(value:Boolean, message:String):Void {
        if (value) passed++; else { failed++; trace("[FAIL] BookRules: " + message); }
    }
    private static function testCf6():Void {
        var definition:Object=org.flashNight.arki.scene.BookDefinition;
        var original:Object=definition._cf6;
        var oldExt:Object=_root._saveExt, oldSlot=_root.savePath, oldLevel=_root.等级;
        var codec:LiteJSON=new LiteJSON();
        var campus:String=codec.stringifySafe(BookDefinition.get("repair-campus"));
        var fixture:Object={schema:"playable-book.v1",id:"cf6-sting",routeId:"historical",stageName:"书中历险-毒刺行动",title:"TEST ONLY",
            startingMoney:0,startingSkillPoints:0,actor:{name:"Andy",gender:"男",height:175,face:"face",hair:"hair",level:60,experience:157526193,
                equipment:[{slot:"上装装备",name:"白色中山上装",enhancement:11}],skills:[{name:"小跳",level:10}]},
            maps:[{id:"A01",title:"TEST ONLY",background:"cf6/CF6_A01_BG.swf",dialogue:[],stage:{Wave:{SubWave:[{EnemyGroup:{Enemy:[{Type:"兵种1",Level:35,Quantity:1,Parameters:{掉落物:[]}}]}}]}}}]};
        try {
            fixture.maps[0].presentation={scale:1,backgroundX:0,backgroundY:0};
            fixture.maps[0].mechanism={assetScale:1,layers:[]};
            definition._cf6=null;
            check(BookDefinition.valid(fixture),"CF6 authored single-room fixture accepts without campus economy");
            var type61Start:Number=passed+failed;
            testType61(fixture);
            trace("BookRunRules Type61 assertions: "+(passed+failed-type61Start));
            testCf6RuntimeGates(fixture);
            testCf6TransportGates(fixture);
            testCf6BossPreludeGates(fixture);
            testCf6TransportAdditionalWaves(fixture);
            var wrongBackground:Object=org.flashNight.gesh.object.PersistedSnapshot.clone(fixture);
            wrongBackground.maps[0].background="cf6/../CF6_A01_BG.swf";
            check(!BookDefinition.valid(wrongBackground),"CF6 background rejects traversal under the isolated directory");
            wrongBackground.maps[0].background="cf6/CF6_A02_BG.swf";
            check(!BookDefinition.valid(wrongBackground),"CF6 background must belong to the same map identity");
            var tutorial:Object=org.flashNight.gesh.object.PersistedSnapshot.clone(fixture);
            tutorial.maps[0].id="TUTORIAL";tutorial.maps[0].background="cf6/CF6_Tutorial_BG.swf";
            check(BookDefinition.valid(tutorial),"CF6 tutorial accepts its exact independent background");
            var otherTutorialBackgrounds:Array=["gk1_1_BG.swf","cf6/gk1_1_BG.swf","cf6/CF6_A01_BG.swf",
                "CF6_Tutorial_BG.swf","cf6/Other.swf","cf6\\CF6_Tutorial_BG.swf","cf6/../CF6_Tutorial_BG.swf"];
            for(var tb:Number=0;tb<otherTutorialBackgrounds.length;tb++) {
                tutorial.maps[0].background=otherTutorialBackgrounds[tb];
                check(!BookDefinition.valid(tutorial),"CF6 tutorial rejects old placeholder or substituted background "+otherTutorialBackgrounds[tb]);
            }
            var broken:Object=org.flashNight.gesh.object.PersistedSnapshot.clone(fixture);broken.routeId="plan61";
            check(!BookDefinition.valid(broken),"CF6 future route fails closed");
            broken=org.flashNight.gesh.object.PersistedSnapshot.clone(fixture);broken.actor.experience=0;
            check(!BookDefinition.valid(broken),"CF6 level and cumulative XP must match");
            broken=org.flashNight.gesh.object.PersistedSnapshot.clone(fixture);broken.maps[0].stage.bad=Number.NaN;
            check(!BookDefinition.valid(broken),"CF6 rejects nested NaN in actual AVM1");
            check(!BookDefinition.acceptFor("repair-campus",fixture),"late chapter response cannot populate another book cache");
            check(BookDefinition.acceptFor("cf6-sting",fixture) && BookDefinition.ready("cf6-sting"),"CF6 validated chapter unlocks its own entry");
            var first:Array=BookRunRules.stages(17,0,"cf6-sting"),second:Array=BookRunRules.stages(17,0,"cf6-sting");
            first[0].Wave.SubWave[0].EnemyGroup.Enemy[0].Quantity=99;
            check(second[0].Wave.SubWave[0].EnemyGroup.Enemy[0].Quantity==1 && fixture.maps[0].stage.Wave.SubWave[0].EnemyGroup.Enemy[0].Quantity==1,
                "CF6 plans cannot mutate cached authored encounters or the next run");
            check(second[0].BasicInformation.BookBoss==undefined && second[0].Instances.Instance.length==0
                && second[0].Event[0].Callback.Name=="书中章节","CF6 owns authored encounters and receives chapter callback only");
            check(BookRunRules.stages(17,Number.NaN,"cf6-sting").length==0,"CF6 rejects invalid debug index");
            var run:Object={bookId:"cf6-sting",routeId:"historical",slot:"bookrun_cf6_fixture",outcome:"victory",elapsedMs:12000};
            var quote:Object=BookRunRules.reward(run,{});
            check(quote.sp==0 && quote.firstClear && quote.bestMs==12000,"CF6 victory records progress without external SP");
            run.routeId="plan61";
            check(!BookRunRules.reward(run,{}).firstClear,"CF6 foreign route cannot claim historical clear");
            run.routeId="historical";_root._saveExt={bookRun:run};_root.savePath=run.slot;_root.等级=60;
            check(org.flashNight.arki.scene.BookRunService.playerLevelCapReached(),"CF6 applied temporary character is capped at sixty");
            _root.savePath="original";
            check(!org.flashNight.arki.scene.BookRunService.playerLevelCapReached(),"CF6 stale run cannot cap an original slot");
            check(codec.stringifySafe(BookDefinition.get("repair-campus"))==campus,"CF6 load and plan leave campus definition unchanged");
        } finally {
            definition._cf6=original;_root._saveExt=oldExt;_root.savePath=oldSlot;_root.等级=oldLevel;
        }
    }
    private static function testType61(base:Object):Void {
        var definition:Object=org.flashNight.arki.scene.BookDefinition;
        var previous:Object=definition._type61, oldExt:Object=_root._saveExt;
        var oldSlot=_root.savePath,oldLevel=_root.等级;
        var fixture:Object=org.flashNight.arki.scene.Cf6Type61Fixture.book();
        fixture.routeId="type61";fixture.startingMoney=30000;fixture.startingSkillPoints=1050;
        fixture.actor.level=35;fixture.actor.experience=17372868;fixture.actor.equipment[0].enhancement=1;
        fixture.actor.skills=[{name:"铁匠",level:1},{name:"移动射击",level:10}];fixture.actor.quickSkills=["移动射击"];
        try {
            definition._type61=null;
            check(BookDefinition.valid(fixture),"Type61 accepts its partial level35 actor");
            check(!BookDefinition.acceptFor("cf6-sting",fixture,"historical"),"late Type61 response cannot populate historical cache");
            check(BookDefinition.acceptFor("cf6-sting",fixture,"type61"),"Type61 loads into its own exact route cache");
            check(BookDefinition.get("cf6-sting","type61")===fixture && BookDefinition.get("cf6-sting","historical")!==fixture,"route definitions remain independent");
            fixture.startingSkillPoints=2560;
            check(!BookDefinition.valid(fixture),"Type61 cannot receive preset cost again as free SP");fixture.startingSkillPoints=1050;
            fixture.actor.skills[0].level=2;
            check(!BookDefinition.valid(fixture),"Type61 smith is exactly one");fixture.actor.skills[0].level=1;
            fixture.actor.quickSkills.push("移动射击");
            check(!BookDefinition.valid(fixture),"Type61 quick slots cannot duplicate an equipped skill");fixture.actor.quickSkills.pop();
            var identity:Object={bookId:"cf6-sting",routeId:"type61",slot:"bookrun_type61",seed:7,startedAt:100,outcome:"active"};
            var copy:Object=org.flashNight.gesh.object.PersistedSnapshot.clone(identity);
            check(BookRunRules.sameCf6Run(identity,copy),"Type61 same-run identity survives detached reward copies");
            copy.routeId="historical";
            check(!BookRunRules.sameCf6Run(identity,copy),"historical callbacks cannot consume Type61 ownership");
            copy.routeId="plan61";
            check(!BookRunRules.sameCf6Run(identity,copy),"unrecognized routes stay closed");
            _root._saveExt={bookRun:identity};_root.savePath=identity.slot;
            check(BookDefinition.get("cf6-sting")===fixture,"current Type61 runtime resolves its own definition");
            check(!BookDefinition.ready("cf6-sting","unknown"),"invalid explicit route never falls back to historical");
            identity.outcome="victory";identity.elapsedMs=9000;
            var quote:Object=BookRunRules.reward(identity,{});
            check(quote.sp===0 && quote.firstClear===true && quote.bestMs===9000,"Type61 records a clear without permanent SP");
            _root.等级=55;var below:Boolean=!org.flashNight.arki.scene.BookRunService.playerLevelCapReached();_root.等级=60;
            check(below && org.flashNight.arki.scene.BookRunService.playerLevelCapReached(),"Type61 grows until its real level60 cap");
            check(BookDefinition.supportsTarget("cf6-sting.type61") && BookDefinition.bookForTarget("cf6-sting.type61")==="cf6-sting"
                && BookDefinition.routeForTarget("cf6-sting.type61")==="type61" && !BookDefinition.supportsTarget("cf6-sting.plan61"),"play target resolves only the closed canonical book/route pair");
        } finally { definition._type61=previous;_root._saveExt=oldExt;_root.savePath=oldSlot;_root.等级=oldLevel; }
    }
    private static function testCf6TransportGates(base:Object):Void {
        var names:Array=["A09","A14","A18"],depths:Array=[112,505,147],types:Array=["兵种467","兵种469","兵种463"],levels:Array=[45,50,59],counts:Array=[5,7,5];
        var complete:Object;
        for(var i:Number=0;i<3;i++) {
            var fixture:Object=org.flashNight.gesh.object.PersistedSnapshot.clone(base),m:Object=fixture.maps[0];
            m.id=names[i];m.background="cf6/CF6_"+m.id+"_BG.swf";
            var token:String=m.id+"-transport-"+depths[i];
            m.mechanism.transport={schema:"cf6-transport.v1",id:token,sourceSprite:1868,url:"flashswf/backgrounds/cf6/preparation/CF6_Transport1868.swf",
                x:300,y:300,sortY:305.35,artMatrix:[1,0,0,1,0,0],hitBounds:[-295,-42,268,253],frames:29,dispatchFrame:29,subWaveIndex:1};
            m.stage.Wave.SubWave.push({EnemyGroup:{Enemy:[{Type:types[i],Level:levels[i],Quantity:counts[i],Interval:400,SpawnIndex:0,
                TriggerEvent:{EventName:"Cf6TransportReady",Parameters:[token]}}]}});
            check(BookDefinition.valid(fixture),"CF6 exact transport budget/event accepts "+names[i]);
            if(i==0)complete=fixture;
        }
        var cases:Array=["map","extra","matrix","bounds","native","frame","wave","event","token","duplicate","quantity","interval","owner"];
        for(i=0;i<cases.length;i++) {
            var bad:Object=org.flashNight.gesh.object.PersistedSnapshot.clone(complete);m=bad.maps[0];
            var p:Object=m.mechanism.transport,e:Object=m.stage.Wave.SubWave[1].EnemyGroup.Enemy[0],key:String=cases[i];
            if(key=="map"){m.id="A08";m.background="cf6/CF6_A08_BG.swf";}
            else if(key=="extra")p.extra=true;
            else if(key=="matrix")p.artMatrix=[0,0,0,0,0,0];
            else if(key=="bounds")p.hitBounds=[0,0,0,0];
            else if(key=="native")p.sourceSprite=1869;
            else if(key=="frame")p.dispatchFrame=28;
            else if(key=="wave")p.subWaveIndex=0;
            else if(key=="event")delete e.TriggerEvent;
            else if(key=="token")e.TriggerEvent.Parameters=["foreign"];
            else if(key=="duplicate")m.stage.Wave.SubWave[0].EnemyGroup.Enemy[0].TriggerEvent=e.TriggerEvent;
            else if(key=="quantity")e.Quantity=6;
            else if(key=="interval")e.Interval=100;
            else if(key=="owner")delete m.mechanism.transport;
            check(!BookDefinition.valid(bad),"CF6 transport rejects "+key);
        }
    }
    /** Standard mandatory waves precede the controller's one exact final boss. */
    private static function cf6PreludeFixture(base:Object,id:String,phased:Boolean):Object {
        var fixture:Object=org.flashNight.gesh.object.PersistedSnapshot.clone(base),map:Object=fixture.maps[0];
        map.id=id;map.background="cf6/CF6_"+id+"_BG.swf";
        if(id=="A20")map.mechanism.elderFinale=phased;
        map.stage.SpawnPoint={Point:[{x:100,y:300,NoCount:false}]};
        var boss:Object={Type:id=="A20"?"兵种473":"兵种463",Level:60,Quantity:1,InstanceName:"cf6Boss_"+id,Parameters:{}};
        if(id=="A20")boss.Parameters.老头变身=phased;
        map.stage.Wave.SubWave=[
            {WaveInformation:{Duration:0,FinishRequirement:0,MapNoCount:false},EnemyGroup:{Enemy:[
                {Type:"兵种461",Level:60,Quantity:2,SpawnIndex:0,Parameters:{掉落物:[]}}]}},
            {WaveInformation:{Duration:0,FinishRequirement:0},EnemyGroup:{Enemy:[boss]}}];
        map.bossEncounter={instanceName:"cf6Boss_"+id,maxAlive:2,maxRanged:0,intervalFrames:30,
            groups:[{hpRatio:1,enemies:[{Type:"兵种461",Level:60,Quantity:1,ranged:false,SpawnIndex:"left",Parameters:{}}]}]};
        if(phased) {
            map.bossEncounter.nextPhase=org.flashNight.gesh.object.PersistedSnapshot.clone(map.bossEncounter);
            map.bossEncounter.nextPhase.instanceName="cf6Boss_A20__elderbot";
        }
        return fixture;
    }
    private static function testCf6BossPreludeGates(base:Object):Void {
        var maps:Array=["A06","A20","A20"],phases:Array=[false,false,true];
        var primary:Object;
        for(var i:Number=0;i<maps.length;i++) {
            var fixture:Object=cf6PreludeFixture(base,maps[i],phases[i]);
            check(BookDefinition.valid(fixture),"CF6 mandatory prelude accepts "+maps[i]+" phased="+phases[i]);
            if(i==0)primary=fixture;
        }
        var single:Object=org.flashNight.gesh.object.PersistedSnapshot.clone(primary);
        single.maps[0].stage.Wave.SubWave.shift();
        check(BookDefinition.valid(single),"CF6 one-wave boss remains valid without a prelude");
        var six:Object=org.flashNight.gesh.object.PersistedSnapshot.clone(primary);
        var sixWaves:Array=six.maps[0].stage.Wave.SubWave;
        while(sixWaves.length<6)sixWaves.unshift(org.flashNight.gesh.object.PersistedSnapshot.clone(sixWaves[0]));
        check(BookDefinition.valid(six),"CF6 five mandatory preludes accept before the unique sixth-wave boss");
        var flags:Object=org.flashNight.gesh.object.PersistedSnapshot.clone(primary);
        flags.maps[0].stage.SpawnPoint.Point[0].NoCount=0;
        flags.maps[0].stage.Wave.SubWave[0].WaveInformation.MapNoCount=0;
        check(BookDefinition.valid(flags),"CF6 counted prelude flags accept explicit numeric zero");
        delete flags.maps[0].stage.SpawnPoint.Point[0].NoCount;
        delete flags.maps[0].stage.Wave.SubWave[0].WaveInformation.MapNoCount;
        check(BookDefinition.valid(flags),"CF6 omitted count flags retain mandatory standard counting");
        var cases:Array=["zeroWaves","sevenWaves","emptyPrelude","largePrelude",
            "durationMissing","durationPositive","durationBoolean","durationString",
            "finishMissing","finishPositive","finishBoolean","finishString",
            "mapUncounted","mapStringZero","mapNull","pointUncounted","pointStringZero","pointNull",
            "pointsScalar","pointPrimitive","instanceName","instanceNull","primaryType","humanType","robotType",
            "parametersNull","parametersArray","parametersString","bossNotLast","finalDuplicate","finalType","finalName","finalQuantity","latePreludeUncounted"];
        for(i=0;i<cases.length;i++) {
            var key:String=cases[i];
            var bad:Object=org.flashNight.gesh.object.PersistedSnapshot.clone(key=="sevenWaves" || key=="latePreludeUncounted"?six:primary);
            var map:Object=bad.maps[0],waves:Array=map.stage.Wave.SubWave;
            var wave:Object=waves[0],info:Object=wave.WaveInformation,enemy:Object=wave.EnemyGroup.Enemy[0];
            var boss:Object=waves[waves.length-1].EnemyGroup.Enemy[0];
            if(key=="zeroWaves")map.stage.Wave.SubWave=[];
            else if(key=="sevenWaves")waves.unshift(org.flashNight.gesh.object.PersistedSnapshot.clone(wave));
            else if(key=="emptyPrelude")wave.EnemyGroup.Enemy=[];
            else if(key=="largePrelude")while(wave.EnemyGroup.Enemy.length<33)wave.EnemyGroup.Enemy.push(org.flashNight.gesh.object.PersistedSnapshot.clone(enemy));
            else if(key=="durationMissing")delete info.Duration;
            else if(key=="durationPositive")info.Duration=1;
            else if(key=="durationBoolean")info.Duration=false;
            else if(key=="durationString")info.Duration="0";
            else if(key=="finishMissing")delete info.FinishRequirement;
            else if(key=="finishPositive")info.FinishRequirement=1;
            else if(key=="finishBoolean")info.FinishRequirement=false;
            else if(key=="finishString")info.FinishRequirement="0";
            else if(key=="mapUncounted")info.MapNoCount=true;
            else if(key=="mapStringZero")info.MapNoCount="0";
            else if(key=="mapNull")info.MapNoCount=null;
            else if(key=="pointUncounted")map.stage.SpawnPoint.Point[0].NoCount=true;
            else if(key=="pointStringZero")map.stage.SpawnPoint.Point[0].NoCount="0";
            else if(key=="pointNull")map.stage.SpawnPoint.Point[0].NoCount=null;
            else if(key=="pointsScalar")map.stage.SpawnPoint.Point={NoCount:false};
            else if(key=="pointPrimitive")map.stage.SpawnPoint.Point=[1];
            else if(key=="instanceName")enemy.InstanceName="prelude-owner";
            else if(key=="instanceNull")enemy.InstanceName=null;
            else if(key=="primaryType")enemy.Type="兵种463";
            else if(key=="humanType")enemy.Type="兵种473";
            else if(key=="robotType")enemy.Type="兵种474";
            else if(key=="parametersNull")enemy.Parameters=null;
            else if(key=="parametersArray")enemy.Parameters=[];
            else if(key=="parametersString")enemy.Parameters="invalid";
            else if(key=="bossNotLast")waves.push(org.flashNight.gesh.object.PersistedSnapshot.clone(wave));
            else if(key=="finalDuplicate")waves[waves.length-1].EnemyGroup.Enemy.push(org.flashNight.gesh.object.PersistedSnapshot.clone(enemy));
            else if(key=="finalType")boss.Type="兵种461";
            else if(key=="finalName")boss.InstanceName="foreign-boss";
            else if(key=="finalQuantity")boss.Quantity=2;
            else if(key=="latePreludeUncounted")waves[4].WaveInformation.MapNoCount=true;
            check(!BookDefinition.valid(bad),"CF6 mandatory prelude rejects "+key);
        }
        var reserved:Array=["cf6BossOwnerToken","cf6SupportIdentity","InstanceName","产生源","老头变身"];
        for(i=0;i<reserved.length;i++) {
            bad=org.flashNight.gesh.object.PersistedSnapshot.clone(primary);
            bad.maps[0].stage.Wave.SubWave[0].EnemyGroup.Enemy[0].Parameters[reserved[i]]=null;
            check(!BookDefinition.valid(bad),"CF6 mandatory prelude rejects reserved parameter presence "+reserved[i]);
        }
    }
    private static function testCf6TransportAdditionalWaves(base:Object):Void {
        var names:Array=["A09","A14","A18"],depths:Array=[112,505,147],types:Array=["兵种467","兵种469","兵种463"],levels:Array=[45,50,59],counts:Array=[5,7,5];
        var complete:Object;
        for(var i:Number=0;i<names.length;i++) {
            var fixture:Object=org.flashNight.gesh.object.PersistedSnapshot.clone(base),map:Object=fixture.maps[0];
            map.id=names[i];map.background="cf6/CF6_"+map.id+"_BG.swf";
            var token:String=map.id+"-transport-"+depths[i];
            map.mechanism.transport={schema:"cf6-transport.v1",id:token,sourceSprite:1868,url:"flashswf/backgrounds/cf6/preparation/CF6_Transport1868.swf",
                x:300,y:300,sortY:305.35,artMatrix:[1,0,0,1,0,0],hitBounds:[-295,-42,268,253],frames:29,dispatchFrame:29,subWaveIndex:1};
            var waves:Array=map.stage.Wave.SubWave;
            waves.push({EnemyGroup:{Enemy:[{Type:types[i],Level:levels[i],Quantity:counts[i],Interval:400,SpawnIndex:0,
                TriggerEvent:{EventName:"Cf6TransportReady",Parameters:[token]}}]}});
            var ordinary:Object=org.flashNight.gesh.object.PersistedSnapshot.clone(waves[0]);
            ordinary.WaveInformation={Duration:0,FinishRequirement:0};waves.push(ordinary);
            check(BookDefinition.valid(fixture),"CF6 transport accepts a later ordinary wave "+names[i]);
            while(waves.length<6)waves.push(org.flashNight.gesh.object.PersistedSnapshot.clone(ordinary));
            check(BookDefinition.valid(fixture),"CF6 transport accepts six waves with unchanged second-wave budget "+names[i]);
            var bad:Object=org.flashNight.gesh.object.PersistedSnapshot.clone(fixture),bw:Array=bad.maps[0].stage.Wave.SubWave;
            bw[5].EnemyGroup.Enemy[0].TriggerEvent=org.flashNight.gesh.object.PersistedSnapshot.clone(bw[1].EnemyGroup.Enemy[0].TriggerEvent);
            check(!BookDefinition.valid(bad),"CF6 transport rejects a duplicate late transport event "+names[i]);
            delete bw[1].EnemyGroup.Enemy[0].TriggerEvent;
            check(!BookDefinition.valid(bad),"CF6 transport rejects even a unique event moved to a late wave "+names[i]);
            if(i>0) {
                bad=org.flashNight.gesh.object.PersistedSnapshot.clone(fixture);
                bad.maps[0].stage.Wave.SubWave[1].EnemyGroup.Enemy[0].Quantity=counts[i]+1;
                check(!BookDefinition.valid(bad),"CF6 extra waves cannot relax exact transport quantity "+names[i]);
            }
            if(i==0)complete=fixture;
        }
        var tooMany:Object=org.flashNight.gesh.object.PersistedSnapshot.clone(complete);
        tooMany.maps[0].stage.Wave.SubWave.push(org.flashNight.gesh.object.PersistedSnapshot.clone(tooMany.maps[0].stage.Wave.SubWave[2]));
        check(!BookDefinition.valid(tooMany),"CF6 transport rejects seven waves");
        var booleanSpawn:Object=org.flashNight.gesh.object.PersistedSnapshot.clone(complete);
        booleanSpawn.maps[0].stage.Wave.SubWave[1].EnemyGroup.Enemy[0].SpawnIndex=false;
        check(!BookDefinition.valid(booleanSpawn),"CF6 transport cannot treat boolean false as numeric spawn index zero");
    }
    private static function findDrop(enemy:Object, name:String):Object {
        var rules:Array = enemy.Parameters.掉落物;
        for (var i:Number = 0; i < rules.length; i++) {
            if (rules[i].名字 == name) return rules[i];
        }
        return null;
    }
    private static function testCf6RuntimeGates(base:Object):Void {
        var merged:Object=org.flashNight.gesh.object.PersistedSnapshot.clone(base);
        var room:Object=merged.maps[0];room.id="A20";room.background="cf6/CF6_A20_BG.swf";
        room.mechanism.elderFinale=true;
        room.stage.Wave.SubWave=[{EnemyGroup:{Enemy:[{Type:"兵种473",Level:60,Quantity:1,
            InstanceName:"cf6Boss_A20",Parameters:{老头变身:true}}]}}];
        room.bossEncounter={instanceName:"cf6Boss_A20",maxAlive:2,maxRanged:0,intervalFrames:30,
            groups:[{hpRatio:1,enemies:[{Type:"兵种461",Level:60,Quantity:1,ranged:false,SpawnIndex:"left",Parameters:{}}]}]};
        room.bossEncounter.nextPhase=org.flashNight.gesh.object.PersistedSnapshot.clone(room.bossEncounter);
        room.bossEncounter.nextPhase.instanceName="cf6Boss_A20__elderbot";
        check(BookDefinition.valid(merged),"CF6 same-room human/robot plan accepts exact native successor identity");
        var old:Object=org.flashNight.gesh.object.PersistedSnapshot.clone(merged);
        old.maps[0].mechanism.elderFinale=false;delete old.maps[0].bossEncounter.nextPhase;
        old.maps[0].stage.Wave.SubWave[0].EnemyGroup.Enemy[0].Parameters.老头变身=false;
        check(BookDefinition.valid(old),"CF6 non-phased authored fixture retains explicit disabled transform contract");
        var invalid:Array=["missingPlan","missingNext","switchFalse","switchOffNext","nextName","nestedNext",
            "duplicateA22","nextCap","nextRanged","nextBudget","nextSpawn","nextPod"];
        for(var i:Number=0;i<invalid.length;i++) {
            var bad:Object=org.flashNight.gesh.object.PersistedSnapshot.clone(merged);
            var map:Object=bad.maps[0],p:Object=map.bossEncounter,child:Object=p.nextPhase;
            var key:String=invalid[i];
            if(key=="missingPlan") delete map.bossEncounter;
            else if(key=="missingNext") delete p.nextPhase;
            else if(key=="switchFalse") map.stage.Wave.SubWave[0].EnemyGroup.Enemy[0].Parameters.老头变身=false;
            else if(key=="switchOffNext") {
                map.mechanism.elderFinale=false;map.stage.Wave.SubWave[0].EnemyGroup.Enemy[0].Parameters.老头变身=false;
            } else if(key=="nextName") child.instanceName="cf6Boss_A22";
            else if(key=="nestedNext") child.nextPhase={};
            else if(key=="duplicateA22") {
                var last:Object=org.flashNight.gesh.object.PersistedSnapshot.clone(map);
                last.id="A22";last.background="cf6/CF6_A22_BG.swf";delete last.mechanism.elderFinale;
                last.bossEncounter=org.flashNight.gesh.object.PersistedSnapshot.clone(child);last.bossEncounter.instanceName="cf6Boss_A22";
                last.stage.Wave.SubWave[0].EnemyGroup.Enemy=[{Type:"兵种474",Level:60,Quantity:1,InstanceName:"cf6Boss_A22"}];
                bad.maps.push(last);
            } else if(key=="nextCap") child.maxAlive=0;
            else if(key=="nextRanged") child.groups[0].enemies[0].ranged=true;
            else if(key=="nextBudget") child.groups[0].enemies[0].Quantity=129;
            else if(key=="nextSpawn") child.groups[0].enemies[0].SpawnIndex=0;
            else if(key=="nextPod") child.groups[0].enemies[0].podId="foreign-pod";
            check(!BookDefinition.valid(bad),"CF6 merged finale rejects "+key);
        }
        var ownership:Array=["cf6BossOwnerToken","cf6SupportIdentity","publishStageEvent","产生源","InstanceName"];
        for(i=0;i<ownership.length;i++) {
            bad=org.flashNight.gesh.object.PersistedSnapshot.clone(merged);
            bad.maps[0].bossEncounter.nextPhase.groups[0].enemies[0].Parameters[ownership[i]]=null;
            check(!BookDefinition.valid(bad),"CF6 next-phase ownership field presence is forbidden even when null: "+ownership[i]);
        }
        var expressions:Array=["普通","微笑","挑战","惊讶","侦察","严肃","愤怒"];
        for(i=0;i<expressions.length;i++) {
            bad=org.flashNight.gesh.object.PersistedSnapshot.clone(base);
            bad.maps[0].dialogue=[{speaker:"Andy",text:"test",char:"Andy Law#"+expressions[i]}];
            check(BookDefinition.valid(bad),"CF6 exact approved Andy expression accepts: "+expressions[i]);
        }
        bad.maps[0].dialogue[0].speaker="other";
        check(!BookDefinition.valid(bad),"CF6 explicit Andy portrait cannot attach to another speaker");
        bad.maps[0].dialogue[0].speaker="Andy Law";bad.maps[0].dialogue[0].char="Andy Law#unreviewed";
        check(!BookDefinition.valid(bad),"CF6 unknown expression rejected");
        bad.maps[0].dialogue[0].char="Andy Law#普通";bad.maps[0].dialogue[0].portrait="injected";
        check(!BookDefinition.valid(bad),"CF6 dialogue cannot carry an alternate portrait field");
        delete bad.maps[0].dialogue[0].portrait;bad.maps[0].dialogue[0].char=null;
        check(!BookDefinition.valid(bad),"CF6 explicit null char cannot masquerade as omitted fallback");
        var turret:Object=org.flashNight.gesh.object.PersistedSnapshot.clone(base);
        turret.maps[0].mechanism.turrets={assetUrl:"flashswf/backgrounds/cf6/CF6_A01_Turret.swf",
            linkage:"CF6教学炮塔-A01自动炮",filterMarker:"cf6-a01-turret-zombie",fireIntervalFrames:18,fireFrameOffset:11,
            turrets:[{x:100,y:100,facing:"right",ownFootprint:[90,90,110,110]},
                {x:200,y:100,facing:"right",ownFootprint:[190,90,210,110]}]};
        check(BookDefinition.valid(turret),"CF6 A01 exact turret emitter lies strictly inside its own footprint");
        var footprints:Array=[null,[90,90,110],[100,90,110,110],["90",90,110,110],[90,90,90,110],[Number.NaN,90,110,110]];
        for(i=0;i<footprints.length;i++) {
            bad=org.flashNight.gesh.object.PersistedSnapshot.clone(turret);
            if(i==0) delete bad.maps[0].mechanism.turrets.turrets[0].ownFootprint;
            else bad.maps[0].mechanism.turrets.turrets[0].ownFootprint=footprints[i];
            check(!BookDefinition.valid(bad),"CF6 A01 rejects missing/malformed/noncontaining own footprint case "+i);
        }
    }
    private static function carrier(wave:Object):Object {
        var enemies:Array = wave.EnemyGroup.Enemy;
        return enemies[enemies.length - 1];
    }
    private static function testProgressionAndSupplies(plan:Array, config:Object):Void {
        var experienceValid:Boolean = true, moneyValid:Boolean = true;
        var healingValid:Boolean = true, supportValid:Boolean = true, budgetsValid:Boolean = true;
        var cumulative:Number = 0, milestones:Array = [];
        for (var m:Number = 0; m < plan.length; m++) {
            var waves:Array = plan[m].Wave.SubWave;
            var total:Number = 0, hasMana:Boolean = false, hasAmmo:Boolean = false, hasGrenades:Boolean = false;
            for (var w:Number = 0; w < waves.length; w++) {
                var enemy:Object = carrier(waves[w]);
                var xp:Object = findDrop(enemy, "经验值");
                experienceValid = experienceValid && xp != null && xp.概率 == 100
                    && xp.最小数量 > 0 && xp.最小数量 == xp.最大数量 && xp.总数 >= xp.最大数量;
                total += xp.最小数量 * enemy.Quantity;
                var money:Object = findDrop(enemy, "金币");
                moneyValid = moneyValid && money != null && findDrop(enemy, "金钱") == null
                    && money.概率 == 100 && money.最小数量 >= 1500 && money.总数 >= money.最大数量;
                var healing:Object = findDrop(enemy, config.maps[m].healingItem);
                healingValid = healingValid && healing != null && healing.概率 == 100
                    && healing.最小数量 >= 3 && healing.总数 >= healing.最大数量;
                var mana:Object = findDrop(enemy, config.maps[m].manaItem);
                var ammo:Object = findDrop(enemy, config.ammoBundle.name);
                if (mana != null && mana.概率 == 100 && mana.最小数量 >= 1) hasMana = true;
                if (ammo != null && ammo.概率 == 100 && ammo.最小数量 == 1 && ammo.总数 == 1) hasAmmo = true;
                var grenades:Object = findDrop(enemy, "普通手雷");
                if (grenades != null && grenades.概率 == 100 && grenades.最小数量 >= 4) hasGrenades = true;
            }
            supportValid = supportValid && (waves.length < 3 || (hasMana && hasAmmo && hasGrenades));
            budgetsValid = budgetsValid && total >= config.maps[m].experience
                && total < config.maps[m].experience + waves.length;
            cumulative += total; milestones.push(cumulative);
        }
        check(experienceValid, "each wave carries one guaranteed concentrated XP pickup with sufficient total cap");
        check(moneyValid, "currency uses the real item dictionary key and covers basic consumables");
        check(healingValid, "healing potions are independent of random instant buffs");
        check(supportValid, "each regular map guarantees mana, magazines and grenades before the next encounter tier");
        check(budgetsValid, "map XP budget survives variable enemy counts within rounding only");
        // 当前正式升级曲线的累计门槛：6 级 8625，9 级 53748，15 级 499908。
        check(milestones[0] >= 8625, "first map pickup budget unlocks the baseball bat");
        check(milestones[1] >= 53748, "second map pickup budget unlocks the military knife");
        check(milestones[5] >= 499908, "all candidate gear is usable before the boss");
        var acrossSeeds:Boolean = true;
        for (var seed:Number = 1; seed <= 64; seed++) {
            var generated:Array = BookRunRules.stages(seed * 7919, 0);
            for (m = 0; m < generated.length; m++) {
                var earned:Number = 0, count:Number = 0;
                waves = generated[m].Wave.SubWave;
                for (w = 0; w < waves.length; w++) {
                    enemy = carrier(waves[w]);
                    earned += findDrop(enemy, "经验值").最小数量 * enemy.Quantity;
                    count += enemy.Quantity;
                }
                acrossSeeds = acrossSeeds && earned >= config.maps[m].experience
                    && earned < config.maps[m].experience + count;
            }
        }
        check(acrossSeeds, "64 different spawn plans preserve every map growth budget");
    }
    private static function testSurvivalChoices(plan:Array, config:Object):Void {
        var armorValid:Boolean = true, differentArmor:Boolean = true, medicalValid:Boolean = true;
        var randomBuffValid:Boolean = true, trainerValid:Boolean = true;
        for (var m:Number = 0; m < plan.length; m++) {
            var map:Object = config.maps[m], waves:Array = plan[m].Wave.SubWave;
            var previousArmor:String = "";
            for (var w:Number = 0; w < waves.length; w++) {
                var enemy:Object = carrier(waves[w]);
                var armorCount:Number = 0, armorName:String = "";
                for (var a:Number = 0; a < map.armor.length; a++) {
                    var armor:Object = findDrop(enemy, map.armor[a]);
                    if (armor != null) {
                        armorCount++; armorName = armor.名字;
                        armorValid = armorValid && armor.概率 == 100 && armor.最小数量 == 1
                            && armor.最大数量 == 1 && armor.总数 == 1;
                    }
                }
                armorValid = armorValid && armorCount == (w < 2 ? 1 : 0);
                if (w == 1) differentArmor = differentArmor && armorName != previousArmor;
                previousArmor = armorName;
                var emergency:Object = findDrop(enemy, "战场复合急救包");
                if (w % 2 == 0) medicalValid = medicalValid && emergency != null
                    && emergency.概率 == 100 && emergency.最小数量 == 1 && emergency.总数 == 1;
                else {
                    var hasBuff:Boolean = false;
                    for (var b:Number = 0; b < config.supplies.length; b++) {
                        var buff:Object = findDrop(enemy, config.supplies[b]);
                        if (buff != null && buff.概率 == 25) hasBuff = true;
                    }
                    randomBuffValid = randomBuffValid && emergency == null && hasBuff;
                }
            }
            var trainer:Object = plan[m].Instances.Instance[0].Parameters.可学的技能;
            for (var s:Number = 0; s < config.skills.length; s++)
                trainerValid = trainerValid && trainer[String(s)] == config.skills[s];
            var count:Number = 0;
            for (var key:String in trainer) count++;
            trainerValid = trainerValid && count == config.skills.length;
        }
        check(armorValid, "first two waves guarantee one armor each independently of weapon rolls");
        check(differentArmor, "two guaranteed armor pieces in a map are different choices");
        check(medicalValid, "first and third waves guarantee exactly one compound emergency pickup");
        check(randomBuffValid, "middle waves retain the random battlefield buff slot");
        check(trainerValid && config.skills.length == 11, "every map exposes only the 11 essential skills only");
        check(config.maps[0].healingItem == "普通hp药剂" && config.maps[2].healingItem == "加强抗生素药剂"
            && config.maps[5].healingItem == "大HP药剂" && config.maps[5].manaItem == "大MP药剂",
            "carried medicines progress from early supplies to late HP and MP recovery");
    }
    private static function testBuildResources(plan:Array, config:Object):Void {
        var spValid:Boolean = true, materialValid:Boolean = true, sequenceValid:Boolean = true;
        var medValid:Boolean = true;
        var spTotal:Number = 0, tierTotal:Number = 0, stoneTotal:Number = 0;
        var hp:Array = ["普通hp药剂", "普通hp药剂", "加强抗生素药剂", "加强抗生素药剂", "大HP药剂", "大HP药剂", "大HP药剂"];
        var mp:Array = ["普通mp药剂", "普通mp药剂", "加强mp药剂", "加强mp药剂", "大MP药剂", "大MP药剂", "大MP药剂"];
        var types:Array = [[44,45], [48,49], [447,448], [436,437], [449,450], [444,446], [455]];
        for (var m:Number = 0; m < plan.length; m++) {
            var waves:Array = plan[m].Wave.SubWave, map:Object = config.maps[m];
            for (var w:Number = 0; w < waves.length; w++) {
                var enemy:Object = carrier(waves[w]);
                sequenceValid = sequenceValid && (enemy.Type == "兵种" + types[m][0]
                    || enemy.Type == "兵种" + types[m][1]);
                var sp:Object = findDrop(enemy, "技能点");
                if (m < 6 && w == 0) {
                    spValid = spValid && sp != null && sp.概率 == 100
                        && sp.最小数量 == map.skillPoints && sp.最大数量 == sp.最小数量
                        && sp.总数 == sp.最小数量;
                    spTotal += sp.最小数量;
                } else spValid = spValid && sp == null;
                medValid = medValid && findDrop(enemy, hp[m]) != null
                    && (w != 0 || findDrop(enemy, mp[m]) != null);
                if (w < map.materials.length) {
                    var material:Object = map.materials[w];
                    var drop:Object = findDrop(enemy, material.name);
                    materialValid = materialValid && drop != null && drop.概率 == (m >= 2 && m <= 5 ? 75 : 100)
                        && drop.最小数量 == material.count && drop.最大数量 == material.count
                        && drop.总数 == material.count;
                    if (drop.名字 == "二阶复合防御组件") tierTotal += drop.最小数量;
                    if (drop.名字 == "强化石") stoneTotal += drop.最小数量;
                }
            }
        }
        check(sequenceValid, "both student factions precede military students and sword club");
        check(config.maps[4].level[0] == 5 && config.maps[4].level[1] == 7,
            "moving military later does not silently raise their existing levels");
        check(medValid, "actual pickup plans use small then medium then large HP and MP potions");
        check(spValid && spTotal == 360, "360 local SP in six guaranteed single stacks before the boss");
        check(materialValid, "optional material value in maps three through six moves one quarter to cards");
        check(tierTotal == 5 && stoneTotal == 78, "five tier components and 78 enhancement stones support local tuning");
        var unchanged:Array = BookRunRules.stages(1729, 0);
        var itemName:String = config.maps[0].materials[0].name;
        findDrop(carrier(unchanged[0].Wave.SubWave[0]), itemName).总数 = 0;
        check(findDrop(carrier(plan[0].Wave.SubWave[0]), itemName).总数 == 3,
            "consuming a material stack never depletes another generated plan");
    }
    private static function testLoadoutChoices(plan:Array, config:Object):Void {
        var exact:Boolean = true, count:Number = 0;
        for (var c:Number = 0; c < config.buildChoices.length; c++) {
            var choice:Object = config.buildChoices[c];
            for (var m:Number = 0; m < plan.length; m++) {
                var waves:Array = plan[m].Wave.SubWave;
                for (var w:Number = 0; w < waves.length; w++) {
                    var voucher:Object = findDrop(carrier(waves[w]), choice.choiceItem);
                    var expected:Boolean = m == choice.afterMap && w == waves.length - 1;
                    exact = exact && ((voucher != null) == expected);
                    if (voucher != null) {
                        count++;
                        exact = exact && voucher.概率 == 100 && voucher.最小数量 == 1
                            && voucher.最大数量 == 1 && voucher.总数 == 1;
                    }
                }
            }
        }
        check(exact && count == 2, "only two single-use vouchers appear, at the second and fourth map finales");
        check(config.startingSkillPoints == 120, "initial SP allows an early build without taking from the original character");
        var seedIndependent:Boolean = true;
        for (var seed:Number = 1; seed <= 64; seed++) {
            var other:Array = BookRunRules.stages(seed * 7919, 0);
            for (c = 0; c < config.buildChoices.length; c++) {
                choice = config.buildChoices[c];
                waves = other[choice.afterMap].Wave.SubWave;
                seedIndependent = seedIndependent && findDrop(carrier(waves[waves.length - 1]), choice.choiceItem).总数 == 1;
            }
        }
        check(seedIndependent, "equipment RNG cannot remove or multiply either build opportunity");
        var jump:Array = BookRunRules.stages(1729, 4);
        var noPastVouchers:Boolean = true;
        for (m = 0; m < jump.length; m++) {
            waves = jump[m].Wave.SubWave;
            for (w = 0; w < waves.length; w++) for (c = 0; c < config.buildChoices.length; c++)
                noPastVouchers = noPastVouchers && findDrop(carrier(waves[w]), config.buildChoices[c].choiceItem) == null;
        }
        check(noPastVouchers, "a debug map jump does not reissue earlier checkpoint vouchers");
    }
    public static function runAllTests():Void {
        passed = 0; failed = 0;
        var codec:LiteJSON = new LiteJSON();
        var first:Array = BookRunRules.stages(1729, 0);
        var same:Array = BookRunRules.stages(1729, 0);
        var changed:Array = BookRunRules.stages(1730, 0);
        check(first.length == 7, "seven maps");
        check(codec.stringifySafe(first) == codec.stringifySafe(same), "seed reproduces complete spawn plan");
        check(codec.stringifySafe(first) != codec.stringifySafe(changed), "different seed changes plan");
        check(codec.stringifySafe(BookRunRules.stages(1729, 6)[0]) == codec.stringifySafe(first[6]), "boss jump preserves plan");
        var config:Object = BookDefinition.get();
        check(BookDefinition.valid(config), "runtime config accepts generated data");
        var broken:Object = org.flashNight.gesh.object.PersistedSnapshot.clone(config);
        broken.maps[0].background = "../outside.swf";
        check(!BookDefinition.valid(broken), "runtime config rejects traversal");
        broken = org.flashNight.gesh.object.PersistedSnapshot.clone(config); broken.maps[0].count = [0, 999];
        check(!BookDefinition.valid(broken), "runtime config rejects malformed spawn range");
        check(BookDefinition.accept(config) && BookDefinition.ready(), "validated data unlocks runtime entry");
        var waveCount:Number = 0;
        var bounded:Boolean = true, drops:Boolean = true, services:Boolean = true, concentrated:Boolean = true;
        var priorDropSlots:Number = 0, currentDropSlots:Number = 0, cadence:Boolean = true;
        for (var m:Number = 0; m < first.length; m++) {
            var map:Object = config.maps[m];
            services = services && first[m].Instances.Instance[0].Parameters.商店检索名 == "书中-迷之盔甲君";
            var waves:Array = first[m].Wave.SubWave;
            for (var w:Number = 0; w < waves.length; w++) {
                waveCount++;
                var group:Array = waves[w].EnemyGroup.Enemy;
                var quantity:Number = 0, carriers:Number = 0;
                var spawnTimes:Array = [];
                for (var g:Number = 0; g < group.length; g++) {
                    quantity += group[g].Quantity;
                    bounded = bounded && group[g].Level >= map.level[0] && group[g].Level <= map.level[1];
                    var slots:Number = group[g].Parameters.掉落物.length;
                    currentDropSlots += slots * group[g].Quantity;
                    if (slots > 0) { carriers++; concentrated = concentrated && group[g].Quantity == 1; }
                    for (var n:Number = 0; n < group[g].Quantity; n++)
                        spawnTimes.push(Number(group[g].Delay || 0) + (n + 1) * group[g].Interval);
                }
                spawnTimes.sort(Array.NUMERIC);
                for (var t:Number = 0; t < spawnTimes.length; t++) cadence = cadence && spawnTimes[t] == (t + 1) * 900;
                concentrated = concentrated && carriers == 1;
                priorDropSlots += map.count[0] * 6;
                bounded = bounded && quantity >= map.count[0] && quantity <= map.count[1];
                var enemy:Object = carrier(waves[w]);
                var expectedSlots:Number = 6 + (w < config.loot.armorWaves ? 1 : 0)
                    + (w == 0 && map.skillPoints > 0 ? 1 : 0) + (w < map.materials.length ? 1 : 0)
                    + (m < 6 && w == map.waves - 1 ? 2 : 0);
                drops = drops && enemy.Parameters.掉落物.length == expectedSlots
                    && findDrop(enemy, "金币") != null;
            }
        }
        check(waveCount == 19 && bounded, "nineteen bounded waves");
        check(drops, "carrier adds at most one armor, one material and one map SP stack to existing supplies");
        check(concentrated, "exactly one carrier per wave including the single-enemy boss");
        check(cadence, "splitting the carrier preserves the original 900ms arrival cadence without a double spawn");
        check(currentDropSlots == 163 && currentDropSlots < priorDropSlots * 0.75,
            "six choice vouchers and the K budget still cut pickup rules by at least a quarter of the minimum old scatter");
        check(services, "each stage exposes existing shop and skill service");
        check(first[6].Wave.SubWave[0].EnemyGroup.Enemy[0].Type == "兵种455", "physical teacher boss");
        first[0].Wave.SubWave[0].EnemyGroup.Enemy[0].Quantity = 999;
        check(same[0].Wave.SubWave[0].EnemyGroup.Enemy[0].Quantity != 999, "plans do not alias");
        testProgressionAndSupplies(same, config);
        testSurvivalChoices(same, config);
        testBuildResources(same, config);
        testLoadoutChoices(same, config);
        var kTotal:Number=0, deliveryCount:Number=0, budgetOk:Boolean=true;
        for(var bm:Number=0;bm<same.length;bm++) {
            var bw:Array=same[bm].Wave.SubWave;
            for(var wi:Number=0;wi<bw.length;wi++) {
                var budgetDrop:Object=findDrop(carrier(bw[wi]),"K点");
                if(budgetDrop!=null) {kTotal+=budgetDrop.最小数量;budgetOk=budgetOk&&bm<6&&wi==bw.length-1&&budgetDrop.最小数量>=200&&budgetDrop.最大数量<=300&&budgetDrop.概率==100;}
                for(var mi:Number=0;mi<config.minorChoices.length;mi++) if(findDrop(carrier(bw[wi]),config.minorChoices[mi].choiceItem)!=null) deliveryCount++;
            }
        }
        check(budgetOk&&kTotal>=1200&&kTotal<=1800,"six exact K budgets replace random coin conversion");
        check(deliveryCount==4,"four small choices supplement two complete loadout choices");
        findDrop(carrier(first[0].Wave.SubWave[0]), "经验值").总数 = 0;
        check(findDrop(carrier(same[0].Wave.SubWave[0]), "经验值").总数 > 0
                && findDrop(carrier(first[0].Wave.SubWave[1]), "经验值").总数 > 0,
            "consuming one XP drop does not deplete other waves or plans");
        var run:Object = {bookId:"repair-campus",outcome:"victory",elapsedMs:31 * 60000};
        var quote:Object = BookRunRules.reward(run, {});
        check(quote.sp == 45 && quote.firstClear && quote.bestTier == 0, "first clear is a personal best");
        quote = BookRunRules.reward(run, {firstClear:true,bestTier:0,bestMs:31 * 60000});
        check(quote.sp == 5, "ordinary clear");
        run.elapsedMs = 20 * 60000;
        quote = BookRunRules.reward(run, {});
        check(quote.sp == 45 && quote.bestTier == 3, "first clear pays the personal-best total only");
        quote = BookRunRules.reward(run, {firstClear:true,bestTier:3,bestMs:19 * 60000});
        check(quote.sp == 5 && quote.bestMs == 19 * 60000, "record cannot be farmed again");
        quote = BookRunRules.reward(run, {firstClear:true,bestTier:1});
        check(quote.sp == 45, "missing old time establishes a personal best");
        run.outcome = "defeat";
        quote = BookRunRules.reward(run, {});
        check(quote.sp == 0 && !quote.firstClear && quote.bestTier == 0, "defeat neither pays nor consumes first clear");
        run.outcome = "abandoned";
        check(BookRunRules.reward(run, {}).sp == 0, "abandon has zero reward");
        run.outcome = "active";
        check(BookRunRules.reward(run, {}).sp == 0, "interrupted active run has zero reward");
        run.outcome = "victory"; run.debug = true;
        check(BookRunRules.reward(run, {}).sp == 0, "debug boss jump has zero reward");
        run.debug = false; run.bookId = "another-book";
        check(BookRunRules.reward(run, {}).sp == 0, "foreign book result rejected");
        run.bookId = "repair-campus";
        run.elapsedMs = Number.NaN;
        check(BookRunRules.reward(run, {}).sp == 0, "NaN time rejected in real AS2");
        run.elapsedMs = 0;
        check(BookRunRules.reward(run, {}).sp == 0, "zero time rejected");
        run.elapsedMs = 86400000;
        check(BookRunRules.reward(run, {}).sp == 0, "stale day-long result rejected");
        check(codec.stringifySafe(BookRunRules.stages(Number.NaN, 0)) == codec.stringifySafe(BookRunRules.stages(1, 0)), "invalid seed normalized");
        testCf6();
        trace("BookRunRulesTest Tests Passed: " + passed);
        trace("BookRunRulesTest Tests Failed: " + failed);
    }
}
