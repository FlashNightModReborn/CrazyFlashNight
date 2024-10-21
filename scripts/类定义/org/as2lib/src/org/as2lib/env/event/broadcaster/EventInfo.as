/*
 * Copyright the original author or authors.
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

import org.as2lib.core.BasicInterface;

/**
 * {@code EventInfo} provides at least information about the name of the event and
 * possibly further information.
 * 
 * @author Simon Wacker
 */
interface org.as2lib.env.event.broadcaster.EventInfo extends BasicInterface {
	
	/**
	 * Returns the name of the event.
	 *
	 * <p>The name of the event must be the same as the method to invoke on the listener
	 * this event serves.
	 * 
	 * @return the name of the event
	 */
	public function getName(Void):String;
	
}