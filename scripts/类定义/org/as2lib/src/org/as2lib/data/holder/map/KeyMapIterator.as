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
import org.as2lib.env.except.IllegalArgumentException;
import org.as2lib.data.holder.Iterator;
import org.as2lib.data.holder.array.ArrayIterator;
import org.as2lib.data.holder.Map;

/**
 * {@code KeyMapIterator} is used to iterate over the keys of a map.
 * 
 * <p>This iterator is quite simple to use. There is one method to check whether
 * there are more elements left to iterate over {@link #hasNext}, one method to get
 * the next element {@link #next} and one to remove the current element {@link #remove}.
 *
 * <p>Example:
 * <code>
 *   var map:Map = new HashMap();
 *   map.put("key1", 1);
 *   map.put("key2", 2);
 *   map.put("key3", 3);
 *   var iterator:Iterator = new KeyMapIterator(map);
 *   while (iterator.hasNext()) {
 *       trace(iterator.next());
 *   }
 * </code>
 *
 * <p>You normally do not use this class directly, but obtain an iterator that
 * iterates over the keys of a map using the {@link Map#keyIterator} method. The
 * returned iterator can, but does not have to be an instance of this class.
 * 
 * <p>Example:
 * <code>
 *   var map:Map = new HashMap();
 *   // ...
 *   var iterator:Iterator = map.keyIterator();
 *   // ...
 * </code>
 *
 * @author Simon Wacker
 */
class org.as2lib.data.holder.map.KeyMapIterator extends BasicClass implements Iterator {
	
	/** The target map to iterate over. */
	private var target:Map;
	
	/** The iterator used as a helper. */
	private var iterator:ArrayIterator;
	
	/** The presently selected key. */
	private var key;
	
	/**
	 * Constructs a new {@code KeyMapIterator} instance.
	 * 
	 * @param target the map to iterate over
	 * @throws IllegalArgumentException if the passed-in {@code target} map is {@code null}
	 * or {@code undefined}
	 */
	public function KeyMapIterator(target:Map) {
		if (!target) throw new IllegalArgumentException("The passed-in target map '" + target + "' is not allowed to be null or undefined.", this, arguments);
		this.target = target;
		iterator = new ArrayIterator(target.getKeys());
	}
	
	/**
	 * Returns whether there exists another key to iterate over.
	 * 
	 * @return {@code true} if there is at least one key left to iterate over
	 */
	public function hasNext(Void):Boolean {
		return iterator.hasNext();
	}
	
	/**
	 * Returns the next key.
	 * 
	 * @return the next key
	 * @throws org.as2lib.data.holder.NoSuchElementException if there is no next key
	 */
	public function next(Void) {
		key = iterator.next();
		return key;
	}
	
	/**
	 * Removes the currently selected key-value pair from this iterator and from the
	 * map this iterator iterates over.
	 * 
	 * @throws org.as2lib.env.except.IllegalStateException if you try to remove a
	 * key-value pair when none is selected
	 */
	public function remove(Void):Void {
		iterator.remove();
		target.remove(key);
	}
	
}