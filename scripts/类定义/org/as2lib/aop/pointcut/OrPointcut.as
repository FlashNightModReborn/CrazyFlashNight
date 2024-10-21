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

import org.as2lib.aop.pointcut.CompositePointcut;
import org.as2lib.aop.pointcut.AbstractCompositePointcut;
import org.as2lib.aop.AopConfig;
import org.as2lib.aop.Pointcut;
import org.as2lib.aop.JoinPoint;

/**
 * {@code OrPointcut} combines multiple pointcuts with a logical OR. This means that
 * this pointcut captures a given join point if at least one of its contained pointcuts
 * captures the given join point.
 *
 * <p>This pointcut expects a string representation as parameter on construction. Such
 * a string representation may look something like this:
 * <code>execution(org.as2lib.env.Logger.*) || execution(org.as2lib.reflect.*.*)</code>
 * 
 * @author Simon Wacker
 */
class org.as2lib.aop.pointcut.OrPointcut extends AbstractCompositePointcut implements CompositePointcut {
	
	/**
	 * Constructs a new {@code OrPointcut} instance.
	 * 
	 * <p>The string representation is supposed to be a combination of multiple
	 * pointcuts where some of them are combined with the {@code ||} operator.
	 * 
	 * @param pointcut the string representation of this or pointcut
	 */
	public function OrPointcut(pointcut:String) {
		if (pointcut != null && pointcut != "") {
			// source this out
			var pointcuts:Array = pointcut.split("||");
			for (var i:Number = 0; i < pointcuts.length; i++) {
				addPointcut(AopConfig.getPointcutFactory().getPointcut(pointcuts[i]));
			}
		}
	}
	
	/**
	 * Checks whether this pointcut captures the given {@code joinPoint}. The
	 * {@code joinPoint} is captured if at least one sub-pointcut of this pointcut
	 * captures it.
	 * 
	 * {@code false} will be returned if:
	 * <ul>
	 *   <li>The passed-in {@code joinPoint} is {@code null} or {@code undefined}.</li>
	 *   <li>Not even one sub-pointcut captures the given {@code joinPoint}.</li>
	 *   <li>There are no pointcuts added.</li>
	 * </ul>
	 *
	 * @param joinPoint the join point to check whether it is captured by this pointcut
	 * @return {@code true} if this pointcut captures the given {@code joinPoint} else
	 * {@code false}
	 */
	public function captures(joinPoint:JoinPoint):Boolean {
		if (!joinPoint) return false;
		var i:Number = this.pointcuts.length;
		if (i < 1) return false;
		while (--i-(-1)) {
			var pointcut:Pointcut = this.pointcuts[i];
			if (pointcut.captures(joinPoint)) {
				return true;
			}
		}
		return false;
	}
	
}