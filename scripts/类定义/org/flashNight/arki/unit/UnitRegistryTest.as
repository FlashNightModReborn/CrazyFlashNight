import org.flashNight.arki.unit.UnitRegistry;
import org.flashNight.arki.scene.StageInfo;
import org.flashNight.arki.scene.StageEvent;
import org.flashNight.arki.scene.BookDefinition;
import org.flashNight.gesh.xml.XMLParser;
import org.flashNight.gesh.json.LoadJson.BaseJSONLoader;
import org.flashNight.gesh.path.PathManager;
import org.flashNight.gesh.object.ObjectUtil;
import LiteJSON;

/** 真实 AVM1 测试入口；离线工具通过不能代替本套件执行。 */
class org.flashNight.arki.unit.UnitRegistryTest {
    private static var passed:Number;
    private static var failed:Number;
    private static var draws:Number;
    private static var savedLibrary:Object;
    private static var savedUnits:Array;
    private static var savedDraw:Function;

    public static function runAllTests():Void {
        passed = 0;
        failed = 0;
        savedLibrary = _root.兵种库;
        savedUnits = _root.units;
        savedDraw = _root.__unitRegistryDraw;
        try {
            testRegistry();
            testAttributes();
            testInlineAndDialogue();
            testRejectedReferences();
            testReload();
            testCaseSwitch();
            testWave();
            testJson();
        } catch (syncError) {
            restoreGlobals();
            throw syncError;
        }
        testProductionAssets();
    }

    private static function restoreGlobals():Void {
        _root.兵种库 = savedLibrary;
        if (savedDraw === undefined) delete _root.__unitRegistryDraw;
        else _root.__unitRegistryDraw = savedDraw;
        if (savedUnits instanceof Array && savedUnits.length > 0) UnitRegistry.initialize(savedUnits);
        else {
            try { UnitRegistry.initialize([]); } catch (emptyRegistry) { }
        }
    }

    private static function check(ok:Boolean, label:String):Void {
        if (ok) passed++;
        else { failed++; trace("[FAIL] UnitRegistry: " + label); }
    }

    private static function rejects(action:Function):Boolean {
        try { action(); } catch (expectedError) { return true; }
        return false;
    }

    private static function rows():Array {
        return [
            {id:0, key:"测试.零号", name:"同名", spritename:"敌人-共享素材"},
            {id:1, name:"同名", spritename:"敌人-共享素材"},
            {id:466, key:"cf6.特种兵.二阶段", name:"特种兵", spritename:"敌人-CF6特种兵"},
            {id:467, key:"cf6.特种兵.持盾一阶段", name:"特种兵", spritename:"敌人-CF6持盾特种兵"}
        ];
    }

    private static function install():Void {
        UnitRegistry.initialize(rows());
        var library:Object = {};
        library["兵种0"] = {兵种名:"敌人-共享素材", 名字:"同名", 等级:1, 是否为敌人:true};
        library["兵种1"] = {兵种名:"敌人-共享素材", 名字:"同名", 等级:1, 是否为敌人:false};
        library["兵种466"] = {兵种名:"敌人-CF6特种兵", 名字:"特种兵", 等级:30, 是否为敌人:true, 长枪:"G36"};
        library["兵种467"] = {兵种名:"敌人-CF6持盾特种兵", 名字:"特种兵", 等级:30, 是否为敌人:true};
        _root.兵种库 = library;
    }

    private static function buildProductionLibrary(units:Array):Object {
        var library:Object = {};
        for (var i:Number = 0; i < units.length; i++) {
            var u:Object = units[i];
            var d:Object = u.data != null ? u.data : {};
            var entry:Object = {
                兵种名: u.spritename,
                等级: u.level,
                名字: u.name,
                是否为敌人: u.is_hostile,
                身高: u.height,
                长枪: !d.primary ? "" : d.primary,
                手枪: !d.secondary ? "" : d.secondary,
                手枪2: !d.secondary2 ? "" : d.secondary2,
                刀: !d.melee ? "" : d.melee,
                手雷: !d.grenade ? "" : d.grenade
            };
            if (u.NPC != undefined) entry.NPC = u.NPC;
            if (u.pet_attr) entry.宠物属性 = u.pet_attr;
            if (d.face != undefined) entry.脸型 = d.face == null ? "" : d.face;
            if (d.hairstyle != undefined) entry.发型 = d.hairstyle == null ? "" : d.hairstyle;
            if (d.head != undefined) entry.头部装备 = d.head == null ? "" : d.head;
            if (d.body != undefined) entry.上装装备 = d.body == null ? "" : d.body;
            if (d.leg != undefined) entry.下装装备 = d.leg == null ? "" : d.leg;
            if (d.hand != undefined) entry.手部装备 = d.hand == null ? "" : d.hand;
            if (d.foot != undefined) entry.脚部装备 = d.foot == null ? "" : d.foot;
            if (d.neck != undefined) entry.颈部装备 = d.neck == null ? "" : d.neck;
            if (d.gender != undefined) entry.性别 = d.gender == null ? "" : d.gender;
            library["兵种" + String(u.id)] = entry;
        }
        return library;
    }

    private static function testRegistry():Void {
        install();
        check(UnitRegistry.resolveType("兵种0") === "兵种0", "zero legacy id");
        check(UnitRegistry.resolveType("测试.零号") === "兵种0", "zero semantic id");
        check(UnitRegistry.resolveType("cf6.特种兵.二阶段") === "兵种466", "semantic variant");
        check(UnitRegistry.resolveType("兵种1") === "兵种1", "legacy-only record");
        check(UnitRegistry.resolveType("cf6.特种兵.持盾一阶段") === "兵种467", "same display name stays distinct");
        check(UnitRegistry.validKey("军阀.铁卫犬"), "Chinese namespace");
        check(!UnitRegistry.validKey("cf6.单位 名"), "whitespace rejected");
        check(!UnitRegistry.validKey("constructor.单位"), "reserved segment rejected");
        check(!UnitRegistry.isLegacyType("兵种0466"), "leading zeros rejected");
    }

    private static function testAttributes():Void {
        var legacy:Object = StageInfo.parseEnemyAttribute({Type:"兵种466", IsHostile:false});
        var source:Object = {Type:"cf6.特种兵.二阶段", IsHostile:false, Level:17};
        var semantic:Object = StageInfo.parseEnemyAttribute(source);
        check(semantic.兵种名 === legacy.兵种名, "linkage parity");
        check(semantic.名字 === legacy.名字, "display name parity");
        check(semantic.等级 === 30, "template level remains for WaveSpawner override");
        check(semantic.是否为敌人 === false && _root.兵种库["兵种466"].是否为敌人 === true, "hostility override is isolated");
        check(source.Type === "兵种466", "runtime descriptor is canonical");
        check(semantic.key === undefined, "authoring key is not an actor attribute");
        semantic.长枪 = "modified";
        check(_root.兵种库["兵种466"].长枪 === "G36", "template is cloned");
        var count:Number = 0;
        for (var identity:String in _root.兵种库) count++;
        check(count === 4 && _root.兵种库["cf6.特种兵.二阶段"] === undefined, "no duplicate enumeration aliases");
    }

    private static function testInlineAndDialogue():Void {
        var inline:Object = StageInfo.parseEnemyAttribute({spritename:"敌人-内联", Name:"内联", Level:12});
        check(inline.兵种名 === "敌人-内联" && inline.名字 === "内联", "inline unit remains supported");
        check(inline.NPC === "", "inline missing fields retain normalization");
        check(StageInfo.parseEnemyAttribute({Type:"", spritename:"敌人-内联"}).兵种名 === "敌人-内联", "empty Type compatibility");
        var lines:Array = StageInfo.parseSingleDialogue([{Name:"对白", spritename:"敌人-内联", Text:"text"}]);
        check(lines[0].target.兵种名 === "敌人-内联", "inline dialogue appearance");
        lines = StageInfo.parseSingleDialogue([{Name:"对白", Type:"cf6.特种兵.二阶段", Text:"text"}]);
        check(lines[0].target.兵种名 === "敌人-CF6特种兵", "semantic dialogue appearance");
        var stageXml:XML = new XML();
        stageXml.ignoreWhite = true;
        stageXml.parseXML(
            "<SubStage id=\"0\">" +
            "<Dialogue><SubDialogue id=\"0\"><Type>测试.零号</Type><Text>intro</Text></SubDialogue></Dialogue>" +
            "<Event><EventName>WaveFinished</EventName>" +
            "<Dialogue id=\"0\"><Type>cf6.特种兵.二阶段</Type><Text>event</Text></Dialogue>" +
            "<Dialogue id=\"1\"><Type>测试.零号</Type><Type>cf6.特种兵.持盾一阶段</Type><Text>override</Text></Dialogue>" +
            "<Enemy><Type>cf6.特种兵.持盾一阶段</Type><Level>25</Level></Enemy></Event>" +
            "<Wave><SubWave id=\"0\"><WaveInformation><Duration>0</Duration></WaveInformation>" +
            "<Dialogue><SubDialogue id=\"0\"><Type>cf6.特种兵.持盾一阶段</Type><Text>wave</Text></SubDialogue></Dialogue>" +
            "<EnemyGroup><Enemy><Type>cf6.特种兵.二阶段</Type><Level>30</Level><Quantity>2</Quantity></Enemy></EnemyGroup>" +
            "</SubWave></Wave></SubStage>"
        );
        var subStage:Object = XMLParser.parseStageXMLNode(stageXml.firstChild);
        var stageDialogues:Array = StageInfo.parseDialogues(subStage);
        check(stageDialogues[0][0].target.兵种名 === "敌人-共享素材", "SubStage Dialogue/SubDialogue/Type resolves");
        check(stageDialogues[1][0].target.兵种名 === "敌人-CF6持盾特种兵", "SubWave Dialogue/SubDialogue/Type resolves");
        var stageEvent:StageEvent = new StageEvent(subStage.Event);
        var eventLines:Array = StageInfo.parseSingleDialogue(stageEvent.dialogue);
        check(eventLines[0].target.兵种名 === "敌人-CF6特种兵", "Event/Dialogue/Type resolves");
        check(eventLines[1].target.兵种名 === "敌人-CF6持盾特种兵", "Event/Dialogue multi-Type override resolves");
        check(StageInfo.parseEnemyGroup(stageEvent.enemy)[0].Attribute.兵种名 === "敌人-CF6持盾特种兵", "Event/Enemy/Type resolves");
        var waves:Array = StageInfo.parseWaveInfo(subStage);
        check(waves[0][1].Type === "兵种466" && waves[0][1].Attribute.兵种名 === "敌人-CF6特种兵", "parseWaveInfo normalizes Type and resolves Attribute");
    }

    private static function testRejectedReferences():Void {
        check(rejects(function():Void { StageInfo.parseEnemyAttribute({Type:"cf6.拼错"}); }), "unknown semantic key fails");
        check(rejects(function():Void { StageInfo.parseEnemyAttribute({Type:"CF6.特种兵.二阶段"}); }), "case is exact");
        check(rejects(function():Void { StageInfo.parseEnemyAttribute({Type:"兵种999999"}); }), "unknown legacy id fails");
        check(rejects(function():Void { StageInfo.parseEnemyAttribute({Type:"兵种0466"}); }), "malformed legacy id fails");
        check(rejects(function():Void { StageInfo.parseEnemyAttribute({Type:466}); }), "numeric Type fails");
        check(rejects(function():Void { StageInfo.parseEnemyAttribute({Type:"cf6.特种兵.二阶段 "}); }), "no whitespace alias");
        check(rejects(function():Void { StageInfo.parseEnemyAttribute({Type:["测试.零号", "cf6.拼错"]}); }), "multi-Type array rejects unknown element");
        check(rejects(function():Void { UnitRegistry.initialize([{id:1,spritename:"x"},{id:1,spritename:"y"}]); }), "duplicate id fails");
        check(rejects(function():Void { UnitRegistry.initialize([{id:1,key:"测试.重复",spritename:"x"},{id:2,key:"测试.重复",spritename:"y"}]); }), "duplicate key fails");
    }

    private static function testReload():Void {
        install();
        check(UnitRegistry.resolveType("cf6.特种兵.二阶段") === "兵种466", "initial catalog");
        UnitRegistry.initialize([{id:466,key:"测试.替换目录",spritename:"敌人-CF6特种兵"}]);
        check(rejects(function():Void { UnitRegistry.resolveType("cf6.特种兵.二阶段"); }), "old key removed on reload");
        try { UnitRegistry.initialize([{id:-1,spritename:"x"}]); } catch (expectedError) { }
        check(rejects(function():Void { UnitRegistry.resolveType("测试.替换目录"); }), "failed reload invalidates semantic catalog");
        install();
        check(UnitRegistry.resolveType("cf6.特种兵.二阶段") === "兵种466", "fresh reload restores catalog");
    }

    public static function draw(a:Number, b:Number):Number { draws++; return 1; }

    private static function testCaseSwitch():Void {
        draws = 0;
        _root.__unitRegistryDraw = function(a:Number, b:Number):Number {
            return org.flashNight.arki.unit.UnitRegistryTest.draw(a, b);
        };
        var xml:XML = new XML();
        xml.ignoreWhite = true;
        xml.parseXML('<Enemy><Type><CaseSwitch expression="_root.__unitRegistryDraw" params="0,1"><Case casevalue="0">兵种466</Case><Case casevalue="1">cf6.特种兵.持盾一阶段</Case></CaseSwitch></Type></Enemy>');
        var enemy:Object = XMLParser.parseStageXMLNode(xml.firstChild);
        check(draws === 1, "existing parser draws once for two-argument expression");
        check(enemy.Type === "cf6.特种兵.持盾一阶段", "selected semantic branch");
        var attribute:Object = StageInfo.parseEnemyAttribute(enemy);
        check(attribute.兵种名 === "敌人-CF6持盾特种兵", "selected branch resolves");
        check(draws === 1, "identity resolution does not redraw");
    }

    private static function testWave():Void {
        var parsed:Array = StageInfo.parseEnemyGroup([
            {Type:"cf6.特种兵.二阶段", Level:20, Parameters:{Type:"opaque.parameter"}},
            {Type:"兵种467", Level:21}
        ]);
        check(parsed.length === 2, "mixed wave length");
        check(parsed[0].Type === "兵种466", "first type normalized");
        check(parsed[1].Type === "兵种467", "second legacy type preserved");
        check(parsed[0].Attribute.兵种名 === "敌人-CF6特种兵" && parsed[1].Attribute.兵种名 === "敌人-CF6持盾特种兵", "spawn order preserved");
        check(parsed[0].Parameters.Type === "opaque.parameter", "arbitrary parameters are opaque");
    }

    private static function testJson():Void {
        var codec:LiteJSON = new LiteJSON();
        var parsed:Array = codec.parse('[{"id":466,"key":"cf6.特种兵.二阶段","spritename":"敌人-CF6特种兵"}]');
        UnitRegistry.initialize(parsed);
        check(UnitRegistry.resolveType("cf6.特种兵.二阶段") === "兵种466", "real LiteJSON Unicode key");
        check(rejects(function():Void { UnitRegistry.initialize([{id:1,key:null,spritename:"x"}]); }), "explicit null key fails");
        check(rejects(function():Void { UnitRegistry.initialize([{id:1.5,spritename:"x"}]); }), "fractional id fails");
        check(UnitRegistry.isLegacyType("兵种2147483647") && !UnitRegistry.isLegacyType("兵种2147483648"), "legacy integer boundary");
    }

    private static function testProductionAssets():Void {
        PathManager.initialize();
        var state:Object = {
            listDone: false,
            listValue: "",
            unitsDone: false,
            unitsData: null,
            duoluoDone: false,
            duoluoXml: null,
            milinDone: false,
            milinXml: null,
            startedAt: getTimer(),
            completed: false
        };

        var listXml:XML = new XML();
        listXml.ignoreWhite = true;
        listXml.onLoad = function(ok:Boolean):Void {
            if (ok && listXml.firstChild != null && listXml.firstChild.firstChild != null && listXml.firstChild.firstChild.firstChild != null) {
                state.listValue = String(listXml.firstChild.firstChild.firstChild.nodeValue);
            }
            state.listDone = true;
        };
        listXml.load(PathManager.resolvePath("data/units/list.xml"));

        var unitsLoader:BaseJSONLoader = new BaseJSONLoader("data/units/units.json", "LiteJSON");
        unitsLoader.load(function(data:Object):Void {
            state.unitsData = data;
            state.unitsDone = true;
        }, function(err:String):Void {
            state.unitsDone = true;
        });

        var duoluoXml:XML = new XML();
        duoluoXml.ignoreWhite = true;
        duoluoXml.onLoad = function(ok:Boolean):Void {
            if (ok) state.duoluoXml = duoluoXml;
            state.duoluoDone = true;
        };
        duoluoXml.load(PathManager.resolvePath("data/stages/副本任务/堕落城的骚动.xml"));

        var milinXml:XML = new XML();
        milinXml.ignoreWhite = true;
        milinXml.onLoad = function(ok:Boolean):Void {
            if (ok) state.milinXml = milinXml;
            state.milinDone = true;
        };
        milinXml.load(PathManager.resolvePath("data/stages/副本任务/密林深处.xml"));

        BookDefinition.load("repair-campus");
        BookDefinition.load("cf6-sting", "historical");
        BookDefinition.load("cf6-sting", "type61");

        var watch:MovieClip = _root.createEmptyMovieClip("__unitRegistryWatch", 78199);
        watch.onEnterFrame = function():Void {
            if (state.completed) return;
            var booksReady:Boolean = BookDefinition.ready("repair-campus") &&
                BookDefinition.ready("cf6-sting", "historical") &&
                BookDefinition.ready("cf6-sting", "type61");
            var allReady:Boolean = state.listDone && state.unitsDone && state.duoluoDone && state.milinDone && booksReady;
            var timedOut:Boolean = (getTimer() - state.startedAt) > 20000;
            if (!allReady && !timedOut) return;
            state.completed = true;
            this.removeMovieClip();
            org.flashNight.arki.unit.UnitRegistryTest.finishProductionAssets(state);
        };
    }

    public static function finishProductionAssets(state:Object):Void {
        var unitCount:Number = 0;
        var resolvedKeyCount:Number = 0;
        var totalStageEnemies:Number = 0;
        try {
            check(state.listValue === "units.json", "production data/units/list.xml entry");
            var units:Array = state.unitsData instanceof Array ? state.unitsData : null;
            unitCount = units != null ? units.length : 0;
            check(unitCount === 475, "production data/units/units.json 475 units");
            if (units != null) {
                UnitRegistry.initialize(units);
                _root.兵种库 = buildProductionLibrary(units);
                for (var i:Number = 0; i < units.length; i++) {
                    var u:Object = units[i];
                    var expectedLegacy:String = "兵种" + String(u.id);
                    if (UnitRegistry.validKey(u.key) &&
                        UnitRegistry.resolveType(u.key) === expectedLegacy &&
                        _root.兵种库[expectedLegacy] != null &&
                        _root.兵种库[expectedLegacy].兵种名 === u.spritename) {
                        resolvedKeyCount++;
                    }
                }
            }
            check(resolvedKeyCount === 475, "all 475 production semantic keys resolve to library templates");

            var duoluoStage:Object = state.duoluoXml != null ? XMLParser.parseStageXMLNode(state.duoluoXml.firstChild) : null;
            var duoluoWaves:Array = duoluoStage != null ? StageInfo.parseWaveInfo(duoluoStage.SubStage) : null;
            var duoluoEnemies:Number = 0;
            if (duoluoWaves != null) {
                for (var wi:Number = 0; wi < duoluoWaves.length; wi++) {
                    duoluoEnemies += duoluoWaves[wi].length - 1;
                }
            }
            totalStageEnemies += duoluoEnemies;
            check(duoluoWaves != null && duoluoWaves.length === 20 && duoluoEnemies === 125 &&
                duoluoWaves[0][1].Type === "兵种44" && duoluoWaves[0][1].Attribute.兵种名 === "敌人-盗贼枪手",
                "production 堕落城的骚动.xml 20 waves / 125 enemies resolve");

            var milinStage:Object = state.milinXml != null ? XMLParser.parseStageXMLNode(state.milinXml.firstChild) : null;
            var milinSub1:Object = (milinStage != null && milinStage.SubStage != null) ? milinStage.SubStage[1] : null;
            var milinWaves:Array = milinSub1 != null ? StageInfo.parseWaveInfo(milinSub1) : null;
            var milinEnemies:Number = 0;
            if (milinWaves != null) {
                for (var mi:Number = 0; mi < milinWaves.length; mi++) {
                    milinEnemies += milinWaves[mi].length - 1;
                }
            }
            totalStageEnemies += milinEnemies;
            var milinEvent:StageEvent = (milinSub1 != null && milinSub1.Event != null) ? new StageEvent(milinSub1.Event[1]) : null;
            var milinLines:Array = milinEvent != null ? StageInfo.parseSingleDialogue(milinEvent.dialogue) : null;
            check(milinWaves != null && milinWaves.length === 3 && milinEnemies === 9 &&
                milinLines != null && milinLines[0].target.兵种名 === "主角-男" && milinLines[0].target.头部装备 === "诛神头盔",
                "production 密林深处.xml waves and multi-Type Event/Dialogue resolve");

            var campus:Object = BookDefinition.get("repair-campus");
            var campusOk:Boolean = campus != null && campus.maps instanceof Array && campus.maps.length === 7;
            if (campusOk) {
                for (var ci:Number = 0; ci < campus.maps[0].enemies.length; ci++) {
                    if (_root.兵种库["兵种" + String(campus.maps[0].enemies[ci])] == null) campusOk = false;
                }
            }
            check(campusOk, "production repair-campus.runtime.json enemies resolve");

            var cf6:Object = BookDefinition.get("cf6-sting", "historical");
            var cf6Waves:Array = (cf6 != null && cf6.maps instanceof Array) ? StageInfo.parseWaveInfo(ObjectUtil.clone(cf6.maps[0].stage)) : null;
            check(cf6Waves != null && cf6Waves.length > 0 && cf6Waves[0][1].Attribute.兵种名 !== "",
                "production cf6-sting.runtime.json wave enemies resolve");

            var type61:Object = BookDefinition.get("cf6-sting", "type61");
            var type61Waves:Array = (type61 != null && type61.maps instanceof Array) ? StageInfo.parseWaveInfo(ObjectUtil.clone(type61.maps[0].stage)) : null;
            check(type61Waves != null && type61Waves.length > 0 && type61Waves[0][1].Attribute.兵种名 !== "",
                "production cf6-type61.runtime.json wave enemies resolve");
        } finally {
            restoreGlobals();
        }
        trace("UnitRegistryTest Production Summary: units=" + unitCount + ", keys=" + resolvedKeyCount + ", stageEnemies=" + totalStageEnemies + ", books=3/3");
        trace("UnitRegistryTest Tests Passed: " + passed);
        trace("UnitRegistryTest Tests Failed: " + failed);
        if (failed > 0 || passed != 62) {
            throw new Error("UnitRegistryTest failed: " + passed + "/62 passed, " + failed + " failed");
        }
        trace("UnitRegistryTest Cases Passed: 9/9");
        if (typeof _root.__unitRegistryRunId === "string" && _root.__unitRegistryRunId.length > 0) {
            trace("FocusedTestRunId unit-registry Complete: " + _root.__unitRegistryRunId);
        }
    }
}
