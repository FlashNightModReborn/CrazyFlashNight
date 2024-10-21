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
import org.as2lib.aop.advice.AbstractBeforeAdvice;
import org.as2lib.aop.advice.BeforeAdvice;

/**
 * {@code DynamicBeforeAdvice} executes a callback at the weave-in point.
 * 
 * @author Simon Wacker
 */
class org.as2lib.aop.advice.DynamicBeforeAdvice extends AbstractBeforeAdvice implements BeforeAdvice {
	
	/** The callback to invoke. */
	private var callback:Executable;
	
	/**
	 * @overload #DynamicBeforeAdviceByPointcut
	 * @overload #DynamicBeforeAdviceByPointcutPattern
	 */
	public function DynamicBeforeAdvice() {
		var o:Overload = new Overload(this);
		o.addHandler([Pointcut, Executable], DynamicBeforeAdviceByPointcut);
		o.addHandler([String, Executable], DynamicBeforeAdviceByPointcutPattern);
		o.forward(arguments);
	}
	
	/**
	 * Constrcuts a new {@code DynamicBeforeAdvice} instance with a pointcut.
	 *
	 * @param pointcut the pointcut that determines the join points to weave this
	 * advice in
	 * @param callback the callback that is executed at the weave-in point
	 */
	private function DynamicBeforeAdviceByPointcut(pointcut:Pointcut, callback:Executable) {
		setPointcutByPointcut(pointcut);
		this.callback = callback;
	}
	
	/**
	 * Constrcuts a new {@code DynamicBeforeAdvice} instance with a pointcut pattern.
	 *
	 * @param pointcut the pointcut that determines the join points to weave this
	 * advice in
	 * @param callback the callback that is executed at the weave-in point
	 */
	private function DynamicBeforeAdviceByPointcutPattern(pointcut:String, callback:Executable) {
		setPointcutByString(pointcut);
		this.callback = callback;
	}
	
	/**
	 * Executes the callback passing the passed {@code joinPoint} and {@code args}.
	 * 
	 * @param joinPoint the join point the advice was woven into
	 * @param args the arguments passed to the join point
	 */
	public function execute(joinPoint:JoinPoint, args:Array):Void {
		callback.execute(joinPoint, args);
	}
	
}