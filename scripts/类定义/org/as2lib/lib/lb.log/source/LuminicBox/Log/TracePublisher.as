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
import LuminicBox.Utils.StringUtility;

/*
 * Class: LuminicBox.Log.TracePublisher
 * 
 * Publishes logging messages into the OUTPUT window of the Macromedia Flash editor.
 * 
 * This publisher will only work if used inside the Flash editor.
 * 
 * See also:
 * 	- <LuminicBox.Log.IPublisher>
 * 	- <LuminicBox.Log.Logger>
 */
class LuminicBox.Log.TracePublisher implements IPublisher {
	
// Group: Constructor
	/*
	 * Constructor: TracePublisher
	 * 
	 * Creates a TracePublisher instance with a default max inspection depth of 4.
	 */
	public function TracePublisher() {
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
	
// Group: Public Methods
	/*
	 * Function: publish
	 * 
	 * Logs a message into the OUTPUT window of the Flash editor.
	 * 
	 * Parameters:
	 * 	e - <LuminicBox.Log.LogEvent> object.
	 */
	public function publish(e:LogEvent):Void {
		inProgress = new Array();
		var arg:Object = e.argument;
		var txt:String = "*" + e.level.getName() + "*";
		if(e.loggerId) txt += ":" + e.loggerId;
		txt += ":";
		txt += analyzeObj(arg,1);
		trace(txt);
	}
	
	/*
	 * Function: toString
	 * 
	 * Returns the publisher's type.
	 */
	public function toString():String { return "LuminicBox.Log.TracePublisher"; }	

// Group: Private methods
	private function analyzeObj(o,depth:Number):String {
		var txt:String = "";
		var typeOf:String = typeof(o);
		if(typeOf == "string") {
			// STRING
			txt += "\"" + o + "\"";
		} else if(typeOf == "boolean" || typeOf == "number") {
			// BOOLEAN / NUMBER
			txt += o;
		} else if(typeOf == "undefined" || typeOf == "null") {
			// UNDEFINED / NULL
			txt += "("+typeOf+")";
		} else {
			// OBJECT
			var stringifyObj:Boolean = false;
			var analize:Boolean = true;
			if(o instanceof Array) {
				// ARRAY
				typeOf = "array";
				stringifyObj = false;
			} else if(o instanceof Button) {
				// BUTTON
				typeOf = "button";
				stringifyObj = true;
			} else if(o instanceof Date) {
				// DATE
				typeOf = "date";
				analize = false;
				stringifyObj = true;
			} else if(o instanceof Color) {
				// COLOR
				typeOf = "color";
				analize = false;
				stringifyObj = true;
				o = o.getRGB().toString(16);
			} else if(o instanceof MovieClip) {
				// MOVIECLIP
				typeOf = "movieclip";
				stringifyObj = true;
			} else if(o instanceof XML) {
				// XML
				typeOf = "xml";
				analize = false;
				stringifyObj = true;
			} else if(o instanceof XMLNode) {
				// XML
				typeOf = "xmlnode";
				analize = false;
				stringifyObj = true;
			} else if(o instanceof Sound) {
				// SOUND
				typeOf = "sound";
			} else if(o instanceof TextField) {
				typeOf = "textfield";
				stringifyObj = true;
			} else if(o instanceof Function) {
				typeOf = "function";
				analize = false;
			}
			txt += "(" 
			if(stringifyObj) txt += typeOf + " " + o;
			else if(typeOf == "object") txt += o;
			else if(typeOf == "array") txt += typeOf + ":" + o.length;
			else txt += typeOf;
			txt += ")";
			
			// detect cross-reference
			for (var i=0; i<inProgress.length; i++) {
				if (inProgress[i] == o) return txt + ": **cross-reference**";
			}
			inProgress.push(o);
			
			if(analize && depth <= _maxDepth) {
				var txtProps = "";
				if(typeOf == "array") {
					for(var i:Number=0; i<o.length; i++) {
						txtProps += "\n" +
						StringUtility.multiply( "\t", (depth+1) ) +
						i + ":" +
						analyzeObj(o[i], (depth+1) );
					}
				} else {
					for(var prop in o) {
						txtProps += "\n" +
							StringUtility.multiply( "\t", (depth+1) ) +
							prop + ":" +
							analyzeObj(o[prop], (depth+1) );
					}
				}
				if(txtProps.length > 0) txt += " {" + txtProps + "\n" + StringUtility.multiply( "\t", depth ) + "}";
			}
			
			inProgress.pop();
		}
		return txt;
	}
	
// Group: Private Fields
	private var _maxDepth:Number;
	private var inProgress:Array;
	
}


/*
 * Group: Changelog
 * 
 * Mon May 02 02:29:00 2005
 * 	- added sound and textfield objects
 * Wed Apr 27 01:05:31 2005:
 * 	- changed documentation format into NaturalDocs.
 * 
 * Fri Apr 22 20:18:56 2005:
 * 	- added cross-reference detection.
 * 
 * Fri Mar 25 00:39:59 2005:
 * 	- arrays are inspected using it's index.
 * 	- object.toString() and array.length are appended to the object's type (as suggested by Kelvin Luck).
 * 	- changed toString() returns value to 'LuminicBox.Log.TracePublisher'.
 * 
 * Fri Feb 25 12:00:00 2005:
 * 	- first release.
 */