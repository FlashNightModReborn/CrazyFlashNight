import org.flashNight.arki.render.EquipmentLightBridge;

// Same five AVM1 workloads for the pre-migration and XML implementations.
class org.flashNight.arki.render.ProjectileLightBenchmark {
    private static var reference:Object;
    private static var comparisonId:String;
    private static var report:Array;

    public static function setReference(api:Object, id:String):Void { reference=api; comparisonId=id; }
    private static function measure(world:MovieClip, scenario:Number, api:Object, mode:String):Void {
        var actorList:Array = [];
        var clips:Array = [];
        var i:Number;
        for (i = 0; i < 8; i++) {
            actorList.push(world.createEmptyMovieClip("shooter" + i, world.getNextHighestDepth()));
        }
        for (i = 0; i < 60; i++) {
            var clip:MovieClip = world.createEmptyMovieClip("projectile" + i, world.getNextHighestDepth());
            clip._x = 80 + i % 8 * 26; clip._y = 60 + Math.floor(i / 8) * 20;
            clips.push(clip);
        }
        var empty:Object = {baseAsset:"透明子弹", 子弹种类:"透明子弹", 声音:"", 魔法伤害属性:"", 吸血:0, shootX:120, shootY:100};
        var cold:Object = {baseAsset:"透明子弹", 子弹种类:"透明子弹", 魔法伤害属性:"冷",
            lightBinding:"area.ice-stream", lightCastId:1, lightSourceSlot:0, lightFacing:1};
        var hit:Object = {aabbCollider:{left:120, right:340, top:100, bottom:150}};
        var shot:Object = {baseAsset:"火球", 子弹种类:"火球"};
        var factoryTimes:Array = [], renderTimes:Array = [], totalTimes:Array = [], lookupTimes:Array = [];
        var keys:Array=["火球","普通爆炸","透明子弹","未知测试资产"];
        var catalog:Object = mode=="baseline" ? api["bulletProfiles"] : api["lightProfiles"].projectile;
        if (mode=="baseline" && catalog==null) catalog=api["initBulletProfiles"]();
        var hits:Number = 0;
        var count:Number = scenario == 4 ? 60 : 24;
        var sources:Number, admitted:Number, entryCount:Number, ids:Number;
        for (var sample:Number = 0; sample < 34; sample++) {
            api.resetScene();
            var before:Number = api["nextId"];
            _root.帧计时器.当前帧数++;
            var start:Number = getTimer();
            for (i = 0; i < count; i++) {
                if (scenario == 0) api.registerBullet(hit, empty, actorList[0]);
                else if (scenario == 1 || scenario == 2) {
                    api.registerBullet(hit, cold, actorList[scenario == 1 ? 0 : i % 8]);
                } else if (scenario == 3 && i % 2 != 0) {
                    api.registerEffect(clips[i], "普通爆炸");
                } else api.registerBullet(clips[i], shot, actorList[i % 8]);
            }
            var registered:Number = getTimer();
            api.payload();
            var completed:Number = getTimer();
            if (sample >= 4) {
                factoryTimes.push(registered - start);
                renderTimes.push(completed - registered);
            }
            // Resolve the same two hits and two misses in a separate batch; registration timing above includes the real lookup.
            var lookupStart:Number=getTimer();
            hits=0;
            for (var j:Number=0;j<256;j++) if (catalog[keys[j%4]]!=undefined) hits++;
            var lookupElapsed:Number=getTimer()-lookupStart;
            if (sample>=4) { lookupTimes.push(lookupElapsed); totalTimes.push(completed-start); }
            var stats:Object = api.getStats();
            admitted = stats.admitted;
            sources = stats.activeSources;
            entryCount = api["projectiles"].length;
            ids = api["nextId"] - before;
        }
        factoryTimes.sort(Array.NUMERIC);
        renderTimes.sort(Array.NUMERIC); totalTimes.sort(Array.NUMERIC); lookupTimes.sort(Array.NUMERIC);
        if (hits!=128) trace("[TEST_FAIL] projectile workload lookup hits="+hits);
        if (!isFinite(entryCount + ids) || entryCount > 48 || admitted > 16 || (scenario == 0 ? sources != 0 : !(sources > 0))) {
            trace("[TEST_FAIL] projectile lighting workload " + scenario + " entries=" + entryCount + " active=" + sources);
        }
        var row:String="ProjectileLightBenchmark case=" + scenario + " calls=" + count + " samples=30 allocations=" + ids
            + " registered=" + entryCount + " sources=" + sources + " admitted=" + admitted
            + " culledOrMerged=" + stats.coalescedOrCulled + " candidates=" + stats.candidates + " dropped=" + stats.dropped
            + " lookupBatch=256 lookupHits=" + hits + " lookupMsP50=" + lookupTimes[14] + " lookupMsP95=" + lookupTimes[28]
            + " totalMsP50=" + totalTimes[14] + " totalMsP95=" + totalTimes[28]
            + " registerMsP50=" + factoryTimes[14] + " registerMsP95=" + factoryTimes[28]
            + " payloadMsP50=" + renderTimes[14] + " payloadMsP95=" + renderTimes[28];
        trace(mode=="baseline" ? "Reference "+row : row);
        report.push(mode+" "+row);
        for (i = 0; i < actorList.length; i++) actorList[i].removeMovieClip();
        for (i = 0; i < clips.length; i++) clips[i].removeMovieClip();
    }
    public static function runAllTests():Void {
        var oldWorld:MovieClip = _root.gameworld;
        var oldClock:Object = _root.帧计时器;
        var oldPause:Object = _root.暂停;
        var world:MovieClip = _root.createEmptyMovieClip("__projectileLightBench", _root.getNextHighestDepth());
        _root.gameworld = world; _root.帧计时器 = {当前帧数:1}; _root.暂停 = false;
        var caps:Object = {equipmentLights:2, equipmentRadialLights:1}; caps["native"] = true;
        report=[];
        var scenario:Number;
        if(reference!=null) {
            reference.configure(caps);
            for (scenario=0; scenario<5; scenario++) measure(world,scenario,reference,"baseline");
            reference.disconnect();
        }
        EquipmentLightBridge.configure(caps);
        for (scenario=0; scenario<5; scenario++) measure(world,scenario,EquipmentLightBridge,"candidate");
        if(reference!=null) {
            if(_root._url.indexOf("/light-author-proof/")>=0) {
                var receipt:SharedObject=SharedObject.getLocal("cf7-light-bench-"+comparisonId);
                receipt.data.report="CF7-LIGHT-BEGIN\n"+System.capabilities.version+"\n"+report.join("\n")+"\nCF7-LIGHT-END";
                receipt.flush();
            }
            trace("LightBenchmarkComparison complete");
        }
        EquipmentLightBridge.disconnect(); world.removeMovieClip();
        _root.gameworld = oldWorld; _root.帧计时器 = oldClock; _root.暂停 = oldPause;
    }
}
