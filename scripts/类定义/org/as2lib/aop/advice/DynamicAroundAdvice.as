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

import org.as2lib.app.exec.Executable;
import org.as2lib.env.overload.Overload;
import org.as2lib.aop.JoinPoint;
import org.as2lib.aop.Pointcut;
import org.as2lib.aop.advice.AbstractAroundAdvice;
import org.as2lib.aop.advice.AroundAdvice;

/**
 * {@code DynamicAroundAdvice} executes a callback at the weave-in point.
 * 
 * @author Simon Wacker
 */
class org.as2lib.aop.advice.DynamicAroundAdvice extends AbstractAroundAdvice implements AroundAdvice {
	
	/** The callback to invoke. */
	private var callback:Executable;
	
	/**
	 * @overload #DynamicAroundAdviceByPointcut
	 * @overload #DynamicAroundAdviceByPointcutPattern
	 */
	public function DynamicAroundAdvice() {
		var o:Overload = new Overload(this);
		o.addHandler([Pointcut, Executable], DynamicAroundAdviceByPointcut);
		o.addHandler([String, Executable], DynamicAroundAdviceByPointcutPattern);
		o.forward(arguments);
	}
	
	/**
	 * Constrcuts a new {@code DynamicAroundAdvice} instance with a pointcut.
	 *
	 * @param pointcut the pointcut that determines the join points to weave this
	 * advice in
	 * @param callback the callback that is executed at the weave-in point
	 */
	private function DynamicAroundAdviceByPointcut(pointcut:Pointcut, callback:Executable) {
		setPointcutByPointcut(pointcut);
		this.callback = callback;
	}
	
	/**
	 * Constrcuts a new {@code DynamicAroundAdvice} instance with a pointcut pattern.
	 *
	 * @param pointcut the pointcut that determines the join points to weave this
	 * advice in
	 * @param callback the callback that is executed at the weave-in point
	 */
	private function DynamicAroundAdviceByPointcutPattern(pointcut:String, callback:Executable) {
		setPointcutByString(pointcut);
		this.callback = callback;
	}
	
	/**
	 * Executes the callback passing the passed {@code joinPoint} and {@code args}.
	 * 
	 * @param joinPoint the join point this advice was woven into
	 * @param args the arguments passed to the join point
	 * @return the result of the execution of the callback
	 */
	public function execute(joinPoint:JoinPoint, args:Array) {
		return callback.execute(joinPoint, args);
	}
	
}