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

import LuminicBox.Log.IPublisher;
import LuminicBox.Log.LogEvent;
import LuminicBox.Log.PropertyInspector;

/*
 * Class: LuminicBox.Log.ConsolePublisher
 * 
 * Publishes logging messages into the FlashInspector console.
 * 
 * This publisher can be used in any enviroment as long as the FlashInspector is running.
 * 
 * It can be used from inside the Flash editor and from the final production enviroment without making any changes.
 * This allows to see the logging messages even after the final SWF is in production.
 */
class LuminicBox.Log.ConsolePublisher implements IPublisher {
	
// Group: Constructor
	/*
	 * Constructor: ConsolePublisher
	 * 
	 * Creates a ConsolePublisher instance with a default max inspection depth of 4.
	 */
	public function ConsolePublisher() {
		maxDepth = 4;
	}

// Group: Properties
	/*
	 * Property: maxDepth
	 * 
	 * Sets the max inspection depth.
	 * 
	 * The default value is 4 and the max valid value is 255.
	 */
	public function set maxDepth(value:Number) { _maxDepth = (_maxDepth>255)?255:value; }
	
	/*
	 * Property: maxDepth
	 * 
	 * Get the current inspection depth
	 */
	public function get maxDepth():Number { return _maxDepth; }
	
	/*
	 * Property: showFunctions
	 * 
	 * Tells the publisher if [function] types should be serialized along with the obj.
	 * The default value is false;
	 */
	public function set showFunctions(value:Boolean) { _showFunctions = value; }
	public function get showFunctions():Boolean { return _showFunctions; }
	

// Group: Public Functions
	/*
	 * Function: publish
	 * 
	 * Serializes and sends a log message to the FlashInspector console.
	 * 
	 * Parameters:
	 * 	e - <LuminicBox.Log.LogEvent> object.
	 */
	public function publish(e:LogEvent):Void {
		_inProgressObjs = new Array();
		_inProgressSerial = new Array();
		var o:Object = LogEvent.serialize(e);
		o.argument = serializeObj(o.argument,1);
		o.version = _version;
		var lc = new LocalConnection();
		lc.send("_luminicbox_log_console", "log", o);
	}
	
	/*
	 * Function: toString
	 * 
	 * Returns the publisher's type.
	 */
	public function toString():String { return "LuminicBox.Log.ConsolePublisher"; }
	
// Group: Private Methods
	private function serializeObj(o,depth:Number) {
		var serial = new Object();
		var type = getType(o);
		serial.type = type.name;
		
		if(!type.inspectable) {
			serial.value = o;
		} else if(type.stringify) {
			serial.value = o.toString();
		} else {
			var items:Array = new Array();
			serial.value = items;
			// add target if possible
			if(type.name == "movieclip" || type.name == "button" || type.name == "object" || type.name == "textfield") serial.id = ""+o;
			// detect recursion
			for (var i=0; i<_inProgressObjs.length; i++) {
				if(_inProgressObjs[i] == o) {
					// cross-reference detected
					var refSerial:Object = _inProgressSerial[i];
					var newSerial:Object = {value:refSerial.value,type:refSerial.type,crossRef:true};
					if(refSerial.id) newSerial.id = refSerial.id;
					return newSerial;
				}
			}
			_inProgressObjs.push(o);
			_inProgressSerial.push(serial);
			// validate current depth
			if(depth <= _maxDepth) {
				if(type.properties) {
					// inspect built-in properties
					var props = new Object();
					for(var i:Number=0; i<type.properties.length; i++) {
						props[type.properties[i]] = o[type.properties[i]];
					}
					props = serializeObj(props, _maxDepth);
					props.type = "properties";
					items.push( {property:"$properties",value:props } );
				}
				// serialize fields
				if(o instanceof Array) {
					// array fields
					for(var pos:Number=0; pos<o.length; pos++) items.push( {property:pos,value:serializeObj( o[pos], (depth+1) )} );
				} else {
					// object fields
					for(var prop:String in o) {
						if( !(o[prop] instanceof Function && !_showFunctions) ) {
							// avoid inspecting built-in properties again
							var serialize = true;
							if(type.properties) {
								for(var i:Number=0; i<type.properties.length; i++) {
									if(prop == type.properties[i]) serialize = false;
								}
							}
							if(serialize) items.push( {property:prop,value:serializeObj( o[prop], (depth+1) )} );
						}
					}
				}
			} else {
				// max depth reached
				serial.reachLimit =true;
			}
			_inProgressObjs.pop();
			_inProgressSerial.pop();
		}
		return serial;
	}
	
	private function getType(o) {
		var typeOf = typeof(o);
		var type = new Object();
		type.inspectable = true;
		type.name = typeOf;
		if(typeOf == "string" || typeOf == "boolean" || typeOf == "number" || typeOf == "undefined" || typeOf == "null") {
			type.inspectable = false;
		} else if(o instanceof Date) {
			// DATE
			type.inspectable = false;
			type.name = "date";
		} else if(o instanceof Array) {
			// ARRAY
			type.name = "array";
		} else if(o instanceof Button) {
			// BUTTON
			type.name = "button";
			type.properties = PropertyInspector.buttonProperties;
		} else if(o instanceof MovieClip) {
			// MOVIECLIP
			type.name = "movieclip";
			type.properties = PropertyInspector.movieClipProperties;
		} else if(o instanceof XML) {
			// XML
			type.name = "xml";
			type.stringify = true;
		} else if(o instanceof XMLNode) {
			// XML node
			type.name = "xmlnode"
			type.stringify = true;
		} else if(o instanceof Color) {
			// COLOR
			type.name = "color"
		} else if(o instanceof Sound) {
			// SOUND
			type.name = "sound";
			type.properties = PropertyInspector.soundProperties;
		} else if(o instanceof TextField) {
			// TEXTFIELD
			type.name = "textfield";
			type.properties = PropertyInspector.textFieldProperties;
		}
		return type;
	}
	
// Group: Private Fields
	private var _version:Number=0.15;
	private var _maxDepth:Number;
	private var _showFunctions:Boolean=false;
	private var _inProgressObjs:Array;
	private var _inProgressSerial:Array;
	
}


/*
 * Group: Changelog
 * 
 * Tue May 03 01:17:27 2005:
 * 	- properties are serialized one time only.
 * 
 * Mon May 02 01:43:52 2005:
 * 	- inspection of Sound and TextField properties.
 * 
 * Sat Apr 30 13:05:13 2005:
 * 	- object.toString() is appended to the object's id.
 * 
 * Wed Apr 27 01:05:31 2005:
 * 	- changed documentation format into NaturalDocs.
 * 
 * Mon Apr 25 15:21:15 2005:
 * 	- added cross-reference detection.
 * 
 * Tue Apr 19 01:19:45 2005:
 * 	- new version build: 0.15.
 * 	- publisher version is added to serialized obj.
 * 
 * Tue Mar 22 22:02:03 2005:
 * 	- added support for inspecting movieclips, button properties
 * 	- changed toString() returns value to 'LuminicBox.Log.ConsolePublisher'
 */