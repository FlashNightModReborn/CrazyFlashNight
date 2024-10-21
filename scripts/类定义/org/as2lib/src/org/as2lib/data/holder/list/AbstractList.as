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
import org.as2lib.env.overload.Overload;
import org.as2lib.data.holder.List;
import org.as2lib.util.Stringifier;
import org.as2lib.data.holder.list.ListStringifier;
import org.as2lib.data.holder.list.SubList;
import org.as2lib.data.holder.IndexOutOfBoundsException;

/**
 * {@code AbstractList} provides common implementations of methods needed by
 * implementations of the {@link List} interface.
 * 
 * @author Simon Wacker
 */
class org.as2lib.data.holder.list.AbstractList extends BasicClass {
	
	/** Stringifies lists. */
	private static var stringifier:Stringifier;
	
	/**
	 * Returns the stringifier to stringify lists.
	 *
	 * @return the list stringifier
	 */
	public static function getStringifier(Void):Stringifier {
		if (!stringifier) stringifier = new ListStringifier();
		return stringifier;
	}
	
	/**
	 * Sets the stringifier to stringify lists.
	 * 
	 * @param listStringifier the stringifier to stringify lists
	 */
	public static function setStringifier(listStringifier:Stringifier):Void {
		stringifier = listStringifier;
	}
	
	/** This instance casted to interface {@code List}. */
	private var thiz:List;
	
	/**
	 * Constructs a new {@code AbstractList} instance.	 */
	private function AbstractList(Void) {
		thiz = List(this);
	}
	
	/**
	 * @overload #insertByValue
	 * @overload insertByIndexAndValue
	 */
	public function insert():Void {
		var o:Overload = new Overload(this);
		o.addHandler([Object], insertByValue);
		o.addHandler([Number, Object], thiz.insertByIndexAndValue);
		o.forward(arguments);
	}
	
	/**
	 * Inserts {@code value} at the end of this list.
	 * 
	 * @param value the value to insert
	 * @see #insertLast
	 */
	public function insertByValue(value):Void {
		insertLast(value);
	}
	
	/**
	 * Inserts {@code value} at the beginning of this list.
	 * 
	 * @param value the value to insert
	 */
	public function insertFirst(value):Void {
		thiz.insertByIndexAndValue(0, value);
	}
	
	/**
	 * Inserts {@code value} at the end of this list.
	 * 
	 * @param value the value to insert
	 * @see #insert
	 */
	public function insertLast(value):Void {
		thiz.insertByIndexAndValue(thiz.size(), value);
	}
	
	/**
	 * @overload #insertAllByList
	 * @overload #insertAllByIndexAndList
	 */
	public function insertAll():Void {
		var o:Overload = new Overload(this);
		o.addHandler([List], insertAllByList);
		o.addHandler([Number, List], insertAllByIndexAndList);
		o.forward(arguments);
	}
	
	/**
	 * Inserts all values contained in {@code list} to the end of this list.
	 * 
	 * @param list the values to insert
	 */
	public function insertAllByList(list:List):Void {
		var v:Array = list.toArray();
		var l:Number = v.length;
		for (var i:Number = 0; i < l; i++) {
			thiz.insertLast(v[i]);
		}
	}
	
	/**
	 * Inserts all values contained in {@code list} to this list, starting at the
	 * specified {@code index}.
	 * 
	 * <p>Elements that are at an affected index are shifted to the right by the size
	 * of the given {@code list}.
	 * 
	 * @param index the index to start the insertion at
	 * @param list the values to insert
	 * @throws IndexOutOfBoundsException if the given {@code index} is not in range,
	 * this is less than 0 or greater than this list's size
	 */
	public function insertAllByIndexAndList(index:Number, list:List):Void {
		if (index < 0 || index > thiz.size()) {
			throw new IndexOutOfBoundsException("Argument 'index' [" + index + "] is out of range, this is less than 0 or greater than this list's size [" + thiz.size() + "].", this, arguments);
		}
		var v:Array = list.toArray();
		var l:Number = v.length;
		for (var i:Number = 0; i < l; i++) {
			thiz.insertByIndexAndValue(i + index, v[i]);
		}
	}
	
	/**
	 * @overload #removeByValue
	 * @overload removeByIndex
	 */
	public function remove() {
		var o:Overload = new Overload(this);
		o.addHandler([Object], removeByValue);
		o.addHandler([Number], thiz.removeByIndex);
		return o.forward(arguments);
	}
	
	/**
	 * Removes {@code value} from this list if it exists.
	 * 
	 * @param value the value to remove
	 */
	public function removeByValue(value):Number {
		var result:Number = indexOf(value);
		if (result > -1) {
			thiz.removeByIndex(indexOf(value));
		}
		return result;
	}
	
	/**
	 * Removes the value at the beginning of this list.
	 * 
	 * @return the removed value
	 */
	public function removeFirst(Void) {
		return thiz.removeByIndex(0);
	}
	
	/**
	 * Removes the value at the end of this list.
	 * 
	 * @return the removed value
	 */
	public function removeLast(Void) {
		return thiz.removeByIndex(thiz.size() - 1);
	}
	
	/**
	 * Removes all values contained in {@code list}.
	 * 
	 * @param list the values to remove
	 */
	public function removeAll(list:List):Void {
		var v:Array = list.toArray();
		var l:Number = v.length;
		for (var i:Number = 0; i < l; i++) {
			removeByValue(v[i]);
		}
	}
	
	/**
	 * Sets all values contained in {@code list} to this list, starting from given
	 * {@code index}. They values that were originally at the given {@code index}
	 * and following indices will be overwritten.
	 * 
	 * <p>This method only overwrites existing index-value pairs. If an affected index
	 * is equal to or greater than this list's size, which would mean that this list's
	 * size had to be expanded, an {@code IndexOutOfBoundsException} will be thrown. In
	 * such a case use the {@link #insertAll} method instead, which expands this list
	 * dynamically.
	 * 
	 * @param index the index to start at
	 * @param list the values to set
	 * @throws IndexOutOfBoundsException if given {@code index} is less than 0 or if
	 * any affected index, that is the given {@code index} plus the index of the
	 * specific value in the given {@code list}, is equal to or greater than this list's
	 * size
	 */
	public function setAll(index:Number, list:List):Void {
		if (index < 0 || index + list.size() > thiz.size()) {
			throw new IndexOutOfBoundsException("Argument 'index' [" + index + "] is out of range, this is less than 0 or the 'index' plus the size of the given 'list' [" + list.size() + "] is greater than this list's size [" + thiz.size() + "].", this, arguments);
		}
		var v:Array = list.toArray();
		var l:Number = v.length;
		for (var i:Number = 0; i < l; i++) {
			thiz.set(index++, v[i]);
		}
	}
	
	/**
	 * Retains all values the are contained in {@code list} and removes all others.
	 * 
	 * @param list the list of values to retain
	 */
	public function retainAll(list:List):Void {
		var i:Number = thiz.size();
		while(--i-(-1)) {
			if (!list.contains(thiz.get(i))) {
				thiz.removeByIndex(i);
			}
		}
	}
	
	/**
	 * Checks whether {@code value} is contained in this list.
	 * 
	 * @param value the value to check whether it is contained
	 * @return {@code true} if {@code value} is contained else {@code false}
	 */
	public function contains(value):Boolean {
		return (indexOf(value) > -1);
	}
	
	/**
	 * Checks whether all values of {@code list} are contained in this list.
	 * 
	 * @param list the values to check whether they are contained
	 * @return {@code true} if all values of {@code list} are contained else
	 * {@code false}
	 */
	public function containsAll(list:List):Boolean {
		var v:Array = list.toArray();
		var l:Number = v.length;
		for (var i:Number = 0; i < l; i++) {
			if (!contains(v[i])) {
				return false;
			}
		}
		return true;
	}
	
	/**
	 * Returns a view of the portion of this list between the specified {@code fromIndex},
	 * inclusive, and {@code toIndex}, exclusive.
	 * 
	 * <p>If {@code fromIndex} and {@code toIndex} are equal an empty list is returned.
	 * 
	 * <p>The returned list is backed by this list, so changes in the returned list are
	 * reflected in this list, and vice-versa.
	 * 
	 * @param fromIndex the index from which the sub-list starts (inclusive)
	 * @param toIndex the index specifying the end of the sub-list (exclusive)
	 * @return a view of the specified range within this list
	 * @throws IndexOutOfBoundsException if argument {@code fromIndex} is less than 0
	 * @throws IndexOutOfBoundsException if argument {@code toIndex} is greater than
	 * the size of this list
	 * @throws IndexOutOfBoundsException if argument {@code fromIndex} is greater than
	 * {@code toIndex}
	 */
	public function subList(fromIndex:Number, toIndex:Number):List {
		return new SubList(thiz, fromIndex, toIndex);
	}
	
	/**
	 * Returns the index of {@code value}.
	 * 
	 * @param value the value to return the index of
	 * @return the index of {@code value}
	 */
	public function indexOf(value):Number {
		var l:Number = thiz.size();
		while (--l > -1 && thiz.get(l) !== value);
		return l;
	}
	
	/**
	 * Returns whether this list is empty.
	 * 
	 * <p>This list is empty if it has no values assigned to it.
	 * 
	 * @return {@code true} if this list is empty else {@code false}
	 */
	public function isEmpty(Void):Boolean {
		return (thiz.size() < 1);
	}
	
	/**
	 * Returns the string representation of this list.
	 * 
	 * <p>The string representation is obtained via the stringifier returned by the
	 * static {@link #getStringifier} method.
	 * 
	 * @return the string representation of this list
	 */
	public function toString():String {
		return getStringifier().execute(this);
	}
	
}