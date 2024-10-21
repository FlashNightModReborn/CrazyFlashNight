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
 * {@code AroundAdvice} is invoked instead of a join point. The special thing about the
 * around advice is that it can nevertheless proceed the join point if it likes to and
 * can also change the arguments to use for the procession and alter the return type if
 * wished. This means with the around advice you can change contextual information of
 * the join point it is woven into.
 * 
 * @author Simon Wacker
 * @see <a href="http://www.simonwacker.com/blog/archives/000066.php">Advice</a>
 */
interface org.as2lib.aop.advice.AroundAdvice extends Advice {
	
	/**
	 * Executes the actions to perform instead of the given {@code joinPoint}. If the
	 * {@code joinPoint} shall nevertheless be executed this has to be done manually
	 * by invoking the {@link JoinPoint#proceed} method.
	 * 
	 * <p>The implementation of this method decides whether the actual join point is
	 * bypassed or if it is executed. It can also be decided what arguments to use for
	 * the procession and what to do with the response of the procession be it a return
	 * value or an exception. This means you can alter the context as you please.
	 * 
	 * <p>If you use the proxy returned by the {@link AbstractAroundAdvice#getProxy}
	 * method to overwrite the actual join point, this method is executed instead of
	 * the join point and the result of this method is returned to the invoker of the
	 * join point.
	 *
	 * @param joinPoint the join point this advice was woven into
	 * @param args the arguments passed to the join point
	 * @return the result of the execution
	 */
	public function execute(joinPoint:JoinPoint, args:Array);

}