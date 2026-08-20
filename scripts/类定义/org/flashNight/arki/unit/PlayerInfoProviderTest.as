
import org.flashNight.arki.unit.UnitComponent.Initializer.DressupInitializer;
import org.flashNight.arki.component.StatHandler.ImpactHandler;
import org.flashNight.arki.component.StatHandler.DamageResistanceHandler;

/** PlayerInfoProvider 结构化 snapshot 与 legacy renderer 回归。 */
class org.flashNight.arki.unit.PlayerInfoProviderTest {
    private static var _passed:Number = 0;
    private static var _failed:Number = 0;
    private static var _hero:MovieClip;
    private static var _oldGameworld:Object;
    private static var _oldControlTarget;
    private static var _oldHeight;
    private static var _oldLevel;
    private static var _oldExperience;
    private static var _oldKillStats;
    private static var _oldLevelFormula:Function;

    public static function runAllTests():Void {
        _passed = 0;
        _failed = 0;
        trace("=== PlayerInfoProviderTest start ===");

        installFixture();
        testTenacityFormulaAndDerivedState();
        testDressupProjectionIsIdempotent();
        testStructuredShapeOrderAndRawValues();
        testStyledTitleProjection();
        testLegacyRendererParity();
        testExtremeAndInvalidNumbers();
        testMissingHeroFailsClosed();
        restoreFixture();

        trace("PlayerInfoProviderTest Tests Passed: " + _passed);
        trace("PlayerInfoProviderTest Tests Failed: " + _failed);
        trace("=== PlayerInfoProviderTest end ===");
    }

    private static function check(condition:Boolean, message:String):Void {
        if (condition) {
            _passed++;
            trace("[PASS] " + message);
        } else {
            _failed++;
            trace("[FAIL] " + message);
        }
    }

    private static function installFixture():Void {
        _oldGameworld = _root.gameworld;
        _oldControlTarget = _root.控制目标;
        _oldHeight = _root.身高;
        _oldLevel = _root.等级;
        _oldExperience = _root.经验值;
        _oldKillStats = _root.killStats;
        _oldLevelFormula = _root.根据等级计算值;

        _hero = _root.createEmptyMovieClip(
            "__playerInfoProviderTestHero", _root.getNextHighestDepth());
        _root.gameworld = {};
        _root.gameworld[_hero._name] = _hero;
        _root.控制目标 = _hero._name;
        _root.身高 = 188;
        _root.等级 = 50;
        _root.经验值 = 7654321;
        _root.killStats = {total:123456};
        _root.根据等级计算值 = function(minValue:Number, maxValue:Number,
                                             level:Number):Number {
            return minValue + (maxValue - minValue) * level / 100;
        };

        _hero.等级 = 50;
        _hero.体重 = 82;
        _hero.重量 = 20;
        _hero.称号 = "结构化观察者";
        _hero.hp满血值 = 987654;
        _hero.mp满血值 = 4321;
        _hero.内力 = 77;
        _hero.hp = 765432;
        _hero.防御力 = 2468.9;
        _hero.基本防御力 = 1200.9;
        _hero.装备防御力 = 1268.9;
        _hero.装备防御力加成 = 37.8;
        _hero.damageTakenMultiplier = 0.75;
        _hero.魔法抗性 = {
            基础:31.9, 热:32.9, 蚀:33.9, 毒:34.9,
            冷:35.9, 电:36.9, 波:37.9, 冲:38.9
        };
        _hero.韧性系数 = 1.5;
        _hero.躲闪率 = 0.8;
        _hero.命中率 = 12.34;
        _hero.懒闪避 = 0.27;
        _hero.行走X速度 = 4.56;
        _hero.伤害加成 = 19.8;
        _hero.空手攻击力 = 210;
        _hero.空手攻击力_min = 100;
        _hero.空手攻击力_max = 200;
        _hero.装备刀锋利度加成 = 4.5;
        _hero.装备枪械威力加成 = 6.5;
        _hero.基础毒 = 3;
        _hero.空手毒 = 4;
        _hero.兵器毒 = 5;
        _hero.手雷毒 = 6;
        _hero.淬毒 = 8;
        _hero.刀属性 = {power:80};
        _hero.手雷属性 = {power:90};
        _hero.手枪属性 = null;
        _hero.手枪2属性 = null;
        _hero.长枪属性 = null;
    }

    private static function restoreFixture():Void {
        _root.gameworld = _oldGameworld;
        _root.控制目标 = _oldControlTarget;
        _root.身高 = _oldHeight;
        _root.等级 = _oldLevel;
        _root.经验值 = _oldExperience;
        _root.killStats = _oldKillStats;
        _root.根据等级计算值 = _oldLevelFormula;
        if (_hero) _hero.removeMovieClip();
        _hero = null;
    }

    private static function makeLegacyTarget(sentinel):MovieClip {
        var depth:Number = _hero.getNextHighestDepth();
        var target:MovieClip = _hero.createEmptyMovieClip(
            "__playerInfoLegacyTarget" + depth, depth);
        target.负重滑块 = {};
        if (sentinel !== undefined) target.sentinel = sentinel;
        return target;
    }

    private static function testTenacityFormulaAndDerivedState():Void {
        var expectedCap:Number = _hero.韧性系数 * _hero.hp
            / DamageResistanceHandler.defenseDamageRatio(_hero.防御力);
        var observedCap:Number = org.flashNight.arki.unit.PlayerInfoProvider
            .getTenacityLimitValue(_hero);
        var expectedStagger:Number = expectedCap / 2 / _hero.躲闪率;

        _hero.remainingImpactForce = expectedCap / 4;
        ImpactHandler.refreshImpactDerived(_hero);
        check(Math.abs(observedCap - expectedCap) < 0.0001
                && Math.abs(_hero.韧性上限 - expectedCap) < 0.0001,
            "个人信息与战斗使用完整防御力及同一韧性上限公式");
        check(Math.abs(org.flashNight.arki.unit.PlayerInfoProvider
                    .getStaggerTenacityValue(_hero) - expectedStagger) < 0.0001
                && Math.abs(_hero.impactStaggerBoundary - expectedStagger) < 0.0001
                && Math.abs(_hero.nonlinearMappingResilience - 0.5) < 0.0001,
            "踉跄阈值与韧性条派生字段共享当前权威属性");

        _hero.remainingImpactForce = expectedCap * 4;
        ImpactHandler.refreshImpactDerived(_hero);
        check(_hero.nonlinearMappingResilience == 0,
            "冲击残量越过上限时韧性条夹到零而不产生 NaN/负宽度");
        _hero.remainingImpactForce = 0;
        ImpactHandler.refreshImpactDerived(_hero);

        var originalDefense:Number = _hero.防御力;
        _hero.防御力 = -999;
        var normalizedCap:Number = _hero.韧性系数 * _hero.hp
            / DamageResistanceHandler.defenseDamageRatio(1);
        check(Math.abs(ImpactHandler.calculateImpactCap(_hero) - normalizedCap) < 0.0001,
            "异常非正防御与实际伤害链统一归一到1");
        _hero.防御力 = originalDefense;

        // focused TestLoader 的帧计时器外壳不接受属性写入；本用例临时替换并完整恢复。
        var originalFrameTimer = _root.帧计时器;
        var currentFrame:Number = 1000;
        _root.帧计时器 = {当前帧数:currentFrame};
        var missTarget:Object = {
            hp:100, 防御力:300, 韧性系数:1, 躲闪率:1,
            remainingImpactForce:50, lastHitTime:currentFrame - 300
        };
        ImpactHandler.refreshImpactForce(missTarget, false);
        check(missTarget.remainingImpactForce == 0
                && missTarget.lastHitTime == currentFrame - 300,
            "MISS 推进既有冲击衰减但不重置残留窗口"
                + " remaining=" + missTarget.remainingImpactForce
                + " last=" + missTarget.lastHitTime + " current=" + currentFrame);

        missTarget.remainingImpactForce = 50;
        missTarget.lastHitTime = currentFrame - 300;
        ImpactHandler.refreshImpactForce(missTarget, true);
        check(missTarget.remainingImpactForce == 0
                && missTarget.lastHitTime == currentFrame,
            "真实命中在衰减旧残量后刷新冲击残留窗口"
                + " remaining=" + missTarget.remainingImpactForce
                + " last=" + missTarget.lastHitTime + " current=" + currentFrame);
        _root.帧计时器 = originalFrameTimer;
    }

    private static function testDressupProjectionIsIdempotent():Void {
        var target:MovieClip = _root.createEmptyMovieClip(
            "__dressupProjectionTest", _root.getNextHighestDepth());
        target.等级 = 50;
        target.体重 = 70;
        target.是否为敌人 = false;
        target.hp基本满血值 = 1000;
        target.mp基本满血值 = 100;
        target.基本防御力 = 300;
        target.基础命中率 = 10;
        target.基础韧性系数 = 1.2;
        target.基础躲闪率 = 5;
        target.攻击模式 = "空手";
        target.area = {_height:1};
        target._yscale = 100;
        target.根据模式重新读取武器加成 = function(mode:String):Void {};

        var dataKeys:Array = [
            "头部装备数据", "上装装备数据", "手部装备数据", "下装装备数据",
            "脚部装备数据", "颈部装备数据", "长枪数据", "手枪数据",
            "手枪2数据", "刀数据", "手雷数据"
        ];
        for (var i:Number = 0; i < dataKeys.length; i++) {
            target[dataKeys[i]] = {data:{}};
        }
        target.上装装备数据 = {
            data:{hp:100, mp:20, toughness:50, evasion:5}
        };

        DressupInitializer.updateProperties(target);
        var firstToughness:Number = target.韧性系数;
        var firstDodge:Number = target.躲闪率;
        var firstHpMax:Number = target.hp满血值;
        var firstMpMax:Number = target.mp满血值;
        DressupInitializer.updateProperties(target);

        check(Math.abs(firstToughness - 2.04) < 0.0001
                && Math.abs(target.韧性系数 - firstToughness) < 0.0001
                && Math.abs(firstDodge - (5 / 1.05)) < 0.0001
                && Math.abs(target.躲闪率 - firstDodge) < 0.0001,
            "重复装扮刷新始终从基础韧性/躲闪投影，不发生乘算漂移");
        check(firstHpMax == 3300 && target.hp满血值 == firstHpMax
                && firstMpMax == 12 && target.mp满血值 == firstMpMax,
            "佣兵 HP×3 与 MP/10 在装备投影内一次性且可重复");
        target.removeMovieClip();
    }

    private static function expectedKeys():Array {
        return [
            "height", "bodyWeight", "killCount", "title", "level", "experience",
            "equipmentWeight", "lightMediumThreshold", "mediumHeavyThreshold",
            "heavyThreshold", "weightRatio", "encumbranceState",
            "maxHp", "maxMp", "innerPower",
            "energyResistance", "heatResistance", "corrosionResistance",
            "poisonResistance", "coldResistance", "lightningResistance",
            "waveResistance", "impactResistance",
            "totalDefense", "baseDefense", "equipmentDefense",
            "equipmentDefenseBonus", "damageReduction",
            "tenacityLimit", "staggerTenacity", "guardBreakAbility",
            "stabilityAbility", "accuracy", "evasionCost", "lazyDodge",
            "movementSpeed", "damageBonus", "unarmedBonus", "unarmedAttack",
            "meleeBonus", "firearmBonus", "unarmedPower", "meleePower",
            "mainHandPower", "offHandPower", "riflePower", "grenadePower"
        ];
    }

    private static function flattenRows(snapshot:Object):Array {
        var result:Array = [];
        for (var i:Number = 0; i < snapshot.groups.length; i++) {
            var rows:Array = snapshot.groups[i].rows;
            for (var j:Number = 0; j < rows.length; j++) result.push(rows[j]);
        }
        return result;
    }

    private static function findRow(snapshot:Object, key:String):Object {
        var rows:Array = flattenRows(snapshot);
        for (var i:Number = 0; i < rows.length; i++) {
            if (rows[i].key == key) return rows[i];
        }
        return null;
    }

    private static function testStructuredShapeOrderAndRawValues():Void {
        var snapshot:Object = org.flashNight.arki.unit.PlayerInfoProvider.getPlayerInfoSnapshot();
        var rows:Array = flattenRows(snapshot);
        var expected:Array = expectedKeys();
        var expectedGroups:Array = [
            "profile", "encumbrance", "vitals", "resistance", "defense",
            "tenacity", "mobility", "offense", "power"
        ];
        var groupsOrdered:Boolean = snapshot.groups.length == expectedGroups.length;
        for (var g:Number = 0; g < expectedGroups.length; g++) {
            groupsOrdered = groupsOrdered
                && snapshot.groups[g].key == expectedGroups[g];
        }
        check(snapshot.v == 1 && snapshot.stateHealth == "ok"
                && snapshot.diagnostics.length == 0 && groupsOrdered,
            "snapshot 根形状与 group 顺序稳定");

        var seen:Object = {};
        var keysUniqueAndOrdered:Boolean = rows.length == expected.length;
        var rowsHaveExactShape:Boolean = true;
        var wireHasNoHtmlOrLayout:Boolean = true;
        for (var i:Number = 0; i < rows.length; i++) {
            var item:Object = rows[i];
            keysUniqueAndOrdered = keysUniqueAndOrdered
                && item.key == expected[i] && seen[item.key] !== true;
            seen[item.key] = true;

            var ownCount:Number = 0;
            for (var ownKey:String in item) {
                if (item.hasOwnProperty(ownKey)) ownCount++;
            }
            var expectedOwnCount:Number = item.key == "title" ? 6 : 5;
            rowsHaveExactShape = rowsHaveExactShape
                && ownCount == expectedOwnCount
                && item.hasOwnProperty("key") && item.hasOwnProperty("label")
                && item.hasOwnProperty("value") && item.hasOwnProperty("unit")
                && item.hasOwnProperty("displayHint")
                && (item.key != "title" || item.hasOwnProperty("spans"));
            wireHasNoHtmlOrLayout = wireHasNoHtmlOrLayout
                && item.key.indexOf("_x") < 0
                && String(item.value).indexOf("<") < 0
                && String(item.value).indexOf(">") < 0;
            if (item.spans instanceof Array) {
                for (var s:Number = 0; s < item.spans.length; s++) {
                    var span:Object = item.spans[s];
                    var spanOwnCount:Number = 0;
                    var spanKeysSafe:Boolean = true;
                    for (var spanKey:String in span) {
                        if (span.hasOwnProperty(spanKey)) {
                            spanOwnCount++;
                            spanKeysSafe = spanKeysSafe
                                && (spanKey == "text" || spanKey == "color"
                                    || spanKey == "size");
                        }
                    }
                    wireHasNoHtmlOrLayout = wireHasNoHtmlOrLayout
                        && spanKeysSafe && spanOwnCount >= 1
                        && spanOwnCount <= 3 && typeof(span.text) == "string"
                        && String(span.text).indexOf("<") < 0
                        && String(span.text).indexOf(">") < 0;
                }
            }
        }
        check(rows.length >= 40 && rows.length == 47,
            "snapshot 覆盖稳定的 40+ rows");
        check(keysUniqueAndOrdered, "row key 唯一且完整顺序冻结");
        check(rowsHaveExactShape,
            "普通 row 固定五键，称号仅追加受限 spans");
        check(wireHasNoHtmlOrLayout
                && findRow(snapshot, "movementSpeed").unit == "m/s"
                && typeof(findRow(snapshot, "experience").value) == "number"
                && typeof(findRow(snapshot, "title").value) == "string",
            "wire 只保留原始值/单位/提示，不含 HTML 或布局坐标");

        var capturedHp:Number = findRow(snapshot, "maxHp").value;
        _hero.hp满血值 = capturedHp + 1;
        var freshSnapshot:Object = org.flashNight.arki.unit.PlayerInfoProvider.getPlayerInfoSnapshot();
        check(findRow(snapshot, "maxHp").value == capturedHp
                && findRow(freshSnapshot, "maxHp").value == capturedHp + 1,
            "snapshot 与 live hero 脱离，后续读取返回新值对象");
        _hero.hp满血值 = capturedHp;
    }

    private static function testStyledTitleProjection():Void {
        var originalTitle:String = _hero.称号;
        _hero.称号 = "<FONT COLOR='#FFCC00'>金刚</FONT>"
            + "<font color=\"#00ccff\" size='14'>不坏</font>！";

        var styled:Object = org.flashNight.arki.unit.PlayerInfoProvider.getPlayerInfoSnapshot();
        var title:Object = findRow(styled, "title");
        var target:MovieClip = makeLegacyTarget();
        org.flashNight.arki.unit.PlayerInfoProvider.populatePlayerInfo(target);
        check(styled.stateHealth == "ok"
                && title.value == "金刚不坏！"
                && title.displayHint == "styled-text"
                && title.spans.length == 3
                && title.spans[0].text == "金刚"
                && title.spans[0].color == "#FFCC00"
                && title.spans[1].text == "不坏"
                && title.spans[1].color == "#00CCFF"
                && title.spans[1].size == 14
                && title.spans[2].text == "！",
            "现役 font color/size 转为纯文本标量与受限 spans");
        check(target.称号
                == "<font color='#FFCC00'>金刚</font>"
                    + "<font color='#00CCFF' size='14'>不坏</font>！",
            "legacy renderer 仅从净化 spans 重建等价 font 显示");

        _hero.称号 = "<script>alert</script><font onclick='x'>坏</font>"
            + "<font color='#fff'>短色</font>";
        var unknown:Object = org.flashNight.arki.unit.PlayerInfoProvider.getPlayerInfoSnapshot();
        var unknownTitle:Object = findRow(unknown, "title");
        var unknownTarget:MovieClip = makeLegacyTarget();
        org.flashNight.arki.unit.PlayerInfoProvider.populatePlayerInfo(unknownTarget);
        check(unknown.stateHealth == "ok"
                && unknownTitle.value == "alert坏短色"
                && unknownTitle.spans.length == 1
                && unknownTitle.spans[0].text == "alert坏短色"
                && unknownTitle.spans[0].color === undefined
                && unknownTarget.称号 == "alert坏短色",
            "未知属性/标签与短色值整体降为不可执行纯文本");

        _hero.称号 = "<font color='#FF0000'>未闭合";
        var malformed:Object = org.flashNight.arki.unit.PlayerInfoProvider.getPlayerInfoSnapshot();
        var malformedTitle:Object = findRow(malformed, "title");
        check(malformed.stateHealth == "ok"
                && malformedTitle.value == "未闭合"
                && malformedTitle.spans.length == 1
                && malformedTitle.spans[0].color === undefined,
            "未闭合 font 不透传并稳定降为纯文本");

        _hero.称号 = originalTitle;
    }

    private static function testLegacyRendererParity():Void {
        var target:MovieClip = makeLegacyTarget();
        org.flashNight.arki.unit.PlayerInfoProvider.populatePlayerInfo(target);
        var encumbranceTarget:MovieClip = makeLegacyTarget();
        org.flashNight.arki.unit.PlayerInfoProvider.displayEncumbranceStatus(encumbranceTarget, _hero);

        check(target.身高体重 == org.flashNight.arki.unit.PlayerInfoProvider.getHeightAndWeight(_hero)
                && target.杀敌数 == org.flashNight.arki.unit.PlayerInfoProvider.getKillCount(_hero)
                && target.称号 == org.flashNight.arki.unit.PlayerInfoProvider.getTitle(_hero)
                && target.经验值 == org.flashNight.arki.unit.PlayerInfoProvider.getExperience(),
            "legacy 基础字段文本与旧 getter 一致");
        check(target.装备重量 == org.flashNight.arki.unit.PlayerInfoProvider.getEquipmentWeight(_hero)
                && target.轻甲_中甲重量 == encumbranceTarget.轻甲_中甲重量
                && target.中甲_重甲重量 == encumbranceTarget.中甲_重甲重量
                && target.重甲重量 == encumbranceTarget.重甲重量
                && target.负重滑块._x == encumbranceTarget.负重滑块._x,
            "legacy 负重三阈值与滑块坐标保持一致");
        check(target.最大HP === org.flashNight.arki.unit.PlayerInfoProvider.getMaxHP(_hero)
                && target.能量抗性 === org.flashNight.arki.unit.PlayerInfoProvider.getEnergyResistance(_hero)
                && target.装备防御 == org.flashNight.arki.unit.PlayerInfoProvider.getEquipmentDefense(_hero)
                && target.减伤率 == org.flashNight.arki.unit.PlayerInfoProvider.getDamageReductionRate(_hero),
            "legacy 生命/抗性/防御字段保持值与类型");
        check(target.韧性上限 == org.flashNight.arki.unit.PlayerInfoProvider.getTenacityLimit(_hero)
                && target.踉跄韧性 == org.flashNight.arki.unit.PlayerInfoProvider.getStaggerTenacity(_hero)
                && target.速度 == org.flashNight.arki.unit.PlayerInfoProvider.getMovementSpeed(_hero)
                && target.手雷威力 === org.flashNight.arki.unit.PlayerInfoProvider.getGrenadePower(_hero),
            "legacy 韧性/速度/威力格式保持一致");

        var directFields:Array = [
            "身高体重", "杀敌数", "称号", "经验值", "装备重量",
            "最大HP", "最大MP", "内力", "能量抗性", "热抗性", "蚀抗性",
            "毒抗性", "冷抗性", "电抗性", "波抗性", "冲抗性",
            "综合防御力", "基本防御", "装备防御", "减伤率",
            "韧性上限", "踉跄韧性", "拆挡能力", "坚稳能力",
            "命中力", "闪避负荷", "懒闪避", "速度", "伤害加成",
            "空手加成", "空手攻击力", "冷兵加成", "枪械加成",
            "空手威力", "冷兵威力", "主手威力", "副手威力",
            "长枪威力", "手雷威力"
        ];
        var expectedValues:Array = [
            org.flashNight.arki.unit.PlayerInfoProvider.getHeightAndWeight(_hero),
            org.flashNight.arki.unit.PlayerInfoProvider.getKillCount(_hero),
            org.flashNight.arki.unit.PlayerInfoProvider.getTitle(_hero),
            org.flashNight.arki.unit.PlayerInfoProvider.getExperience(),
            org.flashNight.arki.unit.PlayerInfoProvider.getEquipmentWeight(_hero),
            org.flashNight.arki.unit.PlayerInfoProvider.getMaxHP(_hero),
            org.flashNight.arki.unit.PlayerInfoProvider.getMaxMP(_hero),
            org.flashNight.arki.unit.PlayerInfoProvider.getInnerPower(_hero),
            org.flashNight.arki.unit.PlayerInfoProvider.getEnergyResistance(_hero),
            org.flashNight.arki.unit.PlayerInfoProvider.getHeatResistance(_hero),
            org.flashNight.arki.unit.PlayerInfoProvider.getCorrosionResistance(_hero),
            org.flashNight.arki.unit.PlayerInfoProvider.getPoisonResistance(_hero),
            org.flashNight.arki.unit.PlayerInfoProvider.getColdResistance(_hero),
            org.flashNight.arki.unit.PlayerInfoProvider.getLightningResistance(_hero),
            org.flashNight.arki.unit.PlayerInfoProvider.getWaveResistance(_hero),
            org.flashNight.arki.unit.PlayerInfoProvider.getImpactResistance(_hero),
            org.flashNight.arki.unit.PlayerInfoProvider.getTotalDefense(_hero),
            org.flashNight.arki.unit.PlayerInfoProvider.getBaseDefense(_hero),
            org.flashNight.arki.unit.PlayerInfoProvider.getEquipmentDefense(_hero),
            org.flashNight.arki.unit.PlayerInfoProvider.getDamageReductionRate(_hero),
            org.flashNight.arki.unit.PlayerInfoProvider.getTenacityLimit(_hero),
            org.flashNight.arki.unit.PlayerInfoProvider.getStaggerTenacity(_hero),
            org.flashNight.arki.unit.PlayerInfoProvider.getGuardBreakAbility(_hero),
            org.flashNight.arki.unit.PlayerInfoProvider.getStabilityAbility(_hero),
            org.flashNight.arki.unit.PlayerInfoProvider.getAccuracy(_hero),
            org.flashNight.arki.unit.PlayerInfoProvider.getEvasionCost(_hero),
            org.flashNight.arki.unit.PlayerInfoProvider.getLazyDodge(_hero),
            org.flashNight.arki.unit.PlayerInfoProvider.getMovementSpeed(_hero),
            org.flashNight.arki.unit.PlayerInfoProvider.getDamageBonus(_hero),
            org.flashNight.arki.unit.PlayerInfoProvider.getUnarmedBonus(_hero),
            org.flashNight.arki.unit.PlayerInfoProvider.getUnarmedAttack(_hero),
            org.flashNight.arki.unit.PlayerInfoProvider.getMeleeBonus(_hero),
            org.flashNight.arki.unit.PlayerInfoProvider.getFirearmBonus(_hero),
            org.flashNight.arki.unit.PlayerInfoProvider.getUnarmedPower(_hero),
            org.flashNight.arki.unit.PlayerInfoProvider.getMeleePower(_hero),
            org.flashNight.arki.unit.PlayerInfoProvider.getMainHandPower(_hero),
            org.flashNight.arki.unit.PlayerInfoProvider.getOffHandPower(_hero),
            org.flashNight.arki.unit.PlayerInfoProvider.getRiflePower(_hero),
            org.flashNight.arki.unit.PlayerInfoProvider.getGrenadePower(_hero)
        ];
        var populated:Number = 0;
        var allDirectValuesMatch:Boolean =
            directFields.length == expectedValues.length;
        for (var i:Number = 0; i < directFields.length; i++) {
            if (target[directFields[i]] !== undefined) populated++;
            allDirectValuesMatch = allDirectValuesMatch
                && target[directFields[i]] === expectedValues[i];
        }
        check(populated == 39 && allDirectValuesMatch
                && typeof(target.装备防御) == "string"
                && typeof(target.综合防御力) == "number"
                && typeof(target.负重滑块._x) == "number",
            "legacy 39 个命名字段值/类型及 4 处负重写入无回归");
    }

    private static function testExtremeAndInvalidNumbers():Void {
        var originalHp:Number = _hero.hp满血值;
        var originalWeight:Number = _hero.重量;
        _hero.hp满血值 = 999999999;
        _hero.重量 = -999999;
        var low:Object = org.flashNight.arki.unit.PlayerInfoProvider.getPlayerInfoSnapshot();
        check(low.stateHealth == "ok"
                && findRow(low, "maxHp").value == 999999999
                && findRow(low, "weightRatio").value == 0
                && findRow(low, "encumbranceState").value == "light",
            "大数值保留且负重量 ratio 安全夹到 0");

        _hero.重量 = 999999999;
        var high:Object = org.flashNight.arki.unit.PlayerInfoProvider.getPlayerInfoSnapshot();
        check(high.stateHealth == "ok"
                && findRow(high, "weightRatio").value == 1
                && findRow(high, "encumbranceState").value == "heavy",
            "极大重量 ratio 安全夹到 1");

        var zero:Number = 0;
        _hero.hp满血值 = 1 / zero;
        var invalid:Object = org.flashNight.arki.unit.PlayerInfoProvider.getPlayerInfoSnapshot();
        var degraded:MovieClip = makeLegacyTarget("keep");
        org.flashNight.arki.unit.PlayerInfoProvider.populatePlayerInfo(degraded);
        check(invalid.stateHealth == "unavailable"
                && invalid.groups.length == 0
                && invalid.diagnostics[0] == "invalid_row:maxHp"
                && degraded.sentinel == "keep"
                && degraded.最大HP == 1 / zero
                && degraded.杀敌数
                    == org.flashNight.arki.unit.PlayerInfoProvider
                        .getKillCount(_hero)
                && degraded.手雷威力
                    === org.flashNight.arki.unit.PlayerInfoProvider
                        .getGrenadePower(_hero),
            "非有限数值令 Web snapshot fail-closed，但 legacy 逐字段继续刷新");

        _hero.hp满血值 = originalHp;
        _hero.重量 = originalWeight;
    }

    private static function testMissingHeroFailsClosed():Void {
        var fixtureWorld:Object = _root.gameworld;
        var fixtureTarget = _root.控制目标;
        _root.gameworld = {};
        _root.控制目标 = "__missingPlayerInfoHero";

        var snapshot:Object = org.flashNight.arki.unit.PlayerInfoProvider.getPlayerInfoSnapshot();
        var untouched:MovieClip = makeLegacyTarget("keep");
        org.flashNight.arki.unit.PlayerInfoProvider.populatePlayerInfo(untouched);
        check(snapshot.stateHealth == "unavailable"
                && snapshot.groups.length == 0
                && snapshot.diagnostics[0] == "hero_not_found"
                && untouched.sentinel == "keep"
                && untouched.身高体重 === undefined
                && untouched.负重滑块._x === undefined,
            "缺 hero 返回空分组并拒绝 legacy 部分写入");

        _root.gameworld = fixtureWorld;
        _root.控制目标 = fixtureTarget;
    }
}
