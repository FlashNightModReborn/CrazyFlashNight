import logging.Level;

/**
*	LogRecord value objects are used to pass logging requests between the logging framework and individual publishers. 
*
*	@author Ralf Siegel
*/
class logging.LogRecord
{
	private var date:Date;
	private var loggerName:String;
	private var level:Level;
	private var message:String;
	
	/**
	*	Construct a LogRecord with the given date, source's logger name, level and message values. 
	*
	*	@param date The date object stored in this log record object
	*	@param loggerName The logger name string stored in this log record object
	*	@param level The level object stored in this log record object
	*	@param message The message string stored in this log record object
	*/
	public function LogRecord(date:Date, loggerName:String, level:Level, message:String)
	{
		this.date = date;
		this.loggerName = loggerName;
		this.level = level;
		this.message = message;
	}
	
	/**
	*	Get the event date.
	*
	*	@return a Date object
	*/
	public function getDate():Date
	{
		return this.date;
	}
	
	/**
	*	Get the source's logger name
	*
	*	@return the logger name string
	*/
	public function getLoggerName():String
	{
		return this.loggerName;
	}
	
	/**
	*	Get the logging message level, for example Level.SEVERE.
	*
	*	@return the logging message level object
	*/
	public function getLevel():Level
	{
		return this.level;
	}
	
	/**
	*	Get the "raw" log message before formatting. 
	*
	*	@return the raw message string
	*/
	public function getMessage():String
	{
		return this.message;
	}
}
