
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

import org.as2lib.data.holder.Map;
import org.as2lib.data.holder.Iterator;
import org.as2lib.core.BasicClass;
import org.as2lib.util.ObjectUtil;
import org.as2lib.env.except.IllegalArgumentException;
import org.as2lib.env.reflect.ReflectUtil;

/**
 * {@code TypedMap} is a wrapper for {@link Map} instances that ensures that only
 * values of a specific type are added to the wrapped map.
 * 
 * <p>This class simply delegates all method invocations to the wrapped map. If the
 * specific method is responsible for adding values it first checks if the values
 * to add are of the expected type. If they are the method invocation is forwarded,
 * otherwise an {@link IllegalArgumentException} is thrown.
 *
 * @author Simon Wacker
 */
class org.as2lib.data.holder.map.TypedMap extends BasicClass implements Map {
	
	/** The wrapped map. */
	private var map:Map;
	
	/** The type of values that can be added. */
	private var type:Function;
	
	/**
	 * Constructs a new {@code TypedMap} instance.
	 *
	 * <p>If the passed-in {@code map} does already contain values, these values do not
	 * get type-checked.
	 * 
	 * @param type the type of the values this map is allowed to contain
	 * @param map the map to type-check
	 * @throws IllegalArgumentException if the passed-in {@code type} is {@code null}
	 * or {@code undefined}
	 * @throws IllegalArgumentException if {@code map} is {@code null} or
	 * {@code undefined}
	 */
	public function TypedMap(type:Function, map:Map) {
		if (!type) throw new IllegalArgumentException("Argument 'type' [" + type + "] must not be 'null' nor 'undefined'.", this, arguments);
		if (!map) throw new IllegalArgumentException("Argument 'map' [" + map + "] must not be 'null' nor 'undefined'.", this, arguments);
		this.type = type;
		this.map = map;
	}
	
	/**
	 * Returns the type that all values in the wrapped map have.
	 * 
	 * <p>This is the type passed-in on construction.
	 *
	 * @return the type that all values in the wrapped map have
	 */
	public function getType(Void):Function {
		return type;
	}
	
	/**
	 * Checks if the passed-in {@code key} exists.
	 *
	 * <p>That means whether a value has been mapped to it.
	 *
	 * @param key the key to be checked for availability
	 * @return {@code true} if the {@code key} exists else {@code false}
	 */
	public function containsKey(key):Boolean {
		return map.containsKey(key);
	}
	
	/**
	 * Checks if the passed-in {@code value} is mapped to a key.
	 *
	 * @param value the value to be checked for availability
	 * @return {@code true} if the {@code value} is mapped to a key else {@code false}
	 */
	public function containsValue(value):Boolean {
		return map.containsValue(value);
	}
	
	/**
	 * Returns an array that contains all keys that have a value mapped to it.
	 * 
	 * @return an array that contains all keys
	 */
	public function getKeys(Void):Array {
		return map.getKeys();
	}
	
	/**
	 * Returns an array that contains all values that are mapped to a key.
	 *
	 * @return an array that contains all mapped values
	 */
	public function getValues(Void):Array {
		return map.getValues();
	}
	
	/**
	 * Returns the value that is mapped to the passed-in {@code key}.
	 *
	 * @param key the key to return the corresponding value for
	 * @return the value corresponding to the {@code key}
	 */
	public function get(key) {
		return map.get(key);
	}
	
	/**
	 * Maps the given {@code key} to the {@code value}.
	 *
	 * @param key the key used as identifier for the {@code value}
	 * @param value the value to map to the {@code key}
	 * @return the value that was originally mapped to the {@code key}
	 * @throws IllegalArgumentException if the type of the passed-in {@code value} is
	 * invalid
	 */
	public function put(key, value) {
		validate(value);
		return map.put(key, value);
	}
	
	/**
	 * Copies all mappings from the passed-in {@code map} to this map.
	 *
	 * <p>If one value in the given {@code map} is invalid, no key-value pair will be
	 * added.
	 * 
	 * @param map the mappings to add to this map
	 * @throws IllegalArgumentException if the type of any value to put is invalid
	 */
	public function putAll(map:Map):Void {
		var array:Array = map.getValues();
		for (var i:Number = 0; i < array.length; i++) {
			validate(array[i]);
		}
		this.map.putAll(map);
	}
	
	/**
	 * Removes the mapping from the specified {@code key} to the value.
	 *
	 * @param key the key identifying the mapping to remove
	 * @return the value that was originally mapped to the {@code key}
	 */
	public function remove(key) {
		return map.remove(key);
	}
	
	/**
	 * Clears all mappings.
	 */
	public function clear(Void):Void {
		map.clear();
	}
	
	/**
	 * Returns an iterator to iterate over the values of this map.
	 *
	 * @return an iterator to iterate over the values of this map
	 * @see #valueIterator
	 * @see #getValues
	 */
	public function iterator(Void):Iterator {
		return map.iterator();
	}
	
	/**
	 * Returns an iterator to iterate over the values of this map.
	 *
	 * @return an iterator to iterate over the values of this map
	 * @see #iterator
	 * @see #getValues
	 */
	public function valueIterator(Void):Iterator {
		return map.valueIterator();
	}
	
	/**
	 * Returns an iterator to iterate over the keys of this map.
	 *
	 * @return an iterator to iterate over the keys of this map
	 * @see #getKeys
	 */
	public function keyIterator(Void):Iterator {
		return map.keyIterator();
	}
	
	/**
	 * Returns the amount of mappings.
	 *
	 * @return the amount of mappings
	 */
	public function size(Void):Number {
		return map.size();
	}
	
	/**
	 * Returns whether this map contains any mappings.
	 *
	 * @return {@code true} if this map contains no mappings else {@code false}
	 */
	public function isEmpty(Void):Boolean {
		return map.isEmpty();
	}
	
	/**
	 * Returns the string representation of the wrapped map.
	 *
	 * @return the string representation of the wrapped map
	 */
	public function toString():String {
		return map.toString();
	}
	
	/**
	 * Validates the passed-in {@code value} based on its type.
	 * 
	 * @param value the value whose type to validate
	 * @throws IllegalArgumentException if the type of the passed-in {@code value} is
	 * not valid
	 */
	private function validate(value):Void {
		if (!ObjectUtil.typesMatch(value, type)) {
			throw new IllegalArgumentException("Type mismatch between value [" + value + "] and type [" + ReflectUtil.getTypeNameForType(type) + "].", this, arguments);
		}
	}
	
}