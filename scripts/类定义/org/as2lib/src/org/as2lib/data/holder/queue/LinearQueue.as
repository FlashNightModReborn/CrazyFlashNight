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
import org.as2lib.data.holder.Queue;
import org.as2lib.data.holder.Iterator;
import org.as2lib.data.holder.array.ArrayIterator;
import org.as2lib.data.holder.EmptyDataHolderException;
import org.as2lib.util.Stringifier;
import org.as2lib.data.holder.queue.QueueStringifier;

/**
 * {@code LinearQueue} stores values in a 'first-in, first-out' manner.
 * 
 * <p>This class is a linear implementation of the {@code Queue} interface. This
 * means that enqueued values are stored in a linear manner and that you can store
 * as many values as you please. There are also queues that store values in a cyclic
 * manner. These queues can normally only hold a prescribed number of values and
 * overwrite old values or throw an exception if you try to enqueue more values.
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
 * <p>You can modify the string representation that is returned by the {@link #toString}
 * method with the static {@link #setStringifier} method.
 *
 * <p>Example:
 * <code>
 *   // construct the queue
 *   var queue:Queue = new LinearQueue();
 *   queue.enqueue("value1");
 *   queue.enqueue("value2");
 *   queue.enqueue("value3");
 *   // use the queue
 *   trace(queue.peek());
 *   while (!queue.isEmpty()) {
 *       trace(queue.pop());
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
 * <p>You can alternatively pass-in the content of the queue on construction.
 * <code>
 *   var queue:Queue = new LinearQueue(["value1", "value2", "value3"]);
 *   // ..
 * </code>
 *
 * @author Simon Wacker
 */
class org.as2lib.data.holder.queue.LinearQueue extends BasicClass implements Queue {
	
	/** Stringifies queues. */
	private static var stringifier:Stringifier;
	
	/** Contains the inserted elements. */
	private var data:Array;
	
	/**
	 * Returns the stringifier that stringifies queues.
	 *
	 * <p>If no stringifier has been set manually via the static {@link #setStringifier}
	 * method an instance of class {@link QueueStringifier} will be returned.
	 * 
	 * @return the stringifier that stringifies queues
	 */
	public static function getStringifier(Void):Stringifier {
		if (!stringifier) stringifier = new QueueStringifier();
		return stringifier;
	}
	
	/**
	 * Sets the new stringifier that stringifies queues.
	 * 
	 * <p>If the passed-in {@code queueStringifier} is {@code null} or {@code undefined},
	 * the static {@link #getStringifier} method will return the default stringifier.
	 *
	 * @param queueStringifier the new queue stringifier
	 */
	public static function setStringifier(queueStringifier:Stringifier):Void {
		stringifier = queueStringifier;
	}
	
	/**
	 * Constructs a new {@code LinearQueue} instance.
	 *
	 * <p>The queue steps through the passed-in {@code source} beginning at position 0
	 * and enqueues all contained elements.
	 * 
	 * <p>Example:
	 * <code>
	 *   var queue:LinearQueue = new LinearQueue([1, 2, 3]);
 	 *   while (!queue.isEmpty()) {
	 * 	     trace(queue.dequeue());
	 *   }
	 * </code>
	 *
	 * <p>The output is made in the following order: 1, 2, 3
	 * 
	 * @param source (optional) an array that contains values to populate this queue with
	 */
	public function LinearQueue(source:Array) {
		if (source) {
			data = source.concat();
		} else {
			data = new Array();
		}
	}
	
	/**
	 * Adds the passed-in {@code value} to this queue.
	 *
	 * <p>{@code null} and {@code undefined} values are allowed.
	 *
	 * @param value the value to add
	 */
	public function enqueue(value):Void {
		data.push(value);
	}
	
	/**
	 * Removes and returns the firstly inserted value.
	 *
	 * @return the firstly inserted value
	 * @throws EmptyDataHolderException if this queue is empty
	 */
	public function dequeue(Void) {
		if (isEmpty()) {
			throw new EmptyDataHolderException("You tried to dequeue an element from an empty Queue.", this, arguments);
		}
		return data.shift();
	}
	
	/**
	 * Returns the firstly inserted value.
	 *
	 * @return the firstly inserted value
	 * @throws EmptyDataHolderException if this queue is empty
	 */
	public function peek(Void) {
		if (isEmpty()) {
			throw new EmptyDataHolderException("You tried to peek an element from an empty Queue.", this, arguments);
		}
		return data[0];
	}
	
	/**
	 * Returns an iterator that can be used to iterate over the values of this queue.
	 * 
	 * @return an iterator to iterate over this queue's values
	 * @see #toArray
	 */
	public function iterator(Void):Iterator {
		return (new ArrayIterator(data.concat()));
	}
	
	/**
	 * Returns whether this queue contains any values.
	 *
	 * @return {@code true} if this queue contains no values else {@code false}
	 */
	public function isEmpty(Void):Boolean {
		return (data.length < 1);
	}
	
	/**
	 * Returns the number of enqueued elements.
	 *
	 * @return the number of enqueued elements
	 * @see #enqueue
	 */
	public function size(Void):Number {
		return data.length;
	}
	
	/**
	 * Returns an array representation of this queue.
	 *
	 * <p>The elements are copied onto the array in a 'first-in, first-out' order,
	 * similar to the order of the elements returned by a succession of calls to the
	 * {@link #dequeue} method.
	 * ################################################################################
	 * @return the array representation of this queue
	 */
	public function toArray(Void):Array {
		return data.concat();
	}
	
	/**
	 * Returns the string representation of this queue.
	 *
	 * <p>The string representation is obtained via the stringifier returned by the
	 * static {@link #getStringifier} method.
	 * 
	 * @return the string representation of this queue
	 */
	public function toString():String {
		return getStringifier().execute(this);
	}
	
}