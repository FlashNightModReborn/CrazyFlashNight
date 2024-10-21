/**
* 
* Debug CLASS
* 
* OPEN SOURCE
*
* @ Created by: Robert Hoekman, Jr. (www.rhjr.net) & Interactive Alchemy (www.InteractiveAlchemy.com)
*
* @ PURPOSE: Used in conjunction with DebugIt Receiver (SWF). Creates a LocalConnection so you can
* trace data outside of the Flash authoring tool, while your application is running in its
* testing/production environment. Data is also traced to the Output panel, so you can use Debug.write()
* instead of trace() calls in all cases.
*
* @ USAGE: Instead of calling trace(), call Debug.write() and pass it as many parameters as you
* need (comma-delimited, of course). Each parameter displays on a new line in DebugIt Receiver.
*
*/
class com.interactiveAlchemy.utils.Debug extends MovieClip
{
	/**
	* Private members
	*/
	private static var _lc : LocalConnection;
	private static var _isInitialized : Boolean = false;
	
	/**
	* write()
	* Traces data to the Output panel within Flash, and displays the same data
	* in DebugIt Receiver, enabling debugging outside of Flash.
	*/
	public static function write (arguments) : Void 
	{
		// Check for existing LocalConnection. If none, create one.
		if ( ! _isInitialized)
		{
			_lc = new LocalConnection ();
		}
		// Send params to DebugIt Receiver
		_lc.send ("_debugIt", "write", arguments);
		// Trace each argument on its own line in the Output panel as well
		for (var i = 0; i < arguments.length; i ++)
		{
			trace (arguments [i]);
		}
	}
}