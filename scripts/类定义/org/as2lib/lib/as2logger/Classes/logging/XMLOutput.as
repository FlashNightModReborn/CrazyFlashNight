import logging.IFilter;
import logging.IPublisher;
import logging.Level;
import logging.LogRecord;
import logging.IFormatter;
import logging.XMLFormatter;

/**
*	Standard implementation of the Logger's framework IPublisher interface.
*	XML formats incoming logging messages and sends them (traces) to the output window.
*
*	@author Ralf Siegel
*/
class logging.XMLOutput implements IPublisher
{
	private var filter:IFilter;
	private var formatter:IFormatter;
	private var level:Level;

	/**
	*	Constructs a new trace publisher with the standard XML formatter
	*/
	public function XMLOutput() 
	{
		this.setFormatter(new XMLFormatter());
	}

	/**
	*	@see logging.IPublisher
	*/	
	public function publish(logRecord:LogRecord):Void
	{
		if (this.isLoggable(logRecord)) {
			trace(this.getFormatter().format(logRecord));
		}
	}
	
	/**
	*	@see logging.IPublisher
	*/
	public function setFilter(filter:IFilter):Void
	{
		this.filter = filter;
	}
	
	/**
	*	@see logging.IPublisher
	*/
	public function getFilter():IFilter
	{
		return this.filter;
	}

	/**
	*	@see logging.IPublisher
	*/		
	public function setFormatter(formatter:IFormatter):Void
	{
		this.formatter = formatter;
	}

	/**
	*	@see logging.IPublisher
	*/	
	public function getFormatter():IFormatter
	{
		return this.formatter;
	}
	
	/**
	*	@see logging.IPublisher
	*/
	public function setLevel(level:Level):Void
	{
		this.level = level;
	}
	
	/**
	*	@see logging.IPublisher
	*/
	public function getLevel():Level
	{
		return this.level;
	}
	
	/**
	*	@see logging.IPublisher
	*/
	public function isLoggable(logRecord:LogRecord):Boolean
	{
		if (this.getLevel() > logRecord.getLevel()) {
			return false;
		}
		
		if (this.getFilter() == undefined || this.getFilter() == null) {
			return true;
		}
		
		if (this.getFilter().isLoggable(logRecord)) {
			return true;
		}
		
		return false;
	}	
}
