import logging.IFormatter;
import logging.LogRecord;

/**
*	A formatter which only returns the log message in uppercase
*
*	@author Ralf Siegel
*/
class de.audiofarm.code.logger.CustomFormatter implements IFormatter
{
	/**
	*	@see logging.IFormatter
	*/
	public function format(logRecord:LogRecord):String
	{
		return logRecord.getMessage().toUpperCase();
	}
}