import logging.IFilter;
import logging.IPublisher;
import logging.Level;
import logging.Logger;
import logging.LogManager;

import logging.util.Class;

/**
*	The property handler takes various logging properties and assigns them to the suitable loggers.
*
*	@author Ralf Siegel
*/
class logging.PropertyHandler
{
	private static var logger:Logger = Logger.getLogger("logging.PropertyHandler");
	
	/**
	*	Handles appliable properties for loggers. 
	*
	*	Important: If a filter is specified, make sure to import and reference the given class so it can be accessed by the Logger framework
	*
	*	@param name the Logger's name string, e.g. "a.b.c"
	*	@param level the logging level, e.g. "WARNING"
	*	@param filter the filter class name, e.g. "com.domain.CustomFilter"
	*/
	public function handleLoggerProperties(name:String, level:String, filter:String):Void
	{
		try {		
			Logger.getLogger(name).setLevel(Level.forName(level));
		} catch (e:logging.errors.InvalidLevelError) {
			logger.warning(e.toString());
		} catch (e:logging.errors.IllegalArgumentError) {
			// silently ignore
		}
		
		try {
			Logger.getLogger(name).setFilter(LogManager.createFilterByName(filter));
		} catch (e:logging.errors.ClassNotFoundError) {
			logger.warning(e.toString());
		} catch (e:logging.errors.InvalidFilterError) {
			logger.warning(e.toString());
		} catch (e:logging.errors.IllegalArgumentError) {
			// silently ignore
		}
	}
	
	/**
	*	Handles appliable properties for publishers. 
	*
	*	Important: If a publisher or formatter is specified, make sure to import and reference the given class so it can be accessed by the Logging Framework
	*
	*	@param name the Logger's name string, e.g. "a.b.c"
	*	@param publisher the publisher class name, e.g. "com.domain.CustomPublisher"
	*	@param filter the formatter class name, e.g. "com.domain.CustomFormatter"
	*/
	public function handlePublisherProperties(name:String, publisher:String, formatter:String, level:String):Void
	{
		try {
			var p:IPublisher = LogManager.createPublisherByName(publisher);
			Logger.getLogger(name).addPublisher(p);
		} catch (e:logging.errors.ClassNotFoundError) {
			logger.warning(e.toString());
			return;
		} catch (e:logging.errors.InvalidPublisherError) {
			logger.warning(e.toString());
			return;
		} catch (e:logging.errors.IllegalArgumentError) {
			return;
		}
		
		try {		
			p.setLevel(Level.forName(level));
		} catch (e:logging.errors.InvalidLevelError) {
			logger.warning(e.toString());
		} catch (e:logging.errors.IllegalArgumentError) {
			// silently ignore
		}
		
		try {
			p.setFormatter(LogManager.createFormatterByName(formatter));
		} catch (e:logging.errors.ClassNotFoundError) {
			logger.warning(e.toString());
		} catch (e:logging.errors.InvalidFormatterError) {
			logger.warning(e.toString());
		} catch (e:logging.errors.IllegalArgumentError) {
			// silently ignore
		}
	}
}
