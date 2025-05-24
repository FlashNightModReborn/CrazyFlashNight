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

    private static var complexTestObj:Object;

    private static function initializeComplexTestObj():Void {
        // 创建一个空对象作为 complexTestObj
        complexTestObj = new Object();

        // 初始化 users 数组
        complexTestObj.users = new Array();

        // 创建第一个用户
        var user1: Object = new Object();
        user1.name = "Alice";
        user1["full.name"] = "Alice Smith";

        // 创建 contacts 对象
        var contacts1: Object = new Object();
        contacts1.emails = new Array("alice@work.com", "alice@home.com");

        // 定义 getPrimaryEmail 方法
        contacts1.getPrimaryEmail = function():String {
            return this.emails[0];
        };

        user1.contacts = contacts1;
        complexTestObj.users.push(user1);

        // 创建第二个用户
        var user2: Object = new Object();
        user2.name = "Bob";
        user2["full.name"] = "Robert Johnson";

        // 定义 getDisplayInfo 方法
        user2.getDisplayInfo = function(format:String):String {
            return (format == "short") ? this.name : this["full.name"];
        };

        complexTestObj.users.push(user2);

        // 创建 factory 对象
        complexTestObj.factory = new Object();

        // 定义 factory.create 方法
        complexTestObj.factory.create = function(className:String, params:Array):Object {
            return {type: className, args: params};
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



    // 新增测试用例
    public static function test13_NestedFunctionCalls():Void {
        initializeComplexTestObj();
        var value:Object = EvalParser.getPropertyValue(
            complexTestObj,
            'users[0].contacts.getPrimaryEmail()'
        );
        assertEquals("alice@work.com", value, "测试13：嵌套函数调用");
    }

    public static function test14_QuotedPropertyNames():Void {
        initializeComplexTestObj();
        var result:Boolean = EvalParser.setPropertyValue(
            complexTestObj,
            'users[1]["full.name"]',
            "Bob Marley"
        );
        var value:Object = EvalParser.getPropertyValue(
            complexTestObj,
            'users[1].getDisplayInfo("long")'
        );
        assertEquals(true, result && value == "Bob Marley", "测试14：带引号的属性名");
    }

    public static function test15_ComplexArgumentsParsing():Void {
        initializeComplexTestObj();
        var result:Boolean = EvalParser.setPropertyValue(
            complexTestObj,
            'factory.create("Employee", ["John", 30, {"dep": "IT"}])',
            null
        );
        var createdObj:Object = EvalParser.getPropertyValue(
            complexTestObj,
            'factory.create("Employee", ["John", 30, {"dep": "IT"}])'
        );
        assertEquals(
            true,
            result && createdObj.type == "Employee" && createdObj.args[2].dep == "IT",
            "测试15：复杂参数解析"
        );
    }

    public static function test16_MixedSyntaxPath():Void {
        initializeComplexTestObj();
        var value:Object = EvalParser.getPropertyValue(
            complexTestObj,
            'users[1].getDisplayInfo("short").length'
        );
        assertEquals(3, value, "测试16：混合语法路径");
    }

    public static function test17_ErrorHandling_InvalidIndex():Void {
        initializeComplexTestObj();
        var value:Object = EvalParser.getPropertyValue(
            complexTestObj,
            'users[5].name' // 越界索引
        );
        assertEquals(undefined, value, "测试17：无效数组索引处理");
    }

    public static function test18_CacheValidation():Void {
        var path1:String = "users[0].contacts.emails[1]";
        var path2:String = "users[0].contacts.emails[1]";
        var parsed1:Array = EvalParser.parsePath(path1);
        var parsed2:Array = EvalParser.parsePath(path2);
        
        // 修改缓存路径的异常测试
        parsed1.push("hack");
        assertEquals(
            4, 
            parsed2.length, 
            "测试18：缓存不可变性验证"
        );
    }

    public static function test19_EdgeCase_EmptyPath():Void {
        var value:Object = EvalParser.getPropertyValue(complexTestObj, "");
        assertEquals(complexTestObj, value, "测试19：空路径处理");
    }

    public static function test20_EdgeCase_DeepNesting():Void {
        var obj:Object = {a: {b: {c: {d: {e: {f: "deep"}}}}}};
        var result:Boolean = EvalParser.setPropertyValue(
            obj,
            "a.b.c.d.e.f",
            "deeper"
        );
        assertEquals(
            "deeper",
            EvalParser.getPropertyValue(obj, "a.b.c.d.e.f"),
            "测试20：深度嵌套路径"
        );
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

        trace("\n=== 开始扩展测试 ===");
        initializeComplexTestObj();
        test13_NestedFunctionCalls();
        test14_QuotedPropertyNames();
        test15_ComplexArgumentsParsing();
        test16_MixedSyntaxPath();
        test17_ErrorHandling_InvalidIndex();
        test18_CacheValidation();
        test19_EdgeCase_EmptyPath();
        test20_EdgeCase_DeepNesting();
        
        trace("\n=== 开始性能测试 ===");
        testParsePathPerformance();
        testSetPropertyPerformance();
    }
}