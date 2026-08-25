import org.flashNight.arki.merc.ArenaDropRuleCatalog;
import org.flashNight.arki.item.obtain.ItemObtainIndex;
import org.flashNight.gesh.tooltip.builder.ObtainMethodsBuilder;

/** 竞技场掉落规则、来源索引与通用装备 tooltip 的 focused 回归。 */
class org.flashNight.arki.merc.ArenaDropRuleCatalogTest {
    private static var passed:Number = 0;
    private static var failed:Number = 0;

    public static function runAllTests():Void {
        passed = 0;
        failed = 0;

        var catalog:Object = ArenaDropRuleCatalog.parse(makeRawCatalog());
        check(catalog != null && catalog.schemaVersion === 1
            && catalog.profiles.length == 1
            && catalog.sources.length == 8,
            "strict parser normalizes one profile and eight authored sources");

        var zhanSource:Object = findSource(catalog, "斩马刀");
        check(zhanSource != null
            && zhanSource.ruleId == "zhanmadao_guaranteed"
            && zhanSource.chanceModel == "arena_equipped_drop"
            && zhanSource.carrierScope == "carrier"
            && zhanSource.conditionalChancePercent === 100,
            "zhanmadao source is a guaranteed equipped drop");

        var weaponSource:Object = findSource(catalog, "巨兽");
        check(weaponSource != null
            && weaponSource.slot == "长枪"
            && weaponSource.conditionalChancePercent === 25,
            "gladiator weapon source retains nominal 25 percent");

        var armorSource:Object = findSource(catalog, "合金盔");
        check(armorSource != null
            && armorSource.chanceModel == "arena_weighted_slot_then_drop"
            && armorSource.selectionWeight === 1
            && armorSource.totalWeight === 7
            && armorSource.carrierScope == "specific_carrier"
            && armorSource.selectedDropChancePercent === 100
            && armorSource.conditionalChancePercent === 14.285714,
            "armor source retains one-of-seven slot selection semantics");

        var shortCircuitUnit:Object = makeGladiatorUnit();
        shortCircuitUnit.刀 = "斩马刀";
        var drops:Array = ArenaDropRuleCatalog.resolveDrops(catalog,
            "standard_merc", shortCircuitUnit, fixedRoll(0));
        check(drops.length == 1 && drops[0].名字 == "斩马刀"
            && drops[0].概率 === 100,
            "zhanmadao rule short-circuits the necklace rule exactly");

        drops = ArenaDropRuleCatalog.resolveDrops(catalog,
            "standard_merc", makeGladiatorUnit(), fixedRoll(0));
        check(drops.length == 3
            && drops[0].名字 == "巨兽" && drops[0].概率 === 25
            && drops[1].名字 == "冰魄斩" && drops[1].概率 === 25
            && drops[2].名字 == "合金盔" && drops[2].概率 === 100,
            "necklace rule emits two weapon entries then selected head armor");

        drops = ArenaDropRuleCatalog.resolveDrops(catalog,
            "standard_merc", makeGladiatorUnit(), fixedRoll(1));
        check(drops.length == 3 && drops[2].名字 == "合金甲",
            "lottery roll one selects body armor in authored physical order");

        drops = ArenaDropRuleCatalog.resolveDrops(catalog,
            "standard_merc", makeGladiatorUnit(), fixedRoll(2));
        check(drops.length == 3 && drops[2].名字 == "合金腿甲",
            "lottery roll two selects leg armor in authored physical order");

        drops = ArenaDropRuleCatalog.resolveDrops(catalog,
            "standard_merc", makeGladiatorUnit(), fixedRoll(5));
        check(drops.length == 2 && drops[0].名字 == "巨兽"
            && drops[1].名字 == "冰魄斩",
            "first empty lottery outcome suppresses armor without affecting weapons");

        drops = ArenaDropRuleCatalog.resolveDrops(catalog,
            "standard_merc", makeGladiatorUnit(), fixedRoll(6));
        check(drops.length == 2,
            "second empty lottery outcome preserves the old two-of-seven empty weight");

        var exactUnit:Object = makeGladiatorUnit();
        exactUnit.长枪 = "巨兽#2";
        exactUnit.刀 = "";
        drops = ArenaDropRuleCatalog.resolveDrops(catalog,
            "standard_merc", exactUnit, fixedRoll(5));
        check(drops.length == 0,
            "eligible equipment matching remains exact and does not broaden to encoded names");

        var encodedTrigger:Object = makeGladiatorUnit();
        encodedTrigger.刀 = "斩马刀#2";
        encodedTrigger.颈部装备 = "";
        drops = ArenaDropRuleCatalog.resolveDrops(catalog,
            "standard_merc", encodedTrigger, fixedRoll(0));
        check(drops.length == 0,
            "zhanmadao trigger remains exact as in the legacy branch");

        var noTrigger:Object = makeGladiatorUnit();
        noTrigger.颈部装备 = "新手军牌";
        drops = ArenaDropRuleCatalog.resolveDrops(catalog,
            "standard_merc", noTrigger, fixedRoll(0));
        check(drops.length == 0,
            "units without an authored trigger receive no arena equipment drops");

        drops = ArenaDropRuleCatalog.resolveDrops(catalog,
            "roster", makeGladiatorUnit(), fixedRoll(0));
        check(drops.length == 0,
            "unknown roster profile fails closed and cannot inherit standard drops");

        var badSchema:Object = makeRawCatalog();
        badSchema.schemaVersion = 2;
        check(ArenaDropRuleCatalog.parse(badSchema) == null,
            "unknown schema versions fail closed");

        var badField:Object = makeRawCatalog();
        badField.unexpected = true;
        check(ArenaDropRuleCatalog.parse(badField) == null,
            "unknown root fields fail closed");

        var missingSlotCoverage:Object = makeRawCatalog();
        missingSlotCoverage.Profile.Rule[1].EligibleItem.pop();
        check(ArenaDropRuleCatalog.parse(missingSlotCoverage) == null,
            "every executable slot requires an explicit eligible item set");

        var index:ItemObtainIndex = ItemObtainIndex.getInstance();
        index.reset(true);
        index.buildIndex(null, null, [], catalog);
        var indexed:Array = index.getExactObtainRecords("合金盔");
        check(indexed.length == 1
            && indexed[0].kind == ItemObtainIndex.KIND_DROP
            && indexed[0].dropType == ItemObtainIndex.DROP_TYPE_ARENA
            && indexed[0].arenaId == "death_match"
            && indexed[0].probability === 14.285714,
            "ItemObtainIndex projects a structured static arena source");

        index.clearDynamicDiscoveries();
        indexed = index.getExactObtainRecords("合金盔");
        check(indexed.length == 1
            && indexed[0].dropType == ItemObtainIndex.DROP_TYPE_ARENA,
            "clearing discoveries preserves authored arena sources");

        var carrierTooltip:String = ObtainMethodsBuilder.build("斩马刀").join("");
        var specificTooltip:String = ObtainMethodsBuilder.build("合金盔").join("");
        check(carrierTooltip.indexOf("竞技场：") >= 0
            && carrierTooltip.indexOf("携带该装备的佣兵") >= 0
            && carrierTooltip.indexOf("携带该装备的特定佣兵") < 0
            && specificTooltip.indexOf("竞技场：") >= 0
            && specificTooltip.indexOf("携带该装备的特定佣兵") >= 0
            && carrierTooltip.indexOf("DEATH MATCH") < 0
            && specificTooltip.indexOf("1/7") < 0,
            "shared TooltipComposer separates carrier and specific-carrier sources");

        index.reset(true);
        trace("ArenaDropRuleCatalogTest Tests Passed: " + passed);
        trace("ArenaDropRuleCatalogTest Tests Failed: " + failed);
    }

    private static function makeRawCatalog():Object {
        return {
            schemaVersion:1,
            Profile:{
                id:"standard_merc",
                arenaId:"death_match",
                arenaLabel:"DEATH MATCH",
                modeLabel:"标准佣兵对战",
                Rule:[
                    {
                        id:"zhanmadao_guaranteed",
                        stopOnMatch:true,
                        carrierScope:"carrier",
                        Trigger:{slot:"刀", item:"斩马刀"},
                        Drop:{slot:"刀", chancePercent:100},
                        EligibleItem:{name:"斩马刀", slot:"刀"}
                    },
                    {
                        id:"gladiator_equipment",
                        stopOnMatch:true,
                        carrierScope:"specific_carrier",
                        Trigger:[
                            {slot:"颈部装备", item:"角斗高手项链"},
                            {slot:"颈部装备", item:"角斗王者项链"}
                        ],
                        Drop:[
                            {slot:"长枪", chancePercent:25},
                            {slot:"刀", chancePercent:25}
                        ],
                        SlotLottery:{
                            dropChancePercent:100,
                            Choice:[
                                {slot:"头部装备", weight:1},
                                {slot:"上装装备", weight:1},
                                {slot:"下装装备", weight:1},
                                {slot:"手部装备", weight:1},
                                {slot:"脚部装备", weight:1},
                                {empty:true, weight:2}
                            ]
                        },
                        EligibleItem:[
                            {name:"巨兽", slot:"长枪"},
                            {name:"冰魄斩", slot:"刀"},
                            {name:"合金盔", slot:"头部装备"},
                            {name:"合金甲", slot:"上装装备"},
                            {name:"合金腿甲", slot:"下装装备"},
                            {name:"合金手套", slot:"手部装备"},
                            {name:"合金鞋", slot:"脚部装备"}
                        ]
                    }
                ]
            }
        };
    }

    private static function makeGladiatorUnit():Object {
        return {
            颈部装备:"角斗高手项链",
            长枪:"巨兽",
            刀:"冰魄斩",
            头部装备:"合金盔",
            上装装备:"合金甲",
            下装装备:"合金腿甲",
            手部装备:"合金手套",
            脚部装备:"合金鞋"
        };
    }

    private static function fixedRoll(value:Number):Function {
        return function(totalWeight:Number):Number { return value; };
    }

    private static function findSource(catalog:Object, itemName:String):Object {
        if (catalog == null || !(catalog.sources instanceof Array)) return null;
        for (var i:Number = 0; i < catalog.sources.length; i++) {
            if (catalog.sources[i].itemName === itemName) return catalog.sources[i];
        }
        return null;
    }

    private static function check(value:Boolean, label:String):Void {
        if (value) {
            passed++;
            trace("[PASS] " + label);
        } else {
            failed++;
            trace("[FAIL] " + label);
        }
    }
}
