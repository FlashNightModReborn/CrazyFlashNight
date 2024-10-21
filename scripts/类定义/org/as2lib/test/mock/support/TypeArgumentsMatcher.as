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
import org.as2lib.util.ObjectUtil;
import org.as2lib.test.mock.ArgumentsMatcher;
import org.as2lib.test.mock.ArgumentMatcher;

/**
 * {@code TypeArgumentsMatcher} matches the actual arguments agains a list of types.
 * 
 * @author Simon Wacker
 */
class org.as2lib.test.mock.support.TypeArgumentsMatcher extends BasicClass implements ArgumentsMatcher {
	
	/** The expected types. */
	private var expectedTypes:Array;
	
	/**
	 * Constructs a new {@code TypeArgumentsMatcher} instance.
	 *
	 * <p>If a type in the {@code expectedType} array is {@code null} or
	 * {@code undefined} the expected and actual argument will be compared.
	 * 
	 * <p>If an element in the {@code expectedType} array is an instance of type
	 * {@link ArgumentMatcher}, this argument matcher will be used to check whether
	 * the actual argument is correct.
	 * 
	 * @param expectedTypes the expected types of the arguments
	 */
	public function TypeArgumentsMatcher(expectedTypes:Array) {
		this.expectedTypes = expectedTypes;
	}
	
	/**
	 * Compares the actual arguments only by type against the expected types given on
	 * contruction.
	 *
	 * <p>If a type of the expected types is {@code null} or {@code undefined} the
	 * expected and actual argument will be compared directly with the strict equals
	 * operator.
	 *
	 * <p>{@code false} will be returned if:
	 * <ul>
	 *   <li>The lengths of the expected and actual arguments differ.</li>
	 *   <li>The lengths of the expected types and the actual arguments differ.</li>
	 *   <li>Any actual argument is not of the expected type.</li>
	 * </ul>
	 *
	 * @param expectedArgumens the expected arguments
	 * @param actualArguments the actual arguments
	 */
	public function matchArguments(expectedArguments:Array, actualArguments:Array):Boolean {
		if (expectedArguments.length != actualArguments.length) return false;
		if (actualArguments.length != expectedTypes.length) return false;
		for (var i:Number = 0; i < expectedArguments.length; i++) {
			if (expectedTypes[i] == null) {
				if (expectedArguments[i] !== actualArguments[i]) {
					return false;
				}
			} else if (expectedTypes[i] instanceof ArgumentMatcher) {
				if (!ArgumentMatcher(expectedTypes[i]).matchArgument(actualArguments[i])) {
					return false;
				}
			} else {
				if (!ObjectUtil.typesMatch(actualArguments[i], expectedTypes[i])) {
					return false;
				}
			}
		}
		return true;
	}
	
}