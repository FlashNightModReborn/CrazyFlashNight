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

import org.as2lib.core.BasicClass;
import org.as2lib.aop.JoinPoint;
import org.as2lib.aop.Pointcut;

/**
 * {@code WithinPointcut} captures join points based one their lexical-structure, that
 * means on the scope of the code as it was written. This within-pointcut allows for
 * capturing join points inside the lexical scope of classes and interfaces.
 * 
 * @author Simon Wacker
 * @see <a href="http://www.simonwacker.com/blog/archives/000061.php">Lexical-Structure Based Pointcuts</a>
 */
class org.as2lib.aop.pointcut.WithinPointcut extends BasicClass implements Pointcut {
	
	/** The type pattern used to determine whether specific join points are captured. */
	private var typePattern:String;
	
	/**
	 * Constructs a new {@code WithinPointcut} instance.
	 * 
	 * <p>A {@code typePattern} is for example:
	 * <code>org.as2lib..*Aspect</code>
	 * 
	 * <p>The above pattern matches all join points within all types in the "org.as2lib"
	 * package and any sub-package that have a name that ends with "Aspect".
	 * 
	 * @param typePattern the type pattern describing the lexical scope of join points
	 * to capture
	 * @see #captures
	 */
	public function WithinPointcut(typePattern:String) {
		if (typePattern != null) {
			this.typePattern = typePattern + ".*";
		}
	}
	
	/**
	 * Checks if the given {@code joinPoint} is captured by this pointcut.
	 * 
	 * <p>{@code false} will be returned if:
	 * <ul>
	 *   <li>The passed-in {@code joinPoint} is {@code null} or {@code undefined}.</li>
	 *   <li>The passed-in {@code joinPoint} does not match the given type pattern.</li>
	 * </ul>
	 * 
	 * @param joinPoint the join point upon which to make the check
	 * @return {@code true} if the given {@code joinPoint} is captured by this pointcut
	 * else {@code false}
	 * @see JoinPoint#matches
	 */
	public function captures(joinPoint:JoinPoint):Boolean {
		if (!joinPoint) return false;
		return joinPoint.matches(this.typePattern);
	}
	
}