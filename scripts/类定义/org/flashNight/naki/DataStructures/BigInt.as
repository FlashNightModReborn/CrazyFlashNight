class org.flashNight.naki.DataStructures.BigInt {
    private var blocks:Array;
    private var base:Number;
    private var blockSize:Number;
    private var sign:Number; // 1 for positive, -1 for negative

    // Constructor
    public function BigInt(value:String) {
        this.blocks = [];
        this.blockSize = 4; // 4 digits per block
        this.base = Math.pow(10, this.blockSize); // 10000
        this.sign = 1; // default positive

        // Handle empty string
        if (value.length == 0) {
            this.blocks.push(0);
            return;
        }

        // Handle sign
        var startIndex:Number = 0;
        if (value.charAt(0) == '-') {
            this.sign = -1;
            startIndex = 1;
        } else if (value.charAt(0) == '+') {
            startIndex = 1;
        }

        // Process digits from right to left, 4 digits at a time
        var len:Number = value.length;
        var i:Number = len;
        while (i > startIndex) {
            var start:Number = Math.max(i - this.blockSize, startIndex);
            var blockStr:String = value.substring(start, i);
            this.blocks.push(Number(blockStr));
            i -= this.blockSize;
        }

        this.trim();
    }

    // Remove leading zeros
    private function trim():Void {
        while (this.blocks.length > 1 && this.blocks[this.blocks.length - 1] == 0) {
            this.blocks.pop();
        }
        // If number is zero, set sign to positive
        if (this.blocks.length == 1 && this.blocks[0] == 0) {
            this.sign = 1;
        }
    }

    // Convert BigInt to string
    public function toString():String {
        var str:String = (this.sign < 0) ? "-" : "";
        for (var i:Number = this.blocks.length - 1; i >= 0; i--) {
            if (i == this.blocks.length - 1) {
                str += this.blocks[i].toString();
            } else {
                var blockStr:String = this.blocks[i].toString();
                // Pad with leading zeros if necessary
                while (blockStr.length < this.blockSize) {
                    blockStr = "0" + blockStr;
                }
                str += blockStr;
            }
        }
        return str;
    }

    // Check if BigInt is zero
    public function isZero():Boolean {
        return (this.blocks.length == 1 && this.blocks[0] == 0);
    }

    // Clone the BigInt
    public function clone():BigInt {
        var cloned:BigInt = new BigInt("0");
        cloned.blocks = this.blocks.slice();
        cloned.blockSize = this.blockSize;
        cloned.base = this.base;
        cloned.sign = this.sign;
        return cloned;
    }

    // Compare absolute values
    private function compareAbs(other:BigInt):Number {
        if (this.blocks.length > other.blocks.length) return 1;
        if (this.blocks.length < other.blocks.length) return -1;
        for (var i:Number = this.blocks.length - 1; i >= 0; i--) {
            if (this.blocks[i] > other.blocks[i]) return 1;
            if (this.blocks[i] < other.blocks[i]) return -1;
        }
        return 0; // equal
    }

    // Compare with sign
    public function compare(other:BigInt):Number {
        if (this.sign > other.sign) return 1;
        if (this.sign < other.sign) return -1;
        // Same sign, compare absolute
        var cmp:Number = this.compareAbs(other);
        return this.sign * cmp;
    }

    // Add absolute values
    private function addAbs(other:BigInt):BigInt {
        var result:BigInt = new BigInt("0");
        result.blocks = [];
        var carry:Number = 0;
        var maxLength:Number = Math.max(this.blocks.length, other.blocks.length);
        for (var i:Number = 0; i < maxLength; i++) {
            var a:Number = (i < this.blocks.length) ? this.blocks[i] : 0;
            var b:Number = (i < other.blocks.length) ? other.blocks[i] : 0;
            var sum:Number = a + b + carry;
            carry = Math.floor(sum / this.base);
            var block:Number = sum % this.base;
            result.blocks.push(block);
        }
        if (carry > 0) {
            result.blocks.push(carry);
        }
        return result;
    }

    // Subtract absolute values (assuming this >= other)
    private function subtractAbs(other:BigInt):BigInt {
        var result:BigInt = new BigInt("0");
        result.blocks = [];
        var borrow:Number = 0;
        for (var i:Number = 0; i < this.blocks.length; i++) {
            var a:Number = this.blocks[i];
            var b:Number = (i < other.blocks.length) ? other.blocks[i] : 0;
            var diff:Number = a - b - borrow;
            if (diff < 0) {
                diff += this.base;
                borrow = 1;
            } else {
                borrow = 0;
            }
            result.blocks.push(diff);
        }
        result.trim();
        return result;
    }

    // Add two BigInts
    public function add(other:BigInt):BigInt {
        var result:BigInt;
        if (this.sign == other.sign) {
            // Same sign, add absolute values
            result = this.addAbs(other);
            result.sign = this.sign;
        } else {
            // Different signs, subtract smaller absolute from larger absolute
            var cmp:Number = this.compareAbs(other);
            if (cmp >= 0) {
                result = this.subtractAbs(other);
                result.sign = this.sign;
            } else {
                result = other.subtractAbs(this);
                result.sign = other.sign;
            }
        }
        result.trim();
        return result;
    }

    // Subtract two BigInts
    public function subtract(other:BigInt):BigInt {
        var negOther:BigInt = other.clone();
        negOther.sign = -other.sign;
        return this.add(negOther);
    }

    // Multiply two BigInts
    public function multiply(other:BigInt):BigInt {
        // Use basic multiplication
        var result:BigInt = this.multiplyBasic(other);
        result.sign = this.sign * other.sign;
        result.trim();
        return result;
    }

    // Basic multiplication (grade-school)
    private function multiplyBasic(other:BigInt):BigInt {
        var result:BigInt = new BigInt("0");
        result.blocks = [];
        for (var i:Number = 0; i < this.blocks.length + other.blocks.length; i++) {
            result.blocks[i] = 0;
        }

        for (var i:Number = 0; i < this.blocks.length; i++) {
            var carry:Number = 0;
            var aDigit:Number = this.blocks[i];
            for (var j:Number = 0; j < other.blocks.length; j++) {
                var product:Number = aDigit * other.blocks[j] + result.blocks[i + j] + carry;
                carry = Math.floor(product / this.base);
                result.blocks[i + j] = product % this.base;
            }
            if (carry > 0) {
                result.blocks[i + other.blocks.length] += carry;
            }
        }

        result.trim();
        return result;
    }

    // Shift left by n blocks (multiply by base^n)
    public function shiftLeft(n:Number):BigInt {
        if (this.isZero()) return new BigInt("0");
        var result:BigInt = this.clone();
        for (var i:Number = 0; i < n; i++) {
            result.blocks.unshift(0);
        }
        return result;
    }

    // Shift right by n blocks (divide by base^n)
    public function shiftRight(n:Number):BigInt {
        if (n >= this.blocks.length) return new BigInt("0");
        var result:BigInt = new BigInt("0");
        result.blocks = this.blocks.slice(n);
        result.sign = this.sign;
        result.trim();
        return result;
    }

    // Divide and mod (using loop-based subtraction for correctness)
    public function divideAndMod(other:BigInt):Object {
        if (other.isZero()) {
            throw new Error("Division by zero");
        }

        var dividend:BigInt = this.clone();
        var divisor:BigInt = other.clone();

        // Handle signs
        var resultSign:Number = this.sign * other.sign;
        dividend.sign = 1;
        divisor.sign = 1;

        var quotient:BigInt = new BigInt("0");
        var remainder:BigInt = new BigInt("0");

        trace("Starting divideAndMod:");
        trace("Dividend = " + dividend.toString());
        trace("Divisor = " + divisor.toString());

        // If dividend < divisor, quotient=0, remainder=dividend
        if (dividend.compareAbs(divisor) < 0) {
            trace("Dividend < Divisor, quotient = 0, remainder = " + dividend.toString());
            return { quotient: quotient, remainder: dividend };
        }

        // Initialize quotient
        var q:BigInt = new BigInt("0");

        // Loop: while dividend >= divisor
        var iteration:Number = 0;
        while (dividend.compareAbs(divisor) >= 0) {
            dividend = dividend.subtract(divisor);
            q = q.add(new BigInt("1"));
            iteration++;
            if (iteration % 1000 == 0) { // Prevent infinite loop
                trace("Iteration " + iteration + ": q = " + q.toString() + ", remainder = " + dividend.toString());
                break; // Exit to prevent infinite loop; adjust as needed
            }
        }

        quotient = q;
        quotient.sign = resultSign;
        quotient.trim();

        remainder = dividend.clone();
        remainder.sign = this.sign;
        remainder.trim();

        trace("divideAndMod Result: quotient = " + quotient.toString() + ", remainder = " + remainder.toString());
        return { quotient: quotient, remainder: remainder };
    }

    // Divide two BigInts, return quotient
    public function divide(other:BigInt):BigInt {
        var result:Object = this.divideAndMod(other);
        return result.quotient;
    }

    // Modulus, return remainder
    public function mod(other:BigInt):BigInt {
        var result:Object = this.divideAndMod(other);
        return result.remainder;
    }

    // Compute GCD
    public function gcd(other:BigInt):BigInt {
        var a:BigInt = this.clone();
        var b:BigInt = other.clone();

        // Ensure positive
        a.sign = 1;
        b.sign = 1;

        trace("Starting GCD computation:");
        trace("a = " + a.toString());
        trace("b = " + b.toString());

        while (!b.isZero()) {
            var modResult:BigInt = a.mod(b);
            trace("a = " + a.toString() + ", b = " + b.toString() + ", a mod b = " + modResult.toString());
            a = b.clone();
            b = modResult;
        }

        trace("Final GCD = " + a.toString());
        return a;
    }

    // Compute mod inverse using Extended Euclidean Algorithm
    public function modInverse(modulus:BigInt):BigInt {
        var a:BigInt = this.mod(modulus).clone();
        var m:BigInt = modulus.clone();

        // Ensure a and m are positive
        a.sign = 1;
        m.sign = 1;

        var m0:BigInt = m.clone();
        var y:BigInt = new BigInt("0");
        var x:BigInt = new BigInt("1");

        trace("Starting Modular Inverse computation:");
        trace("a = " + a.toString());
        trace("m = " + m.toString());

        // Check GCD
        var gcdVal:BigInt = a.gcd(m);
        if (gcdVal.compare(new BigInt("1")) != 0) {
            throw new Error("Inverse does not exist.");
        }

        // Extended Euclidean Algorithm
        var iteration:Number = 0;
        while (a.compare(new BigInt("1")) > 0) {
            var q:BigInt = a.divide(m);
            trace("Quotient (q) = " + q.toString());

            var modResult:BigInt = a.mod(m);
            trace("a mod m = " + modResult.toString());

            // Update a and m
            a = m.clone();
            m = modResult;

            // Update x and y
            var tempY:BigInt = y.clone();
            y = x.subtract(q.multiply(y));
            trace("y = " + y.toString());

            x = tempY.clone();
            trace("x = " + x.toString());

            iteration++;
            if (iteration > 1000000) { // Prevent infinite loop
                throw new Error("Modular inverse computation exceeded iteration limit.");
            }
        }

        // If x is negative, adjust it
        if (x.compare(new BigInt("0")) < 0) {
            x = x.add(m0);
            trace("Adjusted x = " + x.toString());
        }

        trace("Final Inverse (d) = " + x.toString());
        return x;
    }

    // Compute modPow using right-to-left binary method (iterative)
    public function modPow(exponent:BigInt, modulus:BigInt):BigInt {
        var result:BigInt = new BigInt("1");
        var base:BigInt = this.mod(modulus).clone();
        var exp:BigInt = exponent.clone();

        trace("Starting ModPow computation:");
        trace("Base = " + base.toString());
        trace("Exponent = " + exp.toString());
        trace("Modulus = " + modulus.toString());

        var iteration:Number = 0;
        while (!exp.isZero()) {
            if (exp.blocks[0] % 2 == 1) {
                result = result.multiply(base).mod(modulus);
                trace("result = result * base mod modulus = " + result.toString());
            }
            exp = exp.divide(new BigInt("2"));
            base = base.multiply(base).mod(modulus);
            trace("base = base * base mod modulus = " + base.toString());

            iteration++;
            if (iteration > 1000000) { // Prevent infinite loop
                throw new Error("modPow computation exceeded iteration limit.");
            }
        }

        trace("Final ModPow result = " + result.toString());
        return result;
    }
}
/*

import org.flashNight.naki.DataStructures.BigInt;

// Helper function to compare BigInt with expected string
function assertEqual(testName:String, result:BigInt, expected:String):Void {
    if (result.toString() == expected) {
        trace(testName + " Passed");
    } else {
        trace(testName + " Failed: Expected " + expected + ", but got " + result.toString());
    }
}

// Basic Tests

// Test Addition
function testAddition():Void {
    var a:BigInt = new BigInt("1234");
    var b:BigInt = new BigInt("5678");
    var sum:BigInt = a.add(b);
    assertEqual("Addition Test", sum, "6912");
}

// Test Subtraction
function testSubtraction():Void {
    var c:BigInt = new BigInt("10000");
    var d:BigInt = new BigInt("1");
    var diff:BigInt = c.subtract(d);
    assertEqual("Subtraction Test", diff, "9999");
}

// Test Multiplication
function testMultiplication():Void {
    var e:BigInt = new BigInt("1234");
    var f:BigInt = new BigInt("5678");
    var product:BigInt = e.multiply(f);
    assertEqual("Multiplication Test", product, "7006652");
}

// Test Division and Modulus
function testDivisionAndMod():Void {
    var g:BigInt = new BigInt("7006652");
    var h:BigInt = new BigInt("5678");
    var divMod:Object = g.divideAndMod(h);
    assertEqual("Division Quotient Test", divMod.quotient, "1234");
    assertEqual("Division Remainder Test", divMod.remainder, "0");
}

// Test GCD
function testGCD():Void {
    var i:BigInt = new BigInt("48");
    var j:BigInt = new BigInt("18");
    var gcdVal:BigInt = i.gcd(j);
    assertEqual("GCD(48, 18) Test", gcdVal, "6");
}

// Test GCD for e=17 and phi=3120
function testGCD_EPhi():Void {
    var eTest:BigInt = new BigInt("17");
    var phiTest:BigInt = new BigInt("3120");
    var gcdTest:BigInt = eTest.gcd(phiTest);
    assertEqual("GCD(17, 3120) Test", gcdTest, "1");
}

// Test Modulus
function testMod():Void {
    var a:BigInt = new BigInt("17");
    var b:BigInt = new BigInt("3120");
    var modResult:BigInt = a.mod(b);
    assertEqual("Mod Test (17 mod 3120)", modResult, "17");
}

// Test Mod Inverse
function testModInverse():Void {
    var k:BigInt = new BigInt("17");
    var l:BigInt = new BigInt("3120");
    try {
        var inverse:BigInt = k.modInverse(l);
        assertEqual("Mod Inverse Test", inverse, "2753");
    } catch (err:Error) {
        trace("Mod Inverse Test Failed: " + err.message);
    }
}

// Test ModPow
function testModPow():Void {
    var m:BigInt = new BigInt("65"); // Plaintext
    var n:BigInt = new BigInt("3233"); // n = 61 * 53
    var o:BigInt = new BigInt("17"); // Public key e
    var cEncrypted:BigInt = m.modPow(o, n); // Encryption
    assertEqual("ModPow Encryption Test", cEncrypted, "2790");

    var dPrivate:BigInt = new BigInt("2753"); // Private key d
    var mDecrypted:BigInt = cEncrypted.modPow(dPrivate, n); // Decryption
    assertEqual("ModPow Decryption Test", mDecrypted, "65");
}

// Test Negative Numbers
function testNegativeNumbers():Void {
    var a:BigInt = new BigInt("-1234");
    var b:BigInt = new BigInt("5678");
    var sum:BigInt = a.add(b);
    assertEqual("Negative Addition Test", sum, "4444"); // 5678 - 1234 = 4444
}

// Test Large Number Addition
function testLargeNumbers():Void {
    var large1:BigInt = new BigInt("123456789012345678901234567890");
    var large2:BigInt = new BigInt("987654321098765432109876543210");
    var sum:BigInt = large1.add(large2);
    assertEqual("Large Number Addition Test", sum, "1111111110111111111011111111100");
}

// Test Mod Inverse with Large Numbers
function testModInverseLargeNumbers():Void {
    var e:BigInt = new BigInt("65537");
    var phi:BigInt = new BigInt("1050809297030400043696"); // φ(n)
    try {
        var d:BigInt = e.modInverse(phi);
        trace("Private key d = " + d.toString());

        // Verify that e * d mod phi(n) = 1
        var ed:BigInt = e.multiply(d).mod(phi);
        assertEqual("e * d mod phi(n) = 1 Test", ed, "1");
    } catch (err:Error) {
        trace("Mod Inverse Large Numbers Test Failed: " + err.message);
    }
}

// RSA Large Numbers Test
function testRSA():Void {
    trace("\nRunning RSA Large Numbers Test:");

    // Example large primes (for testing purposes; in real applications, use much larger primes)
    var p:BigInt = new BigInt("32416190071"); // Prime p
    var q:BigInt = new BigInt("32416187567"); // Prime q

    // Compute n = p * q
    var n:BigInt = p.multiply(q);
    trace("n = p * q = " + n.toString());

    // Compute φ(n) = (p - 1) * (q - 1)
    var pMinus1:BigInt = p.subtract(new BigInt("1"));
    var qMinus1:BigInt = q.subtract(new BigInt("1"));
    var phi:BigInt = pMinus1.multiply(qMinus1);
    trace("φ(n) = (p - 1) * (q - 1) = " + phi.toString());

    // Choose public key e, commonly 65537
    var e:BigInt = new BigInt("65537");

    // Check if e and phi(n) are coprime
    var gcdVal:BigInt = e.gcd(phi);
    trace("gcd(e, φ(n)) = " + gcdVal.toString());

    if (gcdVal.compare(new BigInt("1")) != 0) {
        trace("Error: e 和 φ(n) 不是互质，无法生成密钥。");
    } else {
        // Compute private key d (modular inverse of e mod phi)
        var d:BigInt;
        try {
            d = e.modInverse(phi);
            trace("私钥 d = " + d.toString());

            // Verify that e * d mod phi(n) = 1
            var ed:BigInt = e.multiply(d).mod(phi);
            assertEqual("e * d mod phi(n) = 1 Test", ed, "1");

            // Encrypt message m
            var m:BigInt = new BigInt("123456789"); // Plaintext message
            var c:BigInt = m.modPow(e, n); // Encryption
            trace("加密后的密文 c = " + m.toString() + "^" + e.toString() + " mod " + n.toString() + " = " + c.toString());

            // Decrypt ciphertext
            var decrypted:BigInt = c.modPow(d, n); // Decryption
            trace("解密后的消息 m = " + c.toString() + "^" + d.toString() + " mod " + n.toString() + " = " + decrypted.toString());

            // Check if decrypted message matches original
            if (decrypted.compare(m) == 0) {
                trace("RSA Encryption/Decryption Test Passed");
            } else {
                trace("RSA Encryption/Decryption Test Failed: Expected " + m.toString() + ", but got " + decrypted.toString());
            }
        } catch (err:Error) {
            trace("Error during RSA key generation: " + err.message);
        }
    }
}

// Run all tests
function runAllTests():Void {
    trace("Running Basic Tests:");
    testAddition();
    testSubtraction();
    testMultiplication();
    testDivisionAndMod();
    testGCD();
    testGCD_EPhi();
    testMod();
    testModInverse();
    testModPow();
    testNegativeNumbers();
    testLargeNumbers();

    // Run Large Number GCD Test
    trace("\nRunning Large Number GCD Test:");
    var eTest:BigInt = new BigInt("65537");
    var phiTest:BigInt = new BigInt("1050809297030400043696");
    var gcdLarge:BigInt = eTest.gcd(phiTest);
    assertEqual("GCD(65537, phi) Test", gcdLarge, "1");

    // Run ModInverse Large Numbers Test
    trace("\nRunning ModInverse Large Numbers Test:");
    testModInverseLargeNumbers();

    // Run RSA Test
    testRSA();
}

// Execute tests
runAllTests();
