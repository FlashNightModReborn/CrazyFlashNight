import org.flashNight.naki.Sort.TestDataGenerator;
import org.flashNight.naki.Sort.PDQSort;

class org.flashNight.naki.Sort.DebugDataGenerator {
    
    /**
     * 调试数据生成器，检查特定模式
     */
    public static function debugSpecificPatterns():Void {
        trace("=== Debugging Data Generator Patterns ===\n");
        
        // 测试小数组的各种模式
        var size:Number = 20;
        
        trace("Size: " + size);
        trace("----------------------------------------");
        
        // 测试sawtooth模式
        debugPattern("sawtooth2", size);
        debugPattern("sawtooth4", size);
        debugPattern("sawtooth8", size);
        
        // 测试organPipe
        debugPattern("organPipe", size);
        
        // 测试manyDuplicates
        debugPattern("manyDuplicates", size);
    }
    
    private static function debugPattern(pattern:String, size:Number):Void {
        trace("\n--- " + pattern + " ---");
        
        // 生成数据
        var data:Array = TestDataGenerator.generate(size, pattern);
        
        // 显示原始数据
        trace("Original: " + arrayToString(data));
        
        // 排序
        var sorted:Array = data.slice();
        PDQSort.sort(sorted, null);
        
        // 显示排序结果
        trace("Sorted:   " + arrayToString(sorted));
        
        // 检查正确性
        var isCorrect:Boolean = verifySorted(sorted);
        trace("Correct:  " + (isCorrect ? "✓" : "✗"));
        
        if (!isCorrect) {
            trace("ERROR: Sorting failed for " + pattern);
            // 显示预期结果
            var expected:Array = data.slice();
            expected.sort(Array.NUMERIC);
            trace("Expected: " + arrayToString(expected));
        }
    }
    
    private static function arrayToString(arr:Array):String {
        var result:String = "[";
        for (var i:Number = 0; i < arr.length; i++) {
            if (i > 0) result += ", ";
            result += arr[i];
            if (i >= 15) {  // 限制显示长度
                result += "...";
                break;
            }
        }
        result += "]";
        return result;
    }
    
    private static function verifySorted(arr:Array):Boolean {
        for (var i:Number = 1; i < arr.length; i++) {
            if (Number(arr[i-1]) > Number(arr[i])) {
                return false;
            }
        }
        return true;
    }
}