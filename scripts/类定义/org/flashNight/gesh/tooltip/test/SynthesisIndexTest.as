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
}