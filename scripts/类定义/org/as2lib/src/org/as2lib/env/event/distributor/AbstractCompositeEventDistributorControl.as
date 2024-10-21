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

import org.as2lib.util.ArrayUtil;
import org.as2lib.env.reflect.ReflectUtil;
import org.as2lib.data.holder.Map;
import org.as2lib.data.holder.map.HashMap;
import org.as2lib.env.except.IllegalArgumentException;
import org.as2lib.env.event.distributor.CompositeEventDistributorControl;
import org.as2lib.env.event.distributor.EventDistributorControl;
import org.as2lib.env.event.distributor.EventDistributorControlFactory;

/**
 * {@code AbstractCompositeEventDistributorControl} is the default implementation
 * of the {@code CompositeEventDistributorControl} interface.
 * 
 * <p>To use its functionalities, simply extend it and set a factory for the default
 * event distributors.
 * 
 * @author Martin Heidegger
 */
class org.as2lib.env.event.distributor.AbstractCompositeEventDistributorControl implements CompositeEventDistributorControl {
	
	/* Factory to create default event distributors for the different types */
	private var eventDistributorControlFactory:EventDistributorControlFactory;
	
	/* All added listeners. */
	private var listeners:Array;
	
	/* All available {@code EventDistributorControl} instances mapped to classes and interfaces. */
	private var distributorMap:Map;
	
	/**
	 * Creates a new {@code AbstractCompositeEventDistributorControl} instance.
	 * 
	 * @param eventDistributorControlFactory the factory to create event distributor
	 * controls for the different listener types	 */
	public function AbstractCompositeEventDistributorControl(eventDistributorControlFactory:EventDistributorControlFactory) {
		this.eventDistributorControlFactory = eventDistributorControlFactory;
		distributorMap = new HashMap();
		listeners = new Array();
	}
	
	/**
	 * Adds a the given listener to this event distributor control.
	 * 
	 * <p>It validates if the passed-in {@code listener} is of any of the accepted
	 * listener types.
	 * 
	 * <p>The listener will be added to all matching distributors.
	 * 
	 * @param l the Listener to add to the control
	 * @throws IllegalArgumentException if the given listener does not match any of the
	 * accepted types.	 */
	public function addListener(l):Void {
		if (!hasListener(l)) {
			var acceptedTypes:Array = distributorMap.getKeys();
			var existingDistributors:Array = distributorMap.getValues();
			var added:Boolean = false;
			for (var i:Number = 0; i < acceptedTypes.length; i++) {
				if (l instanceof acceptedTypes[i]) {
					existingDistributors[i].addListener(l);
					added = true;
				}
			}
			if (added) {
				listeners.push(l);
			} else {
				var message:String = "The passed-in listener [" + ReflectUtil.getTypeNameForInstance(l) + "] does not match any of the accepted listener types.";
				var size:Number = distributorMap.size();
				if (size > 0) {
					message += "(" + size + "):";
					for (var i:Number = 0; i < size; i++) {
						message += "\n - " + ReflectUtil.getTypeNameForType(acceptedTypes[i]);
					}
				} else {
					message += "(No types accepted).";
				}
				throw new IllegalArgumentException(message, this, arguments);
			}
		}
	}
	
	/**
	 * Removes the given listener from this distributor control and thus from listening
	 * to events.
	 * 
	 * @param l the listener to remove	 */
	public function removeListener(l):Void {
		if (hasListener(l)) {
			var acceptedTypes:Array = distributorMap.getKeys();
			var existingDistributors:Array = distributorMap.getValues();
			for (var i:Number = 0; i < acceptedTypes.length; i++) {
				if (l instanceof acceptedTypes[i]) {
					existingDistributors[i].removeListener(l);
				}
			}
			ArrayUtil.removeElement(listeners, l);
		}
	}
	
	/**
	 * Adds a list of listeners to this event distributor control to listen to events.
	 * 
	 * @param listeners the list of listeners to add
	 * @throws IllegalArgumentException if any listener is not accepted (the listeners
	 * before the certain listener will be added) 	 */
	public function addAllListeners(listeners:Array):Void {
		for (var i:Number = 0; i < listeners.length; i++) {
			addListener(listeners[i]);
		}
	}
	
	/**
	 * Removes all added listeners.	 */
	public function removeAllListeners(Void):Void {
		var list:Array = getAllListeners();
		for (var i:Number = 0; i < list.length; i++) {
			removeListener(list[i]);
		}
	}
	
	/**
	 * Returns a list that contains all listeners.
	 * 
	 * @return the list that contains all listeners	 */
	public function getAllListeners(Void):Array {
		return listeners.concat();
	}
	
	/**
	 * Checks if the given listener has already been added.
	 * 
	 * @param l the listener to check whether it has already been added
	 * @return {@code true} if the listener has been added	 */
	public function hasListener(l):Boolean {
		return ArrayUtil.contains(listeners, l);
	}
	
	/**
	 * Adds acception for the given {@code listenerType}.
	 * 
	 * <p>{@code addListener} does not allow listeners that do not match (instanceof)
	 * at least one of the accepted listener types.
	 * 
	 * @param type the type of listeners that are accepted
	 * @see #registerEventDistributorControl
	 * @see #registerDefaultEventDistributorControl
	 */
	public function acceptListenerType(listenerType:Function):Void {
		if (!distributorMap.containsKey(listenerType)) {
			var distributor:EventDistributorControl = eventDistributorControlFactory.createEventDistributorControl(listenerType);
			for (var i:Number = 0; i < listeners.length; i++) {
				if (listeners[i] instanceof listenerType) {
					distributor.addListener(listeners[i]);
				}
			}
			distributorMap.put(listenerType, distributor);
		}
	}
	
	/**
	 * Returns the distributor that can be used to broadcast an event to all added
	 * listeners that match the distributor's type.
	 * 
	 * <p>If the given {@code type} has not been accepted as listener type yet, it will
	 * be accepted after you invoked this method.
	 * 
	 * <p>Note that the returned distributor will not be updated if you add a new
	 * distributor control for the given {@code type} after you obtained a distributor.
	 * You must get a new distributor if you want an updated one.
	 * 
	 * @return the distributor to distribute events
	 */
	public function getDistributor(type:Function) {
		if (!distributorMap.containsKey(type)) {
			acceptListenerType(type);
		}
		var distributor:EventDistributorControl = distributorMap.get(type);
		return distributor.getDistributor();
	}
	
	/**
	 * Registers the given {@code eventDistributorControl} with its listener and
	 * distributor type returned by its {@link EventDistributorControl#getType} method.
	 * 
	 * <p>The type is then automatically an accepted listener type.
	 * 
	 * <p>If there is already a distributor control registered for the given type, it
	 * will be overwritten.
	 * 
	 * <p>If you hold references to distributors of this type, returned by the
	 * {@link #getDistributor} method, you will have to update them, else events will
	 * not be distributed to newly registered listeners of that type.
	 * 
	 * <p>You use this method if you have a specific event that should be executed with
	 * a special kind of distributor, for example with a consumable one.
	 * 
	 * @param eventDistributorControl the event distributor control to use for event
	 * distribution for the given type
	 * @throws IllegalArgumentException if the given argument {@code eventDistributorControl}
	 * is {@code null} or {@code undefined}
	 * @see #registerDefaultEventDistributorControl
	 * @see #acceptListenerType
	 */
	public function registerEventDistributorControl(eventDistributorControl:EventDistributorControl):Void  {
		if (!eventDistributorControl) throw new IllegalArgumentException("Argument 'eventDistributorControl' [" + eventDistributorControl + "] must neither be 'null' nor 'undefined'.", this, arguments);
		var type:Function = eventDistributorControl.getType();
		eventDistributorControl.removeAllListeners();
		for (var i:Number = 0; i < listeners.length; i++) {
			if (listeners[i] instanceof type) {
				eventDistributorControl.addListener(listeners[i]);
			}
		}	
		distributorMap.put(type, eventDistributorControl);
	}
	
	/**
	 * Registers a default event distributor control with the given listener and
	 * distributor {@code type}.
	 * 
	 * <p>The {@code type} is then automatically an accepted listener type.
	 * 
	 * <p>If there is already a distributor control registered for the given type, it
	 * will be overwritten.
	 * 
	 * @param type the type to register a default distributor control with
	 * @throws IllegalArgumentException if argument {@code type} is {@code null} or
	 * {@code undefined}
	 * @see #acceptListenerType
	 */
	public function registerDefaultEventDistributorControl(type:Function):Void {
		if (!type) throw new IllegalArgumentException("Argument 'type' [" + type + "] must neither be 'null' nor 'undefined'.", this, arguments);
		registerEventDistributorControl(eventDistributorControlFactory.createEventDistributorControl(type));
	}
	
}