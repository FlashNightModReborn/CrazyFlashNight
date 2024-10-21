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
import org.as2lib.env.except.IllegalStateException;
import org.as2lib.env.except.IllegalArgumentException;
import org.as2lib.test.mock.MockControlState;
import org.as2lib.test.mock.MethodBehavior;
import org.as2lib.test.mock.Behavior;
import org.as2lib.test.mock.MethodCallRange;
import org.as2lib.test.mock.MethodCall;
import org.as2lib.test.mock.MethodResponse;
import org.as2lib.test.mock.ArgumentsMatcher;

/**
 * {@code ReplayState} replays behavior.
 *
 * @author Simon Wacker
 */
class org.as2lib.test.mock.support.ReplayState extends BasicClass implements MockControlState {
	
	/** Used to verify the expectations and to store actual method calls. */
	private var behavior:Behavior;
	
	/**
	 * Constructs a new {@code ReplayState} instance.
	 *
	 * @param behavior used to verify the expectations and to store actual method
	 * calls
	 * @throws IllegalArgumentException if the passed-in {@code behavior} is
	 * {@code null}
	 */
	public function ReplayState(behavior:Behavior) {
		if (!behavior) throw new IllegalArgumentException("Behavior is not allowed to be null or undefined.", this, arguments);
		this.behavior = behavior;
	}
	
	/**
	 * Returns the behavior set during instantiation.
	 * 
	 * @return the behavior
	 */
	public function getBehavior(Void):Behavior {
		return behavior;
	}
	
	/**
	 * Registers the actual {@code methodCall} in the method behavior if it was
	 * expected or registers a new unexpected method call.
	 *
	 * @return the value returned by the method behaviour's response method
	 * @throws * the exception thrown by the method behaviour's response method
	 */
	public function invokeMethod(methodCall:MethodCall) {
		var methodBehavior:MethodBehavior = behavior.getMethodBehavior(methodCall);
		if (methodBehavior) {
			methodBehavior.addActualMethodCall(methodCall);
			return methodBehavior.response();
		} else {
			methodBehavior = behavior.createMethodBehavior(null);
			if (methodCall.getMethodName() && methodCall.getMethodName() != "") {
				behavior.addMethodBehavior(methodCall.getMethodName(), methodBehavior);
			} else {
				behavior.addMethodBehavior("[unknown]", methodBehavior);
			}
			methodBehavior.addActualMethodCall(methodCall);
			return methodBehavior.response();
		}
	}
	
	/**
	 * Forwards the verification to the behavior of the mock.
	 */
	public function verify(Void):Void {
		behavior.verify();
	}
	
	/**
	 * @throws IllegalStateException
	 */ 
	public function setMethodResponse(methodResponse:MethodResponse, methodCallRange:MethodCallRange):Void {
		throw new IllegalStateException("Method must not be called in replay state.", this, arguments);
	}
	
	/**
	 * @throws IllegalStateException
	 */
	public function setArgumentsMatcher(argumentsMatcher:ArgumentsMatcher):Void {
		throw new IllegalStateException("Method must not be called in replay state.", this, arguments);
	}
	
}