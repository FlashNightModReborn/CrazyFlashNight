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
 * {@code NotPointcut} acts like the logical not "!" operator. It wraps a pointcut and
 * negates the result of its {@code captures} method.
 * 
 * @author Simon Wacker
 */
class org.as2lib.aop.pointcut.NotPointcut extends BasicClass implements Pointcut {
	
	/** The wrapped pointcut to negate. */
	private var pointcut:Pointcut;
	
	/**
	 * Constructs a new {@code NotPointcut} instance.
	 * 
	 * @param pointcut the pointcut whose {@code captures} method to negate
	 */
	public function NotPointcut(pointcut:Pointcut) {
		this.pointcut = pointcut;
	}
	
	/**
	 * Executes the wrapped pointcut's {@code captures} method passing the given
	 * {@code joinPoint}, negates the result and returns the negation.
	 * 
	 * <p>If the wrapped pointcut specified on construction is {@code null} or
	 * {@code undefined}, {@code false} will be returned.
	 * 
	 * @param joinPoint the join point to check whether it is captured
	 * @return the negated result of the execution of the {@code captures} method of
	 * the wrapped pointcut 
	 */
	public function captures(joinPoint:JoinPoint):Boolean {
		if (!this.pointcut) return false;
		return !this.pointcut.captures(joinPoint);
	}
	
}