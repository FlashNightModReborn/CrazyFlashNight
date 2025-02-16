import org.flashNight.gesh.regexp.*;

class org.flashNight.gesh.string.EvalParser {
    // 解析缓存对象，存储已解析的路径
    private static var cache:Object = {};

    // 解析属性路径，返回路径部分数组
    public static function parsePath(propertyPath:String):Array {
        // 检查缓存中是否存在
        if (cache.hasOwnProperty(propertyPath)) {
            return cache[propertyPath];
        }
        
        var pathParts:Array = [];
        var i:Number = 0;
        var length:Number = propertyPath.length;
        var currentPart:String = "";
        
        while (i < length) {
            var char:String = propertyPath.charAt(i);
            
            if (char == '.') {
                if (currentPart.length > 0) {
                    pathParts.push({type: "property", value: currentPart});
                    currentPart = "";
                }
                i++;
            }
            else if (char == '[') {
                if (currentPart.length > 0) {
                    pathParts.push({type: "property", value: currentPart});
                    currentPart = "";
                }
                i++;
                var indexStr:String = "";
                while (i < length && propertyPath.charAt(i) != ']') {
                    indexStr += propertyPath.charAt(i);
                    i++;
                }
                if (propertyPath.charAt(i) == ']') {
                    pathParts.push({type: "index", value: indexStr});
                    i++; // 跳过 ']'
                }
            }
            else if (char == '(') {
                if (currentPart.length > 0) {
                    // 当前部分是函数名
                    var funcName:String = currentPart;
                    currentPart = "";
                    i++; // 跳过 '('
                    var argsStr:String = "";
                    var parenthesesCount:Number = 1;
                    while (i < length && parenthesesCount > 0) {
                        var currentChar:String = propertyPath.charAt(i);
                        if (currentChar == '(') {
                            parenthesesCount++;
                        }
                        else if (currentChar == ')') {
                            parenthesesCount--;
                            if (parenthesesCount == 0) {
                                break;
                            }
                        }
                        if (parenthesesCount > 0) {
                            argsStr += currentChar;
                        }
                        i++;
                    }
                    if (propertyPath.charAt(i) == ')') {
                        pathParts.push({type: "function", value: {name: funcName, args: argsStr}});
                        i++; // 跳过 ')'
                    }
                }
            }
            else {
                currentPart += char;
                i++;
            }
        }
        
        if (currentPart.length > 0) {
            pathParts.push({type: "property", value: currentPart});
        }
        
        // 将解析结果缓存
        cache[propertyPath] = pathParts;
        return pathParts;
    }
    
    // 设置属性值
    public static function setPropertyValue(obj:Object, propertyPath:String, value:Object):Boolean {
        var pathParts:Array = EvalParser.parsePath(propertyPath);
        var currentObject:Object = obj;
        
        for (var i:Number = 0; i < pathParts.length - 1; i++) {
            var part:Object = pathParts[i];
            if (currentObject == null) {
                trace("setPropertyValue 失败：路径 " + part.value + " 中断");
                return false;
            }
            
            switch(part.type) {
                case "property":
                    if (currentObject.hasOwnProperty(part.value)) {
                        currentObject = currentObject[part.value];
                    } else {
                        trace("setPropertyValue 失败：没有属性 " + part.value);
                        return false;
                    }
                    break;
                    
                case "index":
                    var index:Number = parseInt(part.value);
                    if (currentObject instanceof Array && index >= 0 && index < currentObject.length) {
                        currentObject = currentObject[index];
                    } else {
                        trace("setPropertyValue 失败：数组索引 " + part.value + " 越界或对象不是数组");
                        return false;
                    }
                    break;
                    
                case "function":
                    var funcName:String = part.value.name;
                    var args:Array = EvalParser.parseArguments(part.value.args);
                    if (typeof currentObject[funcName] == "function") {
                        currentObject = currentObject[funcName].apply(currentObject, args);
                    } else {
                        trace("setPropertyValue 失败：没有函数 " + funcName);
                        return false;
                    }
                    break;
            }
        }
        
        var lastPart:Object = pathParts[pathParts.length - 1];
        if (currentObject == null) return false;
        
        switch(lastPart.type) {
            case "property":
                if (currentObject.hasOwnProperty(lastPart.value)) {
                    currentObject[lastPart.value] = value;
                    return true;
                }
                break;
                
            case "index":
                var lastIndex:Number = parseInt(lastPart.value);
                if (currentObject instanceof Array && lastIndex >= 0 && lastIndex < currentObject.length) {
                    currentObject[lastIndex] = value;
                    return true;
                }
                break;
                
            case "function":
                var funcName:String = lastPart.value.name;
                var argsFromPath:Array = EvalParser.parseArguments(lastPart.value.args);
                if (argsFromPath.length > 0) {
                    // 如果路径中已经包含函数参数，并且value不为null，则将value作为额外的函数参数
                    if (value != null) {
                        argsFromPath.push(value);
                    }
                    if (typeof currentObject[funcName] == "function") {
                        currentObject[funcName].apply(currentObject, argsFromPath);
                        return true;
                    } else {
                        trace("setPropertyValue 失败：没有函数 " + funcName);
                        return false;
                    }
                } else {
                    // 路径中不包含函数参数，使用value作为函数参数
                    if (typeof currentObject[funcName] == "function") {
                        currentObject[funcName].apply(currentObject, [value]);
                        return true;
                    } else {
                        trace("setPropertyValue 失败：没有函数 " + funcName);
                        return false;
                    }
                }
                break;
        }
        
        trace("setPropertyValue 失败：无法设置 " + lastPart.value);
        return false;
    }
    
    // 获取属性值
    public static function getPropertyValue(obj:Object, propertyPath:String):Object {
        var pathParts:Array = EvalParser.parsePath(propertyPath);
        var currentObject:Object = obj;
        
        for (var i:Number = 0; i < pathParts.length; i++) {
            var part:Object = pathParts[i];
            if (currentObject == null) {
                trace("getPropertyValue 失败：对象为空在路径 " + part.value);
                return undefined;
            }
            
            switch(part.type) {
                case "property":
                    if (currentObject.hasOwnProperty(part.value)) {
                        currentObject = currentObject[part.value];
                    } else {
                        trace("getPropertyValue 失败：没有属性 " + part.value);
                        return undefined;
                    }
                    break;
                    
                case "index":
                    var index:Number = parseInt(part.value);
                    if (currentObject instanceof Array && index >= 0 && index < currentObject.length) {
                        currentObject = currentObject[index];
                    } else {
                        trace("getPropertyValue 失败：数组索引 " + part.value + " 越界或对象不是数组");
                        return undefined;
                    }
                    break;
                    
                case "function":
                    var funcName:String = part.value.name;
                    var args:Array = EvalParser.parseArguments(part.value.args);
                    if (typeof currentObject[funcName] == "function") {
                        currentObject = currentObject[funcName].apply(currentObject, args);
                    } else {
                        trace("getPropertyValue 失败：没有函数 " + funcName);
                        return undefined;
                    }
                    break;
            }
        }
        return currentObject;
    }
    
    // 解析函数参数
    private static function parseArguments(args:String):Array {
        var argsArray:Array = [];
        if (args.length == 0) return argsArray;
        var splitArgs:Array = [];
        var currentArg:String = "";
        var inQuotes:Boolean = false;
        var quoteChar:String = "";
        var i:Number = 0;
        var length:Number = args.length;
        
        while (i < length) {
            var char:String = args.charAt(i);
            if (inQuotes) {
                if (char == quoteChar) {
                    inQuotes = false;
                }
                currentArg += char;
            }
            else {
                if (char == "'" || char == '"') {
                    inQuotes = true;
                    quoteChar = char;
                    currentArg += char;
                }
                else if (char == ',') {
                    splitArgs.push(currentArg);
                    currentArg = "";
                }
                else {
                    currentArg += char;
                }
            }
            i++;
        }
        if (currentArg.length > 0) {
            splitArgs.push(currentArg);
        }
        
        for (var j:Number = 0; j < splitArgs.length; j++) {
            var arg:String = EvalParser.trim(splitArgs[j]); // 去除首尾空格
            arg = EvalParser.removeQuotes(arg); // 去除首尾引号
            
            // 尝试将参数转换为数字或布尔值
            if (!isNaN(arg)) {
                argsArray.push(Number(arg));
            } else if (arg.toLowerCase() == "true") {
                argsArray.push(true);
            } else if (arg.toLowerCase() == "false") {
                argsArray.push(false);
            } else {
                // 认为是字符串
                argsArray.push(arg);
            }
        }
        return argsArray;
    }
    
    // 去除首尾空格
    private static function trim(str:String):String {
        // 去除首尾空格
        while (str.length > 0 && isWhitespace(str.charAt(0))) {
            str = str.substring(1);
        }
        while (str.length > 0 && isWhitespace(str.charAt(str.length - 1))) {
            str = str.substring(0, str.length - 1);
        }
        return str;
    }
    
    // 判断是否为空白字符
    private static function isWhitespace(char:String):Boolean {
        return char == " " || char == "\t" || char == "\n" || char == "\r";
    }
    
    // 去除首尾引号
    private static function removeQuotes(str:String):String {
        if (str.length == 0) return str;
        var firstChar:String = str.charAt(0);
        var lastChar:String = str.charAt(str.length - 1);
        if ((firstChar == '"' && lastChar == '"') || (firstChar == "'" && lastChar == "'")) {
            str = str.substring(1, str.length - 1);
        }
        return str;
    }
}

