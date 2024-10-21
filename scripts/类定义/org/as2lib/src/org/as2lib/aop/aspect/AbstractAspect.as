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

import org.as2lib.core.BasicClass;
import org.as2lib.env.overload.Overload;
import org.as2lib.env.except.IllegalArgumentException;
import org.as2lib.aop.Advice;
import org.as2lib.aop.Pointcut;
import org.as2lib.app.exec.Call;
import org.as2lib.aop.AopConfig;

/**
 * {@code AbstractAspect} provides convenient method implmenetations and offers
 * functionalities to add advices in different manners.
 * 
 * @author Simon Wacker
 */
class org.as2lib.aop.aspect.AbstractAspect extends BasicClass {
	
	/** All added advices. */
	private var advices:Array;
	
	/**
	 * Constructs a new {@code AbstractAspect} instance.
	 */
	private function AbstractAspect(Void) {
		this.advices = new Array();
	}
	
	/**
	 * Returns all added advices.
	 * 
	 * <p>The returned advices are needed by weavers.
	 * 
	 * @return all added advices
	 */
	public function getAdvices(Void):Array {
		return this.advices.concat();
	}
	
	/**
	 * @overload #addAdviceByAdvice
	 * @overload #addAdviceByTypeAndStringAndMethod
	 * @overload #addAdviceByTypeAndPointcutAndMethod
	 */
	private function addAdvice() {
		var o:Overload = new Overload(this);
		o.addHandler([Advice], addAdviceByAdvice);
		o.addHandler([Number, String, Function], addAdviceByTypeAndStringAndMethod);
		o.addHandler([Number, Pointcut, Function], addAdviceByTypeAndPointcutAndMethod);
		return o.forward(arguments);
	}
	
	/**
	 * Adds the passed-in {@code advice}.
	 * 
	 * <p>No action will take place if {@code advice} is {@code null} or
	 * {@code undefined}.
	 *
	 * @param advice the advice to add
	 */
	private function addAdviceByAdvice(advice:Advice):Void {
		if (advice) {
			this.advices.push(advice);
		}
	}
	
	/**
	 * Adds a new advice of the given {@code type}, for the given {@code pointcut} and
	 * with the given {@code method} that is executed if a join point captured by the
	 * {@code pointcut} is reached.
	 * 
	 * <p>The advice is obtained by the {@code getAdvice} method of the advice factory
	 * returned by {@link AopConfig#getDynamicAdviceFactory} method.
	 *
	 * @param type the type of the advice
	 * @param pointcut the pointcut represented by a string that determines which join
	 * points are captured
	 * @param method the method that contains the actions to be executed at specific
	 * join points captured by the {@code pointcut}
	 * @throws IllegalArgumentException if argument {@code method} is {@code null} or
	 * {@code undefined}
	 */
	private function addAdviceByTypeAndStringAndMethod(type:Number, pointcut:String, method:Function):Advice {
		if (method == null) throw new IllegalArgumentException("Argument 'method' must not be 'null' nor 'undefined'.", this, arguments);
		var callback:Call = new Call(this, method);
		var result:Advice = AopConfig.getDynamicAdviceFactory().getAdvice(type, pointcut, callback);
		addAdviceByAdvice(result);
		return result;
	}
	
	/**
	 * Adds a new advice of the given {@code type}, for the given {@code pointcut} and
	 * with the given {@code method} that is executed if a join point captured by the
	 * {@code pointcut} is reached.
	 *
	 * @param type the type of the advice
	 * @param pointcut the pointcut that determines which join points are captured
	 * @param method the method that contains the actions to be executed at specific
	 * join points captured by the {@code pointcut}
	 * @throws IllegalArgumentException if argument {@code method} is {@code null} or
	 * {@code undefined}
	 */
	private function addAdviceByTypeAndPointcutAndMethod(type:Number, pointcut:Pointcut, method:Function):Advice {
		if (method == null) throw new IllegalArgumentException("Argument 'method' must not be 'null' nor 'undefined'.", this, arguments);
		var callback:Call = new Call(this, method);
		var result:Advice = AopConfig.getDynamicAdviceFactory().getAdvice(type, pointcut, callback);
		addAdviceByAdvice(result);
		return result;
	}
	
}