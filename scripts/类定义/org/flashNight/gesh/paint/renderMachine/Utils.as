class org.flashNight.gesh.paint.renderMachine.Utils {
    // 符号字符映射表
    private static var symbolMap:Object;
    
    // 当前解析的索引
    private var currentIndex:Number;

    public function Utils() {
        this.currentIndex = 0;
        initializeSymbolMap();
        // trace("Utils initialized, symbolMap set up."); // 初始化完成日志
    }

    // 初始化符号映射表
    private function initializeSymbolMap():Void {
        symbolMap = {};
        symbolMap["!"] = 62;
        symbolMap["@"] = 63;
        symbolMap["#"] = 64;
        symbolMap["$"] = 65;
        symbolMap["%"] = 66;
        symbolMap["^"] = 67;
        symbolMap["&"] = 68;
        symbolMap["*"] = 69;
        symbolMap["("] = 70;
        symbolMap[")"] = 71;
        symbolMap["-"] = 72;
        symbolMap["_"] = 73;
        symbolMap["="] = 74;
        symbolMap["+"] = 75;
        symbolMap["["] = 76;
        symbolMap["]"] = 77;
        symbolMap["{"] = 78;
        symbolMap["}"] = 79;
        symbolMap[";"] = 80;
        symbolMap[":"] = 81;
        symbolMap["'"] = 82;
        symbolMap["\""] = 83;
        symbolMap[","] = 84;
        symbolMap["."] = 85;
        symbolMap["/"] = 86;
        symbolMap["\\"] = 87;
        symbolMap["|"] = 88;
        symbolMap["<"] = 89;
        symbolMap[">"] = 90;
        symbolMap["?"] = 91;
        symbolMap["`"] = 92;
        symbolMap["~"] = 93;
        // trace("Symbol map initialized."); // 符号映射表初始化日志
    }

    // 获取当前解析的索引
    public function getCurrentIndex():Number {
        // trace("Current index retrieved: " + this.currentIndex); // 输出当前索引
        return this.currentIndex;
    }

    // 读取下一个数字参数，并更新索引
    public function readNumber(commandStream:String, len:Number, i:Number):Number {
        this.currentIndex = i;
        // trace("Reading number, starting at index: " + this.currentIndex); // 日志输出读取开始的索引
        this.skipWhitespace(commandStream, len);
        var start:Number = this.currentIndex;
        var hasDot:Boolean = false;
        var hasMinus:Boolean = false;

        if (commandStream.charAt(this.currentIndex) == '-') {
            hasMinus = true;
            this.currentIndex++;
            // trace("Negative sign detected."); // 检测到负号的日志
        }

        while (this.currentIndex < len) {
            var c:String = commandStream.charAt(this.currentIndex);
            if (c >= '0' && c <= '9') {
                this.currentIndex++;
            } else if (c == '.' && !hasDot) {
                hasDot = true;
                this.currentIndex++;
            } else {
                break;
            }
        }

        var numStr:String = commandStream.substring(start, this.currentIndex);
        var num:Number = Number(numStr);
        if (isNaN(num)) {
            // trace("Invalid number detected: " + numStr); // 无效数字的日志
            throw new Error("无效的数字: " + numStr);
        }

        // trace("Read number: " + num + ", moving to index: " + this.currentIndex); // 输出读取到的数字和索引
        this.skipWhitespace(commandStream, len);
        if (this.currentIndex < len && commandStream.charAt(this.currentIndex) == ' ') {
            this.currentIndex++;
        }
        return num;
    }

    // 读取颜色编码（2字符），并更新索引
    public function readColorCode(commandStream:String, len:Number, i:Number):String {
        this.currentIndex = i;
        // trace("Reading color code, starting at index: " + this.currentIndex); // 输出读取颜色开始的索引
        this.skipWhitespace(commandStream, len);
        if (this.currentIndex + 1 >= len) {
            throw new Error("颜色编码不足");
        }
        var c1:String = commandStream.charAt(this.currentIndex++);
        var c2:String = commandStream.charAt(this.currentIndex++);
        // trace("Color code read: " + c1 + c2); // 输出读取的颜色编码
        this.skipWhitespace(commandStream, len);
        if (this.currentIndex < len && commandStream.charAt(this.currentIndex) == ' ') {
            this.currentIndex++;
        }
        return c1 + c2;
    }

    // 读取字符串参数（如渐变类型、bitmapId等），并更新索引
    public function readString(commandStream:String, len:Number, i:Number):String {
        this.currentIndex = i;
        // trace("Reading string, starting at index: " + this.currentIndex); // 输出读取字符串的起始位置
        this.skipWhitespace(commandStream, len);
        var start:Number = this.currentIndex;
        while (this.currentIndex < len && commandStream.charAt(this.currentIndex) != ' ' && commandStream.charAt(this.currentIndex) != ';') {
            this.currentIndex++;
        }
        var str:String = commandStream.substring(start, this.currentIndex);
        // trace("Read string: " + str); // 输出读取的字符串
        this.skipWhitespace(commandStream, len);
        if (this.currentIndex < len && commandStream.charAt(this.currentIndex) == ' ') {
            this.currentIndex++;
        }
        return str;
    }

    // 跳过空白字符
    private function skipWhitespace(commandStream:String, len:Number):Void {
        // trace("Skipping whitespace, starting at index: " + this.currentIndex); // 输出开始跳过空白字符的位置
        while (this.currentIndex < len && (commandStream.charAt(this.currentIndex) == ' ' || commandStream.charAt(this.currentIndex) == '\n' || commandStream.charAt(this.currentIndex) == '\t')) {
            this.currentIndex++;
        }
        // trace("Whitespace skipped, new index: " + this.currentIndex); // 输出跳过空白字符后的索引
    }

    // 颜色解码函数，返回 24 位颜色值
    public function decodeColor(colorCode:String):Number {
        // trace("Decoding color code: " + colorCode); // 输出正在解码的颜色编码
        if (colorCode.length != 2) {
            throw new Error("颜色编码必须为2字符");
        }
        var n1:Number = charToNumber(colorCode.charAt(0));
        var n2:Number = charToNumber(colorCode.charAt(1));

        var color:Number = ((((n1 >> 4) & 0xF) * 17) << 16) | (((((n1 & 0xF) << 4) | ((n2 >> 4) & 0xF)) * 17) << 8) | ((n2 & 0xF) * 17);
        // trace("Decoded color: " + color.toString(16)); // 输出解码后的颜色值
        return color;
    }

    // 字符转换为数字
    private function charToNumber(c:String):Number {
        var num:Number;
        if (c >= 'A' && c <= 'Z') {
            num = c.charCodeAt(0) - 'A'.charCodeAt(0);
        } else if (c >= 'a' && c <= 'z') {
            num = 26 + (c.charCodeAt(0) - 'a'.charCodeAt(0));
        } else if (c >= '0' && c <= '9') {
            num = 52 + (c.charCodeAt(0) - '0'.charCodeAt(0));
        } else {
            num = symbolMap[c] != undefined ? symbolMap[c] : 0;
        }
        // trace("Character converted to number: " + c + " -> " + num); // 输出字符与数字的映射关系
        return num;
    }

    // 解码多个颜色编码，返回颜色数组
    public function decodeColors(colors:String):Array {
        // trace("Decoding multiple color codes: " + colors); // 输出需要解码的颜色编码字符串
        var colorArray:Array = [];
        for (var j:Number = 0; j < colors.length; j += 2) {
            if (j + 1 >= colors.length)
                break;
            var c1:String = colors.charAt(j);
            var c2:String = colors.charAt(j + 1);
            var color:Number = decodeColor(c1 + c2);
            colorArray.push(color);
            // trace("Decoded color for " + c1 + c2 + ": " + color.toString(16)); // 输出解码后的每个颜色
        }
        return colorArray;
    }

    // 解码多个透明度编码，返回透明度数组
    public function decodeAlphas(alphas:String):Array {
        // trace("Decoding multiple alpha codes: " + alphas); // 输出需要解码的透明度编码字符串
        var alphaArray:Array = [];
        for (var j:Number = 0; j < alphas.length; j++) {
            var a:Number = charToNumber(alphas.charAt(j)) * 2; // 简化的透明度解码
            alphaArray.push(a > 255 ? 255 : a);
            // trace("Decoded alpha for " + alphas.charAt(j) + ": " + alphaArray[alphaArray.length - 1]); // 输出解码后的透明度
        }
        return alphaArray;
    }

    // 解码多个比例值，返回比例数组
    public function decodeRatios(ratios:String):Array {
        // trace("Decoding ratios: " + ratios); // 输出需要解码的比例字符串
        var ratioArray:Array = [];
        var parts:Array = ratios.split(',');
        for (var j:Number = 0; j < parts.length; j++) {
            var ratio:Number = Number(parts[j]);
            if (!isNaN(ratio)) {
                ratioArray.push(ratio);
                // trace("Decoded ratio: " + ratio); // 输出解码后的每个比例值
            }
        }
        return ratioArray;
    }

    // 获取位图数据，根据 bitmapId 获取对应的 MovieClip
    public function getBitmapById(bitmapId:String):MovieClip {
        // trace("Getting bitmap by id: " + bitmapId); // 输出位图ID
        var depth:Number = _root.getNextHighestDepth();
        var bitmapMC:MovieClip = _root.attachMovie(bitmapId, "bitmap_" + bitmapId + "_" + depth, depth);
        if (bitmapMC != undefined) {
            // trace("Bitmap found: " + bitmapId); // 输出找到的位图
            return bitmapMC;
        } else {
            // trace("Bitmap not found or invalid bitmapId: " + bitmapId); // 输出未找到位图的情况
            return null;
        }
    }
}
