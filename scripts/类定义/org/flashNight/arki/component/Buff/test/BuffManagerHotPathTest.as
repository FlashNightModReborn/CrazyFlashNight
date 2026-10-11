import org.flashNight.arki.component.Buff.*;
import org.flashNight.arki.component.Buff.Component.*;
import org.flashNight.arki.component.Buff.test.BuffManagerLegacyUpdateFixture;

/** Actual manager lifecycle and event order, with the prior update passes as oracle. */
class org.flashNight.arki.component.Buff.test.BuffManagerHotPathTest {
    private static var passed:Number = 0;
    private static var failed:Number = 0;
    private static var checksum:Number = 0;
    private static var codec:LiteJSON;
    private static function check(value:Boolean, label:String):Void {
        if (value) passed++; else { failed++; trace("[FAIL] BuffManagerHotPathTest: " + label); }
    }
    private static function eventKey(id:String, buff:Object):String {
        return isNaN(Number(id)) ? id : "injected:" + buff.getTargetProperty() + ":" + buff.getValue();
    }
    private static function make(legacy:Boolean, metaCount:Number, podCount:Number):Object {
        var target:Object = {power:100, armor:50, nested:{power:20}};
        var callbacks:Object = {};
        callbacks.onBuffAdded = function(id:String, buff:Object):Void {
            var owner:Object = this;
            owner.testEvents.push("add:" + BuffManagerHotPathTest.eventKey(id,buff));
            if (owner.testCascade && id == "delayed") owner.addBuff(new PodBuff("power", BuffCalculationType.ADD, 3), "wave2");
            if (owner.testCascade && id == "wave2") owner.addBuff(new PodBuff("armor", BuffCalculationType.ADD, 2), "wave3");
        };
        callbacks.onBuffRemoved = function(id:String, buff:Object):Void {
            var owner:Object = this;
            owner.testEvents.push("remove:" + BuffManagerHotPathTest.eventKey(id,buff));
            if (owner.testDrain && id == "p0") owner.removeBuff("p1");
        };
        var manager:Object = new BuffManager(target,callbacks);
        manager.testEvents = []; manager.testCascade = false; manager.testDrain = false;
        if (legacy) BuffManagerLegacyUpdateFixture.install(manager);
        var metas:Array = [], pods:Array = [];
        for (var i:Number = 0; i < podCount; i++) {
            var pod:PodBuff = new PodBuff(i % 2 == 0 ? "power" : "armor", BuffCalculationType.ADD, i + 1);
            pods.push(pod); manager.addBuff(pod,"p" + i);
        }
        for (i = 0; i < metaCount; i++) {
            var meta:MetaBuff = new MetaBuff([new PodBuff("power",BuffCalculationType.ADD,2), new PodBuff("armor",BuffCalculationType.PERCENT,0.01)], [new TimeLimitComponent(100000)], 0);
            metas.push(meta); manager.addBuff(meta,"m" + i);
        }
        manager.update(0);
        return {manager:manager, target:target, metas:metas, pods:pods};
    }
    private static function snapshot(f:Object):Object {
        var manager:Object = f.manager, buffs:Array = manager._buffs, members:Array = [], timers:Array = [];
        for (var i:Number = 0; i < buffs.length; i++) {
            var buff:Object = buffs[i];
            members.push(eventKey(String(buff.__regId),buff) + ":" + buff.isActive());
        }
        for (i = 0; i < f.metas.length; i++) {
            var timer:Object = f.metas[i].getPrimaryTimer();
            timers.push(timer == null ? null : timer.getRemaining());
        }
        return {power:f.target.power, armor:f.target.armor, nested:f.target.nested.power,
            counter:manager._updateCounter, inUpdate:manager._inUpdate, members:members, timers:timers,
            pendingRemove:manager._pendingRemovals.length, pendingA:manager._pendingAddsA.length, pendingB:manager._pendingAddsB.length,
            events:manager.testEvents.concat()};
    }
    private static function same(a:Object,b:Object,label:String):Void {
        var left:String = codec.stringifySafe(snapshot(a)), right:String = codec.stringifySafe(snapshot(b));
        check(left == right,label);
        if (left != right) { trace("[BUFF_ACTUAL] " + left); trace("[BUFF_ORACLE] " + right); }
    }
    private static function addReentry(f:Object):Void {
        var comp:Object = {owner:f.manager, armed:false};
        comp.onAttach = function():Void {};
        comp.onDetach = function():Void {};
        comp.isLifeGate = function():Boolean { return false; };
        comp.update = function(host:Object,delta:Number):Boolean {
            if (this.armed) {
                this.armed = false;
                this.owner.addBuff(new PodBuff("power",BuffCalculationType.ADD,5),"delayed");
                this.owner.removeBuff("p0");
                this.owner.update(4);
                this.owner.setPodBuffValue("p2",9);
            }
            return true;
        };
        f.trigger = comp;
        f.manager.addBuff(new MetaBuff([], [comp], 0),"trigger");
        f.manager.addBuff(new PodBuff("nested.power",BuffCalculationType.ADD,3),"path");
        f.manager.update(0);
        f.manager.testCascade = f.manager.testDrain = true;
    }
    private static function action(f:Object, frame:Number):Void {
        var manager:Object = f.manager;
        if (frame == 1) f.trigger.armed = true;
        if (frame == 2) f.metas[0].deactivate();
        if (frame == 3) {
            var meta:MetaBuff = new MetaBuff([new PodBuff("power",BuffCalculationType.ADD,7)], [new TimeLimitComponent(16)],0);
            f.metas.push(meta); manager.addBuff(meta,"m0");
        }
        if (frame == 4) { f.target.nested = {power:70}; manager.notifyPathRootChanged("nested"); }
        if (frame == 5) f.pods[3].deactivate();
        if (frame == 6) manager.unmanageProperty("armor",true);
        if (frame == 7) manager.addBuff(new PodBuff("armor",BuffCalculationType.ADD,4),"newArmor");
        if (frame == 8) manager.clearAllBuffs();
        if (frame == 9) {
            meta = new MetaBuff([new PodBuff("power",BuffCalculationType.MULTIPLY,1.1)], [new TimeLimitComponent(20)],0);
            f.metas.push(meta); manager.addBuff(meta,"restart");
        }
        if (frame == 10) f.metas[f.metas.length - 1].getPrimaryTimer().pause();
        if (frame == 12) f.metas[f.metas.length - 1].getPrimaryTimer().resume();
        if (frame == 14) manager.removeBuff("restart");
        var delta:Number = frame == 11 ? 0 : frame == 15 ? -2 : 4;
        manager.update(delta);
    }
    private static function testLifecycle():Void {
        var actual:Object = make(false,3,4), expected:Object = make(true,3,4);
        addReentry(actual); addReentry(expected); same(actual,expected,"setup with real Meta/Pod/path containers");
        check(actual.target.power > 100 && actual.manager.testEvents.length > 0,"fixture really admits buffs and invokes callbacks");
        for (var frame:Number = 1; frame < 19; frame++) { action(actual,frame); action(expected,frame); same(actual,expected,"callback/timer/membership frame " + frame); }
        check(actual.manager._pendingRemovals.length == 0 && !actual.manager._inUpdate,"drain and reentry flags close cleanly");
        var before:Number = actual.manager._updateCounter;
        actual.manager.update(Number.NaN); expected.manager.update(Number.NaN); same(actual,expected,"NaN delta ignored");
        actual.manager.update(Number.POSITIVE_INFINITY); expected.manager.update(Number.POSITIVE_INFINITY); same(actual,expected,"infinite delta ignored");
        check(actual.manager._updateCounter == before,"invalid deltas do not count an update");
        actual.manager.destroy(); expected.manager.destroy(); same(actual,expected,"destroy finalizes and clears members");
    }
    private static function testMixedScript():Void {
        var actual:Object = make(false,0,0), expected:Object = make(true,0,0), fixtures:Array = [actual,expected];
        var seed:Number = 73;
        for (var frame:Number = 0; frame < 100; frame++) {
            seed = (seed * 1103515245 + 12345) % 2147483647;
            var selector:Number = Math.floor(seed) % 7;
            for (var side:Number = 0; side < 2; side++) {
                var f:Object = fixtures[side], manager:Object = f.manager, id:String = "slot" + (frame % 9);
                if (selector == 0) manager.addBuff(new PodBuff("power",BuffCalculationType.ADD,frame % 11),id);
                else if (selector == 1) manager.addBuff(new MetaBuff([new PodBuff("armor",BuffCalculationType.ADD,3)],[new TimeLimitComponent(8 + frame % 13)],0),id);
                else if (selector == 2) manager.removeBuff("slot" + ((frame + 6) % 9));
                else if (selector == 3) manager.setBaseValue("power",100 + frame);
                else if (selector == 4) manager.addBuffImmediate(new PodBuff("power",BuffCalculationType.MULTIPLY,1.01),id);
                else if (selector == 5) manager.setPodBuffValue(id,frame % 7);
                else { f.target.nested = {power:frame}; manager.notifyPathRootChanged("nested"); }
                manager.update(frame % 4 == 0 ? 0 : 4);
            }
            same(actual,expected,"deterministic mixed script frame " + frame);
        }
        actual.manager.destroy(); expected.manager.destroy(); same(actual,expected,"mixed script destroy");
    }
    private static function time(manager:Object,count:Number):Number {
        var start:Number = getTimer();
        for (var i:Number = 0; i < count; i++) manager.update(4);
        checksum += manager._updateCounter;
        return getTimer() - start;
    }
    private static function bench(metaCount:Number,podCount:Number):Void {
        var original:Object = make(true,metaCount,podCount), candidate:Object = make(false,metaCount,podCount);
        time(original.manager,10); time(candidate.manager,10);
        var before:Array = [], after:Array = [];
        for (var round:Number = 0; round < 5; round++) {
            if ((round & 1) == 0) { before.push(time(original.manager,800)); after.push(time(candidate.manager,800)); }
            else { after.push(time(candidate.manager,800)); before.push(time(original.manager,800)); }
        }
        same(candidate,original,"benchmark post-state meta=" + metaCount + " pod=" + podCount);
        trace("[AS2_HOTPATH_BENCH] buff_update_meta" + metaCount + "_pod" + podCount + "|iterations=800|baselineMs=" + before.join(",") + "|candidateMs=" + after.join(","));
        original.manager.destroy(); candidate.manager.destroy();
    }
    private static function timeChurn(f:Object,count:Number):Number {
        var manager:Object=f.manager,start:Number=getTimer();
        for(var i:Number=0;i<count;i++) {
            manager.addBuff(new MetaBuff([new PodBuff("power",BuffCalculationType.ADD,7)], [new TimeLimitComponent(8)],0),"churn");
            manager.update(4);manager.removeBuff("churn");manager.update(0);
            manager.addBuff(new PodBuff("armor",BuffCalculationType.ADD,2),"churnPod");
            manager.update(0);manager.removeBuff("churnPod");manager.update(0);
        }
        return getTimer()-start;
    }
    private static function benchChurn():Void {
        var original:Object=make(true,2,4),candidate:Object=make(false,2,4);
        var before:Array=[],after:Array=[];
        timeChurn(original,2);timeChurn(candidate,2);
        for(var round:Number=0;round<5;round++) {
            if((round&1)==0){before.push(timeChurn(original,30));after.push(timeChurn(candidate,30));}
            else{after.push(timeChurn(candidate,30));before.push(timeChurn(original,30));}
        }
        same(candidate,original,"frequent add/remove exact event and state parity");
        check(candidate.manager._metaBuffs.length==2 && candidate.manager._standalonePodBuffs.length==4,"scheduling lists contain only surviving registered members");
        trace("[AS2_HOTPATH_BENCH] buff_churn_meta2_pod4|iterations=30|baselineMs="+before.join(",")+"|candidateMs="+after.join(","));
        candidate.manager.destroy();original.manager.destroy();
        check(candidate.manager._metaBuffs.length==0 && candidate.manager._standalonePodBuffs.length==0,"destroy releases both scheduling lists");
    }
    public static function runAllTests():Void {
        passed = failed = checksum = 0; codec = new LiteJSON();
        testLifecycle(); testMixedScript();
        bench(0,0); bench(0,12); bench(1,8); bench(8,0); bench(8,24); benchChurn();
        trace("BuffManagerHotPathTest Tests Passed: " + passed);
        trace("BuffManagerHotPathTest Tests Failed: " + failed);
    }
}
