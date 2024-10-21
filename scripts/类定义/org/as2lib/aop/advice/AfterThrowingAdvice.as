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
 * {@code AfterThrowingAdvice} is invoked after a join point, this advice has been
 * woven-into, has been invoked and threw an exception.
 * 
 * @author Simon Wacker
 * @see AfterAdvice
 * @see AfterReturningAdvice
 * @see <a href="http://www.simonwacker.com/blog/archives/000066.php">Advice</a>
 */
interface org.as2lib.aop.advice.AfterThrowingAdvice extends Advice {
	
	/**
	 * Executes the actions that shall take place after a specific join point threw
	 * an exception.
	 * 
	 * <p>If you use the proxy returned by the {@link AbstractAfterThrowingAdvice#getProxy}
	 * method to overwrite the actual join point, this method is invoked after the
	 * procession of the given {@code joinPoint} resulted in an exception.
	 *
	 * @param joinPoint the join point this advice was woven into
	 * @param throwable the throwable thrown by the given {@code joinPoint}
	 */
	public function execute(joinPoint:JoinPoint, throwable):Void;
	
}