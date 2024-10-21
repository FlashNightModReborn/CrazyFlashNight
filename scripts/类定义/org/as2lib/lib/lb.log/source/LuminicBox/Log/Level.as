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

/*
 * Class: LuminicBox.Log.Level
 * 
 * This abtract class contains definitions for the message's levels.
 * 
 * The possible levels are:
 * 
 * 	- ALL (same as LOG)
 * 	- LOG
 * 	- DEBUG
 * 	- INFO
 * 	- WARN
 * 	- ERROR
 * 	- FATAL
 * 	- NONE
 */
class LuminicBox.Log.Level {
	
// Group: Static Fields
	/*
	 * Field: ALL
	 * The ALL level designates the lowest level possible. 
	 */
	public static var ALL:Level = new Level("ALL", 1);
	
	/*
	 * Field: LOG
	 * The LOG level designates fine-grained informational events.
	 */
	public static var LOG:Level = new Level("LOG", 1);
	
	/*
	 * Field: DEBUG 
	 * The DEBUG level designates fine-grained debug information.
	 */
	public static var DEBUG:Level = new Level("DEBUG", 2);
	
	/*
	 * Field: INFO
	 * The INFO level designates informational messages that highlight the progress of the application at coarse-grained level.
	 */
	public static var INFO:Level = new Level("INFO",4);
	
	/*
	 * Field: WARN
	 * The WARN level designates potentially harmful situations. 
	 */
	public static var WARN:Level = new Level("WARN",8);
	
	/*
	 * Field: ERROR
	 * The ERROR level designates error events that might still allow the application to continue running. 
	 */
	public static var ERROR:Level = new Level("ERROR",16);
	
	/*
	 * Field: FATAL
	 * The FATAL level designates very severe error events that will presumably lead the application to abort or stop. 
	 */
	public static var FATAL:Level = new Level("FATAL",32);
	
	/*
	 * Field: NONE
	 * The NONE level when used with setLevel makes all messages to be ignored.
	 */
	public static var NONE:Level = new Level("NONE", 1024);
	
	//static var INSPECT:Level = new Level("INSPECT", 0);
	
// Group: Public Functions
	/*
	 * Function: getName
	 * 
	 * Returns the level's name.
	 */
	public function getName():String { return _name; }
	
	/*
	 * Function: getValue
	 * 
	 * Returns the level's bitwise value as a number.
	 */
	public function getValue():Number { return _value; }
	
	/*
	 * Function: toString
	 * 
	 * Returns the obj's type.
	 */
	public function toString():String { return "[object LuminicBox.Log.Level." + getName() + "]"; }
	
// Group: Private Fields
	private var _name:String;
	private var _value:Number;
	
// Group: Private Constructor
	/*
	 * Constructor: Level
	 * 
	 * The constructor is private, use static fields for accessing different levels.
	 */
	private function Level(name:String, value:Number) {
		this._name = name;
		this._value = value;
	}
}


/*
 * Group: Changelog
 * 
 * Tue Apr 26 23:41:52 2005:
 * 	- changed documentation format into NaturalDocs.
 * 
 * Fri Apr 01 01:20:52 2005:
 * 	- changed toString() override to include full class name and level.
 * 
 * Fri Feb 25 12:00:00 2005:
 * 	- first release.
 */