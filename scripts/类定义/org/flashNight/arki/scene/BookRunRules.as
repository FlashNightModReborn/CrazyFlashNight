/** 可复现的出怪计划和有限纪录奖励。纯规则不读取或改写玩家状态。 */
class org.flashNight.arki.scene.BookRunRules {
    private static function next(state:Object):Number {
        state.value = (state.value * 48271) % 2147483647;
        return state.value / 2147483647;
    }
    private static function integer(state:Object, lo:Number, hi:Number):Number {
        return lo + Math.floor(next(state) * (hi - lo + 1));
    }
    public static function stages(seed:Number, startAt:Number):Array {
        var config:Object = org.flashNight.arki.scene.BookDefinition.get();
        var state:Object = {value:seed};
        if (isNaN(seed) || seed < 1 || seed >= 2147483647 || Math.floor(seed) != seed) state.value = 1;
        var result:Array = [];
        var economy:Object = config.loot;
        var supportIndex:Number = 0;
        for (var i:Number = 0; i < config.maps.length; i++) {
            var map:Object = config.maps[i], waves:Array = [];
            var choice:Object = null;
            for (var c:Number = 0; c < config.buildChoices.length; c++) {
                if (config.buildChoices[c].afterMap == i) choice = config.buildChoices[c];
            }
            var armorOffset:Number = integer(state, 0, map.armor.length - 1);
            for (var w:Number = 0; w < map.waves; w++) {
                var loot:String = map.equipment[integer(state, 0, map.equipment.length - 1)];
                var supply:String = config.supplies[integer(state, 0, config.supplies.length - 1)];
                // 首波及第三波提供比例急救；中间一波保留随机增益，复用原补给位。
                var medical:Boolean = w % 2 == 0;
                if (medical) supply = economy.medicalItem;
                var enemyType:Number = map.enemies[integer(state, 0, map.enemies.length - 1)];
                var enemyLevel:Number = integer(state, map.level[0], map.level[1]);
                var quantity:Number = integer(state, map.count[0], map.count[1]);
                // 每波一名敌人携带整波配给；一堆可装多份药品/弹药，不再每敌人散落六堆。
                // 经验总预算保持不变，且不随出怪数量或随机装备抽签减少。
                var experience:Number = Math.ceil(map.experience / map.waves);
                var support:Object = economy.support[supportIndex % economy.support.length];
                var supportName:String = support.kind == "mana" ? map.manaItem : support.name;
                supportIndex++;
                var carrier:Object = {
                    Type:"兵种" + enemyType, Level:enemyLevel,
                    Quantity:1, Interval:900, Delay:(quantity - 1) * 900, SpawnIndex:"right",
                    Parameters:{掉落物:[{名字:loot, 概率:economy.equipmentChance, 最小数量:1, 最大数量:1, 总数:1},
                        {名字:supply, 概率:medical ? 100 : economy.supplyChance, 最小数量:1, 最大数量:1, 总数:1},
                        // 敌人先查物品字典，必须使用“金币”；显示名“金钱”会被跳过。
                        {名字:economy.moneyItem, 概率:100, 最小数量:map.money[0], 最大数量:map.money[1], 总数:map.money[1]},
                        {名字:economy.experienceItem, 概率:100, 最小数量:experience, 最大数量:experience, 总数:experience},
                        {名字:map.healingItem, 概率:100, 最小数量:economy.healingCount, 最大数量:economy.healingCount, 总数:economy.healingCount},
                        {名字:supportName, 概率:100, 最小数量:support.count, 最大数量:support.count, 总数:support.count}]}
                };
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
                    carrier.Parameters.掉落物.push({名字:material.name, 概率:100,
                        最小数量:material.count, 最大数量:material.count, 总数:material.count});
                }
                // 末波一个自选配给包；打开后冻结候选，选定整套物资进入持久暂存。
                if (choice != null && w == map.waves - 1) carrier.Parameters.掉落物.push({
                    名字:choice.choiceItem, 概率:100, 最小数量:1, 最大数量:1, 总数:1});
                var enemies:Array = [];
                if (quantity > 1) enemies.push({Type:"兵种" + enemyType, Level:enemyLevel,
                    Quantity:quantity - 1, Interval:900, SpawnIndex:"right", Parameters:{掉落物:[]}});
                enemies.push(carrier);
                waves.push({WaveInformation:{Duration:0}, EnemyGroup:{Enemy:enemies}});
            }
            var trainer:Object = {};
            for (var s:Number = 0; s < config.skills.length; s++) trainer[String(s)] = config.skills[s];
            var stage:Object = {BasicInformation:{Background:"flashswf/backgrounds/" + map.background,
                    EndFrame:"房间", BGM:{Command:"play", Title:"Bulletproof", Loop:true}},
                Wave:{SubWave:waves}, Event:[{EventName:"Start", Callback:{Name:"书中章节", Parameter:[i]}, Message:"修理大学 · " + (i + 1) + "/7 · " + map.title
                    + (i == 0 ? "。先找迷之盔甲君选择武器和技能；初始 " + config.startingSkillPoints + " SP。弹药补给包需在背包打开并领取。" : "")
                    + (choice != null ? "。末波掉落自选配给包：从背包打开，三选一后到暂存物资领取。" : "")
                    + (i == 2 || i == 4 ? "。出发前可打开上图的自选配给包，在装备界面的自选礼包中选择一套武器、插件与补给。" : "")}],
                Instances:{Instance:[]}, Pickups:{Pickup:[]}};
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
        var c:Object = org.flashNight.arki.scene.BookDefinition.get();
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
            sp = c.regularSp + (first ? 0 : c.firstClearSp) + Math.max(0, tier - best) * c.recordSpPerTier;
            first = true; best = Math.max(best, tier);
            if (bestMs == 0 || elapsed < bestMs) bestMs = elapsed;
        }
        return {sp:sp, firstClear:first, bestTier:best, bestMs:bestMs};
    }
}
