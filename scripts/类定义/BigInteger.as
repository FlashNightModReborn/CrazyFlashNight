class BigInteger {
    static var DB = 30; // number of significant bits per chunk
    static var DV = (1<<DB);
    static var DM = (DV-1); // Max value in a chunk
    
    static var BI_FP = 52;
    static var FV = Math.pow(2, BI_FP);
    static var F1 = BI_FP - DB;
    static var F2 = 2 * DB - BI_FP;
    
    static var ZERO = BigInteger.nbv(0);
    static var ONE = BigInteger.nbv(1);
    
    var t; // number of chunks.
    var s; // sign
    var a; // chunks
    
    function BigInteger(value, radix, unsigned) {
        if (arguments.length < 3) unsigned = false;
        if (arguments.length < 2) radix = 0;
        if (arguments.length < 1) value = null;

        a = [];
        if (typeof value == "string") {
            if (radix && radix != 16) {
                fromRadix(value, radix);
            } else {
                value = Hex.toArray(value);
                radix = 0;
            }
        }
        if (value instanceof ByteArray) {
            var array = value;
            var length = radix || (array.length - array.position);
            fromArray(array, length, unsigned);
        }
    }
    
    function dispose() {
        var r = new Random();
        for (var i = 0; i < a.length; i++) {
            a[i] = r.nextByte();
            delete a[i];
        }
        a = null;
        t = 0;
        s = 0;
        Memory.gc();
    }
    
    function toString(radix) {
        if (arguments.length < 1) radix = 16;
        if (s < 0) return "-" + negate().toString(radix);
        var k;
        switch (radix) {
            case 2:   k = 1; break;
            case 4:   k = 2; break;
            case 8:   k = 3; break;
            case 16:  k = 4; break;
            case 32:  k = 5; break;
            default:
                return toRadix(radix);
        }
        var km = (1 << k) - 1;
        var d = 0;
        var m = false;
        var r = "";
        var i = t;
        var p = DB - (i * DB) % k;
        if (i-- > 0) {
            if (p < DB && (d = a[i] >> p) > 0) {
                m = true;
                r = d.toString(36);
            }
            while (i >= 0) {
                if (p < k) {
                    d = (a[i] & ((1 << p) - 1)) << (k - p);
                    d |= a[--i] >> (p += DB - k);
                } else {
                    d = (a[i] >> (p -= k)) & km;
                    if (p <= 0) {
                        p += DB;
                        --i;
                    }
                }
                if (d > 0) {
                    m = true;
                }
                if (m) {
                    r += d.toString(36);
                }
            }
        }
        return m ? r : "0";
    }
    
    function toArray(array) {
        var k = 8;
        var km = (1 << k) - 1;
        var d = 0;
        var i = t;
        var p = DB - (i * DB) % k;
        var m = false;
        var c = 0;
        if (i-- > 0) {
            if (p < DB && (d = a[i] >> p) > 0) {
                m = true;
                array.writeByte(d);
                c++;
            }
            while (i >= 0) {
                if (p < k) {
                    d = (a[i] & ((1 << p) - 1)) << (k - p);
                    d |= a[--i] >> (p += DB - k);
                } else {
                    d = (a[i] >> (p -= k)) & km;
                    if (p <= 0) {
                        p += DB;
                        --i;
                    }
                }
                if (d > 0) {
                    m = true;
                }
                if (m) {
                    array.writeByte(d);
                    c++;
                }
            }
        }
        return c;
    }
    
    function valueOf() {
        if (s == -1) {
            return -negate().valueOf();
        }
        var coef = 1;
        var value = 0;
        for (var i = 0; i < t; i++) {
            value += a[i] * coef;
            coef *= DV;
        }
        return value;
    }
    
    function negate() {
        var r = BigInteger.nbi();
        ZERO.subTo(this, r);
        return r;
    }
    
    function abs() {
        return (s < 0) ? negate() : this;
    }
    
    function compareTo(v) {
        var r = s - v.s;
        if (r != 0) {
            return r;
        }
        var i = t;
        r = i - v.t;
        if (r != 0) {
            return (s < 0) ? r * -1 : r;
        }
        while (--i >= 0) {
            r = a[i] - v.a[i];
            if (r != 0) return r;
        }
        return 0;
    }
    
    function nbits(x) {
        var r = 1;
        var t;
        if ((t = x >>> 16) != 0) {
            x = t;
            r += 16;
        }
        if ((t = x >> 8) != 0) {
            x = t;
            r += 8;
        }
        if ((t = x >> 4) != 0) {
            x = t;
            r += 4;
        }
        if ((t = x >> 2) != 0) {
            x = t;
            r += 2;
        }
        if ((t = x >> 1) != 0) {
            x = t;
            r += 1;
        }
        return r;
    }
    
    function bitLength() {
        if (t <= 0) return 0;
        return DB * (t - 1) + nbits(a[t - 1] ^ (s & DM));
    }
    
    function mod(v) {
        var r = BigInteger.nbi();
        abs().divRemTo(v, null, r);
        if (s < 0 && r.compareTo(ZERO) > 0) {
            v.subTo(r, r);
        }
        return r;
    }
    
    function modPowInt(e, m) {
        var z;
        if (e < 256 || m.isEven()) {
            z = new ClassicReduction(m);
        } else {
            z = new MontgomeryReduction(m);
        }
        return exp(e, z);
    }
    
    function copyTo(r) {
        for (var i = t - 1; i >= 0; --i) {
            r.a[i] = a[i];
        }
        r.t = t;
        r.s = s;
    }
    
    function fromInt(value) {
        t = 1;
        s = (value < 0) ? -1 : 0;
        if (value > 0) {
            a[0] = value;
        } else if (value < -1) {
            a[0] = value + DV;
        } else {
            t = 0;
        }
    }
    
    function fromArray(value, length, unsigned) {
        if (arguments.length < 3) unsigned = false;
        
        var p = value.position;
        var i = p + length;
        var sh = 0;
        var k = 8;
        t = 0;
        s = 0;
        while (--i >= p) {
            var x = (i < value.length) ? value[i] : 0;
            if (sh == 0) {
                a[t++] = x;
            } else if (sh + k > DB) {
                a[t - 1] |= (x & ((1 << (DB - sh)) - 1)) << sh;
                a[t++] = x >> (DB - sh);
            } else {
                a[t - 1] |= x << sh;
            }
            sh += k;
            if (sh >= DB) sh -= DB;
        }
        if (!unsigned && (value[0] & 0x80) == 0x80) {
            s = -1;
            if (sh > 0) {
                a[t - 1] |= ((1 << (DB - sh)) - 1) << sh;
            }
        }
        clamp();
        value.position = Math.min(p + length, value.length);
    }
    
    function clamp() {
        var c = s & DM;
        while (t > 0 && a[t - 1] == c) {
            --t;
        }
    }
    
    function dlShiftTo(n, r) {
        var i;
        for (i = t - 1; i >= 0; --i) {
            r.a[i + n] = a[i];
        }
        for (i = n - 1; i >= 0; --i) {
            r.a[i] = 0;
        }
        r.t = t + n;
        r.s = s;
    }
    
    function drShiftTo(n, r) {
        var i;
        for (i = n; i < t; ++i) {
            r.a[i - n] = a[i];
        }
        r.t = Math.max(t - n, 0);
        r.s = s;
    }
    
    function lShiftTo(n, r) {
        var bs = n % DB;
        var cbs = DB - bs;
        var bm = (1 << cbs) - 1;
        var ds = Math.floor(n / DB);
        var c = (s << bs) & DM;
        var i;
        for (i = t - 1; i >= 0; --i) {
            r.a[i + ds + 1] = (a[i] >> cbs) | c;
            c = (a[i] & bm) << bs;
        }
        for (i = ds - 1; i >= 0; --i) {
            r.a[i] = 0;
        }
        r.a[ds] = c;
        r.t = t + ds + 1;
        r.s = s;
        r.clamp();
    }
    
    function rShiftTo(n, r) {
        r.s = s;
        var ds = Math.floor(n / DB);
        if (ds >= t) {
            r.t = 0;
            return;
        }
        var bs = n % DB;
        var cbs = DB - bs;
        var bm = (1 << bs) - 1;
        r.a[0] = a[ds] >> bs;
        var i;
        for (i = ds + 1; i < t; ++i) {
            r.a[i - ds - 1] |= (a[i] & bm) << cbs;
            r.a[i - ds] = a[i] >> bs;
        }
        if (bs > 0) {
            r.a[t - ds - 1] |= (s & bm) << cbs;
        }
        r.t = t - ds;
        r.clamp();
    }
    
    function subTo(v, r) {
        var i = 0;
        var c = 0;
        var m = Math.min(v.t, t);
        while (i < m) {
            c += a[i] - v.a[i];
            r.a[i++] = c & DM;
            c >>= DB;
        }
        if (v.t < t) {
            c -= v.s;
            while (i < t) {
                c += a[i];
                r.a[i++] = c & DM;
                c >>= DB;
            }
            c += s;
        } else {
            c += s;
            while (i < v.t) {
                c -= v.a[i];
                r.a[i++] = c & DM;
                c >>= DB;
            }
            c -= v.s;
        }
        r.s = (c < 0) ? -1 : 0;
        if (c < -1) {
            r.a[i++] = DV + c;
        } else if (c > 0) {
            r.a[i++] = c;
        }
        r.t = i;
        r.clamp();
    }
    
    function am(i, x, w, j, c, n) {
        var xl = x & 0x7fff;
        var xh = x >> 15;
        while (--n >= 0) {
            var l = a[i] & 0x7fff;
            var h = a[i++] >> 15;
            var m = xh * l + h * xl;
            l = xl * l + ((m & 0x7fff) << 15) + w.a[j] + (c & 0x3fffffff);
            c = (l >>> 30) + (m >>> 15) + xh * h + (c >>> 30);
            w.a[j++] = l & 0x3fffffff;
        }
        return c;
    }
    
    function multiplyTo(v, r) {
        var x = abs();
        var y = v.abs();
        var i = x.t;
        r.t = i + y.t;
        while (--i >= 0) {
            r.a[i] = 0;
        }
        for (i = 0; i < y.t; ++i) {
            r.a[i + x.t] = x.am(0, y.a[i], r, i, 0, x.t);
        }
        r.s = 0;
        r.clamp();
        if (s != v.s) {
            ZERO.subTo(r, r);
        }
    }
    
    function squareTo(r) {
        var x = abs();
        var i = r.t = 2 * x.t;
        while (--i >= 0) r.a[i] = 0;
        for (i = 0; i < x.t - 1; ++i) {
            var c = x.am(i, x.a[i], r, 2 * i, 0, 1);
            if ((r.a[i + x.t] += x.am(i + 1, 2 * x.a[i], r, 2 * i + 1, c, x.t - i - 1)) >= DV) {
                r.a[i + x.t] -= DV;
                r.a[i + x.t + 1] = 1;
            }
        }
        if (r.t > 0) {
            r.a[r.t - 1] += x.am(i, x.a[i], r, 2 * i, 0, 1);
        }
        r.s = 0;
        r.clamp();
    }
    
    function divRemTo(m, q, r) {
        var pm = m.abs();
        if (pm.t <= 0) return;
        var pt = abs();
        if (pt.t < pm.t) {
            if (q != null) q.fromInt(0);
            if (r != null) copyTo(r);
            return;
        }
        if (r == null) r = BigInteger.nbi();
        var y = BigInteger.nbi();
        var ts = s;
        var ms = m.s;
        var nsh = DB - nbits(pm.a[pm.t - 1]); // normalize modulus
        if (nsh > 0) {
            pm.lShiftTo(nsh, y);
            pt.lShiftTo(nsh, r);
        } else {
            pm.copyTo(y);
            pt.copyTo(r);
        }
        var ys = y.t;
        var y0 = y.a[ys - 1];
        if (y0 == 0) return;
        var yt = y0 * (1 << F1) + ((ys > 1) ? y.a[ys - 2] >> F2 : 0);
        var d1 = FV / yt;
        var d2 = (1 << F1) / yt;
        var e = 1 << F2;
        var i = r.t;
        var j = i - ys;
        var t = (q == null) ? BigInteger.nbi() : q;
        y.dlShiftTo(j, t);
        if (r.compareTo(t) >= 0) {
            r.a[r.t++] = 1;
            r.subTo(t, r);
        }
        ONE.dlShiftTo(ys, t);
        t.subTo(y, y); // "negative" y so we can replace sub with am later.
        while (y.t < ys) y.a[y.t++] = 0;
        while (--j >= 0) {
            // Estimate quotient digit
            var qd = (r.a[--i] == y0) ? DM : Math.floor((r.a[i] * d1 + (r.a[i - 1] + e) * d2));
            if ((r.a[i] += y.am(0, qd, r, j, 0, ys)) < qd) { // Try it out
                y.dlShiftTo(j, t);
                r.subTo(t, r);
                while (r.a[i] < --qd) {
                    r.subTo(t, r);
                }
            }
        }
        if (q != null) {
            r.drShiftTo(ys, q);
            if (ts != ms) {
                ZERO.subTo(q, q);
            }
        }
        r.t = ys;
        r.clamp();
        if (nsh > 0) {
            r.rShiftTo(nsh, r); // Denormalize remainder
        }
        if (ts < 0) {
            ZERO.subTo(r, r);
        }
    }
    
    function invDigit() {
        if (t < 1) return 0;
        var x = a[0];
        if ((x & 1) == 0) return 0;
        var y = x & 3;                             // y == 1/x mod 2^2
        y = (y * (2 - (x & 0xf) * y)) & 0xf;       // y == 1/x mod 2^4
        y = (y * (2 - (x & 0xff) * y)) & 0xff;     // y == 1/x mod 2^8
        y = (y * (2 - ((x & 0xffff) * y & 0xffff))) & 0xffff; // y == 1/x mod 2^16
        // last step - calculate inverse mod DV directly;
        // assumes 16 < DB <= 32 and assumes ability to handle 48-bit ints
        // XXX 48 bit ints? Whaaaa? is there an implicit float conversion in here?
        y = (y * (2 - x * y % DV)) % DV;    // y == 1/x mod 2^dbits
        // we really want the negative inverse, and -DV < y < DV
        return (y > 0) ? DV - y : -y;
    }
    
    function isEven() {
        return ((t > 0) ? (a[0] & 1) : s) == 0;
    }
    
    function exp(e, z) {
        if (e > 0xffffffff || e < 1) return ONE;
        var r = BigInteger.nbi();
        var r2 = BigInteger.nbi();
        var g = z.convert(this);
        var i = nbits(e) - 1;
        g.copyTo(r);
        while (--i >= 0) {
            z.sqrTo(r, r2);
            if ((e & (1 << i)) > 0) {
                z.mulTo(r2, g, r);
            } else {
                var t = r;
                r = r2;
                r2 = t;
            }
        }
        return z.revert(r);
    }
    
    function intAt(str, index) {
        var i = parseInt(str.charAt(index), 36);
        return isNaN(i) ? -1 : i;
    }
    
    function nbi() {
        return new BigInteger();
    }
    
    static function nbv(value) {
        var bn = new BigInteger();
        bn.fromInt(value);
        return bn;
    }
    
    function clone() {
        var r = new BigInteger();
        this.copyTo(r);
        return r;
    }
    
    function intValue() {
        if (s < 0) {
            if (t == 1) {
                return a[0] - DV;
            } else if (t == 0) {
                return -1;
            }
        } else if (t == 1) {
            return a[0];
        } else if (t == 0) {
            return 0;
        }
        // assumes 16 < DB < 32
        return ((a[1] & ((1 << (32 - DB)) - 1)) << DB) | a[0];
    }
    
    function byteValue() {
        return (t == 0) ? s : (a[0] << 24) >> 24;
    }
    
    function shortValue() {
        return (t == 0) ? s : (a[0] << 16) >> 16;
    }
    
    function chunkSize(r) {
        return Math.floor(Math.LN2 * DB / Math.log(r));
    }
    
    function sigNum() {
        if (s < 0) {
            return -1;
        } else if (t <= 0 || (t == 1 && a[0] <= 0)) {
            return 0;
        } else {
            return 1;
        }
    }
    
    function toRadix(b) {
        if (arguments.length < 1) b = 10;
        if (sigNum() == 0 || b < 2 || b > 32) return "0";
        var cs = chunkSize(b);
        var d = Math.pow(b, cs);
        var y = BigInteger.nbi();
        var z = BigInteger.nbi();
        var r = "";
        divRemTo(BigInteger.nbv(d), y, z);
        while (y.sigNum() > 0) {
            r = (d + z.intValue()).toString(b).substr(1) + r;
            y.divRemTo(BigInteger.nbv(d), y, z);
        }
        return z.intValue().toString(b) + r;
    }
    
    function fromRadix(s, b) {
        if (arguments.length < 2) b = 10;
        fromInt(0);
        var cs = chunkSize(b);
        var d = Math.pow(b, cs);
        var mi = false;
        var j = 0;
        var w = 0;
        for (var i = 0; i < s.length; ++i) {
            var x = intAt(s, i);
            if (x < 0) {
                if (s.charAt(i) == "-" && sigNum() == 0) {
                    mi = true;
                }
                continue;
            }
            w = b * w + x;
            if (++j >= cs) {
                dMultiply(d);
                dAddOffset(w, 0);
                j = 0;
                w = 0;
            }
        }
        if (j > 0) {
            dMultiply(Math.pow(b, j));
            dAddOffset(w, 0);
        }
        if (mi) {
            BigInteger.ZERO.subTo(this, this);
        }
    }
    
    function toByteArray() {
        var i = t;
        var r = new ByteArray();
        r[0] = s;
        var p = DB - (i * DB) % 8;
        var d;
        var k = 0;
        if (i-- > 0) {
            if (p < DB && (d = a[i] >> p) != (s & DM) >> p) {
                r[k++] = d | (s << (DB - p));
            }
            while (i >= 0) {
                if (p < 8) {
                    d = (a[i] & ((1 << p) - 1)) << (8 - p);
                    d |= a[--i] >> (p += DB - 8);
                } else {
                    d = (a[i] >> (p -= 8)) & 0xff;
                    if (p <= 0) {
                        p += DB;
                        --i;
                    }
                }
                if ((d & 0x80) != 0) d |= -256;
                if (k == 0 && (s & 0x80) != (d & 0x80)) ++k;
                if (k > 0 || d != s) r[k++] = d;
            }
        }
        return r;
    }
    
    function equals(a) {
        return compareTo(a) == 0;
    }
    
    function min(a) {
        return (compareTo(a) < 0) ? this : a;
    }
    
    function max(a) {
        return (compareTo(a) > 0) ? this : a;
    }
    
    function bitwiseTo(a, op, r) {
        var i;
        var f;
        var m = Math.min(a.t, t);
        for (i = 0; i < m; ++i) {
            r.a[i] = op(this.a[i], a.a[i]);
        }
        if (a.t < t) {
            f = a.s & DM;
            for (i = m; i < t; ++i) {
                r.a[i] = op(this.a[i], f);
            }
            r.t = t;
        } else {
            f = s & DM;
            for (i = m; i < a.t; ++i) {
                r.a[i] = op(f, a.a[i]);
            }
            r.t = a.t;
        }
        r.s = op(s, a.s);
        r.clamp();
    }
    
    function op_and(x, y) {
        return x & y;
    }
    
    function and(a) {
        var r = new BigInteger();
        bitwiseTo(a, op_and, r);
        return r;
    }
    
    function op_or(x, y) {
        return x | y;
    }
    
    function or(a) {
        var r = new BigInteger();
        bitwiseTo(a, op_or, r);
        return r;
    }
    
    function op_xor(x, y) {
        return x ^ y;
    }
    
    function xor(a) {
        var r = new BigInteger();
        bitwiseTo(a, op_xor, r);
        return r;
    }
    
    function op_andnot(x, y) {
        return x & ~y;
    }
    
    function andNot(a) {
        var r = new BigInteger();
        bitwiseTo(a, op_andnot, r);
        return r;
    }
    
    function not() {
        var r = new BigInteger();
        for (var i = 0; i < t; ++i) {
            r.a[i] = DM & ~a[i];
        }
        r.t = t;
        r.s = ~s;
        return r;
    }
    
    function shiftLeft(n) {
        var r = new BigInteger();
        if (n < 0) {
            rShiftTo(-n, r);
        } else {
            lShiftTo(n, r);
        }
        return r;
    }
    
    function shiftRight(n) {
        var r = new BigInteger();
        if (n < 0) {
            lShiftTo(-n, r);
        } else {
            rShiftTo(n, r);
        }
        return r;
    }
    
    function lbit(x) {
        if (x == 0) return -1;
        var r = 0;
        if ((x & 0xffff) == 0) {
            x >>= 16;
            r += 16;
        }
        if ((x & 0xff) == 0) {
            x >>= 8;
            r += 8;
        }
        if ((x & 0xf) == 0) {
            x >>= 4;
            r += 4;
        }
        if ((x & 0x3) == 0) {
            x >>= 2;
            r += 2;
        }
        if ((x & 0x1) == 0) ++r;
        return r;
    }
    
    function getLowestSetBit() {
        for (var i = 0; i < t; ++i) {
            if (a[i] != 0) return i * DB + lbit(a[i]);
        }
        if (s < 0) return t * DB;
        return -1;
    }
    
    function cbit(x) {
        var r = 0;
        while (x != 0) {
            x &= x - 1;
            ++r;
        }
        return r;
    }
    
    function bitCount() {
        var r = 0;
        var x = s & DM;
        for (var i = 0; i < t; ++i) {
            r += cbit(a[i] ^ x);
        }
        return r;
    }
    
    function testBit(n) {
        var j = Math.floor(n / DB);
        if (j >= t) {
            return s != 0;
        }
        return ((a[j] & (1 << (n % DB))) != 0);
    }
    
    function changeBit(n, op) {
        var r = BigInteger.ONE.shiftLeft(n);
        bitwiseTo(r, op, r);
        return r;
    }
    
    function setBit(n) {
        return changeBit(n, op_or);
    }
    
    function clearBit(n) {
        return changeBit(n, op_andnot);
    }
    
    function flipBit(n) {
        return changeBit(n, op_xor);
    }
    
    function addTo(a, r) {
        var i = 0;
        var c = 0;
        var m = Math.min(a.t, t);
        while (i < m) {
            c += this.a[i] + a.a[i];
            r.a[i++] = c & DM;
            c >>= DB;
        }
        if (a.t < t) {
            c += a.s;
            while (i < t) {
                c += this.a[i];
                r.a[i++] = c & DM;
                c >>= DB;
            }
            c += s;
        } else {
            c += s;
            while (i < a.t) {
                c += a.a[i];
                r.a[i++] = c & DM;
                c >>= DB;
            }
            c += a.s;
        }
        r.s = (c < 0) ? -1 : 0;
        if (c > 0) {
            r.a[i++] = c;
        } else if (c < -1) {
            r.a[i++] = DV + c;
        }
        r.t = i;
        r.clamp();
    }
    
    function add(a) {
        var r = new BigInteger();
        addTo(a, r);
        return r;
    }
    
    function subtract(a) {
        var r = new BigInteger();
        subTo(a, r);
        return r;
    }
    
    function multiply(a) {
        var r = new BigInteger();
        multiplyTo(a, r);
        return r;
    }
    
    function divide(a) {
        var r = new BigInteger();
        divRemTo(a, r, null);
        return r;
    }
    
    function remainder(a) {
        var r = new BigInteger();
        divRemTo(a, null, r);
        return r;
    }
    
    function divideAndRemainder(a) {
        var q = new BigInteger();
        var r = new BigInteger();
        divRemTo(a, q, r);
        return [q, r];
    }
    
    function dMultiply(n) {
        a[t] = am(0, n - 1, this, 0, 0, t);
        ++t;
        clamp();
    }
    
    function dAddOffset(n, w) {
        while (t <= w) {
            a[t++] = 0;
        }
        a[w] += n;
        while (a[w] >= DV) {
            a[w] -= DV;
            if (++w >= t) {
                a[t++] = 0;
            }
            ++a[w];
        }
    }
    
    function pow(e) {
        return exp(e, new NullReduction());
    }
    
    function multiplyLowerTo(a, n, r) {
        var i = Math.min(t + a.t, n);
        r.s = 0; // assumes a, this >= 0
        r.t = i;
        while (i > 0) {
            r.a[--i] = 0;
        }
        var j;
        for (j = r.t - t; i < j; ++i) {
            r.a[i + t] = am(0, a.a[i], r, i, 0, t);
        }
        for (j = Math.min(a.t, n); i < j; ++i) {
            am(0, a.a[i], r, i, 0, n - i);
        }
        r.clamp();
    }
    
    function multiplyUpperTo(a, n, r) {
        --n;
        var i = r.t = t + a.t - n;
        r.s = 0; // assumes a, this >= 0
        while (--i >= 0) {
            r.a[i] = 0;
        }
        for (i = Math.max(n - t, 0); i < a.t; ++i) {
            r.a[t + i - n] = am(n - i, a.a[i], r, 0, 0, t + i - n);
        }
        r.clamp();
        r.drShiftTo(1, r);
    }
    
    function modPow(e, m) {
        var i = e.bitLength();
        var k;
        var r = BigInteger.nbv(1);
        var z;
        
        if (i <= 0) {
            return r;
        } else if (i < 18) {
            k = 1;
        } else if (i < 48) {
            k = 3;
        } else if (i < 144) {
            k = 4;
        } else if (i < 768) {
            k = 5;
        } else {
            k = 6;
        }
        if (i < 8) {
            z = new ClassicReduction(m);
        } else if (m.isEven()) {
            z = new BarrettReduction(m);
        } else {
            z = new MontgomeryReduction(m);
        }
        // precomputation
        var g = [];
        var n = 3;
        var k1 = k - 1;
        var km = (1 << k) - 1;
        g[1] = z.convert(this);
        if (k > 1) {
            var g2 = new BigInteger();
            z.sqrTo(g[1], g2);
            while (n <= km) {
                g[n] = new BigInteger();
                z.mulTo(g2, g[n - 2], g[n]);
                n += 2;
            }
        }
        
        var j = e.t - 1;
        var w;
        var is1 = true;
        var r2 = new BigInteger();
        var t;
        i = nbits(e.a[j]) - 1;
        while (j >= 0) {
            if (i >= k1) {
                w = (e.a[j] >> (i - k1)) & km;
            } else {
                w = (e.a[j] & ((1 << (i + 1)) - 1)) << (k1 - i);
                if (j > 0) {
                    w |= e.a[j - 1] >> (DB + i - k1);
                }
            }
            n = k;
            while ((w & 1) == 0) {
                w >>= 1;
                --n;
            }
            if ((i -= n) < 0) {
                i += DB;
                --j;
            }
            if (is1) { // ret == 1, don't bother squaring or multiplying it
                g[w].copyTo(r);
                is1 = false;
            } else {
                while (n > 1) {
                    z.sqrTo(r, r2);
                    z.sqrTo(r2, r);
                    n -= 2;
                }
                if (n > 0) {
                    z.sqrTo(r, r2);
                } else {
                    t = r;
                    r = r2;
                    r2 = t;
                }
                z.mulTo(r2, g[w], r);
            }
            while (j >= 0 && (e.a[j] & (1 << i)) == 0) {
                z.sqrTo(r, r2);
                t = r;
                r = r2;
                r2 = t;
                if (--i < 0) {
                    i = DB - 1;
                    --j;
                }
                
            }
        }
        return z.revert(r);
    }
    
    function gcd(a) {
        var x = (s < 0) ? negate() : clone();
        var y = (a.s < 0) ? a.negate() : a.clone();
        if (x.compareTo(y) < 0) {
            var t = x;
            x = y;
            y = t;
        }
        var i = x.getLowestSetBit();
        var g = y.getLowestSetBit();
        if (g < 0) return x;
        if (i < g) g = i;
        if (g > 0) {
            x.rShiftTo(g, x);
            y.rShiftTo(g, y);
        }
        while (x.sigNum() > 0) {
            if ((i = x.getLowestSetBit()) > 0) {
                x.rShiftTo(i, x);
            }
            if ((i = y.getLowestSetBit()) > 0) {
                y.rShiftTo(i, y);
            }
            if (x.compareTo(y) >= 0) {
                x.subTo(y, x);
                x.rShiftTo(1, x);
            } else {
                y.subTo(x, y);
                y.rShiftTo(1, y);
            }
        }
        if (g > 0) {
            y.lShiftTo(g, y);
        }
        return y;
    }
    
    function modInt(n) {
        if (n <= 0) return 0;
        var d = DV % n;
        var r = (s < 0) ? n - 1 : 0;
        if (t > 0) {
            if (d == 0) {
                r = a[0] % n;
            } else {
                for (var i = t - 1; i >= 0; --i) {
                    r = (d * r + a[i]) % n;
                }
            }
        }
        return r;
    }
    
    function modInverse(m) {
        var ac = m.isEven();
        if ((isEven() && ac) || m.sigNum() == 0) {
            return BigInteger.ZERO;
        }
        var u = m.clone();
        var v = clone();
        var a = BigInteger.nbv(1);
        var b = BigInteger.nbv(0);
        var c = BigInteger.nbv(0);
        var d = BigInteger.nbv(1);
        while (u.sigNum() != 0) {
            while (u.isEven()) {
                u.rShiftTo(1, u);
                if (ac) {
                    if (!a.isEven() || !b.isEven()) {
                        a.addTo(this, a);
                        b.subTo(m, b);
                    }
                    a.rShiftTo(1, a);
                } else if (!b.isEven()) {
                    b.subTo(m, b);
                }
                b.rShiftTo(1, b);
            }
            while (v.isEven()) {
                v.rShiftTo(1, v);
                if (ac) {
                    if (!c.isEven() || !d.isEven()) {
                        c.addTo(this, c);
                        d.subTo(m, d);
                    }
                    c.rShiftTo(1, c);
                } else if (!d.isEven()) {
                    d.subTo(m, d);
                }
                d.rShiftTo(1, d);
            }
            if (u.compareTo(v) >= 0) {
                u.subTo(v, u);
                if (ac) {
                    a.subTo(c, a);
                }
                b.subTo(d, b);
            } else {
                v.subTo(u, v);
                if (ac) {
                    c.subTo(a, c);
                }
                d.subTo(b, d);
            }
        }
        if (v.compareTo(BigInteger.ONE) != 0) {
            return BigInteger.ZERO;
        }
        if (d.compareTo(m) >= 0) {
            return d.subtract(m);
        }
        if (d.sigNum() < 0) {
            d.addTo(m, d);
        } else {
            return d;
        }
        if (d.sigNum() < 0) {
            return d.add(m);
        } else {
            return d;
        }
    }
    
    function isProbablePrime(t) {
        var i;
        var x = abs();
        if (x.t == 1 && x.a[0] <= BigInteger.lowprimes[BigInteger.lowprimes.length - 1]) {
            for (i = 0; i < BigInteger.lowprimes.length; ++i) {
                if (x[0] == BigInteger.lowprimes[i]) return true;
            }
            return false;
        }
        if (x.isEven()) return false;
        i = 1;
        while (i < BigInteger.lowprimes.length) {
            var m = BigInteger.lowprimes[i];
            var j = i + 1;
            while (j < BigInteger.lowprimes.length && m < BigInteger.lplim) {
                m *= BigInteger.lowprimes[j++];
            }
            m = x.modInt(m);
            while (i < j) {
                if (m % BigInteger.lowprimes[i++] == 0) {
                    return false;
                }
            }
        }
        return x.millerRabin(t);
    }
    
    function millerRabin(t) {
        var n1 = subtract(BigInteger.ONE);
        var k = n1.getLowestSetBit();
        if (k <= 0) {
            return false;
        }
        var r = n1.shiftRight(k);
        t = (t + 1) >> 1;
        if (t > BigInteger.lowprimes.length) {
            t = BigInteger.lowprimes.length;
        }
        var a = new BigInteger();
        for (var i = 0; i < t; ++i) {
            a.fromInt(BigInteger.lowprimes[i]);
            var y = a.modPow(r, this);
            if (y.compareTo(BigInteger.ONE) != 0 && y.compareTo(n1) != 0) {
                var j = 1;
                while (j++ < k && y.compareTo(n1) != 0) {
                    y = y.modPowInt(2, this);
                    if (y.compareTo(BigInteger.ONE) == 0) {
                        return false;
                    }
                }
                if (y.compareTo(n1) != 0) {
                    return false;
                }
            }
        }
        return true;
    }
    
    function primify(bits, t) {
        if (!testBit(bits - 1)) {    // force MSB set
            bitwiseTo(BigInteger.ONE.shiftLeft(bits - 1), op_or, this);
        }
        if (isEven()) {
            dAddOffset(1, 0);    // force odd
        }
        while (!isProbablePrime(t)) {
            dAddOffset(2, 0);
            while (bitLength() > bits) subTo(BigInteger.ONE.shiftLeft(bits - 1), this);
        }
    }
    
    // Static properties and methods
    static var lowprimes = [2, 3, 5, 7, 11, 13, 17, 19, 23, 29, 31, 37, 41, 43, 47, 53, 59, 61, 67, 71, 73, 79, 83, 89, 97, 101, 103, 107, 109, 113, 127, 131, 137, 139, 149, 151, 157, 163, 167, 173, 179, 181, 191, 193, 197, 199, 211, 223, 227, 229, 233, 239, 241, 251, 257, 263, 269, 271, 277, 281, 283, 293, 307, 311, 313, 317, 331, 337, 347, 349, 353, 359, 367, 373, 379, 383, 389, 397, 401, 409, 419, 421, 431, 433, 439, 443, 449, 457, 461, 463, 467, 479, 487, 491, 499, 503, 509];
    static var lplim = (1 << 26) / lowprimes[lowprimes.length - 1];
    
    static var Hex = {
        toArray: function (hexString) {
            var result = new ByteArray();
            for (var i = 0; i < hexString.length; i += 2) {
                var hex = hexString.substr(i, 2);
                result.writeByte(parseInt(hex, 16));
            }
            return result;
        }
    };
    
    static var Random = {
        nextByte: function () {
            return Math.floor(Math.random() * 256);
        }
    };
    
    static var Memory = {
        gc: function () {
            // Garbage collection is automatic in ActionScript 2. No need for explicit calls.
        }
    };
}
