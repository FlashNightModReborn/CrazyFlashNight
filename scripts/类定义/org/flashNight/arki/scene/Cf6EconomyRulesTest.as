import org.flashNight.arki.scene.Cf6EconomyRules;
import org.flashNight.arki.scene.BookRunRules;
import org.flashNight.arki.scene.BookDefinition;
import org.flashNight.gesh.object.PersistedSnapshot;

/** Pure plan tests: no player inventory, saves, gameworld or external rewards are written. */
class org.flashNight.arki.scene.Cf6EconomyRulesTest {
    private static var passed:Number;
    private static var failed:Number;
    private static function check(value:Boolean,label:String):Void {
        if (value) passed++; else {failed++;trace("[FAIL] Cf6EconomyRules: "+label);}
    }
    /** Object key enumeration changes when PersistedSnapshot inserts a reversed AVM1 for-in order. */
    private static function sameData(left, right, depth:Number):Boolean {
        if (depth > 32 || typeof left !== typeof right) return false;
        if (left == null || right == null || typeof left != "object") return left === right;
        if ((left instanceof Array) != (right instanceof Array)) return false;
        if (left instanceof Array && left.length !== right.length) return false;
        for (var key:String in left) if (left.hasOwnProperty(key)) {
            if (!right.hasOwnProperty(key) || !sameData(left[key],right[key],depth+1)) return false;
        }
        for (key in right) if (right.hasOwnProperty(key) && !left.hasOwnProperty(key)) return false;
        return true;
    }
    private static function option(name:String):Object { return {weapon:name,ammo:"突击步枪通用弹药",ammoCount:3}; }
    private static function stage(id:String):Object {
        return {id:id,title:"TEST ONLY",background:"cf6/CF6_"+id+"_BG.swf",dialogue:[],
            stage:{BasicInformation:{PlayerX:200,PlayerY:300},Wave:{SubWave:[{EnemyGroup:{Enemy:[]}}]},Pickups:{Pickup:[]}}};
    }
    private static function elite(quota:String):Object {
        return {Type:"兵种467",Level:60,Quantity:1,Parameters:{cf6EliteQuota:quota,长枪:"OLD#11",掉落物:[{名字:"OLD",总数:1}]}};
    }
    private static function fixture():Object {
        var result:Object={schema:"playable-book.v1",id:"cf6-sting",routeId:"historical",stageName:"书中历险-毒刺行动",title:"TEST ONLY",
            startingMoney:0,startingSkillPoints:0,externalRewards:0,
            actor:{name:"Andy",gender:"男",height:175,face:"face",hair:"hair",level:60,experience:157526193,
                equipment:[{slot:"上装装备",name:"白色中山上装",enhancement:11}],skills:[{name:"迅斩",level:10}]},
            maps:[stage("A04"),stage("A09"),stage("A13")],
            economy:{randomWeapons:[{mapId:"A04",choices:[option("DD MK18战术版"),option("M60E3")]}],
                eliteWeapons:[{mapId:"A09",quota:"E1",choices:[option("SAI GRY 幽灵")]},
                    {mapId:"A13",quota:"E2",choices:[option("TTI Gen 12"),option("T181C")]}],choices:[]}};
        result.maps[1].stage.Wave.SubWave[0].EnemyGroup.Enemy.push(elite("E1"));
        result.maps[2].stage.Wave.SubWave[0].EnemyGroup.Enemy.push(elite("E2"));
        return result;
    }
    private static function testRunIdentity():Void {
        var identity:Object={bookId:"cf6-sting",routeId:"historical",slot:"bookrun.identity",seed:17,startedAt:100,planSeed:19,outcome:"active"};
        var current:Object=PersistedSnapshot.clone(identity);
        check(BookRunRules.sameCf6Run(identity,current),"detached commit/rollback copy is the same active run");
        current.seed=18;check(!BookRunRules.sameCf6Run(identity,current),"same slot new seed is a different run");
        current=PersistedSnapshot.clone(identity);current.startedAt=101;
        check(!BookRunRules.sameCf6Run(identity,current),"same slot new start time is a different run");
        current=PersistedSnapshot.clone(identity);current.planSeed=20;
        check(!BookRunRules.sameCf6Run(identity,current),"changed debug plan is not the prepared plan");
        current=PersistedSnapshot.clone(identity);current.routeId="plan61";
        check(!BookRunRules.sameCf6Run(identity,current),"another route cannot inherit the plan");
        current=PersistedSnapshot.clone(identity);current.outcome="retreat";
        check(!BookRunRules.sameCf6Run(identity,current),"terminal outcome cannot resume an active plan");
        var invalid:Object=PersistedSnapshot.clone(identity);invalid.seed=Number.NaN;
        check(!BookRunRules.sameCf6Run(invalid,invalid),"NaN identity rejected despite AVM1 NaN equality");
        invalid=PersistedSnapshot.clone(identity);delete invalid.startedAt;
        check(!BookRunRules.sameCf6Run(invalid,invalid),"missing run timestamp cannot establish identity");
        var service:Object=org.flashNight.arki.scene.BookRunService;
        var saveManager:Object=org.flashNight.neur.Server.SaveManager.getInstance();
        var oldOwner:Object=service._cf6PlanOwner,oldPlans:Object=service._cf6BossPlans,oldEnding:Object=service._ending;
        var oldExt:Object=_root._saveExt,oldSlot=_root.savePath,oldSave:Object=_root.存档系统;
        var oldPending:Function=saveManager.hasRewardCommitPending;
        try {
            _root.savePath=identity.slot;
            service._cf6PlanOwner=PersistedSnapshot.clone(identity);service._cf6BossPlans={};
            var marker:Object={testOnly:true};service._cf6BossPlans["2"]=marker;
            _root._saveExt={bookRun:PersistedSnapshot.clone(identity)};
            check(service.cf6BossPlan(_root._saveExt.bookRun,2)===marker,"prepared boss plan survives reward snapshot replacement");
            _root._saveExt.bookRun.seed=18;
            check(service.cf6BossPlan(_root._saveExt.bookRun,2)==null,"old boss plan refuses a new seed in same slot");
            _root.savePath="other";_root._saveExt.bookRun=PersistedSnapshot.clone(identity);
            check(service.cf6BossPlan(_root._saveExt.bookRun,2)==null,"plan lookup still checks current physical slot");
            _root.savePath=identity.slot;_root.存档系统={markDirty:function():Void {}};
            saveManager.hasRewardCommitPending=function():Boolean {return false;};
            service._ending={slot:identity.slot,outcome:"victory",elapsedMs:1234,run:identity,runIdentity:PersistedSnapshot.clone(identity)};
            service.persistOutcome();
            check(_root._saveExt.bookRun.outcome=="victory" && _root._saveExt.bookRun.elapsedMs==1234 && service._ending==null,
                "pending CF6 terminal outcome reconciles into same-run cloned snapshot");
            _root._saveExt.bookRun=PersistedSnapshot.clone(identity);_root._saveExt.bookRun.startedAt=101;
            service._ending={slot:identity.slot,outcome:"victory",elapsedMs:1234,run:identity,runIdentity:PersistedSnapshot.clone(identity)};
            service.persistOutcome();
            check(_root._saveExt.bookRun.outcome=="active" && service._ending==null,"pending old terminal outcome cannot write a replacement run");
        } finally {
            service._cf6PlanOwner=oldOwner;service._cf6BossPlans=oldPlans;service._ending=oldEnding;
            _root._saveExt=oldExt;_root.savePath=oldSlot;_root.存档系统=oldSave;saveManager.hasRewardCommitPending=oldPending;
        }
    }
    public static function runAllTests():Void {
        passed=0;failed=0;
        var codec:LiteJSON=new LiteJSON();
        var config:Object=fixture();
        var before:String=codec.stringifySafe(config);
        check(Cf6EconomyRules.valid(config),"finite authored economy validates");
        var instructorConfig:Object=fixture();
        instructorConfig.maps[2].stage.Wave.SubWave[0].EnemyGroup.Enemy[0].Type="兵种481";
        check(!Cf6EconomyRules.valid(instructorConfig),"historical quota cannot silently switch soldier family");
        instructorConfig.routeId="type61";
        check(Cf6EconomyRules.valid(instructorConfig),"Type61 finite quota accepts a single instructor carrier");
        instructorConfig.maps[2].stage.Wave.SubWave[0].EnemyGroup.Enemy[0].Quantity=2;
        check(!Cf6EconomyRules.valid(instructorConfig),"instructor carrier cannot multiply the finite weapon quota");
        var first:Array=Cf6EconomyRules.maps(config,1729),same:Array=Cf6EconomyRules.maps(config,1729);
        check(codec.stringifySafe(first)==codec.stringifySafe(same),"seed reproduces complete route");
        check(codec.stringifySafe(config)==before,"selection never mutates cached config");
        var picks:Array=first[0].stage.Pickups.Pickup;
        check(picks.length==2 && picks[0].Value==1 && picks[1].Value==3,"one unenhanced gun and exact ammo quantity");
        check(picks[0].x==200 && picks[1].x==200 && picks[0].y==300,"supplies stay at the verified world spawn without unsafe offsets");
        var carrier:Object=first[2].stage.Wave.SubWave[0].EnemyGroup.Enemy[0];
        check(carrier.Parameters.长枪==carrier.Parameters.掉落物[0].名字+"#1","elite equips exactly the dropped model and enhancement");
        check(carrier.Parameters.不掉装备===true && carrier.Parameters.掉落物.length==2,"default equipment roll suppressed and old source replaced");
        check(carrier.Parameters.掉落物[0].总数==1 && carrier.Parameters.掉落物[1].总数==3,"elite finite one-gun three-ammo quota");
        first[2].stage.Wave.SubWave[0].EnemyGroup.Enemy[0].Parameters.掉落物[0].总数=0;
        check(same[2].stage.Wave.SubWave[0].EnemyGroup.Enemy[0].Parameters.掉落物[0].总数==1,"drop consumption cannot deplete another plan");
        var seen:Object={},eliteSeen:Object={};
        for (var i:Number=1;i<65;i++) {
            var run:Array=Cf6EconomyRules.maps(config,i*23456789);
            seen[run[0].stage.Pickups.Pickup[0].Name]=true;
            eliteSeen[run[2].stage.Wave.SubWave[0].EnemyGroup.Enemy[0].Parameters.长枪]=true;
        }
        check(seen["DD MK18战术版"]===true && seen["M60E3"]===true,"different seeds reach both random candidates in AVM1");
        check(eliteSeen["TTI Gen 12#1"]===true && eliteSeen["T181C#1"]===true,"different seeds reach both elite candidates in AVM1");
        check(codec.stringifySafe(Cf6EconomyRules.maps(config,Number.NaN))==codec.stringifySafe(Cf6EconomyRules.maps(config,1)),"NaN seed normalizes in AVM1");
        var broken:Object=fixture();broken.economy.randomWeapons[0].choices.pop();
        check(!Cf6EconomyRules.valid(broken),"singleton is not a random pool");
        broken=fixture();broken.economy.eliteWeapons[1].choices.pop();
        check(!Cf6EconomyRules.valid(broken),"E2 requires actual alternatives");
        broken=fixture();broken.economy.randomWeapons[0].choices.push(option("SAI GRY 幽灵"));
        check(!Cf6EconomyRules.valid(broken),"random cannot duplicate elite gun source");
        broken=fixture();broken.maps[0].stage.Pickups.Pickup.push({Name:"SAI GRY 幽灵",Value:1});
        check(!Cf6EconomyRules.valid(broken),"fixed pickup cannot duplicate elite gun source");
        broken=fixture();broken.maps[1].stage.Wave.SubWave[0].EnemyGroup.Enemy[0].Quantity=2;
        check(!Cf6EconomyRules.valid(broken),"carrier quantity cannot multiply quota");
        broken=fixture();broken.maps[1].stage.Wave.SubWave[0].EnemyGroup.Enemy.push(elite("E1"));
        check(!Cf6EconomyRules.valid(broken),"duplicate carrier rejected");
        broken=fixture();broken.economy.eliteWeapons.pop();
        check(!Cf6EconomyRules.valid(broken),"marker without configured quota rejected");
        broken=fixture();broken.economy.randomWeapons[0].choices[0].ammoCount=Number.NaN;
        check(!Cf6EconomyRules.valid(broken),"NaN ammo quantity rejected in AVM1");
        broken=fixture();broken.maps[0].stage.BasicInformation.PlayerX=Number.NaN;
        check(!Cf6EconomyRules.valid(broken),"nonfinite supply anchor rejected in AVM1");
        broken=fixture();broken.economy.choices.push({mapId:"A04",poolId:"not.registered",itemName:"TEST ONLY"});
        check(!Cf6EconomyRules.valid(broken),"unknown choice pool fails closed");
        var support:Object=fixture();
        support.maps[1].bossEncounter={groups:[{enemies:[support.maps[1].stage.Wave.SubWave[0].EnemyGroup.Enemy.pop()]}]};
        check(Cf6EconomyRules.valid(support),"finite reinforcement carrier supported without author InstanceName");
        var supportPlan:Array=Cf6EconomyRules.maps(support,1729);
        check(supportPlan[1].bossEncounter.groups[0].enemies[0].Parameters.长枪=="SAI GRY 幽灵#1","reinforcement plan receives same-model equipment and drop");
        check(support.maps[1].bossEncounter.groups[0].enemies[0].Parameters.长枪=="OLD#11","support source remains immutable");
        var shared:Object=fixture();
        shared.economy.randomWeapons.push({mapId:"A13",choices:org.flashNight.gesh.object.PersistedSnapshot.clone(shared.economy.randomWeapons[0].choices)});
        check(Cf6EconomyRules.valid(shared),"ordinary random maps may share candidates while keeping each pool unique");
        var dual:Object=fixture();
        dual.economy.randomWeapons[0].choices=[{weapon:"极品UZI战术版",ammo:"冲锋枪通用弹药",ammoCount:6,weaponCount:2},
            {weapon:"MMP80",ammo:"冲锋枪通用弹药",ammoCount:6,weaponCount:2}];
        check(Cf6EconomyRules.valid(dual),"finite dual short-gun candidates are admitted");
        var dualBefore:String=codec.stringifySafe(dual),dualPlan:Array=Cf6EconomyRules.maps(dual,1729);
        var dualPicks:Array=dualPlan[0].stage.Pickups.Pickup;
        check(dualPicks.length==3&&dualPicks[0].Name==dualPicks[1].Name&&dualPicks[0].Value===1&&dualPicks[1].Value===1
            &&dualPicks[0]!==dualPicks[1],"dual short guns become two independent enhancement-one pickups");
        check(dualPicks[2].Name=="冲锋枪通用弹药"&&dualPicks[2].Value===6,"dual pickups retain their total matching ammunition");
        check(codec.stringifySafe(Cf6EconomyRules.maps(dual,1729))==codec.stringifySafe(dualPlan)
            &&codec.stringifySafe(dual)==dualBefore,"dual selection stays seeded and leaves source unchanged");
        dual.economy.randomWeapons[0].choices[0].weaponCount=true;
        check(!Cf6EconomyRules.valid(dual),"boolean weapon count is not a second equipment instance");
        dual.economy.randomWeapons[0].choices[0].weaponCount=3;
        check(!Cf6EconomyRules.valid(dual),"weapon instance count stays bounded to two");
        dual=fixture();dual.economy.eliteWeapons[0].choices[0].weaponCount=2;
        check(!Cf6EconomyRules.valid(dual),"elite long-gun carrier cannot deliver dual short-gun count");
        var legacy:Object=fixture();delete legacy.economy;
        var legacyCopy:Array=Cf6EconomyRules.maps(legacy,1);
        check(Cf6EconomyRules.valid(legacy) && sameData(legacyCopy,legacy.maps,0),"no economy preserves every authored key, type, array index and value");
        check(legacyCopy!==legacy.maps && legacyCopy[1].stage.Wave.SubWave!==legacy.maps[1].stage.Wave.SubWave,
            "no-economy compatibility still detaches nested stage arrays");
        legacyCopy[1].stage.Wave.SubWave[0].EnemyGroup.Enemy[0].Level=59;
        check(legacy.maps[1].stage.Wave.SubWave[0].EnemyGroup.Enemy[0].Level===60 && !sameData(legacyCopy,legacy.maps,0),
            "deep semantic oracle detects real edits while copied legacy plans cannot mutate source");
        var definition:Object=org.flashNight.arki.scene.BookDefinition;
        var saved:Object=definition._cf6;
        try {
            definition._cf6=config;
            var complete:Array=BookRunRules.stages(1729,0,"cf6-sting");
            var jump:Array=BookRunRules.stages(1729,2,"cf6-sting");
            check(codec.stringifySafe(complete[2])==codec.stringifySafe(jump[0]),"debug jump consumes earlier random draws before slicing");
            check(complete[0].Pickups.Pickup.length==2,"BookRunRules forwards selected native pickups");
            definition._cf6=support;
            var bosses:Array=BookRunRules.stages(1729,0,"cf6-sting");
            check(bosses[1].BasicInformation.Cf6Boss.groups[0].enemies[0].Parameters.长枪=="SAI GRY 幽灵#1","generated boss handoff carries selected loadout");
        } finally {definition._cf6=saved;}
        check(codec.stringifySafe(config)==before,"whole suite leaves authored inputs intact");
        testRunIdentity();
        trace("Cf6EconomyRulesTest Tests Passed: "+passed);
        trace("Cf6EconomyRulesTest Tests Failed: "+failed);
    }
}
