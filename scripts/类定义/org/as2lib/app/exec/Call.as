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
import org.as2lib.env.except.IllegalArgumentException;
import org.as2lib.env.reflect.ReflectUtil;
import org.as2lib.app.exec.ForEachExecutable;
import org.as2lib.util.AccessPermission;

/**
 * {@code Call} enables another object to call a method in another scope without
 * having to know the scope.
 * 
 * <p>This enables you to pass a call to another object and let the object execute
 * the call without losing its scope. You use the {@link #execute} method to do so.
 *
 * @author Simon Wacker
 * @author Martin Heidegger
 */
class org.as2lib.app.exec.Call extends BasicClass implements ForEachExecutable {
	
	/** The object to execute the method on. */
	private var object;
	
	/** The method to execute on the object. */
	private var method:Function;
	
	/**
	 * Constructs a new {@code Call} instance.
	 *
	 * @param object the object to execute the method on
	 * @param method the method to execute
	 * @throws IllegalArgumentException if either {@code object} or {@code method} is 
	 * {@code null} or {@code undefined}
	 */
	public function Call(object, method:Function) {
		if (object == null) {
			throw new IllegalArgumentException("Required parameter 'object' is null or undefined.", this, arguments);
		}
		if (method == null) {
			throw new IllegalArgumentException("Required parameter 'method' is null or undefined.", this, arguments);
		}
		this.object = object;
		this.method = method;
	}
	
	/**
	 * Executes the method on the object passing the given {@code arguments} and returns the
	 * result of the execution.
	 * 
	 * @return the result of the method execution
	 */
	public function execute() {
		return method.apply(object, arguments);
	}
	
	/**
	 * Iterates over the passed-in {@code object} using the for..in loop and executes
	 * this call passing the found member, its name and the passed-in {@code object}.
	 * 
	 * <p>Example:
	 * <code>
	 *   class MyClass {
	 * 
	 *       private var a:String;
	 *       private var b:String;
	 *       private var c:String;
	 * 
	 *       public function MyClass() {
	 *           a = "1";
	 *           b = "2";
	 *           c = "2";
	 *       }
	 *      
	 *       public function traceObject(value, name:String, inObject):Void {
	 *           trace(name + ": " + value);
	 *       }
	 * 
	 *       public function listAll() {
	 *           new Call(this, traceObject).forEach(this);
	 *       }
	 *   }
	 * </code>
	 *
	 * <p>Note that only members visible to for..in loops cause the {@link #execute}
	 * method to be invoked.
	 * 
	 * @param object the object to iterate over
	 */
	public function forEach(object):Array {
		var i:String;
		var result:Array = new Array();
		for (i in object) {
			try {
				result.push(execute(object[i], i, object));
			} catch(e) {
				
			}
		}
		return result;
	}
	
	/**
	 * Returns the string representation of this call.
	 * 
	 * @return the string representation of this call
	 */
	public function toString():String {
		// TODO: Refactor the code and outsource it.
		var result:String="";
		result += "[type " + ReflectUtil.getTypeNameForInstance(this) + " -> ";
		AccessPermission.set(object, null, AccessPermission.ALLOW_ALL);
		var methodName:String = ReflectUtil.getMethodName(method, object);
		if (ReflectUtil.isMethodStatic(methodName, object)) {
			result += "static ";
		}
		if (object == null) {
			result += object.toString();
		} else {
			var className:String = ReflectUtil.getTypeName(object);
			if (className) {
				result += className;
			} else {
				result += object.toString();
			}
		}
		result += "." + methodName;
		result += "()]";
		return result;
	}
	
}