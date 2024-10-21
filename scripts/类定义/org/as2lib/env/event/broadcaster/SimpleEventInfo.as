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

import org.as2lib.core.BasicClass;
import org.as2lib.env.event.broadcaster.EventInfo;

/**
 * {@code SimpleEventInfo} lets you dynamically set the name of the event.
 *
 * <p>Use this dynamic behavior only if it really adds any value. Creating a new
 * {@code EventInfo} implementation that returns always the same name (immutable)
 * for one specific listener is much cleaner. You then also only have to change the
 * name of the event once in your {@code EventInfo} implementation if you change
 * the event method name on the listener.
 * 
 * @author Simon Wacker
 */
class org.as2lib.env.event.broadcaster.SimpleEventInfo extends BasicClass implements EventInfo {
	
	/** Name of the event */
	private var eventName:String;
	
	/**
	 * Constructs a {@code SimpleEventInfo} instance.
	 *
	 * @param name the name of the event
	 */
	public function SimpleEventInfo(eventName:String) {
		this.eventName = eventName;
	}
	
	/**
	 * Returns the name of the event.
	 *
	 * @return the name of the event
	 */
	public function getName(Void):String {
		return this.eventName;
	}
	
}