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
 * {@code AfterReturningAdvice} is invoked after a join point, this advice has been
 * woven-into, has been invoked and returned successfully with a return value, not if
 * it threw an exception.
 * 
 * @author Simon Wacker
 * @see AfterAdvice
 * @see AfterThrowingAdvice
 * @see <a href="http://www.simonwacker.com/blog/archives/000066.php">Advice</a>
 */
interface org.as2lib.aop.advice.AfterReturningAdvice extends Advice {
	
	/** 
	 * Executes the actions that were woven-in the given {@code joinPoint}.
	 * 
	 * <p>If you use the proxy returned by the {@link AbstractAfterReturningAdvice#getProxy}
	 * method to overwrite the actual join point, this method is invoked after the join
	 * point was invoked and returned successfully with a return value.
	 *
	 * @param joinPoint the join point this advice was woven into
	 * @param returnValue the result of the execution of the join point
	 */
	public function execute(joinPoint:JoinPoint, returnValue):Void;
	
}