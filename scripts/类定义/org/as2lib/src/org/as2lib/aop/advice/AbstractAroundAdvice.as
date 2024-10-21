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
import org.as2lib.aop.advice.AroundAdvice;

/**
 * {@code AbstractAroundAdvice} provides implementations of methods commonly needed
 * by {@link AroundAdvice} implementations.
 * 
 * @author Simon Wacker
 */
class org.as2lib.aop.advice.AbstractAroundAdvice extends AbstractAdvice {
	
	/**
	 * Constructs a new {@code AbstractAroundAdvice} instance.
	 * 
	 * @param aspect (optional) the aspect that contains this advice
	 */
	private function AbstractAroundAdvice(aspect:Aspect) {
		super(aspect);
	}
	
	/**
	 * Executes this advice's {@code execute} method, passing the given
	 * {@code joinPoint} and the given {@code args}.
	 * 
	 * @param joinPoint the reached join point
	 * @param args the arguments used to invoke the join point
	 * @return the result of the execution of this advice's {@code execute} method
	 * @throws * if the execution of tis adivce's {@code execute} method results in an
	 * exception
	 */
	private function executeJoinPoint(joinPoint:JoinPoint, args:Array) {
		return AroundAdvice(this).execute(joinPoint, args);
	}
	
}