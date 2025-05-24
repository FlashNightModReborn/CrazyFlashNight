import org.flashNight.gesh.func.FunctionUtil;

// 定义一个原始函数
var myFunction:Function = function() {
    trace("原始函数被调用，参数: " + arguments);
};

// 添加重载方法：接收 (number, string) 类型的参数
myFunction = FunctionUtil.addMethod(myFunction, "number", "string", function(num:Number, str:String):Void {
    trace("重载函数被调用，参数类型为 Number 和 String: " + num + ", " + str);
});

// 添加重载方法：接收 (string) 类型的参数
myFunction = FunctionUtil.addMethod(myFunction, "string", function(str:String):Void {
    trace("重载函数被调用，参数类型为 String: " + str);
});

// 添加重载方法：接收 (object) 类型的参数
myFunction = FunctionUtil.addMethod(myFunction, "object", function(obj:Object):Void {
    trace("重载函数被调用，参数类型为 Object: " + obj);
});

// 添加重载方法：接收 (array) 类型的参数
myFunction = FunctionUtil.addMethod(myFunction, "array", function(arr:Array):Void {
    trace("重载函数被调用，参数类型为 Array: " + arr);
});

// 添加重载方法：接收 (null) 类型的参数
myFunction = FunctionUtil.addMethod(myFunction, "null", function(n):Void {
    trace("重载函数被调用，参数类型为 Null: " + n);
});

// 添加重载方法：接收 (boolean) 类型的参数
myFunction = FunctionUtil.addMethod(myFunction, "boolean", function(flag:Boolean):Void {
    trace("重载函数被调用，参数类型为 Boolean: " + flag);
});

// 添加重载方法：接收 (function) 类型的参数
myFunction = FunctionUtil.addMethod(myFunction, "function", function(fn:Function):Void {
    trace("重载函数被调用，参数类型为 Function.");
});

// 添加重载方法：无参数
myFunction = FunctionUtil.addMethod(myFunction, function():Void {
    trace("重载函数被调用，无参数.");
});

// 添加重载方法：接收 (number) 类型的单个参数
myFunction = FunctionUtil.addMethod(myFunction, "number", function(num:Number):Void {
    trace("重载函数被调用，参数类型为 Number: " + num);
});

// 测试用例

// 1. 精确匹配：(number, string)
myFunction(42, "Hello");           // 预期: 调用 (number, string) 重载

// 2. 精确匹配：(string)
myFunction("Only one string");     // 预期: 调用 (string) 重载

// 3. 精确匹配：(boolean)
myFunction(true);                  // 预期: 调用 (boolean) 重载

// 4. 无参数调用
myFunction();                      // 预期: 调用无参数重载

// 5. 精确匹配：(object)
myFunction({ key: "value" });      // 预期: 调用 (object) 重载

// 6. 精确匹配：(null)
myFunction(null);                  // 预期: 调用 (null) 重载

// 7. 精确匹配：(array)
myFunction([1, 2, 3]);             // 预期: 调用 (array) 重载

// 8. 精确匹配：(function)
myFunction(function() { trace("匿名函数被调用"); }); // 预期: 调用 (function) 重载

// 9. 精确匹配：(number)
myFunction(100);                   // 预期: 调用 (number) 重载

// 10. 类型不匹配但参数数量匹配，触发参数数量匹配的回退逻辑
myFunction("Fallback test", 123);  // 预期: 调用 (number, string) 重载（参数数量匹配）

// 11. 参数数量和类型均不匹配，调用原始函数
myFunction("Extra", "arguments", true);  // 预期: 调用原始函数

// 12. 使用 undefined 作为参数
myFunction(undefined);             // 预期: 调用原始函数

// 13. 使用 NaN 作为参数
myFunction(NaN);                   // 预期: 调用原始函数

// 14. 单个 number 参数
myFunction(42);                    // 预期: 调用 (number) 重载

// 15. 两个 string 参数，参数数量匹配但类型不匹配，触发回退逻辑
myFunction("Test", "Another");     // 预期: 调用 (number, string) 重载（参数数量匹配）

// 16. 三个参数，未定义的重载，调用原始函数
myFunction(1, 2, 3);               // 预期: 调用原始函数

// 17. 测试 typeof 函数直接调用
function testTypeof(input):Void {
    trace("输入: " + input + " | typeof: " + typeof(input));
}

// 18. 基本类型测试
testTypeof(42);                 // 预期: number
testTypeof("Hello, World!");    // 预期: string
testTypeof(true);               // 预期: boolean
testTypeof(null);               // 预期: object
testTypeof(undefined);          // 预期: undefined

// 19. 对象类型测试
testTypeof({ key: "value" });   // 预期: object
testTypeof([1, 2, 3]);          // 预期: object (数组在 AS2 中被视为对象)

// 20. 函数类型测试
testTypeof(function() {});      // 预期: function

// 21. 特殊情况测试
testTypeof("");                 // 预期: string
testTypeof(0);                  // 预期: number
testTypeof(NaN);                // 预期: number (但在代码中被处理为 'nan')
testTypeof(new Object());       // 预期: object
testTypeof(new Array());        // 预期: object




重载函数被调用，参数类型为 Number 和 String: 42, Hello
重载函数被调用，参数类型为 String: Only one string
重载函数被调用，参数类型为 Boolean: true
重载函数被调用，无参数.
重载函数被调用，参数类型为 Object: [object Object]
重载函数被调用，参数类型为 Object: null
重载函数被调用，参数类型为 Array: 1,2,3
重载函数被调用，参数类型为 Function.
重载函数被调用，参数类型为 Number: 100
重载函数被调用，参数类型为 Number 和 String: Fallback test, 123
原始函数被调用，参数: Extra,arguments,true
重载函数被调用，参数类型为 String: undefined
重载函数被调用，参数类型为 String: NaN
重载函数被调用，参数类型为 Number: 42
重载函数被调用，参数类型为 Number 和 String: Test, Another
原始函数被调用，参数: 1,2,3
输入: 42 | typeof: number
输入: Hello, World! | typeof: string
输入: true | typeof: boolean
输入: null | typeof: null
输入: undefined | typeof: undefined
输入: [object Object] | typeof: object
输入: 1,2,3 | typeof: object
输入: [type Function] | typeof: function
输入:  | typeof: string
输入: 0 | typeof: number
输入: NaN | typeof: number
输入: [object Object] | typeof: object
输入:  | typeof: object