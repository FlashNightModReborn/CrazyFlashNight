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

import org.as2lib.env.except.IllegalArgumentException;
import org.as2lib.data.holder.IndexOutOfBoundsException;
import org.as2lib.data.holder.Iterator;
import org.as2lib.data.holder.List;
import org.as2lib.data.holder.list.AbstractList;
import org.as2lib.data.holder.list.ListIterator;

/**
 * {@code SubList} represents a part of a wrapped list. This part is specified by a
 * range from one index to another index. Every changes that are made to this list are
 * actually made to the wrapped list. You can nevertheless treat this list
 * implementation as any other; there is no difference in usage.
 * 
 * @author Simon Wacker
 */
class org.as2lib.data.holder.list.SubList extends AbstractList implements List {
	
	/** Makes the static variables of the super-class accessible through this class. */
	private static var __proto__:Function = AbstractList;
	
	/** The list this is a sub-list of. */
	private var list:List;
	
	/** The start index in the main-list. */
	private var offset:Number;
	
	/** The size of this sub-list. */
	private var length:Number;
	
	/**
	 * Constructs a new {@code SubList} instance.
	 * 
	 * @param list the list this is a sub-list of
	 * @param fromIndex the start index of this sub-list (inclusive)
	 * @param toIndex the end index of this sub-list (exclusive)
	 * @throws IllegalArgumentException if argument {@code list} is {@code null} or
	 * {@code undefined}
	 * @throws IndexOutOfBoundsException if argument {@code fromIndex} is less than 0
	 * @throws IndexOutOfBoundsException if argument {@code toIndex} is greater than
	 * the size of the passed-in {@code list}
	 * @throws IndexOutOfBoundsException if argument {@code fromIndex} is greater than
	 * {@code toIndex}	 */
	public function SubList(list:List, fromIndex:Number, toIndex:Number) {
		if (!list) throw new IllegalArgumentException("Argument 'list' [" + list + "] must not be 'null' nor 'undefined'.", this, arguments);
		if (fromIndex < 0) throw new IndexOutOfBoundsException("Argument 'fromIndex' [" + fromIndex + "] must not be less than 0.", this, arguments);
		if (toIndex > list.size()) throw new IndexOutOfBoundsException("Argument 'toIndex' [" + toIndex + "] must not be greater than the size of the passed-in 'list' [" + list.size() + "].", this, arguments);
		if (fromIndex > toIndex) throw new IndexOutOfBoundsException("Argument 'fromIndex' [" + fromIndex + "] must not be greater than argument 'toIndex' [" + toIndex + "].", this, arguments);
		this.list = list;
		this.offset = fromIndex;
		this.length = toIndex - fromIndex;
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
		if (index < 0 || index >= size()) {
			throw new IndexOutOfBoundsException("Argument 'index' [" + index + "] is out of range, this is less than 0 or equal to or greater than this list's size [" + size() + "].", this, arguments);
		}
		return this.list.set(offset + index, value);
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
		if (index < 0 || index >= size()) {
			throw new IndexOutOfBoundsException("Argument 'index' [" + index + "] is out of range, this is less than 0 or equal to or greater than this list's size [" + size() + "].", this, arguments);
		}
		return this.list.get(offset + index);
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
		if (index < 0 || index > size()) {
			throw new IndexOutOfBoundsException("Argument 'index' [" + index + "] is out of range, this is less than 0 or greater than this list's size [" + size() + "].", this, arguments);
		}
		this.list.insertByIndexAndValue(offset + index, value);
		this.length++;
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
		if (index < 0 || index >= size()) {
			throw new IndexOutOfBoundsException("Argument 'index' [" + index + "] is out of range, this is less than 0 or equal to or greater than this list's size [" + size() + "].", this, arguments);
		}
		// list.removeByIndex may throw an exception, in this case the size must not be reduced
		var result = this.list.removeByIndex(offset + index);
		this.length--;
		return result;
	}
	
	/**
	 * Removes all values from this list.
	 */
	public function clear(Void):Void {
		do {
			this.list.removeByIndex(this.offset);
		} while (--this.length > 0);
	}
	
	/**
	 * Returns the number of added values.
	 * 
	 * @return the number of added values
	 */
	public function size(Void):Number {
		return this.length;
	}
	
	/**
	 * Returns the iterator to iterate over this list.
	 * 
	 * @return the iterator to iterate over this list
	 */
	public function iterator(Void):Iterator {
		return new ListIterator(this);
	}
	
	/**
	 * Returns the array representation of this list.
	 * 
	 * @return the array representation of this list
	 */
	public function toArray(Void):Array {
		return this.list.toArray().slice(this.offset, this.offset + this.length);
	}
	
}