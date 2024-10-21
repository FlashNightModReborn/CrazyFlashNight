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
 * {@code Stack} is the base interface for data holders that follow the 'last-in,
 * first-out' policy.
 * 
 * <p>It offers the opposite functionality of a queue, which follows the 'first-in,
 * first-out' policy.
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
 * <p>Example:
 * <code>
 *   // the stack gets set up
 *   var stack:Stack = new MyStack();
 *   stack.push("value1");
 *   stack.push("value2");
 *   stack.push("value3");
 *   // the stack gets used somewhere in your application
 *   trace(stack.peek()); // traces the last element without removing it
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
 * @author Simon Wacker
 */
interface org.as2lib.data.holder.Stack extends BasicInterface {
	
	/**
	 * Pushes the passed-in {@code value} to this stack.
	 *
	 * @param value the value to push to this stack
	 */
	public function push(value):Void;
	
	/**
	 * Removes and returns the lastly pushed value.
	 *
	 * @return the lastly pushed value
	 * @throws org.as2lib.data.holder.EmptyDataHolderException if this stack is empty
	 */
	public function pop(Void);
	
	/**
	 * Returns the lastly pushed value without removing it.
	 *
	 * @return the lastly pushed value
	 * @throws org.as2lib.data.holder.EmptyDataHolderException if this stack is empty
	 */
	public function peek(Void);
	
	/**
	 * Returns an iterator to iterate over the values of this stack.
	 *
	 * @return an iterator to iterate over this stack's values
	 * @see #toArray
	 */
	public function iterator(Void):Iterator;
	
	/**
	 * Returns whether this stack is empty.
	 *
	 * @return {@code true} if this stack is empty else {@code false}
	 */
	public function isEmpty(Void):Boolean;
	
	/**
	 * Returns the number of pushed values.
	 *
	 * @return the number of pushed values
	 * @see #push
	 */
	public function size(Void):Number;
	
	/**
	 * Returns the array representation of this stack.
	 * 
	 * <p>The elements are copied onto the array in a 'last-in, first-out' order, similar
	 * to the order of the elements returned by a succession of calls to the {@link #pop}
	 * method.
	 *
	 * @return the array representation of this stack
	 */
	 public function toArray(Void):Array;
	
}