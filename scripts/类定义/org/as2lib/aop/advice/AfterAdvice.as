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
 * {@code AfterAdvice} is invoked after the invocation of a specific join point, this
 * advice has been woven-into.
 * 
 * <p>This advice is always invoked, whether a specific join point returned
 * successfully with a return value or threw an exception. If you want an advice that
 * is only invoked after a successful return or after the throwing of an exception use
 * the {@link AfterReturningAdvice} or {@link AfterThrowingAdvice} respectively.
 * 
 * @author Simon Wacker
 * @see <a href="http://www.simonwacker.com/blog/archives/000066.php">Advice</a>
 */
interface org.as2lib.aop.advice.AfterAdvice extends Advice {
	
	/**
	 * Executes the actions that were woven-in the given {@code joinPoint}.
	 * 
	 * <p>If you use the proxy returned by the {@link AbstractAfterAdvice#getProxy}
	 * method to overwrite the original join point, this method is invoked after the
	 * given {@code joinPoint} has been proceeded.
	 *
	 * @param joinPoint the join point this advice has been woven-into
	 */
	public function execute(joinPoint:JoinPoint):Void;
	
}