import logging.IFormatter;
import logging.LogRecord;

/**
*	A default formatter implementation.
*
*	@author Ralf Siegel
*/
class logging.DefaultFormatter implements IFormatter
{
	/**
	*	@see logging.IFormatter
	*/
	public function format(logRecord:LogRecord):String
	{
		var formatted:String = "";		
		formatted += logRecord.getDate() + " | " + logRecord.getLoggerName() + newline;
		formatted += "[" + logRecord.getLevel().getName() + "] " + logRecord.getMessage();
		return formatted;
	}
}