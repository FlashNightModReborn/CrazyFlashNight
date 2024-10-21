class de.richinternet.utils.Dumper {

	// --------------------------------------------
	// Class:	de.richinternet.utils.Dumper
	//
	// Description:	adds realtime trace/debug messaging to Flex
	//
	// Usage:		this class can be used in two ways, either static
	//				or by using a 'hook'. 
	//
	// This code is fully in the public domain. An individual or company 
	// may do whatever they wish with it. It is provided by the author 
	// "as is" and without warranty, expressed or implied - enjoy!
	// Dirk Eismann, deismann@herrlich-ramuschkat.de

	private static var sender:LocalConnection = null;
	

	// loglevel bitmasks
	public static var INFO:Number = 2;
	public static var WARN:Number = 4;
	public static var ERROR:Number = 8;
	
	// --- private constructor ---
	private function Dumper() {	
		// don't call this directly but use the
		// static functions instead
		return;
	}
	
	// --- private setup function --- 
	private static function initSender(Void):Void {
		sender = new LocalConnection();
	}

	// main function, use this from your application
	// or one of the convenience methods below
	public static function dump(val:Object, level:Number):Void {
		if (sender == null) initSender();
		if (isNaN(level)) level = 2;
		sender.send("_tracer", "onMessage", val, level);
	}

	// --- public convenience methods ---
	public static function trace(val:Object):Void {
		dump(val, INFO);
	}
	
	public static function info(val:Object):Void {
		dump(val, INFO);
	}
	
	public static function warn(val:Object):Void {
		dump(val, WARN);
	}
	
	public static function error(val:Object):Void {
		dump(val, ERROR);
	}
	
	// experimental: allows to add a 'hook' to the 
	// main application scope so you can call the
	// dump(), info(), warn() and error() functions
	// directly in your application without calling
	// function on the Dumper class itself
	public static function setHook(Void):Void {
		if (mx.core.Application.application != undefined) {
			if (mx.core.Application.application.dump == undefined) {
				// now wire the top level function calls with
				// this class. You'll have to declare the functions
				// in your mxml files (e.g. var dump:Function;)
				mx.core.Application.application.dump = dump;
				mx.core.Application.application.info = info;
				mx.core.Application.application.warn = warn;
				mx.core.Application.application.error = error;
			}
		}
	}
}