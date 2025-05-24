class RC4
{
	private var s:Array;
	private var i:Number;
	private var j:Number;
	private var key:String;

	public function RC4(key:String)
	{
		this.s = new Array(256);
		this.i = 0;
		this.j = 0;
		this.key = key;
		this.initialize(key);
	}

	private function initialize(key:String):Void
	{
		var k:Array = new Array(256);
		var temp:Number, i:Number, j:Number = 0;

		for (i = 0; i < 256; i++)
		{
			this.s[i] = i;
			k[i] = key.charCodeAt(i % key.length);
		}

		for (i = 0; i < 256; i++)
		{
			j = (j + this.s[i] + k[i]) % 256;
			temp = this.s[i];
			this.s[i] = this.s[j];
			this.s[j] = temp;
		}
	}

	private function reset():Void
	{
		this.i = 0;
		this.j = 0;
		this.initialize(this.key);
	}

	public function encrypt(data:String):String
	{
		this.reset();
		return this.process(data);
	}

	public function decrypt(data:String):String
	{
		this.reset();
		return this.process(data);
	}

	private function process(data:String):String
	{
		var result:String = "";
		var temp:Number;

		for (var x:Number = 0; x < data.length; x++)
		{
			this.i = (this.i + 1) % 256;
			this.j = (this.j + this.s[this.i]) % 256;

			temp = this.s[this.i];
			this.s[this.i] = this.s[this.j];
			this.s[this.j] = temp;

			var k:Number = this.s[(this.s[this.i] + this.s[this.j]) % 256];
			result += String.fromCharCode(data.charCodeAt(x) ^ k);
		}

		return result;
	}
}