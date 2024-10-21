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
import org.as2lib.util.ClassUtil;
import org.as2lib.env.reflect.ReflectUtil;
import org.as2lib.env.except.IllegalArgumentException;
import org.as2lib.env.except.IllegalStateException;
import org.as2lib.env.event.broadcaster.EventBroadcasterFactory;
import org.as2lib.env.event.broadcaster.EventBroadcaster;

/**
 * {@code DynamicEventBroadcasterFactory} creates and returns any kind of event
 * broadcaster. The specific event broadcaster class can be specified on construction
 * or with the {@link #setEventBroadcasterClass} method.
 * 
 * @author Martin Heidegger
 */
class org.as2lib.env.event.broadcaster.DynamicEventBroadcasterFactory extends BasicClass implements EventBroadcasterFactory {
	
	/** The event broadcaster class to return instances of. */
	private var clazz:Function;
	
	/**
	 * Constructs a new {@code DynamicEventBroadcasterFactory} instance.
	 *
	 * @param clazz the {@link EventBroadcaster} implementation to return instances of
	 */
	public function DynamicEventBroadcasterFactory(clazz:Function) {
		setEventBroadcasterClass(clazz);
	}
	
	/**
	 * Sets the {@link EventBroadcaster} implementation to return instances of.
	 * 
	 * @param clazz the {@link EventBroadcaster} implementation to return instances of
	 * @throws IllegalArgumentException if the passed-in {@code clazz} is not an
	 * implementation of the {@code EventBroadcaster} interface
	 */
	public function setEventBroadcasterClass(clazz:Function) {
		if (!ClassUtil.isImplementationOf(clazz, EventBroadcaster)){
			var className:String = ReflectUtil.getTypeNameForType(clazz);
			if (!className) className = "unknown";
			throw new IllegalArgumentException("Argument 'clazz' [" + clazz + ":" + className + "] is not an implementation of the 'org.as2lib.env.event.EventBroadcaster' interface.", this, arguments);
		}
		this.clazz = clazz;
	}
	
	/**
	 * Creates and returns a new instance of a the specified class.
	 * 
	 * @return a new instance of the specified class
	 * @throws IllegalStateException if no class to return instances of has been set
	 * yet
	 */
	public function createEventBroadcaster(Void):EventBroadcaster {
		if (!clazz) {
			throw new IllegalStateException("A class to instantiate must be set before invoking this method.", this, arguments);
		}
		return new clazz();
	}
	
}