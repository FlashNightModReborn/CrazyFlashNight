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
import org.as2lib.env.event.broadcaster.ConsumableEventInfo;

/**
 * {@code SimpleConsumableEventInfo} offers support for consuming events.
 *
 * @author Martin Heidegger
 * @author Simon Wacker
 */
class org.as2lib.env.event.broadcaster.SimpleConsumableEventInfo extends BasicClass implements ConsumableEventInfo {
	
	/** The name of the event */
	private var eventName:String;
	
	/** Determines whether this event is consumed. */
	private var consumed:Boolean;
	
	/**
	 * Constructs a {@code SimpleConsumableEventInfo} instance.
	 *
	 * @param eventName the name of the event
	 */
	public function SimpleConsumableEventInfo(eventName:String) {
		this.eventName = eventName;
		this.consumed = false;
	}
	
	/**
	 * Returns the name of the event.
	 *
	 * @return the name of the event
	 */
	public function getName(Void):String {
		return this.eventName;
	}
	
	/**
	 * Returns whether the event is consumed.
	 *
	 * @return {@code true} if the event is consumed else {@code false}
	 */
	public function isConsumed(Void):Boolean {
		return this.consumed;
	}
	
	/**
     * Consumes the represented event.
	 */
	public function consume(Void):Void {
		this.consumed = true;
	}
	
}