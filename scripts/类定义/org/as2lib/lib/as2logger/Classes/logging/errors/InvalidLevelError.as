/**
*	@author Ralf Siegel
*/
class logging.errors.InvalidLevelError extends Error
{
	public var name:String = "InvalidLevelError";		
	public var message:String;

	public function InvalidLevelError(levelName:String)
	{
		super();
		this.message = "'" + levelName + "' is not a valid Level";
	}
	
	public function toString():String
	{
		return "[" + this.name + "] " + this.message;
	}
}