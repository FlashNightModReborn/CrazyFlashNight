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

import LuminicBox.Log.Logger;

/*
 * Class: LuminicBox.Log.DefaultConfig
 * 
 * IMPORTANTE NOTE:
 * THIS CLASS IS BEING DEPRECATED
 * USE Logger.getLogger() instead
 * 
 * Abstract class for creating Logger instances with default publishers:
 * 	- <LuminicBox.Log.TracePublisher>
 * 	- <LuminicBox.Log.ConsolePublisher>
 * 
 * See Also:
 * 	- <LuminicBox.Log.Logger>
 */
class LuminicBox.Log.DefaultConfig {
	
	/*
	 * Function: getLogger
	 * 
	 * Static function for creating Logger instances with the default publishers
	 * 
	 * The default publishers are:
	 * 	- TracePublisher
	 * 	- ConsolePublisher
	 * 
	 * Parameters:
	 * 	id - String. ID for the new Logger instance.
	 * 	maxDepth - Number (optional). The max inspection depth for the publishers. The default value is 3.
	 * 
	 * Returns:
	 * A <LuminicBox.Log.Logger> instance.
	 */
	public static function getLogger(id:String, maxDepth:Number):Logger {
		return Logger.getLogger(id, maxDepth);
	}
	
// Group: Private Methods
	/*
	 * Constructor: DefaultConfig
	 * 
	 * Private constructor, use static function <LuminicBox.Log.DefaultConfig.getLogger> instead.
	 */
	private function DefaultConfig() { }
	
}


/*
 * Group: Changelog
 
 * Tue May 3 20:04:54 2005:
 * 	- this class is being deprecated
 * 
 * Tue Apr 26 23:08:10 2005:
 * 	- changed documentation format into NaturalDocs.
 * 
 * Fri Feb 25 12:00:00 2005:
 * 	- first release.
 */