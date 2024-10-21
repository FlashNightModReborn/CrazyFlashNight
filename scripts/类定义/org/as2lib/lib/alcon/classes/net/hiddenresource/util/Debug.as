/**
 * @class			Debug
 * @version		1.0.5
 * @author			Sascha Balkau <sascha@hiddenresource.corewatch.net>
 *
 * @description		A logger class that sends trace actions to
 *					an output panel through a local connection.
 *
 * @usage			import net.hiddenresource.util.Debug;
 *					Debug.trace("Trace this message!", 0);
 *					Debug.trace(myObj, 0, true);
 *					Debug.trace(_root, true);
 *					Debug.setFilterLevel(0-4);
 *					Debug.getFilterLevel();
 *					Debug.setRecursionDepth(60);
 *					Debug.showKeywords();
 */
 class net.hiddenresource.util.Debug
{
	// The local connection object:
	private static var debug_lc:LocalConnection;
	// Determines if a connection is already established:
	private static var con:Boolean = false;
	// Filter level. By default filter none (0):
	private static var fl:Number = 0;
	// Don't show level descriptions by default:
	private static var sld:Boolean = false;
	// Default depth of recursion for object tracing:
	private static var rec:Number = 20;
	
	
	/**
	 * Private constructor
	 */
	private function Debug()
	{
	}
	
	
	
	/**
	* trace()
	* @param	argument0:Object	The object to be traced.
	* @param	argument1:Boolean	True if recursive object tracing (optional).
	* @param	argument2:Number	Severity level (optional).
	* @return	nothing.
	*/
	public static function trace():Void
	{
		connect();
		
		// Define default vars:
		var out:String = "";
		var lvl:Number = 1;
		var otr:Boolean = false;
		
		// First argument is always the traceable information:
		var msg:String = arguments[0];
		
		// Find out which parameters were supplied:
		if (arguments.length > 1)
		{
			if (arguments.length == 2)
			{
				if (typeof(arguments[1]) == "number") lvl = arguments[1];
				else if (typeof(arguments[1]) == "boolean") otr = arguments[1];
			}
			else if (arguments.length == 3)
			{
				if (typeof(arguments[1]) == "number") lvl = arguments[1];
				if (typeof(arguments[2]) == "boolean") otr = arguments[2];
			}
		}
		
		// Only show messages equal or higher than current filter level:
		if (lvl >= fl && lvl < 5)
		{
			// Define level descriptions if necessary:
			if (sld)
			{
				if (lvl == 0) out = "-DEBUG: ";
				else if (lvl == 1) out = "--INFO: ";
				else if (lvl == 2) out = "--WARN: ";
				else if (lvl == 3) out = "-ERROR: ";
				else if (lvl == 4) out = "-FATAL: ";
			}
			
			// Check if recursive object tracing:
			if (otr) out += traceObject(msg);
			else out += String(msg);
			
			// Send output to Alcon console:
			debug_lc.send("alcon_lc", "onMessage", out, lvl);
			
			// If you want to trace to the Flash IDE as well, uncomment this line:
			// trace(out);
		}
	}
	
	
	
	/**
	 * clr()
	 * @desciption		Sends a clear buffer signal to the output console.
	 * @return			Nothing.
	 */
	public static function clr():Void
	{
		connect();
		debug_lc.send("alcon_lc", "onMessage", "[%CLR%]", 1);
	}
	
	
	
	/**
	 * dlt()
	 * @desciption		Sends a delimiter signal to the output console.
	 * @return			Nothing.
	 */
	public static function dlt():Void
	{
		connect();
		debug_lc.send("alcon_lc", "onMessage", "[%DLT%]", 1);
	}
	
	
	
	/**
	 * connect()
	 * @description		Establishes the Alcon local connection once.
	 * @return			Nothing.
	 */
	private static function connect():Void
	{
		if (!con)
		{
			debug_lc = new LocalConnection();
			con = true;
		}
	}
	
	
	
	/**
	* traceObject()
	* @description		Prepares objects for recursive tracing.
	* @return			A string that contains the object structure.
	*/
	private static function traceObject(obj:Object):String
	{
		// Set the max. recursive depth:
		var rcdInit:Number = rec;
		// tmp holds the string with the whole object structure:
		var tmp:String = "" + obj + "\n";
		
		// Nested recursive function:
		var processObj:Function;
		processObj = function(o:Object, rcd:Number, idt:Number):Void
		{
			for (var p:String in o)
			{
				// Preparing indention:
				var tb:String = "";
				for (var i:Number = 0; i < idt; i++) tb += "   ";
				
				tmp += tb + p + ": " + o[p] + "\n";
				if (rcd > 0) processObj(o[p], rcd - 1, idt + 1);
			}
		};
		
		processObj(obj, rcdInit, 1);
		return tmp;
	}
	
	
	
	/**
	* setFilterLevel()
	* @param _fl:Number		The filter level to be set.
	*/
	public static function setFilterLevel(_fl:Number):Void
	{
		if (_fl != undefined && _fl >= 0 && _fl < 5) fl = _fl;
	}
	
	/**
	 * getFilterLevel()
	 * @return fl:Number	The filter level.
	 */
	public static function getFilterLevel():Number
	{
		return fl;
	}
	
	/**
	* setRecursionDepth()
	* @param _rec:Number	The depth of object recursion.
	*/
	public static function setRecursionDepth(_rec:Number):Void
	{
		rec = _rec;
	}
	
	/**
	* showKeywords()
	*/
	public static function showKeywords():Void
	{
		sld = true;
	}
	
	/**
	* hideKeywords()
	*/
	public static function hideKeywords():Void
	{
		sld = false;
	}
}
