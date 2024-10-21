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
 * {@code Queue} is the base interface for data holders that follow the 'first-in,
 * first-out' policy.
 * 
 * <p>It offers the opposite functionality of a stack which follows the 'last-in,
 * first-out' policy.
 * 
 * <p>'first-in, first-out' means that the first value that has been enqueued/added
 * to the queue is the first that gets dequeued/removed.
 * 
 * <p>The usage of a queue is quite simple. You have one method to add/enqueue values
 * {@link #enqueue} and one method to remove/dequeue them {@link #dequeue}. You can
 * also peek at the beginning of the queue to see what value has been added/enqueued
 * at first without removing it {@link #peek}.
 *
 * <p>If you want to iterate over the values of the queue you can either use the
 * iterator returned by the {@link #iterator} method or the array that contains the
 * queue's values returned by the {@link #toArray} method.
 * 
 * <p>The two methods {@link #isEmpty} and {@link #size} let you find
 * out whether the queue contains values and how many values it contains.
 *
 * <p>Example:
 * <code>
 *   // the queue gets set up
 *   var queue:Queue = new MyQueue();
 *   queue.enqueue("value1");
 *   queue.enqueue("value2");
 *   queue.enqueue("value3");
 *   // the queue gets used somewhere in your application
 *   trace(queue.peek()); // traces the first element without removing it
 *   while (!queue.isEmpty()) {
 *       trace(queue.dequeue());
 *   }
 * </code>
 *
 * <p>Output:
 * <pre>
 *   value1
 *   value1
 *   value2
 *   value3
 * </pre>
 *
 * @author Simon Wacker
 */
interface org.as2lib.data.holder.Queue extends BasicInterface {
	
	/**
	 * Adds the passed-in {@code value} to this queue.
	 *
	 * @param value the value to add
	 */
	public function enqueue(value):Void;
	
	/**
	 * Removes and returns the firstly inserted value.
	 * 
	 * @return the firstly inserted value
	 * @throws org.as2lib.data.holder.EmptyDataHolderException if this queue is empty
	 */
	public function dequeue(Void);
	
	/**
	 * Returns the firstly inserted value.
	 *
	 * @return the firstly inserted value
	 * @throws org.as2lib.data.holder.EmptyDataHolderException if this queue is empty
	 */
	public function peek(Void);
	
	/**
	 * Returns an iterator to iterate over the values of this queue.
	 *
	 * @return an iterator to iterate over this queue's values
	 * @see #toArray
	 */
	public function iterator(Void):Iterator;
	
	/**
	 * Returns whether this queue contains any values.
	 * 
	 * @return {@code true} if this queue contains no values else {@code false}
	 */
	public function isEmpty(Void):Boolean;
	
	/**
	 * Returns the number of enqueued elements.
	 *
	 * @return the number of enqueued elements
	 * @see #enqueue
	 */
	public function size(Void):Number;
	
	/**
	 * Returns the array representation of this queue.
	 * 
	 * <p>The elements are copied onto the array in a 'first-in, first-out' order,
	 * similar to the order of the elements returned by a succession of calls to the
	 * {@link #dequeue} method.
	 *
	 * @return the array representation of this queue
	 */
	public function toArray(Void):Array;
	
}