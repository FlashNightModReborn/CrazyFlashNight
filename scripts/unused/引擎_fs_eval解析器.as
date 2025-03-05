_root.eval解析器 = {};
_root.eval解析器.解析路径 = function(propertyPath) 
{
    var pathParts = [];
    var tempPart = "";
    var inBracket = false;
    var inFunction = false;
    var length = propertyPath.length;
    for (var i = 0; i < length; ++i) 
	{
        var ch = propertyPath.charAt(i);
        if (ch == '[') 
		{
            if (tempPart.length > 0) pathParts.push(tempPart);
            tempPart = '';
            inBracket = true;
        } 
		else if (ch == ']' and inBracket) 
		{
            if (tempPart.length > 0) pathParts.push(tempPart);
            tempPart = '';
            inBracket = false;
        } 
		else if (ch == '(') 
		{
            tempPart += ch;
            inFunction = true;
        } 
		else if (ch == ')' and inFunction) 
		{
            tempPart += ch;
            inFunction = false;
        } 
		else if (ch == '.' and !inBracket and !inFunction) 
		{
            if (tempPart.length > 0) pathParts.push(tempPart);
            tempPart = '';
        } 
		else 
		{
            tempPart += ch;
        }
    }
    if (tempPart.length > 0) pathParts.push(tempPart);
    return pathParts;
};



_root.eval解析器.设置属性值 = function(obj, propertyPath, value) 
{
    var pathParts = _root.eval解析器.解析路径(propertyPath);
    var currentObject = obj;
    for (var i = 0; i < pathParts.length - 1; ++i) 
	{
        var part = pathParts[i];
        if (currentObject == null) 
		{
            return false;
        }
        if (!isNaN(part) and currentObject instanceof Array) 
		{
            part = parseInt(part);
            if (part >= 0 and part < currentObject.length) 
			{
                currentObject = currentObject[part];
            } 
			else 
			{
                return false;
            }
        } 
		else if (currentObject.hasOwnProperty(part)) 
		{
            currentObject = currentObject[part];
        } 
		else 
		{
            return false;
        }
    }
    var lastPart = pathParts[pathParts.length - 1];
    if (currentObject == null) return false;
    if (!isNaN(lastPart) and currentObject instanceof Array) 
	{
        lastPart = parseInt(lastPart);
        if (lastPart >= 0 and lastPart < currentObject.length) 
		{
            currentObject[lastPart] = value;
            return true;
        }
    } 
	else if (currentObject.hasOwnProperty(lastPart)) 
	{
        currentObject[lastPart] = value;
        return true;
    }
    return false;
};

_root.eval解析器.解析属性值 = function(obj, propertyPath) 
{
    var pathParts = _root.eval解析器.解析路径(propertyPath);
    var currentObject = obj;
    for (var i = 0; i < pathParts.length; i++) 
	{
        var part = pathParts[i];
        if (currentObject == null) 
		{
            return undefined;
        }
        if (part.indexOf('()') > -1) 
		{
            var functionName = part.slice(0, part.indexOf('()'));
            if (typeof currentObject[functionName] == "function") 
			{
                currentObject = currentObject[functionName]();
            } 
			else 
			{
                return undefined;
            }
        } 
		else if (!isNaN(parseInt(part)) and currentObject instanceof Array) 
		{
            var index = parseInt(part);
            if (index >= 0 and index < currentObject.length) 
			{
                currentObject = currentObject[index];
            } 
			else 
			{
                return undefined;
            }
        } 
		else if (currentObject.hasOwnProperty(part)) 
		{
            currentObject = currentObject[part];
        } 
		else 
		{
            return undefined;
        }
    }
    return currentObject;
};

_root.eval解析器.match = function(str, re) {
    return re.exec(str);
};

_root.eval解析器.replace = function(str, re, replacement) {
    var r:String = "";
    var s:String = str;
    re.lastIndex = 0;
    if (re.global) {
        var ip:Number = 0;
        var ix:Number = 0;
        while (re.test(s)) {
            var i:Number = 0;
            var l:Number = replacement.length;
            var c:String = "";
            var pc:String = "";
            var nrs:String = "";
            while (i < l) {
                c = replacement.charAt(i++);
                if (c == "$" && pc != "\\") {
                    c = replacement.charAt(i++);
                    if (isNaN(Number(c)) || Number(c) > 9) {
                        nrs += "$" + c;
                    } else {
                        nrs += RegExp._xa[Number(c)];
                    }
                } else {
                    nrs += c;
                }
                pc = c;
            }
            r += s.substring(ix, re._xi) + nrs;
            ix = re._xi + RegExp.lastMatch.length;
            ip = re.lastIndex;
        }
        re.lastIndex = ip;
    } else {
        if (re.test(s)) {
            r += RegExp.leftContext + replacement;
        }
    }
    r += re.lastIndex == 0 ? s : RegExp.rightContext;
    return r;
};

_root.eval解析器.search = function(str, re) {
    return re.test(str) ? re._xi : -1;
};

_root.eval解析器.split = function(str, re, limit) {
    if (typeof(re) == "object" && re.source) {
        var lm:Number = (limit == undefined) ? 9999 : Number(limit);
        if (isNaN(lm)) lm = 9999;
        var s:String = str;
        var ra:Array = new Array();
        var rc:Number = 0;
        var gs:Boolean = re.global;
        re.global = true;

        re.lastIndex = 0;
        var ip:Number = 0;
        var ipp:Number = 0;
        var ix:Number = 0;
        while (rc < lm && re.test(s)) {
            if (re._xi != ix) ra[rc++] = s.substring(ix, re._xi);
            ix = re._xi + RegExp.lastMatch.length;
            ipp = ip;
            ip = re.lastIndex;
        }
        if (rc == lm) {
            re.lastIndex = ipp;
        } else {
            re.lastIndex = ip;
        }

        if (rc == 0) {
            ra[rc] = s;
        } else {
            if (rc < lm && RegExp.rightContext.length > 0) ra[rc++] = RegExp.rightContext;
        }

        re.global = gs;
        return ra;
    } else {
        return str.split(re, limit);
    }
};