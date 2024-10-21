import logging.LogRecord;

/**
*	A Filter can be used to provide fine grain control over what is logged, beyond the control provided by log levels.
*
*	@author Ralf Siegel
*/
interface logging.IFilter
{
	/**
	*	Check if a given log record should be published. 
	*
	*	@param logRecord A LogRecord
	*	@return true if the log record should be published.
	*/
	public function isLoggable(logRecord:LogRecord):Boolean;
}
