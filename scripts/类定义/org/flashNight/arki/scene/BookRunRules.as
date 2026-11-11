/** 可复现的出怪计划和有限纪录奖励。纯规则不读取或改写玩家状态。 */
class org.flashNight.arki.scene.BookRunRules {
    /** Pure declaration lookup; map/page bindings are generated from the content registry. */
    public static function chapterIntro(config:Object, index:Number):Object {
        if (!(config.chapterIntros instanceof Array) || typeof index!="number" || isNaN(index)
                || Math.floor(index)!=index || index<0 || !(index<config.maps.length)) return null;
        for (var i:Number=0;i<config.chapterIntros.length;i++) {
            var entry:Object=config.chapterIntros[i];
            if (entry.chapter===index && typeof entry.bgmLease=="boolean"
                    && org.flashNight.arki.scene.BookComicService.knownPage(entry.pageId))
                return {kind:"book_chapter",bookId:config.id,chapter:index,pageId:entry.pageId,bgmLease:entry.bgmLease};
        }
        return null;
    }
    public static function sameActiveRun(identity:Object, current:Object):Boolean {
        return identity!=null && current!=null && current.outcome=="active"
            && typeof identity.bookId=="string" && identity.bookId!="" && identity.bookId===current.bookId
            && typeof identity.slot=="string" && identity.slot!="" && identity.slot===current.slot
            && typeof identity.seed=="number" && isFinite(identity.seed) && !isNaN(identity.seed)
            && identity.seed>0 && identity.seed<2147483647 && Math.floor(identity.seed)==identity.seed
            && typeof identity.startedAt=="number" && isFinite(identity.startedAt) && !isNaN(identity.startedAt)
            && identity.startedAt>0 && Math.floor(identity.startedAt)==identity.startedAt
            && identity.seed===current.seed && identity.startedAt===current.startedAt
            && identity.routeId===current.routeId && identity.planSeed===current.planSeed;
    }
    /** RewardStash may clone bookRun during commit/rollback; compare a detached identity, not object references. */
    public static function sameCf6Run(identity:Object, current:Object):Boolean {
        if (identity == null || current == null || identity.bookId !== "cf6-sting" || current.bookId !== "cf6-sting"
                || !org.flashNight.arki.scene.BookDefinition.isCf6Route(identity.routeId)
                || identity.routeId !== current.routeId || current.outcome !== "active"
                || typeof identity.slot != "string" || identity.slot == "" || identity.slot !== current.slot
                || typeof identity.seed != "number" || !isFinite(identity.seed) || isNaN(identity.seed)
                || !(identity.seed > 0) || !(identity.seed < 2147483647) || Math.floor(identity.seed) != identity.seed
                || typeof identity.startedAt != "number" || !isFinite(identity.startedAt) || isNaN(identity.startedAt)
                || !(identity.startedAt > 0) || Math.floor(identity.startedAt) != identity.startedAt
                || identity.seed !== current.seed || identity.startedAt !== current.startedAt
                || identity.planSeed !== current.planSeed) return false;
        return identity.planSeed === undefined || (typeof identity.planSeed == "number" && isFinite(identity.planSeed)
            && !isNaN(identity.planSeed) && identity.planSeed > 0 && identity.planSeed < 2147483647
            && Math.floor(identity.planSeed) == identity.planSeed);
    }
    private static function next(state:Object):Number {
        state.value = (state.value * 48271) % 2147483647;
        return state.value / 2147483647;
    }
    private static function integer(state:Object, lo:Number, hi:Number):Number {
        return lo + Math.floor(next(state) * (hi - lo + 1));
    }
    /** Local plan RNG keeps authored wave composition from perturbing loot draws. */
    private static function planState(seed:Number, index:Number):Object {
        return {value:(seed + (index + 1) * 7919) % 2147483646 + 1};
    }
    private static function spread(state:Object, total:Number, count:Number, lateBias:Boolean):Array {
        var result:Array = [];
        for (var i:Number = 0; i < count; i++) result.push(1);
        for (var n:Number = count; n < total; n++) {
            var index:Number = integer(state, 0, count - 1);
            if (lateBias) index = Math.max(index, integer(state, 0, count - 1));
            result[index]++;
        }
        return result;
    }
    /** Weak-to-strong wave pool: early waves favor lower combat power, later waves higher. */
    private static function basePoolFor(map:Object, wave:Number):Array {
        var pool:Array = [];
        if (map.enemyPower == null) {
            if (map.enemyWeights == null) return map.enemies;
            for (var s:Number = 0; s < map.enemyWeights.length; s++)
                for (var c:Number = 0; c < map.enemyWeights[s].weight; c++)
                    pool.push(map.enemyWeights[s].type);
            return pool;
        }
        var weights:Object = {};
        if (map.enemyWeights != null)
            for (var e:Number = 0; e < map.enemyWeights.length; e++)
                weights[String(map.enemyWeights[e].type)] = map.enemyWeights[e].weight;
        var maxPower:Number = 1;
        for (var t:Number = 0; t < map.enemies.length; t++) {
            var p:Number = Number(map.enemyPower[t]);
            if (isFinite(p) && p > maxPower) maxPower = p;
        }
        var progress:Number = map.waves > 1 ? wave / (map.waves - 1) : 1;
        // Non-final waves exclude the strongest tier so a bad roll cannot start with a heavy.
        var allowedPower:Number = wave < map.waves - 1 && maxPower > 1 ? maxPower - 1 : maxPower;
        for (t = 0; t < map.enemies.length; t++) {
            var type:Number = map.enemies[t];
            p = Number(map.enemyPower[t]);
            if (!isFinite(p) || p < 1) p = 1;
            if (p > allowedPower) continue;
            var baseWeight:Number = weights[String(type)] == undefined ? 1 : weights[String(type)];
            var factor:Number = (1 - progress) * (maxPower + 1 - p) + progress * p;
            var repeat:Number = Math.max(1, Math.round(baseWeight * factor));
            for (var n:Number = 0; n < repeat; n++) pool.push(type);
        }
        if (pool.length == 0) return map.enemies;
        return pool;
    }
    /** 地图 BGM：单曲、序列或 stop；缺省保持既有 Bulletproof，避免空配置退化为静音。 */
    private static function mapBgm(map:Object):Object {
        var spec:Object = map.bgm;
        if (spec == null) return {Command:"play", Title:"Bulletproof", Loop:true};
        if (typeof spec == "string") {
            return String(spec) == "stop" ? {Command:"stop"} : {Command:"play", Title:String(spec), Loop:true};
        }
        if (spec.command != undefined && String(spec.command) == "stop") return {Command:"stop"};
        if (spec.sequence != undefined && String(spec.sequence) != "") {
            var index:Number = Number(spec.index);
            if (isNaN(index)) index = undefined;
            return {Command:"play", Sequence:String(spec.sequence), Index:index,
                Loop:spec.loop !== false, Advance:spec.advance === true};
        }
        if (spec.title != undefined && String(spec.title) != "") {
            return {Command:"play", Title:String(spec.title), Loop:spec.loop !== false};
        }
        return {Command:"play", Title:"Bulletproof", Loop:true};
    }

    public static function stages(seed:Number, startAt:Number, bookId:String, routeId:String):Array {
        var config:Object = org.flashNight.arki.scene.BookDefinition.get(bookId,routeId);
        if (config == null) return [];
        if (config.id === "cf6-sting") return authoredStages(config, seed, startAt);
        var state:Object = {value:seed};
        if (isNaN(seed) || seed < 1 || seed >= 2147483647 || Math.floor(seed) != seed) state.value = 1;
        var planSeed:Number = state.value;
        var result:Array = [];
        var economy:Object = config.loot;
        var supportIndex:Number = 0;
        for (var i:Number = 0; i < config.maps.length; i++) {
            var map:Object = config.maps[i], waves:Array = [];
            var mix:Object = null, waveCounts:Array = null;
            if (map.wavePlan != null) {
                mix = planState(planSeed, i);
                waveCounts = spread(mix, integer(mix, map.wavePlan.baseTotal[0], map.wavePlan.baseTotal[1]), map.waves, true);
            }
            var choices:Array = [];
            for (var c:Number = 0; c < config.buildChoices.length; c++)
                if (config.buildChoices[c].afterMap == i) choices.push(config.buildChoices[c]);
            for (var mc:Number = 0; mc < config.minorChoices.length; mc++)
                if (config.minorChoices[mc].afterMap == i) choices.push(config.minorChoices[mc]);
            if (config.styleChoices != null) {
                for (var sc:Number = 0; sc < config.styleChoices.length; sc++)
                    if (config.styleChoices[sc].afterMap == i) choices.push(config.styleChoices[sc]);
            }
            var optionalPercent:Number = i >= config.optionalLoot.firstMap && i <= config.optionalLoot.lastMap ? config.optionalLoot.percent : 100;
            var armorOffset:Number = integer(state, 0, map.armor.length - 1);
            for (var w:Number = 0; w < map.waves; w++) {
                var loot:String = map.equipment[integer(state, 0, map.equipment.length - 1)];
                var supply:String = config.supplies[integer(state, 0, config.supplies.length - 1)];
                // 首波及第三波提供比例急救；中间一波保留随机增益，复用原补给位。
                var medical:Boolean = w % 2 == 0;
                if (medical) supply = economy.medicalItem;
                // 同图敌池逐只轮转混编：前期少而弱，后期多而强。
                var basePool:Array = basePoolFor(map, w);
                var enemyOffset:Number = integer(state, 0, basePool.length - 1);
                var enemyLevel:Number = integer(state, map.level[0], map.level[1]);
                var quantity:Number;
                if (waveCounts == null) {
                    var span:Number = map.count[1] - map.count[0];
                    var waveLow:Number = map.count[0] + Math.floor(span * w / map.waves);
                    var waveHigh:Number = map.count[0] + Math.floor(span * (w + 1) / map.waves);
                    if (w == map.waves - 1) waveHigh = map.count[1];
                    if (waveHigh < waveLow) waveHigh = waveLow;
                    quantity = integer(state, waveLow, waveHigh);
                } else quantity = integer(state, map.count[0], map.count[1]);
                var baseCount:Number = waveCounts == null ? quantity : waveCounts[w];
                var enemies:Array = [];
                var carAssigned:Boolean = false;
                for (var e:Number = 0; e < baseCount; e++) {
                    var enemyType:Number = basePool[(enemyOffset + e) % basePool.length];
                    var parameters:Object = {掉落物:[]};
                    if (!carAssigned && map.carBombType != null && enemyType == map.carBombType) {
                        parameters.汽车炸弹数量 = 1;
                        carAssigned = true;
                    }
                    enemies.push({Type:"兵种" + enemyType, Level:enemyLevel, Quantity:1,
                        Interval:900, Delay:e * 900, SpawnIndex:"right", Parameters:parameters});
                }
                if (map.wavePlan != null) {
                    var eliteWave:Boolean = w == map.waves - 1;
                    var addTypes:Array = eliteWave ? map.wavePlan.eliteTypes : map.wavePlan.addTypes;
                    var addMin:Number = map.wavePlan.addCount[0];
                    var addMax:Number = map.wavePlan.addCount[1];
                    var addSpan:Number = addMax - addMin;
                    var addCount:Number = eliteWave ? addTypes.length
                        : addMin + Math.floor(addSpan * w / Math.max(1, map.waves - 2));
                    var addLevel:Number = eliteWave ? map.wavePlan.eliteLevel : enemyLevel;
                    var addOffset:Number = integer(mix, 0, addTypes.length - 1);
                    for (var a:Number = 0; a < addCount; a++) enemies.push({
                        Type:"兵种" + addTypes[(addOffset + a) % addTypes.length], Level:addLevel,
                        Quantity:1, Interval:900, Delay:enemies.length * 900,
                        SpawnIndex:"right", Parameters:{掉落物:[]}});
                }
                var carrier:Object = enemies[enemies.length - 1];
                // 每波一名敌人携带整波配给；一堆可装多份药品/弹药，不再每敌人散落六堆。
                // 经验总预算保持不变，且不随出怪数量或随机装备抽签减少。
                var experience:Number = Math.ceil(map.experience / map.waves);
                var support:Object = economy.support[supportIndex % economy.support.length];
                var supportName:String = support.kind == "mana" ? map.manaItem : support.name;
                supportIndex++;
                carrier.Parameters.掉落物 = [
                    {名字:loot, 概率:economy.equipmentChance * optionalPercent / 100, 最小数量:1, 最大数量:1, 总数:1},
                    {名字:supply, 概率:medical ? 100 : economy.supplyChance, 最小数量:1, 最大数量:1, 总数:1},
                    // 敌人先查物品字典，必须使用“金币”；显示名“金钱”会被跳过。
                    {名字:economy.moneyItem, 概率:100, 最小数量:map.money[0], 最大数量:map.money[1], 总数:map.money[1]},
                    {名字:economy.experienceItem, 概率:100, 最小数量:experience, 最大数量:experience, 总数:experience},
                    {名字:map.healingItem, 概率:100, 最小数量:economy.healingCount, 最大数量:economy.healingCount, 总数:economy.healingCount},
                    {名字:supportName, 概率:100, 最小数量:support.count, 最大数量:support.count, 总数:support.count}];
                // 前两波各一件不同防具；与武器抽签独立，不以减少武器机会换生存配额。
                if (w < economy.armorWaves) carrier.Parameters.掉落物.push({
                    名字:map.armor[(armorOffset + w) % map.armor.length], 概率:100,
                    最小数量:1, 最大数量:1, 总数:1});
                // 独立 SP 每图首波一堆；材料每波至多一堆，多件合并数量。
                // 沿用真实拾取/调制服务，只作用于当前书中角色，不进入通关回流奖励。
                if (w == 0 && map.skillPoints > 0) carrier.Parameters.掉落物.push({
                    名字:economy.skillPointItem, 概率:100, 最小数量:map.skillPoints,
                    最大数量:map.skillPoints, 总数:map.skillPoints});
                if (w < map.materials.length) {
                    var material:Object = map.materials[w];
                    carrier.Parameters.掉落物.push({名字:material.name, 概率:optionalPercent,
                        最小数量:material.count, 最大数量:material.count, 总数:material.count});
                }
                if (i < config.kBudget.mapCount && w == map.waves - 1) {
                    var kpoints:Number = config.kBudget.guaranteed + integer(state,0,config.kBudget.randomMax);
                    carrier.Parameters.掉落物.push({名字:"K点",概率:100,最小数量:kpoints,最大数量:kpoints,总数:kpoints});
                }
                // 末波按配置投放一个或多个自选包；打开后冻结候选，选定整套物资进入持久暂存。
                if (w == map.waves - 1) for (var choiceIndex:Number = 0; choiceIndex < choices.length; choiceIndex++)
                    carrier.Parameters.掉落物.push({
                        名字:choices[choiceIndex].choiceItem, 概率:100, 最小数量:1, 最大数量:1, 总数:1});
                waves.push({WaveInformation:{Duration:0}, EnemyGroup:{Enemy:enemies}});
            }
            var trainer:Object = {};
            for (var s:Number = 0; s < config.skills.length; s++) trainer[String(s)] = config.skills[s];
            var stage:Object = {BasicInformation:{Background:"flashswf/backgrounds/" + map.background,
                    EndFrame:"房间", BGM:mapBgm(map)},
                Wave:{SubWave:waves}, Event:[{EventName:"Start", Callback:{Name:"书中章节", Parameter:[i]}, Message:"修理大学 · " + (i + 1) + "/7 · " + map.title
                    + (i == 0 ? "。先找迷之盔甲君选择武器和技能；初始 " + config.startingSkillPoints + " SP。弹药补给包需在背包打开并领取。" : "")
                    + (choices.length > 0 ? "。末波掉落自选配给包：从背包打开，选定后技能直接获得，物品到暂存领取；K点仅在确认付费卡时扣除。" : "")
                    + (i > 0 ? "。出发前可打开上图的自选配给包，在装备界面的自选礼包中选择一套武器、插件与补给。" : "")}],
                Instances:{Instance:[]}, Pickups:{Pickup:[]}};
            var intro:Object=chapterIntro(config,i);
            if (intro!=null) stage.BasicInformation.Intro=intro;
            if (i == config.bossEncounter.mapIndex) {
                waves[0].EnemyGroup.Enemy[0].InstanceName = config.bossEncounter.instanceName;
                stage.BasicInformation.BookBoss = bossPlan(config.bossEncounter, state);
            }
            // 商人位于各场景的合法左端出生区，坐标由环境配置在运行时补齐。
            stage.Instances.Instance.push({Identifier:"生存战-迷之盔甲君", x:0, y:0,
                Parameters:{商店检索名:"书中-迷之盔甲君", 技能检索名:"书中-迷之盔甲君", 可学的技能:trainer,
                    任务名:"书中-迷之盔甲君", 默认对话:[]}});
            if (i >= startAt) result.push(stage);
        }
        return result;
    }
    /** Authored CF6 plans are copied for each run; consumed drops never mutate cached config. */
    private static function authoredStages(config:Object, seed:Number, startAt:Number):Array {
        if (isNaN(startAt) || Math.floor(startAt) != startAt || startAt < 0 || startAt >= config.maps.length) return [];
        var result:Array = [];
        var maps:Array=org.flashNight.arki.scene.Cf6EconomyRules.maps(config,seed);
        for (var i:Number=startAt;i<maps.length;i++) {
            var map:Object=maps[i];
            var stage:Object=map.stage;
            if (stage.BasicInformation == null) stage.BasicInformation = {};
            stage.BasicInformation.Background="flashswf/backgrounds/"+map.background;
            stage.BasicInformation.EndFrame="房间";
            stage.BasicInformation.Cf6Boss=map.bossEncounter;
            stage.BasicInformation.Cf6MapId=map.id;
            stage.BasicInformation.Cf6ChapterIndex=i;
            var intro:Object=chapterIntro(config,i);
            if (intro!=null) stage.BasicInformation.Intro=intro;
            if (!(stage.Event instanceof Array)) stage.Event=[];
            stage.Event.unshift({EventName:"Start",Message:config.title+" · "+map.title});
            if (stage.Instances == null) stage.Instances={Instance:[]};
            if (stage.Pickups == null) stage.Pickups={Pickup:[]};
            result.push(stage);
        }
        return result;
    }
    private static function bossPlan(config:Object, state:Object):Object {
        var result:Object = {instanceName:config.instanceName, intervalFrames:config.intervalFrames,
            maxAlive:config.maxAlive, maxRanged:config.maxRanged, groups:[]};
        var sequence:Number = 0;
        for (var g:Number = 0; g < config.groups.length; g++) {
            var source:Object = config.groups[g], group:Object = {hpRatio:source.hpRatio, enemies:[]};
            for (var p:Number = 0; p < source.pools.length; p++) {
                var pool:Array = source.pools[p];
                var type:Number = pool[integer(state, 0, pool.length - 1)];
                var ranged:Boolean = false;
                for (var r:Number = 0; r < config.rangedTypes.length; r++) if (config.rangedTypes[r] == type) ranged = true;
                var supply:Object = config.supplies[sequence % config.supplies.length];
                group.enemies.push({Type:"兵种" + type, Level:source.level, Quantity:1, SpawnIndex:sequence % 2 == 0 ? "right" : "left",
                    InstanceName:"bookCampusSupport" + sequence, ranged:ranged,
                    Parameters:{publishStageEvent:true, 掉落物:[{名字:supply.name, 概率:100,
                        最小数量:supply.count, 最大数量:supply.count, 总数:supply.count}]}});
                sequence++;
            }
            result.groups.push(group);
        }
        return result;
    }
    public static function reward(run:Object, previous:Object):Object {
        if (run.bookId === "cf6-sting") {
            var cleared:Boolean=org.flashNight.arki.scene.BookDefinition.isCf6Route(run.routeId) && run.outcome === "victory" && run.debug !== true;
            var historicalTime:Number=Number(run.elapsedMs);
            cleared=cleared && !isNaN(historicalTime) && isFinite(historicalTime) && historicalTime > 0 && historicalTime < 86400000;
            var oldBest:Number=Number(previous.bestMs || 0);
            if (isNaN(oldBest) || oldBest < 0 || oldBest >= 86400000) oldBest=0;
            return {sp:0,firstClear:previous.firstClear === true || cleared,bestTier:0,
                bestMs:cleared && (oldBest == 0 || historicalTime < oldBest) ? historicalTime : oldBest,
                reason:cleared ? "clear" : "incomplete"};
        }
        var c:Object = org.flashNight.arki.scene.BookDefinition.get("repair-campus");
        var first:Boolean = previous.firstClear === true;
        var best:Number = Number(previous.bestTier || 0), bestMs:Number = Number(previous.bestMs || 0);
        var elapsed:Number = Number(run.elapsedMs);
        if (isNaN(best) || Math.floor(best) != best || best < 0 || best > c.recordMinutes.length) best = 0;
        if (isNaN(bestMs) || bestMs < 0 || bestMs >= 86400000) bestMs = 0;
        var sp:Number = 0, tier:Number = 0;
        if (run.outcome == "victory" && run.debug !== true && run.bookId == c.id
            && !isNaN(elapsed) && elapsed > 0 && elapsed < 86400000) {
            for (var i:Number = 0; i < c.recordMinutes.length; i++)
                if (elapsed <= c.recordMinutes[i] * 60000) tier = i + 1;
            sp = !first || bestMs == 0 || elapsed < bestMs ? c.recordSp : c.regularSp;
            first = true; best = Math.max(best, tier);
            if (bestMs == 0 || elapsed < bestMs) bestMs = elapsed;
        }
        return {sp:sp, firstClear:first, bestTier:best, bestMs:bestMs,
            reason:sp == 0 ? (run.debug === true ? "debug" : "incomplete")
                : previous.firstClear !== true ? "first_clear"
                : sp == c.recordSp ? "personal_best" : "clear"};
    }

    /** 保存简短战绩；不把临时角色或其装备复制回原档。 */
    public static function resultRecord(run:Object, quote:Object, completedAt:Number):Object {
        var elapsed:Number = Number(run.elapsedMs);
        if (isNaN(elapsed) || elapsed < 0 || elapsed >= 86400000) elapsed = 0;
        var outcome:String = String(run.outcome);
        if (outcome != "victory" && outcome != "failure" && outcome != "defeat" && outcome != "retreat") outcome = "abandoned";
        var record:Object = {runId:String(run.slot), bookId:String(run.bookId), outcome:outcome,
            elapsedMs:Math.floor(elapsed), completedAt:completedAt, sp:quote.sp,
            reason:quote.reason, debug:run.debug === true};
        return record;
    }
}
