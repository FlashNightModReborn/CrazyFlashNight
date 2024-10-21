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
import org.as2lib.util.StringUtil;
import org.as2lib.data.holder.Map;
import org.as2lib.data.holder.map.PrimitiveTypeMap;
import org.as2lib.env.except.IllegalArgumentException;
import org.as2lib.test.mock.ArgumentMatcher;

/**
 * {@code StateArgumentMatcher} checks whether one argument is in an expected state.
 * 
 * @author Simon Wacker
 */
class org.as2lib.test.mock.support.StateArgumentMatcher extends BasicClass implements ArgumentMatcher {
	
	/** The expected type. */
	private var expectedType:Function;
	
	/** The expected properties. */
	private var expectedProperties:Map;
	
	/**
	 * Constructs a new {@code StateArgumentMatcher} instance.
	 * 
	 * <p>If every type is allowed, specifc {@code Object} as expected type.
	 * 
	 * @param expectedType the expected type of the argument
	 * @throws IllegalArgumentException if {@code type} is {@code null} or
	 * {@code undefined}
	 */
	public function StateArgumentMatcher(expectedType:Function) {
		if (!expectedType) throw new IllegalArgumentException("Argument 'expectedType' [" + expectedType + "] must not be 'null' nor 'undefined'.", this, arguments);
		this.expectedType = expectedType;
		this.expectedProperties = new PrimitiveTypeMap();
	}
	
	/**
	 * Adds a new property the argument is expected to have.
	 * 
	 * @param propertyName the name of the expected property
	 * @param propertyValue the value of the expected property
	 * @see #checkProperty	 */
	public function addExpectedProperty(propertyName:String, propertyValue):Void {
		this.expectedProperties.put(propertyName, propertyValue);
	}
	
	/**
	 * Checks whether the passed-in {@code argument} is in the expected state.
	 * 
	 * <p>{@code false} will be returned if:
	 * <ul>
	 *   <li>{@code argument} is {@code null} or {@code undefined}.</li>
	 *   <li>{@code argument} is not of the expected type.</li>
	 *   <li>{@code argument} is not in the expected state.</li>
	 * </ul>
	 * 
	 * @param argument the argument to check whether it is in the expected state
	 * @return {@code true} if the argument is in the expected state else {@code false}	 */
	public function matchArgument(argument):Boolean {
		if (!argument) return false;
		if (!(argument instanceof this.expectedType)) return false;
		var keys:Array = this.expectedProperties.getKeys();
		var values:Array = this.expectedProperties.getValues();
		for (var i:Number = 0; i < keys.length; i++) {
			if (!checkProperty(argument, keys[i], values[i])) {
				return false;
			}
		}
		return true;
	}
	
	/**
	 * Checks whether the value of the property with name {@code propertyName} on the
	 * passed-in {@code target} matches the {@code expectedPropertyValue}.
	 * 
	 * <p>It is first checked whether a getter method with the passed-in
	 * {@code propertyName} exists. If so it will be used to get the property value
	 * that is then compared with the {@code expectedPropertyValue}. Otherwise the
	 * {@code propertyName} will be used directly and its value will be compared with
	 * the {@code expectedPropertyValue}.
	 * 
	 * @param target the target object that declares the property
	 * @param propertyName the name of the property
	 * @param expectedPropertyValue the expected value of the property
	 * @return {@code true} if the property has the expected value else {@code false}	 */
	private function checkProperty(target, propertyName:String, expectedPropertyValue):Boolean {
		var getter:String = "get" + StringUtil.ucFirst(propertyName);
		if (target[getter]) {
			return (target[getter]() === expectedPropertyValue);
		}
		return (target[propertyName] === expectedPropertyValue);
	}
	
}