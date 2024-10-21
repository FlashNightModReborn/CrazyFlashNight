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

import org.as2lib.env.except.IllegalArgumentException;
import org.as2lib.env.event.EventExecutionException;
import org.as2lib.env.event.SimpleEventListenerSource;
import org.as2lib.env.event.multicaster.ConsumableEventMulticaster;

/**
 * {@code SimpleConsumableEventMulticaster} multicasts an event to all added listeners with
 * custom arguments until the event is consumed.
 *
 * <p>Example:
 * <code>
 *   // creates a multicaster for the 'onError' event
 *   var multicaster:SimpleConsumableEventMulticaster = new SimpleConsumableEventMulticaster("onError");
 *   // adds listeners
 *   multicaster.addListener(new SimpleErrorListener());
 *   multicaster.addListener(new MyErrorListener());
 *   // executes the specified event on all listeners passing the given arguments
 *   multicaster.dispatch(myErrorCode, myException);
 * </code>
 *
 * <p>The event dispatch is stopped as soon as any of the above listeners returns
 * {@code true}. If for example the {@code SimpleErrorListener.onError} method
 * returns {@code true}, {@code MyErrorListener.onError} will not be executed
 * because the event is consumed.
 * 
 * @author Simon Wacker
 */
class org.as2lib.env.event.multicaster.SimpleConsumableEventMulticaster extends SimpleEventListenerSource implements ConsumableEventMulticaster {
	
	/** The name of the event. */
	private var eventName:String;
	
	/**
	 * Constructs a new {@code SimpleConsumableEventMulticaster} instance.
	 * 
	 * @param eventName the name of the event to execute on listeners
	 * @param listeners (optional) an array of listeners to populate this broadcaster
	 * with
	 * @throws IllegalArgumentException if passed-in {@code eventName} is {@code null},
	 * {@code undefined} or an empty string
	 */
	public function SimpleConsumableEventMulticaster(eventName:String, listeners:Array) {
		if (!eventName) throw new IllegalArgumentException("Argument 'eventName' [" + eventName + "] must not be 'null' nor 'undefined'.", this, arguments);
		this.eventName = eventName;
		if (listeners) {
			addAllListeners(listeners);
		}
	}
	
	/**
	 * Returns the event name set on construction.
	 *
	 * @return the name of the event
	 */
	public function getEventName(Void):String {
		return this.eventName;
	}
	
	/**
	 * Dispatches the event to all listeners passing the given arguments as parameters
	 * to the listeners' event methods until a listener consumes the event by returning
	 * {@code true}.
	 * 
	 * @param .. any number of arguments to pass to the listeners' event methods
	 * @throws EventExecutionException if a listener's event method threw an exception
	 */
	public function dispatch():Void {
		var i:Number = this.l.length;
		if (i > 0) {
			var k:Number;
			try {
				for (k = 0; k < i; k++) {
					// explicit check whether the return value is true; returning any kind of object
					// would otherwise also result in true if "== true" was omitted
					if (this.l[k][eventName].apply(this.l[k], arguments) == true) {
						return;
					}
				}
			} catch (e) {
				// "new EventExecutionException" without braces is not MTASC compatible because of the following method call to "initCause"
				throw (new EventExecutionException("Unexpected exception was thrown during dispatch of event [" + this.eventName + "] on listener [" + this.l[k] + "] with arguments [" + arguments + "].", this, arguments)).initCause(e);
			}
		}
	}
	
}