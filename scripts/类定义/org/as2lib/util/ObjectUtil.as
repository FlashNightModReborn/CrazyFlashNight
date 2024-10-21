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
import org.as2lib.Config;
import org.as2lib.util.ClassUtil;
import org.as2lib.util.ArrayUtil;
import org.as2lib.util.Comparable;

/**
 * {@code ObjectUtil} contains fundamental methods to efficiently and easily work
 * with any type of object.
 * 
 * @author Simon Wacker
 * @author Martin Heidegger
 */
class org.as2lib.util.ObjectUtil extends BasicClass {
	
	/**
	 * Constant for objects of type string.
	 * 
	 * @see #isTypeOf
	 */
	public static var TYPE_STRING:String = "string";
	
	/**
	 * Constant for objects for type number.
	 * 
	 * @see #isTypeOf
	 */
	public static var TYPE_NUMBER:String = "number";
	
	/**
	 * Constant for objects of type object.
	 * 
	 * @see #isTypeOf
	 */
	public static var TYPE_OBJECT:String = "object";
	
	/**
	 * Constant for objects of type boolean.
	 * 
	 * @see #isTypeOf
	 */
	public static var TYPE_BOOLEAN:String = "boolean";
	
	/**
	 * Constant for objects of type movieclip.
	 * 
	 * @see #isTypeOf
	 */
	public static var TYPE_MOVIECLIP:String = "movieclip";
	
	/**
	 * Constant for objects of type function.
	 * 
	 * @see #isTypeOf
	 */
	public static var TYPE_FUNCTION:String = "function";
	
	/**
	 * Constant for the value undefined.
	 * 
	 * @see #isTypeOf
	 */
	public static var TYPE_UNDEFINED:String = "undefined";
	
	/**
	 * Constant for the value null.
	 * 
	 * @see #isTypeOf
	 */
	public static var TYPE_NULL:String = "null";
	
	/**
	 * Stringifies the passed-in {@code object} using the stringifier returned by the
	 * static {@link Config#getObjectStringifier} method.
	 * 
	 * @param object the object to stringify
	 * @return the string representation of the passed-in {@code object}
	 */
	public static function stringify(object):String {
		return Config.getObjectStringifier().execute(object);
	}
	
	/**
	 * Checks if the type of the passed-in {@code object} matches the passed-in 
	 * {@code type}.
	 * 
	 * <p>Every value (even {@code null} and {@code undefined}) matches type
	 * {@code Object}.
	 *
	 * <p>Instances as well as their primitive correspondent match the types 
	 * {@code String}, {@code Number} or {@code Boolean}.
	 * 
	 * @param object the object whose type to compare with the passed-in {@code type}
	 * @param type the type to use for the comparison
	 * @return {@code true} if the type of the {@code object} matches the passed-in
	 * {@code type} else {@code false}
	 */
	public static function typesMatch(object, type:Function):Boolean {
		if (type === Object) {
			return true;
		}
		if (isPrimitiveType(object)) {
			var t:String = typeof(object);
			// Workaround for former used: typesMatch(type(object), object);
			// Casting is not a good solution, it will break if the Constructor throws a error!
			// This solution is not the fastest but will not break by any exception.
			if ((type === String || ClassUtil.isSubClassOf(type, String)) && t == TYPE_STRING) {
				return true;
			}
			if ((type === Boolean || ClassUtil.isSubClassOf(type, Boolean)) && t == TYPE_BOOLEAN) {
				return true;
			}
			if ((type === Number || ClassUtil.isSubClassOf(type, Number)) && t == TYPE_NUMBER) {
				return true;
			}
			return false;
		} else {
			return (isInstanceOf(object, type));
		}
	}
	
	/**
	 * Compares the results of an execution of the {@code typeof} method applied to
	 * both passed-in objects.
	 * 
	 * @param firstObject the first object of the comparison
	 * @param secondObject the second object of the comparison
	 * @return {@code true} if the execution of the {@code typeof} method returns the 
	 * same else {@code false}
	 */
	public static function compareTypeOf(firstObject, secondObject):Boolean {
		return (typeof(firstObject) == typeof(secondObject));
	}
	
	/**
	 * Checks if the passed-in {@code object} is a primitive type.
	 *
	 * <p>Primitive types are strings, numbers and booleans that are not created via the
	 * new operator. For example {@code "myString"}, {@code 3} and {@code true} are
	 * primitive types, but {@code new String("myString")}, {@code new Number(3)} and
	 * {@code new Boolean(true)} are not.
	 * 
	 * @param object the object to check whether it is a prmitive type
	 * @return {@code true} if {@code object} is a primitive type else {@code false}
	 */
	public static function isPrimitiveType(object):Boolean {
		var t:String = typeof(object);
		return (t == TYPE_STRING || t == TYPE_NUMBER || t == TYPE_BOOLEAN);
	}
	
	/**
	 * Checks if the result of an execution of the {@code typeof} method on the
	 * passed-in {@code object} matches the passed-in {@code type}.
	 * 
	 * <p>All possible types are available as constants.
	 *
	 * @param object the object whose type to check
	 * @param type the string representation of the type
	 * @return {@code true} if the object is of the given {@code type}
	 * @see #TYPE_STRING
	 * @see #TYPE_NUMBER
	 * @see #TYPE_OBJECT
	 * @see #TYPE_BOOLEAN
	 * @see #TYPE_MOVIECLIP
	 * @see #TYPE_NULL
	 * @see #TYPE_UNDEFINED
	 */
	public static function isTypeOf(object, type:String):Boolean {
		return (typeof(object) == type);
	}
	
	/**
	 * Checks if the passed-in {@code object} is an instance of the passed-in
	 * {@code type}.
	 * 
	 * <p>If the passed-in {@code type} is {@code Object}, {@code true} will always be
	 * returned, because every object is an instance of {@code Object}, even {@code null}
	 * and {@code undefined}.
	 * 
	 * @param object the object to check
	 * @param type the type to check whether the {@code object} is an instance of
	 * @return {@code true} if the passed-in {@code object} is an instance of the given
	 * {@code type} else {@code false}
	 */
	public static function isInstanceOf(object, type:Function):Boolean {
		if (type === Object) {
			return true;
		}
		return (object instanceof type);
	}
	
	/**
	 * Checks if the passed-in {@code object} is an explicit instance of the passed-in
	 * {@code clazz}.
	 * 
	 * <p>That means that {@code true} will only be returned if the object was instantiated
	 * directly from the given {@code clazz}.
	 * 
	 * @param object the object to check whether it is an explicit instance of {@code clazz}
	 * @param clazz the class to use as the basis for the check
	 * @return {@code true} if the object is an explicit instance of {@code clazz} else
	 * {@code false}
	 */
	public static function isExplicitInstanceOf(object, clazz:Function):Boolean {
		if (isPrimitiveType(object)) {
			if (clazz == String) {
				return (typeof(object) == TYPE_STRING);
			}
			if (clazz == Number) {
				return (typeof(object) == TYPE_NUMBER);
			}
			if (clazz == Boolean) {
				return (typeof(object) == TYPE_BOOLEAN);
			}
		}
		return (object instanceof clazz	&& !(object.__proto__ instanceof clazz));
	}
	
	/**
	 * Checks if two passed-in parameters are equal.
	 * 
	 * <p>It uses different strategies by the first passed-in {@code obj1}.
	 *   <ul>
	 *     <li>If {@code obj1} is a primitive it compares it with == operator.</li>
	 *     <li>If {@code obj1} implements {@link Comparable} it calls {@code compare()}
	 *         to compare both passed-in parameters</li>
	 *     <li>Any different case compares the structure of both objects.</li>
	 *   </ul>
	 *   
	 * <p>It compares complex objects (that do not implement {@code Comparable})
	 * only if they are instances of the same class. A different class (even
	 * if its only a extended class) will be handled as not equal.
	 * 
	 * <p>It compares complex objects recursivly. It handles back references in 
	 * a proper way.
	 * 
	 * @param obj1 object to be compared
	 * @param obj2 object to compare with passed-in {@code obj1}
	 * @return {@code true} if both parameters are equal
	 */
	public static function compare(obj1, obj2):Boolean {
		return compareRecursive(obj1, obj2, [], []);
	}
	
	/**
	 * Compares recursivly (for objects) if the structure matches.
	 * 
	 * @param obj1 object to compare with a different object.
	 * @param obj2 object to be compared with {@code obj1}.
	 * @param stack1 recursive stack to check endless recursions for the {@code obj1}
	 * @param stack2 recursive stack to check endless recursions for the {@code obj2}
	 * @return {@code true} if both paramerters are equal
	 */
	private static function compareRecursive(obj1, obj2, stack1:Array, stack2:Array):Boolean {
		if (typeof obj1 == "object"
			&& !(   obj1 instanceof String
			     || obj1 instanceof Number
			     || obj1 instanceof Boolean)) {
			if (obj1 === obj2) {
				return true;
			}
			if (obj1 instanceof Comparable) {
				var c:Comparable = obj1;
				return c.compare(obj2);
			}
			if (obj1.__proto__ == obj2.__proto__) {
				var index:Number = ArrayUtil.lastIndexOf(stack1, obj1);
				if (index > -1) {
					if (obj2 == stack2[index]) {
						return true;
					}
				}
				stack1.push(obj1);
				stack2.push(obj2);
				var i:String;
				for (i in obj1) {
					if (!compareRecursive (obj1[i], obj2[i], stack1, stack2)) {
						return false;
					}
				}
				stack1.pop();
				stack2.pop();
				return true;
			} else {
				return false;
			}
		} else {
			return (obj1 == obj2);
		}
	}
	
	/**
	 * Private constructor.
	 */
	private function ObjectUtil(Void) {
	}
	
}