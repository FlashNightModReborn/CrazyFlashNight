import logging.*;
import logging.events.*;

/**
*	Sample Application for Logger tutorial
*
*	@author Ralf Siegel
*/
class de.audiofarm.code.logger.Application implements IPropertyChangeListener
{
	private static var logger:Logger = Logger.getLogger("de.audiofarm.code.logger.Application");

	/**
	*	Usually that's your main application class
	*/
	public function Application()
	{
		logger.fine("Application created");
	}
	
	/**
	*	The handler which will be called when the logging properties in 'logging.xml' are read
	*/
	public function onPropertyChanged(event:PropertyChangeEvent):Void
	{
		logger.fine("Logging properties read");
		
		// 	Usually you would proceed to kick off your application at this point - here we simply load some data.
		this.loadTestData();
	}
	
	/**
	*	Load some data in order to demonstrate loggings at various levels
	*/
	public function loadTestData():Void
	{
		var xml:XML = new XML();
		xml.ignoreWhite = true;
		xml.onLoad = function(ok)
		{
			if (ok) {
				logger.info("XML loaded");
				if (this.status != 0) {
					logger.warning("Parser Error: " + this.status);
				}
			} else {
				logger.severe("XML failed to load");
			}
		};
		xml.load("de/audiofarm/code/logger/data.xml");
	}
	
	/**
	*	The applications entry point.
	*
	*	The main method is usually invoked by your project's main fla. 
	*/
	public static function main():Void
	{
		var app:Application = new Application();
		
		// Simply add these two lines to read external logging properties.
		LogManager.getInstance().addPropertyChangeListener(app);
		LogManager.getInstance().readProperties("logging.xml");
	}
}
