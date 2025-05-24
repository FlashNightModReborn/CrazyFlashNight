/*
 * Copyright the original author or authors.
 * 
 * Licensed under the Mozilla Public License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *      https://www.mozilla.org/MPL/2.0/
 *
 * This file may be redistributed under the terms of the GNU General Public License,
 * version 3.0 (GPLv3), or any later version.
 * 
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

import org.as2lib.env.event.EventListenerSource;

/**
 * {@code EventMulticaster} multicasts an event to all added listeners with custom
 * arguments.
 * 
 * @author Simon Wacker
 */
interface org.as2lib.env.event.multicaster.EventMulticaster extends EventListenerSource {
	
	/**
	 * Dispatches the event to all added listeners passing the given arguments as
	 * parameters to the listeners' event methods.
	 *
	 * @param .. any number of arguments to pass to the listeners' event methods
	 * @throws EventExecutionException if a listener's event method threw an exception
	 */
	public function dispatch():Void;
	
}