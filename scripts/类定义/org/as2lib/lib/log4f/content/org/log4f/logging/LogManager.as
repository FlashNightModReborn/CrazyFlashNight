/*
   Copyright 2004 Ralf Siegel

   Licensed under the Apache License, Version 2.0 (the "License");
   you may not use this file except in compliance with the License.
   You may obtain a copy of the License at

       http://www.apache.org/licenses/LICENSE-2.0

   Unless required by applicable law or agreed to in writing, software
   distributed under the License is distributed on an "AS IS" BASIS,
   WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
   See the License for the specific language governing permissions and
   limitations under the License.
*/
import org.log4f.logging.IFilter;
import org.log4f.logging.IFormatter;
import org.log4f.logging.IPublisher;
import org.log4f.logging.DefaultPublisher;
import org.log4f.logging.Logger;
import org.log4f.logging.Level;

import org.log4f.logging.util.*;
import org.log4f.logging.errors.*;

/**
 * The LogManager provides a hook mechanism applications can use for loading
 * the logging.xml file which applications can use.
 *
 * The global LogManager object can be retrieved using LogManager.getInstance(). 
 * The LogManager object is created during class initialization and cannot
 * subsequently be changed. 
 *
 * @author Ralf Siegel
 */
class org.log4f.logging.LogManager
{		
	private static var _instance:LogManager;
	
	private var defaultPublisher:IPublisher;
	
	/**
	*	Private constructor.
	*/
	private function LogManager() 
	{	
	}
	
	/**
	*	Get the singleton instance.
	*
	*	@return The LogManager instance
	*/
	public static function getInstance():LogManager
	{
		if (_instance == undefined) {
			_instance = new LogManager();
		}
		return _instance;
	}
	
	/**
	*	Returns the Filter object associated with the class with the given string name
	*
	*	@return the Filter object
	*/
	public static function getNewFilterInstanceByName(className:String):IFilter
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
	*	@return the Formatter object
	*/
	public static function getNewFormatterInstanceByName(className:String):IFormatter
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
	*	@return the Publisher object
	*/
	public static function getNewPublisherInstanceByName(className:String):IPublisher
	{
		var Publisher:Function = Class.forName(className);
		if (!(new Publisher instanceof IPublisher)) {
			throw new InvalidPublisherError(className);
		}
		return new Publisher();		
	}

	/**
	*	Enables logging (logging is enabled by deafult) for all loggers.
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
     * Gets the default publisher, which usually will be the DefaultPublisher.
     *
     * @return the default publisher instance
     */
	public function getDefaultPublisher():IPublisher
	{
		if (this.defaultPublisher == undefined) {
			this.defaultPublisher = new DefaultPublisher();
		}
		return this.defaultPublisher;
	}
}