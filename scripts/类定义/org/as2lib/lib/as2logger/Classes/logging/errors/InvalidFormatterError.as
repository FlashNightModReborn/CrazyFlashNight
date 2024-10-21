/**
*	@author Ralf Siegel
*/
class logging.errors.InvalidFormatterError extends Error
{
	public var name:String = "InvalidFormatterError";		
	public var message:String;

	public function InvalidFormatterError(className:String)
	{
		super();
		this.message = "'" + className + "' is not a valid Formatter";
	}
	
	public function toString():String
	{
		return "[" + this.name + "] " + this.message;
	}
}