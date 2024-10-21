import logging.IFilter;
import logging.LogRecord;

/**
*	A custom filter implementation which logs within business hours only ;o)
*
*	@author Ralf Siegel
*/
class de.audiofarm.code.logger.CustomFilter implements IFilter
{
	/**
	*	@see logging.IFilter
	*/
	public function isLoggable(logRecord:LogRecord):Boolean
	{
		if (logRecord.getDate().getHours() >= 7 && logRecord.getDate().getHours() <= 19) {
			return true;
		}
		return false;
	}
}