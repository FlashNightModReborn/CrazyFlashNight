import org.flashNight.gesh.string.StringUtils;
import org.flashNight.naki.Sort.InsertionSort;
import JSON;
import Base64;
import org.flashNight.gesh.toml.*;
import org.flashNight.gesh.fntl.*;
import org.flashNight.naki.DataStructures.Dictionary;

class org.flashNight.gesh.object.ObjectUtil {
    
    /**
     * 克隆一个对象，生成它的深拷贝。
     * @param obj 要克隆的对象。
     * @return 克隆后的新对象。
     */
    public static function clone(obj:Object) {
        var seenObjects:Dictionary = new Dictionary(); // 使用 Dictionary 追踪已处理的对象
        return cloneRecursive(obj, seenObjects);
    }

    /**
     * 递归克隆对象的辅助方法。
     * @param obj 当前要克隆的对象。
     * @param seenObjects 已处理对象的映射表。
     * @return 克隆后的对象。
     */
    private static function cloneRecursive(obj:Object, seenObjects:Dictionary):Object {
        if (obj == null || typeof(obj) != "object") {
            return obj;
        }

        // 检查对象是否已经被克隆过
        if (seenObjects.getItem(obj) != undefined) {
            return seenObjects.getItem(obj);
        }

        var copy:Object;

        // 处理 Date 对象
        if (obj instanceof Date) {
            return new Date(obj.getTime());
        }

        // 处理 RegExp 对象
        if (obj instanceof RegExp) {
            return new RegExp(obj.source, obj.flags);
        }

        // 处理 Array
        if (obj instanceof Array) {
            copy = [];
            seenObjects.setItem(obj, copy);  // 标记对象，防止循环引用
            for (var i:Number = 0; i < obj.length; i++) {
                copy[i] = cloneRecursive(obj[i], seenObjects);
            }
            return copy;
        }

        // 处理一般对象
        copy = {};
        seenObjects.setItem(obj, copy);  // 标记对象
        for (var key:String in obj) {
            if (obj.hasOwnProperty(key) && !isInternalKey(key)) {  // 忽略 __dictUID
                copy[key] = cloneRecursive(obj[key], seenObjects);
            }
        }

        return copy;
    }

    /**
     * 遍历对象的每个自有属性并执行提供的回调函数。
     * 该方法会使用 for...in 遍历对象的所有可枚举属性，但仅对对象的自有属性执行回调，
     * 避免遍历到从原型链继承的属性。
     * 
     * @param obj 要遍历的对象。
     * @param callback 对每个属性执行的回调函数，格式为 function(key:String, value:Object):Void。
     * 回调函数将接收两个参数：属性名 (key) 和对应的属性值 (value)。
     */
    public static function forEach(obj:Object, callback:Function):Void {
        // 检查传入的对象是否为 null 或非对象类型，如果是则直接返回
        if (obj == null || typeof(obj) != "object") {
            return;
        }

        // 使用 for...in 结合 hasOwnProperty 遍历对象的自有属性
        for (var key:String in obj) {
            // hasOwnProperty 用于确保只遍历对象自身的属性，避免遍历原型链上的继承属性
            if (obj.hasOwnProperty(key)) {
                // 对每个自有属性调用回调函数，传递属性名和对应的值
                callback(key, obj[key]);
            }
        }
    }


    /**
     * 比较两个对象，返回它们的差异。
     * @param obj1 第一个对象。
     * @param obj2 第二个对象。
     * @param seenObjects (可选) 追踪已比较的对象，防止循环引用
     * @return Number -1 表示 obj1 < obj2, 1 表示 obj1 > obj2, 0 表示相等。
     */
    public static function compare(obj1:Object, obj2:Object, seenObjects:Dictionary):Number {
        // 如果 seenObjects 为空，则在此处初始化
        if (seenObjects == null) {
            seenObjects = new Dictionary();
        }

        if (obj1 === obj2) return 0;

        // 防止循环比较，标记已比较的对象
        if (seenObjects.getItem(obj1) === obj2) return 0;

        seenObjects.setItem(obj1, obj2);

        // 如果其中一个为 null
        if (obj1 == null) return -1;
        if (obj2 == null) return 1;

        // 类型比较
        var type1:String = typeof(obj1);
        var type2:String = typeof(obj2);
        if (type1 != type2) return (type1 > type2) ? 1 : -1;

        // 简单类型比较
        if (isSimple(obj1)) return (obj1 > obj2) ? 1 : (obj1 < obj2 ? -1 : 0);

        // 数组比较
        if (obj1 instanceof Array && obj2 instanceof Array) {
            if (obj1.length != obj2.length) return (obj1.length > obj2.length) ? 1 : -1;
            for (var i:Number = 0; i < obj1.length; i++) {
                var result:Number = compare(obj1[i], obj2[i], seenObjects);
                if (result != 0) return result;
            }
            return 0;
        }

        // 对象属性比较
        var keys1:Array = getKeys(obj1);
        var keys2:Array = getKeys(obj2);
        keys1 = InsertionSort.sort(keys1, function(a, b):Number { return a > b ? 1 : (a < b ? -1 : 0); });
        keys2 = InsertionSort.sort(keys2, function(a, b):Number { return a > b ? 1 : (a < b ? -1 : 0); });

        if (keys1.length != keys2.length) return (keys1.length > keys2.length) ? 1 : -1;

        for (var j:Number = 0; j < keys1.length; j++) {
            if (keys1[j] != keys2[j]) return (keys1[j] > keys2[j]) ? 1 : -1;
            var compareResult:Number = compare(obj1[keys1[j]], obj2[keys2[j]], seenObjects);
            if (compareResult != 0) return compareResult;
        }

        return 0;
    }

    /**
     * 检查是否有对应属性
     * 
     * @param obj 要检查的对象。
     * @return Boolean 检查结果，true代表有，false代表无
     */

    public static function hasProperties(obj:Object):Boolean {
        for (var prop:String in obj) {
            return true;
        }
        return false;
    }

    /**
     * 检查对象是否为简单数据类型（Number, String, Boolean）。
     * @param obj 要检查的对象。
     * @return Boolean true 表示简单类型，false 表示复杂对象。
     */
    public static function isSimple(obj:Object):Boolean {
        var type:String = typeof(obj);
        return (type == "number" || type == "string" || type == "boolean");
    }

    /**
     * 将对象转换为字符串表示形式（类似于 JSON 格式）。
     * @param obj 要转换的对象。
     * @param seenObjects (可选) 追踪已转换的对象，防止循环引用
     * @param depth (可选) 递归深度，防止无限递归
     * @return String 对象的字符串表示。
     */
    public static function toString(obj:Object, seenObjects:Dictionary, depth:Number):String {
        var MAX_DEPTH:Number = 256;  // 设置最大递归深度
        var result:String = "";

        if(depth == undefined) {
            depth = 0;
        }

        // 如果递归深度超出限制，则返回特殊标志
        if (depth > MAX_DEPTH) {
            return "[Max Depth Reached]";
        }

        // 如果没有传入 seenObjects，则初始化一个新字典
        if (seenObjects == null) {
            seenObjects = new Dictionary();
        }

        // 处理 null 值
        if (obj == null) return "null";

        // 检查是否已处理过该对象，避免循环引用
        if (seenObjects.getItem(obj) != undefined) {
            return "[Circular]";
        }

        // 将当前对象加入到 seenObjects，以追踪后续递归
        seenObjects.setItem(obj, true);

        // 处理函数类型，输出 function:uid 格式
        if (typeof(obj) == "function") {
            var uid:Number = Dictionary.getStaticUID(obj);  // 使用 getUID 方法获取唯一标识符
            result = "func:" + uid;
        }
        // 处理数组类型
        else if (obj instanceof Array) {
            result += "[";
            for (var i:Number = 0; i < obj.length; i++) {
                if (i > 0) result += ", ";
                result += toString(obj[i], seenObjects, depth + 1);  // 递归调用时增加深度
            }
            result += "]";
        }
        // 处理对象类型
        else if (typeof(obj) == "object") {
            result += "{";
            var keys:Array = getKeys(obj);

            keys = InsertionSort.sort(keys, function(a, b):Number { 
                return a > b ? 1 : (a < b ? -1 : 0); 
            });

            for (var j:Number = 0; j < keys.length; j++) {
                if (!isInternalKey(keys[j])) {
                    if (j > 0) result += ", ";
                    result += '"' + keys[j] + '": ' + toString(obj[keys[j]], seenObjects, depth + 1);  // 递归调用时增加深度
                }
            }
            result += "}";
        }
        // 处理简单类型（字符串、数字、布尔值）
        else {
            result = (typeof(obj) == "string") ? '"' + String(obj) + '"' : String(obj);
        }

        // 处理完后，从 seenObjects 中删除当前对象，避免后续使用时的干扰
        seenObjects.removeItem(obj);

        return result;
    }



    /**
     * 判断是否为 ActionScript 内部使用的键（如 __dictUID）
     * @param key 键名
     * @return Boolean 是否为内部键
     */
    public static function isInternalKey(key:String):Boolean {
        return key.substr(0, 2) == "__";  // 忽略以双下划线开头的键
    }


    /**
    * 从源对象复制所有属性到目标对象中。
    * @param source 源对象。
    * @param destination 目标对象。
    */
    public static function copyProperties(source:Object, destination:Object):Void {
        if (source == null || destination == null) {
            return;
        }

        for (var key:String in source) {
            if (source.hasOwnProperty(key) && !isInternalKey(key)) {  // 忽略内部键
                destination[key] = source[key];
            }
        }
    }

    /**
     * 从对象获取所有的键。
     * @param obj 要获取键的对象。
     * @return Array 键数组。
     */
    public static function getKeys(obj:Object):Array {
        var keys:Array = [];
        for (var key:String in obj) {
            if (obj.hasOwnProperty(key) && !isInternalKey(key)) {  // 忽略内部键
                keys.push(key);
            }
        }
        return keys;
    }

    /**
     * 比较两个对象是否相等（递归比较所有属性）。
     * @param obj1 第一个对象。
     * @param obj2 第二个对象。
     * @param seenObjects (可选) 追踪已比较的对象，防止循环引用
     * @return Boolean true 表示相等，false 表示不相等。
     */
    public static function equals(obj1:Object, obj2:Object, seenObjects:Dictionary):Boolean {
        if (seenObjects == null) {
            seenObjects = new Dictionary();
        }

        if (obj1 === obj2) return true;

        // 防止循环引用
        if (seenObjects.getItem(obj1) === obj2) return true;

        seenObjects.setItem(obj1, obj2);

        if (obj1 == null || obj2 == null) return false;

        var type1:String = typeof(obj1);
        var type2:String = typeof(obj2);
        if (type1 != type2) return false;

        // 简单类型比较
        if (isSimple(obj1)) return obj1 === obj2;

        // 数组比较
        if (obj1 instanceof Array && obj2 instanceof Array) {
            if (obj1.length != obj2.length) return false;
            for (var i:Number = 0; i < obj1.length; i++) {
                if (!equals(obj1[i], obj2[i], seenObjects)) return false;
            }
            return true;
        }

        // 对象属性比较
        var keys1:Array = getKeys(obj1);
        var keys2:Array = getKeys(obj2);
        keys1 = InsertionSort.sort(keys1, function(a, b):Number { return a > b ? 1 : (a < b ? -1 : 0); });
        keys2 = InsertionSort.sort(keys2, function(a, b):Number { return a > b ? 1 : (a < b ? -1 : 0); });
        if (keys1.length != keys2.length) return false;

        for (var j:Number = 0; j < keys1.length; j++) {
            if (keys1[j] != keys2[j]) return false;
            if (!equals(obj1[keys1[j]], obj2[keys2[j]], seenObjects)) return false;
        }

        return true;
    }

    /**
     * Returns the number of keys in an object, excluding keys with the '__' prefix.
     * @param obj The object to count keys from.
     * @return The number of valid keys in the object (excluding keys starting with '__').
     */
    public static function size(obj:Object):Number {
        var count:Number = 0;
        for (var key:String in obj) {
            // Exclude keys starting with '__' (used for system internal implementation)
            if (key.indexOf("__") !== 0) {
                count++;
            }
        }
        return count;
    }

    /**
     * 检查两个对象是否具有相同的属性名和相同的属性值。
     * @param obj1 第一个对象。
     * @param obj2 第二个对象。
     * @return Boolean true 表示对象具有相同的属性和属性值，false 表示不同。
     */
    public static function deepEquals(obj1:Object, obj2:Object):Boolean {
        return equals(obj1, obj2, null);
    }

    /**
     * 将对象序列化为 JSON 字符串。
     * @param obj 要序列化的对象。
     * @param pretty 是否格式化输出。
     * @return String JSON 字符串，或 null 解析失败。
     */
    public static function toJSON(obj:Object, pretty:Boolean):String {
        var serializer:JSON = new JSON();
        try {
            var indent:String = pretty ? "  " : ""; // 控制是否格式化输出
            return serializer.stringify(obj, indent); // 序列化对象为 JSON 字符串
        } catch (e:Object) {
            trace("ObjectUtil.toJSON: 无法序列化对象为JSON字符串 - " + e.message);
            return null; // 处理异常并返回 null
        }
    }

    /**
     * 将 JSON 字符串解析为对象。
     * @param json JSON 字符串。
     * @return Object 解析后的对象，或 null 解析失败。
     */
    public static function fromJSON(json:String):Object {
        var parser:JSON = new JSON();
        try {
            return parser.parse(json); // 解析 JSON 字符串为对象
        } catch (e:Object) {
            trace("ObjectUtil.fromJSON: 无法解析JSON字符串 - " + e.message);
            return null; // 处理异常并返回 null
        }
    }

    /**
     * 将对象序列化为压缩后的 Base64 编码字符串。
     * @param obj 要序列化的对象。
     * @param pretty 是否格式化输出 JSON。
     * @return String 压缩并编码后的 Base64 字符串，或 null 如果失败。
     */
    public static function toBase64(obj:Object, pretty:Boolean):String {
        var jsonString:String = toJSON(obj, pretty);
        if (jsonString == null) {
            trace("ObjectUtil.toBase64: 序列化为 JSON 失败");
            return null;
        }

        // 压缩 JSON 字符串
        var compressedString:String = StringUtils.compress(jsonString);
        if (compressedString == null) {
            trace("ObjectUtil.toBase64: 压缩 JSON 失败");
            return null;
        }

        // 将压缩后的字符串编码为 Base64
        var base64String:String = Base64.encode(compressedString);
        return base64String;
    }

    /**
     * 从压缩并编码的 Base64 字符串解析对象。
     * @param base64String 压缩并编码后的 Base64 字符串。
     * @return Object 解析后的对象，或 null 如果失败。
     */
    public static function fromBase64(base64String:String):Object {
        var compressedString:String = Base64.decode(base64String);
        if (compressedString == null) {
            trace("ObjectUtil.fromBase64: Base64 解码失败");
            return null;
        }

        // 解压缩字符串
        var jsonString:String = StringUtils.decompress(compressedString);
        if (jsonString == null) {
            trace("ObjectUtil.fromBase64: 解压缩失败");
            return null;
        }

        // 将 JSON 字符串解析为对象
        return fromJSON(jsonString);
    }

    /**
     * 将对象序列化为 FNTL 字符串。
     * @param obj 要序列化的对象。
     * @param pretty 是否格式化输出。
     * @return String FNTL 字符串，或 null 解析失败。
     */
    public static function toFNTL(obj:Object, pretty:Boolean):String {
        var encoder:FNTLEncoder = new FNTLEncoder(false);
        try {
            return encoder.encode(obj, pretty); // 序列化对象为 FNTL 字符串
        } catch (e:Object) {
            trace("ObjectUtil.toFNTL: 无法序列化对象为FNTL字符串 - " + e.message);
            return null; // 处理异常并返回 null
        }
    }

    /**
     * 将对象序列化为 FNTL 字符串，并将结果转换为单行字符串，方便复制粘贴到其他 AS2 环境中使用。
     * @param obj 要序列化的对象。
     * @param pretty 是否格式化输出。
     * @return String 转换后的单行 FNTL 字符串，或 null 如果解析失败。
     */
    public static function toFNTLSingleLine(obj:Object, pretty:Boolean):String {
        var encoder:FNTLEncoder = new FNTLEncoder(false); // 创建编码器实例
        try {
            var fntlStr:String = encoder.encode(obj, pretty); // 序列化对象为 FNTL 字符串
            if (fntlStr == null) {
                return null; // 如果序列化失败，返回 null
            }
            
            // 转换多行字符串为单行，替换换行符和回车符，确保可以直接复制粘贴
            var singleLineStr:String = fntlStr.split("\n").join("\\n").split("\r").join("\\r");

            // 返回处理后的单行字符串
            return singleLineStr;
        } catch (e:Object) {
            trace("toFNTLSingleLine: 无法序列化对象为 FNTL 字符串 - " + e.message);
            return null; // 处理异常并返回 null
        }
    }


    /**
     * 将 FNTL 字符串解析为对象。
     * @param fntl FNTL 字符串。
     * @return Object 解析后的对象，或 null 解析失败。
     */
    public static function fromFNTL(fntl:String):Object {
        var lexer:FNTLLexer = new FNTLLexer(fntl, true);
        var tokens:Array = [];
        var token:Object;

        try {
            // 获取所有 tokens
            while ((token = lexer.getNextToken()) != null) {
                tokens.push(token);
            }

            // 解析 tokens
            var parser:FNTLParser = new FNTLParser(tokens);
            var result:Object = parser.parse();

            if (parser.hasError()) {
                trace("ObjectUtil.fromFNTL: 解析 FNTL 字符串时发生错误");
                return null; // 返回 null 以处理解析错误
            }
            
            return result; // 返回解析后的对象
        } catch (e:Object) {
            trace("ObjectUtil.fromFNTL: 无法解析 FNTL 字符串 - " + e.message);
            return null; // 处理异常并返回 null
        }
    }


    /**
     * 将对象序列化为 TOML 字符串。
     * @param obj 要序列化的对象。
     * @param pretty 是否格式化输出。
     * @return String TOML 字符串，或 null 解析失败。
     */
    public static function toTOML(obj:Object, pretty:Boolean):String {
        var encoder:TOMLEncoder = new TOMLEncoder();
        try {
            return encoder.encode(obj, pretty); // 序列化对象为 TOML 字符串
        } catch (e:Object) {
            trace("ObjectUtil.toTOML: 无法序列化对象为TOML字符串 - " + e.message);
            return null; // 处理异常并返回 null
        }
    }

    /**
     * 将 TOML 字符串解析为对象。
     * @param toml TOML 字符串。
     * @return Object 解析后的对象，或 null 解析失败。
     */
    public static function fromTOML(toml:String):Object {
        var lexer:TOMLLexer = new TOMLLexer(toml);
        var tokens:Array = [];
        var token:Object;

        try {
            // 获取所有 tokens
            while ((token = lexer.getNextToken()) != null) {
                tokens.push(token);
            }

            // 解析 tokens
            var parser:TOMLParser = new TOMLParser(tokens);
            var result:Object = parser.parse();

            if (parser.hasError()) {
                trace("ObjectUtil.fromTOML: 解析 TOML 字符串时发生错误");
                return null; // 返回 null 以处理解析错误
            }
            
            return result; // 返回解析后的对象
        } catch (e:Object) {
            trace("ObjectUtil.fromTOML: 无法解析 TOML 字符串 - " + e.message);
            return null; // 处理异常并返回 null
        }
    }

    /**
     * 将对象序列化为压缩后的 Base64 编码字符串。
     * @param obj 要序列化的对象。
     * @param pretty 是否格式化输出 JSON。
     * @return String 压缩并编码后的 Base64 字符串，或 null 如果失败。
     */
    public static function toCompress(obj:Object, pretty:Boolean):String {
        var jsonString:String = toJSON(obj, pretty);
        if (jsonString == null) {
            trace("ObjectUtil.toBase64: 序列化为 JSON 失败");
            return null;
        }

        // 压缩 JSON 字符串
        var compressedString:String = StringUtils.compress(jsonString);
        if (compressedString == null) {
            trace("ObjectUtil.toBase64: 压缩 JSON 失败");
            return null;
        }
        return compressedString;
    }

    /**
     * 从压缩并编码的 Base64 字符串解析对象。
     * @param base64String 压缩并编码后的 Base64 字符串。
     * @return Object 解析后的对象，或 null 如果失败。
     */
    public static function fromCompress(compressedString:String):Object {
        // 解压缩字符串
        var jsonString:String = StringUtils.decompress(compressedString);
        if (jsonString == null) {
            trace("ObjectUtil.fromBase64: 解压缩失败");
            return null;
        }

        // 将 JSON 字符串解析为对象
        return fromJSON(jsonString);
    }

}


/*

// 文件路径: ObjectUtilTest.as

// 导入所需的类
import org.flashNight.gesh.object.ObjectUtil;
import org.flashNight.gesh.string.StringUtils;
import JSON;

trace("开始测试 ObjectUtil 类...\n");

// 1. 测试 clone 方法
trace("测试 clone 方法...");
var obj1:Object = { name: "Test", age: 25 };
var clone1:Object = ObjectUtil.clone(obj1);
trace("对象是否相等（深拷贝）: " + (obj1 !== clone1) + "，内容是否相同: " + ObjectUtil.equals(obj1, clone1));

var obj2:Object = { name: "Nested", info: { city: "New York" } };
var clone2:Object = ObjectUtil.clone(obj2);
trace("嵌套对象是否相等（深拷贝）: " + (obj2.info !== clone2.info) + "，内容是否相同: " + ObjectUtil.equals(obj2, clone2));

var arr:Array = [1, 2, 3];
var cloneArr:Array = ObjectUtil.clone(arr);
trace("数组是否相等（深拷贝）: " + (arr !== cloneArr) + "，内容是否相同: " + ObjectUtil.equals(arr, cloneArr));

trace("clone 方法测试完成。\n");

// 2. 测试 compare 方法
trace("测试 compare 方法...");
trace("比较数字: " + ObjectUtil.compare(10, 20)); // 应该返回 -1
trace("比较相同数字: " + ObjectUtil.compare(20, 20)); // 应该返回 0
trace("比较字符串: " + ObjectUtil.compare("abc", "xyz")); // 应该返回 -1

var objA:Object = { name: "Test", age: 25 };
var objB:Object = { name: "Test", age: 30 };
trace("比较不同对象: " + ObjectUtil.compare(objA, objB)); // 应该返回 -1

trace("compare 方法测试完成。\n");

// 3. 测试 isSimple 方法
trace("测试 isSimple 方法...");
trace("是否为简单类型（数字）: " + ObjectUtil.isSimple(123)); // 应该返回 true
trace("是否为简单类型（字符串）: " + ObjectUtil.isSimple("hello")); // 应该返回 true
trace("是否为简单类型（对象）: " + ObjectUtil.isSimple({})); // 应该返回 false

trace("isSimple 方法测试完成。\n");

// 4. 测试 toString 方法
trace("测试 toString 方法...");
var objC:Object = { name: "Test", age: 25 };
trace("对象的字符串表示: " + ObjectUtil.toString(objC)); // 应输出 {"name": "Test", "age": 25}

var nestedObj:Object = { name: "Nested", info: { city: "New York", zip: 10001 } };
trace("嵌套对象的字符串表示: " + ObjectUtil.toString(nestedObj)); // 应输出 {"name": "Nested", "info": {"city": "New York", "zip": 10001}}

var arrTest:Array = [1, 2, 3];
trace("数组的字符串表示: " + ObjectUtil.toString(arrTest)); // 应输出 [1, 2, 3]

trace("toString 方法测试完成。\n");

// 5. 测试 copyProperties 方法
trace("测试 copyProperties 方法...");
var source:Object = { name: "Source", age: 30 };
var destination:Object = {};
ObjectUtil.copyProperties(source, destination);
trace("目标对象内容: " + ObjectUtil.toString(destination)); // 应输出 {"name": "Source", "age": 30}

trace("copyProperties 方法测试完成。\n");

// 6. 测试 equals 方法
trace("测试 equals 方法...");
var objD:Object = { name: "Test", age: 25 };
var objE:Object = { name: "Test", age: 25 };
trace("对象是否相等: " + ObjectUtil.equals(objD, objE)); // 应该返回 true

var objF:Object = { name: "Test", age: 30 };
trace("对象是否相等: " + ObjectUtil.equals(objD, objF)); // 应该返回 false

trace("equals 方法测试完成。\n");

// 7. 测试 merge 方法
trace("测试 merge 方法...");
var target:Object = { name: "Target", age: 20 };
var sourceMerge:Object = { age: 30, city: "New York" };
var merged:Object = ObjectUtil.merge(target, sourceMerge);
trace("合并后的对象: " + ObjectUtil.toString(merged)); // 应输出 {"name": "Target", "age": 30, "city": "New York"}

trace("merge 方法测试完成。\n");

// 8. 测试 deepEquals 方法
trace("测试 deepEquals 方法...");
var objG:Object = { name: "Test", info: { city: "New York", zip: 10001 } };
var objH:Object = { name: "Test", info: { city: "New York", zip: 10001 } };
trace("对象深度相等: " + ObjectUtil.deepEquals(objG, objH)); // 应该返回 true

var objI:Object = { name: "Test", info: { city: "Los Angeles", zip: 90001 } };
trace("对象深度相等: " + ObjectUtil.deepEquals(objG, objI)); // 应该返回 false

trace("deepEquals 方法测试完成。\n");

// 9. 测试 toJSON 方法
trace("测试 toJSON 方法...");
var objJ:Object = { name: "Test", age: 25, info: { city: "New York" } };
trace("JSON 字符串 (紧凑): " + ObjectUtil.toJSON(objJ, false)); // 应输出 {"name":"Test","age":25,"info":{"city":"New York"}}
trace("JSON 字符串 (格式化): " + ObjectUtil.toJSON(objJ, true)); // 应输出格式化的 JSON

trace("toJSON 方法测试完成。\n");

// 10. 测试 fromJSON 方法
trace("测试 fromJSON 方法...");
var jsonString:String = '{"name":"Test","age":25,"info":{"city":"New York"}}';
var parsedObj:Object = ObjectUtil.fromJSON(jsonString);
trace("解析后的对象: " + ObjectUtil.toString(parsedObj)); // 应输出 {"name": "Test", "age": 25, "info": {"city": "New York"}}

var invalidJson:String = '{"name": "Test", "age": 25,'; // Invalid JSON string
var invalidParsed:Object = ObjectUtil.fromJSON(invalidJson);
trace("无效 JSON 解析结果: " + invalidParsed); // 应输出 null

trace("fromJSON 方法测试完成。\n");

// 11. 测试 toBase64 和 fromBase64 方法
trace("测试 toBase64 和 fromBase64 方法...");
var testObject:Object = { name: "Test", value: 123, nested: { key: "value" } };

var base64String:String = ObjectUtil.toBase64(testObject, false);
trace("Base64 编码结果: " + base64String); // 输出 Base64 编码结果

var decodedObject:Object = ObjectUtil.fromBase64(base64String);
trace("从 Base64 解析的对象: " + ObjectUtil.toString(decodedObject)); // 输出解码结果

trace("对象是否一致: " + ObjectUtil.equals(testObject, decodedObject)); // 应该输出 true

trace("toBase64 和 fromBase64 方法测试完成。\n");

trace("\n测试完毕。");


trace("开始测试 ObjectUtil 类...\n");

// 12. 测试 toTOML 方法
trace("测试 toTOML 方法...");
var objK:Object = { title: "My Game", isActive: true, score: 1000, items: ["sword", "shield", "potion"] };

// 测试紧凑格式
var tomlString:String = ObjectUtil.toTOML(objK, false);
trace("TOML 字符串 (紧凑): \n" + tomlString); // 应输出紧凑的 TOML 格式

// 测试格式化输出
var prettyTomlString:String = ObjectUtil.toTOML(objK, true);
trace("TOML 字符串 (格式化): \n" + prettyTomlString); // 应输出格式化的 TOML 格式

trace("toTOML 方法测试完成。\n");

// 12.1. 测试包含嵌套表格和表格数组的对象
trace("测试 toTOML 方法 - 复杂对象...");
var complexObj:Object = {
    title: "Complex TOML",
    owner: { name: "Tom", dob: "1979-05-27" },
    products: [
        { name: "Hammer", sku: 738594937 },
        { name: "Nail", sku: 284758393 }
    ]
};

complexObj["database"] = { // 确保使用字符串键名
    server: "192.168.1.1",
    ports: [8001, 8001, 8002],
    connection_max: 5000,
    enabled: true
};

// 测试复杂对象的 TOML 序列化
var complexToml:String = ObjectUtil.toTOML(complexObj, true);
trace("复杂对象的 TOML 字符串:\n" + complexToml);

trace("toTOML 方法复杂对象测试完成。\n");

// 13. 测试 fromTOML 方法
trace("测试 fromTOML 方法...");
var tomlData:String = 'title = "My Game"\n' +
                      'isActive = true\n' +
                      'score = 1000\n' +
                      'items = ["sword", "shield", "potion"]\n';

// 解析 TOML 字符串为对象
var parsedTOMLObject:Object = ObjectUtil.fromTOML(tomlData);
trace("解析后的 TOML 对象: " + ObjectUtil.toString(parsedTOMLObject)); // 应输出 {"title": "My Game", "isActive": true, "score": 1000, "items": ["sword", "shield", "potion"]}

// 测试无效 TOML 字符串的解析
var invalidTOML:String = 'title = "My Game" isActive = true'; // Invalid TOML string
var invalidParsedTOML:Object = ObjectUtil.fromTOML(invalidTOML);
trace("无效 TOML 解析结果: " + invalidParsedTOML); // 应输出 null

trace("fromTOML 方法测试完成。\n");

// 13.1. 测试解析复杂 TOML 字符串
trace("测试 fromTOML 方法 - 复杂 TOML...");
var complexObj:Object = {
    title: "Complex TOML",
    owner: { name: "Tom", dob: "1979-05-27" },
    products: [
        { name: "Hammer", sku: 738594937 },
        { name: "Nail", sku: 284758393 }
    ]
};

// Assigning string-literal key "database" using bracket notation
complexObj["database"] = {
    server: "192.168.1.1",
    ports: [8001, 8001, 8002],
    connection_max: 5000,
    enabled: true
};

// 解析复杂 TOML 字符串为对象
var parsedComplexTOMLObject:Object = ObjectUtil.fromTOML(complexToml);
trace("解析后的复杂 TOML 对象: " + ObjectUtil.toString(parsedComplexTOMLObject)); // 应输出对应的对象结构

trace("fromTOML 方法复杂 TOML 测试完成。\n");

// 13.2. 测试解析包含多行字符串的 TOML
trace("测试 fromTOML 方法 - 多行字符串...");
var multilineToml:String = 'description = """\nThis is a multiline string.\nIt spans multiple lines.\n"""\n';

// 解析多行字符串的 TOML 为对象
var parsedMultilineTOMLObject:Object = ObjectUtil.fromTOML(multilineToml);
trace("解析后的多行字符串 TOML 对象: " + ObjectUtil.toString(parsedMultilineTOMLObject)); // 应输出 { description: "This is a multiline string.\nIt spans multiple lines.\n" }

trace("fromTOML 方法多行字符串测试完成。\n");

trace("\n所有测试完毕。");


*/

/*

import org.flashNight.gesh.object.ObjectUtil;
import org.flashNight.gesh.fntl.FNTLEncoder;
import org.flashNight.gesh.fntl.FNTLParser;

// 手动创建复杂对象
var complexObj:Object = new Object();
complexObj["player"] = new Object();
complexObj["player"]["name"] = "测试玩家";
complexObj["player"]["level"] = 25;

complexObj["player"]["inventory"] = new Array();
var sword:Object = new Object();
sword["item"] = "剑";
sword["quantity"] = 1;
complexObj["player"]["inventory"].push(sword);

var shield:Object = new Object();
shield["item"] = "盾";
shield["quantity"] = 1;
complexObj["player"]["inventory"].push(shield);

complexObj["game"] = new Object();
complexObj["game"]["title"] = "冒险游戏";
complexObj["game"]["version"] = "1.0.1";
complexObj["game"]["settings"] = new Object();
complexObj["game"]["settings"]["difficulty"] = "normal";
complexObj["game"]["settings"]["sound"] = true;
complexObj["game"]["settings"]["graphics"] = "high";

complexObj["stats"] = new Object();
complexObj["stats"]["health"] = 100;
complexObj["stats"]["mana"] = 50;
complexObj["stats"]["experience"] = 5000;
complexObj["stats"]["achievements"] = new Array();
complexObj["stats"]["achievements"].push("击败巨龙");
complexObj["stats"]["achievements"].push("找到宝藏");
complexObj["stats"]["achievements"].push("完成新手教程");

// 使用 toFNTLSingleLine 方法生成单行 FNTL 字符串
var fntlSingleLine:String = ObjectUtil.toFNTL(complexObj, true);


trace("处理后的单行 FNTL 字符串:");
trace(fntlSingleLine);

// 使用 fromFNTL 方法解析单行 FNTL 字符串为对象
var parsedObj:Object = ObjectUtil.fromFNTL(fntlSingleLine);
trace("解析后的对象:");
trace(ObjectUtil.toString(parsedObj));


*/