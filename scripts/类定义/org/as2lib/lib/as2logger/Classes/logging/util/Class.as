import logging.errors.ClassNotFoundError;
import logging.errors.IllegalArgumentError;

/**
*	@author Ralf Siegel
*	@deprecated will use standard classes if available
*/
class logging.util.Class 
{
	/**
	*	Returns the Function object associated with the class with the given string name.
	*
	*	@return the Function object
	*/
	public static function forName(className:String):Function
	{
		if(className == undefined || className == null) {
			throw new IllegalArgumentError("'" + className + "' is not allowed.");
		}		
		var c:Function = eval("_global." + className);
		if ( c == undefined ) {
			throw new ClassNotFoundError(className);
		}
		return c;
	}
}