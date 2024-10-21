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

/**
 * {@code MethodResponse} holds and carries out the response if requested.
 *
 * @author Simon Wacker
 */
class org.as2lib.test.mock.MethodResponse extends BasicClass {
	
	/** Return value to return. */
	private var returnValue;
	
	/** Throwable to throw. */
	private var throwable;
	
	/**
	 * Constructs a new {@code MethodResponse} instance.
	 */
	public function MethodResponse(Void) {
	}
	
	/**
	 * Sets the return value that is returned when invoking the {@link #response}
	 * method.
	 *
	 * <p>Setting a return value disables the throwable behavior.
	 *
	 * @param returnValue the return value to return
	 */
	public function setReturnValue(returnValue):Void {
		throwable = undefined;
		this.returnValue = returnValue;
	}
	
	/**
	 * Sets the throwable to throw when the {@link #response} method is invoked.
	 *
	 * <p>Setting a throwable disables the return value behavior.
	 *
	 * @param throwable the throwable to throw
	 */
	public function setThrowable(throwable):Void {
		returnValue = undefined;
		this.throwable = throwable;
	}
	
	/**
	 * Returns the set return value or throws the set throwable. If both have been set
	 * the one that has been set at last will be used.
	 *
	 * @return the set return value
	 * @throws the set throwable
	 */
	public function response(Void) {
		if (returnValue !== undefined) return returnValue;
		if (throwable !== undefined) throw throwable;
	}
	
}