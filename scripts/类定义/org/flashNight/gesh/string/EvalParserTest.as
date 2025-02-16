import org.flashNight.gesh.string.EvalParser;

class org.flashNight.gesh.string.EvalParserTest {
    private static var testObj:Object;

    // 初始化测试对象
    private static function initializeTestObj():Void {
        testObj = {
            user: {
                name: "John",
                age: 30,
                address: [{
                    street: "Main St",
                    city: "Springfield"
                }, {
                    street: "Broadway",
                    city: "New York"
                }],
                getName: function() {
                    return this.name;
                },
                setName: function(newName:String) {
                    this.name = newName;
                    return this.name;
                },
                getAddress: function() {
                    return this.address[1];
                },
                setAddress: function(index:Number, newAddress:Object) {
                    if(index >=0 && index < this.address.length){
                        this.address[index] = newAddress;
                        return true;
                    }
                    return false;
                }
            }
        };
    }

    private static function assertEquals(expected:Object, actual:Object, testName:String):Void {
        var condition:Boolean = (expected == actual) || (expected === actual);
        if (!condition) {
            trace(testName + " 失败：期望值 " + expected + "，实际值 " + actual);
        } else {
            trace(testName + " 通过");
        }
    }

    private static function stringifyPath(path:Array):String {
        var result:String = "";
        for (var i:Number = 0; i < path.length; i++) {
            var part:Object = path[i];
            if (part.type == "function") {
                result += "{type:" + part.type + ",value:" + part.value.name + "}";
            } else {
                result += "{type:" + part.type + ",value:" + part.value + "}";
            }
            if (i < path.length - 1) result += ",";
        }
        return result;
    }

    // 测试用例
    public static function test1_PathParsing():Void {
        var parsedPath:Array = EvalParser.parsePath("user.address[1].city");
        var expected:String = "{type:property,value:user},{type:property,value:address},{type:index,value:1},{type:property,value:city}";
        assertEquals(expected, stringifyPath(parsedPath), "测试1：路径解析");
    }

    public static function test2_SetUserName():Void {
        initializeTestObj();
        var result:Boolean = EvalParser.setPropertyValue(testObj, "user.name", "Doe");
        assertEquals(true, result && testObj.user.name == "Doe", "测试2：设置 user.name");
    }

    public static function test3_SetAddressCity():Void {
        initializeTestObj();
        var result:Boolean = EvalParser.setPropertyValue(testObj, "user.address[1].city", "Los Angeles");
        assertEquals(true, result && testObj.user.address[1].city == "Los Angeles", "测试3：设置 address[1].city");
    }

    public static function test4_InvalidSetPath():Void {
        initializeTestObj();
        var result:Boolean = EvalParser.setPropertyValue(testObj, "user.nonExistent.street", "Unknown");
        assertEquals(false, result, "测试4：无效路径设置");
    }

    public static function test5_GetUserName():Void {
        initializeTestObj();
        var value:Object = EvalParser.getPropertyValue(testObj, "user.name");
        assertEquals("John", value, "测试5：获取 user.name");
    }

    public static function test6_GetAddressStreet():Void {
        initializeTestObj();
        var value:Object = EvalParser.getPropertyValue(testObj, "user.address[0].street");
        assertEquals("Main St", value, "测试6：获取 address[0].street");
    }

    public static function test7_InvalidGetPath():Void {
        initializeTestObj();
        var value:Object = EvalParser.getPropertyValue(testObj, "user.nonExistent.street");
        assertEquals(undefined, value, "测试7：无效路径获取");
    }

    public static function test8_FunctionCallGet():Void {
        initializeTestObj();
        var value:Object = EvalParser.getPropertyValue(testObj, "user.getName()");
        assertEquals("John", value, "测试8：调用 getName()");
    }

    public static function test9_FunctionCallSet():Void {
        initializeTestObj();
        var result:Boolean = EvalParser.setPropertyValue(testObj, "user.setName('Alice')", "Alice");
        assertEquals(true, result && testObj.user.name == "Alice", "测试9：调用 setName('Alice')");
    }

    public static function test10_ChainedFunctionGet():Void {
        initializeTestObj();
        EvalParser.setPropertyValue(testObj, "user.address[1].city", "Los Angeles");
        var value:Object = EvalParser.getPropertyValue(testObj, "user.getAddress().city");
        assertEquals("Los Angeles", value, "测试10：调用 getAddress().city");
    }

    public static function test11_FunctionCallWithParams():Void {
        initializeTestObj();
        var result:Boolean = EvalParser.setPropertyValue(testObj, "user.setAddress(1)", {street: "5th Ave", city: "Chicago"});
        assertEquals(true, result && testObj.user.address[1].city == "Chicago", "测试11：调用 setAddress(1)");
    }

    public static function test12_ChainedMethodCall():Void {
        initializeTestObj();
        var setResult:Boolean = EvalParser.setPropertyValue(testObj, "user.setName('Bob')", "Bob");
        if(setResult && testObj.user.name == "Bob") {
            var upperValue:String = testObj.user.setName('Bob').toUpperCase();
            var finalResult:Boolean = EvalParser.setPropertyValue(testObj, "user.name", upperValue);
            assertEquals(true, finalResult && testObj.user.name == "BOB", "测试12：链式函数调用");
        } else {
            assertEquals(true, false, "测试12：链式函数调用");
        }
    }

    // 性能测试
    private static function runPerformanceTest(testName:String, testFunction:Function):Void {
        var start:Number = getTimer();
        testFunction();
        trace(testName + " 耗时: " + (getTimer() - start) + "ms");
    }

    public static function testParsePathPerformance():Void {
        runPerformanceTest("路径解析性能测试", function() {
            for(var i=0; i<1000; i++){
                EvalParser.parsePath("user.address[1].city.toUpperCase()");
            }
        });
    }

    public static function testSetPropertyPerformance():Void {
        initializeTestObj();
        runPerformanceTest("属性设置性能测试", function() {
            for(var i=0; i<1000; i++){
                EvalParser.setPropertyValue(testObj, "user.address[0].city", "TestCity");
            }
        });
    }

    // 运行所有测试
    public static function runAllTests():Void {
        trace("=== 开始单元测试 ===");
        test1_PathParsing();
        test2_SetUserName();
        test3_SetAddressCity();
        test4_InvalidSetPath();
        test5_GetUserName();
        test6_GetAddressStreet();
        test7_InvalidGetPath();
        test8_FunctionCallGet();
        test9_FunctionCallSet();
        test10_ChainedFunctionGet();
        test11_FunctionCallWithParams();
        test12_ChainedMethodCall();
        
        trace("\n=== 开始性能测试 ===");
        testParsePathPerformance();
        testSetPropertyPerformance();
    }
}