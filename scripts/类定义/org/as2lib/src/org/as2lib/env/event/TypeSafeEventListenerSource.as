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
import org.as2lib.env.except.IllegalArgumentException;
import org.as2lib.env.event.EventListenerSource;
import org.as2lib.util.ArrayUtil;

/**
 * {@code TypeSafeEventListenerSource} manages listeners in a type-safe manner.
 * 
 * @author Simon Wacker
 */
class org.as2lib.env.event.TypeSafeEventListenerSource extends BasicClass implements EventListenerSource {
	
	/** The expected listener type. */
	private var t:Function;
	
	/** All added listeners. */
	private var l:Array;
	
	/** Determines whether to check for the correct listener type. */
	private var c:Boolean;
	
	/**
	 * Constructs a new {@code TypeSafeEventListenerSource} instance.
	 *
	 * <p>{@code checkListenerType} is by default set to {@code true}.
	 *
	 * @param listenerType the expected type of listeners
	 * @param checkListenerType determines whether to check that passed-in listeners
	 * are of the expected type
	 * @throws IllegalArgumentException if the passed-in {@code listenerType} is
	 * {@code null} or {@code undefined}
	 */
	public function TypeSafeEventListenerSource(listenerType:Function, checkListenerType:Boolean) {
		if (!listenerType) throw new IllegalArgumentException("Argument 'listenerType' [" + listenerType + "] must not be 'null' nor 'undefined'.", this, arguments);
		this.t = listenerType;
		this.c = checkListenerType == null ? true : checkListenerType;
		this.l = new Array();
	}
	
	/**
	 * Returns the expected listener type.
	 *
	 * @return the expected listener type
	 */
	public function getListenerType(Void):Function {
		return this.t;
	}
	
	/**
	 * Returns whether a listener's type is checked up on the expected listener type.
	 *
	 * @return {@code true} a listener's type is checked else {@code false}
	 */
	public function isListenerTypeChecked(Void):Boolean {
		return this.c;
	}
	
	/**
	 * Adds the passed-in {@code listener}.
	 *
	 * <p>The listener will only be added if it is neither {@code null} nor
	 * {@code undefined} and if it is of the expected listener type specified on
	 * construction and if it has not already been added to this listener source.
	 *
	 * <p>Note that the listener type will not be checked if it was turned of on
	 * construction.
	 * 
	 * @param listener the listener to add
	 * @throws IllegalArgumentException if the passed-in {@code listener} is not of the
	 * expected type specified on construction
	 */
	public function addListener(listener):Void {
		if (listener) {
			if (this.c) {
				if (!(listener instanceof this.t)) {
					throw new IllegalArgumentException("Argument 'listener' [" + listener + "] must be an instance of the expected listener type [" + this.t + "].", this, arguments);
				}
			}
			if (!hasListener(listener)) {
				this.l.push(listener);
			}
		}
	}
	
	/**
	 * Adds all listeners contained in the passed-in {@code listeners} array.
	 *
	 * <p>If the passed-in {@code listeners} array is {@code null} or {@code undefined}
	 * it will be ignored.
	 *
	 * <p>The individual listeners must be instances of the type specified on
	 * construction. If an individual listener is {@code null} or {@code undefined} it
	 * will be ignored.
	 *
	 * <p>All listeners that are of the correct type will be added.
	 * 
	 * <p>Note that the listener type will not be checked if it was turned of on
	 * construction.
	 *
	 * <p>Note also that the order of the listeners contained in the passed-in
	 * {@code listeners} array is preserved.
	 *
	 * @param listeners the listeners to add
	 * @throws IllegalArgumentException if at least one listener in the passed-in
	 * {@code listeners} array is not of the expected type specified on construction
	 * @see #addListener
	 */
	public function addAllListeners(listeners:Array):Void {
		if (listeners) {
			if (this.c) {
				var exceptions:Array;
				var h:Number = listeners.length;
				// the original order of the passed-in 'listeners' is preserved
				for (var i:Number = 0; i < h; i++) {
					try {
						addListener(listeners[i]);
					} catch (e:org.as2lib.env.except.IllegalArgumentException) {
						// this case probably hardly ever occurs; the array is thus only instantiated if
						// really necessary
						if (!exceptions) exceptions = new Array();
						exceptions.push(e);
					}
				}
				if (exceptions) {
					// source this out in own exception; maybe IllegalListenerException?
					var message:String = IllegalArgumentException(exceptions[0]).getMessage();
					for (var k:Number = 1; k < exceptions.length; k++) {
						message += IllegalArgumentException(exceptions[k]).getMessage();
					}
					throw new IllegalArgumentException(message, this, arguments);
				}
			} else {
				var h:Number = listeners.length;
				// the original order of the passed-in 'listeners' is preserved
				for (var i:Number = 0; i < h; i++) {
					addListener(listeners[i]);
				}
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
	 * Returns all added listeners that are of the type specified on construction.
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