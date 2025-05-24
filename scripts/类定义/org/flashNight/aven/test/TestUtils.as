class org.flashNight.aven.test.TestUtils {
    public static function deepEquals(obj1:Object, obj2:Object, depth:Number):Boolean {
        if (depth > 20) {
            return false; // 防止无限递归
        }
        if (typeof(obj1) != typeof(obj2)) {
            return false;
        }
        if (obj1 === obj2) {
            return true;
        }
        if (obj1 instanceof Array && obj2 instanceof Array) {
            if (obj1.length != obj2.length) {
                return false;
            }
            for (var i:Number = 0; i < obj1.length; i++) {
                if (!deepEquals(obj1[i], obj2[i], depth + 1)) {
                    return false;
                }
            }
            return true;
        }
        if (typeof(obj1) == "object" && obj1 != null && obj2 != null) {
            for (var key:String in obj1) {
                if (!deepEquals(obj1[key], obj2[key], depth + 1)) {
                    return false;
                }
            }
            for (var key2:String in obj2) {
                if (obj1[key2] === undefined) {
                    return false;
                }
            }
            return true;
        }
        if (typeof(obj1) == "number" && isNaN(obj1) && typeof(obj2) == "number" && isNaN(obj2)) {
            return true;
        }
        return obj1 === obj2;
    }

    public static function stringify(obj:Object):String {
        if (obj instanceof Array) {
            var arrStr:String = "[";
            for (var i:Number = 0; i < obj.length; i++) {
                arrStr += stringify(obj[i]);
                if (i < obj.length - 1) {
                    arrStr += ", ";
                }
            }
            arrStr += "]";
            return arrStr;
        } else if (typeof(obj) == "object" && obj != null) {
            var objStr:String = "{ ";
            var first:Boolean = true;
            for (var key:String in obj) {
                if (!first) {
                    objStr += ", ";
                }
                objStr += key + ": " + stringify(obj[key]);
                first = false;
            }
            objStr += " }";
            return objStr;
        } else if (typeof(obj) == "string") {
            return '"' + obj + '"';
        } else {
            return String(obj);
        }
    }
}
