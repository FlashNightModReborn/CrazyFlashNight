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
 * {@code EventListenerSource} acts as a source for listeners by declaring basic
 * methods to add, remove and get listeners.
 * 
 * @author Simon Wacker
 * @author Martin Heidegger
 * @version 1.1
 */
interface org.as2lib.env.event.EventListenerSource extends BasicInterface {
	
	/**
	 * Adds the passed-in {@code listener}.
	 * 
	 * @param listener the listener to add
	 */
	public function addListener(listener):Void;
	
	/**
	 * Adds all listeners contained in the passed-in {@code listeners} array.
	 * 
	 * @param listeners the listeners to add
	 */
	public function addAllListeners(listeners:Array):Void;
	
	/**
	 * Removes the passed-in {@code listener}.
	 * 
	 * @param listener the listener to remove
	 */
	public function removeListener(listener):Void;
	
	/**
	 * Removes all added listeners.
	 */
	public function removeAllListeners(Void):Void;
	
	/**
	 * Returns all added listeners.
	 *
	 * @return all added listeners
	 */
	public function getAllListeners(Void):Array;
	
	/**
	 * Returns {@code true} if passed-in {@code listener} has been added.
	 * 
	 * @param listener the listener to check whether it has been added
	 * @return {@code true} if the {@code listener} has been added	 */
	public function hasListener(listener):Boolean;
	
}