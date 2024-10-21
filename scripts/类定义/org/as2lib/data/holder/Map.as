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

import org.as2lib.data.holder.Iterator;
import org.as2lib.core.BasicInterface;

/**
 * {@code Map} is the base interface for data holders that map keys to values.
 * 
 * <p>A map offers two methods that help you find out whether it contains a specific
 * key or value. These two methods are {@link #containsKey} and {@link #containsValue}.
 * 
 * <p>To get the data stored in the map you can use the methods {@link #getKeys},
 * {@link #getValues} and {@link #get}. If you want to iterate over the values of
 * the map you can use the iterators returned by the methods {@link #iterator} or
 * {@link #valueIterator}. If you want to iterate over the keys you can use the
 * iterator returned by the {@link #keyIterator} method.
 *
 * <p>To add key value pairs to the map you can use the methods {@link #put} and
 * {@link #putAll}. The {@code putAll} method lets you add all key-value pairs
 * contained in the passed-in {@code map} to this map.
 * 
 * <p>To remove key-value pairs you can use the methods {@link #remove} and
 * {@link #clear}. The {@code remove} method deletes only the key-value pair
 * corresponding to the passed-in {@code key}, while the clear method removes all
 * key-value pairs.
 *
 * <p>There are two more methods you may need. The {@link #isEmpty} and the
 * {@link #size} method. These methods give you information about whether this
 * map contains any mappings and how many mappings it contains.
 *
 * <p>Example:
 * <code>
 *   // the map gets set up somewhere
 *   var map:Map = new MyMap();
 *   map.put("myKey", "myValue");
 *   // at some different place in your code
 *   if (map.containsKey("myKey")) {
 *       trace(map.get("myKey"));
 *   }
 * </code>
 *
 * @author Simon Wacker
 * @author Michael Herrmann
 */
interface org.as2lib.data.holder.Map extends BasicInterface {
	
	/**
	 * Checks if the passed-in {@code key} exists.
	 *
	 * <p>That means whether a value has been mapped to it.
	 *
	 * @param key the key to be checked for availability
	 * @return {@code true} if the {@code key} exists else {@code false}
	 */
	public function containsKey(key):Boolean;
	
	/**
	 * Checks if the passed-in {@code value} is mapped to a key.
	 * 
	 * @param value the value to be checked for availability
	 * @return {@code true} if the {@code value} is mapped to a key else {@code false}
	 */
	public function containsValue(value):Boolean;
	
	/**
	 * Returns an array that contains all keys that have a value mapped to
	 * it.
	 *
	 * @return an array that contains all keys
	 */
	public function getKeys(Void):Array;
	
	/**
	 * Returns an array that contains all values that are mapped to a key.
	 *
	 * @return an array that contains all mapped values
	 */
	public function getValues(Void):Array;
	
	/**
	 * Returns the value that is mapped to the passed-in {@code key}.
	 * 
	 * @param key the key to return the corresponding value for
	 * @return the value corresponding to the passed-in {@code key}
	 */
	public function get(key);
	
	/**
	 * Maps the given {@code key} to the {@code value}.
	 *
	 * @param key the key used as identifier for the {@code value}
	 * @param value the value to map to the {@code key}
	 * @return the value that was originally mapped to the {@code key}
	 */
	public function put(key, value);
	
	/**
	 * Copies all mappings from the passed-in {@code map} to this map.
	 *
	 * @param map the mappings to add to this map
	 */
	public function putAll(map:Map):Void;
	
	/**
	 * Removes the mapping from the given {@code key} to the value.
	 *
	 * @param key the key identifying the mapping to remove
	 * @return the value that was originally mapped to the {@code key}
	 */
	public function remove(key);
	
	/**
	 * Clears all mappings.
	 */
	public function clear(Void):Void;
	
	/**
	 * Returns an iterator to iterate over the values of this map.
	 *
	 * @return an iterator to iterate over the values of this map
	 * @see #valueIterator
	 * @see #getValues
	 */
	public function iterator(Void):Iterator;
	
	/**
	 * Returns an iterator to iterate over the values of this map.
	 *
	 * @return an iterator to iterate over the values of this map
	 * @see #iterator
	 * @see #getValues
	 */
	public function valueIterator(Void):Iterator;
	
	/**
	 * Returns an iterator to iterate over the keys of this map.
	 *
	 * @return an iterator to iterate over the keys of this map
	 * @see #getKeys
	 */
	public function keyIterator(Void):Iterator;
	
	/**
	 * Returns the amount of mappings.
	 *
	 * @return the amount of mappings
	 */
	public function size(Void):Number;
	
	/**
	 * Returns whether this map contains any mappings.
	 * 
	 * @return {@code true} if this map contains any mappings else {@code false}
	 */
	public function isEmpty(Void):Boolean;
	
}