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
import org.as2lib.util.ObjectUtil;
import org.as2lib.env.except.IllegalArgumentException;
import org.as2lib.env.reflect.ReflectUtil;

/**
 * {@code TypedArray} acts like a normal array but assures that only objects of a
 * specific type are added to the array.
 * 
 * <p>Note that elements that are added to this array using the dot-syntax do not
 * get type-checked. For example:
 * <code>
 *   myArray[0] = "value1";
 *   // or
 *   myArray.myProp = "value2"; // myArray["myProp"] = "value2";
 * </code>
 *
 * <p>Example:
 * <code>
 *   var array:Array = new TypedArray(Number);
 *   array.push(0);
 *   array.push(1);
 *   array.push(2);
 *   // throws an IllegalArgumentException because the element is not of the expected type
 *   array.push("myString");
 * </code>
 *
 * <p>You can also construct your array the following way:
 * <code>
 *   var array:Array = new TypedArray(Number, 0, 1, 2);
 * </code>
 * 
 * @author Simon Wacker
 * @author Martin Heidegger
 * @see <a href="http://livedocs.macromedia.com/flash/mx2004/main_7_2/wwhelp/wwhimpl/common/html/wwhelp.htm?context=Flash_MX_2004&file=00001191.html">Array class</a>
 */
class org.as2lib.data.holder.array.TypedArray extends Array implements BasicInterface {
	
	/** The type of the elements that can be added. */
	private var type:Function;
	
	/**
	 * Constructs a new {@code TypedArray} instance.
	 * 
	 * <p>You can optionally pass-in elements to populate this array with after the type
	 * parameter. These elements also get type-checked. For example:
	 * <code>
	 *   var array:Array = new TypedArray(Number, 1, 2, 3);
	 * </code>
	 *
	 * @param type the type of the elements this array expects
	 * @param .. any number of elements to populate this array with
	 */
	public function TypedArray(type:Function) {
		this.type = type;
		_global.ASSetPropFlags(this, ["type"], 1, true);
		if (arguments.length > 1) {
			arguments.shift();
			push.apply(this, arguments);
		}
	}
	
	/**
	 * Returns the type all elements of this array have.
	 *
	 * <p>This is the type passed-in on construction.
	 *
	 * @return the type all elements of this array have
	 */
	public function getType(Void):Function {
		return type;
	}
	
	/**
	 * Concatenates the elements specified in the parameter list with the elements of
	 * this array and returns a new array containing these elements.
	 * 
	 * <p>This array itself is left unchanged.
	 * 
	 * <p>The returned array expects elements of the same type as this array does.
	 *
	 * <p>If you do not pass-in any elements a duplicate of this array gets returned.
	 * 
	 * @param .. any number of elements to concatenate the elements of this array with
	 * @return a new array that contains the elements of this array as well as the
	 * passed-in elements
	 * @see <a href="http://livedocs.macromedia.com/flash/mx2004/main_7_2/wwhelp/wwhimpl/common/html/wwhelp.htm?context=Flash_MX_2004&file=00001192.html#3988964">Array.concat()</a>
	 */
	public function concat():TypedArray {
		var result:TypedArray = new TypedArray(this.type);
		var i:Number = length;
		// Ignoring type checks within the same array.
		while(--i-(-1)) {
			result[i] = this[i];
		}
		
		// Performance Speed up - so the getter for the length isn't always used (useful with big arrays)
		var l:Number = arguments.length;
		for (var j:Number = 0; j < l; j-=-1) {
			var content = arguments[j];
			if (content instanceof Array) {
				// Performance Speed up - so the getter for the length isn't always used (useful with big arrays)
				var l2:Number = content.length;
				for (var k:Number = 0; k < l2; k-=-1) {
					result.push(content[k]);
				}
			} else {
				result.push(content);
			}
		}
		return result;
	}
	
	/**
	 * Adds one or more elements to the end of this array and returns the new length of
	 * this array.
	 * 
	 * <p>The passed-in elements get type-checked first. They will only be added if they
	 * are all of the correct type.
	 *
	 * @param value the new element to add to the end of this array
	 * @param .. any number of further elements to add to the end of this array
	 * @return the new length of this array
	 * 
	 * @throws IllegalArgumentException if one of the passed-in elements is of invalid
	 * type
	 * @see <a href="http://livedocs.macromedia.com/flash/mx2004/main_7_2/wwhelp/wwhimpl/common/html/wwhelp.htm?context=Flash_MX_2004&file=00001196.html#3989073">Array.push()</a>
	 */
	public function push(value):Number {
		if (arguments.length > 1) {
			var l:Number = arguments.length;
			for (var i:Number = 0; i < l; i++) {
				validate(arguments[i]);
			}
		} else {
			validate(value);
		}
		// cast needed for Flex compatibility
		return Number(super.push.apply(this, arguments));
	}
	
	/**
	 * Adds one or more elements to the beginning of this array and returns the new
	 * length of this array.
	 * 
	 * <p>The passed-in values get type-checked first. They will only be added if they
	 * are all of the correct type.
	 *
	 * @param value the new element to add to the beginning of this array
	 * @param .. any number of further elements to add to the beginning of this array
	 * @return the new length of this array
	 * @throws IllegalArgumentException if one of the passed-in elements is of invalid
	 * type
	 * @see <a href="http://livedocs.macromedia.com/flash/mx2004/main_7_2/wwhelp/wwhimpl/common/html/wwhelp.htm?context=Flash_MX_2004&file=00001204.html#3989452">Array.unshift()</a>
	 */
	public function unshift(value):Number {
		if (arguments.length > 1) {
			var l:Number = arguments.length;
			for (var i:Number = 0; i < l; i++) {
				validate(arguments[i]);
			}
		} else {
			validate(value);
		}
		// cast needed for Flex compatibility
		return Number(super.unshift.apply(this, arguments));
	}
	
	/**
	 * Returns the string representation of this array.
	 *
	 * @return the string representation of this array
	 */
	public function toString():String {
		return super.toString();
	}

	/**
	 * Validates the passed-in {@code object} based on its type.
	 * 
	 * @param object the object whose type to validate
	 * @throws IllegalArgumentException if the type of the {@code object} is invalid
	 */
	private function validate(object):Void {
		if (!ObjectUtil.typesMatch(object, type)) {
			throw new IllegalArgumentException("Type mismatch between object [" + object + "] and type [" + ReflectUtil.getTypeNameForType(type) + "].", this, arguments);
		}
	}
	
}