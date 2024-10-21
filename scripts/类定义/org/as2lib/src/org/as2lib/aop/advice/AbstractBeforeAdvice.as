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

import org.as2lib.aop.Aspect;
import org.as2lib.aop.JoinPoint;
import org.as2lib.aop.advice.AbstractAdvice;
import org.as2lib.aop.advice.BeforeAdvice;

/**
 * @author Simon Wacker
 */
class org.as2lib.aop.advice.AbstractBeforeAdvice extends AbstractAdvice {
	
	/**
	 * Constructs a new {@code AbstractBeforeAdvice} instance.
	 * 
	 * @param aspect (optional) the aspect that contains this advice
	 */
	private function AbstractBeforeAdvice(aspect:Aspect) {
		super(aspect);
	}
	
	/**
	 * Invokes this advice's {@code execute} method and proceeds the passed-in
	 * {@code joinPoint} with the given {@code args} after that and returns the result
	 * of the procession.
	 * 
	 * <p>The given {@code joinPoint} is not proceeded if this advice's {@code execute}
	 * method threw an exception.
	 * 
	 * @param joinPoint the reached join point
	 * @param args the arguments to use for the procession of the join point, these are
	 * normally the ones that were originally passed-to the join point
	 * @return the result of the procession of the given {@code joinPoint} with the
	 * given {@code args}
	 * @throws * if the procession of the {@code joinPoint} with the given {@code args}
	 * results in an exception or if this advice's {@code execute} method threw an
	 * exception
	 */
	private function executeJoinPoint(joinPoint:JoinPoint, args:Array) {
		// create a copy of 'args' to use for the before advice because this advice's 'execute'
		// method may alter the given 'args'
		var a:Array = args.concat();
		// 'caller' and 'callee' may be needed by the before advice
		a.caller = args.caller;
		a.callee = args.callee;
		BeforeAdvice(this).execute(joinPoint, a);
		return joinPoint.proceed(args);
	}
	
}