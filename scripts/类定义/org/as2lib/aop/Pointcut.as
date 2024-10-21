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
 * {@code Pointcut} represents a pointcut in an Aspect-Oriented Programming Language
 * like AspectJ. A pointcut is basically a pattern that can be matched against a join
 * point to check whether the join point is captured. Whether it is captured depends
 * on the pointcut pattern, which means on the characteristics of the join point.
 *
 * @author Simon Wacker
 * @see <a href="http://www.simonwacker.com/blog/archives/000043.php">Pointcuts</a>
 */
interface org.as2lib.aop.Pointcut extends BasicInterface {
	
	/**
	 * Checks if the given {@code joinPoint} is captured by this pointcut.
	 *
	 * @param joinPoint the join point upon which to make the check
	 * @return {@code true} if the given {@code joinPoint} is captured by this pointcut
	 * else {@code false}
	 */
	public function captures(joinPoint:JoinPoint):Boolean;
	
}