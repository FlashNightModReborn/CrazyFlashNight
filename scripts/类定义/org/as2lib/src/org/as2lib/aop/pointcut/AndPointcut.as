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
 * {@code AndPointcut} combines multiple pointcuts with a logical AND. This means that
 * this pointcut captures a given join point if all its contained pointcuts capture the
 * given join point.
 * 
 * <p>This pointcut expects a string representation as parameter on construction. Such
 * a string representation may look something like this:
 * <code>execution(org.as2lib.env.Logger.*) && execution(org.as2lib.reflect.*.*)</code>
 * 
 * @author Simon Wacker
 * @see <a href="http://www.simonwacker.com/blog/archives/000053.php">Wildcards</a>
 */
class org.as2lib.aop.pointcut.AndPointcut extends AbstractCompositePointcut implements CompositePointcut {
	
	/**
	 * Constructs a new {@code AndPointcut} instance.
	 * 
	 * <p>The string representation is supposed to be a combination of multiple
	 * pointcuts where some of them are combined with the {@code &&} operator.
	 * 
	 * @param pointcut (optional) the string representation of this and pointcut
	 */
	public function AndPointcut(pointcut:String) {
		if (pointcut != null && pointcut != "") {
			// source this out
			var pointcuts:Array = pointcut.split("&&");
			for (var i:Number = 0; i < pointcuts.length; i++) {
				addPointcut(AopConfig.getPointcutFactory().getPointcut(pointcuts[i]));
			}
		}
	}
	
	/**
	 * Checks whether this pointcut captures the given {@code joinPoint}. The
	 * {@code joinPoint} is only captured if all sub-pointcuts of this pointcut capture
	 * it.
	 * 
	 * {@code false} will be returned if:
	 * <ul>
	 *   <li>The passed-in {@code joinPoint} is {@code null} or {@code undefined}.</li>
	 *   <li>Any of the sub-pointcuts' {@code captures} method returns {@code false}.</li>
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
			if (!pointcut.captures(joinPoint)) {
				return false;
			}
		}
		return true;
	}
	
}