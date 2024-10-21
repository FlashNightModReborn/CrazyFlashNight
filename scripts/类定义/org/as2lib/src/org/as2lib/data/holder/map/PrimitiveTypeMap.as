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
import org.as2lib.data.holder.map.AbstractMap;
import org.as2lib.data.holder.map.ValueMapIterator;
import org.as2lib.data.holder.map.KeyMapIterator;

/**
 * {@code PrimitiveTypeMap} can be used to map any primitive type key to any type
 * of value.
 * 
 * <p>Primitive data types are strings, numbers and booleans. When you use this map
 * you normally use it in conjunction with string keys, because you can use arrays
 * for numbers and for booleans you normally do not need a data holder at all.
 *
 * <p>Note that if you only want to map values to keys you can also do this using a
 * dynamic or untyped object. But if you also want to be able to iterate over your
 * keys and values in the correct order or if you want this iteration to be fast -
 * the for..in loop is quite slow - you should use this map.
 * 
 * <p>This class offers ordered mapping functionality. That means that the methods
 * {@link #getKeys} and {@link #getValues} return the keys and values in the order
 * they were put to the map and that the iterators returned by the methods
 * {@link #valueIterator} and {@link #keyIterator} also iterate over the keys and
 * values in the correct order.
 *
 * <p>This map offers two methods that help you find out whether it contains a
 * specific key or value. These two methods are {@link #containsKey} and
 * {@link #containsValue}.
 * 
 * <p>To get the data stored in this map you can use the {@link #getKeys},
 * {@link #getValues} and {@link #get} methods. If you want to iterate over the
 * values of this map you can use the iterators returned by the methods {@link #iterator}
 * or {@link #valueIterator}. If you want to iterate over the keys you can use the
 * iterator returned by the {@link #keyIterator} method.
 *
 * <p>To add key-value pairs to this map you can use the methods {@link #put} and
 * {@link #putAll}. The {@code putAll} method lets you add all key-value pairs
 * contained in the passed-in {@code map} to this map.
 * 
 * <p>To remove key-value pairs you can use the methods {@link #remove} and
 * {@link #clear}. The {@code remove} method deletes only the key-value pair
 * corresponding to the passed-in {@code key}, while the clear method removes all
 * key-value pairs.
 *
 * <p>There are two more methods you may need. The {@link #isEmpty} and the {@link #size}
 * method. These methods give you information about whether this map contains any
 * mappings and how many mappings it contains.
 *
 * <p>To change the string representation returned by the {@link #toString}
 * method you can set your own stringifier using the static
 * {@link AbstractMap#setStringifier} method.
 *
 * <p>Example:
 * <code>
 *   // constructs the map
 *   var map:Map = new PrimitiveTypeMap();
 *   map.put("key1", "value1");
 *   map.put("key2", "value2");
 *   map.put("key3", "value3");
 *   // uses the map
 *   trace(map.get("key1"));
 *   trace(map.get("key2"));
 *   trace(map.get("key3"));
 * </code>
 *
 * <p>Output:
 * <pre>
 *   value1
 *   value2
 *   value3
 * </pre>
 *
 * @author Simon Wacker
 */
class org.as2lib.data.holder.map.PrimitiveTypeMap extends AbstractMap implements Map {

	/** Makes the static variables of the super-class accessible through this class. */
	private static var __proto__:Function = AbstractMap;
	
	/** Contains the mappings. */
	private var map:Object;
	
	/** The key-index pairs. */
	private var indexMap:Object;
	
	/** The keys stored in an array. */
	private var keys:Array;
	
	/** The values stored in an array. */
	private var values:Array;
	
	/**
	 * Constructs a new {@code PrimitiveTypeMap} instance.
	 *
	 * <p>This map iterates over the passed-in {@code source} with the for..in loop and
	 * uses the variables' names as key and their values as value. Variables that are
	 * hidden from for..in loops will not be added to this map.
	 * 
	 * @param source (optional) an object that contains key-value pairs to populate this
	 * map with
	 */
	public function PrimitiveTypeMap(source) {
		map = new Object();
		indexMap = new Object();
		indexMap.__proto__ = undefined;
		keys = new Array();
		values = new Array();
		populate(source);
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
		return (map[key] != undefined);
	}
	
	/**
	 * Checks if the passed-in {@code value} is mapped to a key.
	 *
	 * @param value the value to be checked for availability
	 * @return {@code true} if the {@code value} is mapped to a key else {@code false}
	 */
	public function containsValue(value):Boolean {
		var i:Number = keys.length;
		while (--i-(-1)) {
			if (values[i] == value) {
				return true;
			}
		}
		return false;
	}
	
	/**
	 * Returns an array that contains all keys that have a value mapped to it.
	 * 
	 * @return an array that contains all keys
	 */
	public function getKeys(Void):Array {
		return keys.concat();
	}
	
	/**
	 * Returns an array that contains all values that are mapped to a key.
	 *
	 * @return an array that contains all mapped values
	 */
	public function getValues(Void):Array {
		return values.concat();
	}
	
	/**
	 * Returns the value that is mapped to the passed-in {@code key}.
	 *
	 * @param key the key to return the corresponding value for
	 * @return the value corresponding to the passed-in {@code key}
	 */
	public function get(key) {
		return map[key];
	}
	
	/**
	 * Maps the given {@code key} to the {@code value}.
	 *
	 * <p>{@code null} and {@code undefined} values are allowed.
	 *
	 * @param key the key used as identifier for the {@code value}
	 * @param value the value to map to the {@code key}
	 * @return the value that was originally mapped to the {@code key} or {@code undefined}
	 */
	public function put(key, value) {
		var result;
		var i:Number = indexMap[key];
		if (i == undefined) {
			indexMap[key] = keys.push(key) - 1;
			values.push(value);
		} else {
			result = values[i];
			values[i] = value;
		}
		map[key] = value;
		return result;
	}
	
	/**
	 * Copies all mappings from the passed-in {@code map} to this map.
	 *
	 * @param map the mappings to add to this map
	 */
	public function putAll(map:Map):Void {
		var values:Array = map.getValues();
		var keys:Array = map.getKeys();
		var l:Number = keys.length;
		for (var i:Number = 0; i < l; i = i-(-1)) {
			put(keys[i], values[i]);
		}
	}
	
	/**
	 * Removes the mapping from the given {@code key} to the value.
	 *
	 * @param key the key identifying the mapping to remove
	 * @return the value that was originally mapped to the {@code key}
	 */
	public function remove(key) {
		var result;
		var i:Number = indexMap[key];
		if (i != undefined) {
			result = values[i];
			map[key] = undefined;
			indexMap[key] = undefined;
			keys.splice(i, 1);
			values.splice(i, 1);
			// restore indexes in indexMap
			for (var k:Number = i; k < keys.length; k++) {
				indexMap[keys[k]]--;
			}
		}
		return result;
	}
	
	/**
	 * Clears all mappings.
	 */
	public function clear(Void):Void {
		map = new Object();
		indexMap = new Object();
		indexMap.__proto__ = undefined;
		keys = new Array();
		values = new Array();
	}
	
	/**
	 * Returns an iterator to iterate over the values of this map.
	 *
	 * @return an iterator to iterate over the values of this map
	 * @see #valueIterator
	 * @see #getValues
	 */
	public function iterator(Void):Iterator {
		return (new ValueMapIterator(this));
	}
	
	/**
	 * Returns an iterator to iterate over the values of this map.
	 *
	 * @return an iterator to iterate over the values of this map
	 * @see #iterator
	 * @see #getValues
	 */
	public function valueIterator(Void):Iterator {
		return iterator();
	}
	
	/**
	 * Returns an iterator to iterate over the keys of this map.
	 *
	 * @return an iterator to iterate over the keys of this map
	 * @see #getKeys
	 */
	public function keyIterator(Void):Iterator {
		return new KeyMapIterator(this);
	}

	/**
	 * Returns the amount of mappings.
	 *
	 * @return the amount of mappings
	 */
	public function size(Void):Number {
		return keys.length;
	}
	
	/**
	 * Returns whether this map contains any mappings.
	 *
	 * @return {@code true} if this map contains no mappings else {@code false}
	 */
	public function isEmpty(Void):Boolean {
		return (size() < 1);
	}
	
	/**
	 * Returns the string representation of this map.
	 * 
	 * <p>The string representation is obtained using the stringifier returned by the
	 * static {@link AbstractMap#getStringifier} method.
	 *
	 * @return the string representation of this map
	 */
	public function toString():String {
		return getStringifier().execute(this);
	}
	
}