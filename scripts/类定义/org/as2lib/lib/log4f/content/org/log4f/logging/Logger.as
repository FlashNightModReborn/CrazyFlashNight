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
import org.log4f.logging.IPublisher;
import org.log4f.logging.Level;
import org.log4f.logging.LogRecord;
import org.log4f.logging.LogManager;
import org.log4f.logging.util.List;
import org.log4f.logging.util.Vector;

/**
 * A Logger object is used to log messages for a specific system or application
 * component. 
 * Loggers are normally named, using a hierarchical dot-separated namespace. 
 * Logger names can be arbitrary strings, but they should normally be based on
 * the package name or class name of the logged component, such as mx.core or
 * mx.controls. 
 * In additon it is possible to create "anonymous" Loggers that are not stored
 * in the Logger namespace. 
 *
 * @see http://java.sun.com/j2se/1.4.2/docs/guide/util/logging/overview.html
 * @author Ralf Siegel
 */
class org.log4f.logging.Logger
{
	private static var loggerMap:Object;
	private var name:String;
	private var level:Level;
	private var filter:IFilter;
	private var publishers:List;

	/**
	*	Private constructor. Use factory method to create logger objects only.
	*/
	private function Logger(name:String)
	{
		this.name = name;
		this.publishers = new Vector();
	}
	
	/**
     * Find or create a logger for a named subsystem. 
     * If a logger has already been created with the given name it is returned.
     * Otherwise a new logger is created. 
     * If a new logger is created its log level will be configured based on the
     * LogManager configuration and it will configured to also send logging
     * output to its parent's publishers. 
     *
     * @name - A name for the logger, or nothing for anonymous loggers. A name
     * should be a dot-separated name and should normally be based on the
     * package name or class name of the subsystem, such as mx.core or mx.controls 
     * @return - A suitable logger.
     */
	public static function getLogger(name:String):Logger
	{
		if (name == undefined || name == "") {
			return new Logger();
		}
		if (getLoggerMap()[name] == undefined) {
			getLoggerMap()[name] = new Logger(name);
		}
		return getLoggerMap()[name];
	}
	
	/**
	*	Returns the Logger Map where all loggers are kept. If the map does not yet exist, a new one will be created.
	*
	*	@return A map object
	*/
	private static function getLoggerMap():Object
	{
		if (loggerMap == undefined) {
			loggerMap = new Object();
		}
		return loggerMap;
	}
	
	/**
	*	Return the parent for this Logger. 
	*
	*	This method returns the nearest extant parent in the namespace. 
	*	Thus if a Logger is called "a.b.c.d", and a Logger called "a.b" has been created but no logger "a.b.c" exists, then a call of getParent on the Logger "a.b.c.d" will return the Logger "a.b". 
	*	
	*	The parent for the anonymous Logger is always the root (global) Logger.
	*
	*	The result will be undefined if it is called on the root (global) Logger in the namespace. 
	*
	*	@return A logger object or undefined
	*/
	public function getParent():Logger
	{
		if (this.getName() == "global") {
			return undefined;
		}
		
		var a:Array = this.getName().split(".");
		a.pop();
		
		while (a.length > 0) {
			var name:String = a.join(".");
			if (getLoggerMap()[name] != undefined) {
				return getLogger(name);
			} else {
				a.pop();
			}
		}
		
		return getLogger("global");
	}
	
	/**
	*	Get the name for this logger.
	*
	*	@return The logger's name or undefined for anonymous loggers.
	*/
	public function getName():String
	{
		return this.name;
	}

	/**
	 * Log a DEBUG message.
	 * If the logger is currently enabled for the DEBUG message level then the
	 * given message is forwarded to all the registered publishers.
	 *
	 * @param message A String message
	 */
	public function debug(message:String):Void {
		this.log(Level.DEBUG, message);
	}

	/**
	 * Log an INFO message.
	 * If the logger is currently enabled for the INFO message level then the
	 * given message is forwarded to all the registered publishers.
	 *
	 * @param message A String message
	 */
	public function info(message:String):Void {
		this.log(Level.INFO, message);
	}

	/**
	 * Log a WARN message.
	 * If the logger is currently enabled for the WARN message level then the
	 * given message is forwarded to all the registered publishers.
	 *
	 * @param message A String message
	 */
	public function warn(message:String):Void {
		this.log(Level.WARN, message);
	}

	/**
	 * Log an ERROR message.
	 * If the logger is currently enabled for the ERROR message level then the
	 * given message is forwarded to all the registered publishers.
	 *
	 * @param message A String message
	 */
	public function error(message:String):Void {
		this.log(Level.ERROR, message);
	}

	/**
	 * Log a FATAL message.
	 * If the logger is currently enabled for the FATAL message level then the
	 * given message is forwarded to all the registered publishers.
	 *
	 * @param message A String message
	 */
	public function fatal(message:String):Void {
		this.log(Level.FATAL, message);
	}
		
	/**
	*	Log a message (including the provider in the log). 
	*	If the logger is currently enabled for the given message level then the
	*	given message is forwarded to all the registered publishers. 
	*	
	*	@param level The level object
	*	@param message The string message
	*	@param provider An optional object which is the provider of the
	*	debug message (useful for additional debugging / inspection purposes)
	*/
	public function log(level:Level, message:String, provider:Object):Void
	{
		if (this.isLoggable(level)) {
			var logRecord:LogRecord =
				new LogRecord(new Date(), this.getName(), level, message, provider);
			if (this.isPublishable(logRecord)) {
				var ap:List = this.getActivePublishers();
				for (var p = 0; p < ap.size(); p++) {
					IPublisher(ap.getItem(p)).publish(logRecord);
				}
			}
		}
	}
		
	/**
	*	Set the log level specifying which message levels will be logged by this logger. 
	*	Message levels lower than this value will be discarded. The level value Level.OFF can be used to turn off logging. 
	*	If the new level is undefined, it means that this node should inherit its level from its nearest ancestor with a specific (non-undefined) level value. 
	*
	*	@param The new level or undefined.
	*/
	public function setLevel(level:Level):Void
	{
		this.level = level;
	}
	
	/**
	*	Get the log Level that has been specified for this Logger. 
	*	The result may be undefined, which means that this logger's effective level will be inherited from its parent. 
	*
	*	@return The level object for this logger or undefined.
	*/
	public function getLevel():Level
	{
		return this.level;
	}
	
	/**
	*	Get the effective log Level for this logger. 
	*	The result will be Level.ALL if the inherited level from its parent is undefined.
	*
	*	@return The effective level object for this logger.
	*/
	private function getEffectiveLevel():Level
	{
		if (this.getLevel() != undefined) {
			return this.getLevel();
		}

		var level:Level = this.getParent().getEffectiveLevel();
		
		if (level != undefined) {
			return level;
		}
		
		return Level.ALL;
	}
	
	/**
	*	Set a filter to control output on this Logger. 
	*	After passing the initial "level" check, the Logger will call this Filter to check if a log record should really be published. 
	*
	*	@param A filter object
	*/
	public function setFilter(filter:IFilter):Void
	{
		this.filter = filter;
	}
	
	/**
	*	Get the current filter for this Logger. 
	*
	*	@return A filter object or undefined.
	*/
	public function getFilter():IFilter
	{
		return this.filter;
	}
	
	/**
	*	Adds a publisher for this logger to receive logging messages.
	*	By default, Loggers also send their output to their parent logger.
	*
	*	@param A new publisher object.
	*/
	public function addPublisher(publisher:IPublisher):Boolean
	{
		if (!this.publishers.containsItem(Object(publisher))) {
			return this.publishers.addItem(Object(publisher));
		}
		return false;
	}
	
	/**
	*	Removes a publisher currently associated with this logger.
	*
	*	@param A publisher object.
	*/
	public function removePublisher(publisher:IPublisher):Boolean
	{
		return this.publishers.removeItem(Object(publisher));
	}
	
	/**
	*	Gets a list with Publishers currently associated with this logger.
	*
	*	@return A list with publishers (may be empty)
	*/
	public function getPublishers():List
	{
		return this.publishers;
	}
	
	/**
	*	Gets a list with Publishers including the parent's loggers publishers.
	*
	*	@return A list with publishers (may be empty)
	*/
	private function getActivePublishers():List
	{		
		if (this.getParent() != undefined) {
			var v:List = new Vector();
			v.addAll(this.getPublishers());
			v.addAll(this.getParent().getActivePublishers());
			if (v.isEmpty()) {
				v.addItem(Object(LogManager.getInstance().getDefaultPublisher()));
			}	
			return v;
		}
		return this.getPublishers();
	}
	
	/**
	*	Check if a message of the given level would actually be logged by this logger. 
	*	This check is based on the Loggers effective level, which may be inherited from its parent. 
	*
	*	@return true if the given message is currently being logged
	*/
	public function isLoggable(level:Level):Boolean
	{
	
		if (this.getEffectiveLevel() > level) {
			return false;
		}
		
		return true;		
	}
	
	/**
	*	Check if a log record would actually be published by this logger, after it had passed the cheap level check through isLoggable
	*	This private convenience method basically checks if the log record would pass the filter.
	*
	*	@param the LogRecord to be checked
	*	@return true if publishable, otherwise false
	*/
	private function isPublishable(logRecord:LogRecord):Boolean
	{
	
		if (this.getFilter() == undefined || this.getFilter() == null) {
			return true;
		}
		
		if (this.getFilter().isLoggable(logRecord)) {
			return true;
		}

		return false;	
	}
}
