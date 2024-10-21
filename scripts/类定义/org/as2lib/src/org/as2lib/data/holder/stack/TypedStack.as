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
import org.as2lib.data.holder.Stack;
import org.as2lib.data.holder.Iterator;

/**
 * {@code TypedStack} is a wrapper for {@link Stack} instances that ensures that
 * only values of a specific type can be added to the wrapped stack.
 * 
 * <p>This class simply delegates all method invocations to the wrapped stack. If
 * the specific method is responsible for adding values it first checks if the values
 * to add are of the expected type. If they are the method invocation is forwarded,
 * otherwise an {@link IllegalArgumentException} is thrown.
 *
 * @author Simon Wacker
 */
class org.as2lib.data.holder.stack.TypedStack extends BasicClass implements Stack {
	
	/** The wrapped Stack. */
	private var stack:Stack;
	
	/** The type of the values that are allowed. */
	private var type:Function;
	
	/**
	 * Constructs a new {@code TypedStack} instance.
	 *
	 * <p>If the passed-in stack does already contain values, these values do not get
	 * type-checked.
	 * 
	 * @param type the type of values the stack can have
	 * @param stack the stack to type-check
	 * @throws IllegalArgumentException if the passed-in {@code type} is {@code null}
	 * or {@code undefined}
	 * @throws IllegalArgumentException if {@code stack} is {@code null} or
	 * {@code undefined}
	 */
	public function TypedStack(type:Function, stack:Stack) {
		if (!type) throw new IllegalArgumentException("Argument 'type' [" + type + "] must not be 'null' nor 'undefined'.", this, arguments);
		if (!stack) throw new IllegalArgumentException("Argument 'stack' [" + stack + "] must not be 'null' nor 'undefined'.", this, arguments);
		this.type = type;
		this.stack = stack;
	}
	
	/**
	 * Returns the type that all values in the wrapped stack have.
	 * 
	 * <p>This is the type passed-in on construction.
	 *
	 * @return the type that all values of the wrapped stack have
	 */
	public function getType(Void):Function {
		return type;
	}
	
	/**
	 * Pushes the passed-in value to this stack.
	 *
	 * <p>The value is only pushed if it is of the expected type.
	 * 
	 * @param value the value to push to this stack
	 * @throws IllegalArgumentException if the type of the passed-in {@code value} is
	 * invalid
	 */
	public function push(value):Void {
		validate(value);
		stack.push(value);
	}
	
	/**
	 * Removes and returns the lastly pushed value.
	 * 
	 * @return the lastly pushed value
	 * @throws org.as2lib.data.holder.EmptyDataHolderException if this stack is empty
	 */
	public function pop(Void) {
		return stack.pop();
	}
	
	/**
	 * Returns the lastly pushed value without removing it.
	 * 
	 * @return the lastly pushed value
	 * @throws org.as2lib.data.holder.EmptyDataHolderException if this stack is empty
	 */
	public function peek(Void) {
		return stack.peek();
	}
	
	/**
	 * Returns an iterator to iterate over the values of this stack.
	 *
	 * @return an iterator to iterate over this stack's values
	 * @see #toArray
	 */
	public function iterator(Void):Iterator {
		return stack.iterator();
	}
	
	/**
	 * Returns whether this stack is empty.
	 *
	 * @return {@code true} if this stack is empty else {@code false}
	 */
	public function isEmpty(Void):Boolean {
		return stack.isEmpty();
	}
	
	/**
	 * Returns the number of pushed values.
	 *
	 * @return the number of pushed values
	 * @see #push
	 */
	public function size(Void):Number {
		return stack.size();
	}
	
	/**
	 * Returns an array representation of this stack.
	 * 
	 * <p>The elements are copied onto the array in a 'last-in, first-out' order, similar
	 * to the order of the elements returned by a succession of calls to the {@link #pop}
	 * method.
	 *
	 * @return the array representation of this stack
	 */
	public function toArray(Void):Array {
		return stack.toArray();
	}
	
	/**
	 * Returns the string representation of the wrapped stack.
	 *
	 * @return the string representation of the wrapped stack
	 */
	public function toString():String {
		return stack.toString();
	}
	
	/**
	 * Validates the passed-in {@code value} based on its type.
	 *
	 * @param value the value whose type to validate
	 * @throws IllegalArgumentException if the type of the value is invalid
	 */
	private function validate(value):Void {
		if (!ObjectUtil.typesMatch(value, type)) {
			throw new IllegalArgumentException("Type mismatch between value [" + value + "] and type [" + ReflectUtil.getTypeNameForType(type) + "].", this, arguments);
		}
	}
	
}