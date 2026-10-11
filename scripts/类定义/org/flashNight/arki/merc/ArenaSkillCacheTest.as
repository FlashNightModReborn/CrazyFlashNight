import org.flashNight.arki.merc.ArenaSkillCache;

/** 真实玩家模板函数的冷/热缓存隔离；不启动游戏、不读取或写入玩家存档。 */
class org.flashNight.arki.merc.ArenaSkillCacheTest {
    private static var passed:Number;
    private static var failed:Number;
    private static var created:Array;

    public static function runAllTests():Void {
        passed = 0;
        failed = 0;
        created = [];
        var previousCache:Object = _root.技能缓存;
        _root.技能缓存 = {};

        var first:MovieClip = makeUnit("CacheSubject", 0.21, false, false, true);
        var firstState:Object = first._arenaCalibrationSkillState;
        var cacheKey:String = ArenaSkillCache.makeKey("CacheSubject", 30, 0, 0.21);
        trace("ArenaSkillCacheTest cold context: actor=" + first.名字 + "/" + first.等级
            + " actualKey=" + firstState.cacheKey + " expectedKey=" + cacheKey
            + " skillCount=" + first.已学技能表.length);
        var template:Array = _root.技能缓存[cacheKey];
        check(first.已学技能表.length > 0, "cold initialization generates actual skills");
        check(firstState.cacheKey == cacheKey && firstState.cacheHit === false,
            "cold initialization records its exact definition key");
        check(template !== first.已学技能表 && template[0] !== first.已学技能表[0],
            "cold unit and cached definitions do not share mutable entries");
        check(firstState.cooldownsClear === true, "cold unit starts with clear cooldowns");

        var firstDefinition:String = firstState.definitionSignature;
        var firstCount:Number = first.已学技能表.length;
        first.已学技能表[0].上次使用时间 = 98765;
        first.已学技能表[0].技能等级 = 99;
        check(isNaN(Number(template[0].上次使用时间)) && template[0].技能等级 != 99,
            "first actor mutations cannot poison definitions");

        var warm:MovieClip = makeUnit("CacheSubject", 0.21, false, false, true);
        check(warm._arenaCalibrationSkillState.cacheHit === true,
            "same generation inputs take the warm path");
        check(warm.已学技能表 !== first.已学技能表 && warm.已学技能表[0] !== first.已学技能表[0],
            "warm actor receives its own array and skill objects");
        check(warm._arenaCalibrationSkillState.definitionSignature == firstDefinition
            && warm.已学技能表.length == firstCount,
            "warm definitions match the original cold definitions");
        check(warm._arenaCalibrationSkillState.cooldownsClear === true
            && isNaN(Number(warm.已学技能表[0].上次使用时间)),
            "warm actor does not inherit a previous actor cooldown");
        warm.已学技能表[0].上次使用时间 = 12345;
        check(first.已学技能表[0].上次使用时间 == 98765
            && isNaN(Number(template[0].上次使用时间)),
            "parallel actors and cached definitions remain independent");
        var warmSkills:Array = warm.已学技能表;
        warm.初始化可用技能();
        check(warm.已学技能表 === warmSkills && warm.已学技能表[0].上次使用时间 == 12345,
            "reinitializing an active actor keeps its existing cooldown state");

        delete _root.技能缓存[cacheKey];
        var coldAgain:MovieClip = makeUnit("CacheSubject", 0.21, false, false, true);
        check(coldAgain._arenaCalibrationSkillState.cacheHit === false
            && coldAgain._arenaCalibrationSkillState.definitionSignature == firstDefinition,
            "regeneration after cache eviction matches cold and warm definitions");

        var blade:MovieClip = makeUnit("CacheSubject", 0.21, true, false, true);
        var gun:MovieClip = makeUnit("CacheSubject", 0.21, false, true, true);
        var both:MovieClip = makeUnit("CacheSubject", 0.21, true, true, true);
        check(blade._arenaCalibrationSkillState.cacheKey == ArenaSkillCache.makeKey("CacheSubject", 30, 1, 0.21)
            && blade._arenaCalibrationSkillState.cacheHit === false,
            "blade equipment has an independent definition key");
        check(gun._arenaCalibrationSkillState.cacheKey == ArenaSkillCache.makeKey("CacheSubject", 30, 2, 0.21)
            && both._arenaCalibrationSkillState.cacheKey == ArenaSkillCache.makeKey("CacheSubject", 30, 3, 0.21),
            "gun and mixed equipment do not reuse the unarmed definition");
        var sameBucket:MovieClip = makeUnit("CacheSubject", 0.24, false, false, true);
        check(Math.round(0.21 * 4) == Math.round(0.24 * 4)
            && sameBucket._arenaCalibrationSkillState.cacheKey != cacheKey
            && sameBucket._arenaCalibrationSkillState.cacheHit === false,
            "different actual skill budgets cannot alias through rounded technique buckets");

        var normal:MovieClip = makeUnit("OrdinarySubject", 0.21, false, false, false);
        check(normal._arenaCalibrationSkillState == undefined
            && _root.技能缓存["OrdinarySubject_30_t1"] === normal.已学技能表,
            "ordinary player template retains its existing cache path");
        var preset:MovieClip = makeEmptyUnit("PresetSubject", true);
        var registered:Array = [{技能名:"预注册", 技能等级:7, 上次使用时间:222}];
        preset.已学技能表 = registered;
        preset.初始化可用技能();
        check(preset.已学技能表 === registered && registered[0].上次使用时间 == 222,
            "equipment registered skills retain their established initializer ownership");

        var source:Object = {技能名:"拷贝探针", 技能等级:3, 冷却:8, 上次使用时间:77, 自定义标量:42};
        source.__proto__ = {inheritedSkillFlag:true};
        var copied:Array = ArenaSkillCache.copyForUnit([source]);
        check(copied[0].自定义标量 == 42 && copied[0].inheritedSkillFlag == undefined,
            "copy preserves owned scalar definitions without inherited properties");
        check(isNaN(Number(copied[0].上次使用时间)) && source.上次使用时间 == 77,
            "copy resets only the new actor cooldown and preserves its source");
        check(ArenaSkillCache.makeKey("x|l30|e0|t0", 30, 0, 0)
            != ArenaSkillCache.makeKey("x", 30, 0, 0),
            "length-prefixed names do not alias structural key fields");
        check(ArenaSkillCache.copyForUnit([]).length == 0,
            "empty skill definitions remain empty");

        for (var i:Number = 0; i < created.length; i++) created[i].removeMovieClip();
        _root.技能缓存 = previousCache;
        trace("ArenaSkillCacheTest Tests Passed: " + passed);
        trace("ArenaSkillCacheTest Tests Failed: " + failed);
    }

    private static function makeEmptyUnit(subject:String, calibration:Boolean):MovieClip {
        var unit:MovieClip = _root.createEmptyMovieClip("arenaSkillCacheTest_" + created.length,
            _root.getNextHighestDepth());
        created.push(unit);
        unit.名字 = subject;
        unit.等级 = 30;
        unit._arenaCalibrationUnit = calibration;
        unit.初始化可用技能 = _root.主角函数.初始化可用技能;
        return unit;
    }

    private static function makeUnit(subject:String, technique:Number, blade:Boolean,
        gun:Boolean, calibration:Boolean):MovieClip {
        var unit:MovieClip = makeEmptyUnit(subject, calibration);
        unit.personality = {技术:technique};
        unit.刀 = blade ? "测试刀" : null;
        unit.长枪 = gun ? "测试枪" : null;
        unit.初始化可用技能();
        return unit;
    }

    private static function check(condition:Boolean, label:String):Void {
        if (condition) {
            passed++;
            trace("[PASS] " + label);
        } else {
            failed++;
            trace("[FAIL] " + label);
        }
    }
}
