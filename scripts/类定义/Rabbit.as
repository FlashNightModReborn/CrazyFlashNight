class Rabbit {
    private var x:Array;
    private var c:Array;
    private var carry:Number;

    public function Rabbit() {
        this.x = new Array(8);
        this.c = new Array(8);
        this.carry = 0;
    }

    public function initialize(key:String, iv:String):Void {
        var keyBytes:Array = this.stringToBytes(key);
        var ivBytes:Array = this.stringToBytes(iv);

        var k0:Number = keyBytes[0] | (keyBytes[1] << 8) | (keyBytes[2] << 16) | (keyBytes[3] << 24);
        var k1:Number = keyBytes[4] | (keyBytes[5] << 8) | (keyBytes[6] << 16) | (keyBytes[7] << 24);
        var k2:Number = keyBytes[8] | (keyBytes[9] << 8) | (keyBytes[10] << 16) | (keyBytes[11] << 24);
        var k3:Number = keyBytes[12] | (keyBytes[13] << 8) | (keyBytes[14] << 16) | (keyBytes[15] << 24);

        this.x[0] = k0;
        this.x[1] = k2;
        this.x[2] = k1;
        this.x[3] = k3;
        this.x[4] = (k0 << 16) | (k2 >>> 16);
        this.x[5] = (k2 << 16) | (k0 >>> 16);
        this.x[6] = (k1 << 16) | (k3 >>> 16);
        this.x[7] = (k3 << 16) | (k1 >>> 16);

        this.c[0] = (k2 << 16) | (k0 >>> 16);
        this.c[1] = (k3 << 16) | (k1 >>> 16);
        this.c[2] = (k0 << 16) | (k2 >>> 16);
        this.c[3] = (k1 << 16) | (k3 >>> 16);
        this.c[4] = k0;
        this.c[5] = k2;
        this.c[6] = k1;
        this.c[7] = k3;

        this.carry = 0;
        for (var i:Number = 0; i < 4; i++) {
            this.nextState();
        }

        for (var j:Number = 0; j < 8; j++) {
            this.c[j] ^= this.x[(j + 4) & 7];
        }

        if (ivBytes.length > 0) {
            var iv0:Number = ivBytes[0] | (ivBytes[1] << 8) | (ivBytes[2] << 16) | (ivBytes[3] << 24);
            var iv1:Number = ivBytes[4] | (ivBytes[5] << 8) | (ivBytes[6] << 16) | (ivBytes[7] << 24);

            this.c[0] ^= iv0;
            this.c[1] ^= (iv0 >>> 16) | (iv1 << 16);
            this.c[2] ^= iv1;
            this.c[3] ^= (iv1 >>> 16) | (iv0 << 16);
            this.c[4] ^= iv0;
            this.c[5] ^= (iv0 >>> 16) | (iv1 << 16);
            this.c[6] ^= iv1;
            this.c[7] ^= (iv1 >>> 16) | (iv0 << 16);

            for (var k:Number = 0; k < 4; k++) {
                this.nextState();
            }
        }
    }

    public function nextState():Void {
        var g:Array = new Array(8);
        for (var j:Number = 0; j < 8; j++) {
            var tmp:Number = this.x[j] + this.c[j] + this.carry;
            this.carry = (tmp >>> 32) & 1;
            this.c[j] = (tmp & 0xffffffff);
            g[j] = this.gFunc(this.c[j]);
        }

        for (var i:Number = 0; i < 8; i++) {
            this.x[i] = g[i] + this.rotl(g[(i + 7) & 7], 16) + this.rotl(g[(i + 6) & 7], 16);
        }
    }

    private function gFunc(x:Number):Number {
        var a:Number = x & 0xffff;
        var b:Number = x >>> 16;
        return ((a * a) + 2 * a * b + b * b) & 0xffffffff;
    }

    private function rotl(x:Number, n:Number):Number {
        return (x << n) | (x >>> (32 - n));
    }

    public function encrypt(data:String):String {
        return this.process(data);
    }

    public function decrypt(data:String):String {
        return this.process(data);
    }

    private function process(data:String):String {
        var dataBytes:Array = this.stringToBytes(data);
        var outputBytes:Array = new Array(dataBytes.length);

        for (var i:Number = 0; i < dataBytes.length; i++) {
            if (i % 8 == 0) {
                this.nextState();
            }
            outputBytes[i] = dataBytes[i] ^ ((this.x[i % 8] >>> ((i % 4) * 8)) & 0xff);
        }

        return this.bytesToString(outputBytes);
    }

    private function stringToBytes(str:String):Array {
        var bytes:Array = [];
        for (var i:Number = 0; i < str.length; i++) {
            bytes.push(str.charCodeAt(i));
        }
        return bytes;
    }

    private function bytesToString(bytes:Array):String {
        var str:String = "";
        for (var i:Number = 0; i < bytes.length; i++) {
            str += String.fromCharCode(bytes[i]);
        }
        return str;
    }
}