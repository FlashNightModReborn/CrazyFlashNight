
class org.flashNight.aven.test.Assertions {
    public static function assertEquals(expected:Object, actual:Object, message:String):Void {
        if (!org.flashNight.aven.test.TestUtils.deepEquals(expected, actual, 0)) {
            throw new Error("Assertion Failed: " + message + ". Expected: " + org.flashNight.aven.test.TestUtils.stringify(expected) + ", Actual: " + org.flashNight.aven.test.TestUtils.stringify(actual));
        }
    }

    public static function assertTrue(condition:Boolean, message:String):Void {
        if (!condition) {
            throw new Error("Assertion Failed: " + message);
        }
    }

    // 可以添加更多的断言方法
}
