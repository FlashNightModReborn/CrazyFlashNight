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

import org.as2lib.env.except.AbstractOperationException;
import org.as2lib.env.event.TypeSafeEventListenerSource;

/**
 * {@code AbstractEventDistributorControl} offers default implementations of
 * methods needed when implementing the {@link EventDistributorControl} interface
 * or any sub-interface.
 * 
 * @author Simon Wacker
 */
class org.as2lib.env.event.distributor.AbstractEventDistributorControl extends TypeSafeEventListenerSource {
	
	/** The distributor to distribute events. */
	private var d;
	
	/**
	 * Constructs a new {@code AbstractEventDistributorControl} instance.
	 *
	 * <p>{@code checkListenerType} is by default set to {@code true}.
	 *
	 * @param listenerType the expected type of listeners
	 * @param checkListenerType determines whether to check that passed-in listeners
	 * are of the expected type
	 * @throws IllegalArgumentException if the passed-in {@code listenerType} is
	 * {@code null} or {@code undefined}
	 */
	public function AbstractEventDistributorControl(listenerType:Function, checkListenerType:Boolean) {
		super (listenerType, checkListenerType);
	}
	
	/**
	 * Returns the type of listeners this distributor expects. This is also the type of
	 * the distributor returned by the {@link #getDistributor} method.
	 * 
	 * @return the type of the distributor and listeners
	 */
	public function getType(Void):Function {
		return t;
	}
	
	/**
	 * Returns the distributor to distribute the event to all added listeners.
	 *
	 * <p>The returned distributor can be casted to the type specified on construction.
	 * You can then invoke the event method on it to distribute it to all added
	 * listeners. This event distribution approach has the advantage of proper
	 * compile-time type-checking.
	 *
	 * <p>The returned distributor throws an {@link EventExecutionException} on
	 * distribution if an event method of a listener threw an exception.
	 * 
	 * <p>This method does always return the same distributor.
	 * 
	 * @return the distributor to distribute the event
	 */
	public function getDistributor(Void) {
		if (!this.d) this.d = createDistributor();
		return this.d;
	}
	
	/**
	 * Creates a new distributor based on the listener type specified on construction.
	 *
	 * <p>The catching of methods called on the returned distributor takes place using
	 * {@code __resolve}. This method then invokes the {@link #distribute} method with
	 * the name of the called method and the arguments used for the method call.
	 * 
	 * @return the new distributor
	 */
	private function createDistributor(Void) {
		var result = new Object();
		var t:Function = getListenerType();
		result.__proto__ = t.prototype;
		result.__constructor__ = t;
		var e:AbstractEventDistributorControl = this;
		//var d:Function = e["distribute"];
		result.__resolve = function(n:String):Function {
			return (function():Void {
				//d.apply(e, n, arguments); causes 255 recursion error
				// e.distribute is not MTASC compatible because "distribute" is private
				e["distribute"](n, arguments);
			});
		};
		var p:Object = t.prototype;
		while (p != Object.prototype) {
			for (var i:String in p) {
				result[i] = function():Void {
					// e.distribute is not MTASC compatible because "distribute" is private
					e["distribute"](arguments.callee.n, arguments);
				};
				result[i].n = i;
			}
			p = p.__proto__;
		}
		return result;
	}
	
	/**
	 * Executes the event with the given {@code eventName} on all added listeners, using
	 * the arguments after {@code eventName} as parameters.
	 * 
	 * @param eventName the name of the event method to execute on the added listeners
	 * @param args any number of arguments that are used as parameters on execution of
	 * the event on the listeners
	 * @throws EventExecutionException if an event method on a listener threw an
	 * exception
	 */
	private function distribute(eventName:String, args:Array):Void {
		throw new AbstractOperationException("This method is marked as abstract and must be overwritten.", this, arguments);
	}
	
}