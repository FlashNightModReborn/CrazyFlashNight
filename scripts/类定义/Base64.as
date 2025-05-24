// Base64.as
class Base64
{
    // Base64 字符集
    private static var keyStr:String = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/=";
    
    // 反向映射表，用于快速查找字符对应的索引
    private static var reverseKey:Object = Base64.buildReverseKey();
    
    // 构建反向映射表
    private static function buildReverseKey():Object
    {
        var obj:Object = {};
        for (var i:Number = 0; i < keyStr.length; i++)
        {
            obj[keyStr.charAt(i)] = i;
        }
        return obj;
    }
    
    /**
     * Base64 编码
     * @param input 要编码的字符串
     * @return 编码后的 Base64 字符串
     */
    public static function encode(input:String):String
    {
        // 将字符串转换为 UTF-8 字节数组
        var bytes:Array = stringToUTF8Bytes(input);
        var output:Array = [];
        var i:Number = 0;
        
        while (i < bytes.length)
        {
            var chr1:Number = bytes[i++];
            var chr2:Number = (i < bytes.length) ? bytes[i++] : NaN;
            var chr3:Number = (i < bytes.length) ? bytes[i++] : NaN;
            
            var enc1:Number = chr1 >> 2;
            var enc2:Number = ((chr1 & 3) << 4) | ((isNaN(chr2) ? 0 : chr2) >> 4);
            var enc3:Number = isNaN(chr2) ? 64 : (((chr2 & 15) << 2) | ((isNaN(chr3) ? 0 : chr3) >> 6));
            var enc4:Number = isNaN(chr3) ? 64 : (chr3 & 63);
            
            output.push(
                keyStr.charAt(enc1),
                keyStr.charAt(enc2),
                keyStr.charAt(enc3),
                keyStr.charAt(enc4)
            );
        }
        
        return output.join("");
    }
    
    /**
     * Base64 解码
     * @param input 要解码的 Base64 字符串
     * @return 解码后的字符串
     */
    public static function decode(input:String):String
    {
        // 移除并验证输入中的无效 Base64 字符
        input = removeInvalidBase64Chars(input);
        
        // 验证输入长度是否为 4 的倍数
        if (input.length % 4 != 0)
        {
            throw new Error("Invalid Base64 input length.");
        }
        
        var output:Array = [];
        var i:Number = 0;
        
        while (i < input.length)
        {
            var enc1:Number = reverseKey[input.charAt(i++)];
            var enc2:Number = reverseKey[input.charAt(i++)];
            var enc3:Number = reverseKey[input.charAt(i++)];
            var enc4:Number = reverseKey[input.charAt(i++)];
            
            // 检查是否存在未定义的映射
            if (enc1 == undefined || enc2 == undefined || enc3 == undefined || enc4 == undefined)
            {
                throw new Error("Invalid character found in Base64 input.");
            }
            
            var chr1:Number = (enc1 << 2) | (enc2 >> 4);
            var chr2:Number = ((enc2 & 15) << 4) | (enc3 >> 2);
            var chr3:Number = ((enc3 & 3) << 6) | enc4;
            
            output.push(chr1);
            
            if (enc3 != 64)
            {
                output.push(chr2);
            }
            if (enc4 != 64)
            {
                output.push(chr3);
            }
        }
        
        // 将字节数组转换回 UTF-8 字符串
        var str:String = utf8BytesToString(output);
        return str;
    }
    
    /**
     * 移除输入中的所有无效 Base64 字符，如果存在非法字符则抛出错误
     * @param input 原始输入字符串
     * @return 仅包含有效 Base64 字符的字符串
     */
    private static function removeInvalidBase64Chars(input:String):String
    {
        var output:Array = [];
        var base64Chars:String = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/=";
        for (var i:Number = 0; i < input.length; i++)
        {
            var char:String = input.charAt(i);
            if (base64Chars.indexOf(char) != -1)
            {
                output.push(char);
            }
            else
            {
                throw new Error("Invalid character found in Base64 input.");
            }
        }
        return output.join("");
    }
    
    /**
	 * 将字符串转换为 UTF-8 字节数组
	 * @param str 要转换的字符串
	 * @return UTF-8 字节数组
	 */
	private static function stringToUTF8Bytes(str:String):Array
	{
		var bytes:Array = [];
		var i:Number = 0;
		while (i < str.length)
		{
			var c:Number = str.charCodeAt(i++);
			// 检查是否是高代理项
			if (c >= 0xD800 && c <= 0xDBFF && i < str.length)
			{
				var c2:Number = str.charCodeAt(i++);
				if (c2 >= 0xDC00 && c2 <= 0xDFFF)
				{
					// 组合高低代理项
					var codePoint:Number = ((c - 0xD800) << 10) + (c2 - 0xDC00) + 0x10000;
					// 编码为4字节UTF-8
					bytes.push(0xF0 | ((codePoint >> 18) & 0x07));
					bytes.push(0x80 | ((codePoint >> 12) & 0x3F));
					bytes.push(0x80 | ((codePoint >> 6) & 0x3F));
					bytes.push(0x80 | (codePoint & 0x3F));
				}
				else
				{
					throw new Error("Invalid surrogate pair in string.");
				}
			}
			else if (c < 0x80)
			{
				bytes.push(c);  // 1字节的UTF-8字符
			}
			else if (c < 0x800)
			{
				bytes.push(0xC0 | (c >> 6));  // 2字节的UTF-8字符
				bytes.push(0x80 | (c & 0x3F));
			}
			else
			{
				bytes.push(0xE0 | (c >> 12));  // 3字节的UTF-8字符
				bytes.push(0x80 | ((c >> 6) & 0x3F));
				bytes.push(0x80 | (c & 0x3F));
			}
		}
		return bytes;
	}

    
    /**
     * 将 UTF-8 字节数组转换回字符串
     * @param bytes UTF-8 字节数组
     * @return 解码后的字符串
     */
    private static function utf8BytesToString(bytes:Array):String
    {
        var str:String = "";
        var i:Number = 0;
        while (i < bytes.length)
        {
            var c:Number = bytes[i++];
            if (c < 0x80)
            {
                str += String.fromCharCode(c);
            }
            else if ((c & 0xE0) == 0xC0)
            {
                var c2:Number = bytes[i++];
                if ((c2 & 0xC0) != 0x80)
                {
                    throw new Error("Invalid UTF-8 encoding.");
                }
                var charCode:Number = ((c & 0x1F) << 6) | (c2 & 0x3F);
                str += String.fromCharCode(charCode);
            }
            else if ((c & 0xF0) == 0xE0)
            {
                var c2:Number = bytes[i++];
                var c3:Number = bytes[i++];
                if (((c2 & 0xC0) != 0x80) || ((c3 & 0xC0) != 0x80))
                {
                    throw new Error("Invalid UTF-8 encoding.");
                }
                var charCode2:Number = ((c & 0x0F) << 12) | ((c2 & 0x3F) << 6) | (c3 & 0x3F);
                str += String.fromCharCode(charCode2);
            }
            else if ((c & 0xF8) == 0xF0)
            {
                var c2a:Number = bytes[i++];
                var c3a:Number = bytes[i++];
                var c4:Number = bytes[i++];
                if (((c2a & 0xC0) != 0x80) || ((c3a & 0xC0) != 0x80) || ((c4 & 0xC0) != 0x80))
                {
                    throw new Error("Invalid UTF-8 encoding.");
                }
                var codePoint:Number = ((c & 0x07) << 18) | ((c2a & 0x3F) << 12) | ((c3a & 0x3F) << 6) | (c4 & 0x3F);
                // 转换为代理对
                var highSurrogate:Number = Math.floor((codePoint - 0x10000) / 0x400) + 0xD800;
                var lowSurrogate:Number = ((codePoint - 0x10000) % 0x400) + 0xDC00;
                str += String.fromCharCode(highSurrogate) + String.fromCharCode(lowSurrogate);
            }
            else
            {
                throw new Error("Invalid UTF-8 encoding.");
            }
        }
        return str;
    }
}
