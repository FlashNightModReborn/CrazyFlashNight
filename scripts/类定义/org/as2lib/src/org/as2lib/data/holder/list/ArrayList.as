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

import org.as2lib.data.holder.List;
import org.as2lib.data.holder.Iterator;
import org.as2lib.data.holder.array.ArrayIterator;
import org.as2lib.data.holder.list.AbstractList;
import org.as2lib.data.holder.IndexOutOfBoundsException;

/**
 * {@code ArrayList} is a resizable-array implementation of {@code List} interface.
 * 
 * <p>Example:
 * <code>
 *   var list:List = new ArrayList();
 *   list.insert("myValue1");
 *   list.insertFirst("myValue2");
 *   list.insertLast("myValue3");
 *   trace(list.contains("myValue2"));
 *   trace(list.remove(0));
 *   trace(list.contains("myValue2"));
 *   trace(list.removeLast());
 *   trace(list.get(0));
 *   list.clear();
 *   trace(list.size());
 * </code>
 * 
 * <p>Output:
 * <pre>
 *   true
 *   myValue2
 *   false
 *   myValue3
 *   myValue1
 *   0
 * </pre>
 * 
 * @author Simon Wacker
 */
class org.as2lib.data.holder.list.ArrayList extends AbstractList implements List {
	
	/** Makes the static variables of the super-class accessible through this class. */
	private static var __proto__:Function = AbstractList;
	
	/** Holds added values. */
	private var data:Array;
	
	/**
	 * Constructs a new {@code ArrayList} instance.
	 *
	 * @param source (optional) an array that contains values to populate this new list
	 * with
	 */
	public function ArrayList(source:Array) {
		if (source) {
			data = source.concat();
		} else {
			data = new Array();
		}
	}
	
	/**
	 * Inserts {@code value} at the given {@code index}.
	 * 
	 * <p>The element that is currently at the given {@code index} is shifted by one to
	 * the right, as well as any subsequent elements.
	 * 
	 * @param index the index at which to insert the {@code value}
	 * @param value the value to insert
	 * @throws IndexOutOfBoundsException if the given {@code index} is not in range,
	 * this is less than 0 or greater than this list's size
	 */
	public function insertByIndexAndValue(index:Number, value):Void {
		if (index < 0 || index > data.length) {
			throw new IndexOutOfBoundsException("Argument 'index' [" + index + "] is out of range, this is less than 0 or greater than this list's size [" + size() + "].", this, arguments);
		}
		if (index == data.length) {
			data.push(value);
			return;
		}
		if (index == 0) {
			data.unshift(value);
			return;
		}
		data.splice(index, 0, value);
	}
	
	/**
	 * Removes the value at given {@code index} from this list and returns it.
	 * 
	 * @param index the index of the value to remove
	 * @return the removed value that was originally at given {@code index}
	 * @throws IndexOutOfBoundsException if given {@code index} is less than 0 or
	 * equal to or greater than this list's size
	 */
	public function removeByIndex(index:Number) {
		if (index < 0 || index >= data.length) {
			throw new IndexOutOfBoundsException("Argument 'index' [" + index + "] is out of range, this is less than 0 or equal to or greater than this list's size [" + size() + "].", this, arguments);
		}
		if (index == 0) {
			return data.shift();
		}
		if (index == data.length - 1) {
			return data.pop();
		}
		var result = data[index];
		data.splice(index, 1);
		return result;
	}
	
	/**
	 * Sets {@code value} to given {@code index} on this list.
	 * 
	 * @param index the index of {@code value}
	 * @param value the {@code value} to set to given {@code index}
	 * @return the value that was orignially at given {@code index}
	 * @throws IndexOutOfBoundsException if given {@code index} is less than 0 or
	 * equal to or greater than this list's size
	 */
	public function set(index:Number, value) {
		if (index < 0 || index >= data.length) {
			throw new IndexOutOfBoundsException("Argument 'index' [" + index + "] is out of range, this is less than 0 or equal to or greater than this list's size [" + size() + "].", this, arguments);
		}
		var result = data[index];
		data[index] = value;
		return result;
	}
	
	/**
	 * Returns the value at given {@code index}.
	 * 
	 * @param index the index to return the value of
	 * @return the value that is at given {@code index}
	 * @throws IndexOutOfBoundsException if given {@code index} is less than 0 or
	 * equal to or greater than this list's size
	 */
	public function get(index:Number) {
		if (index < 0 || index >= data.length) {
			throw new IndexOutOfBoundsException("Argument 'index' [" + index + "] is out of range, this is less than 0 or equal to or greater than this list's size [" + size() + "].", this, arguments);
		}
		return data[index];
	}
	
	/**
	 * Removes all values from this list.
	 */
	public function clear(Void):Void {
		data = new Array();
	}
	
	/**
	 * Returns the number of added values.
	 * 
	 * @return the number of added values
	 */
	public function size(Void):Number {
		return data.length;
	}
	
	/**
	 * Returns the iterator to iterate over this list.
	 * 
	 * @return the iterator to iterate over this list
	 */
	public function iterator(Void):Iterator {
		return new ArrayIterator(data);
	}
	
	/**
	 * Returns the array representation of this list.
	 * 
	 * @return the array representation of this list
	 */
	public function toArray(Void):Array {
		return data.concat();
	}

}