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
import org.as2lib.aop.advice.AfterThrowingAdvice;

/**
 * {@code AbstractAfterThrowingAdvice} provides implementations of methods needed by
 * {@link AfterThrowingAdvice} implementations.
 * 
 * @author Simon Wacker
 */
class org.as2lib.aop.advice.AbstractAfterThrowingAdvice extends AbstractAdvice {
	
	/**
	 * Constructs a new {@code AbstractAfterThrowingAdvice} instance.
	 * 
	 * @param aspect (optional) the aspect that contains this advice
	 */
	private function AbstractAfterThrowingAdvice(aspect:Aspect) {
		super(aspect);
	}
	
	/**
	 * Proceeds the passed-in {@code joinPoint} with the given {@code args} and returns
	 * the result of this procession after invoking this advice's {@code execute}
	 * method passing the given {@code joinPoint} and the thrown exception.
	 * 
	 * <p>Note that this advice's {@code execute} method is only invoked if the
	 * procession of the {@code joinPoint} with the given {@code args} resulted in an
	 * exception.
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
		// 'this' in the catch block refers to '_level0' without this preceding 'this'
		// (at least in the test cases)
		// a detached 'this' is not allowed by MTASC we does have to store it in a variable
		var x:AbstractAfterThrowingAdvice = this;
		var result;
		try {
			result = joinPoint.proceed(args);
		} catch (throwable) {
			AfterThrowingAdvice(this).execute(joinPoint, throwable);
			throw throwable;
		}
		return result;
	}
	
}