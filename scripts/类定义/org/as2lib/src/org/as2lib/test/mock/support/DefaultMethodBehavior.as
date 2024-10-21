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

import org.as2lib.core.BasicClass;
import org.as2lib.env.except.IllegalArgumentException;
import org.as2lib.env.except.IllegalStateException;
import org.as2lib.test.mock.MethodCallRangeError;
import org.as2lib.test.mock.MethodBehavior;
import org.as2lib.test.mock.MethodResponse;
import org.as2lib.test.mock.MethodCallRange;
import org.as2lib.test.mock.MethodCall;
import org.as2lib.test.mock.ArgumentsMatcher;

/**
 * {@code DefaultMethodBehavior} stores the expected and actual behaviors of one
 * method and verifies the expectation against the actual method calls.
 *
 * @author Simon Wacker
 */
class org.as2lib.test.mock.support.DefaultMethodBehavior extends BasicClass implements MethodBehavior {
	
	/** The expected method call. */
	private var expectedMethodCall:MethodCall;
	
	/** The actual method calls. */
	private var actualMethodCalls:Array;
	
	/** The method call ranges. */
	private var methodCallRanges:Array;
	
	/** The method responses. */
	private var methodResponses:Array;
	
	/**
	 * Constructs a new {@code DefaultMethodBehavior} instance with the passed-in
	 * {@code methodCall}.
	 *
	 * <p>A {@code expectedMethodCall} of value {@code null} means that this behavior
	 * expects no actual method calls.
	 * 
	 * @param expectedMethodCall the expected method call this behavior registers
	 * expectations, actual calls and responses for
	 */
	public function DefaultMethodBehavior(expectedMethodCall:MethodCall) {
		this.expectedMethodCall = expectedMethodCall;
		actualMethodCalls = new Array();
		methodCallRanges = new Array();
		methodResponses = new Array();
	}
	
	/**
	 * Returns the expected method call.
	 *
	 * @return the expected method call
	 */
	public function getExpectedMethodCall(Void):MethodCall {
		return expectedMethodCall;
	}
	
	/**
	 * Adds an actual method call.
	 *
	 * <p>The method call is added if it is not {@code null} and if it matches the
	 * expected method call.
	 *
	 * @param actualMethodCall the new actual method call to add
	 * @throws IllegalArgumentException if the passed-in {@code methodCall} is
	 * {@code null}
	 * @throws AssertionFailedError if no method call was expected or if the
	 * {@code actualMethodCall} does not match the expected method call or if the
	 * total maximum call count has been exceeded
	 */
	public function addActualMethodCall(actualMethodCall:MethodCall):Void {
		if (!actualMethodCall) throw new IllegalArgumentException("Actual method call is not allowed to be null or undefined.", this, arguments);
		if (!expectedMethodCall.matches(actualMethodCall) && expectedMethodCall) {
			var error:MethodCallRangeError = new MethodCallRangeError("Unexpected method call", this, arguments);
			error.addMethodCall(actualMethodCall, new MethodCallRange(0), new MethodCallRange(1));
			error.addMethodCall(expectedMethodCall, new MethodCallRange(getTotalMinimumMethodCallCount(), getTotalMaximumMethodCallCount()), new MethodCallRange(actualMethodCalls.length));
			throw error;
		}
		actualMethodCalls.push(actualMethodCall);
		if (!expectedMethodCall) {
			var error:MethodCallRangeError = new MethodCallRangeError("Unexpected method call", this, arguments);
			error.addMethodCall(actualMethodCall, new MethodCallRange(0), new MethodCallRange(actualMethodCalls.length));
			throw error;
		}
		if (actualMethodCalls.length > getTotalMaximumMethodCallCount()) {
			var error:MethodCallRangeError = new MethodCallRangeError("Unexpected method call", this, arguments);
			error.addMethodCall(actualMethodCall, new MethodCallRange(getTotalMinimumMethodCallCount(), getTotalMaximumMethodCallCount()), new MethodCallRange(actualMethodCalls.length));
			throw error;
		}
	}
	
	/**
	 * Returns the total minimum call count.
	 *
	 * @return the total minimum call count
	 */
	private function getTotalMinimumMethodCallCount(Void):Number {
		if (!expectedMethodCall) return 0;
		if (methodCallRanges.length < 1) return 1;
		var result:Number = 0;
		for (var i:Number = 0; i < methodCallRanges.length; i++) {
			result += MethodCallRange(methodCallRanges[i]).getMinimum();
		}
		return result;
	}
	
	/**
	 * Returns the total maximum call count.
	 *
	 * @return the total maximum call count
	 */
	private function getTotalMaximumMethodCallCount(Void):Number {
		if (!expectedMethodCall) return 0;
		if (methodCallRanges.length < 1) return 1;
		var result:Number = 0;
		for (var i:Number = 0; i < methodCallRanges.length; i++) {
			result += MethodCallRange(methodCallRanges[i]).getMaximum();
		}
		return result;
	}

	/**
	 * Adds the new {@code methodResponse} together with the {@code methodCallRange}
	 * that indicates when and how often the response shall take place.
	 *
	 * <p>If you set no response, the behavior expects exactly one method call.
	 *
	 * @param methodResponse the response to do a given number of times
	 * @param methodCallRange the range that indicates how often the response can take
	 * place
	 *
	 * @throws IllegalStateException if the expected method call is {@code null}
	 */
	public function addMethodResponse(methodResponse:MethodResponse, methodCallRange:MethodCallRange):Void {
		if (!expectedMethodCall) throw new IllegalStateException("It is not possible to set a response for an not-expected method call.", this, arguments);
		methodResponses.push(methodResponse);
		methodCallRanges.push(methodCallRange);
	}
	
	/**
	 * Sets the passed-in {@code argumentsMatcher} for the expected method call.
	 * 
	 * @param argumentsMatcher the arguments matcher for the expected method call
	 */
	public function setArgumentsMatcher(argumentsMatcher:ArgumentsMatcher):Void {
		expectedMethodCall.setArgumentsMatcher(argumentsMatcher);
	}
	
	/**
	 * Checks whether this behavior expects another method call.
	 *
	 * @return {@code true} if a further method call is expected else {@code false}
	 */
	public function expectsAnotherMethodCall(Void):Boolean {
		if (!expectedMethodCall) return false;
		if (methodCallRanges.length < 1) {
			if (actualMethodCalls.length < 1) return true;
			else return false;
		}
		return (getCurrentMethodCallRangeIndex() > -1);
	}
	
	/**
	 * Returns the current position in the method call range array.
	 *
	 * @return the current position in the method call range array
	 */
	private function getCurrentMethodCallRangeIndex(Void):Number {
		var maximum:Number = 0;
		for (var i:Number = 0; i < methodCallRanges.length; i++) {
			var methodCallRange:MethodCallRange = methodCallRanges[i];
			if (methodCallRange) {
				maximum += methodCallRange.getMaximum();
			} else {
				maximum += Number.POSITIVE_INFINITY;
			}
			if (actualMethodCalls.length < maximum) {
				return i;
			}
		}
		return -1;
	}
	
	/**
	 * Responses depending on the current number of actual method calls.
	 *
	 * @return the response's return value
	 * @throw the response's throwable
	 */
	public function response(Void) {
		return MethodResponse(methodResponses[getCurrentMethodResponseIndex()]).response();
	}
	
	/**
	 * Returns the current position in the method response array.
	 *
	 * @return the current position in the method response array
	 */
	private function getCurrentMethodResponseIndex(Void):Number {
		var maximum:Number = 0;
		for (var i:Number = 0; i < methodCallRanges.length; i++) {
			maximum += MethodCallRange(methodCallRanges[i]).getMaximum();
			if (actualMethodCalls.length <= maximum) {
				return i;
			}
		}
		return -1;
	}
	
	/**
	 * Verifies that the expactations have been met.
	 *
	 * @throws AssertionFailedError if the verification fails
	 */
	public function verify(Void):Void {
		if (actualMethodCalls.length < getTotalMinimumMethodCallCount()) {
			var error:MethodCallRangeError = new MethodCallRangeError("Expectation failure on verify", this, arguments);
			error.addMethodCall(expectedMethodCall, new MethodCallRange(getTotalMinimumMethodCallCount(), getTotalMaximumMethodCallCount()), new MethodCallRange(actualMethodCalls.length));
			throw error;
		}
	}
	
}