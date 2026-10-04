import org.flashNight.arki.scene.BookRunRules;
import org.flashNight.arki.scene.BookDefinition;
class org.flashNight.arki.scene.BookRunRulesTest {
    private static var passed:Number;
    private static var failed:Number;
    private static function check(value:Boolean, message:String):Void {
        if (value) passed++; else { failed++; trace("[FAIL] BookRules: " + message); }
    }
    private static function findDrop(enemy:Object, name:String):Object {
        var rules:Array = enemy.Parameters.掉落物;
        for (var i:Number = 0; i < rules.length; i++) {
            if (rules[i].名字 == name) return rules[i];
        }
        return null;
    }
    private static function carrier(wave:Object):Object {
        var enemies:Array = wave.EnemyGroup.Enemy;
        return enemies[enemies.length - 1];
    }
    private static function testProgressionAndSupplies(plan:Array, config:Object):Void {
        var experienceValid:Boolean = true, moneyValid:Boolean = true;
        var healingValid:Boolean = true, supportValid:Boolean = true, budgetsValid:Boolean = true;
        var cumulative:Number = 0, milestones:Array = [];
        for (var m:Number = 0; m < plan.length; m++) {
            var waves:Array = plan[m].Wave.SubWave;
            var total:Number = 0, hasMana:Boolean = false, hasAmmo:Boolean = false, hasGrenades:Boolean = false;
            for (var w:Number = 0; w < waves.length; w++) {
                var enemy:Object = carrier(waves[w]);
                var xp:Object = findDrop(enemy, "经验值");
                experienceValid = experienceValid && xp != null && xp.概率 == 100
                    && xp.最小数量 > 0 && xp.最小数量 == xp.最大数量 && xp.总数 >= xp.最大数量;
                total += xp.最小数量 * enemy.Quantity;
                var money:Object = findDrop(enemy, "金币");
                moneyValid = moneyValid && money != null && findDrop(enemy, "金钱") == null
                    && money.概率 == 100 && money.最小数量 >= 1500 && money.总数 >= money.最大数量;
                var healing:Object = findDrop(enemy, config.maps[m].healingItem);
                healingValid = healingValid && healing != null && healing.概率 == 100
                    && healing.最小数量 >= 3 && healing.总数 >= healing.最大数量;
                var mana:Object = findDrop(enemy, config.maps[m].manaItem);
                var ammo:Object = findDrop(enemy, config.ammoBundle.name);
                if (mana != null && mana.概率 == 100 && mana.最小数量 >= 1) hasMana = true;
                if (ammo != null && ammo.概率 == 100 && ammo.最小数量 == 1 && ammo.总数 == 1) hasAmmo = true;
                var grenades:Object = findDrop(enemy, "普通手雷");
                if (grenades != null && grenades.概率 == 100 && grenades.最小数量 >= 4) hasGrenades = true;
            }
            supportValid = supportValid && (waves.length < 3 || (hasMana && hasAmmo && hasGrenades));
            budgetsValid = budgetsValid && total >= config.maps[m].experience
                && total < config.maps[m].experience + waves.length;
            cumulative += total; milestones.push(cumulative);
        }
        check(experienceValid, "each wave carries one guaranteed concentrated XP pickup with sufficient total cap");
        check(moneyValid, "currency uses the real item dictionary key and covers basic consumables");
        check(healingValid, "healing potions are independent of random instant buffs");
        check(supportValid, "each regular map guarantees mana, magazines and grenades before the next encounter tier");
        check(budgetsValid, "map XP budget survives variable enemy counts within rounding only");
        // 当前正式升级曲线的累计门槛：6 级 8625，9 级 53748，15 级 499908。
        check(milestones[0] >= 8625, "first map pickup budget unlocks the baseball bat");
        check(milestones[1] >= 53748, "second map pickup budget unlocks the military knife");
        check(milestones[5] >= 499908, "all candidate gear is usable before the boss");
        var acrossSeeds:Boolean = true;
        for (var seed:Number = 1; seed <= 64; seed++) {
            var generated:Array = BookRunRules.stages(seed * 7919, 0);
            for (m = 0; m < generated.length; m++) {
                var earned:Number = 0, count:Number = 0;
                waves = generated[m].Wave.SubWave;
                for (w = 0; w < waves.length; w++) {
                    enemy = carrier(waves[w]);
                    earned += findDrop(enemy, "经验值").最小数量 * enemy.Quantity;
                    count += enemy.Quantity;
                }
                acrossSeeds = acrossSeeds && earned >= config.maps[m].experience
                    && earned < config.maps[m].experience + count;
            }
        }
        check(acrossSeeds, "64 different spawn plans preserve every map growth budget");
    }
    private static function testSurvivalChoices(plan:Array, config:Object):Void {
        var armorValid:Boolean = true, differentArmor:Boolean = true, medicalValid:Boolean = true;
        var randomBuffValid:Boolean = true, trainerValid:Boolean = true;
        for (var m:Number = 0; m < plan.length; m++) {
            var map:Object = config.maps[m], waves:Array = plan[m].Wave.SubWave;
            var previousArmor:String = "";
            for (var w:Number = 0; w < waves.length; w++) {
                var enemy:Object = carrier(waves[w]);
                var armorCount:Number = 0, armorName:String = "";
                for (var a:Number = 0; a < map.armor.length; a++) {
                    var armor:Object = findDrop(enemy, map.armor[a]);
                    if (armor != null) {
                        armorCount++; armorName = armor.名字;
                        armorValid = armorValid && armor.概率 == 100 && armor.最小数量 == 1
                            && armor.最大数量 == 1 && armor.总数 == 1;
                    }
                }
                armorValid = armorValid && armorCount == (w < 2 ? 1 : 0);
                if (w == 1) differentArmor = differentArmor && armorName != previousArmor;
                previousArmor = armorName;
                var emergency:Object = findDrop(enemy, "战场复合急救包");
                if (w % 2 == 0) medicalValid = medicalValid && emergency != null
                    && emergency.概率 == 100 && emergency.最小数量 == 1 && emergency.总数 == 1;
                else {
                    var hasBuff:Boolean = false;
                    for (var b:Number = 0; b < config.supplies.length; b++) {
                        var buff:Object = findDrop(enemy, config.supplies[b]);
                        if (buff != null && buff.概率 == 25) hasBuff = true;
                    }
                    randomBuffValid = randomBuffValid && emergency == null && hasBuff;
                }
            }
            var trainer:Object = plan[m].Instances.Instance[0].Parameters.可学的技能;
            for (var s:Number = 0; s < config.skills.length; s++)
                trainerValid = trainerValid && trainer[String(s)] == config.skills[s];
            var count:Number = 0;
            for (var key:String in trainer) count++;
            trainerValid = trainerValid && count == config.skills.length;
        }
        check(armorValid, "first two waves guarantee one armor each independently of weapon rolls");
        check(differentArmor, "two guaranteed armor pieces in a map are different choices");
        check(medicalValid, "first and third waves guarantee exactly one compound emergency pickup");
        check(randomBuffValid, "middle waves retain the random battlefield buff slot");
        check(trainerValid && config.skills.length == 36, "every map exposes only the 36 curated skills through level fifteen");
        check(config.maps[0].healingItem == "普通hp药剂" && config.maps[2].healingItem == "加强抗生素药剂"
            && config.maps[5].healingItem == "大HP药剂" && config.maps[5].manaItem == "大MP药剂",
            "carried medicines progress from early supplies to late HP and MP recovery");
    }
    private static function testBuildResources(plan:Array, config:Object):Void {
        var spValid:Boolean = true, materialValid:Boolean = true, sequenceValid:Boolean = true;
        var medValid:Boolean = true;
        var spTotal:Number = 0, tierTotal:Number = 0, stoneTotal:Number = 0;
        var hp:Array = ["普通hp药剂", "普通hp药剂", "加强抗生素药剂", "加强抗生素药剂", "大HP药剂", "大HP药剂", "大HP药剂"];
        var mp:Array = ["普通mp药剂", "普通mp药剂", "加强mp药剂", "加强mp药剂", "大MP药剂", "大MP药剂", "大MP药剂"];
        var types:Array = [[44,45], [48,49], [447,448], [436,437], [449,450], [444,446], [455]];
        for (var m:Number = 0; m < plan.length; m++) {
            var waves:Array = plan[m].Wave.SubWave, map:Object = config.maps[m];
            for (var w:Number = 0; w < waves.length; w++) {
                var enemy:Object = carrier(waves[w]);
                sequenceValid = sequenceValid && (enemy.Type == "兵种" + types[m][0]
                    || enemy.Type == "兵种" + types[m][1]);
                var sp:Object = findDrop(enemy, "技能点");
                if (m < 6 && w == 0) {
                    spValid = spValid && sp != null && sp.概率 == 100
                        && sp.最小数量 == map.skillPoints && sp.最大数量 == sp.最小数量
                        && sp.总数 == sp.最小数量;
                    spTotal += sp.最小数量;
                } else spValid = spValid && sp == null;
                medValid = medValid && findDrop(enemy, hp[m]) != null
                    && (w != 0 || findDrop(enemy, mp[m]) != null);
                if (w < map.materials.length) {
                    var material:Object = map.materials[w];
                    var drop:Object = findDrop(enemy, material.name);
                    materialValid = materialValid && drop != null && drop.概率 == 100
                        && drop.最小数量 == material.count && drop.最大数量 == material.count
                        && drop.总数 == material.count;
                    if (drop.名字 == "二阶复合防御组件") tierTotal += drop.最小数量;
                    if (drop.名字 == "强化石") stoneTotal += drop.最小数量;
                }
            }
        }
        check(sequenceValid, "both student factions precede military students and sword club");
        check(config.maps[4].level[0] == 5 && config.maps[4].level[1] == 7,
            "moving military later does not silently raise their existing levels");
        check(medValid, "actual pickup plans use small then medium then large HP and MP potions");
        check(spValid && spTotal == 360, "360 local SP in six guaranteed single stacks before the boss");
        check(materialValid, "material quotas are guaranteed exact stacks through the normal pickup path");
        check(tierTotal == 5 && stoneTotal == 78, "five tier components and 78 enhancement stones support local tuning");
        var unchanged:Array = BookRunRules.stages(1729, 0);
        var itemName:String = config.maps[0].materials[0].name;
        findDrop(carrier(unchanged[0].Wave.SubWave[0]), itemName).总数 = 0;
        check(findDrop(carrier(plan[0].Wave.SubWave[0]), itemName).总数 == 3,
            "consuming a material stack never depletes another generated plan");
    }
    private static function testLoadoutChoices(plan:Array, config:Object):Void {
        var exact:Boolean = true, count:Number = 0;
        for (var c:Number = 0; c < config.buildChoices.length; c++) {
            var choice:Object = config.buildChoices[c];
            for (var m:Number = 0; m < plan.length; m++) {
                var waves:Array = plan[m].Wave.SubWave;
                for (var w:Number = 0; w < waves.length; w++) {
                    var voucher:Object = findDrop(carrier(waves[w]), choice.choiceItem);
                    var expected:Boolean = m == choice.afterMap && w == waves.length - 1;
                    exact = exact && ((voucher != null) == expected);
                    if (voucher != null) {
                        count++;
                        exact = exact && voucher.概率 == 100 && voucher.最小数量 == 1
                            && voucher.最大数量 == 1 && voucher.总数 == 1;
                    }
                }
            }
        }
        check(exact && count == 2, "only two single-use vouchers appear, at the second and fourth map finales");
        check(config.startingSkillPoints == 120, "initial SP allows an early build without taking from the original character");
        var seedIndependent:Boolean = true;
        for (var seed:Number = 1; seed <= 64; seed++) {
            var other:Array = BookRunRules.stages(seed * 7919, 0);
            for (c = 0; c < config.buildChoices.length; c++) {
                choice = config.buildChoices[c];
                waves = other[choice.afterMap].Wave.SubWave;
                seedIndependent = seedIndependent && findDrop(carrier(waves[waves.length - 1]), choice.choiceItem).总数 == 1;
            }
        }
        check(seedIndependent, "equipment RNG cannot remove or multiply either build opportunity");
        var jump:Array = BookRunRules.stages(1729, 4);
        var noPastVouchers:Boolean = true;
        for (m = 0; m < jump.length; m++) {
            waves = jump[m].Wave.SubWave;
            for (w = 0; w < waves.length; w++) for (c = 0; c < config.buildChoices.length; c++)
                noPastVouchers = noPastVouchers && findDrop(carrier(waves[w]), config.buildChoices[c].choiceItem) == null;
        }
        check(noPastVouchers, "a debug map jump does not reissue earlier checkpoint vouchers");
    }
    public static function runAllTests():Void {
        passed = 0; failed = 0;
        var codec:LiteJSON = new LiteJSON();
        var first:Array = BookRunRules.stages(1729, 0);
        var same:Array = BookRunRules.stages(1729, 0);
        var changed:Array = BookRunRules.stages(1730, 0);
        check(first.length == 7, "seven maps");
        check(codec.stringifySafe(first) == codec.stringifySafe(same), "seed reproduces complete spawn plan");
        check(codec.stringifySafe(first) != codec.stringifySafe(changed), "different seed changes plan");
        check(codec.stringifySafe(BookRunRules.stages(1729, 6)[0]) == codec.stringifySafe(first[6]), "boss jump preserves plan");
        var config:Object = BookDefinition.get();
        check(BookDefinition.valid(config), "runtime config accepts generated data");
        var broken:Object = org.flashNight.gesh.object.PersistedSnapshot.clone(config);
        broken.maps[0].background = "../outside.swf";
        check(!BookDefinition.valid(broken), "runtime config rejects traversal");
        broken = org.flashNight.gesh.object.PersistedSnapshot.clone(config); broken.maps[0].count = [0, 999];
        check(!BookDefinition.valid(broken), "runtime config rejects malformed spawn range");
        check(BookDefinition.accept(config) && BookDefinition.ready(), "validated data unlocks runtime entry");
        var waveCount:Number = 0;
        var bounded:Boolean = true, drops:Boolean = true, services:Boolean = true, concentrated:Boolean = true;
        var priorDropSlots:Number = 0, currentDropSlots:Number = 0, cadence:Boolean = true;
        for (var m:Number = 0; m < first.length; m++) {
            var map:Object = config.maps[m];
            services = services && first[m].Instances.Instance[0].Parameters.商店检索名 == "书中-迷之盔甲君";
            var waves:Array = first[m].Wave.SubWave;
            for (var w:Number = 0; w < waves.length; w++) {
                waveCount++;
                var group:Array = waves[w].EnemyGroup.Enemy;
                var quantity:Number = 0, carriers:Number = 0;
                var spawnTimes:Array = [];
                for (var g:Number = 0; g < group.length; g++) {
                    quantity += group[g].Quantity;
                    bounded = bounded && group[g].Level >= map.level[0] && group[g].Level <= map.level[1];
                    var slots:Number = group[g].Parameters.掉落物.length;
                    currentDropSlots += slots * group[g].Quantity;
                    if (slots > 0) { carriers++; concentrated = concentrated && group[g].Quantity == 1; }
                    for (var n:Number = 0; n < group[g].Quantity; n++)
                        spawnTimes.push(Number(group[g].Delay || 0) + (n + 1) * group[g].Interval);
                }
                spawnTimes.sort(Array.NUMERIC);
                for (var t:Number = 0; t < spawnTimes.length; t++) cadence = cadence && spawnTimes[t] == (t + 1) * 900;
                concentrated = concentrated && carriers == 1;
                priorDropSlots += map.count[0] * 6;
                bounded = bounded && quantity >= map.count[0] && quantity <= map.count[1];
                var enemy:Object = carrier(waves[w]);
                var expectedSlots:Number = 6 + (w < config.loot.armorWaves ? 1 : 0)
                    + (w == 0 && map.skillPoints > 0 ? 1 : 0) + (w < map.materials.length ? 1 : 0)
                    + ((m == 1 || m == 3) && w == map.waves - 1 ? 1 : 0);
                drops = drops && enemy.Parameters.掉落物.length == expectedSlots
                    && findDrop(enemy, "金币") != null;
            }
        }
        check(waveCount == 19 && bounded, "nineteen bounded waves");
        check(drops, "carrier adds at most one armor, one material and one map SP stack to existing supplies");
        check(concentrated, "exactly one carrier per wave including the single-enemy boss");
        check(cadence, "splitting the carrier preserves the original 900ms arrival cadence without a double spawn");
        check(currentDropSlots == 153 && currentDropSlots < priorDropSlots * 0.7,
            "bundled ammunition and two build vouchers keep pickup rules below seventy percent of the minimum old scatter");
        check(services, "each stage exposes existing shop and skill service");
        check(first[6].Wave.SubWave[0].EnemyGroup.Enemy[0].Type == "兵种455", "physical teacher boss");
        first[0].Wave.SubWave[0].EnemyGroup.Enemy[0].Quantity = 999;
        check(same[0].Wave.SubWave[0].EnemyGroup.Enemy[0].Quantity != 999, "plans do not alias");
        testProgressionAndSupplies(same, config);
        testSurvivalChoices(same, config);
        testBuildResources(same, config);
        testLoadoutChoices(same, config);
        findDrop(carrier(first[0].Wave.SubWave[0]), "经验值").总数 = 0;
        check(findDrop(carrier(same[0].Wave.SubWave[0]), "经验值").总数 > 0
                && findDrop(carrier(first[0].Wave.SubWave[1]), "经验值").总数 > 0,
            "consuming one XP drop does not deplete other waves or plans");
        var run:Object = {bookId:"repair-campus",outcome:"victory",elapsedMs:31 * 60000};
        var quote:Object = BookRunRules.reward(run, {});
        check(quote.sp == 60 && quote.firstClear && quote.bestTier == 0, "first clear plus regular reward");
        quote = BookRunRules.reward(run, {firstClear:true,bestTier:0});
        check(quote.sp == 30, "ordinary clear");
        run.elapsedMs = 20 * 60000;
        quote = BookRunRules.reward(run, {});
        check(quote.sp == 75 && quote.bestTier == 3, "first clear reaches all three finite records");
        quote = BookRunRules.reward(run, {firstClear:true,bestTier:3,bestMs:19 * 60000});
        check(quote.sp == 30 && quote.bestMs == 19 * 60000, "record cannot be farmed again");
        quote = BookRunRules.reward(run, {firstClear:true,bestTier:1});
        check(quote.sp == 40, "only unearned record tiers return");
        run.outcome = "defeat";
        quote = BookRunRules.reward(run, {});
        check(quote.sp == 0 && !quote.firstClear && quote.bestTier == 0, "defeat neither pays nor consumes first clear");
        run.outcome = "abandoned";
        check(BookRunRules.reward(run, {}).sp == 0, "abandon has zero reward");
        run.outcome = "active";
        check(BookRunRules.reward(run, {}).sp == 0, "interrupted active run has zero reward");
        run.outcome = "victory"; run.debug = true;
        check(BookRunRules.reward(run, {}).sp == 0, "debug boss jump has zero reward");
        run.debug = false; run.bookId = "another-book";
        check(BookRunRules.reward(run, {}).sp == 0, "foreign book result rejected");
        run.bookId = "repair-campus";
        run.elapsedMs = Number.NaN;
        check(BookRunRules.reward(run, {}).sp == 0, "NaN time rejected in real AS2");
        run.elapsedMs = 0;
        check(BookRunRules.reward(run, {}).sp == 0, "zero time rejected");
        run.elapsedMs = 86400000;
        check(BookRunRules.reward(run, {}).sp == 0, "stale day-long result rejected");
        check(codec.stringifySafe(BookRunRules.stages(Number.NaN, 0)) == codec.stringifySafe(BookRunRules.stages(1, 0)), "invalid seed normalized");
        trace("BookRunRulesTest Tests Passed: " + passed);
        trace("BookRunRulesTest Tests Failed: " + failed);
    }
}
