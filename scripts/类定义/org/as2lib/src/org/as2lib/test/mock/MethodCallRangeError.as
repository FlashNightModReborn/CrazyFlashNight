/**
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

import org.as2lib.test.mock.AssertionFailedError;
import org.as2lib.test.mock.MethodCall;
import org.as2lib.test.mock.MethodCallRange;
import org.as2lib.env.reflect.ReflectUtil;

/**
 * {@code MethodCallRangeError} is thrown if the expected method call range has not
 * been met.
 * 
 * @author Simon Wacker
 */
class org.as2lib.test.mock.MethodCallRangeError extends AssertionFailedError {
	
	/** The method calls. */
	private var methodCalls:Array;
	
	/** The expected call range. */
	private var expectedMethodCallRanges:Array;
	
	/** The actual call range. */
	private var actualMethodCallRanges:Array;
	
	/** Type of the mock. */
	private var type:Function;
	
	/**
	 * Constructs a new {@code MethodCallRangeError} instance.
	 * 
	 * <p>All arguments are allowed to be {@code null} or {@code undefined}. But if
	 * one is, the string representation returned by the {@code toString} method will
	 * not be complete.
	 *
	 * <p>The {@code args} array should be the internal arguments array of the method
	 * that throws the throwable. The internal arguments array exists in every method
	 * and contains its parameters, the callee method and the caller method. You can
	 * refernce it in every method using the name {@code "arguments"}.
	 * 
	 * @param message the message that describes the problem in detail
	 * @param thrower the object that declares the method that throws this fatal
	 * exception
	 * @param args the arguments of the throwing method
	 */
	public function MethodCallRangeError(message:String, thrower, args:Array) {
		super (message, thrower, args);
		methodCalls = new Array();
		expectedMethodCallRanges = new Array();
		actualMethodCallRanges = new Array();
	}
	
	/**
	 * Adds a new method call together with its expected and actual call range.
	 *
	 * @param methodCall the new method call
	 * @param expectedMethodCallRange the expected method call range
	 * @param actualMethodCallRange the actual method call range
	 */
	public function addMethodCall(methodCall:MethodCall, expectedMethodCallRange:MethodCallRange, actualMethodCallRange:MethodCallRange):Void {
		methodCalls.push(methodCall);
		expectedMethodCallRanges.push(expectedMethodCallRange);
		actualMethodCallRanges.push(actualMethodCallRange);
	}
	
	/**
	 * Sets the type of the mock that did not met all expectations.
	 * 
	 * @param type the type of the mock	 */
	public function setType(type:Function):Void  {
		this.type = type;
	}
	
	/**
	 * Returns the string representation of this error.
	 *
	 * @return the string representation of this error
	 */
	public function doToString(Void):String {
		var message:String = getMessage() + ":";
		for (var i:Number = 0; i < methodCalls.length; i++) {
			message += "\n  ";
			if (type !== undefined && type !== null) {
				message += ReflectUtil.getTypeNameForType(type) + ".";
			}
			message += methodCalls[i] + ": expected: " + expectedMethodCallRanges[i] + ", actual: " + actualMethodCallRanges[i];
		}
		return message;
	}
	
}