class MD5 {
    private static var hexChars:String = "0123456789abcdef";
    private static var s:Array = [7, 12, 17, 22, 5, 9, 14, 20, 4, 11, 16, 23, 6, 10, 15, 21];
    private static var K:Array = [];

    // 初始化 K 值
    private static function initK():Void {
        if (K.length > 0) {
            return;
        }
        for (var i:Number = 0; i < 64; i++) {
            K[i] = Math.floor(Math.abs(Math.sin(i + 1)) * 4294967296);
        }
    }

    public static function hash(message:String):String {
        initK();
        var m:Array = stringToBlocks(message);
        var H:Array = [1732584193, -271733879, -1732584194, 271733878];
        var a:Number, b:Number, c:Number, d:Number;

        for (var i:Number = 0; i < m.length; i += 16) {
            a = H[0];
            b = H[1];
            c = H[2];
            d = H[3];

            for (var j:Number = 0; j < 64; j++) {
                var div16:Number = Math.floor(j / 16);
                var f:Number, g:Number;
                if (div16 == 0) {
                    f = (b & c) | ((~b) & d);
                    g = j;
                } else if (div16 == 1) {
                    f = (d & b) | ((~d) & c);
                    g = (5 * j + 1) % 16;
                } else if (div16 == 2) {
                    f = b ^ c ^ d;
                    g = (3 * j + 5) % 16;
                } else {
                    f = c ^ (b | (~d));
                    g = (7 * j) % 16;
                }
                var tmp:Number = d;
                d = c;
                c = b;
                b = b + rotateLeft((a + f + K[j] + m[i + g]), s[(div16 * 4) + (j % 4)]);
                a = tmp;
            }

            H[0] = add32(H[0], a);
            H[1] = add32(H[1], b);
            H[2] = add32(H[2], c);
            H[3] = add32(H[3], d);
        }

        return toHex(H[0]) + toHex(H[1]) + toHex(H[2]) + toHex(H[3]);
    }

    private static function rotateLeft(lValue:Number, iShiftBits:Number):Number {
        return (lValue << iShiftBits) | (lValue >>> (32 - iShiftBits));
    }

    private static function stringToBlocks(s:String):Array {
        var blocks:Array = [];
        var len:Number = s.length * 8;
        for (var i:Number = 0; i < len; i += 8) {
            blocks[i >> 5] |= (s.charCodeAt(i / 8) & 0xFF) << (i % 32);
        }
        blocks[len >> 5] |= 0x80 << (len % 32);
        blocks[(((len + 64) >>> 9) << 4) + 14] = len;
        return blocks;
    }

    private static function add32(a:Number, b:Number):Number {
        return (a + b) & 0xFFFFFFFF;
    }

    private static function toHex(num:Number):String {
        var str:String = "";
        for (var j:Number = 0; j <= 3; j++) {
            str += hexChars.charAt((num >> (j * 8 + 4)) & 0x0F) + hexChars.charAt((num >> (j * 8)) & 0x0F);
        }
        return str;
    }
}