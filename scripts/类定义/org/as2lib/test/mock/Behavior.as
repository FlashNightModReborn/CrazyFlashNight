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

import org.as2lib.core.BasicInterface;
import org.as2lib.test.mock.MethodBehavior;
import org.as2lib.test.mock.MethodCall;

/**
 * {@code Behavior} stores expected behaviors and exposes them for verification.
 * 
 * @author Simon Wacker
 */
interface org.as2lib.test.mock.Behavior extends BasicInterface {
	
	/**
	 * Adds the given {@code methodBehavior} behavior for the passed-in
	 * {@code methodName}.
	 *
	 * @param methodName the name of the method to register the {@code methodBehavior}
	 * with
	 * @param methodBehavior the method behavior to register
	 */
	public function addMethodBehavior(methodName:String, methodBehavior:MethodBehavior):Void;
	
	/**
	 * Creates a new method behavior for the passed-in {@code expectedMethodCall}.
	 *
	 * @param expectedMethodCall the method call to create a behavior for
	 * @return the created method behavior
	 */
	public function createMethodBehavior(expectedMethodCall:MethodCall):MethodBehavior;
	
	/**
	 * Returns a method behavior that matches the given {@code actualMethodCall}.
	 *
	 * @return a matching method behavior
	 */
	public function getMethodBehavior(actualMethodCall:MethodCall):MethodBehavior;
	
	/**
	 * Returns the lastly added method behavior.
	 *
	 * @return the lastly added method behavior
	 */
	public function getLastMethodBehavior(Void):MethodBehavior;
	
	/**
	 * Removes all added behaviors.
	 */
	public function removeAllBehaviors(Void):Void;
	
	/**
	 * Verifies all added behaviors.
	 */
	public function verify(Void):Void;
	
}