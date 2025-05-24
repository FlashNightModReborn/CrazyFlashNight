class 向量
{
	var x:Number;
	var y:Number;

	function 向量(x:Number, y:Number)
	{
		this.x = x;
		this.y = y;
	}

	function 减(v:向量):向量
	{
		return new 向量(this.x - v.x, this.y - v.y);
	}

	function 点积(v:向量):Number
	{
		return this.x * v.x + this.y * v.y;
	}

	function 叉积(v:向量):Number
	{
		return this.x * v.y - this.y * v.x;
	}

	function 法线化():向量
	{
		return new 向量(-this.y, this.x);
	}

	function 模长():Number
	{
		return Math.sqrt(this.x * this.x + this.y * this.y);
	}

	function 归一化():向量
	{
		var 模:Number = this.模长();
		return (模 > 0) ? new 向量(this.x / 模, this.y / 模) : new 向量(0, 0);
	}

	function 角度差(v:向量):Number
	{
		var 模1:Number = this.模长();
		var 模2:Number = v.模长();
		if (模1 > 0 and 模2 > 0)
		{
			return Math.acos(this.点积(v) / (模1 * 模2));
		}
		else
		{
			return 0;
		}
	}

	function 旋转(theta:Number):向量
	{
		var 余弦值:Number = Math.cos(theta);
		var 正弦值:Number = Math.sin(theta);
		return new 向量(this.x * 余弦值 - this.y * 正弦值, this.x * 正弦值 + this.y * 余弦值);
	}

	function 线性插值(v:向量, t:Number):向量
	{
		return new 向量(this.x + (v.x - this.x) * t, this.y + (v.y - this.y) * t);
	}

	function 投影(v:向量):向量
	{
		var 伸展度:Number = this.点积(v) / (v.x * v.x + v.y * v.y);
		return new 向量(伸展度 * v.x, 伸展度 * v.y);
	}

	function 距离(v:向量):Number
	{
		var dx:Number = v.x - this.x;
		var dy:Number = v.y - this.y;
		return Math.sqrt(dx * dx + dy * dy);
	}

}