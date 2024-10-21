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

import org.as2lib.env.except.IllegalArgumentException;
import org.as2lib.env.reflect.PropertyInfo;
import org.as2lib.aop.joinpoint.PropertyJoinPoint;

/**
 * {@code GetPropertyJoinPoint} is a join point matching get access to a property. It
 * represents the getter method of a property.
 * 
 * @author Simon Wacker
 */
class org.as2lib.aop.joinpoint.GetPropertyJoinPoint extends PropertyJoinPoint {
	
	/**
	 * Constructs a new {@code GetPropertyJoinPoint) instance.
	 * 
	 * @param info the property info of the represented property
	 * @param thiz the logical this of the interception
	 * @throws IllegalArgumentException if argument {@code info} is {@code null} or
	 * {@code undefined}
	 * @throws IllegalArgumentException if argument {@code info} reflects a not-readable
	 * property
	 * @see <a href="http://www.simonwacker.com/blog/archives/000068.php">Passing Context</a>
	 */
	public function GetPropertyJoinPoint(info:PropertyInfo, thiz) {
		super(info, thiz);
		if (!info.isReadable()) {
			throw new IllegalArgumentException("Argument 'info' [" + info + "] reflects a not-readable property. Get access is not possible for this kind of property.", this, arguments);
		}
	}
	
	/**
	 * Proceeds this join point by executing the getter of the represented property
	 * with the given arguments and returning the result of the execution.
	 * 
	 * @param args the arguments to use for the execution
	 * @return the result of the execution
	 */
	public function proceed(args:Array) {
		return proceedMethod(this.info.getGetter(), args);
	}
	
	/**
	 * Returns the type of this property.
	 * 
	 * @return {@link AbstractJoinPoint#GET_PROPERTY}
	 */
	public function getType(Void):Number {
		return GET_PROPERTY;
	}
	
}