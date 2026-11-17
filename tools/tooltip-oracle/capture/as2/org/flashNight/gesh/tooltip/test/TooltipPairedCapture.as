import org.flashNight.arki.item.InventoryPanelService;
import org.flashNight.gesh.tooltip.TooltipInputProjection;
import org.flashNight.arki.item.BaseItem;
import org.flashNight.gesh.tooltip.NativeTooltipDocument;
import org.flashNight.gesh.tooltip.SkillTooltipComposer;
import org.flashNight.gesh.string.StringUtils;

/**
 * OFFLINE ONLY. Compile in the pinned baseline worktree, never in candidate roots.
 * Expected content is executed by the old AVM1 implementation. Input is captured
 * from the same item/state using the candidate read-only producer. No TS output
 * is accepted as truth. The converter requires one complete zero-error run.
 */
class org.flashNight.gesh.tooltip.test.TooltipPairedCapture {
    private static var _runId:String;
    private static var _count:Number = 0;
    private static var _failures:Number = 0;
    private static var _seen:Object;
    private static var _active:Boolean = false;
    private static var _json:LiteJSON;

    public static function captureCount():Number { return _count; }

    public static function begin(runId:String, sourceCommit:String,
                                  projectionSha256:String, catalogContentVersion:String):Boolean {
        _runId = runId;
        _count = 0; _failures = 0; _seen = {}; _active = true;
        _json = new LiteJSON();
        trace("TC_INPUT_BEGIN|" + _json.stringifySafe({runId:runId, provenance:{
            kind:"avm1-capture", sourceCommit:sourceCommit, capturedAt:isoNow(),
            inputProjectionSha256:projectionSha256, catalogContentVersion:catalogContentVersion,
            scope:"baseline AVM1 content paired with candidate read-only input"}}));
        if (!verifySerialization()) {
            failure("capture_serializer_mismatch");
            return false;
        }
        captureBody("body:simple", "<B>标题 &amp; 实体</B><BR><FONT COLOR='#66CCFF'>灰蛊</FONT>", "simple");
        captureBody("body:dense", "<B>嵌套 <I>样式</I></B><BR>&lt;literal&gt; &#x4E2D; &#20013;", "dense");
        captureSkillBoundaries();
        return _failures === 0;
    }

    /** Authored equipment, calculated by real BaseItem at explicit test levels. */
    public static function captureEnhancedInstances():Void {
        var names:Array = ["M4A1","KRISS","沙漠军装背心","远古诛神剑","巨兽"];
        var levels:Array = [2,5,10,13];
        for (var itemIndex:Number = 0; itemIndex < names.length; itemIndex++) {
            for (var levelIndex:Number = 0; levelIndex < levels.length; levelIndex++) {
                var name:String = names[itemIndex];
                var level:Number = levels[levelIndex];
                var item:BaseItem = BaseItem.create(name,level,0);
                if (item == null || item.value.level != level) {
                    failure("enhancement_fixture_unavailable:" + name + ":" + level);
                } else {
                    captureInventory("configured:" + name + ":level:" + level,item);
                }
            }
        }
    }

    /** Fixture inputs only; every expected field still executes the old composer. */
    private static function captureSkillBoundaries():Void {
        var standard:Object = {Name:"技能边界",Type:"主动",Equippable:true,CD:1500,MP:20,Description:"fixture"};
        captureSkillFixture("equipped",standard,["oracle-equipped",3,true,0,false]);
        captureSkillFixture("unequipped",standard,["oracle-unequipped",3,false,0,false]);
        var passive:Object = {Name:"被动边界",Type:"被动",Equippable:false,CD:0,MP:0,Description:"fixture"};
        captureSkillFixture("enabled",passive,["oracle-enabled",1,false,0,true]);
        captureSkillFixture("disabled",passive,["oracle-disabled",1,false,0,false]);
        captureSkillFixture("nonfinite",{Name:"非有限数",Type:"主动",Equippable:true,CD:0/0,MP:1/0},
            ["oracle-nonfinite",0/0,true,0,false]);
        captureSkillFixture("negative-infinity",{Name:"负无穷",Type:"主动",Equippable:true,CD:-1/0,MP:0/0},
            ["oracle-negative-infinity",-1/0,false,0,false]);
        captureSkillFixture("null",{Name:null,Type:null,Equippable:null,CD:null,MP:null,Description:null},
            ["oracle-null",null,false,0,false]);
        var sparse:Array = new Array(5); sparse[0] = "oracle-missing";
        captureSkillFixture("missing",{},sparse);
        captureSkillFixture("numeric-strings",{Name:"数值字符串",Type:"主动",Equippable:"false",CD:"2500",MP:"7"},
            ["oracle-numeric-strings","2",1,0,"true"]);
        var costs:Array = new Array(5); costs[0] = "cost"; costs[2] = null; costs[3] = 0/0; costs[4] = 1/0;
        captureSkillFixture("array-holes",{Name:"数组空洞",Type:"主动",Equippable:true,CD:0,MP:costs,Description:["first",null,"last"]},
            ["oracle-array-holes",1,true,0,false]);
        var keyed:Object = {}; keyed[2] = "two"; keyed[1] = "one"; keyed.label = "object";
        captureSkillFixture("numeric-keys",{Name:"数字键",Type:"主动",Equippable:true,CD:1,MP:keyed},
            ["oracle-numeric-keys",1,true,0,false]);
        captureSkillFixture("markup",{Name:"技能 &amp; 名称",Type:"主动",Equippable:true,CD:1999,MP:0,
            Description:"<B>边界</B><BR>&lt;literal&gt; &#x4E2D; &#20013;"},["oracle-markup",10,true,0,false]);
    }

    /** Same real BaseItem is used on both sides; no equipment formula is recreated. */
    public static function captureInventory(id:String, item:Object):Void {
        try {
            var input:Object = inventoryInput(item);
            var before:String = stringify(input);
            var expected:Object = InventoryPanelService.buildTooltipProjection(item);
            if (expected == null || expected.success !== true || expected.document == null)
                throw "legacy_inventory_failed";
            if (before != stringify(inventoryInput(item))) throw "source_drift";
            emit({id:id, input:input, expectedDocument:expected.document,
                expectedIntroHTML:expected.introHTML, expectedDescHTML:expected.descHTML,
                expectedDetails:StringUtils.htmlToPlainTextFast(expected.introHTML + expected.descHTML).substr(0,4096)});
        } catch (error) { failure(id + ":" + String(error)); }
    }

    private static function inventoryInput(item:Object):Object {
        if (item == null || typeof item.name != "string") throw "invalid_item";
        var count:Number = typeof item.value == "number" && isFinite(item.value)
            ? Math.floor(Number(item.value)) : 0;
        var value:Object = typeof item.value == "object" ? item.value : {level:1,count:count};
        var base = typeof item.value == "object" && typeof item.getData == "function" ? item : null;
        var input:Object = TooltipInputProjection.forItem(item.name,value,base,"inventory");
        var meta:Object = InventoryPanelService.buildItemProjection(item);
        if (input == null || meta == null) throw "input_projection_failed";
        input.projection.displayName = String(meta.displayName);
        input.projection.iconName = String(meta.icon);
        return input;
    }

    /** The baseline frame include installs the real old COMMON Web producer. */
    public static function captureWeb(id:String, name:String):Void {
        try {
            if (typeof _root.Web物品注释HTML != "function") throw "legacy_web_entry_missing";
            var input:Object = TooltipInputProjection.preview(name).tooltipInput;
            var before:String = stringify(input);
            var expected:Object = _root.Web物品注释HTML(name);
            if (expected == null || expected.document == null) throw "legacy_web_failed";
            if (before != stringify(TooltipInputProjection.preview(name).tooltipInput)) throw "source_drift";
            emit({id:id,input:input,expectedDocument:expected.document,
                expectedIntroHTML:expected.introHTML,expectedDescHTML:expected.descHTML,
                expectedDetails:StringUtils.htmlToPlainTextFast(expected.introHTML + expected.descHTML).substr(0,4096)});
        } catch (error) { failure(id + ":" + String(error)); }
    }

    /** Optional live-state hook after a real save/skill table has loaded. */
    public static function captureLoadoutSkill(id:String, index:Number):Void {
        try {
            var input:Object = TooltipInputProjection.loadoutSkill(index);
            if (input == null) throw "skill_input_missing";
            var before:String = stringify(input);
            var expected:Object = SkillTooltipComposer.describeLoadout(index);
            if (expected == null || expected.document == null) throw "legacy_skill_failed";
            if (before != stringify(TooltipInputProjection.loadoutSkill(index))) throw "source_drift";
            emit({id:id,input:input,expectedDocument:expected.document,
                expectedIntroHTML:expected.intro,expectedDescHTML:expected.description});
        } catch (error) { failure(id + ":" + String(error)); }
    }

    /** Optional deterministic AVM1 boundary fixture; restore the original tables. */
    public static function captureSkillFixture(id:String, metadata:Object, state:Array):Void {
        var oldRows:Object = _root.主角技能表;
        var oldMeta:Object = _root.技能表对象;
        try {
            var table:Object = {};
            table[state[0]] = metadata;
            _root.主角技能表 = [state];
            _root.技能表对象 = table;
            captureLoadoutSkill("fixture:" + id,0);
        } finally {
            _root.主角技能表 = oldRows;
            _root.技能表对象 = oldMeta;
        }
    }

    public static function captureBody(id:String, html:String, profile:String):Void {
        try {
            var input:Object = TooltipInputProjection.body(html,profile);
            emit({id:id,input:input,
                expectedDocument:NativeTooltipDocument.buildBody(input.html,input.profile),
                expectedIntroHTML:"",expectedDescHTML:input.html});
        } catch (error) { failure(id + ":" + String(error)); }
    }

    private static function emit(record:Object):Void {
        if (!_active) throw "capture_not_active";
        if (!record.id || _seen["$" + record.id]) throw "duplicate_capture_id";
        var wire:String = stringify(record);
        _seen["$" + record.id] = true;
        _count++;
        trace("TC_INPUT|" + _runId + "|" + wire);
    }

    public static function failure(reason:String):Void {
        _failures++;
        trace("TC_INPUT_ERROR|" + _runId + "|" + _json.stringifySafe({reason:reason}));
    }

    public static function finish():Void {
        if (!_active) return;
        trace("TC_INPUT_END|" + _json.stringifySafe({runId:_runId,records:_count,failures:_failures}));
        _active = false;
    }

    private static function stringify(arg):String {
        return org.flashNight.gesh.tooltip.test.TooltipCaptureJson.stringify(arg);
    }

    private static function verifySerialization():Boolean {
        return org.flashNight.gesh.tooltip.test.TooltipCaptureJson.verifySerialization();
    }

    private static function pad(value:Number, digits:Number):String {
        var result:String = String(value);
        while (result.length < digits) result = "0" + result;
        return result;
    }
    private static function isoNow():String {
        var now:Date = new Date();
        return pad(now.getUTCFullYear(),4) + "-" + pad(now.getUTCMonth()+1,2)
            + "-" + pad(now.getUTCDate(),2) + "T" + pad(now.getUTCHours(),2)
            + ":" + pad(now.getUTCMinutes(),2) + ":" + pad(now.getUTCSeconds(),2)
            + "." + pad(now.getUTCMilliseconds(),3) + "Z";
    }
}
