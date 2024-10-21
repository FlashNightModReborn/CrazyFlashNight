import logging.errors.IllegalArgumentError;
import logging.errors.InvalidLevelError;

/**
*	The Level class defines a set of standard logging levels that can be used to control logging output. 
*	The logging Level objects are ordered and are specified by ordered integers. 
*	Enabling logging at a given level also enables logging at all higher levels. 
*
*	Clients should normally use the predefined Level constants such as Level.SEVERE. 
*
*	@author Ralf Siegel
*/
class logging.Level
{
	/**
	*	 ALL indicates that all messages should be logged
	*/
	public static var ALL:Level = new Level("ALL", Number.MIN_VALUE);
	
	/**
	*	CONFIG is a message level for static configuration messages.
	*/
	public static var FINEST:Level = new Level("FINEST", 1);
	
	/**
	*	FINE is a message level providing tracing information.
	*/
	public static var FINER:Level = new Level("FINER", 2);

	/**
	*	FINER indicates a fairly detailed tracing message.
	*/
	public static var FINE:Level = new Level("FINE", 4);
	
	/**
	*	FINEST indicates a highly detailed tracing message.
	*/
	public static var CONFIG:Level = new Level("CONFIG", 5);
	
	/**
	*	INFO is a message level for informational messages.
	*/
	public static var INFO:Level = new Level("INFO", 6);
	
	/**
	*	WARNING is a message level indicating a potential problem.
	*/
	public static var WARNING:Level = new Level("WARNING", 7);
	
	/**
	*	SEVERE is a message level indicating a serious failure.
	*/
	public static var SEVERE:Level = new Level("SEVERE", 8);
	
	/**
	*	OFF is a special level that can be used to turn off logging.
	*/
	public static var OFF:Level = new Level("OFF", Number.MAX_VALUE);
	
	private var name:String;
	private var value:Number;
	
	/**
	*	Create a named Level with a given integer value.
	*
	*	@param name the level's name
	*	@param value the value associated with that level
	*/
	private function Level(name:String, value:Number)
	{
		this.name = name;
		this.value = value;
	}
	
	/**
	*	Returns the level object for the given level string
	*
	*	@param level the level's name
	*	@return the level object
	*/
	public static function forName(level:String):Level
	{
		if(level == undefined || level == null) {
			throw new IllegalArgumentError("'" + level + "' is not allowed.");
		}	
		if (!(Level[level] instanceof Level)) {
			throw new InvalidLevelError(level);
		}
		return Level[level];
	}
	
	/**
	*	Get the name of this level
	*
	*	@return The name as string.
	*/
	public function getName():String
	{
		return this.name;
	}
	
	/**
	*	Get the integer value for this level
	*
	*	@return The name as string.
	*/
	public function valueOf():Number
	{
		return this.value;
	}
	
	/**
	*	@see Object.toString()
	*/
	public function toString():String
	{
		return "Level '" + this.getName() + "'";
	}
}
