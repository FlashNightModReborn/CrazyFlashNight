import logging.IFilter;
import logging.IFormatter;
import logging.IPublisher;
import logging.PropertyHandler;
import logging.PropertyLoader;
import logging.TraceOutput;
import logging.Logger;
import logging.Level;

import logging.util.*;
import logging.events.*;
import logging.errors.*;

/**
*	The LogManager provides a hook mechanism applications can use for loading the logging.xml file which applications can use.
*	
*	The global LogManager object can be retrieved using LogManager.getInstance(). 
*	The LogManager object is created during class initialization and cannot subsequently be changed. 
*
*	@author Ralf Siegel
*/
class logging.LogManager
{		
	private static var instance:LogManager = new LogManager();	
	private var changeListeners:List;	
	private var defaultPublisher:IPublisher;
	
	/**
	*	Private constructor.
	*/
	private function LogManager() 
	{	
		this.changeListeners = new Vector();		
	}
	
	/**
	*	Get the singleton instance.
	*
	*	@return The LogManager instance
	*/
	public static function getInstance():LogManager
	{
		if (instance == undefined) {
			instance = new LogManager();
		}
		return instance;
	}
	
	/**
	*	Returns the Filter object associated with the class with the given string name
	*
	*	@param className the filter's class name 
	*	@return the Filter object
	*/
	public static function createFilterByName(className:String):IFilter
	{
		var Filter:Function = Class.forName(className);
		if (!(new Filter instanceof IFilter)) {
			throw new InvalidFilterError(className);
		}
		return new Filter();		
	}
	
	/**
	*	Returns the Formatter object associated with the class with the given string name
	*
	*	@param className the formatters's class name 
	*	@return the Formatter object
	*/
	public static function createFormatterByName(className:String):IFormatter
	{
		var Formatter:Function = Class.forName(className);
		if (!(new Formatter instanceof IFormatter)) {
			throw new InvalidFormatterError(className);
		}
		return new Formatter();		
	}
	
	/**
	*	Returns the Publisher object associated with the class with the given string name
	*
	*	@param className the publishers's class name 
	*	@return the Publisher object
	*/
	public static function createPublisherByName(className:String):IPublisher
	{
		var Publisher:Function = Class.forName(className);
		if (!(new Publisher instanceof IPublisher)) {
			throw new InvalidPublisherError(className);
		}
		return new Publisher();		
	}

	/**
	*	Enables logging (logging is enabled by default) for all loggers.
	*/
	public function enableLogging():Void
	{
		if (Logger.prototype.log == null) {
			Logger.prototype.log = Logger.prototype.__log__;
			Logger.prototype.__log__ = null;
		}
	}
	
	/**
	*	Disables logging (logging is enabled by default) for all loggers.
	*/
	public function disableLogging():Void
	{
		if (Logger.prototype.log != null) {
			Logger.prototype.__log__ = Logger.prototype.log;
			Logger.prototype.log = null;
		}
	}
	
	/**
	*	Registers a property change listener with the log manager.
	*
	*	@param listener The listener object to be added
	*	@return true if listener was added successfully, otherwise false.
	*/
	public function addPropertyChangeListener(listener:IPropertyChangeListener):Boolean
	{
		if (!this.changeListeners.containsItem(Object(listener))) {
			return this.changeListeners.addItem(Object(listener));
		}
		return false;
	}
	
	/**
	*	Unregisters a property change listener from the log manager.
	*
	*	@param The listener object to be removed
	*	@return true if listener was actually removed, otherwise false.
	*/
	public function removePropertyChangeListener(listener:IPropertyChangeListener):Boolean
	{
		return this.changeListeners.removeItem(Object(listener));
	}
	
	/**
	*	Gets the default publisher, which usually will be the trace output.
	*
	*	@return the default publisher instance
	*/
	public function getDefaultPublisher():IPublisher
	{
		if (this.defaultPublisher == undefined) {
			this.defaultPublisher = new TraceOutput();
		}
		return this.defaultPublisher;
	}

	/**
	*	Convenience method to start reading the external logging properties.
	*	The method is supposed to be invoked by an application's main class on startup as part of the hook mechanism.
	*	Make sure you have registered a listener before in order to proceed.
	*
	*	@param propertyFile A file location which contains logging properties	
	*/
	public function readProperties(propertyFile:String):Void
	{
		Logger.getLogger("logging").setLevel(Level.INFO);
		new PropertyLoader().read(propertyFile, new PropertyHandler(), this);
	}
	
	/**
	*	Proxy handler which will be invoked when properties are read.
	*	It then will forward the event to all registered property change listeners.	
	*/
	public function onPropertiesRead():Void
	{
		for (var p:Number = 0; p < this.changeListeners.size(); p++) {
			IPropertyChangeListener(this.changeListeners.getItem(p)).onPropertyChanged(new PropertyChangeEvent(this));
		}
	}	
}