// --- 测试 JSON 和 liteJSON 类的正确性和性能 ---

// 定义测试数据
var tcpData:Object = new Object();
tcpData.userId = 12345;
tcpData.userName = "Player1";
tcpData.level = 10;
tcpData.stats = new Object();
tcpData.stats.hp = 100;
tcpData.stats.mp = 50;
tcpData.stats.attack = 15;
tcpData.stats.defense = 8;

// 添加 inventory 数组
tcpData.inventory = new Array();
var item1:Object = new Object();
item1.id = 101;
item1.name = "Health Potion";
item1.quantity = 3;
tcpData.inventory.push(item1);

var item2:Object = new Object();
item2.id = 102;
item2.name = "Mana Potion";
item2.quantity = 2;
tcpData.inventory.push(item2);

var item3:Object = new Object();
item3.id = 103;
item3.name = "Sword";
item3.quantity = 1;
tcpData.inventory.push(item3);

// 添加 quests 数组
tcpData.quests = new Array();
var quest1:Object = new Object();
quest1.id = 201;
quest1.title = "Defeat Goblins";
quest1.progress = new Object();
quest1.progress.current = 5;
quest1.progress.total = 10;
tcpData.quests.push(quest1);

// 定义复杂对象用于测试
var complexObject:Object = new Object();
complexObject.userId = 12345;
complexObject.userName = "Player1";
complexObject.level = 10;
complexObject.stats = new Object();
complexObject.stats.hp = 100;
complexObject.stats.mp = 50;
complexObject.stats.attack = 15;
complexObject.stats.defense = 8;
complexObject.inventory = [
    {id: 101, name: "Health Potion", quantity: 3},
    {id: 102, name: "Mana Potion", quantity: 2},
    {id: 103, name: "Sword", quantity: 1}
];
complexObject.quests = [
    {
        id: 201,
        title: "Defeat Goblins",
        progress: {
            current: 5,
            total: 10
        }
    }
];

// 定义测试用例
var testCases:Array = [
    // 原始测试用例
    {input: 12345, description: "Integer"},
    {input: 123.45, description: "Float"},
    {input: "hello world", description: "String"},
    {input: true, description: "Boolean true"},
    {input: false, description: "Boolean false"},
    {input: null, description: "Null"},
    {input: "Line1\nLine2\tTabbed", description: "Newline and tabbed"},
    {input: "Hello \"World\"", description: "Escaped quotes"},
    {input: "Hello 你好", description: "Unicode characters"},
    {input: {name:"Alice", age:30, isActive:true}, description: "Simple object"},
    {input: [1, 2, 3, 4, 5], description: "Simple array"},
    {input: {user:{id:123, info:{name:"Alice", active:true}}}, description: "Nested object"},
    {input: [[1, 2], [3, 4], [5, 6]], description: "Nested array"},
    {input: complexObject, description: "Complex object"},
    {input: {}, description: "Empty object"},
    {input: [], description: "Empty array"},
    {input: [1, null, 3, null, 5], description: "Sparse array"},
    {input: {id:123, name:null, active:true}, description: "Object with null"},
    // 无效 JSON 测试用例
    {input: "{\"name\":\"Alice\", \"age\":30", description: "Unfinished object"},
    {input: "[1, 2, 3", description: "Unfinished array"},
    {input: "{\"name\":\"Alice\", \"age\":30, \"active\":yes}", description: "Invalid JSON"}
];

// Helper function: 序列化输出对象为字符串用于显示
function serializeOutput(obj:Object):String {
    if (obj == null) return "null";
    if (typeof obj == "string") return "\"" + obj + "\"";
    if (typeof obj == "number" || typeof obj == "boolean") return String(obj);
    if (obj instanceof Array) {
        var arrStr:String = "[";
        for (var i:Number = 0; i < obj.length; i++) {
            if (i > 0) arrStr += ", ";
            arrStr += serializeOutput(obj[i]);
        }
        arrStr += "]";
        return arrStr;
    }
    if (typeof obj == "object") {
        var objStr:String = "{";
        var isFirst:Boolean = true;
        for (var key:String in obj) {
            if (!isFirst) objStr += ", ";
            isFirst = false;
            objStr += "\"" + key + "\":" + serializeOutput(obj[key]);
        }
        objStr += "}";
        return objStr;
    }
    return "";
}

// 创建 JSON 和 liteJSON 实例
var originalJSON = new JSON(false); // 假设原始 JSON 类支持构造函数参数控制模式
var liteJSON = new LiteJSON(); // 假设 liteJSON 类无构造参数

// 执行功能测试
trace("=== 功能测试 ===");
for (var i:Number = 0; i < testCases.length; i++) {
    var testCase:Object = testCases[i];
    var input:Object = testCase.input;
    var description:String = testCase.description;
    var outputJSON:Object;
    var outputliteJSON:Object;
    var serializedJSON:String;
    var serializedliteJSON:String;
    
    trace("\n--- Test Case: " + description + " ---");
    
    try {
        // 使用原始 JSON 类序列化
        serializedJSON = originalJSON.stringify(input);
        // 使用原始 JSON 类反序列化
        outputJSON = originalJSON.parse(serializedJSON);
        
        // 显示原始 JSON 类结果
        trace("Original JSON | Serialized: " + serializedJSON);
        trace("Original JSON | Parsed Output: " + serializeOutput(outputJSON));
    } catch (e:Error) {
        trace("Original JSON | Error: " + e.message);
    }
    
    try {
        // 使用 liteJSON 类序列化
        serializedliteJSON = liteJSON.stringify(input);
        // 使用 liteJSON 类反序列化
        outputliteJSON = liteJSON.parse(serializedliteJSON);
        
        // 显示 liteJSON 类结果
        trace("liteJSON     | Serialized: " + serializedliteJSON);
        trace("liteJSON     | Parsed Output: " + serializeOutput(outputliteJSON));
    } catch (e:Error) {
        trace("liteJSON     | Error: " + e.message);
    }
}

// --- 性能测试：分别测量序列化和反序列化的时间 ---

// 设置迭代次数
var numIterations:Number = 100;
var jsonSerializeTimes:Array = [];
var jsonDeserializeTimes:Array = [];
var liteJSONSerializeTimes:Array = [];
var liteJSONDeserializeTimes:Array = [];

// 预先序列化一次数据以供反序列化测试使用
var serializedDataJson:String;
var serializedDataliteJSON:String;

try {
    serializedDataJson = originalJSON.stringify(tcpData);
} catch (e:Error) {
    trace("Error serializing with Original JSON: " + e.message);
}

try {
    serializedDataliteJSON = liteJSON.stringify(tcpData);
} catch (e:Error) {
    trace("Error serializing with liteJSON: " + e.message);
}

// 测试原始 JSON 类性能：序列化
trace("\n=== 性能测试：原始 JSON 类序列化 ===");
for (var j:Number = 0; j < numIterations; j++) {
    var startTime:Number = getTimer();

    // 使用原始 JSON 类序列化
    var tempSerializedJson:String = originalJSON.stringify(tcpData);

    var endTime:Number = getTimer();
    jsonSerializeTimes.push(endTime - startTime);
}

// 测试原始 JSON 类性能：反序列化
trace("\n=== 性能测试：原始 JSON 类反序列化 ===");
for (j = 0; j < numIterations; j++) {
    var startTimeDeser:Number = getTimer();

    // 使用原始 JSON 类反序列化
    var tempDeserializedJson:Object = originalJSON.parse(serializedDataJson);

    var endTimeDeser:Number = getTimer();
    jsonDeserializeTimes.push(endTimeDeser - startTimeDeser);
}

// 测试 liteJSON 类性能：序列化
trace("\n=== 性能测试：liteJSON 类序列化 ===");
for (j = 0; j < numIterations; j++) {
    var startTimeFastSer:Number = getTimer();

    // 使用 liteJSON 类序列化
    var tempSerializedliteJSON:String = liteJSON.stringify(tcpData);

    var endTimeFastSer:Number = getTimer();
    liteJSONSerializeTimes.push(endTimeFastSer - startTimeFastSer);
}

// 测试 liteJSON 类性能：反序列化
trace("\n=== 性能测试：liteJSON 类反序列化 ===");
for (j = 0; j < numIterations; j++) {
    var startTimeFastDeser:Number = getTimer();

    // 使用 liteJSON 类反序列化
    var tempDeserializedliteJSON:Object = liteJSON.parse(serializedDataliteJSON);

    var endTimeFastDeser:Number = getTimer();
    liteJSONDeserializeTimes.push(endTimeFastDeser - startTimeFastDeser);
}

// 定义统计函数
function calculateStatistics(times:Array):Object {
    var stats:Object = new Object();

    if (times.length == 0) {
        stats.totalTime = 0;
        stats.maxTime = 0;
        stats.minTime = 0;
        stats.avgTime = 0;
        stats.variance = 0;
        stats.stdDeviation = 0;
        return stats;
    }

    stats.totalTime = 0;
    stats.maxTime = times[0];
    stats.minTime = times[0];

    // Calculate total time, max, and min time
    for (var k:Number = 0; k < times.length; k++) {
        var cycleTime:Number = times[k];
        stats.totalTime += cycleTime;
        if (cycleTime > stats.maxTime) stats.maxTime = cycleTime;
        if (cycleTime < stats.minTime) stats.minTime = cycleTime;
    }

    // Calculate average time
    stats.avgTime = stats.totalTime / times.length;

    // Calculate variance and standard deviation
    var varianceSum:Number = 0;
    for (k = 0; k < times.length; k++) {
        varianceSum += Math.pow(times[k] - stats.avgTime, 2);
    }
    stats.variance = varianceSum / times.length;
    stats.stdDeviation = Math.sqrt(stats.variance);

    return stats;
}

// 计算并显示原始 JSON 类性能统计
var jsonSerStats:Object = calculateStatistics(jsonSerializeTimes);
var jsonDeserStats:Object = calculateStatistics(jsonDeserializeTimes);
trace("\n--- 原始 JSON 类性能统计 ---");
trace("序列化 - " + numIterations + " 次总时间: " + jsonSerStats.totalTime + " ms");
trace("序列化 - 平均每次时间: " + jsonSerStats.avgTime + " ms");
trace("序列化 - 最大时间: " + jsonSerStats.maxTime + " ms");
trace("序列化 - 最小时间: " + jsonSerStats.minTime + " ms");
trace("序列化 - 方差: " + jsonSerStats.variance + " ms^2");
trace("序列化 - 标准差: " + jsonSerStats.stdDeviation + " ms");

trace("反序列化 - " + numIterations + " 次总时间: " + jsonDeserStats.totalTime + " ms");
trace("反序列化 - 平均每次时间: " + jsonDeserStats.avgTime + " ms");
trace("反序列化 - 最大时间: " + jsonDeserStats.maxTime + " ms");
trace("反序列化 - 最小时间: " + jsonDeserStats.minTime + " ms");
trace("反序列化 - 方差: " + jsonDeserStats.variance + " ms^2");
trace("反序列化 - 标准差: " + jsonDeserStats.stdDeviation + " ms");

// 计算并显示 liteJSON 类性能统计
var liteJSONSerStats:Object = calculateStatistics(liteJSONSerializeTimes);
var liteJSONDeserStats:Object = calculateStatistics(liteJSONDeserializeTimes);
trace("\n--- liteJSON 类性能统计 ---");
trace("序列化 - " + numIterations + " 次总时间: " + liteJSONSerStats.totalTime + " ms");
trace("序列化 - 平均每次时间: " + liteJSONSerStats.avgTime + " ms");
trace("序列化 - 最大时间: " + liteJSONSerStats.maxTime + " ms");
trace("序列化 - 最小时间: " + liteJSONSerStats.minTime + " ms");
trace("序列化 - 方差: " + liteJSONSerStats.variance + " ms^2");
trace("序列化 - 标准差: " + liteJSONSerStats.stdDeviation + " ms");

trace("反序列化 - " + numIterations + " 次总时间: " + liteJSONDeserStats.totalTime + " ms");
trace("反序列化 - 平均每次时间: " + liteJSONDeserStats.avgTime + " ms");
trace("反序列化 - 最大时间: " + liteJSONDeserStats.maxTime + " ms");
trace("反序列化 - 最小时间: " + liteJSONDeserStats.minTime + " ms");
trace("反序列化 - 方差: " + liteJSONDeserStats.variance + " ms^2");
trace("反序列化 - 标准差: " + liteJSONDeserStats.stdDeviation + " ms");

// 显示示例序列化数据
trace("\nSerialized data example (Original JSON): " + serializedDataJson);
trace("Deserialized data example, userName (Original JSON): " + (jsonDeserStats.minTime >= 0 ? originalJSON.parse(serializedDataJson).userName : "null"));
trace("Serialized data example (liteJSON): " + serializedDataliteJSON);
trace("Deserialized data example, userName (liteJSON): " + (liteJSONDeserStats.minTime >= 0 ? liteJSON.parse(serializedDataliteJSON).userName : "null"));

// --- 扩展测试：缓存无效情况下的性能测试 ---

trace("\n=== 扩展测试：缓存无效情况下的性能测试 ===");

// 定义一个函数，用于生成全新的测试对象
function generateUniqueObject():Object {
    var obj:Object = new Object();
    obj.userId = Math.floor(Math.random() * 100000);
    obj.userName = "Player" + Math.floor(Math.random() * 1000);
    obj.level = Math.floor(Math.random() * 100);
    obj.stats = new Object();
    obj.stats.hp = Math.floor(Math.random() * 500);
    obj.stats.mp = Math.floor(Math.random() * 500);
    obj.stats.attack = Math.floor(Math.random() * 100);
    obj.stats.defense = Math.floor(Math.random() * 100);
    
    // 添加 inventory 数组
    obj.inventory = new Array();
    var numItems:Number = Math.floor(Math.random() * 10) + 1; // 1 到 10 个物品
    for (var m:Number = 0; m < numItems; m++) {
        var item:Object = new Object();
        item.id = 100 + m;
        item.name = "Item" + m;
        item.quantity = Math.floor(Math.random() * 20) + 1;
        obj.inventory.push(item);
    }
    
    // 添加 quests 数组
    obj.quests = new Array();
    var numQuests:Number = Math.floor(Math.random() * 5) + 1; // 1 到 5 个任务
    for (m = 0; m < numQuests; m++) {
        var quest:Object = new Object();
        quest.id = 200 + m;
        quest.title = "Quest " + m;
        quest.progress = new Object();
        quest.progress.current = Math.floor(Math.random() * 100);
        quest.progress.total = 100;
        obj.quests.push(quest);
    }
    
    return obj;
}

// 定义扩展测试用例数组（每次都是新对象）
var uniqueTestCases:Array = [];
for (i = 0; i < 50; i++) { // 创建 50 个唯一测试用例
    uniqueTestCases.push({input: generateUniqueObject(), description: "Unique object " + (i+1)});
}

// 执行扩展功能测试
trace("\n=== 扩展功能测试：缓存无效情况下 ===");
for (i = 0; i < uniqueTestCases.length; i++) {
    var uniqueTestCase:Object = uniqueTestCases[i];
    var uniqueInput:Object = uniqueTestCase.input;
    var uniqueDescription:String = uniqueTestCase.description;
    var uniqueOutputJSON:Object;
    var uniqueOutputliteJSON:Object;
    var uniqueSerializedJSON:String;
    var uniqueSerializedliteJSON:String;
    
    trace("\n--- Test Case: " + uniqueDescription + " ---");
    
    try {
        // 使用原始 JSON 类序列化
        uniqueSerializedJSON = originalJSON.stringify(uniqueInput);
        // 使用原始 JSON 类反序列化
        uniqueOutputJSON = originalJSON.parse(uniqueSerializedJSON);
        
        // 显示原始 JSON 类结果
        //trace("Original JSON | Serialized: " + uniqueSerializedJSON);
        //trace("Original JSON | Parsed Output: " + serializeOutput(uniqueOutputJSON));
    } catch (e:Error) {
        trace("Original JSON | Error: " + e.message);
    }
    
    try {
        // 使用 liteJSON 类序列化
        uniqueSerializedliteJSON = liteJSON.stringify(uniqueInput);
        // 使用 liteJSON 类反序列化
        uniqueOutputliteJSON = liteJSON.parse(uniqueSerializedliteJSON);
        
        // 显示 liteJSON 类结果
        //trace("liteJSON     | Serialized: " + uniqueSerializedliteJSON);
        //trace("liteJSON     | Parsed Output: " + serializeOutput(uniqueOutputliteJSON));
    } catch (e:Error) {
        trace("liteJSON     | Error: " + e.message);
    }
}

// --- 性能测试：缓存无效情况下的序列化和反序列化时间 ---

// 设置扩展测试迭代次数
var uniqueNumIterations:Number = 100;
var jsonSerializeTimesUnique:Array = [];
var jsonDeserializeTimesUnique:Array = [];
var liteJSONSerializeTimesUnique:Array = [];
var liteJSONDeserializeTimesUnique:Array = [];

// 生成独立的序列化和反序列化数据
var serializedDataJsonUnique:Array = [];
var serializedDataliteJSONUnique:Array = [];

for (i = 0; i < uniqueNumIterations; i++) {
    var uniqueObj:Object = generateUniqueObject();
    try {
        var serializedJsonUnique:String = originalJSON.stringify(uniqueObj);
        serializedDataJsonUnique.push(serializedJsonUnique);
    } catch (e:Error) {
        serializedDataJsonUnique.push("Error");
    }
    
    try {
        var serializedliteJSONUnique:String = liteJSON.stringify(uniqueObj);
        serializedDataliteJSONUnique.push(serializedliteJSONUnique);
    } catch (e:Error) {
        serializedDataliteJSONUnique.push("Error");
    }
}

// 测试原始 JSON 类性能：序列化（缓存无效）
trace("\n=== 扩展性能测试：原始 JSON 类序列化（缓存无效） ===");
for (j = 0; j < uniqueNumIterations; j++) {
    var startTimeUniqueSer:Number = getTimer();

    // 使用原始 JSON 类序列化
    var tempSerializedJsonUnique:String = originalJSON.stringify(generateUniqueObject());

    var endTimeUniqueSer:Number = getTimer();
    jsonSerializeTimesUnique.push(endTimeUniqueSer - startTimeUniqueSer);
}

// 测试原始 JSON 类性能：反序列化（缓存无效）
trace("\n=== 扩展性能测试：原始 JSON 类反序列化（缓存无效） ===");
for (j = 0; j < uniqueNumIterations; j++) {
    var uniqueSerializedJsonUnique:String = originalJSON.stringify(generateUniqueObject());
    var startTimeUniqueDeser:Number = getTimer();

    // 使用原始 JSON 类反序列化
    var tempDeserializedJsonUnique:Object = originalJSON.parse(uniqueSerializedJsonUnique);

    var endTimeUniqueDeser:Number = getTimer();
    jsonDeserializeTimesUnique.push(endTimeUniqueDeser - startTimeUniqueDeser);
}

// 测试 liteJSON 类性能：序列化（缓存无效）
trace("\n=== 扩展性能测试：liteJSON 类序列化（缓存无效） ===");
for (j = 0; j < uniqueNumIterations; j++) {
    var startTimeFastSerUnique:Number = getTimer();

    // 使用 liteJSON 类序列化
    var tempSerializedliteJSONUnique:String = liteJSON.stringify(generateUniqueObject());

    var endTimeFastSerUnique:Number = getTimer();
    liteJSONSerializeTimesUnique.push(endTimeFastSerUnique - startTimeFastSerUnique);
}

// 测试 liteJSON 类性能：反序列化（缓存无效）
trace("\n=== 扩展性能测试：liteJSON 类反序列化（缓存无效） ===");
for (j = 0; j < uniqueNumIterations; j++) {
    var uniqueSerializedliteJSONUnique:String = liteJSON.stringify(generateUniqueObject());
    var startTimeFastDeserUnique:Number = getTimer();

    // 使用 liteJSON 类反序列化
    var tempDeserializedliteJSONUnique:Object = liteJSON.parse(uniqueSerializedliteJSONUnique);

    var endTimeFastDeserUnique:Number = getTimer();
    liteJSONDeserializeTimesUnique.push(endTimeFastDeserUnique - startTimeFastDeserUnique);
}

// 计算并显示扩展测试性能统计
var jsonSerStatsUnique:Object = calculateStatistics(jsonSerializeTimesUnique);
var jsonDeserStatsUnique:Object = calculateStatistics(jsonDeserializeTimesUnique);
trace("\n--- 扩展测试：原始 JSON 类性能统计（缓存无效） ---");
trace("序列化 - " + uniqueNumIterations + " 次总时间: " + jsonSerStatsUnique.totalTime + " ms");
trace("序列化 - 平均每次时间: " + jsonSerStatsUnique.avgTime + " ms");
trace("序列化 - 最大时间: " + jsonSerStatsUnique.maxTime + " ms");
trace("序列化 - 最小时间: " + jsonSerStatsUnique.minTime + " ms");
trace("序列化 - 方差: " + jsonSerStatsUnique.variance + " ms^2");
trace("序列化 - 标准差: " + jsonSerStatsUnique.stdDeviation + " ms");

trace("反序列化 - " + uniqueNumIterations + " 次总时间: " + jsonDeserStatsUnique.totalTime + " ms");
trace("反序列化 - 平均每次时间: " + jsonDeserStatsUnique.avgTime + " ms");
trace("反序列化 - 最大时间: " + jsonDeserStatsUnique.maxTime + " ms");
trace("反序列化 - 最小时间: " + jsonDeserStatsUnique.minTime + " ms");
trace("反序列化 - 方差: " + jsonDeserStatsUnique.variance + " ms^2");
trace("反序列化 - 标准差: " + jsonDeserStatsUnique.stdDeviation + " ms");

var liteJSONSerStatsUnique:Object = calculateStatistics(liteJSONSerializeTimesUnique);
var liteJSONDeserStatsUnique:Object = calculateStatistics(liteJSONDeserializeTimesUnique);
trace("\n--- 扩展测试：liteJSON 类性能统计（缓存无效） ---");
trace("序列化 - " + uniqueNumIterations + " 次总时间: " + liteJSONSerStatsUnique.totalTime + " ms");
trace("序列化 - 平均每次时间: " + liteJSONSerStatsUnique.avgTime + " ms");
trace("序列化 - 最大时间: " + liteJSONSerStatsUnique.maxTime + " ms");
trace("序列化 - 最小时间: " + liteJSONSerStatsUnique.minTime + " ms");
trace("序列化 - 方差: " + liteJSONSerStatsUnique.variance + " ms^2");
trace("序列化 - 标准差: " + liteJSONSerStatsUnique.stdDeviation + " ms");

trace("反序列化 - " + uniqueNumIterations + " 次总时间: " + liteJSONDeserStatsUnique.totalTime + " ms");
trace("反序列化 - 平均每次时间: " + liteJSONDeserStatsUnique.avgTime + " ms");
trace("反序列化 - 最大时间: " + liteJSONDeserStatsUnique.maxTime + " ms");
trace("反序列化 - 最小时间: " + liteJSONDeserStatsUnique.minTime + " ms");
trace("反序列化 - 方差: " + liteJSONDeserStatsUnique.variance + " ms^2");
trace("反序列化 - 标准差: " + liteJSONDeserStatsUnique.stdDeviation + " ms");

// 显示示例序列化数据
trace("\nSerialized data example (Original JSON): " + serializedDataJson);
trace("Deserialized data example, userName (Original JSON): " + (jsonDeserStats.minTime >= 0 ? originalJSON.parse(serializedDataJson).userName : "null"));
trace("Serialized data example (liteJSON): " + serializedDataliteJSON);
trace("Deserialized data example, userName (liteJSON): " + (liteJSONDeserStats.minTime >= 0 ? liteJSON.parse(serializedDataliteJSON).userName : "null"));








