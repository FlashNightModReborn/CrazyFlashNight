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
import org.as2lib.test.mock.Behavior;
import org.as2lib.test.mock.MethodCallRange;
import org.as2lib.test.mock.MethodResponse;
import org.as2lib.test.mock.MethodCall;
import org.as2lib.test.mock.ArgumentsMatcher;

/**
 * {@code RecordState} records behaviors.
 *
 * @author Simon Wacker
 */
class org.as2lib.test.mock.support.RecordState extends BasicClass implements MockControlState {
	
	/** Used to add and get behaviors of the mock. */
	private var behavior:Behavior;
	
	/**
	 * Constructs a new {@code RecordState} instance.
	 *
	 * @param behavior the behavior to add and get behaviors of the mock
	 * @throws IllegalArgumentException if the passed-in {@code behavior} is
	 * {@code null}
	 */
	public function RecordState(behavior:Behavior) {
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
	 * Adds the expected {@code methodCall} to the expected behavior of the mock.
	 *
	 * @param methodCall contains all information about the method call
	 */
	public function invokeMethod(methodCall:MethodCall) {
		behavior.addMethodBehavior(methodCall.getMethodName(), behavior.createMethodBehavior(methodCall));
	}
	
	/**
	 * Sets the expectation that the lastly called method is called the passed-in
	 * number of times. When called between that range it responses the given way.
	 *
	 * @param methodResponse the response of the method during the expected call
	 * range
	 * @param methodCallRange the expected range of method calls
	 */ 
	public function setMethodResponse(methodResponse:MethodResponse, methodCallRange:MethodCallRange):Void {
		behavior.getLastMethodBehavior().addMethodResponse(methodResponse, methodCallRange);
	}
	
	/**
	 * Sets the arguments matcher for the lastly called method.
	 *
	 * <p>The arguments matcher is used by the expected method call to check whether
	 * it matches an actual method call.
	 *
	 * @param argumentsMatcher the new arguments matcher for the expected method call
	 */
	public function setArgumentsMatcher(argumentsMatcher:ArgumentsMatcher):Void {
		behavior.getLastMethodBehavior().setArgumentsMatcher(argumentsMatcher);
	}
	
	/**
	 * @throws IllegalStateException
	 */
	public function verify(Void):Void {
		throw new IllegalStateException("Method must not be called in record state.", this, arguments);
	}
	
}