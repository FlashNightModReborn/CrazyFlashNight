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
import org.as2lib.env.event.EventListenerSource;
import org.as2lib.util.ArrayUtil;

/**
 * {@code SimpleEventListenerSource} manages listeners in the simplest way possible.
 * 
 * @author Simon Wacker
 */
class org.as2lib.env.event.SimpleEventListenerSource extends BasicClass implements EventListenerSource {
	
	/** All added listeners. */
	private var l:Array;
	
	/**
	 * Constructs a new {@code SimpleEventListenerSource} instance.
	 *
	 * @param listeners (optional) a collection of listeners to populate this listener
	 * source with
	 */
	public function SimpleEventListenerSource(listeners:Array) {
		this.l = new Array();
		if (listeners) {
			addAllListeners(listeners);
		}
	}
	
	/**
	 * Adds the passed-in {@code listener}.
	 *
	 * <p>The listener will only be added if it is neither {@code null} nor
	 * {@code undefined} and if it has not already been added to this listener source.
	 * 
	 * @param listener the listener to add
	 */
	public function addListener(listener):Void {
		if (listener) {
			if (!hasListener(listener)) {
				this.l.push(listener);
			}
		}
	}
	
	/**
	 * Adds all listeners contained in the passed-in {@code listeners} array.
	 *
	 * <p>If the passed-in {@code listeners} array is {@code null} or {@code undefined}
	 * it will be ignored. If an individual listener is {@code null} or
	 * {@code undefined} it will be ignored too.
	 *
	 * <p>Note that the order of the listeners contained in the passed-in
	 * {@code listeners} array is preserved.
	 * 
	 * @param listeners the listeners to add
	 * @see #addListener
	 */
	public function addAllListeners(listeners:Array):Void {
		if (listeners) {
			var h:Number = listeners.length;
			// the original order of the passed-in 'listeners' is preserved
			for (var i:Number = 0; i < h; i++) {
				addListener(listeners[i]);
			}
		}
	}
	
	/**
	 * Removes the passed-in {@code listener}.
	 *
	 * <p>The removal will be ignored if the passed-in {@code listener} is {@code null}
	 * or {@code undefined}.
	 * 
	 * @param listener the listener to remove
	 */
	public function removeListener(listener):Void {
		if (listener) {
			var i:Number = this.l.length;
			while (--i > -1) {
				if (this.l[i] == listener) {
					this.l.splice(i, 1);
					return;
				}
			}
		}
	}
	
	/**
	 * Removes all added listeners.
	 */
	public function removeAllListeners(Void):Void {
		this.l = new Array();
	}
	
	/**
	 * Returns all added listeners.
	 * 
	 * @return all added listeners
	 */
	public function getAllListeners(Void):Array {
		return this.l.concat();
	}
	
	/**
	 * Returns {@code true} if passed-in {@code listener} has been added.
	 * 
	 * @param listener the listener to check whether it has been added
	 * @return {@code true} if the {@code listener} has been added
	 */
	public function hasListener(listener):Boolean {
		return ArrayUtil.contains(this.l, listener);
	}
	
}