import org.flashNight.arki.scene.Cf6SoldierRoster;
import org.flashNight.arki.scene.Cf6FixedRosterFixture;
import org.flashNight.gesh.object.ObjectUtil;

/** Real AVM1 materialization of all reviewed fixed slots, without spawning actors or writing saves. */
class org.flashNight.arki.scene.Cf6SoldierRosterTest {
    private static var passed:Number;
    private static var failed:Number;
    private static function check(ok:Boolean,label:String):Void {
        if(ok)passed++;else{failed++;trace("[FAIL] Cf6SoldierRosterTest: "+label);}
    }
    private static function rejects(source:Object,ordinal:Number,label:String):Void {
        var rejected:Boolean=false;
        try {Cf6SoldierRoster.prepare(source,ordinal,{});}catch(error){rejected=true;}
        check(rejected,label);
    }
    public static function runAllTests():Void {
        passed=0;failed=0;
        var groups:Array=Cf6FixedRosterFixture.groups(),seen:Object={},count:Number=0;
        var falseMode:Object,trueMode:Object;
        for(var i:Number=0;i<groups.length;i++){
            var group:Object=groups[i],slots:Array=group.Parameters.cf6FixedSlots;
            check(group.Quantity==slots.length,"group quantity "+i);
            for(var ordinal:Number=0;ordinal<slots.length;ordinal++){
                var initial:Object={cf6EliteQuota:"stale",cf6FixedSlots:slots};
                var position:Object=Cf6SoldierRoster.prepare(group,ordinal,initial);
                var expected:Object=slots[ordinal].parameters,id:String=initial.cf6UnitIdentity;
                check(id===expected.cf6UnitIdentity && seen[id]!==true,"unique exact identity "+i+"/"+ordinal);
                seen[id]=true;count++;
                check(initial.cf6SourceSeat===expected.cf6SourceSeat && initial.cf6SourceOrdinal===expected.cf6SourceOrdinal,
                    "authored provenance remains stable "+id);
                check(initial.特种兵初始阶段===expected.特种兵初始阶段 && initial.称号===expected.称号,
                    "phase and authored title "+id);
                check(position.x===slots[ordinal].x && position.y===slots[ordinal].y && initial.cf6BirthX===position.x,
                    "fixed geometry "+id);
                check(initial.cf6FixedSlots===undefined && initial.cf6EliteQuota===undefined
                    && typeof initial.cf6BirthIdentity=="object","old random overrides removed and fresh identity allocated "+id);
                if(id=="CF6-M-XX")falseMode=initial;
                if(id=="CF6-M-V")trueMode=initial;
            }
        }
        check(count==158 && groups.length==101,"all158 people including three relocated support slots materialized");
        check(falseMode.cf6G1111FixedMode===false && falseMode.长枪.value.isRocketMode===false,"false is not treated as absent");
        check(trueMode.cf6G1111FixedMode===true && trueMode.长枪.value.isRocketMode===true,"rocket Boolean is preserved");
        falseMode.长枪.value.shot=7;falseMode.长枪.value.mods.push("fixture");
        check(trueMode.长枪.value.shot==0 && trueMode.长枪.value.mods.length==0,"G1111 actors do not share mutable equipment");
        var original:Object=groups[0],a:Object={},b:Object={};
        Cf6SoldierRoster.prepare(original,0,a);Cf6SoldierRoster.prepare(original,0,b);
        check(a.cf6BirthIdentity!==b.cf6BirthIdentity,"each attach attempt has a fresh plain identity token");
        a.称号="changed";check(original.Parameters.cf6FixedSlots[0].parameters.称号!==a.称号,"runtime changes do not rewrite source data");
        rejects(original,-1,"negative ordinal rejected");
        rejects(original,NaN,"NaN ordinal rejected");
        rejects(original,original.Quantity,"out-of-range ordinal rejected");
        var changed:Object=ObjectUtil.clone(original);changed.Quantity++;
        rejects(changed,0,"source quantity mismatch rejected");
        changed=ObjectUtil.clone(original);changed.Parameters.cf6FixedSlots[0].x=1/0;
        rejects(changed,0,"nonfinite position rejected");
        changed=ObjectUtil.clone(original);changed.Parameters.cf6FixedSlots[0].parameters.cf6RosterVersion="another-version";
        rejects(changed,0,"mixed roster versions rejected");
        changed=ObjectUtil.clone(original);changed.Parameters.cf6FixedSlots[0].parameters.cf6UnitIdentity="";
        rejects(changed,0,"empty identity rejected");
        changed=ObjectUtil.clone(original);changed.Parameters.cf6FixedSlots[0].parameters.cf6G1111FixedMode="false";
        rejects(changed,0,"string false cannot opt into fixed G1111");
        trace("Cf6SoldierRosterTest: "+passed+" passed, "+failed+" failed; "+count+" materialized, "+groups.length+" groups");
        if(failed>0)trace("[TEST_FAIL] Cf6SoldierRosterTest suite failed");
    }
}
