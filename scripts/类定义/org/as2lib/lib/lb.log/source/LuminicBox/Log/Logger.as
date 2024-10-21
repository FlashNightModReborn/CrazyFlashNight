/*
 * Copyright (c) 2005 Pablo Costantini (www.luminicbox.com). All rights reserved.
 * 
 * Licensed under the MOZILLA PUBLIC LICENSE, Version 1.1 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 * 
 *      http://www.mozilla.org/MPL/MPL-1.1.html
 * 
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

import LuminicBox.Log.*;

/*
 * Class: LuminicBox.Log.Logger
 * This class contains methods for logging messages at differente levels.
 * 
 * These messages can me basic types (strings, numbers, dates) or complex objects and MovieClips.
 * 
 * There are also configuration methods.
 * 
 * Example 1:
 * (begin example)
 * 	import LuminicBox.Log.*;
 * 	var log = new Logger("myApp");
 * 	log.addPublisher( new TracePublisher() );
 * 	// ...
 * 	log.debug("debug message");
 * 	log.info("info message");
 * 	// ...
 * 	var xml = new XML("<note><to>John</to><from>Dana</from><heading>Reminder</heading><body>Don´t forget the milk</body></note>");
 * 	log.debug(xml);
 * (end)
 * 
 * Example 2:
 * (begin example)
 * 	import LuminicBox.Log.*;
 * 	var log = Logger.getLogger("myApp");
 * 	// ...
 * 	log.debug("debug message");
 * 	log.info("info message");
 * 	// ...
 * 	var xml = new XML("<note><to>John</to><from>Dana</from><heading>Reminder</heading><body>Don´t forget the milk</body></note>");
 * 	log.debug(xml);
 * (end)
 */
class LuminicBox.Log.Logger {
	
// Group: Static Functions
	/*
	 * Function: getLogger
	 *
	 * Provides singleton access to Logger instances. Each logger is identified by it's Id.
	 * When the instance is created both TracePublisher and ConsolePublisher are added to the logger's publisher list.
	 * 
	 * Paremeters:
	 *  logId - String (Required) Logger instance ID.
	 *  maxDepth - Number (Optional) Defines the publisher's maxDepth property
	 */
	public static function getLogger(logId:String, maxDepth:Number) {
		if(logId.length > 0) {
			var log:Logger = _instances[logId];
			if(log == undefined) {
				log = new Logger(logId);
				var tp:TracePublisher = new TracePublisher();
				var cp:ConsolePublisher = new ConsolePublisher();
				if(maxDepth == undefined) maxDepth = 3;
				tp.maxDepth = maxDepth;
				cp.maxDepth = maxDepth;
				log.addPublisher(tp);
				log.addPublisher(cp);
			}
			return log;
		}
		return null;
	}
	
// Group: Constructor
	/*
	 * Function: Logger
	 * 
	 * Creates a new Logger instance.
	 * The logId parameter is optional. It identifies the logger and all messages to the publisher will be sent with this ID.
	 * 
	 * Parameters:
	 * 	logId - String. ID for the new Logger instance.
	 */
	public function Logger(logId:String) {
		this._loggerId = logId;
		this._level = Level.LOG;
		_publishers = new Object();
		//_filters = new Array();
		// save instance
		_instances[logId] = log;
	}
	
// Group: Logging Functions
	/*
	 * Function: log
	 * 
	 * Logs an object or message with the LOG level.
	 * 
	 * Parameters:
	 * 	argument - The message or object to inspect.
	 */
	public function log(argument):Void { publish(argument, Level.LOG); }
	/*
	 * Function: debug
	 * 
	 * Logs an object or message with the DEBUG level.
	 * 
	 * Parameters:
	 * 	argument - The message or object to inspect.
	 */	
	public function debug(argument):Void { publish(argument, Level.DEBUG); }
	/*
	 * Function: info
	 * 
	 * Logs an object or message with the INFO level.
	 * 
	 * Parameters:
	 * 	argument - The message or object to inspect.
	 */
	public function info(argument):Void { publish(argument, Level.INFO); }
	/*
	 * Function: warn
	 * 
	 * Logs an object or message with the WARN level.
	 * 
	 * Parameters:
	 * 	argument - The message or object to inspect.
	 */
	public function warn(argument):Void { publish(argument, Level.WARN); }
	/*
	 * Function: error
	 * 
	 * Logs an object or message with the ERROR level.
	 * 
	 * Parameters:
	 * 	argument - The message or object to inspect.
	 */	
	public function error(argument):Void { publish(argument, Level.ERROR); }
	/*
	 * Function: fatal
	 * 
	 * Logs an object or message with the FATAL level.
	 * 
	 * Parameters:
	 * 	argument - The message or object to inspect.
	 */
	public function fatal(argument):Void { publish(argument, Level.FATAL); }
	
	//function inspect(argument):Void { publish(argument, Level.INSPECT); }
	
// Group: Public Functions
	
	/*
	 * Function: getId
	 * 
	 * Returns the logger's id.
	 */
	public function getId():String { return _loggerId; }
	
	/*
	 * Function: setLevel
	 * 
	 * Sets the lowest required level for any message.
	 * Any message that have a level that is lower than the supplied value will be ignored.
	 * 
	 * This is the most basic form of filter.
	 * 
	 * Parameters:
	 * 	level - <LuminicBox.Log.Level> obj
	 * 
	 * Example:
	 * (begin example)
	 * var log = LuminicBox.Log.DefaultConfig.getLogger("testlog");
	 * log.setLevel(LuminicBox.Log.Level.DEBUG);
	 * (end)
	 */
	public function setLevel(level:Level):Void { _level = level; }
	
	/*
	 * Function: getLevel
	 * 
	 * Returns the lowest required level for any message.
	 * 
	 * Returns: 
	 * 	<LuminicBox.Log.Level> obj
	 */
	public function getLevel():Level { return _level; }
	
	/*
	 * Function: addPublisher
	 * 
	 * Adds a Publisher to the publishers collection.
	 * The supplied publisher must implement the IPublisher interface.
	 * There can only be one instance of each Publisher.
	 * 
	 * Parameters:
	 * 	publisher - <LuminicBox.Log.IPublisher> A publisher that implements IPublisher interface.
	 * 
	 * Example:
	 * (begin example)
	 * import LuminicBox.Log.*;
	 * var log:Logger = new Logger();
	 * // adds an instance of the TracePublisher
	 * log.addPublisher( new TracePublisher() );
	 * // adds an instance of the ConsolePublisher (for the FlashInspector)
	 * log.addPublisher( new ConsolePublisher() );
	 * // ...
	 * (end)
	 * 
	 * See Also:
	 * 	- <LuminicBox.Log.IPublisher>
	 * 	- <LuminicBox.Log.TracePublisher>
	 * 	- <LuminicBox.Log.ConsolePublisher>
	 */
	public function addPublisher(publisher:IPublisher):Void {
		if( !_publishers[publisher.toString()] ) _publishers[publisher.toString()] = publisher
	}
	
	/*
	 * Function: removePublisher
	 * 
	 * Removes a Publisher from the publishers collection. A new instance of that kind of publisher can be supplied.
	 * 
	 * Parameters:
	 * 	publisher - <LuminicBox.Log.IPublisher> A publisher that implements IPublisher interface.
	 * 
	 * Example:
	 * (begin example)
	 * import LuminicBox.Log.*;
	 * var log:Logger = new Logger();
	 * // adds an instance of the TracePublisher
	 * log.addPublisher( new TracePublisher() );
	 * // adds an instance of the ConsolePublisher (for the FlashInspector)
	 * log.addPublisher( new ConsolePublisher() );
	 * // ...
	 * // removes the TracePublisher for the logger
	 * log.removePublisher( new TracePublisher() );
	 * (end)
	 */
	public function removePublisher(publisher:IPublisher):Void {
		delete _publishers[publisher.toString()];
	}
	
	/*
	 * Function: getPublishers
	 * 
	 * Returns an associative object containing all publisher
	 * 
	 * See Also:
	 * 	- <LuminicBox.Log.IPublisher>
	 * 
	 * Example:
	 * (begin example)
	 * var log = LuminicBox.Log.DefaultConfig.getLogger("testlog");
	 * var logPublishers = log.getPublishers();
	 * // logPublishers contains:
	 * //	- LuminicBox.Log.TracePublisher
	 * //	- LuminicBox.Log.ConsolePublisher
	 * log.debug( logPublishers );
	 * (end)
	 */
	public function getPublishers():Object { return _publishers; }
	
	/*
	 * Function: toString
	 * 
	 * Returns the object's type
	 * 
	 * Example:
	 * (begin example)
	 * var log = new LuminicBox.Log.Logger();
	 * trace('log: ' + log.toString());
	 * // prints 'log: [object LuminicBox.Log.Logger]';
	 */
	public function toString():String { return "[object LuminicBox.Log.Logger]"; }
	
// Group: Private Fields
	private var _loggerId:String;
	private var _publishers:Object;
	private var _level:Level;
	private static var _instances:Object = new Object();
	
// Group: Private Functions
	private function publish(argument, level:Level):Void {
		if( level.getValue() >= _level.getValue() ) {
			var e:LogEvent = new LogEvent(this._loggerId, argument, level);
			for(var publisher:String in _publishers) IPublisher(_publishers[publisher]).publish(e);
		}
	}
}


/*
 * Group: Changelog
 * 
 * Tue May 3 20:03:41 2005:
 * 	- added getLogger() for singleton access.
 *
 * Tue Apr 26 16:12:55 2005:
 * 	- changed documentation format into NaturalDocs and added some examples.
 * 
 * Fri Apr 01 01:15:57 2005:
 * 	- added getId() and getLevel() (suggested by Simon Waker).
 * 	- added toString() override.
 * 	- changed _publishers type to object.
 * 
 * Fri Feb 25 12:00:00 2005:
 * 	- first release.
 */ 