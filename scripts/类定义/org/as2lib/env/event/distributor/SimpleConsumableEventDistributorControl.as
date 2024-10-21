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
import org.as2lib.env.event.distributor.ConsumableEventDistributorControl;

/**
 * {@code SimpleConsumableEventDistributorControl} acts as a listener source and
 * event distributor. It enables you to distribute and handle events in the safest
 * way possible.
 * 
 * <p>Note that unlike the {@link SimpleEventDistributorControl} class, this class
 * supports the consumption of events. An event is consumed if an event method on a
 * listener returns {@code true}. This means that the distribution of the event will
 * be stopped immediately. Otherwise the event will further be distributed.
 * 
 * <p>Example:
 * <code>
 *   // creates a distributor control with the expected listener type
 *   var distributorControl:SimpleConsumableEventDistributorControl = new SimpleConsumableEventDistributorControl(ErrorListener);
 *   // adds new listeners that must be of the expected type
 *   distributorControl.addListener(new MyErrorListener());
 *   distributorControl.addListener(new SimpleErrorListener());
 *   // gets a distributor to distribute the event to all listeners
 *   var distributor:ErrorListener = ErrorListener(distributorControl.getDistributor());
 *   // distributes the event with custom arguments
 *   distributor.onError(myErrorCode, myException);
 * </code>
 *
 * <p>If in the above example, the {@code MyErrorListener.onError} method returns
 * {@code true}, the {@code SimpleErrorListener.onError} method will not be invoked
 * because the event is consumed.
 * 
 * @author Simon Wacker
 * @authro Martin Heidegger
 */
class org.as2lib.env.event.distributor.SimpleConsumableEventDistributorControl extends AbstractEventDistributorControl implements ConsumableEventDistributorControl {
	
	/**
	 * Constructs a new {@code SimpleConsumableEventDistributorControl} instance.
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
	public function SimpleConsumableEventDistributorControl(listenerType:Function, checkListenerType:Boolean, listeners:Array) {
		super (listenerType, checkListenerType);
		if (listeners) {
			addAllListeners(listeners);
		}
	}
	
	/**
	 * Executes the event with the given {@code eventName} on all added listeners, using
	 * the arguments after {@code eventName} as parameters.
	 *
	 * <p>If {@code eventName} is {@code null} or {@code undefined} the distribution
	 * will be omited.
	 *
	 * <p>The distribution will be stopped immediately if an event method of a listener
	 * returns {@code true} and thus consumes the event.
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
				var h:Number = this.l.length;
				var i:Number;
				try {
					for (i = 0; i < h; i++) {
						// check "true" explicitely because only an object or something similar
						// does not suffice, but would also result in "true" for the if-statement
						if (this.l[i][eventName].apply(this.l[i], args) == true) {
							return;
						}
					}
				} catch (e) {
					// "new EventExecutionException" without braces is not MTASC compatible because of the following method call to "initCause"
					throw (new EventExecutionException("Unexpected exception was thrown during distribution of event [" + eventName + "] on listener [" + this.l[i] + "] with arguments [" + args + "].", this, arguments)).initCause(e);
				}
			}
		}
	}
	
}