import org.flashNight.arki.audio.AudioBridge;

class org.flashNight.arki.audio.test.AudioBridgeSfxIncrementalTest {
    private static var passed:Number;
    private static var failed:Number;
    private static var session:String = "550e8400-e29b-41d4-a716-446655440000";
    private static function check(value:Boolean, label:String):Void {
        if (value) passed++; else { failed++; trace("[TEST_FAIL] AudioBridgeSfxIncrementalTest: " + label); }
    }
    private static function ready(generation:String, device:String):Object {
        return {task:"audio_ready",wireRevision:2,audioSessionId:session,
            audioReadyGeneration:generation,deviceGeneration:device,loaded:12,failed:0,overrides:0,
            capabilityDigest:"0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"};
    }
    private static function transport():Object {
        var t:Object = {isSocketConnected:true,frames:[],reject:false};
        t.sendSocketMessage = function(message:String):Boolean {
            if (t.reject) { t.reject = false; return false; }
            t.frames.push(message); return true;
        };
        return t;
    }
    private static function same(a:Object,b:Object):Boolean {
        if (a.status !== b.status || a.sfxBuffered !== b.sfxBuffered || a.sfxBatchSequence !== b.sfxBatchSequence) return false;
        var x:Object=a.sfxCounters,y:Object=b.sfxCounters;
        return x.preReadyDrops === y.preReadyDrops && x.recoveryDrops === y.recoveryDrops
            && x.staleGenerationDrops === y.staleGenerationDrops && x.unknownIdCount === y.unknownIdCount
            && x.throttledCount === y.throttledCount;
    }
    public static function runAllTests():Void {
        passed=0;failed=0;
        var old:Object = org.flashNight.arki.audio.test.AudioBridgeSfxLegacyFixture;
        var current:Object = org.flashNight.arki.audio.AudioBridge;
        var before:Object=transport(),after:Object=transport();
        old._resetForTests();current._resetForTests();
        old._setTransportForTests(before);current._setTransportForTests(after);
        check(old.handleAudioReady(ready("9","2")),"legacy fixture admitted ready");
        check(current.handleAudioReady(ready("9","2")),"candidate fixture admitted ready");
        var wide:String="";for(var w:Number=0;w<255;w++)wide+="音";
        var ids:Array=["same.wav","音效😀",wide,"bad|id","bad/path","..",String.fromCharCode(55296),String.fromCharCode(56320),"tab"+String.fromCharCode(9)];
        var seed:Number=13579, id:String, operation:Number;
        for(var i:Number=0;i<20000;i++) {
            seed=(seed*48271)%2147483647;operation=seed%20;
            if(operation<15){id=ids[seed%ids.length];old.playSound(id);current.playSound(id);}
            else if(operation==15){old.flush();current.flush();}
            else if(operation==16){old.reset();current.reset();}
            else if(operation==17){before.reject=true;after.reject=true;old.flush();current.flush();}
            else if(operation==18){old.handleAudioReady(ready("9",String(i%3+2)));current.handleAudioReady(ready("9",String(i%3+2)));}
            else {old.onTransportDisconnected();current.onTransportDisconnected();old.handleAudioReady(ready("9","2"));current.handleAudioReady(ready("9","2"));}
            check(same(old._snapshotForTests(),current._snapshotForTests()),"lifecycle state "+i);
            check(before.frames.length==after.frames.length,"batch count "+i);
            if(before.frames.length>0)check(before.frames[before.frames.length-1]===after.frames[after.frames.length-1],"exact wire "+i);
        }
        check(before.frames.length>100,"differential workload actually sent S2 batches");
        // Maximum decimal sequence and every buffer-reset path must clear the header cache.
        old.reset();current.reset();old._setSfxBatchSequenceForTests("18446744073709551614");current._setSfxBatchSequenceForTests("18446744073709551614");
        old.playSound("last");current.playSound("last");old.flush();current.flush();
        check(before.frames[before.frames.length-1]===after.frames[after.frames.length-1],"u64 final batch");
        old.playSound("overflow");current.playSound("overflow");
        check(same(old._snapshotForTests(),current._snapshotForTests()),"u64 exhaustion");
        before.frames=[];after.frames=[];
        before.sendSocketMessage=function(message:String):Boolean { return true; };
        after.sendSocketMessage=function(message:String):Boolean { return true; };
        old._resetForTests();current._resetForTests();old._setTransportForTests(before);current._setTransportForTests(after);
        check(old.handleAudioReady(ready("9","2")),"legacy benchmark admitted ready");
        check(current.handleAudioReady(ready("9","2")),"candidate benchmark admitted ready");
        var oldMs:Number=0,newMs:Number=0;
        for(var round:Number=0;round<6;round++) {
            if(round%2==0){oldMs+=bench(old);newMs+=bench(current);}
            else {newMs+=bench(current);oldMs+=bench(old);}
        }
        check(old._snapshotForTests().sfxBatchSequence === "720" && current._snapshotForTests().sfxBatchSequence === "720","benchmark emitted every batch");
        trace("[SfxIncrementalBench] batchesPerVariant=720 eventsPerBatch=64 baselineMs="+oldMs+" candidateMs="+newMs);
        trace("AudioBridgeSfxIncrementalTest Tests Passed: "+passed);
        trace("AudioBridgeSfxIncrementalTest Tests Failed: "+failed);
    }
    private static function bench(api:Object):Number {
        var start:Number=getTimer();
        for(var batch:Number=0;batch<120;batch++) {
            for(var item:Number=0;item<64;item++)api.playSound("枪声.wav");
            api.flush();
        }
        return getTimer()-start;
    }

}
