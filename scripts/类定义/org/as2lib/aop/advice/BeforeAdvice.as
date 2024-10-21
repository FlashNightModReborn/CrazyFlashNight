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

import org.as2lib.aop.JoinPoint;
import org.as2lib.aop.Advice;

/**
 * {@code BeforeAdvice} is invoked before the execution of a specific join point, this
 * advice has been woven into.
 * 
 * @author Simon Wacker
 * @see <a href="http://www.simonwacker.com/blog/archives/000066.php">Advice</a>
 */
interface org.as2lib.aop.advice.BeforeAdvice extends Advice {
	
	/**
	 * Executes the actions to perform before the {@code joinPoint} is proceeded.
	 * 
	 * <p>It is not possible to alter the context of the procession of the join point.
	 * The passed-in {@code args} are just a copy of the arguments passed-to the join
	 * point.
	 * 
	 * <p>If you use the proxy returned by the {@code AbstractBeforeAdvice#getProxy}
	 * method to overwrite the actual join point, this method is invoked before the
	 * given {@code joinPoint} is proceeded with the values of the given {@code args}.
	 *
	 * @param joinPoint the join point the advice was woven into
	 * @param args the arguments passed to the join point
	 */
	public function execute(joinPoint:JoinPoint, args:Array):Void;
	
}