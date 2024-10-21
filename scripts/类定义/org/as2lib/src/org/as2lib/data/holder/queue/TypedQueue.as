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
import org.as2lib.util.ObjectUtil;
import org.as2lib.env.except.IllegalArgumentException;
import org.as2lib.env.reflect.ReflectUtil;
import org.as2lib.data.holder.Queue;
import org.as2lib.data.holder.Iterator;

/**
 * {@code TypedQueue} is a wrapper for {@link Queue} instances that ensures that
 * only values of a specific type can be added to the wrapped queue.
 * 
 * <p>This class simply delegates all method invocations to the wrapped queue. If
 * the specific method is responsible for adding values it first checks if the values
 * to add are of the expected type. If they are the method invocation is forwarded,
 * otherwise an {@link IllegalArgumentException} is thrown.
 *
 * @author Simon Wacker
 */
class org.as2lib.data.holder.queue.TypedQueue extends BasicClass implements Queue {
	
	/** The wrapped queue. */
	private var queue:Queue;
	
	/** The type of the values that can be added. */
	private var type:Function;
	
	/**
	 * Constructs a new {@code TypedQueue} instance.
	 *
	 * <p>If the passed-in {@code queue} does already contain values, these values do
	 * not get type-checked.
	 * 
	 * @param type the type of the values that are allowed to be added
	 * @param queue the queue to wrap
	 * @throws IllegalArgumentException if the passed-in {@code type} is {@code null}
	 * or {@code undefined}
	 * @throws IllegalArgumentException if {@code queue} is {@code null} or
	 * {@code undefined}
	 */
	public function TypedQueue(type:Function, queue:Queue) {
		if (!type) throw new IllegalArgumentException("Argument 'type' [" + type + "] must not be 'null' nor 'undefined'.", this, arguments);
		if (!queue) throw new IllegalArgumentException("Argument 'queue' [" + queue + "] must not be 'null' nor 'undefined'.", this, arguments);
		this.type = type;
		this.queue = queue;
	}
	
	/**
	 * Returns the type that all values in the wrapped queue have.
	 *
	 * <p>This is the type passed-in on construction.
	 *
	 * @return the type the all values of the wrapped queue have
	 */
	public function getType(Void):Function {
		return type;
	}
	
	/**
	 * Adds the passed-in {@code value} to this queue.
	 *
	 * <p>The value is only enqueued if it is of the expected type.
	 *
	 * @param value the value to add
	 * @throws IllegalArgumentException if the type of the passed-in {@code value} is
	 * invalid
	 */
	public function enqueue(value):Void {
		validate(value);
		queue.enqueue(value);
	}
	
	/**
	 * Removes the firstly inserted value.
	 *
	 * @return the firstly inserted value
	 * @throws org.as2lib.data.holder.EmptyDataHolderException if this queue is empty
	 */
	public function dequeue(Void) {
		return queue.dequeue();
	}
	
	/**
	 * Returns the firstly inserted value.
	 *
	 * @return the firstly inserted value
	 * @throws org.as2lib.data.holder.EmptyDataHolderException if this queue is empty
	 */
	public function peek(Void) {
		return queue.peek();
	}
	/**
	 * Returns an iterator that can be used to iterate over the values of this queue.
	 * 
	 * @return an iterator to iterate over this queue's values
	 * @see #toArray
	 */
	public function iterator(Void):Iterator {
		return queue.iterator();
	}
	
	/**
	 * Returns whether this queue contains any values.
	 *
	 * @return {@code true} if this queue contains no values else {@code false}
	 */
	public function isEmpty(Void):Boolean {
		return queue.isEmpty();
	}
	
	/**
	 * Returns the number of enqueued elements.
	 *
	 * @return the number of enqueued elements
	 * @see #enqueue
	 */
	public function size(Void):Number {
		return queue.size();
	}
	
	/**
	 * Returns an array representation of this queue.
	 *
	 * <p>The elements are copied onto the array in a 'first-in, first-out' order,
	 * similar to the order of the elements returned by a succession of calls to the
	 * {@link #dequeue} method.
	 * 
	 * @return the array representation of this queue
	 */
	public function toArray(Void):Array {
		return queue.toArray();
	}
	
	/**
	 * Returns the string representation of the wrapped queue.
	 *
	 * @return the string representation of the wrapped queue
	 */
	public function toString():String {
		return queue.toString();
	}
	
	/**
	 * Validates the passed-in {@code value} based on its type.
	 *
	 * @param value the value whose type shall be validated
	 * @throws IllegalArgumentException if the type of the {@code value} is invalid
	 */
	private function validate(value):Void {
		if (!ObjectUtil.typesMatch(value, type)) {
			throw new IllegalArgumentException("Type mismatch between value [" + value + "] and type [" + ReflectUtil.getTypeNameForType(type) + "].", this, arguments);
		}
	}
	
}