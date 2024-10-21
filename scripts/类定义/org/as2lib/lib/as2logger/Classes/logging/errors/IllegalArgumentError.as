/**
*	@author Ralf Siegel
*	@deprecated will use standard classes if available
*/
class logging.errors.IllegalArgumentError extends Error
{
	public var name:String = "IllegalArgumentError";		
	public var message:String;

	public function IllegalArgumentError(message:String)
	{
		super();
		this.message = message;
	}
	
	public function toString():String
	{
		return "[" + this.name + "] " + this.message;
	}
}