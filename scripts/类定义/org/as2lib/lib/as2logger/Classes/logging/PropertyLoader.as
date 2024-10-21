import logging.Level;
import logging.Logger;
import logging.LogManager;
import logging.PropertyHandler;

/**
*	Responsible for loading and traversing the logging properties file data.
*
*	@author Ralf Siegel
*/
class logging.PropertyLoader
{
	private static var logger:Logger = Logger.getLogger("logging.PropertyLoader");
	private static var ROOT_NODE:String = "logging";
	private static var LOGGER_NODE:String = "logger";
	private static var PUBLISHER_NODE:String = "publisher";
			
	/**
	*	Read the given logging property xml file and travers the data. Inform the LogManager when done.
	*
	*	@param file the logging.xml
	*	@param propHandler a reference to the property handler object
	*	@param logManager a reference to the global LogManager
	*/
	public function read(file:String, propHandler:PropertyHandler, logManager:LogManager):Void
	{
		var loader:XML = new XML();
		loader.ignoreWhite = true;
		loader.onLoad = function(ok)
		{
			if (ok) {
				
				var root:XMLNode = this.firstChild;
				
				if (root.nodeName != ROOT_NODE) {
					logger.warning("Invalid root node '" + root.nodeName + "' found -> '" + ROOT_NODE + "' expected instead.");
					return;
				}
				
				if (root.attributes.enabled == "false") {
					logger.info("Logging will be disabled.");
					LogManager.getInstance().disableLogging();
				}
				
				for (var i = 0; i < root.childNodes.length; i++) {
					var loggerNode:XMLNode = root.childNodes[i];
					if (loggerNode.nodeName == LOGGER_NODE) {
						propHandler.handleLoggerProperties(loggerNode.attributes.name, loggerNode.attributes.level, loggerNode.attributes.filter);
						for (var j = 0; j < loggerNode.childNodes.length; j++) {
							var publisherNode:XMLNode = loggerNode.childNodes[j];
							if (publisherNode.nodeName == PUBLISHER_NODE) {
								propHandler.handlePublisherProperties(loggerNode.attributes.name, publisherNode.attributes.name, publisherNode.attributes.formatter, publisherNode.attributes.level);
							} else {
								logger.warning("Invalid child node '" + publisherNode.nodeName + "' found -> '" + PUBLISHER_NODE + "' expected instead.");
							}
						}
					} else {
						logger.warning("Invalid child node '" + loggerNode.nodeName + "' found -> '" + LOGGER_NODE + "' expected instead.");
					}
				}
				logManager.onPropertiesRead();
			} else {
				logger.warning("The file '" + file + "' does not exist -> no logging properties loaded.");
			}
		};
		logger.info("Start loading logging properties from '" + file + "'");
		loader.load(file);
	}
}
