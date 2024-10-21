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

import org.as2lib.env.event.EventExecutionException;
import org.as2lib.env.event.distributor.AbstractEventDistributorControl;
import org.as2lib.env.event.distributor.EventDistributorControl;

/**
 * {@code SimpleEventDistributorControl} acts as a listener source and event
 * distributor control. It enables you to distribute and handle events in the
 * safest way possible by providing a compiler-safe distributor.
 * 
 * <p>Example:
 * <code>
 *   // creates a distributor control with the expected listener type
 *   var distributorControl:SimpleEventDistributorControl = new SimpleEventDistributorControl(ErrorListener);
 *   // adds new listeners that must be of the expected type
 *   distributorControl.addListener(new MyErrorListener());
 *   distributorControl.addListener(new SimpleErrorListener());
 *   // gets a distributor to distribute the event to all listeners
 *   var distributor:ErrorListener = ErrorListener(distributorControl.getDistributor());
 *   // distributes the event with custom arguments
 *   distributor.onError(myErrorCode, myException);
 * </code>
 * 
 * @author Simon Wacker
 * @author Martin Heidegger
 */
class org.as2lib.env.event.distributor.SimpleEventDistributorControl extends AbstractEventDistributorControl implements EventDistributorControl {
	
	/** The wrapped {@code AsBroadcaster} needed for actual distribution. */
	private var b;
	
	/**
	 * Constructs a new {@code SimpleEventDistributorControl} instance.
	 *
	 * <p>{@code checkListenerType} is by default set to {@code true}.
	 * 
	 * @param listenerType the expected type of listeners
	 * @param checkListenerType determines whether to check that passed-in listeners
	 * are of the expected type
	 * @param listeners (optional) the listeners to add
	 * @throws IllegalArgumentException if the passed-in {@code listenerType} is
	 * {@code null} or {@code undefined}
	 */
	public function SimpleEventDistributorControl(listenerType:Function, checkListenerType:Boolean, listeners:Array) {
		super (listenerType, checkListenerType);
		this.b = new Object();
		AsBroadcaster.initialize(this.b);
		this.b._listeners = this.l;
		if (listeners) {
			addAllListeners(listeners);
		}
	}
	
	/**
	 * Removes all added listeners.
	 */
	public function removeAllListeners(Void):Void {
		super.removeAllListeners();
		this.b._listeners = this.l;
	}
	
	/**
	 * Executes the event with the given {@code eventName} on all added listeners, using
	 * the arguments after {@code eventName} as parameters.
	 *
	 * <p>If {@code eventName} is {@code null} or {@code undefined} the distribution
	 * will be omited.
	 *
	 * <p>If {@code args} is {@code null} or {@code undefined} nor parameters will be
	 * passed to the listeners' event methods.
	 * 
	 * @param eventName the name of the event method to execute on the added listeners
	 * @param args any number of arguments that are used as parameters on execution of
	 * the event on the listeners
	 * @throws EventExecutionException if an event method on a listener threw an
	 * exception
	 */
	private function distribute(eventName:String, args:Array):Void {
		if (eventName != null) {
			if (this.l.length > 0) {
				try {
					this.b.broadcastMessage.apply(this.b, [eventName].concat(args));
				} catch (e) {
					// "new EventExecutionException" without braces is not MTASC compatible because of the following method call to "initCause"
					throw (new EventExecutionException("Unexpected exception was thrown during distribution of event [" + eventName + "].", this, arguments)).initCause(e);
				}
			}
		}
	}
	
}