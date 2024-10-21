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
import org.as2lib.aop.Pointcut;
import org.as2lib.aop.JoinPoint;

/**
 * {@code KindedPointcut} represents any kinded pointcuts. These are for example
 * execution, set and get access pointcuts.
 * 
 * <p>Kinded pointcuts build upon a join point pattern and a specific join point type.
 * Pre-defined join point types are {@link AbstractJoinPoint#METHOD},
 * {@link AbstractJoinPoint#PROPERTY}, {@link AbstractJoinPoint#GET_PROPERTY},
 * {@link AbstractJoinPoint#SET_PROPERTY} and {@link AbstractJoinPoint#CONSTRUCTOR}.
 * You may combine several join point types with a bitwise or "|" to make this kinded
 * pointcut match all the combined join point types.
 * 
 * <p>The pattern may consist of wildcards. Using wildcards you can capture join points
 * based on specific characteristics like capture every setter method contained in every
 * class whose name starts with {@code "Abstract"} in the {@code org.as2lib.env} package
 * and every sub-package. Such a pattern would look something like this:
 * <code>org.as2lib.env..Abstract*.set*</code>
 * 
 * <p>You already see two wildcards there: '*' and '..'.
 * <ul>
 *   <li>'*' indicates any number of characters excluding the period.</li>
 *   <li>'..' indicates any number of charecters including all periods.</li>
 *   <li>'+' indicates all subclasses or subinterfaces of a given type.</li>
 *   <li>
 *     '!' negates the match; match all join points except the ones that match the
 *     pattern.
 *   </li>
 * </ul>
 * 
 * @author Simon Wacker
 * @see <a href="http://www.simonwacker.com/blog/archives/000057.php">Kinded Pointcuts</a>
 * @see <a href="http://www.simonwacker.com/blog/archives/000053.php">Wildcards</a>
 */
class org.as2lib.aop.pointcut.KindedPointcut extends BasicClass implements Pointcut {
	
	/** The types of the matching join points. */
	private var matchingJoinPointTypes:Number;
	
	/** The pattern that represents the join point. */
	private var joinPointPattern:String;
	
	/**
	 * Constructs a new {@code KindedPointcut} instance.
	 *
	 * <p>Depending on the join points {@code matches} method a pattern of value
	 * {@code null} or {@code undefined} will cause the {@link #captures} method to
	 * return {@code true} or {@code false}. Note that the join point implementations
	 * provided by this framework return {@code true} for a {@code null} pattern.
	 * 
	 * <p>A matching join point type of value {@code null} or {@code undefined} is
	 * interpreted as "any type of join point allowed".
	 * 
	 * <p>{@code matchingJoinPointTypes} can be either only one type or a bitwise or "|"
	 * combination of several types. It is thus possible to make this kinded pointcut
	 * match more than one join point type.
	 * <code>AbstractJoinPoint.METHOD | AbstractJoinPoint.CONSTRUCTOR</code>
	 * 
	 * @param joinPointPattern the join point pattern
	 * @param matchingJoinPointTypes the types of the join points that match this
	 * pointcut
	 */
	public function KindedPointcut(joinPointPattern:String, matchingJoinPointTypes:Number) {
		this.joinPointPattern = joinPointPattern;
		this.matchingJoinPointTypes = matchingJoinPointTypes;
	}
	
	/**
	 * Checks whether the given {@code joinPoint} is captured by this pointcut. This is
	 * normally the case if the join point is of the correct type and the pattern
	 * matches the join point.
	 * 
	 * {@code false} will be returned if:
	 * <ul>
	 *   <li>The passed-in join point is {@code null} or {@code undefined}.</li>
	 *   <li>The passed-in join point does not match the given join point pattern.</li>
	 *   <li>The passed-in join point's type does not match the given one.</li>
	 * </ul>
	 *
	 * @param joinPoint the join point to check whether it is captured by this pointcut
	 * @return {@code true} if the given {@code joinPoint} is captured else {@code false}
	 * @see JoinPoint#matches
	 */
	public function captures(joinPoint:JoinPoint):Boolean {
		if (!joinPoint) return false;
		if (this.matchingJoinPointTypes == null) {
			return joinPoint.matches(this.joinPointPattern);
		}
		return ((this.matchingJoinPointTypes & joinPoint.getType()) > 0
					&& joinPoint.matches(this.joinPointPattern));
	}
	
}