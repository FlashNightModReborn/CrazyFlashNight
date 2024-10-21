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

import LuminicBox.Log.LogEvent;

/*
 * Interface: LuminicBox.Log.IPublisher
 * 
 * Basic publisher interface.
 * All publishers must implement this interface.
 */
interface LuminicBox.Log.IPublisher {
	
// Group: Functions

	/*
	 * Function: publish
	 * 
	 * Publishes a supplied <LuminicBox.Log.LogEvent>.
	 * The task this method must acomplish depends on the concrete publisher.
	 * 
	 * Parameters:
	 * 	e - <LuminicBox.Log.LogEvent>
	 */
	public function publish(e:LogEvent):Void;
	
	/*
	 * Function: toString
	 * 
	 * Returns the publisher's type.
	 */
	public function toString():String;
}


/*
 * Group: Changelog
 * 
 * Tue Apr 26 23:12:26 2005:
 * 	- changed documentation format into NaturalDocs.
 * 
 * Fri Feb 25 12:00:00 2005:
 * 	- first release.
 */