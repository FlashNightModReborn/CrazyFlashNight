class BigNumber
{
	private var digits:Array;// 存储大数的每一位，使用数组来存储
	private var isNegative:Boolean;// 标识是否为负数

	public function BigNumber(value:String)
	{
		this.digits = [];
		this.isNegative = (value.charAt(0) == '-');
		for (var i:Number = (this.isNegative ? 1 : 0); i < value.length; i++)
		{
			this.digits.push(Number(value.charAt(i)));
		}
	}

	public function toString():String
	{
		var result:String = this.isNegative ? "-" : "";
		for (var i:Number = 0; i < this.digits.length; i++)
		{
			result += this.digits[i].toString();
		}
		return result;
	}

	public function compareTo(b:BigNumber):Number
	{
		if (this.isNegative && !b.isNegative)
		{
			return -1;
		}
		if (!this.isNegative && b.isNegative)
		{
			return 1;
		}

		var sign:Number = this.isNegative ? -1 : 1;

		if (this.digits.length > b.digits.length)
		{
			return 1 * sign;
		}
		if (this.digits.length < b.digits.length)
		{
			return -1 * sign;
		}

		for (var i:Number = 0; i < this.digits.length; i++)
		{
			if (this.digits[i] > b.digits[i])
			{
				return 1 * sign;
			}
			if (this.digits[i] < b.digits[i])
			{
				return -1 * sign;
			}
		}
		return 0;
	}


	public function add(b:BigNumber):BigNumber
	{
		var result:Array = [];
		var carry:Number = 0;
		var maxLength:Number = Math.max(this.digits.length, b.digits.length);
		var signA:Number = this.isNegative ? -1 : 1;
		var signB:Number = b.isNegative ? -1 : 1;

		if (signA == signB)
		{
			// Same sign, simple addition
			for (var i:Number = 0; i < maxLength || carry != 0; i++)
			{
				var digitA:Number = (i < this.digits.length) ? this.digits[this.digits.length - 1 - i] : 0;
				var digitB:Number = (i < b.digits.length) ? b.digits[b.digits.length - 1 - i] : 0;
				var sum:Number = digitA + digitB + carry;
				result.unshift(sum % 10);
				carry = Math.floor(sum / 10);
			}
			var resultStr:String = result.join("");
			return new BigNumber((this.isNegative ? "-" : "") + resultStr);
		}
		else
		{
			// Different signs, perform subtraction
			var a:BigNumber = this.isNegative ? b : this;
			var b:BigNumber = this.isNegative ? this : b;
			return a.subtract(b);
		}
	}

	public function subtract(b:BigNumber):BigNumber
	{
		var result:Array = [];
		var borrow:Number = 0;
		var maxLength:Number = Math.max(this.digits.length, b.digits.length);

		if (this.isNegative && !b.isNegative)
		{
			return new BigNumber("-" + this.add(new BigNumber("-" + b.toString())).toString());
		}
		else if (!this.isNegative && b.isNegative)
		{
			return this.add(new BigNumber(b.toString().substring(1)));
		}
		else if (this.isNegative && b.isNegative)
		{
			return new BigNumber(b.toString().substring(1)).subtract(new BigNumber(this.toString().substring(1)));
		}

		for (var i:Number = 0; i < maxLength || borrow != 0; i++)
		{
			var digitA:Number = (i < this.digits.length) ? this.digits[this.digits.length - 1 - i] : 0;
			var digitB:Number = (i < b.digits.length) ? b.digits[b.digits.length - 1 - i] : 0;
			var diff:Number = digitA - digitB - borrow;

			if (diff < 0)
			{
				diff += 10;
				borrow = 1;
			}
			else
			{
				borrow = 0;
			}

			result.unshift(diff);
		}

		// 去除前导零
		while (result.length > 1 && result[0] == 0)
		{
			result.shift();
		}

		var resultStr:String = result.join("");
		return new BigNumber(resultStr);
	}

	public function multiply(b:BigNumber):BigNumber
	{
		var result:Array = [];
		for (var i:Number = 0; i < this.digits.length + b.digits.length; i++)
		{
			result[i] = 0;
		}

		for (var i:Number = 0; i < this.digits.length; i++)
		{
			var carry:Number = 0;
			for (var j:Number = 0; j < b.digits.length; j++)
			{
				var product:Number = this.digits[this.digits.length - 1 - i] * b.digits[b.digits.length - 1 - j] + carry + result[result.length - 1 - i - j];
				result[result.length - 1 - i - j] = product % 10;
				carry = Math.floor(product / 10);
			}
			result[result.length - 1 - i - b.digits.length] += carry;
		}

		// 去除前导零
		while (result.length > 1 && result[0] == 0)
		{
			result.shift();
		}

		var resultStr:String = result.join("");
		return new BigNumber(resultStr);
	}
	public function divide(b:BigNumber):BigNumber
	{
		if (b.compareTo(new BigNumber("0")) == 0)
		{
			throw new Error("Division by zero");
		}

		var result:Array = [];
		var remainder:BigNumber = new BigNumber("0");
		for (var i:Number = 0; i < this.digits.length; i++)
		{
			remainder = new BigNumber(remainder.toString() + this.digits[i].toString());
			var quotient:Number = 0;
			while (remainder.compareTo(b) >= 0)
			{
				remainder = remainder.subtract(b);
				quotient++;
			}
			result.push(quotient);
		}

		// 去除前导零
		while (result.length > 1 && result[0] == 0)
		{
			result.shift();
		}

		var resultStr:String = result.join("");
		return new BigNumber(resultStr);
	}

	public function mod(b:BigNumber):BigNumber
	{
		var quotient:BigNumber = this.divide(b);
		var product:BigNumber = quotient.multiply(b);
		var remainder:BigNumber = this.subtract(product);
		return remainder;
	}
	public function modPow(exp:BigNumber, mod:BigNumber):BigNumber
	{
		var result:BigNumber = new BigNumber("1");
		var base:BigNumber = this.mod(mod);
		var exponent:BigNumber = exp;

		while (exponent.compareTo(new BigNumber("0")) > 0)
		{
			if (exponent.mod(new BigNumber("2")).compareTo(new BigNumber("0")) != 0)
			{
				result = result.multiply(base).mod(mod);
			}
			exponent = exponent.divide(new BigNumber("2"));
			base = base.multiply(base).mod(mod);
		}

		return result;
	}




}