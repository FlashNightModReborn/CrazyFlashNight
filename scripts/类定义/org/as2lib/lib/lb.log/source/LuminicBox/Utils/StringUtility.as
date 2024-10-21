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

/**
* Static class containing string utilities.
*/
class LuminicBox.Utils.StringUtility {
	
	private function StringUtility() { }
	
	/**
	* Duplicates a given string for the amount of given times.
	* @param str String to duplicate.
	* @paran Amount of time to duplicate.
	*/
	public static function multiply(str:String, n:Number) {
		var ret:String = "";
		for(var i=0;i<n;i++) ret += str;
		return ret;
	}
	
	/**
	* String replacement function. These implementation causes some perform penalties.
	* @param string Original string
	* @param oldValue A string to be replaced
	* @param newValue A string to replace all occurrences of oldValue.
	*/
	public static function replace(string:String, oldValue:String, newValue:String):String {
		return string.split(oldValue).join(newValue);
	}
	
	public static function htmlEncode(str:String) {
		str = str.split("&").join("&amp;");
		str = str.split("\"").join("&quot;");
		str = str.split("'").join("&apos;");
		str = str.split("<").join("&lt;");
		str = str.split(">").join("&gt;");
		return str;
	}

	public static function trim(s) {   
	    var mx;           
	    var i;
		for (mx = s.length; mx > 0; --mx)
		{
			if (ord(s.substring(mx, 1))>32)
			{
				break;
			}
		}
		for (i = 1; i < mx; ++i)
		{
			if (ord(s.substring(i, 1))>32)
			{
				break;
			}
		}
		return s.substring(i, mx + 1 - i);
	}
	
}