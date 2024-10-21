
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

import org.as2lib.env.event.EventListenerSource;
import org.as2lib.env.event.distributor.EventDistributorControl;

/**
 * {@code CompositeEventDistributorControl} allows flexible usage of events for complex class models.
 * 
 * <p>The {@link EventDistributorControl} class allows only for handling of one type of
 * listeners while this {@code CompositeEventDistributor} class allows multiple types
 * of listeners to provide more granularity if many different kinds of listeners are
 * used. It holds a collection of accepted types of listeners and checks if the listener
 * added via the {@link #addListener} method matches any of the accepted types and adds
 * it to the correct event distributor control(s). *
 * <p>Class that uses the composites functionalities:
 * <code>
 *   import org.as2lib.env.event.distributor.SimpleConsumableCompositeEventDistributorControl;
 *   
 *   class MyClass extends SimpleConsumableCompositeEventDistributorControl {
 *      
 *     public function MyClass(Void) {
 *       acceptListenerType(MyListener);
 *     }
 *     
 *     public function customMethod(Void):Void {
 *       var e:MyListener = getDistributor(MyListener);
 *       e.onEvent("1", "2");
 *     }
 *      
 *   }
 * </code>
 * 
 * <p>Listener interface:
 * <code>
 *   interface MyListener {
 *     
 *     public function onEvent(contentA:String, contentB:String):Void;
 *     
 *   }
 * </code>
 * 
 * <p>Listener interface implementation:
 * <code>
 *   class SimpleMyListener implements MyListener {
 *     
 *     private var prefix:String;
 *     
 *     public function SimpleMyListener(prefix:String) {
 *       this.prefix = prefix;
 *     }
 *     
 *     public function onEvent(contentA:String, contentB:String):Void {
 *       trace(prefix + contentA + ", " + prefix + contentB);
 *     }
 *     
 *   }
 * </code>
 * 
 * <p>Usage:
 * <code>
 *   var myClass:MyClass = new MyClass();
 *   myClass.addListener(new SimpleMyListener("a"));
 *   myClass.addListener(new SimpleMyListener("b"));
 *   // traces "a1, a2" and "b1, b2";
 *   myClass.customMethod();
 *   
 *   // throws an exception because listeners of type "Array" are not accepted
 *   myClass.addListener(new Array());
 * </code>
 * 
 * @author Martin Heidegger
 */
interface org.as2lib.env.event.distributor.CompositeEventDistributorControl extends EventListenerSource {
	
	/**
	 * Returns the distributor for the given {@code type} that can be used to distribute
	 * events to all added listeners of the given {@code type}.
	 * 
	 * <p>The returned distributor can be casted to the given {@code type} (type-safe
	 * distribution of events).
	 * 
	 * @return the distributor to distribute events	 */
	public function getDistributor(type:Function);
	
	/**
	 * Specifies that listeners of the given {@code type} are accepted, this includes
	 * implementations of the given {@code type} as well as its sub-classes.
	 * 
	 * <p>{@code addListener} does not allow listeners that do not match (instanceof)
	 * at least one accepted listener type.
	 * 
	 * @param listenerType the type of listeners that can be added
	 */
	public function acceptListenerType(listenerType:Function):Void;
	
	/**
	 * Registers the given {@code eventDistributorControl} with its listener and
	 * distributor type returned by its {@link EventDistributorControl#getType} method.
	 * 
	 * <p>If there is already a distributor control registered for the given type, it
	 * will be overwritten.
	 * 
	 * <p>You use this method if you have a specific event that should be executed with
	 * a special kind of distributor, for example with a consumable one.
	 * 
	 * @param eventDistributorControl the event distributor control to use for event
	 * distribution for the given type
	 * @see #setDefaultEventDistributorControl	 */
	public function registerEventDistributorControl(eventDistributorControl:EventDistributorControl):Void;
	
	/**
	 * Registers a default event distributor control with the given listener and
	 * distributor type.
	 * 
	 * <p>If there is already a distributor control registered for the given type, it
	 * will be overwritten.
	 * 
	 * @param type the type to register a default distributor control with	 */
	public function registerDefaultEventDistributorControl(type:Function):Void;
	
}