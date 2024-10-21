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
 
import org.as2lib.core.BasicInterface;
import org.as2lib.data.holder.Iterator;

/**
 * {@code List} holds values by index. Each value has its unique index.
 * 
 * <p>Example:
 * <code>
 *   var list:List = new MyList();
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
interface org.as2lib.data.holder.List extends BasicInterface {
	
	/**
	 * @overload #insertByValue
	 * @overload #insertByIndexAndValue	 */
	public function insert():Void;
	
	/**
	 * Inserts {@code value} at the end of this list.
	 * 
	 * @param value the value to insert
	 * @see #insertLast	 */
	public function insertByValue(value):Void;
	
	/**
	 * Inserts {@code value} at the given {@code index}.
	 * 
	 * <p>The element that is currently at the given {@code index} is shifted by one to
	 * the right, as well as any subsequent elements.
	 * 
	 * @param index the index at which to insert the {@code value}
	 * @param value the value to insert
	 * @throws IndexOutOfBoundsException if the given {@code index} is not in range,
	 * this is less than 0 or greater than this list's size	 */
	public function insertByIndexAndValue(index:Number, value):Void;
	
	/**
	 * Inserts {@code value} at the beginning of this list.
	 * 
	 * @param value the value to insert	 */
	public function insertFirst(value):Void;
	
	/**
	 * Inserts {@code value} at the end of this list.
	 * 
	 * @param value the value to insert
	 * @see #insert
	 */
	public function insertLast(value):Void;
	
	/**
	 * @overload #insertAllByList
	 * @overload #insertAllByIndexAndList	 */
	public function insertAll():Void;
	
	/**
	 * Inserts all values contained in {@code list} to the end of this list.
	 * 
	 * @param list the values to insert	 */
	public function insertAllByList(list:List):Void;
	
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
	 * this is less than 0 or greater than this list's size	 */
	public function insertAllByIndexAndList(index:Number, list:List):Void;
	
	/**
	 * @overload #removeByValue
	 * @overload #removeByIndex	 */
	public function remove();
	
	/**
	 * Removes {@code value} from this list if it exists and returns the index of the
	 * removed element.
	 * 
	 * @param value the value to remove
	 * @return the index of the removed element or {@code -1} if it did not exist on
	 * this list	 */
	public function removeByValue(value):Number;
	
	/**
	 * Removes the value at given {@code index} from this list and returns it.
	 * 
	 * @param index the index of the value to remove
	 * @return the removed value that was originally at given {@code index}
	 * @throws IndexOutOfBoundsException if given {@code index} is less than 0 or
	 * equal to or greater than this list's size	 */
	public function removeByIndex(index:Number);
	
	/**
	 * Removes the value at the beginning of this list.
	 * 
	 * @return the removed value	 */
	public function removeFirst(Void);
	
	/**
	 * Removes the value at the end of this list.
	 * 
	 * @return the removed value	 */
	public function removeLast(Void);
	
	/**
	 * Removes all values contained in {@code list}.
	 * 
	 * @param list the values to remove	 */
	public function removeAll(list:List):Void;
	
	/**
	 * Sets {@code value} to given {@code index} on this list. The value that was
	 * originally at the given {@code index} will be overwritten.
	 * 
	 * @param index the index of {@code value}
	 * @param value the {@code value} to set to given {@code index}
	 * @return the value that was orignially at given {@code index}
	 * @throws IndexOutOfBoundsException if given {@code index} is less than 0 or
	 * equal to or greater than this list's size	 */
	public function set(index:Number, value);
	
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
	 * size	 */
	public function setAll(index:Number, list:List):Void;
	
	/**
	 * Returns the value at given {@code index}.
	 * 
	 * @param index the index to return the value of
	 * @return the value that is at given {@code index}
	 * @throws IndexOutOfBoundsException if given {@code index} is less than 0 or
	 * equal to or greater than this list's size	 */
	public function get(index:Number);
	
	/**
	 * Checks whether {@code value} is contained in this list.
	 * 
	 * @param value the value to check whether it is contained
	 * @return {@code true} if {@code value} is contained else {@code false}	 */
	public function contains(value):Boolean;
	
	/**
	 * Checks whether all values of {@code list} are contained in this list.
	 * 
	 * @param list the values to check whether they are contained
	 * @return {@code true} if all values of {@code list} are contained else
	 * {@code false}	 */
	public function containsAll(list:List):Boolean;
	
	/**
	 * Retains all values the are contained in {@code list} and removes all others.
	 * 
	 * @param list the list of values to retain	 */
	public function retainAll(list:List):Void;
	
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
	 * {@code toIndex}	 */
	public function subList(fromIndex:Number, toIndex:Number):List;
	
	/**
	 * Removes all values from this list.	 */
	public function clear(Void):Void;
	
	/**
	 * Returns the number of added values.
	 * 
	 * @return the number of added values	 */
	public function size(Void):Number;
	
	/**
	 * Returns whether this list is empty.
	 * 
	 * <p>This list is empty if it has no values assigned to it.
	 * 
	 * @return {@code true} if this list is empty else {@code false}	 */
	public function isEmpty(Void):Boolean;
	
	/**
	 * Returns the iterator to iterate over this list.
	 * 
	 * @return the iterator to iterate over this list	 */
	public function iterator(Void):Iterator;
	
	/**
	 * Returns the index of {@code value}.
	 * 
	 * @param value the value to return the index of
	 * @return the index of {@code value}	 */
	public function indexOf(value):Number;
	
	/**
	 * Returns the array representation of this list.
	 * 
	 * @return the array representation of this list	 */
	public function toArray(Void):Array;
	
}