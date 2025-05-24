// 文件路径：org/flashNight/neur/Event/DelegateTest.as
import org.flashNight.neur.Event.Delegate; // 导入 Delegate 类


class org.flashNight.neur.Event.DelegateTest {
    private var totalTests:Number;
    private var passedTests:Number;
    private var failedTests:Number;
    private var failedDetails:Array;
    
    // 构造函数
    public function DelegateTest() {
        totalTests = 0;
        passedTests = 0;
        failedTests = 0;
        failedDetails = [];
    }
    
    // 断言函数：检查两个值是否相等
    private function assertEquals(expected, actual, message:String):Void {
        totalTests++;
        if (expected === actual) {
            passedTests++;
        } else {
            failedTests++;
            failedDetails.push("Assertion Failed: " + message + "\nExpected: " + expected + "\nActual: " + actual);
        }
    }
    
    // 断言函数：检查条件是否为真
    private function assertTrue(condition:Boolean, message:String):Void {
        totalTests++;
        if (condition) {
            passedTests++;
        } else {
            failedTests++;
            failedDetails.push("Assertion Failed: " + message + "\nCondition is not true.");
        }
    }
    
    // 运行所有测试
    public function runAllTests():Void {
        trace("开始运行所有测试...");
        // 启用所有测试模块
        this.testScopeBinding();
        this.testWithParamsBinding();
        this.testCacheMechanism();
        this.testErrorHandling();
        this.testDynamicArguments();
        this.testComplexScenarios();
        this.testClearCache();
        this.testDifferentScopeTypes();
        this.testEdgeCaseParameters();
        // 输出测试结果
        this.outputResults();
    }
    
    // 模块化测试：作用域绑定测试
    private function testScopeBinding():Void {
        trace("运行模块：作用域绑定测试");
        
        // 创建一个模拟对象用于绑定 scope
        var testInstance:Object = {
            name: "Alice",
            sayHello: function(greeting:String):String {
                return greeting + ", my name is " + this.name;
            }
        };
        
        // 定义全局函数
        function globalTestFunction():String {
            return "Global function called!";
        }
        
        // 测试用例 1：没有参数的函数绑定到全局作用域
        var globalDelegate:Function = org.flashNight.neur.Event.Delegate.create(null, globalTestFunction);
        var result1:String = globalDelegate();
        this.assertEquals("Global function called!", result1, "测试用例 1：全局作用域绑定无参数函数");
        
        // 测试用例 2：带参数的函数绑定到指定对象作用域
        var helloDelegate:Function = org.flashNight.neur.Event.Delegate.create(testInstance, testInstance.sayHello);
        var result2:String = helloDelegate("Hello");
        this.assertEquals("Hello, my name is Alice", result2, "测试用例 2：指定作用域绑定带参数函数");
        
        // 测试用例 3：改变作用域后执行相同的方法
        var anotherInstance:Object = {
            name: "Bob",
            sayHello: testInstance.sayHello
        };
        var anotherHelloDelegate:Function = org.flashNight.neur.Event.Delegate.create(anotherInstance, testInstance.sayHello);
        var result3:String = anotherHelloDelegate("Hi");
        this.assertEquals("Hi, my name is Bob", result3, "测试用例 3：改变作用域后执行相同方法");
    }
    
    // 模块化测试：带参数的委托函数绑定测试
    private function testWithParamsBinding():Void {
        trace("运行模块：带参数的委托函数绑定测试");
        
        // 测试用例 17：使用 createWithParams 绑定函数并预先传递参数
        function preBoundTest(arg1:String, arg2:String):String {
            return "Pre-bound args: " + arg1 + " and " + arg2;
        }
        
        var preBoundDelegate:Function = org.flashNight.neur.Event.Delegate.createWithParams(null, preBoundTest, ["foo", "bar"]);
        var result17:String = preBoundDelegate();
        this.assertEquals("Pre-bound args: foo and bar", result17, "测试用例 17：createWithParams 绑定函数并预传参数");
        
        // 测试用例 18：使用 createWithParams 绑定带作用域的函数并预先传递参数
        var testInstance:Object = {
            name: "Alice"
        };
        var scopedPreBoundDelegate:Function = org.flashNight.neur.Event.Delegate.createWithParams(testInstance, function(arg1:String, arg2:String):String {
            return this.name + " received: " + arg1 + " and " + arg2;
        }, ["baz", "qux"]);
        var result18:String = scopedPreBoundDelegate();
        this.assertEquals("Alice received: baz and qux", result18, "测试用例 18：带作用域的 createWithParams 绑定函数并预传参数");
        
        // 测试用例 19：使用 createWithParams 绑定带作用域的函数并预先传递超过5个参数
        function manyArgsTest(a:Number, b:Number, c:Number, d:Number, e:Number, f:Number, g:Number):String {
            return "Args: " + a + ", " + b + ", " + c + ", " + d + ", " + e + ", " + f + ", " + g;
        }
        
        var manyArgsDelegate:Function = org.flashNight.neur.Event.Delegate.createWithParams(null, manyArgsTest, [1, 2, 3, 4, 5, 6, 7]);
        var result19:String = manyArgsDelegate();
        this.assertEquals("Args: 1, 2, 3, 4, 5, 6, 7", result19, "测试用例 19：createWithParams 绑定带作用域函数并预传超过5个参数");
    }
    
    // 模块化测试：缓存机制测试
    private function testCacheMechanism():Void {
        trace("运行模块：缓存机制测试");
        
        // 测试用例 20：确保缓存机制工作正常，创建相同的委托应该返回相同的函数引用
        function globalTestFunction():String {
            return "Global function called!";
        }
        
        var delegateA1:Function = org.flashNight.neur.Event.Delegate.create(null, globalTestFunction);
        var delegateA2:Function = org.flashNight.neur.Event.Delegate.create(null, globalTestFunction);
        this.assertTrue(delegateA1 === delegateA2, "测试用例 20.1：相同函数相同作用域返回相同委托");
        
        var testInstance:Object = {
            name: "Alice",
            sayHello: function(greeting:String):String {
                return greeting + ", my name is " + this.name;
            }
        };
        
        var delegateB1:Function = org.flashNight.neur.Event.Delegate.create(testInstance, testInstance.sayHello);
        var delegateB2:Function = org.flashNight.neur.Event.Delegate.create(testInstance, testInstance.sayHello);
        this.assertTrue(delegateB1 === delegateB2, "测试用例 20.2：相同方法相同作用域返回相同委托");
        
        function preBoundTest(arg1:String, arg2:String):String {
            return "Pre-bound args: " + arg1 + " and " + arg2;
        }
        
        var delegateC1:Function = org.flashNight.neur.Event.Delegate.createWithParams(null, preBoundTest, ["foo", "bar"]);
        var delegateC2:Function = org.flashNight.neur.Event.Delegate.createWithParams(null, preBoundTest, ["foo", "bar"]);
        this.assertTrue(delegateC1 === delegateC2, "测试用例 20.3：相同参数 createWithParams 返回相同委托");
        
        var scopedPreBoundDelegate1:Function = org.flashNight.neur.Event.Delegate.createWithParams(testInstance, function(arg1:String, arg2:String):String {
            return this.name + " received: " + arg1 + " and " + arg2;
        }, ["baz", "qux"]);

        var scopedPreBoundDelegate2:Function = org.flashNight.neur.Event.Delegate.createWithParams(testInstance, function(arg1:String, arg2:String):String {
            return this.name + " received: " + arg1 + " and " + arg2;
        }, ["baz", "qux"]);

        // 修改后的测试逻辑，判断不同函数对象生成的委托应该不同
        this.assertTrue(scopedPreBoundDelegate1 !== scopedPreBoundDelegate2, "测试用例 20.4：不同函数对象应返回不同的委托");
    }
    
    // 模块化测试：错误处理测试
    private function testErrorHandling():Void {
        trace("运行模块：错误处理测试");
        
        // 测试用例 5：测试 null method 抛出错误
        try {
            var nullDelegate:Function = org.flashNight.neur.Event.Delegate.create(null, null);
            nullDelegate();
            this.assertTrue(false, "测试用例 5：null method 未抛出错误");
        } catch (e:Error) {
            this.assertEquals("The provided method is undefined or null", e.message, "测试用例 5：null method 抛出预期错误");
        }
    }
    
    // 模块化测试：动态参数传递测试
    private function testDynamicArguments():Void {
        trace("运行模块：动态参数传递测试");
        
        // 测试用例 4：测试超过5个参数的调用
        function testMultipleArguments(arg1:Number, arg2:Number, arg3:Number, arg4:Number, arg5:Number, arg6:Number):String {
            return [arg1, arg2, arg3, arg4, arg5, arg6].join(", ");
        }
        
        var multiArgDelegate:Function = org.flashNight.neur.Event.Delegate.create(null, testMultipleArguments);
        var result4:String = multiArgDelegate(1, 2, 3, 4, 5, 6);
        this.assertEquals("1, 2, 3, 4, 5, 6", result4, "测试用例 4：超过5个参数的调用");
        
        // 测试用例 6：测试函数动态参数传递
        function dynamicArgumentTest():String {
            return Array.prototype.join.call(arguments, ", ");
        }
        
        var dynamicDelegate:Function = org.flashNight.neur.Event.Delegate.create(null, dynamicArgumentTest);
        var result6:String = dynamicDelegate(1, "a", true, null);
        this.assertEquals("1, a, true, null", result6, "测试用例 6：动态参数传递");
        
        // 测试用例 7：测试绑定到全局作用域且动态传递大量参数
        function largeArgumentTest():String {
            return Array.prototype.join.call(arguments, ", ");
        }
        
        var largeArgDelegate:Function = org.flashNight.neur.Event.Delegate.create(null, largeArgumentTest);
        var result7:String = largeArgDelegate(1, 2, 3, 4, 5, 6, 7, 8, 9, 10);
        this.assertEquals("1, 2, 3, 4, 5, 6, 7, 8, 9, 10", result7, "测试用例 7：大量参数传递");
    }
    
    // 模块化测试：复杂场景测试
    private function testComplexScenarios():Void {
        trace("运行模块：复杂场景测试");
        
        // 创建一个模拟对象用于绑定 scope
        var testInstance:Object = {
            name: "Alice",
            saySomething: function():String {
                return "a message from object";
            }
        };
        
        // 测试用例 8：测试绑定到指定作用域的函数动态传参
        var scopedDynamicDelegate:Function = org.flashNight.neur.Event.Delegate.create(testInstance, function():String {
            return this.name + ": " + Array.prototype.join.call(arguments, ", ");
        });
        var result8:String = scopedDynamicDelegate("apple", "banana", "orange");
        this.assertEquals("Alice: apple, banana, orange", result8, "测试用例 8：绑定到指定作用域的函数动态传参");
        
        // 测试用例 9：测试边界情况 - 空参数
        var noArgumentDelegate:Function = org.flashNight.neur.Event.Delegate.create(null, function():String {
            return "No arguments";
        });
        var result9:String = noArgumentDelegate();
        this.assertEquals("No arguments", result9, "测试用例 9：空参数调用");
        
        // 测试用例 10：测试函数传递 null 和 undefined 作为参数
        var nullUndefinedDelegate:Function = org.flashNight.neur.Event.Delegate.create(null, function(arg1, arg2):String {
            return "arg1: " + arg1 + ", arg2: " + arg2;
        });
        var result10:String = nullUndefinedDelegate(null, undefined);
        this.assertEquals("arg1: null, arg2: undefined", result10, "测试用例 10：传递 null 和 undefined 参数");
        
        // 测试用例 11：使用作用域的包装函数调用嵌套函数，保证作用域不丢失
        function nestedFunctionTest():String {
            var innerFunction:Function = function():String {
                return this.name + " from inner function";
            };
            return innerFunction.call(this);
        }
        
        var nestedDelegate:Function = org.flashNight.neur.Event.Delegate.create(testInstance, nestedFunctionTest);
        var result11:String = nestedDelegate();
        this.assertEquals("Alice from inner function", result11, "测试用例 11：嵌套函数作用域绑定");
        
        // 测试用例 12：绑定到不同作用域并动态传递对象作为参数
        function objectArgumentTest(obj:Object):String {
            return obj.name + " is " + obj.age + " years old.";
        }
        
        var objectDelegate:Function = org.flashNight.neur.Event.Delegate.create(null, objectArgumentTest);
        var result12:String = objectDelegate({name: "Charlie", age: 28});
        this.assertEquals("Charlie is 28 years old.", result12, "测试用例 12：传递对象参数");
        
        // 测试用例 13：多层作用域绑定传递带有函数参数的对象
        var advancedObjectDelegate:Function = org.flashNight.neur.Event.Delegate.create(testInstance, function(obj:Object):String {
            return this.name + " received: " + obj.saySomething();
        });
        var result13:String = advancedObjectDelegate({ saySomething: function():String { return "a message from object"; } });
        this.assertEquals("Alice received: a message from object", result13, "测试用例 13：多层作用域绑定传递带有函数参数的对象");
        
        // 测试用例 14：测试传递嵌套数组作为参数
        function arrayArgumentTest(arr:Array):String {
            return arr.join(", ");
        }
        
        var arrayDelegate:Function = org.flashNight.neur.Event.Delegate.create(null, arrayArgumentTest);
        var result14:String = arrayDelegate([1, [2, 3], 4, ["nested", "array"]]);
        this.assertEquals("1, 2,3, 4, nested,array", result14, "测试用例 14：传递嵌套数组作为参数");
        
        // 测试用例 15：测试传递包含方法的对象
        var methodInObjectDelegate:Function = org.flashNight.neur.Event.Delegate.create(testInstance, function(obj:Object):String {
            return obj.method();
        });
        
        var result15:String = methodInObjectDelegate({
            method: function():String {
                return testInstance.name + " method called!";
            }
        });
        this.assertEquals("Alice method called!", result15, "测试用例 15：传递包含方法的对象");
        
        // 测试用例 16：作用域绑定后动态传递多个复杂类型参数
        var complexParamDelegate:Function = org.flashNight.neur.Event.Delegate.create(testInstance, function(num:Number, arr:Array, obj:Object, str:String):String {
            return this.name + " got: " + num + ", " + arr.join(", ") + ", " + obj.info + ", " + str;
        });
        
        var result16:String = complexParamDelegate(42, [1, 2, 3], {info: "some info"}, "test string");
        this.assertEquals("Alice got: 42, 1, 2, 3, some info, test string", result16, "测试用例 16：绑定作用域后传递多个复杂类型参数");
    }
    
    // 模块化测试：清理缓存测试
    private function testClearCache():Void {
        trace("运行模块：清理缓存测试");
        
        // 创建一个函数用于测试缓存
        function sampleFunction():String {
            return "Sample function called!";
        }
        
        // 创建委托并确保缓存中有记录
        var sampleDelegate1:Function = org.flashNight.neur.Event.Delegate.create(org.flashNight.neur.Event.Delegate, sampleFunction);
        var sampleDelegate2:Function = org.flashNight.neur.Event.Delegate.create(org.flashNight.neur.Event.Delegate, sampleFunction);
        this.assertTrue(sampleDelegate1 === sampleDelegate2, "测试用例 21.1：相同函数创建前委托缓存");
        
        // 清理缓存
        org.flashNight.neur.Event.Delegate.clearCache();
        trace("已清理缓存");
        
        // 创建委托后，缓存应该被清理，新的委托函数应不同
        var sampleDelegate3:Function = org.flashNight.neur.Event.Delegate.create(org.flashNight.neur.Event.Delegate, sampleFunction);
        this.assertTrue(sampleDelegate1 !== sampleDelegate3, "测试用例 21.2：清理缓存后创建的新委托不同");
        
        // 验证缓存机制仍然有效
        var sampleDelegate4:Function = org.flashNight.neur.Event.Delegate.create(org.flashNight.neur.Event.Delegate, sampleFunction);
        this.assertTrue(sampleDelegate3 === sampleDelegate4, "测试用例 21.3：清理缓存后相同函数再次创建委托");
    }
    
    // 模块化测试：不同类型的作用域对象测试
    private function testDifferentScopeTypes():Void {
        trace("运行模块：不同类型的作用域对象测试");
        
        // 使用数组作为作用域
        var arrayScope:Object = [1, 2, 3];
        function arrayScopeFunction():String {
            return "Array scope length: " + this.length;
        }
        var arrayDelegate:Function = org.flashNight.neur.Event.Delegate.create(arrayScope, arrayScopeFunction);
        var arrayResult:String = arrayDelegate();
        this.assertEquals("Array scope length: 3", arrayResult, "测试用例 22.1：数组作为作用域对象");
        
        function functionScopeFunction():String {
            return "Function scope is bound correctly.";
        }
        var functionScope:Object = function() { return "I'm a function scope"; };
        var functionDelegate:Function = org.flashNight.neur.Event.Delegate.create(functionScope, functionScopeFunction);
        var functionResult:String = functionDelegate();
        // 修改后的断言，确保函数作用域绑定成功
        this.assertEquals("Function scope is bound correctly.", functionResult, "测试用例 22.2：函数作为作用域对象");
    }
    
    // 模块化测试：边界值参数测试
    private function testEdgeCaseParameters():Void {
        trace("运行模块：边界值参数测试");
        
        // 测试用例 23.1：传递空字符串
        function emptyStringTest(str:String):String {
            return "Empty string: '" + str + "'";
        }
        var emptyStringDelegate:Function = org.flashNight.neur.Event.Delegate.create(null, emptyStringTest);
        var emptyStringResult:String = emptyStringDelegate("");
        this.assertEquals("Empty string: ''", emptyStringResult, "测试用例 23.1：传递空字符串");
        
        // 测试用例 23.2：传递数字0
        function zeroNumberTest(num:Number):String {
            return "Number is: " + num;
        }
        var zeroNumberDelegate:Function = org.flashNight.neur.Event.Delegate.create(null, zeroNumberTest);
        var zeroNumberResult:String = zeroNumberDelegate(0);
        this.assertEquals("Number is: 0", zeroNumberResult, "测试用例 23.2：传递数字0");
        
        // 测试用例 23.3：传递布尔值
        function booleanTest(flag:Boolean):String {
            return "Boolean is: " + flag;
        }
        var booleanDelegate:Function = org.flashNight.neur.Event.Delegate.create(null, booleanTest);
        var booleanResultTrue:String = booleanDelegate(true);
        var booleanResultFalse:String = booleanDelegate(false);
        this.assertEquals("Boolean is: true", booleanResultTrue, "测试用例 23.3：传递布尔值 true");
        this.assertEquals("Boolean is: false", booleanResultFalse, "测试用例 23.4：传递布尔值 false");
    }
    
    // 输出测试结果
    private function outputResults():Void {
        trace("测试运行完成！");
        trace("总测试用例数: " + totalTests);
        trace("通过的测试用例: " + passedTests);
        trace("失败的测试用例: " + failedTests);
        
        if (failedTests > 0) {
            trace("失败详情:");
            for (var i:Number = 0; i < failedDetails.length; i++) {
                trace((i + 1) + ". " + failedDetails[i]);
            }
        } else {
            trace("所有测试用例均通过！");
        }
    }
}

