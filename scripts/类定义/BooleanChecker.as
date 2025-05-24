class BooleanChecker
{
	private static var falsyStrings:Array = ["", "undefined", "null", "无"];

	public static function toBoolean(value):Boolean
	{
		// 首先判断是否为 null
		if (value == null)
		{
			return false;
		}
		// 检查字符串是否在特定的 falsy 字符串数组中  
		if (typeof (value) == "string")
		{
			var valueLength:Number = value.length;
			for (var i:Number = falsyStrings.length - 1; i >= 0; i--)
			{
				var falsyValue:String = falsyStrings[i];
				if (falsyValue.length == valueLength && value == falsyValue)
				{
					return false;
				}
			}
		}
		// 检查空数组  
		if (value instanceof Array && value.length == 0)
		{
			return false;
		}
		// 检查空对象  
		if (typeof (value) == "object" && isEmptyObject(value))
		{
			return false;
		}
		// 其他所有情况均返回真实的布尔值  
		return !(!value);
	}

	// 检查对象是否为空
	private static function isEmptyObject(obj:Object):Boolean
	{
		for (var prop in obj)
		{
			return false;// 如果对象有任何自有属性，则不为空
		}
		return true;// 如果没有自有属性，为空
	}
}