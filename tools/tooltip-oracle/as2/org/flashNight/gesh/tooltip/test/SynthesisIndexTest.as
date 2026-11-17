import org.flashNight.arki.item.synthesis.SynthesisIndex;

/**
 * SynthesisIndexTest - 合成配方索引测试
 *
 * 覆盖：
 *   - getRecipe null safety（_root.改装清单对象 不存在时）
 *   - getRecipesUsing 基础查找 / 不存在键 / 空数据兜底
 *   - 排序 + 单配方内同材料去重
 *
 * 隔离策略：每个 test 直接 save → swap → run → restore，不用闭包/try-finally
 * （AS2 1.0 编译器对闭包词法作用域和 try/finally 行为不稳定）。
 */
class org.flashNight.gesh.tooltip.test.SynthesisIndexTest {

    public static var testsRun:Number = 0;
    public static var testsPassed:Number = 0;
    public static var testsFailed:Number = 0;

    private static function assert(cond:Boolean, msg:String):Void {
        testsRun++;
        if (cond) { testsPassed++; trace("[PASS] " + msg); }
        else { testsFailed++; trace("[FAIL] " + msg); }
    }

    public static function runAllTests():Void {
        testsRun = testsPassed = testsFailed = 0;
        trace("--- SynthesisIndexTest ---");

        test_getRecipe_null_safe();
        test_getRecipesUsing_basic();
        test_getRecipesUsing_nonExistent();
        test_getRecipesUsing_emptyData();
        test_getRecipesUsing_sortedAndDedup();
        test_getRecipeUses_exactOccurrences();
        test_getRecipesProducing_exactAuthoredOrder();

        trace("--- SynthesisIndexTest: " + testsPassed + "/" + testsRun + " passed, " + testsFailed + " failed ---");
    }

    private static function test_getRecipe_null_safe():Void {
        // _root.改装清单对象 缺失时应返回 null
        var saved = _root.改装清单对象;
        _root.改装清单对象 = undefined;
        var result = SynthesisIndex.getRecipe("不存在的物品");
        assert(result == null, "getRecipe null safe: " + result);
        _root.改装清单对象 = saved;
    }

    private static function test_getRecipesUsing_basic():Void {
        // 注入受控配方：A 是产物，材料含 X 和 Y
        var saved = _root.改装清单对象;
        _root.改装清单对象 = {
            测试产物A: { name: "测试产物A", materials: ["测试材料X#1", "测试材料Y#5"] },
            测试产物B: { name: "测试产物B", materials: ["测试材料X#2"] }
        };
        SynthesisIndex.reset();

        var xUses:Array = SynthesisIndex.getRecipesUsing("测试材料X");
        assert(xUses.length == 2, "getRecipesUsing X length=2 actual=" + xUses.length);
        var xJoined:String = xUses.join("|");
        assert(xJoined.indexOf("测试产物A") >= 0, "getRecipesUsing X contains A: " + xJoined);
        assert(xJoined.indexOf("测试产物B") >= 0, "getRecipesUsing X contains B: " + xJoined);

        var yUses:Array = SynthesisIndex.getRecipesUsing("测试材料Y");
        assert(yUses.length == 1, "getRecipesUsing Y length=1 actual=" + yUses.length);
        assert(yUses[0] == "测试产物A", "getRecipesUsing Y[0]=A");

        _root.改装清单对象 = saved;
        SynthesisIndex.reset();
    }

    private static function test_getRecipesUsing_nonExistent():Void {
        var saved = _root.改装清单对象;
        _root.改装清单对象 = {
            X: { name: "X", materials: ["A#1"] }
        };
        SynthesisIndex.reset();
        var arr:Array = SynthesisIndex.getRecipesUsing("不存在的材料");
        assert(arr != null, "getRecipesUsing missing returns non-null");
        assert(arr.length == 0, "getRecipesUsing missing returns empty array");
        _root.改装清单对象 = saved;
        SynthesisIndex.reset();
    }

    private static function test_getRecipesUsing_emptyData():Void {
        var saved = _root.改装清单对象;
        _root.改装清单对象 = undefined;
        SynthesisIndex.reset();
        var arr:Array = SynthesisIndex.getRecipesUsing("任意");
        assert(arr != null && arr.length == 0, "getRecipesUsing emptyData returns empty array");
        _root.改装清单对象 = saved;
        SynthesisIndex.reset();
    }

    /**
     * 反向索引应字典序输出，且单配方内同材料只记一次产物。
     * 输入故意非字典序声明 + 含同材料重复，验证：
     *   - 排序：B/A/C/D 输入应排序为 A/B/C/D 输出
     *   - 去重：配方 D 的 materials = [输入#1, 输入#2] 应只产生一个 D
     */
    private static function test_getRecipesUsing_sortedAndDedup():Void {
        var saved = _root.改装清单对象;
        _root.改装清单对象 = {
            B: { name: "B", materials: ["共用输入##1"] },
            A: { name: "A", materials: ["共用输入##1"] },
            C: { name: "C", materials: ["共用输入##1"] },
            D: { name: "D", materials: ["共用输入#1", "共用输入#2"] }
        };
        SynthesisIndex.reset();
        var arr:Array = SynthesisIndex.getRecipesUsing("共用输入");
        assert(arr.length == 4, "sort+dedup: length=4 (D recorded once) actual=" + arr.length);
        assert(arr[0] == "A" && arr[1] == "B" && arr[2] == "C" && arr[3] == "D",
               "sort+dedup: alphabetical order ABCD - actual=" + arr.join(","));
        _root.改装清单对象 = saved;
        SynthesisIndex.reset();
    }

    /** exact reverse-use 必须绕过 product→single recipe 的后写覆盖。 */
    private static function test_getRecipeUses_exactOccurrences():Void {
        var savedList = _root.改装清单;
        var savedMap = _root.改装清单对象;
        _root.改装清单 = {};
        _root.改装清单["基础防具"] = [
            {name:"Andy套装碎片", materials:["国庆纪念币#1", "国庆纪念币#2"]},
            {name:"Andy套装碎片", materials:["月之碎片#1"]},
            {name:"Andy套装碎片", materials:["剑圣碎片#1"]}
        ];
        _root.改装清单对象 = {};
        _root.改装清单对象["Andy套装碎片"] = _root.改装清单["基础防具"][2];
        SynthesisIndex.reset();
        var first:Array = SynthesisIndex.getRecipeUses("国庆纪念币");
        var second:Array = SynthesisIndex.getRecipeUses("月之碎片");
        var third:Array = SynthesisIndex.getRecipeUses("剑圣碎片");
        assert(first.length == 1 && first[0].category == "基础防具"
                && first[0].recipeIndex == 0
                && first[0].productName == "Andy套装碎片",
            "getRecipeUses keeps first same-product occurrence and de-dupes one recipe");
        assert(second.length == 1 && second[0].recipeIndex == 1
                && third.length == 1 && third[0].recipeIndex == 2,
            "getRecipeUses keeps all three Andy occurrence identities");
        _root.改装清单 = savedList;
        _root.改装清单对象 = savedMap;
        SynthesisIndex.reset();
    }

    /** output reverse index keeps duplicate outputs and authored category order. */
    private static function test_getRecipesProducing_exactAuthoredOrder():Void {
        var savedList = _root.改装清单;
        var savedOrder = _root.改装分类顺序;
        _root.改装分类顺序 = ["武器合成", "基础防具"];
        _root.改装清单 = {};
        _root.改装清单["武器合成"] = [
            {recipeId:"craft.weapon.001", title:"武器图纸", name:"嵌套产物", materials:[]}
        ];
        _root.改装清单["基础防具"] = [
            {recipeId:"craft.armor.001", title:"防具图纸一", name:"嵌套产物", materials:[]},
            {recipeId:"craft.armor.002", title:"防具图纸二", name:"嵌套产物", materials:[]}
        ];
        SynthesisIndex.reset();
        var sources:Array = SynthesisIndex.getRecipesProducing("嵌套产物");
        assert(sources.length == 3, "getRecipesProducing keeps all output occurrences");
        assert(sources[0].category == "武器合成" && sources[0].recipeIndex == 0
                && sources[0].recipeId == "craft.weapon.001",
            "getRecipesProducing starts with authored first category");
        assert(sources[1].category == "基础防具" && sources[1].recipeIndex == 0
                && sources[2].recipeIndex == 1,
            "getRecipesProducing keeps exact indexes inside authored category");
        assert(sources[2].title == "防具图纸二",
            "getRecipesProducing projects exact authored title");
        _root.改装分类顺序 = undefined;
        SynthesisIndex.reset();
        assert(SynthesisIndex.getRecipesProducing("嵌套产物").length == 0,
            "getRecipesProducing fails closed without authored category registry");
        _root.改装清单 = savedList;
        _root.改装分类顺序 = savedOrder;
        SynthesisIndex.reset();
    }
}
