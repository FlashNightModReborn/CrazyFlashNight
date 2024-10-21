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

import LuminicBox.Log.Level;

/*
 * Class: LuminicBox.Log.LogEvent
 * 
 * Represents a log message with information about the object to inspect, its level, the originator logger and other information.
 * 
 * THIS CLASS IS USED INTERNALLY. It should only be used when implementing publishers.
 */
class LuminicBox.Log.LogEvent {
	
	
// Group: Public Fields
	/*
	 * Field: loggerId
	 * 
	 * The originator logger id.
	 */
	public var loggerId:String;
	
	/*
	 * Field: time
	 * 
	 * The event's timetamp.
	 */
	public var time:Date;

	/*
	 * Field: level
	 * 
	 * The message level. See <LuminicBox.Log.Level>
	 */
	public var level:Level;
	
	/*
	 * Field: argument
	 * 
	 * The message or object to log
	 */
	public var argument:Object;
	
// Group: Constructor
	/*
	 * Constructor: LogEvent
	 * 
	 * Creates a LogEvent instance.
	 * 
	 * Parameters:
	 * 	loggerId - String. The originators logged id. It can be null.
	 * 	argument - Object. The message or object to log.
	 * 	level - <LuminicBox.Log.Level> The level of the event.
	 */
	public function LogEvent(loggerId:String, argument:Object, level:Level) {
		this.loggerId = loggerId;
		this.argument = argument;
		this.level = level;
		time = new Date();
	}
	
// Group: Static Functions
	/*
	 * Function: serialize
	 * 
	 * Serializes a LogEvent object into an object that can be passed to LocalConnection.
	 * 
	 * Parameters:
	 * 	logEvent - A LogEvent object.
	 * 
	 * Returns:
	 * 	Object:
	 * 		- loggerId:String
	 * 		- time:Date
	 * 		- levelName:String;
	 * 		- argument:Object
	 */
	public static function serialize(logEvent:LogEvent):Object {
		var o:Object = new Object();
		o.loggerId = logEvent.loggerId;
		o.time = logEvent.time;
		o.levelName = logEvent.level.getName();
		o.argument = logEvent.argument;
		return o;
	}
	
	/*
	 * Function: deserialize
	 * 
	 * Deseriliazes an object into a LogEvent object.
	 * 
	 * Parameters:
	 * 	o - The serialized LogEvent object.
	 * 
	 * Returns:
	 * A LogEvent object.
	 */
	public static function deserialize(o:Object):LogEvent {
		var l:Level = LuminicBox.Log.Level[""+o.levelName];
		var e:LogEvent = new LogEvent(o.loggerId, o.argument, l);
		e.time = o.time;
		return e;
	}
	
// Group: Public Functions
	/*
	 * Function: toString
	 * 
	 * Returns the object's type.
	 */
	public function toString():String { return "[object LuminicBox.Log.LogEvent]"; }
	
}


/*
 * Group: Changelog
 * 
 * Wed Apr 27 00:18:29 2005:
 * 	- changed documentation format into NaturalDocs.
 * 
 * Fri Apr 01 01:44:01 2005:
 * 	- added toString() override.
 * 
 * Fri Feb 25 12:00:00 2005:
 * 	- first release.
 */