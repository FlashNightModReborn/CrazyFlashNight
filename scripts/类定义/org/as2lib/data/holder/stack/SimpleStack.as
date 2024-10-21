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
import org.as2lib.data.holder.Stack;
import org.as2lib.data.holder.Iterator;
import org.as2lib.data.holder.ProtectedIterator;
import org.as2lib.data.holder.array.ArrayIterator;
import org.as2lib.data.holder.EmptyDataHolderException;
import org.as2lib.util.Stringifier;
import org.as2lib.data.holder.stack.StackStringifier;

/**
 * {@code SimpleStack} holds data in a 'last-in, first-out' manner.
 * 
 * <p>It is a simple implementation of the {@code Stack} interface and realizes all
 * its basic concepts.
 * 
 * <p>'last-in, first-out' means that the last value that has been pushed to the
 * stack is the first that is popped from the stack.
 *
 * <p>The usage of a stack is quite simple. You have one method to push values,
 * {@link #push}, and one method to pop values, {@link #pop}. You can also peek at
 * the top of the stack to see what's the last value that has been pushed to the
 * stack without removing it {@link #peek}.
 * 
 * <p>If you want to iterate over the values of the stack you can either use the
 * iterator returned by the {@link #iterator} method or the array that contains the
 * stack's values returned by the {@link #toArray} method.
 * 
 * <p>The two methods {@link #isEmpty} and {@link #size} let you find out whether
 * the stack contains values and how many values it contains.
 * 
 * <p>You can modify the string representation that is returned by the {@link #toString}
 * method using the static {@link #setStringifier} method.
 *
 * <p>Example:
 * <code>
 *   // the stack is constructed somewhere
 *   var stack:Stack = new SimpleStack();
 *   stack.push("value1");
 *   stack.push("value2");
 *   stack.push("value3");
 *   // the stack is used
 *   trace(stack.peek());
 *   while (!stack.isEmpty()) {
 *       trace(stack.pop());
 *   }
 * </code>
 *
 * <p>Output:
 * <pre>
 *   value3
 *   value3
 *   value2
 *   value1
 * </pre>
 * 
 * <p>You can alternatively pass-in the content of the stack on construction.
 * <code>
 *   var stack:Stack = new SimpleStack(["value1", "value2", "value3"]);
 *   // ..
 * </code>
 *
 * @author Simon Wacker
 */
class org.as2lib.data.holder.stack.SimpleStack extends BasicClass implements Stack {
	
	/** Stringifies stacks. */
	private static var stringifier:Stringifier;
	
	/** Contains the inserted values. */
	private var values:Array;
	
	/**
	 * Returns the stringifier that stringifies stacks.
	 *
	 * <p>If no stringifier has been set manually the default stringifier will be returned
	 * which is an instance of class {@link StackStringifier}.
	 * 
	 * @return the stringifier that stringifies stacks
	 */
	public static function getStringifier(Void):Stringifier {
		if (!stringifier) stringifier = new StackStringifier();
		return stringifier;
	}
	
	/**
	 * Sets the new stringifier that stringifies stacks.
	 *
	 * <p>If the passed-in {@code stackStringifier} is {@code null} or {@code undefined}
	 * the static {@link #getStringifier} method will return the default stringifier.
	 * 
	 * @param stackStringifier the new stack stringifier
	 */
	public static function setStringifier(stackStringifier:Stringifier):Void {
		stringifier = stackStringifier;
	}
	
	/**
	 * Constructs a new {@code SimpleStack} instance.
	 *
	 * <p>The stack steps through the passed-in {@code source} beginning at position
	 * 0 and pushes all contained elements to this stack.
	 * 
	 * <code>
	 *   var stack:SimpleStack = new SimpleStack([1, 2, 3]);
 	 *   while (!stack.isEmpty()) {
	 * 	     trace(stack.pop());
	 *   }
	 * </code>
	 *
	 * <p>The output is made in the following order: 3, 2, 1
	 * 
	 * @param source (optional) an array that contains values to populate this stack with
	 */
	public function SimpleStack(source:Array) {
		if (source) {
			values = source.concat();
		} else {
			values = new Array();
		}
	}
	
	/**
	 * Pushes the passed-in {@code value} to this stack.
	 *
	 * <p>{@code null} or {@code undefined} values are allowed.
	 *
	 * @param value the value to push to this stack
	 */
	public function push(value):Void {
		values.push(value);
	}
	
	/**
	 * Removes and returns the lastly pushed value.
	 *
	 * @return the lastly pushed value
	 * @throws EmptyDataHolderException if this stack is empty
	 */
	public function pop(Void) {
		if (isEmpty()) {
			throw new EmptyDataHolderException("You tried to pop an element from an empty Stack.", this, arguments);
		}
		return values.pop();
	}
	
	/**
	 * Returns the lastly pushed value without removing it.
	 *
	 * @return the lastly pushed value
	 * @throws EmptyDataHolderException if this stack is empty
	 */
	public function peek(Void) {
		if (isEmpty()) {
			throw new EmptyDataHolderException("You tried to peek an element from an empty Stack.", this, arguments);
		}
		return values[values.length-1];
	}
	
	/**
	 * Returns an iterator to iterate over the values of this stack.
	 *
	 * @return an iterator to iterate over this stack
	 * @see #toArray
	 */
	public function iterator(Void):Iterator {
		var reversedValues:Array = values.slice();
		reversedValues.reverse();
		return (new ProtectedIterator(new ArrayIterator(reversedValues)));
	}
	
	/**
	 * Returns whether this stack is empty.
	 *
	 * @return {@code true} if this stack is empty else {@code false}
	 */
	public function isEmpty(Void):Boolean {
		return (values.length < 1);
	}
	
	/**
	 * Returns the number of pushed values.
	 *
	 * @return the number of pushed values
	 * @see #push
	 */
	public function size(Void):Number {
		return values.length;
	}
	
	/**
	 * Returns the array representation of this stack.
	 * 
	 * <p>The elements are copied onto the array in a 'last-in, first-out' order, similar
	 * to the order of the elements returned by a succession of calls to the {@link #pop}
	 * method.
	 *
	 * @return the array representation of this stack
	 */
	public function toArray(Void):Array {
		var result:Array = values.concat();
		result.reverse();
		return result;
	}
	
	/**
	 * Returns the string representation of this stack.
	 * 
	 * <p>The string representation is obtained using the stringifier returned by the
	 * static {@link #getStringifier} method.
	 *
	 * @return the string representation of this stack
	 */
	public function toString():String {
		return getStringifier().execute(this);
	}
	
}