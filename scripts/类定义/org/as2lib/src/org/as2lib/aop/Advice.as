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
import org.as2lib.aop.JoinPoint;

/**
 * {@code Advice} reflects an advice in an Aspect-Oriented Programming Language like
 * AspectJ. This is the core interface that must be implemented to create a custom
 * advices.
 * 
 * <p>An advice defines the code to be executed at a specific pointcut, that defines
 * where and when this code shall be executed.
 * 
 * @author Simon Wacker
 * @see <a href="http://www.simonwacker.com/blog/archives/000066.php">Advice</a>
 */
interface org.as2lib.aop.Advice extends BasicInterface {
	
	/**
	 * Checks whether this advice captures the given {@code joinPoint}. This check is
	 * normally being done using the set pointcut.
	 * 
	 * @param joinPoint the join point upon which to make the check
	 * @return {@code true} if the given {@code joinPoint} is captured else {@code false}
	 */
	public function captures(joinPoint:JoinPoint):Boolean;
	
	/**
	 * Returns a proxy method that can be used instead of the original method of the
	 * {@code joinPoint}. This proxy does not only invoke the original method, but also
	 * performs the weaved-in actions of the advice.
	 *
	 * @param joinPoint the join point that represents the original method
	 * @return the proxy method
	 */
	public function getProxy(joinPoint:JoinPoint):Function;
	
}