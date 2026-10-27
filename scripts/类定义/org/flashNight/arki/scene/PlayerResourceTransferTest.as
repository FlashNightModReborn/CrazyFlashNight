import org.flashNight.arki.scene.PlayerResourceTransfer;
import org.flashNight.arki.unit.Action.Regeneration.ResourceNumber;
import org.flashNight.arki.unit.Action.Regeneration.HealApplier;
/** 原生 AVM1 验证真实生产类，不把 Python/JS 模型计为运行时证据。 */
class org.flashNight.arki.scene.PlayerResourceTransferTest {
    private static var passed:Number;
    private static var failed:Number;
    private static function check(ok:Boolean,label:String):Void {
        if(ok) passed++;else {failed++;trace("FAIL ResourceTransfer "+label);}
    }
    private static function context():Object {return {context:{},run:{},world:{},actor:{},slot:"fixture",name:"hero",kind:"player",stage:0};}
    private static function next(i:Object):Object {return {context:i.context,run:i.run,world:{},actor:{},slot:i.slot,name:i.name,kind:i.kind,stage:i.stage+1};}
    private static function actor(i:Object,hp:Number,mp:Number,hmax:Number,mmax:Number):Object {
        return {_name:"hero",hp:hp,mp:mp,hp满血值:hmax,mp满血值:mmax,__playerSceneActorIdentity:i.actor};
    }
    private static function roundtrip(hp:Number,mp:Number,oldHp:Number,oldMp:Number,newHp:Number,newMp:Number,
            expectedHp:Number,expectedMp:Number,caps:Object,label:String):Void {
        var t:PlayerResourceTransfer=new PlayerResourceTransfer();var i:Object=context();var ticket:Object={frame:"next"};
        check(t.capture(ticket,i,{hp:hp,mp:mp,hpMax:oldHp,mpMax:oldMp},1),label+" capture");
        check(t.bind(next(i))==null,label+" no_precommit");
        check(t.commit(ticket),label+" commit");
        var d:Object=next(i);var token:Object=t.bind(d);var unit:Object=actor(d,newHp,newMp,newHp,newMp);
        check(t.consume(token,unit,d,caps),label+" consume");
        check(unit.hp===expectedHp && unit.mp===expectedMp,label+" pair");
        check(!t.consume(token,unit,d,caps) && unit.hp===expectedHp && unit.mp===expectedMp,label+" one_shot");
    }
    public static function runAllTests():Void {
        passed=0;failed=0;
        roundtrip(2700,0,3000,1000,3000,1000,2700,0,null,"ordinary_zero");
        roundtrip(3600,1800,3000,1000,3000,1000,3600,1800,null,"same_overflow");
        roundtrip(2700,500,3000,1000,4000,2000,2700,500,null,"grow_absolute");
        roundtrip(2700,500,3000,1000,2000,400,2000,400,null,"shrink_ordinary");
        roundtrip(3600,1800,3000,1000,2000,400,3600,1800,null,"shrink_no_cap");
        roundtrip(3600,1800,3000,1000,2000,400,2500,900,{hp:2500,mp:900},"shrink_cap");
        roundtrip(3600,1800,3000,1000,2000,400,3600,1800,{hp:NaN,mp:"900"},"bad_cap_preserve");
        var bad:Array=[undefined,null,NaN,Infinity,-Infinity,"5",true,-1];
        for(var n:Number=0;n<bad.length;n++) {
            var t:PlayerResourceTransfer=new PlayerResourceTransfer();var i:Object=context();var ticket:Object={frame:"next"};
            check(!t.capture(ticket,i,{hp:500,mp:bad[n],hpMax:1000,mpMax:500},1),"bad_sample_mp_"+n);
            check(!t.capture(ticket,i,{hp:bad[n],mp:0,hpMax:1000,mpMax:500},1),"bad_sample_hp_"+n);
            t=new PlayerResourceTransfer();t.capture(ticket,i,{hp:500,mp:0,hpMax:1000,mpMax:500},1);t.commit(ticket);
            var d:Object=next(i);var token:Object=t.bind(d);var unit:Object=actor(d,1000,500,1000,500);unit.mp=bad[n];
            check(!t.consume(token,unit,d,null) && unit.hp===1000,"bad_destination_atomic_"+n);
            var heal:Object={hp:100,mp:60};
            check(HealApplier.applyMpCapped(heal,bad[n],100)===0 && heal.mp===60,"heal_amount_"+n);
            heal.mp=bad[n];
            check(HealApplier.applyMpCapped(heal,5,100)===0,"heal_balance_"+n);
            heal.mp=60;
            check(!ResourceNumber.payMp(heal,bad[n]) && heal.mp===60,"bad_cost_"+n);
        }
        var ti:PlayerResourceTransfer=new PlayerResourceTransfer();var src:Object=context();var tk:Object={frame:"next"};
        var sample:Object={hp:700,mp:0,hpMax:1000,mpMax:500};
        ti.capture(tk,src,sample,1);sample.hp=900;sample.mp=400;
        check(!ti.commit({frame:"next"}),"wrong_cleanup_owner");
        check(!ti.capture({frame:"next"},context(),sample,1),"duplicate_does_not_replace");
        check(ti.commit(tk),"original_owner_survives_duplicate");
        var dst:Object=next(src);var tok:Object=ti.bind(dst);var u:Object=actor(dst,1000,500,1000,500);
        check(!ti.consume({},u,dst,null) && u.hp===1000 && u.mp===500,"copied_token_rejected");
        check(ti.consume(tok,u,dst,null) && u.hp===700 && u.mp===0,"private_sample_not_mutated");
        var keys:Array=["context","run","world","actor","slot","name","kind","stage"];
        for(var k:Number=0;k<keys.length;k++) {
            ti=new PlayerResourceTransfer();src=context();tk={frame:"next"};
            ti.capture(tk,src,{hp:700,mp:0,hpMax:1000,mpMax:500},1);ti.commit(tk);dst=next(src);tok=ti.bind(dst);
            u=actor(dst,1000,500,1000,500);dst[keys[k]]={};
            check(!ti.consume(tok,u,dst,null) && u.hp===1000 && u.mp===500,"stale_"+keys[k]);
        }
        ti=new PlayerResourceTransfer();src=context();src.kind="lee";tk={frame:"next"};
        check(ti.capture(tk,src,{hp:333,mp:0,hpMax:500,mpMax:0},1),"lee_zero_max_capture");ti.commit(tk);
        dst=next(src);tok=ti.bind(dst);u=actor(dst,500,0,500,0);
        check(ti.consume(tok,u,dst,null) && u.hp===333 && u.mp===0,"lee_zero_max_consume");
        ti=new PlayerResourceTransfer();src=context();tk={frame:"next"};ti.capture(tk,src,{hp:333,mp:0,hpMax:500,mpMax:500},1);
        ti.abort(tk,"teardown_failed");check(!ti.commit(tk) && ti.bind(next(src))==null,"failed_destroy_not_consumable");
        var healed:Object={hp:100,mp:60};
        check(HealApplier.applyMpCapped(healed,5,100)===5 && healed.mp===65,"finite_heal");
        check(ResourceNumber.payMp(healed,0) && healed.mp===65,"zero_cost");
        check(!ResourceNumber.payMp(healed,66) && healed.mp===65,"insufficient_no_write");
        // 真 MovieClip 同路径替换：旧 MC 引用可重指，独立 actor token 不会复用。
        var parent:MovieClip=_root.createEmptyMovieClip("resourceIdentityFixture",_root.getNextHighestDepth());
        var old:MovieClip=parent.createEmptyMovieClip("hero",1);old.__playerSceneActorIdentity={};
        var oldId:Object=old.__playerSceneActorIdentity;old.removeMovieClip();
        var fresh:MovieClip=parent.createEmptyMovieClip("hero",1);fresh.__playerSceneActorIdentity={};
        trace("ResourceTransfer NativeRetarget: "+(old===fresh));
        check(oldId!==fresh.__playerSceneActorIdentity,"native_actor_identity_distinct");parent.removeMovieClip();
        trace("PlayerResourceTransferTest Tests Passed: "+passed);
        trace("PlayerResourceTransferTest Tests Failed: "+failed);
    }
}
