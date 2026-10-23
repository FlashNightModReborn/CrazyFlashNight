import org.flashNight.arki.unit.PlayerStatRefreshCoordinator;
import org.flashNight.arki.unit.Action.Regeneration.HealApplier;
/** 状态机真实 AS2 类 + 注入 adapter；不冒充生产 adapter/游戏旅程。 */
class org.flashNight.arki.unit.PlayerStatRefreshCoordinatorTest {
    private static var passed:Number;
    private static var failed:Number;
    public static function runAllTests():Void {
        passed=failed=0;
        try { testPendingBatchAndReentry();testIdentityAndReset();testResourceRecovery();testEquipmentTickets(); }
        catch(error) { check(false,"unexpected: "+error); }
        trace("PlayerStatRefreshCoordinatorTest Tests Passed: "+passed);
        trace("PlayerStatRefreshCoordinatorTest Tests Failed: "+failed);
    }
    private static function check(ok:Boolean,label:String):Void {
        if(ok) {passed++;trace("[PASS] Coordinator: "+label);} else {failed++;trace("[FAIL] Coordinator: "+label);}
    }
    private static function fixture():Object {
        var f:Object={c:new PlayerStatRefreshCoordinator(),world:{},body:{},actor:{hp:900,hp满血值:1000,mp:100,mp满血值:200},
            computes:0,commits:0,settles:0,derives:0,rebuilds:0,newMax:800,newMpMax:180,blocked:false,owner:{}};
        f.actor.__playerStatBody=f.body;f.token=f.c.resetContext({},"isolated-coordinator",{});
        f.c.setAdapter(adapterFor(f));f.c.bindHero(f.actor,f.world,f.body,f.token);f.c.notifyReady(f.actor,f.world,f.body,f.token,null);
        return f;
    }
    private static function adapterFor(f:Object):Object {
        return {
            isCurrent:function(s:Object):Boolean {return true;},
            compute:function(s:Object,mask:Number):Object {
                f.computes++;
                if(f.reenter || f.forever) { if(!f.forever) f.reenter=false;f.c.invalidate(f.reenterMask || 1,"skills",f.token); }
                if(f.replaceAt=="compute") f.actor.__playerStatBody={};
                if(f.resetAt=="compute") f.c.resetContext({},"new",{});
                if(f.invalid) throw new Error("invalid_input");
                return {max:f.newMax,mpMax:f.newMpMax};
            },
            captureResources:function(s:Object,r:Object):Object {return {hp:f.actor.hp,oldMax:f.actor.hp满血值,mp:f.actor.mp};},
            commit:function(s:Object,r:Object,resources:Object):Void {
                f.commits++;f.actor.hp满血值=r.max;f.actor.mp满血值=r.mpMax;
                if(f.replaceAt=="commit") f.actor.__playerStatBody={};
                if(f.failCommit) {f.failCommit=false;throw new Error("after_max_write");}
            },
            settleResources:function(s:Object,r:Object,resources:Object):Void {
                f.settles++;f.actor.hp=HealApplier.settleHpAfterMaxChange(resources.hp,resources.oldMax,r.max);
                f.actor.mp=HealApplier.settleMpAfterMaxChange(resources.mp,r.mpMax);
            },
            derive:function(s:Object,r:Object):Void {
                f.derives++;
                if(f.revokeAt=="derived") f.c.revokeReady(f.actor,f.body);
                if(f.failDerived) {f.failDerived=false;throw new Error("derived_fault");}
            },
            verify:function(s:Object,r:Object):Boolean {return f.actor.hp满血值==r.max;},
            block:function(s:Object,stage:String,reason:String):Void {f.blocked=true;},
            unblock:function(s:Object):Void {f.blocked=false;},
            verifyEquipmentInput:function(ticket:Object):Boolean {return ticket.proof.generation==1 && ticket.proof.revision==2;},
            verifyEquipment:function(ticket:Object):Boolean {return !f.badEquipment;},
            rebuild:function(ticket:Object):Void {
                f.rebuilds++;
                var next:Object=f.c.startEquipmentTransition(ticket,f.actor);
                if(f.failEquipment) throw new Error("equipment_started_fault");
                if(f.badBody) {f.actor.__playerStatBody={};return;}
                f.c.notifyReady(f.actor,f.world,next,f.token,ticket);
            },
            abortEquipment:function(ticket:Object):Void {f.blocked=true;}
        };
    }
    private static function testPendingBatchAndReentry():Void {
        var c:PlayerStatRefreshCoordinator=new PlayerStatRefreshCoordinator();var tok:Object=c.contextToken();
        c.invalidate(1,"skills",tok);
        check(c.flush("test").reason=="pending_actor","no actor retains work");
        var f:Object=fixture(); f.c.revokeReady(f.actor,f.body);
        check(f.c.flush("test").reason=="pending_ready" && f.commits==0,"unready actor receives zero writes");
        f.c.notifyReady(f.actor,f.world,f.body,f.token,null);
        var batch:Object=f.c.beginBatch(f.token);f.c.invalidate(1,"gym",f.token);f.c.invalidate(2,"skills",f.token);
        check(f.c.flush("test").reason=="batch_open" && f.commits==0,"open batch is not a consistency receipt");
        check(f.c.endBatch(batch,"test").status=="applied" && f.commits==1,"mixed successful batch projects once");
        check(f.c.flush("test").status=="unchanged" && f.commits==1,"unchanged barrier is free of writes");
        f.c.invalidate(1,"skills",f.token);f.reenter=true;
        check(f.c.flush("test").status=="applied" && f.commits==3,"same-bit reentry survives captured revision completion");
        f.c.invalidate(1,"skills",f.token);f.reenter=true;f.reenterMask=2;
        check(f.c.flush("test").status=="applied" && f.commits==5,"different-bit reentry converges without loss");
        f.c.invalidate(1,"skills",f.token);f.forever=true;
        check(f.c.flush("test").reason=="convergence_limit" && f.c.diagnostics().dirtyMask!=0,"continuous reentry is bounded and stays dirty");
    }
    private static function testIdentityAndReset():Void {
        var f:Object=fixture();f.replaceAt="compute";
        check(f.c.flush("test").status=="failed" && f.commits==0,"body replacement after compute rejects commit");
        f=fixture();f.replaceAt="commit";
        check(f.c.flush("test").status=="failed" && f.settles==0,"body replacement after commit rejects resources and receipt");
        f=fixture();f.revokeAt="derived";
        check(f.c.flush("test").status=="failed" && f.c.diagnostics().dirtyMask!=0,"ready revocation before publish rejects receipt");
        f=fixture();f.resetAt="compute";
        check(f.c.flush("test").status=="failed" && f.commits==0,"context reset during compute detaches old actor immediately");
        var hp:Number=f.actor.hp;
        check(f.c.flush("test").reason=="pending_actor" && f.actor.hp==hp,"reset without rebind cannot write old actor");
        check(f.c.invalidate(1,"skills",f.token).reason=="stale_context","late old-context invalidation is rejected");
    }
    private static function testResourceRecovery():Void {
        var f:Object=fixture();f.failCommit=true;
        check(f.c.flush("test").status=="failed" && f.actor.hp满血值==800 && f.actor.hp==900 && f.blocked,"partial max write keeps checkpoint and blocks actor");
        check(f.c.flush("test").status=="applied" && f.actor.hp==800 && !f.blocked,"900/1000 recovery uses old valid 1000 rather than half-written 800");
        f=fixture();f.actor.hp=1300;f.failCommit=true;f.c.flush("test");
        check(f.c.flush("test").status=="applied" && f.actor.hp==1200,"legitimate overflow recovery remains 1200");
        f=fixture();f.failDerived=true;f.c.flush("test");var settles:Number=f.settles;
        check(f.c.flush("test").status=="applied" && f.settles==settles,"derived-only recovery does not replay resource settlement");
        f=fixture();f.invalid=true;
        check(f.c.flush("test").status=="failed" && f.commits==0 && f.actor.hp满血值==1000,"invalid compute is zero live writes");
    }
    private static function testEquipmentTickets():Void {
        var f:Object=fixture();f.c.invalidate(7,"equipment",f.token);
        var ticket:Object=f.c.prepareEquipmentTransition({generation:1,revision:2},f.owner);
        check(f.c.flush("test").status=="applied" && f.rebuilds==1 && f.computes==0
            && f.actor.__playerStatBody===ticket.targetBody,"planned B1 performs one full init and absorbs numeric work");
        f=fixture();f.c.invalidate(7,"equipment",f.token);f.badBody=true;
        ticket=f.c.prepareEquipmentTransition({generation:1,revision:2},f.owner);
        check(f.c.flush("test").status=="failed" && f.rebuilds==1,"unplanned B2 cannot be accepted after full init");
        check(f.c.flush("retry").reason=="equipment_owner_recovery_required" && f.rebuilds==1,"ordinary retry does not repeat a started lifecycle");
        check(!f.c.abortEquipmentTransition(ticket,{}),"another owner cannot abort recovery");
        check(f.c.abortEquipmentTransition(ticket,f.owner) && f.c.flush("test").status!="applied","original owner can explicitly abort while actor remains blocked");
        f=fixture();f.c.invalidate(4,"equipment",f.token);f.failEquipment=true;
        ticket=f.c.prepareEquipmentTransition({generation:1,revision:2},f.owner);
        check(f.c.flush("test").status=="failed" && f.c.flush("retry").reason=="equipment_owner_recovery_required" && f.rebuilds==1,"started exception retains owner recovery and never auto-rebuilds");
    }
}
