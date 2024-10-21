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

import org.as2lib.core.BasicInterface;
import org.as2lib.aop.Pointcut;

/**
 * {@code PointcutFactory} creates and returns pointcuts based on pointcut patterns.
 * 
 * <p>A pointcut pattern consists of the join point's type, for example method
 * execution or get or set access join points.
 * <code>execution(org.as2lib.env.Logger.debug)</code>
 * <code>set(org.as2lib.MyClass.myProperty)</code>
 * <code>get(org.as2lib.MyClass.myProperty)</code>
 * 
 * <p>A pointcut pattern may also be more complex by combining multiple pointcuts with
 * a specific logic.
 * <code>execution(org.as2lib.env.Logger.debug) || set(org.as2lib.MyClass.myProperty)</code>
 * 
 * <p>Note that not all pointcuts allow all of the above ways to describe a pointcut
 * pattern. This depends on the given implementation.
 * 
 * @author Simon Wacker
 */
interface org.as2lib.aop.pointcut.PointcutFactory extends BasicInterface {
	
	/**
	 * Returns a pointcut based on the passed-in {@code pattern} representation.
	 *
	 * @param pattern the string representation of the pointcut
	 * @return the object-oriented view of the passed-in pointcut {@code pattern}
	 */
	public function getPointcut(pattern:String):Pointcut;
	
}